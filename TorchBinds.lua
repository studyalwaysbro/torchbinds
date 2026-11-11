-- Torch Binds: a mage's whole control setup. It puts every spell, consumable and macro on the
-- bars, binds them for the hardware you chose, keeps them current as you level and loot, and
-- counts what you press so the layout can be judged on evidence.
--
-- /torch              help
-- /torch map          what every key and mouse button does
-- /torch stats        what you pressed, clicked and fumbled (stats reset to start over)
-- /torch rested       your rested experience, and where to log out to build more
-- /torch spec         which talent tree the spells are following
-- /torch preset       list the key presets, or /torch preset <name> to switch
-- /torch setup        force the layout again        /torch undo   put bars and binds back
-- /torch binds | dump | bags | off | on
--
-- How it works. LAYOUT says which spell lives in which bar slot; a preset says which keys press
-- which slots. The first time a new layout version loads it is applied once, out of combat, and
-- what was there before is saved for /torch undo. After that the addon only fills empty layout
-- slots, swaps in new ranks, and keeps the best potion, food, water and bandage in their slots.
-- It never moves a key you already know.
--
-- Nothing here presses a key for you. Every cast is still one press by you.

local ADDON, ns = ...

local LAYOUT_VERSION = 14
-- Seven bars, one per thing your hands do. Each is one row of twelve action slots.
-- Two hands, two modifiers: Shift under the thumb, Alt on the pad key above it. That is
-- three layers for the left hand and three for the mouse, and nothing on the pinky.
--   MAIN    main bar, slots 1-12         left hand: Q E R F Z X C, a spare, then the thumb pad
--   SHIFT   Bottom Left, slots 61-72     the same keys with Shift
--   ALT     Action Bar 6, slots 145-156  the same keys with Alt
--   MOUSE   Right Bar, slots 25-36       mouse thumb buttons 1 to 12, in the order they are printed
--   MSHIFT  Right Bar 2, slots 37-48     Shift + mouse thumb buttons 1 to 12
--   MALT    Action Bar 7, slots 157-168  Alt + mouse thumb buttons 1 to 12
--   CLICK   Bottom Right, slots 49-60    things you click out of combat
local MAIN, SHIFT, MOUSE, MSHIFT, CLICK = 1, 61, 25, 37, 49
local ALT, MALT = 145, 157
local BAR_COMMAND = { [MAIN] = "ACTIONBUTTON", [SHIFT] = "MULTIACTIONBAR1BUTTON", [MOUSE] = "MULTIACTIONBAR3BUTTON",
                      [MSHIFT] = "MULTIACTIONBAR4BUTTON", [CLICK] = "MULTIACTIONBAR2BUTTON",
                      [ALT] = "MULTIACTIONBAR5BUTTON", [MALT] = "MULTIACTIONBAR6BUTTON" }
local PAD = { "Q", "E", "R", "F", "Z", "X", "C" }                              -- main bar slots 1 to 7
local DPAD = { "UP", "DOWN", "LEFT", "RIGHT" }                                  -- main bar slots 9 to 12
local GRID = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }     -- what thumb buttons 1 to 12 send
-- A bar drawn as four rows of three fills from the bottom row up. The mouse has 1 2 3 on its top
-- row, so thumb button n lives in the bar position that lands where that button is on the mouse.
-- The Alt layers never touch an action bar slot: this client refuses placements into Action
-- Bars 6 and 7 (every 145+ slot stayed empty since launch while 1-72 fill fine) and PlaceAction
-- cannot say no. Each Alt key presses a hidden secure button that casts its entry directly.
local ALT_BUTTON, ALT_NAME = {}, {}
do
  local pressDown = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("ActionButtonUseKeyDown")
  for _, first in ipairs({ ALT, MALT }) do
    for p = 1, 12 do
      local slot = first + p - 1
      local name = (first == ALT and "TorchBindsAlt" or "TorchBindsMAlt") .. p
      local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
      b:SetSize(1, 1)
      b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
      b:SetAlpha(0)
      b:EnableMouse(false) -- a key binding still clicks it; the mouse never can
      b:RegisterForClicks(pressDown and "AnyDown" or "AnyUp")
      b:Show()
      ALT_BUTTON[slot], ALT_NAME[slot] = b, name
    end
  end
end

local GRID_POS = {}   -- thumb button -> position on the bar (1 to 12)
local GRID_THUMB = {} -- position on the bar -> thumb button
for n = 1, 12 do
  local pos = (3 - math.floor((n - 1) / 3)) * 3 + ((n - 1) % 3) + 1
  GRID_POS[n], GRID_THUMB[pos] = pos, n
end
-- a row written in thumb order, 1 to 12, turned into bar order
local function grid(byThumb)
  local row = {}
  for n = 1, 12 do row[n] = false end
  for n = 1, 12 do row[GRID_POS[n]] = byThumb[n] or false end
  return row
end

local function say(msg) print("|cffffd35aTorch Binds:|r " .. tostring(msg)) end

local function note(kind, msg)
  TorchBindsDB.log = TorchBindsDB.log or {}
  if #TorchBindsDB.log < 200 then table.insert(TorchBindsDB.log, kind .. ": " .. tostring(msg)) end
end

local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e = pcall(f, ...)
  if ok then return a, b, c, d, e end
  return nil
end

-- Is something in this slot? A "no" here takes a key away, so it has to be a real no: the game
-- answered, the answer was readable, and it was no. An error or a hidden value counts as yes.
local function slotRead(slot)
  local asked = false
  for _, f in ipairs({ C_ActionBar and C_ActionBar.HasAction or false, HasAction or false, GetActionInfo or false }) do
    if f then
      local ok, v = pcall(f, slot)
      if not ok or (issecretvalue and issecretvalue(v)) then return true end
      asked = true
      if v then return true end
    end
  end
  return not asked -- cannot tell: bind it
end

-- The game can answer "empty" for every slot at once (bars not loaded yet, a loading screen).
-- Nobody running this layout has 72 empty slots, so that answer means "not readable right now".
local function barsReadable()
  for slot = 1, 72 do if slotRead(slot) then return true end end
  return false
end

local function slotFilled(slot)
  local b = ALT_BUTTON[slot]
  if b then return b:GetAttribute("tb_kind") ~= nil end
  return slotRead(slot) or not barsReadable()
end

-- A cold login can hand us a bar system that is not serving yet: every slot reads empty and
-- PlaceAction is silently ignored. Arranging against that shuffles the bars blind and drops
-- whatever each swap hands back. A character that was arranged before cannot truly have empty
-- bars, so unreadable bars there mean wait, not act; only a never-arranged character may really
-- be empty, and on empty bars a blind pass has nothing to lose.
local function barsServing()
  return barsReadable() or not (TorchBindsDB and TorchBindsDB.lastSetup)
end
local placeRefused = 0 -- placements the client ignored during the current arrange pass

ns.say, ns.note, ns.plain, ns.try = say, note, plain, try
ns.BARS = { MAIN = MAIN, SHIFT = SHIFT, MOUSE = MOUSE, MSHIFT = MSHIFT, CLICK = CLICK, ALT = ALT, MALT = MALT }
ns.GRID_THUMB = GRID_THUMB

-- BINDINGS ------------------------------------------------------------------
local function bindingSet()
  local set = try(GetCurrentBindingSet)
  if set == 1 or set == 2 then return set end -- account / character
  return nil, set
end

-- PRESETS: which keys press which slots. key -> command, false = unbind (so the plain key works).
-- Every preset shares the slots, so the bars look the same whichever one you use.
-- On the two mouse bars `i` is the thumb button number; everywhere else it is the position on the bar.
local function pos(first, i) return (first == MOUSE or first == MSHIFT or first == MALT) and GRID_POS[i] or i end
local function to(first, i)                                                                             -- always bound
  local p = pos(first, i)
  local n = ALT_NAME[first + p - 1]
  if n then return "CLICK " .. n .. ":LeftButton" end
  return BAR_COMMAND[first] .. p
end
local function ifFilled(first, i) return slotFilled(first + pos(first, i) - 1) and to(first, i) or false end -- bound only when something is there

-- Set focus without letting go of your target: whoever the mouse is over becomes the focus. With
-- the mouse over nobody it focuses your target, as the plain key did.
local FOCUS_MACRO = "Focus Hover"
-- Off unless asked for with /torch hoverfocus on.
local function focusBind()
  if not (TorchBindsDB and TorchBindsDB.hoverFocus) then return "FOCUSTARGET" end
  return (try(GetMacroIndexByName, FOCUS_MACRO) or 0) > 0 and ("MACRO " .. FOCUS_MACRO) or "FOCUSTARGET"
end

local function sharedBinds(want)
  for i, k in ipairs(PAD) do
    want[k] = to(MAIN, i)
    want["SHIFT-" .. k] = ifFilled(SHIFT, i)
    want["ALT-" .. k] = ifFilled(ALT, i)
    want["CTRL-" .. k] = false
  end
  want["SHIFT-F"] = false               -- F is Blink. Shift held from the last cast must not block it
  want["ALT-F"] = false                 -- same for Alt: Blink is never allowed to be eaten by a modifier
  for i, k in ipairs(DPAD) do
    want[k] = to(MAIN, 8 + i)
    want["SHIFT-" .. k] = false         -- Shift+Up/Down flip the action bar page by default
    want["ALT-" .. k] = ifFilled(ALT, 8 + i)
    want["CTRL-" .. k] = false
  end
  -- Mouse thumb grid, and the pad's top row, which sends the same 1 to 5.
  for i, k in ipairs(GRID) do
    want[k] = to(MOUSE, i)
    want["SHIFT-" .. k] = ifFilled(MSHIFT, i)
    want["ALT-" .. k] = ifFilled(MALT, i)
    want["CTRL-" .. k] = false
  end
  -- Mouse buttons 4 and 5: the two fastest buttons there are, pressed by the finger that is
  -- already on the mouse, so they get the two spells that cannot wait and must never be a reach.
  -- Same slots as thumb 1 and thumb 4, so the cooldown shows in the mouse block.
  want["BUTTON4"], want["SHIFT-BUTTON4"], want["ALT-BUTTON4"] = to(MOUSE, 1), ifFilled(MSHIFT, 1), ifFilled(MALT, 1)   -- Polymorph
  want["BUTTON5"], want["SHIFT-BUTTON5"], want["ALT-BUTTON5"] = to(MOUSE, 4), ifFilled(MSHIFT, 4), ifFilled(MALT, 4)   -- Counterspell
  want["TAB"] = "TARGETNEARESTENEMY"
  want["SHIFT-TAB"] = focusBind()       -- set focus
  want["ALT-TAB"] = false               -- the window switcher. Never ours
  want["CTRL-TAB"] = "TARGETFOCUS"      -- target my focus
  want["A"] = "STRAFELEFT"
  want["D"] = "STRAFERIGHT"
  -- Shift is under the thumb all fight. Scrolling the camera with it held must not flip Bar 1 away.
  want["SHIFT-MOUSEWHEELUP"] = false
  want["SHIFT-MOUSEWHEELDOWN"] = false
  want["ALT-MOUSEWHEELUP"] = false
  want["ALT-MOUSEWHEELDOWN"] = false
  want["CAPSLOCK"] = false
  want["BACKSPACE"] = false
  -- Run without holding a key. Mapped off the letter row so no spell key can ever trip it.
  want["NUMLOCK"] = "TOGGLEAUTORUN"
  want["HOME"] = "TOGGLEAUTORUN"
end

