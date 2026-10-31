-- Torch Binds curse caller: who in your group is cursed, in the middle of the screen and out loud.
--
--   Text    "CURSE  >  Shift+3" and the names under it, you first, for as long as anyone near you
--           is cursed. People too far away to reach are counted, not named.
--   Voice   one call when a curse lands, a different one when it is you, another when three or more
--           are cursed. Then a reminder now and then, three at most, and "all clean" when your
--           own decurse finished the job. In a raid everything is spaced further apart.
--
-- It only reads and shows: the Decurse key and click-to-decurse do the removing. It stays quiet
-- until you know Remove Lesser Curse, and while you are dead. If Forever hides debuff types from
-- addons it cannot work; what it could read is written to the saved file under curse.probe.

local ADDON, ns = ...
local plain, try, say = ns.plain, ns.try, ns.say

local Curse = {}
ns.Curse = Curse

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local SPELL = "Remove Lesser Curse"
local SOUNDS = "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\curse\\"
local VARIANTS = { self = 3, one = 3, many = 2, still = 3, clean = 3 }
local NAMES_MAX = 4
local REMINDERS = 3
-- seconds: `gap` between any two calls, `remind` before a reminder, `clean` = shortest curse worth an "all clean"
local PACE = { party = { gap = 5, remind = 10, clean = 2 }, raid = { gap = 10, remind = 18, clean = 3 } }

local frame, head, list, built
local episode            -- since the first curse: { since, reminders, mine, saidMany, saidSelf }
local lastVoice, lastClip = -100, nil
local pending            -- a call waiting for the gap to pass
local testing

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

local function opts()
  local db = TorchBindsDB
  if type(db.curse) ~= "table" then db.curse = {} end
  if type(db.curse.probe) ~= "table" then db.curse.probe = {} end
  return db.curse
end

local function probe(what, result)
  local p = opts().probe
  if p[what] ~= result then p[what] = result end
end

local function build()
  if built then return end
  built = true
  frame = CreateFrame("Frame", "TorchBindsCurseFrame", UIParent)
  frame:SetSize(520, 50)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 95)
  frame:SetFrameStrata("HIGH")
  head = frame:CreateFontString(nil, "OVERLAY")
  head:SetFont(FONT, 24, "OUTLINE")
  head:SetPoint("TOP", frame, "TOP", 0, 0)
  head:SetTextColor(0.72, 0.4, 1)
  head:Hide()
  list = frame:CreateFontString(nil, "OVERLAY")
  list:SetFont(FONT, 15, "OUTLINE")
  list:SetPoint("TOP", frame, "TOP", 0, -27)
  list:SetTextColor(0.92, 0.8, 1)
  list:Hide()
end

