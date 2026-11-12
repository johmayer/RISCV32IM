//==============================================================================
// Module:      pc
// Description: Program Counter (PC) for a RISC-V processor.
//
// Functionality:
//   - Stores the address of the current instruction.
//   - Increments the PC by 4 bytes every clock cycle.
//   - Resets the PC to zero when reset is asserted.
//   - Selects between normal increment and branch/jump address based on control signal.
//==============================================================================


module pc #(
    parameter XLEN = 32
) (
    input   logic               clk_i,          // CPU clock
    input   logic               rst_n_i,        // Active-low synchronous reset
    input   logic               pc_mux_sel_i,   // Selects between normal increment and branch/jump address
    input   logic [XLEN-1:0]    alu_output_i,   // ALU output for branch/jump instructions
    output  logic [XLEN-1:0]    pc_o            // Current program counter address
);

always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
        pc_o <= '0;
    end else begin
        // If pc_mux_sel_i is high, use the ALU output (branch/jump address), otherwise increment by 4 (32-bit instruction width)
        pc_o <= pc_mux_sel_i ? {alu_output_i[XLEN-1:1], 1'b0} : (pc_o + XLEN'(4));
    end
end

endmodule