Config = Config or {}

Config.Stations = Config.Stations or {}
Config.Routes = Config.Routes or {}

local function loadRailConfigModule(path)
    local resourceName = GetCurrentResourceName()
    local source = LoadResourceFile(resourceName, path)
    if not source then
        error(('Failed to load config module "%s": file not found in resource "%s"'):format(path, resourceName))
    end

    local chunk, compileErr = load(source, ('@@%s/%s'):format(resourceName, path), 't', _ENV)
    if not chunk then
        error(('Failed to compile config module "%s": %s'):format(path, tostring(compileErr)))
    end

    local ok, loader = pcall(chunk)
    if not ok then
        error(('Failed to load config module "%s": %s'):format(path, tostring(loader)))
    end

    if type(loader) == 'function' then
        loader(Config)
        return
    end

    if type(loader) == 'table' and type(loader.apply) == 'function' then
        loader.apply(Config)
        return
    end

    error(('Config module "%s" must return function(Config) or { apply = function(Config) }'):format(path))
end

local configModules = {
    'config/config-core.lua',
    'config/config-gameplay.lua',
    'config/config-progression.lua',
    'config/config-economy.lua',
    'config/config-metro.lua',
    'config/config-train.lua',
    'config/config-quests.lua',
    'config/config-webhook.lua',
    'config/config-interactions.lua'
}

for _, modulePath in ipairs(configModules) do
    loadRailConfigModule(modulePath)
end
