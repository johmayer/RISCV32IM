//==============================================================================
// Module:      alu
// Description: Arithmetic Logic Unit for a RISC-V processor (RV32IM / RV64IM).
//
// Functionality:
//   - Performs base integer arithmetic, logical, shift, and comparison ops.
//   - Includes single shared, operand-isolated multiplier and divider units
//     for M-extension instructions with full RISC-V edge-case handling.
//
//==============================================================================
import rv32im_pkg::*;

module alu #(
    parameter int XLEN = 32
) (
    input  logic [XLEN-1:0] alu_a_i,    // First operand
    input  logic [XLEN-1:0] alu_b_i,    // Second operand
    input  alu_op_t         alu_op_i,   // ALU operation type
    output logic [XLEN-1:0] result_o    // Result of the ALU operation
);

localparam int SHAMT_WIDTH = $clog2(XLEN);
localparam logic [XLEN-1:0] MIN_SIGNED = {1'b1, {(XLEN-1){1'b0}}};  // -2^(XLEN-1)
localparam logic [XLEN-1:0] ALL_ONES   = {XLEN{1'b1}};              // -1
localparam logic [31:0] MIN_SIGNED_W = 32'h8000_0000;
localparam logic [31:0] ALL_ONES_W = 32'hffff_ffff;


// Operand-Isolated Shared Multiplier (MUL, MULH, MULHSU, MULHU)
logic                     is_mul_op;
logic signed [XLEN:0]     mul_op_a, mul_op_b;
logic signed [2*XLEN+1:0] mul_prod;

always_comb begin
    is_mul_op = (alu_op_i == ALU_MUL)    || (alu_op_i == ALU_MULW) ||
                (alu_op_i == ALU_MULH) ||
                (alu_op_i == ALU_MULHSU) || (alu_op_i == ALU_MULHU);

    if (is_mul_op) begin
        mul_op_a = (alu_op_i == ALU_MULHU)
                   ? $signed({1'b0, alu_a_i})
                   : $signed({alu_a_i[XLEN-1], alu_a_i});

        mul_op_b = (alu_op_i == ALU_MULHU || alu_op_i == ALU_MULHSU)
                   ? $signed({1'b0, alu_b_i})
                   : $signed({alu_b_i[XLEN-1], alu_b_i});
    end else begin
        mul_op_a = '0;
        mul_op_b = '0;
    end

    mul_prod = mul_op_a * mul_op_b;
end


// Operand-Isolated Shared Divider (DIV, DIVU, REM, REMU)
logic                 is_div_op, is_signed_div;
logic                 is_div_zero, is_div_overflow;
logic signed [XLEN:0] div_op_a, div_op_b;
logic signed [XLEN:0] raw_quot, raw_rem;
logic        [XLEN-1:0] div_result, rem_result;
logic signed [32:0] raw_quot_w, raw_rem_w;
logic [31:0] div_result_w, rem_result_w;
logic [31:0] word_result;

always_comb begin
    is_div_op     = (alu_op_i == ALU_DIV)  || (alu_op_i == ALU_DIVU) ||
                    (alu_op_i == ALU_REM)  || (alu_op_i == ALU_REMU);
    is_signed_div = (alu_op_i == ALU_DIV)  || (alu_op_i == ALU_REM);

    is_div_zero     = (alu_b_i == '0);
    is_div_overflow = is_signed_div && (alu_a_i == MIN_SIGNED) && (alu_b_i == ALL_ONES);

    if (is_div_op && !is_div_zero && !is_div_overflow) begin
        div_op_a = is_signed_div ? $signed({alu_a_i[XLEN-1], alu_a_i}) : $signed({1'b0, alu_a_i});
        div_op_b = is_signed_div ? $signed({alu_b_i[XLEN-1], alu_b_i}) : $signed({1'b0, alu_b_i});
    end else begin
        div_op_a = '0;
        div_op_b = (XLEN+1)'(1); // Prevent 0/0 evaluation when idle
    end

    raw_quot = div_op_a / div_op_b;
    raw_rem  = div_op_a % div_op_b;

    if (is_div_zero) begin
        div_result = ALL_ONES;
        rem_result = alu_a_i;
    end else if (is_div_overflow) begin
        div_result = MIN_SIGNED;
        rem_result = '0;
    end else begin
        div_result = raw_quot[XLEN-1:0];
        rem_result = raw_rem[XLEN-1:0];
    end
end

always_comb begin
    raw_quot_w = 0;
    raw_rem_w = 0;
    div_result_w = '0;
    rem_result_w = '0;
    if (alu_b_i[31:0] == 0) begin
        div_result_w = ALL_ONES_W;
        rem_result_w = alu_a_i[31:0];
    end else if ((alu_a_i[31:0] == MIN_SIGNED_W) && (alu_b_i[31:0] == ALL_ONES_W)) begin
        div_result_w = MIN_SIGNED_W;
        rem_result_w = '0;
    end else begin
        raw_quot_w = $signed({alu_a_i[31], alu_a_i[31:0]}) /
                     $signed({alu_b_i[31], alu_b_i[31:0]});
        raw_rem_w = $signed({alu_a_i[31], alu_a_i[31:0]}) %
                    $signed({alu_b_i[31], alu_b_i[31:0]});
        div_result_w = raw_quot_w[31:0];
        rem_result_w = raw_rem_w[31:0];
    end
end

always_comb begin
    unique case (alu_op_i)
        ALU_ADDW:  word_result = alu_a_i[31:0] + alu_b_i[31:0];
        ALU_SUBW:  word_result = alu_a_i[31:0] - alu_b_i[31:0];
        ALU_SLLW:  word_result = alu_a_i[31:0] << alu_b_i[4:0];
        ALU_SRLW:  word_result = alu_a_i[31:0] >> alu_b_i[4:0];
        ALU_SRAW:  word_result = $signed(alu_a_i[31:0]) >>> alu_b_i[4:0];
        ALU_MULW:  word_result = mul_prod[31:0];
        ALU_DIVW:  word_result = div_result_w;
        ALU_DIVUW: word_result = (alu_b_i[31:0] == 0) ? ALL_ONES_W : alu_a_i[31:0] / alu_b_i[31:0];
        ALU_REMW:  word_result = rem_result_w;
        ALU_REMUW: word_result = (alu_b_i[31:0] == 0) ? alu_a_i[31:0] : alu_a_i[31:0] % alu_b_i[31:0];
        default:   word_result = '0;
    endcase
end


// Main ALU Result Multiplexer
always_comb begin
    unique case (alu_op_i)
        // Base Integer Operations
        ALU_ADD,
        ALU_AUIPC:  result_o = alu_a_i + alu_b_i;
        ALU_SUB:    result_o = alu_a_i - alu_b_i;
        ALU_LUI:    result_o = alu_b_i;
        ALU_SLL:    result_o = alu_a_i << alu_b_i[SHAMT_WIDTH-1:0];
        ALU_SLT:    result_o = ($signed(alu_a_i) < $signed(alu_b_i)) ? XLEN'(1) : '0;
        ALU_SLTU:   result_o = (alu_a_i < alu_b_i) ? XLEN'(1) : '0;
        ALU_XOR:    result_o = alu_a_i ^ alu_b_i;
        ALU_SRL:    result_o = alu_a_i >> alu_b_i[SHAMT_WIDTH-1:0];
        ALU_SRA:    result_o = $signed(alu_a_i) >>> alu_b_i[SHAMT_WIDTH-1:0];
        ALU_OR:     result_o = alu_a_i | alu_b_i;
        ALU_AND:    result_o = alu_a_i & alu_b_i;

        ALU_ADDW,
        ALU_SUBW,
        ALU_SLLW,
        ALU_SRLW,
        ALU_SRAW,
        ALU_MULW,
        ALU_DIVW,
        ALU_DIVUW,
        ALU_REMW,
        ALU_REMUW: result_o = {{(XLEN-32){word_result[31]}}, word_result};

        // M-Extension Multiply
        ALU_MUL:    result_o = mul_prod[XLEN-1:0];
        ALU_MULH,
        ALU_MULHSU,
        ALU_MULHU:  result_o = mul_prod[2*XLEN-1:XLEN];

        // M-Extension Divide & Remainder
        ALU_DIV,
        ALU_DIVU:   result_o = div_result;
        ALU_REM,
        ALU_REMU:   result_o = rem_result;

        default:    result_o = '0;
    endcase
end

endmodule