local function decurseKey()
  local best
  for slot, keys in pairs(ns.keysBySlot()) do
    local _, _, text = ns.slotInfo(slot)
    if (text == "Decurse" or text == SPELL) and (not best or #keys[1] < #best) then best = keys[1] end
  end
  return best and ns.prettyKey(best)
end

local function knowsSpell()
  local id = plain(try(C_Spell and C_Spell.GetSpellIDForSpellIdentifier, SPELL))
  if type(id) == "number" then return true end
  return plain(try(C_Spell and C_Spell.GetSpellInfo, SPELL)) ~= nil
end

-- true, false, or nil when the game hides debuff types
local function cursed(unit)
  local get = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex
  if not get then return nil end
  local hidden
  for i = 1, 40 do
    local ok, aura = pcall(get, unit, i, "HARMFUL")
    if not ok or aura == nil then break end
    if secret(aura) or type(aura) ~= "table" then hidden = true break end
    local kind = aura.dispelName
    if secret(kind) then hidden = true
    elseif kind == "Curse" then return true end
  end
  if hidden then return nil end
  return false
end

local function inRaid() return plain(try(IsInRaid)) == true end

local function groupUnits()
  local units = {}
  if inRaid() then
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
  else
    units[1] = "player"
    for i = 1, 4 do units[#units + 1] = "party" .. i end
  end
  return units
end

-- who is cursed: names within reach (you first), and how many are out of reach
local function scan()
  local near, far, me, sawHidden = {}, 0, false, false
  for _, unit in ipairs(groupUnits()) do
    local isMe = unit == "player" or plain(try(UnitIsUnit, unit, "player")) == true
    if plain(try(UnitExists, unit)) and plain(try(UnitIsDeadOrGhost, unit)) ~= true and (isMe or plain(try(UnitIsConnected, unit)) ~= false) then
      local has = cursed(unit)
      if has == nil then sawHidden = true
      elseif has then
        if isMe then
          me = true
        elseif plain(try(C_Spell and C_Spell.IsSpellInRange, SPELL, unit)) == false then
          far = far + 1
        else
          local name = plain((try(UnitName, unit)))
          near[#near + 1] = type(name) == "string" and name or "someone"
        end
      end
    end
  end
  probe("type", sawHidden and "hidden" or "readable")
  return near, far, me
end

local function voice(kind, now)
  lastVoice = now
  pending = nil
  local o = opts()
  if o.mute then return end
  local n = VARIANTS[kind]
  local pick = math.random(n)
  if n > 1 and kind .. pick == lastClip then pick = pick % n + 1 end
  lastClip = kind .. pick
  local ok, played = pcall(PlaySoundFile, SOUNDS .. kind .. pick .. ".ogg", "Master")
  probe("sound", (ok and plain(played) ~= false) and "played" or "refused")
end

local function clear()
  if head then head:Hide() list:Hide() end
end

local function draw(near, far, me)
  local key = decurseKey()
  head:SetText("CURSE" .. (key and ("   >   " .. key) or ""))
  head:Show()
  local names = {}
  if me then names[1] = "YOU" end
  for _, name in ipairs(near) do
    if #names < NAMES_MAX then names[#names + 1] = name end
  end
  local more = (me and 1 or 0) + #near - #names
  local text = table.concat(names, ",  ")
  if more > 0 then text = text .. ("  +%d more"):format(more) end
  if far > 0 then text = text .. (text ~= "" and "   " or "") .. ("(%d out of reach)"):format(far) end
  list:SetText(text)
  list:Show()
end

local function tick()
  if not TorchBindsDB or testing then return end
  local o = opts()
  local now = GetTime()
  if o.off or plain(try(UnitIsDeadOrGhost, "player")) == true or not knowsSpell() then
    episode, pending = nil, nil
    clear()
    return
  end
  local near, far, me = scan()
  local count = #near + (me and 1 or 0)
  local pace = inRaid() and PACE.raid or PACE.party
  if count == 0 then
    -- people out of reach keep the text up, with nothing to shout about
    if far > 0 then draw(near, far, me) else clear() end
    if episode then
      if far == 0 and episode.mine and now - episode.since >= pace.clean and now - lastVoice >= pace.gap then voice("clean", now) end
      if far == 0 then episode = nil end
    end
    pending = nil
    return
  end
  draw(near, far, me)
  local want
  if not episode then
    episode = { since = now, reminders = 0 }
    want = me and "self" or (count >= 3 and "many" or "one")
  elseif me and not episode.saidSelf then
    want = "self"
  elseif count >= 3 and not episode.saidMany then
    want = "many"
  elseif pending then
    want = pending
  elseif episode.reminders < REMINDERS and now - lastVoice >= pace.remind then
    want = "still"
  end
  if not want then return end
  if now - lastVoice < pace.gap then
    if want ~= "still" then pending = want end
    return
  end
  if want == "self" then episode.saidSelf = true end
  if want == "many" or count >= 3 then episode.saidMany = true end
  if me then episode.saidSelf = true end
  if want == "still" then episode.reminders = episode.reminders + 1 end
  voice(want, now)
end

local function onEvent(_, event, unit, _, spellID)
  if not TorchBindsDB then return end
  if event == "UNIT_SPELLCAST_SUCCEEDED" and plain(unit) == "player" and episode then
    if plain(try(C_Spell and C_Spell.GetSpellName, plain(spellID))) == SPELL then episode.mine = true end
  end
end

local started = false
function Curse.Init()
  if started then return end
  started = true
  build()
  local events = CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_SUCCEEDED")
  events:SetScript("OnEvent", function(...) pcall(onEvent, ...) end)
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.3, function() pcall(tick) end) end
  Curse.tick, Curse.onEvent = tick, onEvent -- unguarded, for the tests
end

function Curse.Command(rest)
  local o = opts()
  build()
  if rest == "off" then
    o.off = true
    clear()
    say("Curse caller off.")
  elseif rest == "on" then
    o.off = nil
    say("Curse caller on.")
  elseif rest == "voice off" or rest == "sound off" then o.mute = true say("Curse calls are silent now. The text still shows.")
  elseif rest == "voice on" or rest == "sound on" then o.mute = nil say("Curse calls are out loud again.")
  elseif rest == "test" then
    testing = true
    draw({ "Hyde", "Bueller" }, 1, true)
    local mute = o.mute
    o.mute = nil
    voice("self", GetTime())
    o.mute = mute
    C_Timer.After(6, function() testing = nil clear() end)
    say("This is where a curse shows, and one of the calls. It clears in six seconds.")
  else
    local p = o.probe
    say("Curse caller is " .. (o.off and "off" or "on") .. ", voice " .. (o.mute and "off" or "on") .. ".")
    if not knowsSpell() then print("  Quiet for now: you do not know " .. SPELL .. " yet.") end
    print("  Reading curses: " .. (p.type == "readable" and "working" or (p.type == "hidden" and "the game hides debuff types here, so it stays quiet" or "not checked yet")) .. ".")
    print("  Voice: " .. (p.sound == "played" and "working" or (p.sound == "refused" and "the game would not play the sound file" or "not heard yet")) .. ".")
    print("  /torch curse test    /torch curse off | on    /torch curse voice off | on")
  end
end
