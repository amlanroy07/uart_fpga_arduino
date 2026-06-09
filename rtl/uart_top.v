// =============================================================================
// Module      : uart_top
// Project     : UART — ICE40HX1K FPGA ↔ Arduino Uno
// Author      : (Your Name)
// Description : Top-level integration of uart_rx and uart_tx for the Lattice
//               iCEstick (iCE40HX1K) evaluation board.
//
//               Default behaviour: echo — every byte received over RXD is
//               immediately retransmitted over TXD.
//
// Wiring to Arduino Uno
// ─────────────────────────────────────────────────────────────────────────
//  Arduino Uno        Wire / Note              iCEstick FPGA
//  ───────────        ──────────               ─────────────
//  Pin 1 (TX)  ──[10kΩ resistor]──►  rxd   FPGA pin 62  (PMOD J2 pin 7)
//  Pin 0 (RX)  ◄────────────────────  txd   FPGA pin 61  (PMOD J2 pin 8)
//  GND         ────────────────────── GND   PMOD J2 pin 11
//
//  The 10kΩ resistor on Arduino TX → FPGA RXD is required because Arduino
//  outputs 5V but the iCE40 I/O is only 3.3V tolerant.
//
//  IMPORTANT: Disconnect Arduino pins 0 & 1 before uploading a new sketch.
//             They share the USB bootloader lines.
//
// Pin summary (numeric)
//   clk      → 21   (12 MHz on-board oscillator)
//   rxd      → 62   (PMOD J2 pin 7)
//   txd      → 61   (PMOD J2 pin 8)
//   led      → 99   (on-board LED D1 — activity)
//   frame_err→ 98   (on-board LED D2 — framing error)
//
// Synthesis target : Lattice iCE40HX1K (iCEstick evaluation board)
// Toolchain        : IceStorm / nextpnr / Yosys
// =============================================================================

`default_nettype none

module uart_top #(
    parameter CLK_FREQ  = 12_000_000,   // iCEstick 12 MHz oscillator
    parameter BAUD_RATE = 9_600         // 9600 baud — safe for Arduino Uno link
)(
    input  wire clk,
    
    input  wire rxd,        // ← Arduino Uno Pin 1 (TX) via 10kΩ resistor
    output wire txd,        // → Arduino Uno Pin 0 (RX)
    output wire led,        // on-board LED D1: blinks on each received byte
    output wire frame_err   // on-board LED D2: lights on framing error
);

    // -------------------------------------------------------------------------
    // Internal wiring
    // -------------------------------------------------------------------------
    wire [7:0] rx_byte;
    wire       rx_ready;
    wire       tx_busy;
  wire rst_n = 1'b1;
    // -------------------------------------------------------------------------
    // UART RX instance
    // Receives bytes from Arduino Uno pin 1 (TX) on FPGA pin 62
    // -------------------------------------------------------------------------
    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rxd      (rxd),
        .rx_data  (rx_byte),
        .rx_ready (rx_ready),
        .flag     (frame_err)
    );

    // -------------------------------------------------------------------------
    // UART TX instance
    // Sends echo back to Arduino Uno pin 0 (RX) on FPGA pin 61
    // tx_start fires only when RX has new data AND TX is not busy
    // -------------------------------------------------------------------------
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (rx_byte),
        .tx_start (rx_ready && !tx_busy),
        .txd      (txd),
        .tx_busy  (tx_busy)
    );

    // -------------------------------------------------------------------------
    // Activity LED (D1, FPGA pin 99)
    // Stays ON for ~83 ms after each received byte (1M cycles at 12 MHz)
    // -------------------------------------------------------------------------
    reg [19:0] led_counter;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            led_counter <= 0;
        else if (rx_ready)
            led_counter <= {20{1'b1}};      // reload on new byte
        else if (led_counter != 0)
            led_counter <= led_counter - 1'b1;
    end

    assign led = (led_counter != 0);

endmodule

`default_nettype wire
