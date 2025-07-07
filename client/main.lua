local placedSafes = {}
local placementMode = false
local currentSafeData = nil
local previewObject = nil
local previewRotation = 0.0
local previewCoords = vector3(0, 0, 0)


local dataview = setmetatable({
    EndBig = ">",
    EndLittle = "<",
    Types = {
        Int8 = { code = "i1" },
        Uint8 = { code = "I1" },
        Int16 = { code = "i2" },
        Uint16 = { code = "I2" },
        Int32 = { code = "i4" },
        Uint32 = { code = "I4" },
        Int64 = { code = "i8" },
        Uint64 = { code = "I8" },
        Float32 = { code = "f", size = 4 }, -- a float (native size)
        Float64 = { code = "d", size = 8 }, -- a double (native size)

        LuaInt = { code = "j" }, -- a lua_Integer
        UluaInt = { code = "J" }, -- a lua_Unsigned
        LuaNum = { code = "n" }, -- a lua_Number
        String = { code = "z", size = -1, }, -- zero terminated string
    },

    FixedTypes = {
        String = { code = "c" }, -- a fixed-sized string with n bytes
        Int = { code = "i" }, -- a signed int with n bytes
        Uint = { code = "I" }, -- an unsigned int with n bytes
    },
}, {
    __call = function(_, length)
        return dataview.ArrayBuffer(length)
    end
})
dataview.__index = dataview

-- Create an ArrayBuffer with a size in bytes
function dataview.ArrayBuffer(length)
    return setmetatable({
        blob = string.blob(length),
        length = length,
        offset = 1,
        cangrow = true,
    }, dataview)
end

-- Return the underlying bytebuffer
function dataview:Buffer() return self.blob end

-- Return the Endianness format character
local function ef(big) return (big and dataview.EndBig) or dataview.EndLittle end

-- Helper function for setting fixed datatypes within a buffer
local function packblob(self, offset, value, code)
    local packed = self.blob:blob_pack(offset, code, value)
    if self.cangrow or packed == self.blob then
        self.blob = packed
        self.length = packed:len()
        return true
    else
        return false
    end
end

-- Create the Float32 API methods we need
dataview.Types.Float32.size = string.packsize(dataview.Types.Float32.code)

function dataview:GetFloat32(offset, endian)
    offset = offset or 0
    if offset >= 0 then
        local o = self.offset + offset
        local v,_ = self.blob:blob_unpack(o, ef(endian) .. dataview.Types.Float32.code)
        return v
    end
    return nil
end

function dataview:SetFloat32(offset, value, endian)
    if offset >= 0 and value then
        local o = self.offset + offset
        local v_size = dataview.Types.Float32.size
        if self.cangrow or ((o + (v_size - 1)) <= self.length) then
            if not packblob(self, o, value, ef(endian) .. dataview.Types.Float32.code) then
                error("cannot grow subview")
            end
        else
            error("cannot grow dataview")
        end
    end
    return self
end

local enableScale = false -- allow scaling mode. doesnt scale collisions and resets when physics are applied it seems
local isCursorActive = false
local gizmoEnabled = false
local currentMode = 'translate'
local isRelative = false
local currentEntity



-- NUI Callbacks
RegisterNUICallback('safeCrackingComplete', function(data, cb)
    print('[sj_safes] NUI callback: safeCrackingComplete', json.encode(data))
    SetNuiFocus(false, false)
    
    if data.success then
        -- Send combination to server to open safe
        local combination = table.concat(data.combination, '-')
        print('[sj_safes] Sending combination to server:', combination)
        TriggerServerEvent('sj_safes:server:openSafe', currentSafeData.id, combination)
    else
        lib.notify({
            type = 'error',
            description = 'Failed to crack the safe'
        })
    end
    
    currentSafeData = nil
    cb('ok')
end)

RegisterNUICallback('closeSafeCracking', function(data, cb)
    print('[sj_safes] NUI callback: closeSafeCracking')
    SetNuiFocus(false, false)
    currentSafeData = nil
    cb('ok')
end)

