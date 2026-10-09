/* callchain <pid> <samples>：對 CPU 時間最高的執行緒取樣（Rosetta 翻譯碼中 x4=rsp），
 * 只輸出「前一條指令是 call」的堆疊值（可信的返回位址），每行一個樣本，由內而外。 */
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static mach_port_t t;
static int rd(uint64_t a, void *b, size_t n) { mach_vm_size_t g = 0; return !mach_vm_read_overwrite(t, a, n, (mach_vm_address_t)b, &g) && g == n; }
static int is_ret(uint64_t v) {
    if (v < 0x10000 || v > 0x7fffffffffffULL) return 0;
    uint8_t b[8];
    if (!rd(v - 8, b, 8)) return 0;
    if (b[3] == 0xe8) return 1;                                    /* call rel32 */
    if (b[2] == 0xff && b[3] == 0x15) return 1; /* call [rip+d32] */
    if (b[2] == 0xff && (b[3] & 0x38) == 0x10 && (b[3] & 0xc0) == 0x80) return 1; /* call [r+d32] */
    if (b[1] == 0xff && (b[2] & 0x38) == 0x10 && (b[2] & 0xc0) == 0x80 && (b[2]&7)==4) return 1;
    if (b[5] == 0xff && (b[6] & 0x38) == 0x10 && (b[6] & 0xc0) == 0x40) return 1; /* call [r+d8] */
    if (b[4] == 0xff && (b[5] & 0x38) == 0x10 && (b[5] & 0xc0) == 0x40 && (b[5]&7)==4) return 1;
    if (b[6] == 0xff && (b[7] & 0xf8) == 0xd0) return 1;            /* call reg */
    if (b[5] == 0x41 && b[6] == 0xff && (b[7] & 0xf8) == 0xd0) return 1;
    if (b[6] == 0xff && (b[7] & 0xf8) == 0x10 && (b[7]&7)!=4 && (b[7]&7)!=5) return 1; /* call [reg] */
    return 0;
}
int main(int c, char **v) {
    if (task_for_pid(mach_task_self(), atoi(v[1]), &t)) return 1;
    int n = atoi(v[2]);
    thread_act_array_t th; mach_msg_type_number_t cnt; task_threads(t, &th, &cnt);
    thread_act_t best = 0; double bt = -1;
    for (unsigned i = 0; i < cnt; i++) { thread_basic_info_data_t b; mach_msg_type_number_t bc = THREAD_BASIC_INFO_COUNT;
        thread_info(th[i], THREAD_BASIC_INFO, (thread_info_t)&b, &bc);
        double tt = b.user_time.seconds + b.system_time.seconds; if (tt > bt) { bt = tt; best = th[i]; } }
    static uint64_t buf[8192];
    for (int k = 0; k < n; k++) {
        thread_suspend(best);
        arm_thread_state64_t s; mach_msg_type_number_t sc = ARM_THREAD_STATE64_COUNT;
        thread_get_state(best, ARM_THREAD_STATE64, (thread_state_t)&s, &sc);
        uint64_t pc = arm_thread_state64_get_pc(s), rsp = s.__x[4];
        int jit = pc >= 0x200000000ULL && pc < 0x210000000ULL;
        if (jit && rsp > 0x10000 && rsp < 0x7fff00000000ULL) {
            size_t got = 0;
            for (size_t off = 0; off < sizeof buf; off += 512) { if (!rd(rsp + off, (char *)buf + off, 512)) break; got += 512; }
            printf("S");
            int m = 0;
            for (size_t i = 0; i < got / 8 && m < 40; i++) if (is_ret(buf[i])) { printf(" %llx", buf[i]); m++; }
            printf("\n");
        }
        thread_resume(best); usleep(3000);
    }
    return 0;
}
