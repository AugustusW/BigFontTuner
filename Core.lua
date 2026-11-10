-- 核心：分類定義、設定儲存、套用字型、斜線指令。
local addonName, ns = ...

ns.OUTLINES = {
  { key = "", labelKey = "OUTLINE_NONE" },
  { key = "OUTLINE", labelKey = "OUTLINE_NORMAL" },
  { key = "THICKOUTLINE", labelKey = "OUTLINE_THICK" },
}

ns.SIZE_MIN, ns.SIZE_MAX = 10, 32

-- 分類：每個分類有「標題」與「內文」兩組字型物件（沒有標題組的分類，設定頁只顯示內文字級）。
-- 組的成員是全域名稱：字型物件、FontString、有 SetFont 的框架，或按鈕（取它的文字）；客戶端沒有的直接略過。
-- 組也可以是函式（每次套用時才列出，例如聊天視窗數量會變）。
-- 每組第一個找得到的物件是基準：滑桿顯示與設定的是它的字級，組內其他物件依原始比例跟著縮放
-- （例如目標小字原本比內文小，放大後仍維持比例）。
-- 預設值 nil＝不改，沿用遊戲原本的字級；「恢復預設」就是回到遊戲原始狀態。
-- 聊天、對話、地圖（使用者 2026-11-09）：沒有在永恆探測過，用常見名稱，使用者遊戲內驗證。
local function chatFrames()
  local list = { "ChatFontNormal" }
  for i = 1, (NUM_CHAT_WINDOWS or 10) do list[#list + 1] = "ChatFrame" .. i end
  return list
end

local function gossipBody()
  local list = { "GossipGreetingText" }
  for i = 1, 32 do list[#list + 1] = "GossipTitleButton" .. i end
  return list
end

ns.CATEGORIES = {
  {
    key = "quest", labelKey = "CATEGORY_QUEST", enabled = true,
    title = { "QuestTitleFont", "QuestTitleFontBlackShadow" },
    body = { "QuestFont", "QuestFontNormalSmall" },
  },
  {
    -- 聊天字級遊戲本身就能設：沒設字級時維持遊戲的字級，只換字型與描邊；
    -- 遊戲改字級（FCF_SetChatWindowFontSize）時記下新的遊戲字級並重新套用，避免字型被洗掉、恢復預設也回得去
    key = "chat", labelKey = "CATEGORY_CHAT", enabled = true,
    body = chatFrames, hooks = { "FCF_SetChatWindowFontSize" },
  },
  {
    key = "gossip", labelKey = "CATEGORY_GOSSIP", enabled = true,
    title = { "GossipFrameNpcNameText" },
    body = gossipBody, events = { "GOSSIP_SHOW" },
  },
  {
    key = "map", labelKey = "CATEGORY_MAP", enabled = true,
    title = { "ZoneTextFont", "SubZoneTextFont", "PVPInfoTextFont" },
    body = { "MinimapZoneText", "WorldMapTextFont" },
    events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" },
  },
}

local DEFAULTS = { font = "default", outline = "" } -- titleSize／bodySize 預設為 nil

function ns.Label(item)
  return item.label or ns.L[item.labelKey]
end

function ns.GetCategory(key)
  for _, c in ipairs(ns.CATEGORIES) do
    if c.key == key then return c end
  end
end

-- 每個字型物件第一次被改之前的原始設定（檔案、大小、樣式），以物件為鍵
local originals = {}

-- 名稱 → 有 GetFont／SetFont 的物件；按鈕取它的文字；找不到回 nil
local function resolve(name)
  local obj = _G[name]
  if type(obj) ~= "table" then return nil end
  if not obj.GetFont and obj.GetFontString then obj = obj:GetFontString() end
  if type(obj) == "table" and obj.GetFont and obj.SetFont then return obj end
  return nil
end

local function remember(obj)
  if not obj then return nil end
  if not originals[obj] then
    local ok, file, size, flags = pcall(obj.GetFont, obj)
    if not (ok and file and size) then return nil end
    originals[obj] = { file = file, size = size, flags = flags or "" }
  end
  return originals[obj]
end

local function members(group)
  if type(group) == "function" then group = group() end
  local list = {}
  for _, name in ipairs(group or {}) do
    local obj = resolve(name)
    if obj then list[#list + 1] = obj end
  end
  return list
end

-- 某組目前的基準字級（設定值，或基準物件的原始字級），給滑桿顯示用
function ns.GetGroupSize(categoryKey, group)
  local cat = ns.GetCategory(categoryKey)
  local s = ns.db.categories[categoryKey]
  local value = s[group .. "Size"]
  if value then return value end
  local base = remember(members(cat[group])[1])
  return base and math.floor(base.size + 0.5) or 14
end

-- restore=true 時，全部是預設值的組會還原成原始設定；否則不碰（不覆蓋其他 addon 的字型）
local function applyGroup(group, size, settings, restore)
  if not group then return end
  local font = settings.font ~= ns.FONT_DEFAULT and ns.FindFont(settings.font) or nil
  local untouched = not size and not font and settings.outline == ""
  if untouched and not restore then return end
  local objs = members(group)
  local base = remember(objs[1])
  for _, obj in ipairs(objs) do
    local orig = untouched and originals[obj] or remember(obj)
    if orig then
      local s = orig.size
      if size and base and base.size > 0 then
        s = math.floor(orig.size * size / base.size + 0.5)
      end
      pcall(obj.SetFont, obj, font and font.path or orig.file, s, untouched and orig.flags or settings.outline)
    end
  end
end

-- restore：設定改回預設時要把字型物件還原（設定頁的每次變更與「恢復預設」都會帶 true）
function ns.ApplyCategory(key, restore)
  local cat = ns.GetCategory(key)
  if not (cat and cat.enabled) then return end
  local s = ns.db.categories[key]
  if not s then return end
  applyGroup(cat.title, s.titleSize, s, restore)
  applyGroup(cat.body, s.bodySize, s, restore)
end

-- 分類自己的觸發點：遊戲事件（對話框打開、換區域）與遊戲函式（聊天字級設定）之後重新套用
local function hookCategories()
  local f = CreateFrame("Frame")
  local byEvent = {}
  for _, c in ipairs(ns.CATEGORIES) do
    for _, e in ipairs(c.events or {}) do
      byEvent[e] = byEvent[e] or {}
      table.insert(byEvent[e], c.key)
      f:RegisterEvent(e)
    end
    for _, fn in ipairs(c.hooks or {}) do
      if hooksecurefunc and type(_G[fn]) == "function" then
        hooksecurefunc(fn, function(...)
          -- 遊戲剛改了某個物件的字級（例：聊天視窗）：那就是新的「遊戲原始字級」，恢復預設要回到它
          -- 使用者 2026-11-09 實測：原本拿「目前字級」當原始值，放大過後恢復預設回不去
          for i = 1, select("#", ...) do
            local obj = select(i, ...)
            if type(obj) == "table" and originals[obj] and obj.GetFont then
              local ok, _, size = pcall(obj.GetFont, obj)
              if ok and size then originals[obj].size = size end
            end
          end
          (ns.ErrorLog and ns.ErrorLog.try or pcall)(ns.ApplyCategory, c.key)
        end)
      end
    end
  end
  f:SetScript("OnEvent", function(_, e)
    -- 換區域、開對話框很頻繁：出錯不能每次都跳錯誤視窗
    for _, key in ipairs(byEvent[e] or {}) do (ns.ErrorLog and ns.ErrorLog.try or pcall)(ns.ApplyCategory, key) end
  end)
end

-- 小地圖旁官方「插件收納」按鈕（Addon Compartment；TOC 的 AddonCompartmentFunc* 指名這三個全域函式）
function BigFontTuner_OnAddonCompartmentClick() ns.OpenSettings() end
function BigFontTuner_OnAddonCompartmentEnter(_, button)
  if not GameTooltip then return end
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine("BigFontTuner")
  GameTooltip:AddLine(ns.L.COMPARTMENT_HINT, 0.8, 0.8, 0.8, true)
  GameTooltip:Show()
end
function BigFontTuner_OnAddonCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end

function ns.ApplyAll()
  for _, c in ipairs(ns.CATEGORIES) do
    ns.ApplyCategory(c.key)
  end
end

function ns.ResetCategory(key)
  ns.db.categories[key] = CopyTable(DEFAULTS)
  ns.ApplyCategory(key, true)
end

-- 設定值修正：壞掉或超出範圍的值不能讓登入中斷
local function validOutline(v)
  for _, o in ipairs(ns.OUTLINES) do
    if o.key == v then return true end
  end
  return false
end

local function sanitize(s)
  for _, k in ipairs({ "titleSize", "bodySize" }) do
    local v = s[k]
    if type(v) ~= "number" then
      s[k] = nil
    else
      s[k] = math.max(ns.SIZE_MIN, math.min(ns.SIZE_MAX, math.floor(v + 0.5)))
    end
  end
  if not validOutline(s.outline) then s.outline = DEFAULTS.outline end
  if type(s.font) ~= "string" then s.font = DEFAULTS.font end
end

-- 設定檔：帳號共用（SavedVariables）。補齊缺少的分類與欄位，舊設定不會被覆蓋。
local function initDB()
  if type(BigFontTunerDB) ~= "table" then BigFontTunerDB = {} end
  local db = BigFontTunerDB
  db.version = 1
  if not (db.locale == "auto" or ns.LOCALES[db.locale]) then db.locale = "auto" end
  if type(db.categories) ~= "table" then db.categories = {} end
  for _, c in ipairs(ns.CATEGORIES) do
    if c.enabled then
      local s = db.categories[c.key]
      if type(s) ~= "table" then s = {} ; db.categories[c.key] = s end
      for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
      end
      sanitize(s)
    end
  end
  ns.db = db
end

-- 字型要等字型清單驗證過才知道存不存在：找不到的字型改回遊戲預設，下拉選單才有選中項
local function dropMissingFonts()
  for key, s in pairs(ns.db.categories) do
    if ns.GetCategory(key) and s.font ~= ns.FONT_DEFAULT and not ns.FindFont(s.font) then
      s.font = ns.FONT_DEFAULT
    end
  end
end

-- 斜線指令：/bigfonttuner 一定註冊；/bft 只在沒有其他 addon 用掉時才註冊（避免靜默覆蓋別人的指令）。
-- 在 PLAYER_LOGIN 才檢查，這時所有 addon 都已載入。
local function slashTaken(cmd)
  cmd = cmd:lower()
  for k, v in pairs(_G) do
    if type(k) == "string" and k:sub(1, 6) == "SLASH_" and type(v) == "string" and v:lower() == cmd then
      return true
    end
  end
  return false
end

-- /bigfonttuner 在載入當下就註冊，不等登入，也不受登入時其他步驟出錯影響
-- （CurseForge 回報「Slash commands do not work」：登入流程中途出錯時，原本排在後面的註冊不會執行）
SLASH_BIGFONTTUNER1 = "/bigfonttuner"
SlashCmdList.BIGFONTTUNER = function() ns.OpenSettings() end

local function registerShortSlash()
  if slashTaken("/bft") then
    print(ns.L.BFT_TAKEN)
  else
    SLASH_BIGFONTTUNER2 = "/bft"
  end
end

-- /bft errors test：放在 ErrorLog.lua 之外，因為堆疊過濾會排除 ErrorLog.lua 自身的行
function ns.errorLogSelfTest()
  C_Timer.After(0, function() error("BigFontTuner error log self test") end)
  C_Timer.After(0.1, function() if Mixin then Mixin(nil, { a = 1 }) end end) -- 錯誤發生在內建函式，訊息不含路徑
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    initDB()
  elseif event == "PLAYER_LOGIN" then
    -- 每一步各自 pcall：任何一步出錯都不影響其他步驟（尤其是指令註冊）
    for _, step in ipairs({ registerShortSlash, dropMissingFonts, hookCategories, ns.ApplyAll, ns.CreateSettings }) do
      local ok, err = pcall(step)
      if not ok and geterrorhandler then geterrorhandler()(err) end
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- 其他 addon 可能在登入後才改字型，進入世界時再套用一次，確保我們的設定生效
    ns.ApplyAll()
  end
end)
