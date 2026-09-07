# MIPSforFUN pipeline demo
# Expected memory results:
#   mem[0x100] = 55
#   mem[0x104] = 110
#   mem[0x108] = 1   (PASS sentinel)
#   mem[0x10C] = 165 (jal/jr subroutine result)

        addi $t0, $zero, 10
        addi $t1, $zero, 0
        addi $t2, $zero, 1
loop:
        add  $t1, $t1, $t2
        addi $t2, $t2, 1
        slt  $t3, $t0, $t2
        bne  $t3, $zero, done
        j    loop

done:
        sw   $t1, 256($zero)
        lw   $t4, 256($zero)
        add  $t5, $t4, $t1      # deliberate load-use hazard
        sw   $t5, 260($zero)
        jal  subroutine
        sw   $v0, 268($zero)
        addi $t6, $zero, 1
        sw   $t6, 264($zero)     # PASS sentinel
halt:
        j    halt
        nop

subroutine:
        add  $v0, $t5, $t1
        jr   $ra
