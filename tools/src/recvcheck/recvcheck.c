/* 檢查 wsock32!recv 與 ws2_32!recv 是否為不同位址，並各自實際收資料（loopback TCP 連線）。 */
#include <winsock2.h>
#include <stdio.h>

typedef int (WINAPI *recv_t)(SOCKET, char *, int, int);

/* 由 client 送出 msg，以 recv_fn 在 server 端收下並印出 */
static void check_recv(const char *label, recv_t recv_fn, SOCKET client, SOCKET server, const char *msg) {
    char buf[16] = {0};
    send(client, msg, 5, 0);
    int n = recv_fn(server, buf, sizeof buf, 0);
    printf("%s recv=%d '%.*s'\n", label, n, n > 0 ? n : 0, buf);
}

int main(void) {
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
    recv_t r1 = (recv_t)GetProcAddress(LoadLibraryA("wsock32.dll"), "recv");
    recv_t r2 = (recv_t)GetProcAddress(LoadLibraryA("ws2_32.dll"), "recv");
    printf("wsock32!recv=%p ws2_32!recv=%p %s\n", r1, r2, r1 == r2 ? "SAME (bug)" : "distinct (ok)");

    SOCKET listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in addr = {0};
    int addr_len = sizeof addr;
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(listener, (struct sockaddr *)&addr, sizeof addr);
    listen(listener, 1);
    getsockname(listener, (struct sockaddr *)&addr, &addr_len);
    SOCKET client = socket(AF_INET, SOCK_STREAM, 0);
    connect(client, (struct sockaddr *)&addr, sizeof addr);
    SOCKET server = accept(listener, 0, 0);

    check_recv("wsock32", r1, client, server, "hello");
    check_recv("ws2_32 ", r2, client, server, "world");
    return 0;
}
