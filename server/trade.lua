-- Secure player-to-player trading.
-- Offers are references (slot + amount), nothing moves until both players lock AND confirm.
-- Any change to an offer or either inventory resets both locks. The final swap re-validates
-- everything and is applied to both players atomically.

local nextId = 0

local function partnerOf(t, src) return t.a == src and t.b or t.a end

local function tradeItems(t, src)
    local list = {}
    local box = PlayerBox(src)
    for slot, o in pairs(t.offers[src]) do
        local it = box and box.items[slot]
        if it then
            local view = Utils.Copy(it)
            view.amount = o.amount
            view.slot = slot
            list[#list + 1] = view
        end
    end
    table.sort(list, function(x, y) return x.slot < y.slot end)
    return list
end

function TradePayload(id, src)
    local t = MZ.Trades[id]
    if not t then return nil end
    local other = partnerOf(t, src)
    return {
        id = id,
        state = t.state,
        partner = { id = other, name = t.names[other] },
        mine = tradeItems(t, src),
        theirs = tradeItems(t, other),
        myLock = t.locked[src] == true,
        theirLock = t.locked[other] == true,
        myConfirm = t.confirmed[src] == true,
        theirConfirm = t.confirmed[other] == true,
    }
end

local function push(t)
    for _, s in ipairs({ t.a, t.b }) do
        local sess = MZ.Open[s]
        if sess and sess.other and sess.other.kind == 'trade' and sess.other.trade == t.id then
            PushOther(s)
        end
    end
end

local function resetLocks(t)
    t.locked, t.confirmed = {}, {}
end

local function charName(src)
    local p = GetQBPlayer(src)
    local ci = p and p.PlayerData.charinfo
    return ci and (ci.firstname .. ' ' .. ci.lastname) or GetPlayerName(src) or ('#' .. src)
end

function CancelTradeOf(src, reason)
    local id = MZ.TradeOf[src]
    local t = id and MZ.Trades[id]
    if not t then MZ.TradeOf[src] = nil return end
    MZ.Trades[id] = nil
    MZ.TradeOf[t.a], MZ.TradeOf[t.b] = nil, nil
    for _, s in ipairs({ t.a, t.b }) do
        if GetPlayerName(s) then
            local sess = MZ.Open[s]
            if sess and sess.other and sess.other.kind == 'trade' and sess.other.trade == id then
                sess.other = nil -- avoid re-entering releaseOther
                SwitchOther(s, { kind = 'ground', id = 'ground', label = Lang:t('labels.ground') })
            end
            if reason ~= 'done' and t.state == 'active' then Notify(s, Lang:t('notify.tradeCancelled'), 'error') end
            if reason == 'declined' and s == t.a then Notify(s, Lang:t('notify.tradeDeclined'), 'error') end
            TriggerClientEvent('mezos-inventory:client:tradeEnded', s, id)
        end
    end
end

--- Called whenever a trading player's inventory changes: clamp offers, reset locks.
function TradeOnInventoryChanged(src)
    local id = MZ.TradeOf[src]
    local t = id and MZ.Trades[id]
    if not t or t.state ~= 'active' or t.committing then return end
    local box = PlayerBox(src)
    local changed = false
    for slot, o in pairs(t.offers[src]) do
        local it = box and box.items[slot]
        if not it or it.name ~= o.name then
            t.offers[src][slot] = nil
            changed = true
        elseif it.amount < o.amount then
            o.amount = it.amount
            changed = true
        end
    end
    if changed or t.locked[src] then resetLocks(t) end
    push(t)
end

local function validPair(a, b)
    local pa, pb = GetQBPlayer(a), GetQBPlayer(b)
    if not pa or not pb or IsIncapacitated(pa) or IsIncapacitated(pb) then return false end
    return #(PlayerCoords(a) - PlayerCoords(b)) <= Config.TradeDistance
end

-- ───────────── requests ─────────────

QBCore.Functions.CreateCallback('mezos-inventory:server:tradeRequest', function(src, cb, req)
    if type(req) ~= 'table' or not RateOk(src, 'trade', 2) then return cb({ ok = false, err = 'rate' }) end
    local target = tonumber(req.target)
    if not target or target == src or not GetQBPlayer(target) then return cb({ ok = false, err = 'target' }) end
    if not validPair(src, target) then return cb({ ok = false, err = 'tooFar' }) end
    if MZ.TradeOf[src] then CancelTradeOf(src, 'replaced') end
    if MZ.TradeOf[target] then return cb({ ok = false, err = 'tradeBusy' }) end

    nextId = nextId + 1
    local id = ('T%d'):format(nextId)
    MZ.Trades[id] = {
        id = id, a = src, b = target, state = 'pending', created = os.time(),
        offers = { [src] = {}, [target] = {} }, locked = {}, confirmed = {},
        names = { [src] = charName(src), [target] = charName(target) },
    }
    MZ.TradeOf[src], MZ.TradeOf[target] = id, id
    TriggerClientEvent('mezos-inventory:client:tradeIncoming', target, { id = id, from = src, name = MZ.Trades[id].names[src] })
    Notify(target, Lang:t('notify.tradeRequest', { name = MZ.Trades[id].names[src] }), 'primary', 8000)
    Notify(src, Lang:t('notify.tradeSent'), 'success')

    SetTimeout(30000, function()
        local t = MZ.Trades[id]
        if t and t.state == 'pending' then CancelTradeOf(src, 'expired') end
    end)
    cb({ ok = true })
end)

RegisterNetEvent('mezos-inventory:server:tradeRespond', function(id, accept)
    local src = source
    local t = type(id) == 'string' and MZ.Trades[id]
    if not t or t.b ~= src or t.state ~= 'pending' then return end
    if not accept then return CancelTradeOf(src, 'declined') end
    if not validPair(t.a, t.b) then return CancelTradeOf(src, 'tooFar') end
    t.state = 'active'
    for _, s in ipairs({ t.a, t.b }) do
        local other = { kind = 'trade', id = 'trade-' .. id, trade = id, label = 'Trade' }
        if MZ.Open[s] then SwitchOther(s, other) else OpenSession(s, other, { force = true }) end
    end
end)

-- ───────────── offers & locking ─────────────

local function activeTrade(src)
    local id = MZ.TradeOf[src]
    local t = id and MZ.Trades[id]
    if not t or t.state ~= 'active' then return nil end
    return t
end

QBCore.Functions.CreateCallback('mezos-inventory:server:tradeOffer', function(src, cb, req)
    local t = activeTrade(src)
    if not t or type(req) ~= 'table' or not RateOk(src, 'move') then return cb({ ok = false, err = 'closed' }) end
    local slot = Utils.Int(req.slot)
    local amount = tonumber(req.amount) or 0
    if not slot then return cb({ ok = false, err = 'slot' }) end
    if amount <= 0 then
        t.offers[src][slot] = nil
    else
        amount = Utils.Int(amount)
        local box = PlayerBox(src)
        local it = box and box.items[slot]
        if not it or not amount then return cb({ ok = false, err = 'missing' }) end
        if Utils.Meta(it.name).noTrade then return cb({ ok = false, err = 'noTrade' }) end
        local sess = MZ.Open[src]
        if it.info and it.info.containerId and sess and sess.other and sess.other.container == it.info.containerId then
            return cb({ ok = false, err = 'containerOpen' })
        end
        local count = 0
        for _ in pairs(t.offers[src]) do count = count + 1 end
        if not t.offers[src][slot] and count >= 12 then return cb({ ok = false, err = 'slots' }) end
        t.offers[src][slot] = { name = it.name, amount = math.min(amount, it.amount) }
    end
    resetLocks(t)
    push(t)
    cb({ ok = true })
end)

QBCore.Functions.CreateCallback('mezos-inventory:server:tradeLock', function(src, cb, lock)
    local t = activeTrade(src)
    if not t then return cb({ ok = false, err = 'closed' }) end
    t.locked[src] = lock == true or nil
    t.confirmed = {}
    push(t)
    cb({ ok = true })
end)

local function commit(t)
    local a, b = t.a, t.b
    if not validPair(a, b) then return false, 'tooFar' end
    local A, B = PlayerBox(a), PlayerBox(b)
    if not A or not B then return false, 'closed' end
    local TA, TB = CopyBox(A), CopyBox(B)
    local moving = { [a] = {}, [b] = {} }

    for _, side in ipairs({ { a, TA }, { b, TB } }) do
        local s, box = side[1], side[2]
        for slot, o in pairs(t.offers[s]) do
            local it = box.items[slot]
            if not it or it.name ~= o.name or it.amount < o.amount then return false, 'changed' end
            moving[s][#moving[s] + 1] = { name = it.name, amount = o.amount, info = Utils.Copy(it.info), type = it.type }
            if not BoxRemove(box, it.name, o.amount, slot) then return false, 'changed' end
        end
    end
    for _, m in ipairs(moving[a]) do
        if not BoxAdd(TB, m.name, m.amount, nil, m.info, true) then return false, 'full' end
    end
    for _, m in ipairs(moving[b]) do
        if not BoxAdd(TA, m.name, m.amount, nil, m.info, true) then return false, 'full' end
    end
    if not BackpackCheck(TA) or not BackpackCheck(TB) then return false, 'backpack' end

    t.committing = true
    CommitBox(TA)
    CommitBox(TB)
    t.committing = nil

    for _, m in ipairs(moving[a]) do
        if m.type == 'weapon' then checkWeapon(a, m) end
        TriggerClientEvent('qb-inventory:client:ItemBox', a, Utils.ItemDef(m.name), 'remove', m.amount)
        TriggerClientEvent('qb-inventory:client:ItemBox', b, Utils.ItemDef(m.name), 'add', m.amount)
    end
    for _, m in ipairs(moving[b]) do
        if m.type == 'weapon' then checkWeapon(b, m) end
        TriggerClientEvent('qb-inventory:client:ItemBox', b, Utils.ItemDef(m.name), 'remove', m.amount)
        TriggerClientEvent('qb-inventory:client:ItemBox', a, Utils.ItemDef(m.name), 'add', m.amount)
    end
    local function list(ms)
        local out = {}
        for _, m in ipairs(ms) do out[#out + 1] = m.name .. ' x' .. m.amount end
        return #out > 0 and table.concat(out, ', ') or 'nothing'
    end
    Log('Trade', 'purple', ('**%s (%s)** gave: %s\n**%s (%s)** gave: %s')
        :format(GetPlayerName(a) or '?', a, list(moving[a]), GetPlayerName(b) or '?', b, list(moving[b])))
    return true
end

QBCore.Functions.CreateCallback('mezos-inventory:server:tradeConfirm', function(src, cb)
    local t = activeTrade(src)
    if not t then return cb({ ok = false, err = 'closed' }) end
    if not (t.locked[t.a] and t.locked[t.b]) then return cb({ ok = false, err = 'notLocked' }) end
    t.confirmed[src] = true
    if t.confirmed[t.a] and t.confirmed[t.b] then
        local ok, err = commit(t)
        if not ok then
            resetLocks(t)
            push(t)
            Notify(t.a, Lang:t('notify.tradeFailed'), 'error')
            Notify(t.b, Lang:t('notify.tradeFailed'), 'error')
            return cb({ ok = false, err = err })
        end
        Notify(t.a, Lang:t('notify.tradeDone'), 'success')
        Notify(t.b, Lang:t('notify.tradeDone'), 'success')
        CancelTradeOf(src, 'done')
        return cb({ ok = true, done = true })
    end
    push(t)
    cb({ ok = true })
end)

RegisterNetEvent('mezos-inventory:server:tradeCancel', function()
    CancelTradeOf(source, 'cancelled')
end)

-- distance / state watchdog for active trades
CreateThread(function()
    while true do
        Wait(1000)
        for id, t in pairs(MZ.Trades) do
            if t.state == 'active' and not validPair(t.a, t.b) then
                CancelTradeOf(t.a, 'tooFar')
            end
        end
    end
end)
