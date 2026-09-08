package mipsforfun_pkg;
  typedef enum logic [3:0] {
    ALU_ADD  = 4'd0,
    ALU_SUB  = 4'd1,
    ALU_AND  = 4'd2,
    ALU_OR   = 4'd3,
    ALU_XOR  = 4'd4,
    ALU_SLT  = 4'd5,
    ALU_SLTU = 4'd6,
    ALU_SLL  = 4'd7,
    ALU_SRL  = 4'd8,
    ALU_SRA  = 4'd9,
    ALU_LUI  = 4'd10,
    ALU_PASS = 4'd11
  } alu_op_t;

  typedef enum logic [1:0] {
    DST_RT = 2'd0,
    DST_RD = 2'd1,
    DST_RA = 2'd2
  } dst_sel_t;

  typedef enum logic [1:0] {
    BR_NONE = 2'd0,
    BR_BEQ  = 2'd1,
    BR_BNE  = 2'd2
  } branch_t;
endpackage
