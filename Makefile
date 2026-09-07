CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -std=c11
IVERILOG ?= iverilog
VVP ?= vvp

RTL = rtl/mipsforfun_pkg.sv rtl/alu.sv rtl/regfile.sv rtl/control.sv \
      rtl/hazard_unit.sv rtl/forward_unit.sv rtl/cpu.sv rtl/memory.sv rtl/soc.sv

.PHONY: all ref pipeline-model asm program sim test-c clean
all: ref pipeline-model asm program

ref: build/mips_ref
pipeline-model: build/mips_pipeline_model
asm: build/mipsasm

build:
	mkdir -p build

build/mips_ref: ref/mips_ref.c | build
	$(CC) $(CFLAGS) -o $@ $<

build/mips_pipeline_model: ref/mips_pipeline_model.c | build
	$(CC) $(CFLAGS) -o $@ $<

build/mipsasm: tools/mipsasm.c | build
	$(CC) $(CFLAGS) -D_POSIX_C_SOURCE=200809L -o $@ $<

program: build/mipsasm
	./build/mipsasm programs/pipeline_demo.asm programs/pipeline_demo.hex

test-c: all
	./build/mips_ref programs/pipeline_demo.hex
	./build/mips_pipeline_model programs/pipeline_demo.hex

sim: program
	$(IVERILOG) -g2012 -s tb_MIPSforFUN -o build/tb.vvp $(RTL) sim/tb_MIPSforFUN.sv
	$(VVP) build/tb.vvp

clean:
	rm -rf build mipsforfun.vcd
