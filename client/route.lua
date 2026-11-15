
local function getEntityRightVectorCompat(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return vec3(1.0, 0.0, 0.0)
    end

    local forward = GetEntityForwardVector(entity)
    local length = math.sqrt((forward.x * forward.x) + (forward.y * forward.y))
    if length <= 0.001 then
        local heading = math.rad(GetEntityHeading(entity) or 0.0)
        return vec3(math.cos(heading), math.sin(heading), 0.0)
    end

    return vec3(forward.y / length, (-forward.x) / length, 0.0)
end

function GetRightSidePosition(vehicle, distance)
    local coords = GetEntityCoords(vehicle)
    local rightVector = getEntityRightVectorCompat(vehicle)
    return vec3(
        coords.x + rightVector.x * distance,
        coords.y + rightVector.y * distance,
        coords.z
    )
end

local getMetroBoardingSideSign
local abortActiveRouteWithMode

local function getStationsByTrainType(trainType)
    local t = Utils.NormalizeRouteTypeKey(trainType)
    if t == 'freight' then
        return Config.StationsTrain or Config.Stations or {}
    end
    return Config.StationsMetro or Config.Stations or {}
end

local function getCurrentStation(routeState)
    local stationId = routeState.stationOrder[routeState.currentStationIdx]
    local stations = routeState.stations or getStationsByTrainType(routeState.trainType)
    return stationId, stations[stationId]
end

local function getStationStopCoords(station)
    local stopCoords = station and (station.stopCoords or station.snapCoords or station.coords)
    if not stopCoords then
        return vec3(0.0, 0.0, 0.0)
    end
    return vec3(stopCoords.x + 0.0, stopCoords.y + 0.0, stopCoords.z + 0.0)
end

local function getStationStopHeading(station)
    return tonumber(station and (station.stopHeading or station.snapHeading or station.heading)) or 0.0
end

local function applyRouteSpeedProfile(routeState, station)
    if not routeState then return end

    local newMaxSpeed = station and tonumber(station.newMaxSpeed) or nil
    if newMaxSpeed and newMaxSpeed > 0 then
        routeState.routeSpeedLimitKmh = newMaxSpeed
    else
        routeState.routeSpeedLimitKmh = nil
    end
end

local TRAINSPORTATION_MODEL_POOL = {
    'freight',
    'freightcar',
    'freightgrain',
    'freightcont1',
    'freightcont2',
    'freighttrailer',
    'tankercar',
    'metrotrain'
}

local trainModelsLoaded = false
local getMetroRuntimeConfig
local updateHud
local getRouteEconomy
local buildMetroBoardingPortals
local getPassengerBoardingConfig

local DEFAULT_PASSENGER_BOARDING = {
    enabled = true,
    simpleSeatBoarding = true,
    autoStartMetroBoarding = false,
    spawnNearMetro = true,
    lockTrainWhileBoarding = true,
    durationMs = 14500,
    durationPerPassengerMs = 720,
    maxDurationMs = 30000,
    cooldownMs = 1200,
    minPassengers = 4,
    maxPassengers = 12,
    seatedCapacityPerCarriage = 4,
    boardingSideSign = -1.0,
    allowCancel = false,
    approachSpeed = 1.05,
    queueSpacing = 0.9,
    queueDepth = 1.5,
    stagingDepth = 3.2,
    doorOffset = 1.45,
    laneOffsets = { -4.2, 4.2 },
    startDelayStepMs = 0,
    boardDistance = 1.2,
    boardFallbackEnterMs = 1700,
    repathIntervalMs = 450,
    maxQueuePerDoor = 4,
    exitDwellMs = 1000,
    doorSnapDistance = 1.2,
    doorSnapAfterMs = 500,
    doorPauseMs = 260,
    seatWarpDelayMinMs = 220,
    seatWarpDelayMaxMs = 650,
    targetOccupancyMin = 0.42,
    targetOccupancyMax = 0.78,
    minExitRatio = 0.06,
    maxExitRatio = 0.24,
    forceExitOccupancyThreshold = 0.82,
    exitWalkOutMs = 2400,
    exitDeleteDelayMs = 12000,
    stuckNpcCleanupEnabled = true,
    stuckNpcCleanupIntervalMs = 3500,
    stuckNpcCleanupDuringBoarding = false,
    stuckNpcCleanupRadius = 85.0,
    debug = {
        enabled = false,
        notify = false
    }
}

local function resolvePassengerBoardingConfig(source)
    local merged = {}
    for key, value in pairs(DEFAULT_PASSENGER_BOARDING) do
        if type(value) == 'table' then
            merged[key] = Utils.DeepCopy(value)
        else
            merged[key] = value
        end
    end

    for key, value in pairs(source or {}) do
        if type(value) == 'table' then
            merged[key] = Utils.DeepCopy(value)
        else
            merged[key] = value
        end
    end

    return merged
end

local function getRouteTransportConfigKey(routeState)
    local trainType = string.lower(tostring((routeState and routeState.trainType) or 'metro'))
    return (trainType == 'metro') and 'metro' or 'train'
end

local function isPassengerBoardingDebugEnabled(routeState)
    local cfg = getPassengerBoardingConfig and getPassengerBoardingConfig(routeState) or nil
    local debugCfg = cfg and cfg.debug or nil
    return type(debugCfg) == 'table' and debugCfg.enabled == true
end

local function passengerBoardingDebug(routeState, code, message, ped)
    if not isPassengerBoardingDebugEnabled(routeState) then
        return
    end

    local pedTag = ''
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        local pedId = tostring(ped)
        if NetworkGetEntityIsNetworked(ped) then
            pedId = ('net:%s'):format(tostring(NetworkGetNetworkIdFromEntity(ped)))
        end
        pedTag = (' ped=%s'):format(pedId)
    end

    Utils.DebugVerbose('passenger_boarding', ('%s%s %s'):format(tostring(code or 'log'), pedTag, tostring(message or '')))

    local debugCfg = getPassengerBoardingConfig(routeState).debug or {}
    if debugCfg.notify == true then
        local nowTick = GetGameTimer()
        if nowTick >= tonumber(routeState.boardingDebugNotifyAt or 0) then
            routeState.boardingDebugNotifyAt = nowTick + 800
            ClientBridge.Notify(('[BOARDING] %s'):format(tostring(message or code or 'log')), 'inform')
        end
    end
end

local function getTeleportTargetCoords(configKey, teleportCfg)
    local mode = string.lower(tostring((teleportCfg and teleportCfg.mode) or 'coords'))
    if mode == 'current' then
        return nil
    end

    if mode == 'npc' then
        local startNpcCfg = Config.StartNPC or {}
        local npcTypes = startNpcCfg.types or {}
        local npcCfg = npcTypes[configKey] or npcTypes.default or startNpcCfg
        if npcCfg and npcCfg.coords then
            return npcCfg.coords
        end
        return nil
    end

    return teleportCfg and teleportCfg.coords or nil
end

local function getEarlyExitTeleportConfig(routeState)
    local configKey = getRouteTransportConfigKey(routeState)
    local cfg = (Config.EarlyExitTeleport or {})[configKey]
    if type(cfg) ~= 'table' then
        return nil, cfg, configKey
    end
    return getTeleportTargetCoords(configKey, cfg), cfg, configKey
end

local function shouldTeleportPlayerToRouteStart(route)
    local configKey = getRouteTransportConfigKey(route)
    local cfg = (Config.StartRouteTeleport or {})[configKey]
    return type(cfg) == 'table' and cfg.enabled == true
end

local function teleportPedToEntitySafe(ped, entity)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return
    end
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return
    end

    local coords = GetEntityCoords(entity)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z + 1.0, false, false, false)
    SetEntityHeading(ped, GetEntityHeading(entity) + 0.0)
end

local function trainEntityMatchesModel(train, modelName)
    if not modelName or modelName == '' then return true end
    if not train or train == 0 or not DoesEntityExist(train) then return false end
    return GetEntityModel(train) == joaat(modelName)
end

local function vehicleIsTrainEntity(vehicle)
    return vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle) and IsThisModelATrain(GetEntityModel(vehicle))
end

local function isVehiclePartOfAssignedTrain(routeState, vehicle)
    if not routeState or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end
    if routeState.vehicle == vehicle then
        return true
    end
    if routeState.vehicle and routeState.vehicle ~= 0 and DoesEntityExist(routeState.vehicle) then
        for i = 1, 12 do
            local carriage = GetTrainCarriage(routeState.vehicle, i)
            if carriage and carriage ~= 0 and carriage == vehicle then
                return true
            end
        end
    end
    if type(routeState.attachedVehicles) == 'table' then
        for _, attached in ipairs(routeState.attachedVehicles) do
            if attached and attached ~= 0 and attached == vehicle then
                return true
            end
        end
    end
    return false
end

local function setVehicleFuelSafe(vehicle, fuelLevel)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then
        return
    end

    local level = tonumber(fuelLevel) or 100.0

    pcall(function()
        SetVehicleFuelLevel(vehicle, level + 0.0)
    end)

    if DecorIsRegisteredAsType('fuelLevel', 1) then
        pcall(function()
            DecorSetFloat(vehicle, 'fuelLevel', level + 0.0)
        end)
    end

    if DecorIsRegisteredAsType('_FUEL_LEVEL', 1) then
        pcall(function()
            DecorSetFloat(vehicle, '_FUEL_LEVEL', level + 0.0)
        end)
    end

    if GetResourceState('LegacyFuel') == 'started' then
        pcall(function()
            exports['LegacyFuel']:SetFuel(vehicle, level)
        end)
    end

    if GetResourceState('cdn-fuel') == 'started' then
        pcall(function()
            exports['cdn-fuel']:SetFuel(vehicle, level)
        end)
    end

    if GetResourceState('ps-fuel') == 'started' then
        pcall(function()
            exports['ps-fuel']:SetFuel(vehicle, level)
        end)
    end

    if GetResourceState('ox_fuel') == 'started' then
        pcall(function()
            exports['ox_fuel']:setFuel(vehicle, level)
        end)
    end
end

local function keepVehicleFuelFull(routeState)
    if not Config.Vehicle.keepFuelFull then return end

    local now = GetGameTimer()
    local tickMs = Config.Performance.fuelTickMs or 1500
    if routeState.lastFuelTick and (now - routeState.lastFuelTick) < tickMs then
        return
    end

    routeState.lastFuelTick = now
    setVehicleFuelSafe(routeState.vehicle, Config.Vehicle.fuelLevel or 100.0)
end

local function getTrainControlProfile(routeState, vehicle)
    local controlCfg = Config.TrainControl
    if not controlCfg or not controlCfg.enabled then
        return nil
    end

    local profiles = controlCfg.profiles or {}
    local routeType = string.lower(tostring(routeState and routeState.trainType or ''))
    if routeType ~= '' then
        if routeType == 'train' and profiles.freight then
            return profiles.freight
        end
        if profiles[routeType] then
            return profiles[routeType]
        end
    end

    local modelHash = GetEntityModel(vehicle)
    local profile = profiles[modelHash]

    if not profile then
        local modelName = GetDisplayNameFromVehicleModel(modelHash)
        if modelName and modelName ~= '' then
            profile = profiles[string.lower(modelName)]
        end
    end

    return profile or profiles.default
end

local function getActiveSpeedLimitKmh(routeState, vehicle)
    local limitKmh = nil

    local function applyLimit(candidate)
        candidate = tonumber(candidate)
        if not candidate or candidate <= 0 then
            return
        end
        limitKmh = limitKmh and math.min(limitKmh, candidate) or candidate
    end

    applyLimit(routeState and routeState.routeSpeedLimitKmh)
    applyLimit(routeState and routeState.dynamicSpeedLimitKmh)
    applyLimit(routeState and routeState.stationApproachLimitKmh)

    local routeRules = Config.RouteRules or {}
    local routeTypeKey = string.lower(tostring(routeState and routeState.trainType or 'metro'))
    local routeRuleCfg = routeRules[routeTypeKey] or routeRules[(routeTypeKey == 'train') and 'freight' or routeTypeKey] or {}
    applyLimit(routeRuleCfg.cityMaxSpeedKmh)

    return limitKmh
end

local function getSpeedDisplayConfig(routeState)
    local routeRules = Config.RouteRules or {}
    local routeTypeKey = string.lower(tostring(routeState and routeState.trainType or 'metro'))
    local routeRuleCfg = routeRules[routeTypeKey] or routeRules[(routeTypeKey == 'train') and 'freight' or routeTypeKey] or {}
    local displayCfg = Config.SpeedDisplay or {}
    local unit = string.lower(tostring(routeRuleCfg.speedUnit or displayCfg.unit or 'kmh'))
    if unit ~= 'mph' then
        unit = 'kmh'
    end

    local multiplier = (unit == 'mph') and 0.621371 or 1.0
    local unitLabel = (unit == 'mph') and 'MPH' or 'KM.'
    local notifyLabel = (unit == 'mph') and 'mph' or 'km/h'
    return unit, multiplier, unitLabel, routeRuleCfg, notifyLabel
end

local function convertKmhToConfiguredUnit(routeState, speedKmh)
    local _, multiplier = getSpeedDisplayConfig(routeState)
    return (tonumber(speedKmh) or 0.0) * multiplier
end

local function getArrivalSpeedLimitKmh(routeState, penaltyCfg)
    local limitValue = tonumber(penaltyCfg and penaltyCfg.stationArrivalSpeedLimit) or 60.0
    local limitUnit = string.lower(tostring(penaltyCfg and penaltyCfg.stationArrivalSpeedUnit or 'kmh'))
    if limitUnit == 'mph' then
        return limitValue * 1.60934
    end
    return limitValue
end

local function getSpeedingToleranceKmh(routeState, penaltyCfg)
    local _, displayMultiplier, _, routeRuleCfg = getSpeedDisplayConfig(routeState)
    local toleranceDisplay = tonumber(routeRuleCfg and routeRuleCfg.speedingTolerance)
    local toleranceUnit = string.lower(tostring(routeRuleCfg and routeRuleCfg.speedingToleranceUnit or 'display'))
    if toleranceDisplay and toleranceDisplay > 0 then
        if toleranceUnit == 'kmh' then
            return toleranceDisplay
        end
        if toleranceUnit == 'mph' then
            return toleranceDisplay * 1.60934
        end
        local multiplier = tonumber(displayMultiplier) or 1.0
        if multiplier > 0.0 then
            return toleranceDisplay / multiplier
        end
    end
    return tonumber(penaltyCfg and penaltyCfg.speedingToleranceKmh) or 0.0
end

local function isMetroAutoBoardEnabled(routeState)
    local cfg = getPassengerBoardingConfig and getPassengerBoardingConfig(routeState) or resolvePassengerBoardingConfig(Config.PassengerBoarding or {})
    return string.lower(tostring(routeState and routeState.trainType or 'metro')) == 'metro'
        and cfg.enabled ~= false
        and cfg.autoStartMetroBoarding ~= false
end

local function isTrainServiceLocked(routeState)
    if not routeState then return false end
    if routeState.isBoarding then
        return true
    end

    local currentStage = string.lower(tostring(routeState.currentStage or ''))
    if currentStage == 'boarding' or currentStage == 'loading' then
        return true
    end

    return tonumber(routeState.serviceLockUntilMs or 0) > GetGameTimer()
end

local function playBrakeSqueal(routeState, vehicle)
    local controlCfg = Config.TrainControl or {}
    local squealCfg = controlCfg.brakeSqueal or {}
    if squealCfg.enabled == false then return end

    local now = GetGameTimer()
    local holdMs = tonumber(squealCfg.holdMs) or 1800
    local intervalMs = tonumber(squealCfg.intervalMs) or 1200
    local holdStartedAt = routeState.brakeHoldStartedAt or now

    if (now - holdStartedAt) < holdMs then
        return
    end

    if routeState.lastBrakeSquealAt and (now - routeState.lastBrakeSquealAt) < intervalMs then
        return
    end

    routeState.lastBrakeSquealAt = now

    local useTrainHorn = squealCfg.useTrainHorn ~= false
    if useTrainHorn then
        local hornDurationMs = tonumber(squealCfg.hornDurationMs) or 280
        local hornMode = tostring(squealCfg.hornMode or 'NORMAL')
        local hornLoud = squealCfg.hornLoud == true

        local ok = pcall(function()
            StartVehicleHorn(vehicle, hornDurationMs, GetHashKey(hornMode), hornLoud)
        end)
        if ok then
            return
        end
    end

    local soundName = squealCfg.soundName or 'Train_Horn'
    local soundSet = squealCfg.soundSet or 'DLC_HEIST_HACKING_SNAKE_SOUNDS'

    pcall(function()
        PlaySoundFromEntity(-1, soundName, vehicle, soundSet, false, 0)
    end)
end

local function updateTrainControls(routeState)
    local vehicle = routeState.vehicle
    if not vehicleIsTrainEntity(vehicle) then return end

    local runtimeCfg = routeState.runtimeCfg or {}
    local controlCfg = runtimeCfg.trainControl or Config.TrainControl or {}
    local boardingCfg = runtimeCfg.passengerBoarding or Config.PassengerBoarding or {}
    if isTrainServiceLocked(routeState) and boardingCfg.lockTrainWhileBoarding ~= false then
        routeState.manualTrainSpeed = 0.0
        SetTrainSpeed(vehicle, 0.0)
        SetTrainCruiseSpeed(vehicle, 0.0)
        return
    end

    local profile = getTrainControlProfile(routeState, vehicle)
    if not profile then return end

    local ped = PlayerPedId()
    local pedVehicle = GetVehiclePedIsIn(ped, false)
    if not isVehiclePartOfAssignedTrain(routeState, pedVehicle) or GetPedInVehicleSeat(pedVehicle, -1) ~= ped then
        return
    end

    local speed = routeState.manualTrainSpeed
    if speed == nil then
        speed = GetEntitySpeed(vehicle)
    end

    local isMetro = string.lower(tostring(routeState.trainType or '')) == 'metro'
    local maxSpeed = profile.maxSpeed or 40.0
    if profile.maxSpeedKmh then
        maxSpeed = (tonumber(profile.maxSpeedKmh) or 0) / 3.6
    end
    local accel = profile.accel or 0.05
    local decel = profile.decel or accel
    local brakeDecel = profile.brakeDecel or (decel * 2.0)
    local trainApproachCfg = controlCfg.trainApproach or {}
    local approachCfg = isMetro and (trainApproachCfg.metro or {}) or (trainApproachCfg.freight or {})
    local approachEnabled = approachCfg.enabled == true
    local approachAllowThrottleOverride = approachCfg.allowThrottleOverride ~= false
    local approachThrottleBrakeMultiplier = tonumber(approachCfg.throttleBrakeMultiplier) or 0.45
    local approachFar = tonumber(approachCfg.approachDistFar) or 140.0
    local approachNear = tonumber(approachCfg.approachDistNear) or 60.0
    local approachMaxFar = tonumber(approachCfg.maxSpeedFar) or 20.0
    local approachMaxNear = tonumber(approachCfg.maxSpeedNear) or 12.0
    if approachCfg.maxSpeedFarKmh then
        approachMaxFar = (tonumber(approachCfg.maxSpeedFarKmh) or 0) / 3.6
    end
    if approachCfg.maxSpeedNearKmh then
        approachMaxNear = (tonumber(approachCfg.maxSpeedNearKmh) or 0) / 3.6
    end
    local distToStop = nil
    local routeSpeedLimitKmh = tonumber(routeState.routeSpeedLimitKmh)

    local approachRecommendedSpeed = nil
    if approachEnabled then
        local _, station = getCurrentStation(routeState)
        if station then
            distToStop = #(GetEntityCoords(vehicle) - getStationStopCoords(station))
        else
            distToStop = 9999.0
        end

        if distToStop < approachNear then
            approachRecommendedSpeed = approachMaxNear
        elseif distToStop < approachFar then
            local span = math.max(0.001, approachFar - approachNear)
            local t = Utils.Clamp((distToStop - approachNear) / span, 0.0, 1.0)
            approachRecommendedSpeed = approachMaxNear + ((approachMaxFar - approachMaxNear) * t)
        end
    end
    local maxReverseSpeed = isMetro and math.min(maxSpeed * 0.9, 30.0) or maxSpeed
    local coastDecel = 0.0
    if controlCfg.coastToStop == true then
        coastDecel = isMetro and (decel * 0.55) or (decel * 0.35)
    end
    local smoothing = 1.0
    local nowTick = GetGameTimer()
    local lastTick = routeState.controlLastTickAt or (nowTick - (runtimeCfg.activeWait or Config.Performance.activeWait or 100))
    local deltaMs = Utils.Clamp(nowTick - lastTick, 5, 200)
    routeState.controlLastTickAt = nowTick
    local tickScale = deltaMs / 16.666
    local deltaSec = deltaMs / 1000.0
    local accelStep = accel * deltaSec
    local decelStep = decel * deltaSec
    local brakeDecelStep = brakeDecel * deltaSec
    local reverseAccelStep = isMetro and math.max(accelStep * 2.0, decelStep * 1.6) or math.max(accelStep * 1.5, decelStep * 1.2)

    local emergencyPressed = IsControlPressed(0, Config.Keys.TrainEmergencyBrake or 73)
    local rawSpeedUpPressed = IsControlPressed(0, Config.Keys.TrainSpeedUp or 71)
    local speedUpPressed = rawSpeedUpPressed
    local speedDownPressed = IsControlPressed(0, Config.Keys.TrainSpeedDown or 72)
    local brakePressed = IsControlPressed(0, Config.Keys.TrainBrake or 22)
    local serviceBrakePressed = brakePressed

    local isBraking = emergencyPressed or serviceBrakePressed
    if isBraking then
        routeState.brakeHoldStartedAt = routeState.brakeHoldStartedAt or GetGameTimer()
    else
        routeState.brakeHoldStartedAt = nil
        routeState.lastBrakeSquealAt = nil
    end

    local targetSpeed = speed
    if emergencyPressed then
        targetSpeed = 0.0
    elseif serviceBrakePressed then
        if speed > 0.0 then
            targetSpeed = math.max(0.0, speed - brakeDecelStep)
        elseif speed < 0.0 then
            targetSpeed = math.min(0.0, speed + brakeDecelStep)
        end
        playBrakeSqueal(routeState, vehicle)
    elseif speedDownPressed then
        if speed > 0.2 then
            targetSpeed = math.max(0.0, speed - brakeDecelStep)
        else
            targetSpeed = math.max(-maxReverseSpeed, speed - reverseAccelStep)
        end
    elseif speedUpPressed and speed < maxSpeed then
        if isMetro then
            if speed < 0.0 then
                targetSpeed = math.min(0.0, speed + brakeDecelStep)
            else
                local speedRatio = Utils.Clamp(speed / math.max(maxSpeed, 0.001), 0.0, 1.0)
                local metroAccelStep = ((2.55 * (1.0 - speedRatio)) + 0.28) * deltaSec
                targetSpeed = math.min(maxSpeed, speed + metroAccelStep)
            end
        else
            local safeMaxSpeed = math.max(maxSpeed, 0.001)
            local speedRatio = Utils.Clamp(math.max(speed, 0.0) / safeMaxSpeed, 0.0, 1.0)
            local saltyAccel = (tonumber(profile.accelBase) or accel or 0.2) * (1.0 - speedRatio)
            targetSpeed = math.min(maxSpeed, speed + saltyAccel)
        end
    elseif coastDecel > 0.0 then
        local coastStep = coastDecel * deltaSec
        if speed > 0.0 then
            targetSpeed = math.max(0.0, speed - coastStep)
        elseif speed < 0.0 then
            targetSpeed = math.min(0.0, speed + coastStep)
        end
    end
    if approachRecommendedSpeed and speed > approachRecommendedSpeed then
        local throttleOverrideActive = approachAllowThrottleOverride and rawSpeedUpPressed
        if not throttleOverrideActive then
            local approachBrakeStep = math.max(decelStep * 4.5, brakeDecelStep * 1.35)
            targetSpeed = math.max(approachRecommendedSpeed, math.min(targetSpeed, speed - approachBrakeStep))
        end
    end

    if speed > maxSpeed then
        local overspeed = speed - maxSpeed
        local overspeedRatio = Utils.Clamp(overspeed / math.max(maxSpeed, 0.001), 0.0, 1.0)
        local enforcedDecel = decelStep + ((brakeDecelStep - decelStep) * (0.2 + (overspeedRatio * 0.8)))
        if routeState.stationApproachLimitActive == true then
            enforcedDecel = enforcedDecel * 1.85
        end
        targetSpeed = math.max(maxSpeed, math.min(targetSpeed, speed - enforcedDecel))
    elseif speed < -maxReverseSpeed then
        local overspeed = math.abs(speed) - maxReverseSpeed
        local overspeedRatio = Utils.Clamp(overspeed / math.max(maxReverseSpeed, 0.001), 0.0, 1.0)
        local enforcedDecel = decelStep + ((brakeDecelStep - decelStep) * (0.2 + (overspeedRatio * 0.8)))
        if routeState.stationApproachLimitActive == true then
            enforcedDecel = enforcedDecel * 1.85
        end
        targetSpeed = math.min(-maxReverseSpeed, math.max(targetSpeed, speed + enforcedDecel))
    end

    if smoothing < 1.0 then
        speed = speed + ((targetSpeed - speed) * smoothing)
    else
        speed = targetSpeed
    end
    speed = Utils.Clamp(speed, -maxReverseSpeed, maxSpeed)

    routeState.manualTrainSpeed = speed
    SetTrainSpeed(vehicle, speed)
    SetTrainCruiseSpeed(vehicle, speed)
