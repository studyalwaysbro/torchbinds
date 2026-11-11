-- What version 11 added: the Alt layer, the race-aware racials and the spec-aware spells.
-- lua tests/v11.lua tests/fixture-v3.lua
local svPath = assert(arg[1], "give the SavedVariables file")
dofile(svPath)
local saved = TorchBindsDB
local passed, failed = 0, 0
local function check(c, label) if c then passed = passed + 1 else failed = failed + 1 io.write("FAIL: " .. label .. "\n") end end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local G, fire, at, whereIs = M.G, M.fire, M.at, M.whereIs
local BUTTON_FIRST = { ACTIONBUTTON = 1, MULTIACTIONBAR1BUTTON = 61, MULTIACTIONBAR2BUTTON = 49, MULTIACTIONBAR3BUTTON = 25,
                       MULTIACTIONBAR4BUTTON = 37, MULTIACTIONBAR5BUTTON = 145, MULTIACTIONBAR6BUTTON = 157, MULTIACTIONBAR7BUTTON = 169 }
local function slotOf(key)
  local command = G.binds[key]
  if not command then return nil end
  local mp, p = command:match("^CLICK TorchBinds(M?)Alt(%d+):LeftButton$")
  if p then return (mp == "M" and 157 or 145) + tonumber(p) - 1 end
  for prefix, first in pairs(BUTTON_FIRST) do
    local n = command:match("^" .. prefix .. "(%d+)$")
    if n then return first + tonumber(n) - 1 end
  end
  return nil
end
-- The plain keys are reserved: the addon binds Q, E, 1, mouse 4 and the rest whether or not the
-- square has anything in it yet, so the key is already yours the day you learn the spell. Only
-- the Shift and Alt layers are bound on demand, so only those may be checked for empty squares.
local function onDemand(key) return key:find("^SHIFT%-") ~= nil or key:find("^ALT%-") ~= nil end
local function cast(key) local slot = slotOf(key) return slot and at(slot) or nil end

local ns
local function load(reset)
  local fresh = {}
  for i = #M.frames, 1, -1 do M.frames[i] = nil end
  G.tickers, G.timers = {}, {}
  TryUseActionButton = function() end
  for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
                            "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
    for i = 1, 12 do _G[prefix .. i].scripts = {} end
  end
  if reset then G.slots, G.binds, G.macros = {}, {}, {} TorchBindsDB = {} end
  -- one namespace table per load, shared by every file, exactly as the game does it
  for _, file in ipairs({ "TorchBinds.lua", "Stats.lua", "Coach.lua", "Alert.lua", "Curse.lua", "Look.lua", "Rested.lua", "Panel.lua" }) do
    assert(loadfile(file))("TorchBinds", fresh)
  end
  ns = fresh
  fire("PLAYER_ENTERING_WORLD", true, false)
end
for key, a in pairs(saved.actions) do G.slots[tonumber(key:sub(2))] = { kind = a.kind, id = a.id, text = a.kind == "macro" and a.text or nil } end
for _, sp in ipairs(saved.spells) do G.book[sp.slot] = { name = sp.name, spellID = sp.id, itemType = sp.type, isPassive = sp.passive, sub = sp.sub } end
for _, sp in ipairs(saved.spells) do M.spellName[sp.id] = sp.name end
local nextSlot = 500
local function learn(name, id)
  nextSlot = nextSlot + 1
  G.book[nextSlot] = { name = name, spellID = id, itemType = 1 }
  M.spellName[id] = name
end
-- the Forever mage kit this fixture predates: every one of these is in the live spell data
learn("Frost Blast", 1293653) learn("Arcane Blast", 400574) learn("Arcane Wrath", 1239800) learn("Frostfire Bolt", 1239801)
learn("Pyroblast", 11366) learn("Combustion", 11129) learn("Arcane Power", 12042) learn("Presence of Mind", 12043)
learn("Ice Barrier", 11426) learn("Blast Wave", 11113) learn("Mage Armor", 6117) learn("Cannibalize", 20577)
learn("Will of the Forsaken", 7744)
G.level = 60

