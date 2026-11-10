-- 錯誤紀錄：接在遊戲的全域錯誤處理器後面，只留自己插件的錯誤，玩家回報問題時可複製給開發者。
-- 插件不能連網也不能寫檔，紀錄只存在 SavedVariables。
-- TOC 第一個載入，而且不依賴其他檔案：主程式載入失敗時正是最需要這份紀錄的時候。
local ADDON, ns = ...

-- 兩個插件共用同一份程式，只有這幾個常數不同
local DB_NAME = "BigFontTunerDB"
local SLASH_KEYS = { "BIGFONTTUNER" }
local ALIAS_KEY, ALIAS_CMD = "BFTERRORS", "/bfterrors"
local FRAME_NAME = "BigFontTunerErrorLogFrame"

local MAX_ENTRIES, MAX_BYTES, MSG_BYTES = 20, 2048, 512
local STACK_INTERVAL = 1 -- 秒：別的插件連續報錯時，查堆疊的頻率上限
local OWN_PATH = "AddOns/" .. ADDON .. "/"
local SELF_PATH = OWN_PATH .. "ErrorLog.lua"
local POPUP_KEY = ADDON:upper() .. "_CLEAR_ERRORS"

local Log = { try = pcall } -- 檔案後段出錯時，呼叫端至少還有 pcall 的行為
ns.ErrorLog = Log

-- Locale.lua 載入失敗時視窗仍要能開：字串退回鍵名
local function strings()
  return ns.L or setmetatable({}, { __index = function(_, k) return k end })
end

local entries = {} -- 接上 SavedVariables 前的暫存；之後就是存檔裡那張表，順序為最近發生的在前
local prevHandler
local lastStackAt
local refreshWindow -- 定義在視窗區段；視窗開著時新錯誤要反映到文字框，否則複製到的是舊內容

-- 文字中第一個非遊戲內建的插件名稱：錯誤訊息的路徑、堆疊最上層都是實際出錯的那一方。
-- 只看「有沒有自己」會誤收：自己呼叫遊戲函式，遊戲再呼叫別的插件時，堆疊底下也有自己。
local function firstAddon(text)
  for name in (text:gsub("\\", "/")):gmatch("AddOns/([^/]+)/") do
    if name:sub(1, 9) ~= "Blizzard_" then return name end
  end
end

-- 截到 n 位元組內，不切斷 UTF-8 字元
local function cut(s, n)
  if #s <= n then return s end
  local i = n
  while i > 0 and s:byte(i + 1) >= 0x80 and s:byte(i + 1) < 0xC0 do i = i - 1 end
  return s:sub(1, i)
end

