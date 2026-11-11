# Torch Binds changelog

## 8.2.4 — 2026-11-11
- A macro you save is yours, for good. The addon used to mark every macro it created "ours"
  forever, so an edit you saved over one (the recruiting ad above all) was rewritten back to
  the addon's text 8 seconds into every login. The record now keeps the exact text the addon
  last wrote: its own older text is brought up to date, but a standing text that is not the
  addon's is your save, and that macro is never written over again.
- The recruiting ad is the current one (the guild is True Torchmen, no "The"), on three
  macros: Recruit General (/1), Recruit Trade (/2), Recruit Yell (/y). The world-channel
  macro (/6) is retired and removed, but only while it still reads exactly what the addon
  wrote; a text you saved there stays.
- Tests: run 402 on both fixtures, v11 178, fuzz clean; new section replays the relog stomp,
  the upgrade from the old records, a save of yours standing under a stale record, and a
  deleted macro of yours staying deleted.

## 8.2.3 — 2026-11-10
- Never arrange against a bar system that is not serving. A cold login can hand the addon a
  client whose slots all read empty while PlaceAction is silently ignored; the 8.2.2 layout
  upgrade ran into exactly that at the first login of the day, rearranged the bars blind and
  dropped what each swap handed back (90 refused placements in one session, Polymorph and Feed
  among them). The binds side already had this defense (`barsReadable`, 8.2); the placement
  side now has it too: a character whose bars were arranged before cannot truly have 72 empty
  slots, so unreadable bars mean wait, not act. Setup, upkeep and respec all hold until the
  client serves, and the login upgrade retries itself until it lands.
- A pass the client half-refuses records nothing, so the whole layout is retried from the top
  instead of being declared done with holes in it. Manual `/torch setup` says what happened.
- Test fixtures carry the real character again (they still had the old troll mage from 8.1,
  which left the suite red while the checks expected the Forsaken); new cold-login section.
- Tests: run 383 on both fixtures, v11 178, fuzz clean.

## 8.2.2 — 2026-11-10
- Shift+R casts Arcane Missiles instead of the rank 1 Fireball downrank: the cheap-filler slot
  earns a real second nuke, and a fresh mage no longer gets a junk downrank before learning it.
  The `Fireball R1` macro is retired; found on a bar, it is replaced.
- LAYOUT_VERSION 14: one forced re-setup at next login.

## 8.2.1 — 2026-11-09
- Feed (the Forsaken Cannibalize macro) moves from Shift + thumb 6 to Shift + thumb 2. Thumb 2
  is also the pad's top row, so the hand that just finished the pack reaches it without the
  mouse; a button pressed over a corpse after every pull belongs there. Blast Wave, which held
  that square, takes thumb 6 instead: a mage outside the fire tree never learns it, and a spell
  that may never exist should not hold a key the pad can reach. Until you learn Blast Wave the
  square is empty and its key stays unbound, which is the addon's standing rule: a key is only
  bound while something lives on its square. That rule is also why dragging a spell onto an
  empty square shows no hotkey until the layout blesses it.
- LAYOUT_VERSION 13: one forced re-setup at next login moves Feed and binds Shift+2.
- Tests: run 378, v11 180, fuzz seeds clean.

## 8.2 — 2026-11-08
- The Alt layers (ALT and MALT) no longer live on Action Bars 6 and 7. The live Forever client
  silently refuses every placement into slots 145+, so since launch nothing had ever landed
  there: no Mage Armor, no racials, no buffs, and Alt keys that pressed empty squares. Each Alt
  key now presses a hidden secure button that casts its entry directly (spell, macro or item
  attribute); no action slot is involved, so the client's bar support no longer matters.
- `place()` verifies the slot after `PlaceAction` and writes a `place failed <label> @ <slot>`
  note when the client refused it. PlaceAction cannot say no; the empty slot afterwards is the
  only evidence, and before this the failure was invisible.
- LAYOUT_VERSION 12: one forced re-setup at next login, which also restores the
  potion/food/water/bandage row that had drifted (water was squatting the bandage key).
- Ranks are chosen by their real rank number now, not the client's low-rank flag, which the
  Forever client does not report reliably: that is what kept dropping a rank 1 Frost Armor on
  the key no matter how often you replaced it. A spell always binds at its highest known rank.
