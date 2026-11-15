Utils = {}

local function resolveDebugLevel()
    if type(Config.Debug) == 'boolean' then
        return Config.Debug and 'basic' or 'off'
    end
    return string.lower(tostring((Config and Config.DebugLevel) or 'off'))
end

function Utils.Clamp(value, minV, maxV)
    if value < minV then return minV end
    if value > maxV then return maxV end
    return value
end

function Utils.Round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

function Utils.Accuracy(hit, total)
    if total <= 0 then return 0 end
    return Utils.Round((hit / total) * 100, 2)
end

function Utils.DeepCopy(tbl)
    local copy = {}
    for k, v in pairs(tbl or {}) do
        if type(v) == 'table' then
            copy[k] = Utils.DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

function Utils.NormalizeProfileType(profileType)
    if ((Config or {}).Persistence or {}).sharedProgression == true then
        return 'train'
    end

    local normalized = string.lower(tostring(profileType or 'train'))
    if normalized ~= 'metro' then
        return 'train'
    end

    return normalized
end

function Utils.NormalizeRouteTypeKey(routeType)
    local normalized = string.lower(tostring(routeType or 'metro'))
    if normalized == 'freight' or normalized == 'train' then
        return 'freight'
    end
    return 'metro'
end

function Utils.GetRouteRules(routeType)
    local routeRules = (Config and Config.RouteRules) or {}
    return routeRules[Utils.NormalizeRouteTypeKey(routeType)] or {}
end

function Utils.GetPenaltyConfig(routeType)
    local legacy = (Config and Config.Penalties) or {}
    local routeCfg = Utils.GetRouteRules(routeType)

    return {
        latePenaltyPerMinute = tonumber(routeCfg.latePenaltyPerMinute) or tonumber(legacy.latePenaltyPerMinute) or 0,
        latePenaltyOnce = tonumber(routeCfg.latePenaltyOnce) or tonumber(legacy.latePenaltyOnce) or 0,
        speedPenaltyPerSecond = tonumber(routeCfg.speedPenaltyPerSecond) or tonumber(legacy.speedPenaltyPerSecond) or 0,
        hardBrakePenalty = tonumber(routeCfg.hardBrakePenalty) or tonumber(legacy.hardBrakePenalty) or 0,
        derailRiskPenalty = tonumber(routeCfg.derailRiskPenalty) or tonumber(legacy.derailRiskPenalty) or 0,
        stationArrivalSpeedLimit = tonumber(routeCfg.stationArrivalSpeedLimit) or tonumber(legacy.stationArrivalSpeedLimit) or 0,
        stationArrivalSpeedUnit = tostring(routeCfg.stationArrivalSpeedUnit or legacy.stationArrivalSpeedUnit or 'kmh'),
        stationArrivalSpeedPenalty = tonumber(routeCfg.stationArrivalSpeedPenalty) or tonumber(legacy.stationArrivalSpeedPenalty) or 0,
        stationArrivalSpeedTriggerDistance = tonumber(routeCfg.stationArrivalSpeedTriggerDistance) or tonumber(legacy.stationArrivalSpeedTriggerDistance) or 0,
        speedingToleranceKmh = tonumber(routeCfg.speedingToleranceKmh) or tonumber(legacy.speedingToleranceKmh) or 0,
        citySpeedLimitKmh = tonumber(routeCfg.citySpeedLimitKmh) or tonumber(routeCfg.cityMaxSpeedKmh) or tonumber(legacy.citySpeedLimitKmh) or tonumber(legacy.cityMaxSpeedKmh) or 0,
        cityMaxSpeedKmh = tonumber(routeCfg.cityMaxSpeedKmh) or tonumber(routeCfg.citySpeedLimitKmh) or tonumber(legacy.cityMaxSpeedKmh) or tonumber(legacy.citySpeedLimitKmh) or 0,
        cityZones = routeCfg.cityZones or legacy.cityZones or {},
        timeLimitMin = tonumber(routeCfg.timeLimitMin) or tonumber(legacy.timeLimitMin) or 0
    }
end

function Utils.Debug(...)
    local level = resolveDebugLevel()
    if level == 'off' then
        return
    end
    print('[god-advanced-train-job][DEBUG]', ...)
end

function Utils.DebugVerbose(...)
    local level = resolveDebugLevel()
    if level ~= 'verbose' then
        return
    end
    print('[god-advanced-train-job][DEBUG][VERBOSE]', ...)
end
