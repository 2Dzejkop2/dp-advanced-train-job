MetroClient = MetroClient or {}

MetroClient.state = {
    uiOpen = false,
    hudVisible = true,
    hudLayout = nil,
    panelData = nil,
    startNpc = nil,
    startNpcs = {},
    startNpcBlips = {},
    spawnedStationPeds = {},
    activeRoute = nil,
    lastProfileType = nil
}

local openPanel
local normalizeNpcTypeToProfile
local getNpcSpawnPointForStation
local activePanelHeadshot = nil

local function avatarDebugEnabled()
    return tostring(Config.DebugLevel or 'off') == 'verbose'
end

local function avatarDebug(message)
    if avatarDebugEnabled() then
        print(('[godtrain][avatar-debug] %s'):format(tostring(message)))
    end
end

local function releasePanelHeadshot()
    if activePanelHeadshot and IsPedheadshotValid(activePanelHeadshot) then
        UnregisterPedheadshot(activePanelHeadshot)
    end
    activePanelHeadshot = nil
end

local function getPlayerMugshotUrl()
    releasePanelHeadshot()

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return nil
    end

    local mugshotHeading = GetEntityHeading(ped)
    local ok, mugHandle = pcall(RegisterPedheadshotTransparent, ped)
    if not ok or not mugHandle or mugHandle == -1 then
        avatarDebug('RegisterPedheadshotTransparent failed')
        SetEntityHeading(ped, mugshotHeading)
        return nil
    end

    avatarDebug(('RegisterPedheadshotTransparent handle=%s'):format(tostring(mugHandle)))

    local timeoutAt = GetGameTimer() + 2000
    while not IsPedheadshotReady(mugHandle) do
        Wait(0)
        if GetGameTimer() > timeoutAt then
            avatarDebug(('RegisterPedheadshotTransparent timeout handle=%s'):format(tostring(mugHandle)))
            if IsPedheadshotValid(mugHandle) then
                UnregisterPedheadshot(mugHandle)
            end
            SetEntityHeading(ped, mugshotHeading)
            return nil
        end
    end

    if IsPedheadshotValid(mugHandle) then
        local mugTxd = GetPedheadshotTxdString(mugHandle)
        avatarDebug(('RegisterPedheadshotTransparent txd=%s'):format(tostring(mugTxd)))
        if mugTxd and mugTxd ~= '' then
            activePanelHeadshot = mugHandle
            SetEntityHeading(ped, mugshotHeading)
            return mugTxd
        end

        UnregisterPedheadshot(mugHandle)
    end

    avatarDebug('transparent mugshot did not produce valid txd, using fallback avatar')
    SetEntityHeading(ped, mugshotHeading)
    return nil
end

local function decoratePanelDataForUi(panelData)
    if type(panelData) ~= 'table' then
        return panelData
    end

    panelData.ui = panelData.ui or {}
    local avatarImage = getPlayerMugshotUrl()
    avatarDebug(('decoratePanelDataForUi avatarImage=%s fallback=%s name=%s'):format(
        tostring(avatarImage),
        'assets/avatar.png',
        tostring(panelData.player and panelData.player.name or panelData.char_name or 'unknown')
    ))
    panelData.ui.avatarImage = avatarImage
    panelData.ui.avatarFallback = 'assets/avatar.png'
    panelData.ui.avatarNonce = GetGameTimer()
    return panelData
end

MetroClient.DecoratePanelDataForUi = decoratePanelDataForUi

local function menuOpenProvider()
    return string.lower(tostring(Config.MenuOpen or 'qb-target'))
end

local function isTargetMode(provider)
    return provider == 'qb-target' or provider == 'ox-target'
end

local function isTextUIMode(provider)
    return provider == 'qb-textui' or provider == 'ox-textui'
end

local function showMenuOpenPrompt(text)
    local provider = menuOpenProvider()
    if provider == 'qb-textui' then
        local pos = Config.QBTextPosition or 'left'
        exports['qb-core']:DrawText(text, pos)
        return
    end
    if provider == 'ox-textui' and lib and lib.showTextUI then
        lib.showTextUI(text)
        return
    end
    TrainUI.ShowTextUI(text)
