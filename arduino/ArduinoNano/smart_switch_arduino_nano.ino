#include <Servo.h>
#include <SoftwareSerial.h>

// ── BLE 모듈 핀 설정 (D2=RX, D3=TX) ─────────────────
// 나노 D2핀 → BLE TXD 연결
// 나노 D3핀 → BLE RXD 연결
SoftwareSerial bleSerial(2, 3);  // (RX, TX)

// ── 서보 핀 설정 ─────────────────────────────────────
const int SERVO1_PIN = 9;   // D9~  서보1 (OFF 담당)
const int SERVO2_PIN = 10;  // D10~ 서보2 (ON 담당)

// ── 각도 설정 ─────────────────────────────────────────
const int S1_REST = 90;
const int S1_PUSH = 10;     // 0
const int S2_REST = 90;
const int S2_PUSH = 170;    // 180
const int PUSH_DELAY   = 300;
const int RETURN_DELAY = 500;

Servo servo1;
Servo servo2;

void setup() {
  Serial.begin(9600);       // PC 시리얼 모니터
  bleSerial.begin(9600);    // BLE 모듈 통신

  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);
  servo1.write(S1_REST);
  servo2.write(S2_REST);
  delay(1000);

  Serial.println("나노 스마트 스위치 준비 완료!");
}

void loop() {
  if (bleSerial.available()) {
    char cmd = bleSerial.read();
    Serial.print("수신: ");
    Serial.println(cmd);

    if (cmd == '1') {
      Serial.println("불 켜기 → 서보2 동작");
      turnON();
      bleSerial.println("ON");
    }
    else if (cmd == '0') {
      Serial.println("불 끄기 → 서보1 동작");
      turnOFF();
      bleSerial.println("OFF");
    }
  }
}

void turnON() {
  servo2.write(S2_PUSH);
  delay(PUSH_DELAY);
  servo2.write(S2_REST);
  delay(RETURN_DELAY);
  Serial.println("서보2 복귀 완료");
}

void turnOFF() {
  servo1.write(S1_PUSH);
  delay(PUSH_DELAY);
  servo1.write(S1_REST);
  delay(RETURN_DELAY);
  Serial.println("서보1 복귀 완료");
}