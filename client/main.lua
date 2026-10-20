-- Client state, item decoration, opening/closing and the NUI focus watchdog.

PlayerData = nil
Client = {
    open = false,
    other = nil,          -- last secondary payload (raw)
    alive = 0,            -- last NUI heartbeat
    trunkVehicle = nil,
    wheelOpen = false,
}

-- ───────────── decoration (UI-friendly item views) ─────────────

function Decorate(item)
    if type(item) ~= 'table' or not item.name then return nil end
    local def = Utils.ItemDef(item.name) or {}
    local meta = Utils.Meta(item.name)
    return {
        slot = tonumber(item.slot),
        name = item.name,
        label = item.label or def.label or item.name,
        amount = tonumber(item.amount) or 1,
        weight = tonumber(item.weight) or def.weight or 0,
        image = item.image or def.image or 'placeholder.png',
        unique = item.unique or def.unique or false,
        useable = item.useable or def.useable or false,
        description = item.description or def.description or '',
        info = type(item.info) == 'table' and item.info or {},
        type = item.type or def.type or 'item',
        price = item.price,
        category = Utils.Category(item.name, def),
        rarity = Utils.Rarity(item.name, def),
        decay = Config.Decay.enabled and meta.decay or nil,
        equip = meta.equip,
        container = meta.container,
        backpack = meta.backpack,
        noGive = meta.noGive, noDrop = meta.noDrop, noTrade = meta.noTrade,
        ammotype = def.ammotype,
        stack = meta.stack,
    }
end

function DecorateList(items)
    local list = {}
    for k, item in pairs(items or {}) do
        if type(item) == 'table' then
            if not item.slot then item.slot = tonumber(k) end
            local d = Decorate(item)
            if d and d.slot then list[#list + 1] = d end
        end
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end

local function money()
    local m = PlayerData and PlayerData.money or {}
    return { cash = m.cash or 0, bank = m.bank or 0 }
end

local function charName()
    local ci = PlayerData and PlayerData.charinfo
    return ci and (ci.firstname .. ' ' .. ci.lastname) or GetPlayerName(PlayerId())
end

function PlayerView(items)
    items = items or (PlayerData and PlayerData.items) or {}
    local slots, maxweight = Utils.Capacity(items)
    return {
        items = DecorateList(items),
        slots = slots,
        maxweight = maxweight,
        money = money(),
        name = charName(),
        id = GetPlayerServerId(PlayerId()),
    }
end

function OtherView(o)
    if type(o) ~= 'table' then return nil end
    local v = {}
    for k, val in pairs(o) do v[k] = val end
    if o.items then v.items = DecorateList(o.items) end
    if o.trade then
        v.trade = {}
        for k, val in pairs(o.trade) do v.trade[k] = val end
        v.trade.mine = DecorateList(o.trade.mine)
        v.trade.theirs = DecorateList(o.trade.theirs)
    end
    return v
end

function StaticConfig()
    local equip = {}
    for _, e in ipairs(Config.EquipSlots) do
        equip[#equip + 1] = { id = e.id, slot = e.slot, label = e.label, icon = e.icon, accepts = e.accepts or {} }
    end
    return {
        theme = Config.Theme,
        categories = Config.Categories,
        rarities = Config.Rarities,
        equip = equip,
        hotbar = Config.HotbarSlots,
        maxSlots = Config.MaxSlots,
        camera = Config.ShowcaseCamera,
        keys = Config.Keybinds,
    }
end

-- ───────────── open / close ─────────────

local function setOtherSideEffects(o)
    -- close the trunk door when we stop looking at it
    if Client.trunkVehicle and (not o or o.id == nil or not tostring(o.id):find('^trunk%-')) then
        CloseTrunk(Client.trunkVehicle)
        Client.trunkVehicle = nil
    end
end

function OpenUI(data)
    if not data or not data.player then return end
    if PlayerData then PlayerData.items = data.player.items end
    Client.open = true
    Client.alive = GetGameTimer()
    Client.other = data.other
    setOtherSideEffects(data.other)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    local view = PlayerView(data.player.items)
    view.slots, view.maxweight = data.player.slots or view.slots, data.player.maxweight or view.maxweight
    SendNUIMessage({
        action = 'open',
        config = StaticConfig(),
        player = view,
        other = OtherView(data.other),
        trade = PendingTrade,
    })
    Camera.Start()
end

--- @param fromNui boolean the UI asked to close (server needs to know)
function CloseUI(fromNui)
    local wasOpen = Client.open
    Client.open = false
    Client.other = nil
    SetNuiFocus(false, false)
    if not fromNui then SendNUIMessage({ action = 'close' }) end
    Camera.Stop()
    setOtherSideEffects(nil)
    if wasOpen or fromNui then TriggerServerEvent('mezos-inventory:server:close') end
end

RegisterNetEvent('mezos-inventory:client:open', function(data)
    if Client.wheelOpen then CloseWheel() end
    OpenUI(data)
end)

RegisterNetEvent('mezos-inventory:client:other', function(other)
    if not Client.open then return end
    Client.other = other
    setOtherSideEffects(other)
    SendNUIMessage({ action = 'other', other = OtherView(other) })
end)

RegisterNetEvent('mezos-inventory:client:close', function()
    if Client.open then
        Client.open = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
        Camera.Stop()
        setOtherSideEffects(nil)
    end
end)

RegisterNetEvent('mezos-inventory:client:notify', function(msg, typ, len)
    if Client.open then
        SendNUIMessage({ action = 'toast', text = msg, type = typ })
    else
        QBCore.Functions.Notify(msg, typ, len)
    end
end)

-- ───────────── player data sync ─────────────

local function pushPlayer()
    if Client.open then SendNUIMessage({ action = 'player', player = PlayerView() }) end
    RefreshHotbar()
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    LocalPlayer.state:set('inv_busy', false, true)
    PlayerData = QBCore.Functions.GetPlayerData()
    LoadDrops()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    if Client.open then CloseUI(true) end
    LocalPlayer.state:set('inv_busy', true, true)
    PlayerData = nil
end)

RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, val)
    if key == 'all' then
        PlayerData = val
        pushPlayer()
        return
    end
    if not PlayerData then return end
    PlayerData[key] = val
    if key == 'items' or key == 'money' then pushPlayer() end
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)
    PlayerData = val
    pushPlayer()
