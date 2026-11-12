"""Comprehensive instruction, corner-case, and randomized verification for RV32IM/RV64IM."""

from __future__ import annotations

from dataclasses import dataclass, field
import random
from typing import Iterable

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


# ---------------------------------------------------------------------------
# Bit-manipulation helpers
# ---------------------------------------------------------------------------

def mask(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def signed(value: int, width: int) -> int:
    value = mask(value, width)
    return value - (1 << width) if value & (1 << (width - 1)) else value


def sext(value: int, from_width: int, to_width: int) -> int:
    return mask(signed(value, from_width), to_width)


def c_div(dividend: int, divisor: int, width: int) -> int:
    """RISC-V signed division semantics (truncates toward zero, handles overflow/div-by-0)."""
    a = signed(dividend, width)
    b = signed(divisor, width)
    min_val = -(1 << (width - 1))
    if b == 0:
        return mask(-1, width)
    if a == min_val and b == -1:
        return mask(min_val, width)
    q = abs(a) // abs(b)
    if (a < 0) ^ (b < 0):
        q = -q
    return mask(q, width)


def c_rem(dividend: int, divisor: int, width: int) -> int:
    """RISC-V signed remainder semantics."""
    a = signed(dividend, width)
    b = signed(divisor, width)
    min_val = -(1 << (width - 1))
    if b == 0:
        return mask(a, width)
    if a == min_val and b == -1:
        return 0
    r = abs(a) % abs(b)
    if a < 0:
        r = -r
    return mask(r, width)


# ---------------------------------------------------------------------------
# Instruction Encoders (RV32IM + RV64IM)
# ---------------------------------------------------------------------------

def r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int = 0x33) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def i_type(imm: int, rs1: int, funct3: int, rd: int, opcode: int = 0x13) -> int:
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def s_type(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | 0x23


def b_type(offset: int, rs2: int, rs1: int, funct3: int) -> int:
    imm = offset & 0x1FFF
    return (
        ((imm >> 12) << 31)
        | (((imm >> 5) & 0x3F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (((imm >> 1) & 0xF) << 8)
        | (((imm >> 11) & 1) << 7)
        | 0x63
    )


def u_type(imm20: int, rd: int, opcode: int) -> int:
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def j_type(offset: int, rd: int) -> int:
    imm = offset & 0x1FFFFF
    return (
        ((imm >> 20) << 31)
        | (((imm >> 1) & 0x3FF) << 21)
        | (((imm >> 11) & 1) << 20)
        | (((imm >> 12) & 0xFF) << 12)
        | (rd << 7)
        | 0x6F
    )


def addi(rd: int, rs1: int, imm: int) -> int:
    return i_type(imm, rs1, 0, rd, 0x13)


def addiw(rd: int, rs1: int, imm: int) -> int:
    return i_type(imm, rs1, 0, rd, 0x1B)


def slli(rd: int, rs1: int, shamt: int) -> int:
    return i_type(shamt & 0x3F, rs1, 1, rd, 0x13)


def srli(rd: int, rs1: int, shamt: int) -> int:
    return i_type(shamt & 0x3F, rs1, 5, rd, 0x13)


def srai(rd: int, rs1: int, shamt: int) -> int:
    return i_type(0x400 | (shamt & 0x3F), rs1, 5, rd, 0x13)


def lui(rd: int, imm20: int) -> int:
    return u_type(imm20, rd, 0x37)


def auipc(rd: int, imm20: int) -> int:
    return u_type(imm20, rd, 0x17)


def jal(rd: int, offset: int) -> int:
    return j_type(offset, rd)


def jalr(rd: int, rs1: int, imm: int) -> int:
    return i_type(imm, rs1, 0, rd, 0x67)


def load(rd: int, rs1: int, imm: int, funct3: int) -> int:
    return i_type(imm, rs1, funct3, rd, 0x03)


def store(rs2: int, rs1: int, imm: int, funct3: int) -> int:
    return s_type(imm, rs2, rs1, funct3)


def halt() -> int:
    return jal(0, 0)


def load_const(rd: int, value: int, xlen: int) -> list[int]:
    """Emit an instruction sequence that loads an arbitrary 32-bit or 64-bit constant into `rd`."""
    if rd == 0:
        return []
    val = mask(value, xlen)
    if xlen == 32 or -2048 <= signed(val, 64) <= 2047:
        lo = signed(val & 0xFFF, 12)
        hi = ((val - lo) >> 12) & 0xFFFFF
        if hi == 0:
            return [addi(rd, 0, lo)]
        return [lui(rd, hi), addi(rd, rd, lo)] if lo != 0 else [lui(rd, hi)]

    # General 64-bit constant construction: build upper 32 bits, shift left 32, add lower 32 bits
    hi32 = (val >> 32) & 0xFFFFFFFF
    lo32 = val & 0xFFFFFFFF
    # Adjust for signed lower-half additions
    lo12 = signed(lo32 & 0xFFF, 12)
    mid20 = ((lo32 - lo12) >> 12) & 0xFFFFF
    if mid20 & 0x80000:
        hi32 = (hi32 + 1) & 0xFFFFFFFF

    seq = load_const(rd, signed(hi32, 32), 32)
    seq.append(slli(rd, rd, 32))
    if mid20 != 0:
        # Use x31 as scratch for upper-32 LUI without sign-extension pollution
        seq += [lui(31, mid20), slli(31, 31, 32), srli(31, 31, 32), r_type(0, 31, rd, 0, rd)]
    if lo12 != 0:
        seq.append(addi(rd, rd, lo12))
    return seq

def init_zero_regs() -> list[int]:
    """Explicitly zero x1..x30 so uninitialized RTL registers match RVModel across tests."""
    return [addi(r, 0, 0) for r in range(1, 31)]

# ---------------------------------------------------------------------------
# Byte-Addressable Memory & Golden RV32IM / RV64IM Reference Model
# ---------------------------------------------------------------------------

@dataclass
class Memory:
    bytes: dict[int, int]
    width: int

    def read(self, address: int, num_bytes: int | None = None) -> int:
        n = self.width if num_bytes is None else num_bytes
        return sum(self.bytes.get(address + i, 0) << (8 * i) for i in range(n))

    def write(self, address: int, value: int, enables: int) -> None:
        # Mask address to bus width in case DUT outputs aligned address + lane-shifted data
        aligned = address & ~(self.width - 1)
        for i in range(self.width):
            if enables & (1 << i):
                self.bytes[aligned + i] = (value >> (8 * i)) & 0xFF

    def write_bytes(self, address: int, value: int, num_bytes: int) -> None:
        for i in range(num_bytes):
            self.bytes[address + i] = (value >> (8 * i)) & 0xFF


@dataclass
class RVModel:
    """Architectural Golden Reference Model for RV32IM and RV64IM."""
    xlen: int
    program: list[int]
    mem: Memory
    regs: list[int] = field(default_factory=lambda: [0] * 32)
    pc: int = 0

    def step(self) -> bool:
        """Execute one instruction. Returns False when halted."""
        idx = self.pc // 4
        instr = self.program[idx] if 0 <= idx < len(self.program) else halt()
        if instr == halt() and self.pc != 0:
            return False

        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        funct3 = (instr >> 12) & 0x7
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        funct7 = (instr >> 25) & 0x7F

        v1 = self.regs[rs1]
        v2 = self.regs[rs2]
        next_pc = mask(self.pc + 4, self.xlen)
        result: int | None = None

        if opcode == 0x37:  # LUI
            result = sext(instr & 0xFFFFF000, 32, self.xlen)

        elif opcode == 0x17:  # AUIPC
            result = mask(self.pc + signed(instr & 0xFFFFF000, 32), self.xlen)

        elif opcode == 0x6F:  # JAL
            imm = (
                ((instr >> 31) & 1) << 20
                | ((instr >> 12) & 0xFF) << 12
                | ((instr >> 20) & 1) << 11
                | ((instr >> 21) & 0x3FF) << 1
            )
            result = next_pc
            next_pc = mask(self.pc + signed(imm, 21), self.xlen)

        elif opcode == 0x67:  # JALR
            imm = signed(instr >> 20, 12)
            result = next_pc
            next_pc = mask((v1 + imm) & ~1, self.xlen)

        elif opcode == 0x63:  # BRANCH
            imm = (
                ((instr >> 31) & 1) << 12
                | ((instr >> 7) & 1) << 11
                | ((instr >> 25) & 0x3F) << 5
                | ((instr >> 8) & 0xF) << 1
            )
            s1, s2 = signed(v1, self.xlen), signed(v2, self.xlen)
            u1, u2 = mask(v1, self.xlen), mask(v2, self.xlen)
            taken = {
                0: u1 == u2,
                1: u1 != u2,
                4: s1 < s2,
                5: s1 >= s2,
                6: u1 < u2,
                7: u1 >= u2,
            }[funct3]
            if taken:
                next_pc = mask(self.pc + signed(imm, 13), self.xlen)

        elif opcode == 0x03:  # LOAD
            addr = mask(v1 + signed(instr >> 20, 12), self.xlen)
            size = 1 << (funct3 & 0x3)
            raw = self.mem.read(addr, size)
            if funct3 in (0, 1, 2, 3):  # LB, LH, LW, LD
                result = sext(raw, size * 8, self.xlen)
            else:  # LBU, LHU, LWU
                result = mask(raw, self.xlen)

        elif opcode == 0x23:  # STORE
            imm = ((instr >> 25) << 5) | ((instr >> 7) & 0x1F)
            addr = mask(v1 + signed(imm, 12), self.xlen)
            size = 1 << (funct3 & 0x3)
            self.mem.write_bytes(addr, v2, size)

        elif opcode == 0x13:  # OP-IMM
            imm = signed(instr >> 20, 12)
            shamt = (instr >> 20) & (0x3F if self.xlen == 64 else 0x1F)
            if funct3 == 0:
                result = mask(v1 + imm, self.xlen)
            elif funct3 == 1:
                result = mask(v1 << shamt, self.xlen)
            elif funct3 == 2:
                result = 1 if signed(v1, self.xlen) < imm else 0
            elif funct3 == 3:
                result = 1 if mask(v1, self.xlen) < mask(imm, self.xlen) else 0
            elif funct3 == 4:
                result = mask(v1 ^ mask(imm, self.xlen), self.xlen)
            elif funct3 == 5:
                if (instr >> 30) & 1:
                    result = mask(signed(v1, self.xlen) >> shamt, self.xlen)
                else:
                    result = mask(v1, self.xlen) >> shamt
            elif funct3 == 6:
                result = mask(v1 | mask(imm, self.xlen), self.xlen)
            elif funct3 == 7:
                result = mask(v1 & mask(imm, self.xlen), self.xlen)

        elif opcode == 0x1B and self.xlen == 64:  # OP-IMM-32 (RV64I)
            imm = signed(instr >> 20, 12)
            shamt = (instr >> 20) & 0x1F
            w1 = mask(v1, 32)
            if funct3 == 0:  # ADDIW
                result = sext(w1 + imm, 32, 64)
            elif funct3 == 1:  # SLLIW
                result = sext(w1 << shamt, 32, 64)
            elif funct3 == 5:
                if (instr >> 30) & 1:  # SRAIW
                    result = sext(signed(w1, 32) >> shamt, 32, 64)
                else:  # SRLIW
                    result = sext(w1 >> shamt, 32, 64)

        elif opcode == 0x33:  # OP (RV32I/RV64I + M-Extension)
            shamt = v2 & (0x3F if self.xlen == 64 else 0x1F)
            if funct7 == 0x01:  # M-Extension
                s1, s2 = signed(v1, self.xlen), signed(v2, self.xlen)
                u1, u2 = mask(v1, self.xlen), mask(v2, self.xlen)
                if funct3 == 0:    # MUL
                    result = mask(s1 * s2, self.xlen)
                elif funct3 == 1:  # MULH
                    result = mask((s1 * s2) >> self.xlen, self.xlen)
                elif funct3 == 2:  # MULHSU
                    result = mask((s1 * u2) >> self.xlen, self.xlen)
                elif funct3 == 3:  # MULHU
                    result = mask((u1 * u2) >> self.xlen, self.xlen)
                elif funct3 == 4:  # DIV
                    result = c_div(v1, v2, self.xlen)
                elif funct3 == 5:  # DIVU
                    result = mask(-1, self.xlen) if u2 == 0 else mask(u1 // u2, self.xlen)
                elif funct3 == 6:  # REM
                    result = c_rem(v1, v2, self.xlen)
                elif funct3 == 7:  # REMU
                    result = u1 if u2 == 0 else mask(u1 % u2, self.xlen)
            else:
                if funct3 == 0:
                    result = mask(v1 - v2 if funct7 == 0x20 else v1 + v2, self.xlen)
                elif funct3 == 1:
                    result = mask(v1 << shamt, self.xlen)
                elif funct3 == 2:
                    result = 1 if signed(v1, self.xlen) < signed(v2, self.xlen) else 0
                elif funct3 == 3:
                    result = 1 if mask(v1, self.xlen) < mask(v2, self.xlen) else 0
                elif funct3 == 4:
                    result = mask(v1 ^ v2, self.xlen)
                elif funct3 == 5:
                    if funct7 == 0x20:
                        result = mask(signed(v1, self.xlen) >> shamt, self.xlen)
                    else:
                        result = mask(v1, self.xlen) >> shamt
                elif funct3 == 6:
                    result = mask(v1 | v2, self.xlen)
                elif funct3 == 7:
                    result = mask(v1 & v2, self.xlen)

        elif opcode == 0x3B and self.xlen == 64:  # OP-32 (RV64IM)
            w1, w2 = mask(v1, 32), mask(v2, 32)
            shamt = w2 & 0x1F
            if funct7 == 0x01:  # RV64M *W
                s1, s2 = signed(w1, 32), signed(w2, 32)
                if funct3 == 0:    # MULW
                    result = sext(s1 * s2, 32, 64)
                elif funct3 == 4:  # DIVW
                    result = sext(c_div(w1, w2, 32), 32, 64)
                elif funct3 == 5:  # DIVUW
                    q = 0xFFFFFFFF if w2 == 0 else (w1 // w2)
                    result = sext(q, 32, 64)
                elif funct3 == 6:  # REMW
                    result = sext(c_rem(w1, w2, 32), 32, 64)
                elif funct3 == 7:  # REMUW
                    r = w1 if w2 == 0 else (w1 % w2)
                    result = sext(r, 32, 64)
            else:
                if funct3 == 0:    # ADDW / SUBW
                    result = sext(w1 - w2 if funct7 == 0x20 else w1 + w2, 32, 64)
                elif funct3 == 1:  # SLLW
                    result = sext(w1 << shamt, 32, 64)
                elif funct3 == 5:
                    if funct7 == 0x20:  # SRAW
                        result = sext(signed(w1, 32) >> shamt, 32, 64)
                    else:               # SRLW
                        result = sext(w1 >> shamt, 32, 64)

        elif opcode in (0x0F, 0x73):  # FENCE, ECALL, EBREAK (NOPs)
            pass

        if result is not None and rd != 0:
            self.regs[rd] = mask(result, self.xlen)
        self.regs[0] = 0
        self.pc = next_pc
        return True

    def run(self, max_cycles: int = 2000) -> None:
        for _ in range(max_cycles):
            if not self.step():
                break


# ---------------------------------------------------------------------------
# DUT Runner + Golden Lockstep Checker
# ---------------------------------------------------------------------------

async def run_and_verify(
    dut,
    program: Iterable[int],
    initial: dict[int, int] | None = None,
    cycles: int = 500,
) -> tuple[Memory, RVModel]:
    """Execute `program` on both the DUT and Golden Model, then assert full memory equivalence."""
    xlen = len(dut.pc_o)
    width = len(dut.mem_byte_en_o)
    prog_list = list(program)

    dut_mem = Memory(dict(initial or {}), width)
    ref_mem = Memory(dict(initial or {}), width)
    model = RVModel(xlen=xlen, program=prog_list, mem=ref_mem)

    clock = Clock(dut.clk_i, 1, unit="ns")
    cocotb.start_soon(clock.start())
    dut.rst_n_i.value = 0
    dut.instr_i.value = 0
    dut.data_mem_i.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk_i)
    dut.rst_n_i.value = 1

    for _ in range(cycles):
        await ReadOnly()
        await Timer(1, unit="ps")
        pc = int(dut.pc_o.value)
        assert pc == model.pc, f"PC mismatch: DUT=0x{pc:x}, REF=0x{model.pc:x}"

        dut.instr_i.value = prog_list[pc // 4] if 0 <= pc // 4 < len(program) else halt()
        await Timer(1, unit="ps")

        address = int(dut.mem_addr_o.value)
        aligned = address & ~(width - 1)
        dut.data_mem_i.value = dut_mem.read(aligned)
        await Timer(1, unit="ps")
        await ReadOnly()

        write = bool(dut.mem_write_en_o.value)
        write_enables = int(dut.mem_byte_en_o.value) if write else 0
        write_data = 0
        if write:
            bit_str = str(dut.data_mem_o.value)
            clean_bits = bit_str.lower().replace("x", "0").replace("z", "0")
            write_data = int(clean_bits, 2)

        await RisingEdge(dut.clk_i)
        if write:
            dut_mem.write(address, write_data, write_enables)

        if not model.step():
            break

    # Compare every byte written in either DUT or Reference memory
    all_addrs = sorted(set(dut_mem.bytes.keys()) | set(ref_mem.bytes.keys()))
    for addr in all_addrs:
        d_val = dut_mem.bytes.get(addr, 0)
        r_val = ref_mem.bytes.get(addr, 0)
        assert d_val == r_val, (
            f"Memory mismatch at 0x{addr:04x}: DUT=0x{d_val:02x}, REF=0x{r_val:02x}"
        )

    return dut_mem, model


def dump_all_registers(xlen: int, base_addr: int = 0x400, regs: Iterable[int] = range(31)) -> list[int]:
    """Append instructions to store selected registers into memory at `base_addr`."""
    stride = xlen // 8
    store_funct3 = 3 if xlen == 64 else 2
    seq = load_const(31, base_addr, xlen)
    for reg in regs:
        seq.append(store(reg, 31, reg * stride, store_funct3))
    seq.append(halt())
    return seq


# ---------------------------------------------------------------------------
# Directed & Edge-Case Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_x0_hardwired_zero(dut):
    """Verify writes to x0 from ALU, LUI, AUIPC, JAL, JALR, and LOAD are ignored."""
    xlen = len(dut.pc_o)
    p = [
        addi(0, 0, 123),
        lui(0, 0xABCDE),
        auipc(0, 0x10),
        jal(0, 4),
        jalr(0, 0, 20),  # PC=16 -> jumps to 20
        load(0, 0, 0x100, 2),
        r_type(0, 0, 0, 0, 1),  # x1 = x0 + x0 (must be 0)
    ] + dump_all_registers(xlen)
    _, model = await run_and_verify(dut, p, initial={0x100: 0xFF, 0x101: 0xFF})
    assert model.regs[0] == 0


@cocotb.test()
async def test_all_alu_and_m_corner_cases(dut):
    """Verify full-XLEN ALU, negative shifts, upper MULH*, and DIV/REM corner cases."""
    xlen = len(dut.pc_o)
    min_val = -(1 << (xlen - 1))
    max_val = (1 << (xlen - 1)) - 1

    p = []
    p += load_const(1, min_val, xlen)       # x1 = INT_MIN (0x8000...0000)
    p += load_const(2, -1, xlen)            # x2 = -1 (0xFFFF...FFFF)
    p += load_const(3, max_val, xlen)       # x3 = INT_MAX (0x7FFF...FFFF)
    p += load_const(4, 0x12345678, xlen)

    p += [
        # Negative arithmetic vs logical shifts (verifies MSB sign replication)
        srai(5, 1, 4),                      # INT_MIN >>> 4
        srli(6, 1, 4),                      # INT_MIN >> 4
        slli(7, 4, xlen - 4),               # Shift up to MSB boundary
        # Upper half multiplications (MUL, MULH, MULHSU, MULHU)
        r_type(1, 3, 1, 0, 8),              # MUL(INT_MIN, INT_MAX)
        r_type(1, 3, 1, 1, 9),              # MULH(INT_MIN, INT_MAX) -> neg * pos
        r_type(1, 2, 1, 2, 10),             # MULHSU(INT_MIN, -1_unsigned) -> neg * big_pos
        r_type(1, 2, 2, 3, 11),             # MULHU(-1_u, -1_u)
        # Division / Remainder corner cases: overflow (INT_MIN / -1) and div-by-zero
        r_type(1, 2, 1, 4, 12),             # DIV(INT_MIN, -1) -> INT_MIN
        r_type(1, 2, 1, 6, 13),             # REM(INT_MIN, -1) -> 0
        r_type(1, 0, 1, 4, 14),             # DIV(INT_MIN, 0)  -> -1
        r_type(1, 0, 1, 5, 15),             # DIVU(INT_MIN, 0) -> -1 (all 1s)
        r_type(1, 0, 1, 6, 16),             # REM(INT_MIN, 0)  -> INT_MIN
        r_type(1, 0, 1, 7, 17),             # REMU(INT_MIN, 0) -> INT_MIN
    ] + dump_all_registers(xlen)

    await run_and_verify(dut, p)


@cocotb.test()
async def test_rv64_word_instructions(dut):
    """Exercise RV64IM *W instructions and LWU/LD/SD (skips cleanly on RV32)."""
    init_zero_regs()
    xlen = len(dut.pc_o)
    if xlen != 64:
        return

    p = []
    # Load 0x0000_0001_8000_0000 into x1 (bit 32 = 1, bit 31 = 1)
    p += load_const(1, 0x0000_0001_8000_0000, 64)
    p += load_const(2, 0x0000_0000_FFFF_FFFF, 64)
    p += load_const(3, 0x100, 64)

    p += [
        addiw(4, 1, 0),                     # Must sign-extend lower 32 bits -> 0xFFFF_FFFF_8000_0000
        r_type(0, 2, 1, 0, 5, 0x3B),        # ADDW: 0x80000000 + 0xFFFFFFFF = 0x7FFFFFFF (sext -> +)
        r_type(0x20, 2, 1, 0, 6, 0x3B),     # SUBW: 0x80000000 - 0xFFFFFFFF = 0x80000001 (sext -> -)
        r_type(0, 2, 1, 1, 7, 0x3B),        # SLLW by 31 -> 0
        r_type(0, 2, 1, 5, 8, 0x3B),        # SRLW by 31 -> 1
        r_type(0x20, 2, 1, 5, 9, 0x3B),     # SRAW by 31 -> -1 (0xFFFF_FFFF_FFFF_FFFF)
        # RV64M *W overflow & sign extension
        r_type(1, 2, 1, 4, 10, 0x3B),       # DIVW(0x80000000, -1) -> 0xFFFF_FFFF_8000_0000
        r_type(1, 2, 1, 6, 11, 0x3B),       # REMW(0x80000000, -1) -> 0
        r_type(1, 2, 1, 5, 12, 0x3B),       # DIVUW(0x80000000, 0xFFFFFFFF) -> 0
        # 64-bit Store/Load & LWU vs LW
        store(1, 3, 0, 3),                  # SD 0x0000_0001_8000_0000 -> [0x100]
        load(13, 3, 0, 3),                  # LD -> 0x0000_0001_8000_0000
        load(14, 3, 0, 2),                  # LW -> 0xFFFF_FFFF_8000_0000 (sign-extended)
        load(15, 3, 0, 6),                  # LWU -> 0x0000_0000_8000_0000 (zero-extended)
    ] + dump_all_registers(64)

    await run_and_verify(dut, p)


@cocotb.test()
async def test_unaligned_loads_and_stores(dut):
    """Verify byte-lane extraction and byte-enables across all sub-word offsets."""
    xlen = len(dut.pc_o)
    stride = xlen // 8
    p = init_zero_regs() + load_const(10, 0x200, xlen)
    p += load_const(1, 0x89ABCDEF01234567 if xlen == 64 else 0x89ABCDEF, xlen)

    # Store full bus word, then overwrite individual bytes & halfwords at sub-offsets
    p.append(store(1, 10, 0, 3 if xlen == 64 else 2))
    for off in range(stride):
        p.append(addi(2, 0, 0x80 + off))
        p.append(store(2, 10, stride + off, 0))       # SB at every byte offset
        p.append(load(11 + off, 10, off, 0))          # LB (signed)
        p.append(load(19 + off, 10, off, 4))          # LBU (unsigned)

    for off in range(0, stride, 2):
        p.append(load(27 + (off // 2), 10, off, 1))   # LH (signed)

    p += dump_all_registers(xlen)
    await run_and_verify(dut, p)


@cocotb.test()
async def test_signed_vs_unsigned_branches_and_jalr_hazards(dut):
    """Test signed vs unsigned branches with -1 vs +1, plus JALR LSB masking and rd==rs1."""
    xlen = len(dut.pc_o)
    p = init_zero_regs() + [
        addi(1, 0, -1),   # x1 = -1 (0xFFFF...FFFF)
        addi(2, 0, 1),    # x2 = +1
        addi(3, 0, 0),    # Result bitmap
        # BLT -1, 1 -> TAKEN (skips next)
        b_type(8, 2, 1, 4),
        addi(3, 3, 1),    # Should be skipped
        # BLTU -1, 1 -> NOT TAKEN (0xFFFF... > 1)
        b_type(8, 2, 1, 6),
        addi(3, 3, 2),    # Must execute -> x3 |= 2
        # BGEU -1, 1 -> TAKEN
        b_type(8, 2, 1, 7),
        addi(3, 3, 4),    # Should be skipped
    ]
    # JALR LSB clearing & rd == rs1 hazard:
    # Next 3 instructions are: addi(5,...), jalr(5,5,0), addi(3,3,8) [skipped]
    # Target instruction addi(3,3,16) will be at (len(p) + 3) * 4
    jalr_pc = (len(p) + 1) * 4
    target_pc = (len(p) + 3) * 4
    p += [
        addi(5, 0, target_pc | 1),  # Odd address to verify LSB is cleared
        jalr(5, 5, 0),              # Jumps to target_pc, sets x5 = jalr_pc + 4
        addi(3, 3, 8),              # Skipped
        addi(3, 3, 16),             # Target -> executes -> x3 = 18
    ] + dump_all_registers(xlen)

    _, model = await run_and_verify(dut, p)
    assert model.regs[3] == 18
    assert model.regs[5] == jalr_pc + 4


# ---------------------------------------------------------------------------
# Constrained-Random Instruction Fuzzer
# ---------------------------------------------------------------------------

def generate_random_program(xlen: int, num_ops: int = 300, seed: int = 42) -> list[int]:
    """Generate a straight-line random RV32IM/RV64IM ALU + Memory program with corner-case operands."""
    rng = random.Random(seed)
    interesting = [
        0, 1, -1, 2, -2,
        0x7FFFFFFF, -0x80000000,
        0x55555555, -0x55555556,
    ]
    if xlen == 64:
        interesting += [
            0x7FFFFFFFFFFFFFFF, -0x8000000000000000,
            0x00000000FFFFFFFF, 0xFFFFFFFF00000000,
        ]

    # Reserve x30 as safe data-memory base pointer (0x800..0x900)
    prog: list[int] = load_const(30, 0x800, xlen)
    for reg in range(1, 30):
        prog += load_const(reg, rng.choice(interesting), xlen)

    for _ in range(num_ops):
        rd = rng.randint(0, 29)  # Includes x0 to continuously stress x0 immutability
        rs1 = rng.randint(0, 29)
        rs2 = rng.randint(0, 29)
        choice = rng.choice(["alu_r", "alu_i", "muldiv", "mem", "branch", "word64"])

        if choice == "alu_r":
            funct3 = rng.randint(0, 7)
            funct7 = 0x20 if (funct3 in (0, 5) and rng.random() < 0.5) else 0x00
            prog.append(r_type(funct7, rs2, rs1, funct3, rd))

        elif choice == "alu_i":
            funct3 = rng.randint(0, 7)
            if funct3 in (1, 5):
                shamt = rng.randint(0, xlen - 1)
                imm = (0x400 if (funct3 == 5 and rng.random() < 0.5) else 0) | shamt
            else:
                imm = rng.randint(-2048, 2047)
            prog.append(i_type(imm, rs1, funct3, rd))

        elif choice == "muldiv":
            funct3 = rng.randint(0, 7)
            prog.append(r_type(0x01, rs2, rs1, funct3, rd))

        elif choice == "mem":
            # Safe offset within [0x800, 0x8F8] aligned to access size
            f3_choices = [0, 1, 2, 3, 4, 5, 6] if xlen == 64 else [0, 1, 2, 4, 5]
            funct3 = rng.choice(f3_choices)
            align = 1 << (funct3 & 0x3)
            offset = rng.randrange(0, 240, align)
            if rng.random() < 0.5:
                prog.append(load(rd, 30, offset, funct3))
            else:
                prog.append(store(rs2, 30, offset, funct3 & 0x3))

        elif choice == "branch":
            funct3 = rng.choice([0, 1, 4, 5, 6, 7])
            # Forward branch over 1 NOP (offset = +8 bytes) so control flow never loops infinitely
            prog.append(b_type(8, rs2, rs1, funct3))
            prog.append(addi(rd, rs1, rng.randint(-16, 15)))

        elif choice == "word64" and xlen == 64:
            if rng.random() < 0.5:
                funct3 = rng.choice([0, 1, 5])
                if funct3 == 0:
                    prog.append(addiw(rd, rs1, rng.randint(-2048, 2047)))
                else:
                    shamt = rng.randint(0, 31)
                    imm = (0x400 if (funct3 == 5 and rng.random() < 0.5) else 0) | shamt
                    prog.append(i_type(imm, rs1, funct3, rd, 0x1B))
            else:
                if rng.random() < 0.5:
                    funct3 = rng.choice([0, 1, 5])
                    funct7 = 0x20 if (funct3 in (0, 5) and rng.random() < 0.5) else 0x00
                    prog.append(r_type(funct7, rs2, rs1, funct3, rd, 0x3B))
                else:
                    funct3 = rng.choice([0, 4, 5, 6, 7])
                    prog.append(r_type(0x01, rs2, rs1, funct3, rd, 0x3B))

    prog += dump_all_registers(xlen)
    return prog


@cocotb.test()
async def test_randomized_instruction_fuzzing(dut):
    """Run 3 constrained-random seeds comparing full architectural state against the Golden Model."""
    xlen = len(dut.pc_o)
    for seed in (101, 202, 303):
        prog = generate_random_program(xlen=xlen, num_ops=250, seed=seed)
        await run_and_verify(dut, prog, cycles=len(prog) + 50)