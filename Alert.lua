-- Torch Binds alerts: three things worth seeing in the middle of the screen during a fight.
--
--   1. Your target or your focus starts a cast: big text, with the key that interrupts it.
--   2. Your Polymorph: a countdown, and a shout when it breaks early.
--   3. Enemy players who have you targeted: how many, and their classes.
--
-- An addon cannot set your focus or cast for you, so this only shows and sounds. Forever hides
-- some enemy information from addons ("secret" values). Each part checks what it is allowed
-- to read and goes quiet when it is not, and writes what it found to the saved file under
-- alert.probe so the limits can be read back afterwards.

local ADDON, ns = ...
local plain, try, say = ns.plain, ns.try, ns.say

local Alert = {}
ns.Alert = Alert

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local CAST_MAX = 12        -- a cast line never outlives this, in case the end of the cast is missed
local SHEEP_WARN = 5       -- seconds left when the countdown turns red
local SCAN_EVERY = 0.4
local POLY_SECONDS = { 20, 30, 40, 50 } -- by rank, used only when the game will not say
local SOUND_CAST, SOUND_BREAK, SOUND_ONYOU = 8959, 8960, 3081 -- raid warning, ready check, tell message

local frame, lines, built
local casting = {}         -- unit -> time the cast line went up
local sheep                -- { unit, guid, expires, live, name }
local broke                -- time the "broke" line went up
local onYou, scanOff = 0, false

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
-- true when there is a value at all, readable or not
local function present(v) return secret(v) or v ~= nil end

local function opts()
  local db = TorchBindsDB
  if type(db.alert) ~= "table" then db.alert = {} end
  if type(db.alert.probe) ~= "table" then db.alert.probe = {} end
  return db.alert
end

local function probe(what, result)
  local p = opts().probe
  if p[what] ~= result then p[what] = result end
end

local function sound(id)
  if opts().mute then return end
  try(PlaySound, id, "Master")
end

local function build()
  if built then return end
  built = true
  frame = CreateFrame("Frame", "TorchBindsAlertFrame", UIParent)
  frame:SetSize(520, 120)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 190)
  frame:SetFrameStrata("HIGH")
  lines = {}
  local function line(name, size, y, r, g, b)
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetPoint("TOP", frame, "TOP", 0, y)
    fs:SetTextColor(r, g, b)
    fs:Hide()
    lines[name] = fs
  end
  line("target", 26, 0, 1, 0.25, 0.2)
  line("targetSpell", 14, -28, 1, 0.85, 0.6)
  line("focus", 22, -46, 1, 0.55, 0.1)
  line("focusSpell", 13, -70, 1, 0.85, 0.6)
  line("sheep", 20, -88, 0.6, 0.85, 1)
  line("onYou", 16, -112, 1, 0.82, 0.35)
end

local function show(name, text)
  local fs = lines[name]
  fs:SetText(text)
  fs:Show()
end
local function hide(name) lines[name]:Hide() end

-- the key that interrupts: plain for the target, the focus macro for the focus
local function interruptKeys()
  local onTarget, onFocus
  for slot, keys in pairs(ns.keysBySlot()) do
    local _, _, text = ns.slotInfo(slot)
    if text == "Counterspell" or text == "Counterspell!" then
      if not onTarget or #keys[1] < #onTarget then onTarget = keys[1] end
    elseif text == "Counterspell Foc" then
      if not onFocus or #keys[1] < #onFocus then onFocus = keys[1] end
    end
  end
  return onTarget and ns.prettyKey(onTarget), onFocus and ns.prettyKey(onFocus)
end

local function hostile(unit)
  if not plain(try(UnitExists, unit)) then return false end
  local can = try(UnitCanAttack, "player", unit)
  if secret(can) then probe("hostile", "hidden") return false end
  return can and true or false
end

local function sameUnit(a, b)
  local same = try(UnitIsUnit, a, b)
  if secret(same) then return nil end
  return same and true or false
end

-- CASTS -----------------------------------------------------------------------
local function castInfo(unit)
  if type(UnitCastingInfo) == "function" then
    local ok, name, _, _, _, _, _, _, shielded = pcall(UnitCastingInfo, unit)
    if ok and present(name) then return name, shielded end
  end
  if type(UnitChannelInfo) == "function" then
    local ok, name, _, _, _, _, _, shielded = pcall(UnitChannelInfo, unit)
    if ok and present(name) then return name, shielded end
  end
end

local function castOff(unit)
  if not casting[unit] then return end
  casting[unit] = nil
  hide(unit)
  hide(unit .. "Spell")
end

