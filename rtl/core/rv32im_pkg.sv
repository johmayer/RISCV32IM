//==============================================================================
// Package:     rv32im_pkg
// Description: Package for a RISC-V processor.
//
// Functionality:
//   - Introduces parameters and definitions for the RISC-V processor, including register width and address width.
//   - Defines data types and constants used across the processor modules.
//==============================================================================

package rv32im_pkg;

// Define the width of the registers and addresses
parameter int XLEN = 32;                    // Register width (32 bits for RV32)
parameter int REGISTER_ADDR_WIDTH = 5;      // Address width (5 bits for 32 registers)


// immediate selection type
typedef enum logic [2:0] {
    IMM_I_TYPE = 3'b000,    // I-type immediate
    IMM_S_TYPE = 3'b001,    // S-type immediate
    IMM_B_TYPE = 3'b010,    // B-type immediate
    IMM_U_TYPE = 3'b011,    // U-type immediate
    IMM_J_TYPE = 3'b100,    // J-type immediate
    IMM_NONE   = 3'b111     // No immediate (used for default cases)
} imm_select_t;


// ALU operation type
typedef enum logic [4:0] {
    // RV32I
    ALU_ADD    = 5'b00000,
    ALU_SUB    = 5'b00001,
    ALU_AND    = 5'b00010,
    ALU_OR     = 5'b00011,
    ALU_XOR    = 5'b00100,
    ALU_SLL    = 5'b00101,
    ALU_SRL    = 5'b00110,
    ALU_SRA    = 5'b00111,
    ALU_SLT    = 5'b01000,
    ALU_SLTU   = 5'b01001,
    ALU_LUI    = 5'b01010,
    ALU_AUIPC  = 5'b01011,

    // RV32M
    ALU_MUL    = 5'b01100,
    ALU_MULH   = 5'b01101,
    ALU_MULHSU = 5'b01110,
    ALU_MULHU  = 5'b01111,
    ALU_DIV    = 5'b10000,
    ALU_DIVU   = 5'b10001,
    ALU_REM    = 5'b10010,
    ALU_REMU   = 5'b10011,

    ALU_NONE   = 5'b11111 // No operation (used for default cases)

} alu_op_t;


// Memory operation type
typedef enum logic [3:0] {
    MEM_NONE = 4'b0000,
    
    // Loads
    MEM_LB   = 4'b0001,
    MEM_LH   = 4'b0010,
    MEM_LW   = 4'b0011,
    MEM_LBU  = 4'b0100,
    MEM_LHU  = 4'b0101,
    MEM_LWU  = 4'b0110, // RV64
    MEM_LD   = 4'b0111, // RV64

    // Stores
    MEM_SB   = 4'b1000,
    MEM_SH   = 4'b1001,
    MEM_SW   = 4'b1010,
    MEM_SD   = 4'b1011  // RV64
    
} mem_op_t;


// Branch operation type
typedef enum logic [2:0] {
    BR_NONE = 3'b000, // No branch

    BR_EQ   = 3'b001, // BEQ
    BR_NE   = 3'b010, // BNE
    BR_LT   = 3'b011, // BLT (signed)
    BR_GE   = 3'b100, // BGE (signed)
    BR_LTU  = 3'b101, // BLTU (unsigned)
    BR_GEU  = 3'b110  // BGEU (unsigned)

} branch_op_t;


// Jump operation type
typedef enum logic [1:0] {
    JUMP_NONE = 2'b00,
    JUMP_JAL  = 2'b01,
    JUMP_JALR = 2'b10
} jump_op_t;


// ALU operand selection types
typedef enum logic [1:0] {
    ALU_A_RS1  = 2'b00, // Register rs1
    ALU_A_PC   = 2'b01, // Program counter (AUIPC, JAL, Branch)
    ALU_A_ZERO = 2'b10  // Constant 0 (LUI)
} alu_a_sel_t;

typedef enum logic {
    ALU_B_RS2  = 1'b0,  // Register rs2 (R-type)
    ALU_B_IMM  = 1'b1   // Extended immediate (I, S, B, U, J)
} alu_b_sel_t;


endpackage