end

local function updateMetroDriveContext(routeState)
    if not routeState or string.lower(tostring(routeState.trainType or '')) ~= 'metro' then
        return
    end

    local veh = routeState.vehicle
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return
    end

    local _, station = getCurrentStation(routeState)
    if not station then
        routeState.metroCtxDistToStation = nil
        routeState.metroCtxAlignment = nil
        return
    end

    local vehPos = GetEntityCoords(veh)
    local toStop = getStationStopCoords(station) - vehPos
    local dist = #(toStop)
    routeState.metroCtxDistToStation = dist

    if dist < 0.001 then
        routeState.metroCtxAlignment = 1.0
        return
    end

    local fwd = GetEntityForwardVector(veh)
    local nx, ny = toStop.x / dist, toStop.y / dist
    local dot = (fwd.x * nx) + (fwd.y * ny)
    routeState.metroCtxAlignment = Utils.Clamp(dot, -1.0, 1.0)
end

local function applyMetroDerailGuard(routeState)
    if not routeState or string.lower(tostring(routeState.trainType or '')) ~= 'metro' then
        return
    end

    local veh = routeState.vehicle
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return
    end

    local inWater = IsEntityInWater(veh)
    local inAir = IsEntityInAir(veh)
    local speed = GetEntitySpeed(veh)
    local unstable = inWater or (inAir and speed > 1.0)
    local now = GetGameTimer()
    local metroRuntimeCfg = getMetroRuntimeConfig()

        if unstable then
            routeState.metroUnstableSince = routeState.metroUnstableSince or now
        if (now - routeState.metroUnstableSince) > metroRuntimeCfg.unstableForMs then
            SetTrainSpeed(veh, 0.0)
            SetTrainCruiseSpeed(veh, 0.0)
            routeState.manualTrainSpeed = 0.0
            routeState.derailRiskEvents = (routeState.derailRiskEvents or 0) + 1
            if not routeState.metroGuardNotifiedAt or (now - routeState.metroGuardNotifiedAt) > metroRuntimeCfg.notifyCooldownMs then
                routeState.metroGuardNotifiedAt = now
                ClientBridge.Notify(_L('metro_stability_guard_stopped'), 'error')
            end
        end
    else
        routeState.metroUnstableSince = nil
    end
end

local function clearRouteGuidance(routeState)
    if not routeState then return end

    if routeState.stationBlips then
        for _, blip in ipairs(routeState.stationBlips) do
            if blip and blip ~= 0 and DoesBlipExist(blip) then
                SetBlipRoute(blip, false)
                RemoveBlip(blip)
            end
        end
    end

    routeState.stationBlips = nil
    routeState.lastGuidedStationId = nil

    pcall(function()
        ClearGpsCustomRoute()
        SetGpsCustomRouteRender(false, 0, 0)
    end)
end

