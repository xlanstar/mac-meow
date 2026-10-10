/*
 * machsample：以固定間隔連續取樣（Rosetta 轉譯中）程序的執行緒，供 hitchprof.py 找出卡頓（FPS drop）的原因。
 * 與 machstack 相同以 Mach API 讀取暫存器與堆疊，但不暫停程序或執行緒、不在取樣時解析符號，
 * 只記錄原始位址與區段表，符號留給 hitchprof.py 事後解析，因此可以每幾毫秒取樣一次。
 *
 * 用法：machsample <pid> <間隔 ms> <秒數（0 = 直到 SIGINT／SIGTERM）>
 * 需要：目標帶 get-task-allow（或以 root 執行）。
 *
 * 輸出（stdout，一行一筆、空白分隔、位址為不含 0x 的十六進位；hitchprof.py 解析，修改時一併更新）：
 *   H <pid> <間隔 us> <開始 epoch us>
 *   D <載入位址> <__TEXT 大小> <路徑>       x86 dyld 映像（含 shared cache 內的；只輸出新出現的）
 *   M <起點> <終點> <prot> <路徑|->         有檔案的區段與可執行的匿名區段；只輸出新出現的
 *                                           （映像與區段由背景執行緒每 REGION_REFRESH_US 重掃；Wine 程序的
 *                                            區段表很大，一次約 150 ms，放在取樣迴圈裡會讓取樣停頓）
 *   N <pid> <名稱>                          程序名稱（argv[0] 的檔名，第一次看到時）
 *   P <t> <pid> <CPU us>                    同使用者其他程序的累計 CPU（每 PROC_REFRESH_US，只輸出有增加的）
 *   C <t> <faults> <pageins> <cow_faults> <csw> <mach syscalls> <unix syscalls> <msgs sent> <msgs recv> <running threads>
 *                                           目標程序的累計計數（每次取樣）
 *   T <t> <tid> <CPU us> <run_state> <suspend> <名稱|->   執行緒（第一次看到或 CPU／狀態改變時）
 *   S <t> <tid> <s|j> <x16> <原生 pc,lr,fp 鏈...> <x86 堆疊上的程式碼位址...|->
 *                                           堆疊：s = 系統呼叫中（Rosetta 暫存器區塊），j = 執行翻譯碼／Rosetta 本身
 *   E <t> <取樣次數> <落後次數> <平均取樣耗時 us> <最大取樣耗時 us>
 * t 為 epoch 微秒（與 Metal HUD 記錄的本地時間對齊）。
 *
 * 取堆疊的執行緒：自上次取樣後用了 CPU、正在執行、RECENT_US 內用過 CPU，或累計 CPU 最多的前
 * ALWAYS_TOP 條（每幀都會執行的執行緒卡在等待時沒有 CPU 增量，仍要知道它在等什麼）。
 */
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/mach_vm.h>
#include <mach/thread_status.h>
#include <mach/mach_error.h>
#include <libproc.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <time.h>
#include <unistd.h>
#include <mach-o/dyld_images.h>
#include <mach-o/loader.h>

#define MAX_THREADS 1024
#define MAX_REGIONS 65536
#define MAX_PROCS 8192
#define MAX_IMAGES 4096
#define ALWAYS_TOP 3              /* 累計 CPU 最多、每次都取堆疊的執行緒數 */
#define RECENT_US 300000          /* 最近這段時間內用過 CPU 的執行緒，閒置時也取堆疊 */
#define REGION_REFRESH_US 2000000 /* 區段表重掃間隔 */
#define PROC_REFRESH_US 100000    /* 其他程序 CPU 取樣間隔 */
#define NATIVE_DEPTH 6            /* 原生 fp 鏈最多幾層 */
#define X86_SCAN_BYTES 4096       /* 從 x86 rsp 往上掃描的位元組數 */
#define X86_EMIT 40               /* 每個堆疊最多輸出幾個 x86 程式碼位址 */
#define PAC_MASK 0x0000ffffffffffffULL

/* x86 暫存器區塊（Rosetta 系統呼叫時位於 [sp+8]，見 machstack.c）：返回位址後依序為
 * rax rcx rdx rbx rsp rbp rsi rdi r8-r15 rflags */
enum { BLK_LR, BLK_RAX, BLK_RCX, BLK_RDX, BLK_RBX, BLK_RSP, BLK_RBP, BLK_WORDS = 19 };

