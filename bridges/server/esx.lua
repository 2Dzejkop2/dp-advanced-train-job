local ESX = nil

local M = {}

function M.Init()
    ESX = exports['es_extended']:getSharedObject()
end

function M.GetIdentifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.getIdentifier() or ('src:%s'):format(src)
end

function M.GetCharacterName(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return ('Player %s'):format(src) end
    return xPlayer.getName() or ('Player %s'):format(src)
end

function M.GetMoney(src, account)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return 0 end
    if account == 'cash' then
        return xPlayer.getMoney()
    end
    local acc = xPlayer.getAccount(account)
    return acc and acc.money or 0
end

function M.RemoveMoney(src, account, amount, reason)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    if account == 'cash' then
        xPlayer.removeMoney(amount, reason or 'godtrain-remove')
    else
        xPlayer.removeAccountMoney(account, amount, reason or 'godtrain-remove')
    end
    return true
end

function M.AddMoney(src, account, amount, reason)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    if account == 'cash' then
        xPlayer.addMoney(amount, reason or 'godtrain-add')
    else
        xPlayer.addAccountMoney(account, amount, reason or 'godtrain-add')
    end
    return true
end

function M.Notify(src, message, nType)
    TriggerClientEvent('esx:showNotification', src, message, nType or 'info')
end

ServerBridgeImpl = ServerBridgeImpl or {}
ServerBridgeImpl.esx = M
