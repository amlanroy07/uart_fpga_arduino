// =============================================================================
// File        : uart_tb.v
// Project     : UART — ICE40HX1K FPGA ↔ Arduino Uno
// Description : Simple self-checking testbench.
//               Drives uart_tx with a known byte, connects txd → rxd to
//               feed uart_rx, and checks that the recovered byte matches.
//               Also exercises the top-level echo loopback.
//
// Simulate    : make sim   (uses Icarus Verilog + VCD dump → GTKWave)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module uart_tb;

    // -------------------------------------------------------------------------
    // Parameters (match RTL defaults)
    // -------------------------------------------------------------------------
    localparam CLK_FREQ  = 12_000_000;
    localparam BAUD_RATE = 9_600;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ; // ≈ 83 ns

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg        clk    = 0;
    reg        rst_n  = 0;
    reg  [7:0] tx_data;
    reg        tx_start = 0;
    wire       txd;
    wire       tx_busy;
    wire [7:0] rx_data;
    wire       rx_ready;
    wire       frame_err;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // -------------------------------------------------------------------------
    // TX DUT
    // -------------------------------------------------------------------------
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (tx_data),
        .tx_start (tx_start),
        .txd      (txd),
        .tx_busy  (tx_busy)
    );

    // -------------------------------------------------------------------------
    // RX DUT — loopback: TXD → RXD
    // -------------------------------------------------------------------------
    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rxd      (txd),        // loopback
        .rx_data  (rx_data),
        .rx_ready (rx_ready),
        .flag     (frame_err)
    );

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("sim/uart_tb.vcd");
        $dumpvars(0, uart_tb);
    end

    // -------------------------------------------------------------------------
    // Stimulus + self-check
    // -------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task send_byte;
        input [7:0] byte_val;
        begin
            @(posedge clk);
            tx_data  = byte_val;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;
            // wait until TX finishes + RX latches the byte
            wait (rx_ready == 1'b1);
            @(posedge clk);
            if (rx_data === byte_val) begin
                $display("PASS: sent 0x%02X, received 0x%02X", byte_val, rx_data);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: sent 0x%02X, received 0x%02X (frame_err=%b)",
                         byte_val, rx_data, frame_err);
                fail_count = fail_count + 1;
            end
            // wait for TX to go idle before sending next byte
            wait (tx_busy == 1'b0);
            repeat (10) @(posedge clk);
        end
    endtask

    initial begin
        // Reset
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // Send a range of test vectors
        send_byte(8'h55);   // alternating bits
        send_byte(8'hAA);   // inverse alternating
        send_byte(8'h00);   // all zeros
        send_byte(8'hFF);   // all ones
        send_byte(8'h41);   // ASCII 'A'
        send_byte(8'h5A);   // ASCII 'Z'

        $display("----------------------------------------");
        $display("Results: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("----------------------------------------");
        $finish;
    end

endmodule

`default_nettype wire
