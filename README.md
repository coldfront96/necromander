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
scripts/autoload/
  ClassSystem.gd                 # resolves emergent class identity from a build
  GameState.gd                   # local session/character state
  NetworkManager.gd              # authoritative multiplayer lobby (ENet)
scenes/
  main_menu/                     # title screen
  character_creation/            # pick race + starting aspect, deepen/mix loop
  lobby/                         # host/join party, synced roster
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
  both clients load the shared **Dungeon Room** and can move around with the
  on-screen stick (or arrow keys) while the server keeps everyone in sync.

## Status

v0 baseline — see the roadmap in [DESIGN.md](DESIGN.md#6-roadmap).
The next milestone (v0.1) is a dedicated level-up screen with the live
"deepen vs mix" class preview already prototyped in character creation.
