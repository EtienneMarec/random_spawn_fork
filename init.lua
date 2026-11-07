-- Settings keys keep the original mod's prefix so existing settings are preserved.
local SETTING = "evaisa.randomspawn."

local DATA_FILE = "biome_chunks.json"
local START_BIOME_KEY = "evaisa_randomspawn_start_biome"

local CHUNK_SIZE = 512
local MAX_SPAWN_TRIES = 100
local WORLD_LOAD_TIMEOUT = 300 -- frames to wait for a chunk to stream in before trying another point

-- Find this mod's folder, so the mod works whatever its folder is named.
local function is_this_mod(path)
    return ModDoesFileExist(path .. DATA_FILE)
        and ModDoesFileExist(path .. "parse_json.lua")
        and ModDoesFileExist(path .. "crate.xml")
end

local function find_mod_path()
    for _, id in ipairs(ModGetActiveModIDs() or {}) do
        local path = "mods/" .. id .. "/"
        if is_this_mod(path) then
            return path
        end
    end
    return "mods/Fork/"
end

local MOD_PATH = find_mod_path()
local CRATE_FILE = MOD_PATH .. "crate.xml"

-- Remember the path so settings.lua can find the mod files too.
ModSettingSet(SETTING .. "mod_path", MOD_PATH)

-- crate.xml references its images as "mods/Fork/..."; point them at the real folder.
if MOD_PATH ~= "mods/Fork/" then
    local crate = ModTextFileGetContent(CRATE_FILE)
    if crate then
        local replacement = MOD_PATH:gsub("%%", "%%%%")
        ModTextFileSetContent(CRATE_FILE, (crate:gsub("mods/Fork/", replacement)))
    end
end

local delay = dofile(MOD_PATH .. "delay.lua")
local parse_json = dofile(MOD_PATH .. "parse_json.lua")

function OnWorldPostUpdate()
    delay.update()
end

local function split(str)
    local items = {}
    for item in string.gmatch(tostring(str or ""), "[^,]+") do
        table.insert(items, item)
    end
    return items
end

local function to_set(list)
    local set = {}
    for _, item in ipairs(list) do
        set[item] = true
    end
    return set
end