- When upkeep swaps a key to a different spell that supersedes what you dragged there, it now
  says so in chat: "Updated on your bars: Armor (replaces Frost Armor, which it outgrows)".
  Ice Armor wears the same icon as Frost Armor, so the silent swap read like a rank-1 bug.
- Tests: run 378, v11 180, fuzz 3 seeds clean; the harness learned to read the button layer.

## 8.1 — 2026-10-28

`Panel.lua`: the four numbers you otherwise keep opening bags and the character sheet to find,
on a thin strip you drag where you want it. `/torch panel`, plus `lock`, `unlock`, `reset`,
`report`, and `xp|gold|bags|dur off` to drop a part.

The bars are untouched. `LAYOUT_VERSION` stays at 11 on purpose, so installing this does not
re-apply your keybinds or move a single square.

### What it shows

| Part | Reads | Notes |
|---|---|---|
| experience | `UnitXP`, `UnitXPMax` | per hour, and how long the level has left at that pace. Says "max level" at 60 instead of a rate |
| gold | `GetMoney` | per hour and the session total. Goes negative and says so |
| bags | `C_Container.GetContainerNumSlots`, `GetContainerNumFreeSlots` | free of total, amber at 4 slots left, red at 0 |
| durability | `GetInventoryItemDurability` | the worst-worn equipped piece, amber at 35%, red at 15% |

### Why the rate is a rolling window and not a session average

An hour parked at the auction house would drag a session average to nothing and tell you
levelling is slower than it is. The headline rate comes from a **ten-minute** window and says
what your hands are doing now; the session total is kept beside it for the whole picture.
Nothing is extrapolated from under **two minutes** of play, because that figure would be noise.

### The level-up wrap

Experience falls back to nearly nothing on a level up and the maximum grows, so a raw
subtraction reads as a huge loss. `xpGained` keeps the previous sample's maximum and closes the
gap as `(oldMax - oldXP) + newXP`. Two level ups inside one window still add up. There is a test
for each case.

### A hidden value is a dash, never a zero

First draft had a real bug, caught by the new test: when the client hid experience, `rate()`
divided a zero total by a real span and the strip printed a confident `0/hr`. Each sample now
records whether the client actually answered, and a rate is refused outright if any sample in
the window came back hidden. "Warming up" and "the client will not say" are different answers and
no longer share a word.

### Verified

`tests/panel.lua tests/fixture-v3.lua` 46 checks, new: the two-minute floor, one and two level
ups mid-window, a negative gold rate, the worst-worn piece, an unworn slot never reading 0%, a
genuinely broken piece still reading 0%, hidden values showing a dash and landing in the probe,
every command, and the saved drag position. The older suites now load `Rested.lua` and
`Panel.lua` too: `tests/run.lua` 395, `tests/v11.lua` 222 on both fixtures, `tests/fuzz.lua`
300 sessions and 18,000 steps with 0 failures.

`tests/mock.lua` gained the player state those two files read, which nothing had stubbed before,
so **Rested.lua was never actually exercised either** — every one of its reads returned nil
through `try` and the module silently did nothing in the suites. It is loaded in all of them now.

### Not verified in game

Nothing in 8.1 has been run inside the client. Read `TorchBindsDB.panel.probe` after the first
session: it says per value whether the client answered. `GetInventoryItemDurability` is the one
read with no entry in Blizzard's generated API documentation, so it is the first to suspect.

## 8.0 — 2026-10-27

Built for an Undead mage levelling from 1 on the live WoW: Forever client (build
1.60.1.70634), rather than for the Troll frost mage of the beta.

### Installed where the game can actually see it

The live client is `_forever_`, not `_classic_beta_`. It was installed 2026-10-27 13:42
and played the same evening, and its `Interface/AddOns` folder was **empty** — every addon
was still sitting in the dead beta folder. Fixed outside this repo:

- `/home/yeeterson/projects/yeeterson-forge/forge.json` → `addon_dirs` now points at
  `_forever_/Interface/AddOns` (backup: `forge.json.bak-2026-10-27`). `yforge update`
  installed the six managed addons there.
