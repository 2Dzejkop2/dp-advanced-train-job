MetroService = {}

local rankFlow = { 'trainee', 'junior', 'senior', 'chief' }
local routeSessions = {}
local eventCooldowns = {}
local panelCache = {}
local PANEL_CACHE_TTL_MS = 1200

local function cacheKey(src, profileType)
    return ('%s:%s'):format(tonumber(src) or 0, tostring(profileType or 'train'))
end

local function nowMs()
    return GetGameTimer()
end

local function getReq(rankKey)
    local rankCfg = Config.Licenses.ranks[rankKey]
    return rankCfg and rankCfg.requirements or { minKm = 0, minRoutes = 0, minAccuracy = 0, minLevel = 1 }
end

local function getAccuracy(data)
    return Utils.Accuracy(data.good_stops or 0, data.total_stops or 0)
end

local function getXpConfig()
    local cfg = Config.XP or {}

    return {
        perStop = tonumber(cfg.perStop) or 20,
        perRoute = tonumber(cfg.perRoute) or 70,
        perKm = tonumber(cfg.perKm) or 12,
        levelStep = tonumber(cfg.levelStep) or 500
    }
end

local function getXpData(data)
    local xpCfg = getXpConfig()
    local totalXp = math.floor(
        ((tonumber(data.good_stops) or 0) * xpCfg.perStop) +
        ((tonumber(data.completed_routes) or 0) * xpCfg.perRoute) +
        ((tonumber(data.total_km) or 0) * xpCfg.perKm)
    )

    local levelStep = math.max(1, tonumber(xpCfg.levelStep) or 500)
    local level = math.max(1, math.floor(totalXp / levelStep) + 1)
    local levelBaseXp = (level - 1) * levelStep
    local progress = Utils.Clamp(((totalXp - levelBaseXp) / levelStep) * 100.0, 0.0, 100.0)

    return {
        totalXp = totalXp,
        level = level,
        progress = progress
    }
end

local function syncXpFields(data)
    local xpData = getXpData(data)
    data.xp_total = xpData.totalXp
    data.player_level = xpData.level
    return xpData
end

local function getPeriodKey(period)
    local t = os.date('*t')
    if period == 'weekly' then
        local day = tonumber(os.date('%w'))
        local mondayOffset = (day == 0 and 6 or day - 1)
        local monday = os.time({ year = t.year, month = t.month, day = t.day - mondayOffset, hour = 0, min = 0, sec = 0 })
        return ('w:%s'):format(os.date('%Y-%m-%d', monday))
    end
    return ('d:%04d-%02d-%02d'):format(t.year, t.month, t.day)
end

local function canUnlockRank(data, rankKey)
    local req = getReq(rankKey)
    local accuracy = getAccuracy(data)
    local xpData = getXpData(data)
    local minLevel = tonumber(req.minLevel) or 1
    return (data.total_km >= req.minKm) and (data.completed_routes >= req.minRoutes) and (accuracy >= req.minAccuracy) and (xpData.level >= minLevel)
end

local function sanitizeNum(v, minV, maxV)
    local n = tonumber(v) or 0
    return Utils.Clamp(n, minV, maxV)
end

local function getRouteStopCount(route)
    if not route or type(route.stationOrder) ~= 'table' then return 0 end
    return #route.stationOrder
end

local function getRankConfig(rankKey)
    return Config.Licenses.ranks[rankKey] or Config.Licenses.ranks.trainee or { payoutMultiplier = 1.0 }
end

local function getTipChance(rankKey)
    local tipsCfg = Config.Tips or {}
    local byRank = tipsCfg.chanceByRank or {}
    return sanitizeNum(byRank[rankKey] or 0, 0, 100)
end

local function getTipAmountRange(rankKey)
    local tipsCfg = Config.Tips or {}
    local byRank = tipsCfg.amountByRank or {}
    local range = byRank[rankKey] or { min = 0, max = 0 }
    local minV = sanitizeNum(range.min, 0, 100000)
    local maxV = sanitizeNum(range.max, minV, 100000)
    return minV, maxV
end

local function rollPassengerTips(rankKey, completedGoodStops)
    local tipsCfg = Config.Tips or {}
    if tipsCfg.enabled == false then return 0, 0 end
    if completedGoodStops <= 0 then return 0, 0 end

    local chance = getTipChance(rankKey)
    if chance <= 0 then return 0, 0 end

    local minTip, maxTip = getTipAmountRange(rankKey)
    if maxTip <= 0 then return 0, 0 end

    local rolls = (tipsCfg.rollPerCompletedStop ~= false) and completedGoodStops or 1
    local totalTip, tipHits = 0, 0

    for _ = 1, rolls do
        if math.random(1, 100) <= chance then
            totalTip = totalTip + math.random(minTip, maxTip)
            tipHits = tipHits + 1
        end
    end

    return totalTip, tipHits