end

local function hideMenuOpenPrompt()
    local provider = menuOpenProvider()
    if provider == 'qb-textui' then
        exports['qb-core']:HideText()
        return
    end
    if provider == 'ox-textui' and lib and lib.hideTextUI then
        lib.hideTextUI()
        return
    end
    TrainUI.HideTextUI()
end

local function registerStartNpcTarget(entity, npcType, interactionDistance)
    local provider = menuOpenProvider()
    if not isTargetMode(provider) then return end

    local label = tostring(_L('interact_open'))
    label = label:gsub("^%s*%[[^%]]+%]%s*", "")

    local onInteract = function()
        openPanel(normalizeNpcTypeToProfile(npcType))
    end

    if provider == 'qb-target' then
        pcall(function()
            exports['qb-target']:AddTargetEntity(entity, {
                options = {
                    {
                        icon = 'fas fa-train',
                        label = label,
                        action = function()
                            onInteract()
                        end
                    }
                },
                distance = interactionDistance or 2.0
            })
        end)
        return
    end

    if provider == 'ox-target' then
        local id = ('godtrain_npc_%s_%s'):format(tostring(entity), tostring(npcType or 'default'))
        pcall(function()
            exports.ox_target:addLocalEntity(entity, {
                {
                    name = id,
                    icon = 'fa-solid fa-train',
                    label = label,
                    distance = interactionDistance or 2.0,
                    onSelect = function()
                        onInteract()
                    end
                }
            })
        end)
    end
end

local function unregisterStartNpcTarget(entity)
    local provider = menuOpenProvider()
    if not isTargetMode(provider) then return end

    if provider == 'qb-target' then
        pcall(function()
            exports['qb-target']:RemoveTargetEntity(entity)
        end)
        return
    end

    if provider == 'ox-target' then
        pcall(function()
            exports.ox_target:removeLocalEntity(entity)
        end)
    end
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        Wait(50)
        if GetGameTimer() > timeout then return false end
    end
    return hash
end

local function createStartNpc()
    if not Config.StartNPC.enabled then return end

    MetroClient.state.startNpcs = {}

    local function spawnStartNpc(data, npcType)
        if not data or not data.model or not data.coords then return end

        local hash = loadModel(data.model)
        if not hash then return end

        local ped = CreatePed(4, hash, data.coords.x, data.coords.y, data.coords.z - 1.0, data.coords.w, false, true)
        SetEntityAsMissionEntity(ped, true, true)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)

        MetroClient.state.startNpcs[#MetroClient.state.startNpcs + 1] = {
            ped = ped,
            interactionDistance = data.interactionDistance,
            npcType = npcType,
            coords = vec3(data.coords.x, data.coords.y, data.coords.z)
        }
        registerStartNpcTarget(ped, npcType, data.interactionDistance or Config.StartNPC.interactionDistance or 2.0)

        local blipCfg = data.blip or Config.StartNPC.blip or {}
        if blipCfg.enabled ~= false then
            local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
            SetBlipSprite(blip, blipCfg.sprite or 280)
            SetBlipScale(blip, blipCfg.scale or 0.85)
            SetBlipColour(blip, blipCfg.color or 5)
            SetBlipAsShortRange(blip, blipCfg.shortRange ~= false)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(tostring(blipCfg.name or _L('blip_train_job')))
            EndTextCommandSetBlipName(blip)
            MetroClient.state.startNpcBlips[#MetroClient.state.startNpcBlips + 1] = blip
        end

        SetModelAsNoLongerNeeded(hash)
    end

    local types = Config.StartNPC.types
    if type(types) == 'table' then
        for npcType, npcCfg in pairs(types) do
            spawnStartNpc(npcCfg, npcType)
        end
    else
        spawnStartNpc(Config.StartNPC, 'default')
    end

    MetroClient.state.startNpc = (MetroClient.state.startNpcs[1] and MetroClient.state.startNpcs[1].ped) or nil
end

normalizeNpcTypeToProfile = function(npcType)
    local t = string.lower(tostring(npcType or 'train'))
    if t == 'metro' then
        return 'metro'
    end
    return 'train'
end

openPanel = function(preferredProfileType)
    local profileType = preferredProfileType
        or MetroClient.state.lastProfileType
        or (MetroClient.state.panelData and MetroClient.state.panelData.ui and MetroClient.state.panelData.ui.profileType)
        or 'train'

    MetroClient.state.lastProfileType = profileType
    SetNuiFocus(true, true)
    MetroClient.state.uiOpen = true

    if MetroClient.state.panelData and MetroClient.state.panelData.ui then
        MetroClient.DecoratePanelDataForUi(MetroClient.state.panelData)
        SendNUIMessage({
            action = 'openPanel',
            data = MetroClient.state.panelData
        })
    end

    CreateThread(function()
        local panelData = lib.callback.await('godtrain:server:getPanelData', false, profileType)
        if not MetroClient.state.uiOpen then return end
        MetroClient.DecoratePanelDataForUi(panelData)
        MetroClient.state.panelData = panelData
        MetroClient.state.lastProfileType = profileType
        SendNUIMessage({
            action = 'openPanel',
            data = panelData
        })
    end)
end

local function forceHideUi()
    MetroClient.state.uiOpen = false
    releasePanelHeadshot()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'forceHide' })
    SendNUIMessage({ action = 'setHudVisible', visible = false })
