dofile("data/scripts/lib/mod_settings.lua") 

local mod_id = "evaisa.randomspawn" -- This should match the name of your mod's folder.
mod_settings_version = 1 -- This is a magic global that can be used to migrate settings to new mod versions. call mod_settings_get_version() before mod_settings_update() to get the old value. 
mod_settings = 
{
	{
		category_id = "default_settings",
		ui_name = "",
		ui_description = "",
		settings = {
			{
				id = "no_repeat_spawn",
				ui_name = "No Repeat Spawns",
				ui_description = "Never spawn in the same biome twice in a row",
				value_default = false,
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "shuffle_mode",
				ui_name = "Sequential Shuffle Mode",
				ui_description = "Shuffle biomes and go through them in order, regenerating when the list runs out or biomes change",
				value_default = false,
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "attempt_count",
				ui_name = "Attempt Count",
				ui_description = "Count of attempts.",
				value_default = 0,
				scope = MOD_SETTING_SCOPE_RUNTIME,
				ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
					local value = ModSettingGetNextValue(mod_setting_get_id(mod_id, setting))
					if type(value) ~= "number" then value = setting.value_default or 0 end
					GuiText(gui, 0, 0, setting.ui_name .. " : " .. tostring(value))
				end
			},
		},
	},
}

function ModSettingsUpdate( init_scope )
	local old_version = mod_settings_get_version( mod_id ) 
	mod_settings_update( mod_id, mod_settings, init_scope )
end

function ModSettingsGuiCount()
	return 1
end


active_biomes = active_biomes or {}
active_biomes_list = active_biomes_list or nil
inactive_biome_list = inactive_biome_list or nil

function ModSettingsGui( gui, in_main_menu )
	mod_settings_gui( mod_id, mod_settings, gui, in_main_menu )

	local list_changed = false

	local function set_enabled( id, enabled )
		if(enabled)then
			active_biomes_list[id] = true
			inactive_biome_list[id] = false
		else
			active_biomes_list[id] = false
			inactive_biome_list[id] = true
		end
		list_changed = true
	end
        
	screen_width, screen_height = GuiGetScreenDimensions(gui)

	local id = 2352352
	local function new_id() id = id + 1; return id end

	GuiOptionsAdd( gui, GUI_OPTION.NoPositionTween )

	GuiColorSetForNextWidget( gui, 0.8, 0.8, 0.8, 1 )

	GuiText( gui, -2, 8, "----- Biome Whitelist -----" )

	if(not in_main_menu)then

		-- if active_biomes_list is nil, try to load it from "evaisa.randomspawn.whitelist", otherwise, set to {}
		if(active_biomes_list == nil)then
			local whitelist = ModSettingGet("evaisa.randomspawn.whitelist") or ""
			local blacklist = ModSettingGet("evaisa.randomspawn.blacklist") or ""
			active_biomes_list = {}
			inactive_biome_list = {}
			for biome in string.gmatch(whitelist, "[^,]+") do
				active_biomes_list[biome] = true
			end
			for biome in string.gmatch(blacklist, "[^,]+") do
				inactive_biome_list[biome] = true
			end
		end
		
		local function refresh()
			active_biomes = {}
            local parse_json = dofile("mods/Fork/parse_json.lua")
            local parsed_biomes = parse_json.get_biomes()
            
            local active_states = {}
            for _, b in ipairs(parsed_biomes) do
                table.insert(active_biomes, b.name)
                active_states[b.name] = (b.active ~= 0)
            end

			-- sort by alphabetical
			table.sort(active_biomes, function(a, b) return a < b end)

			-- add any biomes missing from the active_biomes_list to it as enabled/disabled according to json
			for k, v in ipairs(active_biomes)do
				if(active_biomes_list[v] == nil and inactive_biome_list[v] == nil)then
					set_enabled(v, active_states[v] == true)
				end
			end
		end

    	if(GuiButton( gui, new_id(), 0, 0, "[Refresh Biomelist]" ))then
			refresh()
		end

		if(#active_biomes == 0)then
			refresh()
		end



        GuiText( gui, 0, 0, " " )

        GuiLayoutBeginHorizontal( gui, 0, 0, false, 15, 10 )
        if GuiButton( gui, new_id(), 0, 0, "[Enable All]" )then
            for k, v in ipairs(active_biomes)do
				set_enabled(v, true)
            end
        end
        if GuiButton( gui, new_id(), 0, 0, "[Disable All]" )then
            for k, v in ipairs(active_biomes)do
				set_enabled(v, false)
            end
        end
        GuiLayoutEnd(gui)

        


        for k, v in ipairs(active_biomes)do
            
            GuiLayoutBeginHorizontal( gui, 0, 0, false, 2, 2 )

            local disabled = inactive_biome_list[v]

            if(disabled)then
                GuiColorSetForNextWidget( gui, 0.8, 0.5, 0.5, 1 )
            else
                GuiColorSetForNextWidget( gui, 0.5, 0.8, 0.5, 1 )
            end

            GuiText( gui, 0, 0, v )

            if GuiButton( gui, new_id(), 0, 0, (disabled and "[Disabled]" or "[Enabled]")) then
                if(disabled)then
					set_enabled(v, true)
				else
					set_enabled(v, false)
				end
            end
            
            GuiLayoutEnd(gui)
            
        end

	else
		GuiText( gui, 0, 0, "Enter new game to edit whitelist." )
    end

	-- if changes were made, save them to "evaisa.randomspawn.whitelist" using ModSettingSet()
	if(list_changed)then
		local whitelist = ""
		local blacklist = ""
		for k, v in pairs(active_biomes_list)do
			if(v)then
				whitelist = whitelist .. k .. ","
			end
		end
		for k, v in pairs(inactive_biome_list)do
			if(v)then
				blacklist = blacklist .. k .. ","
			end
		end

		if(whitelist ~= "")then
			whitelist = string.sub(whitelist, 1, -2)
		end
		if(blacklist ~= "")then
			blacklist = string.sub(blacklist, 1, -2)
		end

		ModSettingSet("evaisa.randomspawn.whitelist", whitelist)
		ModSettingSet("evaisa.randomspawn.blacklist", blacklist)
	end


end

