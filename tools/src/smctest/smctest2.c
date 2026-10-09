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

#define PAGE_SIZE_RWX 0x4000
#define CODE_OFFSET 0xc80
#define VAR_OFFSET 0x6a0
#define BATCH 200
#define MAX_ITERS 2000000

/* mov rax, rdi; ret */
static const uint8_t code[] = { 0x48, 0x89, 0xf8, 0xc3 };
static const int RWX = PROT_READ | PROT_WRITE | PROT_EXEC;

static double elapsed(const struct timespec *start) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - start->tv_sec) + (now.tv_nsec - start->tv_nsec) / 1e9;
}

/* 至少 1 秒或 MAX_ITERS 次呼叫 */
static void bench(uint8_t *page, const char *label) {
    volatile uint64_t *var = (uint64_t *)(page + VAR_OFFSET);
    memcpy(page + CODE_OFFSET, code, sizeof code);
    uint64_t (*fn)(uint64_t) = (void *)(page + CODE_OFFSET);
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
    } while (t < 1 && iters < MAX_ITERS);
    printf("%-28s %12.0f calls/s\n", label, iters / t);
}

static uint8_t *map_shared(void) {
    int fd = shm_open("/smctest", O_CREAT | O_RDWR, 0600);
    if (fd < 0) return MAP_FAILED;
    shm_unlink("/smctest");
    ftruncate(fd, PAGE_SIZE_RWX);
    return mmap(0, PAGE_SIZE_RWX, RWX, MAP_SHARED, fd, 0);
}

static uint8_t *map_file(void) {
    char path[] = "/tmp/smcXXXXXX";
    int fd = mkstemp(path);
    if (fd < 0) return MAP_FAILED;
    unlink(path);
    ftruncate(fd, PAGE_SIZE_RWX);
    return mmap(0, PAGE_SIZE_RWX, RWX, MAP_PRIVATE, fd, 0);
}

int main(int argc, char **argv) {
    static const char *labels[] = { "anon RWX (no MAP_JIT)", "shared RWX", "file private RWX" };
    setvbuf(stdout, 0, _IONBF, 0);
    if (argc < 2) {
        fprintf(stderr, "usage: %s 0|1|2\n", argv[0]);
        return 2;
    }
    int mode = atoi(argv[1]);
    uint8_t *page;
    switch (mode) {
    case 0:
        page = mmap(0, PAGE_SIZE_RWX, RWX, MAP_PRIVATE | MAP_ANON, -1, 0);
        break;
    case 1:
        page = map_shared();
        break;
    case 2:
        page = map_file();
        break;
    default:
        return 0;
    }
    if (page == MAP_FAILED) {
        perror("mmap");
        return 1;
    }
    bench(page, labels[mode]);
    return 0;
}