local function castOn(unit, fromEvent)
  if not opts().off and hostile(unit) then
    local name, shielded = castInfo(unit)
    if not present(name) and not fromEvent then castOff(unit) return end
    probe("cast", secret(name) and "hidden name" or (name and "readable" or "event only"))
    if plain(shielded) == true then castOff(unit) return end -- cannot be interrupted: not worth the noise
    -- a focus that is also the target gets one line, the target's
    if unit == "focus" and casting.target and sameUnit("focus", "target") then return end
    if unit == "target" and casting.focus and sameUnit("focus", "target") then castOff("focus") end
    local onTarget, onFocus = interruptKeys()
    local key = unit == "target" and onTarget or onFocus
    local fresh = not casting[unit]
    casting[unit] = GetTime()
    show(unit, (unit == "target" and "TARGET CASTING" or "FOCUS CASTING") .. (key and ("   >   " .. key) or ""))
    if present(name) then
      -- a hidden name can still be handed to the game to draw; it just cannot be read here
      local fs = lines[unit .. "Spell"]
      if pcall(fs.SetText, fs, name) then fs:Show() end
    end
    if fresh and plain(try(UnitIsPlayer, unit)) then sound(SOUND_CAST) end
  else
    castOff(unit)
  end
end

-- POLYMORPH ------------------------------------------------------------------------
local function myPolymorph(unit, name)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil, "none" end
  local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HARMFUL|PLAYER")
  if not ok then return nil, "none" end
  if secret(aura) then return nil, "hidden" end
  if type(aura) ~= "table" then return nil, "absent" end
  local expires = aura.expirationTime
  if secret(expires) or type(expires) ~= "number" then return nil, "hidden" end
  return expires, "readable"
end

local function sheepOff()
  sheep = nil
  if not broke then hide("sheep") end
end