-- 1. Undead: both racials you press get a key, and the troll ones are nowhere ------------------
G.race, G.raceName = "Scourge", "Undead"
for slot, item in pairs(G.book) do
  if item.name == "Berserking" or item.name == "Rapid Regeneration" then G.book[slot] = nil end
end
load(true)
eq(cast("ALT-Q"), "Free Me", "undead: Will of the Forsaken is on Alt+Q")
eq(G.macros["Free Me"], "#showtooltip Will of the Forsaken\n/stopcasting\n/cast Will of the Forsaken", "undead: the escape stops the cast it was in")
eq(cast("SHIFT-2"), "Feed", "undead: Cannibalize is on Shift + thumb 2, the pad's top row")
check(not whereIs("Berserking"), "undead: no troll racial anywhere")
check(not whereIs("Rapid Regeneration"), "undead: no troll regeneration anywhere")
-- Touch of the Grave and Underwater Breathing are passive: they must never take a button
check(not whereIs("Touch of the Grave"), "undead: the passive racial gets no button")

-- 2. the trees: the keys never move, only what comes out of them -------------------------------
local JOBS = { ["E"] = "main nuke", ["SHIFT-E"] = "second nuke", ["R"] = "follow-up", ["SHIFT-X"] = "burst" }
local seen = {}
for _, tree in ipairs({ "frost", "fire", "arcane" }) do
  G.spec = { [tree] = 31 }
  load(true)
  seen[tree] = {}
  for key in pairs(JOBS) do seen[tree][key] = cast(key) end
  eq(cast("Q"), "Frost Nova", tree .. ": Q is still the freeze")
  eq(cast("F"), "Blink!", tree .. ": F is still Blink")
  eq(cast("Z"), "Fire Blast!", tree .. ": Z is still the instant")
  eq(cast("C"), "Shoot", tree .. ": C is still the wand")
  eq(cast("X"), "Ice Block!", tree .. ": X is still the panic button")
  eq(cast("ALT-X"), "Trinkets", tree .. ": Alt+X is still the trinket")
  check(cast("ALT-Q") == "Free Me", tree .. ": Alt+Q is still the racial")
end
eq(seen.frost["E"], "Frostbolt", "frost casts Frostbolt from the nuke key")
eq(seen.fire["E"], "Fireball", "fire casts Fireball from the same key")
eq(seen.arcane["E"], "Arcane Blast", "arcane casts Arcane Blast from the same key")
eq(seen.frost["SHIFT-E"], "Frost Blast!", "frost's second nuke is Frost Blast, the move Forever added")
eq(seen.fire["SHIFT-E"], "Pyroblast", "fire's second nuke is Pyroblast")
eq(seen.arcane["SHIFT-E"], "Arcane Wrath", "arcane's second nuke is Arcane Wrath")
eq(seen.frost["R"], "Ice Lance!", "frost follows up with Ice Lance")
eq(seen.fire["R"], "Scorch", "fire follows up with Scorch")
eq(seen.arcane["R"], "Arcane Missiles", "arcane follows up with Arcane Missiles")
eq(seen.frost["SHIFT-X"], "Cold Snap", "frost's burst key is Cold Snap")
eq(seen.fire["SHIFT-X"], "Combustion", "fire's burst key is Combustion")
eq(seen.arcane["SHIFT-X"], "Arcane Power", "arcane's burst key is Arcane Power")
for key, job in pairs(JOBS) do
  check(seen.frost[key] ~= seen.fire[key] or seen.frost[key] ~= seen.arcane[key], "the " .. job .. " key really does change with the tree (" .. key .. ")")
end

