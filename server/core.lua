-- The inventory engine. Everything that changes items goes through a "box":
--   { kind = 'player'|'stash'|'drop', id, items, slots, maxweight, player?, src? }
-- Box operations are synchronous (no Wait / await), so a move or trade is atomic.


-- ───────────── item building ─────────────

function BuildItem(def, amount, info, slot)
    return {
        name = def.name,
        amount = amount,
        info = info or {},
        label = def.label,
        description = def.description or '',
        weight = def.weight or 0,
        type = def.type,
        unique = def.unique,
        useable = def.useable,
        image = def.image,
        shouldClose = def.shouldClose,
        slot = slot,
        combinable = def.combinable,
    }
end

local function prepareInfo(def, info)
    info = type(info) == 'table' and info or {}
    if def.type == 'weapon' then
        if not info.serie then info.serie = Utils.Serial() end
        if not info.quality then info.quality = 100 end
    end
    Decay.Stamp(def, info)
    return info
end

--- Player capacity including the equipped backpack bonus.
function Capacity(items)
    return Utils.Capacity(items)
end

-- ───────────── boxes ─────────────

local function playerIdOf(identifier)
    if type(identifier) == 'number' then return identifier end
    if type(identifier) == 'string' then
        return tonumber(identifier:match('^otherplayer%-(%d+)$') or identifier:match('^(%d+)$'))
    end
end

function PlayerBox(src, player)
    player = player or GetQBPlayer(src)
    if not player then return nil end
    local items = player.PlayerData.items
    if type(items) ~= 'table' then items = {} end
    -- normalise keys (msgpack may hand back string keys) and slot fields
    local clean = {}
    for k, v in pairs(items) do
        local slot = tonumber(k) or (type(v) == 'table' and tonumber(v.slot))
        if slot and type(v) == 'table' and v.name then
            v.slot = slot
            v.amount = tonumber(v.amount) or 1
            if type(v.info) ~= 'table' then v.info = {} end
            clean[slot] = v
        end
    end
    local slots, maxweight = Capacity(clean)
    return { kind = 'player', id = src, src = src, items = clean, slots = slots, maxweight = maxweight, player = player }
end

--- Resolve any identifier (player source, 'otherplayer-x', stash name, drop id) to a box.
function OpenBox(identifier, requireCapacity)
    local pid = playerIdOf(identifier)
    if pid then
        local box = PlayerBox(pid)
        if box then return box end
    end
    if type(identifier) ~= 'string' then return nil end
    local drop = MZ.Drops[identifier]
    if drop then
        return { kind = 'drop', id = identifier, items = drop.items, slots = drop.slots, maxweight = drop.maxweight }
    end
    local inv = MZ.Inventories[identifier]
    if inv then
        if requireCapacity and (not inv.slots or not inv.maxweight) then
            print(('^3[mezos-inventory]^7 inventory %s has no capacity yet, create or open it first'):format(identifier))
            return nil
        end
        return { kind = 'stash', id = identifier, items = inv.items, slots = inv.slots or Config.StashSize.slots, maxweight = inv.maxweight or Config.StashSize.maxweight }
    end
end

function CopyBox(box)
    local c = {}
    for k, v in pairs(box) do c[k] = v end
    c.items = Utils.Copy(box.items)
    return c
end

--- Write a box back to where it lives and refresh anyone looking at it.
function CommitBox(box)
    if box.kind == 'player' then
        for slot, item in pairs(box.items) do item.slot = slot end
        box.player.Functions.SetPlayerData('items', box.items)
        box.slots, box.maxweight = Capacity(box.items)
        RefreshViewersOf(box.src)
    elseif box.kind == 'stash' then
        local inv = MZ.Inventories[box.id]
        if not inv then return end
        for slot, item in pairs(box.items) do item.slot = slot end
        inv.items = box.items
        inv.dirty = true
        if not inv.isOpen then SaveInventoryItems(box.id) end
        RefreshViewersOf(box.id)
    elseif box.kind == 'drop' then
        local drop = MZ.Drops[box.id]
        if not drop then return end
        for slot, item in pairs(box.items) do item.slot = slot end
        drop.items = box.items
        if not next(drop.items) and not drop.isOpen then RemoveDrop(box.id) return end
        RefreshViewersOf(box.id)
    end
