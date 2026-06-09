/*
 * File        : fpga_uart_demo.ino
 * Project     : UART — ICE40HX1K FPGA ↔ Arduino Uno
 * Board       : Arduino Uno (ATmega328P @ 16 MHz)
 * Description : Sends test strings to the iCEstick FPGA every 2 seconds
 *               and reads back the echo response.
 *
 * ─── Wiring ──────────────────────────────────────────────────────────────────
 *
 *   Arduino Uno          Connection            iCEstick FPGA
 *   ───────────          ──────────            ─────────────
 *   Pin 1 (TX)  ──[10kΩ resistor]──►  rxd   (FPGA pin 62, PMOD J2 pin 7)
 *   Pin 0 (RX)  ◄────────────────────  txd   (FPGA pin 61, PMOD J2 pin 8)
 *   GND         ─────────────────────  GND   (PMOD J2 pin 11)
 *
 *   The 10kΩ resistor is REQUIRED on Arduino TX → FPGA RXD.
 *   Arduino TX outputs 5V; the iCE40 is 3.3V — without the resistor
 *   you risk damaging the FPGA over time.
 *
 *   The FPGA TXD → Arduino RX direction needs NO resistor.
 *   Arduino Uno RX accepts 3.3V as a valid HIGH level.
 *
 * ─── IMPORTANT BEFORE UPLOADING ──────────────────────────────────────────────
 *   Arduino pins 0 (RX) and 1 (TX) are shared with the USB bootloader.
 *   You MUST disconnect the wires from pins 0 and 1 before uploading
 *   a new sketch, then reconnect them after upload completes.
 *
 * ─── Baud Rate ────────────────────────────────────────────────────────────────
 *   9600 baud — matches the FPGA RTL default (CLK_FREQ=12MHz, BAUD_RATE=9600)
 *   Do NOT change to 115200 — the 12 MHz iCEstick clock gives 6.5% baud
 *   error at that rate, causing unreliable communication.
 * ─────────────────────────────────────────────────────────────────────────────
 */

// ─── Configuration ────────────────────────────────────────────────────────────
static const unsigned long BAUD_RATE        = 9600;
static const unsigned long SEND_INTERVAL_MS = 2000;  // send every 2 seconds

// ─── Test messages sent to FPGA ───────────────────────────────────────────────
const char* messages[] = {
    "Hello FPGA!\r\n",
    "UART test 1234\r\n",
    "ICE40HX1K OK?\r\n",
    "Echo check...\r\n",
};
static const uint8_t NUM_MESSAGES =
    sizeof(messages) / sizeof(messages[0]);

// ─── Globals ──────────────────────────────────────────────────────────────────
unsigned long lastSendTime = 0;
uint8_t       messageIndex = 0;

// ─── Setup ────────────────────────────────────────────────────────────────────
void setup() {
    // Serial uses Arduino pins 0 (RX) and 1 (TX)
    // These connect directly to FPGA pin 61 (txd) and pin 62 (rxd)
    Serial.begin(BAUD_RATE);

    // Wait for FPGA to finish booting after power-on
    delay(300);
}

// ─── Loop ─────────────────────────────────────────────────────────────────────
void loop() {

    // 1. Every SEND_INTERVAL_MS, send the next test message to the FPGA
    if (millis() - lastSendTime >= SEND_INTERVAL_MS) {
        lastSendTime = millis();

        const char* msg = messages[messageIndex % NUM_MESSAGES];
        Serial.print(msg);
        messageIndex++;
    }

    // 2. Read any bytes echoed back by the FPGA
    //    On the Arduino Uno, Serial is shared between USB and pins 0/1,
    //    so echoed bytes appear in the Serial Monitor automatically.
    //    Just drain the buffer to keep things clean.
    while (Serial.available() > 0) {
        Serial.read();  // byte is already visible in Serial Monitor via USB
    }
}
