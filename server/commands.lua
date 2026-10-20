-- Admin commands (same names as qb-inventory)

local function defaultInfo(def, player)
    local info = {}
    local ci = player.PlayerData.charinfo
    if def.name == 'id_card' then
        info.citizenid = player.PlayerData.citizenid
        info.firstname, info.lastname, info.birthdate = ci.firstname, ci.lastname, ci.birthdate
        info.gender, info.nationality = ci.gender, ci.nationality
    elseif def.name == 'driver_license' then
        info.firstname, info.lastname, info.birthdate = ci.firstname, ci.lastname, ci.birthdate
        info.type = 'Class C Driver License'
    elseif def.name == 'harness' then
        info.uses = 20
    elseif def.name == 'markedbills' then
        info.worth = math.random(5000, 10000)
    end
    return info
end

QBCore.Commands.Add('giveitem', 'Give An Item (Admin Only)', {
    { name = 'id', help = 'Player ID' },
    { name = 'item', help = 'Name of the item (not a label)' },
    { name = 'amount', help = 'Amount of items' },
}, false, function(source, args)
    local id = tonumber(args[1])
    local player = id and GetQBPlayer(id)
    local amount = Utils.Int(tonumber(args[3]) or 1, 100000) or 1
    local def = Utils.ItemDef(tostring(args[2]))
    if not player then return QBCore.Functions.Notify(source, 'Player is not online', 'error') end
    if not def then return QBCore.Functions.Notify(source, 'Item does not exist', 'error') end
    if def.type == 'weapon' then amount = 1 end
    if AddItem(id, def.name, amount, false, defaultInfo(def, player), 'give item command') then
        QBCore.Functions.Notify(source, ('You have given %s %dx %s'):format(GetPlayerName(id), amount, def.label), 'success')
        TriggerClientEvent('qb-inventory:client:ItemBox', id, def, 'add', amount)
    else
        QBCore.Functions.Notify(source, 'Can\'t give item!', 'error')
    end
end, 'admin')

QBCore.Commands.Add('randomitems', 'Receive random items', {}, false, function(source)
    local pool = {}
    for _, v in pairs(QBCore.Shared.Items) do
        if v.type ~= 'weapon' then pool[#pool + 1] = v end
    end
    for _ = 1, 10 do
        local def = pool[math.random(1, #pool)]
        local amount = def.unique and 1 or math.random(1, 10)
        if AddItem(source, def.name, amount, nil, nil, 'random items command') then
            TriggerClientEvent('qb-inventory:client:ItemBox', source, def, 'add', amount)
        end
        Wait(250)
    end
end, 'god')

QBCore.Commands.Add('clearinv', 'Clear Inventory (Admin Only)', { { name = 'id', help = 'Player ID' } }, false, function(source, args)
    ClearInventory(tonumber(args[1]) or source)
end, 'admin')

QBCore.Commands.Add('openstash', 'Open any stash by name (Admin Only)', { { name = 'name', help = 'Stash identifier' } }, true, function(source, args)
    if not args[1] then return end
    OpenInventory(source, args[1])
end, 'admin')

RegisterCommand('closeInv', function(source)
    if source > 0 then CloseSession(source) end
end, false)
