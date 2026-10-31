-- The panel: rates, bags and durability. The two places a bug would actually hide are the level-up
-- wrap (experience falls back to nearly nothing, which a raw subtraction reads as a huge loss) and
-- the refusal to state a rate before there is enough play to mean anything.
-- lua tests/panel.lua tests/fixture-v3.lua
local svPath = assert(arg[1], "give the SavedVariables file")
dofile(svPath)
local passed, failed = 0, 0
local function check(c, label) if c then passed = passed + 1 else failed = failed + 1 io.write("FAIL: " .. label .. "\n") end end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
local function has(text, want, label) check(type(text) == "string" and text:find(want, 1, true) ~= nil, label .. " (got " .. tostring(text) .. ", wanted it to contain " .. want .. ")") end
local function lacks(text, want, label) check(type(text) ~= "string" or text:find(want, 1, true) == nil, label .. " (got " .. tostring(text) .. ", did not want " .. want .. ")") end

package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local G, fire = M.G, M.fire

local ns
local function load()
  local fresh = {}
  for i = #M.frames, 1, -1 do M.frames[i] = nil end
  G.tickers, G.timers, G.named = {}, {}, {}
  G.hide = {}
  G.now = 100
  G.xp = { cur = 0, max = 1000, exhaustion = nil, restState = 2, resting = false }
  G.money = 0
  G.durability = {}
  G.bagFree = { [0] = 40 }
  G.printed = {}
  TorchBindsDB = {}
  TryUseActionButton = function() end
  for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
                            "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
    for i = 1, 12 do _G[prefix .. i].scripts = {} end
  end
  for _, file in ipairs({ "TorchBinds.lua", "Stats.lua", "Coach.lua", "Alert.lua", "Curse.lua", "Look.lua", "Rested.lua", "Panel.lua" }) do
    assert(loadfile(file))("TorchBinds", fresh)
  end
  ns = fresh
end

-- Bring the panel up the way a login does, then let the ticker sample.
local function login() fire("PLAYER_ENTERING_WORLD", true) end
local function tick(seconds)
  G.now = G.now + (seconds or 10)
  for _, fn in ipairs(G.tickers) do fn() end
end
local function panel() return G.named["TorchBindsPanel"] end
local function part(i) local f = panel() return f and f.strings[i] and f.strings[i].text end
local XP, GOLD, BAGS, DUR = 1, 2, 3, 4

-- ---------------------------------------------------------------------------
load()
login()
check(panel() ~= nil, "the panel frame is built on login")
check(panel().shown, "the panel shows by default")
eq(panel().movable, true, "the panel can be dragged")
eq(panel().dragButton, "LeftButton", "dragging is on the left button")

-- A rate needs two minutes of play. Before that it says so rather than extrapolating from noise.
G.xp.cur = 400
tick(30)
has(part(XP), "warming up", "under two minutes the panel refuses to state an experience rate")
has(part(GOLD), "warming up", "under two minutes the panel refuses to state a gold rate")

-- 500 experience over 150 seconds is 12,000 an hour.
load() login()
G.xp.cur = 500
tick(150)
has(part(XP), "12.0k", "experience an hour is the gain over the window, scaled to an hour")
has(part(XP), "/hr", "the experience rate is labelled per hour")

-- 500 of 1000 done at 12,000 an hour is another 150 seconds, which reads as 2m.
has(part(XP), "to go", "the panel says how long the level has left")
has(part(XP), "2m", "time to level is the experience left divided by the current rate")

-- ---------------------------------------------------------------------------
-- The level-up wrap: experience falls to nearly nothing and the maximum grows.
load() login()
G.xp.cur = 900
tick(60)
G.xp.cur, G.xp.max = 200, 1400          -- levelled: 100 left in the old level, then 200 into the new one
tick(60)
-- 900 into the old level, then the last 100 of it plus 200 into the new one: 1200 over 120s.
local text = part(XP)
lacks(text, "-", "a level up never shows a negative experience rate")
has(text, "36.0k", "a level up counts the rest of the old level plus the new progress")

-- Two levels in one window still add up rather than cancelling out.
load() login()
G.xp.cur = 950
tick(60)
G.xp.cur, G.xp.max = 50, 1200
tick(60)
G.xp.cur, G.xp.max = 25, 1500
tick(60)
check(tonumber((part(XP):match("(%d+%.?%d*)k")) or 0) > 0, "two level ups in one window still read as a positive rate")

-- ---------------------------------------------------------------------------
-- Gold, including going backwards.
load() login()
G.money = 36000                          -- 3g 60s earned
tick(180)
has(part(GOLD), "/hr", "the gold rate is labelled per hour")
has(part(GOLD), "session", "the session total sits next to the rate")