local function createRouteGuidance(routeState)
    local guidance = Config.RouteGuidance
    if not guidance or guidance.enabled == false then return end

    routeState.stationBlips = {}

    for idx, stationId in ipairs(routeState.stationOrder) do
        local stations = getStationsByTrainType(routeState.trainType)
        local station = stations[stationId]
        if station then
            local stopCoords = getStationStopCoords(station)
            local blip = AddBlipForCoord(stopCoords.x, stopCoords.y, stopCoords.z)
            SetBlipSprite(blip, guidance.blipSprite or 280)
            SetBlipScale(blip, guidance.blipScale or 0.85)
            SetBlipAsShortRange(blip, guidance.blipShortRange == true)
            SetBlipDisplay(blip, 4)

            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(('[%d/%d] %s'):format(idx, #routeState.stationOrder, station.label))
            EndTextCommandSetBlipName(blip)

            routeState.stationBlips[idx] = blip
        end
    end
end

local function refreshRouteGuidance(routeState)
    local guidance = Config.RouteGuidance
    if not guidance or guidance.enabled == false or not routeState.stationBlips then return end

    local currentIdx = routeState.currentStationIdx
    local colors = guidance.colors or {}

    for idx, blip in ipairs(routeState.stationBlips) do
        if blip and blip ~= 0 and DoesBlipExist(blip) then
            local stationId = routeState.stationOrder[idx]
            local isCurrent = idx == currentIdx
            local isPast = idx < currentIdx
            local isMissed = stationId and routeState.stationMissed[stationId] == true

            local color = colors.upcoming or 3
            local alpha = guidance.blipAlphaUpcoming or 170

            if isCurrent then
                color = colors.current or 5
                alpha = 255
            elseif isPast then
                color = isMissed and (colors.missed or 1) or (colors.done or 2)
                alpha = guidance.blipAlphaDone or 120
            end

            SetBlipColour(blip, color)
            SetBlipAlpha(blip, alpha)
            SetBlipRoute(blip, false)
            SetBlipDisplay(blip, isCurrent and 4 or 0)
        end
    end

    pcall(function()
        ClearGpsCustomRoute()
        local color = tonumber(((guidance.colors or {}).current)) or 5
        StartGpsCustomRoute(color, true, true)
        local stationId = routeState.stationOrder[currentIdx]
        local station = stationId and (routeState.stations or getStationsByTrainType(routeState.trainType))[stationId]
        if station then
            local stopCoords = getStationStopCoords(station)
            AddPointToGpsCustomRoute(stopCoords.x, stopCoords.y, stopCoords.z)
        end
        SetGpsCustomRouteRender(true, 16, 16)
    end)
end

local function requestModelSync(modelName, timeoutMs)
    local hash = type(modelName) == 'number' and modelName or joaat(modelName)
    if not IsModelInCdimage(hash) then
        return false
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + (timeoutMs or 7000)
    while not HasModelLoaded(hash) do
        Wait(0)
        RequestModel(hash)
        if GetGameTimer() > timeout then
            return false
        end
    end

    return true
end

local function ensureTrainModelsLoaded(trainCfg)
    if not trainModelsLoaded then
        for _, model in ipairs(TRAINSPORTATION_MODEL_POOL) do
            requestModelSync(model, 7000)
        end
        trainModelsLoaded = true
    end

    if trainCfg and trainCfg.model then
        requestModelSync(trainCfg.model, 7000)
    end

    if trainCfg and trainCfg.requiredCarriageModel then
        requestModelSync(trainCfg.requiredCarriageModel, 7000)
    end
end

local function getRouteTrainConfig(route)
    local trainType = (route and route.trainType) or 'metro'
    local trainCfg = (Config.Vehicle.types and Config.Vehicle.types[trainType]) or Config.Vehicle
    return trainCfg, trainType
end

local function trainHasCarriageModel(train, modelName)
    if not modelName or modelName == '' then return true end
    local hash = joaat(modelName)
    for i = 1, 12 do
        local carriage = GetTrainCarriage(train, i)
        if carriage and carriage ~= 0 and DoesEntityExist(carriage) then
            if GetEntityModel(carriage) == hash then
                return true
            end
        end
    end
    return false
end

getMetroRuntimeConfig = function()
    local runtimeCfg = Config.Runtime or {}
    local metroCfg = runtimeCfg.metro or {}
    local derailGuardCfg = metroCfg.derailGuard or {}

    return {
        clearReadyStageSpeed = tonumber(metroCfg.clearReadyStageSpeed) or 0.75,
        unstableForMs = tonumber(derailGuardCfg.unstableForMs) or 1200,
        notifyCooldownMs = tonumber(derailGuardCfg.notifyCooldownMs) or 5000,
        offRouteRecoveryDelayMs = tonumber(metroCfg.offRouteRecoveryDelayMs) or 2500,
        interiorPassengerModelTimeoutMs = tonumber(metroCfg.interiorPassengerModelTimeoutMs) or 5000,
        interiorPassengerCleanupDelayMs = tonumber(metroCfg.interiorPassengerCleanupDelayMs) or 2500,
        stationPassengerEnterMinTimeoutMs = tonumber(metroCfg.stationPassengerEnterMinTimeoutMs) or 1500
    }
end

local function getHudRuntimeConfig()
    local runtimeCfg = Config.Runtime or {}
    local hudCfg = runtimeCfg.hud or {}
    return {
        cancelKeyLabel = tostring(hudCfg.cancelKeyLabel or '[G]'),
        minUpdateIntervalMs = tonumber(hudCfg.minUpdateIntervalMs) or 90
    }
end

local function getNotificationRuntimeConfig()
    local runtimeCfg = Config.Runtime or {}
    local notificationsCfg = runtimeCfg.notifications or {}
    return {
        speedingWarningCooldownMs = tonumber(notificationsCfg.speedingWarningCooldownMs) or 5000
    }
end

local function getRouteRuleConfig(trainType)
    return Utils.GetRouteRules(trainType)
end

local function getPenaltyConfig(trainType)
    return Utils.GetPenaltyConfig(trainType)
end

local function estimateHudNetPayout(routeState)
    if not routeState then return 0 end

    local economy = Config.Economy or {}
    local partial = economy.partial or {}
    local antiAbuse = economy.antiAbuse or {}
    local stopReward, completionReward = getRouteEconomy(routeState)
    local routeStops = #(routeState.stationOrder or {})
    local goodStops = math.max(0, tonumber(routeState.goodStops) or 0)
    local missedStops = math.max(0, tonumber(routeState.missedStops) or 0)
    local completedStops = math.min(routeStops, goodStops + missedStops)
    local elapsedSeconds = math.max(0, math.floor((GetGameTimer() - (routeState.startedAtMs or GetGameTimer())) / 1000.0))
    local minSecondsBeforeAnyPayout = math.max(0, tonumber(antiAbuse.minSecondsBeforeAnyPayout) or 0)
    local minSecondsPerStopCredit = math.max(0, tonumber(antiAbuse.minSecondsPerStopCredit) or 0)
    local stopsEligibleByTime = routeStops

    if minSecondsPerStopCredit > 0 then
        stopsEligibleByTime = math.floor(elapsedSeconds / minSecondsPerStopCredit)
    end

    stopsEligibleByTime = Utils.Clamp(stopsEligibleByTime, 0, routeStops)

    local payableGoodStops = math.min(goodStops, stopsEligibleByTime)
    local payoutPositiveBase = 0

    if elapsedSeconds < minSecondsBeforeAnyPayout then
        payableGoodStops = 0
    end

    if routeStops > 0 and completedStops >= routeStops then
        payoutPositiveBase = completionReward + (payableGoodStops * stopReward)
    elseif partial.enabled ~= false then
        local minStopsForPartial = math.max(0, tonumber(partial.minCompletedStopsForPartial) or 0)
        local partialStopReward = math.max(0, tonumber(partial.rewardPerCompletedStop) or stopReward)
        local maxPartialStops = math.max(1, tonumber(partial.maxPayableStops) or routeStops)
        if payableGoodStops >= minStopsForPartial then
            payoutPositiveBase = math.min(payableGoodStops, maxPartialStops) * partialStopReward
        end
    end

    local multiplier = tonumber(routeState.rankMultiplier) or 1.0
    local payoutPositive = math.floor(payoutPositiveBase * multiplier)
    local penalties =
        ((routeState.missedStops or 0) * (tonumber(Config.Payout.missedStopPenalty) or 0)) +
        ((routeState.wrongStops or 0) * (tonumber(Config.Payout.wrongStopPenalty) or 0)) +
        (tonumber(routeState.dynamicPenaltyAmount) or 0)

    local net = payoutPositive + (tonumber(routeState.passengerRevenue) or 0) - penalties
    return math.max(0, math.floor(net))
end

local function countTrainCarriagesByModel(train, modelName)
    if not modelName or modelName == '' or not train or train == 0 or not DoesEntityExist(train) then
        return 0
    end

    local hash = joaat(modelName)
    local count = 0
    for i = 1, 12 do
        local carriage = GetTrainCarriage(train, i)
        if carriage and carriage ~= 0 and DoesEntityExist(carriage) and GetEntityModel(carriage) == hash then
            count = count + 1
        end
    end
    return count
end

local function getTrainCarriagesByModel(train, modelName, maxCount)
    local matches = {}
    if not modelName or modelName == '' or not train or train == 0 or not DoesEntityExist(train) then
        return matches
    end

    local hash = joaat(modelName)
    for i = 1, 12 do
        local carriage = GetTrainCarriage(train, i)
        if carriage and carriage ~= 0 and DoesEntityExist(carriage) and GetEntityModel(carriage) == hash then
            matches[#matches + 1] = carriage
            if maxCount and #matches >= maxCount then
                break
            end
        end
    end
    return matches
end

local function getTrainCarriages(train, maxCount)
    local matches = {}
    if not train or train == 0 or not DoesEntityExist(train) then
        return matches
    end

    for i = 1, 12 do
        local carriage = GetTrainCarriage(train, i)
        if carriage and carriage ~= 0 and DoesEntityExist(carriage) then
            matches[#matches + 1] = carriage
            if maxCount and #matches >= maxCount then
                break
            end
        end
    end

    return matches
end

local function getTrainConsistDebug(train)
    if not train or train == 0 or not DoesEntityExist(train) then
        return 'missing'
    end

    local models = {}
    for i = 1, 12 do
        local carriage = GetTrainCarriage(train, i)
        if carriage and carriage ~= 0 and DoesEntityExist(carriage) then
            local modelHash = GetEntityModel(carriage)
            local modelName = string.lower(tostring(GetDisplayNameFromVehicleModel(modelHash) or 'unknown'))
            models[#models + 1] = ('%d:%s'):format(i, modelName)
        end
    end

    if #models == 0 then
        return 'no_carriages'
    end

    return table.concat(models, ', ')
end

local function countTrainCarriages(train)
    if not train or train == 0 or not DoesEntityExist(train) then
        return 0
    end

    local count = 0
    for i = 1, 12 do
        local carriage = GetTrainCarriage(train, i)
        if carriage and carriage ~= 0 and DoesEntityExist(carriage) then
            count = count + 1
        end
    end
    return count
end

local function createMissionTrainCompat(variation, spawn, direction)
    local attempts = {
        function()
            return CreateMissionTrain(variation, spawn.x, spawn.y, spawn.z, direction, true, true)
        end,
        function()
            return CreateMissionTrain(variation, spawn.x, spawn.y, spawn.z, direction, true)
        end,
        function()
            return CreateMissionTrain(variation, spawn.x, spawn.y, spawn.z, direction, false)
        end,
        function()
            return CreateMissionTrain(variation, spawn.x, spawn.y, spawn.z, true, false)
        end
    }

    for _, attempt in ipairs(attempts) do
        local ok, train = pcall(attempt)
        if ok and train and train ~= 0 then
            return train
        end
    end

    return nil
end

local function configureSpawnedMissionTrain(train)
    SetTrainSpeed(train, 0.0)
    SetTrainCruiseSpeed(train, 0.0)
    SetEntityAsMissionEntity(train, true, false)
    pcall(function()
        SetTrainState(train, 0)
    end)
    if NetworkGetEntityIsNetworked(train) ~= true then
        NetworkRegisterEntityAsNetworked(train)
    end

    local trainNetId = NetworkGetNetworkIdFromEntity(train)
    if trainNetId and trainNetId ~= 0 then
        SetNetworkIdCanMigrate(trainNetId, true)
        SetNetworkIdExistsOnAllMachines(trainNetId, true)
    end

    for i = 1, 12 do
        local carriage = GetTrainCarriage(train, i)
        if carriage and carriage ~= 0 and DoesEntityExist(carriage) then
            if NetworkGetEntityIsNetworked(carriage) ~= true then
                NetworkRegisterEntityAsNetworked(carriage)
            end

            local carriageNetId = NetworkGetNetworkIdFromEntity(carriage)
            if carriageNetId and carriageNetId ~= 0 then
                SetNetworkIdCanMigrate(carriageNetId, true)
                SetNetworkIdExistsOnAllMachines(carriageNetId, true)
            end
        end
    end
end

local function safeDeleteTrain(train)
    if not train or train == 0 or not DoesEntityExist(train) then
        return
    end

    local ok = pcall(DeleteMissionTrain, train)
    if not ok and DoesEntityExist(train) then
        DeleteEntity(train)
    end
end

local function safeDeleteEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return
    end
    DeleteEntity(entity)
end

local function isFreightRoute(routeState)
    local trainType = string.lower(tostring(routeState and routeState.trainType or ''))
    return trainType == 'freight' or trainType == 'train'
end

local function requestModelSafe(modelName, timeoutMs)
    local modelHash = type(modelName) == 'number' and modelName or joaat(modelName)
    if not IsModelInCdimage(modelHash) then
        return nil
    end
    if not requestModelSync(modelHash, timeoutMs or 7000) then
        return nil
    end
    return modelHash
end

local function clearActiveCargoProp(routeState)
    if not routeState then return end
    if routeState.activeCargoProp and DoesEntityExist(routeState.activeCargoProp) then
        DeleteEntity(routeState.activeCargoProp)
    end
    routeState.activeCargoProp = nil
    routeState.activeCargoStationId = nil
end

local function ensureCargoPropAtStation(routeState, stationId, station)
    if not routeState or not stationId or not station or not station.coords then
        return nil
    end

    if routeState.activeCargoStationId == stationId and routeState.activeCargoProp and DoesEntityExist(routeState.activeCargoProp) then
        return routeState.activeCargoProp
    end

    clearActiveCargoProp(routeState)

    local freightCfg = ((Config.RouteRules or {}).freight or {}).containerProps or {}
    local modelHash = requestModelSafe(freightCfg.modelStation or freightCfg.model or 'prop_container_05a', 7000)
    if not modelHash then
        return nil
    end

    local heading = tonumber(station.heading) or 0.0
    local forward = vec3(math.cos(math.rad(heading)), math.sin(math.rad(heading)), 0.0)
    local right = vec3(-forward.y, forward.x, 0.0)
    local spawnPos = station.coords + (forward * 6.5) + (right * 3.5)
    local obj = CreateObjectNoOffset(modelHash, spawnPos.x, spawnPos.y, spawnPos.z - 1.0, true, true, false)
    if obj and obj ~= 0 and DoesEntityExist(obj) then
        SetEntityHeading(obj, heading + 90.0)
        FreezeEntityPosition(obj, true)
        SetEntityAsMissionEntity(obj, true, true)
        PlaceObjectOnGroundProperly(obj)
        routeState.activeCargoProp = obj
        routeState.activeCargoStationId = stationId
    end

    SetModelAsNoLongerNeeded(modelHash)
    return routeState.activeCargoProp
end

local function getRushHourSnapshot()
    local cfg = Config.RushHour or {}
    if cfg.enabled == false then
        return false, 1.0, 1.0
    end

    local hour = GetClockHours()
    local windows = { cfg.morning or {}, cfg.evening or {} }
    for _, window in ipairs(windows) do
        local startHour = tonumber(window.startHour)
        local endHour = tonumber(window.endHour)
        if startHour and endHour and hour >= startHour and hour < endHour then
            return true, tonumber(window.passengerMultiplier) or 1.0, tonumber(window.fareMultiplier) or 1.0
        end
    end

    return false, 1.0, 1.0
end

local function getMetroCars(routeState)
    local cars = {}
    if not routeState or not routeState.vehicle or routeState.vehicle == 0 or not DoesEntityExist(routeState.vehicle) then
        return cars
    end

    cars[#cars + 1] = routeState.vehicle
    for i = 1, 12 do
        local carriage = GetTrainCarriage(routeState.vehicle, i)
        if carriage and carriage ~= 0 and DoesEntityExist(carriage) then
            cars[#cars + 1] = carriage
        end
    end

    if type(routeState.attachedVehicles) == 'table' then
        for _, attached in ipairs(routeState.attachedVehicles) do
            if attached and attached ~= 0 and DoesEntityExist(attached) then
                cars[#cars + 1] = attached
            end
        end
    end

    return cars
end

local function snapAssignedTrainToStation(routeState, station)
    if not routeState or not station or not routeState.vehicle or routeState.vehicle == 0 or not DoesEntityExist(routeState.vehicle) then
        return false
    end

    local snapCfg = Config.StopSnap or {}
    if snapCfg.enabled == false then
        return false
    end

    local routeType = string.lower(tostring(routeState.trainType or 'metro'))
    local modeCfg = snapCfg[(routeType == 'train') and 'freight' or routeType] or {}
    if modeCfg.enabled == false or modeCfg.snapOnConfirm == false then
        return false
    end

    local stopCoords = getStationStopCoords(station)
    local maxSnapDistance = tonumber(modeCfg.maxSnapDistance or snapCfg.maxSnapDistance) or 30.0
    local currentCoords = GetEntityCoords(routeState.vehicle)
    if #(currentCoords - stopCoords) > maxSnapDistance then
        return false
    end

    routeState.manualTrainSpeed = 0.0
    SetTrainSpeed(routeState.vehicle, 0.0)
    SetTrainCruiseSpeed(routeState.vehicle, 0.0)
    if modeCfg.teleportOnConfirm == true then
        local heading = getStationStopHeading(station)
        SetEntityCoordsNoOffset(routeState.vehicle, stopCoords.x, stopCoords.y, stopCoords.z, false, false, false)
        SetEntityHeading(routeState.vehicle, heading + 0.0)
        pcall(function()
            SetTrainState(routeState.vehicle, 0)
        end)
    end

    for _, attached in ipairs(routeState.attachedVehicles or {}) do
        if attached and attached ~= 0 and DoesEntityExist(attached) then
            SetEntityVelocity(attached, 0.0, 0.0, 0.0)
        end
    end

    return true
end

local metroDoorAnimations = {}

local function getMetroDoorAnimKeyFromCars(cars, sideSign)
    if type(cars) ~= 'table' or #cars == 0 then
        return nil
    end
    return ('%s:%s'):format(tostring(NetworkGetNetworkIdFromEntity(cars[1])), tostring(sideSign >= 0.0 and 1 or -1))
end

local function getMetroDoorIndicesForCar(carIndex, sideSign)
    local isRightSide = sideSign >= 0.0
    local oddCar = (carIndex % 2) == 1

    if oddCar then
        return isRightSide and { 1, 3 } or { 0, 2 }
    end

    return isRightSide and { 0, 2 } or { 1, 3 }
end

local function setMetroDoorRatioForCars(cars, sideSign, ratio)
    for carIndex, car in ipairs(cars) do
        if car and car ~= 0 and DoesEntityExist(car) then
            for _, doorIndex in ipairs(getMetroDoorIndicesForCar(carIndex, sideSign)) do
                pcall(function()
                    SetTrainDoorOpenRatio(car, doorIndex, ratio + 0.0)
                end)
            end
        end
    end
end

local function finalizeMetroDoorStateForCars(cars, sideSign, isOpen)
    for carIndex, car in ipairs(cars) do
        if car and car ~= 0 and DoesEntityExist(car) then
            for _, doorIndex in ipairs(getMetroDoorIndicesForCar(carIndex, sideSign)) do
                pcall(function()
                    if isOpen then
                        SetVehicleDoorOpen(car, doorIndex, false, false)
                    else
                        SetVehicleDoorShut(car, doorIndex, false)
                    end
                end)
            end
        end
    end
end

local function animateMetroDoorStateForCars(cars, sideSign, isOpen)
    if type(cars) ~= 'table' or #cars == 0 then
        return
    end

    local animKey = getMetroDoorAnimKeyFromCars(cars, sideSign)
    if not animKey then
        return
    end

    local animToken = GetGameTimer()
    metroDoorAnimations[animKey] = animToken

    CreateThread(function()
        local ratio = isOpen and 0.0 or 1.0
        local step = isOpen and 0.01 or -0.01

        while true do
            if metroDoorAnimations[animKey] ~= animToken then
                return
            end

            setMetroDoorRatioForCars(cars, sideSign, ratio)

            if (isOpen and ratio >= 1.0) or ((not isOpen) and ratio <= 0.0) then
                break
            end

            ratio = ratio + step
            Wait(5)
        end

        finalizeMetroDoorStateForCars(cars, sideSign, isOpen)
        if metroDoorAnimations[animKey] == animToken then
            metroDoorAnimations[animKey] = nil
        end
    end)
end

local function getMetroCarsFromNetIds(netIds)
    local cars = {}
    if type(netIds) ~= 'table' then
        return cars
    end

    for _, netId in ipairs(netIds) do
        local numericNetId = tonumber(netId)
        if numericNetId and NetworkDoesEntityExistWithNetworkId(numericNetId) then
            local entity = NetworkGetEntityFromNetworkId(numericNetId)
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                cars[#cars + 1] = entity
            end
        end
    end

    return cars
end

RegisterNetEvent('godtrain:client:syncMetroDoors', function(originSource, netIds, sideSign, isOpen)
    if tonumber(originSource) == GetPlayerServerId(PlayerId()) then
        return
    end

    local cars = getMetroCarsFromNetIds(netIds)
    if #cars <= 0 then
        return
    end

    animateMetroDoorStateForCars(cars, tonumber(sideSign) or 1.0, isOpen == true)
end)

local function setMetroDoors(routeState, isOpen)
    if not routeState or string.lower(tostring(routeState.trainType or '')) ~= 'metro' then
        return
    end

    local cars = getMetroCars(routeState)
    if #cars <= 0 then
        return
    end

    local sideSign = tonumber(routeState.metroDoorSideSign) or 1.0
    if isOpen then
        routeState.metroDoorSideSign = sideSign
    else
        sideSign = tonumber(routeState.metroDoorSideSign) or sideSign
    end

    if routeState.vehicle and DoesEntityExist(routeState.vehicle) then
        pcall(function()
            SetTrainState(routeState.vehicle, isOpen and 2 or 4)
        end)
    end

    animateMetroDoorStateForCars(cars, sideSign, isOpen == true)

    local netIds = {}
    for _, car in ipairs(cars) do
        if car and car ~= 0 and DoesEntityExist(car) and NetworkGetEntityIsNetworked(car) then
            netIds[#netIds + 1] = NetworkGetNetworkIdFromEntity(car)
        end
    end

    if #netIds > 0 then
        TriggerServerEvent('godtrain:server:syncMetroDoors', netIds, sideSign, isOpen == true)
    end
end

local function clearMetroPassengerPeds(routeState)
    if not routeState or type(routeState.metroPassengerPeds) ~= 'table' then
        return
    end

    for _, ped in ipairs(routeState.metroPassengerPeds) do
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    routeState.metroPassengerPeds = {}
    routeState.metroPassengerCount = 0
end

local function clearSpawnedStationPassengers()
    local spawned = MetroClient and MetroClient.state and MetroClient.state.spawnedStationPeds
    if type(spawned) ~= 'table' then
        return
    end

    local seen = {}
    for _, list in pairs(spawned) do
        if type(list) == 'table' then
            for _, ped in ipairs(list) do
                if ped and ped ~= 0 and DoesEntityExist(ped) and not seen[ped] then
                    seen[ped] = true
                    DeleteEntity(ped)
                end
            end
        end
    end

    MetroClient.state.spawnedStationPeds = {}
end

local function collectTrackedMetroNpcSet(routeState)
    local tracked = {}

    if routeState and type(routeState.metroPassengerPeds) == 'table' then
        for _, ped in ipairs(routeState.metroPassengerPeds) do
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                tracked[ped] = true
            end
        end
    end

    local spawned = MetroClient and MetroClient.state and MetroClient.state.spawnedStationPeds
    if type(spawned) == 'table' then
        for _, list in pairs(spawned) do
            if type(list) == 'table' then
                for _, ped in ipairs(list) do
                    if ped and ped ~= 0 and DoesEntityExist(ped) then
                        tracked[ped] = true
                    end
                end
            end
        end
    end

    return tracked
end

local isPedSeatedInAssignedTrain

local function cleanupStrayMetroNpcs(routeState, force)
    if not routeState or string.lower(tostring(routeState.trainType or 'metro')) ~= 'metro' then
        return
    end
    if not routeState.vehicle or routeState.vehicle == 0 or not DoesEntityExist(routeState.vehicle) then
        return
    end

    local cfg = (routeState.runtimeCfg and routeState.runtimeCfg.passengerBoarding) or Config.PassengerBoarding or {}
    if cfg.stuckNpcCleanupEnabled == false then
        return
    end

    local now = GetGameTimer()
    if not force then
        local intervalMs = math.max(500, tonumber(cfg.stuckNpcCleanupIntervalMs) or 3000)
        if routeState.lastStrayNpcCleanupAt and (now - routeState.lastStrayNpcCleanupAt) < intervalMs then
            return
        end
    end
    routeState.lastStrayNpcCleanupAt = now

    local duringBoarding = routeState.isBoarding == true or routeState.currentStage == 'boarding'
    if duringBoarding and force ~= true and cfg.stuckNpcCleanupDuringBoarding ~= true then
        return
    end

    local tracked = collectTrackedMetroNpcSet(routeState)
    local cleanupRadius = math.max(20.0, tonumber(cfg.stuckNpcCleanupRadius) or 85.0)
    local trainPos = GetEntityCoords(routeState.vehicle)

    for ped, _ in pairs(tracked) do
        if ped and ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local pedVehicle = GetVehiclePedIsIn(ped, false)
            local inAssignedTrain = pedVehicle ~= 0 and isVehiclePartOfAssignedTrain(routeState, pedVehicle)
            local seatedInAssignedTrain = inAssignedTrain and IsPedSittingInVehicle(ped, pedVehicle)
            if inAssignedTrain and not seatedInAssignedTrain then
                DeleteEntity(ped)
            elseif force == true then
                local distToTrain = #(GetEntityCoords(ped) - trainPos)
                if distToTrain <= cleanupRadius and not IsPedInAnyVehicle(ped, false) then
                    DeleteEntity(ped)
                end
            end
        end
    end
end

isPedSeatedInAssignedTrain = function(routeState, ped)
    if not routeState or not ped or ped == 0 or not DoesEntityExist(ped) then
        return false
    end
    local pedVehicle = GetVehiclePedIsIn(ped, false)
    if pedVehicle == 0 or not isVehiclePartOfAssignedTrain(routeState, pedVehicle) then
        return false
    end
    return IsPedSittingInVehicle(ped, pedVehicle)
end

local function getMetroSeatedCapacityPerCarriage(routeState)
    local cfg = getPassengerBoardingConfig and getPassengerBoardingConfig(routeState) or Config.PassengerBoarding or {}
    local configured = tonumber(cfg.seatedCapacityPerCarriage) or tonumber(cfg.maxPassengersPerCarriage)
    if configured and configured > 0 then
        return math.max(1, math.floor(configured))
    end
    return 4
end

local function getMetroPassengerSeatIndices(routeState, vehicle)
    local seatCount = getMetroSeatedCapacityPerCarriage(routeState)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local model = GetEntityModel(vehicle)
        local modelSeatCount = tonumber(GetVehicleModelNumberOfSeats(model)) or 0
        if modelSeatCount >= 2 then
            local passengerSeatCount = math.max(0, modelSeatCount - 1)
            if passengerSeatCount > 0 then
                seatCount = math.min(seatCount, passengerSeatCount)
            end
        end
    end

    local seats = {}
    for seat = 0, math.max(0, seatCount - 1) do
        seats[#seats + 1] = seat
    end
    return seats
end

local function getMetroPassengerCapacity(routeState)
    local capacity = 0
    for _, car in ipairs(getMetroCars(routeState)) do
        if car and car ~= 0 and DoesEntityExist(car) then
            capacity = capacity + #getMetroPassengerSeatIndices(routeState, car)
        end
    end
    return capacity
end

local syncMetroPassengerManifest
local taskMetroPedWalk

local function getRealisticMetroBoardingTargets(routeState, cfg, isLastStation, passengerMult)
    local currentPassengers = syncMetroPassengerManifest(routeState)
    local capacity = getMetroPassengerCapacity(routeState)
    if isLastStation then
        return 0, currentPassengers, currentPassengers, capacity
    end

    if capacity <= 0 then
        return 0, 0, currentPassengers, 0
    end

    local minPassengers = math.max(0, math.floor((cfg.minPassengers or 4) * passengerMult))
    local maxPassengers = math.max(minPassengers, math.floor((cfg.maxPassengers or minPassengers) * passengerMult))
    local rawDemand = math.random(minPassengers, maxPassengers)

    local targetOccupancyMin = Utils.Clamp(tonumber(cfg.targetOccupancyMin) or 0.42, 0.05, 1.0)
    local targetOccupancyMax = Utils.Clamp(tonumber(cfg.targetOccupancyMax) or 0.78, targetOccupancyMin, 1.0)
    local targetOccupancy = targetOccupancyMin + (math.random() * (targetOccupancyMax - targetOccupancyMin))
    local desiredLoadAfterBoarding = math.floor((capacity * targetOccupancy) + 0.5)

    local occupiedRatio = currentPassengers / math.max(1, capacity)
    local minExitRatio = Utils.Clamp(tonumber(cfg.minExitRatio) or 0.06, 0.0, 1.0)
    local maxExitRatio = Utils.Clamp(tonumber(cfg.maxExitRatio) or 0.24, minExitRatio, 1.0)
    local forceExitThreshold = Utils.Clamp(tonumber(cfg.forceExitOccupancyThreshold) or 0.82, 0.0, 1.0)
    local exitRatio = minExitRatio

    if occupiedRatio > targetOccupancyMax then
        local overflow = occupiedRatio - targetOccupancyMax
        exitRatio = exitRatio + (overflow * 0.9)
    end

    exitRatio = Utils.Clamp(exitRatio + (math.random() * 0.05), minExitRatio, maxExitRatio)
    local exitingTarget = math.min(currentPassengers, math.floor((currentPassengers * exitRatio) + 0.5))
    if currentPassengers > 0 and occupiedRatio >= forceExitThreshold then
        exitingTarget = math.max(1, exitingTarget)
    end

    local passengersAfterExit = math.max(0, currentPassengers - exitingTarget)
    local freeSeatsAfterExit = math.max(0, capacity - passengersAfterExit)
    local occupancyGap = math.max(0, desiredLoadAfterBoarding - passengersAfterExit)
    local boardedTarget = math.min(rawDemand, freeSeatsAfterExit, occupancyGap)

    if boardedTarget <= 0 and freeSeatsAfterExit > 0 and passengersAfterExit < math.floor(capacity * targetOccupancyMin) and rawDemand > 0 then
        boardedTarget = 1
    end

    return math.max(0, boardedTarget), math.max(0, exitingTarget), currentPassengers, capacity
end

syncMetroPassengerManifest = function(routeState)
    if not routeState then
        return 0
    end

    local manifest = {}
    local seen = {}

    for _, car in ipairs(getMetroCars(routeState)) do
        if car and car ~= 0 and DoesEntityExist(car) then
            for _, seatIdx in ipairs(getMetroPassengerSeatIndices(routeState, car)) do
                local ped = GetPedInVehicleSeat(car, seatIdx)
                if ped and ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) and not seen[ped] then
                    seen[ped] = true
                    manifest[#manifest + 1] = ped
                end
            end
        end
    end

    routeState.metroPassengerPeds = manifest
    routeState.metroPassengerCount = #manifest
    return routeState.metroPassengerCount
end

local function spawnMetroInteriorPassenger(routeState)
    if not routeState then return false end
    routeState.metroPassengerPeds = routeState.metroPassengerPeds or {}

    local models = ((Config.NPC or {}).models) or {}
    if #models == 0 then return false end

    local cars = getMetroCars(routeState)
    if #cars == 0 then return false end

    local modelHash = requestModelSafe(models[math.random(1, #models)], getMetroRuntimeConfig().interiorPassengerModelTimeoutMs)
    if not modelHash then return false end

    local chosenCar = cars[math.random(1, #cars)]
    local coords = GetEntityCoords(chosenCar)
    local ped = CreatePed(4, modelHash, coords.x, coords.y, coords.z, GetEntityHeading(chosenCar), false, false)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(modelHash)
        return false
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetEntityInvincible(ped, true)

    local seated = false
    local seatAttempts = getMetroPassengerSeatIndices(routeState, chosenCar)
    for _, seatIdx in ipairs(seatAttempts) do
        if IsVehicleSeatFree(chosenCar, seatIdx) then
            SetPedIntoVehicle(ped, chosenCar, seatIdx)
            seated = true
            break
        end
    end

    if not seated then
        DeleteEntity(ped)
        SetModelAsNoLongerNeeded(modelHash)
        return false
    end

    routeState.metroPassengerPeds[#routeState.metroPassengerPeds + 1] = ped
    routeState.metroPassengerCount = #routeState.metroPassengerPeds
    SetModelAsNoLongerNeeded(modelHash)
    return true
end

local function addMetroInteriorPassengers(routeState, count)
    local added = 0
    for _ = 1, math.max(0, tonumber(count) or 0) do
        if spawnMetroInteriorPassenger(routeState) then
            added = added + 1
        end
    end
    routeState.metroPassengerCount = type(routeState.metroPassengerPeds) == 'table' and #routeState.metroPassengerPeds or 0
    return added
end


local function getSafePedExitCoordsFromVehicle(vehicle, targetCoords)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil, nil
    end

    local offsetY = 2.4
    if targetCoords then
        local localTarget = GetOffsetFromEntityGivenWorldCoords(vehicle, targetCoords.x, targetCoords.y, targetCoords.z)
        offsetY = (localTarget.y or 0.0) >= 0.0 and offsetY or -offsetY
    end

    local exitPos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, offsetY, 0.15)
    local foundGround, groundZ = GetGroundZFor_3dCoord(exitPos.x, exitPos.y, exitPos.z + 2.0, false)
    if foundGround then
        exitPos = vec3(exitPos.x, exitPos.y, groundZ + 0.02)
    end

    return exitPos, GetEntityHeading(vehicle)
end

local function movePedToSafeExitFromVehicle(ped, vehicle, targetCoords)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end

    local exitPos, exitHeading = getSafePedExitCoordsFromVehicle(vehicle, targetCoords)
    if not exitPos then
        return
    end

    ClearPedTasksImmediately(ped)
    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, vehicle, 16)
        Wait(0)
        ClearPedTasksImmediately(ped)
    end
    SetEntityCoordsNoOffset(ped, exitPos.x, exitPos.y, exitPos.z, false, false, false)
    SetEntityHeading(ped, exitHeading)
end

local function releaseMetroInteriorPassengers(routeState, count, station)
    if not routeState or type(routeState.metroPassengerPeds) ~= 'table' then
        return 0
    end

    local portals = buildMetroBoardingPortals(routeState, station)
    local portalIndex = 1
    local exitTarget = nil
    local exitHeading = tonumber((station and station.heading) or 0.0) or 0.0
    if station and station.npc and station.npc.spawnCoords then
        exitTarget = vec3(station.npc.spawnCoords.x, station.npc.spawnCoords.y + 1, station.npc.spawnCoords.z)
        exitHeading = tonumber(station.npc.spawnCoords.w) or exitHeading
    elseif station and station.coords then
        exitTarget = vec3(station.coords.x, station.coords.y + 1, station.coords.z)
    end

    local cfg = getPassengerBoardingConfig(routeState)
    local exitSpeed = math.max(0.95, tonumber(cfg.approachSpeed) or 1.05)
    local exitWalkOutMs = math.max(1200, tonumber(cfg.exitWalkOutMs) or 2400)
    local exitDeleteDelayMs = math.max(6000, tonumber(cfg.exitDeleteDelayMs) or 12000)
    local released = 0
    while released < math.max(0, tonumber(count) or 0) and #routeState.metroPassengerPeds > 0 do
        local ped = table.remove(routeState.metroPassengerPeds, math.random(1, #routeState.metroPassengerPeds))
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedKeepTask(ped, true)
            local vehicle = GetVehiclePedIsIn(ped, false)

            CreateThread(function()
                if not DoesEntityExist(ped) then
                    return
                end

                local portal = portals[portalIndex]
                portalIndex = (portalIndex % math.max(1, #portals)) + 1
                local platformDoor = portal and portal.doorPos or nil
                local interiorDoor = portal and portal.innerDoorPos or platformDoor
                local platformExit = portal and portal.exitPos or platformDoor or exitTarget
                local platformStaging = portal and portal.stagingPos or platformExit or exitTarget

                if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                    if interiorDoor then
                        ClearPedTasksImmediately(ped)
                        SetEntityCoordsNoOffset(ped, interiorDoor.x, interiorDoor.y, interiorDoor.z, false, false, false)
                        SetEntityHeading(ped, GetEntityHeading(vehicle) + 180.0)
                    else
                        movePedToSafeExitFromVehicle(ped, vehicle, platformDoor or exitTarget)
                    end
                end

                if platformDoor then
                    TaskGoStraightToCoord(ped, platformDoor.x, platformDoor.y, platformDoor.z, exitSpeed, -1, exitHeading, 0.12)
                    local walkUntil = GetGameTimer() + 2200
                    while DoesEntityExist(ped) and GetGameTimer() < walkUntil do
                        if #(GetEntityCoords(ped) - platformDoor) <= 1.1 then
                            break
                        end
                        Wait(100)
                    end
                end

                if DoesEntityExist(ped) and platformExit then
                    SetEntityCoordsNoOffset(ped, platformExit.x, platformExit.y, platformExit.z, false, false, false)
                end

                if platformStaging then
                    taskMetroPedWalk(ped, platformStaging, exitSpeed, exitHeading)
                    Wait(exitWalkOutMs)
                    if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
                        if exitTarget then
                            taskMetroPedWalk(ped, exitTarget, exitSpeed, exitHeading)
                        else
                            TaskWanderStandard(ped, 10.0, 10)
                        end
                    end
                else
                    TaskWanderStandard(ped, 10.0, 10)
                end

                local exitCleanupCfg = ((Config.NPC or {}).exitCleanup) or {}
                local deleteDistance = tonumber(exitCleanupCfg.distance) or 26.0
                local stuckInVehicleMs = tonumber(exitCleanupCfg.stuckInVehicleMs) or 14000
                local stillTickLimit = tonumber(exitCleanupCfg.stillTicks) or 12
                local maxLifetimeMs = math.min(tonumber(exitCleanupCfg.maxLifetimeMs) or 32000, exitDeleteDelayMs)
                local cleanupStart = GetGameTimer()
                local lastPos = GetEntityCoords(ped)
                local stillTicks = 0
                while DoesEntityExist(ped) do
                    Wait(1000)
                    if not DoesEntityExist(ped) then break end
                    local pos = GetEntityCoords(ped)
                    local dist = 0.0
                    if exitTarget then
                        dist = #(pos - exitTarget)
                    end
                    if IsPedInAnyVehicle(ped, false) and (GetGameTimer() - cleanupStart > stuckInVehicleMs) then
                        DeleteEntity(ped)
                        break
                    end
                    if dist > deleteDistance then
                        DeleteEntity(ped)
                        break
                    end
                    if #(pos - lastPos) < 0.2 then
                        stillTicks = stillTicks + 1
                    else
                        stillTicks = 0
                    end
                    lastPos = pos
                    if stillTicks >= stillTickLimit then
                        DeleteEntity(ped)
                        break
                    end
                    if GetGameTimer() - cleanupStart > maxLifetimeMs then
                        DeleteEntity(ped)
                        break
                    end
                end
            end)
            released = released + 1
        end
    end

    routeState.metroPassengerCount = #routeState.metroPassengerPeds
    return released
end

local function releaseFailedStationPassenger(ped, station)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return
    end

    local exitTarget = nil
    local exitHeading = 0.0
    if station and station.npc and station.npc.spawnCoords then
        exitTarget = vec3(station.npc.spawnCoords.x, station.npc.spawnCoords.y, station.npc.spawnCoords.z)
        exitHeading = tonumber(station.npc.spawnCoords.w) or 0.0
    elseif station and station.coords then
        exitTarget = vec3(station.coords.x, station.coords.y, station.coords.z)
        exitHeading = tonumber(station.heading) or 0.0
    end

    ClearPedTasks(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)

    if exitTarget then
        TaskFollowNavMeshToCoord(ped, exitTarget.x, exitTarget.y, exitTarget.z, 1.0, 12000, 0.8, false, 0.0)
    else
        TaskWanderStandard(ped, 10.0, 10)
    end

    CreateThread(function()
        local cleanupAt = GetGameTimer() + 12000
        while DoesEntityExist(ped) and GetGameTimer() < cleanupAt do
            Wait(1000)
            if not DoesEntityExist(ped) then
                return
            end
            if exitTarget and #(GetEntityCoords(ped) - exitTarget) <= 1.8 then
                break
            end
        end
        if DoesEntityExist(ped) then
            SetEntityHeading(ped, exitHeading + 0.0)
            DeleteEntity(ped)
        end
    end)
end

local function clearFreightContainers(routeState)
    if not routeState or type(routeState.freightContainerEntities) ~= 'table' then
        return
    end
    for _, entity in ipairs(routeState.freightContainerEntities) do
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
    routeState.freightContainerEntities = {}
end

local function syncFreightContainers(routeState)
    if not routeState or not isFreightRoute(routeState) or not routeState.vehicle or not DoesEntityExist(routeState.vehicle) then
        return
    end

    clearFreightContainers(routeState)
    local freightCfg = ((Config.RouteRules or {}).freight or {}).containerProps or {}
    if freightCfg.enabled == false then
        return
    end
    local maxVisible = tonumber(freightCfg.maxVisible) or #((freightCfg.offsets or {}))
    local maxCount = math.min(tonumber(routeState.freightContainersLoaded) or 0, maxVisible)
    if maxCount <= 0 then return end

    local modelHash = requestModelSafe(freightCfg.model or 'prop_container_05a', 7000)
    if not modelHash then return end

    routeState.freightContainerEntities = {}
    local attachToCarriages = freightCfg.attachToCarriages ~= false
    local carrierModel = freightCfg.carriageModel or 'freightcar'
    local carrierCars = {}
    if attachToCarriages then
        carrierCars = getTrainCarriagesByModel(routeState.vehicle, carrierModel, maxCount)
        if #carrierCars == 0 then
            carrierCars = getTrainCarriages(routeState.vehicle, maxCount)
        end
    end
    local fallbackOffsets = freightCfg.offsets or {}
    local carriageOffset = freightCfg.carriageOffset or vec3(0.0, 0.0, 1.15)

        for idx = 1, maxCount do
            local parentEntity = carrierCars[idx] or routeState.vehicle
            local isCarriageParent = parentEntity ~= routeState.vehicle
            local offset = isCarriageParent and carriageOffset or (fallbackOffsets[idx] or carriageOffset)

            if parentEntity and parentEntity ~= 0 and DoesEntityExist(parentEntity) and offset then
                local parentCoords = GetEntityCoords(parentEntity)

                local obj = CreateObjectNoOffset(modelHash, parentCoords.x, parentCoords.y, parentCoords.z, true, true, false)

                if obj and obj ~= 0 and DoesEntityExist(obj) then
                    AttachEntityToEntity(
                        obj,
                        parentEntity,
                        0,
                        offset.x + 0.0,
                        offset.y + 0.0,
                        offset.z + 0.0,
                        0.0, 0.0, 0.0,
                        true, true, false, true, 2, true
                    )

                    routeState.freightContainerEntities[#routeState.freightContainerEntities + 1] = obj
                    Utils.Debug(
                        ('freight_container_attach slot=%s parent=%s offset=%.2f/%.2f/%.2f'):format(
                            tostring(idx),
                            tostring(GetEntityModel(parentEntity)),
                            tonumber(offset.x or 0.0),
                            tonumber(offset.y or 0.0),
                            tonumber(offset.z or 0.0)
                        )
                    )
                end
            end
        end

    SetModelAsNoLongerNeeded(modelHash)
end

local function cleanupAttachedVehicles(routeState)
    if not routeState or type(routeState.attachedVehicles) ~= 'table' then
        return
    end

    for _, entity in ipairs(routeState.attachedVehicles) do
        safeDeleteEntity(entity)
    end

    routeState.attachedVehicles = {}
end

local function spawnRearAttachedMetro(leadTrain, trainCfg)
    if not leadTrain or leadTrain == 0 or not DoesEntityExist(leadTrain) then
        return nil
    end

    local modelName = trainCfg.rearAttachedModel or trainCfg.model or 'metrotrain'
    local modelHash = joaat(modelName)
    if not requestModelSync(modelHash, 7000) then
        return nil
    end

    local leadCoords = GetEntityCoords(leadTrain)
    local leadHeading = GetEntityHeading(leadTrain)
    local rear = CreateVehicle(modelHash, leadCoords.x, leadCoords.y, leadCoords.z, leadHeading, true, false)
    if not rear or rear == 0 or not DoesEntityExist(rear) then
        return nil
    end

    SetEntityAsMissionEntity(rear, true, true)
    SetVehicleOnGroundProperly(rear)

    local offset = trainCfg.rearAttachOffset or {}
    local ox = tonumber(offset.x) or 0.0
    local oy = tonumber(offset.y) or -25.5
    local oz = tonumber(offset.z) or 0.0
    local pitch = tonumber(offset.pitch) or 0.0
    local roll = tonumber(offset.roll) or 0.0
    local yaw = tonumber(offset.yaw) or 180.0

    AttachEntityToEntity(
        rear,
        leadTrain,
        0,
        ox, oy, oz,
        pitch, roll, yaw,
        false, false, false, false, 2, true
    )

    SetModelAsNoLongerNeeded(modelHash)
    return rear
end

local function spawnMissionTrain(spawn, trainCfg)
    local variations = trainCfg.missionVariations or { trainCfg.missionTrainVariation or Config.Vehicle.missionTrainVariation or 21 }
    local direction = trainCfg.missionTrainDirection
    local saltySpawnStyle = trainCfg.saltySpawnStyle == true
    local requiredMinCarriages = math.max(0, tonumber(trainCfg.requiredMinCarriages) or 0)
    local requiredMaxCarriages = math.max(requiredMinCarriages, tonumber(trainCfg.requiredMaxCarriages) or 999)
    local requiredMatchingCarriages = math.max(0, tonumber(trainCfg.requiredMatchingCarriages) or 0)
    local bestFallbackTrain = nil
    local bestFallbackCarriages = -1
    if direction == nil then direction = Config.Vehicle.missionTrainDirection ~= false end
    local directionAttempts = { direction }
    if directionAttempts[1] ~= (not direction) then
        directionAttempts[#directionAttempts + 1] = not direction
    end

    for _, dir in ipairs(directionAttempts) do
        for _, variation in ipairs(variations) do
            local train = createMissionTrainCompat(variation, spawn, dir)

            if train and train ~= 0 then
                configureSpawnedMissionTrain(train)
                local carriageCount = countTrainCarriages(train)
                local matchingCarriageCount = countTrainCarriagesByModel(train, trainCfg.requiredCarriageModel)
                local modelMatch = trainEntityMatchesModel(train, trainCfg.requiredModel or trainCfg.model)
                local hasRequiredCarriage = trainHasCarriageModel(train, trainCfg.requiredCarriageModel)
                local carriageModelValid = hasRequiredCarriage and matchingCarriageCount >= requiredMatchingCarriages

                Utils.Debug(
                    ('train_spawn_try variation=%s dir=%s lead=%s total=%s matching=%s valid=%s consist=[%s]'):format(
                        tostring(variation),
                        tostring(dir),
                        tostring(string.lower(tostring(GetDisplayNameFromVehicleModel(GetEntityModel(train)) or 'unknown'))),
                        tostring(carriageCount),
                        tostring(matchingCarriageCount),
                        tostring(modelMatch and carriageModelValid),
                        getTrainConsistDebug(train)
                    )
                )

                if saltySpawnStyle then
                    if bestFallbackTrain and bestFallbackTrain ~= train then
                        safeDeleteTrain(bestFallbackTrain)
                    end
                    return train
                end

                if modelMatch and carriageModelValid then
                    if carriageCount >= requiredMinCarriages and carriageCount <= requiredMaxCarriages then
                        if bestFallbackTrain and bestFallbackTrain ~= train then
                            safeDeleteTrain(bestFallbackTrain)
                        end
                        return train
                    end

                    if carriageCount >= requiredMinCarriages and carriageCount < requiredMaxCarriages and carriageCount > bestFallbackCarriages then
                        if bestFallbackTrain and bestFallbackTrain ~= train then
                            safeDeleteTrain(bestFallbackTrain)
                        end
                        bestFallbackTrain = train
                        bestFallbackCarriages = carriageCount
                    else
                        safeDeleteTrain(train)
                    end
                else
                    safeDeleteTrain(train)
                end
                Wait(0)
            end
        end
    end

    return bestFallbackTrain
end

local function spawnJobVehicle(route)
    local ped = PlayerPedId()
    local spawn = route.spawn
    local trainCfg = getRouteTrainConfig(route)
    local useMissionTrain = trainCfg.useMissionTrain
    if useMissionTrain == nil then
        useMissionTrain = Config.Vehicle.useMissionTrain
    end

    ensureTrainModelsLoaded(trainCfg)

    if useMissionTrain then
        local train = spawnMissionTrain(spawn, trainCfg)
        if train and train ~= 0 then
            local attachedVehicles = {}
            local rearModel = string.lower(tostring(trainCfg.rearAttachedModel or ''))
            local forceRearAttach = trainCfg.forceRearAttached == true
            if rearModel ~= '' and rearModel ~= 'nil' and (forceRearAttach or not trainHasCarriageModel(train, rearModel)) then
                local rear = spawnRearAttachedMetro(train, trainCfg)
                if rear and rear ~= 0 then
                    attachedVehicles[#attachedVehicles + 1] = rear
                end
            end

            local warp = trainCfg.warpIntoVehicle
            if warp == nil then warp = Config.Vehicle.warpIntoVehicle end
            if shouldTeleportPlayerToRouteStart(route) then
                teleportPedToEntitySafe(ped, train)
            end
            if warp then
                TaskWarpPedIntoVehicle(ped, train, -1)
            end
            setVehicleFuelSafe(train, Config.Vehicle.fuelLevel or 100.0)
            return train, attachedVehicles
        end

        return nil
    end

    local modelName = trainCfg.model or Config.Vehicle.model
    local model = joaat(modelName)
    RequestModel(model)
    local timeout = GetGameTimer() + 7000
    while not HasModelLoaded(model) do
        Wait(50)
        if GetGameTimer() > timeout then
            return nil
        end
    end

    local veh = CreateVehicle(model, spawn.x, spawn.y, spawn.z, spawn.w, true, false)
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)

    local warp = trainCfg.warpIntoVehicle
    if warp == nil then warp = Config.Vehicle.warpIntoVehicle end
    if shouldTeleportPlayerToRouteStart(route) then
        teleportPedToEntitySafe(ped, veh)
    end
    if warp then
        TaskWarpPedIntoVehicle(ped, veh, -1)
    end

    setVehicleFuelSafe(veh, Config.Vehicle.fuelLevel or 100.0)

    SetModelAsNoLongerNeeded(model)
    return veh, {}
end

local function stationStopAccepted(routeState, station)
    local veh = routeState.vehicle
    local vehCoords = GetEntityCoords(veh)
    local speed = GetEntitySpeed(veh)
    local runtimeCfg = routeState.runtimeCfg or {}
    local radiusMultiplier = runtimeCfg.stopRadiusMultiplier or 1.0
    local effectiveStopRadius = (tonumber(station.stopRadius) or 12.0) * math.max(0.1, radiusMultiplier)
    local stopCoords = getStationStopCoords(station)
    local stopHeading = getStationStopHeading(station)
    local dist = #(vehCoords - stopCoords)
    local maxStopSpeed = runtimeCfg.maxStopSpeed or Config.Vehicle.maxStopSpeed

    local box = station.stopBox
    if box then
        local rad = math.rad(-stopHeading)
        local cosH = math.cos(rad)
        local sinH = math.sin(rad)

        local dx = vehCoords.x - stopCoords.x
        local dy = vehCoords.y - stopCoords.y
        local dz = vehCoords.z - stopCoords.z

        local localX = (dx * cosH) - (dy * sinH)
        local localY = (dx * sinH) + (dy * cosH)

        local halfX = (tonumber(box.x) or (effectiveStopRadius * 2.0)) * 0.5
        local halfY = (tonumber(box.y) or (effectiveStopRadius * 2.0)) * 0.5
        local halfZ = (tonumber(box.z) or 4.0) * 0.5
        local zTolerance = tonumber(station.stopBoxToleranceZ)
            or tonumber((Config.MetroStopZone and Config.MetroStopZone.toleranceZ))
            or 2.0
        local allowedZ = math.max(halfZ, zTolerance)

        local insideBox = math.abs(localX) <= halfX and math.abs(localY) <= halfY and math.abs(dz) <= allowedZ
        if insideBox and speed <= maxStopSpeed then
            return true, dist
        end
        return false, dist
    end

    if dist <= effectiveStopRadius and speed <= maxStopSpeed then
        return true, dist
    end

    return false, dist
end

local function stationStopAcceptedImmediate(routeState, station, insideZone, distToStop)
    if not routeState or not station or not routeState.vehicle or not DoesEntityExist(routeState.vehicle) then
        return false
    end

    local runtimeCfg = routeState.runtimeCfg or {}
    local maxStopSpeed = runtimeCfg.maxStopSpeed or Config.Vehicle.maxStopSpeed
    local speed = math.abs(GetEntitySpeed(routeState.vehicle))
    if speed > maxStopSpeed then
        return false
    end

    if station.stopBox then
        return insideZone == true
    end

    local radiusMultiplier = runtimeCfg.stopRadiusMultiplier or 1.0
    local effectiveStopRadius = (tonumber(station.stopRadius) or 12.0) * math.max(0.1, radiusMultiplier)
    return tonumber(distToStop) and distToStop <= (effectiveStopRadius + 3.0)
end

local function isMetroArrivalReady(routeState, station, insideZone, distToStop)
    if not routeState or not station then
        return false
    end

    if string.lower(tostring(routeState.trainType or 'metro')) ~= 'metro' then
        return false
    end

    local runtimeCfg = routeState.runtimeCfg or {}
    local maxStopSpeed = runtimeCfg.maxStopSpeed or Config.Vehicle.maxStopSpeed
    local speed = math.abs(GetEntitySpeed(routeState.vehicle or 0))
    if speed > maxStopSpeed then
        return false
    end

    if station.stopBox then
        return insideZone == true
    end

    local radiusMultiplier = runtimeCfg.stopRadiusMultiplier or 1.0
    local effectiveStopRadius = (tonumber(station.stopRadius) or 12.0) * math.max(0.1, radiusMultiplier)
    return tonumber(distToStop) and distToStop <= effectiveStopRadius
end

local function updateMetroArrivalDoors(routeState, stationId, station, arrivedReady)
    if not routeState or string.lower(tostring(routeState.trainType or 'metro')) ~= 'metro' then
        return
    end

    local openedForStationId = routeState.doorsOpenStationId
    if openedForStationId ~= nil and openedForStationId ~= stationId then
        setMetroDoors(routeState, false)
        routeState.doorsOpenStationId = nil
    end
end

local function advanceSkippingStation(routeState, station)
    if not routeState then return end

    applyRouteSpeedProfile(routeState, station)
    routeState.currentStationIdx = routeState.currentStationIdx + 1
    TrainUI.HideTextUI()

    if station and station.label then
        ClientBridge.Notify(_L('waypoint_passed', station.label), 'inform')
    end
end

local function syncHudXpFromRoute(routeState)
    local panel = MetroClient and MetroClient.state and MetroClient.state.panelData
    local player = panel and panel.player
    local ui = panel and panel.ui
    if type(player) ~= 'table' then
        return
    end

    local totalXp = math.max(0, math.floor((routeState.baseXp or 0) + (routeState.xpGained or 0)))
    local levelStep = math.max(1, tonumber(ui and ui.xpLevelStep) or 500)
    local level = math.max(1, math.floor(totalXp / levelStep) + 1)
    local levelBaseXp = (level - 1) * levelStep
    local progress = math.max(0.0, math.min(100.0, ((totalXp - levelBaseXp) / levelStep) * 100.0))

    player.xp = totalXp
    player.level = level
    player.levelProgress = Utils.Round(progress, 2)
end

local function completeStationStop(routeState, station)
    local stationId = routeState.stationOrder[routeState.currentStationIdx]
    local stopReward = getRouteEconomy(routeState)
    local shouldLoadFreightContainer = isFreightRoute(routeState) and routeState.currentStationIdx < #routeState.stationOrder
    routeState.goodStops = routeState.goodStops + 1
    routeState.xpGained = (routeState.xpGained or 0) + (routeState.xpPerStop or 0)
    syncHudXpFromRoute(routeState)
    if stationId ~= nil then
        TriggerServerEvent('godtrain:server:recordStop', 'good', stationId)
    end
    ClientBridge.Notify(_L('stop_good', station.label), 'success')
    if (tonumber(stopReward) or 0) > 0 then
        ClientBridge.Notify(_L('station_payment_received', math.floor(stopReward)), 'inform')
    end
    if shouldLoadFreightContainer then
        routeState.freightContainersLoaded = math.min((routeState.freightContainersLoaded or 0) + 1, tonumber(routeState.freightContainerCapacity) or 99)
        syncFreightContainers(routeState)
    end
    applyRouteSpeedProfile(routeState, station)
    routeState.currentStationIdx = routeState.currentStationIdx + 1
    TrainUI.HideTextUI()
end


local function getHudEditorDefaults()
    local hudEditorCfg = (Config.UI and Config.UI.hudEditor) or {}
    local defaultLayout = hudEditorCfg.defaultLayout or {}
    local scaleCfg = hudEditorCfg.scale or {}
    local toggleCommand = '/' .. tostring(hudEditorCfg.toggleCommand or 'godhud')
    local editCommand = '/' .. tostring(hudEditorCfg.command or 'godhudedit')

    return {
        defaultLayout = {
            leftPct = tonumber(defaultLayout.leftPct) or 50.0,
            topPct = tonumber(defaultLayout.topPct) or 1.35,
            scale = tonumber(defaultLayout.scale) or 0.92
        },
        scale = {
            minPct = tonumber(scaleCfg.minPct) or 75,
            maxPct = tonumber(scaleCfg.maxPct) or 220,
            stepPct = tonumber(scaleCfg.stepPct) or 1
        },
        labels = {
            done = _L('ui_hud_edit_done'),
            resetDefault = _L('ui_hud_edit_reset_default'),
            scale = _L('ui_hud_edit_scale'),
            drag = _L('ui_hud_edit_drag'),
            commandHint = _L('ui_hud_command_hint', toggleCommand),
            editCommandHint = _L('ui_hud_edit_command_hint', editCommand)
        }
    }
end

local function collectMetroFreeSeats(routeState)
    syncMetroPassengerManifest(routeState)
    local seats = {}
    for _, car in ipairs(getMetroCars(routeState)) do
        if car and car ~= 0 and DoesEntityExist(car) then
            for _, seatIdx in ipairs(getMetroPassengerSeatIndices(routeState, car)) do
                if IsVehicleSeatFree(car, seatIdx) then
                    seats[#seats + 1] = { vehicle = car, seat = seatIdx }
                end
            end
        end
    end
    return seats
end

local function getStationNpcBoxCenter(station)
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

local function getStationNpcBoxHeading(station)
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

local function getStationNpcBoxSize(station)
    local npc = station and station.npc or {}
    local boxZone = npc.boxZone or {}
    return boxZone.size
end

local function clampPointToStationNpcBox(station, point, padding)
    if not point then
        return nil
    end

    local box = getStationNpcBoxSize(station)
    if not box then
        return point
    end

    local center = getStationNpcBoxCenter(station)
    local heading = getStationNpcBoxHeading(station)
    local safePadding = math.max(0.0, tonumber(padding) or 0.0)
    local halfX = math.max(0.05, ((tonumber(box.x) or 1.0) * 0.5) - safePadding)
    local halfY = math.max(0.05, ((tonumber(box.y) or 1.0) * 0.5) - safePadding)
    local halfZ = math.max(0.05, ((tonumber(box.z) or 2.0) * 0.5) - safePadding)
    local rad = math.rad(-heading)
    local cosH = math.cos(rad)
    local sinH = math.sin(rad)
    local dx = point.x - center.x
    local dy = point.y - center.y
    local dz = point.z - center.z

    local localX = Utils.Clamp((dx * cosH) - (dy * sinH), -halfX, halfX)
    local localY = Utils.Clamp((dx * sinH) + (dy * cosH), -halfY, halfY)
    local localZ = Utils.Clamp(dz, -halfZ, halfZ)

    local worldRad = math.rad(heading)
    local worldCos = math.cos(worldRad)
    local worldSin = math.sin(worldRad)

    return vec3(
        center.x + (localX * worldCos) - (localY * worldSin),
        center.y + (localX * worldSin) + (localY * worldCos),
        center.z + localZ
    )
end

getPassengerBoardingConfig = function(routeState)
    return (routeState and routeState.runtimeCfg and routeState.runtimeCfg.passengerBoarding) or resolvePassengerBoardingConfig(Config.PassengerBoarding or {})
end

local function getRandomStationNpcPoint(station)
    local npcCfg = Config.NPC or {}
    local center = getStationNpcBoxCenter(station)
    local heading = getStationNpcBoxHeading(station)
    local box = getStationNpcBoxSize(station)
    if not box then
        return center, heading
    end

    local padding = math.max(0.0, tonumber(npcCfg.boxPadding) or 0.0)
    local halfX = math.max(0.05, ((tonumber(box.x) or 1.0) * 0.5) - padding)
    local halfY = math.max(0.05, ((tonumber(box.y) or 1.0) * 0.5) - padding)
    local localX = (math.random() * 2.0 - 1.0) * halfX
    local localY = (math.random() * 2.0 - 1.0) * halfY
    local rad = math.rad(heading)
    local cosH = math.cos(rad)
    local sinH = math.sin(rad)

    local point = vec3(
        center.x + (localX * cosH) - (localY * sinH),
        center.y + (localX * sinH) + (localY * cosH),
        center.z
    )
    local foundGround, groundZ = GetGroundZFor_3dCoord(point.x, point.y, point.z + 1.5, false)
    if foundGround then
        point = vec3(point.x, point.y, groundZ + 0.03)
    end

    return point, (npcCfg.randomHeading == true and (math.random() * 360.0) or heading)
end

local function isPointInsideMetroCarBounds(vehicle, point, padding)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or not point then
        return false
    end

    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    if not minDim or not maxDim then
        return false
    end

    local localPoint = GetOffsetFromEntityGivenWorldCoords(vehicle, point.x, point.y, point.z)
    local safePadding = math.max(0.0, tonumber(padding) or 0.0)

    return localPoint.x >= (minDim.x - safePadding)
        and localPoint.x <= (maxDim.x + safePadding)
        and localPoint.y >= (minDim.y - safePadding)
        and localPoint.y <= (maxDim.y + safePadding)
        and localPoint.z >= (minDim.z - 1.0)
        and localPoint.z <= (maxDim.z + 2.2)
end

local function getStationNpcSpawnPoint(routeState, station)
    local cars = getMetroCars(routeState)
    local bestPoint, bestHeading = getRandomStationNpcPoint(station)
    local bestDistance = -1.0

    for _ = 1, 24 do
        local point, heading = getRandomStationNpcPoint(station)
        local blocked = false
        local nearestCarDistance = math.huge

        for _, car in ipairs(cars) do
            if car and car ~= 0 and DoesEntityExist(car) then
                if isPointInsideMetroCarBounds(car, point, 0.55) then
                    blocked = true
                end

                local distanceToCar = #(point - GetEntityCoords(car))
                if distanceToCar < nearestCarDistance then
                    nearestCarDistance = distanceToCar
                end
            end
        end

        if not blocked then
            return point, heading
        end

        if nearestCarDistance > bestDistance then
            bestDistance = nearestCarDistance
            bestPoint = point
            bestHeading = heading
        end
    end

    return bestPoint, bestHeading
end

local function ensureLocalStationPassengers(routeState, stationId, station, desiredCount)
    if not routeState or not stationId or not station then return end
    MetroClient.state.spawnedStationPeds = MetroClient.state.spawnedStationPeds or {}
    local numericKey = stationId
    local namespacedKey = ('metro:%s'):format(tostring(stationId))
    local stationPeds = MetroClient.state.spawnedStationPeds[numericKey] or MetroClient.state.spawnedStationPeds[namespacedKey] or {}
    MetroClient.state.spawnedStationPeds[numericKey] = stationPeds
    MetroClient.state.spawnedStationPeds[namespacedKey] = stationPeds

    local alive = {}
    for _, ped in ipairs(stationPeds) do
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            alive[#alive + 1] = ped
        end
    end
    stationPeds = alive
    MetroClient.state.spawnedStationPeds[numericKey] = stationPeds
    MetroClient.state.spawnedStationPeds[namespacedKey] = stationPeds

    local desired = math.max(0, tonumber(desiredCount) or 0)

    if #stationPeds > desired then
        for i = #stationPeds, desired + 1, -1 do
            local ped = stationPeds[i]
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                DeleteEntity(ped)
            end
            stationPeds[i] = nil
        end
    end

    local spawnCount = desired - #stationPeds
    if spawnCount <= 0 then
        MetroClient.state.spawnedStationPeds[numericKey] = stationPeds
        MetroClient.state.spawnedStationPeds[namespacedKey] = stationPeds
        return
    end

    local models = ((Config.NPC or {}).models) or {}
    if #models == 0 then
        return
    end

    for _ = 1, spawnCount do
        local modelName = models[math.random(1, #models)]
        local modelHash = requestModelSafe(modelName, 5000)
        if modelHash then
            local spawnPoint, spawnHeading = getStationNpcSpawnPoint(routeState, station)
            local ped = CreatePed(4, modelHash, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnHeading, false, false)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedCanBeDraggedOut(ped, false)
                SetPedCanRagdoll(ped, false)
                SetPedFleeAttributes(ped, 0, false)
                SetPedDiesWhenInjured(ped, false)
                SetPedHearingRange(ped, 0.0)
                SetPedSeeingRange(ped, 0.0)
                SetPedAlertness(ped, 0)
                SetPedCanRagdoll(ped, false)
                SetPedRandomComponentVariation(ped, true)
                TaskStandStill(ped, -1)
                stationPeds[#stationPeds + 1] = ped
            end
            SetModelAsNoLongerNeeded(modelHash)
        end
    end

    MetroClient.state.spawnedStationPeds[numericKey] = stationPeds
    MetroClient.state.spawnedStationPeds[namespacedKey] = stationPeds
end

local function getMetroBoardingLaneOffsets(routeState)
    local cfg = getPassengerBoardingConfig(routeState)
    local offsets = cfg.laneOffsets
    if type(offsets) ~= 'table' or #offsets == 0 then
        return { -5.8, 0.0, 5.8 }
    end
    return offsets
end

local function getMetroBoardingPoint(vehicle, rightOffset, forwardOffset, zOffset)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local point = GetOffsetFromEntityInWorldCoords(vehicle, rightOffset + 0.0, forwardOffset + 0.0, zOffset + 0.0)
    local foundGround, groundZ = GetGroundZFor_3dCoord(point.x, point.y, point.z + 1.5, false)
    if foundGround then
        return vec3(point.x, point.y, groundZ + 0.02)
    end
    return vec3(point.x, point.y, point.z)
end

local function getMetroPlatformReferencePoint(station)
    local npc = station and station.npc or {}
    local spawnCoords = npc.spawnCoords
    if spawnCoords then
        return vec3(spawnCoords.x, spawnCoords.y, spawnCoords.z)
    end

    local center = getStationNpcBoxCenter(station)
    if center then
        return center
    end

    local stopCoords = station and getStationStopCoords(station) or nil
    if stopCoords then
        return stopCoords
    end

    return nil
end

local function getConfiguredMetroBoardingSideSign(routeState)
    local cfg = getPassengerBoardingConfig(routeState)
    local configured = tonumber(cfg.boardingSideSign)
    if configured and configured < 0.0 then
        return -1.0
    end
    return 1.0
end

local function getMetroBoardingOffsetSignForCar(carIndex, sideSign)
    local normalizedSign = (tonumber(sideSign) or 1.0) >= 0.0 and 1.0 or -1.0
    if (tonumber(carIndex) or 1) % 2 == 0 then
        return normalizedSign * -1.0
    end
    return normalizedSign
end

local function getStationNpcBoxPadding()
    return math.max(0.15, tonumber(((Config.NPC or {}).boxPadding)) or 0.15)
end

local function tryGetMetroDoorEntryOffset(vehicle, doorIndex, sideSign)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local ok, doorWorld = pcall(function()
        return GetEntryPositionOfDoor(vehicle, doorIndex)
    end)
    if not ok or not doorWorld then
        return nil
    end

    local localDoor = GetOffsetFromEntityGivenWorldCoords(vehicle, doorWorld.x, doorWorld.y, doorWorld.z)
    local localX = tonumber(localDoor and localDoor.x) or 0.0
    local localY = tonumber(localDoor and localDoor.y) or 0.0
    if math.abs(localX) <= 0.05 and math.abs(localY) <= 0.05 then
        return nil
    end

    if (tonumber(sideSign) or 1.0) >= 0.0 then
        localX = math.abs(localX)
    else
        localX = -math.abs(localX)
    end

    return {
        rightOffset = localX,
        forwardOffset = localY
    }
end

local function classifyMetroDoorPosition(doorEntries)
    if type(doorEntries) ~= 'table' or #doorEntries <= 0 then
        return doorEntries or {}
    end

    table.sort(doorEntries, function(a, b)
        return (tonumber(a.forwardOffset) or 0.0) < (tonumber(b.forwardOffset) or 0.0)
    end)

    if #doorEntries == 1 then
        doorEntries[1].doorRole = 'front'
        return doorEntries
    end

    doorEntries[1].doorRole = 'rear'
    doorEntries[#doorEntries].doorRole = 'front'
    return doorEntries
end

getMetroBoardingSideSign = function(vehicle, station, routeState)
    return getConfiguredMetroBoardingSideSign(routeState)
end

buildMetroBoardingPortals = function(routeState, station)
    local cfg = getPassengerBoardingConfig(routeState)
    local cars = getMetroCars(routeState)
    if #cars <= 0 then
        return {}
    end

    local laneOffsets = getMetroBoardingLaneOffsets(routeState)
    local queueDepth = tonumber(cfg.queueDepth) or 1.5
    local stagingDepth = tonumber(cfg.stagingDepth) or 3.2
    local doorOffset = tonumber(cfg.doorOffset) or 1.45
    local boxPadding = getStationNpcBoxPadding()
    local portals = {}
    local sideSign = getConfiguredMetroBoardingSideSign(routeState)

    for carIndex, car in ipairs(cars) do
        local carSideSign = getMetroBoardingOffsetSignForCar(carIndex, sideSign)
        local doorEntries = {}
        for _, doorIndex in ipairs(getMetroDoorIndicesForCar(carIndex, carSideSign)) do
            local doorEntry = tryGetMetroDoorEntryOffset(car, doorIndex, carSideSign)
            if doorEntry then
                doorEntries[#doorEntries + 1] = doorEntry
            end
        end
        if #doorEntries <= 0 then
            for _, laneValue in ipairs(laneOffsets) do
                doorEntries[#doorEntries + 1] = {
                    rightOffset = doorOffset * carSideSign,
                    forwardOffset = tonumber(laneValue) or 0.0
                }
            end
        end

        classifyMetroDoorPosition(doorEntries)

        for laneIndex, doorEntry in ipairs(doorEntries) do
            local laneOffset = tonumber(doorEntry.forwardOffset) or 0.0
            local rightOffset = tonumber(doorEntry.rightOffset) or (doorOffset * carSideSign)
            local doorPos = getMetroBoardingPoint(car, rightOffset, laneOffset, 0.0)
            local innerDoorPos = getMetroBoardingPoint(car, rightOffset - (0.75 * carSideSign), laneOffset, 0.0)
            local entryPos = clampPointToStationNpcBox(
                station,
                getMetroBoardingPoint(car, rightOffset + (0.55 * carSideSign), laneOffset, 0.0),
                boxPadding
            )
            local queuePos = clampPointToStationNpcBox(
                station,
                getMetroBoardingPoint(car, rightOffset + (queueDepth * carSideSign), laneOffset, 0.0),
                boxPadding
            )
            local stagingPos = clampPointToStationNpcBox(station, getMetroBoardingPoint(car, rightOffset + (stagingDepth * carSideSign), laneOffset, 0.0), boxPadding)
            local exitPos = clampPointToStationNpcBox(
                station,
                getMetroBoardingPoint(car, rightOffset + (math.max(1.15, queueDepth * 0.7) * carSideSign), laneOffset, 0.0),
                boxPadding
            )
            if doorPos and innerDoorPos and entryPos and queuePos and stagingPos and exitPos then
                portals[#portals + 1] = {
                    key = ('%s:%s'):format(tostring(car), tostring(laneIndex)),
                    vehicle = car,
                    laneOffset = laneOffset,
                    sideSign = carSideSign,
                    doorRole = doorEntry.doorRole or ((laneOffset >= 0.0) and 'front' or 'rear'),
                    entryPos = entryPos,
                    doorPos = doorPos,
                    innerDoorPos = innerDoorPos,
                    queueBaseOffset = rightOffset + (queueDepth * carSideSign),
                    queuePos = queuePos,
                    stagingPos = stagingPos,
                    exitPos = exitPos
                }
            end
        end
    end

    return portals
end

local function buildMetroBoardingAssignments(routeState, station, targetCount)
    local cfg = getPassengerBoardingConfig(routeState)
    local freeSeats = collectMetroFreeSeats(routeState)
    if #freeSeats <= 0 then
        return {}
    end

    local portals = buildMetroBoardingPortals(routeState, station)
    if #portals <= 0 then
        return {}
    end

    local queueSpacing = tonumber(cfg.queueSpacing) or 0.85
    local maxQueuePerDoor = math.max(1, tonumber(cfg.maxQueuePerDoor) or 3)
    local boxPadding = getStationNpcBoxPadding()
    local assignments = {}
    local portalUsage = {}

    for i = 1, math.min(targetCount, #freeSeats) do
        local seatInfo = freeSeats[i]
        local bestPortal = nil
        local bestScore = math.huge
        local vehicleCenter = seatInfo.vehicle and DoesEntityExist(seatInfo.vehicle)
            and GetOffsetFromEntityInWorldCoords(seatInfo.vehicle, 0.0, 0.0, 0.0)
            or vec3(0.0, 0.0, 0.0)

        for _, portal in ipairs(portals) do
            if portal.vehicle == seatInfo.vehicle then
                local usage = portalUsage[portal.key] or 0
                local score = #(portal.doorPos - vehicleCenter) + (usage * 20.0)
                if score < bestScore and usage < maxQueuePerDoor then
                    bestScore = score
                    bestPortal = portal
                end
            end
        end

        if not bestPortal then
            bestPortal = portals[((i - 1) % #portals) + 1]
        end

        local queueIndex = portalUsage[bestPortal.key] or 0
        portalUsage[bestPortal.key] = queueIndex + 1
        local queuePos = getMetroBoardingPoint(
            bestPortal.vehicle,
            bestPortal.queueBaseOffset + (queueIndex * queueSpacing * bestPortal.sideSign),
            bestPortal.laneOffset,
            0.0
        )
        queuePos = clampPointToStationNpcBox(station, queuePos, boxPadding)
        if queuePos then
            assignments[#assignments + 1] = {
                vehicle = seatInfo.vehicle,
                seat = seatInfo.seat,
                entryPos = bestPortal.entryPos or bestPortal.queuePos,
                doorPos = bestPortal.doorPos,
                innerDoorPos = bestPortal.innerDoorPos or bestPortal.doorPos,
                doorRole = bestPortal.doorRole or 'front',
                queuePos = queuePos,
                stagingPos = bestPortal.stagingPos,
                exitPos = bestPortal.exitPos or bestPortal.queuePos or bestPortal.stagingPos,
                sideSign = bestPortal.sideSign,
                portalKey = bestPortal.key,
                startDelayMs = 0
            }
        end
    end

    return assignments
end

taskMetroPedWalk = function(ped, targetPos, speed, heading)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not targetPos then
        return
    end

    local moveSpeed = math.max(0.45, tonumber(speed) or 1.0)
    local finalHeading = tonumber(heading) or 0.0

    ClearPedTasks(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    if pcall(function()
        TaskFollowNavMeshToCoord(
            ped,
            targetPos.x, targetPos.y, targetPos.z,
            moveSpeed,
            -1,
            0.35,
            0,
            finalHeading
        )
    end) then
        return
    end

    TaskGoStraightToCoord(ped, targetPos.x, targetPos.y, targetPos.z, moveSpeed, -1, finalHeading, 0.12)
end

local function moveMetroPedToPoint(routeState, ped, targetPos, speed, heading, arrivalRadius, timeoutMs, useStraightTask)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not targetPos then
        return false
    end

    local targetSpeed = math.max(0.45, tonumber(speed) or 1.0)
    local targetHeading = tonumber(heading) or 0.0
    local radius = math.max(0.45, tonumber(arrivalRadius) or 1.0)
    local timeout = math.max(300, tonumber(timeoutMs) or 2500)
    local deadline = GetGameTimer() + timeout

    ClearPedTasks(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)

    if useStraightTask == true then
        TaskGoStraightToCoord(ped, targetPos.x, targetPos.y, targetPos.z, targetSpeed, -1, targetHeading, 0.12)
    else
        taskMetroPedWalk(ped, targetPos, targetSpeed, targetHeading)
    end

    while DoesEntityExist(ped) and GetGameTimer() < deadline do
        if routeState and routeState.boardingAbortRequested == true then
            return false
        end

        if #(GetEntityCoords(ped) - targetPos) <= radius then
            return true
        end

        Wait(100)
    end

    if useStraightTask ~= true and DoesEntityExist(ped) and (not routeState or routeState.boardingAbortRequested ~= true) then
        local fallbackDeadline = GetGameTimer() + math.min(1400, timeout)
        TaskGoStraightToCoord(ped, targetPos.x, targetPos.y, targetPos.z, targetSpeed, -1, targetHeading, 0.12)
        while DoesEntityExist(ped) and GetGameTimer() < fallbackDeadline do
            if #(GetEntityCoords(ped) - targetPos) <= radius then
                return true
            end
            Wait(100)
        end
    end

    return DoesEntityExist(ped) and #(GetEntityCoords(ped) - targetPos) <= math.max(radius, 1.25)
end

local function orderStationPassengersByDistance(peds, point)
    table.sort(peds, function(a, b)
        if not DoesEntityExist(a) then return false end
        if not DoesEntityExist(b) then return true end
        return #(GetEntityCoords(a) - point) < #(GetEntityCoords(b) - point)
    end)
end

local function pairStationPassengersToAssignments(candidates, assignments)
    local freePeds = {}
    for _, ped in ipairs(candidates or {}) do
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            freePeds[#freePeds + 1] = {
                ped = ped,
                pos = GetEntityCoords(ped)
            }
        end
    end

    local pairs = {}
    for _, assignment in ipairs(assignments or {}) do
        local anchor = assignment.stagingPos or assignment.entryPos or assignment.queuePos or assignment.doorPos
        local bestIndex = nil
        local bestDistance = math.huge
        if anchor then
            for idx, pedData in ipairs(freePeds) do
                local dist = #(pedData.pos - anchor)
                if dist < bestDistance then
                    bestDistance = dist
                    bestIndex = idx
                end
            end
        elseif #freePeds > 0 then
            bestIndex = 1
        end

        if bestIndex then
            pairs[#pairs + 1] = {
                ped = table.remove(freePeds, bestIndex).ped,
                assignment = assignment
            }
        end
    end

    local leftoverPeds = {}
    for _, pedData in ipairs(freePeds) do
        leftoverPeds[#leftoverPeds + 1] = pedData.ped
    end

    return pairs, leftoverPeds
end

local function boardStationPassengersSimple(routeState, stationId, station, amount, enterTimeoutMs)
    if not routeState or not stationId or not amount or amount <= 0 then return 0 end
    if not MetroClient or not MetroClient.state or not MetroClient.state.spawnedStationPeds then return 0 end
    local cfg = getPassengerBoardingConfig(routeState)

    local stationPeds = MetroClient.state.spawnedStationPeds[stationId]
        or MetroClient.state.spawnedStationPeds[('metro:%s'):format(tostring(stationId))]
    if type(stationPeds) ~= 'table' then return 0 end

    local candidates = {}
    for _, ped in ipairs(stationPeds) do
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            candidates[#candidates + 1] = ped
        end
    end

    local targetCount = math.min(math.max(0, tonumber(amount) or 0), #candidates)
    if targetCount <= 0 then return 0 end

    local assignments = buildMetroBoardingAssignments(routeState, station, targetCount)
    if #assignments <= 0 then
        passengerBoardingDebug(routeState, 'simple_no_assignments', ('station=%s amount=%s candidates=%s'):format(tostring(stationId), tostring(targetCount), tostring(#candidates)))
        for _, ped in ipairs(candidates) do
            releaseFailedStationPassenger(ped, station)
        end
        MetroClient.state.spawnedStationPeds[stationId] = {}
        MetroClient.state.spawnedStationPeds[('metro:%s'):format(tostring(stationId))] = {}
        return 0
    end

    local boarded = 0
    local limit = math.min(targetCount, #assignments, #candidates)
    routeState.metroPassengerPeds = routeState.metroPassengerPeds or {}
    local approachSpeed = math.max(1.0, tonumber(cfg.approachSpeed) or 1.05)
    local repathMs = math.max(250, tonumber(cfg.repathIntervalMs) or 450)
    local timeoutBudgetMs = tonumber(enterTimeoutMs) or 0
    local timeoutMs = timeoutBudgetMs > 0
        and math.max(7000, math.min(30000, timeoutBudgetMs))
        or math.max(9000, math.min(30000, 8000 + (limit * 600)))
    local snapToDoorDistance = math.max(0.8, tonumber(cfg.doorSnapDistance) or 1.2)
    local snapToInteriorDistance = math.max(1.0, tonumber(cfg.boardDistance) or 1.2)
    local warpAfterMs = math.max(1200, tonumber(cfg.boardFallbackEnterMs) or 1700)
    local doorPauseMs = math.max(100, tonumber(cfg.doorPauseMs) or 260)
    local seatWarpDelayMinMs = math.max(80, tonumber(cfg.seatWarpDelayMinMs) or 220)
    local seatWarpDelayMaxMs = math.max(seatWarpDelayMinMs, tonumber(cfg.seatWarpDelayMaxMs) or 650)
    local completed = 0
    local pairedAssignments, leftoverCandidates = pairStationPassengersToAssignments(candidates, assignments)
    local pairCount = math.min(limit, #pairedAssignments)

    if pairCount <= 0 then
        for _, ped in ipairs(candidates) do
            if ped and DoesEntityExist(ped) then
                releaseFailedStationPassenger(ped, station)
            end
        end
        MetroClient.state.spawnedStationPeds[stationId] = {}
        MetroClient.state.spawnedStationPeds[('metro:%s'):format(tostring(stationId))] = {}
        return 0
    end

    local function finishPed(success, ped)
        if success and ped and DoesEntityExist(ped) and isPedSeatedInAssignedTrain(routeState, ped) then
            boarded = boarded + 1
            routeState.metroPassengerPeds[#routeState.metroPassengerPeds + 1] = ped
        elseif ped and DoesEntityExist(ped) then
            releaseFailedStationPassenger(ped, station)
        end
        completed = completed + 1
    end

    for i = 1, pairCount do
        local pair = pairedAssignments[i]
        local ped = pair and pair.ped or nil
        local assignment = pair and pair.assignment or nil
        if ped and DoesEntityExist(ped) and assignment and assignment.vehicle and DoesEntityExist(assignment.vehicle) and IsVehicleSeatFree(assignment.vehicle, assignment.seat) then
            CreateThread(function()
                local startedAt = GetGameTimer()
                local heading = GetEntityHeading(assignment.vehicle) + 0.0
                local lastTaskAt = 0

                if assignment.stagingPos then
                    moveMetroPedToPoint(routeState, ped, assignment.stagingPos, approachSpeed, heading, 1.1, 2400, false)
                end

                if DoesEntityExist(ped) and assignment.queuePos then
                    moveMetroPedToPoint(routeState, ped, assignment.queuePos, approachSpeed, heading, 0.95, 2600, false)
                end

                if DoesEntityExist(ped) and assignment.entryPos then
                    moveMetroPedToPoint(routeState, ped, assignment.entryPos, approachSpeed, heading, 0.9, 2400, false)
                end

                if DoesEntityExist(ped) and assignment.doorPos then
                    moveMetroPedToPoint(routeState, ped, assignment.doorPos, approachSpeed, heading, snapToDoorDistance, 2200, true)
                end

                while DoesEntityExist(ped) and DoesEntityExist(assignment.vehicle) and (GetGameTimer() - startedAt) < timeoutMs do
                    if routeState.boardingAbortRequested == true then
                        finishPed(false, ped)
                        return
                    end

                    if isPedSeatedInAssignedTrain(routeState, ped) then
                        finishPed(true, ped)
                        return
                    end

                    local nowTick = GetGameTimer()
                    local doorDist = #(GetEntityCoords(ped) - assignment.doorPos)
                    if doorDist <= snapToDoorDistance then
                        break
                    end

                    if doorDist <= snapToInteriorDistance and (nowTick - startedAt) >= warpAfterMs then
                        break
                    end

                    if (nowTick - lastTaskAt) >= repathMs then
                        TaskGoStraightToCoord(ped, assignment.doorPos.x, assignment.doorPos.y, assignment.doorPos.z, approachSpeed, -1, heading, 0.12)
                        lastTaskAt = nowTick
                    end

                    Wait(100)
                end

                if not DoesEntityExist(ped) or not DoesEntityExist(assignment.vehicle) then
                    finishPed(false, ped)
                    return
                end

                ClearPedTasksImmediately(ped)
                SetEntityNoCollisionEntity(ped, assignment.vehicle, true)
                SetEntityNoCollisionEntity(assignment.vehicle, ped, true)
                SetEntityCoordsNoOffset(ped, assignment.innerDoorPos.x, assignment.innerDoorPos.y, assignment.innerDoorPos.z, false, false, false)
                SetEntityHeading(ped, heading)
                Wait(doorPauseMs)

                if DoesEntityExist(ped) and DoesEntityExist(assignment.vehicle) and IsVehicleSeatFree(assignment.vehicle, assignment.seat) then
                    Wait(math.random(seatWarpDelayMinMs, seatWarpDelayMaxMs))
                    SetPedIntoVehicle(ped, assignment.vehicle, assignment.seat)
                    Wait(150)
                end

                if DoesEntityExist(ped) and DoesEntityExist(assignment.vehicle) then
                    SetEntityNoCollisionEntity(ped, assignment.vehicle, false)
                    SetEntityNoCollisionEntity(assignment.vehicle, ped, false)
                end

                finishPed(isPedSeatedInAssignedTrain(routeState, ped), ped)
            end)
        elseif ped and DoesEntityExist(ped) then
            releaseFailedStationPassenger(ped, station)
            completed = completed + 1
        end
    end

    local waitStartedAt = GetGameTimer()
    while completed < pairCount and (GetGameTimer() - waitStartedAt) < timeoutMs and routeState.boardingAbortRequested ~= true do
        Wait(100)
    end

    for _, ped in ipairs(leftoverCandidates) do
        if ped and DoesEntityExist(ped) then
            releaseFailedStationPassenger(ped, station)
        end
    end

    MetroClient.state.spawnedStationPeds[stationId] = {}
    MetroClient.state.spawnedStationPeds[('metro:%s'):format(tostring(stationId))] = {}
    syncMetroPassengerManifest(routeState)
    return boarded
end

local function sendStationPassengersToTrain(routeState, stationId, station, amount, enterTimeoutMs)
    return boardStationPassengersSimple(routeState, stationId, station, amount, enterTimeoutMs)
end

local function calculateMetroBoardingDurationMs(cfg, exitingCount, boardingCount)
    local baseDuration = math.max(3500, tonumber(cfg.durationMs) or 14500)
    local perPassengerDuration = math.max(250, tonumber(cfg.durationPerPassengerMs) or 720)
    local maxDuration = math.max(baseDuration, tonumber(cfg.maxDurationMs) or 30000)
    local trafficWeight = math.max(0, math.floor(boardingCount * 0.8) + math.floor(exitingCount * 0.55))
    return math.min(maxDuration, baseDuration + (trafficWeight * perPassengerDuration))
end


local function runPassengerBoarding(routeState, stationId, station)
    local cfg = getPassengerBoardingConfig(routeState)
    if routeState.isBoarding then
        return false
    end

    local now = GetGameTimer()
    if routeState.lastBoardingTick and (now - routeState.lastBoardingTick) < math.max(0, tonumber(cfg.cooldownMs) or 0) then
        return false
    end

    local isLastStation = routeState.currentStationIdx >= #routeState.stationOrder
    local isRushHour, passengerMultiplier, fareMultiplier = getRushHourSnapshot()
    local boardTarget, exitTarget = getRealisticMetroBoardingTargets(routeState, cfg, isLastStation, passengerMultiplier)
    local stageDurationMs = calculateMetroBoardingDurationMs(cfg, exitTarget, boardTarget)
    local exitDwellMs = math.max(250, tonumber(cfg.exitDwellMs) or 1000)
    if boardTarget <= 0 and exitTarget <= 0 then
        stageDurationMs = math.max(1200, math.min(2600, exitDwellMs + 750))
    end

    clearSpawnedStationPassengers()
    routeState.isBoarding = true
    routeState.currentStage = 'boarding'
    routeState.stageStartedAt = now
    routeState.stageDurationMs = stageDurationMs
    routeState.serviceLockUntilMs = now + stageDurationMs + 900
    routeState.metroDoorSideSign = getMetroBoardingSideSign(routeState.vehicle, station, routeState)
    routeState.doorsOpenStationId = stationId
    routeState.boardedPassengers = syncMetroPassengerManifest(routeState)
    routeState.isRushHour = isRushHour
    routeState.rushHourFareMultiplier = fareMultiplier
    routeState.lastHudSignature = nil
    routeState.boardingAbortRequested = false

    if routeState.vehicle and DoesEntityExist(routeState.vehicle) then
        SetTrainSpeed(routeState.vehicle, 0.0)
        SetTrainCruiseSpeed(routeState.vehicle, 0.0)
        routeState.manualTrainSpeed = 0.0
    end

    setMetroDoors(routeState, true)
    updateHud(routeState)

    local boarded = 0
    local workerFinished = false
    local workerOk = true

    CreateThread(function()
        local ok, err = pcall(function()
            local released = 0
            if exitTarget > 0 then
                released = releaseMetroInteriorPassengers(routeState, exitTarget, station)
            end

            if released > 0 or boardTarget > 0 then
                Wait(exitDwellMs)
            else
                Wait(math.max(600, math.min(1200, exitDwellMs)))
            end

            if routeState.boardingAbortRequested == true then
                return
            end

            if boardTarget > 0 then
                ensureLocalStationPassengers(routeState, stationId, station, boardTarget)
                Wait(150)
                if routeState.boardingAbortRequested ~= true then
                    boarded = sendStationPassengersToTrain(routeState, stationId, station, boardTarget, stageDurationMs - 500)
                end
            end

            syncMetroPassengerManifest(routeState)
        end)

        if not ok then
            workerOk = false
            passengerBoardingDebug(routeState, 'boarding_worker_failed', tostring(err))
        end

        workerFinished = true
    end)

    local progressOk = TrainUI.Progress({
        duration = stageDurationMs,
        label = _L('boarding_progress_sync'),
        useWhileDead = false,
        canCancel = cfg.allowCancel == true,
        disable = {
            move = true,
            car = true,
            combat = true
        }
    })

    if not progressOk then
        routeState.boardingAbortRequested = true
    end

    local waitDeadlineAt = GetGameTimer() + math.max(2500, stageDurationMs + 3000)
    while not workerFinished and GetGameTimer() < waitDeadlineAt do
        Wait(100)
    end

    syncMetroPassengerManifest(routeState)
    routeState.boardedPassengers = routeState.metroPassengerCount or 0
    routeState.totalPassengerTrips = (routeState.totalPassengerTrips or 0) + math.max(0, boarded)
    routeState.isBoarding = false
    routeState.currentStage = 'ready'
    routeState.stageStartedAt = nil
    routeState.stageDurationMs = nil
    routeState.lastBoardingTick = GetGameTimer()
    routeState.serviceLockUntilMs = routeState.lastBoardingTick + 900
    routeState.doorsOpenStationId = nil
    routeState.lastHudSignature = nil
    routeState.boardingAbortRequested = nil

    clearSpawnedStationPassengers()
    setMetroDoors(routeState, false)
    cleanupStrayMetroNpcs(routeState, false)
    updateHud(routeState)

    if not progressOk then
        ClientBridge.Notify(_L('boarding_cancelled'), 'error')
        return false
    end

    return workerOk
end

local function runFreightLoading(routeState, stationId, station)
    local cfg = (routeState.runtimeCfg and routeState.runtimeCfg.passengerBoarding) or Config.PassengerBoarding or {}
    if routeState.isBoarding then
        return false
    end

    local now = GetGameTimer()
    if routeState.lastBoardingTick and (now - routeState.lastBoardingTick) < (cfg.cooldownMs or 0) then
        return false
    end

    routeState.isBoarding = true
    routeState.currentStage = 'loading'
    routeState.stageStartedAt = GetGameTimer()
    routeState.stageDurationMs = cfg.durationMs or 6500
    routeState.serviceLockUntilMs = GetGameTimer() + routeState.stageDurationMs + 750
    routeState.lastHudSignature = nil

    if routeState.vehicle and DoesEntityExist(routeState.vehicle) then
        SetTrainSpeed(routeState.vehicle, 0.0)
        SetTrainCruiseSpeed(routeState.vehicle, 0.0)
        routeState.manualTrainSpeed = 0.0
    end

    ensureCargoPropAtStation(routeState, stationId, station)
    updateHud(routeState)
    ClientBridge.Notify(_L('freight_loading_title'), 'inform')

    local ok = TrainUI.Progress({
        duration = cfg.durationMs or 6500,
        label = _L('freight_loading_progress_sync'),
        useWhileDead = false,
        canCancel = false,
        disable = {
            move = true,
            car = true,
            combat = true
        }
    })

    routeState.isBoarding = false
    routeState.lastBoardingTick = GetGameTimer()

    if not ok then
        routeState.currentStage = nil
        routeState.stageStartedAt = nil
        routeState.stageDurationMs = nil
        routeState.serviceLockUntilMs = nil
        routeState.lastHudSignature = nil
        updateHud(routeState)
        ClientBridge.Notify(_L('boarding_cancelled'), 'error')
        return false
    end

    clearActiveCargoProp(routeState)
    routeState.currentStage = 'ready'
    routeState.stageStartedAt = nil
    routeState.stageDurationMs = nil
    routeState.serviceLockUntilMs = GetGameTimer() + 750
    routeState.lastHudSignature = nil
    updateHud(routeState)
    ClientBridge.Notify(_L('freight_loading_done', station.label), 'success')
    ClientBridge.Notify(_L('freight_ready_departure'), 'success')
    return true
end

local function runStationService(routeState, stationId, station)
    snapAssignedTrainToStation(routeState, station)
    if isFreightRoute(routeState) then
        return runFreightLoading(routeState, stationId, station)
    end
    return runPassengerBoarding(routeState, stationId, station)
end

local function setStopPrompt(routeState, text)
    if not routeState then return end
    if text then
        if (not routeState.stopPromptVisible) or routeState.stopPromptText ~= text then
            TrainUI.ShowTextUI(text)
            routeState.stopPromptVisible = true
            routeState.stopPromptText = text
            routeState.reenterPromptVisible = false
            routeState.reenterPromptText = nil
        end
    elseif routeState.stopPromptVisible then
        TrainUI.HideTextUI()
        routeState.stopPromptVisible = false
        routeState.stopPromptText = nil
    end
end

local function setReenterPrompt(routeState, text)
    if not routeState then return end
    if routeState.stopPromptVisible then
        return
    end
    if text then
        if (not routeState.reenterPromptVisible) or routeState.reenterPromptText ~= text then
            TrainUI.ShowTextUI(text)
            routeState.reenterPromptVisible = true
            routeState.reenterPromptText = text
        end
    elseif routeState.reenterPromptVisible then
        TrainUI.HideTextUI()
        routeState.reenterPromptVisible = false
        routeState.reenterPromptText = nil
    end
end

local function clearRouteTextPrompts(routeState)
    if not routeState then
        TrainUI.HideTextUI()
        return
    end

    routeState.stopPromptVisible = false
    routeState.stopPromptText = nil
    routeState.reenterPromptVisible = false
    routeState.reenterPromptText = nil
    routeState.earlyFinishNoRewardConfirmUntilMs = nil
    TrainUI.HideTextUI()
end

getRouteEconomy = function(routeState)
    local panel = MetroClient and MetroClient.state and MetroClient.state.panelData
    local routes = panel and panel.routes or {}
    local routeId = tonumber(routeState and routeState.routeId)

    if type(routes) == 'table' then
        for _, route in ipairs(routes) do
            if tonumber(route.id) == routeId then
                return tonumber(route.stopReward) or 0, tonumber(route.completionReward or route.baseReward) or 0
            end
        end
    end

    local economy = Config.Economy or {}
    return tonumber(economy.stopReward) or 0, tonumber(Config.Payout.baseReward or economy.completionReward) or 0
end

local getNoRewardConfirmRemaining

local function buildHudStatus(routeState, station, distToStation)
    if not routeState then
        return 'Awaiting job data'
    end

    local confirmRemaining = getNoRewardConfirmRemaining(routeState)
    if confirmRemaining > 0 then
        return _L('hud_status_cancel_confirm', confirmRemaining)
    end

    if (routeState.cancelProgress or 0) > 0 then
        return _L('hud_status_cancelling', math.floor(routeState.cancelProgress or 0))
    end

    if routeState.currentStage == 'ready' then
        return _L('hud_status_ready_for_departure')
    end

    if routeState.isBoarding then
        if isFreightRoute(routeState) then
            return _L('freight_loading_title')
        end
        if string.lower(tostring(routeState.trainType or 'metro')) == 'metro' then
            return _L('hud_status_passengers_boarding')
        end
        return _L('hud_status_container_loading')
    end

    if routeState.reenterPromptVisible then
        return _L('hud_status_return_to_assigned_train')
    end

    if routeState.stopPromptVisible then
        if station and station.label then
            if isFreightRoute(routeState) then
                return _L('hud_status_position_freight_loading', station.label)
            end
            return _L('hud_status_position_vehicle', station.label)
        end
        return _L('hud_status_position_vehicle_plain')
    end

    if station and distToStation ~= nil then
        if distToStation <= 25.0 and not isFreightRoute(routeState) then
            return _L('hud_status_ready_for_departure')
        end
        if isFreightRoute(routeState) then
            return _L('hud_status_proceed_to_container_point', station.label)
        end
        return _L('hud_status_proceed_to_station', station.label)
    end

    return _L('hud_status_follow_route')
end

updateHud = function(routeState)
    if not MetroClient.state.hudVisible then return end
    local metroRuntimeCfg = getMetroRuntimeConfig()
    local hudRuntimeCfg = getHudRuntimeConfig()

    local stationId, station = getCurrentStation(routeState)
    if not station and routeState and routeState.currentStationIdx and routeState.stationOrder then
        local idx = math.max(1, math.min(routeState.currentStationIdx, #routeState.stationOrder))
        local fallbackStationId = routeState.stationOrder[idx]
        local stations = routeState.stations or getStationsByTrainType(routeState.trainType)
        station = stations and stations[fallbackStationId] or nil
        if routeState.lastHudFallbackLogAt == nil or (GetGameTimer() - routeState.lastHudFallbackLogAt) >= 3000 then
            routeState.lastHudFallbackLogAt = GetGameTimer()
            if station then
                Utils.DebugVerbose('hud_fallback_station', ('stationId=%s idx=%s'):format(tostring(fallbackStationId), tostring(idx)))
            else
                Utils.DebugVerbose('hud_fallback_missing_station', ('idx=%s'):format(tostring(idx)))
            end
        end
    end
    local vehicle = routeState.vehicle
    local vehicleCoords = vehicle and DoesEntityExist(vehicle) and GetEntityCoords(vehicle) or nil
    local vehicleSpeed = vehicle and DoesEntityExist(vehicle) and math.abs(GetEntitySpeed(vehicle)) or 0.0
    if routeState.currentStage == 'ready' and vehicleSpeed > metroRuntimeCfg.clearReadyStageSpeed then
        routeState.currentStage = nil
    end
    local stopCoords = station and getStationStopCoords(station) or nil
    local distToStation = (stopCoords and vehicleCoords) and #(vehicleCoords - stopCoords) or nil
    local currentStationNumber = math.min((routeState.goodStops or 0) + 1, #routeState.stationOrder)
    local penaltyAmount =
        ((routeState.missedStops or 0) * (tonumber(Config.Payout.missedStopPenalty) or 0)) +
        ((routeState.wrongStops or 0) * (tonumber(Config.Payout.wrongStopPenalty) or 0)) +
        (tonumber(routeState.dynamicPenaltyAmount) or 0)
    local isMetro = string.lower(tostring(routeState.trainType or 'metro')) == 'metro'
    local boardedCount = isMetro and (routeState.metroPassengerCount or routeState.boardedPassengers or 0) or (routeState.freightContainersLoaded or 0)
    local liveEarnings
    if isMetro then
        liveEarnings = tonumber(routeState.passengerRevenue) or 0
    else
        local containerReward = (Config.FreightPayout and Config.FreightPayout.containerReward) or 0
        liveEarnings = (tonumber(routeState.freightContainersLoaded) or 0) * containerReward
        if routeState.currentStationIdx > #routeState.stationOrder then
            local completionBonus = (Config.FreightPayout and Config.FreightPayout.completionBonus) or 0
            liveEarnings = liveEarnings + completionBonus
        end
    end
    local totalEarned = liveEarnings
    local cancelKey = hudRuntimeCfg.cancelKeyLabel
    local nowMs = GetGameTimer()
    local timeRemaining = math.max(0, math.floor(((routeState.routeDeadlineAt or 0) - nowMs) / 1000.0))
    local stageProgress = 0
    if (routeState.currentStage == 'boarding' or routeState.currentStage == 'loading')
        and routeState.stageStartedAt and routeState.stageDurationMs and routeState.stageDurationMs > 0 then
        local elapsed = math.max(0, nowMs - routeState.stageStartedAt)
        stageProgress = Utils.Clamp((elapsed / routeState.stageDurationMs) * 100.0, 0.0, 100.0)
    elseif routeState.currentStage == 'ready' then
        stageProgress = 100.0
    end
    local limitKmh = getActiveSpeedLimitKmh(routeState, vehicle)
    local _, speedUnitMultiplier, speedUnitLabel = getSpeedDisplayConfig(routeState)
    local speedLimitDisplay = nil
    if limitKmh and limitKmh > 0 then
        speedLimitDisplay = limitKmh * speedUnitMultiplier
    end
    local statusText = buildHudStatus(routeState, station, distToStation)
    if timeRemaining > 0 then
        statusText = ('%s | %s'):format(statusText, _L('hud_time_left', math.floor(timeRemaining / 60), timeRemaining % 60))
    elseif routeState.routeDeadlineAt then
        statusText = ('%s | %s'):format(statusText, _L('hud_late'))
    end

    local hudData = {
        title = string.lower(tostring(routeState.trainType or 'metro')) == 'metro' and _L('hud_title_metro') or _L('hud_title_train'),
        mode = isMetro and 'metro' or 'train',
        currentStage = routeState.currentStage,
        timeRemainingSec = timeRemaining,
        stageDurationMs = routeState.stageDurationMs or 0,
        stageProgress = Utils.Round(stageProgress, 1),
        nextStation = station and station.label or (stationId and tostring(stationId)) or _L('ui_hud_route_complete'),
        distanceToNext = Utils.Round(distToStation or 0, 1),
        stationCurrent = currentStationNumber,
        stationTotal = #routeState.stationOrder,
        speedLimit = speedLimitDisplay,
        speedUnit = speedUnitLabel,
        citySpeedActive = routeState.citySpeedZoneActive == true,
        citySpeedLabel = routeState.citySpeedZoneLabel or _L('ui_hud_city_zone'),
        cargoCount = boardedCount,
        liveEarnings = liveEarnings,
        totalEarned = totalEarned,
        penaltyAmount = penaltyAmount,
        status = statusText,
        cancelKey = cancelKey,
        cancelProgress = Utils.Round(routeState.cancelProgress or 0, 0),
        currentKm = Utils.Round(routeState.distanceKm, 2),
        targetKm = routeState.targetKm,
        totalMileage = Utils.Round(routeState.totalMileageEstimate, 2),
        stopsDone = routeState.goodStops,
        stopsTotal = #routeState.stationOrder,
        routeLabel = routeState.routeLabel,
        currentXp = (routeState.baseXp or 0) + (routeState.xpGained or 0),
        gainedXp = routeState.xpGained or 0
    }

    local hudSignature = table.concat({
        tostring(hudData.mode or ''),
        tostring(hudData.nextStation or ''),
        tostring(hudData.distanceToNext or 0),
        tostring(hudData.stationCurrent or 0),
        tostring(hudData.stationTotal or 0),
        tostring(hudData.speedLimit or 0),
        tostring(hudData.speedUnit or ''),
        tostring(hudData.citySpeedActive == true),
        tostring(hudData.cargoCount or 0),
        tostring(hudData.liveEarnings or 0),
        tostring(hudData.totalEarned or 0),
        tostring(hudData.penaltyAmount or 0),
        tostring(hudData.cancelProgress or 0),
        tostring(hudData.currentKm or 0),
        tostring(hudData.totalMileage or 0),
        tostring(hudData.currentXp or 0),
        tostring(hudData.gainedXp or 0),
        tostring(hudData.currentStage or ''),
        tostring(hudData.timeRemainingSec or 0),
        tostring(hudData.stageDurationMs or 0),
        tostring(hudData.stageProgress or 0),
        tostring(hudData.status or '')
    }, '|')
    local priorityHudSignature = table.concat({
        tostring(hudData.currentStage or ''),
        tostring(hudData.cancelProgress or 0),
        tostring(hudData.timeRemainingSec or 0),
        tostring(hudData.nextStation or ''),
        tostring(hudData.status or '')
    }, '|')

    if routeState.lastHudSignature == hudSignature then
        return
    end

    local nowTick = GetGameTimer()
    if routeState.lastHudSentAt and (nowTick - routeState.lastHudSentAt) < hudRuntimeCfg.minUpdateIntervalMs then
        if routeState.lastPriorityHudSignature == priorityHudSignature then
            routeState.lastHudSignature = hudSignature
            return
        end
    end

    routeState.lastHudSignature = hudSignature
    routeState.lastPriorityHudSignature = priorityHudSignature
    routeState.lastHudSentAt = nowTick
    SendNUIMessage({
        action = 'updateHud',
        data = hudData
    })
end

local function recoverMetroIfOffRoute(routeState, station, distToStation)
    if not routeState or not station then
        return false
    end

    local trainType = string.lower(tostring(routeState.trainType or ''))
    if trainType ~= 'metro' then
        return false
    end

    local veh = routeState.vehicle
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return false
    end

    if (routeState.manualTrainSpeed or 0.0) < -0.1 then
        routeState.offRouteSince = nil
        return false
    end

    local vehPos = GetEntityCoords(veh)
    local inWater = IsEntityInWater(veh)
    local hardOffRoute = inWater or vehPos.z < -5.0 or distToStation > 3000.0
    if not hardOffRoute then
        routeState.offRouteSince = nil
        return false
    end

    local now = GetGameTimer()
    routeState.offRouteSince = routeState.offRouteSince or now
    if (now - routeState.offRouteSince) < getMetroRuntimeConfig().offRouteRecoveryDelayMs then
        return false
    end

    SetTrainSpeed(routeState.vehicle, 0.0)
    SetTrainCruiseSpeed(routeState.vehicle, 0.0)
    routeState.manualTrainSpeed = 0.0
    local stopCoords = getStationStopCoords(station)
    SetEntityCoordsNoOffset(routeState.vehicle, stopCoords.x, stopCoords.y, stopCoords.z, false, false, false)
    SetEntityHeading(routeState.vehicle, getStationStopHeading(station) + 0.0)
    routeState.offRouteSince = nil
    ClientBridge.Notify(_L('metro_auto_recovered'), 'inform')
    return true
end

local function finishRoute(routeState)
    local routeCompleted = routeState.currentStationIdx > #routeState.stationOrder
    clearActiveCargoProp(routeState)
    setMetroDoors(routeState, false)

    TriggerServerEvent('godtrain:server:finishRoute', {
        distance = routeState.distanceKm,
        totalStops = #routeState.stationOrder,
        goodStops = routeState.goodStops,
        missedStops = routeState.missedStops,
        wrongStops = routeState.wrongStops,
        routeCompleted = routeCompleted,
        passengerRevenue = routeState.passengerRevenue or 0,
        totalPassengerTrips = routeState.totalPassengerTrips or 0,
        lateSeconds = math.max(0, math.floor((GetGameTimer() - (routeState.routeDeadlineAt or GetGameTimer())) / 1000.0)),
        speedingSeconds = routeState.speedingSeconds or 0,
        hardBrakeEvents = routeState.hardBrakeEvents or 0,
        derailRiskEvents = routeState.derailRiskEvents or 0,
        penaltyAmount = routeState.dynamicPenaltyAmount or 0
    })

    if Config.Vehicle.deleteOnFinish and routeState.vehicle and DoesEntityExist(routeState.vehicle) then
        cleanupAttachedVehicles(routeState)
        safeDeleteTrain(routeState.vehicle)
    end

    clearMetroPassengerPeds(routeState)
    clearSpawnedStationPassengers()
    clearFreightContainers(routeState)
    clearRouteGuidance(routeState)
end

local function updateRouteConditions(routeState)
    if not routeState or not routeState.vehicle or not DoesEntityExist(routeState.vehicle) then
        return
    end

    local nowTick = GetGameTimer()
    local lastTick = tonumber(routeState.lastConditionTickAt) or nowTick
    local deltaSec = math.max(0.01, (nowTick - lastTick) / 1000.0)
    routeState.lastConditionTickAt = nowTick

    local vehSpeedKmh = GetEntitySpeed(routeState.vehicle) * 3.6
    local trainType = string.lower(tostring(routeState.trainType or 'metro'))
    local ruleCfg = getRouteRuleConfig(trainType)
    local notifyRuntimeCfg = getNotificationRuntimeConfig()

    local shouldRecalcCityZone = (routeState.lastCityZoneEvalAt == nil) or ((nowTick - routeState.lastCityZoneEvalAt) >= 250)
    if shouldRecalcCityZone and trainType == 'freight' then
        routeState.lastCityZoneEvalAt = nowTick
        routeState.dynamicSpeedLimitKmh = nil
        routeState.citySpeedZoneLabel = nil
        local zones = ruleCfg.cityZones or {}
        local vehPos = GetEntityCoords(routeState.vehicle)
        local insideZoneLabel = nil
        for _, zone in ipairs(zones) do
            local center = zone.center
            local radius = tonumber(zone.radius) or 0.0
            if center and radius > 0.0 and #(vehPos - center) <= radius then
                routeState.dynamicSpeedLimitKmh = tonumber(zone.speedLimitKmh) or tonumber(ruleCfg.citySpeedLimitKmh)
                insideZoneLabel = zone.label or _L('ui_hud_city_zone')
                break
            end
        end

        local wasInZone = routeState.citySpeedZoneActive == true
        local isInZone = routeState.dynamicSpeedLimitKmh ~= nil
        if isInZone and not wasInZone then
            routeState.citySpeedZoneActive = true
            routeState.citySpeedZoneLabel = insideZoneLabel or _L('ui_hud_city_zone')
            local _, _, _, _, unitNotify = getSpeedDisplayConfig(routeState)
            ClientBridge.Notify(_L('speed_zone_entered', insideZoneLabel or _L('ui_hud_city_zone'), math.floor(convertKmhToConfiguredUnit(routeState, routeState.dynamicSpeedLimitKmh)), unitNotify), 'inform')
        elseif wasInZone and not isInZone then
            routeState.citySpeedZoneActive = false
            routeState.citySpeedZoneLabel = nil
            ClientBridge.Notify(_L('speed_zone_left'), 'inform')
        elseif isInZone then
            routeState.citySpeedZoneLabel = insideZoneLabel or _L('ui_hud_city_zone')
        end
    end

    local stationId, station = getCurrentStation(routeState)
    local stationLimitKmh = nil
    local stationLimitActive = false
    if station and routeState.vehicle and DoesEntityExist(routeState.vehicle) then
        local approachPenaltyCfg = getPenaltyConfig(routeState.trainType)
        local stopCoords = getStationStopCoords(station)
        local distToStop = #(GetEntityCoords(routeState.vehicle) - stopCoords)
        local arrivalLimitKmh = getArrivalSpeedLimitKmh(routeState, approachPenaltyCfg)
        local autoBrakeDistance = tonumber(ruleCfg.stationApproachAutoBrakeDistance) or tonumber(approachPenaltyCfg.stationArrivalSpeedTriggerDistance) or 28.0
        local releaseDistance = tonumber(ruleCfg.stationApproachReleaseDistance) or math.max(24.0, autoBrakeDistance + 12.0)
        local sameStationActive = tostring(routeState.stationApproachLimitStationId or '') == tostring(stationId or '')
        if distToStop <= autoBrakeDistance then
            stationLimitKmh = arrivalLimitKmh
            stationLimitActive = true
            routeState.stationApproachLimitStationId = stationId
        elseif sameStationActive and distToStop <= releaseDistance then
            stationLimitKmh = arrivalLimitKmh
            stationLimitActive = true
        else
            routeState.stationApproachLimitStationId = nil
        end
    else
        routeState.stationApproachLimitStationId = nil
    end
    routeState.stationApproachLimitKmh = stationLimitKmh
    routeState.stationApproachLimitActive = stationLimitActive

    local speedLimitKmh = getActiveSpeedLimitKmh(routeState, routeState.vehicle)
    local speedLimitDisplay = convertKmhToConfiguredUnit(routeState, speedLimitKmh)
    local penaltyCfg = getPenaltyConfig(routeState.trainType)
    local tolerance = getSpeedingToleranceKmh(routeState, penaltyCfg)
    if speedLimitKmh and vehSpeedKmh > (speedLimitKmh + tolerance + 0.01) then
        routeState.speedingSeconds = (routeState.speedingSeconds or 0) + deltaSec
        if not routeState.lastSpeedingNotifyAt or (nowTick - routeState.lastSpeedingNotifyAt) > notifyRuntimeCfg.speedingWarningCooldownMs then
            routeState.lastSpeedingNotifyAt = nowTick
            local _, _, _, _, unitNotify = getSpeedDisplayConfig(routeState)
            ClientBridge.Notify(_L('speed_limit_warning', math.floor(speedLimitDisplay), unitNotify), 'error')
        end
    end

    local prevSpeedKmh = tonumber(routeState.prevSpeedKmh) or vehSpeedKmh
    local deltaDrop = prevSpeedKmh - vehSpeedKmh
    if deltaDrop >= (tonumber(penaltyCfg.hardBrakeDeltaKmh) or 999.0) then
        routeState.hardBrakeEvents = (routeState.hardBrakeEvents or 0) + 1
    end
    routeState.prevSpeedKmh = vehSpeedKmh

    local lateSeconds = 0
    if routeState.routeDeadlineAt and nowTick > routeState.routeDeadlineAt then
        lateSeconds = math.max(0, math.floor((nowTick - routeState.routeDeadlineAt) / 1000.0))
    end

    routeState.dynamicPenaltyAmount =
        (lateSeconds > 0 and ((tonumber(penaltyCfg.latePenaltyOnce) or 0) + math.floor((lateSeconds / 60.0) * (tonumber(penaltyCfg.latePenaltyPerMinute) or 0))) or 0) +
        math.floor((routeState.speedingSeconds or 0) * (tonumber(penaltyCfg.speedPenaltyPerSecond) or 0)) +
        ((routeState.hardBrakeEvents or 0) * (tonumber(penaltyCfg.hardBrakePenalty) or 0)) +
        ((routeState.derailRiskEvents or 0) * (tonumber(penaltyCfg.derailRiskPenalty) or 0)) +
        ((routeState.stationArrivalSpeedViolations or 0) * (tonumber(penaltyCfg.stationArrivalSpeedPenalty) or 0))
end

local function abortActiveRoute(routeState)
    return abortActiveRouteWithMode(routeState, false)
end

local function getCompletedStopCount(routeState)
    if not routeState then
        return 0
    end

    return math.max(0, tonumber(routeState.goodStops or 0) + tonumber(routeState.missedStops or 0))
end

getNoRewardConfirmRemaining = function(routeState)
    if not routeState then
        return 0
    end

    local expiresAt = tonumber(routeState.earlyFinishNoRewardConfirmUntilMs) or 0
    if expiresAt <= 0 then
        return 0
    end

    return math.max(0, math.ceil((expiresAt - GetGameTimer()) / 1000.0))
end

abortActiveRouteWithMode = function(routeState, forceNoReward)
    clearRouteTextPrompts(routeState)
    clearActiveCargoProp(routeState)
    setMetroDoors(routeState, false)
    TriggerServerEvent('godtrain:server:finishRoute', {
        distance = routeState.distanceKm,
        totalStops = #routeState.stationOrder,
        goodStops = routeState.goodStops,
        missedStops = routeState.missedStops,
        wrongStops = routeState.wrongStops,
        routeCompleted = false,
        earlyExit = true,
        passengerRevenue = routeState.passengerRevenue or 0,
        totalPassengerTrips = routeState.totalPassengerTrips or 0,
        lateSeconds = math.max(0, math.floor((GetGameTimer() - (routeState.routeDeadlineAt or GetGameTimer())) / 1000.0)),
        speedingSeconds = routeState.speedingSeconds or 0,
        hardBrakeEvents = routeState.hardBrakeEvents or 0,
        derailRiskEvents = routeState.derailRiskEvents or 0,
        penaltyAmount = routeState.dynamicPenaltyAmount or 0,
        forceNoReward = forceNoReward == true
    })

    if Config.Vehicle.deleteOnFinish and routeState.vehicle and DoesEntityExist(routeState.vehicle) then
        cleanupAttachedVehicles(routeState)
        safeDeleteTrain(routeState.vehicle)
    end
    local teleportCoords = getEarlyExitTeleportConfig(routeState)
    local ped = PlayerPedId()
    if teleportCoords and ped and ped ~= 0 and DoesEntityExist(ped) then
        SetEntityCoordsNoOffset(ped, teleportCoords.x + 0.0, teleportCoords.y + 0.0, teleportCoords.z + 0.5, false, false, false)
        SetEntityHeading(ped, (tonumber(teleportCoords.w) or GetEntityHeading(ped)) + 0.0)
    end

    clearMetroPassengerPeds(routeState)
    clearSpawnedStationPassengers()
    clearFreightContainers(routeState)
    clearRouteGuidance(routeState)
    MetroClient.state.activeRoute = nil
    return true
end

local function tryEarlyFinishRoute(routeState, triggerType)
    if routeState.earlyFinishDialogOpen then
        return false
    end

    local isMetroRoute = string.lower(tostring(routeState.trainType or '')) == 'metro'
    local completedStops = getCompletedStopCount(routeState)
    local now = GetGameTimer()
    local earlyFinishCfg = Config.EarlyFinish or {}
    local modeCfg = earlyFinishCfg[isMetroRoute and 'metro' or 'freight'] or {}
    local trigger = string.lower(tostring(triggerType or 'hold'))
    local instantHoldFinish = modeCfg.instantHoldFinish == true
    local forceNoRewardOnHold = modeCfg.forceNoRewardOnHold ~= false
    local normalAllowedAfterCompletedStops = math.max(0, tonumber(modeCfg.normalAllowedAfterCompletedStops) or 0)
    local confirmWindowMs = math.max(1000, tonumber(modeCfg.noRewardConfirmWindowMs) or 8000)
    local allowNoRewardBeforeThreshold = modeCfg.allowNoRewardBeforeThreshold == true

    if trigger == 'hold' and instantHoldFinish then
        routeState.earlyFinishNoRewardConfirmUntilMs = nil
        return abortActiveRouteWithMode(routeState, forceNoRewardOnHold)
    end

    if completedStops < normalAllowedAfterCompletedStops then
        if not allowNoRewardBeforeThreshold then
            ClientBridge.Notify(_L('early_finish_locked_until_stop', normalAllowedAfterCompletedStops), 'error')
            return false
        end

        local confirmUntil = tonumber(routeState.earlyFinishNoRewardConfirmUntilMs) or 0
        if confirmUntil > now then
            routeState.earlyFinishNoRewardConfirmUntilMs = nil
            return abortActiveRouteWithMode(routeState, true)
        end

        routeState.earlyFinishNoRewardConfirmUntilMs = now + confirmWindowMs
        ClientBridge.Notify(_L('early_finish_no_reward_confirm_again', normalAllowedAfterCompletedStops), 'early_exit')
        local remainingSec = getNoRewardConfirmRemaining(routeState)
        if remainingSec > 0 then
            TrainUI.ShowTextUI(_L('cancel_confirm_prompt', remainingSec))
        end
        return false
    end

    routeState.earlyFinishNoRewardConfirmUntilMs = nil

    routeState.earlyFinishDialogOpen = true

    local previewResponse = lib.callback.await('godtrain:server:getEarlyFinishPreview', false, {
        distance = routeState.distanceKm,
        goodStops = routeState.goodStops,
        missedStops = routeState.missedStops,
        wrongStops = routeState.wrongStops
    })

    if not previewResponse or not previewResponse.ok or not previewResponse.data then
        routeState.earlyFinishDialogOpen = false
        ClientBridge.Notify((previewResponse and previewResponse.message) or _L('early_finish_preview_failed'), 'error')
        return false
    end

    local preview = previewResponse.data
    local minStops = preview.minStopsForEarlyFinish or 0
    local previewPayout = tonumber(preview.payout) or 0
    local warningLine = ''
    if preview.partialBlockedByMinStops and minStops > 0 then
        warningLine = _L('early_finish_preview_warning_min_stops', minStops)
    elseif preview.earlyExitNoPayout then
        warningLine = _L('early_finish_preview_warning_no_payout')
    else
        warningLine = _L('early_finish_preview_info_partial')
    end

    local message = ([[
### %s

- **%s:** %s/%s
- **%s:** %s
- **%s:** **$%s**
%s

%s
]]):format(
        routeState.routeLabel or _L('route_generic_label'),
        _L('early_finish_preview_completed_stops'),
        preview.completedStops or 0,
        preview.routeStops or 0,
        _L('early_finish_preview_remaining_stops'),
        preview.remainingStops or 0,
        _L('early_finish_preview_estimated_payout'),
        previewPayout,
        warningLine,
        _L('early_finish_preview_confirm_question')
    )

    local decision = TrainUI.Dialog({
        header = _L('early_finish_title'),
        content = message,
        centered = true,
        cancel = true,
        labels = {
            confirm = _L('early_finish_confirm'),
            cancel = _L('early_finish_cancel')
        }
    })

    routeState.earlyFinishDialogOpen = false

    if decision ~= 'confirm' then
        return false
    end

    return abortActiveRoute(routeState)
end

local function jobLoop(routeState)
    local runtimeCfg = routeState.runtimeCfg or {}
    local lastPos = GetEntityCoords(routeState.vehicle)
    local lastHudTick = 0
    local wasInAssignedVehicle = true
    local exitGraceStartedAt = nil
    local exitPopupShown = false
    local exitGraceMs = runtimeCfg.exitGraceMs or 9000
    local isMetroRoute = string.lower(tostring(routeState.trainType or '')) == 'metro'
    local reenterDistance = runtimeCfg.reenterDistance or 14.0
    local exitPopupDistance = runtimeCfg.exitPopupDistance or 24.0
    local reenterEnterTimeoutMs = runtimeCfg.reenterEnterTimeoutMs or 6000
    local cancelHoldMs = runtimeCfg.cancelHoldMs or 5000
    local activeWait = runtimeCfg.activeWait or Config.Performance.activeWait
    local uiTickMs = runtimeCfg.uiTickMs or Config.Performance.uiTickMs or 500
    local markerCfg = runtimeCfg.marker or Config.Marker or {}
    local markerInsideColor = markerCfg.insideColor or {}
    local markerOutsideColor = markerCfg.outsideColor or {}
    local markerAlpha = tonumber(markerCfg.alpha) or 140
    local markerBoxZOffset = tonumber(markerCfg.boxZOffset) or 0.03
    local markerCircleZOffset = tonumber(markerCfg.circleZOffset) or -1.2
    local markerHysteresis = tonumber(markerCfg.hysteresis) or 0.45
    local radiusMultiplier = runtimeCfg.stopRadiusMultiplier or 1.0
    local boardingCfg = runtimeCfg.passengerBoarding or Config.PassengerBoarding or {}
    local boardingEnabled = boardingCfg.enabled == true
    local maxStopSpeed = runtimeCfg.maxStopSpeed or 1.5
    local stopInputCooldownMs = tonumber((Config.Boarding and Config.Boarding.inputCooldownMs)) or tonumber(boardingCfg.inputCooldownMs) or 350
    local reenterPromptKey = runtimeCfg.reenterPromptKey or (isMetroRoute and 'metro_reenter_prompt' or 'train_reenter_prompt')

    while MetroClient.state.activeRoute == routeState do
        Wait(activeWait)
        local nowTick = GetGameTimer()

        if not DoesEntityExist(routeState.vehicle) then
            ClientBridge.Notify(_L('assigned_vehicle_missing'), 'error')
            cleanupAttachedVehicles(routeState)
            clearRouteGuidance(routeState)
            MetroClient.state.activeRoute = nil
            break
        end

        local ped = PlayerPedId()
        local currentVehicle = GetVehiclePedIsIn(ped, false)
        local inAssignedVehicle = isVehiclePartOfAssignedTrain(routeState, currentVehicle)
        local vehicleCoords = GetEntityCoords(routeState.vehicle)
        local pedCoords = GetEntityCoords(ped)
        local distToAssignedTrain = #(pedCoords - vehicleCoords)

        if wasInAssignedVehicle and not inAssignedVehicle and DoesEntityExist(routeState.vehicle) then
            exitGraceStartedAt = nowTick
            exitPopupShown = false
        end

        if inAssignedVehicle then
            exitGraceStartedAt = nil
            exitPopupShown = false
            routeState.reenterAttemptStartedAt = nil
            routeState.reenterAttemptPending = false
            setReenterPrompt(routeState, nil)
        end

        if not inAssignedVehicle and DoesEntityExist(routeState.vehicle) and distToAssignedTrain <= reenterDistance then
            setReenterPrompt(routeState, _L(reenterPromptKey))
            if IsControlJustReleased(0, Config.Keys.VehicleExitEnter or 23) then
                routeState.reenterAttemptStartedAt = nowTick
                routeState.reenterAttemptPending = true
                ClearPedTasks(ped)
                TaskEnterVehicle(ped, routeState.vehicle, reenterEnterTimeoutMs, -1, 1.5, 1, 0)
            end
        else
            setReenterPrompt(routeState, nil)
        end

        if inAssignedVehicle then
            if IsControlPressed(0, 47) then
                routeState.cancelHoldStartedAt = routeState.cancelHoldStartedAt or nowTick
            else
                routeState.cancelHoldStartedAt = nil
            end
        else
            routeState.cancelHoldStartedAt = nil
        end

        local cancelProgress = 0
        local cancelHudDirty = false
        if (tonumber(routeState.earlyFinishNoRewardConfirmUntilMs) or 0) > 0 and nowTick >= tonumber(routeState.earlyFinishNoRewardConfirmUntilMs) then
            routeState.earlyFinishNoRewardConfirmUntilMs = nil
            if not routeState.stopPromptVisible and not routeState.reenterPromptVisible then
                TrainUI.HideTextUI()
            end
            cancelHudDirty = true
        end
        if routeState.cancelHoldStartedAt then
            cancelProgress = Utils.Clamp(((nowTick - routeState.cancelHoldStartedAt) / cancelHoldMs) * 100.0, 0.0, 100.0)
            cancelHudDirty = math.abs((routeState.cancelProgress or 0) - cancelProgress) >= 0.5
            if cancelProgress >= 100.0 then
                routeState.cancelHoldStartedAt = nil
                routeState.cancelProgress = 100.0
                if tryEarlyFinishRoute(routeState, 'hold') then
                    break
                end
                cancelProgress = 0
                cancelHudDirty = true
            end
        end
        if routeState.cancelProgress and routeState.cancelProgress > 0 and cancelProgress == 0 then
            cancelHudDirty = true
        end
        routeState.cancelProgress = cancelProgress

        local confirmRemaining = getNoRewardConfirmRemaining(routeState)
        if confirmRemaining > 0 and not routeState.stopPromptVisible and not routeState.reenterPromptVisible then
            TrainUI.ShowTextUI(_L('cancel_confirm_prompt', confirmRemaining))
        end

        if routeState.reenterAttemptPending and not inAssignedVehicle then
            local attemptStartedAt = routeState.reenterAttemptStartedAt or nowTick
            if (nowTick - attemptStartedAt) >= reenterEnterTimeoutMs then
                TaskWarpPedIntoVehicle(ped, routeState.vehicle, -1)
                routeState.reenterAttemptPending = false
                routeState.reenterAttemptStartedAt = nil
            end
        end

        if not inAssignedVehicle and not exitPopupShown and exitGraceStartedAt and DoesEntityExist(routeState.vehicle) then
            local elapsedOutside = nowTick - exitGraceStartedAt
            if elapsedOutside >= exitGraceMs and distToAssignedTrain >= exitPopupDistance then
                exitPopupShown = true
                if tryEarlyFinishRoute(routeState, 'auto') then
                    break
                end
            end
        end

        wasInAssignedVehicle = inAssignedVehicle

        if not IsPedInAnyVehicle(ped, false) then
            if not routeState.lastOutOfVehicleNotify or (nowTick - routeState.lastOutOfVehicleNotify) > 3000 then
                routeState.lastOutOfVehicleNotify = nowTick
                ClientBridge.Notify(_L('return_to_vehicle_to_continue'), 'error')
            end
        end

        if isTrainServiceLocked(routeState) then
            DisableControlAction(0, Config.Keys.TrainSpeedUp or 71, true)
            DisableControlAction(0, Config.Keys.TrainSpeedDown or 72, true)
            DisableControlAction(0, Config.Keys.TrainEmergencyBrake or 73, true)
            DisableControlAction(0, Config.Keys.TrainBrake or 22, true)
            routeState.manualTrainSpeed = 0.0
            SetTrainSpeed(routeState.vehicle, 0.0)
            SetTrainCruiseSpeed(routeState.vehicle, 0.0)
        end

        local pauseActive = IsPauseMenuActive()
        if pauseActive ~= routeState.pauseMenuVisible then
            routeState.pauseMenuVisible = pauseActive
            SendNUIMessage({ action = 'setHudVisible', visible = (not pauseActive) and MetroClient.state.hudVisible })
        end

        updateMetroDriveContext(routeState)
        updateRouteConditions(routeState)
        cleanupStrayMetroNpcs(routeState, false)
        updateTrainControls(routeState)
        applyMetroDerailGuard(routeState)
        keepVehicleFuelFull(routeState)

        local vehPos = GetEntityCoords(routeState.vehicle)
        local stepDist = #(vehPos - lastPos)
        lastPos = vehPos

        routeState.distanceKm = routeState.distanceKm + (stepDist / 1000.0)
        routeState.totalMileageEstimate = routeState.baseTotalKm + routeState.distanceKm

        local stationId, station = getCurrentStation(routeState)
        if not station then
            finishRoute(routeState)
            MetroClient.state.activeRoute = nil
            break
        end

        refreshRouteGuidance(routeState)

        local effectiveStopRadius = (tonumber(station.stopRadius) or 12.0) * math.max(0.1, radiusMultiplier)
        local boardingStopRadius = effectiveStopRadius
        local stopCoords = getStationStopCoords(station)
        local stopHeading = getStationStopHeading(station)

        local dist = #(vehPos - stopCoords)
        local box = station.stopBox
        local insideZone = false
        local markerType = tonumber(station.zoneMarkerType) or (box and 43 or 1)
        local markerSizeX, markerSizeY, markerSizeZ
        local markerPosZ = stopCoords.z
        local markerRotZ = stopHeading
        local groundFound, groundZ = GetGroundZFor_3dCoord(stopCoords.x, stopCoords.y, stopCoords.z + 3.0, false)
        local markerBaseZ = groundFound and (groundZ + 0.02) or stopCoords.z

        if box then
            local rad = math.rad(-stopHeading)
            local cosH = math.cos(rad)
            local sinH = math.sin(rad)

            local dx = vehPos.x - stopCoords.x
            local dy = vehPos.y - stopCoords.y
            local dz = vehPos.z - stopCoords.z

            local localX = (dx * cosH) - (dy * sinH)
            local localY = (dx * sinH) + (dy * cosH)

            local halfX = (tonumber(box.x) or (effectiveStopRadius * 2.0)) * 0.5
            local halfY = (tonumber(box.y) or (effectiveStopRadius * 2.0)) * 0.5
            local halfZ = (tonumber(box.z) or 4.0) * 0.5
            local zTolerance = tonumber(station.stopBoxToleranceZ)
                or tonumber((Config.MetroStopZone and Config.MetroStopZone.toleranceZ))
                or tonumber((Config.TrainStopZone and Config.TrainStopZone.toleranceZ))
                or 2.0
            local allowedZ = math.max(halfZ, zTolerance)

            local rawInside = math.abs(localX) <= halfX and math.abs(localY) <= halfY and math.abs(dz) <= allowedZ
            local zoneState = routeState.stationZoneInsideStable or {}
            local wasInside = zoneState[stationId] == true
            local exitHalfX = halfX + markerHysteresis
            local exitHalfY = halfY + markerHysteresis
            local exitAllowedZ = allowedZ + markerHysteresis

            if wasInside then
                insideZone = math.abs(localX) <= exitHalfX and math.abs(localY) <= exitHalfY and math.abs(dz) <= exitAllowedZ
            else
                insideZone = rawInside
            end

            zoneState[stationId] = insideZone
            routeState.stationZoneInsideStable = zoneState

            markerSizeX = halfX * 2.0
            markerSizeY = halfY * 2.0
            markerSizeZ = halfZ * 2.0
            markerPosZ = markerBaseZ + halfZ + markerBoxZOffset
        else
            insideZone = dist <= boardingStopRadius
            local markerDiameter = math.max(5.0, effectiveStopRadius * 2.0)
            markerSizeX = markerDiameter
            markerSizeY = markerDiameter
            markerSizeZ = 1.5
            markerPosZ = markerBaseZ + markerCircleZOffset
            markerRotZ = 0.0
        end

        local markerR = insideZone and (tonumber(markerInsideColor.r) or 0) or (tonumber(markerOutsideColor.r) or 255)
        local markerG = insideZone and (tonumber(markerInsideColor.g) or 255) or (tonumber(markerOutsideColor.g) or 60)
        local markerB = insideZone and (tonumber(markerInsideColor.b) or 120) or (tonumber(markerOutsideColor.b) or 60)
        routeState.activeMarker = {
            markerType = markerType,
            x = stopCoords.x,
            y = stopCoords.y,
            z = markerPosZ,
            rotZ = markerRotZ,
            sizeX = markerSizeX,
            sizeY = markerSizeY,
            sizeZ = markerSizeZ,
            r = markerR,
            g = markerG,
            b = markerB,
            a = markerAlpha
        }
        if isFreightRoute(routeState) and not station.isSkipping and routeState.currentStationIdx < #routeState.stationOrder then
            ensureCargoPropAtStation(routeState, stationId, station)
        elseif routeState.activeCargoStationId == stationId then
            clearActiveCargoProp(routeState)
        end
        if dist <= (boardingStopRadius + 16.0) then
            routeState.stationApproached[stationId] = true
        end
        if routeState.stationApproached[stationId] and not routeState.stationArrivalSpeedChecked[stationId] then
            local penaltyCfg = getPenaltyConfig(routeState.trainType)
            local arrivalPenalty = tonumber(penaltyCfg.stationArrivalSpeedPenalty) or 0
            if arrivalPenalty > 0 then
                local triggerDistance = tonumber(penaltyCfg.stationArrivalSpeedTriggerDistance) or (boardingStopRadius + 16.0)
                if dist <= triggerDistance then
                    routeState.stationArrivalSpeedChecked[stationId] = true
                    local arrivalLimitKmh = getArrivalSpeedLimitKmh(routeState, penaltyCfg)
                    local toleranceKmh = getSpeedingToleranceKmh(routeState, penaltyCfg)
                    local currentSpeedKmh = math.abs(GetEntitySpeed(routeState.vehicle)) * 3.6
                    if currentSpeedKmh > (arrivalLimitKmh + toleranceKmh) then
                        routeState.stationArrivalSpeedViolations = (routeState.stationArrivalSpeedViolations or 0) + 1
                        local speedDisplay = math.floor(convertKmhToConfiguredUnit(routeState, arrivalLimitKmh))
                        local _, _, _, _, unitNotify = getSpeedDisplayConfig(routeState)
                        ClientBridge.Notify(_L('arrival_speed_penalty', speedDisplay, unitNotify, arrivalPenalty), 'error')
                    end
                end
            end
        end

        local promptEnterDist = boardingStopRadius + 4.0
        local promptExitDist = boardingStopRadius + 7.0
        local speed = math.abs(GetEntitySpeed(routeState.vehicle))
        local inPromptZone = box and insideZone or dist <= promptEnterDist
        local arrivedReady = isMetroArrivalReady(routeState, station, insideZone, dist)
        updateMetroArrivalDoors(routeState, stationId, station, arrivedReady)
        local keepPromptZone = box and insideZone or (routeState.stopPromptVisible and dist <= promptExitDist)
        local canShowStopPrompt = (inPromptZone or keepPromptZone) and speed <= maxStopSpeed
        local canManualStopNow = not routeState.isBoarding
            and not station.isSkipping
            and stationStopAcceptedImmediate(routeState, station, insideZone, dist)
        local canAutoStartMetroBoarding = isMetroAutoBoardEnabled(routeState)
            and arrivedReady
            and not routeState.isBoarding
            and stationStopAccepted(routeState, station)

        if station.isSkipping then
            setStopPrompt(routeState, nil)
            routeState.stationAutoBoardReadyAt = nil
            routeState.stationAutoBoardStarted = nil
            if dist <= boardingStopRadius then
                advanceSkippingStation(routeState, station)
            elseif routeState.stationApproached[stationId] and dist > (effectiveStopRadius + 70.0) and not routeState.stationMissed[stationId] then
                routeState.stationMissed[stationId] = true
                advanceSkippingStation(routeState, station)
            end
            goto continue_station_loop
        end

        if canAutoStartMetroBoarding then
            if routeState.stationAutoBoardStarted ~= stationId then
                routeState.stationAutoBoardReadyAt = routeState.stationAutoBoardReadyAt or (nowTick + 50)
                passengerBoardingDebug(routeState, 'auto_board_ready', ('station=%s dist=%.2f speed=%.2f inside=%s'):format(tostring(stationId), tonumber(dist or 0.0), tonumber(speed or 0.0), tostring(insideZone == true)))
            end

            if routeState.stationAutoBoardStarted ~= stationId and nowTick >= tonumber(routeState.stationAutoBoardReadyAt or 0) then
                routeState.stationAutoBoardReadyAt = nil
                routeState.nextStopInputAt = nowTick + stopInputCooldownMs
                setStopPrompt(routeState, nil)
                if runStationService(routeState, stationId, station) then
                    routeState.stationAutoBoardStarted = stationId
                    passengerBoardingDebug(routeState, 'auto_board_started', ('station=%s'):format(tostring(stationId)))
                    completeStationStop(routeState, station)
                    goto continue_station_loop
                else
                    passengerBoardingDebug(routeState, 'auto_board_failed', ('station=%s inside=%s arrived=%s stopped=%s'):format(tostring(stationId), tostring(insideZone == true), tostring(arrivedReady == true), tostring(speed <= maxStopSpeed)))
                end
            end
        else
            if isPassengerBoardingDebugEnabled(routeState) and string.lower(tostring(routeState.trainType or 'metro')) == 'metro' and not station.isSkipping then
                local autoWaitSig = ('%s:%s:%s:%s:%s'):format(tostring(stationId), tostring(insideZone == true), tostring(arrivedReady == true), tostring(canShowStopPrompt == true), tostring(math.floor((tonumber(speed or 0.0) * 10.0) + 0.5)))
                if routeState.boardingDebugLastAutoWaitSig ~= autoWaitSig or nowTick >= tonumber(routeState.boardingDebugLastAutoWaitAt or 0) then
                    routeState.boardingDebugLastAutoWaitSig = autoWaitSig
                    routeState.boardingDebugLastAutoWaitAt = nowTick + 1000
                    passengerBoardingDebug(routeState, 'auto_board_wait', ('station=%s inside=%s arrived=%s prompt=%s speed=%.2f'):format(tostring(stationId), tostring(insideZone == true), tostring(arrivedReady == true), tostring(canShowStopPrompt == true), tonumber(speed or 0.0)))
                end
            end
            routeState.stationAutoBoardReadyAt = nil
        end

        local confirmPressed = IsControlJustReleased(0, Config.Keys.StopConfirm)
            or IsDisabledControlJustReleased(0, Config.Keys.StopConfirm)

        if canShowStopPrompt then
            if boardingEnabled then
                if isFreightRoute(routeState) then
                    setStopPrompt(routeState, ('[E] %s (%s)'):format(_L('freight_loading_title'), station.label))
                else
                    setStopPrompt(routeState, _L('stop_prompt_board', station.label))
                end
            else
                setStopPrompt(routeState, _L('stop_prompt_plain', station.label))
            end

            local nextAllowedInputAt = tonumber(routeState.nextStopInputAt) or 0
            local canProcessInput = nowTick >= nextAllowedInputAt

            if canProcessInput and confirmPressed then
                if not canManualStopNow then
                    goto continue_stop_prompt
                end

                routeState.nextStopInputAt = nowTick + stopInputCooldownMs
                setStopPrompt(routeState, nil)
                if boardingEnabled then
                    if runStationService(routeState, stationId, station) then
                        routeState.stationAutoBoardStarted = stationId
                        routeState.stationAutoBoardReadyAt = nil
                        completeStationStop(routeState, station)
                    end
                else
                    routeState.stationAutoBoardStarted = stationId
                    routeState.stationAutoBoardReadyAt = nil
                    setStopPrompt(routeState, nil)
                    completeStationStop(routeState, station)
                end
            end
            ::continue_stop_prompt::
        elseif boardingEnabled and canManualStopNow and nowTick >= tonumber(routeState.nextStopInputAt or 0) and confirmPressed then
            routeState.nextStopInputAt = nowTick + stopInputCooldownMs
            setStopPrompt(routeState, nil)
            if runStationService(routeState, stationId, station) then
                routeState.stationAutoBoardStarted = stationId
                routeState.stationAutoBoardReadyAt = nil
                completeStationStop(routeState, station)
            end
        else
            setStopPrompt(routeState, nil)
            routeState.stationAutoBoardReadyAt = nil
            if routeState.stationApproached[stationId] and dist > (effectiveStopRadius + 70.0) and not routeState.stationMissed[stationId] then
                routeState.stationMissed[stationId] = true
                routeState.missedStops = routeState.missedStops + 1
                TriggerServerEvent('godtrain:server:recordStop', 'missed', stationId)
                routeState.currentStationIdx = routeState.currentStationIdx + 1
                ClientBridge.Notify(_L('stop_missed'), 'error')
            end
        end

        if (nowTick - lastHudTick) >= uiTickMs then
            if routeState.lastVerboseTickLogAt == nil or (nowTick - routeState.lastVerboseTickLogAt) >= 1000 then
                Utils.DebugVerbose(
                    'route_tick',
                    ('route=%s station=%s dist=%.2f speed=%.2f inside=%s good=%s missed=%s wrong=%s'):format(
                        tostring(routeState.routeId or '?'),
                        tostring(stationId or '?'),
                        tonumber(dist or 0),
                        tonumber(speed or 0),
                        tostring(insideZone == true),
                        tostring(routeState.goodStops or 0),
                        tostring(routeState.missedStops or 0),
                        tostring(routeState.wrongStops or 0)
                    )
                )
                routeState.lastVerboseTickLogAt = nowTick
            end
            updateHud(routeState)
            lastHudTick = nowTick
        elseif cancelHudDirty then
            updateHud(routeState)
        end
        ::continue_station_loop::
    end

    clearRouteTextPrompts(routeState)
    routeState.activeMarker = nil
    setMetroDoors(routeState, false)
    clearActiveCargoProp(routeState)
    clearMetroPassengerPeds(routeState)
    clearSpawnedStationPassengers()
    clearFreightContainers(routeState)
    clearRouteGuidance(routeState)
end

RegisterNetEvent('godtrain:client:startRoute', function(data)
    if MetroClient.state.activeRoute then
        ClientBridge.Notify(_L('route_already_active'), 'error')
        return
    end

    local vehicle, attachedVehicles = spawnJobVehicle(data.route)
    if not vehicle then
        ClientBridge.Notify(_L('spawn_vehicle_failed'), 'error')
        return
    end

    local panel = MetroClient.state.panelData
    local currentTotal = panel and panel.player and panel.player.totalKm or 0
    local currentXp = panel and panel.player and panel.player.xp or 0
    local stopXpReward = panel and panel.ui and panel.ui.stopXpReward or 0
    local routeRuleCfg = getRouteRuleConfig(data.route.trainType)

    local earlyFinishCfg = Config.EarlyFinish or {}
    local earlyFinishModeCfg = earlyFinishCfg[((data.route.trainType or 'metro') == 'metro') and 'metro' or 'freight'] or {}

    local routeState = {
        vehicle = vehicle,
        routeId = data.routeId,
        routeLabel = data.route.label,
        trainType = data.route.trainType or 'metro',
        stations = getStationsByTrainType(data.route.trainType),
        stationOrder = data.route.stationOrder,
        routeSpawn = data.route.spawn,
        currentStationIdx = 1,
        targetKm = data.route.targetKm,
        distanceKm = 0,
        baseTotalKm = currentTotal,
        totalMileageEstimate = currentTotal,
        baseXp = currentXp,
        xpPerStop = stopXpReward,
        xpGained = 0,
        goodStops = 0,
        missedStops = 0,
        wrongStops = 0,
        passengerRevenue = 0,
        totalPassengerTrips = 0,
        rankMultiplier = tonumber((data.rank and data.rank.multiplier) or 1.0) or 1.0,
        metroPassengerCount = 0,
        metroPassengerPeds = {},
        freightContainersLoaded = 0,
        freightContainerCapacity = math.max(0, #(((((Config.RouteRules or {}).freight or {}).containerProps or {}).offsets) or {})),
        speedingSeconds = 0,
        hardBrakeEvents = 0,
        derailRiskEvents = 0,
        dynamicPenaltyAmount = 0,
        routeSpeedLimitKmh = nil,
        startedAtMs = GetGameTimer(),
        routeDeadlineAt = GetGameTimer() + (((tonumber(routeRuleCfg.timeLimitMin) or (data.route.trainType == 'metro' and 25 or 20)) * 60) * 1000),
        attachedVehicles = attachedVehicles or {},
        runtimeCfg = {
            activeWait = Config.Performance.activeWait,
            uiTickMs = Config.Performance.uiTickMs,
            stopRadiusMultiplier = (Config.Vehicle and tonumber(Config.Vehicle.stopRadiusMultiplier)) or 1.0,
            maxStopSpeed = (Config.Vehicle and tonumber(Config.Vehicle.maxStopSpeed)) or 1.5,
            reenterDistance = (Config.Vehicle and (((data.route.trainType or 'metro') == 'metro') and Config.Vehicle.reenterDistanceMetro or Config.Vehicle.reenterDistance)) or 14.0,
            exitPopupDistance = (Config.Vehicle and Config.Vehicle.reenterPopupDistance) or 24.0,
            reenterEnterTimeoutMs = (Config.Vehicle and Config.Vehicle.reenterEnterTimeoutMs) or 6000,
            cancelHoldMs = tonumber(earlyFinishModeCfg.holdToCancelMs) or tonumber(((Config.Runtime or {}).cancelHoldMs)) or 5000,
            exitGraceMs = 9000,
            reenterPromptKey = ((data.route.trainType or 'metro') == 'metro') and 'metro_reenter_prompt' or 'train_reenter_prompt',
            passengerBoarding = resolvePassengerBoardingConfig(Config.PassengerBoarding or {}),
            marker = Config.Marker or {},
            trainControl = Config.TrainControl or {}
        },
        stopPromptVisible = false,
        stopPromptText = nil,
        stationMissed = {},
        stationApproached = {},
        stationArrivalSpeedChecked = {},
        stationArrivalSpeedViolations = 0,
        currentStage = nil,
        stationApproachLimitKmh = nil,
        stationApproachLimitActive = false,
        stationApproachLimitStationId = nil,
        stationAutoBoardReadyAt = nil,
        stationAutoBoardStarted = nil
    }

    local _, firstStation = getCurrentStation(routeState)
    applyRouteSpeedProfile(routeState, firstStation)

    MetroClient.state.activeRoute = routeState
    setMetroDoors(routeState, false)
    CreateThread(function()
        Wait(350)
        if MetroClient.state.activeRoute == routeState then
            setMetroDoors(routeState, false)
        end
    end)
    createRouteGuidance(routeState)
    refreshRouteGuidance(routeState)
    MetroClient.state.hudVisible = true
    SendNUIMessage({ action = 'setHudVisible', visible = true })
    updateHud(routeState)

    CreateThread(function()
        while MetroClient.state.activeRoute == routeState do
            Wait(0)
            local m = routeState.activeMarker
            if m then
                DrawMarker(
                    m.markerType, m.x, m.y, m.z,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, m.rotZ,
                    m.sizeX, m.sizeY, m.sizeZ,
                    m.r, m.g, m.b, m.a or 140,
                    false, false, 2, false, nil, nil, false
                )
            end
        end
    end)

    jobLoop(routeState)
end)

RegisterCommand(tostring((((Config.UI or {}).hudEditor or {}).toggleCommand) or 'godhud'), function()
    MetroClient.state.hudVisible = not MetroClient.state.hudVisible
    SendNUIMessage({ action = 'setHudVisible', visible = MetroClient.state.hudVisible })
end, false)

local function loadHudLayout()
    local hudEditorCfg = (Config.UI and Config.UI.hudEditor) or {}
    local defaultLayout = hudEditorCfg.defaultLayout or {}
    local leftPct = GetResourceKvpFloat('godtrain:hud:leftPct')
    local topPct = GetResourceKvpFloat('godtrain:hud:topPct')
    local scale = GetResourceKvpFloat('godtrain:hud:scale')
    local hiddenItemsRaw = GetResourceKvpString('godtrain:hud:hiddenItems')
    local hiddenItems = {}
    if hiddenItemsRaw and hiddenItemsRaw ~= '' then
        local ok, decoded = pcall(json.decode, hiddenItemsRaw)
        if ok and type(decoded) == 'table' then
            hiddenItems = decoded
        end
    end

    if leftPct == 0.0 then leftPct = tonumber(defaultLayout.leftPct) or 50.0 end
    if topPct == 0.0 then topPct = tonumber(defaultLayout.topPct) or 1.35 end
    if scale == 0.0 then scale = tonumber(defaultLayout.scale) or 0.92 end
    if leftPct <= 5.0 and topPct >= 20.0 then
        leftPct = tonumber(defaultLayout.leftPct) or 50.0
        topPct = tonumber(defaultLayout.topPct) or 1.35
        scale = tonumber(defaultLayout.scale) or 0.92
    end

    MetroClient.state.hudLayout = {
        leftPct = leftPct,
        topPct = topPct,
        scale = scale,
        hiddenItems = hiddenItems
    }
end

local function buildHudEditorCopySnippet()
    local hudEditorCfg = (Config.UI and Config.UI.hudEditor) or {}
    local defaultLayout = hudEditorCfg.defaultLayout or {}
    local scaleCfg = hudEditorCfg.scale or {}
    local layout = MetroClient.state.hudLayout or {}

    local leftPct = tonumber(layout.leftPct) or tonumber(defaultLayout.leftPct) or 50.0
    local topPct = tonumber(layout.topPct) or tonumber(defaultLayout.topPct) or 1.35
    local scale = tonumber(layout.scale) or tonumber(defaultLayout.scale) or 0.92
    local minPct = tonumber(scaleCfg.minPct) or 75
    local maxPct = tonumber(scaleCfg.maxPct) or 220
    local stepPct = tonumber(scaleCfg.stepPct) or 1

    return table.concat({
        "defaultLayout = {",
        ("    leftPct = %.14f,"):format(leftPct),
        ("    topPct = %.14f,"):format(topPct),
        ("    scale = %.14f"):format(scale),
        "},",
        "scale = {",
        ("    minPct = %d,"):format(math.floor(minPct)),
        ("    maxPct = %d,"):format(math.floor(maxPct)),
        ("    stepPct = %d"):format(math.floor(stepPct)),
        "}"
    }, "\n")
end

loadHudLayout()

CreateThread(function()
    Wait(500)
    if MetroClient.state.hudLayout then
        SendNUIMessage({
            action = 'applyHudLayout',
            data = MetroClient.state.hudLayout
        })
    end
    SendNUIMessage({
        action = 'setHudEditorConfig',
        data = getHudEditorDefaults()
    })
end)

RegisterCommand(tostring((((Config.UI or {}).hudEditor or {}).command) or 'godhudedit'), function()
    if not MetroClient.state.hudLayout then
        loadHudLayout()
    end

    MetroClient.state.hudVisible = true
    SendNUIMessage({
        action = 'setHudEditorConfig',
        data = getHudEditorDefaults()
    })
    SendNUIMessage({ action = 'setHudVisible', visible = true })
    SendNUIMessage({ action = 'applyHudLayout', data = MetroClient.state.hudLayout })
    SendNUIMessage({ action = 'setHudEditMode', enabled = true })
    SetNuiFocus(true, true)
end, false)

RegisterCommand(tostring((((Config.UI or {}).hudEditor or {}).copyCommand) or 'godhudeditcopy'), function()
    if not MetroClient.state.hudLayout then
        loadHudLayout()
    end

    local snippet = buildHudEditorCopySnippet()
    SendNUIMessage({
        action = 'copyHudEditorConfig',
        data = {
            snippet = snippet
        }
    })
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local routeState = MetroClient and MetroClient.state and MetroClient.state.activeRoute
    if routeState then
        setMetroDoors(routeState, false)
        clearMetroPassengerPeds(routeState)
        clearSpawnedStationPassengers()
        clearFreightContainers(routeState)
        clearActiveCargoProp(routeState)
        if Config.Vehicle.deleteOnFinish and routeState.vehicle and DoesEntityExist(routeState.vehicle) then
            cleanupAttachedVehicles(routeState)
            safeDeleteTrain(routeState.vehicle)
        end

        clearRouteGuidance(routeState)
        MetroClient.state.activeRoute = nil
    end

    TrainUI.HideTextUI()
    SendNUIMessage({ action = 'setHudVisible', visible = false })
end)
