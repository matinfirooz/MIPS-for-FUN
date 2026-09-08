module mipsforfun_hazard_unit (
  input  logic       id_uses_rs,
  input  logic       id_uses_rt,
  input  logic [4:0] id_rs,
  input  logic [4:0] id_rt,
  input  logic       ex_mem_read,
  input  logic [4:0] ex_dst,
  output logic       stall
);
  always_comb begin
    stall = 1'b0;
    if (ex_mem_read && (ex_dst != 5'd0)) begin
      if (id_uses_rs && (id_rs == ex_dst)) stall = 1'b1;
      if (id_uses_rt && (id_rt == ex_dst)) stall = 1'b1;
    end
  end
endmodule
