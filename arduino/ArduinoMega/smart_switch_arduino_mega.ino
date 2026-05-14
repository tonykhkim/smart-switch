#include <Servo.h>

// ── 핀 설정 ──────────────────────────────────────
const int SERVO1_PIN = 9;   // D9~  서보1 (OFF 담당)
const int SERVO2_PIN = 10;  // D10~ 서보2 (ON 담당)

// ── 각도 설정 ────────────────────────────────────
// 서보1 (OFF) — 스위치를 아래로 눌러 끄는 방향
const int S1_REST = 90;   // 대기 각도
const int S1_PUSH = 0;    // 스위치 누르는 각도 (실측 후 조정)

// 서보2 (ON) — 스위치를 위로 눌러 켜는 방향
const int S2_REST = 90;   // 대기 각도
const int S2_PUSH = 180;  // 스위치 누르는 각도 (실측 후 조정)

const int PUSH_DELAY   = 300;  // 누른 채 대기 (ms)
const int RETURN_DELAY = 500;  // 복귀 후 안정화 (ms)

// ── 서보 객체 ────────────────────────────────────
Servo servo1;  // OFF 담당
Servo servo2;  // ON  담당

void setup() {
  Serial.begin(9600);
  Serial1.begin(9600);   // BLE 모듈 (TX1=18, RX1=19)

  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);

  // 시작 시 두 서보 모두 대기 위치로
  servo1.write(S1_REST);
  servo2.write(S2_REST);
  delay(1000);

  Serial.println("스마트 스위치 준비 완료!");
  Serial.println("앱에서 1 = ON / 0 = OFF");
}

void loop() {
  if (Serial1.available()) {
    char cmd = Serial1.read();
    Serial.print("수신: ");
    Serial.println(cmd);

    if (cmd == '1') {
      Serial.println("불 켜기 → 서보2(ON) 동작");
      turnON();
      Serial1.println("ON");
    }
    else if (cmd == '0') {
      Serial.println("불 끄기 → 서보1(OFF) 동작");
      turnOFF();
      Serial1.println("OFF");
    }
  }
}

// ── 켜기: 서보2가 스위치를 ON 방향으로 누름 ──────
void turnON() {
  servo2.write(S2_PUSH);      // ON 방향으로 눌러
  delay(PUSH_DELAY);
  servo2.write(S2_REST);      // 제자리 복귀
  delay(RETURN_DELAY);
  Serial.println("서보2 복귀 완료");
}

// ── 끄기: 서보1이 스위치를 OFF 방향으로 누름 ─────
void turnOFF() {
  servo1.write(S1_PUSH);      // OFF 방향으로 눌러
  delay(PUSH_DELAY);
  servo1.write(S1_REST);      // 제자리 복귀
  delay(RETURN_DELAY);
  Serial.println("서보1 복귀 완료");
}