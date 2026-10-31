-- Torch Binds coach: a line or two after each fight about what your hands did.
--
-- Stats.lua keeps the running totals. This file looks at one fight at a time: what you clicked
-- instead of pressing (and which key it was on), which presses did nothing, keys hit together,
-- and how long you went without pressing anything. It only reads and prints.
-- /torch coach shows the trend and the one thing to drill; /torch coach off keeps it quiet.

local ADDON, ns = ...
local say = ns.say

local Coach = {}
ns.Coach = Coach

local MIN_SECONDS, MIN_ACTIONS = 6, 4 -- anything shorter is a stray hit, not a fight
local KEEP = 60                       -- fights remembered for the trend
local GAP = 4                         -- seconds with no press, mid fight, worth a mention
local TREND = 10

local fight

local function store()
  local db = TorchBindsDB
  if type(db.coach) ~= "table" then db.coach = {} end
  if type(db.coach.fights) ~= "table" then db.coach.fights = {} end
  return db.coach
end

function Coach.Start()
  local now = GetTime()
  fight = { t0 = now, last = now, keys = 0, clicks = 0, empty = 0, fumbles = 0, moved = 0, gap = 0, clicked = {}, wasted = {} }
end

local function touch()
  local now = GetTime()
  if now - fight.last > fight.gap then fight.gap = now - fight.last end
  fight.last = now
end

-- Called by Stats.lua as things happen. kind: key, click, error, moved.
function Coach.Note(kind, slot, name, detail)
  if not fight then return end
  if kind == "key" then
    touch()
    fight.keys = fight.keys + 1
    if detail == "empty" then fight.empty = fight.empty + 1 end
    if detail == "fumble" then fight.fumbles = fight.fumbles + 1 end
  elseif kind == "click" then
    touch()
    fight.clicks = fight.clicks + 1
    if slot then
      local c = fight.clicked[slot] or { slot = slot, n = 0 }
      c.n, c.name = c.n + 1, name or c.name
      fight.clicked[slot] = c
    end
  elseif kind == "error" and slot and detail then
    local id = slot .. ":" .. detail
    local w = fight.wasted[id] or { slot = slot, why = detail, n = 0 }
    w.n, w.name = w.n + 1, name or w.name
    fight.wasted[id] = w
  elseif kind == "moved" then
    fight.moved = fight.moved + 1
  end
end

local function sorted(map)
  local list = {}
  for _, row in pairs(map) do list[#list + 1] = row end
  table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.slot < b.slot end)
  return list
end

local function keyFor(slot, keys)
  local list = keys[slot]
  return list and ns.prettyKey(list[1]) or nil
end

-- The record kept for one fight. Small on purpose: sixty of these live in the saved file.
local function summarise(f, seconds)
  local rec = { t = time(), s = math.floor(seconds + 0.5), k = f.keys, c = f.clicks, x = f.empty, f = f.fumbles, mv = f.moved,
                gap = math.floor(f.gap * 10 + 0.5) / 10, clicked = {}, wasted = {} }
  for i, row in ipairs(sorted(f.clicked)) do
    if i <= 3 then rec.clicked[i] = { slot = row.slot, name = row.name, n = row.n } end
  end
  for i, row in ipairs(sorted(f.wasted)) do
    if i <= 2 then rec.wasted[i] = { slot = row.slot, name = row.name, n = row.n, why = row.why } end
  end
  return rec
end

local function cleanStreak(fights)
  local n = 0
  for i = #fights, 1, -1 do
    if fights[i].c > 0 then break end
    n = n + 1
  end
  return n
end

