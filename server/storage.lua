MetroStorage = {}

local DEFAULT_DB_TABLE_BY_TYPE = {
    train = 'god_advanced_train_job_players_train',
    metro = 'god_advanced_train_job_players_metro'
}

local cache = {}
local dbSchemaEnsured = {}
local STANDALONE_FILE = 'data/standalone_players.json'

local function getDbTableName(profileType)
    local pType = Utils.NormalizeProfileType(profileType)
    local tableByType = Config.Persistence and Config.Persistence.dbTableByType
    if type(tableByType) == 'table' then
        local mapped = tableByType[pType]
        if type(mapped) == 'string' and mapped:match('^[%w_]+$') then
            return mapped
        end
    end
    return DEFAULT_DB_TABLE_BY_TYPE[pType]
end

local function mysqlAvailable()
    return Framework.IsDbEnabled() and type(MySQL) == 'table' and MySQL.single and MySQL.update
end

local function getStandaloneKey(identifier, profileType)
    local pType = Utils.NormalizeProfileType(profileType)
    if pType == 'train' then
        return tostring(identifier)
    end
    return ('%s:%s'):format(tostring(identifier), pType)
end

local function loadStandaloneStore()
    local raw = LoadResourceFile(GetCurrentResourceName(), STANDALONE_FILE)
    if not raw or raw == '' then
        return {}
    end

    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then
        return decoded
    end

    return {}
end

local function saveStandaloneStore(store)
    local ok, payload = pcall(json.encode, store or {})
    SaveResourceFile(GetCurrentResourceName(), STANDALONE_FILE, ok and payload or '{}', -1)
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

local function calculateXpAndLevel(data)
    local xpCfg = getXpConfig()
    local xp = math.floor(
        ((tonumber(data.good_stops) or 0) * xpCfg.perStop) +
        ((tonumber(data.completed_routes) or 0) * xpCfg.perRoute) +
        ((tonumber(data.total_km) or 0) * xpCfg.perKm)
    )
    local levelStep = math.max(1, tonumber(xpCfg.levelStep) or 500)
    local level = math.max(1, math.floor(xp / levelStep) + 1)
    return xp, level
end

local function ensureDbSchemaForTable(tableName)
    local columns = {
        { name = 'xp_total', ddl = 'ALTER TABLE `%s` ADD COLUMN `xp_total` INT NOT NULL DEFAULT 0 AFTER `good_stops`' },
        { name = 'player_level', ddl = 'ALTER TABLE `%s` ADD COLUMN `player_level` INT NOT NULL DEFAULT 1 AFTER `xp_total`' }
    }

    for _, column in ipairs(columns) do
        local exists = MySQL.single.await(
            'SELECT 1 AS found FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ? LIMIT 1',
            { tableName, column.name }
        )

        if not exists then
            MySQL.update.await(column.ddl:format(tableName))
        end
    end
end

local function ensureDbSchema(profileType)
    if not mysqlAvailable() then
        return
    end

    local tableName = getDbTableName(profileType)
    if dbSchemaEnsured[tableName] then
        return
    end

    ensureDbSchemaForTable(tableName)

    dbSchemaEnsured[tableName] = true
end

local function decode(content)
    if not content or content == '' then return {} end
    local ok, result = pcall(json.decode, content)
    if ok and type(result) == 'table' then
        return result
    end
    return {}
end

local function encode(data)
    local ok, result = pcall(json.encode, data or {})
    return ok and result or '{}'
end

local function defaultData(identifier, charName)
    local defaultRank = Config.Licenses.defaultRank or 'trainee'
    return {
        identifier = identifier,
        char_name = charName or identifier,
        rank = defaultRank,
        total_km = 0.0,
        completed_routes = 0,
        total_stops = 0,
        good_stops = 0,
        xp_total = 0,
        player_level = 1,
        licenses = {
            [defaultRank] = true
        },
        quests = {},
        claimed_rewards = {},
        updated_at = os.time()
    }
end

