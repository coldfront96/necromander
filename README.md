# Necromander

A mobile-first, multiplayer RPG dungeon crawler with a deep character builder
where **no single build dominates**. Pick Melee, Ranged, or Arcane to start —
then every level-up is a fork: deepen your class or **mix in another power
source** to unlock emergent hybrids. Arcane + Divine → **Necromancer**.
Melee + Arcane → **War Mage**. Add a third source later and entirely new powers
open up. The combination space is near-unlimited.

> Read **[DESIGN.md](DESIGN.md)** for the full vision and design pillars.

## Tech

- **Engine:** Godot 4.3 (mobile renderer, portrait).
- **Multiplayer:** server-authoritative, player-hosted lobbies over ENet.
- **Class system:** fully data-driven via [`data/combinations.json`](data/combinations.json) —
  adding a class or power source is a data change, not code.

## Project layout

```
data/combinations.json          # the class/aspect registry (data-driven)
scripts/model/CharacterBuild.gd  # a character's aspect investments
scripts/dungeon/
  DungeonGenerator.gd            # seed-driven procedural layouts (v0.5)
scripts/autoload/
  ClassSystem.gd                 # resolves emergent class identity from a build
  GameState.gd                   # local session/character state
  NetworkManager.gd              # authoritative multiplayer lobby (ENet)
scenes/
  main_menu/                     # title screen
  character_creation/            # pick race + starting aspect, deepen/mix loop
  lobby/                         # host/join party, synced roster
  game/                          # the shared, server-authoritative dungeon run
```

## Run it

1. Install [Godot 4.3+](https://godotengine.org/download).
2. Open this folder as a project (`Import` → select `project.godot`).
3. Press **Play** (F5).

### Try multiplayer locally

- Enable Godot's *Debug → Run Multiple Instances* (set 2 instances).
- In window A: create a character → **Host** a lobby.
- In window B: create a character → **Join** `127.0.0.1`.
- Watch the roster sync. Then in the host window press **Start Run (host)** —
  the host rolls a seed and every peer generates the **same procedural dungeon**
  (rooms + corridors on a room-graph; only the seed crosses the wire). Move with
  the on-screen stick (or arrow keys); walls are real, the camera follows you,
  and the **minimap** (top-right) shows the layout and the exit room.
- Tap an ability on the **hotbar** (built from your loadout) to fight the
  **husks** — the server resolves damage/healing, applies your identity
  affinity bonus, and broadcasts HP to everyone. Husks chase and hit back, and
  they get **meaner the deeper the room** — healing matters; downed players
  respawn back at the entrance.
- Husks **drop loot** (rarity-colored diamonds) that rolls **higher item levels
  in deeper rooms** — walk over a drop to pick it up. Open **Inventory** from
  the main menu to equip gear; its stats scale your damage/healing/HP
  server-side. Your character (build, gear, gold, XP) **saves automatically** —
  use **Continue** on the title screen next launch.
- Kills also grant **party-shared XP** (deeper rooms pay more). When your bank
  covers the next level, a **▲ LEVEL UP!** button lights up — tap it to face
  the signature fork *mid-run*: **deepen** an Aspect or **mix** in a new one,
  with a live preview of the class you'd become. The dungeon doesn't pause, so
  choose fast. Your new abilities and HP apply immediately.
- Clear the deepest room (a **boss** guards it) to open the **exit portal** —
  step in and the whole party extracts back to the lobby with a bonus reward,
  ready to roll the next dungeon.

## Status

v0.6 — XP and the in-run "deepen vs mix" level-up fork are live; see the
roadmap in [DESIGN.md](DESIGN.md#6-roadmap). Next up (v0.7): a town/hub scene
and shop (gold, Respec Tokens) — the first full pass of the target game loop.
