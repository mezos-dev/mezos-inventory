-- Hooks (can cancel by returning false, or mutate data) and listeners (fire after).
-- Same API, event names and payloads as qb-inventory 2.2.x.

Events = {
    ItemMoved = { hooks = {}, listeners = {} },
    ItemDropped = { hooks = {}, listeners = {} },
    ItemUsed = { hooks = {}, listeners = {} },
    ItemBought = { hooks = {}, listeners = {} },
    ItemAdded = { hooks = {}, listeners = {} },
    ItemRemoved = { hooks = {}, listeners = {} },
    InventoryOpened = { hooks = {}, listeners = {} },
    ShopOpened = { hooks = {}, listeners = {} },
}

function TriggerHook(hookType, ...)
    local ev = Events[hookType]
    if not ev then return end
    local result
    for i = 1, #ev.hooks do
        local h = ev.hooks[i]
        if h then
            local ok, response = pcall(h.fn, ...)
            if not ok then
                print(('^1[mezos-inventory] hook %s from %s errored: %s^7'):format(hookType, h.resource or '?', response))
            elseif response == false then
                return false
            elseif response ~= nil then
                result = response
            end
        end
    end
    return result
end

function TriggerListener(listenerType, ...)
    local ev = Events[listenerType]
    if not ev then return end
    for i = 1, #ev.listeners do
        local l = ev.listeners[i]
        if l then
            local ok, err = pcall(l.fn, ...)
            if not ok then print(('^1[mezos-inventory] listener %s errored: %s^7'):format(listenerType, err)) end
        end
    end
end

local function isFn(cb)
    return type(cb) == 'function' or (type(cb) == 'table' and rawget(cb, '__cfx_functionReference'))
end

function AddHook(hookType, callback)
    if not hookType or not isFn(callback) then return end
    local ev = Events[hookType]
    if not ev then print('AddHook: Invalid hook type', hookType) return end
    local idx = #ev.hooks + 1
    ev.hooks[idx] = { fn = callback, resource = GetInvokingResource() }
    return idx
end

function RemoveHook(hookType, idx)
    local ev = Events[hookType]
    if ev and idx and ev.hooks[idx] then ev.hooks[idx] = false end
end

function AddListener(listenerType, callback)
    if not listenerType or not isFn(callback) then return end
    local ev = Events[listenerType]
    if not ev then print('AddListener: Invalid listener type', listenerType) return end
    local idx = #ev.listeners + 1
    ev.listeners[idx] = { fn = callback, resource = GetInvokingResource() }
    return idx
end

function RemoveListener(listenerType, idx)
    local ev = Events[listenerType]
    if ev and idx and ev.listeners[idx] then ev.listeners[idx] = false end
end

-- ───────────── payload builders ─────────────

local function shallowCopy(t)
    if type(t) ~= 'table' then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function buildPlayerInventory(player)
    local items = player and player.PlayerData and player.PlayerData.items or {}
    local slots, maxweight = Capacity(items)
    return { slots = slots, maxweight = maxweight, items = items }
end

function GetInventoryType(identifier)
    if not identifier then return end
    if identifier == 'player' or type(identifier) == 'number' then return 'player' end
    identifier = tostring(identifier)
    if identifier:match('^otherplayer%-') then return 'player' end
    if identifier:match('^trunk%-') then return 'trunk' end
    if identifier:match('^glovebox%-') then return 'glovebox' end
    if identifier:match('^container%-') then return 'container' end
    if MZ.Drops[identifier] then return 'drop' end
    if MZ.Inventories[identifier] then return 'inventory' end
    local shop = MZ.Shops[identifier]
    if shop then return shop.type or (shop.name:gsub('%d+$', '')) end
end

local function resolveContext(inventory, id, player)
    if not inventory or not id then return end
    local t = GetInventoryType(inventory)
    if t == 'player' then
        player = player or GetQBPlayer(id)
        return t, buildPlayerInventory(player)
    end
    if t == 'drop' then return t, MZ.Drops[id] end
    return t, MZ.Inventories[id]
end

local builders = {
    ItemMoved = function(fromInventory, toInventory, fromId, toId, fromSlot, toSlot, amount, fromPlayer, toPlayer)
        local fromType, fromData = resolveContext(fromInventory, fromId, fromPlayer)
        local toType, toData = resolveContext(toInventory, toId, toPlayer)
        return {
            fromType = fromType, toType = toType, fromInventory = fromData, toInventory = toData,
            fromId = fromId, toId = toId, fromSlot = fromSlot, toSlot = toSlot, amount = amount,
        }
    end,
    ItemDropped = function(source, player, coords, slot, amount)
        local item = shallowCopy(player.PlayerData.items[slot])
        if item then item.amount = amount end
        return { source = source, sourceInventory = buildPlayerInventory(player), coords = coords, item = item, amount = amount }
    end,
    ItemUsed = function(source, player, item)
        return { source = source, sourceInventory = buildPlayerInventory(player), item = shallowCopy(item) }
    end,
    ItemBought = function(shopType, shopId, slot, amount, toId)
        local shop = MZ.Shops[shopId]
        local item = shop and shop.items[slot]
        return {
            shopType = shopType, shop = shop, toId = toId, item = shallowCopy(item), amount = amount,
            totalPrice = item and (item.price or 0) * amount or 0,
        }
    end,
    ItemAdded = function(identifier, item, slot, amount, player, reason, resource)
        local t, data = resolveContext(identifier, identifier, player)
        return { toId = identifier, toInventory = data, toType = t, toSlot = slot, item = item, amount = amount, reason = reason, resource = resource }
    end,
    ItemRemoved = function(identifier, item, slot, amount, player, reason, resource)
        local t, data = resolveContext(identifier, identifier, player)
        local copy = shallowCopy(item)
        copy.amount = amount
        return { fromId = identifier, fromInventory = data, fromType = t, fromSlot = slot, item = copy, amount = amount, reason = reason, resource = resource }
    end,
    InventoryOpened = function(id, player, otherId, otherPlayer)
        local _, data = resolveContext(otherId, otherId, otherPlayer)
        return { source = id, sourceInventory = buildPlayerInventory(player), inventoryId = otherId, inventory = data }
    end,
    ShopOpened = function(source, player, shopName)
        return { source = source, sourceInventory = buildPlayerInventory(player), shop = MZ.Shops[shopName] }
    end,
}

function buildHookData(hookType, ...)
    local b = builders[hookType]
    if b then return b(...) end
end

function RefreshInventorySnapshot(payload, field, identifier)
    if not payload or not payload[field] then return payload end
    if GetInventoryType(identifier) ~= 'player' then return payload end
    local id = identifier
    if type(id) == 'string' then id = tonumber(id:match('^otherplayer%-(%d+)$')) or id end
    payload[field] = buildPlayerInventory(GetQBPlayer(id))
    return payload
end
