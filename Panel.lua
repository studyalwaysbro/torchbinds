-- Torch Binds panel: the four numbers you otherwise keep opening bags and character sheets to find.
--
--   experience  per hour, and how long this level has left at that pace
--   gold        per hour, and what the session has made or spent
--   bags        free slots, and a warning before you are actually full
--   durability  your worst-worn piece, because the first you hear of 0% is usually a dead mage
--
-- A thin strip, like Titan Panel, dragged wherever you want it. It only reads and shows.
--
--   /torch panel              show it, or hide it again
--   /torch panel lock|unlock  stop it being dragged, or allow it
--   /torch panel reset        put it back at the top of the screen
--   /torch panel <part> off   drop one part: xp, gold, bags, dur
--
-- Rates need a clock, and a clock is the part that is easy to get wrong. An hour parked at the
-- auction house would drag a session average down to nothing and tell you levelling is slower
-- than it is. So the headline rate comes from a ten-minute rolling window and says what your
-- hands are doing now; the session total is kept alongside it for the whole picture. Nothing is
-- extrapolated from fewer than two minutes of play, because that number would be noise.
--
-- Every figure comes from the game's own functions. When the client will not answer, the part
-- shows a dash rather than a guess, and what it could and could not read is written to
-- TorchBindsDB.panel.probe.

local ADDON, ns = ...
local say, note, plain, try = ns.say, ns.note, ns.plain, ns.try

local MAX_LEVEL = 60
local WINDOW = 600            -- seconds the rolling rate looks back over
local SAMPLE = 10             -- seconds between samples
local MIN_SPAN = 120          -- refuse to state a rate on less play than this
local BAG_WARN = 4            -- free slots at or below which bags turn amber
local DUR_WARN, DUR_BAD = 35, 15
local PARTS = { "xp", "gold", "bags", "dur" }

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local AMBER, RED, DIM, WHITE = "|cffffd35a", "|cffff5555", "|cff999999", "|cffffffff"

local frame, texts, built
local samples = {}            -- ring of { at, xp, money }, oldest first
local session = { xp = 0, money = 0, start = nil, lastXP = nil, lastMax = nil, lastMoney = nil }

local function db()
  TorchBindsDB.panel = TorchBindsDB.panel or {}
  local d = TorchBindsDB.panel
  if type(d.off) ~= "table" then d.off = {} end
  return d
end

-- ---------------------------------------------------------------------------
-- Reading the game
-- ---------------------------------------------------------------------------

local function level() return tonumber(plain(try(UnitLevel, "player"))) or 1 end

local function xpNow()
  local now = tonumber(plain(try(UnitXP, "player")))
  local max = tonumber(plain(try(UnitXPMax, "player")))
  return now, max
end

local function money() return tonumber(plain(try(GetMoney))) end

-- Forever carries the modern container API; the old globals are kept as a fallback so a client
-- that moved them again degrades to a dash instead of an error.
local function bagSlots()
  local free, total = 0, 0
  local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  if not (getSlots and getFree) then return nil end
  local any = false
  for bag = 0, 4 do
    local n = tonumber(plain(try(getSlots, bag)))
    if n and n > 0 then
      any = true
      total = total + n
      free = free + (tonumber(plain(try(getFree, bag))) or 0)
    end
  end
  if not any then return nil end
  return free, total
end

-- The worst-worn equipped piece, as a percentage. Empty and indestructible slots are skipped,
-- so a mage with no shield does not read as 0%.
local function durability()
  local fn = GetInventoryItemDurability
  if type(fn) ~= "function" then return nil end
  local worst, worstSlot = nil, nil
  for slot = 1, 18 do
    local cur, max = try(fn, slot)
    cur, max = tonumber(plain(cur)), tonumber(plain(max))
    if cur and max and max > 0 then
      local pct = cur / max * 100
      if not worst or pct < worst then worst, worstSlot = pct, slot end
    end
  end
  return worst, worstSlot
end

-- ---------------------------------------------------------------------------
-- The clock
-- ---------------------------------------------------------------------------

-- Experience wraps to nearly nothing on a level up, so a raw difference would read as a huge
-- loss. The previous level's maximum is kept from the last sample to close the gap properly.
local function xpGained(now, max)
  local last, lastMax = session.lastXP, session.lastMax
  session.lastXP, session.lastMax = now, max
  if not (last and now) then return 0 end
  if now >= last and max == lastMax then return now - last end
  if lastMax and now < last then return (lastMax - last) + now end  -- levelled
  return 0
