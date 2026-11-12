.PHONY: all doctor test lint clean

SIM ?= icarus
SIM_BIN := $(if $(filter icarus,$(SIM)),iverilog,$(SIM))
RTL_TOP := rtl/core/rv32im_single_cycle.sv
COCOTB_TEST := tb/cocotb/test_rv32im_single_cycle.py

all: test

doctor:
	@command -v python3 >/dev/null || (echo "error: python3 is required" >&2; exit 1)
	@command -v $(SIM_BIN) >/dev/null || (echo "error: $(SIM_BIN) is required; install it with your system package manager" >&2; exit 1)
	@python3 -c "import cocotb" || (echo "error: cocotb is missing; run python3 -m pip install -r requirements.txt" >&2; exit 1)
	@echo "Toolchain is available: simulator=$(SIM)"

test:
	@if [ ! -f "$(RTL_TOP)" ] || [ ! -f "$(COCOTB_TEST)" ]; then \
		echo "RTL/testbench not implemented yet; scaffold is ready."; \
	else \
		$(MAKE) doctor SIM=$(SIM) && $(MAKE) -C sim test SIM=$(SIM); \
	fi

lint:
	@command -v verilator >/dev/null || (echo "error: verilator is required for lint" >&2; exit 1)
	@verilator --lint-only -Wall --language 1800-2012 $(RTL_TOP)

clean:
	rm -rf sim/build sim/results sim/coverage