end

local function localeOrFallback(key, fallback, ...)
    local translated = _L(key, ...)
    if type(translated) == 'string' and translated:sub(1, 15) == 'missing_locale:' then
        return fallback
    end
    return translated
end

local function resolveQuestLabel(def)
    if type(def.label) == 'string' and def.label ~= '' then
        return def.label
    end
    local questLabelKey = def.labelKey or ('quest_%s_title'):format(def.id)
    return localeOrFallback(questLabelKey, _L('quest_label_fallback', tostring(def.id)))
end

local function resolveQuestDescription(def)
    if type(def.description) == 'string' then
        return def.description
    end
    local questDescKey = def.descKey or ('quest_%s_desc'):format(def.id)
    return localeOrFallback(questDescKey, _L('quest_desc_fallback', tostring(def.id)))
end

local function resolveRouteCategory(route)
    local trainType = string.lower(tostring((route and route.trainType) or 'metro'))
    if trainType:find('freight', 1, true) or trainType:find('train', 1, true) then
        return 'train'
    end
    return 'metro'
end

local function setQuestDefaults(state, definition)
    state.progress = state.progress or 0
    state.completed = state.completed or false
    state.claimed = state.claimed or false
    state.period = definition.period
    state.periodKey = state.periodKey or getPeriodKey(definition.period)
end

local function questEnabled(definition)
    return definition and definition.enabled ~= false
end

local function questMatchesRouteType(definition, routeType)
    local questType = string.lower(tostring(definition.routeType or 'all'))
    if questType == 'all' or questType == '' then
        return true
    end
    local current = string.lower(tostring(routeType or 'all'))
    return questType == current
end

local function refreshQuestPeriods(data)
    data.quests = data.quests or {}
    for _, def in ipairs(Config.Quests.definitions or {}) do
        if not questEnabled(def) then goto continue end
        data.quests[def.id] = data.quests[def.id] or {}
        local state = data.quests[def.id]
        setQuestDefaults(state, def)
        local key = getPeriodKey(def.period)
        if state.periodKey ~= key then
            state.progress = 0
            state.completed = false
            state.claimed = false
            state.periodKey = key
        end
        ::continue::
    end
end

local function resetAllQuestProgress(data)
    data.quests = data.quests or {}
    for _, def in ipairs(Config.Quests.definitions or {}) do
        if not questEnabled(def) then goto continue end
        data.quests[def.id] = data.quests[def.id] or {}
        local state = data.quests[def.id]
        state.progress = 0
        state.completed = false
        state.claimed = false
        state.period = def.period
        state.periodKey = getPeriodKey(def.period)
        ::continue::
    end
end

local function updateQuestProgress(data, stats)
    if not Config.Quests.enabled then return end

    refreshQuestPeriods(data)

    local currentAccuracy = getAccuracy(data)

    for _, def in ipairs(Config.Quests.definitions or {}) do
        if not questEnabled(def) then goto continue end
        if not questMatchesRouteType(def, stats.routeType) then goto continue end
        local state = data.quests[def.id]
        if state.claimed then goto continue end

        if def.type == 'distance' then
            state.progress = state.progress + stats.distance
        elseif def.type == 'stops' then
            state.progress = state.progress + stats.goodStops
        elseif def.type == 'routes' then
            state.progress = state.progress + (stats.routeCompleted and 1 or 0)
        elseif def.type == 'accuracy' then
            state.progress = currentAccuracy
        end

        if state.progress >= def.target then
            state.progress = def.target
            state.completed = true
        end

        ::continue::
    end
end

local function cooldownPassed(src, key)
    eventCooldowns[src] = eventCooldowns[src] or {}
    local now = GetGameTimer()
    local last = eventCooldowns[src][key] or 0
    local cd = (Config.Security and Config.Security.eventCooldownMs) or 900
    if now - last < cd then
        return false
    end
    eventCooldowns[src][key] = now
    return true
end

local function resolveRoute(routeId)
    local rid = tonumber(routeId)
    if rid then
        if Config.Routes[rid] then
            return rid, Config.Routes[rid]
        end

        if rid >= 0 and Config.Routes[rid + 1] then
            return rid + 1, Config.Routes[rid + 1]
        end
    end

    if type(routeId) == 'string' then
        local lowered = string.lower(routeId)
        for id, route in pairs(Config.Routes) do
            if type(route.label) == 'string' and string.lower(route.label) == lowered then
                return id, route
            end
        end
    end

    return nil, nil
end

