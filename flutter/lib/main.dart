import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── HM-10 / CC2541 UUID ──────────────────────────────
const String SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
const String CHAR_UUID    = "0000ffe1-0000-1000-8000-00805f9b34fb";
const String PREF_KEY_ID  = "saved_device_id";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 상태바 색상 설정
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const SmartSwitchApp());
}

class SmartSwitchApp extends StatelessWidget {
  const SmartSwitchApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '스마트 스위치',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F11),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B7FFF),
          surface: Color(0xFF1A1A1F),
        ),
      ),
      home: const SwitchHomePage(),
    );
  }
}

// ── 색상 상수 ─────────────────────────────────────────
const kBg       = Color(0xFF0F0F11);
const kSurface  = Color(0xFF1A1A1F);
const kSurface2 = Color(0xFF222228);
const kBorder   = Color(0xFF1E1E24);
const kText     = Color(0xFFF0EFF5);
const kMuted    = Color(0xFF7A7A8A);
const kOnColor  = Color(0xFFC8F060);
const kOffColor = Color(0xFFFF5F5F);
const kAccent   = Color(0xFF8B7FFF);

// ── 로그 모델 ─────────────────────────────────────────
enum LogType { success, error, info }
class LogEntry {
  final String time, msg;
  final LogType type;
  LogEntry(this.time, this.msg, this.type);
}

// ── 메인 화면 ─────────────────────────────────────────
class SwitchHomePage extends StatefulWidget {
  const SwitchHomePage({super.key});
  @override
  State<SwitchHomePage> createState() => _SwitchHomePageState();
}