-- What to say about one fight, worst thing first. Returned as lines so the tests can read them.
function Coach.Lines(rec, streak)
  local keys = ns.keysBySlot()
  local reasons = ns.Stats and ns.Stats.REASON_TEXT or {}
  local lines, notes = {}, {}
  if rec.c > 0 then
    local parts = {}
    for _, row in ipairs(rec.clicked) do
      local key = keyFor(row.slot, keys)
      parts[#parts + 1] = ("%s x%d (%s)"):format(row.name or "a button", row.n, key and ("key: " .. key) or "no key yet")
    end
    notes[#notes + 1] = "Clicked " .. table.concat(parts, ", ") .. "."
  end
  for _, row in ipairs(rec.wasted) do
    if row.n >= 2 then
      notes[#notes + 1] = ("%s did nothing %d times: %s."):format(row.name or "A key", row.n, reasons[row.why] or row.why)
    end
  end
  if rec.f >= 1 then notes[#notes + 1] = ("Two neighbouring keys at once, %d time%s."):format(rec.f, rec.f == 1 and "" or "s") end
  if rec.x >= 2 then notes[#notes + 1] = ("Pressed a key with nothing on it %d times."):format(rec.x) end
  if rec.mv >= 2 then notes[#notes + 1] = ("Moved and cut your own cast %d times."):format(rec.mv) end
  if rec.gap >= GAP then notes[#notes + 1] = ("Longest stretch without a press: %.1f seconds."):format(rec.gap) end

  if #notes == 0 then
    local tail = (streak or 0) >= 2 and (" That is %d fights in a row without a click."):format(streak) or ""
    lines[1] = ("Clean fight, %d seconds: %d key presses, no clicks.%s"):format(rec.s, rec.k, tail)
    return lines
  end
  lines[1] = ("Fight, %d seconds: %d key presses, %d click%s."):format(rec.s, rec.k, rec.c, rec.c == 1 and "" or "s")
  for i = 1, math.min(3, #notes) do lines[#lines + 1] = notes[i] end
  return lines
end

function Coach.Finish()
  local f = fight
  fight = nil
  if not f then return end
  local seconds = GetTime() - f.t0
  if seconds < MIN_SECONDS or f.keys + f.clicks < MIN_ACTIONS then return end
  local db = store()
  local rec = summarise(f, seconds)
  table.insert(db.fights, rec)
  while #db.fights > KEEP do table.remove(db.fights, 1) end
  if db.quiet then return end
  for i, line in ipairs(Coach.Lines(rec, cleanStreak(db.fights))) do
    if i == 1 then say(line) else print("  " .. line) end
  end
end

local function clickShare(fights, from, to)
  local keys, clicks = 0, 0
  for i = from, to do
    if fights[i] then keys, clicks = keys + fights[i].k, clicks + fights[i].c end
  end
  local total = keys + clicks
  return total > 0 and math.floor(clicks * 100 / total + 0.5) or nil
end

-- The trend over the remembered fights, and the single habit most worth fixing.
function Coach.Report()
  local fights = store().fights
  local lines = {}
  local n = #fights
  if n == 0 then
    lines[1] = "No fights recorded yet. A fight counts once it lasts six seconds."
    return lines
  end
  local recent = clickShare(fights, math.max(1, n - TREND + 1), n)
  local before = n > TREND and clickShare(fights, math.max(1, n - 2 * TREND + 1), n - TREND) or nil
  local line = ("Last %d fights: %d%% of your actions were clicks"):format(math.min(n, TREND), recent or 0)
  if before then
    line = line .. (recent < before and (", down from %d%% in the ten before."):format(before)
      or recent > before and (", up from %d%% in the ten before."):format(before) or ", the same as the ten before.")
  else
    line = line .. "."
  end
  lines[1] = line
  local streak = cleanStreak(fights)
  if streak >= 2 then lines[#lines + 1] = ("%d fights in a row without a click."):format(streak) end

  local totals = {}
  for i = math.max(1, n - 2 * TREND + 1), n do
    for _, row in ipairs(fights[i].clicked or {}) do
      local t = totals[row.slot] or { slot = row.slot, n = 0 }
      t.n, t.name = t.n + row.n, row.name or t.name
      totals[row.slot] = t
    end
  end
  local worst = sorted(totals)[1]
  if worst then
    local key = keyFor(worst.slot, ns.keysBySlot())
    lines[#lines + 1] = key and ("Drill this one: %s is on %s. You clicked it %d times lately."):format(worst.name or "that button", key, worst.n)
      or ("%s has no key and you clicked it %d times lately. It may deserve one."):format(worst.name or "A button", worst.n)
  end
  local gaps, long = 0, 0
  for i = math.max(1, n - TREND + 1), n do
    if fights[i].gap >= GAP then gaps = gaps + 1 end
    if fights[i].gap > long then long = fights[i].gap end
  end
  if gaps >= 3 then lines[#lines + 1] = ("In %d of them you went %d seconds or more without pressing anything (longest %.1f)."):format(gaps, GAP, long) end
  return lines
end

function Coach.Command(rest)
  local db = store()
  if rest == "off" then
    db.quiet = true
    say("The coach will stay quiet after fights. It still counts. /torch coach shows the trend.")
  elseif rest == "on" then
    db.quiet = nil
    say("The coach will speak after each fight again.")
  elseif rest == "reset" then
    db.fights = {}
    say("Fight history cleared.")
  else
    for i, line in ipairs(Coach.Report()) do
      if i == 1 then say(line) else print("  " .. line) end
    end
    print("  /torch coach off keeps it quiet after fights, /torch coach on brings it back.")
  end
end
