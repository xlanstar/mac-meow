/* rsaenh.dll 反覆載入/卸載測試：重現「同位址卸載後再映射」是否會在 Wine/Rosetta 下卡死。
 * 背景執行緒持續載入/卸載，主執行緒 300 次載入並查 CPAcquireContext，印出經過毫秒數。 */
typedef void *HANDLE;
typedef unsigned long DWORD;
typedef int BOOL;
#define WINAPI __stdcall
__declspec(dllimport) HANDLE WINAPI LoadLibraryA(const char *);
__declspec(dllimport) BOOL WINAPI FreeLibrary(HANDLE);
__declspec(dllimport) void *WINAPI GetProcAddress(HANDLE, const char *);
__declspec(dllimport) HANDLE WINAPI CreateThread(void *, unsigned long long, DWORD (WINAPI *)(void *), void *, DWORD, DWORD *);
__declspec(dllimport) DWORD WINAPI GetTickCount(void);
__declspec(dllimport) int __cdecl printf(const char *, ...);
__declspec(dllimport) int __cdecl _flushall(void);

#define ITERATIONS 300

static volatile int stop;

static DWORD WINAPI worker(void *unused) {
    (void)unused;
    while (!stop) {
        HANDLE h = LoadLibraryA("rsaenh.dll");
        if (h) FreeLibrary(h);
    }
    return 0;
}

int main(void) {
    DWORD t0 = GetTickCount();
    CreateThread(0, 0, worker, 0, 0, 0);
    for (int i = 0; i < ITERATIONS; i++) {
        HANDLE h = LoadLibraryA("rsaenh.dll");
        void *f = h ? GetProcAddress(h, "CPAcquireContext") : 0;
        printf("iter %d h=%p f=%p t=%lu\n", i, h, f, GetTickCount() - t0);
        _flushall();
        if (h) FreeLibrary(h);
    }
    stop = 1;
    printf("done\n");
    return 0;
}