local function isPlayerNearStartNpc(src, route)
    if not Config.StartNPC or Config.StartNPC.enabled == false then
        return true
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return false
    end

    local pCoords = GetEntityCoords(ped)
    if not pCoords then
        return false
    end

    local npcCfg = Config.StartNPC
    local types = Config.StartNPC.types
    if type(types) == 'table' then
        local routeType = (route and route.startNpcType) or (route and route.trainType) or 'metro'
        npcCfg = types[routeType] or types.default or Config.StartNPC
    end

    if not npcCfg or not npcCfg.coords then
        return true
    end

    local npc = npcCfg.coords
    local dx = (pCoords.x or 0.0) - (npc.x or 0.0)
    local dy = (pCoords.y or 0.0) - (npc.y or 0.0)
    local dz = (pCoords.z or 0.0) - (npc.z or 0.0)
    local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

    local allowedDistance = (tonumber(npcCfg.interactionDistance) or tonumber(Config.StartNPC.interactionDistance) or 2.0) + 1.5
    return dist <= allowedDistance
end

function MetroService.GetPlayerData(src, profileType)
    local identifier = ServerBridge.GetIdentifier(src)
    local charName = ServerBridge.GetCharacterName(src)
    return MetroStorage.Load(identifier, charName, Utils.NormalizeProfileType(profileType))
end

