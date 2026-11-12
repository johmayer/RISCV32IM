# RISCV32IM

Open-source development environment for a portable SystemVerilog RV32IM
single-cycle core and its cocotb testbench.

The current scope is deliberately small:

- SystemVerilog RTL in [`rtl/core`](./rtl/core)
- cocotb tests in [`tb/cocotb`](./tb/cocotb)
- Icarus Verilog as the easiest default simulator
- Verilator as an optional fast simulator and lint tool
- no FPGA, ASIC, SoC, or software targets yet

See [`docs/SINGLE_CYCLE_WORKFLOW.md`](./docs/SINGLE_CYCLE_WORKFLOW.md) for
installation, source layout, test conventions, and the recommended first
implementation sequence.

## Quick start

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt

# Install iverilog using the system package manager; see the workflow guide.
make doctor
make test
```

`make test` is intentionally a setup check until the first RTL top level and
cocotb test are added. It will run the cocotb regression automatically once
`rtl/core/rv32im_single_cycle.sv` and `tb/cocotb/test_rv32im_single_cycle.py`
exist.