local function shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = Random(1, i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

-- A biome is enabled if the player enabled it, or if it isn't disabled
-- (by the player or by "actif": 0 in the data file). Biomes without chunks are skipped.
local function get_enabled_biomes(all_biomes)
    local whitelist = to_set(split(ModSettingGet(SETTING .. "whitelist")))
    local blacklist = to_set(split(ModSettingGet(SETTING .. "blacklist")))

    local enabled = {}
    for _, biome in ipairs(all_biomes) do
        local on
        if blacklist[biome.name] then
            on = false
        elseif whitelist[biome.name] then
            on = true
        else
            on = biome.active ~= 0
        end

        if on and #biome.chunks > 0 then
            table.insert(enabled, biome)
        end
    end
    return enabled
end

-- Go through a shuffled list of the enabled biomes, one per run.
-- The order is stored in mod settings so it carries over between runs.
local function pick_shuffled(biomes, last_biome)
    local by_name = {}
    local names = {}
    for _, biome in ipairs(biomes) do
        by_name[biome.name] = biome
        table.insert(names, biome.name)
    end
    table.sort(names)
    local signature = table.concat(names, ",")

    local order = split(ModSettingGet(SETTING .. "shuffle_order"))
    local index = tonumber(ModSettingGet(SETTING .. "shuffle_index")) or 0

    if ModSettingGet(SETTING .. "shuffle_signature") ~= signature or index >= #order then
        order = shuffle(names)
        -- Don't start a new cycle with the biome the last run used.
        if #order > 1 and order[1] == last_biome then
            order[1], order[2] = order[2], order[1]
        end
        index = 0
        ModSettingSet(SETTING .. "shuffle_order", table.concat(order, ","))
        ModSettingSet(SETTING .. "shuffle_signature", signature)
    end

    ModSettingSet(SETTING .. "shuffle_index", index + 1)
    return by_name[order[index + 1]] or biomes[Random(1, #biomes)]
end

local function pick_biome(biomes)
    local last_biome = ModSettingGet(SETTING .. "last_biome") or ""

    if ModSettingGet(SETTING .. "shuffle_mode") then
        return pick_shuffled(biomes, last_biome)
    end

    local candidates = biomes
    if ModSettingGet(SETTING .. "no_repeat_spawn") and #biomes > 1 then
        candidates = {}
        for _, biome in ipairs(biomes) do
            if biome.name ~= last_biome then
                table.insert(candidates, biome)
            end
        end
        if #candidates == 0 then
            candidates = biomes
        end
    end

    return candidates[Random(1, #candidates)]
end

local function place_player(player_entity, x, y)
    EntityApplyTransform(player_entity, x, y)
    EntityLoad(CRATE_FILE, x, y)
end

local function try_spawn(player_entity, biome, tries)
    tries = tries + 1
    local chunk = biome.chunks[Random(1, #biome.chunks)]

    if tries > MAX_SPAWN_TRIES then
        -- Too many failed attempts: use the center of a chunk without checking.
        place_player(player_entity, chunk.x * CHUNK_SIZE + CHUNK_SIZE / 2, chunk.y * CHUNK_SIZE + CHUNK_SIZE / 2)
        return
    end

    local x = chunk.x * CHUNK_SIZE + Random(0, CHUNK_SIZE - 1)
    local y = chunk.y * CHUNK_SIZE + Random(0, CHUNK_SIZE - 1)

    -- Move the camera there to force the chunk to load.
    GameSetCameraPos(x, y)

    -- Gold biomes are almost entirely solid, so the free-space check would always fail.
    if biome.skip_ground_check then
        place_player(player_entity, x, y)
        return
    end

    local waited = 0
    delay.new(function()
        waited = waited + 1
        return waited > WORLD_LOAD_TIMEOUT or DoesWorldExistAt(x - 5, y - 5, x + 5, y + 5)
    end, function()
        -- RaytraceSurfaces hits only solids, so liquids and empty space are valid spawn points.
        if waited <= WORLD_LOAD_TIMEOUT and not RaytraceSurfaces(x, y, x, y) then
            place_player(player_entity, x, y)
        else
            delay.new(1, function()
                try_spawn(player_entity, biome, tries)
            end)
        end
    end)
end

function OnPlayerSpawned(player_entity)
    if GameHasFlagRun("random_spawn_picked") then
        return
    end
    GameAddFlagRun("random_spawn_picked")

    -- Count runs. The value is visible in the mod settings and in save00/mod_config.xml.
    local count = tonumber(ModSettingGetNextValue(SETTING .. "attempt_count")) or 0
    ModSettingSetNextValue(SETTING .. "attempt_count", count + 1, false)

    local seed = tonumber(MagicNumbersGetValue("WORLD_SEED")) or 0
    SetRandomSeed(seed + 324523, seed + 3285239)

    local biomes = get_enabled_biomes(parse_json.get_biomes(MOD_PATH .. DATA_FILE))
    if #biomes == 0 then
        print("Random Spawns: no enabled biome with spawn data, using the normal spawn.")
        GamePrint("Random Spawns: no biome is enabled, using the normal spawn.")
        return
    end

    local biome = pick_biome(biomes)
    biome.skip_ground_check = string.find(string.lower(biome.name), "gold", 1, true) ~= nil

    ModSettingSet(SETTING .. "last_biome", biome.name)
    GlobalsSetValue(START_BIOME_KEY, biome.name)

    try_spawn(player_entity, biome, 0)
end

function OnPlayerDied(player_entity)
    local biome_name = GlobalsGetValue(START_BIOME_KEY, "")
    if biome_name ~= "" then
        GamePrintImportant("Starting location", GameTextGetTranslatedOrNot(biome_name))
    end
end
