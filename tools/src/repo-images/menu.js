// 以 HTML 重現 MacMeow 的選單列選單（App 只在選單列，沒有可以截圖的視窗）。
// 內容對應 app/Sources/App/MenuBarContent.swift 與 app/Sources/UI/Menu/ 在「遊戲執行中、環境全部就緒」時的樣子；
// 選單項目或文字改變時一起更新這裡。版本號由 tools/dev/repo-images.sh 以 ?version= 傳入。
//
// 用法：在頁面放 <div class="screen"></div>（data-submenu="checklist" 時展開「環境檢查」），最後載入本檔。

const params = new URLSearchParams(location.search);
if (params.get("theme") === "dark") document.documentElement.classList.add("dark");
const version = params.get("version") || "";

// 「環境檢查」子選單（ChecklistMenu）：狀態列在選單中是停用的文字
const CHECKLIST = [
  { text: "✓  Cyder：/Applications/Cyder.app", disabled: true },
  { text: "✓  Windows 環境：已建立", disabled: true },
  { text: "✓  遊戲資料夾：~/Games/MapleStory", disabled: true },
  { text: "✓  本機網路位址：已設定，開機自動套用", disabled: true },
  { text: "✓  Wine 修補：已套用", disabled: true },
  { text: "✓  VB6 執行環境：已安裝", disabled: true },
  "-",
  { text: "更改遊戲資料夾…" },
];

// 主選單（MenuBarContent）
const MENU = [
  { text: "遊戲執行中", disabled: true },
  { text: "連線通道：4/4", disabled: true },
  "-",
  { text: "顯示登入器", key: "⌘L" },
  { text: "重新啟動" },
  { text: "全部關閉…", key: "⌘." },
  "-",
  { text: "環境檢查", submenu: "checklist" },
  { text: "遊戲設定", submenu: "settings" },
  "-",
  { text: "說明", submenu: "help" },
  { text: `貓貓谷 for Mac ${version}`.trim(), submenu: "about" },
  "-",
  { text: "結束貓貓谷 for Mac", key: "⌘Q" },
];

const SUBMENUS = { checklist: CHECKLIST };

// SF Symbols 的 pawprint.fill 無法在網頁使用，以相近的形狀代替
const PAW = `<svg viewBox="0 0 20 20" aria-hidden="true"><g fill="currentColor">
  <ellipse cx="10" cy="13.4" rx="4.6" ry="3.9"/>
  <ellipse cx="4.1" cy="8.6" rx="1.9" ry="2.4" transform="rotate(-20 4.1 8.6)"/>
  <ellipse cx="7.8" cy="4.9" rx="1.9" ry="2.5" transform="rotate(-6 7.8 4.9)"/>
  <ellipse cx="12.2" cy="4.9" rx="1.9" ry="2.5" transform="rotate(6 12.2 4.9)"/>
  <ellipse cx="15.9" cy="8.6" rx="1.9" ry="2.4" transform="rotate(20 15.9 8.6)"/>
</g></svg>`;

function menu(items, openSubmenu) {
  const el = document.createElement("div");
  el.className = "menu";
  for (const item of items) {
    if (item === "-") {
      el.insertAdjacentHTML("beforeend", '<div class="sep"></div>');
      continue;
    }
    const row = document.createElement("div");
    row.className = "item";
    if (item.disabled) row.classList.add("disabled");
    const open = item.submenu && item.submenu === openSubmenu;
    if (open) row.classList.add("selected");
    row.insertAdjacentHTML("beforeend", `<span class="label"></span>`);
    row.querySelector(".label").textContent = item.text;
    if (item.key) row.insertAdjacentHTML("beforeend", `<span class="key">${item.key}</span>`);
    if (item.submenu) row.insertAdjacentHTML("beforeend", '<span class="chevron">›</span>');
    el.appendChild(row);
    if (open) {
      const sub = menu(SUBMENUS[item.submenu], null);
      sub.classList.add("submenu");
      row.appendChild(sub);
    }
  }
  return el;
}

for (const screen of document.querySelectorAll(".screen")) {
  const openSubmenu = screen.dataset.submenu || null;
  screen.insertAdjacentHTML(
    "beforeend",
    `<div class="menubar"><span class="status-item">${PAW}</span><span class="clock">週五 下午9:41</span></div>`,
  );
  const dropdown = menu(MENU, openSubmenu);
  dropdown.classList.add("dropdown");
  screen.appendChild(dropdown);
  // 與 macOS 相同：選單左緣對齊選單列圖示，超出螢幕右緣時往左移；子選單往左開
  const icon = screen.querySelector(".status-item");
  dropdown.style.left = `${Math.min(icon.offsetLeft, screen.clientWidth - dropdown.offsetWidth - 6)}px`;
}
