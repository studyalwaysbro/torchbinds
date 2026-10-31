-- Torch Binds looks: how the bars are drawn on screen.
--
--   devices   the two mouse bars are 3-wide, 4-tall blocks laid out exactly like the thumb buttons
--             on the mouse, side by side and centred just above your bars: plain left, Shift right
--   corner    the same two blocks in the bottom right corner of the screen
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

local LOOK_VERSION = 2 -- raise when the positions below change, so an applied look is refreshed

local function styles()
  local S = Enum.EditModeActionBarSetting
  local block = { [S.Orientation] = 0, [S.NumRows] = 4, [S.NumIcons] = 12 }
  return {
    -- side by side, centred on the end of your Shift bar, sitting just above your bars
    devices = {
      label = "Torch Devices",
      about = "the mouse blocks centred just above your bars",
      bars = {
        [RIGHT1] = { settings = block, anchor = { point = "BOTTOMRIGHT", relativeTo = "MultiBarBottomLeft", relativePoint = "TOPRIGHT", offsetX = -8, offsetY = 10 } },
        [RIGHT2] = { settings = block, anchor = { point = "BOTTOMLEFT", relativeTo = "MultiBarBottomLeft", relativePoint = "TOPRIGHT", offsetX = 8, offsetY = 10 } },
      },
    },
    corner = {
      label = "Torch Corner",
      about = "the mouse blocks in the bottom right corner",
      bars = {
        [RIGHT1] = { settings = block, anchor = { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = -172, offsetY = 10 } },
        [RIGHT2] = { settings = block, anchor = { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = -8, offsetY = 10 } },
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
end

-- Switches to a look. Returns "ok", or the reason it could not.
function Look.Apply(style)
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
  end
  return result
end

-- A look applied by an older version of this file is redrawn with the current positions.
function Look.Refresh()
  local style = TorchBindsDB.look
  if style == "rows" then style = "corner" end -- the strip look is gone: bars now read like the mouse only as blocks
  if style and style ~= "off" and style ~= "none" and TorchBindsDB.lookVersion ~= LOOK_VERSION and available() and styles()[style] then
    return Look.Apply(style)
  end
end

-- Back to the layout you were using before any look was applied.
function Look.Off()
  if InCombatLockdown() then return "you are in combat" end
  if not available() then return "this client has no Edit Mode for addons" end
  local ok, result = pcall(function()
    local info = allLayouts()
    local wanted = TorchBindsDB.lookBefore
    for i, layout in ipairs(info.layouts) do
      if layout.layoutName == wanted then
        C_EditMode.SetActiveLayout(i)
        return "ok"
      end
    end
    C_EditMode.SetActiveLayout(1) -- the layout you had is gone: fall back to the game's own
    return "ok"
  end)
  if not ok then note("look failed", result) return "the game refused it" end
  TorchBindsDB.look = "off"
  Look.Captions()
  return result
end

function Look.Command(rest)
  if rest == "off" then
    local result = Look.Off()
    say(result == "ok" and "Back to the screen layout you had before. The Torch layouts are still in Edit Mode if you want them." or ("Look not changed: " .. result .. "."))
  elseif styles()[rest] then
    local result = Look.Apply(rest)
    say(result == "ok" and ("Look: " .. rest .. ", " .. styles()[rest].about .. ". Drag them anywhere in Edit Mode (Esc, Edit Mode).") or ("Look not changed: " .. result .. "."))
  else
    say("looks (you are on |cffffffff" .. tostring(TorchBindsDB.look or "none") .. "|r):")
    print("  |cffffd35a/torch look devices|r  the two mouse blocks side by side, centred just above your bars")
    print("  |cffffd35a/torch look corner|r   the two mouse blocks in the bottom right corner")
    print("  |cffffd35a/torch look off|r      the screen layout you had before")
  end
end
