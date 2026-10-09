/*
 * machstack：以 Mach API 直接讀取（Rosetta 轉譯中）程序每條執行緒的原生 arm64 狀態。
 * 不經過 LLDB／Rosetta debug 協定、不送訊號，因此對「收不到訊號、LLDB 無法暫停」的程序也有效。
 *
 * 用法：machstack <pid> [nosuspend]
 * 需要：目標帶 get-task-allow（或以 root 執行）。
 *
 * 每條執行緒輸出：run_state、suspend_count、CPU 時間、名稱、pc/lr/fp/sp/x16（arm64 syscall 號）、
 * 以 frame pointer 回溯的原生堆疊；每個位址標上所屬檔案＋偏移與（若可解析）符號。
 * 輸出格式由 symbolize.py、machprof.py 解析，修改時一併更新。
 */
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/thread_status.h>
#include <mach/mach_error.h>
#include <libproc.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach-o/dyld_images.h>

#define MAX_IMAGES 4096
#define IMAGE_SPAN 0x4000000ULL         /* 距載入位址超過 64MB 視為不屬於該映像 */
#define USER_ADDR_MAX 0x7fffffffffffULL
#define PAC_MASK 0x0000ffffffffffffULL  /* 去掉 arm64 返回位址的 PAC 位元 */
#define ARM_FP_DEPTH 48
#define X86_RBP_DEPTH 64
#define X86_SCAN_WORDS 1024

/* x86_THREAD_STATE64（arm64 標頭沒有定義）：21 個 64-bit 暫存器
 * rax rbx rcx rdx rdi rsi rbp rsp r8..r15 rip rflags cs fs gs */
#define X86_THREAD_STATE64_FLAVOR 4
#define X86_STATE_WORDS 21
enum { X86_RAX = 0, X86_RBP = 6, X86_RSP = 7, X86_RIP = 16 };

/* x86 暫存器區塊（Rosetta 系統呼叫時位於 [sp+8]）：返回位址後依序為
 * rax rcx rdx rbx rsp rbp rsi rdi r8-r15 rflags */
enum { BLK_LR, BLK_RAX, BLK_RCX, BLK_RDX, BLK_RBX, BLK_RSP, BLK_RBP, BLK_RSI, BLK_RDI, BLK_R8, BLK_R9, BLK_R10,
       BLK_WORDS = 19 };

static int pid;
static mach_port_t task;

/* dyld 映像清單（Rosetta 程序為 x86 dyld 的清單） */
struct img {
    uint64_t load;
    char path[512];
};
static struct img imgs[MAX_IMAGES];
static int nimg;

static int readmem(uint64_t addr, void *buf, size_t len) {
    mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(task, addr, len, (mach_vm_address_t)buf, &got) == KERN_SUCCESS && got == len;
}

static void load_images(void) {
    struct task_dyld_info di;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    struct dyld_all_image_infos aii;
    mach_vm_size_t got;

    if (task_info(task, TASK_DYLD_INFO, (task_info_t)&di, &count)) return;
    if (mach_vm_read_overwrite(task, di.all_image_info_addr, sizeof aii, (mach_vm_address_t)&aii, &got)) return;
    uint32_t n = aii.infoArrayCount;
    if (n > MAX_IMAGES) n = MAX_IMAGES;
    struct dyld_image_info *arr = calloc(n, sizeof *arr);
    if (!arr) return;
    if (mach_vm_read_overwrite(task, (uint64_t)aii.infoArray, n * sizeof *arr, (mach_vm_address_t)arr, &got) == KERN_SUCCESS) {
        for (uint32_t i = 0; i < n; i++) {
            struct img *im = &imgs[nimg++];
            im->load = (uint64_t)arr[i].imageLoadAddress;
            mach_vm_read_overwrite(task, (uint64_t)arr[i].imageFilePath, sizeof im->path - 1,
                                   (mach_vm_address_t)im->path, &got);
            im->path[sizeof im->path - 1] = 0;
        }
    }
    free(arr);
}

/* 載入位址不大於 a 的最近映像 */
static const struct img *find_img(uint64_t a) {
    const struct img *best = NULL;
    for (int i = 0; i < nimg; i++) {
        if (imgs[i].load <= a && (!best || imgs[i].load > best->load)) best = &imgs[i];
    }
    if (best && a - best->load > IMAGE_SPAN) return NULL;
    return best;
}

/* addr 所在的 VM 區段；未映射時回傳 0 */
static int region_at(uint64_t addr, mach_vm_address_t *start, vm_region_basic_info_data_64_t *info) {
    mach_vm_size_t size = 0;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object;
    *start = addr;
    return mach_vm_region(task, start, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)info, &count, &object) == KERN_SUCCESS
        && *start <= addr;
}