-- GIZMO HELPER FUNCTIONS
local function normalize(x, y, z)
    local length = math.sqrt(x * x + y * y + z * z)
    if length == 0 then
        return 0, 0, 0
    end
    return x / length, y / length, z / length
end

local function makeEntityMatrix(entity)
    local f, r, u, a = GetEntityMatrix(entity)
    local view = dataview.ArrayBuffer(60)

    view:SetFloat32(0, r[1])
        :SetFloat32(4, r[2])
        :SetFloat32(8, r[3])
        :SetFloat32(12, 0)
        :SetFloat32(16, f[1])
        :SetFloat32(20, f[2])
        :SetFloat32(24, f[3])
        :SetFloat32(28, 0)
        :SetFloat32(32, u[1])
        :SetFloat32(36, u[2])
        :SetFloat32(40, u[3])
        :SetFloat32(44, 0)
        :SetFloat32(48, a[1])
        :SetFloat32(52, a[2])
        :SetFloat32(56, a[3])
        :SetFloat32(60, 1)

    return view
end

local function applyEntityMatrix(entity, view)
    local x1, y1, z1 = view:GetFloat32(16), view:GetFloat32(20), view:GetFloat32(24)
    local x2, y2, z2 = view:GetFloat32(0), view:GetFloat32(4), view:GetFloat32(8)
    local x3, y3, z3 = view:GetFloat32(32), view:GetFloat32(36), view:GetFloat32(40)
    local tx, ty, tz = view:GetFloat32(48), view:GetFloat32(52), view:GetFloat32(56)

    if not enableScale then
        x1, y1, z1 = normalize(x1, y1, z1)
        x2, y2, z2 = normalize(x2, y2, z2)
        x3, y3, z3 = normalize(x3, y3, z3)
    end

    SetEntityMatrix(entity,
        x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        tx, ty, tz
    )
end

-- GIZMO LOOPS
local function gizmoLoop(entity)
    if not gizmoEnabled then
        return LeaveCursorMode()
    end

    EnterCursorMode()
    isCursorActive = true

    if IsEntityAPed(entity) then
        SetEntityAlpha(entity, 200)
    else
        SetEntityDrawOutline(entity, true)
    end
    
    while gizmoEnabled and DoesEntityExist(entity) do
        Wait(0)
        if IsControlJustPressed(0, 47) then -- G
            if isCursorActive then
                LeaveCursorMode()
                isCursorActive = false
            else
                EnterCursorMode()
                isCursorActive = true
            end
        end
        DisableControlAction(0, 24, true)  -- lmb
        DisableControlAction(0, 25, true)  -- rmb
        DisableControlAction(0, 140, true) -- r
        DisablePlayerFiring(cache.playerId, true)

        local matrixBuffer = makeEntityMatrix(entity)
        local changed = Citizen.InvokeNative(0xEB2EDCA2, matrixBuffer:Buffer(), 'Editor1',
            Citizen.ReturnResultAnyway())

        if changed then
            applyEntityMatrix(entity, matrixBuffer)
        end
    end
    
    if isCursorActive then
        LeaveCursorMode()
    end
    isCursorActive = false

    if DoesEntityExist(entity) then
        if IsEntityAPed(entity) then SetEntityAlpha(entity, 255) end
        SetEntityDrawOutline(entity, false)
    end

    gizmoEnabled = false
    currentEntity = nil
end

local function GetVectorText(vectorType) 
    if not currentEntity then return 'ERR_NO_ENTITY_' .. (vectorType or "UNK") end
    local label = (vectorType == "coords" and "Position" or "Rotation")
    local vec = (vectorType == "coords" and GetEntityCoords(currentEntity) or GetEntityRotation(currentEntity))
    return ('%s: %.2f, %.2f, %.2f'):format(label, vec.x, vec.y, vec.z)
end