end

local function interactionThread()
    if not isTextUIMode(menuOpenProvider()) then
        return
    end

    while true do
        local waitTime = Config.Performance.idleWait

        local nearestDist = nil
        local inInteractRange = false
        local activeNpcType = nil

        local startNpcs = MetroClient.state.startNpcs or {}
        if #startNpcs > 0 then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)

            for _, npcData in ipairs(startNpcs) do
                local npcPed = npcData.ped
                if npcPed and DoesEntityExist(npcPed) then
                    local nCoords = npcData.coords or GetEntityCoords(npcPed)
                    local dist = #(pCoords - nCoords)

                    if not nearestDist or dist < nearestDist then
                        nearestDist = dist
                    end

                    local interactionDistance = npcData.interactionDistance or Config.StartNPC.interactionDistance or 2.0
                    if dist <= interactionDistance then
                        inInteractRange = true
                        activeNpcType = npcData.npcType or activeNpcType
                    end
                end
            end
        elseif MetroClient.state.startNpc and DoesEntityExist(MetroClient.state.startNpc) then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local nCoords = GetEntityCoords(MetroClient.state.startNpc)
            nearestDist = #(pCoords - nCoords)
            inInteractRange = nearestDist <= (Config.StartNPC.interactionDistance or 2.0)
        end

        if nearestDist and nearestDist <= 15.0 then
            waitTime = 0
        end

        if inInteractRange then
            waitTime = 0
            showMenuOpenPrompt(_L('interact_open'))
            if IsControlJustReleased(0, Config.Keys.Interact) then
                openPanel(normalizeNpcTypeToProfile(activeNpcType))
            end
        else
            hideMenuOpenPrompt()
        end

        Wait(waitTime)
    end
end

local function getBoxZoneCenter(station)
    local npc = station and station.npc or {}
    local spawnCoords = npc.spawnCoords
    local globalOffset = tonumber(((Config.NPC or {}).spawnZOffset)) or 0.0
    local stationOffset = tonumber(npc.spawnZOffset)
    local zOffset = stationOffset or globalOffset
    if spawnCoords then
        return vec3(spawnCoords.x, spawnCoords.y, spawnCoords.z + zOffset)
    end
    local base = station and station.coords or vec3(0.0, 0.0, 0.0)
    return vec3(base.x, base.y, base.z + zOffset)
end

