/* smctest [sep]：重現 Themida VM 的情況：同一個 4K 頁裡有被執行的程式碼與每次都會寫入的變數。
 * 量測每秒呼叫數，比較 Rosetta 設定。sep：變數放在另一頁（對照組）。 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <stdint.h>

#define CODE_OFFSET 0xc80
#define BATCH 1000
#define SECONDS 2

/* mov rax, rdi; ret */
static const uint8_t code[] = { 0x48, 0x89, 0xf8, 0xc3 };

static double elapsed(const struct timespec *start) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - start->tv_sec) + (now.tv_nsec - start->tv_nsec) / 1e9;
}

int main(int argc, char **argv) {
    int sep = argc > 1 && !strcmp(argv[1], "sep");
    uint8_t *page = mmap(0, 0x4000, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (page == MAP_FAILED) {
        perror("mmap");
        return 1;
    }
    volatile uint64_t *var = (uint64_t *)(page + (sep ? 0x2000 : 0x6a0));
    memcpy(page + CODE_OFFSET, code, sizeof code);
    uint64_t (*fn)(uint64_t) = (void *)(page + CODE_OFFSET);

    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    uint64_t iters = 0, acc = 0;
    double t;
    do {
        for (int i = 0; i < BATCH; i++) {
            *var = 0x7ffc000003470804ULL;
            acc += fn(i);
            *var = 0;
        }
        iters += BATCH;
        t = elapsed(&start);
    } while (t <= SECONDS);
    printf("%s: %.0f calls/s (acc=%llu)\n", sep ? "separate page" : "same page", iters / t, acc);
    return 0;
}
