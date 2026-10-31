-- Torch Binds stats: counts what you press so the layout can be judged on evidence.
--
-- It records, per key preset: key presses and mouse clicks on the eight standard action bars, which
-- presses did nothing and why (moving, out of range, not facing, no target), keys pressed with
-- nothing on them, neighbouring keys hit at the same instant, and casts cut short by moving.
-- It only counts. It never presses, blocks or changes anything, and nothing leaves your computer.
-- /torch stats shows the summary; the full counts are in the saved variables file.

local ADDON, ns = ...
local plain, try, say = ns.plain, ns.try, ns.say

local Stats = {}
ns.Stats = Stats

local ATTRIBUTE_WINDOW = 0.4  -- an error this soon after a press belongs to that press
local FUMBLE_WINDOW = 0.12    -- two neighbouring keys this close together were one finger
local PAIR_CAP = 150

-- where each left-hand key sits on the keypad (column, row), in bar order: Q E R F Z X C
local PAD = { { 1, 1 }, { 3, 1 }, { 4, 1 }, { 4, 2 }, { 1, 3 }, { 2, 3 }, { 3, 3 } }
local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton",
               "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local SLOT_MAX = 180

-- which message means what. Checked in order; the first match wins.
local REASONS = {
  { "moving", { "while moving", "can't do that while moving" } },
  { "range", { "out of range", "too far away", "too close" } },
  { "facing", { "facing", "in front of you" } },
  { "sight", { "line of sight" } },
  { "target", { "no target", "invalid target", "must have a target", "have no target", "target is" } },
  { "mana", { "not enough mana", "not enough" } },
  { "cooldown", { "not ready", "isn't ready", "cooldown" } },
  { "busy", { "in progress" } },
  { "silenced", { "silenced", "stunned", "can't do that while" } },
}
local REASON_TEXT = { moving = "pressed while moving", range = "out of range", facing = "not facing the target", sight = "no line of sight",
                      target = "no target, or the wrong kind", mana = "not enough mana", busy = "pressed during another cast", silenced = "silenced, stunned or otherwise unable" }
Stats.REASON_TEXT = REASON_TEXT

local data, inCombat, combatStart
local last = { slot = nil, t = -10 }
local lastMove, lastClick = -10, {}

local function bucket()
  local db = TorchBindsDB
  db.stats = db.stats or { since = time(), presets = {} }
  local name = ns.presetName()
  local p = db.stats.presets[name]
  if not p then
    p = { since = time(), presses = 0, clicks = 0, clicksCombat = 0, empty = 0, seconds = 0, fights = 0, casts = 0,
          slots = {}, errors = {}, pairs = {}, cancels = { moved = 0, other = 0 } }
    db.stats.presets[name] = p
  end
  return p
end

local function slotRecord(p, slot)
  local id = "s" .. slot
  local rec = p.slots[id]
  if not rec then rec = { k = 0, m = 0, mc = 0, e = {} } p.slots[id] = rec end
  local kind, itemID, text = ns.slotInfo(slot)
  if kind then rec.n = text or (kind == "item" and (plain(try(C_Item and C_Item.GetItemNameByID, itemID)) or "item")) or rec.n end
  return rec, kind ~= nil
end

local function padPosition(slot)
  local B = ns.BARS
  local i = (slot >= B.MAIN and slot < B.MAIN + 7 and slot - B.MAIN + 1) or (slot >= B.SHIFT and slot < B.SHIFT + 7 and slot - B.SHIFT + 1)
  if i then return PAD[i] end
  -- thumb buttons 1 to 5 are also the pad's top row
  for _, first in ipairs({ B.MOUSE, B.MSHIFT }) do
    if slot >= first and slot < first + 12 then
      local n = ns.GRID_THUMB[slot - first + 1]
      if n <= 5 then return { n - 1, 0 } end
    end
  end
end

-- the number printed on the mouse's thumb button that presses this slot
local function gridNumber(slot)
  local B = ns.BARS
  if slot >= B.MOUSE and slot < B.MOUSE + 12 then return ns.GRID_THUMB[slot - B.MOUSE + 1] end
  if slot >= B.MSHIFT and slot < B.MSHIFT + 12 then return ns.GRID_THUMB[slot - B.MSHIFT + 1] end
end

local function neighbours(a, b)
  local pa, pb = padPosition(a), padPosition(b)
  if pa and pb and math.abs(pa[1] - pb[1]) <= 1 and math.abs(pa[2] - pb[2]) <= 1 then return true end
  local ga, gb = gridNumber(a), gridNumber(b)
  if ga and gb and ga ~= gb then
    local ax, ay, bx, by = (ga - 1) % 3, math.floor((ga - 1) / 3), (gb - 1) % 3, math.floor((gb - 1) / 3)
    if math.abs(ax - bx) <= 1 and math.abs(ay - by) <= 1 then return true end
  end
  return false
end
Stats.neighbours = neighbours