local function getBoxZoneHeading(station)
    local npc = station and station.npc or {}
    local boxZone = npc.boxZone or {}
    if boxZone.heading ~= nil then
        return tonumber(boxZone.heading) or 0.0
    end
    local spawnCoords = npc.spawnCoords
    if spawnCoords and spawnCoords.w ~= nil then
        return tonumber(spawnCoords.w) or 0.0
    end
    return tonumber(station and station.heading) or 0.0
end

local function getBoxZoneSize(station)
    local npc = station and station.npc or {}
    local boxZone = npc.boxZone or {}
    return boxZone.size
end

local function isInsideBoxZone(center, heading, box, pos, fallbackRadius, toleranceZ)
    if box then
        local rad = math.rad(-heading)
        local cosH = math.cos(rad)
        local sinH = math.sin(rad)
        local dx = pos.x - center.x
        local dy = pos.y - center.y
        local dz = pos.z - center.z
        local localX = (dx * cosH) - (dy * sinH)
        local localY = (dx * sinH) + (dy * cosH)
        local halfX = (tonumber(box.x) or (fallbackRadius * 2.0)) * 0.5
        local halfY = (tonumber(box.y) or (fallbackRadius * 2.0)) * 0.5
        local halfZ = (tonumber(box.z) or 4.0) * 0.5
        local allowedZ = math.max(halfZ, tonumber(toleranceZ) or halfZ)
        return math.abs(localX) <= halfX and math.abs(localY) <= halfY and math.abs(dz) <= allowedZ
    end

    return #(pos - center) <= fallbackRadius
end

local function getRandomPointInBoxZone(center, heading, box, padding)
    local halfX = math.max(0.05, ((tonumber(box.x) or 1.0) * 0.5) - padding)
    local halfY = math.max(0.05, ((tonumber(box.y) or 1.0) * 0.5) - padding)
    local localX = (math.random() * 2.0 - 1.0) * halfX
    local localY = math.random() * halfY
    local rad = math.rad(heading)
    local cosH = math.cos(rad)
    local sinH = math.sin(rad)
    return vec3(
        center.x + (localX * cosH) - (localY * sinH),
        center.y + (localX * sinH) + (localY * cosH),
        center.z
    )
end

getNpcSpawnPointForStation = function(station)
    local npcCfg = Config.NPC or {}
    local npcStation = station and station.npc or {}
    local center = getBoxZoneCenter(station)
    local heading = getBoxZoneHeading(station)
    local box = getBoxZoneSize(station)
    local fallbackRadius = tonumber(station and station.stopRadius) or 12.0

    if box and npcStation.enabled ~= false then
        local attempts = math.max(1, tonumber(npcCfg.spawnAttempts) or 12)
        local padding = math.max(0.0, tonumber(npcCfg.boxPadding) or 0.0)
        local toleranceZ = tonumber(npcStation.toleranceZ)
            or tonumber((Config.MetroStopZone and Config.MetroStopZone.toleranceZ))
            or tonumber((Config.TrainStopZone and Config.TrainStopZone.toleranceZ))
            or 2.0

        for _ = 1, attempts do
            local point = getRandomPointInBoxZone(center, heading, box, padding)
            if isInsideBoxZone(center, heading, box, point, fallbackRadius, toleranceZ) then
                local pedHeading = npcCfg.randomHeading == true and (math.random() * 360.0) or heading
                return point, pedHeading
            end
        end
    end

    return center, heading
end

local function forEachNpcStation(cb)
    local npcCfg = Config.NPC or {}
    local onlyId = tonumber(npcCfg.onlyStationId)

    local metro = Config.StationsMetro or {}
    for id, station in pairs(metro) do
        if (not onlyId) or tonumber(id) == onlyId then
            cb(('metro:%s'):format(tostring(id)), station, id, 'metro')
        end
    end

    local train = Config.StationsTrain or {}
    for id, station in pairs(train) do
        if (not onlyId) or tonumber(id) == onlyId then
            cb(('train:%s'):format(tostring(id)), station, id, 'train')
        end
    end
