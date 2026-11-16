-- 設定畫面：主要放在內建「選項 → 插件 → BigFontTuner」（使用者 2026-11-07 選 B）。
-- /bft 先試著跳到那一頁；跳不過去（永恆實測 OpenToCategory(ID) 沒反應）才開同樣內容的獨立視窗，共用同一份設定。
-- 預覽的文字直接掛在被調整的字型物件上（SetFontObject），所以預覽看到的就是實際套用的結果。
local addonName, ns = ...
local L = ns.L

local selected = "quest" -- 目前選中的分類（兩份畫面共用）
local instances = {}      -- 每份畫面的元件，用來一起重新整理

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
  s:SetPoint("TOPLEFT", 120, y + 2)
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

  function s:SetLabel(t) text:SetText(t) end

  -- 沒有標題組的分類（聊天）整列隱藏：標籤、滑桿、數值一起
  function s:SetRowShown(show)
    for _, o in ipairs({ text, self, value }) do if show then o:Show() else o:Hide() end end
  end

  -- 程式設定數值時不觸發 onChange（避免切換分類時把值寫回設定）
  function s:SetSilently(v)
    self.silent = true
    self:SetValue(v)
    value:SetText(v)
    self.silent = false
  end
  return s
end

local function makeDropdown(parent, label, y, buildItems, x)
  x = x or 16
  local text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", x, y)
  text:SetText(label)

  local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dd:SetWidth(180)
  dd:SetPoint("TOPLEFT", x + 100, y + 6)
  dd:SetupMenu(function(_, root) buildItems(root) end)
  return dd
end

-- 把目前分類的設定值顯示到每一份畫面上
local function refreshAll()
  if not cur() then return end
  for _, w in ipairs(instances) do
    local cat = ns.GetCategory(selected)
    local hasTitle = cat.title ~= nil
    w.title:SetLabel(ns.GroupLabel(cat, "title"))
    w.body:SetLabel(ns.GroupLabel(cat, "body"))
    w.title:SetRowShown(hasTitle)
    if hasTitle then w.title:SetSilently(ns.GetGroupSize(selected, "title")) end
    w.body:SetSilently(ns.GetGroupSize(selected, "body"))
    w.font:GenerateMenu()
    w.outline:GenerateMenu()
    w.language:GenerateMenu()
    w.global:GenerateMenu()
    w.showPreview(selected)
    w.note:SetText(cat.noteKey and L[cat.noteKey] or "")
    for key, b in pairs(w.tabs) do
      if key == selected then b:LockHighlight() else b:UnlockHighlight() end
    end
  end
end

local function changed()
  ns.ApplyCategory(selected, true)
  refreshAll()
end

