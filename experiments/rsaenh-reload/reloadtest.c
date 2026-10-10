/* rsaenh.dll 反覆載入/卸載測試：重現「同位址卸載後再映射」是否會在 Wine/Rosetta 下卡死。
 * 背景執行緒持續載入/卸載，主執行緒 300 次載入並查 CPAcquireContext，印出經過毫秒數。 */
#include <windows.h>
#include <stdio.h>

#define ITERATIONS 300

static volatile int stop;

static DWORD WINAPI worker(void *unused) {
    (void)unused;
    while (!stop) {
        HMODULE h = LoadLibraryA("rsaenh.dll");
        if (h) FreeLibrary(h);
    }
    return 0;
}

int main(void) {
    DWORD t0 = GetTickCount();
    CreateThread(0, 0, worker, 0, 0, 0);
    for (int i = 0; i < ITERATIONS; i++) {
        HMODULE h = LoadLibraryA("rsaenh.dll");
        FARPROC f = h ? GetProcAddress(h, "CPAcquireContext") : 0;
        printf("iter %d h=%p f=%p t=%lu\n", i, (void *)h, (void *)f, GetTickCount() - t0);
        _flushall();
        if (h) FreeLibrary(h);
    }
    stop = 1;
    printf("done\n");
    return 0;
}
