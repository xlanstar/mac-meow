/* smcprobe：拆解 Rosetta 處理「程式碼與頻繁寫入的變數同頁」（SMC）的成本，找出可從 Wine／系統端調整的因素。
 * x86_64 程式，在 Rosetta 下反覆「寫變數、呼叫程式碼」，回報每秒迴圈數、每次迴圈的 page fault／Mach 訊息／
 * context switch，以及 Rosetta exceptionserver 執行緒每次迴圈用掉的 CPU。
 *
 * 用法：smcprobe <測試> [參數]
 *   offset <hex>     變數相對「程式碼所在 16 KB 頁」開頭的位移（可為負，程式碼在 0xc80）：量測偵測粒度
 *   blocks <n>       每次寫入後呼叫同頁 n 個不同的程式碼區塊（n ≤ 60）：重新翻譯成本是否與區塊數成正比
 *   size <n>         同頁單一區塊含 n 個指令（n ≤ 480）：重新翻譯成本是否與區塊大小成正比
 *   other <n>        同頁只有小區塊，另一頁有 n 個指令的區塊每次也執行：失效是否波及其他頁
 *   writes <k>       每次呼叫前寫 k 次：只有第一次寫入要付費嗎
 *   calls <k>        每次寫入後呼叫 k 次
 *   samebytes        寫入程式碼本身但值不變：Rosetta 是否比對內容
 *   modbytes         真正改寫程式碼（立即值），並驗證結果
 *   timeline <秒>    每秒輸出一次速率：Rosetta 是否隨時間調適
 *   map <方式>       配置方式（變數 0x6a0）：anon｜jit｜mprot｜fixed｜machvm｜fileprot｜noreserve｜shared｜shm
 *   stages <方式>    以該配置方式逐步執行「執行 → 寫入 → 再執行」並印出進度：找出在哪一步失敗
 *   thread           另一執行緒持續寫變數、主執行緒持續呼叫：寫入者不是執行者時的成本
 * 環境變數 SMC_QOS=ui|in|ut|bg：先設定主執行緒 QoS（預設不設定）。SMC_SECS：量測秒數（預設 1）。
 * SMC_IDLE=n／SMC_BUSY=n：另開 n 條閒置（sleep）／忙碌（在別的頁空轉）執行緒，模擬 Wine 程序的多執行緒（遊戲約 40 條）。
 * SMC_WARM=n：先在另外 n 個 4 KB 頁各翻譯 16 個區塊，模擬遊戲龐大的已翻譯程式碼（翻譯快取大小是否影響每次成本）。 */
#include <fcntl.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

#define REGION 0x20000    /* 配置 128 KB，從中取 64 KB 對齊 */
#define CODE_PAGE 0x4000  /* 程式碼所在 16 KB 頁相對對齊後起點的位移 */
#define CODE_OFFSET 0xc80 /* 程式碼在頁內的位移（同 smc-same-page） */
#define BLOCK_BASE 0x100  /* blocks／size 測試的程式碼起點（頁內） */
#define BLOCK_STEP 0x40
#define BATCH 100

static const int RWX = PROT_READ | PROT_WRITE | PROT_EXEC;
typedef uint64_t (*fn_t)(uint64_t);

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

/* ---------- 計數 ---------- */
struct counters {
    double t;
    long faults, csw;
    long msg_sent, msg_recv;
    double exc_cpu; /* exceptionserver 執行緒 CPU 秒數 */
    int exc_pri, exc_curpri;
};

