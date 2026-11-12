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
typedef enum logic [5:0] {
    // RV32I
    ALU_ADD    = 6'b000000,
    ALU_SUB    = 6'b000001,
    ALU_AND    = 6'b000010,
    ALU_OR     = 6'b000011,
    ALU_XOR    = 6'b000100,
    ALU_SLL    = 6'b000101,
    ALU_SRL    = 6'b000110,
    ALU_SRA    = 6'b000111,
    ALU_SLT    = 6'b001000,
    ALU_SLTU   = 6'b001001,
    ALU_LUI    = 6'b001010,
    ALU_AUIPC  = 6'b001011,

    // RV32M
    ALU_MUL    = 6'b001100,
    ALU_MULH   = 6'b001101,
    ALU_MULHSU = 6'b001110,
    ALU_MULHU  = 6'b001111,
    ALU_DIV    = 6'b010000,
    ALU_DIVU   = 6'b010001,
    ALU_REM    = 6'b010010,
    ALU_REMU   = 6'b010011,

    // RV64I/RV64M word operations
    ALU_ADDW   = 6'b10100,
    ALU_SUBW   = 6'b10101,
    ALU_SLLW   = 6'b10110,
    ALU_SRLW   = 6'b10111,
    ALU_SRAW   = 6'b11000,
    ALU_MULW   = 6'b11001,
    ALU_DIVW   = 6'b11010,
    ALU_DIVUW  = 6'b11011,
    ALU_REMW   = 6'b11100,
    ALU_REMUW  = 6'b11101,

    ALU_NONE   = 6'b111111 // No operation (used for default cases)

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