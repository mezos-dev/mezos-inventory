-- Ground drops: server-owned data, clients spawn local props around them.

local counter = 0

local function syncData(d)
    return { id = d.name, coords = d.coords, bucket = d.bucket }
end

function CreateDrop(src, coords)
    counter = counter + 1
    local id = ('drop-%d%03d'):format(os.time() % 100000, counter % 1000)
    while MZ.Drops[id] do counter = counter + 1 id = ('drop-%d%03d'):format(os.time() % 100000, counter % 1000) end
    local drop = {
        name = id,
        label = Lang:t('labels.drop'),
        items = {},
        coords = vector3(coords.x, coords.y, coords.z),
        bucket = src and GetPlayerRoutingBucket(src) or 0,
        createdTime = os.time(),
        slots = Config.DropSize.slots,
        maxweight = Config.DropSize.maxweight,
        isOpen = false,
    }
    MZ.Drops[id] = drop
    TriggerClientEvent('mezos-inventory:client:dropAdd', -1, syncData(drop))
    return id
end

function RemoveDrop(id)
    local d = MZ.Drops[id]
    if not d then return end
    MZ.Drops[id] = nil
    TriggerClientEvent('mezos-inventory:client:dropRemove', -1, id)
    if d.isOpen and MZ.Open[d.isOpen] and MZ.Open[d.isOpen].other and MZ.Open[d.isOpen].other.id == id then
        SwitchOther(d.isOpen, { kind = 'ground', id = 'ground', label = Lang:t('labels.ground') })
    end
end

--- Nearest drop within radius in the player's routing bucket.
--- excludeLocked: ignore drops someone else has open.
function NearestDrop(src, radius, excludeLocked)
    local pos, bucket = PlayerCoords(src), GetPlayerRoutingBucket(src)
    local best, bestDist
    for id, d in pairs(MZ.Drops) do
        if d.bucket == bucket and not (excludeLocked and d.isOpen and d.isOpen ~= src) then
            local dist = #(d.coords - pos)
            if dist <= radius and (not bestDist or dist < bestDist) then best, bestDist = id, dist end
        end
    end
    return best
end

QBCore.Functions.CreateCallback('mezos-inventory:server:drops', function(_, cb)
    local list = {}
    for _, d in pairs(MZ.Drops) do list[#list + 1] = syncData(d) end
    cb(list)
end)

-- Expire old drops that nobody is looking at
CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for id, d in pairs(MZ.Drops) do
            if not d.isOpen and (not next(d.items) or d.createdTime + Config.DropLifetime * 60 < now) then
                RemoveDrop(id)
            end
        end
    end
end)
