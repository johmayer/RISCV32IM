//==============================================================================
// Module:      branch_unit
// Description: Branch Unit for a RISC-V processor.
//
// Functionality:
//   - Evaluates branch conditions and resolves control-flow PC muxing.
//
//==============================================================================
import rv32im_pkg::*;

module branch_unit #(
    parameter int XLEN = 32
) (
    input  logic [XLEN-1:0] rs1_data_i,     // Register source 1 data
    input  logic [XLEN-1:0] rs2_data_i,     // Register source 2 data
    input  branch_op_t      branch_op_i,    // Branch operation type
    input  jump_op_t        jump_op_i,      // Jump operation type
    output logic            pc_mux_sel_o    // High when branch is taken or jump occurs
);

logic branch_taken;

always_comb begin
    unique case (branch_op_i)
        BR_EQ:   branch_taken = (rs1_data_i == rs2_data_i);
        BR_NE:   branch_taken = (rs1_data_i != rs2_data_i);
        BR_LT:   branch_taken = ($signed(rs1_data_i) <  $signed(rs2_data_i));
        BR_GE:   branch_taken = ($signed(rs1_data_i) >= $signed(rs2_data_i));
        BR_LTU:  branch_taken = (rs1_data_i <  rs2_data_i);
        BR_GEU:  branch_taken = (rs1_data_i >= rs2_data_i);
        default: branch_taken = 1'b0; // BR_NONE
    endcase

    // Select target address on any jump (JAL/JALR) or a taken conditional branch
    pc_mux_sel_o = (jump_op_i != JUMP_NONE) || branch_taken;
end

endmodule