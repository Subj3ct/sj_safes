local placedSafes = {}
local playerSafeCounts = {}
local RESOURCE_NAME = GetCurrentResourceName()
local SAFES_FILE = GetResourcePath(RESOURCE_NAME) .. '/sj_safes_data.json'

-- JSON persistence functions
local function saveSafesToFile()
    local file = io.open(SAFES_FILE, 'w')
    if not file then
        print('[sj_safes] ERROR: Could not open file for writing: ' .. SAFES_FILE)
        return false
    end
    
    local saveData = {
        safes = placedSafes,
        playerCounts = playerSafeCounts,
        timestamp = os.time()
    }
    
    local success, jsonData = pcall(json.encode, saveData)
    if not success then
        print('[sj_safes] ERROR: Could not encode data to JSON')
        file:close()
        return false
    end
    
    file:write(jsonData)
    file:close()
    
    local safeCount = 0
    for _ in pairs(placedSafes) do
        safeCount = safeCount + 1
    end
    
    print('[sj_safes] Saved ' .. safeCount .. ' safes to file: ' .. SAFES_FILE)
    return true
end

local function loadSafesFromFile()
    local file = io.open(SAFES_FILE, 'r')
    if not file then
        print('[sj_safes] No existing safes file found, starting fresh: ' .. SAFES_FILE)
        return
    end
    
    local content = file:read('*all')
    file:close()
    
    if not content or content == '' then
        print('[sj_safes] Empty safes file, starting fresh')
        return
    end
    
    local success, data = pcall(json.decode, content)
    if not success or not data then
        print('[sj_safes] ERROR: Could not parse safes file, starting fresh')
        return
    end
    
    placedSafes = data.safes or {}
    playerSafeCounts = data.playerCounts or {}
    
    local safeCount = 0
    for _ in pairs(placedSafes) do
        safeCount = safeCount + 1
    end
    
    print('[sj_safes] Loaded ' .. safeCount .. ' safes from file: ' .. SAFES_FILE)
    
    -- Re-register all stashes and spawn safes for clients
    for stashId, safe in pairs(placedSafes) do
        local safeConfig = Config.SafeTypes[safe.type]
        if safeConfig then
            -- Re-register the stash
            exports.ox_inventory:RegisterStash(
                stashId,
                safeConfig.label,
                safeConfig.slots,
                safeConfig.maxWeight,
                false,
                nil,
                safe.coords
            )
        end
    end
    
    TriggerClientEvent('sj_safes:client:syncSafes', -1, placedSafes)
end

-- Generate safe combination
local function generateCombination()
    local combo = {}
    for i = 1, 3 do
        combo[i] = math.random(0, 100)
    end
    return table.concat(combo, '-')
end


-- Generate unique ID for safes
local function generateSafeId()
    return string.format('%d_%d_%d', os.time(), math.random(1000, 9999), math.random(1000, 9999))
end

-- Check if player is admin
local function isPlayerAdmin(source)
    -- Server console is always admin
    if source == 0 then return true end
    
    -- Check if player has the sj_safes.admin ace permission
    return IsPlayerAceAllowed(source, "sj_safes.admin")
end

