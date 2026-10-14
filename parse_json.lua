local parse_json = {}

function parse_json.get_biomes()
    local content = ModTextFileGetContent("mods/Fork/test.json")
    local biomes = {}
    if not content then return biomes end
    
    local names = {}
    for name_pos, name in string.gmatch(content, '()"name"%s*:%s*"([^"]+)"') do
        table.insert(names, {pos = name_pos, name = name})
    end
    
    for i, n in ipairs(names) do
        local start_pos = n.pos
        local end_pos = (i < #names) and names[i+1].pos or #content
        
        local block = string.sub(content, start_pos, end_pos)
        
        local active = 1
        local active_match = string.match(block, '"actif"%s*:%s*(%d+)')
        if active_match then active = tonumber(active_match) end
        
        local chunks = {}
        for x, y in string.gmatch(block, "%[%s*(%-?%d+)%s*,%s*(%-?%d+)%s*%]") do
            table.insert(chunks, {x = tonumber(x), y = tonumber(y)})
        end
        
        table.insert(biomes, {name = n.name, chunks = chunks, active = active})
    end
    
    return biomes
end

return parse_json