local function textUILoop()
    CreateThread(function()
        while gizmoEnabled do
            Wait(100)

            local scaleText = (enableScale and '[S] - Scale Mode  \n') or ''
            local modeLine = 'Current Mode: ' .. currentMode .. ' | ' .. (isRelative and 'Relative' or 'World') .. '  \n'

            lib.showTextUI(
                modeLine ..
                GetVectorText("coords") .. '  \n' ..
                GetVectorText("rotation") .. '  \n' ..
                '[G]     - ' .. (isCursorActive and "Disable Cursor" or "Enable Cursor") .. '  \n' ..
                '[W]     - Translate Mode  \n' ..
                '[R]     - Rotate Mode  \n' ..
                scaleText ..
                '[Q]     - Toggle Space  \n' ..
                '[LALT]  - Snap to Ground  \n' ..
                '[ENTER] - Done Editing  \n'
            )
        end
        lib.hideTextUI()
    end)
end

-- GIZMO MAIN FUNCTION
local function useGizmo(entity)
    gizmoEnabled = true
    currentEntity = entity
    
    textUILoop()
    gizmoLoop(entity)

    -- Wait a few frames to ensure entity position is synchronized
    Wait(50)
    
    -- Get final position after gizmo manipulation
    local finalCoords = GetEntityCoords(entity)
    local finalRotation = GetEntityRotation(entity)

    return {
        handle = entity,
        position = finalCoords,
        rotation = finalRotation
    }
end

-- Safe placement functions
function startPlacement(safeType, slot, metadata)
    if placementMode then return end
    
    placementMode = true
    currentSafeData = {
        type = safeType,
        slot = slot,
        metadata = metadata
    }
    
    -- Close inventory
    exports.ox_inventory:closeInventory()
    
    -- Get safe config
    local safeConfig = Config.SafeTypes[safeType]
    if not safeConfig then
        lib.notify({
            type = 'error',
            description = 'Invalid safe type'
        })
        return
    end
    
    -- Create preview object
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local playerHeading = GetEntityHeading(playerPed)
    
    -- Place 3 units in front of player
    local forwardX = playerCoords.x + math.sin(math.rad(playerHeading)) * 3.0
    local forwardY = playerCoords.y + math.cos(math.rad(playerHeading)) * 3.0
    local groundZ = playerCoords.z
    
    local modelHash = GetHashKey(safeConfig.prop)
    lib.requestModel(modelHash)
    
    previewObject = CreateObject(modelHash, forwardX, forwardY, groundZ, false, false, false)
    SetEntityAlpha(previewObject, 150, false) -- Semi-transparent
    SetEntityCollision(previewObject, false, false)
    SetEntityCanBeDamaged(previewObject, false)
    FreezeEntityPosition(previewObject, true)
    
    -- Start gizmo
    local result = useGizmo(previewObject)
    
    -- After gizmo is done, place the safe
    placeSafe(result)
end

function cancelPlacement()
    placementMode = false
    gizmoEnabled = false
    currentSafeData = nil
    
    if DoesEntityExist(previewObject) then
        DeleteEntity(previewObject)
        previewObject = nil
    end
end

function placeSafe(gizmoResult)
    if not currentSafeData or not gizmoResult then 
        cancelPlacement()
        return 
    end
    
    local coords = gizmoResult.position
    local rotation = gizmoResult.rotation
    
    -- Create the data object that useItem expects
    local itemData = {
        name = currentSafeData.type,
        slot = currentSafeData.slot.slot,
        metadata = currentSafeData.metadata
    }
    
    -- Remove the item from inventory first
    exports.ox_inventory:useItem(itemData, function(data)
        if data then
            -- Send to server to place safe
            TriggerServerEvent('sj_safes:server:placeSafe', currentSafeData.type, coords, rotation, currentSafeData.metadata)
            
            lib.notify({
                type = 'success',
                description = 'Safe placed successfully'
            })
        else
            lib.notify({
                type = 'error',
                description = 'Failed to place safe'
            })
        end
        
        -- Clean up
        cancelPlacement()
    end)
end

