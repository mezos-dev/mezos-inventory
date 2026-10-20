-- Crafting benches: local props, qb-target or [E] prompt.

local props = {}

local function openBench(idx)
    if Client.open then return end
    if not PlayerData or IsNuiFocused() then return end
    TriggerServerEvent('mezos-inventory:server:openBench', idx)
end

local function spawn(idx, bench)
    if props[idx] and DoesEntityExist(props[idx]) then return end
    if not bench.prop then return end
    RequestModel(bench.prop)
    local t = GetGameTimer() + 3000
    while not HasModelLoaded(bench.prop) and GetGameTimer() < t do Wait(0) end
    if not HasModelLoaded(bench.prop) then return end
    local c = bench.coords
    local e = CreateObject(bench.prop, c.x, c.y, c.z - 1.0, false, false, false)
    SetEntityHeading(e, c.w or 0.0)
    PlaceObjectOnGroundProperly(e)
    FreezeEntityPosition(e, true)
    SetModelAsNoLongerNeeded(bench.prop)
    props[idx] = e
    if Config.UseTarget and GetResourceState('qb-target') == 'started' then
        exports['qb-target']:AddTargetEntity(e, {
            options = { { icon = 'fas fa-screwdriver-wrench', label = bench.label, action = function() openBench(idx) end } },
            distance = Config.BenchDistance,
        })
    end
end

local function despawn(idx)
    local e = props[idx]
    if e and DoesEntityExist(e) then
        if Config.UseTarget and GetResourceState('qb-target') == 'started' then
            pcall(function() exports['qb-target']:RemoveTargetEntity(e) end)
        end
        DeleteEntity(e)
    end
    props[idx] = nil
end

CreateThread(function()
    while true do
        local sleep = 1000
        if PlayerData then
            local pos = GetEntityCoords(PlayerPedId())
            for idx, bench in ipairs(Config.Benches) do
                local c = vector3(bench.coords.x, bench.coords.y, bench.coords.z)
                local dist = #(pos - c)
                if dist < 60.0 then spawn(idx, bench) else despawn(idx) end
                local usePrompt = not (Config.UseTarget and bench.prop and GetResourceState('qb-target') == 'started')
                if usePrompt and dist <= Config.BenchDistance and not Client.open then
                    sleep = 0
                    QBCore.Functions.DrawText3D(c.x, c.y, c.z + 0.1, Lang:t('interact.bench', { label = bench.label }))
                    if IsControlJustReleased(0, 38) and CanOpen() then openBench(idx) end
                elseif dist < 10.0 then
                    sleep = math.min(sleep, 250)
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for idx in pairs(props) do despawn(idx) end
end)
