/* 重現 Themida VM 的情況：同一個 4K 頁裡有被執行的程式碼與每次都會寫入的變數。量測每秒迴圈數，比較 Rosetta 設定。 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <stdint.h>
int main(int argc, char **argv) {
    int sep = argc > 1 && !strcmp(argv[1], "sep");   /* sep：變數放在另一頁（對照組） */
    uint8_t *page = mmap(0, 0x4000, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (page == MAP_FAILED) { perror("mmap"); return 1; }
    volatile uint64_t *var = (uint64_t *)(page + (sep ? 0x2000 : 0x6a0));
    /* 函式：mov rax, rdi; ret  放在 0xc80 */
    static const uint8_t code[] = { 0x48, 0x89, 0xf8, 0xc3 };
    memcpy(page + 0xc80, code, sizeof code);
    uint64_t (*fn)(uint64_t) = (void *)(page + 0xc80);
    struct timespec s, n; clock_gettime(CLOCK_MONOTONIC, &s);
    uint64_t iters = 0, acc = 0;
    for (;;) {
        for (int i = 0; i < 1000; i++) { *var = 0x7ffc000003470804ULL; acc += fn(i); *var = 0; }
        iters += 1000;
        clock_gettime(CLOCK_MONOTONIC, &n);
        double t = (n.tv_sec - s.tv_sec) + (n.tv_nsec - s.tv_nsec) / 1e9;
        if (t > 2) { printf("%s: %.0f calls/s (acc=%llu)\n", sep ? "separate page" : "same page", iters / t, acc); break; }
    }
    return 0;
}