/* 只在區段確實包含 addr 時回傳檔名（proc_regionfilename 會給「下一個」區段） */
static int region_path(uint64_t addr, char *path, size_t len) {
    struct proc_regionwithpathinfo ri;
    path[0] = 0;
    if (proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, addr, &ri, sizeof ri) != sizeof ri) return 0;
    if (addr < ri.prp_prinfo.pri_address || addr >= ri.prp_prinfo.pri_address + ri.prp_prinfo.pri_size) return 0;
    strlcpy(path, ri.prp_vip.vip_path, len);
    return path[0] != 0;
}

/* 一行：位址、所屬檔案＋偏移、保護、（arm64 shared cache）符號、dyld 映像 */
static void describe(uint64_t addr) {
    char path[PROC_PIDPATHINFO_MAXSIZE] = "";
    mach_vm_address_t start;
    vm_region_basic_info_data_64_t info;
    if (!region_at(addr, &start, &info)) {
        printf("  0x%016llx  ?\n", addr);
        return;
    }
    region_path(addr, path, sizeof path);
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : (path[0] ? path : "(anon)");

    printf("  0x%016llx  %s+0x%llx prot=%d%s%s", addr, base, addr - start, info.protection,
           info.protection & VM_PROT_EXECUTE ? "x" : "", info.shared ? " shared" : "");
    /* 共享快取內的 arm64 系統函式庫在本程序同位址：可直接 dladdr */
    Dl_info dl;
    if (dladdr((void *)addr, &dl) && dl.dli_sname && dl.dli_fname && path[0] && strstr(dl.dli_fname, base))
        printf("  %s+%llu", dl.dli_sname, addr - (uint64_t)dl.dli_saddr);
    const struct img *im = find_img(addr);
    if (im) printf("  [img %s load=0x%llx off=0x%llx]", im->path, im->load, addr - im->load);
    printf("\n");
}

static void print_thread_info(thread_act_t th, unsigned i) {
    thread_basic_info_data_t b;
    thread_identifier_info_data_t id;
    thread_extended_info_data_t ex;
    mach_msg_type_number_t bc = THREAD_BASIC_INFO_COUNT;
    mach_msg_type_number_t ic = THREAD_IDENTIFIER_INFO_COUNT;
    mach_msg_type_number_t ec = THREAD_EXTENDED_INFO_COUNT;
    memset(&id, 0, sizeof id);
    memset(&ex, 0, sizeof ex);
    thread_info(th, THREAD_BASIC_INFO, (thread_info_t)&b, &bc);
    thread_info(th, THREAD_IDENTIFIER_INFO, (thread_info_t)&id, &ic);
    thread_info(th, THREAD_EXTENDED_INFO, (thread_info_t)&ex, &ec);
    printf("\n=== thread[%u] tid=%llu name='%s' run_state=%d suspend=%d flags=0x%x user=%d.%06ds sys=%d.%06ds\n",
           i, id.thread_id, ex.pth_name, b.run_state, b.suspend_count, b.flags,
           b.user_time.seconds, b.user_time.microseconds, b.system_time.seconds, b.system_time.microseconds);
}

/* 原生 arm64 暫存器與 frame pointer 鏈 */
static void print_arm_frames(const arm_thread_state64_t *s) {
    uint64_t pc = arm_thread_state64_get_pc(*s), lr = arm_thread_state64_get_lr(*s);
    uint64_t fp = arm_thread_state64_get_fp(*s), sp = arm_thread_state64_get_sp(*s);
    printf("  arm64 pc=0x%llx lr=0x%llx fp=0x%llx sp=0x%llx x16=%lld x0=0x%llx x1=0x%llx x2=0x%llx\n",
           pc, lr, fp, sp, (long long)s->__x[16], s->__x[0], s->__x[1], s->__x[2]);
    printf(" pc:\n");
    describe(pc);
    printf(" lr:\n");
    describe(lr);
    printf(" fp chain:\n");
    for (int depth = 0; depth < ARM_FP_DEPTH && fp && !(fp & 7); depth++) {
        uint64_t frame[2];
        if (!readmem(fp, frame, sizeof frame) || !frame[1]) break;
        describe(frame[1] & PAC_MASK);
        if (frame[0] <= fp) break;
        fp = frame[0];
    }
}

/* 堆疊值是否值得列出：位於 dyld 映像（Rosetta 本身除外）或 .dll/.exe/.so 檔案映射內 */
static int is_code_value(uint64_t v) {
    mach_vm_address_t start;
    vm_region_basic_info_data_64_t info;
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (v < 0x10000 || v > USER_ADDR_MAX || !region_at(v, &start, &info)) return 0;
    const struct img *im = find_img(v);
    if (im && v - im->load < 0x1000000 && !strstr(im->path, "oah/") && !strstr(im->path, "rosetta/")) return 1;
    return region_path(v, path, sizeof path) && (strstr(path, ".dll") || strstr(path, ".exe") || strstr(path, ".so"));
}

