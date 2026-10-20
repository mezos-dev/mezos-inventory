QBCore = exports['qb-core']:GetCoreObject()

Utils = {}

-- ───────────── item definitions ─────────────

function Utils.ItemDef(name)
    if type(name) ~= 'string' then return nil end
    return QBCore.Shared.Items[name:lower()]
end

function Utils.Meta(name)
    if type(name) ~= 'string' then return {} end
    return Config.ItemMeta[name:lower()] or {}
end

local categoryRules = {
    { 'ammo', 'ammo' },
    { '_attachment', 'tool' }, { 'muzzle_brake', 'tool' }, { 'weapontint', 'tool' },
    { 'weed_', 'drug' }, { 'coke', 'drug' }, { 'meth', 'drug' },
    { 'veh_', 'tool' }, { 'kit', 'tool' },
}

function Utils.Category(name, def)
    def = def or Utils.ItemDef(name)
    local meta = Utils.Meta(name)
    if meta.category then return meta.category end
    if def and def.type == 'weapon' then return 'weapon' end
    for i = 1, #categoryRules do
        if name:find(categoryRules[i][1], 1, true) then return categoryRules[i][2] end
    end
    return 'misc'
end

function Utils.Rarity(name, def)
    def = def or Utils.ItemDef(name)
    local meta = Utils.Meta(name)
    if meta.rarity then return meta.rarity end
    if def and def.type == 'weapon' then return Config.WeaponRarity or 'common' end
    return 'common'
end

-- ───────────── equipment ─────────────

local equipBySlot, equipById = {}, {}
for _, e in ipairs(Config.EquipSlots) do
    equipBySlot[e.slot] = e
    equipById[e.id] = e
end

function Utils.EquipBySlot(slot) return equipBySlot[tonumber(slot) or -1] end
function Utils.EquipById(id) return equipById[id] end
function Utils.IsEquipSlot(slot) return equipBySlot[tonumber(slot) or -1] ~= nil end

--- Can this item go into this equipment slot?
function Utils.CanEquip(equip, name)
    if not equip or not name then return false end
    local def = Utils.ItemDef(name)
    if not def then return false end
    local meta = Utils.Meta(name)
    if meta.equip == equip.id then return true end
    if equip.accepts then
        for _, a in ipairs(equip.accepts) do
            if a == def.name or a == def.type then return true end
        end
    end
    return false
end

--- Player capacity (slots, weight) including the equipped backpack bonus.
function Utils.Capacity(items)
    local slots, weight = Config.MaxSlots, Config.MaxWeight
    local bp = equipById.backpack and items and items[equipById.backpack.slot]
    if bp and bp.name then
        local b = Utils.Meta(bp.name).backpack
        if b then
            slots = slots + (b.slots or 0)
            weight = weight + (b.weight or 0)
        end
    end
    return math.min(slots, 100), weight
end

-- ───────────── math ─────────────

function Utils.Weight(items)
    local w = 0
    if type(items) ~= 'table' then return 0 end
    for _, item in pairs(items) do
        if type(item) == 'table' then
            local amount = tonumber(item.amount) or 1
            w = w + (tonumber(item.weight) or 0) * amount
        end
    end
    return w
end

--- Positive integer or nil (rejects NaN, inf, floats, negatives, strings)
function Utils.Int(v, max)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    if v < 1 or math.floor(v) ~= v then return nil end
    if max and v > max then return nil end
    return v
end

function Utils.Copy(t, seen)
    if type(t) ~= 'table' then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do out[Utils.Copy(k, seen)] = Utils.Copy(v, seen) end
    return out
end

function Utils.Serial()
    return tostring(QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(4))
end

function Utils.Debug(...)
    if Config.Debug then print('^5[mezos-inventory]^7', ...) end
end
