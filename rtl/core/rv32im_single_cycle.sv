//==============================================================================
// Module:      riscv32im_single_cycle
// Description: Single-cycle RISC-V processor.
//
// Functionality:
//   - Implements a single-cycle RISC-V processor supporting the RV32IM instruction set.
//
// Reset:
//   - Active-low synchronous reset.
//   - Reset takes effect on the next rising clock edge.
//
// Parameters:
//   None.
//
// Inputs:
//   clk_i   - CPU clock.
//   rst_n_i - Active-low synchronous reset.
//
// Outputs:
//   None.
//
//==============================================================================
import rv32im_pkg::*;

module riscv32im_single_cycle #(
    parameter XLEN = rv32im_pkg::XLEN,
    parameter REGISTER_ADDR_WIDTH = rv32im_pkg::REGISTER_ADDR_WIDTH
) (
    input   logic                   clk_i,          // CPU clock
    input   logic                   rst_n_i,        // Active-low synchronous reset
    input   logic [XLEN-1:0]        instr_i,        // Instruction input from instruction memory
    input   logic [XLEN-1:0]        data_mem_i,     // Data input from data memory

    output  logic [XLEN-1:0]        pc_o,           // Program counter output
    output  logic [XLEN-1:0]        data_mem_o,     // Data output to data memory
    output  logic [XLEN-1:0]        mem_addr_o,     // Address output to data memory
    output  logic                   mem_write_en_o, // Write enable output to data memory
    output  logic [(XLEN/8)-1:0]    mem_byte_en_o   // 4-bit byte strobe (e.g., 4'b0001 for SB at offset 0)
);

// general purpose signals
logic [XLEN-1:0] alu_output;    // Output from the ALU
logic pc_mux_sel;               // Control signal to select between normal increment and branch/jump address

// register file signals
logic [XLEN-1:0] reg_data_1;        // Data output 1 from the register file
logic [XLEN-1:0] reg_data_2;        // Data output 2 from the register file
logic [XLEN-1:0] reg_write_data;    // Data to write to the register file
logic reg_write_en;                 // Write enable signal for the register file

// immediate extension signals
logic [XLEN-1:0] imm_extended;      // Extended immediate value

// instruction decode signals
alu_op_t alu_op;                    // ALU operation type
mem_op_t mem_op;                    // Memory operation type
branch_op_t branch_op;              // Branch operation type
jump_op_t jump_op;                  // Jump operation type
imm_select_t imm_select;            // Immediate selection type

// ALU operand signals
alu_a_sel_t      alu_a_sel;
alu_b_sel_t      alu_b_sel;
logic [XLEN-1:0] alu_operand_a;
logic [XLEN-1:0] alu_operand_b;

/ load / store signals
logic [XLEN-1:0] load_data;         // Data loaded from memory


// Instantiate the program counter
pc pc_inst (
    .clk_i(clk_i),
    .rst_n_i(rst_n_i),
    .pc_mux_sel_i(pc_mux_sel),
    .alu_output_i(alu_output),
    .pc_o(pc_o)
);


// Instantiate the register file
register_file #(
    .XLEN(XLEN),
    .ADDR_WIDTH(REGISTER_ADDR_WIDTH)
) reg_file_inst (
    .clk_i(clk_i),
    .write_addr_i(instr_i[11:7]),               // rd of instruction
    .read_addr_1_i(instr_i[19:15]),             // rs1 of instruction
    .read_addr_2_i(instr_i[24:20]),             // rs2 of instruction
    .data_i(reg_write_data),
    .write_en_i(reg_write_en),
    .data_1_o(reg_data_1),
    .data_2_o(reg_data_2)
);


// Immediate extension unit
immediate_extend #(
    .XLEN(XLEN)
) imm_ext_inst (
    .instr_i(instr_i),
    .imm_select_i(imm_select),
    .imm_o(imm_extended)
);

// Instruction decode unit
instruction_decode instr_dec_inst (
    .opcode_i(instr_i[6:0]),
    .funct3_i(instr_i[14:12]),
    .funct7_i(instr_i[31:25]),
    .alu_op_o(alu_op),
    .mem_op_o(mem_op),
    .branch_op_o(branch_op),
    .jump_op_o(jump_op),
    .reg_write_en_o(reg_write_en),
    .imm_select_o(imm_select),
    .alu_a_sel_o(alu_a_sel),
    .alu_b_sel_o(alu_b_sel)
);

// Operand A Mux
always_comb begin
    unique case (alu_a_sel)
        ALU_A_RS1:  alu_operand_a = reg_data_1;
        ALU_A_PC:   alu_operand_a = pc_o;
        ALU_A_ZERO: alu_operand_a = '0;
        default:    alu_operand_a = reg_data_1;
    endcase
end

// Operand B Mux
assign alu_operand_b = (alu_b_sel == ALU_B_IMM) ? imm_extended : reg_data_2;

// ALU instantiation
alu #(
    .XLEN(XLEN)
) alu_inst (
    .alu_a_i (alu_operand_a),
    .alu_b_i (alu_operand_b),
    .alu_op_i(alu_op),
    .result_o(alu_output)
);

// Branch Unit instantiation
branch_unit #(
    .XLEN(XLEN)
) branch_unit_inst (
    .rs1_data_i  (reg_data_1),
    .rs2_data_i  (reg_data_2),
    .branch_op_i (branch_op),
    .jump_op_i   (jump_op),
    .pc_mux_sel_o(pc_mux_sel)
);

// Load/Store Unit instantiation
load_store_unit #(
    .XLEN(XLEN)
) lsu_inst (
    .mem_op_i      (mem_op),
    .addr_i        (alu_output),
    .rs2_data_i    (reg_data_2),
    .mem_rdata_i   (data_mem_i),
    .mem_addr_o    (mem_addr_o),
    .mem_wdata_o   (data_mem_o),
    .mem_write_en_o(mem_write_en_o),
    .mem_byte_en_o (mem_byte_en_o),
    .load_data_o   (load_data)
);

// Write-back Mux
always_comb begin
    if (jump_op != JUMP_NONE) begin
        reg_write_data = pc_o + XLEN'(4); // Return address (rd = PC + 4) for JAL/JALR
    end else if (mem_op == MEM_LB  || mem_op == MEM_LH  || mem_op == MEM_LW  ||
                 mem_op == MEM_LBU || mem_op == MEM_LHU || mem_op == MEM_LWU ||
                 mem_op == MEM_LD) begin
        reg_write_data = load_data;       // Data loaded from memory
    end else begin
        reg_write_data = alu_output;      // ALU result (R-type, I-ALU, LUI, AUIPC)
    end
end

endmodule