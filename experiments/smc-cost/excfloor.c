/* excfloor：原生 arm64 量測 Rosetta 處理 SMC 時「作業系統部分」的下限：
 * mprotect 唯讀（等同 Rosetta 翻譯後重新保護）→ 寫入 → EXC_BAD_ACCESS 以 Mach 訊息送到處理執行緒
 * → 處理執行緒 mprotect 可寫並回覆 → 寫入完成。不含 Rosetta 讓翻譯失效與重新翻譯的成本。
 *
 * 用法：excfloor [秒數（預設 1）]
 * 另輸出兩個對照：只做 mprotect 來回（不觸發例外）的成本；改由同一執行緒的 SIGBUS 訊號處理（沒有跨執行緒
 * Mach 訊息，FEX 等在 Wine 內處理存取違規的翻譯器走這類路徑）的成本。訊號對照會先清除 task 例外 port（見 noexc.c）。 */
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/* mach_exc.defs 產生的訊息格式（EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES；MIG 以 4 位元組對齊） */
#pragma pack(push, 4)
typedef struct {
    mach_msg_header_t head;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t thread, task;
    NDR_record_t ndr;
    exception_type_t exception;
    mach_msg_type_number_t code_count;
    int64_t code[2];
    char pad[512];
} exc_msg_t;

typedef struct {
    mach_msg_header_t head;
    NDR_record_t ndr;
    kern_return_t ret;
} exc_reply_t;
#pragma pack(pop)

static mach_port_t port;
static uint8_t *page;
static size_t pagesz;
static volatile uint64_t handled;

static void on_signal(int sig, siginfo_t *si, void *uc) {
    (void)sig, (void)uc;
    uint8_t *addr = si->si_addr;
    if (addr < page || addr >= page + pagesz) abort();
    mprotect(page, pagesz, PROT_READ | PROT_WRITE);
    handled++;
}

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static void *server(void *arg) {
    (void)arg;
    for (;;) {
        exc_msg_t msg;
        if (mach_msg(&msg.head, MACH_RCV_MSG, 0, sizeof msg, port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL)) continue;
        uint8_t *addr = (uint8_t *)(uintptr_t)msg.code[1];
        kern_return_t ret = KERN_FAILURE;
        if (msg.exception == EXC_BAD_ACCESS && addr >= page && addr < page + pagesz) {
            mprotect(page, pagesz, PROT_READ | PROT_WRITE);
            handled++;
            ret = KERN_SUCCESS;
        }
        mach_port_deallocate(mach_task_self(), msg.thread.name);
        mach_port_deallocate(mach_task_self(), msg.task.name);
        exc_reply_t r = {0};
        r.head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(msg.head.msgh_bits), 0);
        r.head.msgh_remote_port = msg.head.msgh_remote_port;
        r.head.msgh_size = sizeof r;
        r.head.msgh_id = msg.head.msgh_id + 100;
        r.ndr = NDR_record;
        r.ret = ret;
        mach_msg(&r.head, MACH_SEND_MSG, sizeof r, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    }
    return 0;
}

int main(int argc, char **argv) {
    setvbuf(stdout, 0, _IONBF, 0);
    double limit = argc > 1 ? atof(argv[1]) : 1;
    pagesz = (size_t)getpagesize();
    page = mmap(0, pagesz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
    /* 只設定在主執行緒上，不影響其他執行緒與 crash reporter */
    thread_set_exception_ports(mach_thread_self(), EXC_MASK_BAD_ACCESS, port,
                               (exception_behavior_t)(EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES), THREAD_STATE_NONE);
    pthread_t th;
    pthread_create(&th, 0, server, 0);

    volatile uint64_t *var = (uint64_t *)(page + 0x6a0);
    uint64_t n = 0;
    double t0 = now(), t;
    do {
        for (int i = 0; i < 100; i++) {
            mprotect(page, pagesz, PROT_READ);
            *var = (uint64_t)i;
        }
        n += 100;
    } while ((t = now() - t0) < limit);
    printf("page %zu：寫入例外來回 %.2f us/次（處理 %llu 次）\n", pagesz, t * 1e6 / n, handled);

    n = 0;
    t0 = now();
    do {
        for (int i = 0; i < 100; i++) {
            mprotect(page, pagesz, PROT_READ);
            mprotect(page, pagesz, PROT_READ | PROT_WRITE);
            *var = (uint64_t)i;
        }
        n += 100;
    } while ((t = now() - t0) < limit);
    printf("對照：mprotect 唯讀＋可寫兩次 %.2f us/次\n", t * 1e6 / n);

    thread_set_exception_ports(mach_thread_self(), EXC_MASK_BAD_ACCESS, MACH_PORT_NULL, EXCEPTION_DEFAULT, THREAD_STATE_NONE);
    task_set_exception_ports(mach_task_self(), EXC_MASK_BAD_ACCESS, MACH_PORT_NULL, EXCEPTION_DEFAULT, THREAD_STATE_NONE);
    struct sigaction sa = {0};
    sa.sa_sigaction = on_signal;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGBUS, &sa, 0);
    sigaction(SIGSEGV, &sa, 0);
    handled = n = 0;
    t0 = now();
    do {
        for (int i = 0; i < 100; i++) {
            mprotect(page, pagesz, PROT_READ);
            *var = (uint64_t)i;
        }
        n += 100;
    } while ((t = now() - t0) < limit);
    printf("對照：同執行緒訊號處理寫入例外 %.2f us/次（處理 %llu 次）\n", t * 1e6 / n, handled);
    return 0;
}
