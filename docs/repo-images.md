# Repo 圖片

README 頂部主圖與 GitHub 社群預覽圖的產生與更新。

`just repo-images` 以 `tools/src/repo-images/` 的 HTML 範本與 App 視窗截圖產生圖片；用法、截圖方式與需求見 `tools/dev/repo-images.sh` 開頭。

- `social-preview.jpg`：在 repo「Settings → General → Social preview」上傳，不放進 repo。
- `readme-hero-light.jpg`、`readme-hero-dark.jpg`：`--update-readme` 複製到 `docs/images/`，README 頂部的 `<picture>` 依 GitHub 淺色／深色模式切換；檔名與 `README.md` 的 `srcset` 一致。

App 介面改變後重新擷取截圖並執行 `just repo-images --update-readme` 後提交；社群預覽圖要另外到 Settings 重新上傳。