- `/home/yeeterson/.config/wow-clipper/config.json` → `wow_dir` moved to `_forever_` and
  `process` changed from `WowB.exe` to `Wow.exe`, the live binary (backup:
  `config.json.bak-2026-10-27`). The clipper could never have recorded otherwise.

### A third key layer: Alt

Two bars were added, so each hand now has three layers and the pinky is still unused.

| Bar | Slots | Binding prefix | What presses it |
|---|---|---|---|
| ALT | 145-156 | `MULTIACTIONBAR5BUTTON` (Action Bar 6) | Alt + Q E R F Z X C and the thumb pad |
| MALT | 157-168 | `MULTIACTIONBAR6BUTTON` (Action Bar 7) | Alt + mouse thumb 1-12 |

**Alt lives on Tartarus pad key 11**, the pinky-column key directly above the Shift key at
16. It was doing nothing before. This is the sourced convention (Hazelnuttygames puts Shift
and Alt on the bottom-left two keys; `RESEARCH-2026-10-10.md` §3). Ctrl is still handed
back to the game untouched — the lazy-pinky rule did not change.

**Action Bars 6 and 7 must be switched on** under Options → Action Bars to see those
buttons. The keys work either way; the cooldowns do not show until they are visible.

`/torch look` only ever positioned bars 4 and 5 and still does.

### The spells follow your tree; the keys never move

`LAYOUT.MAGE.rows(spec)` is built on demand from `SPEC_ROWS`, read through
`C_SpecializationInfo.GetSpecializationInfo` (falling back to the `GetTalentTabInfo` shim).
A tree counts once it holds `SPEC_MIN` = 5 points; below that the `core` set runs, which is
why a level 1 mage is already fully bound.

Seven squares change with the tree. Everything else is identical in all three:

| Key | Job | Frost | Fire | Arcane |
|---|---|---|---|---|
| E | main nuke | Frostbolt | Fireball | Arcane Blast |
| R | follow-up | Ice Lance | Scorch | Arcane Missiles |
| X | panic | Ice Block | Ice Block | Ice Block |
| Shift+E | second nuke | **Frost Blast** | Pyroblast | Arcane Wrath |
| Shift+X | burst | Cold Snap | Combustion | Arcane Power |
| Alt+E | off-school nuke | Frostfire Bolt | Frostbolt | Frostbolt |
| Alt+Z | absorb | Ice Barrier | Ice Barrier | Ice Barrier |

A respec calls `respec()`, which replaces only those seven and records the old contents in
the same `/torch undo` log as every other change. It fires on `PLAYER_TALENT_UPDATE`,
`CHARACTER_POINTS_CHANGED`, `ACTIVE_TALENT_GROUP_CHANGED`, `PLAYER_SPECIALIZATION_CHANGED`
and `TRAIT_CONFIG_UPDATED`, and waits for the end of combat if you are in a fight.
`TorchBindsDB.specApplied` is the guard that stops it running on every point spent.
`/torch spec` says which tree is driving the bars.

### Forever's own mage spells

Read from the client's spell data and the beta export, build 1.60.1.70634, on 2026-10-27:

- **Frost Blast** (level 24, 1.5 s cast, 3 ranks, ids 1326053/1326054/1326055) now has a
  key: Shift+E in Frost, as a `/stopcasting` macro. It is what Nick meant by "the
  downranked Frostbolt": a baseline fast frost nuke, not a rank 1 trick. Rank 1 Frostbolt
  stays on thumb 11 for the slow.
- **Arcane Wrath** (level 25, id 1326079) and **Arcane Blast** (level 20, id 400574) drive
  the Arcane set; **Frostfire Bolt** (level 40, id 401502) is the off-school nuke.
- Ice Lance, Ice Block, Ice Barrier, Cold Snap, Pyroblast, Blast Wave, Combustion, Arcane
  Power and Presence of Mind are **talents** in Forever, not baseline. That is what the
  tree detection is reading.

### Race-aware racials

`RACE_ACTIVES` replaces the old single `first(...)` racial, which could only ever place one
button. An Undead mage has **two** racials worth a key:

- **Will of the Forsaken** → Alt+Q, as the `Free Me` macro so `/stopcasting` gets it out
  mid-Frostbolt when a fear lands.
