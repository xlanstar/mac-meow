/* memdump <pid> <addr-hex> <len>：讀目標程序記憶體並輸出可列印字串（≥4 字元）與 hexdump 開頭。 */
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
int main(int c, char **v) {
    mach_port_t t; if (c < 4 || task_for_pid(mach_task_self(), atoi(v[1]), &t)) return 1;
    uint64_t a = strtoull(v[2], 0, 16); size_t n = strtoul(v[3], 0, 0);
    unsigned char *b = calloc(1, n); mach_vm_size_t got = 0;
    for (size_t off = 0; off < n; off += 4096) { mach_vm_size_t g = 0; size_t l = n - off < 4096 ? n - off : 4096;
        if (!mach_vm_read_overwrite(t, a + off, l, (mach_vm_address_t)(b + off), &g)) got = off + g; }
    printf("read %llu bytes\n", got);
    size_t s = 0;
    for (size_t i = 0; i <= got; i++) {
        if (i < got && (isprint(b[i]) || b[i] == '\n' || b[i] == '\t')) continue;
        if (i - s >= 6) { printf("0x%llx: ", a + s); fwrite(b + s, 1, i - s, stdout); printf("\n"); }
        s = i + 1;
    }
    return 0;
}