-- Safe interaction functions
local function setCombination(safeId)
    -- Get the first number
    local input1 = lib.inputDialog('Set Safe Combination - Number 1', {
        {type = 'number', label = 'First Number (0-100)', placeholder = '0-100', min = 0, max = 100, required = true}
    })
    
    if not input1 then return end
    
    -- Get the second number
    local input2 = lib.inputDialog('Set Safe Combination - Number 2', {
        {type = 'number', label = 'Second Number (0-100)', placeholder = '0-100', min = 0, max = 100, required = true}
    })
    
    if not input2 then return end
    
    -- Get the third number
    local input3 = lib.inputDialog('Set Safe Combination - Number 3', {
        {type = 'number', label = 'Third Number (0-100)', placeholder = '0-100', min = 0, max = 100, required = true}
    })
    
    if not input3 then return end
    
    -- Send the new combination to server
    local newCombination = input1[1] .. '-' .. input2[1] .. '-' .. input3[1]
    TriggerServerEvent('sj_safes:server:setCombination', safeId, newCombination)
end

local function openSafeCracking(safeId)
    currentSafeData = placedSafes[safeId]
    if not currentSafeData then 
        return 
    end
    
    -- Store the safeId for later use
    currentSafeData.id = safeId
    
    -- Request combination from server for minigame
    TriggerServerEvent('sj_safes:server:getSafeCombination', safeId)
end

-- Safe management functions
local function createSafeEntity(safeData)
    
    local safeConfig = Config.SafeTypes[safeData.type]
    if not safeConfig then 
        return 
    end
    
    -- Create safe object
    lib.requestModel(safeConfig.prop)
    local modelHash = GetHashKey(safeConfig.prop)
    local safeObject = CreateObject(modelHash, safeData.coords.x, safeData.coords.y, safeData.coords.z, false, false, false)
    
    -- Force the entity to the exact position (CreateObject might auto-adjust Z)
    SetEntityCoords(safeObject, safeData.coords.x, safeData.coords.y, safeData.coords.z, false, false, false, true)
    
    if safeData.rotation then
        SetEntityRotation(safeObject, safeData.rotation.x, safeData.rotation.y, safeData.rotation.z, 2, true)
    elseif safeData.heading then
        -- Backwards compatibility
        SetEntityHeading(safeObject, safeData.heading)
    end
    FreezeEntityPosition(safeObject, true)
    
    -- Verify the actual entity position after creation
    local actualCoords = GetEntityCoords(safeObject)
    local actualRotation = GetEntityRotation(safeObject)
    
    -- Store reference
    safeData.entity = safeObject
    
    -- Add interaction target
    exports.ox_target:addLocalEntity(safeObject, {
        {
            name = 'open_safe',
            label = 'Open Safe',
            icon = 'fa-solid fa-unlock',
            onSelect = function()
                openSafeCracking(safeData.id)
            end
        },
        {
            name = 'set_combination',
            label = 'Set Combination',
            icon = 'fa-solid fa-key',
            onSelect = function()
                setCombination(safeData.id)
            end,
            canInteract = function()
                -- Only for owners - will be checked server-side
                return true
            end
        },
        {
            name = 'remove_safe',
            label = 'Remove Safe',
            icon = 'fa-solid fa-trash',
            onSelect = function()
                TriggerServerEvent('sj_safes:server:removeSafe', safeData.id)
            end,
            canInteract = function()
                -- Only owner can remove
                return true -- Server will check ownership
            end
        }
    })
end

local function removeSafeEntity(safeId)
    local safeData = placedSafes[safeId]
    if not safeData then return end
    
    -- Remove target
    if DoesEntityExist(safeData.entity) then
        exports.ox_target:removeLocalEntity(safeData.entity)
        DeleteEntity(safeData.entity)
    end
    
    -- Remove from tracking
    placedSafes[safeId] = nil
end

-- Item usage exports
exports('small_safe', function(data, slot)
    local metadata = slot and slot.metadata
    
    if not metadata or not metadata.combination then
        lib.notify({
            type = 'error',
            description = 'Invalid safe item - no metadata found'
        })
        return
    end
    
    startPlacement('small_safe', slot, metadata)
end)

exports('large_safe', function(data, slot)
    local metadata = slot and slot.metadata
    
    if not metadata or not metadata.combination then
        lib.notify({
            type = 'error',
            description = 'Invalid safe item - no metadata found'
        })
        return
    end
    
    startPlacement('large_safe', slot, metadata)
end)

