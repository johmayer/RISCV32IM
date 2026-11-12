.PHONY: test clean

SIM ?= icarus
TOPLEVEL_LANG := verilog
TOPLEVEL := rv32im_single_cycle
MODULE := test_rv32im_single_cycle
VERILOG_SOURCES := $(abspath ../rtl/core/rv32im_single_cycle.sv)
COCOTB_TEST_MODULES := $(abspath ../tb/cocotb)

export TOPLEVEL_LANG TOPLEVEL MODULE VERILOG_SOURCES
export PYTHONPATH := $(COCOTB_TEST_MODULES):$(PYTHONPATH)

test:
	@mkdir -p build
	@cd build && \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) TOPLEVEL=$(TOPLEVEL) \
		MODULE=$(MODULE) VERILOG_SOURCES=$(VERILOG_SOURCES) \
		PYTHONPATH=$(PYTHONPATH) \
		$(MAKE) -f $$(cocotb-config --makefiles)/Makefile.sim SIM=$(SIM)

clean:
	rm -rf build
