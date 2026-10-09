/* x86_64 輔助程式（在 Rosetta 下執行）：從 stdin 每行讀一個十六進位位址，以 dladdr 解析 x86 shared cache 符號。
 * 輸出「位址 檔名`符號+偏移」，查不到時為「位址 ?」（symbolize.py 解析）。 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *basename_of(const char *path) {
    if (!path) return "?";
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

int main(void) {
    char line[64];
    while (fgets(line, sizeof line, stdin)) {
        unsigned long long a = strtoull(line, 0, 16);
        Dl_info d;
        if (a && dladdr((void *)a, &d) && d.dli_sname)
            printf("%llx %s`%s+%llu\n", a, basename_of(d.dli_fname), d.dli_sname, a - (unsigned long long)d.dli_saddr);
        else
            printf("%llx ?\n", a);
        fflush(stdout);
    }
    return 0;
}