-- Hook into item creation to add metadata to safes
local function createItemHook(payload)
    local item = payload.item
    local itemName = item.name
    
    -- Check if it's a safe item
    if Config.SafeTypes[itemName] then
        local metadata = {}
        if payload.metadata and type(payload.metadata) == "table" and not payload.metadata[1] then
            metadata = payload.metadata
        end
        
        -- Generate unique combination for this safe
        metadata.combination = generateCombination()
        metadata.safeId = generateSafeId()
        metadata.description = Config.SafeTypes[itemName].description
        metadata.label = Config.SafeTypes[itemName].label
        
        return metadata
    end
    
    -- Return nil if not a safe item (don't modify other items)
    return nil
end

-- Register the hook
local hookId = exports.ox_inventory:registerHook('createItem', createItemHook, {
    itemFilter = {
        small_safe = true,
        large_safe = true
    }
})

print('[sj_safes] Hook registered with ID:', hookId)

-- Validate placement coordinates
local function validatePlacementCoords(source, coords)
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    local distance = #(coords - playerCoords)
    
    -- Check distance from player (max 15 units)
    if distance > 15.0 then
        return false, "Safe placement too far from player"
    end
    
    -- Check minimum distance (prevent placement inside player)
    if distance < 1.0 then
        return false, "Safe placement too close to player"
    end
    
    -- Basic coordinate validation (within reasonable map bounds)
    if coords.x < -4000 or coords.x > 4000 or coords.y < -4000 or coords.y > 4000 then
        return false, "Safe placement outside map boundaries"
    end
    
    -- Check Z coordinate
    if coords.z < -100 or coords.z > 1000 then
        return false, "Invalid placement height"
    end
    
    return true, "Valid placement"
end

-- Place a safe in the world
RegisterNetEvent('sj_safes:server:placeSafe', function(safeType, coords, rotation, clientMetadata)
    local source = source
    print('[sj_safes] Received placeSafe event from source:', source)
    print('[sj_safes] Safe type:', safeType)
    print('[sj_safes] Coords:', coords)
    print('[sj_safes] Rotation:', rotation)
    
    local Player = exports.qbx_core:GetPlayer(source)
    
    if not Player then 
        print('[sj_safes] Player not found for source:', source)
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Player not found'
        })
        return 
    end
    
    print('[sj_safes] Player citizenid:', Player.PlayerData.citizenid)
    
    -- Validate safe type server-side
    local safeConfig = Config.SafeTypes[safeType]
    if not safeConfig then 
        print('[sj_safes] Safe config not found for type:', safeType)
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Invalid safe type'
        })
        return 
    end
    
    -- Validate placement coordinates
    local isValid, reason = validatePlacementCoords(source, coords)
    if not isValid then
        print('[sj_safes] Invalid placement coordinates:', reason)
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = reason
        })
        return
    end
    
    -- Regenerate metadata server-side (don't trust client metadata)
    local metadata = {
        combination = generateCombination(),
        safeId = generateSafeId(),
        description = safeConfig.description,
        label = safeConfig.label
    }
    
    -- Validate the client had a safe item with valid metadata structure
    if not clientMetadata or not clientMetadata.safeId then
        print('[sj_safes] Invalid client metadata')
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Invalid safe item'
        })
        return
    end
    
    -- Check player safe limit
    local playerId = Player.PlayerData.citizenid
    playerSafeCounts[playerId] = playerSafeCounts[playerId] or 0
    
    if Config.General.maxSafesPerPlayer > 0 and playerSafeCounts[playerId] >= Config.General.maxSafesPerPlayer then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'You have reached the maximum number of safes you can place'
        })
        return
    end
    
    -- Create unique stash ID
    local stashId = 'safe_' .. metadata.safeId
    
    -- Register the stash
    exports.ox_inventory:RegisterStash(
        stashId,
        safeConfig.label,
        safeConfig.slots,
        safeConfig.maxWeight,
        false, -- Not owned by specific player
        nil, -- No group restrictions
        coords
    )
    
    -- Store safe data
    placedSafes[stashId] = {
        id = stashId,
        type = safeType,
        coords = coords,
        rotation = rotation,
        combination = metadata.combination,
        owner = Player.PlayerData.citizenid,
        prop = safeConfig.prop
    }
    
    -- Increment player safe count
    playerSafeCounts[playerId] = playerSafeCounts[playerId] + 1
    
    -- Notify all clients about the new safe (WITHOUT combination)
    local clientSafeData = {
        id = stashId,
        type = safeType,
        coords = coords,
        rotation = rotation,
        owner = Player.PlayerData.citizenid,
        prop = safeConfig.prop
        -- Note: combination is NOT sent to client for security
    }
    TriggerClientEvent('sj_safes:client:addSafe', -1, stashId, clientSafeData)
    
    -- Save to file
    saveSafesToFile()
    
    print(('[sj_safes] Safe placed: %s at %s with combination: %s'):format(stashId, coords, metadata.combination))
end)

-- Get safe combination for cracking (temporary access)
RegisterNetEvent('sj_safes:server:getSafeCombination', function(safeId)
    local source = source
    local safe = placedSafes[safeId]
    
    if not safe then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Safe not found'
        })
        return
    end
    
    -- Send combination temporarily for minigame
    TriggerClientEvent('sj_safes:client:receiveCombination', source, safeId, safe.combination)
end)

