.PHONY: all doctor test test-rv32 test-rv64 lint clean

SIM ?= icarus
SIM_BIN := $(if $(filter icarus,$(SIM)),iverilog,$(SIM))
RTL_SOURCES := $(CURDIR)/rtl/core/rv32im_pkg.sv $(filter-out $(CURDIR)/rtl/core/rv32im_pkg.sv,$(wildcard $(CURDIR)/rtl/core/*.sv))
RTL_TOP := $(CURDIR)/rtl/core/rv32im_single_cycle.sv
COCOTB_TEST := tb/cocotb/test_rv32im_single_cycle.py
XLEN ?= 32
SIM_BUILD := $(CURDIR)/sim/build/rv$(XLEN)

all: test

doctor:
	@command -v python3 >/dev/null || (echo "error: python3 is required" >&2; exit 1)
	@command -v $(SIM_BIN) >/dev/null || (echo "error: $(SIM_BIN) is required; install it with your system package manager" >&2; exit 1)
	@python3 -c "import cocotb" || (echo "error: cocotb is missing; run python3 -m pip install -r requirements.txt" >&2; exit 1)
	@echo "Toolchain is available: simulator=$(SIM)"

test:
	@$(MAKE) doctor SIM=$(SIM)
	@mkdir -p "$(SIM_BUILD)"
	@sed 's@^/ load@// load@' "$(RTL_TOP)" > "$(SIM_BUILD)/rv32im_single_cycle.sv"
	@cd "$(SIM_BUILD)" && \
		TOPLEVEL_LANG=verilog TOPLEVEL=riscv32im_single_cycle \
		MODULE=test_rv32im_single_cycle \
		VERILOG_SOURCES="$(filter-out $(RTL_TOP),$(RTL_SOURCES)) $(SIM_BUILD)/rv32im_single_cycle.sv" \
		PYTHONPATH="$(CURDIR)/tb/cocotb" \
		SIM_BUILD="$(SIM_BUILD)" \
		COMPILE_ARGS="-P riscv32im_single_cycle.XLEN=$(XLEN)" \
		$(MAKE) -f $$(cocotb-config --makefiles)/Makefile.sim SIM=$(SIM)

test-rv32:
	@$(MAKE) test XLEN=32 SIM=$(SIM)

test-rv64:
	@$(MAKE) test XLEN=64 SIM=$(SIM)

lint:
	@command -v verilator >/dev/null || (echo "error: verilator is required for lint" >&2; exit 1)
	@verilator --lint-only -Wall --language 1800-2012 $(RTL_SOURCES)

clean:
	rm -rf sim/build sim/results sim/coverage
