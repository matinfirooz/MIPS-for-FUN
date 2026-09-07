# MIPSforFUN microarchitecture

## Pipeline

MIPSforFUN is a 32-bit, in-order, single-issue, 5-stage pipelined MIPS-style processor.

| Stage | Function |
|---|---|
| IF | Fetch instruction and calculate PC+4 |
| ID | Decode, read 32x32 register file, extend immediate, hazard check |
| EX | Forward operands, ALU, branch/jump decision and target generation |
| MEM | Word load/store through the data-memory interface |
| WB | Select ALU/load/link result and write register file |

Pipeline registers: `IF/ID`, `ID/EX`, `EX/MEM`, and `MEM/WB`.

## Hazards

### RAW forwarding

The forwarding unit selects each EX register operand from:

1. ID/EX register value,
2. EX/MEM ALU result, or
3. MEM/WB final writeback value.

EX/MEM forwarding is disabled for loads because the load data does not exist until MEM.

### Load-use interlock

If a load in EX writes a register needed by the instruction in ID, PC and IF/ID are frozen for one cycle and a bubble is inserted into ID/EX.

### Control hazards

BEQ/BNE/J/JAL/JR resolve in EX. A redirect flushes IF/ID and ID/EX. MIPSforFUN intentionally does **not** implement the historical MIPS branch delay slot. `jal` therefore writes `PC+4` to `$ra`.

## Memory model

The core exposes separate instruction and data ports (Harvard style). The provided SoC wrapper uses asynchronous reads and synchronous writes. Only naturally aligned 32-bit `lw`/`sw` are part of the current ISA subset.

## Implemented ISA subset

R-type: `add`, `addu`, `sub`, `subu`, `and`, `or`, `xor`, `slt`, `sltu`, `sll`, `srl`, `sra`, `jr`.

Immediate: `addi`, `addiu`, `slti`, `andi`, `ori`, `xori`, `lui`.

Memory: `lw`, `sw`.

Control flow: `beq`, `bne`, `j`, `jal`.

`$zero` is hardwired to zero.

## Deliberate simplifications

This project is educational/research RTL, not a complete MIPS32 Release 2 implementation. It does not yet implement exceptions, CP0, interrupts, multiply/divide HI/LO, byte/halfword accesses, unaligned accesses, caches, virtual memory, or arithmetic-overflow traps.
