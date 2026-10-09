/* x86_64 輔助程式（在 Rosetta 下執行）：從 stdin 讀位址，以 dladdr 解析 x86 shared cache 符號。 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    char line[64];
    while (fgets(line, sizeof line, stdin)) {
        unsigned long long a = strtoull(line, 0, 16); Dl_info d;
        if (a && dladdr((void *)a, &d) && d.dli_sname)
            printf("%llx %s`%s+%llu\n", a, d.dli_fname ? (strrchr(d.dli_fname,'/')?strrchr(d.dli_fname,'/')+1:d.dli_fname) : "?", d.dli_sname, a - (unsigned long long)d.dli_saddr);
        else printf("%llx ?\n", a);
        fflush(stdout);
    }
    return 0;
}
