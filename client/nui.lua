-- NUI callbacks. The UI is optimistic; every call returns the authoritative state from the server.

local allowed = {
    move = true, quickMove = true, drop = true, give = true, use = true, equip = true,
    purchase = true, craftStart = true, craftFinish = true, craftCancel = true,
    repairStart = true, repairFinish = true,
    tradeRequest = true, tradeOffer = true, tradeLock = true, tradeConfirm = true,
    snapshot = true, sort = true,
}

local function decorateResponse(res)
    if type(res) ~= 'table' then return { ok = false } end
    local out = {}
    for k, v in pairs(res) do out[k] = v end
    if res.player then
        if PlayerData then PlayerData.items = res.player.items end
        out.player = PlayerView(res.player.items)
    end
    if res.other ~= nil then
        Client.other = res.other
        out.other = OtherView(res.other)
    end
    return out
end

RegisterNUICallback('server', function(data, cb)
    if type(data) ~= 'table' or not allowed[data.name] then return cb({ ok = false }) end
    local arg = type(data.args) == 'table' and data.args[1] or nil
    QBCore.Functions.TriggerCallback('mezos-inventory:server:' .. data.name, function(res)
        local out = decorateResponse(res)
        cb(out)
        if data.name == 'use' and out.ok and out.close and Client.open then CloseUI(false) end
        if data.name == 'use' and out.ok == false and out.err == 'spoiled' then
            SendNUIMessage({ action = 'toast', text = Lang:t('notify.spoiled'), type = 'error' })
        end
    end, arg)
end)

RegisterNUICallback('close', function(_, cb)
    cb({})
    if Client.open then CloseUI(true) end
end)

RegisterNUICallback('alive', function(_, cb)
    Client.alive = GetGameTimer()
    cb({})
end)

RegisterNUICallback('sound', function(data, cb)
    if data and data.name == 'fail' then
        PlaySoundFrontend(-1, 'Place_Prop_Fail', 'DLC_Dmod_Prop_Editor_Sounds', false)
    end
    cb({})
end)

-- Players near me (give / trade pickers)
RegisterNUICallback('nearby', function(data, cb)
    local range = (data and data.range == 'trade') and Config.TradeDistance or Config.GiveDistance
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local list = {}
    for _, p in ipairs(GetActivePlayers()) do
        if p ~= PlayerId() then
            local ped = GetPlayerPed(p)
            local d = #(GetEntityCoords(ped) - pos)
            if d <= range and IsEntityVisible(ped) then
                list[#list + 1] = { id = GetPlayerServerId(p), name = GetPlayerName(p), dist = math.floor(d * 10) / 10 }
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    cb(list)
end)

RegisterNUICallback('camera', function(data, cb)
    if type(data) == 'table' then
        if data.rotate then Camera.Rotate(tonumber(data.rotate) or 0) end
        if data.enabled ~= nil then Camera.SetAllowed(data.enabled == true) end
    end
    cb({})
end)

RegisterNUICallback('tradeRespond', function(data, cb)
    if type(data) == 'table' and data.id then
        TriggerServerEvent('mezos-inventory:server:tradeRespond', data.id, data.accept == true)
        PendingTrade = nil
    end
    cb({})
end)

RegisterNUICallback('tradeCancel', function(_, cb)
    TriggerServerEvent('mezos-inventory:server:tradeCancel')
    cb({})
end)

-- ───────────── weapon attachments (qb-weapons) ─────────────

local function attachmentsConfig()
    if GetResourceState('qb-weapons') ~= 'started' then return nil end
    local ok, cfg = pcall(function() return exports['qb-weapons']:getConfigWeaponAttachments() end)
    return ok and cfg or nil
end

local function formatAttachments(item)
    local out = {}
    local cfg = attachmentsConfig()
    if not cfg or not item or not item.info or type(item.info.attachments) ~= 'table' then return out end
    for attachmentType, weapons in pairs(cfg) do
        local component = weapons[item.name]
        if component then
            for _, a in pairs(item.info.attachments) do
                local c = a.component
                if c == component or (type(c) == 'string' and joaat(c) == component) or (type(component) == 'string' and type(c) == 'string' and c == component) then
                    local def = Utils.ItemDef(attachmentType)
                    out[#out + 1] = { attachment = attachmentType, label = def and def.label or attachmentType, image = def and def.image or 'placeholder.png' }
                end
            end
        end
    end
    return out
end

RegisterNUICallback('attachments', function(data, cb)
    local item = PlayerData and PlayerData.items and PlayerData.items[tonumber(data and data.slot) or -1]
    if not item or item.type ~= 'weapon' then return cb({ ok = false }) end
    cb({ ok = true, list = formatAttachments(item), available = attachmentsConfig() ~= nil })
end)

RegisterNUICallback('removeAttachment', function(data, cb)
    local slot = tonumber(data and data.slot)
    local item = PlayerData and PlayerData.items and slot and PlayerData.items[slot]
    local cfg = attachmentsConfig()
    if not item or not cfg or type(data.attachment) ~= 'string' or not cfg[data.attachment] then return cb({ ok = false }) end
    local component = cfg[data.attachment][item.name]
    QBCore.Functions.TriggerCallback('qb-weapons:server:RemoveAttachment', function(result)
        if component then RemoveWeaponComponentFromPed(PlayerPedId(), joaat(item.name), type(component) == 'string' and joaat(component) or component) end
        if result == false then return cb({ ok = false }) end
        local updated = PlayerData.items[slot]
        if updated then updated.info.attachments = result end
        cb({ ok = true, list = formatAttachments(updated or item) })
    end, { attachment = data.attachment }, item)
end)

-- ───────────── quick wheel ─────────────

RegisterNUICallback('wheelUse', function(data, cb)
    cb({})
    CloseWheel()
    local slot = tonumber(data and data.slot)
    if slot then TriggerServerEvent('mezos-inventory:server:useSlot', slot) end
end)

RegisterNUICallback('wheelClose', function(_, cb)
    cb({})
    CloseWheel()
end)
