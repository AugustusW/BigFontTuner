-- 專業視窗分類（使用者 2026-11-16 選 1A 2A）：只改專業視窗裡的文字，不動共用字型物件，其他視窗不受影響。
-- 結構照暴雪 Blizzard_ProfessionsTemplates；永恆 2026-11-16 /fstack 確認 ProfessionsFrame.CraftingPage.SchematicForm。
-- 專業視窗是隨需載入（第一次打開才有 ProfessionsFrame），所以 hook 等 Blizzard_Professions 載入後才掛（Core 的 setupLoaded）。
-- 標題組＝右側配方名稱＋清單分類標題；內文組＝清單每列名稱與可製作數量、說明、需要的工具、材料名稱。
-- 清單列高原本固定（配方 20、分類 25），字變大時跟著加高（2A），一頁能看到的配方會變少。
local _, ns = ...

local KEY = "profession"
ns.previewProf = ns.previewProf or { title = {}, body = {} } -- 設定頁預覽的文字（Settings.lua 填入）

local function page()
  local f = _G.ProfessionsFrame
  return type(f) == "table" and f.CraftingPage or nil
end

local function scrollBox()
  local p = page()
  return p and p.RecipeList and p.RecipeList.ScrollBox
end

local function form()
  local p = page()
  return p and p.SchematicForm
end

-- 清單的列：配方列有 SkillUps，分類標題有 CollapseIcon，分隔線只有 Label
local function rowGroup(row)
  if row.SkillUps then return "body", { row.Label, row.Count } end
  return "title", { row.Label }
end

local function eachRow(fn)
  local sb = scrollBox()
  if not (sb and sb.ForEachFrame) then return end
  sb:ForEachFrame(fn)
end

