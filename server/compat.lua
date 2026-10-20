-- qb-inventory compatibility layer.
-- `provide 'qb-inventory'` handles dependencies, but Lua exports are keyed by the real resource
-- name, so every export is also registered under 'qb-inventory' by hand.

local function export(name, fn)
    exports(name, fn)
    AddEventHandler(('__cfx_export_qb-inventory_%s'):format(name), function(setCB) setCB(fn) end)
end

-- ───────────── open / close API ─────────────

function OpenInventory(source, identifier, data)
    source = tonumber(source)
    local player = source and GetQBPlayer(source)
    if not player then return end

    if not identifier then
        local hookData = buildHookData('InventoryOpened', source, player)
        if TriggerHook('InventoryOpened', nil, hookData) == false then return end
        if OpenSession(source, nil) then TriggerListener('InventoryOpened', nil, hookData) end
        return
    end
    if type(identifier) ~= 'string' then
        print('^3[mezos-inventory]^7 OpenInventory: invalid identifier')
        return
    end

    local inv = MZ.Inventories[identifier]
    if inv and inv.isOpen and inv.isOpen ~= source and MZ.Open[inv.isOpen] and MZ.Open[inv.isOpen].other and MZ.Open[inv.isOpen].other.id == identifier then
        Notify(source, Lang:t('notify.invinuse'), 'error')
        return
    end
    inv = ResolveInventory(identifier, data)
    local hookData = buildHookData('InventoryOpened', source, player, identifier, identifier)
    if TriggerHook('InventoryOpened', GetInventoryType(identifier), hookData) == false then return end

    local other = { kind = 'stash', id = identifier, label = inv.label, radius = Config.ExportOpenRadius }
    local ok
    if MZ.Open[source] then ok = SwitchOther(source, other) else ok = OpenSession(source, other) end
    if ok ~= false then TriggerListener('InventoryOpened', GetInventoryType(identifier), hookData) end
end

function OpenInventoryById(source, targetId)
    source, targetId = tonumber(source), tonumber(targetId)
    if not source or not targetId or source == targetId then return end
    local player, target = GetQBPlayer(source), GetQBPlayer(targetId)
    if not player or not target then return end
    if MZ.Open[targetId] then CloseSession(targetId) end
    local hookData = buildHookData('InventoryOpened', source, player, targetId, target)
    if TriggerHook('InventoryOpened', 'player', hookData) == false then return end
    Wait(1500)
    if not GetQBPlayer(targetId) then return end
    local trusted = IsAdmin(source) and #(PlayerCoords(source) - PlayerCoords(targetId)) > Config.OtherPlayerDistance
    local other = {
        kind = 'player', id = 'otherplayer-' .. targetId, target = targetId,
        label = GetPlayerName(targetId) or ('#' .. targetId), trusted = trusted,
    }
    local ok
    if MZ.Open[source] then ok = SwitchOther(source, other) else ok = OpenSession(source, other, { force = true }) end
    if ok ~= false then
        Player(targetId).state.inv_busy = true
        TriggerListener('InventoryOpened', 'player', hookData)
    end
end

function CloseInventory(source, identifier)
    source = tonumber(source)
    if not source then return end
    if identifier and MZ.Inventories[identifier] and MZ.Inventories[identifier].isOpen == source then
        MZ.Inventories[identifier].isOpen = false
    end
    CloseSession(source)
end

function CreateInventory(identifier, data)
    if type(identifier) ~= 'string' then return end
    ResolveInventory(identifier, data)
end

function GetInventory(identifier)
    return MZ.Inventories[identifier]
end

function RemoveInventory(identifier)
    local inv = MZ.Inventories[identifier]
    if not inv then return end
    if inv.isOpen and MZ.Open[inv.isOpen] then
        SwitchOther(inv.isOpen, { kind = 'ground', id = 'ground', label = Lang:t('labels.ground') })
    end
    MZ.Inventories[identifier] = nil
end

function ClearStash(identifier)
    local inv = identifier and MZ.Inventories[identifier]
    if not inv then return end
    inv.items = {}
    MySQL.prepare('UPDATE inventories SET items = ? WHERE identifier = ?', { '[]', identifier })
    RefreshViewersOf(identifier)
end

-- ───────────── exports ─────────────

export('LoadInventory', LoadInventory)
export('SaveInventory', SaveInventory)
export('SetInventory', SetInventory)
export('SetItemData', SetItemData)
export('UseItem', UseItem)
export('GetSlotsByItem', GetSlotsByItem)
export('GetFirstSlotByItem', GetFirstSlotByItem)
export('GetItemBySlot', GetItemBySlot)
export('GetTotalWeight', GetTotalWeight)
export('GetItemByName', GetItemByName)
export('GetItemsByName', GetItemsByName)
export('GetSlots', GetSlots)
export('GetItemCount', GetItemCount)
export('CanAddItem', CanAddItem)
export('GetFreeWeight', GetFreeWeight)
export('ClearInventory', ClearInventory)
export('HasItem', HasItem)
export('CloseInventory', CloseInventory)
export('OpenInventoryById', OpenInventoryById)
export('ClearStash', ClearStash)
export('CreateShop', CreateShop)
export('OpenShop', OpenShop)
export('OpenInventory', OpenInventory)
export('CreateInventory', CreateInventory)
export('GetInventory', GetInventory)
export('RemoveInventory', RemoveInventory)
export('AddItem', AddItem)
export('RemoveItem', RemoveItem)
export('AddHook', AddHook)
export('RemoveHook', RemoveHook)
export('AddListener', AddListener)
export('RemoveListener', RemoveListener)

-- mezos extras
export('OpenContainer', OpenContainer)
export('GetCapacity', function(source)
    local box = PlayerBox(source)
    if not box then return Config.MaxSlots, Config.MaxWeight end
    return box.slots, box.maxweight
end)
export('CreateDrop', function(coords, items, bucket)
    local id = CreateDrop(nil, coords)
    if bucket then MZ.Drops[id].bucket = bucket end
    local box = OpenBox(id)
    for _, it in ipairs(items or {}) do BoxAdd(box, it.name, it.amount or 1, nil, it.info) end
    CommitBox(box)
    return id
end)

-- ───────────── legacy events ─────────────

RegisterNetEvent('qb-inventory:server:snowball', function(action)
    local src = source
    if not RateOk(src, 'snow', 2) then return end
    if action == 'add' then
        AddItem(src, 'weapon_snowball', 1, false, false, 'qb-inventory:server:snowball')
    elseif action == 'remove' then
        RemoveItem(src, 'weapon_snowball', 1, false, 'qb-inventory:server:snowball')
    end
end)

RegisterNetEvent('qb-inventory:server:closeInventory', function()
    CloseSession(source, true)
end)

-- ───────────── sanity check ─────────────

CreateThread(function()
    Wait(2000)
    if GetResourceState('qb-inventory') == 'missing' then
        print('^1[mezos-inventory] GetResourceState("qb-inventory") reports missing. qb-core only loads/saves player items when it')
        print('^1finds qb-inventory - make sure `provide \'qb-inventory\'` is honoured (update FXServer) or player items will not persist!^7')
    end
    if GetResourceState('qb-inventory') == 'started' and GetResourceState('mezos-inventory') == 'started' then
        local ok = pcall(function() return exports['qb-inventory']:GetTotalWeight({}) end)
        if not ok then print('^1[mezos-inventory] the qb-inventory export alias is not answering^7') end
    end
end)
