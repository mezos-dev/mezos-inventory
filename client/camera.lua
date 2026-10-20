-- Showcase camera: frames your character in the transparent centre of the UI.

Camera = { cam = nil, heading = nil, allowed = true }

local function canUse()
    if not Config.ShowcaseCamera or not Camera.allowed then return false end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedSwimming(ped) then return false end
    return true
end

local function placement(ped)
    local pos = GetEntityCoords(ped)
    local dist = 2.35
    local target = GetOffsetFromEntityInWorldCoords(ped, 0.0, dist, 0.25)
    -- keep the camera out of walls
    local ray = StartShapeTestRay(pos.x, pos.y, pos.z + 0.25, target.x, target.y, target.z, 1 + 16, ped, 0)
    local _, hit, hitPos = GetShapeTestResult(ray)
    if hit == 1 then
        local d = math.max(0.9, #(hitPos - pos) - 0.25)
        target = GetOffsetFromEntityInWorldCoords(ped, 0.0, d, 0.25)
    end
    return target, pos
end

function Camera.Start()
    if Camera.cam then return end
    if not canUse() then
        if Config.Blur then TriggerScreenblurFadeIn(250) end
        return
    end
    local ped = PlayerPedId()
    Camera.heading = GetEntityHeading(ped)
    local camPos, pedPos = placement(ped)
    Camera.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, 42.0, false, 0)
    PointCamAtCoord(Camera.cam, pedPos.x, pedPos.y, pedPos.z + 0.05)
    SetCamActive(Camera.cam, true)
    RenderScriptCams(true, true, 450, true, true)
    SetTimecycleModifier('MP_corona_heist_DOF')
    SetTimecycleModifierStrength(0.6)
end

function Camera.Stop()
    if Config.Blur then TriggerScreenblurFadeOut(250) end
    if not Camera.cam then return end
    RenderScriptCams(false, true, 350, true, true)
    DestroyCam(Camera.cam, false)
    Camera.cam = nil
    ClearTimecycleModifier()
    local ped = PlayerPedId()
    if Camera.heading and not IsPedInAnyVehicle(ped, false) then SetEntityHeading(ped, Camera.heading) end
    Camera.heading = nil
end

function Camera.Rotate(delta)
    if not Camera.cam then return end
    local ped = PlayerPedId()
    SetEntityHeading(ped, (GetEntityHeading(ped) + math.max(-45.0, math.min(45.0, delta))) % 360.0)
end

-- The UI turns the camera off on narrow layouts where the centre isn't visible
function Camera.SetAllowed(allowed)
    if Camera.allowed == allowed then return end
    Camera.allowed = allowed
    if not Client.open then return end
    if allowed then Camera.Start() else Camera.Stop() if Config.Blur then TriggerScreenblurFadeIn(150) end end
end
