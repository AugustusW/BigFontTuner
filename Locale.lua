-- 介面文字：依客戶端語系顯示（GetLocale）。繁中客戶端用 zhTW，其餘語系一律英文。
-- 新增語系：在 LOCALES 加一張表；缺的字串會自動退回英文。
local _, ns = ...

local enUS = {
  CATEGORY_QUEST = "Quest",
  CATEGORY_CHAT = "Chat",
  CATEGORY_GOSSIP = "Gossip",
  CATEGORY_MAP = "Map",
  CATEGORY_BAG = "Bags",
  CATEGORY_PROFESSION = "Professions",
  COMING_LATER = "%s (later)",

  OUTLINE_NONE = "None",
  OUTLINE_NORMAL = "Outline",
  OUTLINE_THICK = "Thick outline",

  FONT_GAME_DEFAULT = "Game default",
  FONT_KAI = "Kai (bKAI00M, quest default)",
  FONT_HEI = "Hei (bHEI00M)",
  FONT_HEI_BOLD = "Hei bold (bHEI01B)",
  FONT_LEI = "bLEI00D",
  FONT_ARKAI = "AR Kai (ARKai_T)",
  FONT_HUNINN = "jf open Huninn (rounded)",
  FONT_TAIPEI = "Taipei Sans TC",
  FONT_FOLLOW_GLOBAL = "Follow whole UI (%s)",
  GLOBAL_FONT = "Whole UI font",
  GLOBAL_FONT_NOTE = "Changes every font in the game; categories set to \"Follow whole UI\" use it. Names above heads and combat numbers change after /reload.",

  TITLE_SIZE = "Title size",
  BODY_SIZE = "Body size",
  BAG_COUNT_SIZE = "Stack count",
  BAG_TOOLTIP_SIZE = "Tooltip text",
  PROF_TITLE_SIZE = "Recipe name & headers",
  PROF_BODY_SIZE = "List & details",
  PROF_NOTE = "Only the profession window changes. List rows get taller as the text grows, so fewer recipes fit on screen.",
  SAMPLE_PROF_CATEGORY = "Weapons",
  SAMPLE_PROF_RECIPE = "Copper Shortsword",
  SAMPLE_PROF_ROW1 = "Copper Shortsword [3]",
  SAMPLE_PROF_ROW2 = "Rough Sharpening Stone",
  SAMPLE_PROF_DESC = "A plain blade for a new adventurer.",
  SAMPLE_PROF_REAGENT = "Copper Bar 6/6",
  BAG_NOTE = "Stack counts change only in bags (not action bars); outline \"None\" keeps the game's outline. Tooltip text changes every tooltip.",
  FONT = "Font",
  OUTLINE = "Outline",
  RESET = "Reset category",
  PREVIEW = "Preview (live)",
  OPEN_WINDOW = "Open settings window",
  HINT = "Changes apply immediately and are saved account-wide. Only fonts found on this client are listed.",
  NAV_HINT = "D-pad, left stick or arrow keys: Up/Down to select, Left/Right to change, A (Enter) to press a button. While this page is open the stick moves the selection, not your character.",
  NAV_OFF = "BigFontTuner: gamepad / arrow-key control in the settings is off. Type /bft nav on to turn it back on.",
  NAV_ON = "BigFontTuner: gamepad / arrow-key control in the settings is on.",
  NAV_DEBUG_ON = "BigFontTuner: key debug output on. Type /bft navdebug again to turn it off.",
  NAV_DEBUG_OFF = "BigFontTuner: key debug output off.",
  COMMANDS = "Commands: %s",
  BFT_TAKEN = "BigFontTuner: /bft is used by another addon, type /bigfonttuner instead.",
  COMPARTMENT_HINT = "Click to open the settings. Also /bigfonttuner or /bft.",

  ERRORS_TITLE = "BigFontTuner: Error log",
  ERRORS_HINT = "Click the text, press Ctrl+A then Ctrl+C to copy, and paste it when reporting a problem.",
  ERRORS_EMPTY = "No errors recorded.",
  ERRORS_SELECT_ALL = "Select all",
  ERRORS_CLEAR = "Clear log",
  ERRORS_CLEAR_CONFIRM = "Clear all error records?\nThis cannot be undone. Copy the log first if a problem needs reporting.",
  ERRORS_CLEAR_OK = "Clear",
  ERRORS_CANCEL = "Cancel",

  SAMPLE_TITLE = "A Journey Begins",
  SAMPLE_BODY = "Follow the mountain road west, turn left at the fork, and find the old hunter at the camp.",
  SAMPLE_HEADER = "Description",
  SAMPLE_BODY2 = "Deliver this letter to him; he will tell you what to do next.",
  SAMPLE_BAG = "Backpack",
  SAMPLE_ITEM = "Copper Ore",
  SAMPLE_ITEM_TYPE = "Trade Goods",
  SAMPLE_ITEM_DESC = "Can be smelted into a copper bar.",
}