static int pid;
static mach_port_t task;
static volatile sig_atomic_t stop;
static mach_timebase_info_data_t timebase;

struct tinfo {
    thread_act_t port; /* 保留一個 send right，讓同一執行緒的 port 名稱不變 */
    uint64_t tid, cpu_first, cpu_last, delta, active_t;
    int state, suspend, seen;
};
static struct tinfo threads[MAX_THREADS];
static int nthreads;

struct range {
    uint64_t start, end;
    int prot;
    uint32_t hash;
};
/* exec_ranges：取樣迴圈使用。其餘（scan_*）只由重掃的執行緒使用，結果放在 staged_* 再由取樣迴圈取用。 */
static struct range exec_ranges[MAX_REGIONS], seen_regions[MAX_REGIONS], next_regions[MAX_REGIONS], images[MAX_IMAGES];
static struct range scan_exec[MAX_REGIONS], staged_exec[MAX_REGIONS];
static int nexec, nseen, nimages, nscan_exec, nstaged;
static FILE *scan_out; /* 重掃產生的 M、D 行 */
static char *staged_text;
static size_t staged_len;
static int staged_ready;
static pthread_mutex_t staged_lock = PTHREAD_MUTEX_INITIALIZER;

struct proc {
    int pid;
    uint64_t cpu;
};
static struct proc procs[MAX_PROCS];
static int nprocs;

static uint64_t now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

static uint64_t mach_to_us(uint64_t t) { return t * timebase.numer / timebase.denom / 1000; }

static int readmem(uint64_t addr, void *buf, size_t len) {
    mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(task, addr, len, (mach_vm_address_t)buf, &got) == KERN_SUCCESS && got == len;
}

/* 從 addr 讀最多 len 位元組，遇到未映射的頁就停；回傳讀到的位元組數 */
static size_t readmem_upto(uint64_t addr, void *buf, size_t len) {
    size_t done = 0;
    while (done < len) {
        uint64_t a = addr + done;
        size_t chunk = vm_page_size - (a & (vm_page_size - 1));
        if (chunk > len - done) chunk = len - done;
        if (!readmem(a, (char *)buf + done, chunk)) break;
        done += chunk;
    }
    return done;
}

static uint32_t hash_str(const char *s) {
    uint32_t h = 2166136261u;
    while (*s) h = (h ^ (uint8_t)*s++) * 16777619u;
    return h;
}

/* ---------- 區段表 ---------- */

static int region_seen(const struct range *r) {
    int lo = 0, hi = nseen - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (seen_regions[mid].start < r->start) lo = mid + 1;
        else if (seen_regions[mid].start > r->start) hi = mid - 1;
        else
            return seen_regions[mid].end == r->end && seen_regions[mid].prot == r->prot && seen_regions[mid].hash == r->hash;
    }
    return 0;
}

static void scan_regions(void) {
    struct proc_regionwithpathinfo ri;
    uint64_t addr = 0;
    int nnext = 0;
    nscan_exec = 0;
    while (nnext < MAX_REGIONS && proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, addr, &ri, sizeof ri) == sizeof ri) {
        uint64_t start = ri.prp_prinfo.pri_address, end = start + ri.prp_prinfo.pri_size;
        int prot = ri.prp_prinfo.pri_protection;
        const char *path = ri.prp_vip.vip_path;
        if (end <= addr) break;
        addr = end;
        if (prot & VM_PROT_EXECUTE) {
            if (nscan_exec && scan_exec[nscan_exec - 1].end == start) scan_exec[nscan_exec - 1].end = end;
            else if (nscan_exec < MAX_REGIONS) scan_exec[nscan_exec++] = (struct range){start, end, prot, 0};
        }
        if (!path[0] && !(prot & VM_PROT_EXECUTE)) continue;
        struct range r = {start, end, prot, hash_str(path)};
        if (!region_seen(&r)) fprintf(scan_out, "M %llx %llx %d %s\n", start, end, prot, path[0] ? path : "-");
        next_regions[nnext++] = r;
    }
    memcpy(seen_regions, next_regions, nnext * sizeof *next_regions);
    nseen = nnext;
}

static int is_exec(uint64_t v) {
    int lo = 0, hi = nexec - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (v < exec_ranges[mid].start) hi = mid - 1;
        else if (v >= exec_ranges[mid].end) lo = mid + 1;
        else return 1;
    }
    return 0;
}

