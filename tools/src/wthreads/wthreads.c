/* wthreads.exe <pid-hex>
 * 唯讀診斷：列出 Windows 程序每條執行緒的 suspend count、RIP/RSP，
 * 並掃描堆疊中落在已載入模組內的位址（近似呼叫堆疊）。
 * 不寫入目標程序記憶體；取 context 時會短暫 SuspendThread/ResumeThread。
 * 以 clang-cl + lld-link 建置，不需 Windows SDK（見 build.sh）。 */
typedef unsigned long DWORD; typedef long LONG; typedef int BOOL; typedef void *HANDLE;
typedef unsigned short WCHAR; typedef unsigned long long U64; typedef unsigned char BYTE;
#define WINAPI __stdcall
#define INVALID_HANDLE_VALUE ((HANDLE)(long long)-1)

typedef struct { DWORD dwSize, cntUsage, th32ThreadID, th32OwnerProcessID; LONG tpBasePri, tpDeltaPri; DWORD dwFlags; } THREADENTRY32;
typedef struct { DWORD dwSize, th32ModuleID, th32ProcessID, GlblcntUsage, ProccntUsage; BYTE *modBaseAddr; DWORD modBaseSize; HANDLE hModule; WCHAR szModule[256]; WCHAR szExePath[260]; } MODULEENTRY32W;

__declspec(dllimport) HANDLE WINAPI CreateToolhelp32Snapshot(DWORD, DWORD);
__declspec(dllimport) BOOL WINAPI Thread32First(HANDLE, THREADENTRY32 *);
__declspec(dllimport) BOOL WINAPI Thread32Next(HANDLE, THREADENTRY32 *);
__declspec(dllimport) BOOL WINAPI Module32FirstW(HANDLE, MODULEENTRY32W *);
__declspec(dllimport) BOOL WINAPI Module32NextW(HANDLE, MODULEENTRY32W *);
__declspec(dllimport) HANDLE WINAPI OpenThread(DWORD, BOOL, DWORD);
__declspec(dllimport) HANDLE WINAPI OpenProcess(DWORD, BOOL, DWORD);
__declspec(dllimport) DWORD WINAPI SuspendThread(HANDLE);
__declspec(dllimport) DWORD WINAPI ResumeThread(HANDLE);
__declspec(dllimport) BOOL WINAPI GetThreadContext(HANDLE, void *);
__declspec(dllimport) BOOL WINAPI ReadProcessMemory(HANDLE, const void *, void *, U64, U64 *);
__declspec(dllimport) BOOL WINAPI CloseHandle(HANDLE);
__declspec(dllimport) DWORD WINAPI GetLastError(void);
__declspec(dllimport) LONG WINAPI NtQueryInformationThread(HANDLE, int, void *, DWORD, DWORD *);
__declspec(dllimport) int __cdecl printf(const char *, ...);
__declspec(dllimport) unsigned long __cdecl strtoul(const char *, char **, int);
__declspec(dllimport) int __cdecl _flushall(void);

typedef struct { U64 base, size; WCHAR name[64]; } MOD;
static MOD mods[512]; static int nmods;
static __declspec(align(16)) BYTE ctx[1232];
static U64 stackbuf[16384];

static U64 min_u64(U64 a, U64 b) { return a < b ? a : b; }

