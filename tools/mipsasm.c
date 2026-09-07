/*
 * MIPSforFUN tiny two-pass assembler.
 * Supported: add/addu/sub/subu/and/or/xor/slt/sltu, sll/srl/sra, jr,
 * addi/addiu/slti/andi/ori/xori/lui, lw/sw, beq/bne, j/jal, nop.
 */
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINES 8192
#define MAX_LABELS 2048
#define MAX_NAME 64

typedef struct { char name[MAX_NAME]; uint32_t pc; } label_t;
static label_t labels[MAX_LABELS];
static int nlabels;
static char *lines[MAX_LINES];
static int nlines;

static char *trim(char *s) {
    while (isspace((unsigned char)*s)) ++s;
    char *e = s + strlen(s);
    while (e > s && isspace((unsigned char)e[-1])) *--e = 0;
    return s;
}

static void strip_comment(char *s) {
    char *p = strchr(s, '#'); if (p) *p = 0;
    p = strchr(s, ';'); if (p) *p = 0;
}

static int regnum(const char *s) {
    if (*s == '$') ++s;
    if (isdigit((unsigned char)*s)) return atoi(s);
    static const char *names[32] = {
        "zero","at","v0","v1","a0","a1","a2","a3",
        "t0","t1","t2","t3","t4","t5","t6","t7",
        "s0","s1","s2","s3","s4","s5","s6","s7",
        "t8","t9","k0","k1","gp","sp","fp","ra"
    };
    for (int i=0;i<32;i++) if (!strcmp(s,names[i])) return i;
    fprintf(stderr,"unknown register: %s\n",s); exit(2);
}

static int32_t number(const char *s) { return (int32_t)strtol(s,NULL,0); }
static int find_label(const char *s, uint32_t *pc) {
    for (int i=0;i<nlabels;i++) if (!strcmp(labels[i].name,s)) { *pc=labels[i].pc; return 1; }
    return 0;
}
static uint32_t R(int rs,int rt,int rd,int sh,int fn){return ((uint32_t)rs<<21)|((uint32_t)rt<<16)|((uint32_t)rd<<11)|((uint32_t)sh<<6)|(uint32_t)fn;}
static uint32_t I(int op,int rs,int rt,int32_t imm){return ((uint32_t)op<<26)|((uint32_t)rs<<21)|((uint32_t)rt<<16)|((uint16_t)imm);}
static uint32_t J(int op,uint32_t target){return ((uint32_t)op<<26)|((target>>2)&0x03ffffffu);}

static int tokenize(char *s, char *t[], int max) {
    int n=0;
    for (char *p=s; *p && n<max;) {
        while (*p && (isspace((unsigned char)*p)||*p==','||*p=='('||*p==')')) ++p;
        if (!*p) break;
        t[n++]=p;
        while (*p && !(isspace((unsigned char)*p)||*p==','||*p=='('||*p==')')) ++p;
        if (*p) *p++=0;
    }
    return n;
}

static uint32_t encode(char *text, uint32_t pc) {
    char *t[8]; int n=tokenize(text,t,8); if (!n) return 0;
    #define EQ(x) (!strcmp(t[0],x))
    if (EQ("nop")) return 0;
    if (EQ("add")||EQ("addu")||EQ("sub")||EQ("subu")||EQ("and")||EQ("or")||EQ("xor")||EQ("slt")||EQ("sltu")) {
        if(n!=4) goto bad;
        int fn=EQ("add")?0x20:EQ("addu")?0x21:EQ("sub")?0x22:EQ("subu")?0x23:EQ("and")?0x24:EQ("or")?0x25:EQ("xor")?0x26:EQ("slt")?0x2a:0x2b;
        return R(regnum(t[2]),regnum(t[3]),regnum(t[1]),0,fn);
    }
    if (EQ("sll")||EQ("srl")||EQ("sra")) { if(n!=4) goto bad;
        int fn=EQ("sll")?0:EQ("srl")?2:3; return R(0,regnum(t[2]),regnum(t[1]),number(t[3])&31,fn); }
    if (EQ("jr")) { if(n!=2) goto bad; return R(regnum(t[1]),0,0,0,8); }
    if (EQ("addi")||EQ("addiu")||EQ("slti")||EQ("andi")||EQ("ori")||EQ("xori")) {
        if(n!=4) goto bad;
        int op=EQ("addi")?8:EQ("addiu")?9:EQ("slti")?10:EQ("andi")?12:EQ("ori")?13:14;
        return I(op,regnum(t[2]),regnum(t[1]),number(t[3]));
    }
    if (EQ("lui")) { if(n!=3) goto bad; return I(15,0,regnum(t[1]),number(t[2])); }
    if (EQ("lw")||EQ("sw")) { if(n!=4) goto bad; return I(EQ("lw")?0x23:0x2b,regnum(t[3]),regnum(t[1]),number(t[2])); }
    if (EQ("beq")||EQ("bne")) {
        if(n!=4) goto bad;
        uint32_t target; int32_t off;
        if(find_label(t[3],&target)) off=((int32_t)target-(int32_t)(pc+4))/4; else off=number(t[3]);
        return I(EQ("beq")?4:5,regnum(t[1]),regnum(t[2]),off);
    }
    if (EQ("j")||EQ("jal")) {
        if(n!=2) goto bad;
        uint32_t target;
        if(!find_label(t[1],&target)) target=(uint32_t)number(t[1]);
        return J(EQ("j")?2:3,target);
    }
    fprintf(stderr,"unknown opcode at PC 0x%08x: %s\n",pc,t[0]); exit(2);
bad:
    fprintf(stderr,"bad operand count/syntax at PC 0x%08x\n",pc); exit(2);
}

int main(int argc,char **argv){
    if(argc<3){fprintf(stderr,"usage: %s input.asm output.hex\n",argv[0]);return 1;}
    FILE *f=fopen(argv[1],"r"); if(!f){perror(argv[1]);return 1;}
    char buf[1024]; uint32_t pc=0;
    while(fgets(buf,sizeof(buf),f)){
        if(nlines>=MAX_LINES){fprintf(stderr,"too many lines\n");return 1;}
        lines[nlines++]=strdup(buf);
        char temp[1024]; strcpy(temp,buf); strip_comment(temp); char *s=trim(temp); if(!*s) continue;
        char *c=strchr(s,':');
        if(c){ *c=0; char *name=trim(s); if(nlabels>=MAX_LABELS)return 1; strncpy(labels[nlabels].name,name,MAX_NAME-1); labels[nlabels].pc=pc; nlabels++; s=trim(c+1); if(!*s)continue; }
        pc+=4;
    }
    fclose(f);
    FILE *o=fopen(argv[2],"w"); if(!o){perror(argv[2]);return 1;}
    pc=0;
    for(int i=0;i<nlines;i++){
        char temp[1024]; strncpy(temp,lines[i],sizeof(temp)-1); temp[sizeof(temp)-1]=0; strip_comment(temp); char *s=trim(temp); if(!*s)continue;
        char *c=strchr(s,':'); if(c){ s=trim(c+1); if(!*s)continue; }
        uint32_t code=encode(s,pc); fprintf(o,"%08x\n",code); pc+=4;
    }
    fclose(o);
    for(int i=0;i<nlines;i++)free(lines[i]);
    return 0;
}
