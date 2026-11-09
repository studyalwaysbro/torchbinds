-- Torch Binds looks: how the bars are drawn on screen.
--
--   devices   the two mouse bars are 3-wide, 4-tall blocks laid out exactly like the thumb buttons
--             on the mouse, side by side and centred just above your bars: plain left, Shift right.
--             The two Alt bars (Action Bars 6 and 7) stack as rows on top of the left block,
--             so they never sit in the middle of the screen on the character
--   corner    the same blocks and rows in the bottom right corner of the screen
--   off       back to the layout you had before
--
-- It works through the game's own Edit Mode. Each look is a normal Edit Mode layout named
-- "Torch Devices" or "Torch Corner", made as a copy of the layout you were using, so everything
-- else on your screen stays where you put it and you can still drag these bars yourself.

local ADDON, ns = ...
local plain, try, say, note = ns.plain, ns.try, ns.say, ns.note

local Look = {}
ns.Look = Look

local RIGHT1, RIGHT2 = 4, 5 -- Edit Mode's numbers for Right Bar (mouse) and Right Bar 2 (Shift + mouse)
local ALT1, ALT2 = 6, 7 -- Action Bar 6 (Alt + pad) and Action Bar 7 (Alt + thumb), added in v8

local LOOK_VERSION = 3 -- raise when the positions below change, so an applied look is refreshed

local function styles()
  local S = Enum.EditModeActionBarSetting
  local block = { [S.Orientation] = 0, [S.NumRows] = 4, [S.NumIcons] = 12 }
  local row = { [S.Orientation] = 0, [S.NumRows] = 1, [S.NumIcons] = 12 }
  return {
    -- side by side, centred on the end of your Shift bar, sitting just above your bars;
    -- the two Alt rows stack on top of the left block, out of the middle of the screen
    devices = {
      label = "Torch Devices",
      about = "the mouse blocks centred just above your bars, Alt rows stacked on top",
      bars = {
        [RIGHT1] = { settings = block, anchor = { point = "BOTTOMRIGHT", relativeTo = "MultiBarBottomLeft", relativePoint = "TOPRIGHT", offsetX = -8, offsetY = 10 } },
        [RIGHT2] = { settings = block, anchor = { point = "BOTTOMLEFT", relativeTo = "MultiBarBottomLeft", relativePoint = "TOPRIGHT", offsetX = 8, offsetY = 10 } },
        [ALT1] = { settings = row, anchor = { point = "BOTTOMLEFT", relativeTo = "MultiBarRight", relativePoint = "TOPLEFT", offsetX = 0, offsetY = 20 } },
        [ALT2] = { settings = row, anchor = { point = "BOTTOMLEFT", relativeTo = "MultiBar5", relativePoint = "TOPLEFT", offsetX = 0, offsetY = 18 } },
      },
    },
    corner = {
      label = "Torch Corner",
      about = "the mouse blocks in the bottom right corner, Alt rows stacked on top",
      bars = {
        [RIGHT1] = { settings = block, anchor = { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = -172, offsetY = 10 } },
        [RIGHT2] = { settings = block, anchor = { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = -8, offsetY = 10 } },
        [ALT1] = { settings = row, anchor = { point = "BOTTOMRIGHT", relativeTo = "MultiBarLeft", relativePoint = "TOPRIGHT", offsetX = 0, offsetY = 20 } },
        [ALT2] = { settings = row, anchor = { point = "BOTTOMRIGHT", relativeTo = "MultiBar5", relativePoint = "TOPRIGHT", offsetX = 0, offsetY = 18 } },
      },
    },
  }
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function available()
  return C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and C_EditMode.SetActiveLayout
    and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts
    and Enum and Enum.EditModeActionBarSetting and Enum.EditModeSystem and Enum.EditModeLayoutType
end