static void read_counters(struct counters *c) {
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
    c->faults = ru.ru_minflt + ru.ru_majflt;
    c->csw = ru.ru_nvcsw + ru.ru_nivcsw;
    task_events_info_data_t ev;
    mach_msg_type_number_t n = TASK_EVENTS_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_EVENTS_INFO, (task_info_t)&ev, &n) == KERN_SUCCESS) {
        c->msg_sent = ev.messages_sent;
        c->msg_recv = ev.messages_received;
    }
    c->exc_cpu = 0;
    c->exc_pri = c->exc_curpri = -1;
    thread_act_array_t list;
    mach_msg_type_number_t count;
    if (task_threads(mach_task_self(), &list, &count) == KERN_SUCCESS) {
        for (mach_msg_type_number_t i = 0; i < count; i++) {
            thread_extended_info_data_t xi;
            mach_msg_type_number_t xn = THREAD_EXTENDED_INFO_COUNT;
            if (thread_info(list[i], THREAD_EXTENDED_INFO, (thread_info_t)&xi, &xn) == KERN_SUCCESS &&
                strstr(xi.pth_name, "exceptionserver")) {
                c->exc_cpu += (xi.pth_user_time + xi.pth_system_time) / 1e9;
                c->exc_pri = xi.pth_priority;
                c->exc_curpri = xi.pth_curpri;
            }
            mach_port_deallocate(mach_task_self(), list[i]);
        }
        vm_deallocate(mach_task_self(), (vm_address_t)list, count * sizeof(thread_act_t));
    }
    c->t = now();
}

static void report(const char *label, const struct counters *a, const struct counters *b, uint64_t iters) {
    double dt = b->t - a->t, n = (double)iters;
    printf("%-30s %10.0f it/s %8.2f us/it  fault/it %.2f  msg/it %.2f  csw/it %.2f  excsrv %.1f us/it (%.0f%%) pri %d/%d\n", label,
           n / dt, dt * 1e6 / n, (b->faults - a->faults) / n, (b->msg_recv - a->msg_recv) / n, (b->csw - a->csw) / n,
           (b->exc_cpu - a->exc_cpu) * 1e6 / n, (b->exc_cpu - a->exc_cpu) * 100 / dt, b->exc_pri, b->exc_curpri);
}

static double secs(void) {
    const char *s = getenv("SMC_SECS");
    return s ? atof(s) : 1.0;
}

/* ---------- 配置 ---------- */
static uint8_t *align64k(uint8_t *p) { return (uint8_t *)(((uintptr_t)p + 0xffff) & ~(uintptr_t)0xffff); }