/* 映像 __TEXT 的大小（讀目標記憶體中的 mach header）；讀不到時回傳 0 */
static uint64_t text_size(uint64_t load) {
    struct mach_header_64 mh;
    static char cmds[65536];
    if (!readmem(load, &mh, sizeof mh) || mh.magic != MH_MAGIC_64 || mh.sizeofcmds > sizeof cmds
        || !readmem(load + sizeof mh, cmds, mh.sizeofcmds))
        return 0;
    for (uint32_t i = 0, off = 0; i < mh.ncmds && off + sizeof(struct load_command) <= mh.sizeofcmds; i++) {
        const struct load_command *lc = (const void *)(cmds + off);
        if (lc->cmdsize < sizeof *lc || off + lc->cmdsize > mh.sizeofcmds) break;
        if (lc->cmd == LC_SEGMENT_64 && !strncmp(((const struct segment_command_64 *)lc)->segname, "__TEXT", 16))
            return ((const struct segment_command_64 *)lc)->vmsize;
        off += lc->cmdsize;
    }
    return 0;
}

/* x86 dyld 映像：只輸出新載入的，並記下 __TEXT 範圍。shared cache 在區段表中是唯讀的 submap，
 * 不靠映像範圍就無法判斷堆疊值是否指向系統函式庫的程式碼。 */
static void scan_images(void) {
    struct task_dyld_info di;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    struct dyld_all_image_infos aii;
    if (task_info(task, TASK_DYLD_INFO, (task_info_t)&di, &count) || !readmem(di.all_image_info_addr, &aii, sizeof aii))
        return;
    uint32_t n = aii.infoArrayCount < MAX_IMAGES ? aii.infoArrayCount : MAX_IMAGES;
    struct dyld_image_info *arr = calloc(n, sizeof *arr);
    if (arr && readmem((uint64_t)aii.infoArray, arr, n * sizeof *arr)) {
        for (uint32_t i = 0; i < n && nimages < MAX_IMAGES; i++) {
            uint64_t load = (uint64_t)arr[i].imageLoadAddress;
            int known = 0;
            for (int j = 0; j < nimages && !known; j++) known = images[j].start == load;
            if (known) continue;
            char path[1024];
            mach_vm_size_t got = 0;
            memset(path, 0, sizeof path);
            mach_vm_read_overwrite(task, (uint64_t)arr[i].imageFilePath, sizeof path - 1, (mach_vm_address_t)path, &got);
            uint64_t size = text_size(load);
            images[nimages++] = (struct range){load, load + size, VM_PROT_READ | VM_PROT_EXECUTE, 0};
            if (path[0]) fprintf(scan_out, "D %llx %llx %s\n", load, size, path);
        }
    }
    free(arr);
}

static int cmp_range(const void *a, const void *b) {
    const struct range *x = a, *y = b;
    return x->start < y->start ? -1 : x->start > y->start;
}

/* scan_exec = 可執行區段 ∪ 映像 __TEXT，排序並合併重疊 */
static void build_exec_ranges(void) {
    for (int i = 0; i < nimages && nscan_exec < MAX_REGIONS; i++)
        if (images[i].end > images[i].start) scan_exec[nscan_exec++] = images[i];
    qsort(scan_exec, nscan_exec, sizeof *scan_exec, cmp_range);
    int out = 0;
    for (int i = 0; i < nscan_exec; i++) {
        if (out && scan_exec[i].start <= scan_exec[out - 1].end) {
            if (scan_exec[i].end > scan_exec[out - 1].end) scan_exec[out - 1].end = scan_exec[i].end;
        } else {
            scan_exec[out++] = scan_exec[i];
        }
    }
    nscan_exec = out;
}

/* 重掃一次，結果交給取樣迴圈（上一份還沒被取用時等下一輪） */
static void rescan(void) {
    char *text = NULL;
    size_t len = 0;
    scan_out = open_memstream(&text, &len);
    if (!scan_out) return;
    scan_images();
    scan_regions();
    build_exec_ranges();
    fclose(scan_out);
    pthread_mutex_lock(&staged_lock);
    if (!staged_ready) {
        memcpy(staged_exec, scan_exec, nscan_exec * sizeof *scan_exec);
        nstaged = nscan_exec;
        staged_text = text;
        staged_len = len;
        staged_ready = 1;
        text = NULL;
    }
    pthread_mutex_unlock(&staged_lock);
    free(text);
}

