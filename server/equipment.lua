-- Equipment (backpack, armor, phone, radio, weapons) and container items (wallet, duffel bag…).

--- Put the item in `slot` into its equipment slot (swapping whatever is there).
function EquipFromSlot(src, slot)
    local box = PlayerBox(src)
    slot = tonumber(slot)
    local item = box and slot and box.items[slot]
    if not item then return false, 'missing' end
    if Utils.IsEquipSlot(slot) then
        -- already equipped → unequip to first free pocket slot
        local free = FirstFree(box)
        if not free then return false, 'slots' end
        return MoveItem(src, box, slot, box, free, nil, item.name)
    end
    for _, e in ipairs(Config.EquipSlots) do
        if Utils.CanEquip(e, item.name) and not box.items[e.slot] then
            return MoveItem(src, box, slot, box, e.slot, nil, item.name)
        end
    end
    for _, e in ipairs(Config.EquipSlots) do
        if Utils.CanEquip(e, item.name) then
            return MoveItem(src, box, slot, box, e.slot, nil, item.name)
        end
    end
    return false, 'equip'
end

QBCore.Functions.CreateCallback('mezos-inventory:server:equip', function(src, cb, req)
    if type(req) ~= 'table' or not RateOk(src, 'move') then return cb({ ok = false, err = 'rate' }) end
    local ok, err = EquipFromSlot(src, req.slot)
    cb({ ok = ok, err = err, other = OtherPayload(src) })
end)

-- ───────────── containers ─────────────

local function newContainerId()
    return ('%s%04d'):format(QBCore.Shared.RandomStr(4):upper(), math.random(0, 9999)) .. tostring(os.time() % 100000)
end

function OpenContainer(src, slot)
    local box = PlayerBox(src)
    slot = tonumber(slot)
    local item = box and slot and box.items[slot]
    if not item then return false end
    local meta = Utils.Meta(item.name).container
    if not meta then return false end
    if not item.info.containerId then
        item.info.containerId = newContainerId()
        CommitBox(box)
    end
    local cid = item.info.containerId
    local id = 'container-' .. cid
    ResolveInventory(id, { label = item.label, slots = meta.slots, maxweight = meta.weight })
    local other = { kind = 'stash', id = id, label = item.label, container = cid, sub = 'container' }
    if MZ.Open[src] then return SwitchOther(src, other) end
    return OpenSession(src, other)
end

CreateThread(function()
    Wait(1000)
    for name, meta in pairs(Config.ItemMeta) do
        if Utils.ItemDef(name) then
            if meta.container then
                QBCore.Functions.CreateUseableItem(name, function(source, item)
                    OpenContainer(source, item and item.slot)
                end)
            elseif meta.backpack then
                QBCore.Functions.CreateUseableItem(name, function(source, item)
                    local ok, err = EquipFromSlot(source, item and item.slot)
                    if not ok and err == 'backpack' then Notify(source, Lang:t('notify.backpackFull'), 'error') end
                end)
            end
        end
    end
end)
