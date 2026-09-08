module mipsforfun_alu (
  input  logic [31:0] a,
  input  logic [31:0] b,
  input  logic [4:0]  shamt,
  input  mipsforfun_pkg::alu_op_t op,
  output logic [31:0] y,
  output logic        zero
);
  import mipsforfun_pkg::*;

  always_comb begin
    unique case (op)
      ALU_ADD:  y = a + b;
      ALU_SUB:  y = a - b;
      ALU_AND:  y = a & b;
      ALU_OR:   y = a | b;
      ALU_XOR:  y = a ^ b;
      ALU_SLT:  y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      ALU_SLTU: y = (a < b) ? 32'd1 : 32'd0;
      ALU_SLL:  y = b << shamt;
      ALU_SRL:  y = b >> shamt;
      ALU_SRA:  y = $signed(b) >>> shamt;
      ALU_LUI:  y = {b[15:0], 16'h0000};
      default:  y = b;
    endcase
  end

  assign zero = (y == 32'd0);
endmodule
