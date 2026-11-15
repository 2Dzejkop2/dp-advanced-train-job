return function(Config)
    -- Internal helper that normalizes UI provider names.

    local function uiProvider(value, fallback)
        local provider = string.lower(tostring(value or fallback or 'qb'))
        return provider
    end

    -- Maps generic notification types to provider-specific types.
    local function mapNotifyType(nType)
        local t = string.lower(tostring(nType or 'inform'))
        if t == 'inform' then return 'primary' end
        return t
    end

    -- Client-side notification bridge.
    Config.ClientNotification = function(message, nType, length)
        TriggerEvent('god:client:ui:notify', tostring(message or ''), nType or 'inform', length or 5000)
        return true
    end

    -- Server-side notification bridge.
    Config.ServerNotification = function(src, message, nType, length)
        TriggerClientEvent('god:client:ui:notify', src, tostring(message or ''), nType or 'inform', length or 5000)
        return true
    end

    -- Show text UI using the configured provider.
    Config.ClientTextUIShow = function(text)
        local provider = uiProvider(Config.TextUI, 'qb')

        if provider == 'qb' or provider == 'qbox' then
            local pos = Config.QBTextPosition or 'left'
            exports['qb-core']:DrawText(text, pos)
            return true
        end

        if provider == 'esx' then
            TriggerEvent('esx:showNotification', tostring(text or ''))
            return true
        end

        if provider == 'ox' and lib and lib.showTextUI then
            lib.showTextUI(text)
            return true
        end

        return false
    end

    -- Hide text UI using the configured provider.
    Config.ClientTextUIHide = function()
        local provider = uiProvider(Config.TextUI, 'qb')

        if provider == 'qb' or provider == 'qbox' then
            exports['qb-core']:HideText()
            return true
        end

        if provider == 'esx' then
            return true
        end

        if provider == 'ox' and lib and lib.hideTextUI then
            lib.hideTextUI()
            return true
        end

        return false
    end

    -- Show a progress bar using the configured provider.
    Config.ClientProgress = function(options)
        local provider = uiProvider(Config.Progress, 'ox')
        local duration = (options and options.duration) or 0

        if provider == 'ox' and lib and lib.progressBar then
            return lib.progressBar(options) ~= false
        end

        if provider == 'qb' or provider == 'qbox' or provider == 'esx' then
            Wait(duration)
            return true
        end

        return false
    end

    -- Show a dialog / confirm popup using the configured provider.
    Config.ClientDialog = function(options)
        local provider = uiProvider(Config.Dialog, 'ox')

        if provider == 'ox' and lib and lib.alertDialog then
            return lib.alertDialog(options)
        end

        return nil
    end
end
