# BigFontTuner

Adjust the font size, typeface and outline of in-game text for **World of Warcraft: Forever** (Interface 16001), with a live preview. The first release covers the quest window; chat, gossip and map categories will follow.

**Download:** [CurseForge](https://www.curseforge.com/wow/addons/bigfonttuner) (or grab the source from this repository).

- `/bft` (or `/bigfonttuner` if `/bft` is taken by another addon) toggles the settings window.
- Default changes nothing; "reset" returns to the game's original fonts.
- Smaller text in the same group (e.g. quest objectives) scales proportionally.
- Settings are saved account-wide. MIT licensed.
- UI text follows the client language (Traditional Chinese on zhTW clients, English elsewhere), or pick a language in the settings.
- Settings live under Options → AddOns → BigFontTuner; /bft jumps there, or opens a standalone window if it can't (e.g. in combat).

---

## 中文說明

魔獸世界：永恆（Interface 16001）用的字體調整 addon。可以調整遊戲文字的字級、字型和描邊，並即時預覽效果。第一版只支援任務視窗，之後會陸續加入聊天、對話、地圖。

## 安裝

從 [CurseForge](https://www.curseforge.com/wow/addons/bigfonttuner) 下載（CurseForge App 可自動更新），或直接從這個 repo 取得原始碼。

把整個 `BigFontTuner` 資料夾放到遊戲目錄的 `_forever_/Interface/AddOns/`，然後在角色選擇畫面左下角的「插件」中勾選。

如果之前裝過舊版 `BigQuestText`，請先刪除那個資料夾，否則兩個 addon 會同時修改任務字型。

## 使用

- 輸入 `/bigfonttuner` 開啟設定。如果 `/bft` 沒被其他 addon 佔用，也可以用 `/bft`。
- 設定放在「選項 → 插件 → BigFontTuner」。輸入指令會先嘗試跳到那一頁；跳不過去（或戰鬥中）時改開同樣內容的獨立視窗，可以拖曳，按 Esc 關閉。
- 介面語言預設跟隨客戶端（只有繁中客戶端顯示中文，其他語系顯示英文），也可以在設定裡選「English／繁體中文」，切換後按「重新載入」套用。
- 標題字級、內文字級、字型、描邊調整後都會立即套用，設定自動儲存，同帳號的角色共用。
- 預設不更動任何字型（維持遊戲原樣）；「恢復此分類預設」會回到遊戲原始狀態。同一組裡的小字（例如任務目標）會依原始比例一起縮放。
- 戰鬥中也能開設定視窗。

## 自訂字型

1. 把 `.ttf` 放到 `BigFontTuner/Fonts/`。字型必須包含中文字，否則中文會顯示成方塊。
2. 在 `Fonts.lua` 的 `FONT_CANDIDATES` 加一行：`{ key = "noto", label = "思源黑體", path = "Interface\\AddOns\\BigFontTuner\\Fonts\\NotoSansTC.ttf" }`

addon 啟動時會逐一檢查字型檔，載入失敗的不會出現在選單中。

## 檔案

| 檔案 | 內容 |
|---|---|
| `Locale.lua` | 介面文字（enUS、zhTW），其他語系退回英文 |
| `Fonts.lua` | 候選字型清單與存在檢查（用 pcall 包 SetFont，檔案不存在時 SetFont 會報錯） |
| `Core.lua` | 分類定義、設定儲存（`BigFontTunerDB`）、套用字型、斜線指令 |
| `Settings.lua` | 設定內容與即時預覽：主要在「選項 → 插件」頁，/bft 跳不過去時才開獨立視窗 |
| `Media/icon.tga` | 插件清單圖示（64×64） |
| `assets/` | CurseForge 用 logo（Codex 生成），不打包進 addon |

## 測試

`tests/harness.lua` 用假的 WoW API 跑載入流程，驗證設定儲存、套用、字型驗證、指令註冊等邏輯，不驗畫面。這個檔沒有列在 toc 裡，遊戲不會載入。

```
lua tests/harness.lua .
```