-- Open safe (check combination first)
RegisterNetEvent('sj_safes:server:openSafe', function(safeId, enteredCombination)
    local source = source
    local safe = placedSafes[safeId]
    
    if not safe then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Safe not found'
        })
        return
    end
    
    -- Check combination
    if enteredCombination == safe.combination then
        -- Open the stash
        exports.ox_inventory:forceOpenInventory(source, 'stash', safeId)
        
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'success',
            description = 'Safe opened successfully'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Incorrect combination'
        })
    end
end)

-- Set safe combination (owner only)
RegisterNetEvent('sj_safes:server:setCombination', function(safeId, newCombination)
    local source = source
    local safe = placedSafes[safeId]
    
    if not safe then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Safe not found'
        })
        return
    end
    
    -- Check if player is the owner
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player or Player.PlayerData.citizenid ~= safe.owner then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'You are not the owner of this safe'
        })
        return
    end
    
    -- Validate combination format
    local parts = {}
    for part in string.gmatch(newCombination, '([^-]+)') do
        local num = tonumber(part)
        if not num or num < 0 or num > 100 then
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'error',
                description = 'Invalid combination. Numbers must be between 0-100'
            })
            return
        end
        table.insert(parts, num)
    end
    
    if #parts ~= 3 then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Combination must have exactly 3 numbers'
        })
        return
    end
    
    -- Update the combination
    safe.combination = newCombination
    
    -- Save to file
    saveSafesToFile()
    
    -- Notify all clients about the combination change
    TriggerClientEvent('sj_safes:client:updateCombination', -1, safeId, newCombination)
    
    TriggerClientEvent('ox_lib:notify', source, {
        type = 'success',
        description = 'Safe combination updated successfully'
    })
    
    print(('[sj_safes] Safe %s combination changed to: %s by %s'):format(safeId, newCombination, Player.PlayerData.citizenid))
end)

-- Remove safe
RegisterNetEvent('sj_safes:server:removeSafe', function(safeId)
    local source = source
    local safe = placedSafes[safeId]
    
    if not safe then return end
    
    -- Check if player is the owner
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player or Player.PlayerData.citizenid ~= safe.owner then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'You are not the owner of this safe'
        })
        return
    end
    
    -- Check if safe is empty (always required for player removal)
    local stashItems = exports.ox_inventory:GetInventory(safeId)
    if stashItems and stashItems.items and next(stashItems.items) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Safe must be empty before removal'
        })
        return
    end
    
    -- Remove from tracking
    placedSafes[safeId] = nil
    playerSafeCounts[safe.owner] = math.max(0, (playerSafeCounts[safe.owner] or 0) - 1)
    
    -- Save to file
    saveSafesToFile()
    
    -- Notify all clients to remove the safe
    TriggerClientEvent('sj_safes:client:removeSafe', -1, safeId)
    
    TriggerClientEvent('ox_lib:notify', source, {
        type = 'success',
        description = 'Safe removed successfully'
    })
end)

-- Get all safes (for client sync)
RegisterNetEvent('sj_safes:server:getSafes', function()
    local source = source
    
    -- Create client-safe data (WITHOUT combinations)
    local clientSafes = {}
    for safeId, safeData in pairs(placedSafes) do
        clientSafes[safeId] = {
            id = safeId,
            type = safeData.type,
            coords = safeData.coords,
            rotation = safeData.rotation,
            owner = safeData.owner,
            prop = safeData.prop
            -- Note: combination is NOT sent to client for security
        }
    end
    
    TriggerClientEvent('sj_safes:client:syncSafes', source, clientSafes)
end)

-- Admin function to remove safe (bypasses empty check)
local function adminRemoveSafe(safeId, source)
    local safe = placedSafes[safeId]
    if not safe then return false end
    
    -- Remove from tracking
    placedSafes[safeId] = nil
    playerSafeCounts[safe.owner] = math.max(0, (playerSafeCounts[safe.owner] or 0) - 1)
    
    -- Clear the stash inventory
    exports.ox_inventory:ClearInventory(safeId)
    
    -- Save to file
    saveSafesToFile()
    
    -- Notify all clients to remove the safe
    TriggerClientEvent('sj_safes:client:removeSafe', -1, safeId)
    
    print(('[sj_safes] Admin removed safe: %s (by source: %s)'):format(safeId, source or 'console'))
    return true
end

