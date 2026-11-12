//==============================================================================
// Module:      immediate_extend
// Description: Immediate Extend Unit for a RISC-V processor.
//
// Functionality:
//   - Extends the immediate value from the instruction to the full XLEN.
//
//==============================================================================
import rv32im_pkg::*;

module immediate_extend #(
    parameter XLEN = 32
) (
    input   logic [XLEN-1:0]    instr_i,        // Instruction input
    input   imm_select_t        imm_select_i,   // Immediate selection input
    output  logic [XLEN-1:0]    imm_o           // Extended immediate output
);

always_comb begin
    case (imm_select_i)
        // I-type immediate
        IMM_I_TYPE: imm_o = $signed(instr_i[31:20]);
        
        // S-type immediate
        IMM_S_TYPE: imm_o = $signed({instr_i[31:25], instr_i[11:7]});

        // B-type immediate
        IMM_B_TYPE: imm_o = $signed({instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0});

        // U-type immediate
        IMM_U_TYPE: imm_o = $signed({instr_i[31:12], 12'b0});

        // J-type immediate
        IMM_J_TYPE: imm_o = $signed({instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0});

        // No immediate
        IMM_NONE:   imm_o = '0;
        default:    imm_o = '0;
    endcase
end


endmodule