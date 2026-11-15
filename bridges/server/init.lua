ServerBridge = {}
ServerBridgeImpl = ServerBridgeImpl or {}

local bridgeImpl = nil

function ServerBridge.Init()
    local mode = Framework.Detect()
    bridgeImpl = ServerBridgeImpl[mode]
    if bridgeImpl and bridgeImpl.Init then
        bridgeImpl.Init()
    end
    Utils.Debug('Server bridge initialized:', mode)
end

function ServerBridge.GetMode()
    return Framework.mode
end

function ServerBridge.GetIdentifier(src)
    if not bridgeImpl or not bridgeImpl.GetIdentifier then
        return ('src:%s'):format(src)
    end
    return bridgeImpl.GetIdentifier(src)
end

function ServerBridge.GetCharacterName(src)
    if not bridgeImpl or not bridgeImpl.GetCharacterName then
        return ('Player %s'):format(src)
    end
    return bridgeImpl.GetCharacterName(src)
end

function ServerBridge.GetMoney(src, account)
    if not bridgeImpl or not bridgeImpl.GetMoney then
        return 0
    end
    return bridgeImpl.GetMoney(src, account)
end

function ServerBridge.RemoveMoney(src, account, amount, reason)
    if not bridgeImpl or not bridgeImpl.RemoveMoney then
        return false
    end
    return bridgeImpl.RemoveMoney(src, account, amount, reason)
end

function ServerBridge.AddMoney(src, account, amount, reason)
    if not bridgeImpl or not bridgeImpl.AddMoney then
        return false
    end
    return bridgeImpl.AddMoney(src, account, amount, reason)
end

function ServerBridge.Notify(src, message, nType)
    if type(Config.ServerNotification) == 'function' then
        local ok, handled = pcall(Config.ServerNotification, src, message, nType, 5000)
        if ok and handled ~= false then
            return
        end
    end

    if bridgeImpl and bridgeImpl.Notify then
        bridgeImpl.Notify(src, message, nType)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '[Metro]', message } })
    end
end
