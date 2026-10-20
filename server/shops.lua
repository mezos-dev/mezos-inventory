-- Shops (qb-inventory CreateShop / OpenShop API) and vending machines.

local function setupShopItems(list)
    local items, slot = {}, 1
    for _, it in pairs(list or {}) do
        local def = type(it) == 'table' and Utils.ItemDef(it.name)
        if def then
            items[slot] = {
                name = def.name,
                amount = tonumber(it.amount) or 0,
                info = type(it.info) == 'table' and it.info or {},
                label = def.label,
                description = def.description or '',
                weight = def.weight or 0,
                type = def.type,
                unique = def.unique,
                useable = def.useable,
                price = tonumber(it.price) or 0,
                image = def.image,
                slot = slot,
                requiredJob = it.requiredJob,
                requiredGrade = it.requiredGrade,
            }
            slot = slot + 1
        end
    end
    return items
end

local function register(name, data)
    MZ.Shops[name] = {
        name = name,
        label = data.label or name,
        coords = data.coords,
        slots = #(data.items or {}),
        items = setupShopItems(data.items),
        type = data.type,
    }
end

function CreateShop(shopData)
    if type(shopData) ~= 'table' then return end
    if shopData.name then
        register(shopData.name, shopData)
        return
    end
    for key, data in pairs(shopData) do
        if type(data) == 'table' then
            if data.name then
                register(type(key) == 'number' and data.name or key, data)
            else
                CreateShop(data)
            end
        end
    end
end

function OpenShop(source, name)
    if not name then return end
    local player = GetQBPlayer(source)
    local shop = MZ.Shops[name]
    if not player or not shop then return end
    if shop.coords then
        local c = vector3(shop.coords.x, shop.coords.y, shop.coords.z)
        if #(PlayerCoords(source) - c) > Config.ShopDistance then return end
    end
    local hookData = buildHookData('ShopOpened', source, player, name)
    if TriggerHook('ShopOpened', GetInventoryType(name), hookData) == false then return end
    local other = { kind = 'shop', id = 'shop-' .. name, shop = name, label = shop.label }
    local ok
    if MZ.Open[source] then ok = SwitchOther(source, other) else ok = OpenSession(source, other, { force = false }) end
    if ok ~= false then TriggerListener('ShopOpened', GetInventoryType(name), hookData) end
end

QBCore.Functions.CreateCallback('mezos-inventory:server:purchase', function(src, cb, req)
    local function done(ok, err) cb({ ok = ok, err = err, other = OtherPayload(src) }) end
    if type(req) ~= 'table' or not RateOk(src, 'buy', 4) then return done(false, 'rate') end
    local s = MZ.Open[src]
    local o = s and s.other
    if not o or o.kind ~= 'shop' then return done(false, 'closed') end
    if not SessionInRange(src, o) then return done(false, 'tooFar') end
    local shop = MZ.Shops[o.shop]
    local player = GetQBPlayer(src)
    if not shop or not player then return done(false, 'closed') end

    local slot = Utils.Int(req.slot)
    local amount = Utils.Int(req.amount, 1000)
    local item = slot and shop.items[slot]
    if not item or not amount then return done(false, 'amount') end
    if req.name and req.name ~= item.name then return done(false, 'stale') end
    if item.amount <= 0 or amount > item.amount then
        Notify(src, Lang:t('notify.notenoughstock'), 'error')
        return done(false, 'stock')
    end

    local method = 'cash'
    for _, m in ipairs(Config.ShopPayments) do if m == req.method then method = m end end
    local price = math.floor((item.price or 0) * amount)
    if (player.PlayerData.money[method] or 0) < price then
        Notify(src, Lang:t('notify.notenoughmoney'), 'error')
        return done(false, 'money')
    end

    local box = PlayerBox(src, player)
    local test = CopyBox(box)
    local ok, why = BoxAdd(test, item.name, amount, nil, Utils.Copy(item.info))
    if not ok then return done(false, why) end

    local shopType = GetInventoryType(o.shop)
    local hookData = buildHookData('ItemBought', shopType, o.shop, slot, amount, src)
    if TriggerHook('ItemBought', shopType, hookData) == false then return done(false, 'blocked') end

    if price > 0 and not player.Functions.RemoveMoney(method, price, 'shop-purchase') then return done(false, 'money') end
    CommitBox(test)
    item.amount = item.amount - amount
    TriggerEvent('qb-shops:server:UpdateShopItems', o.shop, { name = item.name, slot = slot, amount = item.amount, price = item.price }, amount)
    TriggerClientEvent('qb-inventory:client:ItemBox', src, Utils.ItemDef(item.name), 'add', amount)
    TriggerListener('ItemBought', shopType, hookData)
    Log('Shop Purchase', 'green', ('**Player:** %s (%s)\n**Shop:** %s\n**Item:** %s x%d\n**Paid:** $%d (%s)')
        :format(GetPlayerName(src) or '?', src, o.shop, item.name, amount, price, method))
    done(true)
end)

-- Vending machines
local function openVending(src, c)
    if #(PlayerCoords(src) - c) > 4.0 then return end
    local name = 'vending-' .. src
    CreateShop({ name = name, label = Lang:t('labels.vending'), coords = c, items = Config.VendingItems, type = 'vending' })
    OpenShop(src, name)
end

RegisterNetEvent('mezos-inventory:server:openVending', function(coords)
    if type(coords) ~= 'vector3' and type(coords) ~= 'table' then return end
    openVending(source, vector3(tonumber(coords.x) or 0, tonumber(coords.y) or 0, tonumber(coords.z) or 0))
end)

-- qb-inventory name kept for anything still triggering it
RegisterNetEvent('qb-inventory:server:openVending', function(data)
    local src = source
    local c = type(data) == 'table' and data.coords
    c = c and vector3(tonumber(c.x) or 0, tonumber(c.y) or 0, tonumber(c.z) or 0) or PlayerCoords(src)
    openVending(src, c)
end)

AddEventHandler('playerDropped', function()
    MZ.Shops['vending-' .. source] = nil
end)