static void *rescan_thread(void *arg) {
    (void)arg;
    for (uint64_t slept = 0; !stop;) {
        usleep(100000); /* 分段睡，結束時不必等滿一個週期 */
        if ((slept += 100000) < REGION_REFRESH_US) continue;
        slept = 0;
        rescan();
    }
    return NULL;
}

/* 取樣迴圈：有新的重掃結果就換上（輸出順序上 M、D 行在使用它們的 S 行之前） */
static void take_rescan(int wait) {
    if (wait ? pthread_mutex_lock(&staged_lock) : pthread_mutex_trylock(&staged_lock)) return;
    if (staged_ready) {
        memcpy(exec_ranges, staged_exec, nstaged * sizeof *staged_exec);
        nexec = nstaged;
        fwrite(staged_text, 1, staged_len, stdout);
        free(staged_text);
        staged_ready = 0;
    }
    pthread_mutex_unlock(&staged_lock);
}

/* ---------- 程序 ---------- */

/* argv[0] 的檔名（Wine 程序為 Windows exe 名稱）。只讀 argv[0]，不讀其他參數（可能含帳號資訊）。 */
static void print_proc_name(int p) {
    static char buf[16384];
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, p};
    size_t len = sizeof buf;
    const char *name = NULL;
    if (sysctl(mib, 3, buf, &len, NULL, 0) == 0 && len > sizeof(int)) {
        char *s = buf + sizeof(int), *end = buf + len;
        while (s < end && *s) s++; /* 執行檔路徑 */
        while (s < end && !*s) s++;
        if (s < end && memchr(s, 0, end - s)) name = s;
    }
    char comm[2 * MAXCOMLEN + 1] = "";
    if (!name) {
        proc_name(p, comm, sizeof comm);
        name = comm[0] ? comm : "?";
    }
    const char *base = name;
    for (const char *c = name; *c; c++)
        if (*c == '/' || *c == '\\') base = c + 1;
    printf("N %d ", p);
    for (const char *c = base; *c; c++) putchar(*c == ' ' || *c == '\n' ? '_' : *c);
    putchar('\n');
}

static struct proc *find_proc(int p) {
    for (int i = 0; i < nprocs; i++)
        if (procs[i].pid == p) return &procs[i];
    return NULL;
}

static void sample_procs(uint64_t t) {
    static int pids[MAX_PROCS];
    int n = proc_listallpids(pids, sizeof pids);
    uid_t uid = getuid();
    for (int i = 0; i < n && i < MAX_PROCS; i++) {
        struct proc_taskallinfo ai;
        if (pids[i] == pid || pids[i] == getpid()) continue;
        if (proc_pidinfo(pids[i], PROC_PIDTASKALLINFO, 0, &ai, sizeof ai) != sizeof ai) continue;
        if (ai.pbsd.pbi_uid != uid) continue;
        uint64_t cpu = mach_to_us(ai.ptinfo.pti_total_user + ai.ptinfo.pti_total_system);
        struct proc *pr = find_proc(pids[i]);
        if (!pr) {
            if (nprocs >= MAX_PROCS) continue;
            pr = &procs[nprocs++];
            *pr = (struct proc){pids[i], cpu};
            print_proc_name(pids[i]);
            printf("P %llu %d %llu\n", t, pids[i], cpu);
        } else if (cpu > pr->cpu) {
            pr->cpu = cpu;
            printf("P %llu %d %llu\n", t, pids[i], cpu);
        }
    }
}

static void sample_counters(uint64_t t) {
    struct proc_taskinfo ti;
    if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, sizeof ti) != sizeof ti) return;
    printf("C %llu %d %d %d %d %d %d %d %d %d\n", t, ti.pti_faults, ti.pti_pageins, ti.pti_cow_faults, ti.pti_csw,
           ti.pti_syscalls_mach, ti.pti_syscalls_unix, ti.pti_messages_sent, ti.pti_messages_received,
           ti.pti_numrunning);
}

/* ---------- 執行緒 ---------- */