local function onKey(slot)
  slot = plain(slot)
  if type(slot) ~= "number" or slot < 1 or slot > SLOT_MAX then return end
  local p, now = bucket(), GetTime()
  local rec, filled = slotRecord(p, slot)
  rec.k = rec.k + 1
  p.presses = p.presses + 1
  if not filled then p.empty = p.empty + 1 rec.x = (rec.x or 0) + 1 end
  local fumbled = last.slot and last.slot ~= slot and now - last.t < FUMBLE_WINDOW and neighbours(last.slot, slot)
  if ns.Coach then ns.Coach.Note("key", slot, rec.n, (not filled and "empty") or (fumbled and "fumble") or nil) end
  if fumbled then
    local a, b = math.min(last.slot, slot), math.max(last.slot, slot)
    local id = a .. "+" .. b
    if p.pairs[id] then
      p.pairs[id] = p.pairs[id] + 1
    else
      local n = 0
      for _ in pairs(p.pairs) do n = n + 1 end
      if n < PAIR_CAP then p.pairs[id] = 1 end
    end
  end
  last.slot, last.t = slot, now
end
Stats.onKey = onKey

local function onMouse(slot)
  slot = plain(slot)
  if type(slot) ~= "number" or slot < 1 or slot > SLOT_MAX then return end
  local now = GetTime()
  if lastClick[slot] and now - lastClick[slot] < 0.1 then return end -- down and up of one click
  lastClick[slot] = now
  local p = bucket()
  local rec = slotRecord(p, slot)
  rec.m = rec.m + 1
  p.clicks = p.clicks + 1
  if inCombat then rec.mc = rec.mc + 1 p.clicksCombat = p.clicksCombat + 1 end
  if ns.Coach then ns.Coach.Note("click", slot, rec.n) end
  last.slot, last.t = slot, now
end
Stats.onMouse = onMouse

local function reasonFor(message)
  local text = message:lower()
  for _, reason in ipairs(REASONS) do
    for _, needle in ipairs(reason[2]) do
      if text:find(needle, 1, true) then return reason[1] end
    end
  end
  return "other"
end
Stats.reasonFor = reasonFor

local handlers = {}

function handlers.UI_ERROR_MESSAGE(_, message)
  message = plain(message)
  if type(message) ~= "string" then return end
  local p, reason = bucket(), reasonFor(message)
  p.errors[reason] = (p.errors[reason] or 0) + 1
  -- only a message that is about casting is pinned on the key you just pressed
  if reason ~= "other" and last.slot and GetTime() - last.t < ATTRIBUTE_WINDOW then
    local rec = slotRecord(p, last.slot)
    rec.e[reason] = (rec.e[reason] or 0) + 1
    if ns.Coach and reason ~= "cooldown" and reason ~= "mana" then ns.Coach.Note("error", last.slot, rec.n, reason) end
  end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit)
  if plain(unit) == "player" then local p = bucket() p.casts = p.casts + 1 end
end

function handlers.UNIT_SPELLCAST_INTERRUPTED(unit)
  if plain(unit) ~= "player" then return end
  local p = bucket()
  if GetTime() - lastMove < 0.35 then
    p.cancels.moved = p.cancels.moved + 1
    if ns.Coach then ns.Coach.Note("moved") end
  else
    p.cancels.other = p.cancels.other + 1
  end
end

function handlers.PLAYER_STARTED_MOVING() lastMove = GetTime() end
function handlers.PLAYER_REGEN_DISABLED()
  inCombat, combatStart = true, GetTime()
  if ns.Coach then ns.Coach.Start() end
end
function handlers.PLAYER_REGEN_ENABLED()
  if inCombat and combatStart then
    local p = bucket()
    p.seconds = p.seconds + (GetTime() - combatStart)
    p.fights = p.fights + 1
  end
  inCombat, combatStart = false, nil
  if ns.Coach then ns.Coach.Finish() end
end

local started = false
function Stats.Init()
  if started then return end
  started = true
  -- a keybind on a standard action button goes through this one function; mouse clicks do not
  if type(TryUseActionButton) == "function" then
    pcall(hooksecurefunc, "TryUseActionButton", function(button, down)
      if down and type(button) == "table" then pcall(onKey, button.action) end
    end)
  end
  for _, prefix in ipairs(BARS) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if type(button) == "table" and button.HookScript then
        pcall(button.HookScript, button, "OnClick", function(self) pcall(onMouse, self.action) end)
      end
    end
  end
  local frame = CreateFrame("Frame")
  for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
  frame:SetScript("OnEvent", function(_, event, ...)
    if TorchBindsDB then pcall(handlers[event], ...) end
  end)
  Stats.frame = frame
end

-- REPORT --------------------------------------------------------------------
local function keyFor(slot, keys)
  local list = keys[slot]
  return list and ns.prettyKey(list[1]) or "no key"
end

