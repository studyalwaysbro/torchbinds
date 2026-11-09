-- Offline check of Torch Binds against the real character's saved state.
-- lua tests/run.lua <path to a copy of the character's SavedVariables/TorchBinds.lua>
local svPath = assert(arg[1], "give the SavedVariables file")
dofile(svPath)
local saved = TorchBindsDB
local passed, failed = 0, 0
local function check(c, label) if c then passed = passed + 1 else failed = failed + 1 io.write("FAIL: " .. label .. "\n") end end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local G, ITEM, spellName, runTimers, fire, at, rank, whereIs, press, click = M.G, M.ITEM, M.spellName, M.runTimers, M.fire, M.at, M.rank, M.whereIs, M.press, M.click
local say = io.write
-- The sim's world has to own what the live bars hold, or the forced re-arrange below could not
-- pick these real actions up again: an item on a bar is also in the bags, a bar macro exists,
-- and an off-book spell (a profession) gets its name from the dump.
for key, a in pairs(saved.actions) do
  G.slots[tonumber(key:sub(2))] = { kind = a.kind, id = a.id, text = a.kind == "macro" and a.text or nil }
  if a.kind == "item" and not G.bags[a.id] then G.bags[a.id] = 1 end
  if a.kind == "macro" and a.text and G.macros[a.text] == nil then G.macros[a.text] = "old" end
  if a.kind == "spell" and a.id and a.name and not spellName[a.id] then spellName[a.id] = a.name end
end
-- The Shift+F square (slot 64) holds whatever the live game last had there. The check below
-- needs the OLD premise: an older layout's stray copy of a spell the new layout places on a
-- fixed key. Plant one (Evocation lives on Shift+Z), so the sweep that clears copies is always
-- exercised no matter what the live SV happens to hold at 64.
G.slots[64] = { kind = "spell", id = 12051 }
for _, sp in ipairs(saved.spells) do G.book[sp.slot] = { name = sp.name, spellID = sp.id, itemType = sp.type, isPassive = sp.passive, sub = sp.sub } end
for cmd, keys in pairs(saved.binds) do for key in keys:gmatch("[^ ,]+") do G.binds[key] = cmd end end
G.binds["SHIFT-MOUSEWHEELUP"], G.binds["BUTTON5"], G.binds["CTRL-E"] = "PREVIOUSACTIONPAGE", "MULTIACTIONBAR1BUTTON2", "MULTIACTIONBAR3BUTTON7"
for _, name in ipairs({ "Counterspell Ins", "Counterspell Foc", "Poly Focus" }) do G.macros[name] = "old" end
for _, sp in ipairs(saved.spells) do spellName[sp.id] = sp.name end

local FIRST = { ACTIONBUTTON = 1, MULTIACTIONBAR1BUTTON = 61, MULTIACTIONBAR2BUTTON = 49, MULTIACTIONBAR3BUTTON = 25, MULTIACTIONBAR4BUTTON = 37,
                MULTIACTIONBAR5BUTTON = 145, MULTIACTIONBAR6BUTTON = 157, MULTIACTIONBAR7BUTTON = 169 }
local BUTTON = { ACTIONBUTTON = "ActionButton", MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton", MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton",
                 MULTIACTIONBAR3BUTTON = "MultiBarRightButton", MULTIACTIONBAR4BUTTON = "MultiBarLeftButton",
                 MULTIACTIONBAR5BUTTON = "MultiBar5Button", MULTIACTIONBAR6BUTTON = "MultiBar6Button", MULTIACTIONBAR7BUTTON = "MultiBar7Button" }
-- the bar slot a key presses, and what is in it
local function slotOf(key)
  local command = G.binds[key]
  if not command then return nil end
  local mp, cp = command:match("^CLICK TorchBinds(M?)Alt(%d+):LeftButton$")
  if cp then return (mp == "M" and 157 or 145) + tonumber(cp) - 1 end
  local prefix, n = command:match("^(%u+%d?%u*)(%d+)$")
  for p, first in pairs(FIRST) do
    local m = command:match("^" .. p .. "(%d+)$")
    if m then return first + tonumber(m) - 1, BUTTON[p], tonumber(m) end
  end
end
local function cast(key) local slot = slotOf(key) return slot and at(slot) or ("<" .. tostring(G.binds[key]) .. ">") end
local function pressKey(key) local _, prefix, i = slotOf(key) press(prefix, i) end
local function clickKey(key) local _, prefix, i = slotOf(key) click(prefix, i) end

local function load()
  local ns = {}
  -- one client, one copy of the addon: nothing from the last load keeps listening
  for i = #M.frames, 1, -1 do M.frames[i] = nil end
  G.tickers, G.timers = {}, {}
  TryUseActionButton = function() end
  for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton",
                            "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
    for i = 1, 12 do _G[prefix .. i].scripts = {} end
  end
  for _, file in ipairs({ "TorchBinds.lua", "Stats.lua", "Coach.lua", "Alert.lua", "Curse.lua", "Look.lua", "Rested.lua", "Panel.lua" }) do assert(loadfile(file))("TorchBinds", ns) end
  return ns
end
local original = {}
for slot = 1, 180 do original[slot] = at(slot) end
-- STALE-PREMISE GUARD: the live SV may already be on the current layout version (the real
-- character has logged in with this build since this suite was written), which would turn the
-- "first login on the new version" below into a silent no-op and leave every ALT-layer secure
-- button empty. Force the recorded version down one so the upgrade path is always exercised,
-- and drop the live undo/bindsBefore records so the sim's forced setup records its own:
-- section 8 measures undo against the state THIS file loaded, not against the real character's
-- bars from launch day.
saved.layoutVersion = saved.layoutVersion and (saved.layoutVersion - 1)
saved.undo, saved.bindsBefore = nil, nil
-- the sim plays the character the SV describes; the racial keys depend on it
G.race = (saved.character and saved.character.race) or G.race
TorchBindsDB = saved
local ns = load()

