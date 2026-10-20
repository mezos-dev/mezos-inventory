-- Open/close sessions, locking (one viewer per secondary inventory) and the watchdog that
-- auto-closes inventories when the player walks away, dies, gets cuffed or loses access.
--
-- MZ.Open[src] = { other = { kind, id, label, slots, maxweight, origin, radius, ... } | nil }
--   kind: 'ground' | 'stash' | 'drop' | 'player' | 'shop' | 'crafting' | 'trade'

local function trimPlate(p) return (tostring(p or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
TrimPlate = trimPlate

-- ───────────── inventory metadata ─────────────

--- Create a stash if missing and fill in capacity. Explicit data wins over what was stored.
function ResolveInventory(identifier, data, keepExisting)
    local inv = MZ.Inventories[identifier]
    if not inv then
        inv = { items = {}, isOpen = false }
        MZ.Inventories[identifier] = inv
    end
    if keepExisting and inv.slots and inv.maxweight then
        inv.label = (data and data.label) or inv.label or identifier
        return inv
    end
    inv.label = (data and data.label) or inv.label or identifier
    inv.maxweight = tonumber(data and data.maxweight) or inv.maxweight or Config.StashSize.maxweight
    inv.slots = math.min(tonumber(data and data.slots) or inv.slots or Config.StashSize.slots, 200)
    return inv
end

-- ───────────── payloads ─────────────

local function shopPayload(shop)
    local items = {}
    for slot, it in pairs(shop.items) do items[#items + 1] = it end
    return items
end

function OtherPayload(src)
    local s = MZ.Open[src]
    local o = s and s.other
    if not o then return nil end
    local p = { kind = o.kind, id = o.id, label = o.label, slots = o.slots, maxweight = o.maxweight }
    if o.kind == 'stash' then
        local inv = MZ.Inventories[o.id]
        if not inv then return nil end
        p.items, p.slots, p.maxweight, p.label = inv.items, inv.slots, inv.maxweight, inv.label
        p.sub = o.sub
    elseif o.kind == 'drop' then
        local d = MZ.Drops[o.id]
        if not d then return nil end
        p.items, p.slots, p.maxweight = d.items, d.slots, d.maxweight
    elseif o.kind == 'player' then
        local box = PlayerBox(o.target)
        if not box then return nil end
        p.items, p.slots, p.maxweight = box.items, box.slots, box.maxweight
    elseif o.kind == 'ground' then
        p.items = {}
        p.slots, p.maxweight = Config.DropSize.slots, Config.DropSize.maxweight
    elseif o.kind == 'shop' then
        local shop = MZ.Shops[o.shop]
        if not shop then return nil end
        p.items = shopPayload(shop)
        p.slots = shop.slots
        p.payments = Config.ShopPayments
    elseif o.kind == 'crafting' then
        p.bench = BenchPayload(o.bench, src)
    elseif o.kind == 'trade' then
        p.trade = TradePayload(o.trade, src)
    end
    return p
end

local function playerPayload(src)
    local box = PlayerBox(src)
    if not box then return nil end
    Decay.RefreshBox(box)
    return { items = box.items, slots = box.slots, maxweight = box.maxweight }
end

function PushOther(src)
    if not MZ.Open[src] then return end
    TriggerClientEvent('mezos-inventory:client:other', src, OtherPayload(src))
end

--- Something changed in `identifier` (player source, stash name, drop id): refresh whoever is looking.
function RefreshViewersOf(identifier)
    if type(identifier) == 'number' then
        local viewer = MZ.Viewers[identifier]
        if viewer and MZ.Open[viewer] then PushOther(viewer) end
        if MZ.TradeOf[identifier] then TradeOnInventoryChanged(identifier) end
        return
    end
    local holder = (MZ.Inventories[identifier] and MZ.Inventories[identifier].isOpen)
        or (MZ.Drops[identifier] and MZ.Drops[identifier].isOpen)
    if holder and MZ.Open[holder] and MZ.Open[holder].other and MZ.Open[holder].other.id == identifier then
        PushOther(holder)
    end
end

-- ───────────── locking ─────────────

local function holderValid(holder, id)
    return holder and MZ.Open[holder] and MZ.Open[holder].other and MZ.Open[holder].other.id == id
end

local function tryLock(src, other)
    if other.kind == 'stash' then
        local inv = MZ.Inventories[other.id]
        if inv.isOpen and inv.isOpen ~= src and holderValid(inv.isOpen, other.id) then return false end
        inv.isOpen = src
    elseif other.kind == 'drop' then
        local d = MZ.Drops[other.id]
        if not d then return false end
        if d.isOpen and d.isOpen ~= src and holderValid(d.isOpen, other.id) then return false end
        d.isOpen = src
    elseif other.kind == 'player' then
        local viewer = MZ.Viewers[other.target]
        if viewer and viewer ~= src and holderValid(viewer, other.id) then return false end
        MZ.Viewers[other.target] = src
    end
    return true
end

local function releaseOther(src, other)
    if not other then return end
    if other.kind == 'stash' then
        local inv = MZ.Inventories[other.id]
        if inv and inv.isOpen == src then
            inv.isOpen = false
            if inv.dirty then SaveInventoryItems(other.id) end
        end
    elseif other.kind == 'drop' then
        local d = MZ.Drops[other.id]
        if d and d.isOpen == src then
            d.isOpen = false
            if not next(d.items) then RemoveDrop(other.id) end
        end
    elseif other.kind == 'player' then
        if MZ.Viewers[other.target] == src then
            MZ.Viewers[other.target] = nil
            if GetQBPlayer(other.target) then Player(other.target).state.inv_busy = false end
        end
    elseif other.kind == 'crafting' then
        MZ.Crafting[src] = nil
    elseif other.kind == 'trade' then
        CancelTradeOf(src, 'closed')
    end
end

-- ───────────── open / close ─────────────

--- Open the inventory UI for `src` with an optional secondary inventory.
--- opts: { force = bool (skip busy checks), silentFail = bool }
function OpenSession(src, other, opts)
    opts = opts or {}
    local player = GetQBPlayer(src)
    if not player then return false end
    if not opts.force then
        if IsIncapacitated(player) then return false end
        if Player(src).state.inv_busy and not MZ.Open[src] then
            if not opts.silentFail then Notify(src, Lang:t('notify.busy'), 'error') end
            return false
        end
    end

    other = other or { kind = 'ground', id = 'ground', label = Lang:t('labels.ground') }
    other.origin = other.origin or PlayerCoords(src)

    local prev = MZ.Open[src] and MZ.Open[src].other
    if prev and prev.id ~= other.id then
        releaseOther(src, prev)
    end

    if not tryLock(src, other) then
        Notify(src, Lang:t('notify.invinuse'), 'error')
        if not prev then return false end
        other = { kind = 'ground', id = 'ground', label = Lang:t('labels.ground'), origin = PlayerCoords(src) }
    end

    MZ.Open[src] = { other = other, opened = os.time() }
    Player(src).state.inv_busy = true

    if other.kind == 'stash' then Decay.RefreshBox(OpenBox(other.id)) end
    if other.kind == 'drop' then Decay.RefreshBox(OpenBox(other.id)) end

    TriggerClientEvent('mezos-inventory:client:open', src, {
        player = playerPayload(src),
        other = OtherPayload(src),
    })
    return true
end

--- Switch only the secondary panel of an already open inventory.
function SwitchOther(src, other)
    if not MZ.Open[src] then return OpenSession(src, other) end
    local prev = MZ.Open[src].other
    if prev and prev.id == other.id then return PushOther(src) end
    other.origin = other.origin or PlayerCoords(src)
    if not tryLock(src, other) then
        Notify(src, Lang:t('notify.invinuse'), 'error')
        return false
    end
    if prev then releaseOther(src, prev) end
    MZ.Open[src].other = other
    PushOther(src)
    return true
end

function CloseSession(src, silent)
    local s = MZ.Open[src]
    MZ.Open[src] = nil
    if s then releaseOther(src, s.other) end
    if GetPlayerName(src) then
        Player(src).state.inv_busy = false
        if not silent then TriggerClientEvent('mezos-inventory:client:close', src) end
    end
end

-- Client closed the UI
RegisterNetEvent('mezos-inventory:server:close', function()
    CloseSession(source, true)
end)

-- ───────────── main open (TAB) ─────────────

RegisterNetEvent('mezos-inventory:server:open', function(ctx)
    local src = source
    if not MZ.Ready then return end
    if type(ctx) ~= 'table' then ctx = {} end
    local ped = GetPlayerPed(src)

    if ctx.kind == 'glovebox' then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and type(ctx.plate) == 'string' and trimPlate(GetVehicleNumberPlateText(veh)) == trimPlate(ctx.plate) then
            local id = 'glovebox-' .. ctx.plate
            local storage = VehicleStorage[tonumber(ctx.class)] or VehicleStorage.default
            ResolveInventory(id, { label = Lang:t('labels.glovebox'), slots = storage.gloveboxSlots, maxweight = storage.gloveboxWeight }, true)
            return OpenSession(src, { kind = 'stash', id = id, label = Lang:t('labels.glovebox'), vehicle = veh, sub = 'glovebox' })
        end
    elseif ctx.kind == 'trunk' then
        local veh = tonumber(ctx.netId) and NetworkGetEntityFromNetworkId(ctx.netId)
        if veh and veh ~= 0 and DoesEntityExist(veh) and #(GetEntityCoords(veh) - PlayerCoords(src)) < 8.0
            and type(ctx.plate) == 'string' and trimPlate(GetVehicleNumberPlateText(veh)) == trimPlate(ctx.plate) then
            local id = 'trunk-' .. ctx.plate
            local storage = VehicleStorage[tonumber(ctx.class)] or VehicleStorage.default
            ResolveInventory(id, { label = Lang:t('labels.trunk'), slots = storage.trunkSlots, maxweight = storage.trunkWeight }, true)
            return OpenSession(src, { kind = 'stash', id = id, label = Lang:t('labels.trunk'), vehicle = veh, sub = 'trunk', netId = ctx.netId })
        end
    elseif ctx.kind == 'drop' and type(ctx.id) == 'string' then
        local d = MZ.Drops[ctx.id]
        if d and d.bucket == GetPlayerRoutingBucket(src) and #(d.coords - PlayerCoords(src)) <= Config.DropOpenDistance + 1.0 then
            return OpenSession(src, { kind = 'drop', id = ctx.id, label = Lang:t('labels.drop') })
        end
    end

    local player = GetQBPlayer(src)
    if not player then return end
    local hookData = buildHookData('InventoryOpened', src, player)
    if TriggerHook('InventoryOpened', nil, hookData) == false then return end
    if OpenSession(src, nil) then TriggerListener('InventoryOpened', nil, hookData) end
end)

-- ───────────── watchdog ─────────────

function SessionInRange(src, o)
    local pos = PlayerCoords(src)
    if o.kind == 'player' then
        if o.trusted then return true end
        local tp = PlayerCoords(o.target)
        return #(pos - tp) <= Config.OtherPlayerDistance + 1.0
    end
    if o.vehicle then
        if not DoesEntityExist(o.vehicle) then return false end
        if o.sub == 'glovebox' then return GetVehiclePedIsIn(GetPlayerPed(src), false) == o.vehicle end
        return #(GetEntityCoords(o.vehicle) - pos) <= Config.MaxOpenDistance + 2.0
    end
    if o.kind == 'drop' then
        local d = MZ.Drops[o.id]
        return d and #(d.coords - pos) <= Config.DropOpenDistance + 2.0
    end
    if o.kind == 'shop' then
        local shop = MZ.Shops[o.shop]
        if not shop then return false end
        if shop.coords then
            return #(vector3(shop.coords.x, shop.coords.y, shop.coords.z) - pos) <= Config.ShopDistance
        end
        return #(o.origin - pos) <= Config.ExportOpenRadius
    end
    if o.kind == 'crafting' then
        local b = Config.Benches[o.bench]
        return b and #(vector3(b.coords.x, b.coords.y, b.coords.z) - pos) <= Config.BenchDistance + 2.0
    end
    if o.kind == 'ground' or o.kind == 'trade' or o.container then return true end
    if o.origin and o.radius then return #(o.origin - pos) <= o.radius end
    if o.origin then return #(o.origin - pos) <= Config.MaxOpenDistance end
    return true
end

local function containerStillHeld(src, cid)
    local box = PlayerBox(src)
    if not box then return false end
    for _, it in pairs(box.items) do
        if it.info and it.info.containerId == cid then return true end
    end
    return false
end

CreateThread(function()
    while true do
        Wait(750)
        for src, s in pairs(MZ.Open) do
            if not GetPlayerName(src) then
                MZ.Open[src] = nil
            else
                local o = s.other
                local player = GetQBPlayer(src)
                if not player then
                    CloseSession(src, true)
                elseif IsIncapacitated(player) then
                    CloseSession(src)
                elseif o and not SessionInRange(src, o) then
                    if o.kind == 'player' or o.kind == 'shop' or o.kind == 'crafting' or o.kind == 'trade' then
                        CloseSession(src)
                    else
                        -- stepping away from a stash only closes the stash, not your pockets
                        SwitchOther(src, { kind = 'ground', id = 'ground', label = Lang:t('labels.ground') })
                    end
                elseif o and o.container and not containerStillHeld(src, o.container) then
                    SwitchOther(src, { kind = 'ground', id = 'ground', label = Lang:t('labels.ground') })
                end
            end
        end
    end
end)
