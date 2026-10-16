# Repo 圖片

README 頂部主圖與 GitHub 社群預覽圖的產生與更新。

`just repo-images` 以 `tools/src/repo-images/` 的 HTML 範本產生圖片；用法與需求見 `tools/dev/repo-images.sh` 開頭。

- App 只在選單列，沒有可以截圖的視窗；圖中的選單列與選單由 `menu.js` 以 HTML 重現（淺色／深色都由同一份產生）。內容對應 App 在「遊戲執行中、環境全部就緒」時的選單。

- `social-preview.jpg`：在 repo「Settings → General → Social preview」上傳，不放進 repo。
- `readme-hero-light.jpg`、`readme-hero-dark.jpg`：`--update-readme` 複製到 `docs/images/`，README 頂部的 `<picture>` 依 GitHub 淺色／深色模式切換；檔名與 `README.md` 的 `srcset` 一致。

App 的選單項目或文字改變後，同步更新 `menu.js`，再執行 `just repo-images --update-readme` 後提交；社群預覽圖要另外到 Settings 重新上傳。
