# RISCV32IM

This is an implementation of a RV32IM or RV64IM single-cycle core with a 
cocotb based verification.

## Design and testbench

The design is a single-cycle RISC-V integer core with the RV32I base ISA and
M extension. It includes instruction decode, an ALU, register file,
program counter, branch/jump logic, and a byte-addressed load/store interface.
The same RTL can be simulated as RV64IM by overriding `XLEN`.

The cocotb testbench drives instructions and memory directly, then checks
instruction results, memory operations, control-flow programs, and edge cases.
Both configurations can be run with `make test-rv32` and `make test-rv64`.

The current scope:

- SystemVerilog RTL in [`rtl/core`](./rtl/core)
- cocotb tests in [`tb/cocotb`](./tb/cocotb)
- Icarus Verilog as the easiest default simulator
- Verilator as an optional fast simulator and lint tool

## Quick start

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt

# Install iverilog using the system package manager; see the workflow guide.
make doctor
make test
```

`make test` runs the RV32IM cocotb regression.
