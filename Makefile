# =============================================================================
# Makefile — UART ICE40HX1K FPGA ↔ Arduino Uno
# Toolchain : Yosys + nextpnr-ice40 + icepack + iceprog (IceStorm)
# =============================================================================

TOP      := uart_top
DEVICE   := hx1k
PACKAGE  := tq144
PCF      := constraints/icestick.pcf

RTL_SRCS := rtl/uart_rx.v \
            rtl/uart_tx.v \
            rtl/uart_top.v

BUILD_DIR := build

.PHONY: all synth pnr pack prog sim clean

all: $(BUILD_DIR)/$(TOP).bin

$(BUILD_DIR):
	mkdir -p $@

# --- Synthesis (Yosys) -------------------------------------------------------
$(BUILD_DIR)/$(TOP).json: $(RTL_SRCS) | $(BUILD_DIR)
	yosys -p "synth_ice40 -top $(TOP) -json $@" $(RTL_SRCS)

synth: $(BUILD_DIR)/$(TOP).json

# --- Place & Route (nextpnr-ice40) -------------------------------------------
$(BUILD_DIR)/$(TOP).asc: $(BUILD_DIR)/$(TOP).json $(PCF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) \
	              --json $< --pcf $(PCF) --asc $@

pnr: $(BUILD_DIR)/$(TOP).asc

# --- Bitstream packing (icepack) ---------------------------------------------
$(BUILD_DIR)/$(TOP).bin: $(BUILD_DIR)/$(TOP).asc
	icepack $< $@

pack: $(BUILD_DIR)/$(TOP).bin

# --- Flash to iCEstick (iceprog) ---------------------------------------------
prog: $(BUILD_DIR)/$(TOP).bin
	iceprog $<

# --- Icarus Verilog simulation -----------------------------------------------
sim:
	iverilog -g2012 -o $(BUILD_DIR)/sim_out \
	         sim/uart_tb.v rtl/uart_rx.v rtl/uart_tx.v rtl/uart_top.v
	vvp $(BUILD_DIR)/sim_out
	@echo "Open sim/uart_tb.vcd in GTKWave to inspect waveforms."

# --- Cleanup -----------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR)
