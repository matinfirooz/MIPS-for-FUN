#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#define IMEM_WORDS 4096
#define DMEM_WORDS 4096
#define MAX_STEPS   1000000u

static uint32_t imem[IMEM_WORDS];
static uint32_t dmem[DMEM_WORDS];
static uint32_t r[32];
static uint32_t pc;

static int load_hex(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); return -1; }
    char line[256];
    size_t n = 0;
    while (fgets(line, sizeof(line), f) && n < IMEM_WORDS) {
        char *p = line;
        while (*p == ' ' || *p == '\t') ++p;
        if (*p == '\0' || *p == '\n' || *p == '#') continue;
        unsigned long v = strtoul(p, NULL, 16);
        imem[n++] = (uint32_t)v;
    }
    fclose(f);
    return (int)n;
}

static int32_t sext16(uint16_t x) { return (int16_t)x; }
static uint32_t regv(unsigned idx) { return idx ? r[idx & 31u] : 0u; }
static void setr(unsigned idx, uint32_t v) { if (idx) r[idx & 31u] = v; }

static void step(void) {
    uint32_t ins = imem[(pc >> 2) & (IMEM_WORDS - 1)];
    uint32_t cur_pc = pc;
    uint32_t next_pc = pc + 4;
    unsigned op = ins >> 26;
    unsigned rs = (ins >> 21) & 31u;
    unsigned rt = (ins >> 16) & 31u;
    unsigned rd = (ins >> 11) & 31u;
    unsigned sh = (ins >> 6) & 31u;
    unsigned fn = ins & 63u;
    uint16_t imm = (uint16_t)ins;
    uint32_t a = regv(rs), b = regv(rt);

    switch (op) {
    case 0x00:
        switch (fn) {
        case 0x00: setr(rd, b << sh); break;
        case 0x02: setr(rd, b >> sh); break;
        case 0x03: setr(rd, (uint32_t)((int32_t)b >> sh)); break;
        case 0x08: next_pc = a; break;                    // jr
        case 0x20: case 0x21: setr(rd, a + b); break;    // add/addu
        case 0x22: case 0x23: setr(rd, a - b); break;    // sub/subu
        case 0x24: setr(rd, a & b); break;
        case 0x25: setr(rd, a | b); break;
        case 0x26: setr(rd, a ^ b); break;
        case 0x2A: setr(rd, (int32_t)a < (int32_t)b); break;
        case 0x2B: setr(rd, a < b); break;
        default: break;
        }
        break;
    case 0x08: case 0x09: setr(rt, a + (uint32_t)sext16(imm)); break;
    case 0x0A: setr(rt, (int32_t)a < sext16(imm)); break;
    case 0x0C: setr(rt, a & (uint32_t)imm); break;
    case 0x0D: setr(rt, a | (uint32_t)imm); break;
    case 0x0E: setr(rt, a ^ (uint32_t)imm); break;
    case 0x0F: setr(rt, (uint32_t)imm << 16); break;
    case 0x23: { // lw
        uint32_t addr = a + (uint32_t)sext16(imm);
        if ((addr & 3u) == 0 && (addr >> 2) < DMEM_WORDS) setr(rt, dmem[addr >> 2]);
        break;
    }
    case 0x2B: { // sw
        uint32_t addr = a + (uint32_t)sext16(imm);
        if ((addr & 3u) == 0 && (addr >> 2) < DMEM_WORDS) dmem[addr >> 2] = b;
        break;
    }
    case 0x04: if (a == b) next_pc = cur_pc + 4 + ((uint32_t)sext16(imm) << 2); break;
    case 0x05: if (a != b) next_pc = cur_pc + 4 + ((uint32_t)sext16(imm) << 2); break;
    case 0x02: next_pc = ((cur_pc + 4) & 0xF0000000u) | ((ins & 0x03FFFFFFu) << 2); break;
    case 0x03:
        setr(31, cur_pc + 4); // MIPSforFUN intentionally has no delay slot
        next_pc = ((cur_pc + 4) & 0xF0000000u) | ((ins & 0x03FFFFFFu) << 2);
        break;
    default: break;
    }

    r[0] = 0;
    pc = next_pc;
}

int main(int argc, char **argv) {
    const char *hex = argc > 1 ? argv[1] : "programs/pipeline_demo.hex";
    int words = load_hex(hex);
    if (words < 0) return 1;
    printf("MIPSforFUN C reference model: loaded %d instructions\n", words);

    for (uint32_t n = 0; n < MAX_STEPS; ++n) {
        step();
        if (dmem[66] == 1u) {
            printf("PASS after %" PRIu32 " ISA steps\n", n + 1);
            printf("mem[0x100]=%" PRIu32 "\n", dmem[64]);
            printf("mem[0x104]=%" PRIu32 "\n", dmem[65]);
            printf("mem[0x108]=%" PRIu32 "\n", dmem[66]);
            printf("mem[0x10C]=%" PRIu32 "\n", dmem[67]);
            return (dmem[64] == 55 && dmem[65] == 110 && dmem[67] == 165) ? 0 : 2;
        }
    }
    fprintf(stderr, "TIMEOUT\n");
    return 3;
}
