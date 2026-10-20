-- Validated item moves coming from the UI. The client only sends intents; every rule lives here.

local rate = {}

function RateOk(src, bucket, perSecond)
    local key = bucket .. ':' .. src
    local now = GetGameTimer()
    local r = rate[key]
    if not r or now - r.t >= 1000 then
        rate[key] = { t = now, n = 1 }
        return true
    end
    r.n = r.n + 1
    return r.n <= (perSecond or Config.MovesPerSecond)
end

AddEventHandler('playerDropped', function()
    local src = source
    for key in pairs(rate) do
        if key:match(':' .. src .. '$') then rate[key] = nil end
    end
end)

-- ───────────── side resolution ─────────────

--- Returns box, sessionOther for a UI side ('player' | 'other').
function SideBox(src, side)
    if side == 'player' then return PlayerBox(src), nil end
    if side ~= 'other' then return nil end
    local s = MZ.Open[src]
    local o = s and s.other
    if not o then return nil end
    if o.kind == 'stash' then
        local inv = MZ.Inventories[o.id]
        if not inv or inv.isOpen ~= src then return nil end
        local box = OpenBox(o.id)
        if box and o.container then box.containerTarget = true end
        return box, o
    elseif o.kind == 'drop' then
        local d = MZ.Drops[o.id]
        if not d or d.isOpen ~= src then return nil end
        return OpenBox(o.id), o
    elseif o.kind == 'player' then
        if MZ.Viewers[o.target] ~= src then return nil end
        return PlayerBox(o.target), o
    elseif o.kind == 'ground' then
        return { kind = 'ground', id = 'ground', items = {}, slots = Config.DropSize.slots, maxweight = Config.DropSize.maxweight }, o
    end
    return nil
end

local function invLabel(box)
    if box.kind == 'player' then return box.isOther and ('otherplayer-' .. box.src) or 'player' end
    return box.id
end

local function hookId(box)
    if box.kind == 'player' then return box.src end
    return box.id
end

local function openContainerId(src)
    local s = MZ.Open[src]
    return s and s.other and s.other.container
end

-- ───────────── the move ─────────────

