//==============================================================================
// Module:      instruction_decode
// Description: Instruction Decode Unit for a RISC-V processor.
//
// Functionality:
//   - Decodes the instruction and generates the appropriate control signals.
//
//==============================================================================
import rv32im_pkg::*;

module instruction_decode (
    input   logic [6:0]     opcode_i,           // Opcode from the instruction
    input   logic [2:0]     funct3_i,           // funct3 field from the instruction
    input   logic [6:0]     funct7_i,           // funct7 field from the instruction

    output  alu_op_t        alu_op_o,           // ALU operation
    output  mem_op_t        mem_op_o,           // Memory operation
    output  branch_op_t     branch_op_o,        // Branch operation
    output  jump_op_t       jump_op_o,          // Jump operation
    output  imm_select_t    imm_select_o,       // Immediate selection
    output  logic           reg_write_en_o,     // Register write enable signal
    output  alu_a_sel_t     alu_a_sel_o,        // ALU operand A mux select
    output  alu_b_sel_t     alu_b_sel_o         // ALU operand B mux select
);

localparam OP_R_TYPE        = 7'b0110011; // RV32I + M
localparam OP_B_TYPE        = 7'b1100011; // Branch
localparam OP_S_TYPE        = 7'b0100011; // Store
localparam OP_I_JALR_TYPE   = 7'b1100111; // JALR
localparam OP_I_LOAD_TYPE   = 7'b0000011; // Load
localparam OP_I_ALU_TYPE    = 7'b0010011; // Immediate ALU
localparam OP_I_FENCE_TYPE  = 7'b0001111; // FENCE / FENCE.I
localparam OP_SYSTEM_TYPE   = 7'b1110011; // ECALL, EBREAK, CSR
localparam OP_U_LUI_TYPE    = 7'b0110111; // LUI
localparam OP_U_AUIPC_TYPE  = 7'b0010111; // AUIPC
localparam OP_J_TYPE        = 7'b1101111; // JAL


