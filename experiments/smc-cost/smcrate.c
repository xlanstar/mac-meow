/* smcrate：唯讀觀察執行中（Rosetta 轉譯）程序的 SMC 速率，供遊戲內設定、地圖、更新率的 A/B 比較。
 * 只用 proc_pidinfo（不取 task port、不暫停、不讀寫目標記憶體），同使用者的程序即可，不需要 sign-debug。
 *
 * 用法：smcrate <pid> [秒數（預設 10）] [間隔 ms（預設 1000）]
 * 每個間隔輸出一行：page fault/s、推估 SMC 週期/s（= fault ÷ FAULTS_PER_CYCLE）、
 * 程序收到的 Mach 訊息/s（smcprobe：每個 SMC 週期約「之後執行到的失效區塊數」則；遊戲另有其他訊息）、
 * Rosetta exceptionserver 與本間隔 CPU 最多的執行緒（推定主執行緒）的 CPU% 與目前優先權；最後輸出平均。
 * FAULTS_PER_CYCLE 來自 smcprobe（一次「寫入 → 執行」約 2.1 次 page fault）；遊戲中另有其他 fault，只能當上限。 */
#include <libproc.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <time.h>
#include <unistd.h>

#define MAX_THREADS 2048
#define FAULTS_PER_CYCLE 2.1

struct tcpu {
    uint64_t tid, cpu;
};

struct snap {
    double t;
    uint64_t faults, msgs;
    uint64_t exc_cpu;   /* exceptionserver 累計 CPU ns */
    uint64_t top_delta; /* 與前一次相比 CPU 增量最多的執行緒的增量 ns */
    uint64_t top_tid;
    int top_pri, exc_pri, nthreads;
    struct tcpu th[MAX_THREADS];
    int nth;
};

static uint64_t tids[MAX_THREADS];

static uint64_t find_cpu(const struct snap *s, uint64_t tid) {
    for (int i = 0; i < s->nth; i++)
        if (s->th[i].tid == tid) return s->th[i].cpu;
    return UINT64_MAX;
}

/* prev 可為 NULL（第一次） */
static int take(int pid, const struct snap *prev, struct snap *s) {
    struct proc_taskinfo ti;
    if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, sizeof ti) != sizeof ti) return -1;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    s->t = ts.tv_sec + ts.tv_nsec / 1e9;
    s->faults = ti.pti_faults;
    s->msgs = ti.pti_messages_received;
    int n = proc_pidinfo(pid, PROC_PIDLISTTHREADS, 0, tids, sizeof tids) / (int)sizeof(uint64_t);
    s->nthreads = n;
    s->exc_cpu = s->top_delta = s->top_tid = 0;
    s->top_pri = s->exc_pri = -1;
    s->nth = 0;
    for (int i = 0; i < n && s->nth < MAX_THREADS; i++) {
        struct proc_threadinfo th;
        if (proc_pidinfo(pid, PROC_PIDTHREADINFO, tids[i], &th, sizeof th) != sizeof th) continue;
        uint64_t cpu = th.pth_user_time + th.pth_system_time;
        s->th[s->nth].tid = tids[i];
        s->th[s->nth++].cpu = cpu;
        if (strstr(th.pth_name, "exceptionserver")) {
            s->exc_cpu = cpu;
            s->exc_pri = th.pth_curpri;
            continue;
        }
        uint64_t p = prev ? find_cpu(prev, tids[i]) : UINT64_MAX;
        uint64_t d = p == UINT64_MAX || cpu < p ? 0 : cpu - p;
        if (d >= s->top_delta) s->top_delta = d, s->top_tid = tids[i], s->top_pri = th.pth_curpri;
    }
    return 0;
}

static struct snap snaps[3];

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "用法：smcrate <pid> [秒數] [間隔 ms]\n");
        return 64;
    }
    int pid = atoi(argv[1]);
    double total = argc > 2 ? atof(argv[2]) : 10;
    int interval = argc > 3 ? atoi(argv[3]) : 1000;
    struct snap *first = &snaps[0], *a = &snaps[1], *b = &snaps[2], *tmp;
    if (take(pid, NULL, first)) {
        perror("proc_pidinfo");
        return 1;
    }
    *a = *first;
    double sum_top = 0;
    int rows = 0;
    printf("%6s %9s %9s %9s %8s %8s %4s %4s %5s\n", "t(s)", "fault/s", "cycle/s", "msg/s", "excsrv%", "main%", "pri", "xpri", "nthr");
    for (;;) {
        usleep(interval * 1000);
        if (take(pid, a, b)) break;
        double dt = b->t - a->t, f = (b->faults - a->faults) / dt;
        double top = b->top_delta / 1e9 / dt * 100;
        printf("%6.1f %9.0f %9.0f %9.0f %8.1f %8.0f %4d %4d %5d\n", b->t - first->t, f, f / FAULTS_PER_CYCLE, (b->msgs - a->msgs) / dt,
               (b->exc_cpu - a->exc_cpu) / 1e9 / dt * 100, top, b->top_pri, b->exc_pri, b->nthreads);
        sum_top += top;
        rows++;
        tmp = a, a = b, b = tmp;
        if (a->t - first->t >= total) break;
    }
    if (rows) {
        double dt = a->t - first->t, f = (a->faults - first->faults) / dt;
        printf("平均：fault %.0f/s、SMC 週期約 %.0f/s（上限）、excsrv %.1f%%、主執行緒約 %.0f%%\n", f, f / FAULTS_PER_CYCLE,
               (a->exc_cpu - first->exc_cpu) / 1e9 / dt * 100, sum_top / rows);
    }
    return 0;
}
