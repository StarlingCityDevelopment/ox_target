if not lib.checkDependency('ox_lib', '3.30.0', true) then return end

lib.locale()

local utils = require 'client.utils'
local state = require 'client.state'
local options = require 'client.api'.getTargetOptions()

require 'client.debug'
require 'client.defaults'
require 'client.compat.qtarget'

local SendNuiMessage = SendNuiMessage
local GetEntityCoords = GetEntityCoords
local HasEntityClearLosToEntity = HasEntityClearLosToEntity
local GetEntityBoneIndexByName = GetEntityBoneIndexByName
local GetEntityBonePosition_2 = GetEntityBonePosition_2
local GetEntityModel = GetEntityModel
local IsDisabledControlJustPressed = IsDisabledControlJustPressed
local DisableControlAction = DisableControlAction
local DisablePlayerFiring = DisablePlayerFiring
local GetModelDimensions = GetModelDimensions
local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords
local currentTarget = {}
local currentMenu
local menuChanged
local menuHistory = {}
local nearbyZones
local flag = 26

-- Toggle ox_target, instead of holding the hotkey
local toggleHotkey = GetConvarInt('ox_target:toggleHotkey', 0) == 1
local mouseButton = GetConvarInt('ox_target:leftClick', 1) == 1 and 24 or 25
local debug = GetConvarInt('ox_target:debug', 0) == 1
local vec0 = vec3(0, 0, 0)

---@param option OxTargetOption 
---@param distance number
---@param endCoords vector3
---@param entityHit? number
---@param entityType? number
---@param entityModel? number | false
local function shouldHide(option, distance, endCoords, entityHit, entityType, entityModel)
    if option.menuName ~= currentMenu then
        return true
    end

    if distance > (option.distance or 7) then
        return true
    end

    if option.groups and not utils.hasPlayerGotGroup(option.groups) then
        return true
    end

    if option.items and not utils.hasPlayerGotItems(option.items, option.anyItem) then
        return true
    end

    if not option.me and entityHit == cache.ped then
        return true
    end

    local bone = entityModel and option.bones or nil

    if bone then
        local _type = type(bone)

        if _type == 'string' then
            local boneId = GetEntityBoneIndexByName(entityHit, bone)

            if boneId == -1 or #(endCoords - GetEntityBonePosition_2(entityHit, boneId)) > 2 then
                return true
            end
        elseif _type == 'table' then
            local closestBone, boneDistance

            for j = 1, #bone do
                local boneId = GetEntityBoneIndexByName(entityHit, bone[j])

                if boneId ~= -1 then
                    local dist = #(endCoords - GetEntityBonePosition_2(entityHit, boneId))

                    if dist <= (boneDistance or 1) then
                        closestBone = boneId
                        boneDistance = dist
                    end
                end
            end

            if not closestBone then
                return true
            end
        end
    end

    local offset = entityModel and option.offset or nil

    if offset then
        if not option.absoluteOffset then
            local min, max = GetModelDimensions(entityModel)
            offset = (max - min) * offset + min
        end

        offset = GetOffsetFromEntityInWorldCoords(entityHit, offset.x, offset.y, offset.z)

        if #(endCoords - offset) > (option.offsetSize or 1) then
            return true
        end
    end

    if option.canInteract then
        local success, resp = pcall(option.canInteract, entityHit, distance, endCoords, option.name, bone)
        return not success or not resp
    end

    return false
end

local disablePunching = false