-- 1. first login on the new version: the whole layout is applied by itself --------------
fire("PLAYER_ENTERING_WORLD", true, false)
eq(TorchBindsDB.layoutVersion, 12, "layout version recorded")
eq(TorchBindsDB.appliedVersion, 12, "binds version recorded")
eq(#(TorchBindsDB.log or {}), 0, "nothing went wrong: " .. table.concat(TorchBindsDB.log or {}, " | "))
if arg[2] == "dump" then
  local keys = {}
  for key in pairs(G.binds) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local slot = slotOf(key)
    io.write(string.format("%-18s %-28s %s\n", key, tostring(G.binds[key]), slot and at(slot) or ""))
  end
  os.exit(0)
end
local KEYMAP = {
  -- left hand
  Q = "Frost Nova", E = "Frostbolt", R = "Ice Lance!", F = "Blink!", Z = "Fire Blast!", X = "Ice Block!", C = "Shoot",
  ["SHIFT-E"] = "Scorch", ["SHIFT-R"] = "Fireball R1", ["SHIFT-Z"] = "Evocation", ["SHIFT-X"] = "Cold Snap", ["SHIFT-C"] = "Mana Gem",
  UP = "Health Pot", DOWN = "Conjured Pumpernickel", LEFT = "Conjured Spring Water", RIGHT = "Bandage Self",
  -- left hand with Alt, the pad key above Shift: the racial, the off-school nuke, the panic kit
  ["ALT-Q"] = "Free Me", ["ALT-E"] = "Fireball", ["ALT-Z"] = "Mana Shield", ["ALT-X"] = "Trinkets", ["ALT-C"] = "Decurse",
  ["ALT-DOWN"] = "Conjure Food", ["ALT-LEFT"] = "Conjure Water", ["ALT-RIGHT"] = "Conjure Mana Agate",
  -- mouse thumb grid (1 to 5 are also the pad's top row)
  ["1"] = "Poly Focus", ["2"] = "Cone of Cold!", ["3"] = "Arcane Explosion", ["4"] = "Counterspell!", ["5"] = "Blizzard", ["6"] = "Arcane Missiles",
  ["7"] = "Frost Ward", ["8"] = "Fire Ward", ["0"] = "Flamestrike", ["-"] = "Frostbolt R1",
  ["SHIFT-1"] = "Polymorph", ["SHIFT--"] = "Scroll of Cryoblast", ["SHIFT-3"] = "Remove Lesser Curse", ["SHIFT-4"] = "Counterspell Foc", ["SHIFT-5"] = "Shield Off",
  ["SHIFT-6"] = "Feed", ["SHIFT-7"] = "Slow Fall", ["SHIFT-0"] = "Ice Armor", ["SHIFT-="] = "Hearthstone",
  ["ALT-1"] = "Poly Over", ["ALT-2"] = "CS Mouseover", ["ALT-3"] = "Arcane Intellect", ["ALT-5"] = "Dampen Magic", ["ALT-6"] = "Amplify Magic",
  BUTTON4 = "Poly Focus", BUTTON5 = "Counterspell!", ["SHIFT-BUTTON4"] = "Polymorph", ["SHIFT-BUTTON5"] = "Counterspell Foc",
  ["ALT-BUTTON4"] = "Poly Over",
}
for key, spell in pairs(KEYMAP) do eq(cast(key), spell, "key " .. key) end
-- thumb 9 and Shift + thumb 8 are the pool's first two squares: what lands there depends on what
-- you know, but they must never sit empty while anything is waiting for a button.
for _, key in ipairs({ "9", "SHIFT-8" }) do
  local slot = slotOf(key)
  check(slot and at(slot) ~= "-", "the pool filled the bound square on " .. key .. " (slot " .. tostring(slot) .. ")")
end
eq(cast("="), "-", "thumb 12 waits for a mount")
eq(at(64), "-", "the Shift+F square is empty: the old layout's copy there was cleared")
eq(G.macros["Poly Focus"], "#showtooltip Polymorph\n/cast [@focus,exists,harm,nodead] Polymorph; Polymorph", "thumb 1 sheeps the focus if there is one, otherwise the target")
check(not whereIs("Scroll of Cryoblast") or whereIs("Scroll of Cryoblast") == slotOf("SHIFT--"), "Cryoblast has its key and is not listed twice")
for _, key in ipairs({ "SHIFT-F", "SHIFT-Q", "SHIFT-9", "CTRL-E", "CTRL-Q", "SHIFT-MOUSEWHEELUP" }) do eq(G.binds[key], nil, key .. " is unbound") end
eq(G.binds.TAB, "TARGETNEARESTENEMY", "Tab targets") eq(G.binds["SHIFT-BUTTON3"], "FOCUSTARGET", "Shift + wheel click sets focus")
SlashCmdList["TORCHBINDS"]("hoverfocus on") runTimers()
eq(G.binds["SHIFT-BUTTON3"], "MACRO Focus Hover", "hover focus, when asked for, binds the macro")
eq(G.macros["Focus Hover"], "/focus [@mouseover,exists,nodead][]", "the focus macro falls back to your target")
SlashCmdList["TORCHBINDS"]("hoverfocus off") runTimers()
SlashCmdList["TORCHBINDS"]("hovercs on") runTimers()
eq(G.macros["Counterspell!"], "#showtooltip Counterspell\n/stopcasting\n/cast [@mouseover,harm,nodead][] Counterspell", "hovercs on: Counterspell takes the enemy under the mouse, then the target")
fire("SPELLS_CHANGED")
check(G.macros["Counterspell!"]:find("@mouseover", 1, true), "and upkeep does not undo it")
check(not G.macros["Ice Lance!"]:find("@mouseover", 1, true), "other cast-cancelling keys are untouched")
SlashCmdList["TORCHBINDS"]("hovercs off") runTimers()
eq(G.macros["Counterspell!"], "#showtooltip Counterspell\n/stopcasting\n/cast Counterspell", "hovercs off: back to the target only")
G.combat = true
SlashCmdList["TORCHBINDS"]("hovercs on")
check(not TorchBindsDB.hoverCS and not G.macros["Counterspell!"]:find("@mouseover", 1, true), "it is not switched in combat")
G.combat = false
eq(G.binds["SHIFT-BUTTON3"], "FOCUSTARGET", "and off puts the plain bind back") eq(G.binds.BUTTON3, "TARGETNEARESTENEMY", "wheel click targets")
-- each bar is one device, in the order the keys sit
local function row(first, n) local t = {} for i = 0, (n or 12) - 1 do t[#t + 1] = at(first + i) end return table.concat(t, " | ") end
-- the mouse bars fill from the bottom row up, so the bar is stored bottom row first and DRAWN with 1 2 3 on top
eq(row(25), "Flamestrike | Frostbolt R1 | - | Frost Ward | Fire Ward | Teleport: Thunder Bluff | Counterspell! | Blizzard | Arcane Missiles | Poly Focus | Cone of Cold! | Arcane Explosion", "the mouse bar is stored bottom row first")
local drawn = {}
for r = 3, 0, -1 do drawn[#drawn + 1] = row(25 + r * 3, 3) end
eq(table.concat(drawn, " / "), "Poly Focus | Cone of Cold! | Arcane Explosion / Counterspell! | Blizzard | Arcane Missiles / Frost Ward | Fire Ward | Teleport: Thunder Bluff / Flamestrike | Frostbolt R1 | -", "on screen the block reads like the mouse: 1 2 3 on the top row")
eq(row(1, 7), "Frost Nova | Frostbolt | Ice Lance! | Blink! | Fire Blast! | Ice Block! | Shoot", "the main bar reads Q E R F Z X C")
eq(row(9, 4), "Health Pot | Conjured Pumpernickel | Conjured Spring Water | Bandage Self", "then the thumb pad")
-- macros say what they should
for name, needle in pairs({ ["Ice Lance!"] = "/stopcasting\n/cast Ice Lance", ["Cone of Cold!"] = "/stopcasting\n/cast Cone of Cold", ["Fire Blast!"] = "/stopcasting\n/cast Fire Blast",
                            ["Counterspell!"] = "/stopcasting\n/cast Counterspell", ["Bandage Self"] = "/use [@player] item:3531", ["Health Pot"] = "/use item:929",
                            ["Frostbolt R1"] = "/cast Frostbolt(Rank 1)", ["Fireball R1"] = "/cast Fireball(Rank 1)", ["Decurse"] = "@mouseover,help", ["Mana Gem"] = "/use item:5514" }) do
  check(G.macros[name] and G.macros[name]:find(needle, 1, true), "macro " .. name .. " does its job")
end
-- every castable spell he knows is on a bar somewhere. The layout's own ignore list is the
-- one exception: those are spells a later spell fully replaces (Frost Armor under Ice Armor,
-- the lesser conjured gems), and the addon promises them no button on purpose.
local ignored = (ns.classLayout() and ns.classLayout().ignore) or {}
local missing = {}
for _, sp in ipairs(saved.spells) do
  if not sp.passive and not ignored[sp.name] and sp.type == 1 then
    local found = whereIs(sp.name)
    for name, body in pairs(G.macros) do if not found and body:find(sp.name, 1, true) and whereIs(name) then found = true end end
    if not found and not missing[sp.name] then missing[sp.name] = true missing[#missing + 1] = sp.name end
  end
end
eq(#missing, 0, "every spell you know has a home (missing: " .. table.concat(missing, ", ") .. ")")
-- Every square the click-bar pool can use: the two bound ones that come first (the mouse's
-- thumb 9 at slot 30 and Shift + thumb 8 at slot 41), Bottom Right, the tail of the Shift bar,
-- the spare pad squares, Alt + thumb 9 to 12, and Action Bar 8.
local function onClickBars(slot)
  return slot and (slot == 30 or slot == 41 or (slot >= 49 and slot <= 60) or (slot >= 68 and slot <= 72)
                   or slot == 8 or slot == 152 or (slot >= 157 and slot <= 168) or (slot >= 169 and slot <= 180))
end
-- These have a key of their own now: the Alt layer took the buffs, the armours and the conjures.
for _, key in ipairs({ "ALT-3", "SHIFT-0", "ALT-LEFT", "ALT-DOWN", "ALT-RIGHT" }) do
  check(slotOf(key) ~= nil and at(slotOf(key)) ~= "-", "Alt and Shift layer key " .. key .. " carries something")
end
-- and everything with no fixed home still lands somewhere you can reach
for _, name in ipairs({ "Scroll of Polymorph: Odd Melon", "Scroll of Confuse Beast", "Scroll of Imbue Frost", "Scroll of Protection II",
                        "Teleport: Thunder Bluff", "Teleport: Undercity" }) do
  local slot = whereIs(name)
  check(onClickBars(slot) or (slot and slot >= 157 and slot <= 168), name .. " has a home (slot " .. tostring(slot) .. ")")
end
check(not whereIs("Counterspell Ins"), "the old Counterspell macro is gone from the bars")
check(not whereIs("Mana Agate"), "the loose mana gem item is gone from the bars")
check(G.saves > 0, "bindings saved")
eq(TorchBindsDB.clickCast, "ok", "click casting set up")
say("after setup:\n  main    " .. row(1) .. "\n  shift   " .. row(61) .. "\n  mouse   " .. row(25) .. "\n  m+shift " .. row(37) .. "\n  click   " .. row(49) .. "\n")
say("  said: " .. table.concat(G.printed, "\n        ") .. "\n")

-- 1b. the look: NOTHING is written to Edit Mode — the 11-04 launch build wiped the
--     account's layouts on SaveLayouts, so the bars are pinned straight onto the frames
eq(#G.edit.layouts, 0, "and no Edit Mode layout is ever written")
local function pinOf(name) return _G[name].point end
if saved.look == "off" then
  -- the character turned the look off; an upgrade must not drag his bars around
  eq(TorchBindsDB.look, "off", "a look you turned off is honored through the upgrade")
  eq(pinOf("MultiBar5"), nil, "so no row is pinned until you ask")
else
  eq(TorchBindsDB.look, "devices", "the devices look is applied on the first run")
end
SlashCmdList["TORCHBINDS"]("look devices")
eq(TorchBindsDB.look, "devices", "look devices applies on request")
eq(pinOf("MultiBar5") and pinOf("MultiBar5").to, "MultiBarRight", "the Alt pad row is pinned above the mouse block")
eq(pinOf("MultiBar5").point, "BOTTOMLEFT", "by its bottom left corner")
eq(pinOf("MultiBar6") and pinOf("MultiBar6").to, "MultiBar5", "the Alt thumb row stacks on the pad row")
eq(pinOf("MultiBar7") and pinOf("MultiBar7").to, "MultiBar6", "action bar 8 rides on top while it is switched on")
MultiBar7.shown = false MultiBar7.point = nil
SlashCmdList["TORCHBINDS"]("look devices")
eq(pinOf("MultiBar7"), nil, "a hidden action bar 8 is left alone")
MultiBar7.shown = true
SlashCmdList["TORCHBINDS"]("look corner")
eq(TorchBindsDB.look, "corner", "corner look selected")
eq(#G.edit.layouts, 0, "corner writes nothing to Edit Mode either")
SlashCmdList["TORCHBINDS"]("look off")
eq(TorchBindsDB.look, "off", "and remembers you turned it off")
G.combat = true
SlashCmdList["TORCHBINDS"]("look devices")
eq(TorchBindsDB.look, "off", "no look change in combat")
G.combat = false
SlashCmdList["TORCHBINDS"]("look devices") SlashCmdList["TORCHBINDS"]("look") SlashCmdList["TORCHBINDS"]("look nonsense")
eq(TorchBindsDB.look, "devices", "devices on again")

-- a look applied by an older version is restamped at login, still without Edit Mode
TorchBindsDB.lookVersion, TorchBindsDB.layoutVersion = 1, 9
fire("PLAYER_ENTERING_WORLD", true, false)
check(TorchBindsDB.lookVersion > 1, "an older look is restamped by itself")
eq(#G.edit.layouts, 0, "and still nothing is written to Edit Mode")

-- 2. second login: nothing moves, and a key you changed stays changed --------------------------
local calls = G.placeCalls
fire("PLAYER_ENTERING_WORLD", true, false)
eq(G.placeCalls, calls, "a second login places nothing")
local zSlot = slotOf("Z")
G.slots[zSlot] = { kind = "spell", id = 12051 }
fire("PLAYER_ENTERING_WORLD", true, false) fire("SPELLS_CHANGED")
eq(cast("Z"), "Evocation", "a key you changed yourself is left alone")
G.slots[zSlot] = { kind = "macro", id = 1, text = "Fire Blast!" }

-- 3. training ------------------------------------------------------------------------------------
G.book[200] = { name = "Frostbolt", spellID = 8407, itemType = 1 } spellName[8407] = "Frostbolt"
G.book[201] = { name = "Ice Barrier", spellID = 11426, itemType = 2 } spellName[11426] = "Ice Barrier" -- shown in the book but not learned
G.book[202] = { name = "Detect Magic", spellID = 2855, itemType = 1 } spellName[2855] = "Detect Magic"
G.book[203] = { name = "Brand New Forever Spell", spellID = 999001, itemType = 1 } spellName[999001] = "Brand New Forever Spell"
fire("SPELLS_CHANGED")
eq(rank(slotOf("E")), 8407, "E got the new Frostbolt rank")
eq(cast("ALT-Z"), "Mana Shield", "a spell only shown in the book is not treated as learned")
check(whereIs("Detect Magic"), "a newly learned utility spell is added to the click buttons")
check(whereIs("Brand New Forever Spell"), "a spell this addon has never heard of is still put on a bar")
G.book[201].itemType = 1
fire("SPELLS_CHANGED")
eq(cast("ALT-Z"), "Ice Barrier", "Ice Barrier takes over the Mana Shield key when you learn it")
-- Mana Shield does not lose its button when Ice Barrier arrives: the Shield Off macro on
-- Shift + thumb 5 still casts it, and cancels it, which is the only reason that key exists.
eq(cast("SHIFT-5"), "Shield Off", "Mana Shield still has a key: the Shield Off macro")
check(G.macros["Shield Off"]:find("/cast Mana Shield", 1, true), "and that macro really does cast Mana Shield")
check(G.macros["Shield Off"]:find("/cancelaura Mana Shield", 1, true), "and cancels it on a second press")
G.book[204] = { name = "Arcane Intellect", spellID = 10156, itemType = 1 } spellName[10156] = "Arcane Intellect"
local aiSlot = whereIs("Arcane Intellect")
fire("SPELLS_CHANGED")
eq(rank(aiSlot), 10156, "a click-bar buff gets its new rank too")

-- 4. loot ------------------------------------------------------------------------------------------
G.bags[1710] = 2
fire("BAG_UPDATE_DELAYED")
check(G.macros["Health Pot"]:find("item:1710", 1, true), "the potion key now drinks the better potion")
G.bags[3928] = 1
fire("BAG_UPDATE_DELAYED")
check(G.macros["Health Pot"]:find("item:1710", 1, true), "a potion above your level is not chosen")
G.bags[900001] = 1
fire("BAG_UPDATE_DELAYED")
check(G.macros["Health Pot"]:find("item:900001", 1, true), "a new Forever potion the addon has never seen wins by its level")
G.bags[900002] = 1
fire("BAG_UPDATE_DELAYED")
check(G.macros["Health Pot"]:find("item:900001", 1, true), "and one above your level does not")
G.bags[3827], G.bags[4390], G.bags[6450] = 5, 3, 4
fire("BAG_UPDATE_DELAYED")
eq(cast("SHIFT-9"), "Mana Potion", "a mana potion fills Shift + thumb 9 and the key is bound")
eq(cast("SHIFT--"), "Scroll of Cryoblast", "a Cryoblast scroll outranks a grenade on the burst key")
G.bags[217495] = nil
fire("BAG_UPDATE_DELAYED")
eq(cast("SHIFT--"), "Iron Grenade", "with no scroll left the grenade takes the key")
check(G.macros["Bandage Self"]:find("item:6450", 1, true), "the bandage macro moves up to silk")
G.bags[5655], G.level = 1, 40
fire("BAG_UPDATE_DELAYED")
eq(cast("="), "Mount", "the mount lands on thumb 12 the day you own one")
G.bags[1114] = 0 G.bags[1487] = 20
fire("BAG_UPDATE_DELAYED")
eq(cast("DOWN"), "Conjured Pumpernickel", "better conjured food replaces the old")
G.bags[5514] = nil
fire("BAG_UPDATE_DELAYED")
check(G.macros["Mana Gem"]:find("item:5514", 1, true), "with no gem in the bag the button still shows the gem you can conjure")

-- 5. combat ------------------------------------------------------------------------------------------
G.book[205] = { name = "Frostbolt", spellID = 8408, itemType = 1 } spellName[8408] = "Frostbolt"
G.combat = true
fire("PLAYER_REGEN_DISABLED") fire("SPELLS_CHANGED") fire("BAG_UPDATE_DELAYED")
eq(rank(slotOf("E")), 8407, "no bar change in combat")
for _, cmd in ipairs({ "setup", "undo", "decurse", "binds", "preset keyboard", "look corner", "map" }) do
  check(pcall(SlashCmdList["TORCHBINDS"], cmd), "/torch " .. cmd .. " in combat does not error") runTimers()
end
eq(rank(slotOf("E")), 8407, "and no command changes the bars in combat")
G.combat = false
fire("PLAYER_REGEN_ENABLED")
eq(rank(slotOf("E")), 8408, "caught up after combat")

-- 6. presets ------------------------------------------------------------------------------------------
SlashCmdList["TORCHBINDS"]("preset keyboard") runTimers()
eq(TorchBindsDB.preset, "keyboard", "preset saved")
eq(cast("CTRL-Q"), "Arcane Missiles", "keyboard preset: Ctrl+Q is what thumb 6 is")
eq(cast("CTRL-1"), "Feed", "keyboard preset: Ctrl+1 is what Shift + thumb 6 is")
eq(cast("E"), "Frostbolt", "the main keys are the same in every preset")
SlashCmdList["TORCHBINDS"]("preset xaryu") runTimers()
for key, spell in pairs({ ["3"] = "Frostbolt", TAB = "Frost Nova", ["1"] = "Cone of Cold!", ["5"] = "Fireball R1", BUTTON5 = "Fire Blast!", BUTTON4 = "Ice Block!",
                          MOUSEWHEELDOWN = "Poly Focus", V = "Counterspell!", ["SHIFT-3"] = "Mana Gem", ["SHIFT-BUTTON4"] = "Cold Snap", ["ALT-1"] = "Slow Fall",
                          ["2"] = "Arcane Explosion", ["4"] = "Blizzard" }) do
  eq(cast(key), spell, "xaryu preset: " .. key)
end
SlashCmdList["TORCHBINDS"]("preset thumbmove") runTimers()
eq(G.binds["UP"], "MOVEFORWARD", "thumb preset: the pad walks")
for key, spell in pairs({ W = "Counterspell!", A = "Poly Focus", S = "Cone of Cold!", D = "Arcane Explosion" }) do eq(cast(key), spell, "thumb preset: " .. key) end
eq(G.binds["MOUSEWHEELDOWN"], "CAMERAZOOMOUT", "leaving the xaryu preset gives the wheel back to the camera")
eq(G.binds["V"], "NAMEPLATES", "and V back to nameplates")
SlashCmdList["TORCHBINDS"]("preset tartarus") runTimers()
eq(G.binds["W"], "MOVEFORWARD", "back on the tartarus preset W walks again")
eq(cast("UP"), "Health Pot", "and the pad is consumables again")
eq(G.binds["TAB"], "TARGETNEARESTENEMY", "and Tab targets")
eq(G.binds["CTRL-Q"], nil, "and Ctrl is unbound again")
SlashCmdList["TORCHBINDS"]("preset") SlashCmdList["TORCHBINDS"]("preset nonsense")
for name, preset in pairs(ns.PRESETS) do
  local w = {} preset.apply(w)
  check(w["E"] ~= nil and type(preset.label) == "string" and type(preset.about) == "string", "preset " .. name .. " is complete")
end

-- 7. stats ----------------------------------------------------------------------------------------------
SlashCmdList["TORCHBINDS"]("stats reset")
check(table.concat(ns.Stats.Report("tartarus"), "\n"):find("Nothing recorded yet", 1, true), "empty stats say so")
fire("PLAYER_REGEN_DISABLED")
for _ = 1, 30 do pressKey("E") end
for _ = 1, 8 do pressKey("E") fire("UI_ERROR_MESSAGE", 50, "Can't do that while moving") end
for _ = 1, 4 do pressKey("2") fire("UI_ERROR_MESSAGE", 51, "Out of range.") end
for _ = 1, 2 do pressKey("E") fire("UI_ERROR_MESSAGE", 52, "Inventory is full.") end
for _ = 1, 6 do clickKey("Q") end
for _ = 1, 25 do pressKey("SHIFT-1") end
for _ = 1, 3 do G.now = G.now + 1 TryUseActionButton(_G["ActionButton2"], true) G.now = G.now + 0.03 TryUseActionButton(_G["ActionButton3"], true) end -- E and R together
for _ = 1, 3 do G.now = G.now + 1 TryUseActionButton({ action = slotOf("4") }, true) G.now = G.now + 0.03 TryUseActionButton({ action = slotOf("7") }, true) end -- thumb 4 and 7
G.slots[20] = nil
for _ = 1, 4 do G.now = G.now + 1 TryUseActionButton({ action = 20 }, true) end
for _ = 1, 5 do fire("UNIT_SPELLCAST_SUCCEEDED", "player") end
for _ = 1, 3 do G.now = G.now + 1 fire("PLAYER_STARTED_MOVING") fire("UNIT_SPELLCAST_INTERRUPTED", "player") end
fire("UNIT_SPELLCAST_SUCCEEDED", "target") fire("UI_ERROR_MESSAGE", 1, nil)
G.now = G.now + 120
fire("PLAYER_REGEN_ENABLED")
local st = TorchBindsDB.stats.presets.tartarus
eq(st.presses, 30 + 8 + 4 + 2 + 25 + 6 + 6 + 4, "key presses counted")
eq(st.clicks, 6, "mouse clicks counted once each") eq(st.clicksCombat, 6, "and marked as in combat")
eq(st.slots["s" .. slotOf("E")].e.moving, 8, "moving errors pinned on Frostbolt")
eq(st.slots["s" .. slotOf("E")].e.other, nil, "an unrelated message is not pinned on a key")
eq(st.slots["s" .. slotOf("2")].e.range, 4, "range errors pinned on Cone of Cold")
eq(st.pairs["2+3"], 3, "E and R together counted as a fumble")
local p4, p7 = slotOf("4"), slotOf("7")
eq(st.pairs[math.min(p4, p7) .. "+" .. math.max(p4, p7)], 3, "thumb 4 and thumb 7 together counted as a fumble")
eq(st.empty, 4, "empty key presses counted") eq(st.cancels.moved, 3, "casts cut short by moving counted") eq(st.fights, 1, "one fight")
local report = table.concat(ns.Stats.Report("tartarus"), "\n")
for _, needle in ipairs({ "Frost Nova x6 (its key is Q)", "pressed while moving", "Frostbolt x8", "out of range", "E and R x3", "thumb 7 and thumb 4 x3", "nothing on it 4 times", "moving 3 times", "Most used", "Polymorph is your number" }) do
  check(report:find(needle, 1, true), "report mentions: " .. needle)
end
check(not ns.Stats.neighbours(slotOf("E"), slotOf("Z")), "E and Z are not neighbours")
check(ns.Stats.neighbours(slotOf("1"), slotOf("2")) and ns.Stats.neighbours(slotOf("6"), slotOf("9")) and ns.Stats.neighbours(slotOf("2"), slotOf("Q")), "neighbours on the pad and on the mouse grid")
check(not ns.Stats.neighbours(slotOf("1"), slotOf("=")), "thumb 1 and thumb 12 are not neighbours")
eq(ns.Stats.reasonFor("You are facing the wrong way!"), "facing", "facing message recognised")
eq(ns.Stats.reasonFor("Spell is not ready yet."), "cooldown", "cooldown message recognised")
G.printed = {}
for _, cmd in ipairs({ "stats", "map", "", "dump", "decurse" }) do SlashCmdList["TORCHBINDS"](cmd) end
local text = table.concat(G.printed, "\n")
check(text:find("mouse 4", 1, true) and text:find("Counterspell", 1, true), "map lists the mouse buttons")
check(text:find("thumb 6", 1, true) and text:find("Left hand", 1, true), "map is grouped by device")
say("  map:\n    " .. table.concat(G.printed, "\n    ", 1, math.min(#G.printed, 40)) .. "\n")

-- 7b. the coach: one fight at a time -----------------------------------------------------------------------
TorchBindsDB.coach = nil
local function fightLines(body, seconds)
  G.printed = {}
  fire("PLAYER_REGEN_DISABLED")
  body()
  G.now = G.now + (seconds or 0)
  fire("PLAYER_REGEN_ENABLED")
  return table.concat(G.printed, "\n")
end
local out = fightLines(function()
  for _ = 1, 10 do pressKey("E") end
  for _ = 1, 3 do clickKey("Q") end
  for _ = 1, 2 do pressKey("E") fire("UI_ERROR_MESSAGE", 50, "Can't do that while moving") end
  pressKey("E") fire("UI_ERROR_MESSAGE", 50, "Spell is not ready yet.")
end)
for _, needle in ipairs({ "Fight, 16 seconds: 13 key presses, 3 clicks.", "Clicked Frost Nova x3 (key: Q).", "Frostbolt did nothing 2 times: pressed while moving." }) do
  check(out:find(needle, 1, true), "coach says: " .. needle .. "\n" .. out)
end
check(not out:find("not ready", 1, true) and not out:find("cooldown", 1, true), "a spell on cooldown is not called a mistake")
eq(#TorchBindsDB.coach.fights, 1, "the fight is remembered")
out = fightLines(function() for _ = 1, 8 do pressKey("E") end end)
check(out:find("Clean fight, 8 seconds: 8 key presses, no clicks.", 1, true) and not out:find("in a row", 1, true), "a clean fight is called clean: " .. out)
out = fightLines(function() for _ = 1, 8 do pressKey("E") end end)
check(out:find("2 fights in a row without a click", 1, true), "two clean fights make a streak: " .. out)
out = fightLines(function() pressKey("E") pressKey("E") end)
eq(out, "", "a two-press scuffle is not a fight") eq(#TorchBindsDB.coach.fights, 3, "and is not remembered")
out = fightLines(function() for _ = 1, 4 do pressKey("E") end G.now = G.now + 6.5 for _ = 1, 4 do pressKey("E") end end)
check(out:find("Longest stretch without a press: 7.5 seconds.", 1, true), "a long pause is mentioned: " .. out)
out = fightLines(function()
  for _ = 1, 6 do pressKey("E") end
  G.now = G.now + 1 TryUseActionButton(_G["ActionButton2"], true) G.now = G.now + 0.03 TryUseActionButton(_G["ActionButton3"], true)
  G.slots[20] = nil
  for _ = 1, 2 do G.now = G.now + 1 TryUseActionButton({ action = 20 }, true) end
  for _ = 1, 2 do G.now = G.now + 1 fire("PLAYER_STARTED_MOVING") fire("UNIT_SPELLCAST_INTERRUPTED", "player") end
end)
for _, needle in ipairs({ "Two neighbouring keys at once, 1 time.", "nothing on it 2 times", "cut your own cast 2 times" }) do
  check(out:find(needle, 1, true), "coach says: " .. needle .. "\n" .. out)
end
check(select(2, out:gsub("\n", "")) <= 3, "never more than a headline and three notes")
G.printed = {}
SlashCmdList["TORCHBINDS"]("coach")
out = table.concat(G.printed, "\n")
check(out:find("Last 5 fights:", 1, true) and out:find("Drill this one: Frost Nova is on Q. You clicked it 3 times lately.", 1, true), "the trend names the habit to drill: " .. out)
SlashCmdList["TORCHBINDS"]("coach off")
out = fightLines(function() for _ = 1, 8 do clickKey("Q") end end)
check(not out:find("Fight", 1, true), "coach off is quiet") eq(#TorchBindsDB.coach.fights, 6, "but still counts")
SlashCmdList["TORCHBINDS"]("coach on")
for _ = 1, 70 do fightLines(function() for _ = 1, 5 do pressKey("E") end end, 3) end
eq(#TorchBindsDB.coach.fights, 60, "sixty fights are kept, no more")
G.printed = {}
SlashCmdList["TORCHBINDS"]("coach")
check(table.concat(G.printed, "\n"):find("Last 10 fights: 0% of your actions were clicks, the same as the ten before.", 1, true), "trend compares with the ten before: " .. table.concat(G.printed, "\n"))
TorchBindsDB.coach = "broken"
check(pcall(SlashCmdList["TORCHBINDS"], "coach reset"), "a damaged coach record does not stop it")

-- 7c. alerts: enemy casts, the sheep, who is on you ----------------------------------------------------
local alert = G.named.TorchBindsAlertFrame
check(alert and #alert.strings == 6, "the alert frame is built at login")
local L = { target = alert.strings[1], targetSpell = alert.strings[2], focus = alert.strings[3], focusSpell = alert.strings[4], sheep = alert.strings[5], onYou = alert.strings[6] }
for name, fs in pairs(L) do check(fs.shown == false, name .. " starts hidden") end
local function tick() for _, fn in ipairs(G.tickers) do fn() end end
TorchBindsDB.alert = nil
G.sounds = {}
G.units.target = { hostile = true, player = true, class = "Priest", guid = "p1", cast = "Greater Heal" }
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
check(L.target.shown and L.target.text == "TARGET CASTING   >   thumb 4", "an enemy cast names the interrupt key: " .. tostring(L.target.text))
check(L.targetSpell.shown and L.targetSpell.text == "Greater Heal", "and the spell")
eq(#G.sounds, 1, "an enemy player casting makes a sound")
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
eq(#G.sounds, 1, "once per cast")
fire("UNIT_SPELLCAST_STOP", "target")
check(not L.target.shown and not L.targetSpell.shown, "the line goes when the cast ends")
G.units.target.player = false
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
check(L.target.shown, "a hostile creature casting is shown") eq(#G.sounds, 1, "without the sound")
fire("UNIT_SPELLCAST_INTERRUPTED", "target")
check(not L.target.shown, "an interrupted cast clears the line")
G.units.target.hostile = false
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
check(not L.target.shown, "a friend casting is ignored")
G.units.target.hostile, G.units.target.shielded = true, true
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
check(not L.target.shown, "a cast that cannot be interrupted is ignored")
G.units.target.shielded = nil
fire("UNIT_SPELLCAST_START", "party1", "c1", 1) fire("UNIT_SPELLCAST_START", "nameplate3", "c1", 1)
check(not L.target.shown and not L.focus.shown, "only the target and the focus are watched")
G.units.target.cast, G.units.target.channel = nil, "Mind Flay"
fire("UNIT_SPELLCAST_CHANNEL_START", "target", "c1", 1)
check(L.target.shown and L.targetSpell.text == "Mind Flay", "a channel counts as a cast")
fire("UNIT_SPELLCAST_CHANNEL_STOP", "target")
G.units.target.channel, G.units.target.cast = nil, "Greater Heal"
G.units.focus = { hostile = true, player = true, class = "Shaman", guid = "s1", cast = "Healing Wave" }
fire("UNIT_SPELLCAST_START", "focus", "c2", 2)
check(L.focus.shown and L.focus.text == "FOCUS CASTING   >   Shift+thumb 4", "the focus line names the focus interrupt key: " .. tostring(L.focus.text))
check(not L.target.shown, "and the target line stays down")
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
check(L.focus.shown and L.target.shown, "two different enemies casting: two lines")
fire("UNIT_SPELLCAST_STOP", "target") fire("UNIT_SPELLCAST_STOP", "focus")
G.units.focus = G.units.target
fire("UNIT_SPELLCAST_START", "focus", "c1", 1) fire("UNIT_SPELLCAST_START", "target", "c1", 1)
check(L.target.shown and not L.focus.shown, "a focus that is also the target gets one line")
fire("UNIT_SPELLCAST_STOP", "target") fire("UNIT_SPELLCAST_STOP", "focus")
fire("UNIT_SPELLCAST_START", "target", "c1", 1) fire("UNIT_SPELLCAST_START", "focus", "c1", 1)
check(L.target.shown and not L.focus.shown, "in either order")
fire("UNIT_SPELLCAST_STOP", "target") fire("UNIT_SPELLCAST_STOP", "focus")
G.units.focus = nil
G.hide.cast = true
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
check(L.target.shown and L.targetSpell.text == G.SECRET, "a hidden spell name still raises the alert and is handed over untouched")
eq(TorchBindsDB.alert.probe.cast, "hidden name", "and the limit is written down")
fire("UNIT_SPELLCAST_STOP", "target")
G.hide.cast = nil
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
G.now = G.now + 13 tick()
check(not L.target.shown, "a line whose cast never ended is cleared after twelve seconds")
G.units.target = { hostile = true, player = true, guid = "p9" }
fire("PLAYER_TARGET_CHANGED")
check(not L.target.shown, "a new target that is not casting shows nothing")
G.units.target.cast = "Fear"
fire("PLAYER_TARGET_CHANGED")
check(L.target.shown and L.targetSpell.text == "Fear", "switching to an enemy already casting shows it")
G.units.target = nil
fire("PLAYER_TARGET_CHANGED")
check(not L.target.shown, "dropping the target clears it")
G.units.target = { hostile = true, player = true, guid = "p1", cast = "Heal" }
G.hide.hostile = true
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
check(not L.target.shown, "when the game hides whether a unit is hostile, nothing is guessed")
eq(TorchBindsDB.alert.probe.hostile, "hidden", "and that is written down")
G.hide.hostile = nil

local polyID
for id, name in pairs(spellName) do if name == "Polymorph" then polyID = id end end
check(polyID, "the fixture knows Polymorph")
G.sounds = {}
G.units.target = { hostile = true, player = true, guid = "w1" }
G.units.focus = { hostile = true, player = true, guid = "p1", auras = { Polymorph = G.now + 20 } }
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", polyID)
tick()
check(L.sheep.shown and L.sheep.text == "Sheep 20", "the sheep on the focus gets an exact countdown: " .. tostring(L.sheep.text))
G.now = G.now + 16 tick()
eq(L.sheep.text, "Sheep 4", "it counts down") eq(L.sheep.color[1], 1, "and turns red near the end")
G.units.target, G.units.focus = G.units.focus, G.units.target -- you targeted the sheep and focused the other one
tick()
eq(L.sheep.text, "Sheep 4", "it follows the sheep when target and focus swap")
G.units.target.auras.Polymorph = G.now + 30
G.now = G.now + 2 tick()
eq(L.sheep.text, "Sheep 28", "a fresh sheep on the same enemy restarts it")
G.units.target.auras.Polymorph = nil
tick()
check(L.sheep.text == "SHEEP BROKE" and #G.sounds == 1, "a sheep that breaks early is shouted")
G.now = G.now + 3 tick()
check(not L.sheep.shown, "and the shout clears")
G.units.target.auras.Polymorph = G.now + 2
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", polyID)
G.now = G.now + 1.5 tick()
G.units.target.auras.Polymorph = nil
G.now = G.now + 0.3 tick()
check(L.sheep.text ~= "SHEEP BROKE", "a sheep that ran its full time is not called broken")
G.now = G.now + 1 tick()
check(not L.sheep.shown, "it just ends")
G.hide.aura = true
G.units.focus = nil
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", polyID)
tick()
check(L.sheep.shown and L.sheep.text == "Sheep about 20", "when the game hides the debuff, an estimate is shown and labelled: " .. tostring(L.sheep.text))
eq(TorchBindsDB.alert.probe.sheep, "hidden", "and that is written down")
G.now = G.now + 21 tick()
check(not L.sheep.shown, "the estimate ends on time")
G.hide.aura = nil
local fbID
for id, name in pairs(spellName) do if name == "Frostbolt" then fbID = id end end
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c4", fbID) tick()
check(not L.sheep.shown, "other spells do not start a sheep timer")
G.units.target.auras.Polymorph = G.now + 20
fire("UNIT_SPELLCAST_SUCCEEDED", "target", "c3", polyID) tick()
check(not L.sheep.shown, "somebody else's Polymorph is not yours")
G.units.target.auras.Polymorph = nil

G.sounds = {}
G.units.nameplate1 = { hostile = true, player = true, class = "Rogue", guid = "r1", target = "player" }
G.units.nameplate2 = { hostile = true, player = false, class = "Wolf", guid = "m1", target = "player" }
G.units.nameplate3 = { hostile = true, player = true, class = "Warrior", guid = "w2", target = "nameplate1" }
G.units.nameplate4 = { hostile = false, player = true, class = "Druid", guid = "d1", target = "player" }
tick()
check(L.onYou.shown and L.onYou.text == "1 ON YOU:  Rogue", "one enemy player on you, by class: " .. tostring(L.onYou.text))
eq(#G.sounds, 1, "with a sound")
tick() eq(#G.sounds, 1, "the sound is not repeated while nothing changes")
G.units.nameplate3.target = "player"
tick()
check(L.onYou.text:find("^2 ON YOU") and L.onYou.text:find("Warrior", 1, true) and #G.sounds == 2, "a second one is counted and sounded")
G.units.nameplate1.target, G.units.nameplate3.target = nil, nil
tick()
check(not L.onYou.shown, "nobody on you: nothing shown")
SlashCmdList["TORCHBINDS"]("alert scan off")
G.units.nameplate1.target = "player" tick()
check(not L.onYou.shown, "scan off stops the watch")
SlashCmdList["TORCHBINDS"]("alert scan on") tick()
check(L.onYou.shown, "scan on resumes it")
G.hide.compare = true
tick()
check(not L.onYou.shown, "when the game hides who an enemy targets, the line goes away")
eq(TorchBindsDB.alert.probe.onYou, "hidden", "and that is written down")
G.hide.compare = nil
G.units.nameplate1.target = "player" tick()
check(not L.onYou.shown, "and it stops asking for the rest of the session")

G.sounds = {}
SlashCmdList["TORCHBINDS"]("alert sound off")
G.units.target = { hostile = true, player = true, guid = "p1", cast = "Heal" }
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
check(L.target.shown and #G.sounds == 0, "sound off keeps the text and drops the sound")
SlashCmdList["TORCHBINDS"]("alert off")
check(not L.target.shown, "alert off clears what is showing")
fire("UNIT_SPELLCAST_START", "target", "c1", 1)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", polyID) tick()
check(not L.target.shown and not L.sheep.shown, "and nothing new appears")
SlashCmdList["TORCHBINDS"]("alert on") SlashCmdList["TORCHBINDS"]("alert sound on")
G.printed = {}
check(pcall(SlashCmdList["TORCHBINDS"], "alert test"), "alert test runs")
check(L.target.shown and L.focus.shown and L.sheep.shown and L.onYou.shown, "and shows every line")
runTimers()
check(not L.target.shown and not L.onYou.shown, "and its sample lines clear")
check(pcall(SlashCmdList["TORCHBINDS"], "alert"), "alert status runs")
check(table.concat(G.printed, "\n"):find("the game hides this", 1, true), "status reports what the game would not let it read")
G.units = {}
G.combat = true
check(pcall(fire, "UNIT_SPELLCAST_START", "target", "c1", 1) and pcall(tick), "alerts never touch anything protected in combat")
G.combat = false

-- 7d. the curse caller ------------------------------------------------------------------------------------
local curse = G.named.TorchBindsCurseFrame
check(curse and #curse.strings == 2, "the curse frame is built at login")
local CH, CL = curse.strings[1], curse.strings[2]
local function ctick(seconds) G.now = G.now + (seconds or 0.3) ns.Curse.tick() end
local function lastFile() return (G.files[#G.files] or ""):match("([a-z]+)%d%.ogg$") end
TorchBindsDB.curse = nil
spellName[475] = "Remove Lesser Curse"
G.files, G.units.party1, G.units.party2, G.units.party3 = {}, { name = "Hyde", guid = "h", debuffs = { "Magic", "" } }, { name = "Bueller", guid = "b" }, { name = "Kromwell", guid = "k" }
ctick(60)
check(not CH.shown and #G.files == 0, "a magic debuff is not a curse")
G.units.party1.debuffs = { "Magic", "Curse" }
ctick()
check(CH.shown and CH.text:find("^CURSE   >   "), "a cursed party member puts the line up with the key: " .. tostring(CH.text))
eq(CL.text, "Hyde", "and names them")
eq(lastFile(), "one", "one call out loud")
eq(G.files[1]:match("^(.-)one"), "Interface\\AddOns\\TorchBinds\\Sounds\\curse\\", "from the addon's own folder")
ctick() ctick()
eq(#G.files, 1, "no second call straight away")
G.myDebuffs = { "Curse" }
ctick()
eq(CL.text, "YOU,  Hyde", "you are listed first")
eq(#G.files, 1, "your own curse waits for the gap")
ctick(5)
eq(lastFile(), "self", "then it is called")
G.units.party2.debuffs, G.units.party3.debuffs = { "Curse" }, { "Curse" }
ctick(1)
eq(#G.files, 2, "three cursed waits for the gap too")
ctick(5)
eq(lastFile(), "many", "then the many call")
for _ = 1, 12 do ctick(10) end
eq(#G.files, 6, "three reminders, then quiet")
eq(lastFile(), "still", "the reminders say still")
G.units.party3.far = true
ctick()
eq(CL.text, "YOU,  Hyde,  Bueller   (1 out of reach)", "someone too far to reach is counted, not named: " .. tostring(CL.text))
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 475)
G.myDebuffs, G.units.party1.debuffs, G.units.party2.debuffs, G.units.party3.debuffs = nil, nil, nil, nil
ctick(20)
check(not CH.shown and not CL.shown, "the text goes when everyone is clean")
eq(lastFile(), "clean", "and your own decurse earns the all clean")
G.units.party1.debuffs = { "Curse" }
ctick(30)
eq(lastFile(), "one", "a new curse is a new call")
G.units.party1.debuffs = nil
ctick(20)
eq(lastFile(), "one", "no all clean when you did not decurse")
-- five in the party, only four names
G.myDebuffs = { "Curse" }
for i = 1, 4 do G.units["party" .. i] = { name = "P" .. i, guid = "g" .. i, debuffs = { "Curse" } } end
ctick(30)
eq(CL.text, "YOU,  P1,  P2,  P3  +1 more", "a long list is cut: " .. tostring(CL.text))
G.myDebuffs = nil
for i = 1, 4 do G.units["party" .. i] = nil end
ctick(30)
-- the dead and the offline are not called
local before = #G.files
G.units.party1 = { name = "Hyde", guid = "h", debuffs = { "Curse" }, dead = true }
G.units.party2 = { name = "Bueller", guid = "b", debuffs = { "Curse" }, offline = true }
ctick(30)
check(not CH.shown and #G.files == before, "dead and offline members are left alone")
G.units.party1.dead = false
G.dead = true ctick(30)
check(not CH.shown and #G.files == before, "nothing while you are dead")
G.dead = false
G.knows = {} ctick(30)
check(not CH.shown and #G.files == before, "nothing before you know the spell")
G.knows = { ["Remove Lesser Curse"] = 475 }
G.hide.dispel = true ctick(30)
check(not CH.shown and #G.files == before, "hidden debuff types: quiet")
eq(TorchBindsDB.curse.probe.type, "hidden", "and written down")
G.hide.dispel = nil
G.hide.debuff = true ctick(30)
check(not CH.shown and #G.files == before, "hidden debuffs: quiet")
G.hide.debuff = nil
SlashCmdList["TORCHBINDS"]("curse voice off")
ctick(30)
check(CH.shown and #G.files == before, "voice off: the text still shows, no sound")
SlashCmdList["TORCHBINDS"]("curse off")
ctick(30)
check(not CH.shown, "off clears it")
SlashCmdList["TORCHBINDS"]("curse on") SlashCmdList["TORCHBINDS"]("curse voice on")
G.units.party1, G.units.party2 = nil, nil
ctick(30)
-- a raid: the player is one of the raid units, and calls are further apart
G.raid = true
G.units.raid1 = { name = "Wesheavyn", guid = "me" }
G.units.raid2 = { name = "Hyde", guid = "h", debuffs = { "Curse" } }
before = #G.files
ctick(30)
eq(#G.files, before + 1, "a raid member's curse is called")
eq(CL.text, "Hyde", "and named")
G.units.raid1.debuffs = { "Curse" }
ctick(6)
eq(#G.files, before + 1, "in a raid six seconds is too soon for the next call")
eq(CL.text, "YOU,  Hyde", "you are recognised among the raid units")
ctick(5)
eq(#G.files, before + 2, "ten seconds is not")
G.raid, G.units.raid1, G.units.raid2 = false, nil, nil
ctick(30)
G.printed = {}
check(pcall(SlashCmdList["TORCHBINDS"], "curse") and table.concat(G.printed, "\n"):find("Reading curses: working", 1, true), "status reads back what it found: " .. table.concat(G.printed, "\n"))
check(pcall(SlashCmdList["TORCHBINDS"], "curse test"), "the test does not error")
TorchBindsDB.curse = "broken"
check(pcall(ns.Curse.tick), "a damaged record does not stop it")

-- 7e. a recipe is not the item it teaches -------------------------------------------------------------------
M.ITEM[16112] = { "Manual: Heavy Silk Bandage", 20, 9 }
G.bags[16112] = 1
fire("BAG_UPDATE_DELAYED")
check(not G.macros["Bandage Self"]:find("16112", 1, true), "the bandage manual is never the bandage: " .. G.macros["Bandage Self"])
check(G.macros["Bandage Self"]:find("/use [@player] item:", 1, true), "the bandage macro is cast on yourself")
G.bags[16112] = nil

-- 8. undo goes all the way back to before Torch Binds touched anything -------------------------------------
G.bags[1114], G.bags[5514], G.bags[217495] = 20, 1, 1 -- the food, the gem and the scroll that were on the bars at the start are in the bags again
SlashCmdList["TORCHBINDS"]("undo") runTimers()
local wrong = {}
for slot = 1, 180 do if at(slot) ~= original[slot] then wrong[#wrong + 1] = slot .. " (" .. at(slot) .. " instead of " .. original[slot] .. ")" end end
eq(#wrong, 0, "undo puts every bar slot back exactly: " .. table.concat(wrong, ", "))
eq(G.binds["CTRL-E"], "MULTIACTIONBAR3BUTTON7", "old binds are back")
eq(TorchBindsDB.off, true, "undo turns the addon off so it does not re-apply")
calls = G.placeCalls
fire("PLAYER_ENTERING_WORLD", true, false) fire("SPELLS_CHANGED") fire("BAG_UPDATE_DELAYED")
eq(G.placeCalls, calls, "and it stays off")
SlashCmdList["TORCHBINDS"]("setup") runTimers()
eq(cast("Z"), "Fire Blast!", "/torch setup turns it back on and applies the layout")

-- 8b. things of yours the addon must never destroy --------------------------------------------------------
G.macros["Mount"] = "/cast [mod] Swift Raptor; Chestnut Mare"
TorchBindsDB.macros["Mount"] = nil
fire("BAG_UPDATE_DELAYED")
eq(G.macros["Mount"], "/cast [mod] Swift Raptor; Chestnut Mare", "a macro of yours with the same name is never rewritten")
local eSlot = slotOf("E")
G.slots[eSlot] = { kind = "flyout", id = 9 }
SlashCmdList["TORCHBINDS"]("setup") runTimers()
eq(G.slots[eSlot].kind, "flyout", "an action the addon cannot restore is left where it is, even by a forced setup")
G.slots[eSlot] = nil
fire("SPELLS_CHANGED")
eq(cast("E"), "Frostbolt", "and the key fills again once it is empty")
local mine = {}
-- slots 145+ cannot hold a player's own items any more: the Alt layer is secure buttons, not
-- action slots, so the hoard lives entirely on slots the client really has
for i, slot in ipairs({ 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 68, 69, 70, 71, 72, 8 }) do
  ITEM[800000 + i] = { "My Trinket " .. i, 1 }
  G.bags[800000 + i] = 1
  G.slots[slot] = { kind = "item", id = 800000 + i }
  mine[#mine + 1] = "My Trinket " .. i
end
G.slots[zSlot] = { kind = "item", id = 800001 }
SlashCmdList["TORCHBINDS"]("setup") runTimers()
local lost = {}
for _, name in ipairs(mine) do if not whereIs(name) then lost[#lost + 1] = name end end
eq(#lost, 0, "with the click buttons full of your own items, none is lost (" .. table.concat(lost, ", ") .. ")")
for i = 1, 30 do G.bags[800000 + i] = nil end
for slot = 1, 180 do if G.slots[slot] and G.slots[slot].kind == "item" and G.slots[slot].id > 800000 then G.slots[slot] = nil end end
SlashCmdList["TORCHBINDS"]("setup") runTimers()
eq(cast("Z"), "Fire Blast!", "layout restored after the stress test")
G.clicks = { { type = 3, actionID = 1, button = "MiddleButton", modifiers = 0 }, { type = 3, actionID = 2, button = "RightButton", modifiers = 4 } }
SlashCmdList["TORCHBINDS"]("decurse")
check(TorchBindsDB.clickCast ~= "ok", "click to decurse does not claim success when both clicks are yours")
eq(#G.clicks, 2, "and your click bindings are untouched")
G.clicks = { { type = 3, actionID = 1, button = "MiddleButton", modifiers = 0 } }
SlashCmdList["TORCHBINDS"]("decurse")
eq(TorchBindsDB.clickCast, "ok", "with one click free it uses that one")
G.combat = true
local bodyBefore = G.macros["Health Pot"]
G.bags[900001] = 0
check(pcall(SlashCmdList["TORCHBINDS"], "map"), "/torch map works in combat")
eq(G.macros["Health Pot"], bodyBefore, "and changes no macro there")
G.combat = false
-- a full Edit Mode layout list is never touched: the look does not write layouts at all
SlashCmdList["TORCHBINDS"]("look off")
G.edit.layouts = {}
for i = 1, 5 do G.edit.layouts[i] = { layoutName = "Mine " .. i, layoutType = 1, systems = EditModePresetLayoutManager.GetCopyOfPresetLayouts()[1].systems } end
G.edit.activeLayout = 3
SlashCmdList["TORCHBINDS"]("look devices")
eq(#G.edit.layouts, 5, "five existing layouts are left exactly alone")
eq(G.edit.activeLayout, 3, "and the active one is not switched")
G.edit.layouts, G.edit.activeLayout = {}, 2

-- 9. a fresh level 1 mage ---------------------------------------------------------------------------------
TorchBindsDB = {}
G.slots, G.macros, G.bags, G.level, G.clicks = {}, {}, { [6948] = 1 }, 1, {}
for k in pairs(G.binds) do G.binds[k] = nil end
G.book = { [1] = { name = "Attack", spellID = 6603, itemType = 1 }, [2] = { name = "Fireball", spellID = 133, itemType = 1 }, [3] = { name = "Frost Armor", spellID = 168, itemType = 1 } }
spellName[133], spellName[168] = "Fireball", "Frost Armor"
ns = load()
fire("PLAYER_ENTERING_WORLD", true, false)
eq(cast("E"), "Fireball", "level 1: the nuke key already casts Fireball")
eq(cast("SHIFT-E"), "<nil>", "level 1: the second-nuke key is not bound to an empty square")
eq(#(TorchBindsDB.log or {}), 0, "level 1: nothing went wrong: " .. table.concat(TorchBindsDB.log or {}, " | "))
G.book[4] = { name = "Frostbolt", spellID = 116, itemType = 1 } spellName[116] = "Frostbolt"
fire("SPELLS_CHANGED")
eq(cast("E"), "Frostbolt", "learning Frostbolt puts it on E by itself")
eq(cast("SHIFT-R"), "Fireball R1", "rank 1 Fireball is on Shift+R")
check(whereIs("Frostbolt R1"), "and the rank 1 Frostbolt macro gets a click square")

-- 10. a class with no layout: binds only, no errors ---------------------------------------------------------
TorchBindsDB = {}
G.class = "WARRIOR"
ns = load()
fire("PLAYER_ENTERING_WORLD", true, false)
eq(TorchBindsDB.layoutVersion, 12, "no layout: marked done")
eq(#(TorchBindsDB.log or {}), 0, "no layout: nothing logged: " .. table.concat(TorchBindsDB.log or {}, " | "))

-- 11. the game answers "empty" for every slot at once: no key is taken away -------------------------------
TorchBindsDB = {}
G.class = "MAGE"
G.slots, G.macros, G.bags, G.level, G.clicks = {}, {}, { [6948] = 1 }, 1, {}
for k in pairs(G.binds) do G.binds[k] = nil end
G.book = { [1] = { name = "Attack", spellID = 6603, itemType = 1 }, [2] = { name = "Fireball", spellID = 133, itemType = 1 }, [3] = { name = "Frost Armor", spellID = 168, itemType = 1 } }
ns = load()
fire("PLAYER_ENTERING_WORLD", true, false)
eq(cast("E"), "Fireball", "blind bars: Fireball starts on E")
local shiftE = G.binds["E"]
local realHas, realInfo = C_ActionBar.HasAction, GetActionInfo
C_ActionBar.HasAction, GetActionInfo = function() return false end, function() return nil end
fire("PLAYER_ENTERING_WORLD", false, true) -- a reload while the bars read empty
SlashCmdList["TORCHBINDS"]("binds")
eq(G.binds["E"], shiftE, "blind bars: every slot reading empty does not unbind E")
C_ActionBar.HasAction = function() error("not now") end
SlashCmdList["TORCHBINDS"]("binds")
eq(G.binds["E"], shiftE, "blind bars: the game refusing the question does not unbind it either")
C_ActionBar.HasAction, GetActionInfo = realHas, realInfo
-- binds lost some other way come back at login, and a key you bound yourself is left alone
G.binds["E"] = nil
G.binds["SHIFT-Q"] = "TOGGLEMAP"
fire("PLAYER_ENTERING_WORLD", true, false)
eq(G.binds["E"], shiftE, "repair: a lost bind is back after login")
eq(G.binds["SHIFT-Q"], "TOGGLEMAP", "repair: a key you bound to something else stays yours")
G.binds["E"] = nil
G.combat = true fire("PLAYER_ENTERING_WORLD", true, false)
eq(G.binds["E"], nil, "repair: nothing is touched in combat")
G.combat = false fire("PLAYER_REGEN_ENABLED")
eq(G.binds["E"], shiftE, "repair: it happens when the fight ends")
eq(#(TorchBindsDB.log or {}), 0, "repair: nothing went wrong: " .. table.concat(TorchBindsDB.log or {}, " | "))

-- Max rank always wins (the Frost Armor rank 1 bug). On Forever the client did not report
-- IsSpellBookItemLowRank, so the old resolver kept whatever the slot order handed it and a
-- rank 1 armor landed on the key. The rank number in the subtext is the arbiter now.
do
  local realLow, realSub = C_SpellBook.IsSpellBookItemLowRank, C_Spell.GetSpellSubtext
  C_SpellBook.IsSpellBookItemLowRank = function() return false end   -- the Forever client, which stays silent
  local function frostArmorId() return (ns.spellIndex()["Frost Armor"] or {}).id end
  G.book = { [1] = { name = "Frost Armor", spellID = 168,  itemType = 1, subName = "Rank 1" },
             [2] = { name = "Frost Armor", spellID = 7300, itemType = 1, subName = "Rank 2" },
             [3] = { name = "Frost Armor", spellID = 7301, itemType = 1, subName = "Rank 3" } }
  eq(frostArmorId(), 7301, "max rank Frost Armor wins when the client hides low rank")
  G.book = { [1] = { name = "Frost Armor", spellID = 7301, itemType = 1, subName = "Rank 3" },
             [2] = { name = "Frost Armor", spellID = 7300, itemType = 1, subName = "Rank 2" },
             [3] = { name = "Frost Armor", spellID = 168,  itemType = 1, subName = "Rank 1" } }
  eq(frostArmorId(), 7301, "max rank wins even when ranks are listed highest first")
  C_Spell.GetSpellSubtext = function(id) return ({ [168] = "Rank 1", [7300] = "Rank 2", [7301] = "Rank 3" })[id] or "" end
  G.book = { [1] = { name = "Frost Armor", spellID = 7301, itemType = 1 },
             [2] = { name = "Frost Armor", spellID = 168,  itemType = 1 } }
  eq(frostArmorId(), 7301, "max rank wins from the spell subtext when the book entry omits it")
  C_Spell.GetSpellSubtext, C_SpellBook.IsSpellBookItemLowRank, G.book = realSub, realLow, {}
end

say(("%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
