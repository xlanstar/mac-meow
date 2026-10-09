/* 檢查 wsock32!recv 與 ws2_32!recv 是否為不同位址，並各自實際收資料（socketpair 經 loopback）。 */
#include <winsock2.h>
#include <stdio.h>
typedef int (WINAPI *recv_t)(SOCKET, char *, int, int);
int main(void) {
    WSADATA w; WSAStartup(MAKEWORD(2, 2), &w);
    recv_t r1 = (recv_t)GetProcAddress(LoadLibraryA("wsock32.dll"), "recv");
    recv_t r2 = (recv_t)GetProcAddress(LoadLibraryA("ws2_32.dll"), "recv");
    printf("wsock32!recv=%p ws2_32!recv=%p %s\n", r1, r2, r1 == r2 ? "SAME (bug)" : "distinct (ok)");
    SOCKET l = socket(AF_INET, SOCK_STREAM, 0); struct sockaddr_in a = {0}; int al = sizeof a;
    a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(l, (struct sockaddr *)&a, sizeof a); listen(l, 1); getsockname(l, (struct sockaddr *)&a, &al);
    SOCKET c = socket(AF_INET, SOCK_STREAM, 0); connect(c, (struct sockaddr *)&a, sizeof a);
    SOCKET s = accept(l, 0, 0); char buf[16] = {0};
    send(c, "hello", 5, 0); int n1 = r1(s, buf, sizeof buf, 0); printf("wsock32 recv=%d '%.*s'\n", n1, n1 > 0 ? n1 : 0, buf);
    send(c, "world", 5, 0); int n2 = r2(s, buf, sizeof buf, 0); printf("ws2_32  recv=%d '%.*s'\n", n2, n2 > 0 ? n2 : 0, buf);
    return 0;
}