end)

RegisterNetEvent('QBCore:Client:UpdateObject', function()
    QBCore = exports['qb-core']:GetCoreObject()
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    PlayerData = QBCore.Functions.GetPlayerData()
    if PlayerData and PlayerData.citizenid then LoadDrops() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Client.open then SetNuiFocus(false, false) Camera.Stop() end
end)

-- ───────────── opening ─────────────

function CanOpen()
    if not PlayerData or not PlayerData.citizenid then return false end
    if IsNuiFocused() or IsPauseMenuActive() then return false end
    local m = PlayerData.metadata or {}
    if m.isdead or m.inlaststand or m.ishandcuffed then return false end
    if LocalPlayer.state.inv_busy then return false end
    return true
end

function RequestOpen()
    if Client.open or not CanOpen() then return end
    local ctx = VehicleContext()
    if not ctx then
        local dropId = NearestDropId(Config.DropOpenDistance)
        if dropId then ctx = { kind = 'drop', id = dropId } end
    end
    if ctx and ctx.kind == 'trunk' then
        Client.trunkVehicle = ctx.vehicle
        ctx.vehicle = nil
        -- server refused (in use, too far…): don't leave the trunk hanging open
        SetTimeout(2500, function()
            if not Client.open and Client.trunkVehicle then
                CloseTrunk(Client.trunkVehicle)
                Client.trunkVehicle = nil
            end
        end)
    end
    TriggerServerEvent('mezos-inventory:server:open', ctx or {})
end

RegisterCommand('openInv', RequestOpen, false)
RegisterCommand('inventory', RequestOpen, false)
RegisterKeyMapping('openInv', Lang:t('keys.open'), 'keyboard', Config.Keybinds.Open)

-- ───────────── animations ─────────────

RegisterNetEvent('mezos-inventory:client:dropAnim', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    QBCore.Functions.RequestAnimDict('pickup_object')
    TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 1000, 48, 0, false, false, false)
end)

RegisterNetEvent('qb-inventory:client:giveAnim', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    QBCore.Functions.RequestAnimDict('mp_common')
    TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 8.0, 1.0, -1, 16, 0, false, false, false)
end)

-- ───────────── watchdog ─────────────
-- If the UI ever dies while focused, give control back instead of trapping the player.

CreateThread(function()
    while true do
        Wait(1000)
        if Client.open then
            if GetGameTimer() - Client.alive > 8000 then
                print('^3[mezos-inventory] UI stopped responding, releasing focus^7')
                CloseUI(true)
            elseif not IsNuiFocused() then
                SetNuiFocus(true, true)
            end
            local m = PlayerData and PlayerData.metadata or {}
            if m.isdead or m.inlaststand or m.ishandcuffed then CloseUI(true) end
        elseif Client.wheelOpen and GetGameTimer() - Client.alive > 8000 then
            CloseWheel()
        end
    end
end)
