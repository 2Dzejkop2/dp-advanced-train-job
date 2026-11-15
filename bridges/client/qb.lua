local M = {}

function M.Init()
end

function M.Notify(message, nType)
    TriggerEvent('QBCore:Notify', message, nType or 'primary')
end

function M.Progress(label, duration)
    if lib and lib.progressBar then
        return lib.progressBar({
            duration = duration,
            label = label,
            useWhileDead = false,
            canCancel = false,
            disable = { car = false, move = true, combat = true }
        })
    end
    Wait(duration)
    return true
end

ClientBridgeImpl = ClientBridgeImpl or {}
ClientBridgeImpl.qb = M
