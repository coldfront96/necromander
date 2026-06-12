# Necromander — Game Design Document

> A living document. This is the source of truth for the vision. Expect it to
> evolve every session. Nothing here is sacred except the **Pillars**.

---

## 1. Vision (one paragraph)

Necromander is a mobile-first, multiplayer RPG dungeon crawler with a deep
character builder where **no single build is "the" build**. You start by
picking a Race and one of three foundational combat identities — **Melee,
Ranged, or Arcane** — and from there every level-up is a fork in the road.
Stay your course to deepen a class, or **mix in another power source** to
unlock hybrid classes that didn't exist a moment ago. Mix Arcane + Divine and
you become a **Necromancer**. Mix Melee + Arcane and you're a **War Mage**.
Add a third source later and entirely new powers open up — weaker at first,
but the combinatorial space is near-unlimited. The goal: every road you take
could lead to a very powerful character, and no two players have to walk the
same one.

## 2. Design Pillars (the things we will not compromise)

1. **No "goated" build.** We actively resist the Diablo 3 trap where one
   set/build dominates. Balance philosophy: breadth of *viable* options over a
   single optimal peak. Every combination should have a fantasy and a niche.
2. **The road matters.** Progression is a series of meaningful, branching
   choices. Mixing classes is the core expressive mechanic, not an afterthought.
3. **Combinations are emergent, not hand-placed.** The system is data-driven so
   that "any number of combinations" is real. Adding a new power source or
   hybrid is a data change, not an engine rewrite.
4. **Multiplayer-native.** Built on an authoritative-server model from day one,
   not bolted on later.
5. **Mobile-first.** Touch-first UI, short session loops, performance budget for
   phones.

## 3. The Character System

### 3.1 Power Sources (a.k.a. "Aspects")

The atomic units of identity. The baseline ships with four:

| Aspect  | Fantasy                         | Starting? |
|---------|---------------------------------|-----------|
| MELEE   | Martial might, blades & blood   | Yes       |
| RANGED  | Precision, bows & traps         | Yes       |
| ARCANE  | Raw manipulated magic           | Yes       |
| DIVINE  | Faith, holy & unholy power      | Unlocked  |

Aspects are deliberately extensible — PRIMAL, SHADOW, TECH, etc. can be added
later purely as data.

### 3.2 Character Build

A character is **not** a fixed class. A build is the running record of how many
levels you've invested into each Aspect:

```
build.aspect_levels = { MELEE: 3, ARCANE: 2 }   # a level-5 Spellblade
```

At each level-up the player either:
- **Deepen** — add a level to an Aspect they already have, or
- **Mix** — invest the level into a *new* Aspect.

### 3.3 Emergent Class Identity

Your **class title and ability trees are derived** from the *set* of Aspects
present in your build, resolved against a data-driven combination registry
(`data/combinations.json`).

- **1 Aspect → Base Class**
  - MELEE → Warrior · RANGED → Hunter · ARCANE → Mage · DIVINE → Cleric
- **2 Aspects → Hybrid Class**
  - MELEE+ARCANE → War Mage · MELEE+DIVINE → Paladin
  - RANGED+ARCANE → Arcane Archer · RANGED+DIVINE → Inquisitor
  - **ARCANE+DIVINE → Necromancer** · MELEE+RANGED → Skirmisher
- **3 Aspects → Apex Hybrid** (new powers, start weaker, scale far)
  - MELEE+ARCANE+DIVINE → Death Knight
  - MELEE+RANGED+ARCANE → Spellslinger
  - MELEE+RANGED+DIVINE → Templar
  - RANGED+ARCANE+DIVINE → Plaguebringer
- **4 Aspects → Ascendant** (the omniclass; jack-of-all, master-of-flux)

### 3.4 The "weaker initially, unlimited ceiling" rule

When adding a new Aspect unlocks a higher-order hybrid, that hybrid's ability
tree **begins at Tier 1** regardless of your character level. This is the
intentional cost of flexibility — you trade immediate raw power for a wider
toolkit and a higher long-term ceiling. Deepening a single Aspect climbs its
tree faster; spreading wide unlocks more trees but each climbs slower.

**Tier of a hybrid tree** = the *minimum* investment among its required
Aspects. (A Necromancer with ARCANE 5 / DIVINE 1 is a Tier-1 Necromancer who
also has a deep Mage tree to fall back on.) This single rule is what makes
"any road could lead to a powerful character" mathematically true while keeping
balance tractable.

## 4. Multiplayer Model

- **Authoritative server.** The server owns the canonical game state (positions,
  HP, loot rolls, combat resolution). Clients send intents; the server validates
  and broadcasts results. This prevents the trivial cheating that plagues
  client-authoritative ARPGs.
- **Transport.** Godot high-level multiplayer (`MultiplayerAPI`) over
  `ENetMultiplayerPeer` for the baseline. Swappable for WebSocket/WebRTC later
  for web/mobile NAT traversal.
- **Topology for v0.** Player-hosted lobbies (one peer is host+server) so we can
  iterate without standing up dedicated infrastructure. The code is structured
  so the "server" can later become a headless dedicated build with no gameplay
  rewrite.
- **Co-op first.** 2–4 player party dungeon runs are the target social loop.

See `scripts/autoload/NetworkManager.gd`.

## 5. Game Loop (target)

1. **Town / Hub** — manage character, party up, pick a dungeon.
2. **Dungeon Run** — procedurally assembled rooms, combat, loot.
3. **Level-up choice** — deepen or mix (the signature moment).
4. **Extract / Return** — bank loot & XP, repeat.

## 6. Roadmap

- **v0 (this baseline):** project scaffold, class-mixing engine + tests-by-play,
  character creation screen, host/join lobby over ENet. ✅
- **v0.1:** Confirm level-up "deepen vs mix" UI with live class-title preview.
- **v0.2:** Networked shared dungeon room with synced player avatars.
- **v0.3:** Combat prototype (one ability per base class), server-authoritative.
- **v0.4:** Loot + persistence (local save, then server-side).
- **v0.5:** Procedural dungeon generation.

## 7. Open Questions (to revisit)

- Do mixed Aspects *replace* base abilities or *coexist* as separate hotbars?
  (Leaning coexist — strengthens the "toolkit breadth" pillar.)
- Respec policy — permanent choices (roguelike weight) vs. flexible loadouts?
- Is there a level cap, or infinite scaling with prestige?
- PvP at all, or strictly co-op PvE?

---

*Repo name "necromander" is a nod to the Arcane+Divine archetype that crystalized
this whole idea.*
