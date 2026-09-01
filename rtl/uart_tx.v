// =============================================================================
// Module      : uart_tx
// Project     : UART — ICE40HX1K FPGA ↔ Arduino Uno
// 
// Description : UART transmitter.  Accepts a parallel byte on tx_data when
//               tx_start is asserted, serialises it LSB-first with one start
//               bit (LOW) and one stop bit (HIGH), and drives txd accordingly.
//               tx_busy is asserted for the duration of the transmission.
//
// Parameters
//   CLK_FREQ  – System clock frequency in Hz  (default 12 MHz for iCEstick)
//   BAUD_RATE – UART baud rate in bps          (default 9600)
//
// Hardware connection
//   txd (FPGA pin 61, PMOD J2 pin 8) → Arduino Uno Pin 0 (RX)
//   FPGA output is 3.3V which Arduino Uno RX accepts without level shifting.
//
// Port list
//   txd      – UART TX line to Arduino RX pin
//   tx_busy  – HIGH while a frame is being transmitted
//   clk      – System clock (active-rising edge)
//   rst_n    – Asynchronous active-low reset
//   tx_data  – Byte to transmit (sampled on the rising edge of tx_start)
//   tx_start – Assert for at least one clk cycle to begin transmission
//
// Synthesis target : Lattice iCE40HX1K (iCEstick evaluation board)
// Toolchain        : IceStorm / nextpnr / Yosys
// =============================================================================

`default_nettype none

module uart_tx #(
    parameter CLK_FREQ  = 12_000_000,
    parameter BAUD_RATE = 9_600
)(
    output reg  txd,
    output      tx_busy,
    input wire  clk,
    input wire  rst_n,
    input wire  [7:0] tx_data,
    input wire  tx_start
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    // Baud divider: one tick per full bit period
    localparam integer BAUD_DIV = (CLK_FREQ / BAUD_RATE) - 1;

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    reg [$clog2(BAUD_DIV)-1:0] baud_counter; // baud-rate divider counter
    reg [2:0] bit_index;                      // which data bit is being sent (0-7)
    reg [7:0] tx_shift;                       // shift register holding byte being sent
    reg [1:0] state;                          // FSM state

    wire baud_tick;   // one-cycle strobe at baud rate

    // -------------------------------------------------------------------------
    // 1. Baud-rate divider (full bit period, no oversampling needed on TX)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            baud_counter <= 0;
        else if (state == IDLE)
            baud_counter <= 0;          // hold reset while idle
        else if (baud_tick)
            baud_counter <= 0;
        else
            baud_counter <= baud_counter + 1'b1;
    end

    assign baud_tick = (baud_counter == BAUD_DIV[$clog2(BAUD_DIV)-1:0]);

    // -------------------------------------------------------------------------
    // 2. FSM + datapath (combined for clarity on a simple TX path)
    //
    //   IDLE  : txd = 1 (line idle); wait for tx_start
    //   START : transmit start bit (txd = 0) for one full bit period
    //   DATA  : clock out 8 data bits, LSB first, one bit per baud_tick
    //   STOP  : transmit stop bit (txd = 1) for one full bit period
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state     <= IDLE;
            txd       <= 1'b1;
            tx_shift  <= 8'h00;
            bit_index <= 3'd0;
        end
        else begin
            case (state)
                // ----------------------------------------------------------
                IDLE: begin
                    txd <= 1'b1;            // keep line idle HIGH
                    if (tx_start) begin
                        tx_shift <= tx_data;    // latch byte
                        state    <= START;
                    end
                end

                // ----------------------------------------------------------
                START: begin
                    txd <= 1'b0;            // start bit
                    if (baud_tick) begin
                        bit_index <= 3'd0;
                        state     <= DATA;
                    end
                end

                // ----------------------------------------------------------
                DATA: begin
                    txd <= tx_shift[0];     // LSB first
                    if (baud_tick) begin
                        tx_shift  <= {1'b0, tx_shift[7:1]};  // shift right
                        bit_index <= bit_index + 1'b1;
                        if (bit_index == 3'd7)
                            state <= STOP;
                    end
                end

                // ----------------------------------------------------------
                STOP: begin
                    txd <= 1'b1;            // stop bit
                    if (baud_tick)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign tx_busy = (state != IDLE);

endmodule

`default_nettype wire