function MetroStorage.Load(identifier, charName, profileType)
    local pType = Utils.NormalizeProfileType(profileType)
    local cacheKey = ('%s:%s'):format(identifier, pType)
    if cache[cacheKey] then
        return Utils.DeepCopy(cache[cacheKey])
    end

    local data = nil

    if mysqlAvailable() then
        ensureDbSchema(pType)
        local row = MySQL.single.await(('SELECT * FROM `%s` WHERE identifier = ?'):format(getDbTableName(pType)), { identifier })
        if row then
            local fallbackData = {
                total_km = row.total_km or 0.0,
                completed_routes = row.completed_routes or 0,
                good_stops = row.good_stops or 0
            }
            local fallbackXp, fallbackLevel = calculateXpAndLevel(fallbackData)
            data = {
                identifier = row.identifier,
                char_name = row.char_name,
                rank = row.rank,
                total_km = row.total_km or 0.0,
                completed_routes = row.completed_routes or 0,
                total_stops = row.total_stops or 0,
                good_stops = row.good_stops or 0,
                xp_total = row.xp_total or fallbackXp,
                player_level = row.player_level or fallbackLevel,
                licenses = decode(row.licenses_json),
                quests = decode(row.quests_json),
                claimed_rewards = decode(row.claimed_rewards_json),
                updated_at = row.updated_at or os.time()
            }
        end
    end

    if not data then
        if not mysqlAvailable() then
            local store = loadStandaloneStore()
            local key = getStandaloneKey(identifier, pType)
            local existing = store[key]
            if not existing and pType == 'train' then
                existing = store[tostring(identifier)]
            end
            if type(existing) == 'table' then
                data = existing
            end
        end
    end

    if not data then
        data = defaultData(identifier, charName)
        if mysqlAvailable() then
            MetroStorage.Save(identifier, data, pType)
        else
            local store = loadStandaloneStore()
            store[getStandaloneKey(identifier, pType)] = data
            saveStandaloneStore(store)
        end
    end

    cache[cacheKey] = Utils.DeepCopy(data)
    return Utils.DeepCopy(data)
end

function MetroStorage.Save(identifier, data, profileType)
    local pType = Utils.NormalizeProfileType(profileType)
    local cacheKey = ('%s:%s'):format(identifier, pType)
    data.updated_at = os.time()

    if data.xp_total == nil or data.player_level == nil then
        local xp, level = calculateXpAndLevel(data)
        data.xp_total = xp
        data.player_level = level
    end

    cache[cacheKey] = Utils.DeepCopy(data)

    if mysqlAvailable() then
        ensureDbSchema(pType)
        MySQL.update.await(([[
            INSERT INTO `%s`
            (identifier, char_name, rank, total_km, completed_routes, total_stops, good_stops, xp_total, player_level, licenses_json, quests_json, claimed_rewards_json, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
            char_name = VALUES(char_name),
            rank = VALUES(rank),
            total_km = VALUES(total_km),
            completed_routes = VALUES(completed_routes),
            total_stops = VALUES(total_stops),
            good_stops = VALUES(good_stops),
            xp_total = VALUES(xp_total),
            player_level = VALUES(player_level),
            licenses_json = VALUES(licenses_json),
            quests_json = VALUES(quests_json),
            claimed_rewards_json = VALUES(claimed_rewards_json),
            updated_at = VALUES(updated_at)
        ]]):format(getDbTableName(pType)), {
            identifier,
            data.char_name,
            data.rank,
            data.total_km,
            data.completed_routes,
            data.total_stops,
            data.good_stops,
            data.xp_total,
            data.player_level,
            encode(data.licenses),
            encode(data.quests),
            encode(data.claimed_rewards),
            data.updated_at
        })
    else
        local store = loadStandaloneStore()
        store[getStandaloneKey(identifier, pType)] = data
        saveStandaloneStore(store)
    end
end

function MetroStorage.SaveAsync(identifier, data, profileType)
    local pType = Utils.NormalizeProfileType(profileType)
    local cacheKey = ('%s:%s'):format(identifier, pType)

    data.updated_at = os.time()
    if data.xp_total == nil or data.player_level == nil then
        local xp, level = calculateXpAndLevel(data)
        data.xp_total = xp
        data.player_level = level
    end

    cache[cacheKey] = Utils.DeepCopy(data)

    local snapshot = Utils.DeepCopy(data)
    CreateThread(function()
        MetroStorage.Save(identifier, snapshot, pType)
    end)
end

function MetroStorage.DeleteCache(identifier, profileType)
    if profileType then
        local pType = Utils.NormalizeProfileType(profileType)
        cache[('%s:%s'):format(identifier, pType)] = nil
        return
    end

    cache[('%s:train'):format(identifier)] = nil
    cache[('%s:metro'):format(identifier)] = nil
end
