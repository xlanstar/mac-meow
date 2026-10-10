/* callchain <pid> <samples>：對 CPU 時間最高的執行緒取樣（Rosetta 翻譯碼中 x4=rsp），
 * 只輸出「前一條指令是 call」的堆疊值（可信的返回位址），每行一個樣本（"S" 加位址），由內而外。 */
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define STACK_BYTES 65536
#define STACK_CHUNK 512
#define MAX_RETURNS 40
/* Rosetta 翻譯碼所在的位址範圍 */
#define JIT_START 0x200000000ULL
#define JIT_END 0x210000000ULL

static mach_port_t task;

static int readmem(uint64_t addr, void *buf, size_t len) {
    mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(task, addr, len, (mach_vm_address_t)buf, &got) == KERN_SUCCESS && got == len;
}

/* ModRM 的 reg 欄位為 /2（call）且 mod 欄位為 mod */
static int call_modrm(uint8_t modrm, uint8_t mod) {
    return (modrm & 0x38) == 0x10 && (modrm & 0xc0) == mod;
}

/* v 前面的位元組是否以某種 call 指令結尾（b[7] 是 v 前一個位元組） */
static int is_ret(uint64_t v) {
    uint8_t b[8];
    if (v < 0x10000 || v > 0x7fffffffffffULL) return 0;
    if (!readmem(v - 8, b, sizeof b)) return 0;
    if (b[3] == 0xe8) return 1;                                                  /* call rel32 */
    if (b[2] == 0xff && b[3] == 0x15) return 1;                                  /* call [rip+d32] */
    if (b[2] == 0xff && call_modrm(b[3], 0x80)) return 1;                        /* call [r+d32] */
    if (b[1] == 0xff && call_modrm(b[2], 0x80) && (b[2] & 7) == 4) return 1;     /* call [sib+d32] */
    if (b[5] == 0xff && call_modrm(b[6], 0x40)) return 1;                        /* call [r+d8] */
    if (b[4] == 0xff && call_modrm(b[5], 0x40) && (b[5] & 7) == 4) return 1;     /* call [sib+d8] */
    if (b[6] == 0xff && call_modrm(b[7], 0xc0)) return 1;                        /* call reg */
    if (b[5] == 0x41 && b[6] == 0xff && call_modrm(b[7], 0xc0)) return 1;        /* call r8-r15 */
    if (b[6] == 0xff && call_modrm(b[7], 0x00) && (b[7] & 7) != 4 && (b[7] & 7) != 5) return 1; /* call [reg] */
    return 0;
}

/* CPU 時間（user + system 秒數）最高的執行緒 */
static thread_act_t busiest_thread(void) {
    thread_act_array_t th;
    mach_msg_type_number_t n = 0;
    thread_act_t best = MACH_PORT_NULL;
    double best_time = -1;
    if (task_threads(task, &th, &n) != KERN_SUCCESS) return MACH_PORT_NULL;
    for (unsigned i = 0; i < n; i++) {
        thread_basic_info_data_t b;
        mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
        thread_info(th[i], THREAD_BASIC_INFO, (thread_info_t)&b, &count);
        double t = b.user_time.seconds + b.system_time.seconds;
        if (t > best_time) {
            best_time = t;
            best = th[i];
        }
    }
    return best;
}

static void sample(thread_act_t th) {
    static uint64_t stack[STACK_BYTES / 8];
    arm_thread_state64_t s;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(th, ARM_THREAD_STATE64, (thread_state_t)&s, &count) != KERN_SUCCESS) return;
    uint64_t pc = arm_thread_state64_get_pc(s), rsp = s.__x[4];
    int jit = pc >= JIT_START && pc < JIT_END;
    if (!jit || rsp <= 0x10000 || rsp >= 0x7fff00000000ULL) return;

    size_t got = 0;
    while (got < sizeof stack && readmem(rsp + got, (char *)stack + got, STACK_CHUNK)) got += STACK_CHUNK;
    printf("S");
    int found = 0;
    for (size_t i = 0; i < got / 8 && found < MAX_RETURNS; i++) {
        if (!is_ret(stack[i])) continue;
        printf(" %llx", stack[i]);
        found++;
    }
    printf("\n");
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <pid> <samples>\n", argv[0]);
        return 2;
    }
    if (task_for_pid(mach_task_self(), atoi(argv[1]), &task)) return 1;
    int samples = atoi(argv[2]);
    thread_act_t th = busiest_thread();
    if (th == MACH_PORT_NULL) {
        fprintf(stderr, "task_threads failed\n");
        return 1;
    }
    for (int i = 0; i < samples; i++) {
        thread_suspend(th);
        sample(th);
        thread_resume(th);
        usleep(3000);
    }
    return 0;
}
