/* wthreads.exe <pid-hex> [n] [tid-hex]
 * 唯讀診斷：列出 Windows 程序每條執行緒的 suspend count、RIP/RSP，
 * 並掃描堆疊中落在已載入模組內的位址（近似呼叫堆疊）。
 *   n        只查 suspend count，不 SuspendThread、不取 context
 *   tid-hex  只處理指定執行緒
 * 不寫入目標程序記憶體；取 context 時會短暫 SuspendThread/ResumeThread。
 * 以 mingw-w64 建置（見 tools/build.sh）。 */
#include <windows.h>
#include <tlhelp32.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>

typedef ULONGLONG U64;

#define PROCESS_VM_READ_QUERY (PROCESS_VM_READ | PROCESS_QUERY_INFORMATION)
#define THREAD_SUSPEND_CONTEXT_QUERY (THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION)
#define THREAD_SUSPEND_COUNT_CLASS ((THREADINFOCLASS)35) /* ThreadSuspendCount（mingw 標頭未定義） */
#define SUSPEND_FAILED ((DWORD)-1)

#define MAX_MODS 512
#define MAX_STACK_HITS 40

typedef struct {
    U64 base, size;
    WCHAR name[64];
} MOD;
static MOD mods[MAX_MODS];
static int nmods;
static CONTEXT ctx;
static U64 stackbuf[16384];

static U64 min_u64(U64 a, U64 b) {
    return a < b ? a : b;
}

static const MOD *find_mod(U64 a) {
    for (int i = 0; i < nmods; i++) {
        if (a >= mods[i].base && a < mods[i].base + mods[i].size) return &mods[i];
    }
    return 0;
}

static void load_modules(DWORD pid) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, pid);
    if (snap == INVALID_HANDLE_VALUE) {
        printf("module snapshot failed %lu\n", GetLastError());
        return;
    }
    MODULEENTRY32W me;
    me.dwSize = sizeof(me);
    for (BOOL ok = Module32FirstW(snap, &me); ok && nmods < MAX_MODS; ok = Module32NextW(snap, &me)) {
        MOD *m = &mods[nmods++];
        m->base = (U64)me.modBaseAddr;
        m->size = me.modBaseSize;
        int k = 0;
        for (; k < 63 && me.szModule[k]; k++) m->name[k] = me.szModule[k];
        m->name[k] = 0;
        printf("module %016llx %08lx %ls\n", m->base, (unsigned long)m->size, m->name);
    }
    CloseHandle(snap);
}

/* 從 rsp 讀堆疊到 stackbuf，回傳讀到的位元組數。逐頁讀取：堆疊頂端之後可能是未映射區，一次大量讀取會整體失敗。 */
static U64 read_stack(HANDLE proc, U64 rsp) {
    SIZE_T got = 0, part;
    while (proc && got < sizeof(stackbuf)
           && ReadProcessMemory(proc, (void *)(rsp + got), (BYTE *)stackbuf + got,
                                min_u64(4096 - ((rsp + got) & 4095), sizeof(stackbuf) - got), &part)
           && part)
        got += part;
    return got;
}

/* 已暫停的執行緒：RIP/RSP/RBP 與堆疊中落在模組內的值 */
static void dump_context(HANDLE proc, HANDLE th) {
    ctx.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
    if (!GetThreadContext(th, &ctx)) {
        printf("  suspend/context failed %lu\n", GetLastError());
        return;
    }
    U64 rip = ctx.Rip, rsp = ctx.Rsp, rbp = ctx.Rbp;
    const MOD *m = find_mod(rip);
    printf("  rip=%016llx %ls+%llx rsp=%016llx rbp=%016llx\n", rip, m ? m->name : L"?", m ? rip - m->base : 0, rsp, rbp);
    U64 got = read_stack(proc, rsp);
    if (!got) {
        printf("  stack read failed %lu\n", GetLastError());
        return;
    }
    int hits = 0;
    for (U64 i = 0; i < got / 8 && hits < MAX_STACK_HITS; i++) {
        const MOD *mm = find_mod(stackbuf[i]);
        if (!mm) continue;
        printf("  [rsp+%05llx] %016llx %ls+%llx\n", i * 8, stackbuf[i], mm->name, stackbuf[i] - mm->base);
        hits++;
    }
}

static void dump_thread(HANDLE proc, DWORD tid, int want_ctx) {
    HANDLE th = OpenThread(THREAD_SUSPEND_CONTEXT_QUERY, 0, tid);
    if (!th) {
        printf("\nthread %04lx open failed %lu\n", tid, GetLastError());
        return;
    }
    DWORD count = 0xffffffff;
    LONG status = NtQueryInformationThread(th, THREAD_SUSPEND_COUNT_CLASS, &count, 4, 0);
    printf("\nthread %04lx suspend_count=%lu (status %lx)\n", tid, count, status);
    _flushall();
    if (want_ctx) {
        DWORD prev = SuspendThread(th);
        if (prev != SUSPEND_FAILED) {
            dump_context(proc, th);
        } else {
            printf("  suspend/context failed %lu\n", GetLastError());
        }
        _flushall();
        if (prev != SUSPEND_FAILED) ResumeThread(th);
    }
    CloseHandle(th);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("usage: wthreads <pid-hex> [n] [tid-hex]\n");
        return 2;
    }
    DWORD pid = strtoul(argv[1], 0, 16);
    int want_ctx = !(argc > 2 && argv[2][0] == 'n');
    DWORD only_tid = argc > 3 ? strtoul(argv[3], 0, 16) : 0;
    printf("pid %lx\n", pid);
    _flushall();
    load_modules(pid);
    _flushall();

    HANDLE proc = OpenProcess(PROCESS_VM_READ_QUERY, 0, pid);
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    THREADENTRY32 te;
    te.dwSize = sizeof(te);
    for (BOOL ok = Thread32First(snap, &te); ok; ok = Thread32Next(snap, &te)) {
        if (te.th32OwnerProcessID != pid) continue;
        if (only_tid && te.th32ThreadID != only_tid) continue;
        dump_thread(proc, te.th32ThreadID, want_ctx);
    }
    return 0;
}
