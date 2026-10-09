/* 最小 CRT 進入點：以 msvcrt!__getmainargs 取得 argc/argv 後呼叫 main。
 * 供不依賴 Windows SDK、以 clang-cl + lld-link 建置的工具使用（見 tools/build.sh 的 nosdk_exe）。 */
__declspec(dllimport) int __cdecl __getmainargs(int *, char ***, char ***, int, void *);
__declspec(dllimport) void __cdecl exit(int);
int main(int, char **);
void mainCRTStartup(void)
{
    int argc, si = 0;
    char **argv, **env;
    __getmainargs(&argc, &argv, &env, 0, &si);
    exit(main(argc, argv));
}
