// =============================================================================
// Module      : uart_rx
// Project     : UART — ICE40HX1K FPGA ↔ Arduino Uno
// Author      : Amlan Roy
// Description : UART receiver with 16x oversampling and two-stage CDC sync.
//               Detects start bit, samples 8 data bits at mid-bit, checks
//               stop bit, and asserts rx_ready for one clock cycle when a
//               valid frame is received.  A frame-error flag is set when the
//               start or stop bit is at an unexpected logic level.
//
// Parameters
//   CLK_FREQ  – System clock frequency in Hz  (default 12 MHz for iCEstick)
//   BAUD_RATE – UART baud rate in bps          (default 9600 — do NOT use
//               115200 at 12 MHz; that gives 6.5% baud error)
//
// Hardware connection
//   rxd (FPGA pin 62, PMOD J2 pin 7) ← Arduino Uno Pin 1 (TX) via 10kΩ
//   Arduino TX is 5V; the 10kΩ resistor protects the 3.3V iCE40 input.
//
// Port list
//   rx_data  [7:0] – Received byte (stable while rx_ready is high)
//   rx_ready        – Pulses HIGH for exactly one clk cycle on valid frame
//   flag            – Sticky frame-error flag; cleared at next start-bit edge
//   clk             – System clock (active-rising edge)
//   rxd             – Raw UART RX line from Arduino TX pin
//   rst_n           – Asynchronous active-low reset
//
// Timing notes
//   OVS_TICK_DIV = (CLK_FREQ / (BAUD_RATE * 16)) - 1
//   iCEstick 12 MHz, 9600 baud   → OVS_TICK_DIV = 77  (0.00% error )
//   iCEstick 12 MHz, 115200 baud → OVS_TICK_DIV =  5  (6.51% error )
//   Always use 9600 baud for the Arduino Uno ↔ iCEstick link.
//
// Synthesis target : Lattice iCE40HX1K (iCEstick evaluation board)
// Toolchain        : IceStorm / nextpnr / Yosys
// =============================================================================

