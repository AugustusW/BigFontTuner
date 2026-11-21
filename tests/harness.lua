-- 用假的 WoW API 跑 BigFontTuner 的載入流程（只驗邏輯，不驗畫面）
-- 用法：lua tests/harness.lua <addon 資料夾>
local DIR = arg[1] or "."
unpack = unpack or table.unpack -- 遊戲是 Lua 5.1；測試可能跑在較新的 lua
date, time = date or os.date, time or os.time
local EXISTING = { ["fonts\\bkai00m.ttf"] = true, ["fonts\\bhei00m.ttf"] = true }

-- 萬用假物件：任何方法呼叫都回傳自己，可以接住 UI 鏈式呼叫
local function stub(name)
  local o = { _name = name, scripts = {} }
  return setmetatable(o, { __index = function(t, k)
    return function(self, ...)
      if k == "SetScript" then local ev, fn = ...; t.scripts[ev] = fn end
      if k == "HookScript" then
        local ev, fn = ...
        local hk = rawget(t, "hooks") or {}; rawset(t, "hooks", hk)
        hk[ev] = hk[ev] or {}; table.insert(hk[ev], fn)
      end
      if k == "GetID" then return 42 end
      if k == "GetFrameLevel" then return 1 end
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
  if name == "BigFontTunerErrorLogFrame" then rawset(f, "TitleText", stub("TitleText")) end
  if name == "BigFontTunerNavKeys" then
    -- 記錄鍵盤相關呼叫，驗證什麼時候接管按鍵、什麼時候往下傳
    navKeys = f
    rawset(f, "calls", {})
    rawset(f, "EnableKeyboard", function(self, on) table.insert(self.calls, "enable:" .. tostring(on)); rawset(self, "kb", on) end)
    rawset(f, "SetPropagateKeyboardInput", function(self, on) table.insert(self.calls, "prop:" .. tostring(on)); rawset(self, "prop", on) end)
  end
  if kind == "Slider" then
    -- 假滑桿：存值、限制範圍、SetValue 觸發 OnValueChanged（遊戲的滑桿程式設值也會觸發）
    rawset(f, "silent", false) -- stub 對不存在的欄位會回傳函式（真值），遊戲裡是 nil
    rawset(f, "SetMinMaxValues", function(self, lo, hi) rawset(self, "lo", lo); rawset(self, "hi", hi) end)
    rawset(f, "GetValue", function(self) return rawget(self, "value") or 0 end)
    rawset(f, "SetValue", function(self, v)
      local lo, hi = rawget(self, "lo") or -math.huge, rawget(self, "hi") or math.huge
      v = math.max(lo, math.min(hi, v))
      rawset(self, "value", v)
      if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
    end)
  end
  if kind == "DropdownButton" then
    rawset(f, "SetupMenu", function(self, gen) rawset(self, "menuGen", gen) end)
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
  -- 遊戲實測（2026-11-10）：頁面第一次被開啟前還沒掛進選項面板，沒有 parent，IsVisible() 回 true
  RegisterCanvasLayoutCategory = function(page) optionsPage = page; rawset(page, "visible", true); return stub("category") end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function(id) opened = id; if OPEN_WORKS and optionsPage then rawset(optionsPage, "visible", true); rawset(SettingsPanel, "visible", true) end end,
}
SettingsPanel = stub("SettingsPanel")
rawset(SettingsPanel, "Show", function(self) if OPEN_WORKS then rawset(self, "visible", true) end end) -- 模擬永恆：跳轉沒反應時面板不會開
function HideUIPanel(f) rawset(f, "visible", false); if optionsPage then rawset(optionsPage, "visible", false) end end
function ReloadUI() end

local realPrint = _G.io and function(s) io.write(s, "\n") end
local function check(c, msg) realPrint((c and "PASS " or "FAIL ") .. msg) if not c then FAILED = true end end

local function boot(db, otherSlash)
  frames, opened, inCombat, window, optionsPage = {}, nil, false, nil, nil
  rawset(SettingsPanel, "visible", false)
  resetGlobals()
  for k in pairs(_G) do if type(k) == "string" and k:sub(1, 6) == "SLASH_" then _G[k] = nil end end
  if otherSlash then SLASH_OTHER1 = "/bft" end
  SlashCmdList = {}
  BigFontTunerDB = db
  local ns = {}
  -- 依 TOC 載入：新檔案忘了列進 TOC，測試就會失敗（跟遊戲一樣）
  for raw in io.lines(DIR .. "/BigFontTuner.toc") do
    local file = raw:gsub("\r", "")
    if file ~= "" and not file:match("^#") then assert(loadfile(DIR .. "/" .. file))("BigFontTuner", ns) end
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

-- 10. 使用者 2026-11-09：預留的聊天、對話、地圖三個分類都做（不探測，用常見名稱；找不到的物件略過）
local function fsObj(name, size) local f = fontObj(name, "Fonts\\bKAI00M.TTF", size); f.GetObjectType = function() return "FontString" end; return f end
local hooked = {}
function hooksecurefunc(a, b, c) if type(a) == "string" then hooked[a] = b else hooked[b] = c end end
local function setupWorld()
  ChatFontNormal = fontObj("ChatFontNormal", "Fonts\\bKAI00M.TTF", 14)
  ChatFrame1 = fontObj("ChatFrame1", "Fonts\\bKAI00M.TTF", 14)
  ChatFrame2 = fontObj("ChatFrame2", "Fonts\\bKAI00M.TTF", 12)
  NUM_CHAT_WINDOWS = 2
  FCF_SetChatWindowFontSize = function() end -- 遊戲的聊天字級設定（存在才掛 hook）
  GossipFrameNpcNameText = fsObj("GossipFrameNpcNameText", 16)
  GossipGreetingText = fsObj("GossipGreetingText", 14)
  local opt = fsObj("opt1", 12)
  GossipTitleButton1 = { GetFontString = function() return opt end }
  ZoneTextFont = fontObj("ZoneTextFont", "Fonts\\bKAI00M.TTF", 30)
  SubZoneTextFont = fontObj("SubZoneTextFont", "Fonts\\bKAI00M.TTF", 24)
  MinimapZoneText = fsObj("MinimapZoneText", 12)
  return opt
end
local opt = setupWorld()
LOCALE = "zhTW"; ns = boot(nil, false); login()
for _, k in ipairs({ "chat", "gossip", "map" }) do
  local c = ns.GetCategory(k)
  check(c and c.enabled, k .. " 分類已開放")
  check(type(ns.db.categories[k]) == "table", k .. " 有設定檔")
end
check(ChatFrame1.size == 14 and GossipGreetingText.size == 14 and ZoneTextFont.size == 30, "預設不改三個分類的字")
check(ns.GetCategory("chat").title == nil, "聊天沒有標題組（設定頁只顯示內文字級）")

-- 聊天：字級交給遊戲時只換字型與描邊；遊戲改聊天字級後仍保留字型
local c = ns.db.categories.chat
c.font = "hei"; c.outline = "OUTLINE"; ns.ApplyCategory("chat")
check(ChatFrame1.file == "Fonts\\bHEI00M.TTF" and ChatFrame2.file == "Fonts\\bHEI00M.TTF" and ChatFontNormal.flags == "OUTLINE", "聊天每個視窗與 ChatFontNormal 換字型與描邊")
check(ChatFrame1.size == 14 and ChatFrame2.size == 12, "聊天沒設字級時維持各視窗原本字級")
ChatFrame2.size = 18 -- 玩家用遊戲選單把第二個視窗改成 18（遊戲函式簽名 FCF_SetChatWindowFontSize(self, chatFrame, fontSize)）
check(hooked.FCF_SetChatWindowFontSize ~= nil, "掛上遊戲的聊天字級設定")
hooked.FCF_SetChatWindowFontSize(nil, ChatFrame2, 18)
check(ChatFrame2.size == 18 and ChatFrame2.file == "Fonts\\bHEI00M.TTF", "遊戲改聊天字級後保留新字級、重新套字型（得到 " .. ChatFrame2.size .. "）")
c.bodySize = 20; ns.ApplyCategory("chat", true)
check(ChatFrame1.size == 20, "聊天設了字級就套用（20）")
ns.ResetCategory("chat")
check(ChatFrame1.file == "Fonts\\bKAI00M.TTF" and ChatFrame1.flags == "", "聊天恢復預設回到原始字型")
-- 使用者 2026-11-09 實測：聊天設過字級後「恢復預設」字級回不去
check(ChatFrame1.size == 14 and ChatFrame2.size == 18, "聊天恢復預設回到遊戲設定的字級 14／18（得到 " .. ChatFrame1.size .. "／" .. ChatFrame2.size .. "）")
c = ns.db.categories.chat
c.bodySize = 22; ns.ApplyCategory("chat", true)
ChatFrame2.size = 16; hooked.FCF_SetChatWindowFontSize(nil, ChatFrame2, 16) -- 設了字級之後，玩家又用遊戲選單把第二個視窗改成 16
check(ChatFrame1.size == 22, "設了字級時遊戲改字級後仍套用設定（22）")
c.bodySize = nil; ns.ApplyCategory("chat", true) -- 把字級改回「跟遊戲」
check(ChatFrame1.size == 14 and ChatFrame2.size == 16, "字級改回不設時回到遊戲的字級 14／16（得到 " .. ChatFrame1.size .. "／" .. ChatFrame2.size .. "）")
ns.ResetCategory("chat")

-- 對話：NPC 名稱是標題組；問候語與選項是內文組（選項按鈕取它的文字）
local g = ns.db.categories.gossip
g.bodySize = 21; g.titleSize = 20; ns.ApplyCategory("gossip")
check(GossipGreetingText.size == 21, "對話內文 21")
check(opt.size == 18, "對話選項依比例 12*21/14=18（得到 " .. opt.size .. "）")
check(GossipFrameNpcNameText.size == 20, "對話 NPC 名稱 20")
GossipGreetingText.size = 14; opt.size = 12 -- 對話框重開，遊戲把字型設回原樣
fire("GOSSIP_SHOW")
check(GossipGreetingText.size == 21, "對話框每次打開都重新套用")
check(QuestFont.size == 14, "對話不影響任務字型")

-- 地圖：區域名稱跳字是標題組；小地圖區域名稱是內文組
local m = ns.db.categories.map
m.titleSize = 36; m.bodySize = 15; ns.ApplyCategory("map")
check(ZoneTextFont.size == 36 and SubZoneTextFont.size == 29, "區域名稱 36，副區域依比例 24*36/30=29（得到 " .. SubZoneTextFont.size .. "）")
check(MinimapZoneText.size == 15, "小地圖區域名稱 15")

-- 客戶端沒有的物件直接略過，不報錯
ChatFrame2 = nil; GossipTitleButton1 = nil; ZoneTextFont = nil
local okMissing = pcall(function() for _, k in ipairs({ "chat", "gossip", "map" }) do ns.ApplyCategory(k, true) end end)
check(okMissing, "找不到的字型物件略過不報錯")

-- 11. 使用者 2026-11-15 選 D：背包分類＝物品數量數字（標題組）＋說明框文字（內文組）
do
  local function countFs(size) local f = fsObj("count", size); f.flags = "OUTLINE"; return f end
  -- 舊式客戶端：全域名稱 ContainerFrame1Item1Count；新式客戶端：frame.Items[i].Count
  local named = countFs(13)
  ContainerFrame1 = {}
  ContainerFrame1Item1 = { GetName = function() return "ContainerFrame1Item1" end }
  ContainerFrame1Item1Count = named
  local modern = countFs(13)
  ContainerFrame2 = { Items = { { Count = modern } } }
  NUM_CONTAINER_FRAMES, MAX_CONTAINER_ITEMS = 2, 1
  -- 使用者 2026-11-15 截圖：永恆用「背包已合併」的單一背包；格子只能從 EnumerateValidItems 列出
  local combined = countFs(13)
  ContainerFrameCombinedBags = { EnumerateValidItems = function()
    local done = false
    return function() if done then return nil end done = true return 1, { Count = combined } end
  end }
  GameTooltipText = fontObj("GameTooltipText", "Fonts\\bKAI00M.TTF", 12)
  GameTooltipHeaderText = fontObj("GameTooltipHeaderText", "Fonts\\bKAI00M.TTF", 14)
  GameTooltipTextSmall = fontObj("GameTooltipTextSmall", "Fonts\\bKAI00M.TTF", 10)
  ToggleAllBags = function() end
  hooked = {}
  LOCALE = "zhTW"; ns = boot(nil, false); login()
  local bag = ns.GetCategory("bag")
  check(bag and bag.enabled and type(ns.db.categories.bag) == "table", "背包分類已開放、有設定檔")
  check(ns.Label(bag) == "背包", "背包分類名稱")
  check(ns.GroupLabel(bag, "title") == "數量數字字級" and ns.GroupLabel(bag, "body") == "說明框文字字級", "背包的兩個滑桿用自己的名稱")
  check(ns.GroupLabel(ns.GetCategory("quest"), "title") == "標題字級", "其他分類維持標題／內文字級")
  check(named.size == 13 and GameTooltipText.size == 12 and named.flags == "OUTLINE", "預設不改背包數字與說明框")

  local b = ns.db.categories.bag
  b.titleSize = 18; ns.ApplyCategory("bag", true)
  check(named.size == 18 and modern.size == 18, "數量數字 18（兩種客戶端寫法都找得到）")
  check(combined.size == 18, "合併背包的數量數字 18（得到 " .. combined.size .. "）")
  local preview = countFs(13); ns.previewCounts = { preview }
  ns.ApplyCategory("bag", true)
  check(preview.size == 18 and preview.flags == "OUTLINE", "設定頁預覽的數字跟著套用")
  check(named.flags == "OUTLINE", "數量數字沒選描邊時保留遊戲原本的描邊（得到 '" .. tostring(named.flags) .. "'）")
  check(GameTooltipText.size == 12, "只調數字時說明框不變")

  b.bodySize = 15; ns.ApplyCategory("bag", true)
  check(GameTooltipText.size == 15, "說明框文字 15")
  check(GameTooltipHeaderText.size == 18 and GameTooltipTextSmall.size == 13, "說明框標題與小字依比例 18／13（得到 "
    .. GameTooltipHeaderText.size .. "／" .. GameTooltipTextSmall.size .. "）")
  check(QuestFont.size == 14, "背包不影響任務字型")

  b.outline = "THICKOUTLINE"; ns.ApplyCategory("bag", true)
  check(named.flags == "THICKOUTLINE", "選了粗描邊就套用到數字")
  b.outline = ""

  -- 背包格子在打開背包時才建立：開背包之後新出現的數字也要套用
  local late = countFs(13)
  ContainerFrame2.Items[2] = { Count = late }
  check(hooked.ToggleAllBags ~= nil, "掛上開背包的遊戲函式")
  hooked.ToggleAllBags()
  check(late.size == 18, "開背包後新建立的格子也套用（得到 " .. late.size .. "）")
  late.size = 13
  fire("BAG_UPDATE_DELAYED")
  check(late.size == 18, "背包內容變動後重新套用")

  ns.ResetCategory("bag")
  check(named.size == 13 and named.flags == "OUTLINE" and GameTooltipText.size == 12 and GameTooltipHeaderText.size == 14,
    "背包恢復預設回到原始字級與描邊")

  -- 審查回饋：背包內容一直變動，設定沒變就不要重設字型（SetFont 會讓共用字型的文字重新排版）
  b = ns.db.categories.bag -- ResetCategory 換掉了設定表，要重新取
  b.titleSize = 18; b.bodySize = 15; ns.ApplyCategory("bag", true)
  local calls = 0
  local realSet = named.SetFont
  named.SetFont = function(...) calls = calls + 1; return realSet(...) end
  local tipCalls = 0
  local realTipSet = GameTooltipText.SetFont
  GameTooltipText.SetFont = function(...) tipCalls = tipCalls + 1; return realTipSet(...) end
  fire("BAG_UPDATE_DELAYED")
  check(calls == 0 and tipCalls == 0, "字型已經是設定值時不重設（數字 " .. calls .. " 次、說明框 " .. tipCalls .. " 次）")
  named.size = 13; fire("BAG_UPDATE_DELAYED")
  check(calls == 1 and named.size == 18, "被遊戲改回去時才重設")
  named.SetFont, GameTooltipText.SetFont = nil, nil
  ns.ResetCategory("bag")

  -- 審查回饋：比例基準固定用 NumberFontNormal，不隨「第一個找到的格子」變動
  NumberFontNormal = fontObj("NumberFontNormal", "Fonts\\bKAI00M.TTF", 13)
  ns = boot(nil, false); login()
  local small = countFs(10)           -- 某個格子原本用比較小的數字
  ContainerFrameCombinedBags, ContainerFrame2 = nil, nil -- 讓小字格子成為第一個找到的格子
  ContainerFrame1Item1Count = small
  local pv = countFs(13); ns.previewCounts = { pv }
  ns.db.categories.bag.titleSize = 18; ns.ApplyCategory("bag", true)
  check(pv.size == 18 and small.size == 14, "以 NumberFontNormal 13 為基準：預覽 18、小字 10*18/13=14（得到 "
    .. pv.size .. "／" .. small.size .. "）")
  check(ns.GetGroupSize("bag", "title") == 18, "滑桿顯示設定值")
  ns.db.categories.bag.titleSize = nil
  check(ns.GetGroupSize("bag", "title") == 13, "沒設字級時滑桿顯示 NumberFontNormal 的字級 13")
  NumberFontNormal = nil

  ContainerFrame1, ContainerFrame2, ContainerFrame1Item1, ContainerFrame1Item1Count = nil, nil, nil, nil
  ContainerFrameCombinedBags = { EnumerateValidItems = function() error("not ready") end }
  check(pcall(ns.ApplyCategory, "bag", true), "沒有背包框架時略過不報錯")
end

-- 12. 使用者 2026-11-15 選 A：全部介面字型（只換字型檔，字級與描邊不動；分類另外選的字型優先）＋內建粉圓、台北黑體
do
  local HUNINN = "Interface\\AddOns\\BigFontTuner\\Fonts\\jf-openhuninn-2.1.ttf"
  local TAIPEI = "Interface\\AddOns\\BigFontTuner\\Fonts\\TaipeiSansTCBeta-Regular.ttf"
  EXISTING[HUNINN:lower()] = true; EXISTING[TAIPEI:lower()] = true
  setupWorld()
  -- 原始字型要用替身認得的檔案（EXISTING），不然還原時 SetFont 失敗會被 pcall 吞掉
  GameFontNormal = fontObj("GameFontNormal", "Fonts\\bHEI00M.TTF", 12)
  ZoneTextFont.flags = "THICKOUTLINE"
  GetFonts = function() return { "GameFontNormal", "QuestFont", "ZoneTextFont", "NotThere" } end
  LOCALE = "zhTW"; ns = boot(nil, false); login()
  local keys = {} for _, f in ipairs(ns.GetAvailableFonts()) do keys[#keys + 1] = f.key end
  check(table.concat(keys, ","):find("huninn,taipei", 1, true) ~= nil, "內建粉圓、台北黑體出現在字型清單（得到 " .. table.concat(keys, ",") .. "）")
  check(ns.db.globalFont == "default", "全部介面預設不換")
  check(GameFontNormal.file == "Fonts\\bHEI00M.TTF" and QuestFont.file == "Fonts\\bKAI00M.TTF", "預設不動任何字型")

  -- 任務另外選黑體（跟原始楷體不同，才分得出「分類字型勝出」與「根本沒動」；審查回饋）
  ns.db.categories.quest.font = "hei"; ns.ApplyCategory("quest", true)
  ns.SetGlobalFont("huninn")
  check(GameFontNormal.file == HUNINN and GameFontNormal.size == 12, "全部介面換成粉圓，字級不變")
  check(ZoneTextFont.file == HUNINN and ZoneTextFont.flags == "THICKOUTLINE" and ZoneTextFont.size == 30, "區域名稱換字型但保留粗描邊與字級")
  check(ChatFrame1.file == HUNINN and ChatFrame1.size == 14, "聊天視窗（不是字型物件）也跟著換")
  check(QuestFont.file == "Fonts\\bHEI00M.TTF", "任務另外選了黑體，不被全部介面蓋掉（得到 " .. QuestFont.file .. "）")
  check(ns.FontLabel(ns.GetAvailableFonts()[1]) == "跟隨全部介面（粉圓）", "分類字型選單第一項顯示跟隨全部介面（得到 "
    .. ns.FontLabel(ns.GetAvailableFonts()[1]) .. "）")

  ns.db.categories.map.titleSize = 36; ns.ApplyCategory("map", true)
  check(ZoneTextFont.file == HUNINN and ZoneTextFont.size == 36, "分類調字級時沿用全部介面的字型（得到 " .. ZoneTextFont.file .. "）")
  ns.ResetCategory("map")
  check(ZoneTextFont.file == HUNINN and ZoneTextFont.size == 30 and ZoneTextFont.flags == "THICKOUTLINE", "分類恢復預設回到全部介面字型，字級描邊回原樣")

  ns.SetGlobalFont("default")
  check(GameFontNormal.file == "Fonts\\bHEI00M.TTF" and ZoneTextFont.file == "Fonts\\bKAI00M.TTF" and ChatFrame1.file == "Fonts\\bKAI00M.TTF",
    "全部介面改回遊戲預設，全部還原")
  check(ZoneTextFont.flags == "THICKOUTLINE" and QuestFont.file == "Fonts\\bHEI00M.TTF", "還原後描邊與任務黑體不受影響")
  check(ns.FontLabel(ns.GetAvailableFonts()[1]) == "遊戲預設", "全部介面沒設時第一項顯示遊戲預設")

  -- 存檔：重新登入時套用；不合法或找不到的字型改回預設
  ns = boot({ globalFont = "huninn" }, false); login()
  check(GameFontNormal.file == HUNINN, "已存的全部介面字型在登入時套用")
  ns = boot({ globalFont = 42 }, false); login()
  check(ns.db.globalFont == "default", "不合法的全部介面字型改回預設")
  ns = boot({ globalFont = "gone" }, false); login()
  check(ns.db.globalFont == "default", "找不到的全部介面字型改回預設")
  -- 使用者 2026-11-15：上架版不含字型，自用版用 FONTS_DIR 打包；字型不進 repo 與發布白名單
  for _, script in ipairs({ "tools/package.sh", "tools/export.sh" }) do
    local body = io.open(DIR .. "/" .. script):read("*a")
    check(body:find("FONTS_DIR", 1, true) ~= nil and body:find("git ls-files Fonts", 1, true) == nil, script .. " 只在指定 FONTS_DIR 時才放字型")
  end
  local allow = io.open(DIR .. "/.publish-allowlist"):read("*a")
  check(allow:find(".ttf", 1, true) == nil, "字型檔不在發布白名單內")

  -- 使用者 2026-11-15 截圖：頭上的角色名字沒變。名字、名條、傷害數字用的是遊戲在進入世界前讀的全域字型變數，
  -- 要在插件載入時（ADDON_LOADED）就改，之後換字型要 /reload 才生效
  UNIT_NAME_FONT, NAMEPLATE_FONT, DAMAGE_TEXT_FONT, STANDARD_TEXT_FONT =
    "Fonts\\bHEI01B.TTF", "Fonts\\bHEI01B.TTF", "Fonts\\bHEI01B.TTF", "Fonts\\bLEI00D.TTF"
  ns = boot({ globalFont = "taipei" }, false)
  fire("ADDON_LOADED", "BigFontTuner")
  check(UNIT_NAME_FONT == TAIPEI and NAMEPLATE_FONT == TAIPEI and DAMAGE_TEXT_FONT == TAIPEI and STANDARD_TEXT_FONT == TAIPEI,
    "載入時就把名字、名條、傷害數字的字型變數換成全部介面字型（得到 " .. tostring(UNIT_NAME_FONT) .. "）")
  UNIT_NAME_FONT, NAMEPLATE_FONT = "Fonts\\bHEI01B.TTF", "Fonts\\bHEI01B.TTF"
  ns = boot(nil, false)
  fire("ADDON_LOADED", "BigFontTuner")
  check(UNIT_NAME_FONT == "Fonts\\bHEI01B.TTF", "全部介面沒設時不動字型變數")
  ns = boot({ globalFont = "gone" }, false)
  fire("ADDON_LOADED", "BigFontTuner")
  check(UNIT_NAME_FONT == "Fonts\\bHEI01B.TTF", "找不到的字型不寫進字型變數")
  UNIT_NAME_FONT, NAMEPLATE_FONT, DAMAGE_TEXT_FONT, STANDARD_TEXT_FONT = nil, nil, nil, nil

  GetFonts = nil
  ns = boot({ globalFont = "huninn" }, false)
  check(pcall(login), "客戶端沒有 GetFonts 時不報錯")
  GameFontNormal = nil
end

-- 小地圖旁插件收納按鈕
local toc = io.open(DIR .. "/BigFontTuner.toc"):read("a")
check(toc:find("## AddonCompartmentFunc: BigFontTuner_OnAddonCompartmentClick", 1, true) ~= nil, "TOC 指定收納按鈕點擊函式")
check(type(BigFontTuner_OnAddonCompartmentClick) == "function" and type(BigFontTuner_OnAddonCompartmentEnter) == "function"
  and type(BigFontTuner_OnAddonCompartmentLeave) == "function", "收納按鈕三個全域函式存在")
window = nil
BigFontTuner_OnAddonCompartmentClick()
check(window and window.shown == true, "點收納按鈕開設定")

-- 錯誤紀錄：鏈接原處理器、只收自己的錯誤、errors 子指令、靜默失敗要留紀錄
do
  local prevCalls, popup = {}, nil
  local h = function(e) prevCalls[#prevCalls + 1] = e end
  geterrorhandler = function() return h end
  seterrorhandler = function(f) h = f end
  debugstack = function() return "" end
  GetBuildInfo = function() return "1.60.1", "70862", "x", 16001 end
  StaticPopupDialogs = {}
  StaticPopup_Show = function(k) popup = k end
  LOCALE = "zhTW"; ns = boot(nil, false); login()
  local OWN = "Interface/AddOns/BigFontTuner/Core.lua:1: boom"
  h(OWN)
  check(prevCalls[1] == OWN, "自己的錯誤也交給原處理器")
  check(#ns.ErrorLog.entries() == 1 and BigFontTunerDB.errors[1].msg == OWN, "自己的錯誤寫進存檔")
  h("Interface/AddOns/Other/x.lua:1: y")
  check(#ns.ErrorLog.entries() == 1, "別的插件的錯誤不記錄")
  check(ns.ErrorLog.report():find("BigFontTuner 0.2.0 | Forever 1.60.1.70862 | zhTW", 1, true) ~= nil, "回報文字帶版本與語系")
  window = nil
  SlashCmdList.BIGFONTTUNER("errors")
  check(window == nil, "/bft errors 不開設定")
  SlashCmdList.BIGFONTTUNER("")
  check(window and window.shown == true, "/bft 不帶參數照舊開設定")
  check(SLASH_BFTERRORS1 == "/bfterrors", "備用指令已註冊")
  SlashCmdList.BIGFONTTUNER("errors clear")
  check(popup ~= nil and #ns.ErrorLog.entries() == 1, "清除要先確認")
  StaticPopupDialogs[popup].OnAccept()
  check(#ns.ErrorLog.entries() == 0 and #BigFontTunerDB.errors == 0, "確認後清空存檔")
  local toc2 = {}
  for line in io.lines(DIR .. "/BigFontTuner.toc") do if line ~= "" and not line:match("^#") then toc2[#toc2 + 1] = line end end
  check(toc2[1]:gsub("\r", "") == "ErrorLog.lua", "TOC 第一個載入 ErrorLog.lua")
  -- 事件／hook 觸發的套用失敗：不跳視窗，但要留紀錄（原本是 pcall 吞掉）
  local calls = #prevCalls
  ns.ApplyCategory = function() error("apply failed", 0) end
  local okHook = pcall(hooked.FCF_SetChatWindowFontSize)
  check(okHook and ns.ErrorLog.entries()[1] and ns.ErrorLog.entries()[1].msg == "apply failed", "hook 的套用失敗寫進紀錄")
  check(#prevCalls == calls, "套用失敗不跳錯誤視窗")
  ns.ErrorLog.clear()
  fire("GOSSIP_SHOW")
  check(ns.ErrorLog.entries()[1] and ns.ErrorLog.entries()[1].msg == "apply failed", "事件的套用失敗寫進紀錄")
  ns.ErrorLog.clear()
  local register = Settings.RegisterCanvasLayoutCategory
  Settings.RegisterCanvasLayoutCategory = function() error("settings failed", 0) end
  local okSettings = pcall(ns.CreateSettings)
  Settings.RegisterCanvasLayoutCategory = register
  check(okSettings and ns.ErrorLog.entries()[1] and ns.ErrorLog.entries()[1].msg == "settings failed", "選項頁註冊失敗寫進紀錄")
  geterrorhandler, seterrorhandler, debugstack = nil, nil, nil
end

-- 13. 專業視窗（使用者 2026-11-16 選 1A 2A）：只改專業視窗裡的文字，清單列高跟著字變大
do
  local function sized(name, size, h)
    local f = fsObj(name, size); f.h = h
    f.GetHeight = function(self) return self.h end
    f.SetHeight = function(self, v) self.h = v end
    return f
  end
  GameFontHighlightMed2 = fontObj("GameFontHighlightMed2", "Fonts\\bKAI00M.TTF", 14)
  GameFontHighlight_NoShadow = fontObj("GameFontHighlight_NoShadow", "Fonts\\bKAI00M.TTF", 12)
  GameFontNormal_NoShadow = fontObj("GameFontNormal_NoShadow", "Fonts\\bKAI00M.TTF", 12)
  ProfessionsFrame, ScrollUtil = nil, nil
  hooked = {}
  LOCALE = "zhTW"; ns = boot(nil, false); login()
  local prof = ns.GetCategory("profession")
  check(prof and prof.enabled and ns.Label(prof) == "專業", "專業分類已開放、名稱是專業")
  check(type(ns.db.categories.profession) == "table", "專業分類有設定檔")
  check(pcall(ns.ApplyCategory, "profession", true), "專業視窗還沒載入時套用不報錯")
  ns.db.categories.profession.bodySize = 16
  check(ns.GetGroupSize("profession", "body") == 16, "還沒開過專業視窗也能設定字級")
  ns.db.categories.profession.bodySize = nil

  -- 假的專業視窗：結構照暴雪 Blizzard_ProfessionsTemplates（2026-11-16 /fstack 確認 ProfessionsFrame.CraftingPage.SchematicForm）
  local recipeRow = { SkillUps = {}, Label = sized("recipeLabel", 12, 12), Count = sized("recipeCount", 12, 12) }
  local catRow = { CollapseIcon = {}, Label = sized("catLabel", 12, 10), scripts = {} }
  function catRow:HookScript(ev, fn) self.scripts[ev] = fn end
  local rows = { recipeRow, catRow }
  local view = { calc = function(_, node)
    local d = node:GetData()
    if d.recipeInfo then return 20 end
    if d.categoryInfo then return 25 end
    if d.topPadding then return 1 end
  end }
  function view:GetElementExtentCalculator() return self.calc end
  function view:SetElementExtentCalculator(c) self.calc = c end
  function view:GetDataProvider() return {} end
  local rebuilds, acquired, acquireRegs = 0, nil, 0
  local sb = {}
  function sb:ForEachFrame(fn) for _, r in ipairs(rows) do if fn(r, {}) then return end end end
  function sb:GetView() return view end
  function sb:Rebuild() rebuilds = rebuilds + 1 end
  -- 照暴雪 ScrollUtil：iterateExisting 為真時直接 ForEachFrame(callback)，參數是 (frame, elementData)，
  -- 跟建立事件的 (owner, frame, elementData, new) 不同（審查抓到：原本的替身照後者呼叫，假綠）
  ScrollUtil = { AddAcquiredFrameCallback = function(box, cb, owner, iterateExisting)
    acquired = function(o, frame) return cb(o, frame, {}, false) end
    acquireRegs = acquireRegs + 1
    if iterateExisting then box:ForEachFrame(cb) end
  end }
  local slotName = sized("slotName", 12, 36)
  local form = { OutputText = sized("output", 14, 0), Description = sized("desc", 11, 0), RequiredTools = sized("tools", 11, 0) }
  function form:Init() end
  form.reagentSlotPool = { EnumerateActive = function()
    local done = false
    return function() if done then return nil end done = true return { Name = slotName }, true end
  end }
  ProfessionsFrame = { CraftingPage = { RecipeList = { ScrollBox = sb }, SchematicForm = form } }
  local node = function(d) return { GetData = function() return d end } end

  fire("ADDON_LOADED", "Blizzard_Professions")
  check(acquired ~= nil, "專業視窗載入後掛上清單的列建立回呼")
  check(hooked.Init ~= nil, "掛上右側配方資訊的 Init")
  check(recipeRow.Label.size == 12 and form.OutputText.size == 14 and catRow.Label.size == 12, "預設不改專業視窗")
  check(view.calc(1, node{ recipeInfo = {} }) == 20 and view.calc(1, node{ categoryInfo = {} }) == 25, "預設列高不變")
  check(rebuilds == 0, "剛載入不重建清單")

  local p = ns.db.categories.profession
  p.titleSize = 21; p.bodySize = 18; ns.ApplyCategory("profession", true)
  check(form.OutputText.size == 21, "標題組：右側配方名稱 21")
  check(catRow.Label.size == 18, "標題組：清單分類標題依比例 12*21/14=18（得到 " .. catRow.Label.size .. "）")
  check(recipeRow.Label.size == 18 and recipeRow.Count.size == 18, "內文組：配方列名稱與可製作數量 18")
  check(form.Description.size == 17 and form.RequiredTools.size == 17, "內文組：說明、工具依比例 11*18/12≈17（得到 " .. form.Description.size .. "／" .. form.RequiredTools.size .. "）")
  check(slotName.size == 18, "內文組：材料名稱 18")
  check(view.calc(1, node{ recipeInfo = {} }) == 26, "配方列高 20+(18-12)=26（得到 " .. tostring(view.calc(1, node{ recipeInfo = {} })) .. "）")
  check(view.calc(1, node{ categoryInfo = {} }) == 31, "分類列高 25+(18-12)=31")
  check(view.calc(1, node{ topPadding = true }) == 1, "其他元素列高不變")
  local scaled = ns.ScaledSize
  ns.ScaledSize = function() error("broken") end
  local okCalc, h = pcall(view.calc, 1, node{ recipeInfo = {} })
  ns.ScaledSize = scaled
  check(okCalc and h == 20, "我們的列高計算出錯時退回暴雪原本的 20、不中斷排版")
  check(recipeRow.Label.h == 18 and recipeRow.Count.h == 18 and catRow.Label.h == 16, "文字框高度跟著加大（12+6、10+6）")
  check(rebuilds == 1, "設定改變時重建清單")
  ns.ApplyCategory("profession")
  check(rebuilds == 1, "設定沒變不重建清單")

  local newRow = { SkillUps = {}, Label = sized("newLabel", 12, 12), Count = sized("newCount", 12, 12) }
  acquired(nil, newRow)
  check(newRow.Label.size == 18 and newRow.Label.h == 18, "捲動後新建立的列也套用")

  catRow.Label:SetFont("Fonts\\bKAI00M.TTF", 12, "") -- 遊戲 OnLeave 用 SetFontObject 換回原本字型
  catRow.scripts.OnLeave(catRow)
  check(catRow.Label.size == 18, "滑鼠移開分類標題後字級不被遊戲洗掉")

  local slot2 = sized("slot2", 12, 36)
  form.reagentSlotPool.EnumerateActive = function()
    local done = false
    return function() if done then return nil end done = true return { Name = slot2 }, true end
  end
  hooked.Init(form)
  check(slot2.size == 18, "換配方後新的材料名稱也套用")

  ns.ResetCategory("profession")
  check(form.OutputText.size == 14 and recipeRow.Label.size == 12 and catRow.Label.size == 12 and slot2.size == 12, "恢復預設回到原始字級")
  check(recipeRow.Label.h == 12 and catRow.Label.h == 10, "恢復預設回到原始文字框高度")
  check(view.calc(1, node{ recipeInfo = {} }) == 20, "恢復預設列高回到 20")
  check(rebuilds == 2, "恢復預設重建清單")
  newRow.Label:SetFont("Fonts\\bKAI00M.TTF", 18, "") -- 回收池裡還留著放大字的列
  acquired(nil, newRow)
  check(newRow.Label.size == 12 and newRow.Label.h == 12, "回收的列重新使用時還原成原始字級")

  fire("ADDON_LOADED", "Blizzard_Professions")
  check(acquireRegs == 1, "重複的載入事件不重複掛回呼")

  -- 登入前專業視窗已經載入（例如其他插件先載入它）
  C_AddOns.IsAddOnLoaded = function(n) return n == "Blizzard_Professions" end
  acquired, acquireRegs = nil, 0
  ns = boot(nil, false); login()
  check(acquired ~= nil and acquireRegs == 1, "登入時專業視窗已載入也會掛上")
  C_AddOns.IsAddOnLoaded = nil
  ProfessionsFrame, ScrollUtil = nil, nil
end

-- 11. 下拉選項由 entries 提供：選單與方向鍵用同一份清單、同一個 setter（手把導航，2026-11-20）
do
  LOCALE = "zhTW"; ns = boot(nil, false); login()
  local w = ns.settingsInstances and ns.settingsInstances[1]
  check(w ~= nil, "設定畫面實例可供測試存取")
  if w then
    for _, key in ipairs({ "global", "font", "outline", "language" }) do
      local dd = w[key]
      local radios = {}
      local root = { CreateRadio = function(_, label, isSel, set) radios[#radios + 1] = { label = label, isSel = isSel, set = set } end }
      if rawget(dd, "menuGen") then rawget(dd, "menuGen")(dd, root) end
      local entries = type(rawget(dd, "entries")) == "function" and dd.entries() or {}
      local same = #radios > 0 and #radios == #entries
      for i, r in ipairs(radios) do
        if not entries[i] or r.label ~= entries[i].label or r.isSel() ~= entries[i].isSelected() then same = false end
      end
      check(same, key .. " 下拉的選單項目與 entries 一致（" .. #radios .. "／" .. #entries .. "）")
    end
    local fe = w.font.entries and w.font.entries() or {}
    if fe[2] then fe[2].select() end
    check(fe[2] ~= nil and ns.db.categories.quest.font == "kai", "entries 的 select 寫入目前分類的字型（得到 " .. tostring(ns.db.categories.quest.font) .. "）")
  end
end

-- 12. 方向鍵導航的項目表（手把模式下十字鍵＝方向鍵，2026-11-20 永恆實測）
do
  LOCALE = "zhTW"; ns = boot(nil, false); login()
  local w = ns.settingsInstances[1]
  local ids = {}
  for _, it in ipairs(w.nav or {}) do ids[#ids + 1] = it.id end
  check(table.concat(ids, ",") == "global,tabs,title,body,font,outline,reset,language,reload", "項目順序（得到 " .. table.concat(ids, ",") .. "）")
  local byId = {}
  for _, it in ipairs(w.nav or {}) do byId[it.id] = it end
  local function sel() for _, it in ipairs(w.nav) do end return nil end
  if byId.body then
    local before = ns.GetGroupSize("quest", "body")
    w.body:SetSilently(before) -- 面板顯示時 refreshAll 會設好目前值
    byId.body.right()
    check(ns.db.categories.quest.bodySize == before + 1 and QuestFont.size == before + 1, "內文右鍵 +1 並即時套用（" .. before .. "→" .. tostring(ns.db.categories.quest.bodySize) .. "）")
    byId.body.left()
    check(ns.db.categories.quest.bodySize == before, "內文左鍵 -1")
    ns.db.categories.quest.bodySize = ns.SIZE_MAX; ns.ApplyCategory("quest"); w.body:SetSilently(ns.SIZE_MAX)
    byId.body.right()
    check(ns.db.categories.quest.bodySize == ns.SIZE_MAX, "到上限再右鍵不變")
    ns.db.categories.quest.bodySize = ns.SIZE_MIN; ns.ApplyCategory("quest"); w.body:SetSilently(ns.SIZE_MIN)
    byId.body.left()
    check(ns.db.categories.quest.bodySize == ns.SIZE_MIN, "到下限再左鍵不變")
  end
  if byId.tabs then
    local enabled = {}
    for _, c in ipairs(ns.CATEGORIES) do if c.enabled then enabled[#enabled + 1] = c.key end end
    byId.tabs.right()
    check(ns.settingsSelected() == enabled[2], "頁籤右鍵到下一個啟用分類（得到 " .. tostring(ns.settingsSelected()) .. "）")
    check(byId.title.isShown() == (ns.GetCategory(enabled[2]).title ~= nil), "沒有標題組的分類隱藏標題項目")
    for _ = 1, #ns.CATEGORIES + 2 do byId.tabs.right() end
    check(ns.settingsSelected() == enabled[#enabled], "到最後一個分類再右鍵不變")
    for _ = 1, #ns.CATEGORIES + 2 do byId.tabs.left() end
    check(ns.settingsSelected() == enabled[1], "左鍵回到第一個分類且不循環")
  end
  if byId.font then
    local entries = w.font.entries()
    local idx
    for i, e in ipairs(entries) do if e.isSelected() then idx = i end end
    byId.font.right()
    local now
    for i, e in ipairs(w.font.entries()) do if e.isSelected() then now = i end end
    check(idx and now == idx + 1, "字型右鍵換到下一個選項")
  end
  if byId.reload and byId.reset then
    check(byId.reload.isShown() == false, "還沒改語言時重新載入項目隱藏")
    w.showReload()
    check(byId.reload.isShown() == true and type(byId.reload.enter) == "function", "改語言後重新載入項目出現且可按")
    ns.db.categories.quest.bodySize = 20
    byId.reset.enter()
    check(ns.db.categories.quest.bodySize == nil, "重設項目按 Enter 恢復預設")
  end
  check(ns.LOCALES.enUS.NAV_HINT ~= nil and ns.LOCALES.zhTW.NAV_HINT ~= nil, "提示文字中英都有")
  check(type(w.highlight) == "function", "有亮框函式")
end

-- 13. 方向鍵接管：只在設定頁顯示中、非戰鬥、沒關掉功能時；處理的鍵不往下傳，其他照舊
do
  local function fireHook(f, ev)
    if ev == "OnShow" then rawset(f, "visible", true) elseif ev == "OnHide" then rawset(f, "visible", false) end
    for _, fn in ipairs((rawget(f, "hooks") or {})[ev] or {}) do fn(f) end
  end
  local function key(k) navKeys.scripts.OnKeyDown(navKeys, k); return rawget(navKeys, "prop") end
  local function last(prefix)
    for i = #navKeys.calls, 1, -1 do if navKeys.calls[i]:sub(1, #prefix) == prefix then return navKeys.calls[i] end end
  end
  IsShiftKeyDown = function() return false end
  IsControlKeyDown = function() return false end
  IsAltKeyDown = function() return false end
  GetCurrentKeyBoardFocus = function() return nil end
  LOCALE = "zhTW"; navKeys = nil; ns = boot(nil, false); login()
  check(navKeys ~= nil, "建立鍵盤接收 frame")
  check(last("enable:") ~= "enable:true", "設定頁還沒顯示前不接管按鍵")
  local w1 = ns.settingsInstances[1]
  fireHook(w1.panel, "OnShow")
  check(rawget(navKeys, "kb") == true and last("prop:") == "prop:true", "設定頁顯示後接管，且預設往下傳")
  check(key("DOWN") == false and w1.navState.revealed == true, "第一次 DOWN 只顯示亮框且不往下傳")
  check(key("DOWN") == false and w1.navState.focus == "tabs", "DOWN 移到下一項")
  check(key("ESCAPE") == true, "ESCAPE 往下傳（照原本關閉設定）")
  check(key("LSHIFT") == true and key("W") == true, "其他鍵往下傳")
  check(key("ENTER") == false, "焦點不是按鈕時 ENTER 吃掉（手把 A 不會打開聊天框）")
  navKeys.scripts.OnKeyUp(navKeys, "DOWN")
  check(rawget(navKeys, "prop") == true, "放開按鍵時恢復往下傳（被吃掉的鍵不會讓其他鍵的放開被擋）")
  GetCurrentKeyBoardFocus = function() return {} end
  check(key("DOWN") == true and w1.navState.focus == "tabs", "輸入框有焦點時往下傳")
  GetCurrentKeyBoardFocus = nil
  check(key("DOWN") == false and w1.navState.focus == "title", "沒有 GetCurrentKeyBoardFocus 函式時照常處理")
  GetCurrentKeyBoardFocus = function() return nil end
  IsShiftKeyDown = function() return true end
  check(key("DOWN") == true, "按著修飾鍵時往下傳")
  IsShiftKeyDown = function() return false end

  -- 面板已不可見但沒收到 OnHide（例：整個選項面板被關掉）：按鍵往下傳並停止接管
  rawset(w1.panel, "visible", false)
  check(key("DOWN") == true and rawget(navKeys, "kb") == false, "面板已不可見時往下傳並停用")
  fireHook(w1.panel, "OnShow")

  -- 戰鬥：鍵盤 API 在戰鬥鎖定中呼叫會被遊戲封鎖（2026-11-21 使用者遇到 ADDON_ACTION_BLOCKED）
  local before = #navKeys.calls
  inCombat = true; navKeys.scripts.OnEvent(navKeys, "PLAYER_REGEN_DISABLED")
  check(#navKeys.calls == before, "已在戰鬥鎖定中時進戰鬥事件不呼叫任何鍵盤 API")
  inCombat = false; navKeys.scripts.OnEvent(navKeys, "PLAYER_REGEN_ENABLED")
  navKeys.scripts.OnEvent(navKeys, "PLAYER_REGEN_DISABLED") -- 事件觸發時鎖定還沒開始：趁機停用
  check(rawget(navKeys, "kb") == false, "進入戰鬥（鎖定前）停用鍵盤接管")
  inCombat = true
  local n = #navKeys.calls
  navKeys.scripts.OnKeyDown(navKeys, "DOWN")
  check(#navKeys.calls == n, "戰鬥中 handler 不呼叫任何鍵盤 API")
  inCombat = false; navKeys.scripts.OnEvent(navKeys, "PLAYER_REGEN_ENABLED")
  check(rawget(navKeys, "kb") == true and last("prop:") == "prop:true", "戰鬥結束且設定仍開時恢復接管")

  -- 關閉設定頁：停用；另一份畫面顯示時改作用在那一份
  fireHook(w1.panel, "OnHide")
  check(rawget(navKeys, "kb") == false, "設定頁關閉後停用")
  inCombat = true
  fireHook(w1.panel, "OnShow")
  check(rawget(navKeys, "kb") ~= true, "戰鬥中打開設定不接管")
  inCombat = false; navKeys.scripts.OnEvent(navKeys, "PLAYER_REGEN_ENABLED")
  check(rawget(navKeys, "kb") == true, "戰鬥結束後才接管")
  check(w1.navState.revealed == false, "重新顯示時亮框重置")
  fireHook(w1.panel, "OnHide")
  SlashCmdList.BIGFONTTUNER("") -- 永恆跳不到選項頁：開獨立視窗
  local w2 = ns.settingsInstances[2]
  check(w2 ~= nil, "獨立視窗也有一份畫面")
  if w2 then
    fireHook(w2.panel, "OnShow")
    key("DOWN"); key("DOWN")
    check(w2.navState.focus == "tabs" and w1.navState.focus == nil, "按鍵作用在目前顯示的那一份")
    fireHook(w2.panel, "OnHide")
  end

  -- 保底開關與除錯輸出
  SlashCmdList.BIGFONTTUNER("nav off")
  check(ns.db.navDisabled == true, "/bft nav off 存進設定")
  fireHook(w1.panel, "OnShow")
  check(rawget(navKeys, "kb") ~= true, "關掉後設定頁顯示也不接管")
  SlashCmdList.BIGFONTTUNER("nav on")
  check(ns.db.navDisabled == false and rawget(navKeys, "kb") == true, "/bft nav on 立即恢復")
  local printed = {}
  print = function(s) printed[#printed + 1] = tostring(s) end
  SlashCmdList.BIGFONTTUNER("navdebug")
  key("UP")
  print = function() end
  local saw = false
  for _, s in ipairs(printed) do if s:find("UP", 1, true) and s:find("shift", 1, true) then saw = true end end
  check(ns.db.navDebug == true and saw, "/bft navdebug 印出按鍵與修飾鍵狀態")
  fireHook(w1.panel, "OnHide")
end

-- 14. 沒開過設定時，戰鬥進出完全不碰鍵盤 API；被遊戲封鎖的動作記進錯誤紀錄
do
  LOCALE = "zhTW"; navKeys = nil; ns = boot(nil, false); login()
  local n = #navKeys.calls
  for _, lock in ipairs({ false, true }) do
    inCombat = lock
    navKeys.scripts.OnEvent(navKeys, "PLAYER_REGEN_DISABLED")
    navKeys.scripts.OnEvent(navKeys, "PLAYER_REGEN_ENABLED")
  end
  inCombat = false
  check(#navKeys.calls == n, "設定沒開時進出戰鬥不呼叫鍵盤 API")
  local logEvents
  for _, f in ipairs(frames) do
    local e = rawget(f, "events")
    if e and e.ADDON_ACTION_BLOCKED then logEvents = f end
  end
  check(logEvents ~= nil, "錯誤紀錄監聽 ADDON_ACTION_BLOCKED")
  if logEvents then
    logEvents.scripts.OnEvent(logEvents, "ADDON_ACTION_BLOCKED", "OtherAddon", "Foo()")
    logEvents.scripts.OnEvent(logEvents, "ADDON_ACTION_BLOCKED", "BigFontTuner", "Frame:EnableKeyboard()")
    local found, other = false, false
    for _, e in ipairs(ns.ErrorLog.entries()) do
      if e.msg:find("EnableKeyboard", 1, true) then found = true end
      if e.msg:find("Foo()", 1, true) then other = true end
    end
    check(found and not other, "記錄自己被封鎖的動作，不記別的插件")
  end
end

-- 發布白名單：toc 載入的每個 .lua 都要在 .publish-allowlist，否則 GitHub 發布端缺檔（CurseForge zip 走 toc，不會發現）
do
  local allow = {}
  for raw in io.lines(DIR .. "/.publish-allowlist") do allow[(raw:gsub("\r", ""))] = true end
  for raw in io.lines(DIR .. "/BigFontTuner.toc") do
    local file = raw:gsub("\r", "")
    if file:match("%.lua$") then check(allow[file] == true, "白名單包含 toc 的 " .. file) end
  end
end

os.exit(FAILED and 1 or 0)