--- Move `amount` from fromBox[fromSlot] to toBox[toSlot]. Boxes are copied, validated and committed atomically.
--- Returns ok, errCode
function MoveItem(src, fromBox, fromSlot, toBox, toSlot, amount, expectName)
    fromSlot, toSlot = tonumber(fromSlot), tonumber(toSlot)
    if not fromSlot or not toSlot then return false, 'slot' end
    local same = fromBox.kind == toBox.kind and fromBox.id == toBox.id
    if same and fromSlot == toSlot then return true end

    local A = CopyBox(fromBox)
    local B = same and A or CopyBox(toBox)
    local item = A.items[fromSlot]
    if not item then return false, 'missing' end
    if expectName and item.name ~= expectName then return false, 'stale' end
    amount = amount == nil and item.amount or Utils.Int(amount)
    if not amount or amount > item.amount then return false, 'amount' end
    if not SlotValid(B, toSlot, item.name) then
        return false, Utils.IsEquipSlot(toSlot) and 'equip' or 'slot'
    end

    local def = Utils.ItemDef(item.name)
    if not def then return false, 'missing' end
    if B.containerTarget and Utils.Meta(item.name).container then return false, 'nest' end

    -- an open container can't leave its owner's pockets
    local cid = openContainerId(src)
    if cid and not same and fromBox.kind == 'player' and fromBox.src == src and item.info and item.info.containerId == cid then
        return false, 'containerOpen'
    end

    local target = B.items[toSlot]
    local moveType
    if not target then
        if amount == item.amount then
            A.items[fromSlot] = nil
            B.items[toSlot] = item
            moveType = 'moved'
        else
            local part = Utils.Copy(item)
            part.amount = amount
            item.amount = item.amount - amount
            B.items[toSlot] = part
            moveType = 'split'
        end
    elseif target.name == item.name and not def.unique then
        local max = Utils.Meta(item.name).stack
        local n = amount
        if max then n = math.min(n, max - target.amount) end
        if n <= 0 then return false, 'full' end
        target.amount = target.amount + n
        Decay.MergeInto(target, item.info)
        item.amount = item.amount - n
        if item.amount <= 0 then A.items[fromSlot] = nil end
        moveType = 'stacked'
    else
        if amount ~= item.amount then return false, 'swapPartial' end
        if not SlotValid(A, fromSlot, target.name) then return false, 'equip' end
        if A.containerTarget and Utils.Meta(target.name).container then return false, 'nest' end
        if cid and not same and toBox.kind == 'player' and toBox.src == src and target.info and target.info.containerId == cid then
            return false, 'containerOpen'
        end
        A.items[fromSlot] = target
        B.items[toSlot] = item
        moveType = 'swapped'
    end

    -- weight: only refuse if a side got heavier than its limit
    if not same then
        local wb, wbBefore = Utils.Weight(B.items), Utils.Weight(toBox.items)
        if wb > B.maxweight and wb > wbBefore then return false, 'weight' end
        local wa, waBefore = Utils.Weight(A.items), Utils.Weight(fromBox.items)
        if wa > A.maxweight and wa > waBefore then return false, 'weight' end
    end

    -- backpack capacity changes must not strand items
    local bpSlot = Utils.EquipById('backpack') and Utils.EquipById('backpack').slot
    if bpSlot then
        for _, pair in ipairs({ { A, fromBox }, { B, toBox } }) do
            local nb, ob = pair[1], pair[2]
            if nb.kind == 'player' then
                local was, now = ob.items[bpSlot], nb.items[bpSlot]
                if (was and was.name) ~= (now and now.name) and not BackpackCheck(nb) then
                    return false, 'backpack'
                end
            end
        end
    end

    -- hooks (qb-inventory compatible)
    local player = GetQBPlayer(src)
    local hookData = buildHookData('ItemMoved', invLabel(fromBox), invLabel(toBox), hookId(fromBox), hookId(toBox), fromSlot, toSlot, amount, player)
    if TriggerHook('ItemMoved', moveType, hookData) == false then return false, 'blocked' end

    CommitBox(A)
    if not same then CommitBox(B) end

    -- holster weapons that changed place (qb-weapons tracks by slot)
    if def.type == 'weapon' and fromBox.kind == 'player' then checkWeapon(fromBox.src, item) end
    if moveType == 'swapped' and target.type == 'weapon' and toBox.kind == 'player' then checkWeapon(toBox.src, target) end

    RefreshInventorySnapshot(hookData, 'fromInventory', hookId(fromBox))
    RefreshInventorySnapshot(hookData, 'toInventory', hookId(toBox))
    TriggerListener('ItemMoved', moveType, hookData)

    if fromBox.kind ~= toBox.kind or fromBox.id ~= toBox.id then
        Log('Item Moved', 'blue', ('**Player:** %s (%s)\n**Item:** %s x%d\n**From:** %s [%d]\n**To:** %s [%d]\n**Type:** %s')
            :format(GetPlayerName(src) or '?', src, item.name, amount, tostring(invLabel(fromBox)), fromSlot, tostring(invLabel(toBox)), toSlot, moveType))
    end
    return true
end

-- ───────────── drop on ground ─────────────