-- A negative rate needs the window to end with less than it started with, so begin with gold
-- in the bag and then spend it.
load()
G.money = 10000
login()
G.money = 2000
tick(200)
has(part(GOLD), "-", "ending the window poorer than you started shows a negative gold rate")

-- ---------------------------------------------------------------------------
-- Bags.
load()
G.bagFree = { [0] = 7 }
login()
has(part(BAGS), "7", "free slots are counted")
has(part(BAGS), "40", "total slots are counted")

load()
G.bagFree = { [0] = 0 }
login()
has(part(BAGS), "bags", "a full bag still renders")

-- ---------------------------------------------------------------------------
-- Durability: the worst worn piece, and empty slots are not 0%.
load()
G.durability = { [1] = { 50, 100 }, [5] = { 10, 100 }, [16] = { 100, 100 } }
login()
has(part(DUR), "10%", "durability reports the worst-worn piece")

load()
G.durability = {}                        -- nothing worn at level 1
login()
has(part(DUR), "-", "a character with nothing worn shows a dash, not 0%")
lacks(part(DUR), "0%", "an empty slot is never read as broken")

load()
G.durability = { [16] = { 0, 100 } }     -- weapon actually broken
login()
has(part(DUR), "0%", "a genuinely broken piece does read 0%")

-- ---------------------------------------------------------------------------
-- Secret values: show a dash, record it, never invent a figure.
load()
G.hide.xp = true
G.hide.money = true
login()
tick(200)
lacks(part(XP), "/hr", "experience hidden by the client does not produce a rate")
eq(TorchBindsDB.panel.probe.xp, "hidden", "the probe records that experience was hidden")
eq(TorchBindsDB.panel.probe.money, "hidden", "the probe records that money was hidden")

load()
G.hide.durability = true
G.durability = { [1] = { 50, 100 } }
login()
has(part(DUR), "-", "durability hidden by the client shows a dash")

load() login()
eq(TorchBindsDB.panel.probe.xp, "readable", "the probe records a readable value too")
check(TorchBindsDB.panel.probe.at ~= nil, "the probe is stamped with a time")

-- ---------------------------------------------------------------------------
-- Commands.
load() login()
ns.panelCommand("dur off")
eq(part(DUR), "", "a part turned off renders nothing")
check(TorchBindsDB.panel.off.dur == true, "the dropped part is remembered")
ns.panelCommand("dur on")
check(TorchBindsDB.panel.off.dur == nil, "turning a part back on clears it")
check(part(DUR) ~= "", "a part turned back on renders again")

ns.panelCommand("")
check(not panel().shown, "the bare command hides a shown panel")
check(TorchBindsDB.panel.hidden == true, "being hidden is remembered")
ns.panelCommand("")
check(panel().shown, "the bare command shows it again")

ns.panelCommand("lock")
check(TorchBindsDB.panel.locked == true, "lock is remembered")
ns.panelCommand("unlock")
check(TorchBindsDB.panel.locked == nil, "unlock clears it")

-- Dragging saves a position; reset clears it.
load() login()
panel().point = { point = "CENTER", x = 120, y = -40 }
panel().scripts["OnDragStop"](panel())
eq(TorchBindsDB.panel.pos.point, "CENTER", "where you drop it is saved")
eq(TorchBindsDB.panel.pos.x, 120, "the saved position keeps its x")
ns.panelCommand("reset")
check(TorchBindsDB.panel.pos == nil, "reset forgets the saved position")

-- A locked panel refuses to start moving.
load() login()
ns.panelCommand("lock")
panel().scripts["OnDragStart"](panel())
check(true, "dragging a locked panel does not error")

-- Report prints rather than erroring, with or without enough samples.
load() login()
G.printed = {}
ns.panelCommand("report")
check(#G.printed > 0, "report prints without enough play to state a rate")
G.xp.cur = 300
tick(200)
G.printed = {}
ns.panelCommand("report")
check(#G.printed > 0, "report prints once there is a rate")

-- An unknown word is answered with the usage line, not silence.
load() login()
G.printed = {}
ns.panelCommand("wibble")
check(#G.printed > 0, "an unknown option prints the usage line")

-- ---------------------------------------------------------------------------
-- At the level cap the experience part stops pretending to be useful.
load()
G.level = 60
login()
has(part(XP), "max level", "at 60 the experience part says so instead of showing a rate")

io.write(passed .. " passed, " .. failed .. " failed\n")
if failed > 0 then os.exit(1) end