function MetroService.BuildPanelData(src, profileType)
    local pType = Utils.NormalizeProfileType(profileType)
    local key = cacheKey(src, pType)
    local cached = panelCache[key]
    if cached and (nowMs() - (cached.ts or 0)) <= PANEL_CACHE_TTL_MS then
        return cached.data
    end

    local companyMain = _L('ui_company_title_main')
    local companySub = _L('ui_company_title_sub')
    local hudEditorCfg = (Config.UI and Config.UI.hudEditor) or {}
    local toggleCommand = '/' .. tostring(hudEditorCfg.toggleCommand or 'godhud')
    local cancelKeyLabel = tostring((((Config.Runtime or {}).hud or {}).cancelKeyLabel) or '[G]')
    local data = MetroService.GetPlayerData(src, pType)
    refreshQuestPeriods(data)
    local xpData = syncXpFields(data)
    local xpCfg = getXpConfig()

    local ranks = {}
    for _, rankKey in ipairs(rankFlow) do
        local cfg = Config.Licenses.ranks[rankKey]
        if cfg then
            local rankLabel = localeOrFallback(('rank_label_%s'):format(rankKey), cfg.label)
            table.insert(ranks, {
                key = rankKey,
                label = rankLabel,
                multiplier = cfg.payoutMultiplier,
                unlockPrice = cfg.unlockPrice,
                unlocked = data.licenses and data.licenses[rankKey] == true,
                requirements = cfg.requirements,
                requirementsMet = canUnlockRank(data, rankKey),
                active = data.rank == rankKey
            })
        end
    end

    local quests = {}
    for _, def in ipairs(Config.Quests.definitions or {}) do
        if not questEnabled(def) then goto continue end
        if not questMatchesRouteType(def, pType) then goto continue end
        local state = data.quests[def.id] or { progress = 0, completed = false, claimed = false }
        table.insert(quests, {
            id = def.id,
            label = resolveQuestLabel(def),
            description = resolveQuestDescription(def),
            period = def.period,
            qtype = def.type,
            routeType = def.routeType or 'all',
            target = def.target,
            reward = def.reward,
            progress = state.progress or 0,
            completed = state.completed or false,
            claimed = state.claimed or false
        })
        ::continue::
    end

    local routes = {}
    local economy = Config.Economy or {}
    for routeId, route in pairs(Config.Routes or {}) do
        routes[#routes + 1] = {
            id = routeId,
            label = localeOrFallback(('route_label_%s'):format(routeId), _L('route_label_generic', routeId)),
            trainType = route.trainType or 'metro',
            category = resolveRouteCategory(route),
            stationOrder = route.stationOrder or {},
            targetKm = route.targetKm or 0,
            baseReward = route.baseReward or economy.completionReward or Config.Payout.baseReward,
            stopReward = economy.stopReward or 0,
            completionReward = route.baseReward or economy.completionReward or Config.Payout.baseReward,
            spawn = route.spawn
        }
    end

    table.sort(routes, function(a, b)
        return (a.id or 0) < (b.id or 0)
    end)

    local stationEarningBase = tonumber(economy.stopReward or 0) or 0
    local routeBonusBase = tonumber(economy.completionReward or Config.Payout.baseReward or 0) or 0
    for _, route in ipairs(routes) do
        if string.lower(tostring(route.category or route.trainType or 'metro')) == pType then
            stationEarningBase = tonumber(route.stopReward or stationEarningBase) or stationEarningBase
            routeBonusBase = tonumber(route.completionReward or routeBonusBase) or routeBonusBase
            break
        end
    end

    local panelData = {
        framework = ServerBridge.GetMode(),
        player = {
            name = data.char_name,
            rank = data.rank,
            totalKm = Utils.Round(data.total_km, 2),
            completedRoutes = data.completed_routes,
            accuracy = getAccuracy(data),
            goodStops = data.good_stops or 0,
            xp = data.xp_total or xpData.totalXp,
            level = data.player_level or xpData.level,
            levelProgress = Utils.Round(xpData.progress, 2)
        },
        ranks = ranks,
        quests = quests,
        routes = routes,
        ui = {
            companyTitleMain = companyMain,
            companyTitleSub = companySub,
            companyDescription = _L('ui_company_desc'),
            buyLicenseTitle = _L('ui_buy_license'),
            buyLicenseHint = _L('ui_buy_license_hint'),
            buttonQuests = _L('ui_btn_quests'),
            buttonRefresh = _L('ui_btn_refresh'),
            buttonClose = _L('ui_btn_close'),
            buttonTrain = _L('ui_btn_train'),
            buttonMetro = _L('ui_btn_metro'),
            xpLabel = _L('ui_xp'),
            levelShort = _L('ui_level_short'),
            playerLevelMeta = _L('player_level_meta'),
            rankUnlockProgress = _L('ui_rank_unlock_progress'),
            rankStateActive = _L('rank_state_active'),
            rankStateNext = _L('rank_state_next'),
            rankStateLocked = _L('rank_state_locked'),
            noRoutes = _L('ui_no_routes'),
            modalPaymentText = _L('ui_payment_text'),
            payCash = _L('ui_pay_cash'),
            payBank = _L('ui_pay_bank'),
            questTitle = _L('ui_quest_title'),
            questSubtitle = _L('ui_quest_subtitle'),
            noQuests = _L('ui_no_quests'),
            questClaimReady = _L('ui_quest_claim_ready'),
            questPeriodDaily = _L('ui_quest_period_daily'),
            questPeriodWeekly = _L('ui_quest_period_weekly'),
            rankStationEarning = _L('ui_station_earning'),
            rankRouteBonus = _L('ui_route_bonus'),
            rankButtonStart = _L('ui_rank_button_start'),
            rankButtonActive = _L('ui_rank_button_active'),
            rankButtonLocked = _L('ui_rank_button_locked'),
            rankButtonBuy = _L('ui_rank_button_buy'),
            hudTitle = pType == 'metro'
                and _L('hud_title_metro')
                or _L('hud_title_train'),
            hudNextStation = _L('ui_hud_next_station'),
            hudRouteComplete = _L('ui_hud_route_complete'),
            hudDistance = _L('ui_hud_distance'),
            hudKm = _L('ui_hud_km'),
            hudTotal = _L('ui_hud_total_mileage'),
            hudStops = _L('ui_hud_stops'),
            hudSpeedLimit = _L('ui_hud_speed_limit'),
            hudLiveEarnings = _L('ui_hud_live_earnings'),
            hudTotalEarned = _L('ui_hud_total_earned'),
            hudPenalty = _L('ui_hud_penalty'),
            hudRouteKm = _L('ui_hud_route_km'),
            hudXp = _L('ui_hud_xp'),
            hudPassengers = _L('ui_hud_passengers'),
            hudContainers = _L('ui_hud_containers'),
            hudCancelJob = _L('ui_hud_cancel_job'),
            hudCancelHold = _L('ui_hud_cancel_hold'),
            hudCityZone = _L('ui_hud_city_zone'),
            hudClear = _L('ui_hud_clear'),
            hudNoActiveCityZone = _L('ui_hud_no_active_city_zone'),
            hudCityZoneActive = _L('ui_hud_city_zone_active'),
            hudStatusFollowRoute = _L('hud_status_follow_route'),
            hudSubtitleStatic = _L('hud_status_follow_route'),
            hudAssistantTitle = _L('ui_hud_assistant_title'),
            assistantLoading = _L('ui_hud_assistant_loading'),
            assistantReady = _L('ui_hud_assistant_ready'),
            assistantTransit = _L('ui_hud_assistant_transit'),
            assistantCancelling = _L('ui_hud_assistant_cancelling'),
            assistantCancelJob = _L('ui_hud_assistant_cancel_job'),
            assistantMetroBoarding = _L('ui_hud_assistant_metro_boarding'),
            assistantMetroReady = _L('ui_hud_assistant_metro_ready'),
            assistantMetroTransit = _L('ui_hud_assistant_metro_transit'),
            assistantFreightLoading = _L('ui_hud_assistant_freight_loading'),
            assistantFreightReady = _L('ui_hud_assistant_freight_ready'),
            assistantFreightTransit = _L('ui_hud_assistant_freight_transit'),
            closeLabel = _L('ui_close_label'),
            interactLabel = _L('ui_interact_label'),
            showInHud = _L('ui_show_in_hud'),
            hideFromHud = _L('ui_hide_from_hud'),
            questTooltipLabel = _L('ui_quest_tooltip_label'),
            hudCommandHint = _L('ui_hud_command_hint', toggleCommand),
            hudCancelKeyLabel = cancelKeyLabel,
            xpLevelStep = xpCfg.levelStep,
            xpPerStop = xpCfg.perStop,
            xpPerRoute = xpCfg.perRoute,
            xpPerKm = xpCfg.perKm,
            stopXpReward = xpCfg.perStop,
            stationEarningBase = stationEarningBase,
            routeBonusBase = routeBonusBase,
            rankDescriptions = {
                trainee = _L('ui_rank_desc_trainee'),
                junior = _L('ui_rank_desc_junior'),
                senior = _L('ui_rank_desc_senior'),
                chief = _L('ui_rank_desc_chief')
            },
            profileType = pType
        }
    }

    panelCache[key] = {
        ts = nowMs(),
        data = panelData
    }

    return panelData