static uint8_t *map_region(const char *kind) {
    uint8_t *p = MAP_FAILED;
    if (!strcmp(kind, "anon")) {
        p = mmap(0, REGION, RWX, MAP_PRIVATE | MAP_ANON, -1, 0);
    } else if (!strcmp(kind, "jit")) {
        p = mmap(0, REGION, RWX, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    } else if (!strcmp(kind, "mprot")) { /* 先 RW 再 mprotect 成 RWX（Wine NtProtectVirtualMemory 的路徑） */
        p = mmap(0, REGION, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (p != MAP_FAILED && mprotect(p, REGION, RWX)) p = MAP_FAILED;
    } else if (!strcmp(kind, "fixed")) { /* 先保留 PROT_NONE，再以 MAP_FIXED 覆蓋（Wine 預留位址空間的方式） */
        uint8_t *r = mmap(0, REGION, PROT_NONE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
        if (r != MAP_FAILED) p = mmap(r, REGION, RWX, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
    } else if (!strcmp(kind, "noreserve")) { /* 保留 PROT_NONE 後 mprotect 成 RWX（Wine 對已保留範圍 commit 的方式之一） */
        p = mmap(0, REGION, PROT_NONE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
        if (p != MAP_FAILED && mprotect(p, REGION, RWX)) p = MAP_FAILED;
    } else if (!strcmp(kind, "shared")) { /* 匿名共享 RWX */
        p = mmap(0, REGION, RWX, MAP_SHARED | MAP_ANON, -1, 0);
    } else if (!strcmp(kind, "shm")) { /* shm_open 共享 RWX（smc-same-page 的 smctest2 1；Wine 的 section 也用共享映射） */
        int fd = shm_open("/smcprobe", O_CREAT | O_RDWR, 0600);
        if (fd >= 0) {
            shm_unlink("/smcprobe");
            if (ftruncate(fd, REGION) == 0) p = mmap(0, REGION, RWX, MAP_SHARED, fd, 0);
            close(fd);
        }
    } else if (!strcmp(kind, "machvm")) {
        mach_vm_address_t a = 0;
        if (mach_vm_allocate(mach_task_self(), &a, REGION, VM_FLAGS_ANYWHERE) == KERN_SUCCESS &&
            mach_vm_protect(mach_task_self(), a, REGION, FALSE, VM_PROT_ALL) == KERN_SUCCESS)
            p = (uint8_t *)a;
    } else if (!strcmp(kind, "fileprot")) { /* 檔案私有映射（唯讀）後 mprotect 成 RWX（Wine 映射 PE 區段的方式） */
        char path[] = "/tmp/smcprobeXXXXXX";
        int fd = mkstemp(path);
        if (fd >= 0) {
            unlink(path);
            if (ftruncate(fd, REGION) == 0) p = mmap(0, REGION, PROT_READ, MAP_PRIVATE, fd, 0);
            if (p != MAP_FAILED && mprotect(p, REGION, RWX)) {
                perror("mprotect");
                p = MAP_FAILED;
            }
            close(fd);
        }
    } else {
        fprintf(stderr, "未知的配置方式：%s\n", kind);
        exit(64);
    }
    if (p == MAP_FAILED) {
        perror(kind);
        exit(1);
    }
    return align64k(p);
}

/* ---------- 程式碼產生 ---------- */
/* mov rax, rdi; add rax, 1 ×n; ret */
static size_t emit_block(uint8_t *at, int n) {
    uint8_t *p = at;
    *p++ = 0x48, *p++ = 0x89, *p++ = 0xf8;
    for (int i = 0; i < n; i++) *p++ = 0x48, *p++ = 0x83, *p++ = 0xc0, *p++ = 0x01;
    *p++ = 0xc3;
    return (size_t)(p - at);
}

/* ---------- 迴圈 ---------- */
/* 每次迴圈：寫 writes 次變數，呼叫 nfn 個函式各 calls 次 */
static void run(const char *label, volatile uint64_t *var, fn_t *fns, int nfn, int writes, int calls) {
    struct counters a, b;
    uint64_t iters = 0, acc = 0;
    double limit = secs();
    for (int i = 0; i < nfn; i++) acc += fns[i](1); /* 先翻譯一次 */
    read_counters(&a);
    double start = a.t;
    do {
        for (int i = 0; i < BATCH; i++) {
            for (int w = 0; w < writes; w++) *var = (uint64_t)i + w;
            for (int f = 0; f < nfn; f++)
                for (int c = 0; c < calls; c++) acc += fns[f]((uint64_t)i);
        }
        iters += BATCH;
    } while (now() - start < limit);
    read_counters(&b);
    report(label, &a, &b, iters);
    if (acc == 42) puts("");
}

static void set_qos(void) {
    const char *q = getenv("SMC_QOS");
    if (!q) return;
    qos_class_t c = !strcmp(q, "ui")   ? QOS_CLASS_USER_INTERACTIVE
                    : !strcmp(q, "in") ? QOS_CLASS_USER_INITIATED
                    : !strcmp(q, "ut") ? QOS_CLASS_UTILITY
                                       : QOS_CLASS_BACKGROUND;
    if (pthread_set_qos_class_self_np(c, 0)) perror("qos");
}

static volatile int thread_stop;
static void *idle_thread(void *arg) {
    (void)arg;
    for (;;) sleep(100);
    return 0;
}
static void *busy_thread(void *arg) {
    volatile uint64_t *x = arg;
    while (!thread_stop) (*x)++;
    return 0;
}
static void spawn_threads(void) {
    static uint64_t counters[64][8];
    pthread_t th;
    int idle = getenv("SMC_IDLE") ? atoi(getenv("SMC_IDLE")) : 0, busy = getenv("SMC_BUSY") ? atoi(getenv("SMC_BUSY")) : 0;
    for (int i = 0; i < idle; i++) pthread_create(&th, 0, idle_thread, 0);
    for (int i = 0; i < busy && i < 64; i++) pthread_create(&th, 0, busy_thread, counters[i]);
}
static void *writer(void *arg) {
    volatile uint64_t *var = arg;
    uint64_t i = 0;
    while (!thread_stop) *var = i++;
    return (void *)(uintptr_t)i;
}

static void warm_up(void) {
    long n = getenv("SMC_WARM") ? atol(getenv("SMC_WARM")) : 0;
    if (n <= 0) return;
    uint8_t *p = mmap(0, (size_t)n * 0x1000, RWX, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) {
        perror("warm");
        exit(1);
    }
    uint64_t acc = 0;
    for (long i = 0; i < n; i++)
        for (int b = 0; b < 16; b++) {
            emit_block(p + i * 0x1000 + b * 0x100, 8);
            acc += ((fn_t)(p + i * 0x1000 + b * 0x100))((uint64_t)b);
        }
    if (acc == 42) puts("");
}

static int usage(void) {
    fprintf(stderr, "用法：smcprobe offset <hex>|blocks <n>|size <n>|other <n>|writes <k>|calls <k>|samebytes|modbytes|"
                    "timeline <秒>|map <方式>|thread（見原始碼開頭）\n");
    return 64;
}

int main(int argc, char **argv) {
    setvbuf(stdout, 0, _IONBF, 0);
    if (argc < 2) return usage();
    set_qos();
    spawn_threads();
    warm_up();
    const char *test = argv[1];
    long arg = argc > 2 ? strtol(argv[2], 0, 0) : 0;
    uint8_t *base = map_region(!strcmp(test, "map") && argc > 2 ? argv[2] : "anon");
    uint8_t *page = base + CODE_PAGE;
    char label[64];
    fn_t fns[64];

    if (!strcmp(test, "offset") && argc > 2) {
        emit_block(page + CODE_OFFSET, 0);
        fns[0] = (fn_t)(page + CODE_OFFSET);
        snprintf(label, sizeof label, "var @ %s%#lx", arg < 0 ? "-" : "+", labs(arg));
        run(label, (uint64_t *)(page + arg), fns, 1, 1, 1);
    } else if (!strcmp(test, "blocks") && arg > 0 && arg <= 60) {
        for (int i = 0; i < arg; i++) {
            emit_block(page + BLOCK_BASE + i * BLOCK_STEP, 4);
            fns[i] = (fn_t)(page + BLOCK_BASE + i * BLOCK_STEP);
        }
        snprintf(label, sizeof label, "blocks %ld", arg);
        run(label, (uint64_t *)(page + 0x6a0 + 0x400), fns, (int)arg, 1, 1);
    } else if (!strcmp(test, "size") && arg >= 0 && arg <= 480) {
        emit_block(page + BLOCK_BASE, (int)arg);
        fns[0] = (fn_t)(page + BLOCK_BASE);
        snprintf(label, sizeof label, "size %ld insns", arg);
        run(label, (uint64_t *)(page + 0xff0), fns, 1, 1, 1);
    } else if (!strcmp(test, "other") && arg >= 0 && arg <= 480) {
        emit_block(page + CODE_OFFSET, 0);
        emit_block(page + 0x4000 + BLOCK_BASE, (int)arg);
        fns[0] = (fn_t)(page + CODE_OFFSET);
        fns[1] = (fn_t)(page + 0x4000 + BLOCK_BASE);
        snprintf(label, sizeof label, "other page %ld insns", arg);
        run(label, (uint64_t *)(page + 0x6a0), fns, 2, 1, 1);
    } else if ((!strcmp(test, "writes") || !strcmp(test, "calls")) && arg > 0) {
        emit_block(page + CODE_OFFSET, 0);
        fns[0] = (fn_t)(page + CODE_OFFSET);
        int w = test[0] == 'w' ? (int)arg : 1, c = test[0] == 'c' ? (int)arg : 1;
        snprintf(label, sizeof label, "%d writes, %d calls", w, c);
        run(label, (uint64_t *)(page + 0x6a0), fns, 1, w, c);
    } else if (!strcmp(test, "samebytes")) {
        /* 寫入值與原值相同的程式碼位元組：ret（0xc3）那一格 */
        emit_block(page + CODE_OFFSET, 0);
        fns[0] = (fn_t)(page + CODE_OFFSET);
        volatile uint8_t *b = page + CODE_OFFSET + 3;
        struct counters a, c;
        uint64_t iters = 0, acc = 0;
        acc += fns[0](1);
        read_counters(&a);
        do {
            for (int i = 0; i < BATCH; i++) *b = 0xc3, acc += fns[0](i);
            iters += BATCH;
        } while (now() - a.t < secs());
        read_counters(&c);
        report("write same code byte", &a, &c, iters);
    } else if (!strcmp(test, "modbytes")) {
        /* mov eax, imm32; ret：每次改寫立即值並檢查回傳值，確認 Rosetta 真的重新翻譯 */
        uint8_t *p = page + CODE_OFFSET;
        p[0] = 0xb8, p[5] = 0xc3;
        fns[0] = (fn_t)p;
        volatile uint32_t *imm = (uint32_t *)(p + 1);
        struct counters a, c;
        uint64_t iters = 0, bad = 0;
        read_counters(&a);
        do {
            for (uint32_t i = 0; i < BATCH; i++) {
                *imm = i;
                if ((uint32_t)fns[0](0) != i) bad++;
            }
            iters += BATCH;
        } while (now() - a.t < secs());
        read_counters(&c);
        report("modify code imm", &a, &c, iters);
        printf("  錯誤結果：%llu\n", bad);
    } else if (!strcmp(test, "timeline") && arg > 0) {
        emit_block(page + CODE_OFFSET, 0);
        fns[0] = (fn_t)(page + CODE_OFFSET);
        setenv("SMC_SECS", "1", 1);
        for (long s = 0; s < arg; s++) {
            snprintf(label, sizeof label, "second %ld", s + 1);
            run(label, (uint64_t *)(page + 0x6a0), fns, 1, 1, 1);
        }
    } else if (!strcmp(test, "map") && argc > 2) {
        emit_block(page + CODE_OFFSET, 0);
        fns[0] = (fn_t)(page + CODE_OFFSET);
        snprintf(label, sizeof label, "map %s", argv[2]);
        run(label, (uint64_t *)(page + 0x6a0), fns, 1, 1, 1);
        run("  (control: var other page)", (uint64_t *)(page + 0x2000), fns, 1, 1, 1);
    } else if (!strcmp(test, "stages") && argc > 2) {
        base = map_region(argv[2]);
        page = base + CODE_PAGE;
        emit_block(page + CODE_OFFSET, 0);
        fns[0] = (fn_t)(page + CODE_OFFSET);
        volatile uint64_t *var = (uint64_t *)(page + 0x6a0);
        printf("1 第一次執行：%llu\n", fns[0](1));
        *var = 1;
        printf("2 寫入同頁變數：完成\n");
        printf("3 再次執行：%llu\n", fns[0](2));
        for (int i = 0; i < 1000; i++) *var = (uint64_t)i, fns[0](i);
        printf("4 交替 1000 次：完成\n");
    } else if (!strcmp(test, "thread")) {
        emit_block(page + CODE_OFFSET, 0);
        fns[0] = (fn_t)(page + CODE_OFFSET);
        pthread_t th;
        pthread_create(&th, 0, writer, page + 0x6a0);
        struct counters a, c;
        uint64_t iters = 0, acc = 0;
        read_counters(&a);
        do {
            for (int i = 0; i < BATCH; i++) acc += fns[0](i);
            iters += BATCH;
        } while (now() - a.t < secs());
        read_counters(&c);
        thread_stop = 1;
        void *w;
        pthread_join(th, &w);
        report("exec while other thread writes", &a, &c, iters);
        if (acc == 42) puts("");
        double dt = c.t - a.t;
        printf("  寫入者 %.0f writes/s；整個程序 fault %.0f/s、Mach 訊息 %.0f/s、context switch %.0f/s\n", (double)(uintptr_t)w / dt,
               (c.faults - a.faults) / dt, (c.msg_recv - a.msg_recv) / dt, (c.csw - a.csw) / dt);
    } else {
        return usage();
    }
    return 0;
}
