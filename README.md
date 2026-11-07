# BigFontTuner

Adjust the font size, typeface and outline of in-game text for **World of Warcraft: Forever** (Interface 16001), with a live preview. The first release covers the quest window; chat, gossip and map categories will follow.

- `/bft` (or `/bigfonttuner` if `/bft` is taken by another addon) toggles the settings window.
- Default changes nothing; "reset" returns to the game's original fonts.
- Smaller text in the same group (e.g. quest objectives) scales proportionally.
- Settings are saved account-wide. MIT licensed.

---

## 中文說明

魔獸世界：永恆（Interface 16001）用的字體調整 addon。可以調整遊戲文字的字級、字型和描邊，並即時預覽效果。第一版只支援任務視窗，之後會陸續加入聊天、對話、地圖。

## 安裝

把整個 `BigFontTuner` 資料夾放到遊戲目錄的 `_forever_/Interface/AddOns/`，然後在角色選擇畫面左下角的「插件」中勾選。

如果之前裝過舊版 `BigQuestText`，請先刪除那個資料夾，否則兩個 addon 會同時修改任務字型。

## 使用

- 輸入 `/bigfonttuner` 開啟設定。如果 `/bft` 沒被其他 addon 佔用，也可以用 `/bft`。
- 指令會開關一個獨立的設定視窗，可以拖曳，按 Esc 關閉。如果遊戲的選項裡有「插件」分類，那裡也會有一個「開啟設定視窗」按鈕。
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
| `Fonts.lua` | 候選字型清單與存在檢查（用 pcall 包 SetFont，檔案不存在時 SetFont 會報錯） |
| `Core.lua` | 分類定義、設定儲存（`BigFontTunerDB`）、套用字型、斜線指令 |
| `Settings.lua` | 獨立設定視窗與即時預覽（內建選項只放入口按鈕） |

## 測試

`tests/harness.lua` 用假的 WoW API 跑載入流程，驗證設定儲存、套用、字型驗證、指令註冊等邏輯，不驗畫面。這個檔沒有列在 toc 裡，遊戲不會載入。

```
lua tests/harness.lua .
```