end

function MetroService.InvalidatePanelCache(src, profileType)
    if profileType then
        panelCache[cacheKey(src, Utils.NormalizeProfileType(profileType))] = nil
        return
    end

    panelCache[cacheKey(src, 'train')] = nil
    panelCache[cacheKey(src, 'metro')] = nil
end

local function buildRouteSettlementContext(session, route, payload)
    local routeStops = getRouteStopCount(route)
    local targetKm = tonumber(route.targetKm) or 0
    local reportedDistance = sanitizeNum(payload and payload.distance, 0, math.max(1, targetKm * 2.5))

    local trackedGoodStops = sanitizeNum(session and session.goodStops, 0, routeStops)
    local trackedMissedStops = sanitizeNum(session and session.missedStops, 0, routeStops)
    local completedStops = Utils.Clamp(trackedGoodStops + trackedMissedStops, 0, routeStops)

    local goodStops = Utils.Clamp(trackedGoodStops, 0, completedStops)
    local missedStops = Utils.Clamp(trackedMissedStops, 0, routeStops - goodStops)
    local wrongStops = sanitizeNum(session and session.wrongStops, 0, math.max(10, routeStops * 3))
    local passengerRevenue = sanitizeNum(payload and payload.passengerRevenue, 0, 1000000)
    local totalPassengerTrips = sanitizeNum(payload and payload.totalPassengerTrips, 0, 100000)
    local lateSeconds = sanitizeNum(payload and payload.lateSeconds, 0, 86400)
    local speedingSeconds = sanitizeNum(payload and payload.speedingSeconds, 0, 86400)
    local hardBrakeEvents = sanitizeNum(payload and payload.hardBrakeEvents, 0, 1000)
    local derailRiskEvents = sanitizeNum(payload and payload.derailRiskEvents, 0, 1000)
    local clientPenaltyAmount = sanitizeNum(payload and payload.penaltyAmount, 0, 1000000)
    local forceNoReward = payload and payload.forceNoReward == true

    local earlyExit = payload and payload.earlyExit == true
    local routeCompleted = completedStops >= routeStops and not earlyExit
    local stopProgressRatio = routeStops > 0 and (completedStops / routeStops) or 0.0
    local maxCreditableDistance = targetKm

    if not routeCompleted then
        maxCreditableDistance = math.max(0.25, targetKm * math.max(stopProgressRatio, 0.1) * 1.15)
    else
        maxCreditableDistance = math.max(1.0, targetKm * 1.1)
    end

    local distance = sanitizeNum(reportedDistance, 0, maxCreditableDistance)

    local rankCfg = getRankConfig(session.rankKey)
    local multiplier = sanitizeNum(rankCfg.payoutMultiplier or 1.0, 0.1, 10.0)

    local economy = Config.Economy or {}
    local partial = economy.partial or {}
    local antiAbuse = economy.antiAbuse or {}
    local stopReward = sanitizeNum(economy.stopReward or 0, 0, 100000)
    local completionReward = sanitizeNum(route.baseReward or economy.completionReward or Config.Payout.baseReward, 0, 999999999)

    local elapsedSeconds = math.max(0, os.time() - (session.startTs or os.time()))
    local minSecondsBeforeAnyPayout = sanitizeNum(antiAbuse.minSecondsBeforeAnyPayout, 0, 86400)
    local minSecondsPerStopCredit = sanitizeNum(antiAbuse.minSecondsPerStopCredit, 0, 3600)

    local stopsEligibleByTime = routeStops
    if minSecondsPerStopCredit > 0 then
        stopsEligibleByTime = math.floor(elapsedSeconds / minSecondsPerStopCredit)
    end
    stopsEligibleByTime = Utils.Clamp(stopsEligibleByTime, 0, routeStops)

    local payableGoodStops = math.min(goodStops, stopsEligibleByTime)
    if elapsedSeconds < minSecondsBeforeAnyPayout then
        payableGoodStops = 0
        routeCompleted = false
    end

    local payoutPositiveBase = 0
    local partialEligible = false
    local partialBlockedByMinStops = false

    if routeCompleted then
        payoutPositiveBase = completionReward + (payableGoodStops * stopReward)
    elseif partial.enabled ~= false and (not earlyExit or partial.allowOnEarlyExit ~= false) then
        local minStopsForPartial = sanitizeNum(partial.minCompletedStopsForPartial, 0, 100)
        local partialStopReward = sanitizeNum(partial.rewardPerCompletedStop or stopReward, 0, 100000)
        local maxPartialStops = sanitizeNum(partial.maxPayableStops or routeStops, 1, 100)

        if payableGoodStops >= minStopsForPartial then
            partialEligible = true
            local payablePartialStops = math.min(payableGoodStops, maxPartialStops)
            payoutPositiveBase = payablePartialStops * partialStopReward
        else
            partialBlockedByMinStops = true
        end
    end

    local payoutPositive = math.floor(payoutPositiveBase * multiplier)
    payoutPositive = math.floor(Utils.Clamp(payoutPositive, 0, Config.Security.maxRewardPerRoute or 25000))

    local penaltyCfg = Utils.GetPenaltyConfig(route.trainType)
    local latenessPenalty = 0
    if lateSeconds > 0 then
        local latePenaltyOnce = sanitizeNum(penaltyCfg.latePenaltyOnce, 0, 100000)
        local latePenaltyPerMinute = sanitizeNum(penaltyCfg.latePenaltyPerMinute, 0, 100000)
        latenessPenalty = latePenaltyOnce + math.floor((lateSeconds / 60.0) * latePenaltyPerMinute)
    end
    local speedingPenalty = math.floor(speedingSeconds * sanitizeNum(penaltyCfg.speedPenaltyPerSecond, 0, 10000))
    local hardBrakePenalty = hardBrakeEvents * sanitizeNum(penaltyCfg.hardBrakePenalty, 0, 100000)
    local derailPenalty = derailRiskEvents * sanitizeNum(penaltyCfg.derailRiskPenalty, 0, 100000)
    local dynamicPenaltyTotal = latenessPenalty + speedingPenalty + hardBrakePenalty + derailPenalty
    dynamicPenaltyTotal = math.max(dynamicPenaltyTotal, clientPenaltyAmount)

    if forceNoReward then
        payoutPositive = 0
        passengerRevenue = 0
        totalPassengerTrips = 0
    end

    return {
        distance = distance,
        routeStops = routeStops,
        completedStops = completedStops,
        goodStops = goodStops,
        missedStops = missedStops,
        wrongStops = wrongStops,
        earlyExit = earlyExit,
        routeCompleted = routeCompleted,
        elapsedSeconds = elapsedSeconds,
        payoutPositive = payoutPositive,
        passengerRevenue = passengerRevenue,
        totalPassengerTrips = totalPassengerTrips,
        lateSeconds = lateSeconds,
        speedingSeconds = speedingSeconds,
        hardBrakeEvents = hardBrakeEvents,
        derailRiskEvents = derailRiskEvents,
        dynamicPenaltyTotal = dynamicPenaltyTotal,
        partialEligible = partialEligible,
        partialBlockedByMinStops = partialBlockedByMinStops,
        minStopsForPartial = sanitizeNum(partial.minCompletedStopsForPartial, 0, 100),
        payableGoodStops = payableGoodStops,
        forceNoReward = forceNoReward
    }