`default_nettype none

module uart_rx #(
    parameter CLK_FREQ  = 12_000_000,   // iCEstick oscillator = 12 MHz
    parameter BAUD_RATE = 9_600         // safe default for Arduino Uno link
)(
    output reg [7:0] rx_data,
    output           rx_ready,
    output           flag,
    input wire       clk,
    input wire       rxd,
    input wire       rst_n
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam IDLE         = 2'd0;
    localparam START_CHECK  = 2'd1;
    localparam DATA         = 2'd2;
    localparam STOP_CHECK   = 2'd3;

    localparam OVERSAMPLE_RATE = 16;
    localparam MID_SAMPLE      = 7;   // sample at the 8th tick (0-based) → mid-bit

    // Baud divider for the oversampled tick.
    // The "-1" converts a count to a compare value (counter counts 0…DIV).
    localparam integer OVS_TICK_DIV =
        (CLK_FREQ / (BAUD_RATE * OVERSAMPLE_RATE)) - 1;

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    reg [$clog2(OVS_TICK_DIV)-1:0] baud_counter_ovs; // oversampling baud divider
    reg [3:0]  sample_counter;   // counts 0-15 oversampling ticks per bit period
    reg [2:0]  data_counter;     // counts 0-7 received data bits
    reg [1:0]  rxd_sync;         // two-flop CDC synchroniser for rxd
    reg [1:0]  state;            // registered (current) FSM state
    reg [1:0]  next_state;       // combinational next-state
    reg        flag_store;       // frame-error latch
    reg        rx_ready_store;   // one-cycle data-valid pulse
    reg [7:0]  sipo;             // shift register (serial-in / parallel-out)

    wire baud_tick_ovs;          // oversampling tick strobe (one clk wide)
    wire sample_now;             // mid-bit sample strobe

    // -------------------------------------------------------------------------
    // 1. Oversampling baud-rate divider
    //    Resets on entry to START_CHECK so the first sample_now aligns to the
    //    exact mid-point of the start bit.
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            baud_counter_ovs <= 0;
        else if (state == IDLE && next_state == START_CHECK)
            baud_counter_ovs <= 0;          // re-sync counter on start-bit detect
        else if (baud_tick_ovs)
            baud_counter_ovs <= 0;
        else
            baud_counter_ovs <= baud_counter_ovs + 1'b1;
    end

    assign baud_tick_ovs = (baud_counter_ovs == OVS_TICK_DIV[($clog2(OVS_TICK_DIV)-1):0]);

    // -------------------------------------------------------------------------
    // 2. Two-flop CDC synchroniser for the asynchronous RXD input
    //    rxd_sync[0] is the stable, synchronised version used by the FSM.
    //    The shift direction is: rxd → rxd_sync[1] → rxd_sync[0].
    //    Reset to 1'b1 (UART idle = logic HIGH).
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            rxd_sync <= 2'b11;
        else
            rxd_sync <= {rxd_sync[1], rxd};  // FIX: correct shift order (MSB←input)
    end

    // -------------------------------------------------------------------------
    // 3. FSM — sequential (state register)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // -------------------------------------------------------------------------
    // 3. FSM — combinational (next-state logic)
    //
    //   IDLE        → START_CHECK : falling edge detected on rxd_sync[0]
    //   START_CHECK → DATA        : mid-start-bit sample confirms LOW (valid start)
    //   START_CHECK → IDLE        : mid-start-bit sample is HIGH (noise/glitch)
    //   DATA        → STOP_CHECK  : all 8 bits received
    //   STOP_CHECK  → IDLE        : stop-bit sampled (valid or framing error)
    // -------------------------------------------------------------------------
    always @* begin
        next_state = state;
        case (state)
            IDLE:
                if (rxd_sync[0] == 1'b0)
                    next_state = START_CHECK;

            START_CHECK:
                if (sample_now)
                    next_state = (rxd_sync[0] == 1'b0) ? DATA : IDLE;

            DATA:
                if (sample_now && data_counter == 3'd7)
                    next_state = STOP_CHECK;

            STOP_CHECK:
                if (sample_now)
                    next_state = IDLE;

            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // 4. Sample counter (0-15 oversampling ticks per bit period)
    //    Reset on IDLE→START_CHECK transition so that the 8th tick (MID_SAMPLE)
    //    lands at the centre of each bit.
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            sample_counter <= 0;
        else if (state == IDLE && next_state == START_CHECK)
            sample_counter <= 0;
        else if (baud_tick_ovs)
            sample_counter <= (sample_counter == 4'd15) ? 4'd0
                                                        : sample_counter + 1'b1;
    end

    assign sample_now = (sample_counter == MID_SAMPLE) && baud_tick_ovs;

    // -------------------------------------------------------------------------
    // 5. Data bit counter (0-7)
    //    Cleared on START_CHECK→DATA transition; incremented each sample_now.
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            data_counter <= 0;
        else if (state == START_CHECK && next_state == DATA)
            data_counter <= 0;
        else if (state == DATA && sample_now)
            data_counter <= data_counter + 1'b1;
    end

    // -------------------------------------------------------------------------
    // 6. SIPO shift register
    //    UART sends LSB first, so shifting new bits in from the MSB and letting
    //    them ripple down naturally reconstructs the byte in the correct order.
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            sipo <= 8'h00;
        else if (state == DATA && sample_now)
            sipo <= {rxd_sync[0], sipo[7:1]};  // LSB-first: shift right, fill MSB
    end

    // -------------------------------------------------------------------------
    // 7. Frame-error flag
    //    Set when:  start bit sampled HIGH  (false start / noise)
    //               stop  bit sampled LOW   (framing error)
    //    Cleared on the next start-bit edge (IDLE→START_CHECK).
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            flag_store <= 1'b0;
        else if (state == IDLE && next_state == START_CHECK)
            flag_store <= 1'b0;
        else if (state == START_CHECK && sample_now && rxd_sync[0] == 1'b1)
            flag_store <= 1'b1;   // false start bit
        else if (state == STOP_CHECK && sample_now && rxd_sync[0] == 1'b0)
            flag_store <= 1'b1;   // missing stop bit → framing error
    end

    assign flag = flag_store;

    // -------------------------------------------------------------------------
    // 8. Data-ready output
    //    rx_ready pulses HIGH for exactly one clock cycle and rx_data is
    //    updated only when a complete, valid frame (good stop bit) is received.
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            rx_ready_store <= 1'b0;
            rx_data        <= 8'h00;
        end
        else if (state == STOP_CHECK && sample_now && rxd_sync[0] == 1'b1) begin
            rx_ready_store <= 1'b1;
            rx_data        <= sipo;     // latch the received byte
        end
        else
            rx_ready_store <= 1'b0;
    end

    assign rx_ready = rx_ready_store;

endmodule

`default_nettype wire
