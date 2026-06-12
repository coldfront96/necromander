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

### 3.5 Ability Loadouts (active slots)

Investing in an Aspect *unlocks* abilities into your **known pool** — it does
not auto-equip them. The hotbar is a **limited set of active slots**, and the
player chooses which known abilities to slot. This is the resolution to "do
mixed Aspects replace or coexist?": **both — the player decides per build.**

- All abilities from every Aspect tree you've invested in are *available*.
- Only the ones you slot are *active* on your hotbar.
- A mixed character can therefore **replace** their base hotbar entirely with
  hybrid abilities, or keep a foundation of base-class staples and slot a few
  hybrid tools — it's a loadout choice, not a forced swap.

Loadout slots are a progression reward (see 3.7) — early characters have few
slots and must commit; later characters wield broader kits. This is also the
main PvP-balance lever: a capped slot count means breadth still has an
opportunity cost even at max level.

### 3.6 Respec

Builds are meaningful and semi-permanent — you can't freely reshuffle every
fight. Respeccing requires a **Respec Token**, obtained either:

- **Purchased with gold** in the in-game shop (the standard, grind-friendly
  path), or
- **Bought in a real-money pack** (convenience monetization).

Slotting/unslotting *active abilities* from your known pool is **free and
unlimited** (that's the loadout in 3.5). A Respec Token is only needed to
**re-allocate Aspect investment levels** — i.e. to change the underlying build,
not the active kit. This keeps tactical flexibility free while making
identity-level changes a deliberate, valued action.

### 3.7 Soft Cap & Ascension (no hard level cap)

There is **no hard level cap.** Instead we use a **soft cap via diminishing
returns** — inspired by idle/looter progression (e.g. LootFiend) — so the player
can level forever, but raw level power flattens and other systems take over.

- **Diminishing level power.** A level's contribution to raw stats follows an
  asymptotic curve (`level_power()` in `CharacterBuild`): big gains early,
  flattening toward a ceiling (`LEVEL_POWER_MAX`). Levels matter *a lot* at first
  and quickly get **outshined by other power axes** — gear, build synergy, set
  bonuses, Ascension. By the **soft cap (~level 100)** the curve is ~95% spent.
  - *Why this is PvP-safe:* no amount of grinding pushes the level term past the
    ceiling, so a level-500 and a level-150 are close in raw power. Fights are
    decided by build, gear, and skill — not playtime.
  - *Honest caveat:* "outshined by other systems" only bites once those systems
    exist (gear, sets, crafting). Until then, level is still the main axis — the
    curve is correct now, the payoff grows as we add the lateral systems.
- **Ascension (infinite, horizontal only).** Continued leveling/Ascension grants
  **no raw stat power** — only horizontal rewards: additional loadout slots
  (capped, for PvP sanity), cosmetics/prestige, account-wide unlocks, crafting
  materials, alternate ability visuals. This is the paragon-style "forever ding"
  without the paragon power-creep problem.

> The curve constants (`LEVEL_POWER_MAX`, `LEVEL_POWER_FALLOFF`, `LEVEL_SOFT_CAP`)
> are all tunable. The firm commitment: **vertical power asymptotes; breadth and
> vanity are infinite.** Level is a fast on-ramp, not the endgame engine.

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
- **Co-op AND PvP.** Two social loops, both first-class:
  - **Co-op** — 2–4 player party dungeon runs (the primary, build-expressive loop).
  - **PvP** — competitive arenas where the level-60 power cap (3.7) and the
    capped active-slot count (3.5) keep matches about build + skill, not grind.
    The same server-authoritative model that prevents PvE cheating is what makes
    fair PvP possible at all.

See `scripts/autoload/NetworkManager.gd`.

## 5. Game Loop (target)

1. **Town / Hub** — manage character, party up, pick a dungeon.
2. **Dungeon Run** — procedurally assembled rooms, combat, loot.
3. **Level-up choice** — deepen or mix (the signature moment).
4. **Extract / Return** — bank loot & XP, repeat.

## 6. Roadmap

- **v0 (this baseline):** project scaffold, class-mixing engine + tests-by-play,
  character creation screen, host/join lobby over ENet. ✅
- **v0.1:** Live "deepen vs mix" class preview + derived loadout system
  (known-pool from build, limited active slots) + soft-cap diminishing-power
  model (no hard cap). ✅
- **v0.2:** Networked shared dungeon room with synced player avatars.
- **v0.3:** Combat prototype (one ability per base class), server-authoritative.
- **v0.4:** Loot + persistence (local save, then server-side).
- **v0.5:** Procedural dungeon generation.

## 7. Resolved Decisions

- **Mixed Aspects: replace or coexist?** → *Player's choice via loadouts* (3.5).
  Known pool is unlimited; active hotbar slots are limited and freely re-slotted.
- **Respec policy?** → *Semi-permanent* (3.6). Re-allocating Aspect levels needs
  a Respec Token (gold in shop, or real-money pack). Swapping active abilities is
  free.
- **Level cap?** → *No hard cap. Soft cap via diminishing level-power (~Lv 100);
  raw power asymptotes while gear/synergy/Ascension take over* (3.7).
- **Mixing: automatic or opt-in?** → *Automatic.* The hybrid identity emerges
  the moment you hold the required Aspects — no extra confirmation step (3.3).
- **PvP?** → *Yes — both co-op and PvP* (section 4).

## 8. Still Open (to revisit)

- Exact number of base active-slot count and the per-Ascension slot drip.
- PvP format(s): arena/duels, ranked seasons, objective modes?
- Real-money monetization scope beyond Respec Tokens (cosmetics only? battle pass?).
- Death/penalty model in dungeons (roguelike extraction risk vs. forgiving).
- Season/reset cadence for Ascension horizontal rewards.

---

*Repo name "necromander" is a nod to the Arcane+Divine archetype that crystalized
this whole idea.*