-- 在 panel 裡建一份完整的設定內容
local function buildContent(panel)
  local w = {}

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("BigFontTuner")
  local ver = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  ver:SetPoint("LEFT", title, "RIGHT", 8, 0)
  ver:SetText("v" .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))

  -- 全部介面字型（使用者 2026-11-15 選 A）：放在標題右邊，跟分類設定分開
  w.global = makeDropdown(panel, L.GLOBAL_FONT, -16, function(root)
    for _, f in ipairs(ns.GetAvailableFonts()) do
      root:CreateRadio(f.key == ns.FONT_DEFAULT and L.FONT_GAME_DEFAULT or ns.FontLabel(f),
        function() return ns.db.globalFont == f.key end,
        function() ns.SetGlobalFont(f.key); refreshAll() end)
    end
  end, 300)
  local gnote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  gnote:SetPoint("TOPLEFT", 300, -38)
  gnote:SetWidth(340)
  gnote:SetJustifyH("LEFT")
  gnote:SetText(L.GLOBAL_FONT_NOTE)

  -- 分類頁籤
  w.tabs = {}
  local prev
  for _, c in ipairs(ns.CATEGORIES) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    local label = ns.Label(c)
    b:SetSize(c.enabled and 80 or 110, 22)
    b:SetText(c.enabled and label or L.COMING_LATER:format(label))
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 16, -64) end
    if c.enabled then
      b:SetScript("OnClick", function() selected = c.key; refreshAll() end)
    else
      b:Disable()
    end
    w.tabs[c.key] = b
    prev = b
  end

  -- 左側：設定
  w.title = makeSlider(panel, L.TITLE_SIZE, -96, function(v) cur().titleSize = v; changed() end)
  w.body = makeSlider(panel, L.BODY_SIZE, -130, function(v) cur().bodySize = v; changed() end)

  w.font = makeDropdown(panel, L.FONT, -168, function(root)
    for _, f in ipairs(ns.GetAvailableFonts()) do
      root:CreateRadio(ns.FontLabel(f),
        function() return cur().font == f.key end,
        function() cur().font = f.key; changed() end)
    end
  end)

  w.outline = makeDropdown(panel, L.OUTLINE, -206, function(root)
    for _, o in ipairs(ns.OUTLINES) do
      root:CreateRadio(ns.Label(o),
        function() return cur().outline == o.key end,
        function() cur().outline = o.key; changed() end)
    end
  end)

  local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  reset:SetSize(150, 22)
  reset:SetPoint("TOPLEFT", 16, -246)
  reset:SetText(L.RESET)
  reset:SetScript("OnClick", function() ns.ResetCategory(selected); refreshAll() end)

  -- 介面語言：切換後要重新載入介面才會套用（文字在建立畫面時就決定了）
  local reloadNote, reloadBtn
  w.language = makeDropdown(panel, L.LANGUAGE, -290, function(root)
    for _, c in ipairs(ns.LANGUAGE_CHOICES) do
      root:CreateRadio(c.label or L.LANGUAGE_AUTO,
        function() return ns.db.locale == c.key end,
        function()
          ns.db.locale = c.key
          for _, inst in ipairs(instances) do inst.showReload() end
        end)
    end
  end)
  reloadNote = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  reloadNote:SetPoint("TOPLEFT", 16, -320)
  reloadNote:SetText(L.RELOAD_NOTE)
  reloadNote:Hide()
  reloadBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  reloadBtn:SetSize(120, 22)
  reloadBtn:SetPoint("LEFT", reloadNote, "RIGHT", 8, 0)
  reloadBtn:SetText(L.RELOAD)
  reloadBtn:SetScript("OnClick", function() ReloadUI() end)
  reloadBtn:Hide()
  function w.showReload() reloadNote:Show(); reloadBtn:Show() end

  -- 右側：預覽（仿任務視窗的羊皮紙底）
  local plabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  plabel:SetPoint("TOPLEFT", 340, -80)
  plabel:SetText(L.PREVIEW)

  local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  box:SetPoint("TOPLEFT", plabel, "BOTTOMLEFT", -2, -6)
  box:SetSize(300, 250)
  box:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  box:SetBackdropBorderColor(0.42, 0.35, 0.23, 1)
  -- 底色用貼圖畫：2026-11-07 實測 SetBackdropColor 在這裡沒有效果，預覽框是白的
  local bg = box:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 3, -3)
  bg:SetPoint("BOTTOMRIGHT", -3, 3)
  bg:SetColorTexture(0.91, 0.84, 0.66, 1)
  box:SetClipsChildren(true) -- 字級調到很大時，文字不要溢出預覽框

  -- 任務預覽（背包以外的分類共用）與背包預覽，切分類時切換
  local questPreview = CreateFrame("Frame", nil, box)
  questPreview:SetAllPoints()
  local bagPreview = CreateFrame("Frame", nil, box)
  bagPreview:SetAllPoints()
  local profPreview = CreateFrame("Frame", nil, box)
  profPreview:SetAllPoints()

  local function line(fontObject, text, anchor, gap)
    local fs = questPreview:CreateFontString(nil, "ARTWORK")
    fs:SetFontObject(fontObject)
    fs:SetTextColor(0.16, 0.10, 0.03)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(272)
    if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap) else fs:SetPoint("TOPLEFT", 14, -12) end
    fs:SetText(text)
    return fs
  end
  local p1 = line(QuestTitleFont, L.SAMPLE_TITLE)
  local p2 = line(QuestFont, L.SAMPLE_BODY, p1, 6)
  local p3 = line(QuestTitleFont, L.SAMPLE_HEADER, p2, 10)
  line(QuestFont, L.SAMPLE_BODY2, p3, 6)

  -- 背包預覽：深色底蓋住羊皮紙；格子數字登記到 ns.previewCounts，跟背包格子一起套用
  local dark = bagPreview:CreateTexture(nil, "BORDER")
  dark:SetAllPoints(bg)
  dark:SetColorTexture(0.06, 0.06, 0.06, 1)
  local bagFrame = CreateFrame("Frame", nil, bagPreview)
  bagFrame:SetPoint("TOPLEFT", 12, -12)
  bagFrame:SetSize(182, 72)
  local bagBg = bagFrame:CreateTexture(nil, "BACKGROUND")
  bagBg:SetAllPoints()
  bagBg:SetColorTexture(0.12, 0.10, 0.08, 1)
  local bagTitle = bagFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  bagTitle:SetPoint("TOPLEFT", 6, -5)
  bagTitle:SetText(L.SAMPLE_BAG)
  local slots = {
    { "Interface\\Icons\\INV_Ore_Copper_01", "20" },
    { "Interface\\Icons\\INV_Misc_Flower_02", "5" },
    { "Interface\\Icons\\INV_Potion_51", "12" },
    { "Interface\\Icons\\INV_Misc_Food_15" },
  }
  ns.previewCounts = ns.previewCounts or {}
  for i, info in ipairs(slots) do
    local icon = bagFrame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(38, 38)
    icon:SetPoint("TOPLEFT", 6 + (i - 1) * 43, -24)
    icon:SetTexture(info[1])
    if info[2] then
      local count = bagFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
      count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 2)
      count:SetText(info[2])
      table.insert(ns.previewCounts, count)
    end
  end

  local tip = CreateFrame("Frame", nil, bagPreview, "BackdropTemplate")
  tip:SetPoint("TOPLEFT", bagFrame, "BOTTOMLEFT", 40, -14)
  tip:SetSize(236, 140)
  tip:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  local tipBg = tip:CreateTexture(nil, "BACKGROUND")
  tipBg:SetPoint("TOPLEFT", 3, -3)
  tipBg:SetPoint("BOTTOMRIGHT", -3, 3)
  tipBg:SetColorTexture(0.03, 0.03, 0.12, 0.95)
  local function tipLine(fontObject, text, color, anchor)
    local fs = tip:CreateFontString(nil, "ARTWORK")
    fs:SetFontObject(fontObject)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetWidth(212)
    if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3) else fs:SetPoint("TOPLEFT", 10, -9) end
    fs:SetText(text)
    return fs
  end
  local t1 = tipLine(GameTooltipHeaderText, L.SAMPLE_ITEM, { 1, 1, 1 })
  local t2 = tipLine(GameTooltipText, L.SAMPLE_ITEM_TYPE, { 1, 1, 1 }, t1)
  tipLine(GameTooltipText, L.SAMPLE_ITEM_DESC, { 1, 0.82, 0 }, t2)

  -- 專業預覽：深色底，上半仿右側配方資訊、下半仿左側清單；文字登記到 ns.previewProf，跟專業視窗一起套用
  local profDark = profPreview:CreateTexture(nil, "BORDER")
  profDark:SetAllPoints(bg)
  profDark:SetColorTexture(0.09, 0.07, 0.05, 1)
  ns.previewProf = ns.previewProf or { title = {}, body = {} }
  local function profLine(group, fontObject, text, color, anchor, gap)
    local fs = profPreview:CreateFontString(nil, "ARTWORK")
    fs:SetFontObject(fontObject)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetWidth(272)
    if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap) else fs:SetPoint("TOPLEFT", 14, -12) end
    fs:SetText(text)
    table.insert(ns.previewProf[group], fs)
    return fs
  end
  local white, yellow, gray = { 1, 1, 1 }, { 1, 0.82, 0 }, { 0.6, 0.6, 0.6 }
  local r1 = profLine("title", GameFontHighlightMed2 or GameFontHighlightLarge, L.SAMPLE_PROF_RECIPE, white)
  local r2 = profLine("body", GameFontHighlightSmall2 or GameFontHighlightSmall, L.SAMPLE_PROF_DESC, white, r1, 6)
  local r3 = profLine("body", GameFontHighlight_NoShadow or GameFontHighlight, L.SAMPLE_PROF_REAGENT, white, r2, 6)
  local r4 = profLine("title", GameFontNormal_NoShadow or GameFontNormal, L.SAMPLE_PROF_CATEGORY, yellow, r3, 16)
  local r5 = profLine("body", GameFontHighlight_NoShadow or GameFontHighlight, L.SAMPLE_PROF_ROW1, yellow, r4, 6)
  profLine("body", GameFontHighlight_NoShadow or GameFontHighlight, L.SAMPLE_PROF_ROW2, gray, r5, 4)

  function w.showPreview(key)
    questPreview:SetShown(key ~= "bag" and key ~= "profession")
    bagPreview:SetShown(key == "bag")
    profPreview:SetShown(key == "profession")
  end

  -- 分類說明（例：背包會連帶影響哪些地方）
  w.note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  w.note:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
  w.note:SetWidth(300)
  w.note:SetJustifyH("LEFT")

  local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 16, 14)
  hint:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.HINT .. "\n" .. L.COMMANDS:format("/bigfonttuner" .. (SLASH_BIGFONTTUNER2 and ", /bft" or "")))

  -- 預覽數字是建立畫面時才有的，打開時套用一次背包設定（失敗只記錄，不擋設定頁）
  panel:HookScript("OnShow", function() (ns.ErrorLog and ns.ErrorLog.try or pcall)(ns.ApplyCategory, "bag") end)
  panel:HookScript("OnShow", refreshAll)
  table.insert(instances, w)
  return w