end

local function sample()
  local now, max = xpNow()
  local m = money()
  if now then session.xp = session.xp + xpGained(now, max) end
  if m then
    if session.lastMoney then session.money = session.money + (m - session.lastMoney) end
    session.lastMoney = m
  end
  session.start = session.start or GetTime()
  -- Each sample remembers whether the client actually answered. A rate taken across a sample it
  -- could not read would understate the total and still look like a real number, which is worse
  -- than no number at all, so the gap is recorded and the rate is refused below.
  table.insert(samples, { at = GetTime(), xp = session.xp, money = session.money,
                          xpOk = now ~= nil, moneyOk = m ~= nil })
  while #samples > 1 and samples[1].at < GetTime() - WINDOW do table.remove(samples, 1) end
end

-- "Warming up" and "the client will not say" are different answers and should not share a word.
local function readable(field)
  local last = samples[#samples]
  return last ~= nil and last[field .. "Ok"] == true
end

-- Gained over the window, and the seconds it covers. Returns nil when there is not enough play
-- to say anything honest, or when the client hid the value at any point in the window.
local function rate(field)
  while #samples > 1 and samples[1].at < GetTime() - WINDOW do table.remove(samples, 1) end
  if #samples < 2 then return nil end
  local okField = field .. "Ok"
  for _, s in ipairs(samples) do
    if not s[okField] then return nil end
  end
  local first, last = samples[1], samples[#samples]
  local span = last.at - first.at
  if span < MIN_SPAN then return nil end
  return (last[field] - first[field]) / span * 3600, span
end

-- ---------------------------------------------------------------------------
-- The strip
-- ---------------------------------------------------------------------------

local function coin(copper)
  if not copper then return "-" end
  local sign = copper < 0 and "-" or ""
  local c = math.abs(math.floor(copper))
  local g, s = math.floor(c / 10000), math.floor(c % 10000 / 100)
  if g > 0 then return ("%s%dg %ds"):format(sign, g, s) end
  if s > 0 then return ("%s%ds %dc"):format(sign, s, c % 100) end
  return ("%s%dc"):format(sign, c % 100)
end

local function short(n)
  if not n then return "-" end
  if math.abs(n) >= 1000000 then return ("%.1fm"):format(n / 1000000) end
  if math.abs(n) >= 1000 then return ("%.1fk"):format(n / 1000) end
  return ("%d"):format(n)
end

local function clock(seconds)
  if not seconds or seconds <= 0 or seconds ~= seconds or seconds == math.huge then return nil end
  local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
  if h > 0 then return ("%dh %dm"):format(h, m) end
  return ("%dm"):format(math.max(m, 1))
end

local function xpText()
  if level() >= MAX_LEVEL then return DIM .. "max level|r" end
  if not readable("xp") then return DIM .. "xp  -|r" end
  local per = rate("xp")
  local now, max = xpNow()
  if not per then return DIM .. "xp  warming up|r" end
  local line = "xp " .. WHITE .. short(per) .. "/hr|r"
  -- Time to level is the number you actually act on, so it goes next to the rate.
  if now and max and per > 0 then
    local left = clock((max - now) / per * 3600)
    if left then line = line .. "  " .. DIM .. left .. " to go|r" end
  end
  return line
end

local function goldText()
  if not readable("money") then return DIM .. "gold  -|r" end
  local per = rate("money")
  if not per then return DIM .. "gold  warming up|r" end
  local colour = per < 0 and RED or WHITE
  return "gold " .. colour .. coin(per) .. "/hr|r  " .. DIM .. coin(session.money) .. " session|r"
end

local function bagsText()
  local free, total = bagSlots()
  if not free then return DIM .. "bags  -|r" end
  local colour = free == 0 and RED or (free <= BAG_WARN and AMBER or WHITE)
  return "bags " .. colour .. free .. "|r" .. DIM .. "/" .. total .. " free|r"
end

local function durText()
  local worst = durability()
  if not worst then return DIM .. "dur  -|r" end
  local colour = worst <= DUR_BAD and RED or (worst <= DUR_WARN and AMBER or WHITE)
  return "dur " .. colour .. ("%d%%"):format(worst) .. "|r"
end

local renderers = { xp = xpText, gold = goldText, bags = bagsText, dur = durText }

local function build()
  if built then return end
  built = true
  frame = CreateFrame("Frame", "TorchBindsPanel", UIParent, "BackdropTemplate")
  frame:SetSize(560, 22)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0.55)
    frame:SetBackdropBorderColor(0, 0, 0, 0.9)
  end
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not db().locked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    db().pos = { point = point, x = x, y = y }
  end)

  texts = {}
  local prev
  for _, part in ipairs(PARTS) do
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 12, "OUTLINE")
    fs:SetJustifyH("LEFT")
    if prev then fs:SetPoint("LEFT", prev, "RIGHT", 18, 0) else fs:SetPoint("LEFT", frame, "LEFT", 10, 0) end
    texts[part] = fs
    prev = fs
  end

  local p = db().pos
  if p then frame:SetPoint(p.point, UIParent, p.point, p.x, p.y)
  else frame:SetPoint("TOP", UIParent, "TOP", 0, -4) end
