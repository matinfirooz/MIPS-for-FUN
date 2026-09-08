module mipsforfun_imem #(
  parameter int WORDS = 1024,
  parameter string INIT_HEX = "program.hex"
) (
  input  logic [31:0] addr,
  output logic [31:0] rdata
);
  logic [31:0] mem [0:WORDS-1];
  integer i;
  initial begin
    for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'd0;
    if (INIT_HEX != "") $readmemh(INIT_HEX, mem);
  end
  always_comb begin
    if (addr[31:2] < WORDS) rdata = mem[addr[31:2]];
    else                    rdata = 32'd0;
  end
endmodule

module mipsforfun_dmem #(
  parameter int WORDS = 1024,
  parameter string INIT_HEX = ""
) (
  input  logic        clk,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  output logic [31:0] rdata
);
  logic [31:0] mem [0:WORDS-1];
  integer i;
  initial begin
    for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'd0;
    if (INIT_HEX != "") $readmemh(INIT_HEX, mem);
  end

  always_comb begin
    if (addr[31:2] < WORDS) rdata = mem[addr[31:2]];
    else                    rdata = 32'd0;
  end

  always_ff @(posedge clk) begin
    if (addr[31:2] < WORDS) begin
      if (wstrb[0]) mem[addr[31:2]][7:0]   <= wdata[7:0];
      if (wstrb[1]) mem[addr[31:2]][15:8]  <= wdata[15:8];
      if (wstrb[2]) mem[addr[31:2]][23:16] <= wdata[23:16];
      if (wstrb[3]) mem[addr[31:2]][31:24] <= wdata[31:24];
    end
  end
endmodule