end

local win

local function createWindow()
  local ok, f = pcall(CreateFrame, "Frame", "BigFontTunerWindow", UIParent, "BasicFrameTemplateWithInset")
  if not ok then
    f = CreateFrame("Frame", "BigFontTunerWindow", UIParent, "BackdropTemplate")
  end
  f:SetSize(680, 470)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  if f.TitleText then f.TitleText:SetText("BigFontTuner") end
  tinsert(UISpecialFrames, "BigFontTunerWindow") -- 按 Esc 可以關閉
  return f
end

local category, optionsPage

local function registerOptionsPage()
  optionsPage = CreateFrame("Frame")
  buildContent(optionsPage)
  category = Settings.RegisterCanvasLayoutCategory(optionsPage, "BigFontTuner")
  Settings.RegisterAddOnCategory(category)
end

-- 獨立視窗只在跳不到選項頁時才建立（使用者 2026-11-07 選 B：設定以選項頁為主）
local function ensureWindow()
  if win then return end
  win = createWindow()
  local panel = CreateFrame("Frame", nil, win)
  panel:SetPoint("TOPLEFT", 4, -24)
  panel:SetPoint("BOTTOMRIGHT", -4, 4)
  buildContent(panel)
end

function ns.CreateSettings()
  if Settings and Settings.RegisterCanvasLayoutCategory then
    (ns.ErrorLog and ns.ErrorLog.try or pcall)(registerOptionsPage)
  end