-- Network events
RegisterNetEvent('sj_safes:client:addSafe', function(safeId, safeData)
    print('[sj_safes] Received addSafe event - safeId:', safeId)
    print('[sj_safes] Safe data:', json.encode(safeData))
    
    -- Make sure the safeData has the ID
    safeData.id = safeId
    
    placedSafes[safeId] = safeData
    createSafeEntity(safeData)
end)

RegisterNetEvent('sj_safes:client:removeSafe', function(safeId)
    removeSafeEntity(safeId)
end)

RegisterNetEvent('sj_safes:client:updateCombination', function(safeId, newCombination)
    print('[sj_safes] Combination updated for safe:', safeId)
    -- Note: We don't store the combination client-side for security
    -- The server handles all combination validation
end)

-- Receive combination temporarily for minigame
RegisterNetEvent('sj_safes:client:receiveCombination', function(safeId, combination)
    print('[sj_safes] Received combination for safe:', safeId)
    
    -- Open NUI for safe cracking with the combination
    SetNuiFocus(true, true)
    
    local configToSend = {
        difficulty = Config.General.difficulty,
        SafeCracking = Config.SafeCracking,
        UI = Config.UI,
        combination = combination -- Pass the actual safe combination temporarily
    }
    
    print('[sj_safes] Sending config to NUI:', json.encode(configToSend))
    
    SendNUIMessage({
        action = 'openSafeCracking',
        config = configToSend
    })
    print('[sj_safes] NUI message sent')
end)

RegisterNetEvent('sj_safes:client:syncSafes', function(safes)
    -- Clear existing safes
    for safeId, _ in pairs(placedSafes) do
        removeSafeEntity(safeId)
    end
    
    -- Add new safes
    for safeId, safeData in pairs(safes) do
        placedSafes[safeId] = safeData
        createSafeEntity(safeData)
    end
end)

-- Initialize
CreateThread(function()
    -- Request safes from server
    TriggerServerEvent('sj_safes:server:getSafes')
    
    -- Disable controls during placement
    while true do
        if placementMode then
            DisableControlAction(0, 32, true) -- W (forward)
            DisableControlAction(0, 33, true) -- S (backward)
            DisableControlAction(0, 34, true) -- A (left)
            DisableControlAction(0, 35, true) -- D (right)
            DisableControlAction(0, 19, true) -- R (rotation mode)
            DisableControlAction(0, 191, true) -- ENTER (place)
            DisableControlAction(0, 200, true) -- ESC (cancel)
        end
        Wait(0)
    end
end)

-- Admin menu functions
local function showAdminMenu(safesList)
    local menuOptions = {}
    
    -- Add header
    table.insert(menuOptions, {
        title = 'Safe Management',
        description = 'Total Safes: ' .. #safesList,
        icon = 'fa-solid fa-shield-halved',
        disabled = true
    })
    
    -- Add each safe
    for _, safe in ipairs(safesList) do
        local ownerText = safe.owner or 'Unknown'
        local statusText = safe.isEmpty and 'Empty' or ('Items: ' .. safe.itemCount)
        local typeText = safe.type:gsub('_', ' '):upper()
        
        table.insert(menuOptions, {
            title = typeText .. ' (' .. safe.id .. ')',
            description = 'Owner: ' .. ownerText .. ' | ' .. statusText,
            icon = safe.isEmpty and 'fa-solid fa-box-open' or 'fa-solid fa-box',
            onSelect = function()
                local confirmed = lib.alertDialog({
                    header = 'Delete Safe',
                    content = 'Are you sure you want to delete this safe?\n\n' ..
                             'Type: ' .. typeText .. '\n' ..
                             'Owner: ' .. ownerText .. '\n' ..
                             'Status: ' .. statusText .. '\n' ..
                             'Combination: ' .. safe.combination,
                    centered = true,
                    cancel = true
                })
                
                if confirmed == 'confirm' then
                    TriggerServerEvent('sj_safes:server:adminRemoveSafe', safe.id)
                    
                    -- Refresh the menu
                    TriggerServerEvent('sj_safes:server:getAdminSafes')
                end
            end
        })
    end
    
    -- If no safes
    if #safesList == 0 then
        table.insert(menuOptions, {
            title = 'No Safes Found',
            description = 'There are no safes placed on the server',
            icon = 'fa-solid fa-info-circle',
            disabled = true
        })
    end
    
    -- Add refresh option
    table.insert(menuOptions, {
        title = 'Refresh List',
        description = 'Reload the safes list',
        icon = 'fa-solid fa-refresh',
        onSelect = function()
            TriggerServerEvent('sj_safes:server:getAdminSafes')
        end
    })
    
    lib.registerContext({
        id = 'sj_safes_admin_menu',
        title = 'Safe Management',
        options = menuOptions
    })
    
    lib.showContext('sj_safes_admin_menu')