-- 3. a respec moves the spells without a reload --------------------------------------------------
G.spec = { frost = 31 }
load(true)
eq(cast("E"), "Frostbolt", "before the respec: Frostbolt")
G.spec = { fire = 31 }
fire("PLAYER_TALENT_UPDATE")
eq(cast("E"), "Fireball", "after the respec the same key casts Fireball")
eq(cast("SHIFT-X"), "Combustion", "and the burst key followed the tree")

-- 4. no key is bound to a square with nothing in it, and nothing is on two keys at once ----------
G.spec = { frost = 31 }
load(true)
local where, dupes = {}, {}
for key, command in pairs(G.binds) do
  if command:match("^%u+%d?%u*%d+$") then
    local slot = slotOf(key)
    check(slot ~= nil, "the key " .. key .. " points at a real bar slot")
    if slot then
      local what = at(slot)
      if onDemand(key) then check(what ~= "-", "the key " .. key .. " is not bound to an empty square") end
      -- Mouse 4 and 5 deliberately mirror thumb 1 and thumb 4. Arcane Missiles is deliberately on
      -- two keys as well: Shift+R for the left hand mid-rotation, and mouse thumb 6, which he fires
      -- by clicking in a fight. Everything else is once only.
      local mirrors = key:find("BUTTON[45]$") ~= nil or what == "Arcane Missiles"
      if what ~= "-" and not mirrors then
        if where[what] then dupes[#dupes + 1] = what .. " is on both " .. where[what] .. " and " .. key end
        where[what] = key
      end
    end
  end
end
eq(#dupes, 0, "no spell is on two keys: " .. table.concat(dupes, "; "))

-- 5. Alt is a real third layer: it never steals a key Shift or the plain key already uses --------
local layers = 0
for _, key in ipairs({ "Q", "E", "R", "Z", "X", "C", "1", "2", "3", "4" }) do
  local plain, shift, alt = G.binds[key], G.binds["SHIFT-" .. key], G.binds["ALT-" .. key]
  if plain and shift and alt then layers = layers + 1 end
  check(not (plain and shift) or plain ~= shift, key .. ": Shift does not repeat the plain key")
  check(not (plain and alt) or plain ~= alt, key .. ": Alt does not repeat the plain key")
  check(not (shift and alt) or shift ~= alt, key .. ": Alt does not repeat the Shift key")
end
check(layers >= 8, "most keys carry all three layers (" .. layers .. " of 10)")

-- 6. Ctrl is still given back to the game: the lazy pinky rule did not change ---------------------
for _, key in ipairs({ "CTRL-Q", "CTRL-E", "CTRL-R", "CTRL-1", "CTRL-2" }) do
  eq(G.binds[key], nil, "the tartarus preset leaves " .. key .. " alone")
end

-- 7. levelling: a fresh level 1 mage is already bound, and nothing points at an empty square -----
G.level, G.spec = 1, nil
G.book = {}
G.book[1] = { name = "Fireball", spellID = 133, itemType = 1 } M.spellName[133] = "Fireball"
G.book[2] = { name = "Arcane Intellect", spellID = 1459, itemType = 1 } M.spellName[1459] = "Arcane Intellect"
G.book[3] = { name = "Shoot", spellID = 5019, itemType = 1 } M.spellName[5019] = "Shoot"
load(true)
eq(cast("E"), "Fireball", "level 1: the nuke key casts Fireball from the first minute")
eq(cast("C"), "Shoot", "level 1: the wand is on C")
eq(cast("ALT-3"), "Arcane Intellect", "level 1: the buff already has its own key")
for key, command in pairs(G.binds) do
  if command:match("^%u+%d?%u*%d+$") then
    local slot = slotOf(key)
    check(slot ~= nil, "level 1: " .. key .. " points at a real bar slot")
    if onDemand(key) then check(at(slot) ~= "-", "level 1: " .. key .. " is not bound to an empty square") end
  end
end

io.write(("%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
