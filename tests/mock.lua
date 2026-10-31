-- A stand-in for the game client: bars, spellbook, bags, macros, bindings, click casting, timers.
-- the game ------------------------------------------------------------------------
local G = { slots = {}, book = {}, cursor = nil, binds = {}, combat = false, timers = {}, printed = {}, macros = {}, saves = 0, now = 100,
            bags = { [929] = 3, [1114] = 20, [2136] = 20, [3531] = 13, [213550] = 5, [217495] = 1, [277484] = 5, [1478] = 2, [277485] = 3, [5514] = 1, [4593] = 9, [4592] = 4, [6948] = 1 },
            clicks = {}, buttons = {}, hooks = {}, placeCalls = 0 }
local ITEM = { [118] = { "Minor Healing Potion", 1 }, [858] = { "Lesser Healing Potion", 3 }, [929] = { "Healing Potion", 12 }, [1710] = { "Greater Healing Potion", 21 },
               [3928] = { "Superior Healing Potion", 35 }, [1114] = { "Conjured Rye", 5 }, [1487] = { "Conjured Pumpernickel", 15 }, [2136] = { "Conjured Purified Water", 15 },
               [3772] = { "Conjured Spring Water", 25 }, [3531] = { "Heavy Wool Bandage", 1 }, [6450] = { "Silk Bandage", 1 }, [213550] = { "Scroll of Polymorph: Odd Melon", 1 },
               [217495] = { "Scroll of Cryoblast", 16 }, [277499] = { "Scroll of Greater Cryoblast", 46 }, [277484] = { "Scroll of Confuse Beast", 1 }, [1478] = { "Scroll of Protection II", 1 }, [277485] = { "Scroll of Imbue Frost", 1 },
               [5514] = { "Mana Agate", 1 }, [4593] = { "Bristle Whisker Catfish", 1 }, [4592] = { "Longjaw Mud Snapper", 1 }, [6948] = { "Hearthstone", 1 },
               [3827] = { "Mana Potion", 22 }, [4390] = { "Iron Grenade", 1 }, [900001] = { "Glacial Healing Potion", 28 }, [900002] = { "Titanic Healing Potion", 55 },
               [5655] = { "Chestnut Mare Bridle", 40, 15, 5 } }
local spellName = { [7731] = "Fishing" }

