ClientBridge = {}
ClientBridgeImpl = ClientBridgeImpl or {}

local bridgeImpl = nil

function ClientBridge.Init()
    local mode = Framework.Detect()
    bridgeImpl = ClientBridgeImpl[mode]
    if bridgeImpl and bridgeImpl.Init then
        bridgeImpl.Init()
    end
    Utils.Debug('Client bridge initialized:', mode)
end

function ClientBridge.Notify(message, nType)
    if TrainUI and TrainUI.Notify then
        TrainUI.Notify(message, nType)
        return
    end
    if bridgeImpl and bridgeImpl.Notify then
        bridgeImpl.Notify(message, nType)
    end
end
