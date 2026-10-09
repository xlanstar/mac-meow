/*
 * machstack：以 Mach API 直接讀取（Rosetta 轉譯中）程序每條執行緒的原生 arm64 狀態。
 * 不經過 LLDB／Rosetta debug 協定、不送訊號，因此對「收不到訊號、LLDB 無法暫停」的程序也有效。
 *
 * 用法：machstack <pid> [nosuspend]
 * 需要：目標帶 get-task-allow（或以 root 執行）。
 *
 * 每條執行緒輸出：run_state、suspend_count、CPU 時間、名稱、pc/lr/fp/sp/x16（arm64 syscall 號）、
 * 以 frame pointer 回溯的原生堆疊；每個位址標上所屬檔案＋偏移與（若可解析）符號。
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

static int pid;
static mach_port_t task;

/* dyld 映像清單（Rosetta 程序為 x86 dyld 的清單） */
struct img { uint64_t load; char path[512]; };
static struct img imgs[4096]; static int nimg;
static void load_images(void) {
    struct task_dyld_info di; mach_msg_type_number_t c = TASK_DYLD_INFO_COUNT;
    if (task_info(task, TASK_DYLD_INFO, (task_info_t)&di, &c)) return;
    struct dyld_all_image_infos aii;
    mach_vm_size_t got;
    if (mach_vm_read_overwrite(task, di.all_image_info_addr, sizeof aii, (mach_vm_address_t)&aii, &got)) return;
    uint32_t n = aii.infoArrayCount; if (n > 4096) n = 4096;
    struct dyld_image_info *arr = calloc(n, sizeof *arr);
    if (mach_vm_read_overwrite(task, (uint64_t)aii.infoArray, n * sizeof *arr, (mach_vm_address_t)arr, &got)) return;
    for (uint32_t i = 0; i < n; i++) {
        imgs[nimg].load = (uint64_t)arr[i].imageLoadAddress;
        mach_vm_read_overwrite(task, (uint64_t)arr[i].imageFilePath, 511, (mach_vm_address_t)imgs[nimg].path, &got);
        imgs[nimg].path[511] = 0; nimg++;
    }
}
static const struct img *find_img(uint64_t a) {
    const struct img *best = NULL;
    for (int i = 0; i < nimg; i++) if (imgs[i].load <= a && (!best || imgs[i].load > best->load)) best = &imgs[i];
    if (best && a - best->load > 0x4000000) return NULL;   /* 超過 64MB 視為不屬於該映像 */
    return best;
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

static int readmem(uint64_t addr, void *buf, size_t len) {
    mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(task, addr, len, (mach_vm_address_t)buf, &got) == KERN_SUCCESS && got == len;
}

static void describe(uint64_t addr) {
    char path[PROC_PIDPATHINFO_MAXSIZE] = "";
    mach_vm_address_t start = addr; mach_vm_size_t size = 0;
    vm_region_basic_info_data_64_t info; mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj;
    if (mach_vm_region(task, &start, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &cnt, &obj) != KERN_SUCCESS || start > addr) {
        printf("  0x%016llx  ?\n", addr); return;
    }
    region_path(addr, path, sizeof(path));
    const char *base = strrchr(path, '/'); base = base ? base + 1 : (path[0] ? path : "(anon)");
    Dl_info dl; const char *sym = NULL; uint64_t symoff = 0;
    /* 共享快取內的 arm64 系統函式庫在本程序同位址：可直接 dladdr */
    if (dladdr((void *)addr, &dl) && dl.dli_sname && dl.dli_fname && path[0] && strstr(dl.dli_fname, base)) {
        sym = dl.dli_sname; symoff = addr - (uint64_t)dl.dli_saddr;
    }
    printf("  0x%016llx  %s+0x%llx prot=%d%s%s", addr, base, addr - start, info.protection,
           info.protection & VM_PROT_EXECUTE ? "x" : "", info.shared ? " shared" : "");
    if (sym) printf("  %s+%llu", sym, symoff);
    const struct img *im = find_img(addr);
    if (im) printf("  [img %s load=0x%llx off=0x%llx]", im->path, im->load, addr - im->load);
    printf("\n");
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <pid> [nosuspend]\n", argv[0]); return 2; }
    pid = atoi(argv[1]);
    int suspend = !(argc > 2 && !strcmp(argv[2], "nosuspend"));
    kern_return_t k = task_for_pid(mach_task_self(), pid, &task);
    if (k) { printf("task_for_pid(%d): %s\n", pid, mach_error_string(k)); return 1; }
    if (suspend && (k = task_suspend(task))) printf("task_suspend: %s\n", mach_error_string(k));

    thread_act_array_t th; mach_msg_type_number_t n = 0;
    load_images();
    printf("dyld images: %d\n", nimg);
    if ((k = task_threads(task, &th, &n))) { printf("task_threads: %s\n", mach_error_string(k)); goto out; }
    printf("pid %d: %u threads (suspended=%d)\n", pid, n, suspend);
    for (unsigned i = 0; i < n; i++) {
        thread_basic_info_data_t b; mach_msg_type_number_t c = THREAD_BASIC_INFO_COUNT;
        thread_identifier_info_data_t id; mach_msg_type_number_t ic = THREAD_IDENTIFIER_INFO_COUNT;
        thread_extended_info_data_t ex; mach_msg_type_number_t ec = THREAD_EXTENDED_INFO_COUNT;
        memset(&id, 0, sizeof id); memset(&ex, 0, sizeof ex);
        thread_info(th[i], THREAD_BASIC_INFO, (thread_info_t)&b, &c);
        thread_info(th[i], THREAD_IDENTIFIER_INFO, (thread_info_t)&id, &ic);
        thread_info(th[i], THREAD_EXTENDED_INFO, (thread_info_t)&ex, &ec);
        printf("\n=== thread[%u] tid=%llu name='%s' run_state=%d suspend=%d flags=0x%x user=%d.%06ds sys=%d.%06ds\n",
               i, id.thread_id, ex.pth_name, b.run_state, b.suspend_count, b.flags,
               b.user_time.seconds, b.user_time.microseconds, b.system_time.seconds, b.system_time.microseconds);

        arm_thread_state64_t s; mach_msg_type_number_t sc = ARM_THREAD_STATE64_COUNT;
        k = thread_get_state(th[i], ARM_THREAD_STATE64, (thread_state_t)&s, &sc);
        if (k) { printf("  ARM_THREAD_STATE64: %s\n", mach_error_string(k)); }
        else {
            uint64_t pc = arm_thread_state64_get_pc(s), lr = arm_thread_state64_get_lr(s);
            uint64_t fp = arm_thread_state64_get_fp(s), sp = arm_thread_state64_get_sp(s);
            printf("  arm64 pc=0x%llx lr=0x%llx fp=0x%llx sp=0x%llx x16=%lld x0=0x%llx x1=0x%llx x2=0x%llx\n",
                   pc, lr, fp, sp, (long long)s.__x[16], s.__x[0], s.__x[1], s.__x[2]);
            printf(" pc:\n"); describe(pc);
            printf(" lr:\n"); describe(lr);
            printf(" fp chain:\n");
            for (int f = 0; f < 48 && fp && !(fp & 7); f++) {
                uint64_t fr[2];
                if (!readmem(fp, fr, sizeof fr)) break;
                if (!fr[1]) break;
                describe(fr[1] & 0x0000ffffffffffffULL);
                if (fr[0] <= fp) break;
                fp = fr[0];
            }
        }
        /* Rosetta 系統呼叫路徑：[sp+8]==lr 時，[sp+0x10..] 為 x86 rax rcx rdx rbx rsp rbp rsi rdi r8-r15 rflags */
        if (!k) {
            uint64_t sp = arm_thread_state64_get_sp(s), lr = arm_thread_state64_get_lr(s), blk[19];
            int insys = readmem(sp + 8, blk, sizeof blk) && blk[0] == lr;
            if (!insys) {
                /* 執行翻譯碼中：依 Rosetta 暫存器對應，x4=rsp、x5=rbp（rax..r15 → x0..x15） */
                blk[5] = s.__x[4]; blk[6] = s.__x[5];
                blk[1] = s.__x[0]; blk[2] = s.__x[1]; blk[3] = s.__x[2]; blk[4] = s.__x[3];
                blk[7] = s.__x[6]; blk[8] = s.__x[7]; blk[9] = s.__x[8]; blk[10] = s.__x[9]; blk[11] = s.__x[10];
                printf("  (running: assuming x4=rsp x5=rbp)\n");
            }
            if (1) {
                uint64_t rsp = blk[5], rbp = blk[6];
                printf("  x86(%s) rax=0x%llx rcx=0x%llx rdx=0x%llx rbx=0x%llx rsp=0x%llx rbp=0x%llx rsi=0x%llx rdi=0x%llx r8=0x%llx r9=0x%llx r10=0x%llx\n", insys ? "syscall" : "jit",
                       blk[1], blk[2], blk[3], blk[4], rsp, rbp, blk[7], blk[8], blk[9], blk[10], blk[11]);
                uint64_t ret;
                printf(" x86 [rsp]:\n");
                if (readmem(rsp, &ret, 8)) describe(ret);
                printf(" x86 rbp chain:\n");
                for (int f = 0; f < 64 && rbp && !(rbp & 7); f++) {
                    uint64_t fr[2];
                    if (!readmem(rbp, fr, sizeof fr) || !fr[1]) break;
                    describe(fr[1]);
                    if (fr[0] <= rbp) break;
                    rbp = fr[0];
                }
                printf(" x86 stack scan (file-backed/dyld-image values):\n");
                uint64_t words[1024]; int nw = 0;
                for (nw = 0; nw < 1024 && readmem(rsp + nw * 8, &words[nw], 8); nw++);
                for (int w = 0; w < nw; w++) {
                    uint64_t v = words[w]; char path[PROC_PIDPATHINFO_MAXSIZE] = "";
                    if (v < 0x10000 || v > 0x7fffffffffffULL) continue;
                    mach_vm_address_t rs = v; mach_vm_size_t rz; vm_region_basic_info_data_64_t ri;
                    mach_msg_type_number_t rc = VM_REGION_BASIC_INFO_COUNT_64; mach_port_t ro;
                    if (mach_vm_region(task, &rs, &rz, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&ri, &rc, &ro) || rs > v) continue;
                    const struct img *im = find_img(v);
                    int ok = im && v - im->load < 0x1000000 && !strstr(im->path, "oah/") && !strstr(im->path, "rosetta/");
                    if (!ok && region_path(v, path, sizeof path) && (strstr(path, ".dll") || strstr(path, ".exe") || strstr(path, ".so")))
                        ok = 1;
                    if (ok) { printf("  rsp+0x%x:", w * 8); describe(v); }
                }
            }
        }
        /* Rosetta 執行緒是否也能讀到 x86 狀態（多半不行；成功就印出） */
        /* x86_THREAD_STATE64 = 4，21 個 64-bit 暫存器：rax rbx rcx rdx rdi rsi rbp rsp r8..r15 rip rflags cs fs gs */
        uint64_t xs[21]; mach_msg_type_number_t xc = 42;
        k = thread_get_state(th[i], 4, (thread_state_t)xs, &xc);
        if (!k) printf("  x86 rip=0x%llx rsp=0x%llx rbp=0x%llx rax=0x%llx\n", xs[16], xs[7], xs[6], xs[0]);
        else printf("  x86 state: %s\n", mach_error_string(k));
        mach_port_deallocate(mach_task_self(), th[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)th, n * sizeof(thread_t));
out:
    if (suspend) task_resume(task);
    return 0;
}
