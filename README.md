# BigFontTuner

Adjust the font size, typeface and outline of in-game text for **World of Warcraft: Forever** (Interface 16001), with a live preview. Categories: quest window, chat, NPC dialogue (gossip), map (zone name pop-ups, minimap zone name, map labels) bags (item stack counts, tooltip text) and the profession window (recipe list and recipe details).

**Download:** [CurseForge](https://www.curseforge.com/wow/addons/bigfonttuner) (or grab the source from this repository).

- `/bft` (or `/bigfonttuner` if `/bft` is taken by another addon), or the entry in the addon compartment next to the minimap, opens the settings.
- Chat: if no size is set, each chat window keeps the size chosen in the game's own chat settings; only the typeface and outline change.
- Whole UI font: one setting swaps the typeface of every game font (sizes and outlines stay). Categories set to "Follow whole UI" use it; a font chosen in a category takes priority. Names above heads, nameplates and combat numbers switch after /reload.
- Optional fonts (not included in the download because of their size): put `jf-openhuninn-2.1.ttf` (jf open Huninn) or `TaipeiSansTCBeta-Regular.ttf` (Taipei Sans TC), both SIL OFL 1.1, into `BigFontTuner/Fonts/` and they appear in the font menu. Restart the game completely after adding font files; /reload does not pick up new files.
- Bags: stack counts change only on bag slots (action bars are untouched) and keep their outline unless one is chosen; tooltip text changes every tooltip, not just items.
- Professions: only the profession window changes. Recipe list rows get taller as the text grows, so fewer recipes fit on screen.
- Default changes nothing; "reset" returns to the game's original fonts.
- Smaller text in the same group (e.g. quest objectives) scales proportionally.
- Settings are saved account-wide. MIT licensed.
- UI text follows the client language (Traditional Chinese on zhTW clients, English elsewhere), or pick a language in the settings.
- Settings live under Options → AddOns → BigFontTuner; /bft jumps there, or opens a standalone window if it can't (e.g. in combat).

- Issues / support: support@augustusw.com · [Buy me a coffee / 請我喝杯咖啡](https://link.augustusw.com/coffee)

If this addon helps you, a star on the repo helps other players find it. 覺得好用的話，幫這個 repo 按個星，能讓其他玩家更容易找到。

---

## 中文說明

魔獸世界：永恆（Interface 16001）用的字體調整 addon。可以調整遊戲文字的字級、字型和描邊，並即時預覽效果。分類：任務視窗、聊天、NPC 對話、地圖（進入區域時跳出的區域名稱、小地圖區域名稱、地圖標籤）、背包（物品數量數字、說明框文字）、專業視窗（配方清單與右側配方資訊）。

## 問題回報

support@augustusw.com

遇到問題時輸入 `/bft errors`，按「全選」後用 Ctrl+C 複製，把內容一起寄來會比較好查。紀錄只存在本機（最近 20 種錯誤，不含角色與帳號名稱），插件不會連網。

## 安裝

從 [CurseForge](https://www.curseforge.com/wow/addons/bigfonttuner) 下載（CurseForge App 可自動更新），或直接從這個 repo 取得原始碼。

把整個 `BigFontTuner` 資料夾放到遊戲目錄的 `_forever_/Interface/AddOns/`，然後在角色選擇畫面左下角的「插件」中勾選。

如果之前裝過舊版 `BigQuestText`，請先刪除那個資料夾，否則兩個 addon 會同時修改任務字型。

## 使用

- 輸入 `/bigfonttuner` 開啟設定。如果 `/bft` 沒被其他 addon 佔用，也可以用 `/bft`。也可以點小地圖旁插件收納按鈕裡的 BigFontTuner。
- 聊天：沒設字級時，每個聊天視窗維持遊戲聊天設定裡的字級，只換字型與描邊；設了字級才會統一。
- 全部介面字型：一個選項換掉遊戲所有文字的字型，字級與描邊不變。分類選「跟隨全部介面」時用這個，分類另外選的字型優先。頭上的名字、名條與戰鬥數字要 /reload 後才會換。
- 選用字型（檔案太大，下載包不附）：把 `jf-openhuninn-2.1.ttf`（jf open 粉圓）或 `TaipeiSansTCBeta-Regular.ttf`（台北黑體）放進 `BigFontTuner/Fonts/`，字型選單就會出現。兩者都是 SIL OFL 1.1。放進新檔案後要整個遊戲重開，/reload 讀不到新檔案。
- 背包：數量數字只改背包格子，快捷列的數字不變；描邊選「無」時保留遊戲原本的描邊。說明框文字會連同其他說明框（礦點、技能等）一起變大。
- 專業：只改專業視窗。清單的列高會跟著字變大，一頁能看到的配方會變少。
- 設定放在「選項 → 插件 → BigFontTuner」。輸入指令會先嘗試跳到那一頁；跳不過去（或戰鬥中）時改開同樣內容的獨立視窗，可以拖曳，按 Esc 關閉。
- 介面語言預設跟隨客戶端（只有繁中客戶端顯示中文，其他語系顯示英文），也可以在設定裡選「English／繁體中文」，切換後按「重新載入」套用。
- 標題字級、內文字級、字型、描邊調整後都會立即套用，設定自動儲存，同帳號的角色共用。
- 預設不更動任何字型（維持遊戲原樣）；「恢復此分類預設」會回到遊戲原始狀態。同一組裡的小字（例如任務目標）會依原始比例一起縮放。
- 戰鬥中也能開設定視窗。

## 自訂字型

1. 把 `.ttf` 放到遊戲的 `_forever_/Fonts/`（更新插件不會被清掉），或 `BigFontTuner/Fonts/`。字型必須包含中文字，否則中文會顯示成方塊。只支援單一 `.ttf`，`.ttc`／`.otf` 不保證能用。
2. 在 `Fonts.lua` 的 `FONT_CANDIDATES` 加一行，例如放在 `_forever_/Fonts/` 時：`{ key = "my", label = "我的字型", path = "Fonts\\MyFont.ttf" }`
3. 整個遊戲重開（/reload 讀不到新放的檔案）。注意更新插件時 `Fonts.lua` 會被覆蓋，這行要重加。

不確定路徑對不對，可以在聊天框輸入 `/run local f=CreateFont("BFTProbe") print((pcall(f.SetFont,f,"Fonts\\MyFont.ttf",12,"")))`，印出 true 就是讀得到。

addon 啟動時會逐一檢查字型檔，載入失敗的不會出現在選單中。

## 檔案

| 檔案 | 內容 |
|---|---|
| `ErrorLog.lua` | 錯誤紀錄：接在遊戲的錯誤處理後面，只留本插件的錯誤（`/bft errors`） |
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