-- Admin command to manage safes
RegisterCommand('safes', function(source, args)
    -- Check if player is admin
    if not isPlayerAdmin(source) then
        if source == 0 then
            print('This command is restricted to administrators')
        else
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'error',
                description = 'You do not have permission to use this command'
            })
        end
        return
    end
    
    if source == 0 then -- Server console commands
        -- Handle console commands
        if args[1] == 'list' then
            print('=== All Safes ===')
            for safeId, safe in pairs(placedSafes) do
                print(('ID: %s | Type: %s | Owner: %s | Coords: %s | Combination: %s'):format(
                    safeId, safe.type, safe.owner, safe.coords, safe.combination
                ))
            end
        elseif args[1] == 'remove' and args[2] then
            if adminRemoveSafe(args[2], source) then
                print('Safe removed successfully')
            else
                print('Safe not found')
            end
        else
            print('Usage: safes <list|remove> [safeId]')
        end
        return
    end
    
    -- For in-game players - admin check already done above
    -- Send safe management menu to client
    TriggerClientEvent('sj_safes:client:openAdminMenu', source)
end)

-- Get safes for admin menu
RegisterNetEvent('sj_safes:server:getAdminSafes', function()
    local source = source
    
    -- Check admin permissions
    if not isPlayerAdmin(source) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'You do not have permission to use this command'
        })
        return
    end
    
    local safesList = {}
    for safeId, safe in pairs(placedSafes) do
        local stashItems = exports.ox_inventory:GetInventory(safeId)
        local itemCount = 0
        if stashItems and stashItems.items then
            for _, item in pairs(stashItems.items) do
                if item.count then
                    itemCount = itemCount + item.count
                end
            end
        end
        
        table.insert(safesList, {
            id = safeId,
            type = safe.type,
            owner = safe.owner,
            coords = safe.coords,
            combination = safe.combination,
            itemCount = itemCount,
            isEmpty = itemCount == 0
        })
    end
    
    TriggerClientEvent('sj_safes:client:receiveAdminSafes', source, safesList)
end)

-- Admin remove safe
RegisterNetEvent('sj_safes:server:adminRemoveSafe', function(safeId)
    local source = source
    
    -- Check admin permissions
    if not isPlayerAdmin(source) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'You do not have permission to use this command'
        })
        return
    end
    
    if adminRemoveSafe(safeId, source) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'success',
            description = 'Safe removed successfully'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Safe not found'
        })
    end
end)

-- Add safe item to inventory (for testing/admin)
RegisterCommand('givesafe', function(source, args)
    -- Check admin permissions
    if not isPlayerAdmin(source) then
        if source == 0 then
            print('This command is restricted to administrators')
        else
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'error',
                description = 'You do not have permission to use this command'
            })
        end
        return
    end
    
    if source == 0 then -- Server console
        local playerId = tonumber(args[1])
        local safeType = args[2] or 'small_safe'
        local count = tonumber(args[3]) or 1
        
        if not playerId or not Config.SafeTypes[safeType] then
            print('Usage: givesafe <playerId> <safeType> [count]')
            print('Safe types: small_safe, large_safe')
            return
        end
        
        -- Create metadata for the safe
        local metadata = {
            combination = generateCombination(),
            safeId = generateSafeId(),
            description = Config.SafeTypes[safeType].description,
            label = Config.SafeTypes[safeType].label
        }
        
        local success = exports.ox_inventory:AddItem(playerId, safeType, count, metadata)
        print(('Given %d %s to player %d'):format(count, safeType, playerId))
    else
        -- In-game admin command
        local targetId = tonumber(args[1]) or source -- Default to self if no target
        local safeType = args[2] or 'small_safe'
        local count = tonumber(args[3]) or 1
        
        if not Config.SafeTypes[safeType] then
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'error',
                description = 'Invalid safe type. Use: small_safe, large_safe'
            })
            return
        end
        
        -- Create metadata for the safe
        local metadata = {
            combination = generateCombination(),
            safeId = generateSafeId(),
            description = Config.SafeTypes[safeType].description,
            label = Config.SafeTypes[safeType].label
        }
        
        local success = exports.ox_inventory:AddItem(targetId, safeType, count, metadata)
        if success then
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'success',
                description = 'Safe item given successfully'
            })
        else
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'error',
                description = 'Failed to give safe item'
            })
        end
    end
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Clean up hooks
        if hookId then
            exports.ox_inventory:removeHooks(hookId)
        end
    end
end)



-- Initialize on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Load safes from JSON file
        loadSafesFromFile()
        print('[sj_safes] Server started successfully')
    end
end) 