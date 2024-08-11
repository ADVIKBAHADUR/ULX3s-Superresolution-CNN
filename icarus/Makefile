# Makefile for Icarus Verilog simulation
# 02-11-2019 E. Brombaugh
PROJECT = CSI
BOARD = ulx3s
# 12 25 45 85
FPGA_SIZE = 85
FPGA_PACKAGE = CABGA381
CONSTRAINTS = constraint/ulx3s_v20.lpf
TOP_MODULE = top_module
TOP_MODULE_FILE = ../src/$(TOP_MODULE).v


# sources
SOURCES = 	superresolutiontb.v \
  $(TOP_MODULE_FILE) \
  ../src/SubTop_superresolution.v \
  ../src/superresolution.v \
  ../src/asyn_fifo.v \
  ../src/camera_interface.v \
  ../src/debounce_explicit.v \
  ../src/hdmi_device.v \
  ../src/i2c_top.v \
  ../src/my_vga_clk_generator.v \
  ../src/pll_HDMI.v \
  ../src/pll_SDRAM.v \
  ../src/pll_SOBEL.v \
  ../src/sdram_interface.v \
  ../src/tmds_encoder.v \
  ../src/vga_interface.v \
  ../src/sdram_controller.v \
# preparing the machine code
HEX =	rom.hex

# top level
TOP = superresolutiontb
			
# Executables
VLOG = iverilog
WAVE = gtkwave
TECH_LIB = ~/Downloads/oss-cad-suite-linux-x64-20240702/oss-cad-suite/share/yosys/ecp5/cells_sim.v -I ~/Downloads/oss-cad-suite-linux-x64-20240702/oss-cad-suite/share/yosys/ecp5/
ASM6502 = acme
HEXDUMP = hexdump
HEXDUMP_ARGS = -v -e '1/1 "%02x " "\n"'

# targets
all: $(TOP).vcd

$(HEX):
	$(MAKE) -C ../cc65/
	cp ../cc65/$(HEX) .
	
wave: $(TOP).vcd $(TOP).gtkw
	$(WAVE) $(TOP).gtkw
	
$(TOP).vcd: $(TOP)
	./$(TOP)

$(TOP): $(SOURCES) $(HEX)
	$(VLOG) -D icarus -l $(TECH_LIB) -o $(TOP) $(SOURCES)





	
