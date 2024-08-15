# ******* project, board and chip name *******
PROJECT = CSI
BOARD = ulx3s
# 12 25 45 85
FPGA_SIZE = 85
FPGA_PACKAGE = CABGA381

# ******* if programming with OpenOCD *******
# using local latest openocd until in linux distribution
#OPENOCD=openocd_ft232r
# default onboard usb-jtag
OPENOCD_INTERFACE=$(SCRIPTS)/ft231x.ocd
# ulx3s-jtag-passthru
#OPENOCD_INTERFACE=$(SCRIPTS)/ft231x2.ocd
# ulx2s
#OPENOCD_INTERFACE=$(SCRIPTS)/ft232r.ocd
# external jtag
#OPENOCD_INTERFACE=$(SCRIPTS)/ft2232.ocd

# ******* design files *******
CONSTRAINTS = constraint/ulx3s_v20.lpf
#TOP_MODULE = top
#TOP_MODULE_FILE = top/$(TOP_MODULE).v
TOP_MODULE = top_module
TOP_MODULE_FILE = src/$(TOP_MODULE).v

VERILOG_FILES = \
  $(TOP_MODULE_FILE) \
  src/ecp5pll.sv \
  src/SubTop_superresolution.v \
  src/superresolution.v \
  src/weight_loader.v \
  src/upscaling.v \
  src/conv_layer.v \
  src/dsp.v \
  src/relu.v \
  src/asyn_fifo.v \
  src/camera_interface.v \
  src/debounce_explicit.v \
  src/hdmi_device.v \
  src/i2c_top.v \
  src/my_vga_clk_generator.v \
  src/pll_HDMI.v \
  src/pll_SDRAM.v \
  src/pll_SOBEL.v \
  src/sdram_interface.v \
  src/tmds_encoder.v \
  src/vga_interface.v \
  src/sdram_controller.v \

# *.vhd those files will be converted to *.v files with vhdl2vl (warning overwriting/deleting)
VHDL_FILES = \
#  hdl/vga.vhd \
#  hdl/vga2dvid.vhd \
#  hdl/tmds_encoder.vhd

# synthesis options
YOSYS_OPTIONS = -noccu2
NEXTPNR_OPTIONS = --timing-allow-fail --speed 7 --lpf-allow-unconstrained

SCRIPTS = scripts
include $(SCRIPTS)/diamond_path.mk
include $(SCRIPTS)/trellis_path.mk
include $(SCRIPTS)/trellis_main.mk