- **Cannibalize** → Shift + thumb 6. In Forever it restores 7% mana as well as 7% health
  every 2 seconds, which makes it a mage button and not a flavour one.
- Touch of the Grave and Underwater Breathing are passive and never get a button.

Troll, Orc, Human, Gnome, Dwarf, Night Elf, Tauren and Skyborne are in the table too, and a
race it has not met still gets one racial button.

### Rested experience

New `Rested.lua`. `/torch rested` reports the banked pool as a share of a level and what it
is worth in kill experience, whether you are resting, and the key your Hearthstone is on.
One quiet line when the pool empties, never repeated until it refills.
`PLAYER_LEAVING_WORLD` records whether you logged out resting, so the next login can say
the slow rate was used. Reads `GetXPExhaustion`, `GetRestState`, `IsResting`, `UnitXP` and
`UnitXPMax`, all documented in this client; what it could and could not read goes to
`TorchBindsDB.rested.probe`.

### Everything bound

The click-bar pool now fills **bound keys before click-only squares**, so the first spell
you learn with no fixed home lands on a key instead of a button you forget exists. Order:
mouse thumb 9 and Shift + thumb 8 (bound and visible), then Bottom Right and the tail of
the Shift bar, then Alt + thumb 9-12 (bound, needs Action Bar 7), then Action Bar 8.

New macros: `Frost Blast!`, `Ice Block!` (a toggle: `/cancelaura` then `/cast`),
`Shield Off`, `Trinkets` (`/use 13` and `/use 14`, so the PvP trinket and any engineering
headpiece share one key), `Free Me`, `Feed`, `CS Mouseover`, `Poly Over`. Autorun is on
Num Lock and Home. A new `gadget` item kind binds the best engineering device in your bags
(Target Dummy, Flash Bomb, rocket boots, Discombobulator Ray, Death Ray, Dragonling) and
the `grenade` kind already catches Forever's SAF-T and EZ-Thro explosives by pattern.

### Fixed

- **`try()` truncated at five return values**, so `GetSpecializationInfo`'s seventh return,
  `pointsSpent`, always read as nil and the tree always looked empty. `specOf` now uses its
  own `pcall`. Without this the whole spec feature silently did nothing.
- **The click bars listed a spell again even when a fixed key already held it**, so Ice
  Barrier, Scorch and Mana Shield appeared twice. `poolSequence` now skips a utility entry
  whose spell the layout has already placed. Which spells those are depends on your tree,
  so the off-tree ones still get a button.
- **A macro name over 16 characters is refused by the client.** `Counterspell Over` was 17
  and failed silently; it is `CS Mouseover` now. Every macro name this file can create is
  checked.
- `grid()` filled only the thumb positions it was given, leaving holes that `ipairs` stops
  at. It now returns all twelve, empty as `false`.
- `barsReadable()` scanned slots 1-72 only, so the new Alt bars could not vote on whether
  the bars are readable at all. The v7.1 rule still holds: a failed or empty read never
  takes a key away.

### Verified

`tests/run.lua tests/fixture-v3.lua` 395 checks, `tests/v11.lua tests/fixture-v3.lua` 222
checks (new: the Undead racials, all three trees, the respec, no key on an empty square, no
spell on two keys, the three layers never colliding, a level 1 mage fully bound), five fuzz
soaks of 1500 sessions each, all clean. `tests/fixture-v5.lua` fails two checks — a
`pickup failed: item 213548` and the undo comparison — and the pre-8.0 code fails the same
two on that fixture, which is a post-install snapshot and fails the undo check by design.

**Not verified in game.** Nothing in 8.0 has been run inside the client. Read
`TorchBindsDB.log`, `lastSetup`, `bindCheck`, `specApplied` and `rested.probe` after the
first session; a `pickup failed` or `place failed` line is the first thing to chase.

### Rolling back

The 7.2 source is `TorchBinds.lua.pre-v8`; the 7.2 install is
`backups/TorchBinds-7.2-installed/`. Dropping `LAYOUT_VERSION` back to 10 makes the addon
leave the bars alone again. `/torch undo` puts the bars and binds back as they were.
