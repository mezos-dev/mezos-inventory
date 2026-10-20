-- Server state, persistence and player lifecycle.

MZ = {
    Ready = false,
    Inventories = {},   -- stashes, trunks, gloveboxes, containers: identifier → { items, label, slots, maxweight, isOpen, dirty }
    Drops = {},         -- 'drop-n' → { name, label, items, coords, bucket, createdTime, slots, maxweight, isOpen }
    Shops = {},         -- name → { name, label, coords, items, slots, type }
    Open = {},          -- src → session (see sessions.lua)
    Viewers = {},       -- target src → viewer src (player searches)
    Crafting = {},      -- src → pending craft / repair
    Trades = {},        -- trade id → trade
    TradeOf = {},       -- src → trade id
}

-- qb-inventory globals kept for anything ported verbatim (hooks)
Inventories = MZ.Inventories
Drops = MZ.Drops
RegisteredShops = MZ.Shops

RegisterNetEvent('QBCore:Server:UpdateObject', function()
    if source ~= '' then return end
    QBCore = exports['qb-core']:GetCoreObject()
end)

-- ───────────── helpers ─────────────

function GetQBPlayer(src)
    src = tonumber(src)
    if not src then return nil end
    return exports['qb-core']:GetPlayer(src)
end

function Notify(src, msg, typ, len)
    TriggerClientEvent('mezos-inventory:client:notify', src, msg, typ or 'primary', len)
end

function Log(title, color, message)
    TriggerEvent('qb-log:server:CreateLog', 'playerinventory', title, color, message)
end

function IsIncapacitated(player)
    local m = player and player.PlayerData and player.PlayerData.metadata
    if not m then return true end
    return m.isdead or m.inlaststand or m.ishandcuffed
end

function IsAdmin(src)
    for _, perm in ipairs(Config.AdminPermission) do
        if QBCore.Functions.HasPermission(src, perm) then return true end
    end
    return IsPlayerAceAllowed(src, 'command')
end

function PlayerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return vector3(0, 0, 0) end
    return GetEntityCoords(ped)
end

-- ───────────── persistence ─────────────

function SaveInventoryItems(identifier)
    local inv = MZ.Inventories[identifier]
    if not inv then return end
    inv.dirty = false
    local items = json.encode(StripItems(inv.items))
    MySQL.prepare('INSERT INTO inventories (identifier, items) VALUES (?, ?) ON DUPLICATE KEY UPDATE items = ?', { identifier, items, items })
end

function MarkDirty(identifier)
    local inv = MZ.Inventories[identifier]
    if inv then inv.dirty = true end
end

function SaveAllDirty()
    local n = 0
    for id, inv in pairs(MZ.Inventories) do
        if inv.dirty then
            SaveInventoryItems(id)
            n = n + 1
        end
    end
    return n
end

-- Only persist what is needed; definitions are re-applied from QBCore.Shared.Items on load.
function StripItems(items)
    local out = {}
    for slot, item in pairs(items or {}) do
        if type(item) == 'table' and item.name then
            out[#out + 1] = { name = item.name, amount = item.amount, info = item.info, type = item.type, slot = tonumber(item.slot) or slot }
        end
    end
    return out
end

-- Rebuild a slot-keyed table from saved rows, dropping items that no longer exist.
function HydrateItems(rows, context)
    local out, missing = {}, {}
    if type(rows) ~= 'table' then return out end
    for _, row in pairs(rows) do
        if type(row) == 'table' and type(row.name) == 'string' then
            local def = Utils.ItemDef(row.name)
            local slot = tonumber(row.slot)
            if def and slot and not out[slot] then
                out[slot] = BuildItem(def, tonumber(row.amount) or 1, type(row.info) == 'table' and row.info or {}, slot)
            elseif not def then
                missing[#missing + 1] = row.name
            end
        end
    end
    if #missing > 0 then
        print(('^3[mezos-inventory]^7 removed unknown items from %s: %s'):format(context or '?', table.concat(missing, ', ')))
    end
    return out
end

CreateThread(function()
    local rows = MySQL.query.await('SELECT identifier, items FROM inventories') or {}
    for i = 1, #rows do
        local row = rows[i]
        local ok, decoded = pcall(json.decode, row.items or '[]')
        MZ.Inventories[row.identifier] = {
            items = HydrateItems(ok and decoded or {}, row.identifier),
            isOpen = false,
        }
    end
    MZ.Ready = true
    print(('^5[mezos-inventory]^7 %d inventories loaded'):format(#rows))
end)

CreateThread(function()
    while true do
        Wait(Config.SaveInterval * 60000)
        local n = SaveAllDirty()
        if n > 0 then Utils.Debug(('flushed %d inventories'):format(n)) end
    end
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function() SaveAllDirty() end)
AddEventHandler('txAdmin:events:scheduledRestart', function(data)
    if data and data.secondsRemaining and data.secondsRemaining <= 60 then SaveAllDirty() end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SaveAllDirty()
        for src in pairs(MZ.Open) do Player(src).state.inv_busy = false end
    end
    -- unregister hooks owned by the stopping resource
    for _, ev in pairs(Events) do
        for i = 1, #ev.hooks do
            if ev.hooks[i] and ev.hooks[i].resource == res then ev.hooks[i] = false end
        end
        for i = 1, #ev.listeners do
            if ev.listeners[i] and ev.listeners[i].resource == res then ev.listeners[i] = false end
        end
    end
end)

-- ───────────── player lifecycle ─────────────

local function attachMethods(src)
    QBCore.Functions.AddPlayerMethod(src, 'AddItem', function(item, amount, slot, info, reason)
        return AddItem(src, item, amount, slot, info, reason)
    end)
    QBCore.Functions.AddPlayerMethod(src, 'RemoveItem', function(item, amount, slot, reason)
        return RemoveItem(src, item, amount, slot, reason)
    end)
    QBCore.Functions.AddPlayerMethod(src, 'GetItemBySlot', function(slot) return GetItemBySlot(src, slot) end)
    QBCore.Functions.AddPlayerMethod(src, 'GetItemByName', function(item) return GetItemByName(src, item) end)
    QBCore.Functions.AddPlayerMethod(src, 'GetItemsByName', function(item) return GetItemsByName(src, item) end)
    QBCore.Functions.AddPlayerMethod(src, 'ClearInventory', function(filter) ClearInventory(src, filter) end)
    QBCore.Functions.AddPlayerMethod(src, 'SetInventory', function(items) SetInventory(src, items) end)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(qbPlayer)
    local src = qbPlayer and qbPlayer.PlayerData and qbPlayer.PlayerData.source
    if not src then return end
    attachMethods(src)
    Player(src).state.inv_busy = false
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(QBCore.Functions.GetQBPlayers()) do
        attachMethods(src)
        Player(src).state.inv_busy = false
    end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    CloseSession(src, true)
end)

AddEventHandler('playerDropped', function()
    local src = source
    CloseSession(src, true)
    CancelTradeOf(src, 'left')
    MZ.Crafting[src] = nil
    MZ.Viewers[src] = nil
    for target, viewer in pairs(MZ.Viewers) do
        if viewer == src then MZ.Viewers[target] = nil end
    end
end)
