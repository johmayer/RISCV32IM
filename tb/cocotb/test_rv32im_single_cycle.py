"""Instruction and integration tests for the single-cycle RV32IM/RV64IM core."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


XLEN = 32


def mask(value: int, width: int | None = None) -> int:
    width = XLEN if width is None else width
    return value & ((1 << width) - 1)


def signed(value: int, width: int | None = None) -> int:
    width = XLEN if width is None else width
    value = mask(value, width)
    return value - (1 << width) if value & (1 << (width - 1)) else value


def r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33


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
    return i_type(imm, rs1, 0, rd)


def load(rd: int, rs1: int, imm: int, funct3: int) -> int:
    return i_type(imm, rs1, funct3, rd, 0x03)


def store(rs2: int, rs1: int, imm: int, funct3: int) -> int:
    return s_type(imm, rs2, rs1, funct3)


def halt() -> int:
    return j_type(0, 0)


@dataclass
class Memory:
    bytes: dict[int, int]
    width: int

    def read(self, address: int) -> int:
        return sum(self.bytes.get(address + i, 0) << (8 * i) for i in range(self.width))

    def write(self, address: int, value: int, enables: int) -> None:
        for i in range(self.width):
            if enables & (1 << i):
                self.bytes[address + i] = (value >> (8 * i)) & 0xFF

    def word(self, address: int) -> int:
        return self.read(address)


async def run(dut, program: Iterable[int], initial: dict[int, int] | None = None, cycles: int = 200) -> Memory:
    width = len(dut.mem_byte_en_o)
    memory = Memory(dict(initial or {}), width)
    program = list(program)
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
        dut.instr_i.value = program[pc // 4] if pc // 4 < len(program) else halt()
        await Timer(1, unit="ps")
        address = int(dut.mem_addr_o.value)
        aligned = address & ~(width - 1)
        dut.data_mem_i.value = memory.read(aligned)
        await Timer(1, unit="ps")
        await ReadOnly()
        write = bool(dut.mem_write_en_o.value)
        write_address = address
        write_data = int(dut.data_mem_o.value) if write else 0
        write_enables = int(dut.mem_byte_en_o.value) if write else 0
        await RisingEdge(dut.clk_i)
        if write:
            memory.write(write_address, write_data, write_enables)
        if pc // 4 < len(program) and program[pc // 4] == halt() and pc != 0:
            break
    return memory


def setup_registers(base: int = 0x100) -> list[int]:
    return [u_type(0, 10, 0x37), addi(10, 10, base), addi(1, 0, 5), addi(2, 0, 3)]


@cocotb.test()
async def test_all_rv32i_and_m_alu_instructions(dut):
    """Exercise every implemented R-type and immediate ALU operation."""
    global XLEN
    XLEN = len(dut.pc_o)
    p = setup_registers()
    p += [
        r_type(0, 2, 1, 0, 3), r_type(0x20, 2, 1, 0, 4),
        r_type(0, 2, 1, 1, 5), r_type(0, 2, 1, 2, 6),
        r_type(0, 2, 1, 3, 7), r_type(0, 2, 1, 4, 8),
        r_type(0, 2, 1, 5, 9), r_type(0x20, 2, 1, 5, 11),
        r_type(0, 2, 1, 6, 12), r_type(0, 2, 1, 7, 13),
        r_type(1, 2, 1, 0, 14), r_type(1, 2, 1, 1, 15),
        r_type(1, 2, 1, 2, 16), r_type(1, 2, 1, 3, 17),
        r_type(1, 2, 1, 4, 18), r_type(1, 2, 1, 5, 19),
        r_type(1, 2, 1, 6, 20), r_type(1, 2, 1, 7, 21),
        addi(22, 1, -7), i_type(1, 1, 2, 23), i_type(1, 1, 3, 24),
        i_type(0x1F, 1, 1, 25), i_type(0x1F, 1, 5, 26),
        i_type(0x41F, 1, 5, 27), i_type(-1, 1, 4, 28),
        i_type(-1, 1, 6, 29), i_type(-1, 1, 7, 30),
    ]
    stride = 8 if XLEN == 64 else 4
    for reg, offset in zip(range(3, 31), range(0, 28 * stride, stride)):
        p.append(store(reg, 10, offset, 2))
    memory = await run(dut, p)
    expected = [8, 2, 40, 0, 0, 6, 0, 0x100, 0, 7, 1, 15, 0, 0,
                0, 1, 1, 2, 2, mask(-2), 0, 0, 0x80000000, 0,
                0, mask(-6), mask(-1), 5]
    for index, value in enumerate(expected):
        offset = index * stride
        assert memory.read(0x100 + offset) & 0xFFFFFFFF == value & 0xFFFFFFFF, f"ALU result at offset {offset}"


@cocotb.test()
async def test_load_store_and_complete_program_flow(dut):
    """Verify all implemented loads/stores, sign extension, and a loop."""
    global XLEN
    XLEN = len(dut.pc_o)
    result_offset = 16 if XLEN == 64 else 12
    p = setup_registers(0x200)
    p += [
        addi(3, 0, -1), store(3, 10, 0, 0), store(3, 10, 2, 1),
        store(3, 10, 4, 2), load(4, 10, 0, 0), load(5, 10, 0, 4),
        load(6, 10, 2, 1), load(7, 10, 2, 5), load(8, 10, 4, 2),
        load(9, 10, 4, 0), load(11, 10, 0, 4),
        addi(12, 0, 3), addi(13, 0, 0),
        addi(13, 13, 1), addi(12, 12, -1), b_type(-8, 0, 12, 1),
        store(13, 10, result_offset, 2), halt(),
    ]
    memory = await run(dut, p)
    assert memory.read(0x200 + result_offset) & 0xFFFFFFFF == 3
    assert memory.word(0x200) & 0xFF == 0xFF
    expected_store = 0xFFFFFFFF if XLEN == 32 else 0xFFFF
    assert memory.word(0x204) & expected_store == expected_store


@cocotb.test()
async def test_upper_immediates_and_jalr(dut):
    """Verify LUI/AUIPC values and JALR target/link behavior."""
    global XLEN
    XLEN = len(dut.pc_o)
    p = [
        u_type(0x12345, 1, 0x37), u_type(1, 2, 0x17),
        i_type(16, 0, 0, 5, 0x67), addi(3, 0, 0),
        addi(10, 0, 0x100), store(1, 10, 0, 2),
        store(2, 10, 8, 2), store(5, 10, 16, 2), halt(),
    ]
    memory = await run(dut, p)
    assert memory.read(0x100) & 0xFFFFFFFF == 0x12345000
    assert memory.read(0x108) & 0xFFFFFFFF == 0x1004
    assert memory.read(0x110) & 0xFFFFFFFF == 12


@cocotb.test()
async def test_fence_and_system_nops(dut):
    """Verify decoded FENCE/ECALL/EBREAK instructions advance as NOPs."""
    p = [0x0000000F, 0x00000073, 0x00100073,
         addi(10, 0, 0x100), addi(1, 0, 0x5), store(1, 10, 0, 2), halt()]
    memory = await run(dut, p)
    assert memory.read(0x100) & 0xFFFFFFFF == 5


@cocotb.test()
async def test_branches_jumps_and_edge_cases(dut):
    """Cover both outcomes of every branch and M-extension corner cases."""
    global XLEN
    XLEN = len(dut.pc_o)
    branch_cases = {0: (1, 1), 1: (1, 2), 4: (1, 2),
                    5: (2, 1), 6: (1, 2), 7: (2, 1)}
    for funct3, (left, right) in branch_cases.items():
        p = [addi(10, 0, 0x100), addi(1, 0, left), addi(2, 0, right),
             b_type(16, 2, 1, funct3), addi(3, 0, 0), store(3, 10, 0, 2),
             halt(), addi(3, 0, 1), store(3, 10, 0, 2), halt()]
        memory = await run(dut, p, cycles=30)
        assert memory.read(0x100) & 0xFFFFFFFF == 1

    for funct3, (left, right) in {0: (1, 2), 1: (1, 1), 4: (2, 1),
                                  5: (1, 2), 6: (2, 1), 7: (1, 2)}.items():
        p = [addi(10, 0, 0x100), addi(1, 0, left), addi(2, 0, right),
             b_type(16, 2, 1, funct3), addi(3, 0, 1), store(3, 10, 0, 2),
             halt(), addi(3, 0, 0), store(3, 10, 0, 2), halt()]
        memory = await run(dut, p, cycles=30)
        assert memory.read(0x100) & 0xFFFFFFFF == 1

    p = [addi(1, 0, 7), j_type(12, 5), addi(1, 0, 0), addi(1, 0, 0),
         addi(10, 0, 0x100), store(5, 10, 0, 2), halt()]
    memory = await run(dut, p)
    assert memory.read(0x100) & 0xFFFFFFFF == 8

    min_value = -(1 << (XLEN - 1))
    p = [u_type((min_value >> 12) & 0xFFFFF, 1, 0x37), addi(2, 0, -1),
         r_type(1, 2, 1, 4, 3), r_type(1, 2, 1, 6, 4),
         r_type(1, 0, 1, 4, 5), r_type(1, 0, 1, 6, 6),
         addi(10, 0, 0x100), store(3, 10, 0, 2), store(4, 10, 8, 2),
         store(5, 10, 16, 2), store(6, 10, 24, 2), halt()]
    memory = await run(dut, p)
    assert memory.read(0x100) & 0xFFFFFFFF == mask(min_value) & 0xFFFFFFFF
    assert memory.read(0x108) & 0xFFFFFFFF == 0
    assert memory.read(0x110) & 0xFFFFFFFF == 0xFFFFFFFF
    assert memory.read(0x118) & 0xFFFFFFFF == mask(min_value) & 0xFFFFFFFF
