-- Crafting & repair at benches. The timer runs in the UI, but the server owns it:
-- ingredients are checked at start AND taken at finish, and finish is refused before the time is up.

local function benchAllowed(bench, player)
    local pd = player.PlayerData
    if bench.job then
        local need = bench.job[pd.job.name]
        if need == nil or (pd.job.grade and pd.job.grade.level or 0) < need then return false end
    end
    if bench.gang then
        local need = bench.gang[pd.gang.name]
        if need == nil or (pd.gang.grade and pd.gang.grade.level or 0) < need then return false end
    end
    return true
end

local function itemView(name, amount)
    local def = Utils.ItemDef(name)
    return { name = name, amount = amount, label = def and def.label or name, image = def and def.image or 'placeholder.png' }
end

function BenchPayload(idx, src)
    local bench = Config.Benches[idx]
    if not bench then return nil end
    local recipes = {}
    for _, id in ipairs(bench.recipes or {}) do
        local r = Config.Recipes[id]
        local def = r and Utils.ItemDef(r.item)
        if def then
            local ing, tools = {}, {}
            for name, amount in pairs(r.ingredients or {}) do ing[#ing + 1] = itemView(name, amount) end
            for name in pairs(r.tools or {}) do tools[#tools + 1] = itemView(name, 1) end
            table.sort(ing, function(a, b) return a.label < b.label end)
            recipes[#recipes + 1] = {
                id = id, item = r.item, label = r.label or def.label, image = def.image, description = def.description,
                amount = r.amount or 1, time = r.time or 5, ingredients = ing, tools = tools,
            }
        end
    end
    local repairCost = {}
    for name, amount in pairs(Config.Repair.items) do repairCost[#repairCost + 1] = itemView(name, amount) end
    return { index = idx, label = bench.label, recipes = recipes, repair = bench.repair == true, repairCost = repairCost, repairTime = Config.Repair.time }
end

local function countIn(items, name)
    local c = 0
    for _, it in pairs(items) do if it.name == name then c = c + it.amount end end
    return c
end

--- Simulate a craft on a copy of the player's box. Returns the copy or nil, err.
local function simulateCraft(src, recipe, times)
    local box = PlayerBox(src)
    if not box then return nil, 'closed' end
    for name in pairs(recipe.tools or {}) do
        if countIn(box.items, name) < 1 then return nil, 'missingTools' end
    end
    for name, amount in pairs(recipe.ingredients or {}) do
        if countIn(box.items, name) < amount * times then return nil, 'missingIngredients' end
    end
    local test = CopyBox(box)
    for name, amount in pairs(recipe.ingredients or {}) do
        if not BoxRemove(test, name, amount * times) then return nil, 'missingIngredients' end
    end
    local ok, why = BoxAdd(test, recipe.item, (recipe.amount or 1) * times, nil, Utils.Copy(recipe.info or {}))
    if not ok then return nil, why end
    if not BackpackCheck(test) then return nil, 'backpack' end
    return test
end

local function benchSession(src)
    local s = MZ.Open[src]
    local o = s and s.other
    if not o or o.kind ~= 'crafting' or not SessionInRange(src, o) then return nil end
    return o, Config.Benches[o.bench]
end

RegisterNetEvent('mezos-inventory:server:openBench', function(idx)
    local src = source
    idx = Utils.Int(idx)
    local bench = idx and Config.Benches[idx]
    local player = GetQBPlayer(src)
    if not bench or not player then return end
    if #(PlayerCoords(src) - vector3(bench.coords.x, bench.coords.y, bench.coords.z)) > Config.BenchDistance + 1.5 then return end
    if not benchAllowed(bench, player) then return Notify(src, Lang:t('notify.cantUse'), 'error') end
    local other = { kind = 'crafting', id = 'bench-' .. idx, bench = idx, label = bench.label }
    if MZ.Open[src] then SwitchOther(src, other) else OpenSession(src, other) end
end)

QBCore.Functions.CreateCallback('mezos-inventory:server:craftStart', function(src, cb, req)
    if type(req) ~= 'table' or not RateOk(src, 'craft', 3) then return cb({ ok = false, err = 'rate' }) end
    local o, bench = benchSession(src)
    if not o then return cb({ ok = false, err = 'tooFar' }) end
    local allowed = false
    for _, id in ipairs(bench.recipes or {}) do if id == req.recipe then allowed = true end end
    local recipe = allowed and Config.Recipes[req.recipe]
    local times = Utils.Int(req.times, 50)
    if not recipe or not times then return cb({ ok = false, err = 'amount' }) end
    local _, err = simulateCraft(src, recipe, times)
    if err then return cb({ ok = false, err = err }) end
    local duration = math.floor((recipe.time or 5) * 1000 * times)
    MZ.Crafting[src] = { kind = 'craft', recipe = req.recipe, times = times, finish = GetGameTimer() + duration, bench = o.bench }
    cb({ ok = true, duration = duration })
end)

QBCore.Functions.CreateCallback('mezos-inventory:server:craftFinish', function(src, cb)
    local job = MZ.Crafting[src]
    if not job or job.kind ~= 'craft' then return cb({ ok = false, err = 'closed' }) end
    if GetGameTimer() < job.finish - 400 then return cb({ ok = false, err = 'early' }) end
    MZ.Crafting[src] = nil
    local o = benchSession(src)
    if not o or o.bench ~= job.bench then return cb({ ok = false, err = 'tooFar' }) end
    local recipe = Config.Recipes[job.recipe]
    local test, err = simulateCraft(src, recipe, job.times)
    if not test then return cb({ ok = false, err = err }) end
    CommitBox(test)
    local total = (recipe.amount or 1) * job.times
    local def = Utils.ItemDef(recipe.item)
    for name, amount in pairs(recipe.ingredients or {}) do
        TriggerClientEvent('qb-inventory:client:ItemBox', src, Utils.ItemDef(name), 'remove', amount * job.times)
    end
    TriggerClientEvent('qb-inventory:client:ItemBox', src, def, 'add', total)
    Notify(src, Lang:t('notify.crafted', { amount = total, item = def.label }), 'success')
    Log('Crafted', 'green', ('**Player:** %s (%s)\n**Item:** %s x%d'):format(GetPlayerName(src) or '?', src, recipe.item, total))
    cb({ ok = true })
end)

QBCore.Functions.CreateCallback('mezos-inventory:server:craftCancel', function(src, cb)
    MZ.Crafting[src] = nil
    cb({ ok = true })
end)

-- ───────────── repair ─────────────

local function repairCost(name)
    local meta = Utils.Meta(name)
    return (meta.repair and meta.repair.items) or Config.Repair.items
end

local function simulateRepair(src, slot, expect)
    local box = PlayerBox(src)
    local item = box and box.items[slot]
    if not item then return nil, 'missing' end
    if expect and (item.name ~= expect.name or (item.info.serie and item.info.serie ~= expect.serie)) then return nil, 'stale' end
    if Utils.Meta(item.name).decay then return nil, 'noRepair' end
    local q = tonumber(item.info and item.info.quality)
    if not q or q >= Config.Repair.restore then return nil, 'noRepair' end
    local test = CopyBox(box)
    for name, amount in pairs(repairCost(item.name)) do
        if countIn(test.items, name) < amount then return nil, 'missingIngredients' end
        if not BoxRemove(test, name, amount) then return nil, 'missingIngredients' end
    end
    -- the repaired item may have moved slots if a cost item shared its stack; it can't (unique quality items), but be safe
    local repaired = test.items[slot]
    if not repaired or repaired.name ~= item.name then return nil, 'stale' end
    repaired.info.quality = Config.Repair.restore
    return test, item
end

QBCore.Functions.CreateCallback('mezos-inventory:server:repairStart', function(src, cb, req)
    if type(req) ~= 'table' or not RateOk(src, 'craft', 3) then return cb({ ok = false, err = 'rate' }) end
    local o, bench = benchSession(src)
    if not o or not bench.repair then return cb({ ok = false, err = 'tooFar' }) end
    local slot = Utils.Int(req.slot)
    if not slot then return cb({ ok = false, err = 'missing' }) end
    local test, item = simulateRepair(src, slot)
    if not test then return cb({ ok = false, err = item }) end
    local duration = math.floor(Config.Repair.time * 1000)
    MZ.Crafting[src] = { kind = 'repair', slot = slot, name = item.name, serie = item.info.serie, finish = GetGameTimer() + duration, bench = o.bench }
    cb({ ok = true, duration = duration })
end)

QBCore.Functions.CreateCallback('mezos-inventory:server:repairFinish', function(src, cb)
    local job = MZ.Crafting[src]
    if not job or job.kind ~= 'repair' then return cb({ ok = false, err = 'closed' }) end
    if GetGameTimer() < job.finish - 400 then return cb({ ok = false, err = 'early' }) end
    MZ.Crafting[src] = nil
    local o = benchSession(src)
    if not o or o.bench ~= job.bench then return cb({ ok = false, err = 'tooFar' }) end
    local test, item = simulateRepair(src, job.slot, { name = job.name, serie = job.serie })
    if not test then return cb({ ok = false, err = item }) end
    CommitBox(test)
    if item.type == 'weapon' then checkWeapon(src, item) end
    Notify(src, Lang:t('notify.repaired', { item = item.label }), 'success')
    cb({ ok = true })
end)
