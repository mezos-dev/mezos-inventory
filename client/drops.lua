-- Ground drops: local props near the player, open with TAB or E when close.

HoldingDrop = false
local Drops = {}   -- id → { id, coords, bucket, entity }

local function spawnProp(d)
    if d.entity and DoesEntityExist(d.entity) then return end
    local model = Config.DropModel
    if not HasModelLoaded(model) then
        RequestModel(model)
        local t = GetGameTimer() + 3000
        while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
        if not HasModelLoaded(model) then return end
    end
    local e = CreateObject(model, d.coords.x, d.coords.y, d.coords.z - 0.9, false, false, false)
    PlaceObjectOnGroundProperly(e)
    FreezeEntityPosition(e, true)
    SetEntityCollision(e, false, false)
    SetModelAsNoLongerNeeded(model)
    d.entity = e
end

local function despawnProp(d)
    if d.entity and DoesEntityExist(d.entity) then DeleteEntity(d.entity) end
    d.entity = nil
end

function LoadDrops()
    QBCore.Functions.TriggerCallback('mezos-inventory:server:drops', function(list)
        for _, d in pairs(Drops) do despawnProp(d) end
        Drops = {}
        for _, d in ipairs(list or {}) do Drops[d.id] = d end
    end)
end

RegisterNetEvent('mezos-inventory:client:dropAdd', function(d)
    if type(d) ~= 'table' or not d.id then return end
    if Drops[d.id] then despawnProp(Drops[d.id]) end
    Drops[d.id] = d
end)

RegisterNetEvent('mezos-inventory:client:dropRemove', function(id)
    local d = Drops[id]
    if d then despawnProp(d) end
    Drops[id] = nil
end)

function NearestDropId(radius)
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for id, d in pairs(Drops) do
        local dist = #(vector3(d.coords.x, d.coords.y, d.coords.z) - pos)
        if dist <= radius and (not bestDist or dist < bestDist) then best, bestDist = id, dist end
    end
    return best
end

-- stream props + prompt
CreateThread(function()
    while true do
        local sleep = 750
        if PlayerData then
            local pos = GetEntityCoords(PlayerPedId())
            local near
            for _, d in pairs(Drops) do
                local c = vector3(d.coords.x, d.coords.y, d.coords.z)
                local dist = #(c - pos)
                if dist <= Config.DropRenderDistance then spawnProp(d) else despawnProp(d) end
                if dist <= Config.DropOpenDistance and (not near or dist < near.dist) then near = { d = d, dist = dist, c = c } end
            end
            if near and not Client.open and not IsNuiFocused() then
                sleep = 0
                QBCore.Functions.DrawText3D(near.c.x, near.c.y, near.c.z - 0.6, Lang:t('interact.drop'))
                if IsControlJustReleased(0, 38) and CanOpen() then
                    TriggerServerEvent('mezos-inventory:server:open', { kind = 'drop', id = near.d.id })
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, d in pairs(Drops) do despawnProp(d) end
end)
