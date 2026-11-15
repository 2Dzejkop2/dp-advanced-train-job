local QB = nil

local M = {}

function M.Init()
    QB = exports['qb-core']:GetCoreObject()
end

function M.GetIdentifier(src)
    local player = QB.Functions.GetPlayer(src)
    return player and player.PlayerData.citizenid or ('src:%s'):format(src)
end

function M.GetCharacterName(src)
    local player = QB.Functions.GetPlayer(src)
    if not player then return ('Player %s'):format(src) end
    local pd = player.PlayerData
    return (pd.charinfo.firstname or '') .. ' ' .. (pd.charinfo.lastname or '')
end

function M.GetMoney(src, account)
    local player = QB.Functions.GetPlayer(src)
    if not player then return 0 end
    return player.PlayerData.money[account] or 0
end

function M.RemoveMoney(src, account, amount, reason)
    local player = QB.Functions.GetPlayer(src)
    if not player then return false end
    return player.Functions.RemoveMoney(account, amount, reason or 'godtrain-remove')
end

function M.AddMoney(src, account, amount, reason)
    local player = QB.Functions.GetPlayer(src)
    if not player then return false end
    return player.Functions.AddMoney(account, amount, reason or 'godtrain-add')
end

function M.Notify(src, message, nType)
    TriggerClientEvent('QBCore:Notify', src, message, nType or 'primary')
end

ServerBridgeImpl = ServerBridgeImpl or {}
ServerBridgeImpl.qb = M
