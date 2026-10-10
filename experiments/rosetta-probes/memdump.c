/* memdump <pid> <addr-hex> <len>：讀目標程序記憶體，輸出讀到的位元組數與其中的可列印字串（≥6 字元，含換行與 tab）。 */
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>

#define CHUNK 4096
#define MIN_STRING 6

static int printable(unsigned char c) {
    return isprint(c) || c == '\n' || c == '\t';
}

int main(int argc, char **argv) {
    mach_port_t task;
    if (argc < 4) {
        fprintf(stderr, "usage: %s <pid> <addr-hex> <len>\n", argv[0]);
        return 1;
    }
    if (task_for_pid(mach_task_self(), atoi(argv[1]), &task)) return 1;
    uint64_t addr = strtoull(argv[2], 0, 16);
    size_t len = strtoul(argv[3], 0, 0);
    unsigned char *buf = calloc(1, len);
    if (!buf) return 1;

    /* 逐頁讀取；got 為最後一個讀取成功的區塊結尾 */
    mach_vm_size_t got = 0;
    for (size_t off = 0; off < len; off += CHUNK) {
        mach_vm_size_t g = 0;
        size_t n = len - off < CHUNK ? len - off : CHUNK;
        if (!mach_vm_read_overwrite(task, addr + off, n, (mach_vm_address_t)(buf + off), &g)) got = off + g;
    }
    printf("read %llu bytes\n", got);

    size_t start = 0;
    for (size_t i = 0; i <= got; i++) {
        if (i < got && printable(buf[i])) continue;
        if (i - start >= MIN_STRING) {
            printf("0x%llx: ", addr + start);
            fwrite(buf + start, 1, i - start, stdout);
            printf("\n");
        }
        start = i + 1;
    }
    free(buf);
    return 0;
}