static struct tinfo *thread_entry(thread_act_t port) {
    for (int i = 0; i < nthreads; i++)
        if (threads[i].port == port) {
            mach_port_deallocate(mach_task_self(), port); /* 已保留一個 send right，丟掉這次多拿的 */
            return &threads[i];
        }
    if (nthreads >= MAX_THREADS) {
        mach_port_deallocate(mach_task_self(), port);
        return NULL;
    }
    thread_identifier_info_data_t id;
    mach_msg_type_number_t ic = THREAD_IDENTIFIER_INFO_COUNT;
    struct tinfo *e = &threads[nthreads++];
    memset(e, 0, sizeof *e);
    e->port = port;
    e->state = -1;
    if (thread_info(port, THREAD_IDENTIFIER_INFO, (thread_info_t)&id, &ic) == KERN_SUCCESS) e->tid = id.thread_id;
    return e;
}

static void thread_name(thread_act_t port, char *out, size_t len) {
    thread_extended_info_data_t ex;
    mach_msg_type_number_t ec = THREAD_EXTENDED_INFO_COUNT;
    out[0] = 0;
    if (thread_info(port, THREAD_EXTENDED_INFO, (thread_info_t)&ex, &ec) == KERN_SUCCESS) strlcpy(out, ex.pth_name, len);
    for (char *c = out; *c; c++)
        if (*c == ' ' || *c == '\n') *c = '_';
    if (!out[0]) strlcpy(out, "-", len);
}

/* 是否在累計 CPU 最多的前 ALWAYS_TOP 名 */
static int is_top(const struct tinfo *e) {
    int above = 0;
    uint64_t used = e->cpu_last - e->cpu_first;
    for (int i = 0; i < nthreads; i++)
        if (threads[i].seen && threads[i].cpu_last - threads[i].cpu_first > used) above++;
    return above < ALWAYS_TOP;
}

static void print_stack(uint64_t t, const struct tinfo *e) {
    arm_thread_state64_t s;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    uint64_t blk[BLK_WORDS], words[X86_SCAN_BYTES / 8];

    /* 不 thread_suspend：取樣程式若在暫停期間被強制結束，遊戲執行緒會永遠停住。thread_get_state 期間
     * 核心會短暫停住該執行緒；之後讀堆疊時執行緒可能已往前跑，執行中的執行緒偶爾會讀到不一致的堆疊。 */
    if (thread_get_state(e->port, ARM_THREAD_STATE64, (thread_state_t)&s, &count) != KERN_SUCCESS) return;
    uint64_t pc = arm_thread_state64_get_pc(s) & PAC_MASK, lr = arm_thread_state64_get_lr(s) & PAC_MASK;
    uint64_t fp = arm_thread_state64_get_fp(s), sp = arm_thread_state64_get_sp(s);
    int insys = readmem(sp + 8, blk, sizeof blk) && (blk[BLK_LR] & PAC_MASK) == lr;
    /* 執行翻譯碼中：x86 rsp 在 x4（見 machstack.c） */
    uint64_t rsp = insys ? blk[BLK_RSP] : s.__x[4];

    printf("S %llu %llu %c %lld %llx,%llx", t, e->tid, insys ? 's' : 'j', (long long)s.__x[16], pc, lr);
    for (int depth = 0; depth < NATIVE_DEPTH && fp && !(fp & 7); depth++) {
        uint64_t frame[2];
        if (!readmem(fp, frame, sizeof frame) || !frame[1]) break;
        printf(",%llx", frame[1] & PAC_MASK);
        if (frame[0] <= fp || frame[0] - fp > 0x100000) break;
        fp = frame[0];
    }

    size_t got = rsp && !(rsp & 7) ? readmem_upto(rsp, words, sizeof words) : 0;

    int emitted = 0;
    uint64_t last = 0;
    for (size_t w = 0; w < got / 8 && emitted < X86_EMIT; w++) {
        uint64_t v = words[w];
        if (v == last || v < 0x10000 || !is_exec(v)) continue;
        printf("%c%llx", emitted ? ',' : ' ', v);
        last = v;
        emitted++;
    }
    printf(emitted ? "\n" : " -\n");
}

