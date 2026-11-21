-- 設定頁的方向鍵導航（手把模式下十字鍵、A 會被遊戲轉成方向鍵與 Enter，2026-11-20 永恆實測）。
-- 這裡只放決策邏輯，不碰任何 frame：Settings.lua 提供項目表，依回傳值決定按鍵要不要往下傳給遊戲。
-- 項目：{ id, isShown(), isEnabled(), left()?, right()?, enter()? }
-- 狀態：{ focus = id, revealed = 是否已顯示亮框 }
local _, ns = ...
local Nav = {}
ns.Nav = Nav

local function usable(it)
  return it.isShown() and it.isEnabled()
end

local function indexOf(items, id)
  for i, it in ipairs(items) do
    if it.id == id then return i end
  end
  return nil
end

local function firstUsable(items)
  for _, it in ipairs(items) do
    if usable(it) then return it.id end
  end
  return nil
end

-- 焦點項目不見了（隱藏、停用、還沒設定）：落到原位置之後第一個可用項，沒有就之前最後一個
function Nav.ensureFocus(state, items)
  local i = indexOf(items, state.focus)
  if i and usable(items[i]) then return end
  if not i then
    state.focus = firstUsable(items)
    return
  end
  for j = i + 1, #items do
    if usable(items[j]) then state.focus = items[j].id; return end
  end
  for j = i - 1, 1, -1 do
    if usable(items[j]) then state.focus = items[j].id; return end
  end
  state.focus = nil
end

function Nav.reset(state)
  state.focus = nil
  state.revealed = false
end

local MOVE = { UP = -1, DOWN = 1 }
local ARROWS = { UP = true, DOWN = true, LEFT = true, RIGHT = true }

-- 回傳 true＝這個鍵由設定頁處理（不要往下傳給遊戲）
function Nav.handle(state, items, key, ctx)
  if ctx.combat or ctx.modifier or ctx.editFocus then return false end
  if not ARROWS[key] and key ~= "ENTER" then return false end

  -- 第一次按鍵只把亮框叫出來，避免對看不見的焦點動作
  if not state.revealed then
    if key == "ENTER" then return false end
    state.revealed = true
    state.focus = firstUsable(items)
    return true
  end

  Nav.ensureFocus(state, items)
  local i = indexOf(items, state.focus)
  if not i then return ARROWS[key] or false end
  local it = items[i]

  if MOVE[key] then
    local step = MOVE[key]
    local j = i + step
    while j >= 1 and j <= #items do
      if usable(items[j]) then state.focus = items[j].id; break end
      j = j + step
    end
    return true -- 到頭也吃掉，避免角色移動
  end
  if key == "LEFT" then
    if it.left then it.left() end
    return true
  end
  if key == "RIGHT" then
    if it.right then it.right() end
    return true
  end
  -- ENTER：按鈕就按下；其他項目吃掉但不做事（手把 A＝Enter，往下傳會打開聊天框）
  if it.enter then it.enter() end
  return true
end

-- 下拉選單：依目前選中的項目往前／往後一項；到頭回 nil；目前值不在清單時右＝第一項、左＝最後一項
function Nav.step(entries, dir)
  if #entries == 0 then return nil end
  local cur
  for i, e in ipairs(entries) do
    if e.isSelected() then cur = i; break end
  end
  if not cur then
    return dir > 0 and entries[1] or entries[#entries]
  end
  return entries[cur + dir]
end