end

-- Admin menu events
RegisterNetEvent('sj_safes:client:openAdminMenu', function()
    TriggerServerEvent('sj_safes:server:getAdminSafes')
end)

RegisterNetEvent('sj_safes:client:receiveAdminSafes', function(safesList)
    showAdminMenu(safesList)
end)

-- GIZMO KEYBINDS
lib.addKeybind({
    name = '_gizmoSelect',
    description = 'Select gizmo element',
    defaultMapper = 'MOUSE_BUTTON',
    defaultKey = 'MOUSE_LEFT',
    onPressed = function(self)
        if not gizmoEnabled then return end
        ExecuteCommand('+gizmoSelect')
    end,
    onReleased = function (self)
        ExecuteCommand('-gizmoSelect')
    end
})

lib.addKeybind({
    name = '_gizmoTranslation',
    description = 'Translation mode',
    defaultKey = 'W',
    onPressed = function(self)
        if not gizmoEnabled then return end
        currentMode = 'Translate'
        ExecuteCommand('+gizmoTranslation')
    end,
    onReleased = function (self)
        ExecuteCommand('-gizmoTranslation')
    end
})

lib.addKeybind({
    name = '_gizmoRotation',
    description = 'Rotation mode',
    defaultKey = 'R',
    onPressed = function(self)
        if not gizmoEnabled then return end
        currentMode = 'Rotate'
        ExecuteCommand('+gizmoRotation')
    end,
    onReleased = function (self)
        ExecuteCommand('-gizmoRotation')
    end
})

lib.addKeybind({
    name = '_gizmoLocal',
    description = 'Toggle space',
    defaultKey = 'Q',
    onPressed = function(self)
        if not gizmoEnabled then return end
        isRelative = not isRelative
        ExecuteCommand('+gizmoLocal')
    end,
    onReleased = function (self)
        ExecuteCommand('-gizmoLocal')
    end
})

lib.addKeybind({
    name = 'gizmoclose',
    description = 'Close gizmo',
    defaultKey = 'RETURN',
    onPressed = function(self)
        if not gizmoEnabled then return end
        gizmoEnabled = false
    end,
})

lib.addKeybind({
    name = 'gizmoSnapToGround',
    description = 'Snap to ground',
    defaultKey = 'LMENU',
    onPressed = function(self)
        if not gizmoEnabled then return end
        PlaceObjectOnGroundProperly_2(currentEntity)
    end,
})

if enableScale then
    lib.addKeybind({
        name = '_gizmoScale',
        description = 'Scale mode',
        defaultKey = 'S',
        onPressed = function(self)
            if not gizmoEnabled then return end
            currentMode = 'Scale'
            ExecuteCommand('+gizmoScale')
        end,
        onReleased = function (self)
            ExecuteCommand('-gizmoScale')
        end
    })
end

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Clean up placement mode
        if placementMode then
            cancelPlacement()
        end
        
        -- Clean up safe entities
        for safeId, safeData in pairs(placedSafes) do
            if DoesEntityExist(safeData.entity) then
                exports.ox_target:removeLocalEntity(safeData.entity)
                DeleteEntity(safeData.entity)
            end
        end
        
        -- Hide UI
        lib.hideTextUI()
        SetNuiFocus(false, false)
    end
end) 