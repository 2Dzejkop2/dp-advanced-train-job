local QBX = nil

local M = {}

function M.Init()
    QBX = exports.qbx_core
end

function M.GetIdentifier(src)
    local player = QBX:GetPlayer(src)
    return player and player.PlayerData.citizenid or ('src:%s'):format(src)
end

function M.GetCharacterName(src)
    local player = QBX:GetPlayer(src)
    if not player then return ('Player %s'):format(src) end
    local char = player.PlayerData.charinfo or {}
    return (char.firstname or '') .. ' ' .. (char.lastname or '')
end

function M.GetMoney(src, account)
    local player = QBX:GetPlayer(src)
    if not player then return 0 end
    return player.PlayerData.money[account] or 0
end

function M.RemoveMoney(src, account, amount, reason)
    local player = QBX:GetPlayer(src)
    if not player then return false end
    return player.Functions.RemoveMoney(account, amount, reason or 'godtrain-remove')
end

function M.AddMoney(src, account, amount, reason)
    local player = QBX:GetPlayer(src)
    if not player then return false end
    return player.Functions.AddMoney(account, amount, reason or 'godtrain-add')
end

function M.Notify(src, message, nType)
    TriggerClientEvent('ox_lib:notify', src, {
        description = message,
        type = nType or 'inform'
    })
end

ServerBridgeImpl = ServerBridgeImpl or {}
ServerBridgeImpl.qbox = M
