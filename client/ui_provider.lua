TrainUI = TrainUI or {}

local function getProvider(key, fallback)
    local cfg = Config.UI or {}
    local value = cfg[key]
    if type(value) ~= 'string' or value == '' then
        return fallback
    end
    return string.lower(value)
end

local function callCustom(hookKey, ...)
    local cfg = Config.UI and Config.UI.custom and Config.UI.custom[hookKey]
    if type(cfg) ~= 'table' then return nil, false end
    local resource = cfg.resource
    local fn = cfg.fn
    if type(resource) ~= 'string' or resource == '' or type(fn) ~= 'string' or fn == '' then
        return nil, false
    end

    local ok, result = pcall(function(...)
        return exports[resource][fn](...)
    end, ...)

    if not ok then
        return nil, false
    end
    return result, true
end

local function mapNotifyType(nType)
    local t = string.lower(tostring(nType or 'inform'))
    if t == 'inform' then return 'primary' end
    if t == 'early_exit' then return 'primary' end
    return t
end

local function normalizeLibNotifyType(nType)
    local t = string.lower(tostring(nType or 'inform'))
    if t == 'success' or t == 'error' or t == 'warning' or t == 'inform' then
        return t
    end
    return 'inform'
end

function TrainUI.Notify(message, nType)
    if type(Config.ClientNotification) == 'function' then
        local ok, handled = pcall(Config.ClientNotification, message, nType, 5000)
        if ok and handled ~= false then
            return
        end
    end

    local provider = getProvider('notifyProvider', 'ox_lib')

    if provider == 'custom' then
        local _, ok = callCustom('notify', message, nType)
        if ok then return end
    elseif provider == 'qb' then
        local ok = pcall(function()
            TriggerEvent('QBCore:Notify', message, mapNotifyType(nType))
        end)
        if ok then return end
    end

    if lib and lib.notify then
        lib.notify({
            description = message,
            type = normalizeLibNotifyType(nType)
        })
        return
    end

    TriggerEvent('chat:addMessage', { args = { '[Metro]', tostring(message or '') } })
end

function TrainUI.ShowTextUI(text)
    if type(Config.ClientTextUIShow) == 'function' then
        local ok, handled = pcall(Config.ClientTextUIShow, text)
        if ok and handled ~= false then
            return
        end
    end

    local provider = getProvider('textUIProvider', 'ox_lib')

    if provider == 'custom' then
        local _, ok = callCustom('showTextUI', text)
        if ok then return end
    elseif provider == 'qb' then
        local ok = pcall(function()
            exports['qb-core']:DrawText(text, 'left')
        end)
        if ok then return end
    end

    if lib and lib.showTextUI then
        lib.showTextUI(text)
    end
end

function TrainUI.HideTextUI()
    if type(Config.ClientTextUIHide) == 'function' then
        local ok, handled = pcall(Config.ClientTextUIHide)
        if ok and handled ~= false then
            return
        end
    end

    local provider = getProvider('textUIProvider', 'ox_lib')

    if provider == 'custom' then
        local _, ok = callCustom('hideTextUI')
        if ok then return end
    elseif provider == 'qb' then
        local ok = pcall(function()
            exports['qb-core']:HideText()
        end)
        if ok then return end
    end

    if lib and lib.hideTextUI then
        lib.hideTextUI()
    end
end

function TrainUI.Progress(options)
    options = options or {}
    if type(Config.ClientProgress) == 'function' then
        local ok, result = pcall(Config.ClientProgress, options)
        if ok and result ~= false then
            return result ~= false
        end
    end

    local provider = getProvider('progressProvider', 'ox_lib')

    if provider == 'custom' then
        local result, ok = callCustom('progress', options)
        if ok then return result ~= false end
    elseif provider == 'qb' then
        local result, ok = callCustom('progress', options)
        if ok then return result ~= false end
        Wait(tonumber(options.duration) or 0)
        return true
    end

    if lib and lib.progressBar then
        return lib.progressBar(options)
    end

    Wait(tonumber(options.duration) or 0)
    return true
end

function TrainUI.Dialog(options)
    options = options or {}
    if type(Config.ClientDialog) == 'function' then
        local ok, result = pcall(Config.ClientDialog, options)
        if ok then
            return result
        end
    end

    local provider = getProvider('dialogProvider', 'ox_lib')

    if provider == 'custom' then
        local result, ok = callCustom('dialog', options)
        if ok then return result end
    elseif provider == 'qb' then
        local result, ok = callCustom('dialog', options)
        if ok then return result end
    end

    if lib and lib.alertDialog then
        return lib.alertDialog(options)
    end

    return 'cancel'
end
