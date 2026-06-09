# UART — iCE40HX1K FPGA ↔ Arduino Uno

A clean, fully-oversampled UART implementation in synthesisable Verilog, targeting the **Lattice iCEstick** evaluation board (iCE40HX1K-TQ144) and communicating with an **Arduino Uno** using its dedicated hardware RX/TX pins.

```
 Arduino Uno                              iCEstick (iCE40HX1K)
 ───────────                              ────────────────────
  Pin 1 (TX) ──[10kΩ resistor]──────────► pin 62 / rxd  (PMOD J2 pin 7)
  Pin 0 (RX) ◄──────────────────────────── pin 61 / txd  (PMOD J2 pin 8)
  GND        ─────────────────────────────── GND          (PMOD J2 pin 11)
```

> **Voltage warning:** Arduino TX outputs 5V; the iCE40 is 3.3V.
> Always use a **10kΩ series resistor** on Arduino TX → FPGA RXD.
> The FPGA → Arduino direction needs no resistor.

---

## Features

| Feature | Detail |
|---|---|
| Oversampling | 16× — robust against baud-rate clock mismatch |
| Mid-bit sampling | Samples at tick 7 of 0–15 (true centre of each bit) |
| CDC synchroniser | Two-flop synchroniser on RXD input |
| Frame-error flag | Detects false start bits and missing stop bits |
| TX module | Full FSM transmitter with `tx_busy` handshake |
| Echo loopback | Top-level wires RX directly to TX for end-to-end test |
| Activity LED | On-board LED D1 blinks on each received byte |
| Error LED | On-board LED D2 lights on framing error |
| Simulation | Self-checking Icarus Verilog testbench + VCD output |

---

## Repository Structure

```
uart_fpga_arduino/
├── rtl/
│   ├── uart_rx.v          # UART receiver (16× oversampling)
│   ├── uart_tx.v          # UART transmitter
│   └── uart_top.v         # Top-level: RX + TX echo loopback
├── sim/
│   └── uart_tb.v          # Self-checking testbench (Icarus Verilog)
├── constraints/
│   └── icestick.pcf       # iCEstick pin constraints (numeric pin numbers)
├── arduino/
│   └── fpga_uart_demo/
│       └── fpga_uart_demo.ino   # Arduino Uno sketch
├── Makefile               # Yosys + nextpnr + icepack + iceprog
├── LICENSE
└── README.md
```

---

## Pin Reference

### FPGA Pin Numbers (iCE40HX1K-TQ144)

| Signal | FPGA Pin # | PMOD J2 Pin | Direction | Connect to |
|---|---|---|---|---|
| `clk` | **21** | on-board oscillator | in | 12 MHz crystal |
| `rxd` | **62** | PMOD pin 7 | in ← | Arduino Uno **Pin 1 (TX)** via 10kΩ |
| `txd` | **61** | PMOD pin 8 | out → | Arduino Uno **Pin 0 (RX)** |
| `led` | **99** | on-board LED D1 | out | Activity indicator |
| `frame_err` | **98** | on-board LED D2 | out | Framing error indicator |

### PMOD J2 Layout (top view, looking at the board)

```
[ 1 ][ 2 ][ 3 ][ 4 ][ GND ]
[ 6 ][ 7 ][ 8 ][ 9 ][ VCC ]
    [11 ][12 ]
    [GND][GND]

Pin 7  → FPGA pin 62 → rxd  (← Arduino Pin 1 TX via 10kΩ)
Pin 8  → FPGA pin 61 → txd  (→ Arduino Pin 0 RX)
Pin 11 → GND
```

---

## Wiring Diagram

```
Arduino Uno                    iCEstick FPGA
───────────                    ─────────────

Pin 1 (TX) ──┤10kΩ├──────────► FPGA pin 62  (rxd, PMOD J2 pin 7)
                                              [5V → 3.3V protection]

Pin 0 (RX) ◄───────────────── FPGA pin 61  (txd, PMOD J2 pin 8)
                                              [3.3V, safe for Arduino]

GND ────────────────────────── GND           (PMOD J2 pin 11)
```

> **Before uploading a new sketch:** Always disconnect wires from Arduino
> pins 0 and 1 first. They are shared with the USB bootloader. Reconnect
> after upload is complete.

---

## Quick Start

### Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| [Yosys](https://github.com/YosysHQ/yosys) | Synthesis | `sudo apt install yosys` |
| [nextpnr-ice40](https://github.com/YosysHQ/nextpnr) | Place & route | `sudo apt install nextpnr-ice40` |
| [IceStorm](https://github.com/YosysHQ/icestorm) | Pack + flash | `sudo apt install fpga-icestorm` |
| [Icarus Verilog](http://iverilog.icarus.com/) | Simulation | `sudo apt install iverilog` |
| [GTKWave](http://gtkwave.sourceforge.net/) | Waveform viewer | `sudo apt install gtkwave` |
| [Arduino IDE](https://www.arduino.cc/en/software) | Arduino sketch | Download from arduino.cc |

### Build & Flash the FPGA

```bash
# Clone the repo
git clone https://github.com/<your-username>/uart_fpga_arduino.git
cd uart_fpga_arduino

# Full build + flash in one command
make prog
```

Or step by step:
```bash
make synth   # Synthesis  → build/uart_top.json
make pnr     # Place&Route → build/uart_top.asc
make pack    # Bitstream  → build/uart_top.bin
make prog    # Flash to iCEstick via USB
```

If `iceprog` fails with a permissions error on Linux:
```bash
sudo iceprog build/uart_top.bin
# For a permanent fix (no sudo needed in future):
sudo cp /usr/share/icestorm/icestick.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
```

### Simulate

```bash
make sim
gtkwave sim/uart_tb.vcd
```

Expected output:
```
PASS: sent 0x55, received 0x55
PASS: sent 0xAA, received 0xAA
PASS: sent 0x00, received 0x00
PASS: sent 0xFF, received 0xFF
PASS: sent 0x41, received 0x41
PASS: sent 0x5A, received 0x5A
----------------------------------------
Results: 6 PASS, 0 FAIL
----------------------------------------
```

### Upload Arduino Sketch

1. **Disconnect** wires from Arduino pins 0 and 1
2. Open `arduino/fpga_uart_demo/fpga_uart_demo.ino` in Arduino IDE
3. Select **Tools → Board → Arduino Uno**
4. Select the correct COM port
5. Click **Upload**
6. **Reconnect** wires to pins 0 and 1 after upload finishes
7. Open **Serial Monitor** at **9600 baud**

---

## Timing & Baud Rate

```
OVS_TICK_DIV = (CLK_FREQ / (BAUD_RATE × 16)) − 1
```

| CLK_FREQ | BAUD_RATE | OVS_TICK_DIV | Baud error | Recommended? |
|---|---|---|---|---|
| 12 000 000 | **9 600** | 77 | **0.00 %** | ✅ Yes |
| 12 000 000 | 115 200 | 5 | 6.51 % | ❌ Too high |

**Always use 9600 baud** for the Arduino Uno ↔ iCEstick link at 12 MHz.

---

## Module Reference

### `uart_rx` — Receiver

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | System clock (12 MHz) |
| `rst_n` | in | 1 | Async active-low reset |
| `rxd` | in | 1 | Serial data in (from Arduino Pin 1 TX) |
| `rx_data` | out | 8 | Received byte (valid when rx_ready=1) |
| `rx_ready` | out | 1 | Pulses HIGH for 1 clock cycle on valid frame |
| `flag` | out | 1 | Sticky frame-error flag |

### `uart_tx` — Transmitter

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | System clock (12 MHz) |
| `rst_n` | in | 1 | Async active-low reset |
| `tx_data` | in | 8 | Byte to transmit |
| `tx_start` | in | 1 | Assert for ≥ 1 cycle to begin transmit |
| `txd` | out | 1 | Serial data out (to Arduino Pin 0 RX) |
| `tx_busy` | out | 1 | HIGH while frame is being transmitted |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Upload fails | Pins 0/1 still connected | Disconnect wires before uploading |
| Garbage characters | Baud rate mismatch | Set both sides to exactly 9600 |
| LED never blinks | Wrong PMOD pins | Check PCF: rxd=62, txd=61 |
| FPGA not detected | iceprog permissions | Run `sudo iceprog` or add udev rule |
| Intermittent errors | Missing 10kΩ resistor | Add resistor on Arduino TX → FPGA RXD |
| No echo at all | Wrong wire direction | TX→RXD and TXD→RX, not crossed wrong |

---

## Known Limitations

- No FIFO — back-to-back bytes at high speed may be dropped
- Single stop bit only
- No parity support
- No hardware flow control (RTS/CTS)

---

## License

MIT — see `LICENSE` file.
