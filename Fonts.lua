-- 字型清單。
-- addon 讀不到資料夾，所以只能列「候選字型」，載入時逐一驗證，驗證通過的才出現在選單。
-- 內建字型在遊戲的封存檔裡（Fonts 資料夾只有 .slug 快取），檔名只能實測得知。
-- 驗證在載入時再做一次：遊戲改版若移除某個檔，選單會自動少掉那一項。
local _, ns = ...

ns.FONT_DEFAULT = "default" -- 不換字型，沿用遊戲原本的設定

ns.FONT_CANDIDATES = {
  -- 2026-11-07 遊戲內實測（pcall SetFont，以不存在的 NOPE 為對照組＝false）以下皆存在。
  -- 名稱依檔名推測，實際樣子以預覽為準。
  { key = "kai", label = "楷體（bKAI00M，任務預設）", path = "Fonts\\bKAI00M.TTF" },
  { key = "hei", label = "黑體（bHEI00M）", path = "Fonts\\bHEI00M.TTF" },
  { key = "heib", label = "黑體粗（bHEI01B）", path = "Fonts\\bHEI01B.TTF" },
  { key = "lei", label = "bLEI00D", path = "Fonts\\bLEI00D.TTF" },
  { key = "arkai", label = "AR 楷體（ARKai_T）", path = "Fonts\\ARKai_T.TTF" },
  -- 存在但不列入：ARKai_C、ARHei 推測為簡中字型（可能缺繁體字）；FRIZQT__、ARIALN 是英文字型（中文會變方塊）。
  -- 自訂字型：把 .ttf 放到 BigFontTuner/Fonts/ 底下，在這裡加一行。字型必須有中文字，否則會顯示成方塊。
  -- { key = "noto", label = "思源黑體", path = "Interface\\AddOns\\BigFontTuner\\Fonts\\NotoSansTC.ttf" },
}

-- 回傳通過驗證的字型清單（第一筆一定是「遊戲預設」）。結果會快取，整個登入期間只驗一次。
local available
function ns.GetAvailableFonts()
  if available then return available end
  available = { { key = ns.FONT_DEFAULT, label = "遊戲預設", path = nil } }
  for _, f in ipairs(ns.FONT_CANDIDATES) do
    if ns.FontExists(f.path) then
      table.insert(available, f)
    end
  end
  return available
end

function ns.FindFont(key)
  for _, f in ipairs(ns.GetAvailableFonts()) do
    if f.key == key then return f end
  end
  return nil
end

-- 驗證字型檔是否存在。2026-11-07 實測：SetFont 遇到不存在的檔案會丟錯誤
-- 「Invalid font asset (...): file not found」（不會回傳 false），所以用 pcall 接住，報錯＝不存在。
local probe
function ns.FontExists(path)
  probe = probe or CreateFont("BigFontTunerProbe")
  return (pcall(probe.SetFont, probe, path, 12, ""))
end