local function sheepStart(spellID)
  local name = plain(try(C_Spell and C_Spell.GetSpellName, spellID))
  if type(name) ~= "string" or not name:find("^Polymorph") then return end
  if opts().off then return end
  -- the smart Polymorph key goes to the focus when there is one; ask the game which of the two has it
  local order = hostile("focus") and { "focus", "target" } or { "target", "focus" }
  local unit, expires, state
  for _, u in ipairs(order) do
    if hostile(u) then
      local e, s = myPolymorph(u, name)
      state = state or s
      if e then unit, expires, state = u, e, s break end
    end
  end
  probe("sheep", state or "no unit")
  local live = expires ~= nil
  if not expires then
    unit = hostile(order[1]) and order[1] or (hostile(order[2]) and order[2]) or nil
    if not unit then return end
    local rank = tonumber((plain(try(C_Spell.GetSpellSubtext, spellID)) or ""):match("%d+")) or 1
    expires = GetTime() + (POLY_SECONDS[rank] or POLY_SECONDS[#POLY_SECONDS])
  end
  sheep = { unit = unit, guid = plain(try(UnitGUID, unit)), expires = expires, live = live, name = name }
  broke = nil
end

local function sheepTick(now)
  if broke then
    if now - broke > 2.5 then broke = nil hide("sheep") end
    return
  end
  if not sheep then return end
  if sheep.live then
    -- follow the sheep if it moved from target to focus or back; stop watching if it is on neither
    local unit
    for _, u in ipairs({ sheep.unit, sheep.unit == "focus" and "target" or "focus" }) do
      if sheep.guid and plain(try(UnitGUID, u)) == sheep.guid then unit = u break end
    end
    if unit then
      local expires, state = myPolymorph(unit, sheep.name)
      if expires then
        sheep.expires = expires
      elseif state == "absent" and sheep.expires - now > 1 then
        sheepOff()
        broke = now
        show("sheep", "SHEEP BROKE")
        lines.sheep:SetTextColor(1, 0.25, 0.2)
        sound(SOUND_BREAK)
        return
      end
    end
  end
  local left = sheep.expires - now
  if left <= 0 then sheepOff() return end
  show("sheep", (sheep.live and "Sheep " or "Sheep about ") .. math.ceil(left))
  if left <= SHEEP_WARN then lines.sheep:SetTextColor(1, 0.25, 0.2) else lines.sheep:SetTextColor(0.6, 0.85, 1) end
end

-- WHO IS ON YOU ----------------------------------------------------------------------
local function scan()
  if scanOff or opts().off or opts().noScan then
    if onYou > 0 then onYou = 0 hide("onYou") end
    return
  end
  local count, classes = 0, {}
  for i = 1, 40 do
    local unit = "nameplate" .. i
    if plain(try(UnitExists, unit)) and plain(try(UnitIsPlayer, unit)) and hostile(unit) then
      local onMe = try(UnitIsUnit, unit .. "target", "player")
      if secret(onMe) then
        -- the game will not say who an enemy is targeting: this part cannot work, stop asking
        probe("onYou", "hidden")
        scanOff = true
        onYou = 0
        hide("onYou")
        return
      end
      probe("onYou", "readable")
      if onMe then
        count = count + 1
        local class = plain((try(UnitClass, unit)))
        if type(class) == "string" then classes[#classes + 1] = class end
      end
    end
  end
  if count == 0 then
    if onYou > 0 then hide("onYou") end
  else
    show("onYou", ("%d ON YOU%s"):format(count, #classes > 0 and (":  " .. table.concat(classes, ", ")) or ""))
    if count > onYou then sound(SOUND_ONYOU) end
  end
  onYou = count
end

-- EVENTS ----------------------------------------------------------------------------
local START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
local STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_FAILED = true }

local function onEvent(_, event, unit, _, spellID)
  if not TorchBindsDB then return end
  unit = plain(unit)
  if START[event] then
    if unit == "target" or unit == "focus" then castOn(unit, true) end
  elseif STOP[event] then
    if unit == "target" or unit == "focus" then castOff(unit) end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    -- a moment later, so the sheep is already on the target when we look
    if unit == "player" then C_Timer.After(0.3, function() pcall(sheepStart, plain(spellID)) end) end
  elseif event == "PLAYER_TARGET_CHANGED" then
    castOn("target", false)
  elseif event == "PLAYER_FOCUS_CHANGED" then
    castOn("focus", false)
  end
end

local function tick()
  if not TorchBindsDB then return end
  local now = GetTime()
  for unit, since in pairs(casting) do
    if now - since > CAST_MAX then castOff(unit) end
  end
  sheepTick(now)
end

local started = false
function Alert.Init()
  if started then return end
  started = true
  build()
  local events = CreateFrame("Frame")
  for event in pairs(START) do pcall(events.RegisterEvent, events, event) end
  for event in pairs(STOP) do pcall(events.RegisterEvent, events, event) end
  for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED" }) do pcall(events.RegisterEvent, events, event) end
  events:SetScript("OnEvent", function(...) pcall(onEvent, ...) end)
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.2, function() pcall(tick) end)
    C_Timer.NewTicker(SCAN_EVERY, function() pcall(scan) end)
  end
  Alert.tick, Alert.scan, Alert.onEvent = tick, scan, onEvent -- unguarded, for the tests
end

local function status()
  local o = opts()
  local p = o.probe
  local function word(v, yes) return v == "readable" and yes or (v == "hidden" and "the game hides this, so it stays quiet") or "not seen yet" end
  say("Alerts are " .. (o.off and "off" or "on") .. ", sound " .. (o.mute and "off" or "on") .. ".")
  print("  Enemy casts: " .. ((p.cast == "readable" or p.cast == "hidden name" or p.cast == "event only") and "working" or "not seen yet") .. ".")
  print("  Polymorph countdown: " .. word(p.sheep, "exact, and it shouts when the sheep breaks") .. (p.sheep == "hidden" and " (it shows an estimate instead)" or "") .. ".")
  print("  Who is on you: " .. word(p.onYou, "working") .. ". It needs enemy nameplates switched on.")
  print("  /torch alert test = see where they appear    /torch alert off | on    /torch alert sound off | on    /torch alert scan off | on")
end

function Alert.Command(rest)
  local o = opts()
  build()
  if rest == "off" then
    o.off = true
    for unit in pairs(casting) do castOff(unit) end
    sheepOff()
    hide("onYou")
    say("Alerts off.")
  elseif rest == "on" then
    o.off = nil
    say("Alerts on.")
  elseif rest == "sound off" then o.mute = true say("Alert sounds off. The text still shows.")
  elseif rest == "sound on" then o.mute = nil say("Alert sounds on.")
  elseif rest == "scan off" then o.noScan = true say("No longer watching who has you targeted.")
  elseif rest == "scan on" then o.noScan, scanOff = nil, false say("Watching who has you targeted again.")
  elseif rest == "test" then
    local onTarget, onFocus = interruptKeys()
    show("target", "TARGET CASTING" .. (onTarget and ("   >   " .. onTarget) or ""))
    show("targetSpell", "Greater Heal")
    show("focus", "FOCUS CASTING" .. (onFocus and ("   >   " .. onFocus) or ""))
    show("focusSpell", "Flash Heal")
    show("sheep", "Sheep 12")
    show("onYou", "2 ON YOU:  Rogue, Warrior")
    sound(SOUND_CAST)
    C_Timer.After(6, function()
      for _, name in ipairs({ "target", "targetSpell", "focus", "focusSpell", "sheep", "onYou" }) do hide(name) end
    end)
    say("This is where the alerts appear. They clear in six seconds.")
  else
    status()
  end
end