local PRESETS
PRESETS = {
  tartarus = {
    label = "Tartarus + Scimitar, no pinky",
    about = "One modifier, Shift, on the pad's thumb key. Nothing important on the pinky column. The second layer is the mouse thumb grid.",
    apply = function(want)
      sharedBinds(want)
      want["BUTTON3"] = "TARGETNEARESTENEMY" -- wheel click: next enemy without the pinky on Tab
      want["SHIFT-BUTTON3"] = focusBind()
    end,
  },
  keyboard = {
    label = "Keyboard + Scimitar",
    about = "The same bars. Ctrl is back as a second modifier for anyone whose pinky is happy: Ctrl + Q E R F Z X C press what mouse 6 to 12 press, Ctrl + 1 to 5 press what Shift + mouse 6 to 10 press.",
    apply = function(want)
      sharedBinds(want)
      for i, k in ipairs(PAD) do want["CTRL-" .. k] = ifFilled(MOUSE, 5 + i) end
      for i = 1, 5 do want["CTRL-" .. i] = ifFilled(MSHIFT, 5 + i) end
    end,
  },
  thumbmove = {
    label = "Tartarus, thumb pad moves you (experimental)",
    about = "What most Tartarus players in WoW run: the thumb pad walks and strafes, so W A S D become spell keys and the top-row spells drop to the home row (W Counterspell, A Polymorph, S Cone of Cold, D Arcane Explosion). The catch: your thumb cannot hold Shift while it steers, so Shift spells are for standing still, and potions are on the screen to click. Set the pad to 4-way first.",
    apply = function(want)
      sharedBinds(want)
      want["UP"], want["DOWN"], want["LEFT"], want["RIGHT"] = "MOVEFORWARD", "MOVEBACKWARD", "STRAFELEFT", "STRAFERIGHT"
      want["W"], want["A"], want["S"], want["D"] = to(MOUSE, 4), to(MOUSE, 1), to(MOUSE, 2), to(MOUSE, 3)
      want["BUTTON3"] = "TARGETNEARESTENEMY"
      want["SHIFT-BUTTON3"] = focusBind()
    end,
  },
  xaryu = {
    label = "Xaryu, Classic 2019 (keyboard, partial)",
    about = "The twelve binds he showed on video for the vanilla mage kit: Frostbolt 3, Frost Nova Tab, Cone of Cold 1, rank 1 Frostbolt 5, Fire Blast mouse 5, Ice Block mouse 4, Cold Snap Shift + mouse 4, Polymorph wheel down, Counterspell V, mana gem Shift+3, Fire Ward Alt+1. He never showed the rest, so every other key is this addon's keyboard preset. His Shift binds were mouseover casts; here Shift + wheel down is the focus Polymorph.",
    apply = function(want)
      PRESETS.keyboard.apply(want)
      want["3"], want["TAB"], want["1"], want["5"] = to(MAIN, 2), to(MAIN, 1), to(MOUSE, 2), ifFilled(SHIFT, 3)
      want["BUTTON5"], want["BUTTON4"], want["SHIFT-BUTTON4"] = to(MAIN, 5), to(MAIN, 6), ifFilled(SHIFT, 6)
      want["SHIFT-BUTTON5"] = false
      want["MOUSEWHEELDOWN"], want["SHIFT-MOUSEWHEELDOWN"] = to(MOUSE, 1), ifFilled(MSHIFT, 1)
      want["V"], want["SHIFT-V"] = to(MOUSE, 4), ifFilled(MSHIFT, 4)
      want["SHIFT-3"], want["ALT-1"] = ifFilled(SHIFT, 7), ifFilled(MSHIFT, 7)
      want["2"], want["4"] = to(MOUSE, 3), to(MOUSE, 5)      -- the spells his keys pushed out: Arcane Explosion and the shield
      want["BUTTON3"] = "TARGETNEARESTENEMY"                 -- Tab is Frost Nova in his setup
    end,
  },
}
ns.PRESETS = PRESETS

local function presetName()
  local name = TorchBindsDB and TorchBindsDB.preset
  return PRESETS[name] and name or "tartarus"
end
ns.presetName = presetName

-- keys only some presets use; the others give them back to the game's default
local RELEASE = { W = "MOVEFORWARD", S = "MOVEBACKWARD", MOUSEWHEELDOWN = "CAMERAZOOMOUT", V = "NAMEPLATES", ["SHIFT-V"] = "FRIENDNAMEPLATES",
                  ["ALT-1"] = false, ["SHIFT-MOUSEWHEELDOWN"] = false, BUTTON3 = false, ["SHIFT-BUTTON3"] = false }

local function wanted()
  local want = {}
  PRESETS[presetName()].apply(want)
  for k, command in pairs(RELEASE) do if want[k] == nil then want[k] = command end end
  return want
end

-- what every key any preset touches is bound to right now
local function bindsNow()
  local out = {}
  for _, preset in pairs(PRESETS) do
    local want = {}
    preset.apply(want)
    for k in pairs(want) do out[k] = try(GetBindingAction, k) or "" end
  end
  return out
end

-- returns "ok", "combat" or "notready"
local function applyBinds()
  if InCombatLockdown() then return "combat" end
  local set, raw = bindingSet()
  if not set then TorchBindsDB.bindSetSeen = tostring(raw) return "notready" end
  if not TorchBindsDB.bindsBefore then TorchBindsDB.bindsBefore = bindsNow() end -- for /torch undo
  local want, failed = wanted(), 0
  for key, command in pairs(want) do
    local ok, result = pcall(SetBinding, key, command or nil)
    if not ok or not result then
      failed = failed + 1
      note("bind failed", key .. " -> " .. tostring(command) .. " (" .. tostring(result) .. ")")
    end
  end
  local saved, err = pcall(SaveBindings, set)
  if not saved then note("save failed", "set=" .. tostring(set) .. " " .. tostring(err)) end
  local mismatch
  for key, command in pairs(want) do
    if (try(GetBindingAction, key) or "") ~= (command or "") then mismatch = key break end
  end
  TorchBindsDB.bindCheck = { set = set, saved = saved, failed = failed, firstMismatch = mismatch, version = LAYOUT_VERSION, at = date("%Y-%m-%d %H:%M:%S") }
  if saved and not mismatch then TorchBindsDB.appliedVersion = LAYOUT_VERSION end
  return "ok"
end

-- A key this layout wants that is bound to nothing gets its bind back. A key you bound to
-- something else yourself is left alone.
local function repairBinds()
  if TorchBindsDB.off or InCombatLockdown() or TorchBindsDB.appliedVersion ~= LAYOUT_VERSION then return 0 end
  local set = bindingSet()
  if not set then return 0 end
  local fixed = 0
  for key, command in pairs(wanted()) do
    if command and (try(GetBindingAction, key) or "") == "" then
      local ok, result = pcall(SetBinding, key, command)
      if ok and result then fixed = fixed + 1 end
    end
  end
  if fixed > 0 then
    pcall(SaveBindings, set)
    say(fixed .. " of your keys had lost their binds. They are back.")
  end
  return fixed
end