end

-- ───────────── slot rules ─────────────

function SlotValid(box, slot, name)
    slot = tonumber(slot)
    if not slot or math.floor(slot) ~= slot then return false end
    if slot >= 1 and slot <= box.slots then return true end
    if box.kind == 'player' then
        local equip = Utils.EquipBySlot(slot)
        if equip then return name == nil or Utils.CanEquip(equip, name) end
    end
    return false
end

local function stackMax(def)
    if def.unique then return 1 end
    return Utils.Meta(def.name).stack
end

local function canStack(a, b, def)
    if a.name ~= b.name or def.unique then return false end
    return true
end

function FirstFree(box, exclude)
    for i = 1, box.slots do
        if not box.items[i] and i ~= exclude then return i end
    end
end

-- Normal slots first (ascending), then equipment slots.
local function orderedSlots(items)
    local normal, equip = {}, {}
    for slot in pairs(items) do
        if Utils.IsEquipSlot(slot) then equip[#equip + 1] = slot else normal[#normal + 1] = slot end
    end
    table.sort(normal)
    table.sort(equip)
    for i = 1, #equip do normal[#normal + 1] = equip[i] end
    return normal
end

-- ───────────── pure box operations ─────────────

--- Plan + apply an add. Returns ok, reason ('item'|'amount'|'weight'|'slots'), firstSlot.
function BoxAdd(box, name, amount, slot, info, skipPrepare)
    local def = Utils.ItemDef(name)
    if not def then return false, 'item' end
    amount = Utils.Int(amount)
    if not amount then return false, 'amount' end
    if Utils.Weight(box.items) + (def.weight or 0) * amount > box.maxweight then return false, 'weight' end
    if not skipPrepare then info = prepareInfo(def, info) end
    local max = stackMax(def)
    slot = tonumber(slot)

    local plan = {} -- { slot, add, new }
    local remaining = amount
    local taken = {}

    local function room(cur) return max and (max - cur.amount) or remaining end

    -- requested slot first
    if slot then
        local cur = box.items[slot]
        if cur then
            if canStack(cur, { name = def.name }, def) and SlotValid(box, slot, def.name) and room(cur) > 0 then
                local n = math.min(remaining, room(cur))
                plan[#plan + 1] = { slot = slot, add = n }
                remaining = remaining - n
            end
        elseif SlotValid(box, slot, def.name) then
            local n = math.min(remaining, max or remaining)
            plan[#plan + 1] = { slot = slot, add = n, new = true }
            taken[slot] = true
            remaining = remaining - n
        end
    end

    -- existing stacks in normal slots
    if remaining > 0 and not def.unique then
        for i = 1, box.slots do
            local cur = box.items[i]
            if cur and i ~= slot and cur.name == def.name and room(cur) > 0 then
                local n = math.min(remaining, room(cur))
                plan[#plan + 1] = { slot = i, add = n }
                remaining = remaining - n
                if remaining <= 0 then break end
            end
        end
    end

    -- free slots
    local i = 1
    while remaining > 0 do
        while i <= box.slots and (box.items[i] or taken[i]) do i = i + 1 end
        if i > box.slots then return false, 'slots' end
        local n = math.min(remaining, max or remaining)
        plan[#plan + 1] = { slot = i, add = n, new = true }
        taken[i] = true
        remaining = remaining - n
    end

    -- apply
    local first = plan[1] and plan[1].slot
    local firstNew = true
    for _, p in ipairs(plan) do
        if p.new then
            local itemInfo = info
            if firstNew then
                firstNew = false
            else
                -- every extra unique copy gets its own identity
                itemInfo = Utils.Copy(info)
                if def.type == 'weapon' then itemInfo.serie = Utils.Serial() end
                itemInfo.containerId = nil
            end
            box.items[p.slot] = BuildItem(def, p.add, itemInfo, p.slot)
        else
            local cur = box.items[p.slot]
            cur.amount = cur.amount + p.add
            Decay.MergeInto(cur, info)
        end
    end
    return true, nil, first
end

--- Remove an amount. With a slot: only that slot. Without: across stacks (normal slots first).
--- Returns ok, list of { slot, item (snapshot), amount }.
function BoxRemove(box, name, amount, slot)
    amount = Utils.Int(amount)
    if not amount or type(name) ~= 'string' then return false end
    name = name:lower()
    slot = tonumber(slot)
    local removed = {}
    if slot then
        local item = box.items[slot]
        if not item or item.name:lower() ~= name or item.amount < amount then return false end
        removed[1] = { slot = slot, item = Utils.Copy(item), amount = amount }
        item.amount = item.amount - amount
        if item.amount <= 0 then box.items[slot] = nil end
        return true, removed
    end
    local total = 0
    local order = orderedSlots(box.items)
    for _, s in ipairs(order) do
        local it = box.items[s]
        if it.name:lower() == name then total = total + it.amount end
    end
    if total < amount then return false end
    local remaining = amount
    for _, s in ipairs(order) do
        local it = box.items[s]
        if it and it.name:lower() == name then
            local n = math.min(remaining, it.amount)
            removed[#removed + 1] = { slot = s, item = Utils.Copy(it), amount = n }
            it.amount = it.amount - n
            if it.amount <= 0 then box.items[s] = nil end
            remaining = remaining - n
            if remaining <= 0 then break end
        end
    end
    return true, removed
end

--- Would removing / changing the backpack leave items stranded?
function BackpackCheck(box)
    if box.kind ~= 'player' then return true end
    local slots, maxweight = Capacity(box.items)
    for slot in pairs(box.items) do
        if slot > slots and slot <= 100 then return false end
    end
    if Utils.Weight(box.items) > maxweight then return false end
    return true
end

-- ───────────── weapons ─────────────

--- If the player is holding this weapon, put it away (qb-weapons keeps its own state).
function checkWeapon(src, item)
    local name = type(item) == 'table' and item.name or item
    if type(name) ~= 'string' then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local weapon = GetSelectedPedWeapon(ped)
    local wi = QBCore.Shared.Weapons[weapon]
    if wi and wi.name == name:lower() then
        RemoveWeaponFromPed(ped, weapon)
        TriggerClientEvent('qb-weapons:client:UseWeapon', src, { name = name, info = type(item) == 'table' and item.info or {} }, false)
    end
end

-- ───────────── public API (exports live in compat.lua) ─────────────

local function invName(box)
    if box.kind == 'player' then return ('%s (%s)'):format(GetPlayerName(box.src) or '?', box.src) end
    return tostring(box.id)
end

function AddItem(identifier, item, amount, slot, info, reason, isInternalMove)
    if type(item) ~= 'string' then print('AddItem: Invalid item') return false end
    local def = Utils.ItemDef(item)
    if not def then print(('AddItem: Invalid item %s'):format(item)) return false end
    local box = OpenBox(identifier, true)
    if not box then print(('AddItem: Inventory not found: %s'):format(tostring(identifier))) return false end
    amount = Utils.Int(tonumber(amount) or 1)
    if not amount then return false end

    info = prepareInfo(def, type(info) == 'table' and Utils.Copy(info) or {})
    local resource = GetInvokingResource() or GetCurrentResourceName()

    local hookData
    if not isInternalMove then
        local preview = BuildItem(def, amount, info, tonumber(slot) or FirstFree(box))
        hookData = buildHookData('ItemAdded', identifier, preview, preview.slot, amount, box.player, reason, resource)
        local mutated = TriggerHook('ItemAdded', def.type, hookData)
        if mutated == false then return false end
        if type(mutated) == 'table' then info = mutated end
    end

    local ok, why, first = BoxAdd(box, def.name, amount, slot, info, true)
    if not ok then
        Utils.Debug(('AddItem %s x%d to %s failed: %s'):format(def.name, amount, tostring(identifier), why))
        return false
    end
    CommitBox(box)
    if hookData then TriggerListener('ItemAdded', def.type, hookData) end
    Log('Item Added', 'green', ('**Inventory:** %s (Slot: %s)\n**Item:** %s\n**Amount:** %d\n**Reason:** %s\n**Resource:** %s')
        :format(invName(box), tostring(first), def.name, amount, reason or 'No reason specified', resource))
    return true
end

function RemoveItem(identifier, item, amount, slot, reason, isInternalMove)
    if type(item) ~= 'string' or not Utils.ItemDef(item) then print('RemoveItem: Invalid item') return false end
    local box = OpenBox(identifier)
    if not box then print(('RemoveItem: Inventory not found: %s'):format(tostring(identifier))) return false end
    amount = Utils.Int(tonumber(amount) or 1)
    if not amount then return false end
    slot = tonumber(slot)

    local resource = GetInvokingResource() or GetCurrentResourceName()
    local hookData
    if not isInternalMove then
        local target = slot and box.items[slot]
        if not target then
            for _, s in ipairs(orderedSlots(box.items)) do
                if box.items[s].name:lower() == item:lower() then target = box.items[s] break end
            end
        end
        if not target then return false end
        hookData = buildHookData('ItemRemoved', identifier, target, target.slot, amount, box.player, reason, resource)
        if TriggerHook('ItemRemoved', target.type, hookData) == false then return false end
    end

    local ok, removed = BoxRemove(box, item, amount, slot)
    if not ok then return false end
    -- If another resource removes an equipped backpack, items in its bonus slots stay put;
    -- the UI shows them as overflow and only lets them be moved out.
    CommitBox(box)

    if box.kind == 'player' then
        local def = Utils.ItemDef(item)
        if def.type == 'weapon' then
            local still = false
            for _, it in pairs(box.items) do if it.name == def.name then still = true break end end
            if not still then checkWeapon(box.src, item) end
        end
    end

    if hookData then TriggerListener('ItemRemoved', hookData.item and hookData.item.type, hookData) end
    Log('Item Removed', 'red', ('**Inventory:** %s (Slot: %s)\n**Item:** %s\n**Amount:** %d\n**Reason:** %s\n**Resource:** %s')
        :format(invName(box), tostring(removed[1] and removed[1].slot), item, amount, reason or 'No reason specified', resource))
    return true
end

function CanAddItem(identifier, item, amount)
    local def = Utils.ItemDef(item)
    if not def then return false end
    local box = OpenBox(identifier, true)
    if not box then return false end
    amount = Utils.Int(tonumber(amount) or 1) or 1
    local test = CopyBox(box)
    local ok, why = BoxAdd(test, def.name, amount, nil, {}, true)
    if ok then return true end
    if why == 'weight' then return false, 'weight' end
    return false, 'slots'
end

function GetTotalWeight(items)
    return Utils.Weight(items)
end

function GetFirstSlotByItem(items, itemName)
    if type(items) ~= 'table' or type(itemName) ~= 'string' then return nil end
    itemName = itemName:lower()
    for _, s in ipairs(orderedSlots(items)) do
        local it = items[s]
        if it and it.name and it.name:lower() == itemName then return tonumber(s) end
    end
end

function GetSlotsByItem(items, itemName)
    local found = {}
    if type(items) ~= 'table' or type(itemName) ~= 'string' then return found end
    itemName = itemName:lower()
    for _, s in ipairs(orderedSlots(items)) do
        local it = items[s]
        if it and it.name and it.name:lower() == itemName then found[#found + 1] = s end
    end
    return found
end

function GetItemBySlot(source, slot)
    local box = PlayerBox(source)
    if not box then return nil end
    return box.items[tonumber(slot)]
end

function GetItemByName(source, item)
    local box = PlayerBox(source)
    if not box then return nil end
    local slot = GetFirstSlotByItem(box.items, tostring(item))
    return slot and box.items[slot] or nil
end

function GetItemsByName(source, item)
    local box = PlayerBox(source)
    if not box then return nil end
    local list = {}
    for _, s in ipairs(GetSlotsByItem(box.items, tostring(item))) do list[#list + 1] = box.items[s] end
    return list
end

function GetSlots(identifier)
    local box = OpenBox(identifier, true)
    if not box then return 0, nil end
    local used = 0
    for slot in pairs(box.items) do
        if slot >= 1 and slot <= 100 then used = used + 1 end
    end
    return used, box.slots - used
end

function GetItemCount(source, items)
    local box = PlayerBox(source)
    if not box then return nil end
    local set = nil
    if type(items) == 'table' then
        set = {}
        for _, n in pairs(items) do set[n] = true end
    end
    local count = 0
    for _, it in pairs(box.items) do
        if (set and set[it.name]) or (not set and it.name == items) then count = count + it.amount end
    end
    return count
end

function GetFreeWeight(source)
    if not source then return 0 end
    local box = PlayerBox(source)
    if not box then return 0 end
    return box.maxweight - Utils.Weight(box.items)
end

function HasItem(source, items, amount)
    local box = PlayerBox(source)
    if not box then return false end
    local inv = box.items
    local function count(name)
        local c = 0
        for _, it in pairs(inv) do if it.name == name then c = c + it.amount end end
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

function SetInventory(identifier, items, reason)
    if type(items) ~= 'table' then items = {} end
    local pid = playerIdOf(identifier)
    local player = pid and GetQBPlayer(pid)
    if player then
        -- keep slot keys numeric
        local clean = {}
        for k, v in pairs(items) do
            local slot = tonumber(k) or (type(v) == 'table' and tonumber(v.slot))
            if slot and type(v) == 'table' and v.name then v.slot = slot clean[slot] = v end
        end
        player.Functions.SetPlayerData('items', clean)
        RefreshViewersOf(pid)
    elseif MZ.Drops[identifier] then
        MZ.Drops[identifier].items = items
        RefreshViewersOf(identifier)
    elseif MZ.Inventories[identifier] then
        MZ.Inventories[identifier].items = items
        MarkDirty(identifier)
        RefreshViewersOf(identifier)
    else
        print('SetInventory: Inventory not found')
        return
    end
    Log('Inventory Set', 'blue', ('**Inventory:** %s\n**Reason:** %s\n**Resource:** %s')
        :format(tostring(identifier), reason or 'No reason specified', GetInvokingResource() or GetCurrentResourceName()))
end

function SetItemData(source, itemName, key, val, slot)
    if not itemName or not key then return false end
    local box = PlayerBox(source)
    if not box then return nil end
    local item
    if slot then
        item = box.items[tonumber(slot)]
        if not item or item.name:lower() ~= itemName:lower() then return false end
    else
        local s = GetFirstSlotByItem(box.items, itemName)
        item = s and box.items[s]
        if not item then return false end
    end
    item[key] = val
    CommitBox(box)
    return true
end

function ClearInventory(source, filterItems)
    local box = PlayerBox(source)
    if not box then return end
    local keep = {}
    if filterItems then
        local names = type(filterItems) == 'string' and { filterItems } or filterItems
        for _, name in ipairs(names) do
            for _, s in ipairs(GetSlotsByItem(box.items, name)) do keep[s] = box.items[s] end
        end
    end
    box.items = keep
    CommitBox(box)
    Log('ClearInventory', 'red', ('**%s (citizenid: %s | id: %s)** inventory cleared')
        :format(GetPlayerName(source) or '?', box.player.PlayerData.citizenid, source))
    local ped = GetPlayerPed(source)
    if ped and ped ~= 0 then
        local weapon = GetSelectedPedWeapon(ped)
        if weapon ~= `WEAPON_UNARMED` then RemoveWeaponFromPed(ped, weapon) end
    end
end

-- ───────────── load / save (called by qb-core) ─────────────

function LoadInventory(source, citizenid)
    local raw = MySQL.prepare.await('SELECT inventory FROM players WHERE citizenid = ?', { citizenid })
    local ok, rows = pcall(json.decode, raw or '[]')
    local items = HydrateItems(ok and rows or {}, source and GetPlayerName(source) or citizenid)
    Decay.RefreshItems(items)
    return items
end

function SaveInventory(source, offline)
    local pd
    if offline then
        pd = source
    else
        local player = GetQBPlayer(source)
        if not player then return end
        pd = player.PlayerData
    end
    if not pd or not pd.citizenid then return end
    MySQL.prepare('UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode(StripItems(pd.items)), pd.citizenid })
end
