#include "BluetoothSerial.h"  // BT接続用
#include <Wire.h>
#include "esp_system.h"
#include "esp_mac.h" 

#if !defined(CONFIG_BT_ENABLED) || !defined(CONFIG_BLUEDROID_ENABLED)
#error Bluetooth is not enabled! Please run `make menuconfig` to and enable it
#endif

#if !defined(CONFIG_BT_SPP_ENABLED)
#error Serial Bluetooth not available or not enabled. It is only available for the ESP32 chip.
#endif

//------[ define宣言 ]------
#define INT_INTERVAL  5                   //ミリ秒
#define GAME_DISP_TIME  INT_INTERVAL*200  //秒

// GPIOピンの設定
#define MT_H_A 2  //13 // IN1ピン
#define MT_H_B 15 //12 // IN2ピン
#define MT_V_A 13 //2  // IN3ピン
#define MT_V_B 12 //15 // IN4ピン
#define LED 14 // 

//------[ グローバル変数宣言 ]------
const int buzPin1 = 25;      //圧電ブザー
const int buzPin2 = 26;      //圧電ブザー
const int buzPin3 = 27;      //圧電ブザー
const int GPIO_LED1 = 16;   //IO16 赤色LED
const int GPIO_LED2 = 4;    //IO4  青赤色LED
const int GPIO_LED3 = 15;   //IO15 緑色LED

const int GPIO_SW1 = 0;         //スイッチ1

const int SW1 = 1;          //スイッチ1
const int SW2 = 2;          //スイッチ2
const int SW3 = 4;          //スイッチ3

unsigned char bSwData;      // スイッチデータの格納変数
unsigned char bSwDataOld;   // スイッチデータの格納変数（過去）
unsigned char bSwDataSave;  // スイッチデータの変化検出用変数
int gMode = 0;

boolean playerAFlag = true;
int gameDispCnt = 0;

BluetoothSerial SerialBT;

void beep(int time) {
  int i;
  for( i = 0; i < time; i++) {  // time[ms]の間発音する
    digitalWrite(buzPin1,HIGH);
    digitalWrite(buzPin2,HIGH);
    digitalWrite(buzPin3,HIGH);
    delayMicroseconds(500); // 500us待つ
    digitalWrite(buzPin3,LOW);
    digitalWrite(buzPin2,LOW);
    digitalWrite(buzPin1,LOW);
    delayMicroseconds(500); // 500us待つ
  }
}

void beepHigh(int time) {
  int i;
  for( i = 0; i < time*2; i++) {  // time[ms]の間発音する
    digitalWrite(buzPin1,HIGH);
    digitalWrite(buzPin2,HIGH);
    digitalWrite(buzPin3,HIGH);
    delayMicroseconds(250);
    digitalWrite(buzPin3,LOW);
    digitalWrite(buzPin2,LOW);
    digitalWrite(buzPin1,LOW);
    delayMicroseconds(250);
  }
}

void beepLow(int time) {
  int i;
  for( i = 0; i < time/2; i++) {  // time[ms]の間発音する
    digitalWrite(buzPin1,HIGH);
    digitalWrite(buzPin2,HIGH);
    digitalWrite(buzPin3,HIGH);
    delayMicroseconds(1000);
    digitalWrite(buzPin3,LOW);
    digitalWrite(buzPin2,LOW);
    digitalWrite(buzPin1,LOW);
    delayMicroseconds(1000);
  }
}

void ledFlash(int ledPin, int delayTime){
  digitalWrite(ledPin, HIGH);
  delay(delayTime);
  digitalWrite(ledPin, LOW);
  delay(delayTime);
}

void swScan(void) {
  byte bWk = 0;
  if (digitalRead(GPIO_SW1) == LOW ) {   //戻り値: HIGHまたはLOW
    bWk |= SW1;          //ON
  } else {
    bWk &= SW1 ^ 0xFF;   //OFF
  }
  if (bSwDataOld == bWk) {
    bSwData = bWk; //前回と一致したので更新する
  }
  bSwDataOld = bWk; //今回の値を保存
}

