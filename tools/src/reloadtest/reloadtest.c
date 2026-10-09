/* rsaenh.dll 反覆載入/卸載測試：重現「同位址卸載後再映射」是否會在 Wine/Rosetta 下卡死。 */
typedef void *HANDLE; typedef unsigned long DWORD; typedef int BOOL;
#define WINAPI __stdcall
__declspec(dllimport) HANDLE WINAPI LoadLibraryA(const char *);
__declspec(dllimport) BOOL WINAPI FreeLibrary(HANDLE);
__declspec(dllimport) void *WINAPI GetProcAddress(HANDLE, const char *);
__declspec(dllimport) HANDLE WINAPI CreateThread(void *, unsigned long long, DWORD (WINAPI *)(void *), void *, DWORD, DWORD *);
__declspec(dllimport) DWORD WINAPI GetTickCount(void);
__declspec(dllimport) int __cdecl printf(const char *, ...);
__declspec(dllimport) int __cdecl _flushall(void);
static volatile int stop;
static DWORD WINAPI worker(void *p) {
    volatile unsigned long long x = 0;
    while (!stop) { HANDLE h = LoadLibraryA("rsaenh.dll"); if (h) FreeLibrary(h); x++; }
    return 0;
}
int main(void) {
    DWORD t0 = GetTickCount();
    CreateThread(0, 0, worker, 0, 0, 0);
    for (int i = 0; i < 300; i++) {
        HANDLE h = LoadLibraryA("rsaenh.dll");
        void *f = h ? GetProcAddress(h, "CPAcquireContext") : 0;
        printf("iter %d h=%p f=%p t=%lu\n", i, h, f, GetTickCount() - t0); _flushall();
        if (h) FreeLibrary(h);
    }
    stop = 1;
    printf("done\n");
    return 0;
}
