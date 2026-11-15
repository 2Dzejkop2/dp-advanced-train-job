Framework = {
    mode = 'qb'
}

local function exists(res)
    return GetResourceState(res) == 'started'
end

function Framework.Detect()
    if Config.FrameworkMode and Config.FrameworkMode ~= 'auto' then
        Framework.mode = tostring(Config.FrameworkMode)
        return Framework.mode
    end

    local detectCfg = Config.AutoDetection and Config.AutoDetection.framework or {}
    if detectCfg.enabled == false then
        Framework.mode = 'qb'
        return Framework.mode
    end

    local resources = detectCfg.resources or {
        qbox = 'qbx_core',
        qb = 'qb-core',
        esx = 'es_extended'
    }
    local priority = detectCfg.priority or { 'qbox', 'qb', 'esx' }

    for _, mode in ipairs(priority) do
        local res = resources[mode]
        if res and exists(res) then
            Framework.mode = mode
            return Framework.mode
        end
    end

    Framework.mode = 'qb'
    return Framework.mode
end

function Framework.IsStandalone()
    return false
end

function Framework.IsDbEnabled()
    local depCfg = Config.AutoDetection and Config.AutoDetection.dependencies or {}
    local dbResources = depCfg.database or { 'oxmysql' }
    local dbUp = false
    for _, res in ipairs(dbResources) do
        if GetResourceState(res) == 'started' then
            dbUp = true
            break
        end
    end

    return dbUp
end
