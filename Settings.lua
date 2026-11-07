-- 設定頁：放在遊戲內建「選項 → 插件」裡的自訂畫布（canvas layout），附即時預覽。
-- 預覽的文字直接掛在被調整的字型物件上（SetFontObject），所以預覽看到的就是實際套用的結果。
local addonName, ns = ...

local selected = "quest" -- 目前選中的分類
local widgets = {}

local function cur()
  return ns.db.categories[selected]
end

local function makeSlider(parent, label, y, onChange)
  local text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 16, y)
  text:SetText(label)

  local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
  s:SetOrientation("HORIZONTAL")
  s:SetSize(150, 16)
  s:SetPoint("TOPLEFT", 110, y + 2)
  s:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
  })
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:GetThumbTexture():SetSize(32, 32)
  s:SetMinMaxValues(ns.SIZE_MIN, ns.SIZE_MAX)
  s:SetValueStep(1)
  -- 永恆客戶端的 Slider 沒有 SetObeyStepDrag（2026-11-07 實測 nil），數值在 OnValueChanged 取整
  if s.SetObeyStepDrag then s:SetObeyStepDrag(true) end

  local value = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  value:SetPoint("LEFT", s, "RIGHT", 10, 0)

  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v + 0.5)
    value:SetText(v)
    if not self.silent then onChange(v) end
  end)

  -- 程式設定數值時不觸發 onChange（避免切換分類時把值寫回設定）
  function s:SetSilently(v)
    self.silent = true
    self:SetValue(v)
    value:SetText(v)
    self.silent = false
  end
  return s
end

local function makeDropdown(parent, label, y, buildItems)
  local text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 16, y)
  text:SetText(label)

  local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dd:SetWidth(170)
  dd:SetPoint("TOPLEFT", 106, y + 6)
  dd:SetupMenu(function(_, root) buildItems(root) end)
  return dd
end

-- 把目前分類的設定值顯示到元件上
local function refresh()
  local s = cur()
  if not s then return end
  widgets.title:SetSilently(ns.GetGroupSize(selected, "title"))
  widgets.body:SetSilently(ns.GetGroupSize(selected, "body"))
  widgets.font:GenerateMenu()
  widgets.outline:GenerateMenu()
  for key, b in pairs(widgets.tabs) do
    if key == selected then b:LockHighlight() else b:UnlockHighlight() end
  end
end

local function changed()
  ns.ApplyCategory(selected, true)
end

-- 2026-11-07 遊戲內實測：註冊到內建選項後，Settings.OpenToCategory 打不開這一頁，
-- 選項視窗裡也找不到（Settings.GetCategory 回 nil）。所以設定畫面改成獨立視窗（mockup 方案 B 的形式），
-- 內容與預覽照舊；內建選項只放一個「開啟設定視窗」按鈕，能註冊就註冊，失敗也不影響 /bft。
local win

