# Changelog

每個版本一段，標題是 `## <版本>`；段內小標用 `###`。發版時 GitHub Release 與 CurseForge 的更新說明取自對應的段落。

## 0.7.0

### New

- **Global font**: one setting changes the typeface of every game font, including names above heads, nameplates and damage numbers (those three need `/reload`). Categories can still pick their own font on top of it.
- **Professions category**: enlarges text in the profession window only — recipe name and list headers (title slider), list rows, description, tools and reagent names (body slider). List rows get taller as the text grows, so fewer recipes fit on screen. Other windows are not affected.

### 新增

- **全部介面字型**：一個設定換掉遊戲所有字型，頭上名字、名條、傷害數字也會換（這三項要 `/reload`）。各分類仍可另外選字型蓋過去。
- **專業分類**：只放大專業視窗裡的文字：配方名稱與清單分類標題（標題滑桿），清單每列、說明、工具、材料名稱（內文滑桿）。清單列高會跟著字變大，一頁能看到的配方會變少。其他視窗不受影響。

## 0.6.0

（沒有單獨的 GitHub Release；改動是「全部介面字型」，上架版不附字型，內容隨 0.7.0 一起發布。）

## 0.5.0

New **Bags** category with two sliders:

- **Stack count**: enlarges the item count numbers on bag slots (combined bags included). Action bar numbers are not affected, and the original outline is kept unless you pick one.
- **Tooltip text**: enlarges tooltip text; header and small lines scale proportionally. This applies to every tooltip, not only items.

The settings preview switches to a bag and tooltip sample when the Bags tab is selected.

## 0.4.0

Fixed: `/bft` and the addon compartment button did nothing after a reload until the options page had been opened once. Added a local error log: type `/bft errors` to copy recent errors when reporting a problem. Records stay on your computer; the addon never connects to the network.

## 0.3.0

Added
- Chat category: typeface and outline for every chat window. With no size set, each window keeps the size chosen in the game's chat settings; changing it there keeps your typeface. No title size for chat.
- Gossip (NPC dialogue) category: NPC name as the title; greeting and options as the body. Reapplied each time a dialogue opens.
- Map category: zone name pop-ups as the title; minimap zone name and map labels as the body. Reapplied on zone change.
- Entry in the addon compartment next to the minimap: click to open the settings.

Notes
- Text objects the client does not have are skipped without errors.

## 0.2.1

- Slash commands now register as soon as the addon loads; an error elsewhere during login can no longer block them.
- `/bft` prints a hint in chat when another addon already uses it — type `/bigfonttuner` instead.
- Support: support@augustusw.com

---

- 斜線指令改為插件載入時就註冊，登入流程其他步驟出錯也不會讓指令失效。
- `/bft` 被其他插件佔用時，聊天框會提示改打 `/bigfonttuner`。
- 問題回報：support@augustusw.com

## 0.2.0

First public release, also available on [CurseForge](https://www.curseforge.com/wow/addons/bigfonttuner).

For **World of Warcraft: Forever** (Interface 16001).

- Quest window: adjust title and body font size, typeface and outline, with a live preview
- Changes nothing by default; "reset" restores the game's original fonts
- Smaller text in the same group (e.g. quest objectives) scales proportionally
- Settings live under Options → AddOns → BigFontTuner; `/bft` (or `/bigfonttuner`) jumps there, or opens a standalone window when it can't (e.g. in combat)
- UI follows the client language (Traditional Chinese / English), or pick one in the settings
- Settings are saved account-wide

**Install:** unzip into `_forever_/Interface/AddOns/` and enable it on the character select screen.