function DropFromPlayer(src, slot, amount)
    local player = GetQBPlayer(src)
    if not player or IsIncapacitated(player) then return false, 'busy' end
    local box = PlayerBox(src, player)
    slot = tonumber(slot)
    local item = slot and box.items[slot]
    if not item then return false, 'missing' end
    amount = amount == nil and item.amount or Utils.Int(amount)
    if not amount or amount > item.amount then return false, 'amount' end
    if Utils.Meta(item.name).noDrop then return false, 'noDrop' end
    local cid = openContainerId(src)
    if cid and item.info and item.info.containerId == cid then return false, 'containerOpen' end

    local coords = PlayerCoords(src)
    local hookData = buildHookData('ItemDropped', src, player, coords, slot, amount)
    if not hookData or not hookData.item then return false, 'missing' end
    if TriggerHook('ItemDropped', item.type, hookData) == false then return false, 'blocked' end

    -- reuse a drop you're standing on (and not someone else's open one)
    local dropId = NearestDrop(src, 1.5, true)
    local created = false
    if not dropId then
        dropId = CreateDrop(src, coords)
        created = true
    end
    local dropBox = OpenBox(dropId)
    local test = CopyBox(box)
    local part = Utils.Copy(item)
    local ok = BoxRemove(test, item.name, amount, slot)
    if not ok then if created then RemoveDrop(dropId) end return false, 'missing' end
    local dtest = CopyBox(dropBox)
    local added, why = BoxAdd(dtest, item.name, amount, nil, part.info, true)
    if not added then if created then RemoveDrop(dropId) end return false, why end

    CommitBox(test)
    MZ.Drops[dropId].isOpen = MZ.Drops[dropId].isOpen or false
    CommitBox(dtest)

    if item.type == 'weapon' then checkWeapon(src, item) end
    TriggerClientEvent('mezos-inventory:client:dropAnim', src)
    hookData.dropId = dropId
    RefreshInventorySnapshot(hookData, 'sourceInventory', src)
    TriggerListener('ItemDropped', item.type, hookData)
    Log('Item Dropped', 'orange', ('**Player:** %s (%s)\n**Item:** %s x%d\n**Drop:** %s'):format(GetPlayerName(src) or '?', src, item.name, amount, dropId))
    return true, nil, dropId
end

-- ───────────── give ─────────────

function GiveItem(src, target, slot, amount)
    target = tonumber(target)
    if not target or target == src then return false, 'target' end
    local giver, receiver = GetQBPlayer(src), GetQBPlayer(target)
    if not giver or not receiver or IsIncapacitated(giver) or IsIncapacitated(receiver) then return false, 'target' end
    if #(PlayerCoords(src) - PlayerCoords(target)) > Config.GiveDistance + 1.0 then return false, 'tooFar' end

    local A, B = PlayerBox(src, giver), PlayerBox(target, receiver)
    slot = tonumber(slot)
    local item = slot and A.items[slot]
    if not item then return false, 'missing' end
    amount = amount == nil and item.amount or Utils.Int(amount)
    if not amount or amount > item.amount then return false, 'amount' end
    if Utils.Meta(item.name).noGive then return false, 'noGive' end
    local cid = openContainerId(src)
    if cid and item.info and item.info.containerId == cid then return false, 'containerOpen' end

    local snap = Utils.Copy(item)
    local hookData = buildHookData('ItemMoved', 'player', 'player', src, target, slot, nil, amount, giver, receiver)
    if TriggerHook('ItemMoved', 'given', hookData) == false then return false, 'blocked' end

    if not BoxRemove(A, item.name, amount, slot) then return false, 'missing' end
    local ok, why = BoxAdd(B, snap.name, amount, nil, snap.info, true)
    if not ok then return false, why == 'weight' and 'targetWeight' or 'targetFull' end
    if not BackpackCheck(A) then return false, 'backpack' end

    CommitBox(A)
    CommitBox(B)

    local def = Utils.ItemDef(snap.name)
    if def.type == 'weapon' then checkWeapon(src, snap) end
    TriggerClientEvent('qb-inventory:client:giveAnim', src)
    TriggerClientEvent('qb-inventory:client:giveAnim', target)
    TriggerClientEvent('qb-inventory:client:ItemBox', src, def, 'remove', amount)
    TriggerClientEvent('qb-inventory:client:ItemBox', target, def, 'add', amount)
    Notify(src, Lang:t('notify.given', { amount = amount, item = def.label }), 'success')
    Notify(target, Lang:t('notify.received', { amount = amount, item = def.label }), 'success')
    RefreshInventorySnapshot(hookData, 'fromInventory', src)
    RefreshInventorySnapshot(hookData, 'toInventory', target)
    TriggerListener('ItemMoved', 'given', hookData)
    Log('Item Given', 'green', ('**From:** %s (%s)\n**To:** %s (%s)\n**Item:** %s x%d')
        :format(GetPlayerName(src) or '?', src, GetPlayerName(target) or '?', target, snap.name, amount))
    return true