/* x86 暫存器（系統呼叫中讀 Rosetta 存的區塊，否則依翻譯碼的暫存器對應）、rbp 鏈與堆疊掃描 */
static void print_x86_frames(const arm_thread_state64_t *s) {
    uint64_t sp = arm_thread_state64_get_sp(*s), lr = arm_thread_state64_get_lr(*s), blk[BLK_WORDS];
    int insys = readmem(sp + 8, blk, sizeof blk) && blk[BLK_LR] == lr;
    if (!insys) {
        /* 執行翻譯碼中：rax rcx rdx rbx rsp rbp rsi rdi r8.. 依序在 x0..（x4=rsp、x5=rbp） */
        for (int r = BLK_RAX; r <= BLK_R10; r++) blk[r] = s->__x[r - BLK_RAX];
        printf("  (running: assuming x4=rsp x5=rbp)\n");
    }
    uint64_t rsp = blk[BLK_RSP], rbp = blk[BLK_RBP];
    printf("  x86(%s) rax=0x%llx rcx=0x%llx rdx=0x%llx rbx=0x%llx rsp=0x%llx rbp=0x%llx rsi=0x%llx rdi=0x%llx"
           " r8=0x%llx r9=0x%llx r10=0x%llx\n",
           insys ? "syscall" : "jit", blk[BLK_RAX], blk[BLK_RCX], blk[BLK_RDX], blk[BLK_RBX], rsp, rbp,
           blk[BLK_RSI], blk[BLK_RDI], blk[BLK_R8], blk[BLK_R9], blk[BLK_R10]);

    uint64_t ret;
    printf(" x86 [rsp]:\n");
    if (readmem(rsp, &ret, sizeof ret)) describe(ret);

    printf(" x86 rbp chain:\n");
    for (int depth = 0; depth < X86_RBP_DEPTH && rbp && !(rbp & 7); depth++) {
        uint64_t frame[2];
        if (!readmem(rbp, frame, sizeof frame) || !frame[1]) break;
        describe(frame[1]);
        if (frame[0] <= rbp) break;
        rbp = frame[0];
    }

    printf(" x86 stack scan (file-backed/dyld-image values):\n");
    uint64_t words[X86_SCAN_WORDS];
    int nw = 0;
    while (nw < X86_SCAN_WORDS && readmem(rsp + nw * 8, &words[nw], 8)) nw++;
    for (int w = 0; w < nw; w++) {
        if (!is_code_value(words[w])) continue;
        printf("  rsp+0x%x:", w * 8);
        describe(words[w]);
    }
}

/* Rosetta 執行緒是否也能讀到 x86 狀態（多半不行；成功就印出） */
static void print_x86_state(thread_act_t th) {
    uint64_t xs[X86_STATE_WORDS];
    mach_msg_type_number_t count = X86_STATE_WORDS * 2;
    kern_return_t k = thread_get_state(th, X86_THREAD_STATE64_FLAVOR, (thread_state_t)xs, &count);
    if (k == KERN_SUCCESS)
        printf("  x86 rip=0x%llx rsp=0x%llx rbp=0x%llx rax=0x%llx\n", xs[X86_RIP], xs[X86_RSP], xs[X86_RBP], xs[X86_RAX]);
    else
        printf("  x86 state: %s\n", mach_error_string(k));
}

static void print_thread(thread_act_t th, unsigned i) {
    arm_thread_state64_t s;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    print_thread_info(th, i);
    kern_return_t k = thread_get_state(th, ARM_THREAD_STATE64, (thread_state_t)&s, &count);
    if (k == KERN_SUCCESS) {
        print_arm_frames(&s);
        print_x86_frames(&s);
    } else {
        printf("  ARM_THREAD_STATE64: %s\n", mach_error_string(k));
    }
    print_x86_state(th);
}

static void print_threads(int suspended) {
    thread_act_array_t th;
    mach_msg_type_number_t n = 0;
    kern_return_t k = task_threads(task, &th, &n);
    if (k) {
        printf("task_threads: %s\n", mach_error_string(k));
        return;
    }
    printf("pid %d: %u threads (suspended=%d)\n", pid, n, suspended);
    for (unsigned i = 0; i < n; i++) {
        print_thread(th[i], i);
        mach_port_deallocate(mach_task_self(), th[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)th, n * sizeof(thread_t));
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <pid> [nosuspend]\n", argv[0]);
        return 2;
    }
    pid = atoi(argv[1]);
    int suspend = !(argc > 2 && !strcmp(argv[2], "nosuspend"));
    kern_return_t k = task_for_pid(mach_task_self(), pid, &task);
    if (k) {
        printf("task_for_pid(%d): %s\n", pid, mach_error_string(k));
        return 1;
    }
    if (suspend && (k = task_suspend(task))) printf("task_suspend: %s\n", mach_error_string(k));

    load_images();
    printf("dyld images: %d\n", nimg);
    print_threads(suspend);
    if (suspend) task_resume(task);
    return 0;
}
