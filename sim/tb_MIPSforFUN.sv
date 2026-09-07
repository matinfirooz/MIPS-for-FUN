`timescale 1ns/1ps
module tb_MIPSforFUN;
  logic clk = 1'b0;
  logic reset = 1'b1;
  logic [31:0] debug_pc;
  logic debug_wb_we;
  logic [4:0] debug_wb_rd;
  logic [31:0] debug_wb_data;

  always #5 clk = ~clk;

  MIPSforFUN #(
    .PROGRAM_HEX("programs/pipeline_demo.hex")
  ) dut (
    .clk(clk), .reset(reset),
    .debug_pc(debug_pc),
    .debug_wb_we(debug_wb_we),
    .debug_wb_rd(debug_wb_rd),
    .debug_wb_data(debug_wb_data)
  );

  int cycles;
  initial begin
    $dumpfile("mipsforfun.vcd");
    $dumpvars(0, tb_MIPSforFUN);
    repeat (4) @(posedge clk);
    reset <= 1'b0;

    cycles = 0;
    while (cycles < 500) begin
      @(posedge clk);
      cycles++;
      if (debug_wb_we)
        $display("C%0d PC=%08x WB r%0d=%08x", cycles, debug_pc, debug_wb_rd, debug_wb_data);

      if (dut.dmem.mem[66] == 32'd1) begin
        // Give the preceding store from the jal/jr path time to be visible as well.
        repeat (2) @(posedge clk);
        if (dut.dmem.mem[64] !== 32'd55) begin
          $error("FAIL: mem[0x100]=%0d, expected 55", dut.dmem.mem[64]);
          $fatal;
        end
        if (dut.dmem.mem[65] !== 32'd110) begin
          $error("FAIL: mem[0x104]=%0d, expected 110", dut.dmem.mem[65]);
          $fatal;
        end
        if (dut.dmem.mem[67] !== 32'd165) begin
          $error("FAIL: mem[0x10C]=%0d, expected 165", dut.dmem.mem[67]);
          $fatal;
        end
        $display("PASS: MIPSforFUN pipeline demo completed in %0d cycles", cycles);
        $finish;
      end
    end

    $fatal(1, "TIMEOUT after %0d cycles", cycles);
  end
endmodule
