-- 核心：分類定義、設定儲存、套用字型、斜線指令。
local addonName, ns = ...

ns.OUTLINES = {
  { key = "", labelKey = "OUTLINE_NONE" },
  { key = "OUTLINE", labelKey = "OUTLINE_NORMAL" },
  { key = "THICKOUTLINE", labelKey = "OUTLINE_THICK" },
}

ns.SIZE_MIN, ns.SIZE_MAX = 10, 32

-- 分類：每個分類有「標題」與「內文」兩組字型物件。第一版只開放任務。
-- 每組第一個物件是基準：滑桿顯示與設定的是它的字級，組內其他物件依原始比例跟著縮放
-- （例如目標小字原本比內文小，放大後仍維持比例）。
-- 預設值 nil＝不改，沿用遊戲原本的字級；「恢復預設」就是回到遊戲原始狀態。
ns.CATEGORIES = {
  {
    key = "quest", labelKey = "CATEGORY_QUEST", enabled = true,
    title = { "QuestTitleFont", "QuestTitleFontBlackShadow" },
    body = { "QuestFont", "QuestFontNormalSmall" },
  },
  { key = "chat", labelKey = "CATEGORY_CHAT", enabled = false },
  { key = "gossip", labelKey = "CATEGORY_GOSSIP", enabled = false },
  { key = "map", labelKey = "CATEGORY_MAP", enabled = false },
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

-- 每個字型物件第一次被改之前的原始設定（檔案、大小、樣式）
local originals = {}

local function remember(name)
  local obj = _G[name]
  if not (obj and obj.GetFont) then return nil end
  if not originals[name] then
    local file, size, flags = obj:GetFont()
    if not file then return nil end
    originals[name] = { file = file, size = size, flags = flags or "" }
  end
  return originals[name]
end

-- 某組目前的基準字級（設定值，或基準物件的原始字級），給滑桿顯示用
function ns.GetGroupSize(categoryKey, group)
  local cat = ns.GetCategory(categoryKey)
  local s = ns.db.categories[categoryKey]
  local value = s[group .. "Size"]
  if value then return value end
  local base = remember(cat[group][1])
  return base and math.floor(base.size + 0.5) or 14
end

-- restore=true 時，全部是預設值的組會還原成原始設定；否則不碰（不覆蓋其他 addon 的字型）
local function applyGroup(names, size, settings, restore)
  local font = settings.font ~= ns.FONT_DEFAULT and ns.FindFont(settings.font) or nil
  local untouched = not size and not font and settings.outline == ""
  if untouched and not restore then return end
  local base = remember(names[1])
  for _, name in ipairs(names) do
    local orig = untouched and originals[name] or remember(name)
    if orig then
      local s = orig.size
      if size and base and base.size > 0 then
        s = math.floor(orig.size * size / base.size + 0.5)
      end
      _G[name]:SetFont(font and font.path or orig.file, s, untouched and orig.flags or settings.outline)
    end
  end
end

-- restore：設定改回預設時要把字型物件還原（設定頁的每次變更與「恢復預設」都會帶 true）
function ns.ApplyCategory(key, restore)
  local cat = ns.GetCategory(key)
  if not (cat and cat.enabled) then return end
  local s = ns.db.categories[key]
  applyGroup(cat.title, s.titleSize, s, restore)
  applyGroup(cat.body, s.bodySize, s, restore)
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

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    initDB()
  elseif event == "PLAYER_LOGIN" then
    -- 每一步各自 pcall：任何一步出錯都不影響其他步驟（尤其是指令註冊）
    for _, step in ipairs({ registerShortSlash, dropMissingFonts, ns.ApplyAll, ns.CreateSettings }) do
      local ok, err = pcall(step)
      if not ok and geterrorhandler then geterrorhandler()(err) end
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- 其他 addon 可能在登入後才改字型，進入世界時再套用一次，確保我們的設定生效
    ns.ApplyAll()
  end
end)