static int sample_threads(uint64_t t) {
    thread_act_array_t list;
    mach_msg_type_number_t n = 0;
    if (task_threads(task, &list, &n) != KERN_SUCCESS) return 0;

    for (int i = 0; i < nthreads; i++) threads[i].seen = 0;
    for (unsigned i = 0; i < n; i++) {
        struct tinfo *e = thread_entry(list[i]);
        if (!e) continue;
        thread_basic_info_data_t b;
        mach_msg_type_number_t bc = THREAD_BASIC_INFO_COUNT;
        if (thread_info(e->port, THREAD_BASIC_INFO, (thread_info_t)&b, &bc) != KERN_SUCCESS) continue;
        uint64_t cpu = (uint64_t)(b.user_time.seconds + b.system_time.seconds) * 1000000 + b.user_time.microseconds
                     + b.system_time.microseconds;
        int fresh = e->state < 0;
        if (fresh) e->cpu_first = e->cpu_last = cpu;
        uint64_t delta = cpu - e->cpu_last;
        if (fresh || delta || b.run_state != e->state || b.suspend_count != e->suspend) {
            char name[64] = "-";
            if (fresh) thread_name(e->port, name, sizeof name);
            printf("T %llu %llu %llu %d %d %s\n", t, e->tid, cpu, b.run_state, b.suspend_count, name);
        }
        e->cpu_last = cpu;
        e->delta = delta;
        if (delta) e->active_t = t;
        e->state = b.run_state;
        e->suspend = b.suspend_count;
        e->seen = 1;
    }
    vm_deallocate(mach_task_self(), (vm_address_t)list, n * sizeof(thread_act_t));

    /* 已結束的執行緒：釋放保留的 send right（之後同名 port 才會是新的執行緒） */
    for (int i = 0; i < nthreads;) {
        if (threads[i].seen) {
            i++;
            continue;
        }
        mach_port_deallocate(mach_task_self(), threads[i].port);
        threads[i] = threads[--nthreads];
    }

    for (int i = 0; i < nthreads; i++) {
        struct tinfo *e = &threads[i];
        if (e->state == TH_STATE_RUNNING || e->delta || t - e->active_t < RECENT_US || is_top(e)) print_stack(t, e);
    }
    return 1;
}

static void on_signal(int sig) {
    (void)sig;
    stop = 1;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <pid> <interval ms> <seconds (0 = until SIGINT)>\n", argv[0]);
        return 2;
    }
    pid = atoi(argv[1]);
    double interval_ms = atof(argv[2]), seconds = atof(argv[3]);
    if (pid <= 0 || interval_ms < 1) {
        fprintf(stderr, "invalid pid or interval\n");
        return 2;
    }
    kern_return_t k = task_for_pid(mach_task_self(), pid, &task);
    if (k) {
        fprintf(stderr, "task_for_pid(%d): %s\n", pid, mach_error_string(k));
        return 1;
    }
    mach_timebase_info(&timebase);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    static char outbuf[1 << 20];
    setvbuf(stdout, outbuf, _IOFBF, sizeof outbuf);

    uint64_t interval = (uint64_t)(interval_ms * 1000), start = now_us();
    uint64_t deadline = seconds > 0 ? start + (uint64_t)(seconds * 1e6) : 0;
    printf("H %d %llu %llu\n", pid, interval, start);
    rescan();
    take_rescan(1);
    pthread_t rescanner;
    pthread_create(&rescanner, NULL, rescan_thread, NULL);
    sample_procs(start);

    uint64_t next = start, last_procs = start, samples = 0, behind = 0, cost_sum = 0, cost_max = 0;
    while (!stop) {
        uint64_t t = now_us();
        if (deadline && t >= deadline) break;
        take_rescan(0);
        if (t - last_procs >= PROC_REFRESH_US) {
            sample_procs(t);
            last_procs = t;
        }
        sample_counters(t);
        if (!sample_threads(t)) break; /* 目標程序已結束 */
        uint64_t cost = now_us() - t;
        samples++;
        cost_sum += cost;
        if (cost > cost_max) cost_max = cost;

        next += interval;
        uint64_t after = now_us();
        if (after >= next) {
            behind++;
            next = after;
        } else {
            usleep((useconds_t)(next - after));
        }
    }
    stop = 1;
    pthread_join(rescanner, NULL);
    for (int i = 0; i < nthreads; i++) mach_port_deallocate(mach_task_self(), threads[i].port);
    printf("E %llu %llu %llu %llu %llu\n", now_us(), samples, behind, samples ? cost_sum / samples : 0, cost_max);
    fflush(stdout);
    return 0;
}
