-- 介面文字：依客戶端語系顯示（GetLocale）。繁中客戶端用 zhTW，其餘語系一律英文。
-- 新增語系：在 LOCALES 加一張表；缺的字串會自動退回英文。
local _, ns = ...

local enUS = {
  CATEGORY_QUEST = "Quest",
  CATEGORY_CHAT = "Chat",
  CATEGORY_GOSSIP = "Gossip",
  CATEGORY_MAP = "Map",
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

  TITLE_SIZE = "Title size",
  BODY_SIZE = "Body size",
  FONT = "Font",
  OUTLINE = "Outline",
  RESET = "Reset category",
  PREVIEW = "Preview (live)",
  OPEN_WINDOW = "Open settings window",
  HINT = "Changes apply immediately and are saved account-wide. Only fonts found on this client are listed.",
  COMMANDS = "Commands: %s",
  BFT_TAKEN = "BigFontTuner: /bft is used by another addon, type /bigfonttuner instead.",

  SAMPLE_TITLE = "A Journey Begins",
  SAMPLE_BODY = "Follow the mountain road west, turn left at the fork, and find the old hunter at the camp.",
  SAMPLE_HEADER = "Description",
  SAMPLE_BODY2 = "Deliver this letter to him; he will tell you what to do next.",
}

local zhTW = {
  CATEGORY_QUEST = "任務",
  CATEGORY_CHAT = "聊天",
  CATEGORY_GOSSIP = "對話",
  CATEGORY_MAP = "地圖",
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

  TITLE_SIZE = "標題字級",
  BODY_SIZE = "內文字級",
  FONT = "字型",
  OUTLINE = "描邊",
  RESET = "恢復此分類預設",
  PREVIEW = "預覽（即時更新）",
  OPEN_WINDOW = "開啟設定視窗",
  HINT = "調整後立即套用，設定自動儲存（帳號共用）。字型清單只列出這台電腦上存在的字型。",
  COMMANDS = "指令：%s",
  BFT_TAKEN = "BigFontTuner：/bft 已被其他插件使用，請改打 /bigfonttuner。",

  SAMPLE_TITLE = "旅途的起點",
  SAMPLE_BODY = "沿著山路往西走，在岔路口左轉，找到營地裡的老獵人。",
  SAMPLE_HEADER = "描述",
  SAMPLE_BODY2 = "把這封信交給他，他會告訴你接下來該做什麼。",
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
