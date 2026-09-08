module MIPSforFUN #(
  parameter int IMEM_WORDS = 1024,
  parameter int DMEM_WORDS = 1024,
  parameter string PROGRAM_HEX = "program.hex",
  parameter string DATA_HEX = ""
) (
  input logic clk,
  input logic reset,
  output logic [31:0] debug_pc,
  output logic        debug_wb_we,
  output logic [4:0]  debug_wb_rd,
  output logic [31:0] debug_wb_data
);
  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]  dmem_wstrb;

  mipsforfun_cpu cpu (
    .clk(clk), .reset(reset),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb), .dmem_rdata(dmem_rdata),
    .debug_pc(debug_pc), .debug_wb_we(debug_wb_we), .debug_wb_rd(debug_wb_rd), .debug_wb_data(debug_wb_data)
  );

  mipsforfun_imem #(.WORDS(IMEM_WORDS), .INIT_HEX(PROGRAM_HEX)) imem (
    .addr(imem_addr), .rdata(imem_rdata)
  );

  mipsforfun_dmem #(.WORDS(DMEM_WORDS), .INIT_HEX(DATA_HEX)) dmem (
    .clk(clk), .addr(dmem_addr), .wdata(dmem_wdata), .wstrb(dmem_wstrb), .rdata(dmem_rdata)
  );
endmodule