end

function MetroService.RecordRouteStop(src, stopType, stationId)
    local session = routeSessions[src]
    if not session then
        return false, _L('err_no_active_route_session')
    end

    local route = Config.Routes[session.routeId]
    if not route or type(route.stationOrder) ~= 'table' then
        routeSessions[src] = nil
        return false, _L('err_invalid_route')
    end

    local normalizedType = string.lower(tostring(stopType or ''))
    if normalizedType == 'wrong' then
        session.wrongStops = sanitizeNum((session.wrongStops or 0) + 1, 0, math.max(10, #route.stationOrder * 3))
        return true
    end

    local expectedStationId = route.stationOrder[session.currentStationIdx]
    if expectedStationId == nil then
        return false, _L('err_invalid_route')
    end

    if tostring(expectedStationId) ~= tostring(stationId) then
        session.wrongStops = sanitizeNum((session.wrongStops or 0) + 1, 0, math.max(10, #route.stationOrder * 3))
        return false, _L('stop_wrong')
    end

    if normalizedType == 'good' then
        session.goodStops = sanitizeNum((session.goodStops or 0) + 1, 0, #route.stationOrder)
    elseif normalizedType == 'missed' then
        session.missedStops = sanitizeNum((session.missedStops or 0) + 1, 0, #route.stationOrder)
    else
        return false, _L('err_invalid_route')
    end

    session.currentStationIdx = session.currentStationIdx + 1
    return true
end

function MetroService.TryBuyLicense(src, rankKey, account, profileType)
    if not cooldownPassed(src, 'buy_license') then
        return false, _L('cooldown')
    end

    local rankCfg = Config.Licenses.ranks[rankKey]
    if not rankCfg then return false, _L('err_invalid_rank') end

    local pType = Utils.NormalizeProfileType(profileType)
    local data = MetroService.GetPlayerData(src, pType)

    data.licenses = data.licenses or {}
    if data.licenses[rankKey] then
        data.rank = rankKey
        MetroStorage.Save(data.identifier, data, pType)
        return true, _L('license_bought', rankCfg.label)
    end

    if not canUnlockRank(data, rankKey) then
        return false, _L('license_locked')
    end

    local moneyAccount = account == 'cash' and 'cash' or 'bank'
    local price = sanitizeNum(rankCfg.unlockPrice, 0, 999999999)
    if ServerBridge.GetMoney(src, moneyAccount) < price then
        return false, _L('not_enough_money', moneyAccount)
    end

    if price > 0 then
        local ok = ServerBridge.RemoveMoney(src, moneyAccount, price, ('metro-license-%s'):format(rankKey))
        if not ok then
            return false, _L('not_enough_money', moneyAccount)
        end
    end

    data.licenses[rankKey] = true
    data.rank = rankKey
    MetroStorage.SaveAsync(data.identifier, data, pType)
    MetroService.InvalidatePanelCache(src, pType)

    return true, _L('license_bought', rankCfg.label)
end

function MetroService.StartRoute(src, routeId, rankKey)
    if not cooldownPassed(src, 'start_route') then
        return false, _L('cooldown')
    end

    local resolvedRouteId, route = resolveRoute(routeId)
    if not route then return false, _L('err_route_not_found') end

    if not isPlayerNearStartNpc(src, route) then
        return false, _L('err_not_at_dispatcher')
    end

    if type(route.stationOrder) ~= 'table' or #route.stationOrder == 0 then
        return false, _L('err_route_no_stations')
    end

    local profileType = resolveRouteCategory(route)
    local data = MetroService.GetPlayerData(src, profileType)
    local selectedRank = rankKey or data.rank or Config.Licenses.defaultRank
    if not (data.licenses and data.licenses[selectedRank]) then
        return false, _L('license_locked')
    end

    if routeSessions[src] then
        return false, _L('err_route_session_active')
    end

    routeSessions[src] = {
        routeId = resolvedRouteId,
        rankKey = selectedRank,
        startTs = os.time(),
        profileType = profileType,
        currentStationIdx = 1,
        goodStops = 0,
        missedStops = 0,
        wrongStops = 0
    }

    return true, {
        routeId = resolvedRouteId,
        route = route,
        rank = selectedRank,
        stations = route.stationOrder,
        targetKm = route.targetKm
    }
end

function MetroService.GetEarlyFinishPreview(src, payload)
    local session = routeSessions[src]
    if not session then
        return false, _L('err_no_active_route_session')
    end

    local route = Config.Routes[session.routeId]
    if not route then
        return false, _L('err_invalid_route')
    end

    local settlement = buildRouteSettlementContext(session, route, payload)

    return true, {
        routeStops = settlement.routeStops,
        completedStops = settlement.completedStops,
        goodStops = settlement.goodStops,
        remainingStops = math.max(0, settlement.routeStops - settlement.completedStops),
        minStopsForEarlyFinish = settlement.minStopsForPartial,
        payout = settlement.payoutPositive,
        partialEligible = settlement.partialEligible,
        partialBlockedByMinStops = settlement.partialBlockedByMinStops,
        earlyExitNoPayout = settlement.payoutPositive <= 0,
        elapsedSeconds = settlement.elapsedSeconds,
        account = Config.Payout.currency == 'cash' and 'cash' or 'bank',
        distance = settlement.distance
    }
end

function MetroService.FinishRoute(src, payload)
    if not cooldownPassed(src, 'finish_route') then
        return false, _L('cooldown')
    end

    local session = routeSessions[src]
    if not session then
        return false, _L('err_no_active_route_session')
    end

    local route = Config.Routes[session.routeId]
    if not route then
        routeSessions[src] = nil
        return false, _L('err_invalid_route')
    end

    local settlement = buildRouteSettlementContext(session, route, payload)
    local payoutPositive = settlement.payoutPositive
    local tipReward, tipHits = rollPassengerTips(session.rankKey, settlement.payableGoodStops)

    local penalties = 0
    penalties = penalties + (settlement.missedStops * sanitizeNum(Config.Payout.missedStopPenalty, 0, 100000))
    penalties = penalties + (settlement.wrongStops * sanitizeNum(Config.Payout.wrongStopPenalty, 0, 100000))

    penalties = penalties + sanitizeNum(settlement.dynamicPenaltyTotal, 0, 1000000)

    local payout = payoutPositive + tipReward + sanitizeNum(settlement.passengerRevenue, 0, 1000000) - penalties
    payout = math.floor(Utils.Clamp(payout, 0, Config.Security.maxRewardPerRoute or 25000))

    if settlement.earlyExit and payout <= 0 then
        tipReward = 0
        tipHits = 0
    end

    if settlement.forceNoReward then
        payout = 0
        tipReward = 0
        tipHits = 0
    end

    local pType = Utils.NormalizeProfileType(session.profileType)
    local data = MetroService.GetPlayerData(src, pType)

    if not settlement.forceNoReward then
        data.total_km = Utils.Round((data.total_km or 0) + settlement.distance, 2)
        data.total_stops = (data.total_stops or 0) + settlement.completedStops
        data.good_stops = (data.good_stops or 0) + settlement.goodStops
        if settlement.routeCompleted then
            data.completed_routes = (data.completed_routes or 0) + 1
        end
    end
    local previousLevel = tonumber(data.player_level) or 1
    syncXpFields(data)
    local currentLevel = tonumber(data.player_level) or previousLevel

    if not settlement.forceNoReward then
        updateQuestProgress(data, {
            distance = settlement.distance,
            goodStops = settlement.goodStops,
            routeCompleted = settlement.routeCompleted,
            routeType = resolveRouteCategory(route)
        })
    end

    local payoutAccount = Config.Payout.currency == 'cash' and 'cash' or 'bank'
    if payout > 0 then
        ServerBridge.AddMoney(src, payoutAccount, payout, 'metro-route-payout')
    end

    MetroStorage.Save(data.identifier, data, pType)
    MetroService.InvalidatePanelCache(src, pType)
    routeSessions[src] = nil

    return true, {
        payout = payout,
        tipReward = tipReward,
        tipHits = tipHits,
        passengerRevenue = settlement.passengerRevenue,
        totalPassengerTrips = settlement.totalPassengerTrips,
        lateSeconds = settlement.lateSeconds,
        speedingSeconds = settlement.speedingSeconds,
        hardBrakeEvents = settlement.hardBrakeEvents,
        derailRiskEvents = settlement.derailRiskEvents,
        penaltyAmount = penalties,
        goodStops = settlement.goodStops,
        completedStops = settlement.completedStops,
        routeStops = settlement.routeStops,
        routeCompleted = settlement.routeCompleted,
        partialEligible = settlement.partialEligible,
        partialBlockedByMinStops = settlement.partialBlockedByMinStops,
        earlyExit = settlement.earlyExit,
        forceNoReward = settlement.forceNoReward,
        elapsedSeconds = settlement.elapsedSeconds,
        account = payoutAccount,
        totalKm = data.total_km,
        completedRoutes = data.completed_routes,
        accuracy = getAccuracy(data),
        xp = data.xp_total or 0,
        level = data.player_level or 1
    }
end

function MetroService.ClaimQuest(src, questId, profileType)
    if not cooldownPassed(src, 'claim_quest') then
        return false, _L('cooldown')
    end

    local pType = Utils.NormalizeProfileType(profileType)
    local data = MetroService.GetPlayerData(src, pType)
    refreshQuestPeriods(data)

    local def = nil
    for _, q in ipairs(Config.Quests.definitions or {}) do
        if not questEnabled(q) then goto continue end
        if q.id == questId then
            def = q
            break
        end
        ::continue::
    end

    if not def then return false, _L('err_quest_not_found') end

    local state = data.quests[questId]
    if not state or not state.completed or state.claimed then
        return false, _L('err_quest_not_claimable')
    end

    local reward = sanitizeNum(def.reward, 0, 1000000)
    local account = Config.Payout.currency == 'cash' and 'cash' or 'bank'
    ServerBridge.AddMoney(src, account, reward, 'metro-quest-reward')

    state.claimed = true
    data.claimed_rewards[questId] = true
    MetroStorage.Save(data.identifier, data, pType)
    MetroService.InvalidatePanelCache(src, pType)

    return true, {
        reward = reward,
        account = account
    }
end

AddEventHandler('playerDropped', function()
    routeSessions[source] = nil
    eventCooldowns[source] = nil
    MetroService.InvalidatePanelCache(source)
end)
