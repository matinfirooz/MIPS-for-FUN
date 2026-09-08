module mipsforfun_control (
  input  logic [31:0] instr,
  output logic        valid,
  output logic        uses_rs,
  output logic        uses_rt,
  output logic        reg_write,
  output logic        mem_read,
  output logic        mem_write,
  output logic        mem_to_reg,
  output logic        alu_src_imm,
  output logic        imm_zero_ext,
  output logic        jump,
  output logic        jump_reg,
  output logic        link,
  output mipsforfun_pkg::branch_t branch,
  output mipsforfun_pkg::dst_sel_t dst_sel,
  output mipsforfun_pkg::alu_op_t alu_op
);
  import mipsforfun_pkg::*;

  logic [5:0] op, funct;
  assign op    = instr[31:26];
  assign funct = instr[5:0];

  always_comb begin
    valid        = 1'b1;
    uses_rs      = 1'b0;
    uses_rt      = 1'b0;
    reg_write    = 1'b0;
    mem_read     = 1'b0;
    mem_write    = 1'b0;
    mem_to_reg   = 1'b0;
    alu_src_imm  = 1'b0;
    imm_zero_ext = 1'b0;
    jump         = 1'b0;
    jump_reg     = 1'b0;
    link         = 1'b0;
    branch       = BR_NONE;
    dst_sel      = DST_RT;
    alu_op       = ALU_ADD;

    unique case (op)
      6'h00: begin // R-type
        uses_rs   = 1'b1;
        uses_rt   = 1'b1;
        reg_write = 1'b1;
        dst_sel   = DST_RD;
        unique case (funct)
          6'h20, 6'h21: alu_op = ALU_ADD;  // add/addu
          6'h22, 6'h23: alu_op = ALU_SUB;  // sub/subu
          6'h24: alu_op = ALU_AND;
          6'h25: alu_op = ALU_OR;
          6'h26: alu_op = ALU_XOR;
          6'h2A: alu_op = ALU_SLT;
          6'h2B: alu_op = ALU_SLTU;
          6'h00: begin alu_op = ALU_SLL; uses_rs = 1'b0; end
          6'h02: begin alu_op = ALU_SRL; uses_rs = 1'b0; end
          6'h03: begin alu_op = ALU_SRA; uses_rs = 1'b0; end
          6'h08: begin // jr
            uses_rt   = 1'b0;
            reg_write = 1'b0;
            jump_reg  = 1'b1;
            alu_op    = ALU_PASS;
          end
          default: begin
            valid     = 1'b0;
            reg_write = 1'b0;
          end
        endcase
      end
      6'h08, 6'h09: begin // addi/addiu
        uses_rs     = 1'b1;
        reg_write   = 1'b1;
        alu_src_imm = 1'b1;
        alu_op      = ALU_ADD;
      end
      6'h0A: begin // slti
        uses_rs     = 1'b1;
        reg_write   = 1'b1;
        alu_src_imm = 1'b1;
        alu_op      = ALU_SLT;
      end
      6'h0C: begin // andi
        uses_rs      = 1'b1;
        reg_write    = 1'b1;
        alu_src_imm  = 1'b1;
        imm_zero_ext = 1'b1;
        alu_op       = ALU_AND;
      end
      6'h0D: begin // ori
        uses_rs      = 1'b1;
        reg_write    = 1'b1;
        alu_src_imm  = 1'b1;
        imm_zero_ext = 1'b1;
        alu_op       = ALU_OR;
      end
      6'h0E: begin // xori
        uses_rs      = 1'b1;
        reg_write    = 1'b1;
        alu_src_imm  = 1'b1;
        imm_zero_ext = 1'b1;
        alu_op       = ALU_XOR;
      end
      6'h0F: begin // lui
        reg_write    = 1'b1;
        alu_src_imm  = 1'b1;
        imm_zero_ext = 1'b1;
        alu_op       = ALU_LUI;
      end
      6'h23: begin // lw
        uses_rs     = 1'b1;
        reg_write   = 1'b1;
        mem_read    = 1'b1;
        mem_to_reg  = 1'b1;
        alu_src_imm = 1'b1;
        alu_op      = ALU_ADD;
      end
      6'h2B: begin // sw
        uses_rs     = 1'b1;
        uses_rt     = 1'b1;
        mem_write   = 1'b1;
        alu_src_imm = 1'b1;
        alu_op      = ALU_ADD;
      end
      6'h04: begin // beq
        uses_rs = 1'b1;
        uses_rt = 1'b1;
        branch  = BR_BEQ;
        alu_op  = ALU_SUB;
      end
      6'h05: begin // bne
        uses_rs = 1'b1;
        uses_rt = 1'b1;
        branch  = BR_BNE;
        alu_op  = ALU_SUB;
      end
      6'h02: begin // j
        jump = 1'b1;
      end
      6'h03: begin // jal
        jump      = 1'b1;
        link      = 1'b1;
        reg_write = 1'b1;
        dst_sel   = DST_RA;
      end
      default: valid = 1'b0;
    endcase
  end
endmodule
