#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#define IMEM_WORDS 4096
#define DMEM_WORDS 4096
#define MAX_CYCLES  1000000u

typedef enum { ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR, ALU_SLT, ALU_SLTU, ALU_SLL, ALU_SRL, ALU_SRA, ALU_LUI, ALU_PASS } aluop_t;
typedef enum { BR_NONE, BR_BEQ, BR_BNE } branch_t;

typedef struct {
    int valid, uses_rs, uses_rt, reg_write, mem_read, mem_write, mem_to_reg;
    int alu_src_imm, imm_zero_ext, jump, jump_reg, link;
    int dst_sel; /* 0=rt, 1=rd, 2=ra */
    branch_t branch;
    aluop_t alu;
} ctrl_t;

typedef struct { int valid; uint32_t pc, pc4, ins; } ifid_t;
typedef struct {
    int valid; uint32_t pc, pc4, rsval, rtval, imm, jidx; uint8_t rs, rt, rd, shamt, dst; ctrl_t c;
} idex_t;
typedef struct {
    int valid, reg_write, mem_read, mem_write, mem_to_reg, link;
    uint32_t alu_result, store_data, link_value; uint8_t dst;
} exmem_t;
typedef struct {
    int valid, reg_write, mem_to_reg, link;
    uint32_t alu_result, mem_data, link_value; uint8_t dst;
} memwb_t;

static uint32_t imem[IMEM_WORDS], dmem[DMEM_WORDS], r[32], pc;
static ifid_t ifid;
static idex_t idex;
static exmem_t exmem;
static memwb_t memwb;

static int load_hex(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); return -1; }
    char line[256]; int n = 0;
    while (fgets(line,sizeof line,f) && n < IMEM_WORDS) {
        char *p=line; while (*p==' '||*p=='\t') ++p;
        if (!*p||*p=='\n'||*p=='#') continue;
        imem[n++] = (uint32_t)strtoul(p,NULL,16);
    }
    fclose(f); return n;
}

static ctrl_t decode(uint32_t ins) {
    ctrl_t c; memset(&c,0,sizeof c); c.valid=1; c.alu=ALU_ADD;
    unsigned op=ins>>26, fn=ins&63u;
    switch(op) {
    case 0x00:
        c.uses_rs=c.uses_rt=c.reg_write=1; c.dst_sel=1;
        switch(fn) {
        case 0x20: case 0x21: c.alu=ALU_ADD; break;
        case 0x22: case 0x23: c.alu=ALU_SUB; break;
        case 0x24: c.alu=ALU_AND; break;
        case 0x25: c.alu=ALU_OR; break;
        case 0x26: c.alu=ALU_XOR; break;
        case 0x2a: c.alu=ALU_SLT; break;
        case 0x2b: c.alu=ALU_SLTU; break;
        case 0x00: c.alu=ALU_SLL; c.uses_rs=0; break;
        case 0x02: c.alu=ALU_SRL; c.uses_rs=0; break;
        case 0x03: c.alu=ALU_SRA; c.uses_rs=0; break;
        case 0x08: c.uses_rt=0; c.reg_write=0; c.jump_reg=1; c.alu=ALU_PASS; break;
        default: c.valid=0; c.reg_write=0; break;
        } break;
    case 0x08: case 0x09: c.uses_rs=1;c.reg_write=1;c.alu_src_imm=1;c.alu=ALU_ADD;break;
    case 0x0a: c.uses_rs=1;c.reg_write=1;c.alu_src_imm=1;c.alu=ALU_SLT;break;
    case 0x0c: c.uses_rs=1;c.reg_write=1;c.alu_src_imm=1;c.imm_zero_ext=1;c.alu=ALU_AND;break;
    case 0x0d: c.uses_rs=1;c.reg_write=1;c.alu_src_imm=1;c.imm_zero_ext=1;c.alu=ALU_OR;break;
    case 0x0e: c.uses_rs=1;c.reg_write=1;c.alu_src_imm=1;c.imm_zero_ext=1;c.alu=ALU_XOR;break;
    case 0x0f: c.reg_write=1;c.alu_src_imm=1;c.imm_zero_ext=1;c.alu=ALU_LUI;break;
    case 0x23: c.uses_rs=1;c.reg_write=1;c.mem_read=1;c.mem_to_reg=1;c.alu_src_imm=1;c.alu=ALU_ADD;break;
    case 0x2b: c.uses_rs=1;c.uses_rt=1;c.mem_write=1;c.alu_src_imm=1;c.alu=ALU_ADD;break;
    case 0x04: c.uses_rs=1;c.uses_rt=1;c.branch=BR_BEQ;c.alu=ALU_SUB;break;
    case 0x05: c.uses_rs=1;c.uses_rt=1;c.branch=BR_BNE;c.alu=ALU_SUB;break;
    case 0x02: c.jump=1;break;
    case 0x03: c.jump=1;c.link=1;c.reg_write=1;c.dst_sel=2;break;
    default: c.valid=0;break;
    }
    return c;
}

