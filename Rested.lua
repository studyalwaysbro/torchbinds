-- Rested experience, because levelling a mage is the long part and rested XP is the only
-- multiplier you get for free. It doubles the experience from kills (never from quests), it
-- builds while you are logged out, and it builds four times faster if you logged out in an inn
-- or a capital city than anywhere else. So the one habit worth having is: hearth before you quit.
--
--   /torch rested         where your rested pool stands and whether you are resting
--   /torch rested off|on  stop or resume the reminders
--
-- Nothing here is guessed. Every number comes from the game's own XP functions, and when the
-- client will not answer, this file says nothing rather than inventing a figure. What it could
-- and could not read is written to TorchBindsDB.rested.probe: read that before believing a bug.

local ADDON, ns = ...
local say, note, plain, try = ns.say, ns.note, ns.plain, ns.try

local MAX_LEVEL = 60
local state = { nagged = false, lastPool = nil }

local function db()
  TorchBindsDB.rested = TorchBindsDB.rested or {}
  return TorchBindsDB.rested
end

-- A level's worth of experience, the rested pool, and how far through the level you are.
-- Any of these can come back hidden; a nil here means "do not print anything about it".
local function numbers()
  local max = tonumber(plain(try(UnitXPMax, "player")))
  local now = tonumber(plain(try(UnitXP, "player")))
  local pool = tonumber(plain(try(GetXPExhaustion)))
  return max, now, pool
end

-- 1 rested, 2 normal, 3 and up tired. The client only ever hands back a number here.
local function resting()
  local id = tonumber(plain(try(GetRestState)))
  local inn = plain(try(IsResting))
  return id, inn
end

local function level() return tonumber(plain(try(UnitLevel, "player"))) or 1 end

-- A rested pool is easiest to judge in levels, because the cap is one and a half of them.
local function asLevels(pool, max)
  if not (pool and max and max > 0) then return nil end
  return pool / max
end

-- The key your Hearthstone is on, so the reminder can name it instead of saying "your hearthstone".
local function hearthKey()
  local ok, keys = pcall(ns.keysBySlot)
  if not ok or type(keys) ~= "table" then return nil end
  for slot = 1, 180 do
    local kind, id = ns.slotInfo(slot)
    if kind == "item" and id == 6948 and keys[slot] and keys[slot][1] then return ns.prettyKey(keys[slot][1]) end
  end
  return nil
end

local function probe()
  local max, now, pool = numbers()
  local id = resting()
  db().probe = { xpMax = max and "readable" or "hidden", xp = now and "readable" or "hidden",
                 exhaustion = pool and "readable" or (GetXPExhaustion and "no pool" or "missing"),
                 restState = id and "readable" or "hidden", at = date("%Y-%m-%d %H:%M:%S") }
end

local function report()
  local max, now, pool = numbers()
  local id, inn = resting()
  if level() >= MAX_LEVEL then say("Level " .. MAX_LEVEL .. ": rested experience has nothing left to do.") return end
  if not max then say("The client is not answering about experience right now. Try again out of a loading screen.") return end

  if pool and pool > 0 then
    local levels = asLevels(pool, max)
    local line = ("Rested: %s experience banked"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(pool) or tostring(pool))
    if levels then line = line .. (", %.0f%% of a level"):format(levels * 100) end
    -- The pool is spent at double rate on kills, so it covers twice its own number in monster XP.
    say(line .. ". That is worth " .. (BreakUpLargeNumbers and BreakUpLargeNumbers(pool * 2) or tostring(pool * 2)) .. " experience from kills.")
    if levels and levels >= 1.45 then say("You are at the cap. Rested stops building until you spend some.") end
  else
    say("Rested: nothing banked. Kills are paying normal experience.")
  end

  if now and max then say(("This level: %d of %d, %.0f%% done."):format(now, max, now / max * 100)) end

  if inn then
    say("You are resting. Logging out here builds rested four times faster than the open world.")
  else
    say("You are not resting. An inn or a capital city builds rested four times faster: hearth before you log off"
        .. (hearthKey() and (" (" .. hearthKey() .. ")") or "") .. ".")
  end
  if db().loggedOutResting == false then
    say("Last time you logged out in the open world. That is the slow rate.")
  end
end

-- One quiet line, once, when the pool empties while you still have levels to go. Not a nag:
-- it never repeats until the pool has been refilled.
local function checkEmpty()
  if db().off or level() >= MAX_LEVEL then return end
  local max, _, pool = numbers()
  if not max then return end
  pool = pool or 0
  if pool > 0 then state.nagged = false state.lastPool = pool return end
  if state.lastPool and state.lastPool > 0 and not state.nagged then
    state.nagged = true
    say("Rested experience is spent. Kills are back to normal. Hearth to an inn before your next break"
        .. (hearthKey() and (", " .. hearthKey()) or "") .. ".")
  end
  state.lastPool = 0
end

local function onLogin()
  probe()
  if db().off or level() >= MAX_LEVEL then return end
  local max, _, pool = numbers()
  if not max then return end
  if pool and pool > 0 then
    local levels = asLevels(pool, max)
    say(("Rested: %s banked%s."):format(BreakUpLargeNumbers and BreakUpLargeNumbers(pool) or tostring(pool),
        levels and (", %.0f%% of a level"):format(levels * 100) or ""))
  elseif db().loggedOutResting == false then
    say("No rested experience: you logged out in the open world last time. An inn builds it four times faster.")
  end
  state.lastPool = pool or 0
end

local f = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_EXHAUSTION", "PLAYER_XP_UPDATE", "PLAYER_UPDATE_RESTING", "PLAYER_LEVEL_UP", "PLAYER_LEAVING_WORLD" }) do
  f:RegisterEvent(event)
end
f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    local initial = ...
    if initial then C_Timer.After(4, onLogin) end
  elseif event == "PLAYER_LEAVING_WORLD" then
    -- Remembered so the next login can say whether the slow rate was used.
    db().loggedOutResting = plain(try(IsResting)) and true or false
  else
    checkEmpty()
  end
end)

ns.Rested = { report = report, probe = probe }

ns.restedCommand = function(rest)
  if rest == "off" then db().off = true say("Rested reminders off.") return true end
  if rest == "on" then db().off = false say("Rested reminders on.") return true end
  report()
  return true
end
