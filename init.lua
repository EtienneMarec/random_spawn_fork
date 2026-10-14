delay = dofile("mods/Fork/delay.lua")

local max_search_range = 512
local step_size = 16

function OnWorldPostUpdate()
    delay.update()
end

local get_content = ModTextFileGetContent

function OnPlayerSpawned( player_entity )
    
    if GameHasFlagRun("random_spawn_picked") then
        return
    end

    GameAddFlagRun("random_spawn_picked")

    -- Enregistrer le nombre d'essais dans les parametres "safe"
    -- Vous pourrez consulter ce nombre manuellement dans le fichier 'save00/mod_config.xml' de Noita
    local count = tonumber(ModSettingGetNextValue("evaisa.randomspawn.attempt_count")) or 0
    count = count + 1
    ModSettingSetNextValue("evaisa.randomspawn.attempt_count", count, false)

    local parse_json = dofile("mods/Fork/parse_json.lua")
    local parsed_biomes = parse_json.get_biomes()
    
    local a, b, c, d, e, f = GameGetDateAndTimeLocal()
    local time = a + b + c + d + e + f
	local seed = tonumber(MagicNumbersGetValue("WORLD_SEED") or 0)
    SetRandomSeed(seed + 324523, seed + 3285239)


	local function shuffle(tbl)
	  for i = #tbl, 2, -1 do
		local j = Random(1, i)
		tbl[i], tbl[j] = tbl[j], tbl[i]
	  end
	  return tbl
	end
	
	-- Removed shuffle(positions) as positions is no longer used

    local random_biome_list = {}
    local function GenerateRandomBiomeList()
		local whitelist = ModSettingGet("evaisa.randomspawn.whitelist") or ""

		local whitelist_biomes = {}
		if whitelist ~= "" then
			for biome in string.gmatch(whitelist, "[^,]+") do
				whitelist_biomes[biome] = true
			end
		end

        random_biome_list = {}
		local all_biomes = {}
        for i, v in ipairs(parsed_biomes) do
			table.insert(all_biomes, v.name)
            if (whitelist == "" and v.active ~= 0) or whitelist_biomes[v.name] then
				table.insert(random_biome_list, v)
            end
        end

		GlobalsSetValue("evaisa_randomspawn_biomelist", table.concat(all_biomes, ","))
    end

	local attempts = 20

    local function ChooseSpawn()

        GenerateRandomBiomeList()

		if #random_biome_list == 0 then
			print("Error: No valid biomes found!")
			return
		end
--???
		local no_repeat = ModSettingGet("evaisa.randomspawn.no_repeat_spawn")
		local shuffle_mode = ModSettingGet("evaisa.randomspawn.shuffle_mode")
		local last_biome = ModSettingGet("evaisa.randomspawn.last_biome") or ""
		
		local index = 1

		if shuffle_mode then
			local shuffled_list = GlobalsGetValue("evaisa_randomspawn_shuffled_list", "")
			local shuffle_index = tonumber(GlobalsGetValue("evaisa_randomspawn_shuffle_index", "0"))
			local saved_biomelist = GlobalsGetValue("evaisa_randomspawn_saved_biomelist", "")
			local current_biomelist = GlobalsGetValue("evaisa_randomspawn_biomelist", "")
			
			if shuffled_list == "" or shuffle_index >= #random_biome_list or saved_biomelist ~= current_biomelist then
				local shuffled_indices = {}
				for i = 1, #random_biome_list do
					table.insert(shuffled_indices, i)
				end
				shuffle(shuffled_indices)
				
				local shuffled_str = table.concat(shuffled_indices, ",")
				GlobalsSetValue("evaisa_randomspawn_shuffled_list", shuffled_str)
				GlobalsSetValue("evaisa_randomspawn_shuffle_index", "0")
				GlobalsSetValue("evaisa_randomspawn_saved_biomelist", current_biomelist)
				shuffle_index = 0
			end
			
			local indices = {}
			for idx_str in string.gmatch(GlobalsGetValue("evaisa_randomspawn_shuffled_list", ""), "[^,]+") do
				local idx = tonumber(idx_str)
				if idx then
					table.insert(indices, idx)
				end
			end
			
			if #indices > 0 then
				index = indices[shuffle_index + 1] or 1
				GlobalsSetValue("evaisa_randomspawn_shuffle_index", tostring(shuffle_index + 1))
			else
				index = 1
			end
		elseif no_repeat then
			local attempts = 0
			local max_attempts = 100
			
			repeat
				index = Random(1, #random_biome_list)
				attempts = attempts + 1
			until random_biome_list[index].name ~= last_biome or attempts >= max_attempts or #random_biome_list == 1
		else
        	index = Random(1, #random_biome_list)
		end

        local chosen_biome = random_biome_list[index]
		ModSettingSet("evaisa.randomspawn.last_biome", chosen_biome.name)

        local max_tries = 100
        local tries = 0
        local function TrySpawn()
            tries = tries + 1
            if tries > max_tries then
                -- Fallback to center of chosen chunk if we fail too many times
                local chunk = chosen_biome.chunks[Random(1, #chosen_biome.chunks)]
                local spawn_x = chunk.x * 512 + 256
                local spawn_y = chunk.y * 512 + 256
                EntityApplyTransform(player_entity, spawn_x, spawn_y)
                EntityLoad("mods/Fork/crate.xml", spawn_x, spawn_y)
                return
            end

            if not chosen_biome.chunks or #chosen_biome.chunks == 0 then
                print("Error: No chunks for biome " .. tostring(chosen_biome.name))
                return
            end

            local chunk = chosen_biome.chunks[Random(1, #chosen_biome.chunks)]
            local world_x = chunk.x * 512
            local world_y = chunk.y * 512

            local spawn_x = world_x + Random(0, 512)
            local spawn_y = world_y + Random(0, 512)

            -- Exception pour le biome gold (ou "or") : on spawn sans vérifier si c'est solide/liquide
            local biome_name_lower = string.lower(tostring(chosen_biome.name))
            if string.match(biome_name_lower, "gold") or string.match(biome_name_lower, "or") then
                GameSetCameraPos(spawn_x, spawn_y)
                EntityApplyTransform(player_entity, spawn_x, spawn_y)
                EntityLoad("mods/Fork/crate.xml", spawn_x, spawn_y)
                return
            end

            -- Move camera to force chunk loading
            GameSetCameraPos(spawn_x, spawn_y)

            -- Check if position is safe
            delay.new(function() 
                return DoesWorldExistAt(spawn_x - 5, spawn_y - 5, spawn_x + 5, spawn_y + 5)
            end, function() 
                -- RaytraceSurfaces renvoie true s'il touche un solide. 
                -- Cela permet de spawner dans les liquides (l'eau) ou le vide.
                local hit = RaytraceSurfaces(spawn_x, spawn_y, spawn_x, spawn_y)
                if hit then
                    -- Solide, on réessaie
                    delay.new(1, function()
                        TrySpawn()
                    end)
                else
                    EntityApplyTransform(player_entity, spawn_x, spawn_y)
                    EntityLoad("mods/Fork/crate.xml", spawn_x, spawn_y)
                end
            end)
        end

        TrySpawn()
    end

    ChooseSpawn()
end

function OnPlayerDied( player_entity )
    local biome_name = ModSettingGet("evaisa.randomspawn.last_biome") or "Inconnu"
    GamePrintImportant("Starting location", GameTextGetTranslatedOrNot(tostring(biome_name)))
end
