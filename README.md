# Torch Binds

A whole control setup for **World of Warcraft: Forever**, built for a keypad and an MMO mouse, or just a keyboard.

Made by **The True Torchmen**. For the Horde.

## What it does

- **Three layers of keys, bound for you.** Plain, Shift and Alt across the pad keys, Q E R F Z X C and the twelve mouse thumb buttons. Pick a preset with `/torch preset tartarus` (Razer Tartarus + MMO mouse, the default), `keyboard`, `thumbmove` or `xaryu`. Keys bind to bar slots on any class.
- **Mage bars that fill themselves.** On a mage, every spell you know is placed: fixed homes for the fight keys, click bars for the rest, teleports, scrolls, potions, bandages and conjures kept current as you level. Other classes get the key layers and fill their own bars (`/torch map` shows the plan).
- **Spells follow your talent tree, keys never move.** Five or more points in a tree and the nuke, follow-up, panic, burst and off-school squares switch to that tree's spells. Respec, and your hands don't have to relearn anything.
- **Your race is read too.** Will of the Forsaken gets a stopcasting macro, Cannibalize gets a key (it restores mana in Forever), and the other races' actives are covered.
- **A thin strip with the four numbers you keep opening bags for.** Experience per hour and time left on the level, gold per hour, bag slots, worst durability. `/torch panel`. Rolling ten-minute window, and a hidden value shows a dash, never a fake zero.
- **Rested experience watched.** `/torch rested` says what the banked pool is worth and whether you logged out resting.
- **A coach that reads your hands.** Presses, clicks that should have been keys, fumbled neighbours, casts cut by moving — one to four lines after a fight. `/torch coach`.
- **Interrupt and curse calls.** Big centre text when your target casts (with your interrupt key), your own Polymorph countdown, and a decurse caller with a voice when curses land on the group. What Forever's API hides, the addon says it cannot see instead of guessing.
- **Undo.** `/torch undo` puts your bars and binds back exactly as they were before the addon touched them.

## Install

From [CurseForge](https://www.curseforge.com/wow/addons/torchbinds), or download the zip from the latest release and drop the `TorchBinds` folder into `_forever_/Interface/AddOns/`.

The Alt layer uses Action Bars 6 and 7: switch them on under Options → Action Bars to see those buttons (the keys work either way).

## For the rest of your guild

Per-class keyboard layouts, racial keys, downranking and consumable keys are written up on [the guild compendium](https://passthetorch.pages.dev/keybinds/overview/) — every class, not just the mage.

## License

MIT. See [LICENSE](LICENSE).