end

-- ───────────── callbacks ─────────────

local function snapshot(src)
    local box = PlayerBox(src)
    return {
        player = box and { items = box.items, slots = box.slots, maxweight = box.maxweight } or nil,
        other = OtherPayload(src),
    }
end

local function fail(src, cb, err)
    local res = snapshot(src)
    res.ok = false
    res.err = err
    cb(res)
end

QBCore.Functions.CreateCallback('mezos-inventory:server:move', function(src, cb, req)
    if type(req) ~= 'table' or not MZ.Open[src] then return fail(src, cb, 'closed') end
    if not RateOk(src, 'move') then return fail(src, cb, 'rate') end
    local fromBox, fo = SideBox(src, req.from)
    local toBox, to = SideBox(src, req.to)
    if not fromBox or not toBox then return fail(src, cb, 'access') end
    if (fo and not SessionInRange(src, fo)) or (to and not SessionInRange(src, to)) then return fail(src, cb, 'tooFar') end
    if req.from == 'other' and fromBox.kind == 'player' then fromBox.isOther = true end
    if req.to == 'other' and toBox.kind == 'player' then toBox.isOther = true end

    if toBox.kind == 'ground' then
        if fromBox.kind ~= 'player' or req.from ~= 'player' then return fail(src, cb, 'access') end
        local ok, err, dropId = DropFromPlayer(src, req.fromSlot, req.amount)
        if not ok then return fail(src, cb, err) end
        SwitchOther(src, { kind = 'drop', id = dropId, label = Lang:t('labels.drop') })
        local res = snapshot(src)
        res.ok = true
        return cb(res)
    end
    if fromBox.kind == 'ground' then return fail(src, cb, 'access') end

    local ok, err = MoveItem(src, fromBox, req.fromSlot, toBox, req.toSlot, req.amount, req.name)
    if not ok then return fail(src, cb, err) end
    local res = snapshot(src)
    res.ok = true
    cb(res)
end)

-- Ctrl+click: send to the other side, stacking where possible
QBCore.Functions.CreateCallback('mezos-inventory:server:quickMove', function(src, cb, req)
    if type(req) ~= 'table' or not MZ.Open[src] then return fail(src, cb, 'closed') end
    if not RateOk(src, 'move') then return fail(src, cb, 'rate') end
    local toSide = req.from == 'player' and 'other' or 'player'
    local fromBox, fo = SideBox(src, req.from)
    local toBox, to = SideBox(src, toSide)
    if not fromBox or not toBox then return fail(src, cb, 'access') end
    if (fo and not SessionInRange(src, fo)) or (to and not SessionInRange(src, to)) then return fail(src, cb, 'tooFar') end
    local item = fromBox.items[tonumber(req.slot) or -1]
    if not item then return fail(src, cb, 'missing') end

    if toBox.kind == 'ground' then
        local ok, err, dropId = DropFromPlayer(src, req.slot, req.amount)
        if not ok then return fail(src, cb, err) end
        SwitchOther(src, { kind = 'drop', id = dropId, label = Lang:t('labels.drop') })
        local res = snapshot(src) res.ok = true
        return cb(res)
    end

    local def = Utils.ItemDef(item.name)
    local toSlot
    if def and not def.unique then
        for i = 1, toBox.slots do
            local t = toBox.items[i]
            if t and t.name == item.name then toSlot = i break end
        end
    end
    toSlot = toSlot or FirstFree(toBox)
    if not toSlot then return fail(src, cb, 'slots') end
    if req.from == 'other' and fromBox.kind == 'player' then fromBox.isOther = true end
    if toSide == 'other' and toBox.kind == 'player' then toBox.isOther = true end
    local ok, err = MoveItem(src, fromBox, req.slot, toBox, toSlot, req.amount, item.name)
    if not ok then return fail(src, cb, err) end
    local res = snapshot(src) res.ok = true
    cb(res)
end)

