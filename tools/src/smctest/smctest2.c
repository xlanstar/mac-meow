/* smctest2 <0|1|2>：同 smctest，比較不同映射方式下「程式碼與頻繁寫入的變數同頁」的成本。
 * 0 = 匿名 RWX（無 MAP_JIT）、1 = 共享記憶體 RWX、2 = 檔案私有映射 RWX。 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
static double bench(uint8_t *page, const char *label) {
    volatile uint64_t *var = (uint64_t *)(page + 0x6a0);
    static const uint8_t code[] = { 0x48, 0x89, 0xf8, 0xc3 };
    memcpy(page + 0xc80, code, sizeof code);
    uint64_t (*fn)(uint64_t) = (void *)(page + 0xc80);
    struct timespec s, n; clock_gettime(CLOCK_MONOTONIC, &s); uint64_t it = 0, acc = 0; double t;
    do { for (int i = 0; i < 200; i++) { *var = 1; acc += fn(i); *var = 0; } it += 200;
         clock_gettime(CLOCK_MONOTONIC, &n); t = (n.tv_sec - s.tv_sec) + (n.tv_nsec - s.tv_nsec) / 1e9; } while (t < 1 && it < 2000000);
    printf("%-28s %12.0f calls/s\n", label, it / t); return it / t;
}
int main(int argc,char**argv) {
    uint8_t *p; setvbuf(stdout,0,_IONBF,0);
    if (argc < 2) { fprintf(stderr, "usage: %s 0|1|2\n", argv[0]); return 2; }
    int m=atoi(argv[1]);
    if(m==0){p = mmap(0, 0x4000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANON, -1, 0); bench(p, "anon RWX (no MAP_JIT)");}
    if(m==1){int fd = shm_open("/smctest", O_CREAT|O_RDWR, 0600); shm_unlink("/smctest"); ftruncate(fd, 0x4000);
    p = mmap(0, 0x4000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_SHARED, fd, 0); bench(p, "shared RWX");}
    if(m==2){char tmpl[] = "/tmp/smcXXXXXX"; int f2 = mkstemp(tmpl); unlink(tmpl); ftruncate(f2, 0x4000);
    p = mmap(0, 0x4000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE, f2, 0); bench(p, "file private RWX");}
    return 0;
}
