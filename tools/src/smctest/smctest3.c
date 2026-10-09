/* smctest3：程式碼放在不可執行（RW）頁時，Rosetta 是否強制 NX；若可執行，量測同頁寫入成本。 */
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <signal.h>
#include <stdint.h>
#include <time.h>
#include <setjmp.h>
static sigjmp_buf jb;
static void h(int s){ siglongjmp(jb,1); }
int main(void){
    setvbuf(stdout,0,_IONBF,0);
    signal(SIGSEGV,h); signal(SIGBUS,h);
    uint8_t *p=mmap(0,0x4000,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    static const uint8_t code[]={0x48,0x89,0xf8,0xc3}; memcpy(p+0xc80,code,4);
    uint64_t(*fn)(uint64_t)=(void*)(p+0xc80);
    if(sigsetjmp(jb,1)){ printf("RW (no exec): execution faulted -> Rosetta enforces NX\n"); return 0; }
    uint64_t r=fn(42); printf("RW (no exec): executed, result=%llu\n",r);
    volatile uint64_t *var=(uint64_t*)(p+0x6a0); struct timespec s,n; clock_gettime(CLOCK_MONOTONIC,&s); uint64_t it=0,acc=0; double t;
    do{ for(int i=0;i<200;i++){*var=1;acc+=fn(i);*var=0;} it+=200; clock_gettime(CLOCK_MONOTONIC,&n); t=(n.tv_sec-s.tv_sec)+(n.tv_nsec-s.tv_nsec)/1e9;}while(t<1);
    printf("RW no-exec same page: %.0f calls/s\n",it/t); return 0; }