local function addRows(list, want)
  eachRow(function(row)
    local group, objs = rowGroup(row)
    if group == want then for _, o in ipairs(objs) do list[#list + 1] = o end end
  end)
end

-- 可變參數：中間有 nil（例：沒有重製用的文字）也要繼續往後加，ipairs 遇到 nil 就會停
local function add(list, ...)
  for i = 1, select("#", ...) do
    local o = select(i, ...)
    if o ~= nil then list[#list + 1] = o end
  end
end

local function titleObjects()
  local list, f = {}, form()
  if f then add(list, f.OutputText, f.RecraftingOutputText) end
  addRows(list, "title")
  add(list, unpack(ns.previewProf.title))
  return list
end

local function bodyObjects()
  local list, f = {}, form()
  if f then
    add(list, f.Description, f.RecraftingDescription, f.RequiredTools, f.RecraftingRequiredTools)
    local pool = f.reagentSlotPool
    if pool and pool.EnumerateActive then
      for slot in pool:EnumerateActive() do
        if type(slot) == "table" and slot.Name then list[#list + 1] = slot.Name end
      end
    end
  end
  addRows(list, "body")
  add(list, unpack(ns.previewProf.body))
  return list
end

-- 文字框原本有固定高度（配方名稱 12、分類標題 10），放大的字放不進去會被切掉：高度加上字級增加的量
local origHeights = setmetatable({}, { __mode = "k" })
-- 字型改之前記下原本高度（沒有固定高度的文字框，改字後量到的是放大後的高度）
local function rememberHeights(objs)
  for _, fs in ipairs(objs) do
    if type(fs) == "table" and fs.GetHeight and not origHeights[fs] then origHeights[fs] = fs:GetHeight() end
  end
end

local function fitHeights(objs)
  for _, fs in ipairs(objs) do
    local orig = type(fs) == "table" and fs.GetHeight and ns.OriginalSize(fs)
    if orig then
      if not origHeights[fs] then origHeights[fs] = fs:GetHeight() end
      local ok, _, size = pcall(fs.GetFont, fs)
      if ok and size then fs:SetHeight(origHeights[fs] + math.max(0, size - orig)) end
    end
  end
end

local function applyRow(row)
  if type(row) ~= "table" or not row.Label then return end
  local group, objs = rowGroup(row)
  rememberHeights(objs)
  ns.ApplyObjects(KEY, group, objs)
  fitHeights(objs)
end

-- 列高增加量：清單文字原本的字級（取自它們繼承的字型物件，沒有就用暴雪的 12）放大後多出來的部分
local function fontSize(name, fallback)
  local o = _G[name]
  if type(o) == "table" and o.GetFont then
    local ok, _, size = pcall(o.GetFont, o)
    if ok and size then return ns.OriginalSize(o) or size end
  end
  return fallback
end

local function extra(group, fontName)
  local orig = fontSize(fontName, 12)
  return math.max(0, ns.ScaledSize(KEY, group, orig) - orig)
end

local function wrapExtents(view)
  if not (view and view.GetElementExtentCalculator and view.SetElementExtentCalculator) then return end
  local orig = view:GetElementExtentCalculator()
  if type(orig) ~= "function" then return end
  -- 在暴雪排版途中被呼叫：我們這段出錯就退回原本的高度，不能讓清單排版壞掉
  local function grow(h, node)
    local data = node and node.GetData and node:GetData()
    if type(data) ~= "table" then return h end
    if data.recipeInfo then return h + extra("body", "GameFontHighlight_NoShadow") end
    if data.categoryInfo then return h + extra("title", "GameFontNormal_NoShadow") end
    return h
  end
  view:SetElementExtentCalculator(function(dataIndex, node)
    local h = orig(dataIndex, node)
    if type(h) ~= "number" then return h end
    local ok, grown = pcall(grow, h, node)
    return ok and grown or h
  end)
end

-- 設定真的變了才重建清單（重建會重新建立每一列，暴雪的列寬計算才會用新字級）
local lastSig
local function signature(s)
  return table.concat({ tostring(s.titleSize), tostring(s.bodySize), tostring(s.font), tostring(s.outline),
    tostring(ns.db.globalFont) }, "|")
end

local hookedRows = setmetatable({}, { __mode = "k" })

local function setup()
  local sb = scrollBox()
  if sb then
    wrapExtents(sb.GetView and sb:GetView())
    local try = ns.ErrorLog and ns.ErrorLog.try or pcall
    local function onRow(row)
      if type(row) ~= "table" then return end
      applyRow(row)
      -- 分類標題滑鼠移入／移出時遊戲用 SetFontObject 換字型，會洗掉放大：之後再套一次
      if row.CollapseIcon and row.HookScript and not hookedRows[row] then
        hookedRows[row] = true
        local function again() try(applyRow, row) end
        row:HookScript("OnEnter", again)
        row:HookScript("OnLeave", again)
      end
    end
    -- 列在建立時（暴雪 Init 計算列寬之前）先套字型；回收再用的列也會經過這裡。
    -- 已經存在的列自己跑一次：ScrollUtil 的 iterateExisting 是 ForEachFrame(callback)，參數 (frame, elementData)
    -- 跟建立事件的 (owner, frame, ...) 不同，共用同一個回呼會拿錯參數（審查抓到）
    if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
      ScrollUtil.AddAcquiredFrameCallback(sb, function(_, row) try(onRow, row) end, ns)
    end
    eachRow(function(row) try(onRow, row) end)
  end
  local f = form()
  if f and hooksecurefunc and type(f.Init) == "function" then
    -- 換配方時材料欄位是新建立的，Init 之後套一次
    hooksecurefunc(f, "Init", function() (ns.ErrorLog and ns.ErrorLog.try or pcall)(ns.ApplyCategory, KEY) end)
  end
  local s = ns.db.categories[KEY]
  lastSig = s and signature(s)
end

local function after(s)
  eachRow(function(row)
    local _, objs = rowGroup(row)
    fitHeights(objs)
  end)
  local sig = signature(s)
  if sig == lastSig then return end
  lastSig = sig
  local sb = scrollBox()
  local view = sb and sb.GetView and sb:GetView()
  if sb and sb.Rebuild and view and view.GetDataProvider and view:GetDataProvider() then
    sb:Rebuild(true) -- true＝保留捲動位置（ScrollBoxConstants.RetainScrollPosition）
  end
end

table.insert(ns.CATEGORIES, {
  key = KEY, labelKey = "CATEGORY_PROFESSION", enabled = true,
  titleLabelKey = "PROF_TITLE_SIZE", bodyLabelKey = "PROF_BODY_SIZE", noteKey = "PROF_NOTE",
  title = titleObjects, titleBase = "GameFontHighlightMed2",
  body = bodyObjects, bodyBase = "GameFontHighlight_NoShadow",
  loadOn = "Blizzard_Professions", setup = setup, after = after,
})