print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end G.printed[#G.printed + 1] = table.concat(t, " ") end
function strlower(s) return s:lower() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function date(fmt) return fmt == "%b %d" and "Oct 10" or "2026-10-10 21:00:00" end
function time() return 1791680000 end
function GetTime() return G.now end
function InCombatLockdown() return G.combat end
function UnitClass(unit) local u = unit and unit ~= "player" and G.units and G.units[unit] if u then return u.class end return "Mage", G.class or "MAGE" end
function UnitRace() return G.raceName or "Troll", G.race or "Troll" end
-- The talent trees, as Forever reports them. G.spec is how many points are in each tree.
C_SpecializationInfo = {
  GetSpecializationInfo = function(i)
    local tree = ({ "Arcane", "Fire", "Frost" })[i]
    if not tree then return nil end
    return i, tree, "", 0, nil, nil, (G.spec and G.spec[tree:lower()]) or 0
  end,
}
function UnitLevel() return G.level or 29 end
function UnitFactionGroup() return "Horde" end
function GetRealmName() return "Classic Beta PvP" end
function GetBuildInfo() return "1.60.1", "70338", "", 16001 end
function GetCurrentBindingSet() return 1 end
function SetBinding(key, command) assert(not G.combat, "bindings are locked in combat") G.binds[key] = command return true end
function GetBindingAction(key) return G.binds[key] or "" end
function GetBindingKey(command) for key, c in pairs(G.binds) do if c == command then return key end end end
function SaveBindings(set) assert(set == 1 or set == 2) G.saves = G.saves + 1 end
function GetActionInfo(slot) local a = G.slots[slot] if a then return a.kind, a.id end end
function ClearCursor() G.cursor = nil end
function GetCursorInfo() if G.cursor then return G.cursor.kind, G.cursor.id end end
function PickupAction(slot) assert(not G.combat, "protected in combat") G.cursor, G.slots[slot] = G.slots[slot], nil end
function PlaceAction(slot) assert(not G.combat, "protected in combat") assert(G.cursor, "nothing on the cursor") G.placeCalls = G.placeCalls + 1 G.slots[slot], G.cursor = G.cursor, G.slots[slot] end
function PickupMacro(name) if G.macros[name] then G.cursor = { kind = "macro", id = 1, text = name } end end
function GetMacroIndexByName(name) return G.macros[name] and 1 or 0 end
function GetMacroBody(name) return G.macros[name] end
function EditMacro(name, _, _, body) assert(not G.combat) assert(#name <= 16 and #body <= 255, "macro too long: " .. name) G.macros[name] = body end
function CreateMacro(name, _, body) assert(not G.combat) assert(#name <= 16 and #body <= 255, "macro too long: " .. name) G.macros[name] = body end
function hooksecurefunc(a, b, c)
  local tbl, name, hook = _G, a, b
  if type(a) == "table" then tbl, name, hook = a, b, c end
  local original = tbl[name]
  tbl[name] = function(...) local r = { original(...) } pcall(hook, ...) return unpack(r) end
end
function TryUseActionButton(button, down) end
C_ActionBar = { HasAction = function(slot) return G.slots[slot] ~= nil end, GetActionText = function(slot) return G.slots[slot] and G.slots[slot].text end }
C_Spell = { GetSpellName = function(id) return spellName[id] end, GetSpellSubtext = function() return "" end,
            PickupSpell = function(id) if spellName[id] then G.cursor = { kind = "spell", id = id } end end }
C_Item = { PickupItem = function(id) if (G.bags[id] or 0) > 0 then G.cursor = { kind = "item", id = id } end end,
           GetItemNameByID = function(id) return ITEM[id] and ITEM[id][1] end,
           GetItemInfo = function(id) local it = ITEM[id] if it then return it[1], "link", 1, 1, it[2] end end,
           GetItemInfoInstant = function(id) local it = ITEM[id] if it then return id, "t", "s", "", 1, it[3] or 0, it[4] or 0 end end }
C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 40 or 0 end,
                GetContainerItemID = function(bag, slot) local n = 0 for id, count in pairs(G.bags) do if count > 0 then n = n + 1 if n == slot then return id end end end end }
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 }, ClickBindingType = { Spell = 1 } }
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() local n = 0 for slot in pairs(G.book) do if slot > n then n = slot end end return { name = "All", itemIndexOffset = 0, numSpellBookItems = n } end,
  GetSpellBookItemInfo = function(slot) return G.book[slot] end,
  IsSpellBookItemLowRank = function(slot)
    local me = G.book[slot]
    for other, item in pairs(G.book) do if item.name == me.name and other > slot and item.itemType == 1 then return true end end
    return false
  end,
  PickupSpellBookItem = function(slot) local item = G.book[slot] if item and item.itemType == 1 then G.cursor = { kind = "spell", id = item.spellID } end end,
}
C_ClickBindings = { GetProfileInfo = function() local copy = {} for i, b in ipairs(G.clicks) do copy[i] = b end return copy end,
                    SetProfileByInfo = function(profile) assert(not G.combat) G.clicks = profile end }
function GetStringFromModifiers(bits) return ({ [1] = "ALT", [2] = "CTRL", [4] = "SHIFT" })[bits] or "" end
-- Edit Mode: the game's own presets come first, then the player's layouts
local function barSystems()
  local list = {}
  for i = 1, 8 do
    list[i] = { system = 0, systemIndex = i, isInDefaultPosition = true, settings = { { setting = 0, value = (i == 4 or i == 5) and 1 or 0 }, { setting = 1, value = 1 }, { setting = 2, value = 12 } },
                anchorInfo = { point = "RIGHT", relativeTo = "UIParent", relativePoint = "RIGHT", offsetX = -5 * i, offsetY = 0 } }
  end
  list[9] = { system = 3, isInDefaultPosition = true, settings = {}, anchorInfo = { point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "TOPLEFT", offsetX = 4, offsetY = -4 } }
  return list