QBCore.Functions.CreateCallback('mezos-inventory:server:drop', function(src, cb, req)
    if type(req) ~= 'table' or not MZ.Open[src] then return fail(src, cb, 'closed') end
    if not RateOk(src, 'move') then return fail(src, cb, 'rate') end
    local ok, err, dropId = DropFromPlayer(src, req.slot, req.amount)
    if not ok then return fail(src, cb, err) end
    local o = MZ.Open[src] and MZ.Open[src].other
    if not o or o.kind == 'ground' or o.kind == 'drop' then
        SwitchOther(src, { kind = 'drop', id = dropId, label = Lang:t('labels.drop') })
    end
    local res = snapshot(src) res.ok = true
    cb(res)
end)

QBCore.Functions.CreateCallback('mezos-inventory:server:give', function(src, cb, req)
    if type(req) ~= 'table' then return fail(src, cb, 'closed') end
    if not RateOk(src, 'give', 4) then return fail(src, cb, 'rate') end
    local ok, err = GiveItem(src, req.target, req.slot, req.amount)
    if not ok then return fail(src, cb, err) end
    local res = snapshot(src) res.ok = true
    cb(res)
end)

QBCore.Functions.CreateCallback('mezos-inventory:server:snapshot', function(src, cb)
    cb(snapshot(src))
end)

-- ───────────── auto-sort & stack ─────────────

local catOrder = {}
for i, c in ipairs(Config.Categories) do catOrder[c.id] = i end

--- Merge stacks and pack items in [first .. box.slots] by category then label. Equipment slots are untouched.
local function sortBox(box, first)
    local list, moved = {}, {}
    for slot = first, box.slots do
        local it = box.items[slot]
        if it then
            list[#list + 1] = it
            moved[it] = slot
            box.items[slot] = nil
        end
    end
    -- merge
    local merged, byName = {}, {}
    for _, it in ipairs(list) do
        local def = Utils.ItemDef(it.name)
        local max = def and not def.unique and Utils.Meta(it.name).stack
        local into = (def and not def.unique) and byName[it.name]
        if into and (not max or into.amount + it.amount <= max) then
            into.amount = into.amount + it.amount
            Decay.MergeInto(into, it.info)
        else
            merged[#merged + 1] = it
            if def and not def.unique then byName[it.name] = it end
        end
    end
    table.sort(merged, function(a, b)
        local ca = catOrder[Utils.Category(a.name)] or 99
        local cb = catOrder[Utils.Category(b.name)] or 99
        if ca ~= cb then return ca < cb end
        if a.label ~= b.label then return (a.label or a.name) < (b.label or b.name) end
        return (a.amount or 0) > (b.amount or 0)
    end)
    local slot = first
    for _, it in ipairs(merged) do
        while box.items[slot] do slot = slot + 1 end
        if slot > box.slots then return false end
        box.items[slot] = it
        it.slot = slot
        slot = slot + 1
    end
    return true, moved
end

QBCore.Functions.CreateCallback('mezos-inventory:server:sort', function(src, cb, req)
    if type(req) ~= 'table' or not MZ.Open[src] or not RateOk(src, 'sort', 1) then return fail(src, cb, 'rate') end
    local box = SideBox(src, req.side == 'other' and 'other' or 'player')
    if not box or box.kind == 'ground' then return fail(src, cb, 'access') end
    local copy = CopyBox(box)
    local first = (box.kind == 'player' and req.side == 'player') and (Config.HotbarSlots + 1) or 1
    local ok = sortBox(copy, first)
    if not ok then return fail(src, cb, 'slots') end
    CommitBox(copy)
    if box.kind == 'player' then
        for _, it in pairs(copy.items) do
            if it.type == 'weapon' then checkWeapon(box.src, it) end
        end
    end
    local res = snapshot(src) res.ok = true
    cb(res)
end)
