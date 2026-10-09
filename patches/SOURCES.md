# Wine 修補與預先建置的 DLL

`patches/bin/x86_64-windows/` 內的 DLL 由下列原始碼建置，授權為 **LGPL-2.1-or-later**（與 Wine 相同）。

| 項目 | 內容 |
|---|---|
| 原始碼 | CrossOver 26.3.0 原始碼（CodeWeavers 公開提供）<br>`https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz` |
| 原始碼 SHA-256 | `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872` |
| 修補 | `wsock32-distinct-recv.patch`（wsock32!recv 獨立化）<br>`advapi32-pin-csp.patch`（CSP 常駐） |
| 目標 engine | Cyder `CX26.3.0-W11-Cyder012`（CrossOver 26.3.0 / Wine 11.0 基底）；`patch-cyder-dlls.sh` 只會套用到 CrossOver 基底為 26.3.0 的 engine |
| 重建 | `bash tools/build-wine-dlls.sh`（下載原始碼 → 套修補 → 只建置這兩個 DLL → strip） |
| 校驗 | `bin/SHA256SUMS` |

修補原因與驗證過程見 `docs/technical-notes.md`。
