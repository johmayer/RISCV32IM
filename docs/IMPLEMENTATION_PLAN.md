
# RV32I Processor Implementation for FreeRTOS

## 1. CPU Core

- [ ] 32-bit datapath and ALU
- [ ] 32 × 32-bit general-purpose registers (`x0`–`x31`)
- [ ] Program counter (PC)
- [ ] Instruction fetch and decode
- [ ] Register file read/write
- [ ] Immediate generator (I, S, B, U and J formats)
- [ ] Branch and jump logic
- [ ] Load/store unit
- [ ] Byte and halfword alignment and sign extension
- [ ] Memory interface

## 2. Instruction Set

Implement the complete RV32I base instruction set:

- [ ] Arithmetic: `ADD`, `SUB`, `ADDI`
- [ ] Logical: `AND`, `OR`, `XOR`
- [ ] Shifts: `SLL`, `SRL`, `SRA` and immediate variants
- [ ] Comparisons: `SLT`, `SLTU` and immediate variants
- [ ] Branches: `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`
- [ ] Jumps: `JAL`, `JALR`
- [ ] Memory: `LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`
- [ ] Upper immediate: `LUI`, `AUIPC`
- [ ] Memory ordering: `FENCE`
- [ ] System instructions: `ECALL`, `EBREAK`, `MRET`, `WFI`

## 3. CSR and Interrupt Handling

- [ ] Six CSR instructions:
  - `CSRRW`
  - `CSRRS`
  - `CSRRC`
  - `CSRRWI`
  - `CSRRSI`
  - `CSRRCI`
- [ ] `mstatus`
- [ ] `mie`
- [ ] `mip`
- [ ] `mtvec`
- [ ] `mepc`
- [ ] `mcause`
- [ ] `mtval`
- [ ] Interrupt detection and prioritization
- [ ] Trap entry and return mechanism
- [ ] Save interrupted PC and restore it using `MRET`

## 4. Peripherals

- [ ] Machine timer (`mtime`)
- [ ] Machine timer compare (`mtimecmp`)
- [ ] Timer interrupt signal
- [ ] External interrupt input/controller
- [ ] UART for debugging
- [ ] Memory (RAM and program storage)

## 5. FreeRTOS-Specific Functionality

- [ ] Context switching (saving/restoring CPU registers)
- [ ] Timer-based scheduler tick
- [ ] Interrupt stack handling
- [ ] Critical section support (interrupt masking)
- [ ] Initial task stack setup
- [ ] Task startup and termination support

## 6. Recommended Implementation Milestones

### Milestone 1: Bare-Metal RV32I
- Implement the complete RV32I instruction set.
- Run compiled C programs.
- Verify instruction execution.

### Milestone 2: CSR and Traps
- Implement machine-mode CSRs.
- Implement exceptions and interrupts.
- Implement trap entry and `MRET`.

### Milestone 3: Timer
- Implement `mtime` and `mtimecmp`.
- Generate periodic machine timer interrupts.
- Verify interrupt handling.

### Milestone 4: FreeRTOS
- Implement the RISC-V context-switching port.
- Implement task register saving and restoring.
- Configure the scheduler tick.
- Run multiple tasks.

## 7. Architectural Recommendations

- Base ISA: RV32I
- Privilege mode: Machine mode (M-mode)
- CSR support: Zicsr
- Instruction-fetch synchronization: Zifencei, if required by software
- Atomic extension: Not required for a basic single-core implementation
- Multiplication/division: Optional (M extension)

**Important:** Interrupt masking can provide critical-section support on a basic single-core implementation.

Use an existing FreeRTOS RISC-V port as a reference for context-switching assembly, register saving, interrupt handling and timer configuration.

## 8. Hardware Architecture

The processor should contain the following main blocks:

- RV32I CPU Core
  - ALU
  - Register File
  - Instruction Decoder
  - Immediate Generator
  - Program Counter
- CSR Unit
- Trap Controller
- Timer
- Memory System
- External Interrupt Controller
- UART