end

-- 頁面第一次被開啟前還沒掛進選項面板，沒有 parent 的 frame 的 IsVisible() 是 true，
-- 所以只看 IsVisible 會以為設定已開著而什麼都不做（2026-11-10 遊戲內確認：沒開過選項頁時 /bft 沒反應）
local function pageOpen()
  return optionsPage and SettingsPanel and SettingsPanel:IsShown() and optionsPage:IsVisible()
end

-- 試著跳到選項 → 插件 → BigFontTuner。OpenToCategory(ID) 在永恆實測沒反應，所以依序試幾種寫法，
-- 以「我們的頁面真的顯示出來」判斷成功（不看呼叫有沒有報錯）。
local function tryOpenOptionsPage()
  if not (category and optionsPage) then return false end
  local attempts = {
    function() Settings.OpenToCategory(category:GetID()) end,
    function() Settings.OpenToCategory(category) end,
    function() Settings.OpenToCategory("BigFontTuner") end,
    function() SettingsPanel:Show(); SettingsPanel:SelectCategory(category) end,
    function() SettingsPanel:OpenToCategory(category:GetID()) end,
  }
  for _, attempt in ipairs(attempts) do
    pcall(attempt)
    if pageOpen() then return true end
  end
  if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
  return false
end

-- /bft：優先開選項頁，跳不過去才開獨立視窗。戰鬥中選項面板有 taint 風險，直接用獨立視窗。
function ns.OpenSettings()
  if pageOpen() then
    HideUIPanel(SettingsPanel)
    return
  end
  if win and win:IsShown() then win:Hide(); return end
  if not InCombatLockdown() and tryOpenOptionsPage() then return end
  ensureWindow()
  win:Show()
end