local function startTargeting()
    if state.isDisabled() or state.isActive() or IsNuiFocused() or IsPauseMenuActive() then return end
    state.setActive(true)

    local zones = {}
    local endCoords, hasTarget, entityHit, distance, entityType, lastEntity, entityModel, zonesChanged
    local dict, texture = utils.getTexture()
    local lastCoords

    CreateThread(function()
        while state.isActive() do
            lastCoords = endCoords == vec0 and lastCoords or endCoords or vec0

            if debug then
                DrawMarker(28, lastCoords.x, lastCoords.y, lastCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.2,
                    0.2,
                    ---@diagnostic disable-next-line: param-type-mismatch
                    255, 42, 24, 100, false, false, 0, true, false, false, false)
            end

            if hasTarget then
                local cursorX, cursorY = utils.getCursorScreenPosition()
                SetTextScale(0.35, 0.35)
                SetTextFont(4)
                SetTextProportional(1)
                SetTextColour(255, 255, 255, 215)
                SetTextEntry("STRING")
                SetTextCentre(true)
                AddTextComponentString("intéragir")
                EndTextCommandDisplayText(cursorX + 0.004, cursorY + 0.025)

                if options.size ~= 0 and entityType ~= 0 then
                    SetMouseCursorStyle(5)
                    SetEntityAlpha(entityHit, 150, false)
                end
            else
                SetMouseCursorStyle(1)
            end

            utils.drawZoneSprites(dict, texture)
            DisablePlayerFiring(cache.playerId, true)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            if state.isNuiFocused() then
                if not hasTarget or options and IsDisabledControlJustPressed(0, 25) then
                    Wait(1000)
                    state.setNuiFocus(false, false)
                end
            elseif hasTarget and IsDisabledControlJustPressed(0, mouseButton) then
                state.setNuiFocus(true, true)

                local cursorX, cursorY = utils.getCursorScreenPosition()
                SendNuiMessage(json.encode({
                    event = 'setTarget',
                    options = options,
                    zones = zones,
                    cursorX = cursorX,
                    cursorY = cursorY,
                }, { sort_keys = true }))

                disablePunching = true
                CreateThread(function()
                    while disablePunching do
                        DisablePlayerFiring(cache.playerId, true)
                        DisableControlAction(0, 1, true)
                        DisableControlAction(0, 2, true)
                        DisableControlAction(0, 24, true)
                        DisableControlAction(0, 25, true)
                        DisableControlAction(0, 140, true)
                        DisableControlAction(0, 141, true)
                        DisableControlAction(0, 142, true)
                        Wait(0)
                    end
                end)
                state.setActive(false)
            end

            Wait(0)
        end

        if lastEntity > 0 then
            ResetEntityAlpha(lastEntity)
        end

        SetStreamedTextureDictAsNoLongerNeeded(dict)
    end)

    while state.isActive() do
        if not state.isNuiFocused() and lib.progressActive() then
            state.setActive(false)
            break
        end

        SetMouseCursorThisFrame()

        local playerCoords = GetEntityCoords(cache.ped)
        local rayResult = utils.raycastFromMouse()

        entityHit = rayResult.hitEntity
        endCoords = rayResult.hitCoords
        entityType = rayResult.entityType
        distance = #(playerCoords - endCoords)
        nearbyZones, zonesChanged = utils.getNearbyZones(endCoords)

        local entityChanged = entityHit ~= lastEntity
        local newOptions = (zonesChanged or entityChanged or menuChanged)

        if entityHit > 0 and entityChanged then
            currentMenu = nil

            if flag ~= 511 then
                entityHit = HasEntityClearLosToEntity(entityHit, cache.ped, 7) and entityHit or 0
            end

            if entityHit > 0 then
                local success, result = pcall(GetEntityModel, entityHit)
                entityModel = success and result
            end
        end

        if hasTarget and (zonesChanged or (entityChanged and hasTarget > 1)) then
            if entityChanged then 
                options:wipe() 
            end
            if debug and lastEntity > 0 then 
                SetEntityDrawOutline(lastEntity, false) 
            end
            hasTarget = false
        end

        local shouldReloadOptions = newOptions and entityModel and entityHit > 0
        if shouldReloadOptions and (entityType ~= 1 or entityChanged) then
            options:set(entityHit, entityType, entityModel)
        end

        if lastEntity ~= entityHit then
            ResetEntityAlpha(lastEntity)
        end
        lastEntity = entityHit

        currentTarget.entity = entityHit
        currentTarget.coords = endCoords
        currentTarget.distance = distance

        local hidden = 0
        local totalOptions = 0

        for k, v in pairs(options) do
            local optionCount = #v
            local dist = k == '__global' and 0 or distance
            totalOptions = totalOptions + optionCount

            for i = 1, optionCount do
                local option = v[i]
                local hide = shouldHide(option, dist, endCoords, entityHit, entityType, entityModel)

                if option.hide ~= hide then
                    option.hide = hide
                    newOptions = true
                end

                if hide then 
                    hidden = hidden + 1 
                end
            end
        end

        if zonesChanged then 
            table.wipe(zones) 
        end

        for i = 1, #nearbyZones do
            local zoneOptions = nearbyZones[i].options
            local optionCount = #zoneOptions
            totalOptions = totalOptions + optionCount
            zones[i] = zoneOptions

            for j = 1, optionCount do
                local option = zoneOptions[j]
                local hide = shouldHide(option, distance, endCoords, entityHit)

                if option.hide ~= hide then
                    option.hide = hide
                    newOptions = true
                end

                if hide then 
                    hidden = hidden + 1 
                end
            end
        end

        if newOptions then
            if hasTarget == 1 and (totalOptions - hidden) > 1 then
                hasTarget = true
            end

            if hasTarget and hidden == totalOptions then
                if hasTarget and hasTarget ~= 1 then
                    hasTarget = false
                end
            elseif menuChanged or (hasTarget ~= 1 and hidden ~= totalOptions) then
                hasTarget = options.size
                if currentMenu and options.__global[1] and options.__global[1].name ~= 'builtin:goback' then
                    table.insert(options.__global, 1, {
                        icon = 'fa-solid fa-circle-chevron-left',
                        label = locale('go_back'),
                        name = 'builtin:goback',
                        menuName = currentMenu,
                        openMenu = 'home'
                    })
                end
            end

            menuChanged = false
        end

        if toggleHotkey and IsPauseMenuActive() then
            state.setActive(false)
        end

        if not hasTarget or hasTarget == 1 then
            flag = flag == 511 and 26 or 511
        end

        Wait(0)
    end

    collectgarbage()
