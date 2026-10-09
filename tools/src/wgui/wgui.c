/*
 * wgui：在 Wine 內列出視窗、送滑鼠點擊、擷取視窗畫面（不需 macOS 輔助使用／螢幕錄製權限）。
 *
 *   wgui list                         列出所有頂層視窗（含不可見）與子視窗
 *   wgui click <hwnd-hex> <x> <y>     對視窗 client 座標送 WM_LBUTTONDOWN/UP（PostMessage）
 *   wgui sclick <x> <y>               以 SendInput 在螢幕座標實際點擊（會移動游標）
 *   wgui shot <hwnd-hex> <out.bmp>    以 PrintWindow（失敗時 BitBlt）擷取視窗成 BMP
 *   wgui fg <hwnd-hex>                SetForegroundWindow
 *   wgui key <hwnd-hex> <vk-hex>      送 WM_KEYDOWN/UP
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <shellapi.h>

static void print_win(HWND h, int depth) {
    WCHAR cls[128] = L"", title[256] = L"";
    char ccls[512], ctitle[1024];
    RECT r; DWORD pid = 0;
    GetClassNameW(h, cls, 128); InternalGetWindowText(h, title, 256);
    WideCharToMultiByte(CP_UTF8, 0, cls, -1, ccls, sizeof ccls, 0, 0);
    WideCharToMultiByte(CP_UTF8, 0, title, -1, ctitle, sizeof ctitle, 0, 0);
    GetWindowRect(h, &r); GetWindowThreadProcessId(h, &pid);
    printf("%*s%p pid=%04lx vis=%d rect=(%ld,%ld)-(%ld,%ld) %ldx%ld style=%08lx ex=%08lx class='%s' title='%s'\n",
           depth * 2, "", h, pid, IsWindowVisible(h), r.left, r.top, r.right, r.bottom,
           r.right - r.left, r.bottom - r.top, GetWindowLongW(h, GWL_STYLE), GetWindowLongW(h, GWL_EXSTYLE), ccls, ctitle);
}
static BOOL CALLBACK child_cb(HWND h, LPARAM d) { if (GetParent(h) == (HWND)d) { print_win(h, 2); } return TRUE; }
static BOOL CALLBACK top_cb(HWND h, LPARAM d) {
    print_win(h, 0);
    EnumChildWindows(h, child_cb, (LPARAM)h);
    return TRUE;
}

static int save_bmp(HWND h, const char *out) {
    RECT r; GetWindowRect(h, &r);
    int w = r.right - r.left, ht = r.bottom - r.top;
    if (w <= 0 || ht <= 0) { printf("empty window\n"); return 1; }
    HDC wdc = GetWindowDC(h), mdc = CreateCompatibleDC(wdc);
    BITMAPINFO bi = {0};
    bi.bmiHeader.biSize = sizeof bi.bmiHeader; bi.bmiHeader.biWidth = w; bi.bmiHeader.biHeight = -ht;
    bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
    void *bits; HBITMAP bmp = CreateDIBSection(wdc, &bi, DIB_RGB_COLORS, &bits, 0, 0);
    HGDIOBJ old = SelectObject(mdc, bmp);
    BOOL ok = PrintWindow(h, mdc, 2 /* PW_RENDERFULLCONTENT */);
    if (!ok) ok = BitBlt(mdc, 0, 0, w, ht, wdc, 0, 0, SRCCOPY);
    printf("capture %s %dx%d\n", ok ? "ok" : "failed", w, ht);
    GdiFlush();
    FILE *f = fopen(out, "wb");
    if (!f) { printf("cannot open %s\n", out); return 1; }
    BITMAPFILEHEADER fh = {0};
    DWORD sz = w * ht * 4;
    fh.bfType = 0x4d42; fh.bfOffBits = sizeof fh + sizeof bi.bmiHeader; fh.bfSize = fh.bfOffBits + sz;
    fwrite(&fh, sizeof fh, 1, f); fwrite(&bi.bmiHeader, sizeof bi.bmiHeader, 1, f); fwrite(bits, 1, sz, f); fclose(f);
    SelectObject(mdc, old); DeleteObject(bmp); DeleteDC(mdc); ReleaseDC(h, wdc);
    return 0;
}

static int real_main(int argc, char **argv);
/* 自訂進入點：不依賴 CRT 啟動碼（winecrt0 與此連結方式不相容） */
void __cdecl start(void) {
    int argc, i; WCHAR **wargv = CommandLineToArgvW(GetCommandLineW(), &argc);
    char **argv = HeapAlloc(GetProcessHeap(), 0, sizeof(char *) * (argc + 1));
    for (i = 0; i < argc; i++) {
        int n = WideCharToMultiByte(CP_UTF8, 0, wargv[i], -1, 0, 0, 0, 0);
        argv[i] = HeapAlloc(GetProcessHeap(), 0, n); WideCharToMultiByte(CP_UTF8, 0, wargv[i], -1, argv[i], n, 0, 0);
    }
    argv[argc] = 0;
    int rc = real_main(argc, argv);
    fflush(stdout);
    ExitProcess(rc);
}
static int real_main(int argc, char **argv) {
    if (argc < 2) { printf("usage: wgui list|click|sclick|shot|fg|key ...\n"); return 2; }
    if (!strcmp(argv[1], "list")) { EnumWindows(top_cb, 0); return 0; }
    if (!strcmp(argv[1], "click") && argc >= 5) {
        HWND h = (HWND)(ULONG_PTR)strtoull(argv[2], 0, 16); int x = atoi(argv[3]), y = atoi(argv[4]);
        LPARAM lp = MAKELPARAM(x, y);
        PostMessageW(h, WM_MOUSEMOVE, 0, lp); Sleep(50);
        PostMessageW(h, WM_LBUTTONDOWN, MK_LBUTTON, lp); Sleep(80);
        PostMessageW(h, WM_LBUTTONUP, 0, lp);
        printf("clicked %p at %d,%d\n", h, x, y); return 0;
    }
    if (!strcmp(argv[1], "sclick") && argc >= 4) {
        int x = atoi(argv[2]), y = atoi(argv[3]);
        SetCursorPos(x, y); Sleep(100);
        INPUT in[2] = {0};
        in[0].type = in[1].type = INPUT_MOUSE;
        in[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN; in[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
        SendInput(1, &in[0], sizeof(INPUT)); Sleep(80); SendInput(1, &in[1], sizeof(INPUT));
        printf("sclick %d,%d\n", x, y); return 0;
    }
    if (!strcmp(argv[1], "shot") && argc >= 4) return save_bmp((HWND)(ULONG_PTR)strtoull(argv[2], 0, 16), argv[3]);
    if (!strcmp(argv[1], "fg") && argc >= 3) { printf("%d\n", SetForegroundWindow((HWND)(ULONG_PTR)strtoull(argv[2], 0, 16))); return 0; }
    if (!strcmp(argv[1], "key") && argc >= 4) {
        HWND h = (HWND)(ULONG_PTR)strtoull(argv[2], 0, 16); UINT vk = strtoul(argv[3], 0, 16);
        PostMessageW(h, WM_KEYDOWN, vk, 1); Sleep(50); PostMessageW(h, WM_KEYUP, vk, 0xc0000001);
        return 0;
    }
    printf("bad args\n"); return 2;
}
