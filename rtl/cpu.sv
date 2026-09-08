module mipsforfun_cpu (
  input  logic        clk,
  input  logic        reset,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_wstrb,
  input  logic [31:0] dmem_rdata,
  output logic [31:0] debug_pc,
  output logic        debug_wb_we,
  output logic [4:0]  debug_wb_rd,
  output logic [31:0] debug_wb_data
);
  import mipsforfun_pkg::*;

  // ---------------- IF ----------------
  logic [31:0] pc_f, pc_next, pc_plus4_f;
  logic        stall_d, redirect_x;
  logic [31:0] redirect_pc_x;

  assign pc_plus4_f = pc_f + 32'd4;
  assign imem_addr  = pc_f;
  assign debug_pc   = pc_f;

  always_comb begin
    if (redirect_x) pc_next = redirect_pc_x;
    else            pc_next = pc_plus4_f;
  end

  always_ff @(posedge clk) begin
    if (reset)
      pc_f <= 32'd0;
    else if (!stall_d || redirect_x)
      pc_f <= pc_next;
  end

  // ---------------- IF/ID ----------------
  logic        ifid_valid;
  logic [31:0] ifid_pc, ifid_pc4, ifid_instr;

  always_ff @(posedge clk) begin
    if (reset || redirect_x) begin
      ifid_valid <= 1'b0;
      ifid_pc    <= 32'd0;
      ifid_pc4   <= 32'd0;
      ifid_instr <= 32'd0;
    end else if (!stall_d) begin
      ifid_valid <= 1'b1;
      ifid_pc    <= pc_f;
      ifid_pc4   <= pc_plus4_f;
      ifid_instr <= imem_rdata;
    end
  end

  // ---------------- ID ----------------
  logic [4:0] rs_d, rt_d, rd_d;
  logic [4:0] shamt_d;
  logic [15:0] imm16_d;
  logic [25:0] jidx_d;
  logic [31:0] rs_val_d, rt_val_d, rs_val_bypass_d, rt_val_bypass_d, imm_ext_d;

  logic ctrl_valid_d, uses_rs_d, uses_rt_d, reg_write_d;
  logic mem_read_d, mem_write_d, mem_to_reg_d, alu_src_imm_d;
  logic imm_zero_ext_d, jump_d, jump_reg_d, link_d;
  branch_t branch_d;
  dst_sel_t dst_sel_d;
  alu_op_t alu_op_d;

  assign rs_d    = ifid_instr[25:21];
  assign rt_d    = ifid_instr[20:16];
  assign rd_d    = ifid_instr[15:11];
  assign shamt_d = ifid_instr[10:6];
  assign imm16_d = ifid_instr[15:0];
  assign jidx_d  = ifid_instr[25:0];

  mipsforfun_control u_control (
    .instr(ifid_instr), .valid(ctrl_valid_d), .uses_rs(uses_rs_d), .uses_rt(uses_rt_d),
    .reg_write(reg_write_d), .mem_read(mem_read_d), .mem_write(mem_write_d),
    .mem_to_reg(mem_to_reg_d), .alu_src_imm(alu_src_imm_d), .imm_zero_ext(imm_zero_ext_d),
    .jump(jump_d), .jump_reg(jump_reg_d), .link(link_d), .branch(branch_d),
    .dst_sel(dst_sel_d), .alu_op(alu_op_d)
  );

  logic wb_reg_write;
  logic [4:0] wb_dst;
  logic [31:0] wb_data;

  mipsforfun_regfile u_regfile (
    .clk(clk), .reset(reset), .we(wb_reg_write), .waddr(wb_dst), .wdata(wb_data),
    .raddr1(rs_d), .raddr2(rt_d), .rdata1(rs_val_d), .rdata2(rt_val_d)
  );

  // Same-cycle WB -> ID bypass. Without this, an instruction entering ID/EX on
  // the clock edge of an older writeback could capture the old register value.
  always_comb begin
    rs_val_bypass_d = rs_val_d;
    rt_val_bypass_d = rt_val_d;
    if (wb_reg_write && (wb_dst != 5'd0) && (wb_dst == rs_d)) rs_val_bypass_d = wb_data;
    if (wb_reg_write && (wb_dst != 5'd0) && (wb_dst == rt_d)) rt_val_bypass_d = wb_data;
  end

  always_comb begin
    if (imm_zero_ext_d) imm_ext_d = {16'd0, imm16_d};
    else                imm_ext_d = {{16{imm16_d[15]}}, imm16_d};
  end

  // ---------------- ID/EX ----------------
  logic        idex_valid;
  logic [31:0] idex_pc, idex_pc4;
  logic [31:0] idex_rs_val, idex_rt_val, idex_imm;
  logic [25:0] idex_jidx;
  logic [4:0]  idex_rs, idex_rt, idex_rd, idex_shamt;
  logic        idex_reg_write, idex_mem_read, idex_mem_write, idex_mem_to_reg;
  logic        idex_alu_src_imm, idex_jump, idex_jump_reg, idex_link;
  branch_t     idex_branch;
  dst_sel_t    idex_dst_sel;
  alu_op_t     idex_alu_op;
  logic [4:0]  idex_dst;
  logic [4:0]  idex_dst_r;
  logic [4:0] dst_d;
  always_comb begin
    unique case (dst_sel_d)
      DST_RD: dst_d = rd_d;
      DST_RA: dst_d = 5'd31;
      default: dst_d = rt_d;
    endcase
  end

  mipsforfun_hazard_unit u_hazard (
    .id_uses_rs(uses_rs_d && ifid_valid && ctrl_valid_d),
    .id_uses_rt(uses_rt_d && ifid_valid && ctrl_valid_d),
    .id_rs(rs_d), .id_rt(rt_d),
    .ex_mem_read(idex_valid && idex_mem_read), .ex_dst(idex_dst), .stall(stall_d)
  );

  // Registered destination for hazard detection and execute/writeback routing.
  assign idex_dst = idex_dst_r;

  always_ff @(posedge clk) begin
    if (reset || redirect_x) begin
      idex_valid      <= 1'b0;
      idex_pc         <= 0;
      idex_pc4        <= 0;
      idex_rs_val     <= 0;
      idex_rt_val     <= 0;
      idex_imm        <= 0;
      idex_jidx       <= 0;
      idex_rs         <= 0;
      idex_rt         <= 0;
      idex_rd         <= 0;
      idex_shamt      <= 0;
      idex_dst_r      <= 0;
      idex_reg_write  <= 0;
      idex_mem_read   <= 0;
      idex_mem_write  <= 0;
      idex_mem_to_reg <= 0;
      idex_alu_src_imm<= 0;
      idex_jump       <= 0;
      idex_jump_reg   <= 0;
      idex_link       <= 0;
      idex_branch     <= BR_NONE;
      idex_dst_sel    <= DST_RT;
      idex_alu_op     <= ALU_ADD;
    end else if (stall_d) begin
      idex_valid      <= 1'b0; // inject bubble
      idex_reg_write  <= 1'b0;
      idex_mem_read   <= 1'b0;
      idex_mem_write  <= 1'b0;
      idex_mem_to_reg <= 1'b0;
      idex_jump       <= 1'b0;
      idex_jump_reg   <= 1'b0;
      idex_link       <= 1'b0;
      idex_branch     <= BR_NONE;
      idex_dst_r      <= 5'd0;
    end else begin
      idex_valid       <= ifid_valid && ctrl_valid_d;
      idex_pc          <= ifid_pc;
      idex_pc4         <= ifid_pc4;
      idex_rs_val      <= rs_val_bypass_d;
      idex_rt_val      <= rt_val_bypass_d;
      idex_imm         <= imm_ext_d;
      idex_jidx        <= jidx_d;
      idex_rs          <= rs_d;
      idex_rt          <= rt_d;
      idex_rd          <= rd_d;
      idex_shamt       <= shamt_d;
      idex_dst_r       <= dst_d;
      idex_reg_write   <= reg_write_d;
      idex_mem_read    <= mem_read_d;
      idex_mem_write   <= mem_write_d;
      idex_mem_to_reg  <= mem_to_reg_d;
      idex_alu_src_imm <= alu_src_imm_d;
      idex_jump        <= jump_d;
      idex_jump_reg    <= jump_reg_d;
      idex_link        <= link_d;
      idex_branch      <= branch_d;
      idex_dst_sel     <= dst_sel_d;
      idex_alu_op      <= alu_op_d;
    end
  end

  // ---------------- EX ----------------
  logic [1:0] fwd_a_sel, fwd_b_sel;
  logic [31:0] exmem_alu_result;
  logic        exmem_reg_write, exmem_mem_to_reg;
  logic [4:0]  exmem_dst;
  logic [31:0] src_a_x, src_b_reg_x, src_b_alu_x;
  logic [31:0] alu_result_x;
  logic        alu_zero_x;
  logic [31:0] branch_target_x, jump_target_x;
  logic        branch_taken_x;

  mipsforfun_forward_unit u_forward (
    .ex_rs(idex_rs), .ex_rt(idex_rt),
    .mem_reg_write(exmem_reg_write), .mem_mem_to_reg(exmem_mem_to_reg), .mem_dst(exmem_dst),
    .wb_reg_write(wb_reg_write), .wb_dst(wb_dst), .fwd_a(fwd_a_sel), .fwd_b(fwd_b_sel)
  );

  always_comb begin
    unique case (fwd_a_sel)
      2'b10: src_a_x = exmem_alu_result;
      2'b01: src_a_x = wb_data;
      default: src_a_x = idex_rs_val;
    endcase
    unique case (fwd_b_sel)
      2'b10: src_b_reg_x = exmem_alu_result;
      2'b01: src_b_reg_x = wb_data;
      default: src_b_reg_x = idex_rt_val;
    endcase
    src_b_alu_x = idex_alu_src_imm ? idex_imm : src_b_reg_x;
  end

  mipsforfun_alu u_alu (
    .a(src_a_x), .b(src_b_alu_x), .shamt(idex_shamt), .op(idex_alu_op),
    .y(alu_result_x), .zero(alu_zero_x)
  );

  assign branch_target_x = idex_pc4 + (idex_imm << 2);
  assign jump_target_x   = {idex_pc4[31:28], idex_jidx, 2'b00};

  always_comb begin
    branch_taken_x = 1'b0;
    unique case (idex_branch)
      BR_BEQ: branch_taken_x = (src_a_x == src_b_reg_x);
      BR_BNE: branch_taken_x = (src_a_x != src_b_reg_x);
      default: branch_taken_x = 1'b0;
    endcase

    redirect_x    = 1'b0;
    redirect_pc_x = 32'd0;
    if (idex_valid) begin
      if (idex_jump_reg) begin
        redirect_x    = 1'b1;
        redirect_pc_x = src_a_x;
      end else if (idex_jump) begin
        redirect_x    = 1'b1;
        redirect_pc_x = jump_target_x;
      end else if (branch_taken_x) begin
        redirect_x    = 1'b1;
        redirect_pc_x = branch_target_x;
      end
    end
  end

  // ---------------- EX/MEM ----------------
  logic        exmem_valid, exmem_mem_read, exmem_mem_write, exmem_link;
  logic [31:0] exmem_store_data, exmem_link_value;

  always_ff @(posedge clk) begin
    if (reset) begin
      exmem_valid       <= 0;
      exmem_alu_result  <= 0;
      exmem_store_data  <= 0;
      exmem_dst         <= 0;
      exmem_reg_write   <= 0;
      exmem_mem_read    <= 0;
      exmem_mem_write   <= 0;
      exmem_mem_to_reg  <= 0;
      exmem_link        <= 0;
      exmem_link_value  <= 0;
    end else begin
      exmem_valid       <= idex_valid;
      exmem_alu_result  <= alu_result_x;
      exmem_store_data  <= src_b_reg_x;
      exmem_dst         <= idex_dst;
      exmem_reg_write   <= idex_reg_write;
      exmem_mem_read    <= idex_mem_read;
      exmem_mem_write   <= idex_mem_write;
      exmem_mem_to_reg  <= idex_mem_to_reg;
      exmem_link        <= idex_link;
      exmem_link_value  <= idex_pc4;
    end
  end

  // ---------------- MEM ----------------
  assign dmem_addr  = exmem_alu_result;
  assign dmem_wdata = exmem_store_data;
  assign dmem_wstrb = (exmem_valid && exmem_mem_write) ? 4'b1111 : 4'b0000;

  // ---------------- MEM/WB ----------------
  logic        memwb_valid, memwb_reg_write, memwb_mem_to_reg, memwb_link;
  logic [31:0] memwb_alu_result, memwb_mem_data, memwb_link_value;
  logic [4:0]  memwb_dst;

  always_ff @(posedge clk) begin
    if (reset) begin
      memwb_valid      <= 0;
      memwb_alu_result <= 0;
      memwb_mem_data   <= 0;
      memwb_dst        <= 0;
      memwb_reg_write  <= 0;
      memwb_mem_to_reg <= 0;
      memwb_link       <= 0;
      memwb_link_value <= 0;
    end else begin
      memwb_valid      <= exmem_valid;
      memwb_alu_result <= exmem_alu_result;
      memwb_mem_data   <= dmem_rdata;
      memwb_dst        <= exmem_dst;
      memwb_reg_write  <= exmem_reg_write;
      memwb_mem_to_reg <= exmem_mem_to_reg;
      memwb_link       <= exmem_link;
      memwb_link_value <= exmem_link_value;
    end
  end

  // ---------------- WB ----------------
  always_comb begin
    wb_data = memwb_link ? memwb_link_value :
              (memwb_mem_to_reg ? memwb_mem_data : memwb_alu_result);
    wb_dst = memwb_dst;
    wb_reg_write = memwb_valid && memwb_reg_write;
  end

  assign debug_wb_we   = wb_reg_write;
  assign debug_wb_rd   = wb_dst;
  assign debug_wb_data = wb_data;
endmodule
