RegisterNUICallback('godtrain:close', function(_, cb)
    MetroClient.state.uiOpen = false
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('godtrain:refresh', function(_, cb)
    local profileType = (_ and _.profileType) or 'train'
    local panelData = lib.callback.await('godtrain:server:getPanelData', false, profileType)
    if MetroClient and MetroClient.DecoratePanelDataForUi then
        MetroClient.DecoratePanelDataForUi(panelData)
    end
    MetroClient.state.panelData = panelData
    cb({ ok = true, data = panelData })
end)

RegisterNUICallback('godtrain:buyLicense', function(payload, cb)
    local rankKey = payload.rankKey
    local account = payload.account or Config.Licenses.accountType or 'bank'
    local profileType = payload.profileType or 'train'

    local response = lib.callback.await('godtrain:server:buyLicense', false, rankKey, account, profileType)
    if response.ok then
        if MetroClient and MetroClient.DecoratePanelDataForUi then
            MetroClient.DecoratePanelDataForUi(response.panel)
        end
        MetroClient.state.panelData = response.panel
        SendNUIMessage({ action = 'updatePanel', data = response.panel })
    end

    cb(response)
end)

RegisterNUICallback('godtrain:claimQuest', function(payload, cb)
    local profileType = payload.profileType or 'train'
    local response = lib.callback.await('godtrain:server:claimQuest', false, payload.questId, profileType)
    if response.ok then
        if MetroClient and MetroClient.DecoratePanelDataForUi then
            MetroClient.DecoratePanelDataForUi(response.panel)
        end
        MetroClient.state.panelData = response.panel
        SendNUIMessage({ action = 'updatePanel', data = response.panel })
    end
    cb(response)
end)

RegisterNUICallback('godtrain:startRoute', function(payload, cb)
    if type(payload) ~= 'table' then
        cb({ ok = false, message = 'Invalid payload.' })
        return
    end

    local routeId = payload.routeId
    local rankKey = payload.rankKey

    if routeId == nil then
        cb({ ok = false, message = 'Route not selected.' })
        return
    end

    local response = lib.callback.await('godtrain:server:startRoute', false, routeId, rankKey)
    if not response.ok then
        cb(response)
        return
    end

    TriggerEvent('godtrain:client:startRoute', {
        route = response.data.route,
        routeId = response.data.routeId or tonumber(routeId),
        rank = response.data.rank,
        stations = response.data.stations,
        targetKm = response.data.targetKm
    })

    cb({ ok = true })
end)

RegisterNUICallback('godtrain:saveHudLayout', function(payload, cb)
    MetroClient.state.hudLayout = MetroClient.state.hudLayout or {}
    MetroClient.state.hudLayout.leftPct = tonumber(payload.leftPct) or 50.0
    MetroClient.state.hudLayout.topPct = tonumber(payload.topPct) or 1.35
    MetroClient.state.hudLayout.scale = tonumber(payload.scale) or 0.92
    MetroClient.state.hudLayout.hiddenItems = type(payload.hiddenItems) == 'table' and payload.hiddenItems or {}

    SetResourceKvpFloat('godtrain:hud:leftPct', MetroClient.state.hudLayout.leftPct)
    SetResourceKvpFloat('godtrain:hud:topPct', MetroClient.state.hudLayout.topPct)
    SetResourceKvpFloat('godtrain:hud:scale', MetroClient.state.hudLayout.scale)
    SetResourceKvp('godtrain:hud:hiddenItems', json.encode(MetroClient.state.hudLayout.hiddenItems))

    cb({ ok = true })
end)

RegisterNUICallback('godtrain:closeHudEdit', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'setHudEditMode', enabled = false })
    cb({ ok = true })
end)

RegisterNUICallback('godtrain:hudEditCopyResult', function(payload, cb)
    local snippet = tostring((payload and payload.snippet) or '')
    local ok = payload and payload.ok == true
    local message = tostring((payload and payload.message) or '')

    if snippet ~= '' then
        print('[godtrain][HUD COPY]\n' .. snippet)
    end

    if ClientBridge and ClientBridge.Notify then
        if ok then
            ClientBridge.Notify('HUD default config copied to clipboard.', 'success')
        else
            ClientBridge.Notify('HUD copy failed. Snippet printed to F8 console.', 'error')
            if message ~= '' then
                print(('[godtrain][HUD COPY][ERROR] %s'):format(message))
            end
        end
    end

    cb({ ok = true })
end)
