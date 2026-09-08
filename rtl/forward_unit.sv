module mipsforfun_forward_unit (
  input  logic [4:0] ex_rs,
  input  logic [4:0] ex_rt,
  input  logic       mem_reg_write,
  input  logic       mem_mem_to_reg,
  input  logic [4:0] mem_dst,
  input  logic       wb_reg_write,
  input  logic [4:0] wb_dst,
  output logic [1:0] fwd_a,
  output logic [1:0] fwd_b
);
  // 00 = ID/EX value, 10 = EX/MEM ALU value, 01 = MEM/WB writeback value
  always_comb begin
    fwd_a = 2'b00;
    fwd_b = 2'b00;

    if (mem_reg_write && !mem_mem_to_reg && (mem_dst != 0) && (mem_dst == ex_rs))
      fwd_a = 2'b10;
    else if (wb_reg_write && (wb_dst != 0) && (wb_dst == ex_rs))
      fwd_a = 2'b01;

    if (mem_reg_write && !mem_mem_to_reg && (mem_dst != 0) && (mem_dst == ex_rt))
      fwd_b = 2'b10;
    else if (wb_reg_write && (wb_dst != 0) && (wb_dst == ex_rt))
      fwd_b = 2'b01;
  end
endmodule