static uint32_t alu(uint32_t a,uint32_t b,uint8_t sh,aluop_t op) {
    switch(op){
    case ALU_ADD:return a+b; case ALU_SUB:return a-b; case ALU_AND:return a&b; case ALU_OR:return a|b; case ALU_XOR:return a^b;
    case ALU_SLT:return (int32_t)a<(int32_t)b; case ALU_SLTU:return a<b; case ALU_SLL:return b<<sh; case ALU_SRL:return b>>sh;
    case ALU_SRA:return (uint32_t)((int32_t)b>>sh); case ALU_LUI:return b<<16; default:return b;
    }
}

static uint32_t wb_value(void) {
    if (memwb.link) return memwb.link_value;
    return memwb.mem_to_reg ? memwb.mem_data : memwb.alu_result;
}

static void cycle(void) {
    uint32_t wb=wb_value();
    int wb_we=memwb.valid&&memwb.reg_write&&memwb.dst;
    if (wb_we) r[memwb.dst]=wb;
    r[0]=0;

    /* ID combinational */
    uint32_t ins=ifid.ins; ctrl_t dc=decode(ins);
    uint8_t rs=(ins>>21)&31, rt=(ins>>16)&31, rd=(ins>>11)&31, sh=(ins>>6)&31;
    uint16_t imm16=(uint16_t)ins;
    uint32_t rsval=rs?r[rs]:0, rtval=rt?r[rt]:0;
    if (wb_we && memwb.dst==rs) rsval=wb;
    if (wb_we && memwb.dst==rt) rtval=wb;
    uint32_t imm=dc.imm_zero_ext ? (uint32_t)imm16 : (uint32_t)(int32_t)(int16_t)imm16;
    uint8_t dst=dc.dst_sel==1?rd:dc.dst_sel==2?31:rt;
    int stall=idex.valid&&idex.c.mem_read&&idex.dst && ifid.valid&&dc.valid &&
              ((dc.uses_rs&&rs==idex.dst)||(dc.uses_rt&&rt==idex.dst));

    /* EX combinational */
    uint32_t xa=idex.rsval, xbreg=idex.rtval;
    if (exmem.valid&&exmem.reg_write&&!exmem.mem_to_reg&&exmem.dst&&exmem.dst==idex.rs) xa=exmem.alu_result;
    else if (memwb.valid&&memwb.reg_write&&memwb.dst&&memwb.dst==idex.rs) xa=wb;
    if (exmem.valid&&exmem.reg_write&&!exmem.mem_to_reg&&exmem.dst&&exmem.dst==idex.rt) xbreg=exmem.alu_result;
    else if (memwb.valid&&memwb.reg_write&&memwb.dst&&memwb.dst==idex.rt) xbreg=wb;
    uint32_t xb=idex.c.alu_src_imm?idex.imm:xbreg;
    uint32_t xalu=alu(xa,xb,idex.shamt,idex.c.alu);
    int taken=(idex.c.branch==BR_BEQ&&xa==xbreg)||(idex.c.branch==BR_BNE&&xa!=xbreg);
    int redirect=0; uint32_t rpc=0;
    if(idex.valid){
        if(idex.c.jump_reg){redirect=1;rpc=xa;}
        else if(idex.c.jump){redirect=1;rpc=(idex.pc4&0xf0000000u)|(idex.jidx<<2);}
        else if(taken){redirect=1;rpc=idex.pc4+(idex.imm<<2);}
    }

    /* MEM combinational / synchronous write effect */
    uint32_t mread=0;
    if(exmem.valid&&exmem.mem_read && !(exmem.alu_result&3u) && (exmem.alu_result>>2)<DMEM_WORDS) mread=dmem[exmem.alu_result>>2];
    if(exmem.valid&&exmem.mem_write && !(exmem.alu_result&3u) && (exmem.alu_result>>2)<DMEM_WORDS) dmem[exmem.alu_result>>2]=exmem.store_data;

    memwb_t nmemwb={0};
    nmemwb.valid=exmem.valid;nmemwb.reg_write=exmem.reg_write;nmemwb.mem_to_reg=exmem.mem_to_reg;nmemwb.link=exmem.link;
    nmemwb.alu_result=exmem.alu_result;nmemwb.mem_data=mread;nmemwb.link_value=exmem.link_value;nmemwb.dst=exmem.dst;

    exmem_t nexmem={0};
    nexmem.valid=idex.valid;nexmem.reg_write=idex.c.reg_write;nexmem.mem_read=idex.c.mem_read;nexmem.mem_write=idex.c.mem_write;
    nexmem.mem_to_reg=idex.c.mem_to_reg;nexmem.link=idex.c.link;nexmem.alu_result=xalu;nexmem.store_data=xbreg;nexmem.link_value=idex.pc4;nexmem.dst=idex.dst;

    idex_t nidex=idex;
    if(redirect){memset(&nidex,0,sizeof nidex);} else if(stall){memset(&nidex,0,sizeof nidex);} else {
        memset(&nidex,0,sizeof nidex); nidex.valid=ifid.valid&&dc.valid; nidex.pc=ifid.pc;nidex.pc4=ifid.pc4;nidex.rsval=rsval;nidex.rtval=rtval;
        nidex.imm=imm;nidex.jidx=ins&0x03ffffffu;nidex.rs=rs;nidex.rt=rt;nidex.rd=rd;nidex.shamt=sh;nidex.dst=dst;nidex.c=dc;
    }

    ifid_t nifid=ifid; uint32_t npc=pc;
    if(redirect){memset(&nifid,0,sizeof nifid);npc=rpc;}
    else if(!stall){nifid.valid=1;nifid.pc=pc;nifid.pc4=pc+4;nifid.ins=((pc>>2)<IMEM_WORDS)?imem[pc>>2]:0;npc=pc+4;}

    memwb=nmemwb;exmem=nexmem;idex=nidex;ifid=nifid;pc=npc;
}

int main(int argc,char **argv){
    const char *hex=argc>1?argv[1]:"programs/pipeline_demo.hex";
    int words=load_hex(hex);if(words<0)return 1;
    printf("MIPSforFUN cycle model: loaded %d instructions\n",words);
    for(uint32_t c=1;c<=MAX_CYCLES;c++){
        cycle();
        if(dmem[66]==1u){
            /* allow no more architectural work: sentinel store is already committed in MEM */
            printf("PASS after %" PRIu32 " pipeline cycles\n",c);
            printf("mem[0x100]=%" PRIu32 " mem[0x104]=%" PRIu32 " mem[0x108]=%" PRIu32 " mem[0x10C]=%" PRIu32 "\n",dmem[64],dmem[65],dmem[66],dmem[67]);
            return (dmem[64]==55&&dmem[65]==110&&dmem[67]==165)?0:2;
        }
    }
    fprintf(stderr,"TIMEOUT\n");return 3;
}