-- every layout the way the game numbers them: its own presets first, then yours
local function allLayouts()
  local info = C_EditMode.GetLayouts()
  local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
  local count = #presets
  for _, layout in ipairs(info.layouts) do presets[#presets + 1] = layout end
  info.layouts = presets
  return info, count
end

local function findLayout(info, name)
  for i, layout in ipairs(info.layouts) do
    if layout.layoutName == name and layout.layoutType ~= Enum.EditModeLayoutType.Preset then return i, layout end
  end
end

local function barSystem(layout, index)
  for _, system in ipairs(layout.systems or {}) do
    if system.system == Enum.EditModeSystem.ActionBar and system.systemIndex == index then return system end
  end
end

local function setSetting(system, setting, value)
  for _, entry in ipairs(system.settings) do
    if entry.setting == setting then entry.value = value return end
  end
  system.settings[#system.settings + 1] = { setting = setting, value = value }
end

-- small captions over the two blocks, so you can tell them apart at a glance
local captions = {}
local function caption(barName, text, show)
  local bar = _G[barName]
  if type(bar) ~= "table" or not UIParent or not UIParent.CreateFontString then return end
  local label = captions[barName]
  if not label then
    if not show then return end
    label = UIParent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("BOTTOM", bar, "TOP", 0, 3)
    captions[barName] = label
  end
  label:SetText(text)
  if show then label:Show() else label:Hide() end
end

function Look.Captions()
  local on = TorchBindsDB and TorchBindsDB.look == "devices"
  pcall(caption, "MultiBarRight", "MOUSE THUMB", on)
  pcall(caption, "MultiBarLeft", "SHIFT + THUMB", on)
  pcall(caption, "MultiBar5", "ALT + PAD", on)
  pcall(caption, "MultiBar6", "ALT + THUMB", on)
end

-- Switches to a look. Returns "ok", or the reason it could not.
-- 11-04 HARD RULE: this addon no longer WRITES to Edit Mode at all.
-- C_EditMode.SaveLayouts wiped the account's Edit Mode layouts on the launch
-- build (edit-mode-cache-account.txt was written back EMPTY). The look is now
-- enforced by Look.Pin alone; the old save-path code is kept below, unreachable,
-- until it is proven safe against this client offline.
function Look.Apply(style)
  if InCombatLockdown() then return "you are in combat" end
  local spec = styles()[style]
  if not spec then return "no such look" end
  TorchBindsDB.look, TorchBindsDB.lookVersion = style, LOOK_VERSION
  Look.Captions()
  pcall(Look.Pin)
  C_Timer.After(2, function() pcall(Look.Pin) end)
  return "ok"
end

local function UNREACHABLE_editModeApply(style)
  if InCombatLockdown() then return "you are in combat" end
  if not available() then return "this client has no Edit Mode for addons" end
  if EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown() then return "close Edit Mode first" end
  local spec = styles()[style]
  if not spec then return "no such look" end
  local ok, result = pcall(function()
    local info, presetCount = allLayouts()
    local active = info.layouts[info.activeLayout]
    if not active then return "could not read your current layout" end
    if TorchBindsDB.lookBefore == nil and not tostring(active.layoutName):find("^Torch ") then TorchBindsDB.lookBefore = active.layoutName end
    local index, layout = findLayout(info, spec.label)
    local created = false
    if not layout then
      local accountLayouts, lastAccount = 0, presetCount
      for i, l in ipairs(info.layouts) do
        if l.layoutType == Enum.EditModeLayoutType.Account then accountLayouts, lastAccount = accountLayouts + 1, i end
      end
      local most = Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5
      if accountLayouts >= most then return "you already have " .. most .. " Edit Mode layouts. Delete one in Edit Mode, then try again" end
      if C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(spec.label) then return "the game would not accept the layout name" end
      layout = { layoutName = spec.label, layoutType = Enum.EditModeLayoutType.Account, systems = copy(active.systems) }
      index = lastAccount + 1
      table.insert(info.layouts, index, layout)
      created = true
    end
    local presetBase = info.layouts[1] -- where a bar goes when it is "in its default position"
    for barIndex, bar in pairs(spec.bars) do
      local system = barSystem(layout, barIndex)
      if not system then
        -- the layout was saved before this bar existed (the Alt bars arrived in v8):
        -- adopt the entry from the game's own preset so an old layout can still learn it
        local donor = (presetBase and barSystem(presetBase, barIndex)) or (active and barSystem(active, barIndex))
        if donor then
          system = copy(donor)
          layout.systems[#layout.systems + 1] = system
        end
      end
      if not system then return "this layout has no entry for action bar " .. barIndex end
      for setting, value in pairs(bar.settings) do setSetting(system, setting, value) end
      if bar.default then
        local base = presetBase and barSystem(presetBase, barIndex)
        if base then system.anchorInfo = copy(base.anchorInfo) end
        system.isInDefaultPosition = true
      else
        system.anchorInfo = copy(bar.anchor)
        system.isInDefaultPosition = false
      end
    end
    C_EditMode.SaveLayouts(info)
    if created and C_EditMode.OnLayoutAdded then
      C_EditMode.OnLayoutAdded(index, true, false)
    else
      C_EditMode.SetActiveLayout(index)
    end
    return "ok"
  end)
  if not ok then note("look failed", result) return "the game refused it" end
  if result == "ok" then
    TorchBindsDB.look, TorchBindsDB.lookVersion = style, LOOK_VERSION
    Look.Captions()
    pcall(Look.Pin)
    C_Timer.After(2, function() pcall(Look.Pin) end) -- Edit Mode applies late; the pin has the last word
  end
  return result
end

-- Edit Mode in this client has twice refused to move the Alt bars (11-04). So the rows
-- are ALSO pinned the plain way: ClearAllPoints + SetPoint straight on the frames, after
-- every event that lets the game put them back. When Edit Mode did its job this is a
-- no-op; when it did not, the pin wins anyway.
local PIN_FRAMES = { [ALT1] = "MultiBar5", [ALT2] = "MultiBar6" }

function Look.Pin()
  if InCombatLockdown() then return end
  local style = TorchBindsDB and TorchBindsDB.look
  local spec = style and style ~= "off" and style ~= "none" and styles()[style]
  if not spec then return end
  for barIndex, frameName in pairs(PIN_FRAMES) do
    local bar = spec.bars[barIndex]
    local frame = _G[frameName]
    local to = bar and _G[bar.anchor.relativeTo]
    if bar and frame and to then
      frame:ClearAllPoints()
      frame:SetPoint(bar.anchor.point, to, bar.anchor.relativePoint, bar.anchor.offsetX, bar.anchor.offsetY)
    end
  end
  -- Action Bar 8 is not ours, but while it is switched on it must not sit mid-screen:
  -- it rides on top of the Alt stack until he turns it off under Options, Action Bars
  local b8, b7 = _G.MultiBar7, _G.MultiBar6
  if b8 and b7 and b8:IsShown() then
    b8:ClearAllPoints()
    b8:SetPoint("BOTTOMLEFT", b7, "TOPLEFT", 0, 18)
  end
end

local pinner = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "EDIT_MODE_LAYOUTS_UPDATED" }) do
  pcall(pinner.RegisterEvent, pinner, event)
end
pinner:SetScript("OnEvent", function()
  C_Timer.After(2, function() pcall(Look.Pin) end)
  C_Timer.After(8, function() pcall(Look.Pin) end) -- once more, after Edit Mode has had its say
end)

-- A look applied by an older version of this file is redrawn with the current positions.
-- A failure here must be SAID, never swallowed: a silent miss leaves bars in the wrong
-- place with no clue why (that is exactly how the Alt bars sat mid-screen on 11-04).
function Look.Refresh()
  local style = TorchBindsDB.look
  if style == "rows" then style = "corner" end -- the strip look is gone: bars now read like the mouse only as blocks
  if style and style ~= "off" and style ~= "none" and TorchBindsDB.lookVersion ~= LOOK_VERSION and available() and styles()[style] then
    local result = Look.Apply(style)
    if result ~= "ok" then
      say("The bars kept their old places: " .. tostring(result) .. ". Try /torch look " .. style .. " when you are out of combat.")
    end
    return result
  end
end

-- Stops the pinning. The bars go back to wherever Edit Mode has them on the next /reload.
-- (This no longer switches Edit Mode layouts: see the 11-04 hard rule above.)
function Look.Off()
  TorchBindsDB.look = "off"
  Look.Captions()
  return "ok"
end

function Look.Command(rest)
  if rest == "off" then
    local result = Look.Off()
    say(result == "ok" and "Pinning stopped. /reload and the bars sit wherever Edit Mode has them." or ("Look not changed: " .. result .. "."))
  elseif styles()[rest] then
    local result = Look.Apply(rest)
    say(result == "ok" and ("Look: " .. rest .. ", " .. styles()[rest].about .. ". Drag them anywhere in Edit Mode (Esc, Edit Mode).") or ("Look not changed: " .. result .. "."))
  else
    say("looks (you are on |cffffffff" .. tostring(TorchBindsDB.look or "none") .. "|r):")
    print("  |cffffd35a/torch look devices|r  mouse blocks above your bars, Alt rows stacked on top")
    print("  |cffffd35a/torch look corner|r   the same in the bottom right corner")
    print("  |cffffd35a/torch look off|r      the screen layout you had before")
  end
end