end
G.edit = { layouts = {}, activeLayout = 2, saves = 0 }
local function deep(v) if type(v) ~= "table" then return v end local o = {} for k, x in pairs(v) do o[k] = deep(x) end return o end
EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return { { layoutName = "Modern", layoutType = 0, systems = barSystems() }, { layoutName = "Classic", layoutType = 0, systems = barSystems() } } end }
C_EditMode = {
  GetLayouts = function() return { layouts = deep(G.edit.layouts), activeLayout = G.edit.activeLayout } end,
  SaveLayouts = function(info)
    assert(not G.combat, "Edit Mode is locked in combat")
    local kept = {}
    for _, layout in ipairs(info.layouts) do
      if layout.layoutType ~= 0 then
        assert(type(layout.layoutName) == "string" and type(layout.systems) == "table", "malformed layout")
        for _, system in ipairs(layout.systems) do assert(system.anchorInfo and system.anchorInfo.point and system.settings and system.isInDefaultPosition ~= nil, "malformed system") end
        kept[#kept + 1] = deep(layout)
      end
    end
    G.edit.layouts, G.edit.saves = kept, G.edit.saves + 1
  end,
  SetActiveLayout = function(i) assert(not G.combat) assert(i >= 1 and i <= 2 + #G.edit.layouts, "no such layout") G.edit.activeLayout = i end,
  OnLayoutAdded = function(i, activate) assert(i >= 3 and i <= 2 + #G.edit.layouts, "no such layout") if activate then G.edit.activeLayout = i end end,
  IsValidLayoutName = function(name) return #name > 0 and #name <= 31 end,
}
Enum.EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2 }
Enum.EditModeSystem = { ActionBar = 0 }
Enum.EditModeLayoutType = { Preset = 0, Account = 1, Character = 2 }
Constants = { EditModeConsts = { EditModeMaxLayoutsPerType = 5 } }
local function fontString()
  local fs = { shown = true }
  fs.SetPoint, fs.SetFont, fs.SetTextColor = function() end, function() end, function(self, r, g, b) self.color = { r, g, b } end
  fs.ClearAllPoints, fs.SetJustifyH, fs.SetJustifyV, fs.SetWidth = function() end, function() end, function() end, function() end
  fs.SetText = function(self, t) self.text = t end
  fs.GetText = function(self) return self.text end
  fs.Show = function(self) self.shown = true end
  fs.Hide = function(self) self.shown = false end
  return fs
end
UIParent = { CreateFontString = fontString }
MultiBarRight, MultiBarLeft = {}, {}
C_Timer = { After = function(delay, fn) G.timers[#G.timers + 1] = fn end,
            NewTicker = function(every, fn) G.tickers[#G.tickers + 1] = fn end }
-- other units: G.units.target = { hostile = true, player = true, class = "Priest", guid = "p1", target = "player", cast = "Heal", auras = { Polymorph = 130 } }
-- G.hide names the things the game answers with a secret value
G.units, G.hide, G.sounds, G.tickers, G.named = {}, {}, {}, {}, {}
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
G.SECRET = SECRET
function issecretvalue(v) return v == SECRET end
local function resolve(unit)
  if unit == "player" then return { guid = "me" } end
  local base = unit:match("^(.+)target$")
  if base and G.units[base] then return G.units[base].target and resolve(G.units[base].target) end
  return G.units[unit]
end
function UnitExists(unit) return resolve(unit) ~= nil end
function UnitCanAttack(_, unit) if G.hide.hostile then return SECRET end local u = resolve(unit) return u and u.hostile or false end
function UnitIsPlayer(unit) local u = resolve(unit) return u and u.player or false end
function UnitGUID(unit) local u = resolve(unit) return u and u.guid end
function UnitIsUnit(a, b)
  if G.hide.compare then return SECRET end
  local x, y = resolve(a), resolve(b)
  return x ~= nil and y ~= nil and x.guid == y.guid
end
function UnitCastingInfo(unit)
  local u = resolve(unit)
  if not (u and u.cast) then return nil end
  return G.hide.cast and SECRET or u.cast, "", 1, 0, 0, false, "guid", u.shielded or false
end
function UnitChannelInfo(unit)
  local u = resolve(unit)
  if not (u and u.channel) then return nil end
  return u.channel, "", 1, 0, 0, false, u.shielded or false
end
C_UnitAuras = { GetAuraDataBySpellName = function(unit, name)
  if G.hide.aura then return SECRET end
  local u = resolve(unit)
  local expires = u and u.auras and u.auras[name]
  return expires and { expirationTime = expires } or nil
end }
function PlaySound(id) G.sounds[#G.sounds + 1] = id end
-- group members: G.units.party1 = { name = "Hyde", guid = "h", debuffs = { "Curse", "Magic" }, far = true, dead = true }
G.files, G.raid, G.knows = {}, false, { ["Remove Lesser Curse"] = 475 }
function PlaySoundFile(path) G.files[#G.files + 1] = path return true end
function IsInRaid() return G.raid end
function UnitIsDeadOrGhost(unit) if unit == "player" then return G.dead or false end local u = resolve(unit) return u and u.dead or false end
function UnitIsConnected(unit) local u = resolve(unit) return u ~= nil and not u.offline end
function UnitName(unit) if unit == "player" then return "Wesheavyn" end local u = resolve(unit) return u and u.name end
C_UnitAuras.GetDebuffDataByIndex = function(unit, i)
  local list = unit == "player" and G.myDebuffs or (resolve(unit) or {}).debuffs
  local kind = list and list[i]
  if kind == nil then return nil end
  if G.hide.debuff then return SECRET end
  return { name = "Something", dispelName = G.hide.dispel and SECRET or (kind ~= "" and kind or nil) }
end
C_Spell.GetSpellIDForSpellIdentifier = function(name) return G.knows[name] end
C_Spell.IsSpellInRange = function(_, unit) local u = resolve(unit) if not u then return nil end return not u.far end
C_AddOns = {}
local frames = {}
function CreateFrame(_, name)
  local f = { events = {}, strings = {}, shown = true, scripts = {} }
  f.RegisterEvent = function(_, e) f.events[e] = true end
  f.UnregisterEvent = function(_, e) f.events[e] = nil end
  f.SetScript = function(self, which, fn)
    -- OnEvent stays on .handler because every older test drives frames through it.
    if which == "OnEvent" or which == nil then f.handler = fn end
    f.scripts[which or "OnEvent"] = fn
  end
  f.SetSize, f.SetFrameStrata = function() end, function() end
  f.SetPoint = function(self, point, _, _, x, y) self.point = { point = point, x = x, y = y } end
  f.ClearAllPoints = function(self) self.point = nil end
  f.GetPoint = function(self)
    local p = self.point or {}
    return p.point, UIParent, p.point, p.x or 0, p.y or 0
  end
  -- A movable strip needs these; they record rather than draw so a test can assert on them.
  f.SetMovable = function(self, v) self.movable = v end
  f.SetClampedToScreen = function() end
  f.RegisterForDrag = function(self, button) self.dragButton = button end
  f.StartMoving, f.StopMovingOrSizing = function() end, function() end
  f.SetBackdrop, f.SetBackdropColor, f.SetBackdropBorderColor = function() end, function() end, function() end
  f.Show = function(self) self.shown = true end
  f.Hide = function(self) self.shown = false end
  f.IsShown = function(self) return self.shown end
  f.CreateFontString = function() local fs = fontString() f.strings[#f.strings + 1] = fs return fs end
  if name then G.named[name] = f end
  frames[#frames + 1] = f
  return f
end
for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton",
                          "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
  for i = 1, 12 do
    local b = { scripts = {} }
    b.HookScript = function(self, name, fn) self.scripts[name] = fn end
    _G[prefix .. i] = b
  end
end
local FIRST = { ActionButton = 1, MultiBarBottomLeftButton = 61, MultiBarBottomRightButton = 49, MultiBarRightButton = 25, MultiBarLeftButton = 37,
                MultiBar5Button = 145, MultiBar6Button = 157, MultiBar7Button = 169 }
for prefix, first in pairs(FIRST) do for i = 1, 12 do _G[prefix .. i].action = first + i - 1 end end
SlashCmdList = {}
local function runTimers() local guard = 0 while #G.timers > 0 and guard < 300 do guard = guard + 1 table.remove(G.timers, 1)() end end
local function fire(event, ...) for _, f in ipairs(frames) do if f.events[event] and f.handler then f.handler(f, event, ...) end end runTimers() end
local function at(slot) local a = G.slots[slot] if not a then return "-" end return a.kind == "macro" and a.text or (a.kind == "spell" and (spellName[a.id] or ("spell:" .. a.id)) or (ITEM[a.id] and ITEM[a.id][1] or ("item:" .. a.id))) end
local function rank(slot) return G.slots[slot] and G.slots[slot].id end
local KEYS = { "1", "2", "3", "4", "5", "Q", "E", "R", "F", "Z", "X", "C" }
local function row(first) local t = {} for i = 0, 11 do t[#t + 1] = KEYS[i + 1] .. "=" .. at(first + i) end return table.concat(t, " | ") end
local function whereIs(name) for slot = 1, 180 do if at(slot) == name then return slot end end end
local function press(prefix, i) G.now = G.now + 1 TryUseActionButton(_G[prefix .. i], true) TryUseActionButton(_G[prefix .. i], false) end
local function click(prefix, i)
  G.now = G.now + 1
  local b = _G[prefix .. i]
  if b.scripts.OnClick then b.scripts.OnClick(b, "LeftButton", true) b.scripts.OnClick(b, "LeftButton", false) end
end


-- Player state the panel and the rested reminder read. Defaults are a level 1 mage with nothing
-- banked and nothing worn, so a test that does not care about these sees the same empty character
-- every run. G.hide works on all of them through the usual secret-value path.
G.xp = { cur = 0, max = 1000, exhaustion = nil, restState = 2, resting = false }
G.money = 0
G.durability = {}   -- slot -> { current, maximum }; an absent slot is an empty or indestructible one
G.bagFree = { [0] = 40 }

local function maybeHidden(name, v) if G.hide[name] then return G.SECRET end return v end

function UnitXP(unit) if unit ~= "player" then return 0 end return maybeHidden("xp", G.xp.cur) end
function UnitXPMax(unit) if unit ~= "player" then return 0 end return maybeHidden("xpMax", G.xp.max) end
function GetXPExhaustion() return maybeHidden("exhaustion", G.xp.exhaustion) end
function GetRestState() return maybeHidden("restState", G.xp.restState) end
function IsResting() return maybeHidden("resting", G.xp.resting) end
function GetMoney() return maybeHidden("money", G.money) end
function GetInventoryItemDurability(slot)
  local d = G.durability[slot]
  if not d then return nil end
  return maybeHidden("durability", d[1]), maybeHidden("durability", d[2])
end
C_Container.GetContainerNumFreeSlots = function(bag) return maybeHidden("bagFree", G.bagFree[bag] or 0), 0 end
function BreakUpLargeNumbers(n) return tostring(n) end

return { G = G, ITEM = ITEM, spellName = spellName, frames = frames, runTimers = runTimers, fire = fire, at = at, rank = rank, row = row,
         whereIs = whereIs, press = press, click = click, KEYS = KEYS }