end

do
    ---@type KeybindProps
    local keybind = {
        name = 'ox_target',
        defaultKey = GetConvar('ox_target:defaultHotkey', 'LMENU'),
        defaultMapper = 'keyboard',
        description = locale('toggle_targeting'),
    }

    if toggleHotkey then
        function keybind:onPressed()
            if state.isActive() then
                return state.setActive(false)
            end

            return startTargeting()
        end
    else
        keybind.onPressed = startTargeting

        function keybind:onReleased()
            state.setActive(false)
        end
    end

    lib.addKeybind(keybind)
end

---@generic T
---@param option T
---@param server? boolean
---@return T
local function getResponse(option, server)
    local response = table.clone(option)
    response.entity = currentTarget.entity
    response.zone = currentTarget.zone
    response.coords = currentTarget.coords
    response.distance = currentTarget.distance

    if server then
        response.entity = response.entity ~= 0 and NetworkGetEntityIsNetworked(response.entity) and
            NetworkGetNetworkIdFromEntity(response.entity) or 0
    end

    response.icon = nil
    response.groups = nil
    response.items = nil
    response.canInteract = nil
    response.onSelect = nil
    response.export = nil
    response.event = nil
    response.serverEvent = nil
    response.command = nil

    return response
end

local function cleanupTarget()
    disablePunching = false
    state.setNuiFocus(false, false)
    table.wipe(currentTarget)
    options:wipe()
    SendNuiMessage('{"event": "visible", "state": false}')
    if nearbyZones then 
        table.wipe(nearbyZones) 
    end
end

RegisterNUICallback('close', function(_, cb)
    cb(1)
    cleanupTarget()
end)

RegisterNUICallback('select', function(data, cb)
    cb(1)

    disablePunching = false

    if not data or #data < 2 or data[2] == 0 then
        cleanupTarget()
        return
    end

    local zone = data[3] and nearbyZones and nearbyZones[data[3]]
    local option = zone and zone.options[data[2]] or (data[1] and options[data[1]] and options[data[1]][data[2]])

    if not option then
        cleanupTarget()
        return
    end

    local shouldCleanup = true

    if option.openMenu then
        local menuDepth = #menuHistory

        if option.name == 'builtin:goback' then
            option.menuName = option.openMenu
            option.openMenu = menuHistory[menuDepth]

            if menuDepth > 0 then
                menuHistory[menuDepth] = nil
            end
        else
            menuHistory[menuDepth + 1] = currentMenu
        end

        menuChanged = true
        currentMenu = option.openMenu ~= 'home' and option.openMenu or nil
        options:wipe()
        shouldCleanup = false
    else
        state.setNuiFocus(false)
    end

    currentTarget.zone = zone and zone.id

    if option.onSelect then
        option.onSelect(option.qtarget and currentTarget.entity or getResponse(option))
    elseif option.export then
        exports[option.resource or zone.resource][option.export](nil, getResponse(option))
    elseif option.event then
        TriggerEvent(option.event, getResponse(option))
    elseif option.serverEvent then
        TriggerServerEvent(option.serverEvent, getResponse(option, true))
    elseif option.command then
        ExecuteCommand(option.command)
    end

    if option.menuName == 'home' then
        shouldCleanup = false
    end

    if not (option and option.openMenu) and IsNuiFocused() then
        state.setActive(false)
    end

    if shouldCleanup then
        cleanupTarget()
    else
        state.setNuiFocus(false, false)
        SendNuiMessage('{"event": "visible", "state": false}')
    end
end)
