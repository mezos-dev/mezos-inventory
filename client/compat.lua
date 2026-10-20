-- qb-inventory client compatibility: exports, events, vending targets.

local function export(name, fn)
    exports(name, fn)
    AddEventHandler(('__cfx_export_qb-inventory_%s'):format(name), function(setCB) setCB(fn) end)
end

--- Same semantics as qb-inventory (string | array | { name = amount }).
function HasItem(items, amount)
    local inv = PlayerData and PlayerData.items
    if type(inv) ~= 'table' then return false end
    local function count(name)
        local c = 0
        for _, it in pairs(inv) do if type(it) == 'table' and it.name == name then c = c + (tonumber(it.amount) or 0) end end
        return c
    end
    if type(items) == 'string' then
        local c = count(items)
        if amount then return c >= amount end
        return c > 0
    end
    if type(items) ~= 'table' then return false end
    if table.type(items) == 'array' then
        for _, name in ipairs(items) do
            local c = count(name)
            if (amount and c < amount) or (not amount and c <= 0) then return false end
        end
        return true
    end
    for name, need in pairs(items) do
        if count(name) < (tonumber(need) or 1) then return false end
    end
    return true
end

export('HasItem', HasItem)
export('IsOpen', function() return Client.open end)
export('GetPlayerItems', function() return PlayerData and PlayerData.items or {} end)

-- ───────────── events other resources fire ─────────────

local function itemBox(itemData, typ, amount)
    if type(itemData) ~= 'table' then return end
    local d = Decorate(itemData)
    if not d then
        d = { name = itemData.name, label = itemData.label or itemData.name, image = itemData.image or 'placeholder.png', rarity = 'common' }
    end
    SendNUIMessage({ action = 'itembox', item = d, type = typ or 'add', amount = tonumber(amount) or 1 })
end

RegisterNetEvent('qb-inventory:client:ItemBox', itemBox)
RegisterNetEvent('inventory:client:ItemBox', itemBox) -- legacy name some scripts still use

RegisterNetEvent('qb-inventory:client:requiredItems', function(items, show)
    local list = {}
    if show and type(items) == 'table' then
        for _, v in pairs(items) do
            local def = Utils.ItemDef(v.name)
            list[#list + 1] = {
                name = v.name,
                label = def and def.label or v.name,
                image = v.image or (def and def.image) or 'placeholder.png',
                have = HasItem(v.name),
            }
        end
    end
    SendNUIMessage({ action = 'required', items = list, show = show == true })
end)

RegisterNetEvent('qb-inventory:client:closeInv', function()
    if Client.open then CloseUI(true) end
end)

RegisterNetEvent('qb-inventory:client:updateInventory', function()
    if Client.open then
        SendNUIMessage({ action = 'player', player = PlayerView() })
    end
end)

-- Legacy direct open (items, other) – route through the server so it is validated
RegisterNetEvent('qb-inventory:client:openInventory', function()
    if not Client.open then RequestOpen() end
end)

RegisterNetEvent('qb-inventory:server:RobPlayer', function() end)

-- qb-weapons fires this on the wrong name; forward it
RegisterNetEvent('qb-inventory:client:CheckWeapon', function(weaponName)
    TriggerEvent('qb-weapons:client:CheckWeapon', weaponName)
end)

-- ───────────── vending machines ─────────────

CreateThread(function()
    if GetResourceState('qb-target') == 'missing' then return end
    while GetResourceState('qb-target') ~= 'started' do Wait(500) end
    exports['qb-target']:AddTargetModel(Config.VendingObjects, {
        options = {
            {
                icon = 'fa-solid fa-cash-register',
                label = Lang:t('interact.vending'),
                action = function(entity)
                    local c = GetEntityCoords(entity)
                    TriggerServerEvent('mezos-inventory:server:openVending', { x = c.x, y = c.y, z = c.z })
                end,
            },
        },
        distance = 2.5,
    })
end)