local zhTW = {
  CATEGORY_QUEST = "任務",
  CATEGORY_CHAT = "聊天",
  CATEGORY_GOSSIP = "對話",
  CATEGORY_MAP = "地圖",
  CATEGORY_BAG = "背包",
  CATEGORY_PROFESSION = "專業",
  COMING_LATER = "%s（之後）",

  OUTLINE_NONE = "無",
  OUTLINE_NORMAL = "描邊",
  OUTLINE_THICK = "粗描邊",

  FONT_GAME_DEFAULT = "遊戲預設",
  FONT_KAI = "楷體（bKAI00M，任務預設）",
  FONT_HEI = "黑體（bHEI00M）",
  FONT_HEI_BOLD = "黑體粗（bHEI01B）",
  FONT_LEI = "bLEI00D",
  FONT_ARKAI = "AR 楷體（ARKai_T）",
  FONT_HUNINN = "粉圓",
  FONT_TAIPEI = "台北黑體",
  FONT_FOLLOW_GLOBAL = "跟隨全部介面（%s）",
  GLOBAL_FONT = "全部介面字型",
  GLOBAL_FONT_NOTE = "整個遊戲的字型；各分類選「跟隨全部介面」時用這個。頭上的名字與戰鬥數字要 /reload 後才換。",

  TITLE_SIZE = "標題字級",
  BODY_SIZE = "內文字級",
  BAG_COUNT_SIZE = "數量數字字級",
  BAG_TOOLTIP_SIZE = "說明框文字字級",
  PROF_TITLE_SIZE = "配方名稱與分類字級",
  PROF_BODY_SIZE = "清單與說明字級",
  PROF_NOTE = "只改專業視窗。清單的列高會跟著字變大，一頁能看到的配方會變少。",
  SAMPLE_PROF_CATEGORY = "武器",
  SAMPLE_PROF_RECIPE = "銅質短劍",
  SAMPLE_PROF_ROW1 = "銅質短劍 [3]",
  SAMPLE_PROF_ROW2 = "劣質磨刀石",
  SAMPLE_PROF_DESC = "給新手冒險者的樸素刀刃。",
  SAMPLE_PROF_REAGENT = "銅錠 6/6",
  BAG_NOTE = "數量數字只改背包格子（快捷列不變），描邊選「無」時保留遊戲原本的描邊；說明框文字會連同其他說明框（礦點、技能等）一起變大。",
  FONT = "字型",
  OUTLINE = "描邊",
  RESET = "恢復此分類預設",
  PREVIEW = "預覽（即時更新）",
  OPEN_WINDOW = "開啟設定視窗",
  HINT = "調整後立即套用，設定自動儲存（帳號共用）。字型清單只列出這台電腦上存在的字型。",
  NAV_HINT = "十字鍵、類比或方向鍵：上下選擇、左右調整、A（Enter）按下按鈕。這一頁開著時類比用來選擇，不會移動角色。",
  NAV_OFF = "BigFontTuner：已關閉設定頁的手把／方向鍵操作。輸入 /bft nav on 可重新開啟。",
  NAV_ON = "BigFontTuner：已開啟設定頁的手把／方向鍵操作。",
  NAV_DEBUG_ON = "BigFontTuner：按鍵除錯輸出已開啟。再輸入一次 /bft navdebug 關閉。",
  NAV_DEBUG_OFF = "BigFontTuner：按鍵除錯輸出已關閉。",
  COMMANDS = "指令：%s",
  BFT_TAKEN = "BigFontTuner：/bft 已被其他插件使用，請改打 /bigfonttuner。",
  COMPARTMENT_HINT = "點擊開啟設定。也可以輸入 /bigfonttuner 或 /bft。",

  ERRORS_TITLE = "BigFontTuner：錯誤紀錄",
  ERRORS_HINT = "點一下文字，按 Ctrl+A 再按 Ctrl+C 複製，回報問題時貼上。",
  ERRORS_EMPTY = "目前沒有錯誤紀錄。",
  ERRORS_SELECT_ALL = "全選",
  ERRORS_CLEAR = "清除紀錄",
  ERRORS_CLEAR_CONFIRM = "確定要清除全部錯誤紀錄嗎？\n清除後無法復原，回報問題前請先複製。",
  ERRORS_CLEAR_OK = "清除",
  ERRORS_CANCEL = "取消",

  SAMPLE_TITLE = "旅途的起點",
  SAMPLE_BODY = "沿著山路往西走，在岔路口左轉，找到營地裡的老獵人。",
  SAMPLE_HEADER = "描述",
  SAMPLE_BODY2 = "把這封信交給他，他會告訴你接下來該做什麼。",
  SAMPLE_BAG = "行囊",
  SAMPLE_ITEM = "銅礦石",
  SAMPLE_ITEM_TYPE = "交易物品",
  SAMPLE_ITEM_DESC = "可以熔煉成銅錠。",
}

enUS.LANGUAGE = "Language / 介面語言"
enUS.LANGUAGE_AUTO = "Auto (client language)"
enUS.RELOAD_NOTE = "Reload the UI to apply the new language."
enUS.RELOAD = "Reload UI"
zhTW.LANGUAGE = "介面語言 / Language"
zhTW.LANGUAGE_AUTO = "自動（跟隨客戶端）"
zhTW.RELOAD_NOTE = "重新載入介面後套用新語言。"
zhTW.RELOAD = "重新載入"

ns.LOCALES = { enUS = enUS, zhTW = zhTW }
-- 語言選單：自動＋各語系（名稱用該語言自己的寫法）
ns.LANGUAGE_CHOICES = {
  { key = "auto" },
  { key = "enUS", label = "English" },
  { key = "zhTW", label = "繁體中文" },
}

-- 目前使用的語系：設定裡選了特定語言就用它，否則跟客戶端；沒有翻譯的語系一律英文
function ns.ActiveLocale()
  local pick = ns.db and ns.db.locale
  if pick and pick ~= "auto" and ns.LOCALES[pick] then return pick end
  local client = GetLocale()
  return ns.LOCALES[client] and client or "enUS"
end

-- 每次取字串時才查目前語系（設定檔要到 ADDON_LOADED 才讀得到，比這個檔案載入晚）
ns.L = setmetatable({}, {
  __index = function(_, k)
    return ns.LOCALES[ns.ActiveLocale()][k] or enUS[k]
  end,
})
