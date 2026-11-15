CreateThread(function()
    Framework.Detect()
    ServerBridge.Init()
    Utils.Debug('Metro server initialized in mode:', ServerBridge.GetMode())
end)

local function getWebhookConfig()
    local cfg = Config.Webhooks or {}
    if next(cfg) == nil then
        cfg = {}
    end

    local legacy = Config.DiscordLogging or {}
    if next(cfg) == nil or cfg.enabled == nil then
        cfg.enabled = legacy.enabled
        cfg.all = legacy.webhook
        cfg.username = legacy.username
        cfg.avatarUrl = legacy.avatarUrl
        cfg.color = legacy.color
    end

    return cfg
end

local function resolveWebhook(cfg, eventKey)
    if type(cfg.all) == 'string' and cfg.all ~= '' then
        return cfg.all
    end
    if eventKey == 'routeStart' then return cfg.routeStart end
    if eventKey == 'routeFinish' then return cfg.routeFinish end
    if eventKey == 'licenseBuy' then return cfg.licenseBuy end
    if eventKey == 'questClaim' then return cfg.questClaim end
    return nil
end

local function sendDiscordLog(eventKey, title, description, fields)
    local cfg = getWebhookConfig()
    if cfg.enabled ~= true then return end

    local webhook = resolveWebhook(cfg, eventKey)
    if type(webhook) ~= 'string' or webhook == '' then return end

    local payload = {
        username = cfg.username or _L('webhook_username'),
        avatar_url = cfg.avatarUrl or '',
        embeds = {
            {
                title = title,
                description = description,
                color = tonumber(cfg.color) or 5763719,
                fields = fields or {},
                footer = { text = tostring(cfg.footer or _L('webhook_footer')) },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }
        }
    }

    PerformHttpRequest(webhook, function() end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

local function playerMetaFields(src)
    local identifier = ServerBridge.GetIdentifier(src)
    local charName = ServerBridge.GetCharacterName(src)
    return {
        { name = _L('log_field_player'), value = ('%s (ID: %s)'):format(charName, src), inline = true },
        { name = _L('log_field_identifier'), value = tostring(identifier), inline = false },
        { name = _L('log_field_framework'), value = tostring(ServerBridge.GetMode()), inline = true }
    }
end

lib.callback.register('godtrain:server:getPanelData', function(src, profileType)
    return MetroService.BuildPanelData(src, profileType)
end)

lib.callback.register('godtrain:server:buyLicense', function(src, rankKey, account, profileType)
    local ok, result = MetroService.TryBuyLicense(src, rankKey, account, profileType)
    if not ok then
        ServerBridge.Notify(src, result, 'error')
        return { ok = false, message = result }
    end

    ServerBridge.Notify(src, result, 'success')
    local fields = playerMetaFields(src)
    fields[#fields + 1] = { name = _L('log_field_rank'), value = tostring(rankKey), inline = true }
    fields[#fields + 1] = { name = _L('log_field_account'), value = tostring(account or Config.Licenses.accountType or 'bank'), inline = true }
    sendDiscordLog('licenseBuy', _L('log_title_license_purchased'), result, fields)
    return {
        ok = true,
        message = result,
        panel = MetroService.BuildPanelData(src, profileType)
    }
end)

lib.callback.register('godtrain:server:startRoute', function(src, routeId, rankKey)
    local ok, result = MetroService.StartRoute(src, routeId, rankKey)
    if not ok then
        ServerBridge.Notify(src, result, 'error')
        return { ok = false, message = result }
    end

    ServerBridge.Notify(src, _L('route_started'), 'success')
    local fields = playerMetaFields(src)
    fields[#fields + 1] = { name = _L('log_field_route_id'), value = tostring(result.routeId), inline = true }
    fields[#fields + 1] = { name = _L('log_field_route'), value = tostring((result.route and result.route.label) or routeId), inline = true }
    fields[#fields + 1] = { name = _L('log_field_rank'), value = tostring(result.rank or rankKey), inline = true }
    sendDiscordLog('routeStart', _L('log_title_route_started'), _L('route_started'), fields)
    return {
        ok = true,
        data = result
    }
end)

lib.callback.register('godtrain:server:getEarlyFinishPreview', function(src, payload)
    local ok, result = MetroService.GetEarlyFinishPreview(src, payload)
    if not ok then
        return { ok = false, message = result }
    end

    return {
        ok = true,
        data = result
    }
end)

RegisterNetEvent('godtrain:server:recordStop', function(stopType, stationId)
    local src = source
    local ok, result = MetroService.RecordRouteStop(src, stopType, stationId)
    if not ok and stopType ~= 'wrong' then
        Utils.Debug('Rejected route stop event for player', src, stopType, stationId, result)
    end
end)

RegisterNetEvent('godtrain:server:syncMetroDoors', function(netIds, sideSign, isOpen)
    local src = source
    if type(netIds) ~= 'table' or #netIds == 0 then
        return
    end

    TriggerClientEvent('godtrain:client:syncMetroDoors', -1, src, netIds, tonumber(sideSign) or 1.0, isOpen == true)
end)

RegisterNetEvent('godtrain:server:finishRoute', function(payload)
    local src = source

    if type(payload) ~= 'table' then return end

    local ok, result = MetroService.FinishRoute(src, payload)
    if not ok then
        ServerBridge.Notify(src, result, 'error')
        TriggerClientEvent('godtrain:client:routeFinished', src, { ok = false, message = result })
        return
    end

    local message = _L('route_finished', result.payout)
    local messageType = 'success'

    if not result.routeCompleted then
        if result.earlyExit then
            if result.payout > 0 then
                message = _L('route_finished_partial', result.payout, result.goodStops or 0, result.routeStops or 0)
                messageType = 'success'
            else
                message = _L('route_finished_early_no_payout')
                messageType = 'error'
            end
        elseif result.payout <= 0 and result.partialBlockedByMinStops then
            local minStops = (((Config.Economy or {}).partial or {}).minCompletedStopsForPartial) or 7
            message = _L('route_no_payout_min_stops', minStops)
            messageType = 'error'
        elseif result.payout <= 0 then
            message = _L('route_no_payout_anti_abuse')
            messageType = 'error'
        else
            message = _L('route_finished_partial', result.payout, result.goodStops or 0, result.routeStops or 0)
            messageType = 'success'
        end
    end

    ServerBridge.Notify(src, message, messageType)

    if (result.tipReward or 0) > 0 then
        ServerBridge.Notify(src, _L('tips_received', result.tipReward, result.tipHits or 0), 'inform')
    end

    local fields = playerMetaFields(src)
    fields[#fields + 1] = { name = _L('log_field_route_completed'), value = tostring(result.routeCompleted == true), inline = true }
    fields[#fields + 1] = { name = _L('log_field_early_exit'), value = tostring(result.earlyExit == true), inline = true }
    fields[#fields + 1] = { name = _L('log_field_payout'), value = ('$%s'):format(tonumber(result.payout) or 0), inline = true }
    fields[#fields + 1] = { name = _L('log_field_stops'), value = ('%s/%s'):format(tonumber(result.goodStops) or 0, tonumber(result.routeStops) or 0), inline = true }
    fields[#fields + 1] = { name = _L('log_field_tips'), value = ('$%s (%s hits)'):format(tonumber(result.tipReward) or 0, tonumber(result.tipHits) or 0), inline = true }
    fields[#fields + 1] = { name = _L('log_field_level_xp'), value = ('Lv %s, XP %s'):format(tonumber(result.level) or 1, tonumber(result.xp) or 0), inline = true }
    sendDiscordLog('routeFinish', _L('log_title_route_finished'), message, fields)

    TriggerClientEvent('godtrain:client:routeFinished', src, {
        ok = true,
        message = message,
        data = result
    })
end)

lib.callback.register('godtrain:server:claimQuest', function(src, questId, profileType)
    local ok, result = MetroService.ClaimQuest(src, questId, profileType)
    if not ok then
        ServerBridge.Notify(src, result, 'error')
        return { ok = false, message = result }
    end

    ServerBridge.Notify(src, _L('quest_claimed', result.reward), 'success')
    local fields = playerMetaFields(src)
    fields[#fields + 1] = { name = _L('log_field_quest_id'), value = tostring(questId), inline = true }
    fields[#fields + 1] = { name = _L('log_field_reward'), value = ('$%s'):format(tonumber(result.reward) or 0), inline = true }
    fields[#fields + 1] = { name = _L('log_field_account'), value = tostring(result.account or Config.Payout.currency or 'bank'), inline = true }
    sendDiscordLog('questClaim', _L('log_title_quest_claimed'), _L('quest_claimed', result.reward), fields)
    return {
        ok = true,
        message = _L('quest_claimed', result.reward),
        panel = MetroService.BuildPanelData(src, profileType)
    }
end)