local function createWindow()
  local ok, w = pcall(CreateFrame, "Frame", "BigFontTunerWindow", UIParent, "BasicFrameTemplateWithInset")
  if not ok then
    w = CreateFrame("Frame", "BigFontTunerWindow", UIParent, "BackdropTemplate")
  end
  w:SetSize(660, 400)
  w:SetPoint("CENTER")
  w:SetFrameStrata("DIALOG")
  w:SetMovable(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", w.StartMoving)
  w:SetScript("OnDragStop", w.StopMovingOrSizing)
  w:Hide()
  if w.TitleText then w.TitleText:SetText("BigFontTuner") end
  tinsert(UISpecialFrames, "BigFontTunerWindow") -- 按 Esc 可以關閉
  return w
end

local function registerOptionsEntry()
  local opt = CreateFrame("Frame")
  local t = opt:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  t:SetPoint("TOPLEFT", 16, -16)
  t:SetText("BigFontTuner")
  local b = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
  b:SetSize(160, 24)
  b:SetPoint("TOPLEFT", 16, -50)
  b:SetText("開啟設定視窗")
  b:SetScript("OnClick", function() ns.OpenSettings() end)
  local category = Settings.RegisterCanvasLayoutCategory(opt, "BigFontTuner")
  Settings.RegisterAddOnCategory(category)
end

function ns.CreateSettings()
  win = createWindow()
  local panel = CreateFrame("Frame", nil, win)
  panel:SetPoint("TOPLEFT", 4, -24)
  panel:SetPoint("BOTTOMRIGHT", -4, 4)

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("BigFontTuner")
  local ver = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  ver:SetPoint("LEFT", title, "RIGHT", 8, 0)
  ver:SetText("v" .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))

  -- 分類頁籤
  widgets.tabs = {}
  local prev
  for _, c in ipairs(ns.CATEGORIES) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(c.enabled and 70 or 100, 22)
    b:SetText(c.enabled and c.label or (c.label .. "（之後）"))
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 16, -46) end
    if c.enabled then
      b:SetScript("OnClick", function() selected = c.key; refresh() end)
    else
      b:Disable()
    end
    widgets.tabs[c.key] = b
    prev = b
  end

  -- 左側：設定
  widgets.title = makeSlider(panel, "標題字級", -90, function(v) cur().titleSize = v; changed() end)
  widgets.body = makeSlider(panel, "內文字級", -124, function(v) cur().bodySize = v; changed() end)

  widgets.font = makeDropdown(panel, "字型", -162, function(root)
    for _, f in ipairs(ns.GetAvailableFonts()) do
      root:CreateRadio(f.label,
        function() return cur().font == f.key end,
        function() cur().font = f.key; changed() end)
    end
  end)

  widgets.outline = makeDropdown(panel, "描邊", -200, function(root)
    for _, o in ipairs(ns.OUTLINES) do
      root:CreateRadio(o.label,
        function() return cur().outline == o.key end,
        function() cur().outline = o.key; changed() end)
    end
  end)

  local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  reset:SetSize(140, 22)
  reset:SetPoint("TOPLEFT", 16, -240)
  reset:SetText("恢復此分類預設")
  reset:SetScript("OnClick", function() ns.ResetCategory(selected); refresh() end)

  -- 右側：預覽（仿任務視窗的羊皮紙底）
  local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  box:SetPoint("TOPLEFT", 320, -84)
  box:SetSize(300, 260)
  box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  box:SetBackdropColor(0.91, 0.84, 0.66, 1)
  box:SetBackdropBorderColor(0.42, 0.35, 0.23, 1)
  box:SetClipsChildren(true) -- 字級調到很大時，文字不要溢出預覽框

  local plabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  plabel:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 2, 4)
  plabel:SetText("預覽（即時更新）")

  local function line(fontObject, text, anchor, gap)
    local fs = box:CreateFontString(nil, "ARTWORK")
    fs:SetFontObject(fontObject)
    fs:SetTextColor(0.16, 0.10, 0.03)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(272)
    if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap) else fs:SetPoint("TOPLEFT", 14, -12) end
    fs:SetText(text)
    return fs
  end
  local p1 = line(QuestTitleFont, "十字路口的徵兵行動")
  local p2 = line(QuestFont, "從卡加雨的前哨站往西走。在T字路口左轉，然後朝南走。", p1, 6)
  local p3 = line(QuestTitleFont, "描述", p2, 10)
  line(QuestFont, "把這份簽好的募兵函拿到十字路口去。", p3, 6)

  local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 16, 16)
  hint:SetJustifyH("LEFT")
  hint:SetText("調整後立即套用，設定自動儲存（帳號共用）。字型清單只列出驗證過存在的字型。\n指令：/bigfonttuner" .. (SLASH_BIGFONTTUNER2 and "、/bft" or ""))

  panel:SetScript("OnShow", refresh)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    pcall(registerOptionsEntry)
  end
end

-- /bft：開關獨立設定視窗（一般視窗，戰鬥中也能開）
function ns.OpenSettings()
  if not win then return end
  if win:IsShown() then win:Hide() else win:Show() end
end
