/* smctest3：程式碼放在不可執行（RW）頁時，Rosetta 是否強制 NX；若可執行，量測同頁寫入成本。 */
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <signal.h>
#include <stdint.h>
#include <time.h>
#include <setjmp.h>

#define CODE_OFFSET 0xc80
#define VAR_OFFSET 0x6a0
#define BATCH 200

/* mov rax, rdi; ret */
static const uint8_t code[] = { 0x48, 0x89, 0xf8, 0xc3 };
static sigjmp_buf fault_jump;

static void on_fault(int sig) {
    (void)sig;
    siglongjmp(fault_jump, 1);
}

static double elapsed(const struct timespec *start) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - start->tv_sec) + (now.tv_nsec - start->tv_nsec) / 1e9;
}

int main(void) {
    setvbuf(stdout, 0, _IONBF, 0);
    signal(SIGSEGV, on_fault);
    signal(SIGBUS, on_fault);
    uint8_t *page = mmap(0, 0x4000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page == MAP_FAILED) {
        perror("mmap");
        return 1;
    }
    memcpy(page + CODE_OFFSET, code, sizeof code);
    uint64_t (*fn)(uint64_t) = (void *)(page + CODE_OFFSET);
    if (sigsetjmp(fault_jump, 1)) {
        printf("RW (no exec): execution faulted -> Rosetta enforces NX\n");
        return 0;
    }
    printf("RW (no exec): executed, result=%llu\n", fn(42));

    volatile uint64_t *var = (uint64_t *)(page + VAR_OFFSET);
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    uint64_t iters = 0;
    double t;
    do {
        for (int i = 0; i < BATCH; i++) {
            *var = 1;
            fn(i);
            *var = 0;
        }
        iters += BATCH;
        t = elapsed(&start);
    } while (t < 1);
    printf("RW no-exec same page: %.0f calls/s\n", iters / t);
    return 0;
}