class _SwitchHomePageState extends State<SwitchHomePage>
    with TickerProviderStateMixin {

  // 상태 변수
  bool _isConnected  = false;
  bool _isScanning   = false;
  bool _lightOn      = false;   // 현재 전등 상태
  String _statusMsg  = "연결 안 됨";
  String _deviceName = "";
  String _savedId    = "";

  BluetoothDevice?         _device;
  BluetoothCharacteristic? _characteristic;
  Timer? _reconnectTimer;

  final List<LogEntry> _logs = [];
  final ScrollController _logScroll = ScrollController();

  // 버튼 애니메이션
  late AnimationController _onAnim;
  late AnimationController _offAnim;

  @override
  void initState() {
    super.initState();
    _onAnim  = AnimationController(vsync: this, duration: const Duration(milliseconds: 100), lowerBound: 1.0, upperBound: 1.08);
    _offAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 100), lowerBound: 1.0, upperBound: 1.08);
    _loadAndConnect();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _onAnim.dispose();
    _offAnim.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  // ── 저장된 기기 불러와서 자동 연결 ──────────────────
  Future<void> _loadAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(PREF_KEY_ID) ?? "";
    if (id.isNotEmpty) {
      setState(() => _savedId = id);
      _addLog("이전 기기 발견 — 자동 연결 시도", LogType.info);
      await _requestPermissions();
      _startAutoConnect();
    }
  }

  Future<void> _saveDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREF_KEY_ID, id);
    _savedId = id;
  }

  Future<bool> _requestPermissions() async {
    // Android 12 이상 + 이하 모두 커버하도록 전체 요청
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();

    final allGranted = statuses.values.every((s) =>
      s == PermissionStatus.granted || s == PermissionStatus.limited);

    if (!allGranted) {
      _addLog("권한 설정 필요 — 설정에서 허용해주세요", LogType.error);
      await openAppSettings();
    }
    return allGranted;
  }

  void _addLog(String msg, LogType type) {
    final now = DateTime.now();
    final ts = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}";
    setState(() {
      _logs.add(LogEntry(ts, msg, type));
      if (_logs.length > 30) _logs.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(_logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  // ── 스캔 & 연결 ──────────────────────────────────────
  Future<void> _startScan() async {
    final ok = await _requestPermissions();
    if (!ok) { _addLog("블루투스 권한이 필요해요", LogType.error); return; }

    setState(() { _isScanning = true; _statusMsg = "기기 검색 중..."; });
    _addLog("BLE 스캔 시작", LogType.info);

    await FlutterBluePlus.stopScan();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((results) async {
      for (var r in results) {
        final name = r.device.platformName;
        final id   = r.device.remoteId.str;
        final isTarget = (_savedId.isNotEmpty && id == _savedId) ||
            (_savedId.isEmpty &&
              (name.startsWith("HM") || name.startsWith("BT") ||
               name.startsWith("AT") || name.startsWith("MLT") ||
               name.contains("BT05") || name.contains("CC2541")));
        if (isTarget) {
          await FlutterBluePlus.stopScan();
          _addLog("기기 발견: $name", LogType.info);
          await _connectToDevice(r.device);
          break;
        }
      }
    });

    await Future.delayed(const Duration(seconds: 11));
    if (!_isConnected) {
      setState(() { _isScanning = false; _statusMsg = "기기를 찾지 못했어요"; });
      _addLog("스캔 타임아웃", LogType.error);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() => _statusMsg = "연결 중...");
    try {
      await device.connect(timeout: const Duration(seconds: 8));
      _device = device;
      await _saveDevice(device.remoteId.str);

      final services = await device.discoverServices();
      for (var s in services) {
        if (s.serviceUuid.toString().toLowerCase().contains("ffe0")) {
          for (var c in s.characteristics) {
            if (c.characteristicUuid.toString().toLowerCase().contains("ffe1")) {
              _characteristic = c;
            }
          }
        }
      }

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) _onDisconnected();
      });

      setState(() {
        _isConnected = true; _isScanning = false;
        _deviceName = device.platformName; _statusMsg = "연결됨";
      });
      _addLog("연결 성공! ${device.platformName}", LogType.success);
      _reconnectTimer?.cancel();
    } catch (e) {
      _addLog("연결 실패: $e", LogType.error);
      setState(() { _isScanning = false; _statusMsg = "연결 실패 — 재시도 중..."; });
      _startAutoConnect();
    }
  }

  void _onDisconnected() {
    if (!mounted) return;
    setState(() {
      _isConnected = false; _characteristic = null;
      _device = null; _statusMsg = "연결 끊김 — 재연결 중...";
    });
    _addLog("연결 끊어짐 — 5초 후 재연결", LogType.error);
    _startAutoConnect();
  }

  void _startAutoConnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      if (_isConnected || _savedId.isEmpty) { t.cancel(); return; }
      _addLog("자동 재연결 시도...", LogType.info);
      try {
        final device = BluetoothDevice.fromId(_savedId);
        await _connectToDevice(device);
        if (_isConnected) t.cancel();
      } catch (_) {}
    });
  }

  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    await _device?.disconnect();
    setState(() {
      _isConnected = false; _isScanning = false;
      _characteristic = null; _device = null;
      _statusMsg = "연결 안 됨"; _deviceName = "";
    });
    _addLog("연결 해제됨", LogType.error);
  }

  // ── 명령 전송 ────────────────────────────────────────
  Future<void> _sendCommand(String cmd) async {
    if (_characteristic == null) {
      _addLog("연결 상태를 확인해 주세요", LogType.error); return;
    }
    try {
      await _characteristic!.write(utf8.encode(cmd), withoutResponse: false);
      final label = cmd == "1" ? "ON — 불 켜기" : "OFF — 불 끄기";
      setState(() => _lightOn = cmd == "1");
      _addLog("전송: \"$cmd\" → $label", LogType.success);
    } catch (e) {
      _addLog("전송 실패: $e", LogType.error);
    }
  }

  // ── UI ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildConnectionCard(),
              const SizedBox(height: 12),
              _buildControlCard(),
              const SizedBox(height: 12),
              _buildLogCard(),
              const SizedBox(height: 20),
              const Text("Made by tony & claude",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: kMuted,
                  fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }

  // ── 헤더 ─────────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      children: [
        const Text("BLE 4.0 · CC2541",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, letterSpacing: 2,
            color: kAccent, fontFamily: 'monospace')),
        const SizedBox(height: 8),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
              color: kText, height: 1.2),
            children: [
              TextSpan(text: "옴팡이를 위한\n"),
              TextSpan(text: "스마트 "),
              TextSpan(text: "전등",
                style: TextStyle(color: kOnColor)),
              TextSpan(text: " 스위치"),
            ],
          ),
        ),
      ],
    );
  }

  // ── 연결 카드 ────────────────────────────────────────
  Widget _buildConnectionCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isConnected
            ? kOnColor.withOpacity(0.3)
            : kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 라벨
        const Text("블루투스 연결",
          style: TextStyle(fontSize: 10, letterSpacing: 1.5,
            color: kMuted, fontFamily: 'monospace')),
        const SizedBox(height: 14),
        // 상태 dot + 텍스트
        Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isScanning ? kAccent
                : _isConnected ? kOnColor
                : kMuted,
            ),
          ),
          const SizedBox(width: 10),
          Text(_statusMsg,
            style: TextStyle(fontSize: 12, fontFamily: 'monospace',
              color: _isConnected ? kOnColor : kMuted)),
        ]),
        if (_deviceName.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text("▸ $_deviceName",
            style: const TextStyle(fontSize: 11,
              color: kAccent, fontFamily: 'monospace')),
        ],
        const SizedBox(height: 16),
        // 연결/해제 버튼
        GestureDetector(
          onTap: _isConnected ? _disconnect : _startScan,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _isConnected
                ? kOffColor.withOpacity(0.08)
                : kSurface2,
              border: Border.all(
                color: _isConnected
                  ? kOffColor.withOpacity(0.4)
                  : kBorder),
            ),
            child: _isScanning
              ? const Center(child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: kAccent)))
              : Text(
                  _isConnected ? "연결 해제" : "BLE 기기 검색 및 연결",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: _isConnected ? kOffColor : kText)),
          ),
        ),
      ]),
    );
  }

  // ── 제어 카드 (ON / OFF 버튼 2개) ───────────────────
  Widget _buildControlCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("전등 제어",
          style: TextStyle(fontSize: 10, letterSpacing: 1.5,
            color: kMuted, fontFamily: 'monospace')),
        const SizedBox(height: 14),
        Row(children: [
          // ON 버튼
          Expanded(child: _buildSwitchBtn(
            isOn: true,
            icon: "☀",
            title: "ON",
            label: "경현 불 켜줘",
            sub: "SEND · 1",
            isActive: _lightOn,
            isEnabled: _isConnected,
            anim: _onAnim,
            onTap: () async {
              _onAnim.forward().then((_) => _onAnim.reverse());
              await _sendCommand("1");
            },
          )),
          const SizedBox(width: 12),
          // OFF 버튼
          Expanded(child: _buildSwitchBtn(
            isOn: false,
            icon: "◑",
            title: "OFF",
            label: "경현 불 꺼줘",
            sub: "SEND · 0",
            isActive: !_lightOn && _isConnected,
            isEnabled: _isConnected,
            anim: _offAnim,
            onTap: () async {
              _offAnim.forward().then((_) => _offAnim.reverse());
              await _sendCommand("0");
            },
          )),
        ]),
      ]),
    );
  }

  Widget _buildSwitchBtn({
    required bool isOn,
    required String icon,
    required String title,
    required String label,
    required String sub,
    required bool isActive,
    required bool isEnabled,
    required AnimationController anim,
    required VoidCallback onTap,
  }) {
    final color      = isOn ? kOnColor : kOffColor;
    final borderOpacity = isActive ? 0.6 : 0.2;
    final bgOpacity     = isActive ? 0.12 : 0.04;

    return ScaleTransition(
      scale: anim,
      child: GestureDetector(
        onTap: isEnabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isEnabled ? 1.0 : 0.3,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: color.withOpacity(bgOpacity),
              border: Border.all(
                color: color.withOpacity(borderOpacity),
                width: isActive ? 1.5 : 1.0),
              boxShadow: isActive ? [
                BoxShadow(color: color.withOpacity(0.15),
                  blurRadius: 20, spreadRadius: 2)
              ] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(icon,
                  style: TextStyle(
                    fontSize: isActive ? 42 : 36,
                    color: isEnabled ? Colors.white : kMuted)),
                const SizedBox(height: 8),
                // ON / OFF 큰 텍스트
                Text(title,
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: isEnabled ? color : kMuted)),
                const SizedBox(height: 4),
                // 경현 불 켜줘 / 꺼줘
                Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: isEnabled ? color : kMuted)),
                const SizedBox(height: 4),
                Text(sub,
                  style: TextStyle(
                    fontSize: 9, letterSpacing: 1.5,
                    fontFamily: 'monospace',
                    color: isEnabled
                      ? Colors.white.withOpacity(0.4)
                      : Colors.white.withOpacity(0.15))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 로그 카드 ────────────────────────────────────────
  Widget _buildLogCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("시리얼 로그",
          style: TextStyle(fontSize: 10, letterSpacing: 1.5,
            color: kMuted, fontFamily: 'monospace')),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: _logs.isEmpty
            ? const Center(child: Text("로그 없음",
                style: TextStyle(fontSize: 11,
                  color: kMuted, fontFamily: 'monospace')))
            : ListView.builder(
                controller: _logScroll,
                itemCount: _logs.length,
                itemBuilder: (_, i) {
                  final log = _logs[i];
                  Color c;
                  switch (log.type) {
                    case LogType.success: c = kOnColor; break;
                    case LogType.error:   c = kOffColor; break;
                    case LogType.info:    c = kAccent; break;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(log.time,
                          style: const TextStyle(fontSize: 10,
                            color: kMuted, fontFamily: 'monospace')),
                        const SizedBox(width: 10),
                        Expanded(child: Text(log.msg,
                          style: TextStyle(fontSize: 11,
                            color: c, fontFamily: 'monospace'))),
                      ],
                    ),
                  );
                }),
        ),
      ]),
    );
  }
}
