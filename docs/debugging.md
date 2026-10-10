# 除錯

診斷工具的使用注意事項與在 Rosetta 下除錯 Wine 程序的要點；一次性實驗見 [experiments/README.md](../experiments/README.md)。

## 診斷工具

`just`（即 `just --list`）列出所有指令與參數，完整用法、需求與副作用在各腳本開頭。常見的順序：

```sh
just sign-debug apply
just stack mach
just sign-debug restore
just run-game trace
just wgui list
```

`--list` 看不出的事項：

- GUI Wine 程式需要 Aqua 工作階段（見 [AGENTS.md](../AGENTS.md#runtime-pitfalls)「Runtime pitfalls」）；各腳本是否自行經 Terminal.app 執行見腳本開頭。
- 不是 recipe 的工具：`tools/src/machstack/pesym.py`（Wine PE 位址 → 函式名，用法見檔案開頭）。
- bottle 內執行的工具（`wthreads.exe`、`recvcheck.exe`）：執行方式見原始碼開頭。

## Rosetta 除錯要點

- `sample`／`spindump` 會在 CoreSymbolication 內崩潰；程序凍結時 LLDB 無法暫停。改用 `just stack mach`（machstack：`task_for_pid` + `thread_get_state`）。
- Rosetta 下 x86 暫存器的位置見 `tools/src/machstack/machstack.c`（`[sp+8]` 暫存器區塊註解）。
- LLDB（含 watchpoint）可附加執行中的 Rosetta 程序並取得精確 x86 `rip`，但不認得 Wine PE 映像；用 `pesym.py` 對照位址。