end

local function refresh()
  if not built or not frame:IsShown() then return end
  for _, part in ipairs(PARTS) do
    texts[part]:SetText(db().off[part] and "" or renderers[part]())
  end
  -- Re-flow so a dropped part does not leave a gap.
  local prev
  for _, part in ipairs(PARTS) do
    local fs = texts[part]
    fs:ClearAllPoints()
    if db().off[part] then
      fs:SetPoint("LEFT", frame, "LEFT", 0, 0)
    elseif prev then
      fs:SetPoint("LEFT", prev, "RIGHT", 18, 0)
      prev = fs
    else
      fs:SetPoint("LEFT", frame, "LEFT", 10, 0)
      prev = fs
    end
  end
end

local function probe()
  local now, max = xpNow()
  local free = bagSlots()
  local worst = durability()
  db().probe = {
    xp = now and "readable" or "hidden",
    xpMax = max and "readable" or "hidden",
    money = money() and "readable" or "hidden",
    bags = free and "readable" or (C_Container and "hidden" or "no C_Container"),
    durability = worst and "readable" or (GetInventoryItemDurability and "nothing worn, or hidden" or "missing"),
    at = date("%Y-%m-%d %H:%M:%S"),
  }
end

local function show(on)
  build()
  db().hidden = (not on) or nil
  if on then frame:Show() refresh() else frame:Hide() end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, _, initial)
  if not initial then return end
  C_Timer.After(4, function()
    probe()
    sample()
    if not db().hidden then show(true) end
    C_Timer.NewTicker(SAMPLE, function() sample() refresh() end)
  end)
end)

local function report()
  local per = rate("xp")
  local span = select(2, rate("xp"))
  say("Panel: " .. (db().hidden and "hidden" or "shown") .. (db().locked and ", locked" or "") .. ".")
  if per and span then
    say(("Over the last %s: %s experience an hour, %s."):format(clock(span) or "while", short(per), coin(rate("money") or 0) .. " an hour"))
  else
    say("Not enough play yet to state a rate. It needs two minutes.")
  end
  say(("Session so far: %s experience, %s."):format(short(session.xp), coin(session.money)))
  local free, total = bagSlots()
  local worst, slot = durability()
  say(("Bags: %s free of %s. Worst-worn piece: %s."):format(free or "-", total or "-",
      worst and (("%d%%"):format(worst) .. (slot and (" (slot " .. slot .. ")") or "")) or "-"))
end

ns.Panel = { refresh = refresh, probe = probe, report = report }

ns.panelCommand = function(rest)
  rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local word, tail = rest:match("^(%S+)%s*(%S*)$")
  if rest == "" then show(db().hidden and true or false) say(db().hidden and "Panel hidden." or "Panel shown. Drag it where you want it.") return true end
  if rest == "lock" then db().locked = true say("Panel locked.") return true end
  if rest == "unlock" then db().locked = nil say("Panel unlocked: drag it with the left mouse button.") return true end
  if rest == "reset" then
    db().pos = nil
    if built then frame:ClearAllPoints() frame:SetPoint("TOP", UIParent, "TOP", 0, -4) end
    say("Panel back at the top of the screen.")
    return true
  end
  if rest == "report" or rest == "now" then report() return true end
  if word and renderers[word] then
    if tail == "off" then db().off[word] = true say(word .. " dropped from the panel.")
    elseif tail == "on" then db().off[word] = nil say(word .. " back on the panel.")
    else say(word .. " is " .. (db().off[word] and "off" or "on") .. ". Add off or on to change it.") end
    refresh()
    return true
  end
  say("/torch panel = show or hide. Also lock, unlock, reset, report, and xp|gold|bags|dur off.")
  return true
end