-- 堆疊去掉 ErrorLog.lua 自身的行：取堆疊的當下處理函式一定在裡面，留著會讓所有錯誤都像自己的
local function getStack()
  if not debugstack then return "" end
  local kept = {}
  for line in (debugstack(1, 30, 0) .. "\n"):gmatch("(.-)\n") do
    if line ~= "" and not (line:gsub("\\", "/")):find(SELF_PATH, 1, true) then kept[#kept + 1] = line end
  end
  return table.concat(kept, "\n")
end

local function env()
  local version, build, _, iface = GetBuildInfo()
  local get = C_AddOns and C_AddOns.GetAddOnMetadata
  return string.format("%s | %s %s.%s | %s", get and get(ADDON, "Version") or "?",
    (tonumber(iface) or 0) >= 100000 and "Retail" or "Forever", tostring(version), tostring(build), GetLocale())
end

local function indexOf(msg)
  for i, e in ipairs(entries) do if e.msg == msg then return i end end
end

-- 新增或累加，並移到最前面；超過上限時移除最久沒發生的
local function upsert(entry)
  local i = indexOf(entry.msg)
  if i then
    local old = table.remove(entries, i)
    entry.count = old.count + entry.count
    entry.stack = old.stack ~= "" and old.stack or entry.stack
  end
  table.insert(entries, 1, entry)
  while #entries > MAX_ENTRIES do table.remove(entries) end
end

local function capture(err, forced)
  local msg = cut(tostring(err), MSG_BYTES)
  local who = firstAddon(msg)
  if who and who ~= ADDON then return end -- 路徑是別的插件：連堆疊都不用查，try 接住的也一樣
  local stack = ""
  if who == ADDON or forced then
    if not indexOf(msg) then stack = getStack() end
  else
    -- 訊息沒有插件路徑（例如內建函式的 Usage: ...）才查堆疊
    local now = GetTime and GetTime() or time()
    if lastStackAt and now - lastStackAt < STACK_INTERVAL then return end
    lastStackAt = now
    stack = getStack()
    if firstAddon(stack) ~= ADDON then return end
  end
  upsert({ msg = msg, stack = cut(stack, MAX_BYTES - #msg), count = 1, last = date("%Y-%m-%d %H:%M:%S"), env = env() })
  refreshWindow()
end

local function onError(err)
  pcall(capture, err) -- 記錄邏輯自己出錯也不能影響遊戲原本的錯誤處理
  if prevHandler then return prevHandler(err) end
end

if seterrorhandler and geterrorhandler then
  prevHandler = geterrorhandler()
  seterrorhandler(onError)
end

function Log.entries() return entries end

function Log.clear()
  for i = #entries, 1, -1 do entries[i] = nil end
end

-- 與 pcall 相同的回傳值，失敗時連堆疊一起記錄：給「出錯不能跳錯誤視窗」的地方用
function Log.try(fn, ...)
  local n, args = select("#", ...), { ... }
  return xpcall(function() return fn(unpack(args, 1, n)) end, function(err)
    pcall(capture, err, true)
    return err
  end)
end

function Log.report()
  local lines = { ADDON .. " " .. env(), "Errors: " .. #entries }
  local current = env()
  for i, e in ipairs(entries) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("#%d  x%d  %s", i, e.count, tostring(e.last))
      .. (e.env ~= current and "  [" .. tostring(e.env) .. "]" or "")
    lines[#lines + 1] = e.msg
    if e.stack ~= "" then
      lines[#lines + 1] = "Stack:"
      lines[#lines + 1] = e.stack
    end
  end
  return table.concat(lines, "\n")
end

local function attach()
  local db = _G[DB_NAME]
  if type(db) ~= "table" then db = {}; _G[DB_NAME] = db end
  local clean = {}
  for _, e in ipairs(type(db.errors) == "table" and db.errors or {}) do
    if type(e) == "table" and type(e.msg) == "string" then
      e.stack = type(e.stack) == "string" and e.stack or ""
      e.count = tonumber(e.count) or 1
      clean[#clean + 1] = e
    end
  end
  db.errors = clean
  local pending = entries
  entries = clean
  for i = #pending, 1, -1 do upsert(pending[i]) end
  while #entries > MAX_ENTRIES do table.remove(entries) end
end

local frame, box, hint, selectAll, clearAll
local shownText = ""

local function render()
  if not frame then return end
  local any = #entries > 0
  local L = strings()
  shownText = any and Log.report() or ""
  box:SetText(shownText)
  hint:SetText(any and L.ERRORS_HINT or L.ERRORS_EMPTY)
  selectAll:SetEnabled(any)
  clearAll:SetEnabled(any)
end

-- 合併更新：別的錯誤連續發生時不能每次都重設整段文字
local refreshPending = false
refreshWindow = function()
  if refreshPending or not (frame and frame:IsShown() and C_Timer and C_Timer.After) then return end
  refreshPending = true
  C_Timer.After(0.5, function() refreshPending = false; render() end)
end

local function confirmClear()
  if #entries == 0 then return end
  local L = strings()
  StaticPopupDialogs[POPUP_KEY] = StaticPopupDialogs[POPUP_KEY] or {
    text = L.ERRORS_CLEAR_CONFIRM, button1 = L.ERRORS_CLEAR_OK, button2 = L.ERRORS_CANCEL,
    OnAccept = function() Log.clear(); render() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show(POPUP_KEY)
end

local function build()
  local L = strings()
  frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(600, 430)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  local title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if not frame.TitleText then title:SetPoint("TOP", 0, -5) end
  title:SetText(L.ERRORS_TITLE)
  hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 12, -30)
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -50)
  scroll:SetSize(550, 335)
  box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetFontObject("ChatFontNormal")
  box:SetWidth(540)
  box:SetAutoFocus(false)
  box:ClearFocus() -- EditBox 建立當下會搶焦點，要立刻放掉，否則遊戲的快捷鍵都會被吃掉
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  box:SetScript("OnHide", function(self) self:ClearFocus() end)
  -- 可複製但不能編輯：玩家輸入時還原內容
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(shownText); self:HighlightText() end
  end)
  frame:SetScript("OnHide", function() box:ClearFocus() end)
  scroll:SetScrollChild(box)
  clearAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  clearAll:SetSize(100, 22)
  clearAll:SetPoint("BOTTOMRIGHT", -10, 8)
  clearAll:SetText(L.ERRORS_CLEAR)
  clearAll:SetScript("OnClick", confirmClear)
  selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  selectAll:SetSize(100, 22)
  selectAll:SetPoint("RIGHT", clearAll, "LEFT", -8, 0)
  selectAll:SetText(L.ERRORS_SELECT_ALL)
  selectAll:SetScript("OnClick", function() box:SetFocus(); box:HighlightText() end)
  tinsert(UISpecialFrames, FRAME_NAME)
end

function Log.show()
  if not frame then build() end
  render()
  frame:Show()
  box:ClearFocus()
end

-- errors 子指令；回傳是否已處理
function Log.command(msg)
  local sub, arg = (msg or ""):lower():match("^%s*(%S+)%s*(%S*)")
  if sub ~= "errors" then return false end
  if arg == "test" and ns.errorLogSelfTest then
    ns.errorLogSelfTest()
  else
    Log.show()
    if arg == "clear" then confirmClear() end
  end
  return true
end

-- 包住既有指令攔截 errors，其他照舊；等 PLAYER_LOGIN，所有指令都已註冊
local function wrapSlash()
  for _, key in ipairs(SLASH_KEYS) do
    local original = SlashCmdList[key]
    if original then
      SlashCmdList[key] = function(msg, ...)
        if not Log.command(msg) then return original(msg, ...) end
      end
    end
  end
end

local function aliasFree()
  for k, v in pairs(_G) do
    if type(k) == "string" and k:sub(1, 6) == "SLASH_" and type(v) == "string" and v:lower() == ALIAS_CMD then return false end
  end
  return true
end

-- 備用指令在載入當下註冊：主程式載入失敗、主指令不存在時仍查得到紀錄
if SlashCmdList and aliasFree() then
  _G["SLASH_" .. ALIAS_KEY .. "1"] = ALIAS_CMD
  SlashCmdList[ALIAS_KEY] = function(msg) Log.command("errors " .. (msg or "")) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, ev, name)
  if ev == "ADDON_LOADED" and name == ADDON then attach()
  elseif ev == "PLAYER_LOGIN" then wrapSlash() end
end)
