/* noexc：清除繼承來的 task 例外 port 後執行指定程式。
 * 從某些父程序（例如 agent 工具、IDE 終端機）啟動時，會繼承一個處理 EXC_BAD_ACCESS 卻不修正的 task 例外 port，
 * 存取違規因此無限重試，看起來像「卡住」而不是崩潰（smc-same-page 的 smctest2 1、smctest3 曾被誤判為卡住）。
 * 用法：noexc <程式> [參數...] */
#include <mach/mach.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "用法：noexc <程式> [參數...]\n");
        return 64;
    }
    task_set_exception_ports(mach_task_self(), EXC_MASK_ALL & ~EXC_MASK_RPC_ALERT, MACH_PORT_NULL, EXCEPTION_DEFAULT,
                             THREAD_STATE_NONE);
    execv(argv[1], argv + 1);
    perror("execv");
    return 127;
}