static const MOD *find_mod(U64 a) {
    for (int i = 0; i < nmods; i++) if (a >= mods[i].base && a < mods[i].base + mods[i].size) return &mods[i];
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) { printf("usage: wthreads <pid-hex>\n"); return 2; }
    DWORD pid = strtoul(argv[1], 0, 16);
    int want_ctx = !(argc > 2 && argv[2][0] == 'n');
    DWORD only_tid = argc > 3 ? strtoul(argv[3], 0, 16) : 0; /* 第三參數：只處理指定 tid（hex）*/ /* 第二參數 n：只查 suspend count，不 SuspendThread */
    printf("pid %lx\n", pid); _flushall();
    HANDLE ms = CreateToolhelp32Snapshot(8 /*SNAPMODULE*/, pid);
    if (ms != INVALID_HANDLE_VALUE) {
        MODULEENTRY32W me; me.dwSize = sizeof(me);
        for (BOOL ok = Module32FirstW(ms, &me); ok && nmods < 512; ok = Module32NextW(ms, &me)) {
            MOD *m = &mods[nmods++]; m->base = (U64)me.modBaseAddr; m->size = me.modBaseSize;
            int k = 0; for (; k < 63 && me.szModule[k]; k++) m->name[k] = me.szModule[k]; m->name[k] = 0;
            printf("module %016llx %08lx %ls\n", m->base, (unsigned long)m->size, m->name);
        }
        CloseHandle(ms);
    } else printf("module snapshot failed %lu\n", GetLastError());
    _flushall();

    HANDLE proc = OpenProcess(0x0410 /*VM_READ|QUERY_INFORMATION*/, 0, pid);
    HANDLE ts = CreateToolhelp32Snapshot(4 /*SNAPTHREAD*/, 0);
    THREADENTRY32 te; te.dwSize = sizeof(te);
    for (BOOL ok = Thread32First(ts, &te); ok; ok = Thread32Next(ts, &te)) {
        if (te.th32OwnerProcessID != pid) continue;
        if (only_tid && te.th32ThreadID != only_tid) continue;
        HANDLE th = OpenThread(0x0002 | 0x0008 | 0x0040 /*SUSPEND|GET_CONTEXT|QUERY*/, 0, te.th32ThreadID);
        if (!th) { printf("\nthread %04lx open failed %lu\n", te.th32ThreadID, GetLastError()); continue; }
        DWORD sc = 0xffffffff; LONG st = NtQueryInformationThread(th, 35 /*ThreadSuspendCount*/, &sc, 4, 0);
        printf("\nthread %04lx suspend_count=%lu (status %lx)\n", te.th32ThreadID, sc, st); _flushall();
        if (!want_ctx) { CloseHandle(th); continue; }
        DWORD prev = SuspendThread(th);
        *(DWORD *)(ctx + 0x30) = 0x100003; /* CONTEXT_AMD64 | CONTROL | INTEGER */
        if (prev != 0xffffffff && GetThreadContext(th, ctx)) {
            U64 rip = *(U64 *)(ctx + 0xF8), rsp = *(U64 *)(ctx + 0x98), rbp = *(U64 *)(ctx + 0xA0);
            const MOD *m = find_mod(rip);
            printf("  rip=%016llx %ls+%llx rsp=%016llx rbp=%016llx\n", rip, m ? m->name : L"?", m ? rip - m->base : 0, rsp, rbp);
            U64 got = 0, part;
            /* 逐頁讀取：堆疊頂端之後可能是未映射區，一次大量讀取會整體失敗。 */
            while (proc && got < sizeof(stackbuf) &&
                   ReadProcessMemory(proc, (void *)(rsp + got), (BYTE *)stackbuf + got,
                                     min_u64(4096 - ((rsp + got) & 4095), sizeof(stackbuf) - got), &part) && part)
                got += part;
            if (got) {
                int hits = 0;
                for (U64 i = 0; i < got / 8 && hits < 40; i++) {
                    const MOD *mm = find_mod(stackbuf[i]);
                    if (mm) { printf("  [rsp+%05llx] %016llx %ls+%llx\n", i * 8, stackbuf[i], mm->name, stackbuf[i] - mm->base); hits++; }
                }
            } else printf("  stack read failed %lu\n", GetLastError());
        } else printf("  suspend/context failed %lu\n", GetLastError());
        _flushall();
        if (prev != 0xffffffff) ResumeThread(th);
        CloseHandle(th);
    }
    return 0;
}
