-- 用假的 WoW API 跑 BigFontTuner 的載入流程（只驗邏輯，不驗畫面）
-- 用法：lua tests/harness.lua <addon 資料夾>
local DIR = arg[1] or "."
local EXISTING = { ["fonts\\bkai00m.ttf"] = true, ["fonts\\bhei00m.ttf"] = true }

-- 萬用假物件：任何方法呼叫都回傳自己，可以接住 UI 鏈式呼叫
local function stub(name)
  local o = { _name = name, scripts = {} }
  return setmetatable(o, { __index = function(t, k)
    return function(self, ...)
      if k == "SetScript" then local ev, fn = ...; t.scripts[ev] = fn end
      if k == "GetID" then return 42 end
      if k == "IsVisible" or k == "IsShown" then return rawget(t, "visible") or false end
      if k == "Show" then rawset(t, "visible", true) end
      if k == "Hide" then rawset(t, "visible", false) end
      return self
    end
  end })
end

local function fontObj(name, file, size)
  local f = { name = name, file = file, size = size, flags = "" }
  function f:GetFont() return self.file, self.size, self.flags end
  function f:SetFont(path, sz, flags)
    if not EXISTING[path:lower()] then error("Invalid font asset (" .. path .. "): file not found") end
    if type(sz) ~= "number" then error("Usage: SetFont(path, size, flags)") end
    self.file, self.size, self.flags = path, sz, flags
  end
  return f
end

-- 遊戲原始值（模擬）：標題 18、內文 14、目標小字 12
local function resetGlobals()
  QuestFont = fontObj("QuestFont", "Fonts\\bKAI00M.TTF", 14)
  QuestTitleFont = fontObj("QuestTitleFont", "Fonts\\bKAI00M.TTF", 18)
  QuestFontNormalSmall = fontObj("QuestFontNormalSmall", "Fonts\\bKAI00M.TTF", 12)
  -- QuestTitleFontBlackShadow 刻意不存在，驗證 _G 檢查
end

local frames, opened, inCombat
local window
function CreateFrame(kind, name, parent)
  local f = stub(kind)
  if name == "BigFontTunerWindow" then
    window = f
    rawset(f, "shown", false)
    rawset(f, "TitleText", stub("TitleText"))
    rawset(f, "Show", function(self) rawset(self, "shown", true) end)
    rawset(f, "Hide", function(self) rawset(self, "shown", false) end)
    rawset(f, "IsShown", function(self) return rawget(self, "shown") end)
  end
  if kind == "Frame" and not parent then table.insert(frames, f) end
  f.RegisterEvent = function(self, ev) local e = rawget(self, "events") or {}; rawset(self, "events", e); e[ev] = true; return self end
  return f
