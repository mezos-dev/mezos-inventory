-- Using items (UI double-click / context menu / hotbar keys).

--- qb-inventory signature: UseItem(itemName, source, item, ...).
--- qb-core's QBCore.Functions.UseItem calls UseItem(source, item) — both orders are accepted.
function UseItem(a, b, c, ...)
    local itemName, source, item
    if type(a) == 'string' then
        itemName, source, item = a, b, c
    else
        source, item = a, b
        itemName = type(item) == 'table' and item.name or item
        if type(item) ~= 'table' then item = GetItemByName(source, itemName) end
    end
    if type(itemName) ~= 'string' or not source then return false end
    item = item or {}
    local usable = QBCore.Functions.CanUseItem(itemName)
    local hookData = buildHookData('ItemUsed', source, GetQBPlayer(source), item)
    if TriggerHook('ItemUsed', item.type, hookData) == false then return false end
    if type(usable) == 'table' and usable.func then
        usable.func(source, item, ...)
    elseif type(usable) == 'function' or (type(usable) == 'table' and rawget(usable, '__cfx_functionReference')) then
        usable(source, item, ...)
    end
    RefreshInventorySnapshot(hookData, 'sourceInventory', source)
    TriggerListener('ItemUsed', item.type, hookData)
end

local function showCard(src, template, args)
    local pos = PlayerCoords(src)
    for _, id in pairs(QBCore.Functions.GetPlayers()) do
        if #(pos - PlayerCoords(id)) < 3.0 then
            TriggerClientEvent('chat:addMessage', id, { template = template, args = args })
        end
    end
end

local ID_TEMPLATE = '<div class="chat-message advert" style="background: linear-gradient(to right, rgba(5, 5, 5, 0.6), #74807c); display: flex;"><div style="margin-right: 10px;"><i class="far fa-id-card" style="height: 100%;"></i><strong> {0}</strong><br> <strong>Civ ID:</strong> {1} <br><strong>First Name:</strong> {2} <br><strong>Last Name:</strong> {3} <br><strong>Birthdate:</strong> {4} <br><strong>Gender:</strong> {5} <br><strong>Nationality:</strong> {6}</div></div>'
local DL_TEMPLATE = '<div class="chat-message advert" style="background: linear-gradient(to right, rgba(5, 5, 5, 0.6), #657175); display: flex;"><div style="margin-right: 10px;"><i class="far fa-id-card" style="height: 100%;"></i><strong> {0}</strong><br> <strong>First Name:</strong> {1} <br><strong>Last Name:</strong> {2} <br><strong>Birth Date:</strong> {3} <br><strong>Licenses:</strong> {4}</div></div>'

--- Returns ok, err, shouldClose
function UseSlot(src, slot)
    local player = GetQBPlayer(src)
    if not player or IsIncapacitated(player) then return false, 'busy' end
    local box = PlayerBox(src, player)
    slot = tonumber(slot)
    local itemData = slot and box.items[slot]
    if not itemData then return false, 'missing' end
    local def = Utils.ItemDef(itemData.name)
    if not def then return false, 'missing' end

    -- durability
    if Decay.RefreshItems(box.items) then CommitBox(box) itemData = box.items[slot] if not itemData then return false, 'spoiled' end end
    if Decay.IsSpoiled(itemData) then return false, 'spoiled' end

    if itemData.type == 'weapon' then
        local hookData = buildHookData('ItemUsed', src, player, itemData)
        if TriggerHook('ItemUsed', itemData.type, hookData) == false then return false, 'blocked' end
        local q = tonumber(itemData.info and itemData.info.quality) or 100
        TriggerClientEvent('qb-weapons:client:UseWeapon', src, itemData, q > 0)
        TriggerClientEvent('qb-inventory:client:ItemBox', src, def, 'use')
        TriggerListener('ItemUsed', itemData.type, hookData)
        return true, nil, true
    end

    local info = itemData.info or {}
    if itemData.name == 'id_card' then
        if UseItem(itemData.name, src, itemData) == false then return false, 'blocked' end
        showCard(src, ID_TEMPLATE, { 'ID Card', info.citizenid, info.firstname, info.lastname, info.birthdate, info.gender == 0 and 'Male' or 'Female', info.nationality })
    elseif itemData.name == 'driver_license' then
        if UseItem(itemData.name, src, itemData) == false then return false, 'blocked' end
        showCard(src, DL_TEMPLATE, { 'Drivers License', info.firstname, info.lastname, info.birthdate, info.type })
    else
        if not QBCore.Functions.CanUseItem(itemData.name) then return false, 'notUsable' end
        if UseItem(itemData.name, src, itemData) == false then return false, 'blocked' end
    end
    TriggerClientEvent('qb-inventory:client:ItemBox', src, def, 'use')
    return true, nil, def.shouldClose
end

QBCore.Functions.CreateCallback('mezos-inventory:server:use', function(src, cb, req)
    if type(req) ~= 'table' or not RateOk(src, 'use', 5) then return cb({ ok = false, err = 'rate' }) end
    local ok, err, close = UseSlot(src, req.slot)
    cb({ ok = ok, err = err, close = close })
end)

-- Hotbar keys (inventory closed)
RegisterNetEvent('mezos-inventory:server:useSlot', function(slot)
    local src = source
    if not RateOk(src, 'use', 5) then return end
    slot = Utils.Int(slot)
    if not slot or (slot > 100 and not Utils.IsEquipSlot(slot)) then return end
    if Player(src).state.inv_busy and not MZ.Open[src] then return end
    local ok, err = UseSlot(src, slot)
    if not ok and err == 'spoiled' then Notify(src, Lang:t('notify.spoiled'), 'error') end
end)

-- Legacy event some scripts fire with an item table
RegisterNetEvent('qb-inventory:server:useItem', function(item)
    local src = source
    if type(item) ~= 'table' or not RateOk(src, 'use', 5) then return end
    UseSlot(src, item.slot)
end)

-- Weapon attachments (qb-weapons owns the logic, we just relay and refresh)
QBCore.Functions.CreateCallback('mezos-inventory:server:weaponInfo', function(src, cb, slot)
    local item = GetItemBySlot(src, slot)
    if not item or item.type ~= 'weapon' then return cb(false) end
    cb(item)
end)
