-- Hotbar keys 1..n, hotbar popup (Z), quick-wheel (F2) and weapon wheel suppression.

local hotbarShown = false
local lastUse = 0

local function hotbarItems()
    local items = PlayerData and PlayerData.items or {}
    local list = {}
    for i = 1, Config.HotbarSlots do
        local d = Decorate(items[i])
        if d then d.slot = i end
        list[i] = d or false
    end
    return list
end

function RefreshHotbar()
    if hotbarShown then SendNUIMessage({ action = 'hotbar', show = true, items = hotbarItems() }) end
end

local function useSlot(i)
    if Client.open or Client.wheelOpen or IsNuiFocused() or IsPauseMenuActive() then return end
    if not PlayerData or not PlayerData.items then return end
    if GetGameTimer() - lastUse < 250 then return end
    lastUse = GetGameTimer()
    local item = PlayerData.items[i]
    SendNUIMessage({ action = 'hotbarPulse', slot = i, items = hotbarItems() })
    if not item then return end
    if item.type == 'weapon' and HoldingDrop then
        return QBCore.Functions.Notify(Lang:t('notify.nogunbag'), 'error')
    end
    TriggerServerEvent('mezos-inventory:server:useSlot', i)
end

for i = 1, Config.HotbarSlots do
    RegisterCommand('slot_' .. i, function() useSlot(i) end, false)
    RegisterKeyMapping('slot_' .. i, Lang:t('keys.slot', { slot = i }), 'keyboard', tostring(i))
end

local function toggleHotbar(force, items)
    if force ~= nil then hotbarShown = force else hotbarShown = not hotbarShown end
    SendNUIMessage({ action = 'hotbar', show = hotbarShown, items = items or hotbarItems() })
end

RegisterCommand('toggleHotbar', function()
    if Client.open or IsPauseMenuActive() then return end
    toggleHotbar()
end, false)
RegisterKeyMapping('toggleHotbar', Lang:t('keys.hotbar'), 'keyboard', Config.Keybinds.Hotbar)

RegisterNetEvent('qb-inventory:client:hotbar', function(items)
    local list = {}
    for i = 1, Config.HotbarSlots do
        local d = Decorate(type(items) == 'table' and items[i] or nil)
        if d then d.slot = i end
        list[i] = d or false
    end
    toggleHotbar(nil, list)
end)

-- ───────────── quick wheel ─────────────

function CloseWheel()
    if not Client.wheelOpen then return end
    Client.wheelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'wheel', show = false })
end

RegisterCommand('mz_wheel', function()
    if Client.wheelOpen then return CloseWheel() end
    if Client.open or not CanOpen() then return end
    Client.wheelOpen = true
    Client.alive = GetGameTimer()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'wheel', show = true, player = PlayerView(), config = StaticConfig() })
end, false)
RegisterKeyMapping('mz_wheel', Lang:t('keys.wheel'), 'keyboard', Config.Keybinds.Wheel)

-- ───────────── weapon wheel ─────────────

if Config.DisableWeaponWheel then
    CreateThread(function()
        while true do
            if PlayerData then
                BlockWeaponWheelThisFrame()
                DisableControlAction(0, 37, true)   -- INPUT_SELECT_WEAPON (TAB)
                for c = 157, 165 do DisableControlAction(0, c, true) end -- number-key weapon slots
                HideHudComponentThisFrame(19)
                HideHudComponentThisFrame(20)
                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end