end
function CreateFont(name) return fontObj(name, "Fonts\\bKAI00M.TTF", 12) end
UIParent = stub("UIParent")
UISpecialFrames = {}
tinsert = table.insert
function CopyTable(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
function InCombatLockdown() return inCombat end
LOCALE = "zhTW"
function GetLocale() return LOCALE end
function print(...) end -- 吃掉 addon 的聊天訊息
C_AddOns = { GetAddOnMetadata = function() return "0.2.0" end }
local optionsPage
OPEN_WORKS = false -- 模擬永恆：OpenToCategory 沒反應
Settings = {
  RegisterCanvasLayoutCategory = function(page) optionsPage = page; return stub("category") end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function(id) opened = id; if OPEN_WORKS and optionsPage then rawset(optionsPage, "visible", true) end end,
}
SettingsPanel = stub("SettingsPanel")
function HideUIPanel(f) rawset(f, "visible", false); if optionsPage then rawset(optionsPage, "visible", false) end end
function ReloadUI() end

local realPrint = _G.io and function(s) io.write(s, "\n") end
local function check(c, msg) realPrint((c and "PASS " or "FAIL ") .. msg) if not c then FAILED = true end end

local function boot(db, otherSlash)
  frames, opened, inCombat, window, optionsPage = {}, nil, false, nil, nil
  resetGlobals()
  for k in pairs(_G) do if type(k) == "string" and k:sub(1, 6) == "SLASH_" then _G[k] = nil end end
  if otherSlash then SLASH_OTHER1 = "/bft" end
  SlashCmdList = {}
  BigFontTunerDB = db
  local ns = {}
  for _, f in ipairs({ "Locale.lua", "Fonts.lua", "Core.lua", "Settings.lua" }) do
    assert(loadfile(DIR .. "/" .. f))("BigFontTuner", ns)
  end
  return ns
end
local function fire(ev, a)
  for _, f in ipairs(frames) do
    local e = rawget(f, "events")
    if f.scripts.OnEvent and (not e or e[ev]) then f.scripts.OnEvent(f, ev, a) end
  end
end
local function login() fire("ADDON_LOADED", "BigFontTuner"); fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD") end

-- 1. 第一次安裝：不動任何字級（預設＝遊戲原始）
local ns = boot(nil, true)
login()
check(QuestFont.size == 14 and QuestTitleFont.size == 18 and QuestFontNormalSmall.size == 12, "預設不改字級（14/18/12）")
check(SLASH_BIGFONTTUNER1 == "/bigfonttuner", "/bigfonttuner 已註冊")
check(SLASH_BIGFONTTUNER2 == nil, "/bft 被佔用時不註冊")

-- 2. 調整內文：同組的小字依原始比例縮放
ns.db.categories.quest.bodySize = 21; ns.ApplyCategory("quest")
check(QuestFont.size == 21, "內文設 21")
check(QuestFontNormalSmall.size == 18, "目標小字依比例 12*21/14=18（得到 " .. QuestFontNormalSmall.size .. "）")
check(QuestTitleFont.size == 18, "標題未設定時維持原始 18")

-- 3. 字型清單、換字型與描邊、切回遊戲預設
local keys = {} for _, f in ipairs(ns.GetAvailableFonts()) do keys[#keys + 1] = f.key end
check(table.concat(keys, ",") == "default,kai,hei", "字型清單只列存在的（得到 " .. table.concat(keys, ",") .. "）")
ns.db.categories.quest.font = "hei"; ns.db.categories.quest.outline = "OUTLINE"; ns.ApplyCategory("quest")
check(QuestFont.file == "Fonts\\bHEI00M.TTF" and QuestFont.flags == "OUTLINE", "換字型與描邊後套用")
ns.db.categories.quest.font = "default"; ns.ApplyCategory("quest")
check(QuestFont.file == "Fonts\\bKAI00M.TTF", "切回遊戲預設還原原始字型檔")

-- 4. 恢復預設：回到遊戲原始字級、字型、描邊
ns.ResetCategory("quest")
check(QuestFont.size == 14 and QuestFontNormalSmall.size == 12 and QuestFont.flags == "", "恢復預設回到原始 14/12、無描邊")

-- 5. /bft：先試著跳到選項頁；跳不過去才開獨立視窗（使用者選 B）
SlashCmdList.BIGFONTTUNER("")
check(window and window.shown == true, "跳不到選項頁時開獨立視窗")
SlashCmdList.BIGFONTTUNER("")
check(window.shown == false, "再打一次關閉視窗")
check(UISpecialFrames[1] == "BigFontTunerWindow", "註冊 Esc 關閉")
OPEN_WORKS = true; window.shown = false
SlashCmdList.BIGFONTTUNER("")
check(rawget(optionsPage, "visible") == true and window.shown == false, "跳得到選項頁時不開視窗")
SlashCmdList.BIGFONTTUNER("")
check(rawget(optionsPage, "visible") == false, "選項頁開著時再打一次關閉")
OPEN_WORKS = false
inCombat = true
SlashCmdList.BIGFONTTUNER("")
check(window.shown == true, "戰鬥中直接開獨立視窗")
inCombat = false; window.shown = false

-- 6. 已存設定保留；壞掉的值會被修正，不讓登入中斷
ns = boot({ version = 1, categories = { quest = { bodySize = 24, titleSize = "abc", outline = "BAD", font = "zzz" } } }, false)
local ok = pcall(login)
check(ok, "壞掉的設定值不讓登入中斷")
local q = ns.db.categories.quest
check(q.bodySize == 24 and QuestFont.size == 24, "合法的已存設定保留（24）")
check(q.titleSize == nil and q.outline == "" and q.font == "default", "非法值修正為預設")
check(SLASH_BIGFONTTUNER2 == "/bft", "/bft 未被佔用時註冊")
ns = boot({ categories = { quest = { bodySize = 99 } } }, false); login()
check(ns.db.categories.quest.bodySize == 32, "超出範圍的字級夾到上限 32")

-- 7. 語系：英文客戶端顯示英文，繁中客戶端顯示中文
LOCALE = "enUS"; ns = boot(nil, false); login()
check(ns.Label(ns.GetCategory("quest")) == "Quest", "enUS 分類名稱是英文（得到 " .. tostring(ns.Label(ns.GetCategory("quest"))) .. "）")
check(ns.FontLabel(ns.GetAvailableFonts()[1]) == "Game default", "enUS 字型選單是英文")
check(ns.L.RESET == "Reset category", "enUS 按鈕文字是英文")
LOCALE = "zhTW"; ns = boot(nil, false); login()
check(ns.Label(ns.GetCategory("quest")) == "任務", "zhTW 分類名稱是中文")
check(ns.L.RESET == "恢復此分類預設", "zhTW 按鈕文字是中文")
LOCALE = "deDE"; ns = boot(nil, false); login()
check(ns.L.RESET == "Reset category", "其他語系退回英文")
-- 8. 介面語言選項：設定裡指定的語言優先於客戶端語系；不合法的值改回自動
LOCALE = "enUS"; ns = boot({ locale = "zhTW" }, false); login()
check(ns.L.RESET == "恢復此分類預設", "英文客戶端選繁體中文時顯示中文")
LOCALE = "zhTW"; ns = boot({ locale = "enUS" }, false); login()
check(ns.L.RESET == "Reset category", "繁中客戶端選 English 時顯示英文")
LOCALE = "zhTW"; ns = boot({ locale = "xxXX" }, false); login()
check(ns.db.locale == "auto" and ns.L.RESET == "恢復此分類預設", "不合法的語言設定改回自動")
for k, v in pairs(ns.LOCALES.enUS) do if type(v) ~= "string" then check(false, "L." .. k .. " 不是字串") end
  if ns.LOCALES.zhTW[k] == nil then check(false, "zhTW 缺少 " .. k) end end

-- 9. 使用者回報「Slash commands do not work」：登入時其他步驟出錯，也不能讓指令沒註冊
ns = boot(nil, false)
check(SLASH_BIGFONTTUNER1 == "/bigfonttuner" and type(SlashCmdList.BIGFONTTUNER) == "function", "載入當下就註冊 /bigfonttuner（不等登入）")
ns.GetCategory = function() error("font list broken") end -- 讓登入時的字型檢查出錯
local okLogin = pcall(login)
check(SLASH_BIGFONTTUNER1 == "/bigfonttuner" and type(SlashCmdList.BIGFONTTUNER) == "function", "登入流程出錯時指令仍可用")
check(SLASH_BIGFONTTUNER2 == "/bft", "登入流程出錯時 /bft 仍註冊")
-- /bft 被其他插件佔用：聊天框提示改用 /bigfonttuner
local printed = {}
print = function(s) printed[#printed + 1] = tostring(s) end
ns = boot(nil, true); login()
local found = false
for _, s in ipairs(printed) do if s:find("/bigfonttuner", 1, true) then found = true end end
check(found, "/bft 被佔用時提示改用 /bigfonttuner")
print = function() end

os.exit(FAILED and 1 or 0)
