-- Glovebox / trunk detection and trunk door handling.

local function isBackEngine(model) return BackEngineVehicles[model] end

local function trunkDoor(vehicle)
    return isBackEngine(GetEntityModel(vehicle)) and 4 or 5
end

local function openTrunk(vehicle)
    local ped = PlayerPedId()
    QBCore.Functions.RequestAnimDict('amb@prop_human_bum_bin@idle_b')
    TaskPlayAnim(ped, 'amb@prop_human_bum_bin@idle_b', 'idle_d', 4.0, 4.0, -1, 50, 0, false, false, false)
    SetVehicleDoorOpen(vehicle, trunkDoor(vehicle), false, false)
end

function CloseTrunk(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    local ped = PlayerPedId()
    QBCore.Functions.RequestAnimDict('amb@prop_human_bum_bin@idle_b')
    TaskPlayAnim(ped, 'amb@prop_human_bum_bin@idle_b', 'exit', 4.0, 4.0, -1, 50, 0, false, false, false)
    SetVehicleDoorShut(vehicle, trunkDoor(vehicle), false)
end

--- Context for opening: glovebox when seated, trunk when standing at the back of an unlocked vehicle.
function VehicleContext()
    local ped = PlayerPedId()
    local inVeh = GetVehiclePedIsIn(ped, false)
    if inVeh ~= 0 then
        return { kind = 'glovebox', plate = GetVehicleNumberPlateText(inVeh), class = GetVehicleClass(inVeh) }
    end
    local vehicle, distance = QBCore.Functions.GetClosestVehicle()
    if vehicle == 0 or distance > 5.0 then return nil end
    local pos = GetEntityCoords(ped)
    local dmin, dmax = GetModelDimensions(GetEntityModel(vehicle))
    local trunk = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, isBackEngine(GetEntityModel(vehicle)) and dmax.y or dmin.y, 0.0)
    if #(pos - trunk) > 1.5 then return nil end
    if GetVehicleDoorLockStatus(vehicle) >= 2 then
        QBCore.Functions.Notify(Lang:t('notify.vlocked'), 'error')
        return nil
    end
    if not NetworkGetEntityIsNetworked(vehicle) then return nil end
    openTrunk(vehicle)
    return {
        kind = 'trunk',
        plate = GetVehicleNumberPlateText(vehicle),
        class = GetVehicleClass(vehicle),
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        vehicle = vehicle,
    }
end
