/* 網路瞬斷時 TCP 連線的行為：送資料時收到哪個錯誤、忽略錯誤繼續重送後連線能否存活。
 *
 * 以 HTTP/1.1 keep-alive 連到 <host>:80，每 <interval_ms> 在同一條連線送一次 HEAD，計算收到的回應數。
 * 送出失敗時記錄錯誤、保留這筆請求，下一輪重送（模擬「把暫時性錯誤當成 would-block」的修補）；
 * 收到 EOF 或 recv 錯誤才結束。執行期間關閉 Wi-Fi 數秒再打開，看錯誤碼與之後是否繼續收到回應。
 *
 * 同一份原始碼建置 macOS 原生版（blip）與 Windows 版（blip.exe，在 Wine 內執行，看 Winsock 回報的錯誤）。
 * 用法：blip [host] [秒數] [interval_ms]   預設 www.cloudflare.com 40 250 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
typedef SOCKET sock_t;
#define sock_err() WSAGetLastError()
#define WOULDBLOCK(e) ((e) == WSAEWOULDBLOCK)
static double now(void) { return GetTickCount64() / 1000.0; }
static void nap(int ms) { Sleep(ms); }
static const char *errname(int e) {
    static char buf[64];
    snprintf(buf, sizeof buf, "WSA %d", e);
    return buf;
}
#else
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/select.h>
#include <time.h>
#include <unistd.h>
typedef int sock_t;
#define closesocket close
#define sock_err() errno
#define WOULDBLOCK(e) ((e) == EWOULDBLOCK || (e) == EAGAIN)
static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}
static void nap(int ms) { usleep(ms * 1000); }
static const char *errname(int e) { return strerror(e); }
#endif

static double t0;
#define LOG(...) (printf("%7.3f ", now() - t0), printf(__VA_ARGS__), printf("\n"), fflush(stdout))

static void log_local(sock_t s) {
    struct sockaddr_in a;
    socklen_t len = sizeof a;
    if (getsockname(s, (struct sockaddr *)&a, &len) == 0)
        LOG("local %s:%d", inet_ntoa(a.sin_addr), ntohs(a.sin_port));
    else
        LOG("getsockname failed: %s", errname(sock_err()));
}

int main(int argc, char **argv) {
    const char *host = argc > 1 ? argv[1] : "www.cloudflare.com";
    double secs = argc > 2 ? atof(argv[2]) : 40;
    int interval = argc > 3 ? atoi(argv[3]) : 250;
    char req[256], buf[65536];
    int reqlen, sent = 0, pending = 0, responses = 0, requests = 0, send_errors = 0;
    double next = 0, last_local = 0;
#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
    setvbuf(stdout, NULL, _IOLBF, 0);
    t0 = now();

    struct addrinfo hints = {0}, *ai;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, "80", &hints, &ai)) {
        LOG("getaddrinfo(%s) failed", host);
        return 1;
    }
    sock_t s = socket(AF_INET, SOCK_STREAM, 0);
    if (connect(s, ai->ai_addr, ai->ai_addrlen)) {
        LOG("connect failed: %s", errname(sock_err()));
        return 1;
    }
    LOG("connected to %s (%s)", host, inet_ntoa(((struct sockaddr_in *)ai->ai_addr)->sin_addr));
    log_local(s);
#ifdef _WIN32
    u_long nb = 1;
    ioctlsocket(s, FIONBIO, &nb);
#else
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
#endif
    reqlen = snprintf(req, sizeof req, "HEAD / HTTP/1.1\r\nHost: %s\r\nConnection: keep-alive\r\n\r\n", host);

    while (now() - t0 < secs) {
        double t = now() - t0;
        if (t - last_local >= 1) {
            last_local = t;
            int soerr = 0;
            socklen_t len = sizeof soerr;
            getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&soerr, &len);
            if (soerr) LOG("SO_ERROR %s", errname(soerr));
        }
        /* 送：上一筆送完才開始新的一筆；送失敗則保留，下一輪重送剩下的部分 */
        if (t >= next) {
            next = t + interval / 1000.0;
            if (!pending) {
                pending = 1;
                sent = 0;
                requests++;
            }
            int n = send(s, req + sent, reqlen - sent, 0);
            if (n < 0) {
                int e = sock_err();
                if (!WOULDBLOCK(e)) {
                    send_errors++;
                    LOG("send error: %s (req %d)", errname(e), requests);
                }
            } else if ((sent += n) == reqlen) {
                pending = 0;
            }
        }
        /* 收 */
        fd_set rf;
        FD_ZERO(&rf);
        FD_SET(s, &rf);
        struct timeval tv = {0, 20000};
        if (select((int)s + 1, &rf, NULL, NULL, &tv) > 0) {
            int n = recv(s, buf, sizeof buf - 1, 0);
            if (n == 0) {
                LOG("EOF (responses %d)", responses);
                break;
            }
            if (n < 0) {
                int e = sock_err();
                if (!WOULDBLOCK(e)) {
                    LOG("recv error: %s (responses %d)", errname(e), responses);
                    break;
                }
            } else {
                buf[n] = 0;
                int before = responses;
                for (char *p = buf; (p = strstr(p, "HTTP/1.1 ")); p++) responses++;
                if (responses / 20 != before / 20) LOG("responses %d / requests %d", responses, requests);
            }
        }
        nap(1);
    }
    log_local(s);
    LOG("done: requests %d responses %d send_errors %d", requests, responses, send_errors);
    closesocket(s);
    return 0;
}