local function top(p, score, n)
  local rows = {}
  for id, rec in pairs(p.slots) do
    local value = score(rec)
    if value and value > 0 then rows[#rows + 1] = { slot = tonumber(id:sub(2)), rec = rec, value = value } end
  end
  table.sort(rows, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.slot < b.slot end)
  for i = #rows, n + 1, -1 do rows[i] = nil end
  return rows
end

local function percent(part, whole) return whole > 0 and math.floor(part * 100 / whole + 0.5) or 0 end

-- Plain-language findings for one preset, most useful first. Returned as lines so the tests can read them.
function Stats.Report(name)
  local db = TorchBindsDB.stats
  local p = db and db.presets[name]
  local lines = {}
  if not p or (p.presses + p.clicks) == 0 then
    lines[1] = "Nothing recorded yet on the " .. name .. " preset. Go fight something, then look again."
    return lines
  end
  local keys = ns.keysBySlot()
  local total = p.presses + p.clicks
  lines[#lines + 1] = ("%s preset since %s: %d key presses, %d mouse clicks on buttons (%d%% clicked), %d fights, %d minutes in combat.")
    :format(name, date("%b %d", p.since), p.presses, p.clicks, percent(p.clicks, total), p.fights, math.floor(p.seconds / 60))

  local clicked = top(p, function(rec) return rec.mc end, 5)
  if #clicked > 0 then
    local parts = {}
    for _, row in ipairs(clicked) do parts[#parts + 1] = ("%s x%d (its key is %s)"):format(row.rec.n or "?", row.value, keyFor(row.slot, keys)) end
    lines[#lines + 1] = "Clicked with the mouse during a fight: " .. table.concat(parts, ", ") .. "."
  else
    lines[#lines + 1] = "You did not click a single button during a fight. That is the goal."
  end

  for _, reason in ipairs({ "moving", "range", "facing", "target", "busy", "sight" }) do
    local rows = top(p, function(rec) return rec.e[reason] end, 3)
    if #rows > 0 and (p.errors[reason] or 0) >= 3 then
      local parts = {}
      for _, row in ipairs(rows) do parts[#parts + 1] = ("%s x%d of %d presses"):format(row.rec.n or "?", row.value, row.rec.k + row.rec.m) end
      lines[#lines + 1] = ("Did nothing, %s (%d): %s."):format(REASON_TEXT[reason], p.errors[reason], table.concat(parts, ", "))
    end
  end

  local fumbles = {}
  for id, count in pairs(p.pairs) do
    if count >= 2 then
      local a, b = id:match("^(%d+)%+(%d+)$")
      fumbles[#fumbles + 1] = { a = tonumber(a), b = tonumber(b), count = count }
    end
  end
  table.sort(fumbles, function(x, y) return x.count > y.count end)
  if #fumbles > 0 then
    local parts = {}
    for i = 1, math.min(3, #fumbles) do
      local f = fumbles[i]
      parts[#parts + 1] = ("%s and %s x%d"):format(keyFor(f.a, keys), keyFor(f.b, keys), f.count)
    end
    lines[#lines + 1] = "Two neighbouring keys hit at once (likely one finger on both): " .. table.concat(parts, ", ") .. "."
  end
  if p.empty >= 3 then
    local rows, parts = top(p, function(rec) return rec.x end, 3), {}
    for _, row in ipairs(rows) do parts[#parts + 1] = keyFor(row.slot, keys) .. " x" .. row.value end
    lines[#lines + 1] = ("Pressed a key with nothing on it %d times: %s."):format(p.empty, table.concat(parts, ", "))
  end
  if p.cancels.moved >= 3 then
    lines[#lines + 1] = ("Cut your own cast short by moving %d times (%d%% of the casts that finished)."):format(p.cancels.moved, percent(p.cancels.moved, math.max(p.casts, 1)))
  end

  local used = top(p, function(rec) return rec.k + rec.m end, 6)
  local parts = {}
  for _, row in ipairs(used) do parts[#parts + 1] = ("%s %d (%s)"):format(row.rec.n or "?", row.value, keyFor(row.slot, keys)) end
  lines[#lines + 1] = "Most used: " .. table.concat(parts, ", ") .. "."
  for rank, row in ipairs(used) do
    local list = keys[row.slot]
    local best = list and list[1]
    if best and rank <= 4 and best:find("^SHIFT%-") then
      lines[#lines + 1] = ("%s is your number %d spell and needs a modifier (%s). It has earned a plain key."):format(row.rec.n or "?", rank, ns.prettyKey(best))
    end
  end
  return lines
end

function Stats.Command(rest)
  if rest == "reset" then
    TorchBindsDB.stats = nil
    say("Stats cleared. Counting starts again now.")
    return
  end
  local current = ns.presetName()
  for i, line in ipairs(Stats.Report(current)) do
    if i == 1 then say(line) else print("  " .. line) end
  end
  for name, p in pairs((TorchBindsDB.stats or { presets = {} }).presets) do
    if name ~= current and (p.presses + p.clicks) > 50 then
      print(("  For comparison, on the %s preset: %d%% clicked, %d fumbled pairs, %d presses that did nothing while moving.")
        :format(name, percent(p.clicks, p.presses + p.clicks), (function() local n = 0 for _, c in pairs(p.pairs) do n = n + c end return n end)(), p.errors.moving or 0))
    end
  end
  print("  /torch stats reset starts the count over.")
end
