//==============================================================================
// Module:      register_file
// Description: Register File for a RISC-V processor.
//
// Functionality:
//   - Stores the registers for the processor.
//
//==============================================================================


module register_file #(
    parameter XLEN = 32,
    parameter ADDR_WIDTH = 5
) (
    input   logic                   clk_i,          // Clock signal for register file
    input   logic [ADDR_WIDTH-1:0]  write_addr_i,   // Write address input for register file
    input   logic [ADDR_WIDTH-1:0]  read_addr_1_i,  // Read address 1 input for register file
    input   logic [ADDR_WIDTH-1:0]  read_addr_2_i,  // Read address 2 input for register file
    input   logic [XLEN-1:0]        data_i,         // Data input to register file
    input   logic                   write_en_i,     // Write enable signal for register file
    output  logic [XLEN-1:0]        data_1_o,       // Data output 1 from register file
    output  logic [XLEN-1:0]        data_2_o        // Data output 2 from register file
);

logic [XLEN-1:0] register [0:(1<<ADDR_WIDTH)-1]; // 32 x 32-bit register file

always_comb begin
    data_1_o = (read_addr_1_i == '0) ? '0 : register[read_addr_1_i]; // Read data from the specified register address
    data_2_o = (read_addr_2_i == '0) ? '0 : register[read_addr_2_i]; // Read data from the specified register address
end


always_ff @(posedge clk_i) begin
    if (write_en_i && (write_addr_i != '0)) begin
        register[write_addr_i] <= data_i; // Write data to the specified register address
    end
end

endmodule