-- RECORD --------------------------------------------------------------------
local function dumpSpells()
  local out, seen, SB = {}, {}, C_SpellBook
  if not (SB and SB.GetSpellBookItemInfo) then note("spell dump", "C_SpellBook.GetSpellBookItemInfo missing") return out end
  local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
  local function add(slot, tab)
    if seen[slot] then return true end
    local item = try(SB.GetSpellBookItemInfo, slot, bank)
    if type(item) ~= "table" or not plain(item.name) then return false end
    seen[slot] = true
    local id = plain(item.spellID) or plain(item.actionID)
    local sub = plain(item.subName)
    if (not sub or sub == "") and id and C_Spell then sub = plain(try(C_Spell.GetSpellSubtext, id)) end
    out[#out + 1] = {
      slot = slot, tab = tab, name = item.name, sub = (sub and sub ~= "") and sub or nil, id = id,
      type = plain(item.itemType), passive = item.isPassive or nil, off = item.isOffSpec or nil,
      lowRank = try(SB.IsSpellBookItemLowRank, slot, bank) or nil, -- true = a higher rank is known
    }
    return true
  end
  local lines, nilLines = try(SB.GetNumSpellBookSkillLines) or 0, 0
  for line = 1, lines do
    local info = try(SB.GetSpellBookSkillLineInfo, line) -- may return nothing
    if type(info) == "table" and info.itemIndexOffset and info.numSpellBookItems then
      for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do add(slot, info.name) end
    else
      nilLines = nilLines + 1
    end
  end
  if #out == 0 then -- fallback: flat scan
    local misses = 0
    for slot = 1, 600 do
      if add(slot, "?") then misses = 0 else misses = misses + 1 if misses >= 40 then break end end
    end
  end
  TorchBindsDB.spellDiag = { lines = lines, nilLines = nilLines, found = #out }
  return out
end

local function dumpActions()
  local out, found, errs, has = {}, 0, 0, 0
  local AB = C_ActionBar
  local getText = (AB and AB.GetActionText) or GetActionText
  if type(GetActionInfo) ~= "function" then note("action dump", "GetActionInfo missing") return out, 0 end
  for slot = 1, 120 do
    local ok, kind, id, sub = pcall(GetActionInfo, slot)
    if not ok then
      errs = errs + 1
      if errs <= 3 then note("GetActionInfo failed", slot .. " " .. tostring(kind)) end
    else
      if slotFilled(slot) then has = has + 1 end
      kind, id, sub = plain(kind), plain(id), plain(sub)
      if kind then
        local e = { kind = kind, id = id, sub = sub, text = plain(try(getText, slot)) }
        if kind == "spell" and id then
          e.name = plain(try(C_Spell and C_Spell.GetSpellName, id))
          local rank = plain(try(C_Spell and C_Spell.GetSpellSubtext, id))
          if rank and rank ~= "" then e.rank = rank end
        elseif kind == "item" and id then
          e.name = plain(try(C_Item and C_Item.GetItemNameByID, id))
        elseif kind == "macro" then
          e.name = e.text
        end
        out["s" .. slot] = e
        found = found + 1
      end
    end
  end
  TorchBindsDB.actionDiag = { found = found, hasAction = has, errors = errs }
  return out, found
end

local function dumpBinds()
  local out = {}
  local commands = { "TARGETNEARESTENEMY", "FOCUSTARGET", "TARGETFOCUS", "STRAFELEFT", "STRAFERIGHT", "TURNLEFT", "TURNRIGHT", "MOVEFORWARD", "MOVEBACKWARD", "JUMP", "PREVIOUSACTIONPAGE", "NEXTACTIONPAGE" }
  for i = 1, 12 do
    for _, prefix in ipairs({ "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON", "MULTIACTIONBAR4BUTTON" }) do
      table.insert(commands, prefix .. i)
    end
  end
  for _, command in ipairs(commands) do
    local a, b = GetBindingKey(command)
    out[command] = (a or "") .. (b and (" , " .. b) or "")
  end
  return out
end

local function dump(reason)
  if InCombatLockdown() then return end
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  local build, buildNumber, _, toc = GetBuildInfo()
  local stamp = date("%Y-%m-%d %H:%M:%S")
  TorchBindsDB.character = { name = UnitName("player"), realm = GetRealmName(), class = class, race = race, level = UnitLevel("player"), faction = UnitFactionGroup("player") }
  TorchBindsDB.client = { build = build, buildNumber = buildNumber, toc = toc }
  local spells = dumpSpells()
  if #spells > 0 then TorchBindsDB.spells = spells TorchBindsDB.spellsAt = stamp end -- never replace good data with nothing
  local actions, found = dumpActions()
  if found > 0 then TorchBindsDB.actions = actions TorchBindsDB.actionsAt = stamp end
  TorchBindsDB.binds = dumpBinds()
  TorchBindsDB.dumpedAt, TorchBindsDB.dumpReason = stamp, reason
end

-- BAG FIX: client build 70291 (2026-10-08) stopped hiding the gamepad bag bar for keyboard players.
-- It sits on top of the combined bag, covers the organise button and opens bag menus instead.
-- This hides it again whenever the gamepad interface is not in use. /torch bagfix off turns it off.
local bagFixPending = false
local function fixBags()
  if TorchBindsDB and TorchBindsDB.bagFixOff then return end
  local bar = GamepadBagBar
  if not bar or not bar:IsShown() then return end
  if InputUtil and InputUtil.IsGamepadUIEnabled and try(InputUtil.IsGamepadUIEnabled) then return end
  if InCombatLockdown() then bagFixPending = true return end
  pcall(bar.Hide, bar)
end
local function hookBags()
  for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
    local frame = _G[name]
    if frame and not frame.torchBagHooked then
      frame.torchBagHooked = true
      pcall(frame.HookScript, frame, "OnShow", fixBags)
      if frame.UpdateSearchBox then pcall(hooksecurefunc, frame, "UpdateSearchBox", fixBags) end
    end
  end
  fixBags()
end

-- BAG CHECK: prints facts about the bag window instead of anyone guessing. /torch bags
local function bagCheck(fix)
  local out = {}
  local function add(k, v) out[#out + 1] = k .. ": " .. tostring(v) say(k .. ": |cffffffff" .. tostring(v) .. "|r") end
  local _, build = GetBuildInfo()
  add("client build", build)
  add("gamepad interface active", InputUtil and InputUtil.IsGamepadUIEnabled and try(InputUtil.IsGamepadUIEnabled))
  add("GamePadEnable setting", try(GetCVar, "GamePadEnable"))
  add("combined bag setting", try(GetCVar, "combinedBags"))
  local b = BagItemAutoSortButton
  if not b then
    add("organise button", "does not exist in this client")
  else
    local parent = b:GetParent()
    local point, rel, relPoint, x, y = b:GetPoint(1)
    add("organise button shown", b:IsShown())
    add("organise button visible on screen", b:IsVisible())
    add("organise button attached to", parent and parent.GetName and parent:GetName() or "nothing")
    add("organise button position", tostring(point) .. " of " .. tostring(rel and rel.GetName and rel:GetName()) .. " " .. tostring(x) .. "," .. tostring(y))
    add("organise button size and alpha", string.format("%dx%d alpha %.1f scale %.2f", b:GetWidth(), b:GetHeight(), b:GetAlpha(), b:GetEffectiveScale()))
    local tex = b:GetNormalTexture()
    add("organise button picture", tex and (tex:GetAtlas() or tex:GetTexture()) or "none")
  end
  add("backpack skipped by clean up", C_Container.GetBackpackAutosortDisabled and try(C_Container.GetBackpackAutosortDisabled))
  local flag = Enum and Enum.BagSlotFlags and (Enum.BagSlotFlags.DisableAutoSort or Enum.BagSlotFlags.ExcludeFromSort)
  for bag = 1, 4 do
    if flag and C_Container.GetBagSlotFlag then add("bag " .. bag .. " skipped by clean up", try(C_Container.GetBagSlotFlag, bag, flag)) end
  end
  add("clean up function exists", type(C_Container.SortBags))
  add("gamepad bag bar shown on the bag", GamepadBagBar and GamepadBagBar:IsShown())
  local frame = ContainerFrameCombinedBags
  if frame then
    add("combined bag window shown", frame:IsShown())
    local names = {}
    for _, child in ipairs({ frame:GetChildren() }) do
      local n = child.GetName and child:GetName()
      if n and child:IsShown() and not n:find("Item%d") then names[#names + 1] = n end
    end
    add("named buttons on the bag", table.concat(names, ", "))
  end
  local loaded = {}
  for i = 1, (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or 0) do
    local name = C_AddOns.GetAddOnInfo(i)
    if C_AddOns.IsAddOnLoaded(i) then loaded[#loaded + 1] = name end
  end
  add("addons loaded", table.concat(loaded, ", "))
  if fix then
    if C_Container.SetBackpackAutosortDisabled then pcall(C_Container.SetBackpackAutosortDisabled, false) end
    if flag and C_Container.SetBagSlotFlag then for bag = 1, 4 do pcall(C_Container.SetBagSlotFlag, bag, flag, false) end end
    local ok, err = pcall(C_Container.SortBags)
    add("clean up attempted", ok and "called, watch your bag" or ("error: " .. tostring(err)))
  end
  TorchBindsDB.bagCheck = { at = date("%Y-%m-%d %H:%M:%S"), lines = out }
end


-- LAYOUT --------------------------------------------------------------------
-- What lives in each bar slot. Entry kinds:
--   "Spell"              the spell, highest rank you know
--   first("A", "B")      the first of these you know (an upgrade replaces the older spell)
--   stop("Spell")        a macro: /stopcasting, then the spell. For instants that must come out NOW,
--                        even halfway through a Frostbolt. The price: it cancels the cast you were
--                        making even when the instant is on cooldown, and it skips the game's spell
--                        queue, so a press in the last moments of a cast costs you that cast.
--   { macro = , needs = } a named macro from MACROS, placed once `needs` is learned
--   item("kind")         the best item of that kind in your bags (see ITEMS)
--   MOUNT                your mount, when you have one
--   false                yours, never touched
local function first(...) return { spell = { ... } } end
local function any(...) return { any = { ... } } end
-- the slot on a mouse bar that thumb button n presses
local function mslot(bar, n) return bar + GRID_POS[n] - 1 end
local function stop(spell) return { stop = spell } end
local function item(kind) return { item = kind } end
local MOUNT = { mount = true }

local MACROS = {
  ["Poly Focus"] = "#showtooltip Polymorph\n/cast [@focus,exists,harm,nodead] Polymorph; Polymorph",
  ["Counterspell Foc"] = "#showtooltip Counterspell\n/stopcasting\n/cast [@focus,exists,harm,nodead] Counterspell; Counterspell",
  -- whoever the mouse is over (a party frame, a raid frame, a player in the world), else a
  -- friendly target, else yourself
  ["Decurse"] = "#showtooltip Remove Lesser Curse\n/cast [@mouseover,help,nodead][help,nodead][@player] Remove Lesser Curse",
  -- rank 1: a 1.5 second cast for the slow, not the damage. For kiting and for making a runner stop.
  ["Frostbolt R1"] = "#showtooltip Frostbolt(Rank 1)\n/cast Frostbolt(Rank 1)",
  [FOCUS_MACRO] = "/focus [@mouseover,exists,nodead][]",
  -- Frost Blast is the 1.5 second frost nuke Forever added at level 24. It is the kiting cast:
  -- fast enough to land between steps, and it carries the slow. /stopcasting makes it interrupt
  -- a Frostbolt you no longer want.
  ["Frost Blast!"] = "#showtooltip Frost Blast\n/stopcasting\n/cast Frost Blast",
  -- Ice Block is a toggle: press it to go in, press it again to come out. One key, both jobs.
  ["Ice Block!"] = "#showtooltip Ice Block\n/stopcasting\n/cancelaura Ice Block\n/cast Ice Block",
  -- Mana Shield off, so a shield you no longer want stops eating mana.
  ["Shield Off"] = "#showtooltip Mana Shield\n/cancelaura Mana Shield\n/cast Mana Shield",
  -- Both trinket slots on one key. Covers the PvP trinket and any engineering headpiece or
  -- on-use trinket without this file having to know which one you are wearing.
  ["Trinkets"] = "#showtooltip\n/stopcasting\n/use 13\n/use 14",
  -- Will of the Forsaken: the undead escape. Off the global cooldown is not something to rely on,
  -- so /stopcasting gets it out mid-cast.
  ["Free Me"] = "#showtooltip Will of the Forsaken\n/stopcasting\n/cast Will of the Forsaken",
  -- Cannibalize: 7% health and 7% mana every 2 seconds for 10 seconds off a corpse. In Forever it
  -- gives mana too, which makes it a mage button and not a flavour one. It cancels on any action,
  -- so it is deliberately off the keys you press in a fight.
  ["Feed"] = "#showtooltip Cannibalize\n/cast Cannibalize",
  -- Counterspell on whoever the mouse is over, else the target. Not focus-first: a focus that is
  -- not casting would eat the interrupt.
  ["CS Mouseover"] = "#showtooltip Counterspell\n/stopcasting\n/cast [@mouseover,harm,nodead] Counterspell; Counterspell",
  -- Polymorph on whoever the mouse is over. The second sheep in a fight, without losing your target.
  ["Poly Over"] = "#showtooltip Polymorph\n/cast [@mouseover,harm,nodead] Polymorph; Polymorph",
}
local POLY_FOC = { macro = "Poly Focus", needs = "Polymorph" }
local CS_FOC = { macro = "Counterspell Foc", needs = "Counterspell" }
local GEM = { gem = true }
-- best first: the conjure spell and the gem it makes
local GEMS = { { "Conjure Mana Ruby", 8008 }, { "Conjure Mana Citrine", 8007 }, { "Conjure Mana Jade", 5513 }, { "Conjure Mana Agate", 5514 } }
local CONJURE_GEM = first("Conjure Mana Ruby", "Conjure Mana Citrine", "Conjure Mana Jade", "Conjure Mana Agate")
local DECURSE = { macro = "Decurse", needs = "Remove Lesser Curse" }
local FROST_R1 = { macro = "Frostbolt R1", needs = "Frostbolt" }
local FROST_BLAST = { macro = "Frost Blast!", needs = "Frost Blast" }
local ICE_BLOCK = { macro = "Ice Block!", needs = "Ice Block" }
local SHIELD_OFF = { macro = "Shield Off", needs = "Mana Shield" }
local TRINKETS = { macro = "Trinkets", always = true }
local WOTF = { macro = "Free Me", needs = "Will of the Forsaken" }
local FEED = { macro = "Feed", needs = "Cannibalize" }
local CS_OVER = { macro = "CS Mouseover", needs = "Counterspell" }
local POLY_OVER = { macro = "Poly Over", needs = "Polymorph" }
-- macros and items older versions of this addon placed; found on a bar, they are replaced, not kept
local RETIRED_MACROS = { ["Counterspell Ins"] = true, ["Fireball R1"] = true }
local RETIRED_ITEMS = { [5514] = true, [5513] = true, [8007] = true, [8008] = true } -- loose mana gems

-- Items, worst to best. The best one in your bags that you are high enough to use wins. `pattern`
-- catches items this list does not know yet (new Forever items), judged by their required level.
-- `macro` wraps the item so it does what you need in a fight.
local ITEMS = {
  potion = { label = "health potion", ids = { 118, 858, 929, 1710, 3928, 13446 }, pattern = "Healing Potion$",
             macro = { name = "Health Pot", body = "#showtooltip item:%d\n/stopcasting\n/use item:%d" } },
  manapotion = { label = "mana potion", ids = { 2455, 3385, 3827, 6149, 13443, 13444 }, pattern = "Mana Potion$" },
  bandage = { label = "bandage", ids = { 1251, 2581, 3530, 3531, 6450, 6451, 8544, 8545, 14529, 14530 }, pattern = "Bandage$",
              macro = { name = "Bandage Self", body = "#showtooltip item:%d\n/stopcasting\n/use [@player] item:%d" } },
  water = { label = "water", ids = { 5350, 2288, 2136, 3772, 8077, 8078, 8079 }, pattern = "^Conjured .*Water$" },
  food = { label = "food", ids = { 5349, 1113, 1114, 1487, 8075, 8076, 22895 } },
  -- the burst button: a Cryoblast scroll (a point-blank Frost burst, one minute cooldown, stand still to
  -- use it) when you carry one, otherwise your best engineering explosive
  grenade = { label = "Cryoblast scroll or grenade", ids = { 4360, 4365, 4370, 4374, 4378, 4380, 4390, 4394, 10507, 10514, 10562, 15993, 18641, 217495, 277499 },
              patterns = { "Grenade$", "Bomb$", "Dynamite$", "Cryoblast$" } },
  hearth = { label = "Hearthstone", ids = { 6948 } },
  -- Engineering devices worth a key, worst to best. Most of these need the profession; the
  -- EZ-Thro line does not, and the pattern catches the SAF-T and EZ-Thro items Forever added.
  gadget = { label = "engineering device", ids = { 4366, 4392, 4852, 7189, 10724, 4388, 10645, 10721, 16022 },
             patterns = { "Target Dummy$", "Rocket Boots$", "Flash Bomb$", "Ray$", "Dragonling$" } },
}
local SCROLL_PATTERN = "^Scroll of "

-- Racials you press, by race, best first. Read from the Forever racial data on 2026-10-27, so
-- the Forsaken have two: Will of the Forsaken is the escape and gets a key of its own, and
-- Cannibalize now restores mana as well as health, which makes it a real button for a mage.
-- Touch of the Grave and Underwater Breathing are passive and never get a key.
local RACE_ACTIVES = {
  Scourge = { WOTF, FEED },                                      -- Undead
  Troll   = { "Berserking", "Rapid Regeneration" },
  Orc     = { "Blood Fury", "Shatter Curse" },
  Human   = { "Will to Survive", "Perception" },
  Gnome   = { "Eureka!", "Escape Artist" },
  Dwarf   = { "Stoneform" },
  NightElf = { "Shadowmeld" },
  Tauren  = { "War Stomp" },
  Skyborne = { "Walk on Air", "Skysight", "Read Leyline" },
}
-- Every racial any race might have, so a race this table has not met still gets its button.
local RACIALS = { "Will of the Forsaken", "Cannibalize", "Berserking", "Rapid Regeneration", "Blood Fury", "Shatter Curse",
                  "Will to Survive", "Perception", "Eureka!", "Escape Artist", "Stoneform", "Shadowmeld", "War Stomp",
                  "Walk on Air", "Skysight", "Read Leyline" }

local function raceToken()
  local _, token = try(UnitRace, "player")
  return plain(token)
end

-- The nth racial you press, as a first(...) entry: your own race's list, then anything else.
-- Returns nil when your race has no nth one, so the slot falls through to the pool.
local function racial(n)
  local mine = RACE_ACTIVES[raceToken() or ""] or {}
  if mine[n] then return type(mine[n]) == "table" and mine[n] or { spell = { mine[n] } } end
  if n > 1 then return false end
  return { spell = RACIALS }   -- a race this file has not met still gets one racial button
end

-- SPEC ----------------------------------------------------------------------
-- Forever gives the mage three talent trees, and the spells that decide how you fight are
-- talents: Ice Lance, Ice Block, Ice Barrier and Cold Snap are Frost; Pyroblast, Blast Wave and
-- Combustion are Fire; Arcane Blast, Arcane Wrath, Arcane Power and Presence of Mind are Arcane.
-- So the addon reads where your points went and swaps the spells, never the keys. The key that
-- casts your main nuke is E in every tree. Only what comes out of it changes.
local SPEC_NAMES = { arcane = "arcane", fire = "fire", frost = "frost" }
local SPEC_MIN = 5 -- points in one tree before it counts as your tree

local function specOf()
  local best, bestPoints = nil, 0
  local S = C_SpecializationInfo
  for i = 1, 5 do
    local name, points
    if S and S.GetSpecializationInfo then
      -- pointsSpent is the seventh return, past where the shared try() helper stops
      local ok, _, n, _, _, _, _, spent = pcall(S.GetSpecializationInfo, i)
      if ok then name, points = plain(n), plain(spent) end
    end
    if name == nil and GetTalentTabInfo then -- the deprecation shim, when the CVar has it loaded
      local ok, _, n, _, _, spent = pcall(GetTalentTabInfo, i)
      if ok then name, points = plain(n), plain(spent) end
    end
    if not name then break end
    points = tonumber(points) or 0
    if points > bestPoints then best, bestPoints = SPEC_NAMES[name:lower()], points end
  end
  if bestPoints < SPEC_MIN then return nil, bestPoints end
  return best, bestPoints
end
ns.specOf = specOf

-- What each role casts in each tree. "core" is what you press before any tree has enough
-- points to matter, so a level 1 mage is already fully bound and nothing moves when it grows.
local SPEC_ROWS = {
  core = {
    nuke      = first("Frostbolt", "Fireball"),
    follow    = any(stop("Ice Lance"), "Scorch", "Arcane Missiles"),
    panic     = any(ICE_BLOCK, SHIELD_OFF),
    second    = any(FROST_BLAST, "Scorch", "Arcane Missiles"),
    burst     = any("Cold Snap", "Combustion", "Arcane Power", "Presence of Mind"),
    offschool = any("Frostfire Bolt", "Pyroblast", "Fireball"),
    absorb    = first("Ice Barrier", "Mana Shield"),
  },
  -- Frost: Frostbolt into Ice Lance, and Frost Blast when you have to keep moving.
  frost = {
    nuke      = first("Frostbolt"),
    follow    = stop("Ice Lance"),
    panic     = any(ICE_BLOCK, SHIELD_OFF),
    second    = any(FROST_BLAST, "Scorch"),
    burst     = any("Cold Snap", "Presence of Mind"),
    offschool = first("Frostfire Bolt", "Fireball"),
    absorb    = first("Ice Barrier", "Mana Shield"),
  },
  -- Fire: Fireball into Scorch for the vulnerability stack, Pyroblast when Heating Up has paid out.
  fire = {
    nuke      = first("Fireball"),
    follow    = first("Scorch"),
    panic     = any(ICE_BLOCK, SHIELD_OFF),
    second    = any("Pyroblast", FROST_BLAST),
    burst     = any("Combustion", "Presence of Mind"),
    offschool = first("Frostfire Bolt", "Frostbolt"),
    absorb    = first("Ice Barrier", "Mana Shield"),
  },
  -- Arcane: Arcane Blast to build the stack, Arcane Missiles when Missile Barrage procs,
  -- Arcane Wrath as the one that hits hardest.
  arcane = {
    nuke      = first("Arcane Blast", "Frostbolt"),
    follow    = first("Arcane Missiles"),
    panic     = any(ICE_BLOCK, SHIELD_OFF),
    second    = any("Arcane Wrath", FROST_BLAST),
    burst     = any("Arcane Power", "Presence of Mind"),
    offschool = first("Frostbolt", "Fireball"),
    absorb    = first("Ice Barrier", "Mana Shield"),
  },
}

-- LAYOUT --------------------------------------------------------------------
-- Role contract. Each key has one job for the whole life of the character; the spell in it is
-- whatever your tree uses for that job. Nothing moves when you respec.
--
--   left hand, plain      Q freeze   E nuke   R follow-up   F escape   Z instant   X panic   C wand
--   left hand, Shift      E second nuke   R Arcane Missiles   Z mana back   X burst   C gem
--   left hand, Alt        Q racial   E off-school nuke   R instant-cast   Z cone   X absorb   C decurse
--   thumb pad             potion, food, water, bandage; with Alt, mana potion, the conjures, hearth
--   mouse thumb, plain    control, area damage and the sustain you press mid-fight
--   mouse thumb, Shift    the second target version of each, wards, the burst item
--   mouse thumb, Alt      mouseover versions, trinkets, armours, buffs, gadgets
local LAYOUT = {
  MAGE = {
    -- Built when it is asked for, not when the file loads: it needs your race, your tree and
    -- your level, and none of those are readable yet while addons are still loading.
    rows = function(spec)
      local by = SPEC_ROWS[spec or "core"] or SPEC_ROWS.core
      -- The seven squares whose spell is decided by your tree. Everything else is the same in
      -- all three, which is the whole point: a respec changes what casts, never where it is.
      local owned = { [MAIN + 1] = true, [MAIN + 2] = true, [MAIN + 5] = true,
                      [SHIFT + 1] = true, [SHIFT + 5] = true, [ALT + 1] = true, [ALT + 4] = true }
      return owned, {
        -- Q E R F Z X C, a spare square, then pad up, down, left, right
        [MAIN] = { "Frost Nova", by.nuke, by.follow, stop("Blink"), stop("Fire Blast"), by.panic, "Shoot", false,
                   item("potion"), item("food"), item("water"), item("bandage") },
        -- the same seven keys with Shift, the pad's thumb key.
        -- Shift+Q and Shift+F stay empty on purpose: a cooldown pressed with Shift still held sent
        -- the next E out as the wrong spell, and Blink must never be eaten by a modifier.
        [SHIFT] = { false, by.second, "Arcane Missiles", false, "Evocation", by.burst, GEM, false,
                    false, false, false, false },
        -- the same seven keys with Alt, the pad key directly above Shift. Alt is the layer for
        -- things that save your life once a fight and for the housekeeping between fights.
        [ALT] = { racial(1), by.offschool, "Presence of Mind", false, by.absorb, TRINKETS, DECURSE, false,
                  item("manapotion"), "Conjure Food", "Conjure Water", CONJURE_GEM },
        -- mouse thumb buttons 1 to 12, as printed on the mouse. 1 to 5 are also the pad's top row.
        -- thumb 1 is the smart Polymorph: your focus if you have one, otherwise your target.
        -- Thumb 7 and up are a reach on this mouse, so nothing that decides a fight lives there.
        [MOUSE] = grid({ POLY_FOC, stop("Cone of Cold"), "Arcane Explosion", stop("Counterspell"), "Blizzard", "Arcane Missiles",
                         "Frost Ward", "Fire Ward", false, "Flamestrike", FROST_R1, MOUNT }),
        -- Shift + mouse thumb buttons 1 to 12. Thumb 2 is the second racial: it is also on the
        -- pad's top row, so the left hand reaches it while the right hand loots, which is exactly
        -- what Feed, pressed over a corpse after every pack, wants. Blast Wave lives at thumb 6:
        -- a mage outside the fire tree never learns it, and a spell that may never exist must
        -- not hold a key the pad can reach.
        [MSHIFT] = grid({ "Polymorph", racial(2), "Remove Lesser Curse", CS_FOC, SHIELD_OFF, "Blast Wave",
                          "Slow Fall", false, item("manapotion"), first("Ice Armor", "Frost Armor"), item("grenade"), item("hearth") }),
        -- Alt + mouse thumb buttons 1 to 12: the mouseover versions, and everything you set up with
        -- Thumb 9 to 12 with Alt are left empty on purpose. They are in the pool below, so the
        -- teleports, portals, conjures and anything else you learn land on a key you can press
        -- instead of a square you have to click. That is what "everything is bound" means here.
        [MALT] = grid({ POLY_OVER, CS_OVER, first("Arcane Brilliance", "Arcane Intellect"), "Mage Armor", "Dampen Magic",
                        "Amplify Magic", item("gadget"), "Comprehend Scroll", false, false, false, false }),
      }
    end,
    -- click buttons: everything you cast standing still. Filled in this order, then your scrolls,
    -- then any spell this file has never heard of, so nothing you learn is ever missing.
    -- Filled in this order, and the order is the promise: a key you can press comes before a
    -- square you can only click. So the first spell you learn with no fixed home lands on
    -- thumb 9, not on a click button you will forget is there.
    pool = { mslot(MOUSE, 9), mslot(MSHIFT, 8),                                     -- bound, and on a bar you can see
             CLICK, CLICK + 1, CLICK + 2, CLICK + 3, CLICK + 4, CLICK + 5,          -- click, on a bar you can see
             CLICK + 6, CLICK + 7, CLICK + 8, CLICK + 9, CLICK + 10, CLICK + 11,
             SHIFT + 7, SHIFT + 8, SHIFT + 9, SHIFT + 10, SHIFT + 11, MAIN + 7,
             -- Bound, but on Action Bar 7: switch that on under Options, Action Bars to see them
             mslot(MALT, 9), mslot(MALT, 10), mslot(MALT, 11), mslot(MALT, 12), ALT + 7,
             -- Action Bar 8: switch it on too when everything above is full
             169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180 },
    visible = 20, -- how many of those are on bars that are already showing
    utility = { "Conjure Water", "Conjure Food",
                first("Conjure Mana Ruby", "Conjure Mana Citrine", "Conjure Mana Jade", "Conjure Mana Agate"),
                "Arcane Power", "Combustion", "Cold Snap", "Pyroblast", "Blast Wave", "Arcane Blast", "Arcane Wrath",
                "Frost Blast", "Frostfire Bolt", "Scorch", "Ice Barrier", "Mana Shield", "Ice Block", "Ice Lance",
                "Flamestrike", "Comprehend Scroll" },
    -- never given a button: the auto attack, and spells a later spell fully replaces
    ignore = { Attack = true, ["Frost Armor"] = true, ["Conjure Mana Agate"] = true, ["Conjure Mana Jade"] = true, ["Conjure Mana Citrine"] = true },
  },
}

local function bank() return (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0 end

-- name -> { slot = spellbook slot, id = spell id } for the highest rank of every spell you know
local function spellIndex()
  local best, SB = {}, C_SpellBook
  if not (SB and SB.GetSpellBookItemInfo) then return best end
  local spellType = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
  local function add(slot)
    local entry = try(SB.GetSpellBookItemInfo, slot, bank())
    if type(entry) ~= "table" then return false end
    local name, kind = plain(entry.name), plain(entry.itemType)
    if not name then return false end
    if entry.isPassive or entry.isOffSpec or (kind and kind ~= spellType) then return true end -- not castable yet
    local id = plain(entry.spellID) or plain(entry.actionID)
    local low = try(SB.IsSpellBookItemLowRank, slot, bank()) and true or false
    -- The rank NUMBER is the real arbiter of which entry is highest. Forever does not
    -- reliably report IsSpellBookItemLowRank or list ranks lowest-first, which is what put a
    -- rank 1 Frost Armor on the key. So read "Rank N" from the book entry (falling back to the
    -- spell itself) and let the largest rank win; a buff is always kept at its highest rank.
    local sub = plain(entry.subName)
    if (not sub or sub == "") and id and C_Spell and C_Spell.GetSpellSubtext then sub = plain(try(C_Spell.GetSpellSubtext, id)) end
    local rank = tonumber((sub or ""):match("%d+")) or 0
    local have = best[name]
    local better
    if not have then better = true
    elseif rank ~= have.rank then better = rank > have.rank       -- a real rank number settles it
    elseif have.low ~= low then better = have.low and not low      -- else a known top rank beats a known low one
    else better = slot > have.slot end                            -- else the later slot (the usual lowest-first order)
    if better then
      best[name] = { slot = slot, id = id, base = plain(entry.actionID) or plain(entry.spellID), low = low, rank = rank }
    end
    return true
  end
  local found = false
  for line = 1, try(SB.GetNumSpellBookSkillLines) or 0 do
    local info = try(SB.GetSpellBookSkillLineInfo, line)
    if type(info) == "table" and info.itemIndexOffset and info.numSpellBookItems then
      for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        if add(slot) then found = true end
      end
    end
  end
  if not found then
    local misses = 0
    for slot = 1, 600 do
      if add(slot) then misses = 0 else misses = misses + 1 if misses >= 40 then break end end
    end
  end
  return best
end
ns.spellIndex = spellIndex

-- BAGS ----------------------------------------------------------------------
local function bagCounts()
  local counts, C = {}, C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerItemID) then return counts end
  for bag = 0, 4 do
    for slot = 1, try(C.GetContainerNumSlots, bag) or 0 do
      local id = plain(try(C.GetContainerItemID, bag, slot))
      if id then counts[id] = (counts[id] or 0) + 1 end
    end
  end
  return counts
end

local function itemName(id)
  local name = plain(try(C_Item and C_Item.GetItemNameByID, id))
  if type(name) == "string" then return name end
end

-- the level an item needs, or 0 when the game has not loaded it yet
local function itemLevelNeeded(id)
  local _, _, _, _, minLevel = try((C_Item and C_Item.GetItemInfo) or GetItemInfo, id)
  minLevel = plain(minLevel)
  return type(minLevel) == "number" and minLevel or 0
end

-- "Manual: Heavy Silk Bandage" teaches the bandage, it is not one: recipe names never count
local function matchesKind(kind, name)
  if not name or name:find("^%a+: ") then return false end
  if kind.pattern and name:find(kind.pattern) then return true end
  for _, pattern in ipairs(kind.patterns or {}) do if name:find(pattern) then return true end end
  return false
end

local function isRecipe(id)
  local _, _, _, _, _, class = try((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant, id)
  return plain(class) == 9
end

local function kindHas(kind, id)
  for _, known in ipairs(kind.ids) do if known == id then return true end end
  return matchesKind(kind, itemName(id))
end

-- the best item of a kind that is in the bags and usable at this level: highest required level
-- wins, the list order breaks ties, so an item this file has never heard of still competes
local function bestItem(kind, bags, level)
  local best, bestScore
  local function consider(id, order)
    local need = itemLevelNeeded(id)
    if need > level then return end
    local score = need * 1000 + order
    if not best or score > bestScore then best, bestScore = id, score end
  end
  local listed = {}
  for order, id in ipairs(kind.ids) do
    listed[id] = true
    if bags[id] then consider(id, order) end
  end
  for id in pairs(bags) do
    if not listed[id] and matchesKind(kind, itemName(id)) and not isRecipe(id) then consider(id, 0) end
  end
  return best
end

local function scrollsInBags(bags)
  local list = {}
  for id in pairs(bags) do
    local name = itemName(id)
    -- a scroll that already has a key of its own (Cryoblast) is not listed again as a click button
    if name and name:find(SCROLL_PATTERN) and not kindHas(ITEMS.grenade, id) then list[#list + 1] = { id = id, name = name } end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- a mount you own: its macro text, or nil
local function mountMacro(bags)
  local MJ = C_MountJournal
  if MJ and MJ.GetMountIDs and MJ.GetMountInfoByID then
    for _, id in ipairs(try(MJ.GetMountIDs) or {}) do
      local r = { pcall(MJ.GetMountInfoByID, id) } -- ok, name, spellID, icon, active, usable, source, favorite, factionOnly, faction, hide, collected
      if r[1] and plain(r[12]) == true and plain(r[11]) ~= true and type(plain(r[2])) == "string" then
        return "#showtooltip\n/cast " .. r[2]
      end
    end
  end
  local instant = C_Item and C_Item.GetItemInfoInstant
  for id in pairs(bags) do
    local r = { pcall(instant, id) } -- ok, itemID, type, subType, equipLoc, icon, classID, subClassID
    if r[1] and plain(r[7]) == 15 and plain(r[8]) == 5 then return ("#showtooltip item:%d\n/use item:%d"):format(id, id) end
  end
end

-- MACROS --------------------------------------------------------------------
local function macroExists(name) return (try(GetMacroIndexByName, name) or 0) > 0 end

-- macros earlier versions of this addon made, before it kept a list of its own
local LEGACY_MACROS = { ["Poly Focus"] = true, ["Counterspell Foc"] = true, ["Counterspell Ins"] = true, ["Mana Gem"] = true }

-- Is this macro the addon's to manage? A record carrying text (or the old `true`) says ours;
-- an explicit false says yours, and that wins even over the legacy name list.
local function ownedMacro(name)
  local o = (TorchBindsDB.macros or {})[name]
  if o == nil then return LEGACY_MACROS[name] or false end
  return o ~= false
end

-- Makes sure a macro of ours exists with this text. The record keeps the exact text this addon
-- last wrote, so a difference tells us whose the standing text is: the addon's own older text
-- is brought up to date, but a text YOU saved -- your own macro, or your edit of ours -- is
-- yours for good and never written over again. Records from before 8.2.4 only said "ours"
-- (true): such a record is believed only while the standing text is one the addon is known to
-- have written (`old`, when given), so a save of yours is recognized even against a stale
-- record from another character. A body that cannot be read decides nothing.
local function ensureMacro(name, body, old)
  local owned = TorchBindsDB.macros
  if not owned then owned = {} TorchBindsDB.macros = owned end
  local ok, err = pcall(function()
    if owned[name] == false then return end -- yours, for good, standing or deleted
    if not macroExists(name) then
      CreateMacro(name, "INV_MISC_QUESTIONMARK", body, false)
      if macroExists(name) then owned[name] = body end
      return
    end
    local current = plain(try(GetMacroBody, name))
    if type(current) ~= "string" then return end -- a blind read decides nothing
    if current == body then
      if owned[name] == nil then owned[name] = false -- same text, but yours came first
      else owned[name] = body end
    elseif (owned[name] == true and (not old or old[current])) or owned[name] == current
        or (owned[name] == nil and LEGACY_MACROS[name]) then
      EditMacro(name, name, nil, body)
      owned[name] = body
    elseif owned[name] == nil then
      owned[name] = false
      note("macro kept", name .. " is yours and was not changed")
    else
      -- ours once, but the standing text is not one we wrote: you saved your own over it
      owned[name] = false
      note("macro kept", name .. " carries your edit now and will not be touched again")
    end
  end)
  if not ok then note("macro failed", name .. " " .. tostring(err)) end
  return macroExists(name)
end

-- The guild recruiting line, one macro per channel (a macro holds 255 characters, one line of
-- this). The addon keeps the text current only until you save your own over one: from that
-- moment that macro is yours and survives every relog untouched.
local RECRUIT = "<True Torchmen> (Horde) : Semi-hardcore guild from Era/Nost is recruiting War, Mage, Sham. We use our PvP  addon: Godslayer, curseforge. Guild page: passthetorch.pages.dev .  Raid Time Sat: 8pm EST"
-- the ad every version before 8.2.4 wrote, recognized during the one-time cleanup below
local OLD_RECRUIT = "<The True Torchmen> (Horde) building an enjoyable progression PvP and raid core. Nov 4 launch. We have our own addons and a site with guides that explain everything: passthetorch.pages.dev  Discord: discord.gg/passthetorch  PST for an invite!"
local function recruitMacros()
  if InCombatLockdown() then return end
  -- 8.2.4 retired the world-channel ad (/6) for a yell. The old macro goes, but only while it
  -- reads exactly what this addon wrote; a text you saved there stays yours.
  if macroExists("Recruit World") then
    local body = plain(try(GetMacroBody, "Recruit World"))
    if body == "/6 " .. OLD_RECRUIT or body == "/6 " .. RECRUIT then
      try(DeleteMacro, "Recruit World")
      if not macroExists("Recruit World") and TorchBindsDB.macros then TorchBindsDB.macros["Recruit World"] = nil end
    end
  end
  -- the texts older versions wrote: a record that only says "ours" (true) is believed against
  -- these and no other, so an ad you saved is yours even under a stale record
  local olds = { ["/2 " .. OLD_RECRUIT] = true, ["/6 " .. OLD_RECRUIT] = true }
  ensureMacro("Recruit General", "/1 " .. RECRUIT, olds)
  ensureMacro("Recruit Trade", "/2 " .. RECRUIT, olds)
  ensureMacro("Recruit Yell", "/y " .. RECRUIT, olds)
end

local function stopName(spell) return (spell .. "!"):sub(1, 16) end
local function stopBody(spell)
  -- with /torch hovercs on, Counterspell goes to an enemy under the mouse first, then your target
  local where = (spell == "Counterspell" and TorchBindsDB and TorchBindsDB.hoverCS) and "[@mouseover,harm,nodead][] " or ""
  return "#showtooltip " .. spell .. "\n/stopcasting\n/cast " .. where .. spell
end

-- RESOLVE -------------------------------------------------------------------
-- Turns a layout entry into the thing to put on the bar right now:
--   { kind = "spell", id =, name = } | { kind = "macro", name = } | { kind = "item", id = }
-- or nil plus a label when you do not have it yet.
local function key(desc)
  if desc.kind == "spell" then return "spell:" .. tostring(desc.name) end
  if desc.kind == "macro" then return "macro:" .. tostring(desc.name) end
  return "item:" .. tostring(desc.id)
end

local function resolve(entry, ctx)
  if type(entry) == "string" then
    local known = ctx.index[entry]
    if known then return { kind = "spell", id = known.id, name = entry, label = entry } end
    return nil, entry
  end
  if entry.spell then
    for _, name in ipairs(entry.spell) do
      local known = ctx.index[name]
      if known then return { kind = "spell", id = known.id, name = name, label = name } end
    end
    return nil, entry.spell[#entry.spell]
  end
  if entry.any then
    local lastLabel
    for _, sub in ipairs(entry.any) do
      local desc, label = resolve(sub, ctx)
      if desc then return desc end
      lastLabel = label or lastLabel
    end
    return nil, lastLabel
  end
  if entry.stop then
    if not ctx.index[entry.stop] then return nil, entry.stop end
    local name = stopName(entry.stop)
    if not ctx.make(name, stopBody(entry.stop)) then return nil, entry.stop end
    return { kind = "macro", name = name, label = entry.stop }
  end
  if entry.macro then
    if not entry.always and not ctx.index[entry.needs] then return nil, entry.macro end
    if not ctx.make(entry.macro, MACROS[entry.macro]) then return nil, entry.macro end
    return { kind = "macro", name = entry.macro, label = entry.macro }
  end
  if entry.item then
    local kind = ITEMS[entry.item]
    local id = bestItem(kind, ctx.bags, ctx.level)
    if not id then return nil, kind.label end
    if kind.macro then
      if not ctx.make(kind.macro.name, kind.macro.body:format(id, id)) then return { kind = "item", id = id, label = kind.label } end
      return { kind = "macro", name = kind.macro.name, label = kind.label }
    end
    return { kind = "item", id = id, label = kind.label }
  end
  if entry.gem then
    -- the best gem you are carrying; with none in the bag, the best one you can conjure, so the
    -- button shows that gem greyed out instead of a question mark
    local id
    for _, gem in ipairs(GEMS) do if ctx.bags[gem[2]] then id = gem[2] break end end
    if not id then for _, gem in ipairs(GEMS) do if ctx.index[gem[1]] then id = gem[2] break end end end
    if not id or not ctx.make("Mana Gem", ("#showtooltip item:%d\n/use item:%d"):format(id, id)) then return nil, "Mana Gem" end
    return { kind = "macro", name = "Mana Gem", label = "Mana Gem" }
  end
  if entry.mount then
    local body = mountMacro(ctx.bags)
    if not body or not ctx.make("Mount", body) then return nil, "mount" end
    return { kind = "macro", name = "Mount", label = "Mount" }
  end
end

-- the spell an entry puts on the bar right now. Of a first(...) list only the one chosen counts:
-- an older spell you still know (Mana Shield beside Ice Barrier) gets its own button on the click bars.
local function spellsOf(entry, desc, into)
  if type(entry) == "string" then into[entry] = true
  elseif type(entry) == "table" then
    if entry.spell and desc and desc.name then into[desc.name] = true end
    if entry.stop then into[entry.stop] = true end
    if entry.needs then into[entry.needs] = true end
    -- an any(...) key owns whichever of its choices is on it right now; the ones it passed over
    -- are not claimed, so they still get their own click button.
    if entry.any then
      if desc and desc.name then into[desc.name] = true end
      for _, sub in ipairs(entry.any) do
        if type(sub) == "table" and sub.needs and desc and desc.kind == "macro" and desc.name == sub.macro then into[sub.needs] = true end
        if type(sub) == "table" and sub.stop and desc and desc.label == sub.stop then into[sub.stop] = true end
      end
    end
  end
end

-- Is what sits in the slot an older form of this entry (lower rank, older spell of the same
-- line, a weaker item of the same kind)? Then upkeep may replace it without asking.
local function sameFamily(entry, kind, id, text)
  if type(entry) == "string" then return kind == "spell" and text == entry end
  if entry.spell then
    if kind ~= "spell" then return false end
    for _, name in ipairs(entry.spell) do if name == text then return true end end
    return false
  end
  if entry.stop then return (kind == "spell" and text == entry.stop) or (kind == "macro" and RETIRED_MACROS[text] and entry.stop == "Counterspell") end
  -- upkeep may trade up inside an any(...) key: the Mana Shield toggle gives way to Ice Block
  if entry.any then
    for _, sub in ipairs(entry.any) do if sameFamily(sub, kind, id, text) then return true end end
    for _, sub in ipairs(entry.any) do
      if type(sub) == "table" and sub.macro and kind == "macro" and text == sub.macro then return true end
    end
    return false
  end
  if entry.item then
    local k = ITEMS[entry.item]
    return (kind == "item" and kindHas(k, id)) or false
  end
  return false
end

-- BARS ----------------------------------------------------------------------
local function cursorFull() return plain((try(GetCursorInfo))) ~= nil end

-- what a bar slot holds: kind ("spell", "item", "macro"), id, and its name
local function slotInfo(slot)
  local b = ALT_BUTTON[slot]
  if b then return b:GetAttribute("tb_kind"), b:GetAttribute("tb_id"), b:GetAttribute("tb_text") end
  local kind, id = try(GetActionInfo, slot)
  kind, id = plain(kind), plain(id)
  if not kind then return nil end
  local text
  if kind == "macro" then text = plain(try((C_ActionBar and C_ActionBar.GetActionText) or GetActionText, slot)) end
  if kind == "spell" and id and C_Spell and C_Spell.GetSpellName then text = plain(try(C_Spell.GetSpellName, id)) end
  return kind, id, text
end
ns.slotInfo = slotInfo

local function holds(slot, desc)
  local kind, id, text = slotInfo(slot)
  if kind ~= desc.kind then return false end
  if kind == "macro" then return text == desc.name end
  return id == desc.id
end

local function pickup(desc, ctx)
  ClearCursor()
  if desc.kind == "spell" then
    local known = desc.name and ctx.index[desc.name]
    if known and known.id == desc.id and C_SpellBook and C_SpellBook.PickupSpellBookItem then try(C_SpellBook.PickupSpellBookItem, known.slot, bank()) end
    if not cursorFull() and desc.id and C_Spell and C_Spell.PickupSpell then try(C_Spell.PickupSpell, desc.id) end
  elseif desc.kind == "macro" then
    try(PickupMacro, desc.name)
  elseif desc.kind == "item" then
    try((C_Item and C_Item.PickupItem) or PickupItem, desc.id)
  end
  return cursorFull()
end

local function remember(changes, slot)
  if changes[slot] ~= nil then return end
  local kind, id, text = slotInfo(slot)
  changes[slot] = kind and { kind = kind, id = id, text = text } or false
end

-- Puts one thing in one slot. The new action is picked up first, so a failed pickup leaves the
-- slot exactly as it was.
local SUPPORTED = { spell = true, macro = true, item = true }

-- A slot holding something this addon cannot put back later (a flyout, a pet, an outfit) is never touched.
local function untouchable(slot)
  local kind = plain((try(GetActionInfo, slot)))
  return kind ~= nil and not SUPPORTED[kind]
end

local function place(slot, desc, ctx, changes)
  if holds(slot, desc) then return false end
  if untouchable(slot) then return false end
  local b = ALT_BUTTON[slot]
  if b then
    if InCombatLockdown() then return false end
    local t = desc.kind
    if t ~= "spell" and t ~= "macro" and t ~= "item" then return false end
    remember(changes, slot)
    b:SetAttribute("spell", nil) b:SetAttribute("macro", nil) b:SetAttribute("item", nil)
    b:SetAttribute("type", t)
    if t == "spell" then b:SetAttribute("spell", desc.name or desc.id)
    elseif t == "macro" then b:SetAttribute("macro", desc.name)
    else b:SetAttribute("item", desc.name or ("item:" .. tostring(desc.id))) end
    b:SetAttribute("tb_kind", t) b:SetAttribute("tb_id", desc.id) b:SetAttribute("tb_text", desc.name or desc.label)
    return true
  end
  if not pickup(desc, ctx) then
    note("pickup failed", tostring(desc.label or desc.name or desc.id))
    return false
  end
  remember(changes, slot)
  PlaceAction(slot)
  ClearCursor() -- whatever was there comes off on the cursor and is dropped; the plan re-places what should be kept
  if plain((try(GetActionInfo, slot))) == nil then
    -- the client refused the slot (an action bar this build does not really have, say) and
    -- PlaceAction cannot say no, so the empty slot after the fact is the only evidence
    placeRefused = placeRefused + 1
    note("place failed", tostring(desc.label or desc.name or desc.id) .. " @ " .. tostring(slot))
    return false
  end
  return true
end

local function clear(slot, changes)
  local b = ALT_BUTTON[slot]
  if b then
    if InCombatLockdown() or not b:GetAttribute("tb_kind") then return end
    remember(changes, slot)
    for _, a in ipairs({ "type", "spell", "macro", "item", "tb_kind", "tb_id", "tb_text" }) do b:SetAttribute(a, nil) end
    return
  end
  if not slotFilled(slot) or untouchable(slot) then return end
  remember(changes, slot)
  ClearCursor()
  PickupAction(slot)
  ClearCursor()
end

-- readOnly: look, do not create or edit a macro (for /torch map, which may be typed in a fight)
local function context(readOnly)
  return { index = spellIndex(), bags = bagCounts(), level = plain(try(UnitLevel, "player")) or 60,
           make = (readOnly or InCombatLockdown()) and macroExists or ensureMacro }
end

-- The layout as it stands right now: your class, your tree, your race. Rebuilt whenever the
-- tree changes, so a respec moves the spells and leaves every key where your hands expect it.
local layoutCache, layoutFor
local function classLayout()
  local _, class = UnitClass("player")
  local def = LAYOUT[plain(class) or ""]
  if not def then return nil end
  local spec = specOf()
  local stamp = tostring(class) .. "/" .. tostring(spec) .. "/" .. tostring(raceToken())
  if layoutCache and layoutFor == stamp then return layoutCache end
  local owned, fixed = def.rows(spec)
  layoutCache, layoutFor = { fixed = fixed, owned = owned, pool = def.pool, visible = def.visible,
                             utility = def.utility, ignore = def.ignore, spec = spec }, stamp
  return layoutCache
end
-- Did the tree or the race change since the layout was last built? Cheap: no table is made.
local function layoutStale()
  local _, class = UnitClass("player")
  return layoutFor ~= (tostring(class) .. "/" .. tostring(specOf()) .. "/" .. tostring(raceToken()))
end
ns.classLayout, ns.layoutStale = classLayout, layoutStale

-- The click bars: utility spells in order, then scrolls, then spells this file does not list.
local function poolSequence(layout, ctx, fixedSpells)
  local seq, listed = {}, {}
  for name in pairs(fixedSpells) do listed[name] = true end
  for _, entry in ipairs(layout.utility) do
    local desc = resolve(entry, ctx)
    -- A fixed key already holding this spell is the end of it: one spell, one button. Which
    -- spells those are depends on your tree, so the off-tree ones still land here.
    local already = desc and desc.name and listed[desc.name]
    spellsOf(entry, desc, listed)
    if desc and not already then seq[#seq + 1] = desc end
  end
  local travel = {}
  for name in pairs(ctx.index) do
    if name:find("^Teleport: ") or name:find("^Portal: ") then travel[#travel + 1] = name listed[name] = true end
  end
  table.sort(travel)
  for _, name in ipairs(travel) do seq[#seq + 1] = { kind = "spell", id = ctx.index[name].id, name = name, label = name } end
  for _, scroll in ipairs(scrollsInBags(ctx.bags)) do seq[#seq + 1] = { kind = "item", id = scroll.id, label = scroll.name } end
  local extra = {}
  for name in pairs(ctx.index) do
    if not listed[name] and not layout.ignore[name] then extra[#extra + 1] = name end
  end
  table.sort(extra)
  for _, name in ipairs(extra) do seq[#seq + 1] = { kind = "spell", id = ctx.index[name].id, name = name, label = name, unlisted = true } end
  return seq
end

-- Applies the layout.
--   force = true   every slot the layout owns gets its action; what was in the way moves to the click bars
--   force = false  only empty slots are filled, and older ranks, spells and items are upgraded in place
-- Returns a report: placed, missing, moved, upgraded, overflow
local function arrange(force, changes)
  local layout = classLayout()
  local report = { placed = 0, missing = {}, moved = {}, upgraded = {}, overflow = {}, added = {} }
  if not layout then return report end
  local ctx = context()
  if TorchBindsDB.hoverFocus then ctx.make(FOCUS_MACRO, MACROS[FOCUS_MACRO]) end -- bound to a key, not placed on a bar
  local fixedSpells, target, entryAt = {}, {}, {}
  for first, row in pairs(layout.fixed) do
    for i, entry in ipairs(row) do
      if entry then
        local slot = first + i - 1
        entryAt[slot] = entry
        local desc, label = resolve(entry, ctx)
        spellsOf(entry, desc, fixedSpells)
        if desc then target[slot] = desc elseif not report.missing[label] then report.missing[label] = true table.insert(report.missing, label) end
      end
    end
  end
  local seq = poolSequence(layout, ctx, fixedSpells)

  if not force then
    -- fixed slots: fill the empty ones, upgrade what is an older form of the same thing
    for slot, desc in pairs(target) do
      local kind, id, text = slotInfo(slot)
      if not kind then
        if place(slot, desc, ctx, changes) then report.placed = report.placed + 1 table.insert(report.added, desc.label) end
      elseif not holds(slot, desc) and sameFamily(entryAt[slot], kind, id, text) then
        if place(slot, desc, ctx, changes) then
          report.placed = report.placed + 1
          local label = desc.label
          -- A different spell taking the key reads like a bug unless it is said out loud:
          -- Ice Armor over a hand-dragged Frost Armor wears the very same icon. A higher
          -- rank of the same name stays quiet.
          if text and desc.name and text ~= desc.name then
            label = label .. " (replaces " .. text .. ", which it outgrows)"
            report.renamed = true
          end
          table.insert(report.upgraded, label)
        end
      end
    end
    -- click bars: newer ranks in place, then anything not on any bar goes into the first empty slot
    local onBars = {}
    for slot = 1, 180 do
      local kind, id, text = slotInfo(slot)
      if kind == "spell" and text then onBars["spell:" .. text] = slot elseif kind == "macro" and text then onBars["macro:" .. text] = slot elseif kind == "item" then onBars["item:" .. tostring(id)] = slot end
    end
    for _, desc in ipairs(seq) do
      local at = onBars[key(desc)]
      if at then
        local kind, id = slotInfo(at)
        if desc.kind == "spell" and kind == "spell" and id ~= desc.id and not entryAt[at] then
          local inPool
          for _, slot in ipairs(layout.pool) do if slot == at then inPool = true end end
          if inPool and place(at, desc, ctx, changes) then report.placed = report.placed + 1 table.insert(report.upgraded, desc.label) end
        end
      else
        local free
        for _, slot in ipairs(layout.pool) do if not slotFilled(slot) then free = slot break end end
        if free then
          if place(free, desc, ctx, changes) then report.placed = report.placed + 1 table.insert(report.added, desc.label) onBars[key(desc)] = free end
        else
          table.insert(report.overflow, desc.label)
        end
      end
    end
    return report
  end

  -- forced: work out what the layout itself will place, so only things it will NOT place are kept
  local managed = {}
  for _, desc in pairs(target) do managed[key(desc)] = true end
  for _, desc in ipairs(seq) do managed[key(desc)] = true end
  for name in pairs(fixedSpells) do managed["spell:" .. name] = true end
  local function foreign(slot)
    local kind, id, text = slotInfo(slot)
    if not kind then return nil end
    if kind == "macro" and (RETIRED_MACROS[text] or not text) then return nil end
    if kind == "item" and RETIRED_ITEMS[id] then return nil end
    local desc = (kind == "spell" and { kind = "spell", id = id, name = text, label = text or ("spell " .. tostring(id)) })
      or (kind == "macro" and { kind = "macro", name = text, label = text })
      or (kind == "item" and { kind = "item", id = id, label = itemName(id) or ("item " .. tostring(id)) })
    if not desc then return nil end
    -- a macro you wrote is yours even when it shares a name with one of this addon's
    local yours = kind == "macro" and not ownedMacro(text)
    if yours then
      if managed["yours:" .. text] then return nil end
      managed["yours:" .. text] = true
      return desc
    end
    if managed[key(desc)] then return nil end
    if kind == "item" then for _, k in pairs(ITEMS) do if kindHas(k, id) then return nil end end end -- an older potion or bandage: its slot has the best one
    managed[key(desc)] = true
    return desc
  end
  local kept = {}
  for slot in pairs(entryAt) do
    if target[slot] and not holds(slot, target[slot]) then
      local desc = foreign(slot)
      if desc then kept[#kept + 1] = desc table.insert(report.moved, desc.label) end
    elseif not target[slot] and slotFilled(slot) then
      -- reserved for something you do not have yet (a mount, a grenade). What sits there now moves
      -- to the click bars so the key is free the day you get it.
      local desc = foreign(slot)
      if desc then kept[#kept + 1] = desc table.insert(report.moved, desc.label) end
      clear(slot, changes)
    end
  end
  -- A copy of something the layout places elsewhere, left behind on one of the five bars by an
  -- older arrangement, is removed so each spell shows once where its key is.
  local placedKeys, isPool = {}, {}
  for _, desc in pairs(target) do placedKeys[key(desc)] = true end
  for _, slot in ipairs(layout.pool) do isPool[slot] = true end
  for _, first in ipairs({ MAIN, SHIFT, MOUSE, MSHIFT, CLICK }) do
    for slot = first, first + 11 do
      if not target[slot] and not isPool[slot] and not entryAt[slot] then
        local kind, id, text = slotInfo(slot)
        local k = (kind == "spell" and text and ("spell:" .. text)) or (kind == "macro" and text and ("macro:" .. text)) or nil
        local ours = kind == "macro" and text and ownedMacro(text)
        if k and placedKeys[k] and (kind == "spell" or ours) then clear(slot, changes) end
      end
    end
  end

  local open = {} -- click-bar slots this addon may write to
  for _, slot in ipairs(layout.pool) do
    if not untouchable(slot) then
      open[#open + 1] = slot
      local desc = foreign(slot)
      if desc then kept[#kept + 1] = desc end
    end
  end
  -- Your own things are never the ones left out. If space runs short, the spells at the end of
  -- this addon's own list wait (they are still in the spellbook), and yours all stay on a bar.
  local room = #open - #kept
  if room < 0 then
    -- more of your own actions than slots: leave the click bars exactly as they are
    for _, desc in ipairs(seq) do table.insert(report.overflow, desc.label) end
    report.moved = {}
    for slot in pairs(entryAt) do
      if not target[slot] or not holds(slot, target[slot]) then
        local kind = slotInfo(slot)
        if kind then target[slot] = nil end -- and do not push anything else of yours out of a key either
      end
    end
  else
    for i = #seq, room + 1, -1 do table.insert(report.overflow, 1, seq[i].label) seq[i] = nil end
    for _, desc in ipairs(kept) do seq[#seq + 1] = desc end
    for i, slot in ipairs(open) do
      local desc = seq[i]
      if desc then target[slot] = desc else clear(slot, changes) end
    end
    report.hidden = math.max(0, #seq - layout.visible)
  end
  for slot, desc in pairs(target) do
    if place(slot, desc, ctx, changes) then
      report.placed = report.placed + 1
    elseif not holds(slot, desc) then
      -- could not be placed (an item that is gone): do not leave an old copy of something else sitting there
      local kind, _, text = slotInfo(slot)
      local k = (kind == "spell" and text and ("spell:" .. text)) or (kind == "macro" and text and ("macro:" .. text)) or nil
      if k and placedKeys[k] then clear(slot, changes) end
    end
  end
  return report
end

-- CLICK TO DECURSE -----------------------------------------------------------
-- The game has click casting built in for its own party, raid and player frames. This adds
-- Remove Lesser Curse to it: middle-click a frame, or Shift + right-click it. Left click still
-- targets and plain right click still opens the menu.
local function clickCast()
  local CB = C_ClickBindings
  local known = spellIndex()["Remove Lesser Curse"]
  if not known then return "not learned" end
  if not (CB and CB.GetProfileInfo and CB.SetProfileByInfo and Enum and Enum.ClickBindingType) then return "no click casting in this client" end
  if InCombatLockdown() then return "combat" end
  local profile = try(CB.GetProfileInfo)
  if type(profile) ~= "table" then return "could not read the click bindings" end
  local shift
  local toText = (C_Input and C_Input.GetStringFromModifiers) or GetStringFromModifiers
  for bits = 1, 16 do
    local text = plain(try(toText, bits))
    if type(text) == "string" and text:upper():gsub("[^A-Z]", "") == "SHIFT" then shift = bits break end
  end
  local spell = known.base or known.id
  local wantList = { { button = "MiddleButton", modifiers = 0, label = "middle-click" } }
  if shift then wantList[2] = { button = "RightButton", modifiers = shift, label = "Shift + right-click" } end
  local ours, added = {}, 0
  for _, want in ipairs(wantList) do
    local holder
    for _, b in ipairs(profile) do
      if plain(b.button) == want.button and plain(b.modifiers) == want.modifiers then holder = b end
    end
    if holder then
      -- already ours, or yours for something else: either way it is not replaced
      if plain(holder.type) == Enum.ClickBindingType.Spell and plain(holder.actionID) == spell then ours[#ours + 1] = want.label end
    else
      profile[#profile + 1] = { type = Enum.ClickBindingType.Spell, actionID = spell, button = want.button, modifiers = want.modifiers }
      added = added + 1
      ours[#ours + 1] = want.label
    end
  end
  if added > 0 then
    local ok, err = pcall(CB.SetProfileByInfo, profile)
    if not ok then note("click cast", err) return "the game refused it" end
    -- read it back: only what the game kept counts
    local now, kept = try(CB.GetProfileInfo), {}
    for _, want in ipairs(wantList) do
      for _, b in ipairs(type(now) == "table" and now or {}) do
        if plain(b.button) == want.button and plain(b.modifiers) == want.modifiers and plain(b.actionID) == spell then kept[#kept + 1] = want.label end
      end
    end
    ours = kept
  end
  if #ours == 0 then return "both clicks are already used for something else. Set one yourself: spellbook, Click Bindings" end
  return "ok", table.concat(ours, " or ")
end

-- SETUP, UPKEEP, UNDO, MAP --------------------------------------------------
local function list(items, most)
  if #items <= most then return table.concat(items, ", ") end
  return table.concat(items, ", ", 1, most) .. " and " .. (#items - most) .. " more"
end

local function setup(auto)
  if InCombatLockdown() then say("You are in combat. Try again after the fight.") return false end
  if not classLayout() then say("No bar layout for this class yet. Your keys are bound; the bars are yours to fill.") return false end
  if not barsServing() then
    if not auto then say("The game is not serving the action bars yet. Try again in a moment.") end
    return false
  end
  placeRefused = 0
  local changes = {}
  local report = arrange(true, changes)
  if not TorchBindsDB.undo then -- keep the oldest record: undo goes back to before Torch Binds touched anything
    TorchBindsDB.undo = { at = date("%Y-%m-%d %H:%M:%S"), slots = changes }
  else
    for slot, old in pairs(changes) do if TorchBindsDB.undo.slots[slot] == nil then TorchBindsDB.undo.slots[slot] = old end end
  end
  if placeRefused > 0 then
    -- the client took some placements and ignored others: half ready. Record nothing, so the
    -- whole layout is tried again from the top once the client serves.
    note("layout deferred", placeRefused .. " placements refused by the client")
    if not auto then say("The game refused " .. placeRefused .. " placements. The layout will finish when the client is ready.") end
    return false
  end
  TorchBindsDB.lastSetup = { placed = report.placed, missing = report.missing, moved = report.moved, overflow = report.overflow, auto = auto or nil, at = date("%Y-%m-%d %H:%M:%S") }
  TorchBindsDB.layoutVersion = LAYOUT_VERSION
  -- which tree this arrangement was built for, so a later respec knows it has to change
  TorchBindsDB.specApplied = (classLayout() or {}).spec or "core"
  if report.placed > 0 then say("Layout applied. " .. report.placed .. " buttons changed. /torch map shows every key, /torch undo puts it back.") else say("Your bars already match the layout.") end
  if #report.moved > 0 then say("Moved to your click bars: " .. list(report.moved, 6)) end
  if (report.hidden or 0) > 0 then say(report.hidden .. " of the least used buttons are on Action Bar 6. Switch it on under Options, Action Bars to see them.") end
  if #report.overflow > 0 then say("No room on any bar for: " .. list(report.overflow, 6)) end
  if #report.missing > 0 then say("Not yours yet, added by itself when you get them: " .. list(report.missing, 8)) end
  local state = applyBinds()
  if state ~= "ok" then say("Keybinds will apply when the game is ready.") end
  local click, how = clickCast()
  TorchBindsDB.clickCast = click
  if click == "ok" then say("Decurse: " .. how .. " a party, raid or player frame. Or hold Shift and press 3 with the mouse over anyone.") end
  dump("setup")
  return true
end

-- after training or looting: new spells into their slots, new ranks over old ones, best potion in the potion slot
local TALENT_EVENT = { PLAYER_TALENT_UPDATE = true, CHARACTER_POINTS_CHANGED = true, ACTIVE_TALENT_GROUP_CHANGED = true,
                      PLAYER_SPECIALIZATION_CHANGED = true, TRAIT_CONFIG_UPDATED = true }
local specPending = false

local function upkeep(quiet)
  if InCombatLockdown() or TorchBindsDB.off or TorchBindsDB.layoutVersion ~= LAYOUT_VERSION or not barsServing() then return false end
  -- what upkeep adds is recorded too, so /torch undo takes it back off
  local report = arrange(false, TorchBindsDB.undo and TorchBindsDB.undo.slots or {})
  if report.placed > 0 then
    if #report.upgraded > 0 and (not quiet or report.renamed) then say("Updated on your bars: " .. list(report.upgraded, 6)) end
    if #report.added > 0 then say("Added to your bars: " .. list(report.added, 6) .. ". /torch map shows where.") end
    applyBinds()
  end
  repairBinds()
  return true
end

-- Your tree changed. Replace only the squares the tree owns, say what moved, and keep the keys.
local function respec(quiet)
  if InCombatLockdown() or TorchBindsDB.off or TorchBindsDB.layoutVersion ~= LAYOUT_VERSION or not barsServing() then return false end
  local layout = classLayout()
  if not (layout and layout.owned) then return false end
  local ctx, changes = context(), (TorchBindsDB.undo and TorchBindsDB.undo.slots or {})
  local moved = {}
  for first, row in pairs(layout.fixed) do
    for i, entry in ipairs(row) do
      local slot = first + i - 1
      if entry and layout.owned[slot] and not untouchable(slot) then
        local desc = resolve(entry, ctx)
        if desc and not holds(slot, desc) then
          if place(slot, desc, ctx, changes) then table.insert(moved, desc.label) end
        end
      end
    end
  end
  TorchBindsDB.specApplied = layout.spec or "core"
  if #moved > 0 then
    if not quiet then say("Your tree changed, so these keys cast something new: " .. list(moved, 7) .. ". The keys did not move.") end
    applyBinds()
  end
  return true
end

local function undo()
  if InCombatLockdown() then say("You are in combat. Try again after the fight.") return end
  local saved = TorchBindsDB.undo
  if type(saved) ~= "table" then say("Nothing to undo.") return end
  local restored, ctx = 0, context()
  for slot, old in pairs(saved.slots or {}) do
    local b = ALT_BUTTON[slot]
    if b then
      pcall(function()
        for _, a in ipairs({ "type", "spell", "macro", "item", "tb_kind", "tb_id", "tb_text" }) do b:SetAttribute(a, nil) end
        if old and old.kind then
          b:SetAttribute("type", old.kind)
          if old.kind == "spell" then b:SetAttribute("spell", old.text or old.id)
          elseif old.kind == "macro" then b:SetAttribute("macro", old.text)
          else b:SetAttribute("item", old.text or ("item:" .. tostring(old.id))) end
          b:SetAttribute("tb_kind", old.kind) b:SetAttribute("tb_id", old.id) b:SetAttribute("tb_text", old.text)
          restored = restored + 1
        end
      end)
    else
      pcall(function()
        ClearCursor()
        PickupAction(slot)
        ClearCursor()
        if old and pickup({ kind = old.kind, id = old.id, name = old.text }, ctx) then
          PlaceAction(slot)
          restored = restored + 1
        end
        ClearCursor()
      end)
    end
  end
  for k, command in pairs(TorchBindsDB.bindsBefore or {}) do pcall(SetBinding, k, command ~= "" and command or nil) end
  local set = bindingSet()
  if set then pcall(SaveBindings, set) end
  TorchBindsDB.undo, TorchBindsDB.bindsBefore = nil, nil
  TorchBindsDB.off = true -- or the next login would apply the layout again
  say("Bars and binds are back as they were (" .. restored .. " buttons restored). Torch Binds is now off; /torch on turns it back on.")
end

local PRETTY = { BUTTON3 = "wheel click", BUTTON4 = "mouse 4", BUTTON5 = "mouse 5", UP = "pad up", DOWN = "pad down", LEFT = "pad left", RIGHT = "pad right",
                 MOUSEWHEELDOWN = "wheel down", ["0"] = "thumb 10", ["-"] = "thumb 11", ["="] = "thumb 12" }
for n = 1, 9 do PRETTY[tostring(n)] = "thumb " .. n end
local function prettyKey(k)
  local mod, base = k:match("^(%u+)%-(.+)$")
  if mod ~= "SHIFT" and mod ~= "CTRL" and mod ~= "ALT" then mod, base = nil, k end
  base = PRETTY[base] or base
  if mod then return mod:sub(1, 1) .. mod:sub(2):lower() .. "+" .. base end
  return base
end
ns.prettyKey = prettyKey

-- slot -> the keys that press it under the current preset, shortest first
local function keysBySlot()
  local out = {}
  for k, command in pairs(wanted()) do
    if command then
      local mp, p = command:match("^CLICK TorchBinds(M?)Alt(%d+):LeftButton$")
      if p then
        local slot = (mp == "M" and MALT or ALT) + tonumber(p) - 1
        out[slot] = out[slot] or {}
        table.insert(out[slot], k)
      else
        for first, prefix in pairs(BAR_COMMAND) do
          local n = command:match("^" .. prefix .. "(%d+)$")
          if n then
            local slot = first + tonumber(n) - 1
            out[slot] = out[slot] or {}
            table.insert(out[slot], k)
          end
        end
      end
    end
  end
  for _, keys in pairs(out) do table.sort(keys, function(a, b) if #a ~= #b then return #a < #b end return a < b end) end
  return out
end
ns.keysBySlot = keysBySlot

local function map()
  local layout = classLayout()
  if not layout then say("No layout for this class yet.") return end
  local ctx, keys = context(true), keysBySlot()
  say("preset: " .. PRESETS[presetName()].label .. "  (grey = not yours yet)")
  local title = { [MAIN] = "Left hand", [SHIFT] = "Left hand + Shift", [MOUSE] = "Mouse thumb (1 to 5 are also the pad's top row)", [MSHIFT] = "Mouse thumb + Shift" }
  for _, first in ipairs({ MAIN, SHIFT, MOUSE, MSHIFT }) do
    print(" |cff9d9d9d" .. title[first] .. "|r")
    local parts = {}
    local onMouse = first == MOUSE or first == MSHIFT
    for n = 1, 12 do
      local i = onMouse and GRID_POS[n] or n -- the mouse bars are listed thumb 1 to 12, not in bar order
      local entry = (layout.fixed[first] or {})[i]
      local slot = first + i - 1
      if entry and keys[slot] then
        local desc, label = resolve(entry, ctx)
        local shown = {}
        for n = 1, math.min(first == MOUSE and 2 or 1, #keys[slot]) do shown[n] = prettyKey(keys[slot][n]) end
        parts[#parts + 1] = "|cffffd35a" .. table.concat(shown, " / ") .. "|r " .. (desc and desc.label or ("|cff808080" .. tostring(label) .. "|r"))
      end
    end
    for i = 1, #parts, 4 do print("  " .. table.concat(parts, "   ", i, math.min(i + 3, #parts))) end
  end
  print("  |cffffd35aTab / wheel click|r next enemy   |cffffd35aShift+Tab|r set focus   |cffffd35aCtrl+Tab|r target focus   |cffffd35amiddle-click a frame|r decurse")
end

-- EVENTS --------------------------------------------------------------------
local applyTries, pending, dumpQueued = 0, false, false
local layoutPending, upkeepQueued = false, false

local function queueDump(reason, delay)
  if dumpQueued then return end
  dumpQueued = true
  C_Timer.After(delay or 3, function() dumpQueued = false pcall(dump, reason) end)
end

local function tryApply(force)
  if TorchBindsDB.off then return end
  if not force and TorchBindsDB.appliedVersion == LAYOUT_VERSION then return end -- already applied: leave manual changes alone
  local state = applyBinds()
  if state == "ok" then
    if TorchBindsDB.appliedVersion == LAYOUT_VERSION then say("Keybinds applied. Type /torch for options.") end
    queueDump("binds", 1)
  elseif state == "combat" then
    pending = true
  elseif applyTries < 30 then
    applyTries = applyTries + 1
    C_Timer.After(1, function() tryApply(force) end)
  else
    note("binds", "binding set never became 1 or 2, last value " .. tostring(TorchBindsDB.bindSetSeen))
  end
end

-- first login on a new layout version: apply it once. Afterwards only upkeep runs.
local function tryLayout()
  if TorchBindsDB.off or TorchBindsDB.layoutVersion == LAYOUT_VERSION then return end
  if InCombatLockdown() then layoutPending = true return end
  if not classLayout() then TorchBindsDB.layoutVersion = LAYOUT_VERSION return end
  if next(spellIndex()) == nil then -- spellbook not loaded yet
    C_Timer.After(2, tryLayout)
    return
  end
  if not barsServing() then -- arranged bars reading all empty: a cold login's dead bar system
    C_Timer.After(2, tryLayout)
    return
  end
  local ok, err = pcall(setup, true)
  if not ok then note("setup failed", err) end
  if ok and TorchBindsDB.layoutVersion ~= LAYOUT_VERSION then
    -- setup saw the client refuse placements and recorded nothing: run it again from the top
    C_Timer.After(5, tryLayout)
    return
  end
  -- the first time, also draw the bars to match: mouse blocks shaped like the mouse
  if ok and ns.Look and TorchBindsDB.look == nil and TorchBindsDB.layoutVersion == LAYOUT_VERSION then
    local result = ns.Look.Apply("devices")
    if result == "ok" then say("Your two mouse bars are now blocks above your bars, shaped like your thumb buttons. /torch look corner or /torch look off changes that.")
    else TorchBindsDB.look = "none" note("look", result) end
  elseif ok and ns.Look then
    ns.Look.Refresh() -- a look applied by an older version gets the current positions
  end
end

local function queueUpkeep(quiet)
  if upkeepQueued then return end
  upkeepQueued = true
  C_Timer.After(2, function()
    upkeepQueued = false
    if InCombatLockdown() then layoutPending = true return end
    local ok, err = pcall(upkeep, quiet)
    if not ok then note("upkeep failed", err) end
  end)
end

local frame = CreateFrame("Frame")
-- The talent events: Forever fires whichever of these its own talent frame uses, so all of them
-- are asked for and an unknown name is simply skipped.
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP",
                      "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
                      "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
  pcall(frame.RegisterEvent, frame, ev) -- pcall: an unknown event name throws
end
frame:SetScript("OnEvent", function(_, event, isLogin, isReload)
  TorchBindsDB = TorchBindsDB or {}
  if event == "PLAYER_ENTERING_WORLD" then
    if isLogin or isReload then
      TorchBindsDB.log = {}
      applyTries = 0
      C_Timer.After(3, function() tryApply(false) end) -- after the game has loaded its own bindings
      C_Timer.After(7, function() pcall(repairBinds) end)
      C_Timer.After(8, function() pcall(recruitMacros) end)
      C_Timer.After(5, tryLayout)
      queueDump("login", 9)
      pcall(hookBags)
      if ns.Stats then pcall(ns.Stats.Init) end
      if ns.Alert then pcall(ns.Alert.Init) end
      if ns.Curse then pcall(ns.Curse.Init) end
      if ns.Look then C_Timer.After(6, function() pcall(ns.Look.Captions) end) end
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pending then pending = false tryApply(false) end
    if specPending then specPending = false pcall(respec) queueUpkeep() end
    pcall(repairBinds)
    if layoutPending then
      layoutPending = false
      if TorchBindsDB.layoutVersion == LAYOUT_VERSION then queueUpkeep() else tryLayout() end
    end
    if bagFixPending then bagFixPending = false fixBags() end
  elseif event == "BAG_UPDATE_DELAYED" then
    queueUpkeep(true) -- a better potion, a new scroll, the last bandage used
  elseif TALENT_EVENT[event] then
    -- Spending or wiping points. Only act when the tree it adds up to has actually changed,
    -- because these fire on every single point.
    if layoutStale() or TorchBindsDB.specApplied ~= ((classLayout() or {}).spec or "core") then
      if InCombatLockdown() then specPending = true else pcall(respec) queueUpkeep() end
    end
  else
    queueUpkeep() -- trained something: new spells and new ranks go onto the bars
    queueDump(event, 5)
  end
end)

SLASH_TORCHBINDS1 = "/torch"
SlashCmdList["TORCHBINDS"] = function(input)
  local raw = strtrim(input or "")
  local cmd, rest = raw:match("^(%S*)%s*(.-)$")
  cmd, rest = strlower(cmd), strlower(rest)
  TorchBindsDB = TorchBindsDB or {}
  if cmd == "setup" then
    TorchBindsDB.off = nil
    local ok, err = pcall(setup)
    if not ok then note("setup failed", err) say("Setup stopped part way: " .. tostring(err) .. ". /torch undo puts everything back.") end
  elseif cmd == "undo" then undo()
  elseif cmd == "map" then map()
  elseif cmd == "stats" then
    if ns.Stats then ns.Stats.Command(rest) else say("The stats part of the addon did not load.") end
  elseif cmd == "coach" then
    if ns.Coach then ns.Coach.Command(rest) else say("The coach part of the addon did not load. Quit the game fully and start it again.") end
  elseif cmd == "curse" or cmd == "curses" then
    if ns.Curse then ns.Curse.Command(rest) else say("The curse caller did not load. Quit the game fully and start it again.") end
  elseif cmd == "rested" or cmd == "rest" or cmd == "xp" then
    if ns.restedCommand then ns.restedCommand(rest) else say("The rested experience part of the addon did not load. Quit the game fully and start it again.") end
  elseif cmd == "panel" then
    if ns.panelCommand then ns.panelCommand(rest) else say("The panel did not load. Quit the game fully and start it again.") end
  elseif cmd == "spec" then
    local spec, points = ns.specOf()
    say(spec and ("Your tree is " .. spec .. ", " .. points .. " points in. The spells follow it; the keys never move.")
               or ("No tree yet (" .. tostring(points) .. " points): you are on the levelling set."))
  elseif cmd == "alert" or cmd == "alerts" then
    if ns.Alert then ns.Alert.Command(rest) else say("The alerts part of the addon did not load. Quit the game fully and start it again.") end
  elseif cmd == "hoverfocus" then
    if InCombatLockdown() then say("You are in combat. Try again after the fight.") return end
    TorchBindsDB.hoverFocus = (rest == "on") or nil
    if TorchBindsDB.hoverFocus then ensureMacro(FOCUS_MACRO, MACROS[FOCUS_MACRO]) end
    applyTries = 0
    tryApply(true)
    say(TorchBindsDB.hoverFocus and "Set focus now takes whoever your mouse is over, without changing your target. With the mouse over nobody it focuses your target." or "Set focus is back to focusing your target.")
  elseif cmd == "hovercs" then
    if InCombatLockdown() then say("You are in combat. Try again after the fight.") return end
    TorchBindsDB.hoverCS = (rest == "on") or nil
    local name = stopName("Counterspell")
    if (try(GetMacroIndexByName, name) or 0) > 0 then ensureMacro(name, stopBody("Counterspell")) end
    say(TorchBindsDB.hoverCS and "Counterspell now goes to an enemy under your mouse first, then your target. Shift still sends it to your focus." or "Counterspell is back to your target only.")
  elseif cmd == "look" then
    if ns.Look then ns.Look.Command(rest) else say("The looks part of the addon did not load. Quit the game fully and start it again.") end
  elseif cmd == "preset" then
    if PRESETS[rest] then
      TorchBindsDB.preset = rest
      applyTries = 0
      TorchBindsDB.off = nil
      tryApply(true)
      say("Preset: " .. PRESETS[rest].label .. ". " .. PRESETS[rest].about)
    else
      say("presets (you are on |cffffffff" .. presetName() .. "|r):")
      for name, preset in pairs(PRESETS) do print("  |cffffd35a/torch preset " .. name .. "|r  " .. preset.label .. ". " .. preset.about) end
    end
  elseif cmd == "decurse" then
    local result, how = clickCast()
    TorchBindsDB.clickCast = result
    say(result == "ok" and ("To decurse: " .. how .. " a party, raid or player frame.") or ("Click to decurse: " .. result .. ". The Decurse key still works on whoever the mouse is over."))
  elseif cmd == "binds" or cmd == "on" then
    TorchBindsDB.off = nil
    applyTries = 0
    tryApply(true)
  elseif cmd == "dump" then
    dump("manual")
    say("Recorded " .. #(TorchBindsDB.spells or {}) .. " spells. Type /reload to save the file.")
  elseif cmd == "bagfix" and rest == "off" then
    TorchBindsDB.bagFixOff = true
    say("Bag fix off. /reload to bring the gamepad bag bar back.")
  elseif cmd == "bagfix" and rest == "on" then
    TorchBindsDB.bagFixOff = nil
    hookBags()
    say("Bag fix on.")
  elseif cmd == "bags" then
    bagCheck(rest == "fix")
  elseif cmd == "off" then
    TorchBindsDB.off = true
    say("Will not touch your keybinds or bars.")
  else
    say("/torch map = what every key and mouse button does")
    say("/torch stats = what you pressed, clicked and fumbled")
    say("/torch coach = how your last fights went and the one habit to drill")
    say("/torch alert = enemy cast, sheep and who-is-on-you warnings (test, off, on)")
    say("/torch curse = the curse caller: who is cursed, on screen and out loud (test, off, on)")
    say("/torch rested = how much rested experience you have banked, and where to log out (off, on)")
    say("/torch panel = a strip with experience and gold an hour, free bag slots and your worst-worn piece (lock, unlock, reset, report)")
    say("/torch spec = which talent tree the spells are following right now")
    say("/torch preset = switch between Tartarus and keyboard key sets")
    say("/torch look = where the mouse blocks sit: devices (above your bars), corner or off")
    say("/torch setup = force the layout again    /torch undo = put everything back")
    say("/torch decurse = set up click to decurse    /torch binds = re-apply the keybinds")
    say("/torch hoverfocus on = set focus on whoever the mouse is over    /torch hovercs on = Counterspell the enemy under the mouse")
    say("/torch off or /torch on = stop or resume")
  end
end
