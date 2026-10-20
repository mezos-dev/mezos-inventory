-- Incoming trade requests. The request shows as a banner when you open your inventory,
-- and can also be answered with /tradeaccept or /tradedecline.

PendingTrade = nil

RegisterNetEvent('mezos-inventory:client:tradeIncoming', function(data)
    if type(data) ~= 'table' or not data.id then return end
    PendingTrade = data
    if Client.open then SendNUIMessage({ action = 'tradeIncoming', trade = data }) end
    SetTimeout(30000, function()
        if PendingTrade and PendingTrade.id == data.id then
            PendingTrade = nil
            SendNUIMessage({ action = 'tradeIncoming', trade = false })
        end
    end)
end)

RegisterNetEvent('mezos-inventory:client:tradeEnded', function(id)
    if PendingTrade and PendingTrade.id == id then PendingTrade = nil end
    SendNUIMessage({ action = 'tradeIncoming', trade = false })
end)

RegisterCommand('tradeaccept', function()
    if not PendingTrade then return end
    TriggerServerEvent('mezos-inventory:server:tradeRespond', PendingTrade.id, true)
    PendingTrade = nil
end, false)

RegisterCommand('tradedecline', function()
    if not PendingTrade then return end
    TriggerServerEvent('mezos-inventory:server:tradeRespond', PendingTrade.id, false)
    PendingTrade = nil
end, false)
