-- Soak test: lua tests/fuzz.lua [sessions] [steps] [seed]
-- Random mages (any mix of the Forever spell list and ranks), random bags, bars already full of
-- the player's own things, then random logins, training, looting, fights, commands and presses.
-- After every step it checks that:
--   * nothing raised an error, and nothing was attempted in combat that the game forbids there
--   * an action the addon cannot restore (a flyout) is never touched
--   * a macro the player wrote is never edited
--   * nothing of the player's own is ever dropped from the bars
--   * a settled layout stays settled: asking again places nothing
--   * after a forced setup with room to spare, every spell the mage knows is on a bar
package.path = "tests/?.lua;" .. package.path
local SESSIONS, STEPS, SEED = tonumber(arg[1]) or 300, tonumber(arg[2]) or 60, tonumber(arg[3]) or 1
math.randomseed(SEED)
local R = math.random
local function chance(p) return R() < p end
local function pick(t) return t[R(#t)] end

local M = require("mock")
local G, ITEM, spellName = M.G, M.ITEM, M.spellName
local SPELLS = dofile("tests/mage_spells.lua")
local byName, names = {}, {}
for _, row in ipairs(SPELLS) do
  if not byName[row[1]] then byName[row[1]] = {} names[#names + 1] = row[1] end
  table.insert(byName[row[1]], row)
  spellName[row[4]] = row[1]
end
for _, list in pairs(byName) do table.sort(list, function(a, b) return a[2] < b[2] end) end
local RACIAL = { { "Berserking", 20554 }, { "Rapid Regeneration", 1260270 }, { "Will of the Forsaken", 7744 }, { "Escape Artist", 20589 } }
for _, r in ipairs(RACIAL) do spellName[r[2]] = r[1] end
spellName[251] = "Teleport" spellName[6603] = "Attack" spellName[900900] = "Unheard Of Spell"
local LOOT = { 118, 858, 929, 1710, 3928, 1114, 1487, 2136, 3772, 3531, 6450, 213550, 217495, 277484, 1478, 277485, 5514, 6948, 3827, 4390, 900001, 900002, 5655 }
for i = 1, 40 do ITEM[700000 + i] = { "Keepsake " .. i, 1 } end
local SLOTS = {}
for _, first in ipairs({ 1, 13, 25, 37, 49, 61, 145 }) do for i = 0, 11 do SLOTS[#SLOTS + 1] = first + i end end
local COMMANDS = { "", "map", "stats", "stats reset", "setup", "undo", "binds", "on", "off", "dump", "decurse", "preset", "preset tartarus", "preset keyboard",
                   "preset xaryu", "preset thumbmove", "preset nope", "look", "look devices", "look corner", "look off", "look zz", "hovercs on", "hovercs off", "hoverfocus on", "hoverfocus off", "bags", "bagfix off", "bagfix on", "zzz",
                   "coach", "coach off", "coach on", "coach reset", "alert", "alert test", "alert off", "alert on", "alert sound off", "alert sound on", "alert scan off", "alert scan on", "alerts zz" }
local BUTTONS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton" }
local ERRORS = { "Can't do that while moving", "Out of range.", "Spell is not ready yet.", "You have no target.", "Inventory is full.", "Not enough mana", "Another action is in progress" }

local ns, book, totals = nil, 0, { steps = 0, setups = 0, placed = 0, sessions = 0 }
local flyouts, userMacros, mineKeys, userLayouts

local function learn(name, upTo)
  for _, row in ipairs(byName[name]) do
    if row[2] <= upTo then
      book = book + 1
      G.book[book] = { name = name, spellID = row[4], itemType = chance(0.03) and 2 or 1 }
    end
  end
end

local function key(slot)
  local a = G.slots[slot]
  if not a then return nil end
  return a.kind .. ":" .. tostring(a.kind == "macro" and a.text or a.id)
end

local function isMine(slot)
  local a = G.slots[slot]
  if not a then return false end
  if a.kind == "item" then return a.id > 700000 and a.id < 800000 end
  if a.kind == "macro" then return userMacros[a.text] ~= nil end
  if a.kind == "spell" then return a.id == 7731 end -- a profession, not in the spellbook the addon reads
  return false
end

local function mineOnBars()
  local set = {}
  for slot = 1, 180 do if isMine(slot) then set[key(slot)] = true end end
  return set
end

local function newSession()
  for k in pairs(G.slots) do G.slots[k] = nil end
  for k in pairs(G.book) do G.book[k] = nil end
  for k in pairs(G.macros) do G.macros[k] = nil end
  for k in pairs(G.bags) do G.bags[k] = nil end
  for k in pairs(G.binds) do G.binds[k] = nil end
  G.clicks, G.combat, G.timers, G.level, G.class, G.cursor = {}, false, {}, R(1, 60), "MAGE", nil
  G.edit.layouts, G.edit.activeLayout = {}, R(1, 2)
  for i = 1, R(0, 5) do G.edit.layouts[i] = { layoutName = "Mine " .. i, layoutType = 1, systems = EditModePresetLayoutManager.GetCopyOfPresetLayouts()[1].systems } end
  if #G.edit.layouts > 0 and chance(0.5) then G.edit.activeLayout = 2 + R(#G.edit.layouts) end
  userLayouts = #G.edit.layouts
  M.frames.n = nil
  for i = #M.frames, 1, -1 do M.frames[i] = nil end
  TorchBindsDB, book, flyouts, userMacros = {}, 0, {}, {}
  G.book[1] = { name = "Attack", spellID = 6603, itemType = 1 } book = 1
  local depth = R()
  for _, name in ipairs(names) do
    if name ~= "Attack" and chance(depth) then learn(name, R(1, #byName[name])) end
  end
  for _, r in ipairs(RACIAL) do if chance(0.4) then book = book + 1 G.book[book] = { name = r[1], spellID = r[2], itemType = 1 } end end
  if chance(0.5) then book = book + 1 G.book[book] = { name = "Teleport", spellID = 251, itemType = 4 } end -- a flyout entry in the book
  if chance(0.3) then book = book + 1 G.book[book] = { name = "Unheard Of Spell", spellID = 900900, itemType = 1 } end
  for _, id in ipairs(LOOT) do if chance(0.4) then G.bags[id] = R(1, 20) end end
  -- the player's own bars before the addon ever runs
  local clutter = R(0, 34)
  for _ = 1, clutter do
    local slot, roll = pick(SLOTS), R()
    if roll < 0.45 then
      local id = 700000 + R(1, 40)
      G.bags[id] = 1
      G.slots[slot] = { kind = "item", id = id }
    elseif roll < 0.6 then
      local name = pick({ "My Burst", "Trinket", "Mount", "Decurse", "Health Pot", "Bandage Self", "Blink!" })
      userMacros[name] = "/say " .. name .. " is mine"
      G.macros[name] = userMacros[name]
      G.slots[slot] = { kind = "macro", id = 1, text = name }
    elseif roll < 0.7 then
      G.slots[slot] = { kind = "spell", id = 7731 }
    elseif roll < 0.8 then
      G.slots[slot] = { kind = "flyout", id = R(1, 9) }
      flyouts[slot] = G.slots[slot].id
    elseif roll < 0.9 and book > 1 then
      local entry = G.book[R(2, book)]
      if entry.itemType == 1 then G.slots[slot] = { kind = "spell", id = entry.spellID } end
    else
      local id = pick(LOOT)
      G.bags[id] = G.bags[id] or 1
      G.slots[slot] = { kind = "item", id = id }
    end
  end
  for slot in pairs(flyouts) do if not (G.slots[slot] and G.slots[slot].kind == "flyout") then flyouts[slot] = nil end end
  if chance(0.3) then G.clicks = { { type = 3, actionID = 1, button = "MiddleButton", modifiers = 0 } } end
  TryUseActionButton = function() end -- a fresh client: no hooks left over from the last session
  for _, prefix in ipairs(BUTTONS) do for i = 1, 12 do _G[prefix .. i].scripts = {} end end
  ns = {}
  G.tickers, G.units, G.hide = {}, {}, {}
  for _, file in ipairs({ "TorchBinds.lua", "Stats.lua", "Coach.lua", "Alert.lua", "Curse.lua", "Look.lua", "Rested.lua", "Panel.lua" }) do assert(loadfile(file))("TorchBinds", ns) end
  ns.Alert.Init()
  mineKeys = mineOnBars()
  totals.sessions = totals.sessions + 1
end

local STEP = {
  function() M.fire("PLAYER_ENTERING_WORLD", true, false) end,
  function() M.fire("PLAYER_ENTERING_WORLD", false, true) end,
  function() local name = pick(names) if name ~= "Attack" then learn(name, R(1, #byName[name])) end M.fire("SPELLS_CHANGED") end,
  function() for _ = 1, R(1, 4) do local id = pick(LOOT) G.bags[id] = chance(0.25) and nil or R(1, 20) end M.fire("BAG_UPDATE_DELAYED") end,
  function() G.level = math.min(60, G.level + R(0, 6)) M.fire("PLAYER_LEVEL_UP") end,
  function() G.combat = true M.fire("PLAYER_REGEN_DISABLED") end,
  function() G.combat = false M.fire("PLAYER_REGEN_ENABLED") end,
  function() SlashCmdList["TORCHBINDS"](pick(COMMANDS)) M.runTimers() end,
  function() SlashCmdList["TORCHBINDS"](pick(COMMANDS)) M.runTimers() end,
  function() M.press(pick(BUTTONS), R(1, 12)) if chance(0.4) then M.fire("UI_ERROR_MESSAGE", 1, pick(ERRORS)) end end,
  function() M.click(pick(BUTTONS), R(1, 12)) end,
  function() M.fire("UNIT_SPELLCAST_SUCCEEDED", "player") M.fire("PLAYER_STARTED_MOVING") M.fire("UNIT_SPELLCAST_INTERRUPTED", "player") end,
  function() G.now = G.now + R() * 3 end,
}

-- the coach and the alerts are called directly here, without the guard the game events get,
-- so an error in them stops the soak instead of being swallowed
local UNITS = { "target", "focus", "nameplate1", "nameplate2", "nameplate7", "player", "party1" }
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED",
                      "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED" }
local function randomUnit()
  if chance(0.25) then return nil end
  local u = { hostile = chance(0.7), player = chance(0.6), guid = pick({ "a", "b", "c", "d" }), class = chance(0.8) and pick({ "Rogue", "Priest", "Warrior" }) or nil }
  if chance(0.5) then u.cast = "Heal" end
  if chance(0.2) then u.channel = "Mind Flay" end
  if chance(0.2) then u.shielded = true end
  if chance(0.5) then u.target = pick({ "player", "target", "focus", "nameplate1" }) end
  if chance(0.5) then u.auras = { Polymorph = G.now + R() * 40 - 5, ["Polymorph: Pig"] = chance(0.3) and G.now + 9 or nil } end
  return u
end
local function anySpell() return pick({ 118, 116, 12824, 28272, 900900, 1, false }) or nil end
spellName[118], spellName[12824], spellName[28272] = "Polymorph", "Polymorph", "Polymorph: Pig"
for _, step in ipairs({
  function()
    for _, u in ipairs(UNITS) do if u ~= "player" then G.units[u] = randomUnit() end end
    for _, k in ipairs({ "cast", "aura", "compare", "hostile" }) do G.hide[k] = chance(0.2) or nil end
  end,
  function() ns.Alert.onEvent(nil, pick(CAST_EVENTS), pick(UNITS), "cast", anySpell()) M.runTimers() end,
  function() ns.Alert.onEvent(nil, pick(CAST_EVENTS), chance(0.1) and G.SECRET or pick(UNITS), "cast", chance(0.1) and G.SECRET or anySpell()) M.runTimers() end,
  function() ns.Alert.tick() ns.Alert.scan() end,
  function() G.now = G.now + R() * 15 ns.Alert.tick() end,
  function()
    ns.Coach.Start()
    for _ = 1, R(0, 30) do
      G.now = G.now + R() * 2
      local kind = pick({ "key", "key", "key", "click", "error", "moved", "nonsense" })
      ns.Coach.Note(kind, chance(0.9) and R(1, 180) or nil, chance(0.7) and pick({ "Frostbolt", "Ice Lance" }) or nil, pick({ "empty", "fumble", "moving", "range", "weird" }) or nil)
    end
    if chance(0.8) then ns.Coach.Finish() end
    for _, line in ipairs(ns.Coach.Report()) do assert(type(line) == "string") end
    if #TorchBindsDB.coach.fights > 60 then error("BROKEN: the coach kept more than sixty fights", 0) end
  end,
  function() ns.Coach.Finish() ns.Coach.Note("key", 3) end,
}) do STEP[#STEP + 1] = step end

local function fail(msg) error("BROKEN: " .. msg, 0) end

local function check()
  for _, line in ipairs(TorchBindsDB.log or {}) do
    if line:find("failed", 1, true) and not line:find("^pickup failed") then fail("the addon logged a failure: " .. line) end
  end
  for _, line in ipairs(G.printed) do
    if line:find("stopped part way", 1, true) then fail("setup raised: " .. line) end
  end
  G.printed = {}
  for slot, id in pairs(flyouts) do
    local a = G.slots[slot]
    if not (a and a.kind == "flyout" and a.id == id) then fail("a flyout on slot " .. slot .. " was touched") end
  end
  for name, body in pairs(userMacros) do
    if G.macros[name] ~= body then fail("the player's macro '" .. name .. "' was edited") end
  end
  -- the player's own Edit Mode layouts are never removed or renamed
  local seen = 0
  for _, layout in ipairs(G.edit.layouts) do if layout.layoutName:find("^Mine ") then seen = seen + 1 end end
  if seen ~= userLayouts then fail("one of the player's Edit Mode layouts disappeared") end
  if G.edit.activeLayout < 1 or G.edit.activeLayout > 2 + #G.edit.layouts then fail("the active Edit Mode layout points at nothing") end
  local now = mineOnBars()
  for k in pairs(mineKeys) do
    if not now[k] then fail("the player's own " .. k .. " is no longer on any bar") end
  end
end

local function settled()
  if G.combat or TorchBindsDB.off or TorchBindsDB.layoutVersion ~= 10 then return end
  M.fire("SPELLS_CHANGED") M.fire("BAG_UPDATE_DELAYED")
  local calls = G.placeCalls
  M.fire("SPELLS_CHANGED") M.fire("BAG_UPDATE_DELAYED")
  if G.placeCalls ~= calls then fail("a settled layout kept moving: " .. (G.placeCalls - calls) .. " more placements on the second pass") end
end

local function everySpellHasAHome()
  if next(flyouts) then return end
  G.combat = false
  M.fire("PLAYER_REGEN_ENABLED")
  TorchBindsDB.off = nil
  SlashCmdList["TORCHBINDS"]("setup") M.runTimers()
  totals.setups = totals.setups + 1
  local last = TorchBindsDB.lastSetup
  if not last or #(last.overflow or {}) > 0 then return end
  local IGNORE = { Attack = true, ["Frost Armor"] = true, ["Conjure Mana Agate"] = true, ["Conjure Mana Jade"] = true, ["Conjure Mana Citrine"] = true }
  local onBar, inMacro = {}, {}
  for slot = 1, 180 do
    local a = G.slots[slot]
    if a and a.kind == "spell" then onBar[spellName[a.id] or "?"] = true end
    if a and a.kind == "macro" and G.macros[a.text] then inMacro[#inMacro + 1] = G.macros[a.text] end
  end
  for _, entry in pairs(G.book) do
    local name = entry.name
    if entry.itemType == 1 and not IGNORE[name] and not onBar[name] then
      local found = false
      for _, body in ipairs(inMacro) do if body:find(name, 1, true) then found = true break end end
      -- a key the player's own macro of the same name already holds counts as theirs, not missing
      if not found and not userMacros[(name .. "!"):sub(1, 16)] then fail("after a forced setup with room to spare, " .. name .. " is on no bar") end
    end
  end
end

local started = os.clock()
for session = 1, SESSIONS do
  newSession()
  for step = 1, STEPS do
    local ok, err = pcall(STEP[R(#STEP)])
    if ok then ok, err = pcall(check) end
    if ok and step % 20 == 0 then ok, err = pcall(settled) if ok then ok, err = pcall(check) end end
    if not ok then
      io.write(("FAILED in session %d, step %d (seed %d): %s\n"):format(session, step, SEED, tostring(err)))
      io.write("log: " .. table.concat(TorchBindsDB.log or {}, " | ") .. "\n")
      os.exit(1)
    end
    totals.steps = totals.steps + 1
  end
  local ok, err = pcall(everySpellHasAHome)
  if ok then ok, err = pcall(check) end
  if not ok then
    io.write(("FAILED at the end of session %d (seed %d): %s\n"):format(session, SEED, tostring(err)))
    io.write("log: " .. table.concat(TorchBindsDB.log or {}, " | ") .. "\n")
    os.exit(1)
  end
end
io.write(("%d sessions, %d steps, %d forced setups checked, %d bar placements, 0 failures in %.1fs (seed %d)\n")
  :format(totals.sessions, totals.steps, totals.setups, G.placeCalls, os.clock() - started, SEED))
