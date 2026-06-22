# Zombas — Trap Structures
**Project Zomboid | Build 42**

Adds three craftable primitive trap structures to the game. Traps can damage or immobilize zombies, injure careless survivors, and even destroy vehicle tires.

---

## Features

### 1. Stake Pit Trap
A shallow pit filled with sharpened wooden stakes.

- Dig with a **shovel** (right-click ground → *Dig Stake Pit*)
- Add up to **4 Wooden Stakes** one at a time
- Optionally **conceal with Hay** — the ground will look like a normal hay pile
- Damages **zombies**, **players**, and **vehicles** (tire damage; critical hit = blowout)
- Each stake has a **15% chance to break** on every trigger
- Zombies can be **immobilized** on trigger

### 2. Pit Trap (Hole)
A deep pit that entities fall into and cannot escape without aid.

- Dig with a **shovel** — requires **Strength ≥ 4** (right-click ground → *Dig Pit Trap*)
- Can only be dug on **dirt, grass, sand, or gravel** surfaces
- If no structure exists below, a **dirt chamber** is automatically generated at the level beneath
- Entities that walk over the hole **fall in** and are trapped
- Uses the **native PZ fall damage** system on impact
- Configurable **maximum zombie capacity** (default: 6; 0 = unlimited). Once full, additional zombies pass over normally

### 3. Stake Fence
A low barrier of five sharpened stakes driven into the ground.

- Place with **5 Wooden Stakes** on valid ground (right-click → *Place Stake Fence* → choose **North** or **West** face)
- Can only be placed on **dirt, grass, sand, or gravel** surfaces
- Deals damage when a zombie or player **crosses** the fence face
- Each stake has a **15% chance to break** on trigger; fence disappears when all stakes are gone
- Does **not** block pathfinding — entities walk into it and take damage

---

## Crafting

### Wooden Stake
| Ingredient | Tool (kept) | Result |
|---|---|---|
| Tree Branch | Flint Knife / Stone Knife / Chipped Knife | Wooden Stake |

Category: **Survival** — Time: 150 ticks

---

## Mod Options

All values are configurable in the **Mod Options** menu. In multiplayer, the **server host's settings** apply to all players.

### Feature Toggles
| Option | Default | Description |
|---|---|---|
| Enable Stake Pit Trap | `true` | Enable/disable stake pit entirely |
| Enable Hole Trap | `true` | Enable/disable deep pit trap |
| Enable Stake Fence | `true` | Enable/disable stake fence |

### Stake Pit
| Option | Default | Range | Description |
|---|---|---|---|
| Min Damage | `3` | 1–100 | Minimum damage per trigger |
| Max Damage | `10` | 1–200 | Maximum damage per trigger |
| Crit Chance (%) | `12` | 0–100 | Chance of a critical hit (×2.5 damage) |
| Stake Break Chance (%) | `15` | 0–100 | Chance each stake breaks on trigger |

### Vehicle Damage (Stake Pit)
| Option | Default | Range | Description |
|---|---|---|---|
| Min Tire Damage | `10` | 1–100 | Minimum tire condition loss |
| Max Tire Damage | `30` | 1–100 | Maximum tire condition loss |
| Blowout Chance (%) | `15` | 0–100 | Chance of critical hit (tire condition → 0) |

### Hole Trap
| Option | Default | Range | Description |
|---|---|---|---|
| Max Zombies in Hole | `6` | 0–100 | Max zombies trapped at once; 0 = unlimited |

### Stake Fence
| Option | Default | Range | Description |
|---|---|---|---|
| Min Damage | `2` | 1–100 | Minimum damage on crossing |
| Max Damage | `8` | 1–200 | Maximum damage on crossing |
| Crit Chance (%) | `10` | 0–100 | Chance of a critical hit |

---

## Compatibility

- **Single-player:** fully supported
- **Multiplayer:** fully supported — server is authoritative for all damage values and trap state
- **Build:** Project Zomboid **Build 42** only

---

## File Structure

```
Zombas/
├── mod.info
└── media/
    ├── scripts/
    │   ├── items/ZombasItems.txt        — WoodenStake item definition
    │   └── recipes/ZombasRecipes.txt    — Carve Wooden Stake recipe
    ├── textures/tiles/                  — Sprite PNGs (placeholder art)
    └── lua/
        ├── shared/
        │   ├── ZombasShared.lua         — Config, constants, shared utilities
        │   └── Translate/EN/Zombas_EN.txt
        ├── client/
        │   ├── ZombasModOptions.lua     — Mod options registration & sync
        │   ├── ZombasContextMenu.lua    — Right-click menu for all traps
        │   └── ZombasTimedActions.lua   — Timed actions (dig, place, disarm)
        └── server/
            └── ZombasTrapServer.lua     — Trap logic, damage, chamber generation
```

---

## Known Limitations / TODO

- Sprites are placeholder pixel art — final art to be added
- `Zombas_Hole_0` sprite name needs a matching **tile definition file** for PZ's tile system
- Hole trap Z-level numbers should be verified in-engine (outdoor terrain assumed at `z=1` in B42)
- ModOptions API call (`ModOptions:getInstance`) requires verification against the final B42 PZAPI

---

## License

This mod is released for personal and community use. Attribution appreciated.
