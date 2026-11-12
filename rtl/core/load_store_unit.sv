//==============================================================================
// Module:      load_store_unit
// Description: Load/Store Unit for a RISC-V processor.
//
// Functionality:
//   - Aligns store data/byte-strobes and extracts/extends load data
//     for RV32 and RV64 data memory interfaces.
//
//==============================================================================
import rv32im_pkg::*;

module load_store_unit #(
    parameter int XLEN = 32
) (
    input  mem_op_t             mem_op_i,       // Memory operation from decoder
    input  logic [XLEN-1:0]     addr_i,         // Effective byte address (from ALU)
    input  logic [XLEN-1:0]     rs2_data_i,     // Store data from register file
    input  logic [XLEN-1:0]     mem_rdata_i,    // Raw data word read from data memory

    output logic [XLEN-1:0]     mem_addr_o,     // Aligned word/doubleword address to memory
    output logic [XLEN-1:0]     mem_wdata_o,    // Lane-aligned write data to memory
    output logic                mem_write_en_o, // High on store instructions
    output logic [(XLEN/8)-1:0] mem_byte_en_o,  // Byte-lane write strobes
    output logic [XLEN-1:0]     load_data_o     // Sign/zero-extended load data to regfile
);

localparam int NUM_BYTES    = XLEN / 8;
localparam int OFFSET_WIDTH = $clog2(NUM_BYTES);

logic [OFFSET_WIDTH-1:0] byte_offset;
logic [XLEN-1:0]         shifted_rdata;

assign byte_offset = addr_i[OFFSET_WIDTH-1:0];

// Pass full byte address
assign mem_addr_o  = addr_i;

// Shift read data right so target byte/halfword/word is aligned to bit 0
assign shifted_rdata = mem_rdata_i >> (byte_offset * 8);


// Store Alignment & Byte Strobe Generation
always_comb begin
    mem_write_en_o = 1'b0;
    mem_byte_en_o  = '0;
    mem_wdata_o    = rs2_data_i << (byte_offset * 8);

    unique case (mem_op_i)
        MEM_SB: begin
            mem_write_en_o = 1'b1;
            mem_byte_en_o  = NUM_BYTES'(1'b1) << byte_offset;
        end
        MEM_SH: begin
            mem_write_en_o = 1'b1;
            mem_byte_en_o  = NUM_BYTES'(2'b11) << byte_offset;
        end
        MEM_SW: begin
            mem_write_en_o = 1'b1;
            mem_byte_en_o  = NUM_BYTES'(4'b1111) << byte_offset;
        end
        MEM_SD: begin
            mem_write_en_o = 1'b1;
            mem_byte_en_o  = {NUM_BYTES{1'b1}};
        end
        default: begin
            mem_write_en_o = 1'b0;
            mem_byte_en_o  = '0;
        end
    endcase
end


// Load Extraction & Sign/Zero Extension
always_comb begin
    unique case (mem_op_i)
        MEM_LB:  load_data_o = {{(XLEN-8){shifted_rdata[7]}},   shifted_rdata[7:0]};
        MEM_LBU: load_data_o = {{(XLEN-8){1'b0}},               shifted_rdata[7:0]};
        MEM_LH:  load_data_o = {{(XLEN-16){shifted_rdata[15]}}, shifted_rdata[15:0]};
        MEM_LHU: load_data_o = {{(XLEN-16){1'b0}},              shifted_rdata[15:0]};
        MEM_LW:  load_data_o = {{(XLEN-32){shifted_rdata[31]}}, shifted_rdata[31:0]};
        MEM_LWU: load_data_o = {{(XLEN-32){1'b0}},              shifted_rdata[31:0]};
        MEM_LD:  load_data_o = shifted_rdata;
        default: load_data_o = '0;
    endcase
end

endmodule