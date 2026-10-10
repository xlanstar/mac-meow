/* x86_64 輔助程式（在 Rosetta 下執行）：從 stdin 每行讀一個十六進位位址，以 dladdr 解析 x86 shared cache 符號。
 * 輸出「位址 檔名`符號+偏移」，查不到時為「位址 ?」（symbolize.py 解析）。
 * dladdr 只認得本程序已載入的映像，所以先載入遊戲常經過的系統框架（Metal、Cocoa 等）。 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *basename_of(const char *path) {
    if (!path) return "?";
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static const char *const preload[] = {
    "/System/Library/Frameworks/AppKit.framework/AppKit",
    "/System/Library/Frameworks/Metal.framework/Metal",
    "/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
    "/System/Library/Frameworks/IOKit.framework/IOKit",
    "/System/Library/Frameworks/IOSurface.framework/IOSurface",
    "/System/Library/Frameworks/CoreAudio.framework/CoreAudio",
    "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",
};

int main(void) {
    char line[64];
    for (size_t i = 0; i < sizeof preload / sizeof *preload; i++) dlopen(preload[i], RTLD_LAZY);
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
