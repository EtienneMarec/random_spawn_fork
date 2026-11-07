# Random Spawns (Fork)

A [Noita](https://noitagame.com/) mod that drops the player into a protective crate at a random location in the world at the start of each run, instead of the usual mountain entrance.

This is a fork of the *Random Spawns* mod (mod ID `evaisa.randomspawn`) and keeps its settings IDs.

## Features

- **Random starting location:** at the start of a new run, the mod picks a biome from its list, then a random 512×512 chunk inside that biome, then a random point inside that chunk.
- **Safe spawn check:** the mod waits for the chunk to load, then checks that the spawn point isn't inside solid terrain. Liquids and empty space are allowed. If the chunk doesn't load within 5 seconds, it tries another point. After 100 failed attempts it falls back to the center of a chunk in the chosen biome.
- **Gold biomes:** biomes whose name contains `gold` are almost entirely solid, so they skip the solid-terrain check.
- **Spawn crate:** a small pixel-scene crate (`crate.xml`) is placed around the player when they arrive.
- **Biome whitelist:** you can turn each biome on or off from the in-game mod settings.
- **No-repeat mode:** never start in the same biome twice in a row.
- **Sequential shuffle mode:** go through a shuffled list of the enabled biomes, one per run. The order is kept between runs and is reshuffled when the list runs out or when the enabled biomes change.
- **Attempt counter:** counts how many runs you've started with the mod.
- **Starting location on death:** when you die, the name of the biome you started in is shown on screen.

## Installation

1. Copy the mod folder into your Noita `mods` directory, for example:
   ```
   C:\Program Files (x86)\Steam\steamapps\common\Noita\mods\Fork
   ```
   The folder can have any name: the mod finds its own folder when it loads.
2. Start Noita, open **Mods**, and enable **Random Spawns**.
3. Start a new game.

## Settings

Open them from **Options → Mod Settings**.

| Setting | Description | Default |
| --- | --- | --- |
| No Repeat Spawns | Never spawn in the same biome twice in a row | Off |
| Sequential Shuffle Mode | Go through a shuffled biome list in order, one biome per run. Takes priority over No Repeat Spawns | Off |
| Attempt Count | Read-only counter, increased once per run | 0 |

### Biome whitelist

The **Biome Whitelist** section can only be edited **during a run** (not from the main menu). It lists every biome in the data file, sorted alphabetically:

- **[Enabled] / [Disabled]**: toggle a single biome.
- **[Enable All] / [Disable All]**: toggle every biome at once.
- **[Refresh Biomelist]**: reload the biome list from the data file.

Changes are saved to the `evaisa.randomspawn.whitelist` and `evaisa.randomspawn.blacklist` settings and apply to the next run. A biome that isn't in either list uses its default from the data file. If every biome is disabled, the mod shows a message and the player spawns normally.

The attempt count and other settings are stored in Noita's `save00/mod_config.xml`.

## Biome data

Spawn locations come from `biome_chunks.json`. It's a list of biomes, each with a name and the chunk coordinates it covers (one chunk = 512×512 pixels):

```json
[
  {
    "name": "lake-1",
    "actif": 1,
    "locations": [
      { "x-y": [ [-31, -14], [-30, -14] ] }
    ]
  }
]
```

- `name`: the biome name shown in the settings and on death.
- `actif` (optional): set it to `0` to disable the biome by default. Biomes without this field are enabled.
- `x-y`: a list of `[chunk_x, chunk_y]` pairs. World coordinates are `chunk * 512`.

The file is read by a small pattern-based parser (`parse_json.lua`), not a full JSON parser. Keep the same structure when you edit it, and put `actif` and the coordinates **after** the biome's `name`.

## Project structure

| File | Purpose |
| --- | --- |
| `mod.xml` | Mod metadata (name, description) |
| `compatibility.xml` | Noita build compatibility info |
| `init.lua` | Main logic: mod folder detection, biome selection, spawn search, teleport, crate placement, death message |
| `settings.lua` | Mod settings and the biome whitelist UI |
| `parse_json.lua` | Reads biome names, `actif` flags, and chunk coordinates from `biome_chunks.json` |
| `delay.lua` | Small frame-based scheduler (wait N frames or until a condition is true) |
| `crate.xml`, `crate*.png` | The spawn crate pixel scene (material, visual, and background layers) |
| `biome_chunks.json` | Biome → chunk data used for spawning |
| `biomes.json`, `biome_boundries_py.json`, `biome_blacklist.lua` | Other biome data files, not currently used by the scripts |

## Notes

- The spawn is seeded from the world seed, so the same seed gives the same starting location (unless No Repeat or Shuffle mode changes the pick).
- `crate.xml` lists its images as `mods/Fork/...`. If the folder has another name, `init.lua` rewrites those paths in memory when the mod loads.