end

local function spawnStationPeds(stationKey, station)
    if not Config.NPC.enabled then return end

    if not station then return end
    if station.npc and station.npc.enabled == false then return end

    MetroClient.state.spawnedStationPeds[stationKey] = MetroClient.state.spawnedStationPeds[stationKey] or {}
    local stationPeds = MetroClient.state.spawnedStationPeds[stationKey]

    local densityMode = Config.NPC.densityMode
    local metroDensity = Config.NPC.metroDensityByMode or Config.NPC.densityByMode
    local targetCount = metroDensity[densityMode] or 2
    if #stationPeds >= targetCount then return end

    for i = #stationPeds + 1, targetCount do
        local model = Config.NPC.models[math.random(1, #Config.NPC.models)]
        local hash = loadModel(model)
        if hash then
            local spawnPoint, spawnHeading = getNpcSpawnPointForStation(station)
            local p = CreatePed(4, hash, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnHeading, false, true)
            SetEntityAsMissionEntity(p, true, true)
            SetBlockingOfNonTemporaryEvents(p, true)
            if Config.NPC.behavior == 'wander' then
                TaskWanderStandard(p, 10.0, 10)
            else
                TaskStandStill(p, -1)
            end
            CreateThread(function()
                local center = getBoxZoneCenter(station)
                local heading = getBoxZoneHeading(station)
                local box = getBoxZoneSize(station)
                local fallbackRadius = tonumber(station and station.stopRadius) or 12.0
                local toleranceZ = tonumber((station.npc and station.npc.toleranceZ))
                    or tonumber((Config.MetroStopZone and Config.MetroStopZone.toleranceZ))
                    or tonumber((Config.TrainStopZone and Config.TrainStopZone.toleranceZ))
                    or 2.0
                while DoesEntityExist(p) do
                    Wait(2000)
                    local pos = GetEntityCoords(p)
                    if not isInsideBoxZone(center, heading, box, pos, fallbackRadius, toleranceZ) then
                        ClearPedTasksImmediately(p)
                        TaskStandStill(p, -1)
                    end
                end
            end)
            table.insert(stationPeds, p)
            SetModelAsNoLongerNeeded(hash)
        end
    end
end

local function cleanupAllPeds()
    local startNpcs = MetroClient.state.startNpcs or {}
    for _, npcData in ipairs(startNpcs) do
        local npcPed = npcData.ped
        if npcPed and DoesEntityExist(npcPed) then
            unregisterStartNpcTarget(npcPed)
            DeleteEntity(npcPed)
        end
    end
    if MetroClient.state.startNpcBlips then
        for _, blip in ipairs(MetroClient.state.startNpcBlips) do
            if blip and blip ~= 0 and DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end
    end

    if MetroClient.state.startNpc and DoesEntityExist(MetroClient.state.startNpc) then
        unregisterStartNpcTarget(MetroClient.state.startNpc)
        DeleteEntity(MetroClient.state.startNpc)
    end
    MetroClient.state.startNpc = nil
    MetroClient.state.startNpcs = {}
    MetroClient.state.startNpcBlips = {}

    for _, list in pairs(MetroClient.state.spawnedStationPeds) do
        for _, ped in ipairs(list) do
            if DoesEntityExist(ped) then
                DeleteEntity(ped)
            end
        end
    end
    MetroClient.state.spawnedStationPeds = {}
end

local function isInsideStationBox(station, pos, fallbackRadius)
    local box = station and station.stopBox
    if box then
        local heading = tonumber(station.heading) or 0.0
        local rad = math.rad(-heading)
        local cosH = math.cos(rad)
        local sinH = math.sin(rad)

        local dx = pos.x - station.coords.x
        local dy = pos.y - station.coords.y
        local dz = pos.z - station.coords.z

        local localX = (dx * cosH) - (dy * sinH)
        local localY = (dx * sinH) + (dy * cosH)

        local halfX = (tonumber(box.x) or (fallbackRadius * 2.0)) * 0.5
        local halfY = (tonumber(box.y) or (fallbackRadius * 2.0)) * 0.5
        local halfZ = (tonumber(box.z) or 4.0) * 0.5
        local zTolerance = tonumber(station.stopBoxToleranceZ)
            or tonumber((Config.MetroStopZone and Config.MetroStopZone.toleranceZ))
            or 2.0
        local allowedZ = math.max(halfZ, zTolerance)

        return math.abs(localX) <= halfX and math.abs(localY) <= halfY and math.abs(dz) <= allowedZ
    end

    local dist = #(pos - station.coords)
    return dist <= fallbackRadius
end

local function drawMetroStopDebugZones()
    local zoneCfg = Config.MetroStopZone or {}
    if zoneCfg.debugAlwaysVisible ~= true then
        return
    end
    local activeType = string.lower(tostring((MetroClient.state.activeRoute and MetroClient.state.activeRoute.trainType) or ''))
    if activeType == 'metro' then
        return
    end

    local stations = Config.StationsMetro or {}
    if next(stations) == nil then
        return
    end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local radiusMultiplier = (Config.Vehicle and tonumber(Config.Vehicle.stopRadiusMultiplier)) or 1.0

    for _, station in pairs(stations) do
        if station and station.coords then
            local effectiveStopRadius = (tonumber(station.stopRadius) or 12.0) * math.max(0.1, radiusMultiplier)
            local inside = isInsideStationBox(station, pCoords, effectiveStopRadius)

            local box = station.stopBox
            local markerType = tonumber(station.zoneMarkerType) or (box and 43 or 1)
            local markerSizeX, markerSizeY, markerSizeZ
            local markerPosZ = station.coords.z
            local markerRotZ = tonumber(station.heading) or 0.0
            local groundFound, groundZ = GetGroundZFor_3dCoord(station.coords.x, station.coords.y, station.coords.z + 3.0, false)
            local markerBaseZ = groundFound and (groundZ + 0.02) or station.coords.z

            if box then
                local halfX = (tonumber(box.x) or (effectiveStopRadius * 2.0)) * 0.5
                local halfY = (tonumber(box.y) or (effectiveStopRadius * 2.0)) * 0.5
                local halfZ = (tonumber(box.z) or 4.0) * 0.5
                markerSizeX = halfX * 2.0
                markerSizeY = halfY * 2.0
                markerSizeZ = halfZ * 2.0
                markerPosZ = markerBaseZ
            else
                local markerDiameter = math.max(5.0, effectiveStopRadius * 2.0)
                markerSizeX = markerDiameter
                markerSizeY = markerDiameter
                markerSizeZ = 1.5
                markerPosZ = markerBaseZ - 1.2
                markerRotZ = 0.0
            end

            local r = inside and 0 or 255
            local g = inside and 255 or 60
            local b = inside and 120 or 60

            DrawMarker(
                markerType,
                station.coords.x, station.coords.y, markerPosZ,
                0.0, 0.0, 0.0,
                0.0, 0.0, markerRotZ,
                markerSizeX, markerSizeY, markerSizeZ,
                r, g, b, 110,
                false, false, 2, false, nil, nil, false
            )
        end
    end
end

local function drawTrainStopDebugZones()
    local zoneCfg = Config.TrainStopZone or {}
    if zoneCfg.debugAlwaysVisible ~= true then
        return
    end
    local activeType = string.lower(tostring((MetroClient.state.activeRoute and MetroClient.state.activeRoute.trainType) or ''))
    if activeType == 'train' or activeType == 'freight' then
        return
    end

    local stations = Config.StationsTrain or {}
    if next(stations) == nil then
        return
    end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local radiusMultiplier = (Config.Vehicle and tonumber(Config.Vehicle.stopRadiusMultiplier)) or 1.0

    for _, station in pairs(stations) do
        if station and station.coords then
            local effectiveStopRadius = (tonumber(station.stopRadius) or 12.0) * math.max(0.1, radiusMultiplier)
            local inside = isInsideStationBox(station, pCoords, effectiveStopRadius)

            local box = station.stopBox
            local markerType = tonumber(station.zoneMarkerType) or (box and 43 or 1)
            local markerSizeX, markerSizeY, markerSizeZ
            local markerPosZ = station.coords.z
            local markerRotZ = tonumber(station.heading) or 0.0
            local groundFound, groundZ = GetGroundZFor_3dCoord(station.coords.x, station.coords.y, station.coords.z + 3.0, false)
            local markerBaseZ = groundFound and (groundZ + 0.02) or station.coords.z

            if box then
                local halfX = (tonumber(box.x) or (effectiveStopRadius * 2.0)) * 0.5
                local halfY = (tonumber(box.y) or (effectiveStopRadius * 2.0)) * 0.5
                local halfZ = (tonumber(box.z) or 4.0) * 0.5
                markerSizeX = halfX * 2.0
                markerSizeY = halfY * 2.0
                markerSizeZ = halfZ * 2.0
                markerPosZ = markerBaseZ
            else
                local markerDiameter = math.max(5.0, effectiveStopRadius * 2.0)
                markerSizeX = markerDiameter
                markerSizeY = markerDiameter
                markerSizeZ = 1.5
                markerPosZ = markerBaseZ - 1.2
                markerRotZ = 0.0
            end

            local r = inside and 0 or 255
            local g = inside and 255 or 60
            local b = inside and 120 or 60

            DrawMarker(
                markerType,
                station.coords.x, station.coords.y, markerPosZ,
                0.0, 0.0, 0.0,
                0.0, 0.0, markerRotZ,
                markerSizeX, markerSizeY, markerSizeZ,
                r, g, b, 110,
                false, false, 2, false, nil, nil, false
            )
        end
    end
end

local function hasAnyDebugZonesEnabled()
    return ((Config.MetroStopZone or {}).debugAlwaysVisible == true)
        or ((Config.TrainStopZone or {}).debugAlwaysVisible == true)
        or (((Config.NPC or {}).debug or {}).enabled == true)
end

local function isNearAnyDebugStation(maxDistance)
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local maxDist = tonumber(maxDistance) or 180.0
    local maxDistSq = maxDist * maxDist

    local metroStations = Config.StationsMetro or {}
    for _, station in pairs(metroStations) do
        if station and station.coords then
            local dx = pCoords.x - station.coords.x
            local dy = pCoords.y - station.coords.y
            local dz = pCoords.z - station.coords.z
            if (dx * dx + dy * dy + dz * dz) <= maxDistSq then
                return true
            end
        end
    end

    local trainStations = Config.StationsTrain or {}
    for _, station in pairs(trainStations) do
        if station and station.coords then
            local dx = pCoords.x - station.coords.x
            local dy = pCoords.y - station.coords.y
            local dz = pCoords.z - station.coords.z
            if (dx * dx + dy * dy + dz * dz) <= maxDistSq then
                return true
            end
        end
    end

    return false
end

local function drawNpcSpawnDebugZones()
    local debugCfg = (Config.NPC or {}).debug or {}
    if debugCfg.enabled ~= true then
        return
    end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local onlyClosest = debugCfg.onlyClosest == true
    local closestStationKey, closestDistSq

    if onlyClosest then
        forEachNpcStation(function(stationKey, station)
            local npcStation = station and station.npc or nil
            local box = npcStation and getBoxZoneSize(station) or nil
            if npcStation and npcStation.enabled ~= false and box then
                local center = getBoxZoneCenter(station)
                local dx = pCoords.x - center.x
                local dy = pCoords.y - center.y
                local dz = pCoords.z - center.z
                local distSq = (dx * dx) + (dy * dy) + (dz * dz)
                if (not closestDistSq) or distSq < closestDistSq then
                    closestDistSq = distSq
                    closestStationKey = stationKey
                end
            end
        end)
    end

    forEachNpcStation(function(stationKey, station)
        if onlyClosest and stationKey ~= closestStationKey then return end
        local npcStation = station and station.npc or nil
        local box = npcStation and getBoxZoneSize(station) or nil
        if npcStation and npcStation.enabled ~= false and box then
            local center = getBoxZoneCenter(station)
            local heading = getBoxZoneHeading(station)
            local toleranceZ = tonumber(npcStation.toleranceZ)
                or tonumber((Config.MetroStopZone and Config.MetroStopZone.toleranceZ))
                or tonumber((Config.TrainStopZone and Config.TrainStopZone.toleranceZ))
                or 2.0
            local inside = isInsideBoxZone(center, heading, box, pCoords, tonumber(station.stopRadius) or 12.0, toleranceZ)
            local nearColor = debugCfg.nearColor or {}
            local farColor = debugCfg.farColor or {}
            local color = inside and nearColor or farColor
            local markerSizeX = tonumber(box.x) or 2.0
            local markerSizeY = tonumber(box.y) or 2.0
            local markerSizeZ = tonumber(box.z) or 2.0

            DrawMarker(
                43,
                center.x, center.y, center.z,
                0.0, 0.0, 0.0,
                0.0, 0.0, heading,
                markerSizeX, markerSizeY, markerSizeZ,
                tonumber(color.r) or 255, tonumber(color.g) or 140, tonumber(color.b) or 60, tonumber(debugCfg.alpha) or 110,
                false, false, 2, false, nil, nil, false
            )

            if debugCfg.showCenter == true then
                DrawMarker(
                    1,
                    center.x, center.y, center.z,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    0.16, 0.16, 0.16,
                    0, 255, 80, 220,
                    false, false, 2, false, nil, nil, false
                )
            end
        end
    end)
end

RegisterNetEvent('godtrain:client:updatePanel', function(panelData)
    if MetroClient and MetroClient.DecoratePanelDataForUi then
        MetroClient.DecoratePanelDataForUi(panelData)
    end
    MetroClient.state.panelData = panelData
    SendNUIMessage({ action = 'updatePanel', data = panelData })
end)

RegisterNetEvent('godtrain:client:routeFinished', function(payload)
    if payload and payload.ok then
        MetroClient.state.activeRoute = nil
        SendNUIMessage({ action = 'setHudVisible', visible = false })
        local profileType = (MetroClient.state.panelData and MetroClient.state.panelData.ui and MetroClient.state.panelData.ui.profileType) or 'train'
        local panelData = lib.callback.await('godtrain:server:getPanelData', false, profileType)
        if MetroClient and MetroClient.DecoratePanelDataForUi then
            MetroClient.DecoratePanelDataForUi(panelData)
        end
        MetroClient.state.panelData = panelData
        SendNUIMessage({ action = 'updatePanel', data = panelData })
    else
        ClientBridge.Notify(payload and payload.message or _L('route_finish_failed'), 'error')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupAllPeds()
    forceHideUi()
end)

RegisterNetEvent('god:client:ui:notify', function(message, nType, length)
    SendNUIMessage({
        action = 'assistantNotify',
        message = tostring(message or ''),
        type = tostring(nType or 'inform'),
        duration = tonumber(length) or 5000
    })
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    forceHideUi()
end)

CreateThread(function()
    Framework.Detect()
    ClientBridge.Init()
    pcall(function()
        SetTrainsForceDoorsOpen(false)
    end)
    forceHideUi()
    Wait(500)
    forceHideUi()
    createStartNpc()
    CreateThread(function()
        while true do
            local waitMs = 1000
            if hasAnyDebugZonesEnabled() then
                if isNearAnyDebugStation(tonumber((((Config.NPC or {}).debug or {}).drawDistance)) or 220.0) then
                    waitMs = 0
                    drawMetroStopDebugZones()
                    drawTrainStopDebugZones()
                    drawNpcSpawnDebugZones()
                else
                    waitMs = 350
                end
            end
            Wait(waitMs)
        end
    end)
    interactionThread()
end)