always_comb begin

    alu_op_o       = ALU_NONE;
    mem_op_o       = MEM_NONE;
    branch_op_o    = BR_NONE;
    jump_op_o      = JUMP_NONE;
    imm_select_o   = IMM_NONE;
    alu_a_sel_o    = ALU_A_RS1;
    alu_b_sel_o    = ALU_B_RS2;
    reg_write_en_o = 1'b0;

    unique case(opcode_i)
        OP_R_TYPE: begin
            // R-type Instructions:
            // - Write to a register, no branch/jump

            reg_write_en_o = 1'b1;
            unique case ({funct7_i, funct3_i})
                // RV32I Base
                {7'b0000000, 3'b000}: alu_op_o = ALU_ADD;
                {7'b0100000, 3'b000}: alu_op_o = ALU_SUB;
                {7'b0000000, 3'b001}: alu_op_o = ALU_SLL;
                {7'b0000000, 3'b010}: alu_op_o = ALU_SLT;
                {7'b0000000, 3'b011}: alu_op_o = ALU_SLTU;
                {7'b0000000, 3'b100}: alu_op_o = ALU_XOR;
                {7'b0000000, 3'b101}: alu_op_o = ALU_SRL;
                {7'b0100000, 3'b101}: alu_op_o = ALU_SRA;
                {7'b0000000, 3'b110}: alu_op_o = ALU_OR;
                {7'b0000000, 3'b111}: alu_op_o = ALU_AND;

                // RV32M Extension
                {7'b0000001, 3'b000}: alu_op_o = ALU_MUL;
                {7'b0000001, 3'b001}: alu_op_o = ALU_MULH;
                {7'b0000001, 3'b010}: alu_op_o = ALU_MULHSU;
                {7'b0000001, 3'b011}: alu_op_o = ALU_MULHU;
                {7'b0000001, 3'b100}: alu_op_o = ALU_DIV;
                {7'b0000001, 3'b101}: alu_op_o = ALU_DIVU;
                {7'b0000001, 3'b110}: alu_op_o = ALU_REM;
                {7'b0000001, 3'b111}: alu_op_o = ALU_REMU;

                default: begin
                    alu_op_o       = ALU_NONE;
                    reg_write_en_o = 1'b0; // Illegal instruction
                end
            endcase
        end

        OP_B_TYPE: begin
            // BRANCH Instructions:
            // - Compute target address (PC + imm_b) via ALU
            // - Do not write to a register, may affect PC if branch taken

            alu_op_o     = ALU_ADD;
            alu_a_sel_o  = ALU_A_PC;
            alu_b_sel_o  = ALU_B_IMM;
            imm_select_o = IMM_B_TYPE;
            unique case (funct3_i)
                3'b000: branch_op_o = BR_EQ;
                3'b001: branch_op_o = BR_NE;
                3'b100: branch_op_o = BR_LT;
                3'b101: branch_op_o = BR_GE;
                3'b110: branch_op_o = BR_LTU;
                3'b111: branch_op_o = BR_GEU;
                default: begin
                    alu_op_o     = ALU_NONE;
                    branch_op_o  = BR_NONE;
                end
            endcase
        end

        OP_S_TYPE: begin
            // STORE Instructions:
            // - Compute effective memory address (rs1 + imm_s) via ALU
            // - Do not write to a register, write to memory

            alu_op_o     = ALU_ADD;
            alu_a_sel_o  = ALU_A_RS1;
            alu_b_sel_o  = ALU_B_IMM;
            imm_select_o = IMM_S_TYPE;
            unique case (funct3_i)
                3'b000: mem_op_o = MEM_SB;
                3'b001: mem_op_o = MEM_SH;
                3'b010: mem_op_o = MEM_SW;
                default: begin
                    alu_op_o = ALU_NONE;
                    mem_op_o = MEM_NONE;
                end
            endcase
        end

        OP_I_JALR_TYPE: begin
            // JALR Instruction:
            // - Compute target address (rs1 + imm_i) via ALU
            // - Writes link address (PC + 4) to rd

            imm_select_o = IMM_I_TYPE;
            if (funct3_i == 3'b000) begin
                alu_op_o       = ALU_ADD;
                jump_op_o      = JUMP_JALR;
                alu_a_sel_o    = ALU_A_RS1;
                alu_b_sel_o    = ALU_B_IMM;
                reg_write_en_o = 1'b1;
            end
        end

        OP_I_LOAD_TYPE: begin
            // LOAD Instructions:
            // - Compute effective memory address (rs1 + imm_i) via ALU
            // - Writes loaded value to rd

            alu_op_o       = ALU_ADD;
            alu_a_sel_o    = ALU_A_RS1;
            alu_b_sel_o    = ALU_B_IMM;
            imm_select_o   = IMM_I_TYPE;
            reg_write_en_o = 1'b1;
            unique case (funct3_i)
                3'b000: mem_op_o = MEM_LB;
                3'b001: mem_op_o = MEM_LH;
                3'b010: mem_op_o = MEM_LW;
                3'b100: mem_op_o = MEM_LBU;
                3'b101: mem_op_o = MEM_LHU;
                default: begin
                    alu_op_o       = ALU_NONE;
                    mem_op_o       = MEM_NONE;
                    reg_write_en_o = 1'b0;
                end
            endcase
        end

        OP_I_ALU_TYPE: begin
            // Immediate ALU Instructions:
            // - Writes ALU result to rd

            alu_a_sel_o    = ALU_A_RS1;
            alu_b_sel_o    = ALU_B_IMM;
            imm_select_o   = IMM_I_TYPE;
            reg_write_en_o = 1'b1;
            unique case (funct3_i)
                3'b000: alu_op_o = ALU_ADD;
                3'b010: alu_op_o = ALU_SLT;
                3'b011: alu_op_o = ALU_SLTU;
                3'b100: alu_op_o = ALU_XOR;
                3'b110: alu_op_o = ALU_OR;
                3'b111: alu_op_o = ALU_AND;
                3'b001: begin
                    if (funct7_i == 7'b0000000) alu_op_o = ALU_SLL;
                    else reg_write_en_o = 1'b0;
                end
                3'b101: begin
                    if (funct7_i == 7'b0000000)      alu_op_o = ALU_SRL;
                    else if (funct7_i == 7'b0100000) alu_op_o = ALU_SRA;
                    else reg_write_en_o = 1'b0;
                end
                default: begin
                    alu_op_o       = ALU_NONE;
                    reg_write_en_o = 1'b0;
                end
            endcase
        end

        OP_I_FENCE_TYPE: begin
            // FENCE Instructions:
            // - Handled as NOP in basic single-cycle core
        end

        OP_SYSTEM_TYPE: begin
            // SYSTEM Instructions:
            // - Handled by control/CSR unit if implemented
        end

        OP_U_LUI_TYPE: begin
            // LUI Instruction:
            // - Passes upper immediate through ALU to rd

            alu_a_sel_o    = ALU_A_ZERO;
            alu_b_sel_o    = ALU_B_IMM;
            imm_select_o   = IMM_U_TYPE;
            alu_op_o       = ALU_LUI;
            reg_write_en_o = 1'b1;
        end

        OP_U_AUIPC_TYPE: begin
            // AUIPC Instruction:
            // - Computes PC + upper immediate via ALU and writes to rd

            alu_a_sel_o    = ALU_A_PC;
            alu_b_sel_o    = ALU_B_IMM;
            imm_select_o   = IMM_U_TYPE;
            alu_op_o       = ALU_AUIPC;
            reg_write_en_o = 1'b1;
        end

        OP_J_TYPE: begin
            // JAL Instruction:
            // - Computes jump target (PC + imm_j) via ALU
            // - Writes link address (PC + 4) to rd

            alu_op_o       = ALU_ADD;
            alu_a_sel_o    = ALU_A_PC;
            alu_b_sel_o    = ALU_B_IMM;
            imm_select_o   = IMM_J_TYPE;
            jump_op_o      = JUMP_JAL;
            reg_write_en_o = 1'b1;
        end

        default: begin
            // default already set
        end
    endcase
end

endmodule