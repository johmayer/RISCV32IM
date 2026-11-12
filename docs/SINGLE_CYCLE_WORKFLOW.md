# Single-cycle open-source workflow

## 1. Install the tools

Use the distribution packages for the simulators and a Python virtual
environment for Cocotb 2.1. On Debian/Ubuntu:

```sh
sudo apt install python3 python3-venv make iverilog verilator
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

The minimum workflow only needs Icarus Verilog, GNU Make, Python, and cocotb.
Verilator is useful for stricter linting and a faster simulator, but is not
required to start the core.

Check the environment with:

```sh
make doctor
```

## 2. Keep the first interface intentionally simple

The first top level should have one clock, one reset, and separate
instruction/data memory ports. Use a fixed one-cycle response contract first:

- instruction address is presented every cycle;
- instruction data is returned combinationally by the test memory;
- stores provide address, write data, byte enables, and a write strobe;
- loads receive data combinationally;
- no wait states, caches, interrupts, or bus fabric in the first version.

Document the exact port names and reset behavior in the RTL before writing
the testbench. Keep the core independent of the cocotb memory model so that
the same RTL can later be synthesized.

## 3. Recommended source layout

```text
rtl/core/rv32im_single_cycle.sv       # top-level core
rtl/core/rv32im_decoder.sv            # decode and immediate generation
rtl/core/rv32im_alu.sv                # arithmetic and comparison
rtl/core/rv32im_regfile.sv            # x0 hardwired to zero
tb/cocotb/test_rv32im_single_cycle.py # cocotb regression
sim/Makefile                           # simulator adapter
```

Start with one top-level file if that makes bring-up faster, then split
modules only when a boundary improves reuse or testability.

## 4. Implement in small verified increments

Use this order:

1. Reset, program counter, and instruction fetch.
2. Register reads/writes with x0 permanently zero.
3. Immediate ALU instructions.
4. Register-register ALU instructions.
5. Branches and jumps.
6. Loads and stores with byte enables.
7. M-extension operations, with division edge cases specified explicitly.
8. Illegal-instruction behavior and architectural cleanup.

After each increment, add a directed cocotb test before adding the next
instruction class. Test observable architectural state rather than internal
signals wherever possible.

## 5. Cocotb test conventions

The testbench should provide reusable helpers for:

- clock and reset;
- loading 32-bit instruction words into a small instruction memory;
- emulating data memory;
- stepping until a defined completion condition;
- reading registers or a memory-mapped test result.

Prefer short assembly encodings or hand-built instruction words initially.
Later, add ELF/bin loading and RISC-V architectural tests. Keep each test
focused on one behavior and include a timeout so a broken core cannot hang
the regression.

Once the two expected files exist, run:

```sh
make test
```

For linting:

```sh
make lint
```

To try another cocotb simulator, pass its simulator name when supported by
the installed cocotb makefile:

```sh
make test SIM=verilator
```

## 6. Reproducibility rules

- Pin Python dependencies in a lock file once the test suite exists.
- Record simulator versions in bug reports and CI logs.
- Never put generated waveforms or simulator build products under source
  control.
- Add CI only after the local `make doctor`, `make test`, and `make lint`
  commands are stable.

Do not add FPGA constraints, OpenROAD configuration, SRAM models, or SoC
software until the single-cycle core has a passing architectural regression.