void swOperation(void) {
  static int brightCnt = 0;
  if (bSwData != bSwDataSave) {
    if ((bSwData & SW1) == SW1) {  // SW1操作判別
      digitalWrite(GPIO_LED1, HIGH);
      Serial.println("SW1 ON");
      beep(150);
    } else if ((bSwData & SW2) == SW2) {  // SW2操作判別
      digitalWrite(GPIO_LED2, HIGH);
      Serial.println("SW2 ON");
    } else if ((bSwData & SW3) == SW3) {  // SW3操作判別
      digitalWrite(GPIO_LED3, HIGH);
      Serial.println("SW3 ON");
    }
    if(bSwData == 0) {
      digitalWrite(GPIO_LED1, LOW);
      digitalWrite(GPIO_LED2, LOW);
      digitalWrite(GPIO_LED3, LOW);
    }
  }
  bSwDataSave = bSwData;
}

void motorOp(int pwmValueX, int dirX, int pwmValueY, int dirY) {
  // Horizontal motor control
  if (dirX == 1) {
    analogWrite(MT_H_A, pwmValueX);
    analogWrite(MT_H_B, 0);
  } else {
    analogWrite(MT_H_A, 0);
    analogWrite(MT_H_B, pwmValueX);
  }

  // Vertical motor control
  if (dirY == 1) {
    analogWrite(MT_V_A, 0);
    analogWrite(MT_V_B, pwmValueY);
  } else {
    analogWrite(MT_V_A, pwmValueY);
    analogWrite(MT_V_B, 0);
  }
}

void setup() {
  pinMode(LED, OUTPUT);
  pinMode(MT_H_A, OUTPUT);
  pinMode(MT_H_B, OUTPUT);
  pinMode(MT_V_A, OUTPUT);
  pinMode(MT_V_B, OUTPUT);
  pinMode(GPIO_SW1, INPUT_PULLUP);
  pinMode(GPIO_LED1, OUTPUT);
  pinMode(GPIO_LED2, OUTPUT);
  pinMode(GPIO_LED3, OUTPUT);
  pinMode(buzPin1, OUTPUT);
  pinMode(buzPin2, OUTPUT);
  pinMode(buzPin3, OUTPUT);

  Serial.begin(115200);
  SerialBT.begin("ESP32test"); //Bluetooth device name
  Serial.println("The device started, now you can pair it with bluetooth!");

  uint8_t macBT[6];
  esp_read_mac(macBT, ESP_MAC_BT);
  Serial.printf("%02X:%02X:%02X:%02X:%02X:%02X\r\n", macBT[0], macBT[1], macBT[2], macBT[3], macBT[4], macBT[5]);

  beepLow(150);
  beep(150);
}

void loop() {
  static uint32_t cnt = 0;
  char str[16] = {'\0'};  //スタックオーバーフロー対策のため多めに設定

  if (SerialBT.available()) {
    String rcvData = SerialBT.readStringUntil('\n');
    Serial.println("Received: " + rcvData);

    if (rcvData.startsWith("STOP")) {
      // Stop the motors
      motorOp(0, 0, 0, 0);
      return;
    }

    // Parse the received command
    float angleX, angleY, speedX, speedY;
    sscanf(rcvData.c_str(), "X:%f,Y:%f,SX:%f,SY:%f", &angleX, &angleY, &speedX, &speedY);

    // Convert angles to motor control signals
    int pwmValueX = map(abs(angleX), 0, 360, 0, speedX); // Adjust the range based on speed
    int pwmValueY = map(abs(angleY), 0, 360, 0, speedY); // Adjust the range based on speed

    // Determine direction
    int dirX = (angleX > 0) ? 1 : 0;
    int dirY = (angleY > 0) ? 1 : 0;

    // Move both motors simultaneously
    motorOp(pwmValueX, dirX, pwmValueY, dirY);
  }

  swScan();
  swOperation();
  cnt++;
  delay(5); // Reduce the delay for faster response
}