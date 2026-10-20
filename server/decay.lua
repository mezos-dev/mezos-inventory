-- Durability over time. Quality is derived from info.created and the item's decay time,
-- so nothing ticks in the background: it's recalculated whenever an inventory is loaded, viewed or used.

Decay = {}

local function hours(name)
    local d = Config.Decay.enabled and Utils.Meta(name).decay
    return tonumber(d)
end

function Decay.Stamp(def, info)
    if not hours(def.name) then return end
    if not tonumber(info.created) then info.created = os.time() end
    if not info.quality then info.quality = 100 end
end

function Decay.Quality(item)
    local h = hours(item.name)
    if not h or h <= 0 then return item.info and tonumber(item.info.quality) or nil end
    local created = tonumber(item.info and item.info.created)
    if not created then return 100 end
    local q = 100 - ((os.time() - created) / (h * 3600)) * 100
    return math.max(0, math.min(100, math.floor(q * 10 + 0.5) / 10))
end

function Decay.IsSpoiled(item)
    local h = hours(item.name)
    if not h then return false end
    return (Decay.Quality(item) or 100) <= 0
end

--- Merging a stack keeps the oldest timestamp, so fresh items can't "reset" old ones.
function Decay.MergeInto(cur, info)
    if not hours(cur.name) or type(info) ~= 'table' then return end
    local a, b = tonumber(cur.info.created), tonumber(info.created)
    if a and b then cur.info.created = math.min(a, b)
    elseif b then cur.info.created = b end
    cur.info.quality = Decay.Quality(cur)
end

--- Update info.quality on decaying items. Returns true if anything changed (or got removed).
function Decay.RefreshItems(items)
    if not Config.Decay.enabled or type(items) ~= 'table' then return false end
    local changed = false
    for slot, item in pairs(items) do
        if type(item) == 'table' and hours(item.name) then
            if type(item.info) ~= 'table' then item.info = {} end
            if not tonumber(item.info.created) then
                item.info.created = os.time()
                changed = true
            end
            local q = Decay.Quality(item)
            if q <= 0 and Config.Decay.removeWhenSpoiled then
                items[slot] = nil
                changed = true
            elseif math.floor(tonumber(item.info.quality) or -1) ~= math.floor(q) then
                item.info.quality = q
                changed = true
            end
        end
    end
    return changed
end

function Decay.RefreshBox(box)
    if box and Decay.RefreshItems(box.items) then CommitBox(box) end
end
