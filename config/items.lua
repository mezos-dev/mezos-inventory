-- Extra item behaviour, layered on top of QBCore.Shared.Items (qb-core/shared/items.lua stays the source of truth).
--
--   category  = filter chip id (see Config.Categories); auto-detected when omitted
--   rarity    = common | uncommon | rare | epic | legendary (slot glow)
--   decay     = hours until the item reaches 0% quality (food rots, drugs go stale…)
--   stack     = max amount per slot (default: unlimited for non-unique items)
--   equip     = equipment slot id this item may go into (see Config.EquipSlots)
--   backpack  = { slots = n, weight = g }  bonus capacity while equipped in the backpack slot
--   container = { slots = n, weight = g }  item that holds its own inventory (wallet, duffel bag…)
--   repair    = { items = { name = amount } } what a repair at a bench costs (quality items only)
--   noGive / noDrop / noTrade = true      block those actions for this item

Config.ItemMeta = {
    -- Backpacks & containers (added by mezos-inventory, see README)
    backpack_small = { category = 'misc', rarity = 'uncommon', equip = 'backpack', backpack = { slots = 10, weight = 25000 } },
    backpack_large = { category = 'misc', rarity = 'rare', equip = 'backpack', backpack = { slots = 20, weight = 50000 } },
    wallet         = { category = 'valuable', rarity = 'common', container = { slots = 6, weight = 2000 } },
    duffelbag      = { category = 'misc', rarity = 'uncommon', container = { slots = 20, weight = 40000 } },
    mz_repairkit   = { category = 'tool', rarity = 'rare' },

    -- Food & drink rot over time
    tosti          = { category = 'food', decay = 72 },
    sandwich       = { category = 'food', decay = 72 },
    twerks_candy   = { category = 'food', decay = 336 },
    snikkel_candy  = { category = 'food', decay = 336 },
    water_bottle   = { category = 'drink', decay = 720 },
    coffee         = { category = 'drink', decay = 48 },
    kurkakola      = { category = 'drink', decay = 720 },
    beer           = { category = 'drink', decay = 336 },
    grapejuice     = { category = 'drink', decay = 168 },
    grape          = { category = 'food', decay = 96 },
    whiskey        = { category = 'drink' },
    vodka          = { category = 'drink' },
    wine           = { category = 'drink' },

    -- Medical
    firstaid       = { category = 'medical', rarity = 'uncommon' },
    bandage        = { category = 'medical' },
    ifaks          = { category = 'medical', rarity = 'uncommon' },
    painkillers    = { category = 'medical' },
    armor          = { category = 'medical', equip = 'armor' },
    heavyarmor     = { category = 'medical', rarity = 'rare', equip = 'armor' },

    -- Drugs go stale
    joint          = { category = 'drug', decay = 240 },
    oxy            = { category = 'drug' },
    meth           = { category = 'drug' },
    cokebaggy      = { category = 'drug' },
    crack_baggy    = { category = 'drug' },
    xtcbaggy       = { category = 'drug' },
    coke_brick     = { category = 'drug', rarity = 'epic' },
    weed_brick     = { category = 'drug', rarity = 'rare' },

    -- Valuables
    rolex          = { category = 'valuable', rarity = 'rare' },
    diamond_ring   = { category = 'valuable', rarity = 'epic' },
    diamond        = { category = 'valuable', rarity = 'epic' },
    goldchain      = { category = 'valuable', rarity = 'uncommon' },
    tenkgoldchain  = { category = 'valuable', rarity = 'rare' },
    goldbar        = { category = 'valuable', rarity = 'legendary' },
    markedbills    = { category = 'valuable', rarity = 'uncommon' },
    casinochips    = { category = 'valuable' },

    -- Tools
    lockpick          = { category = 'tool' },
    advancedlockpick  = { category = 'tool', rarity = 'uncommon' },
    electronickit     = { category = 'tool', rarity = 'uncommon' },
    thermite          = { category = 'tool', rarity = 'rare' },
    trojan_usb        = { category = 'tool', rarity = 'rare' },
    drill             = { category = 'tool', rarity = 'uncommon' },
    gatecrack         = { category = 'tool', rarity = 'rare' },
    repairkit         = { category = 'tool' },
    advancedrepairkit = { category = 'tool', rarity = 'uncommon' },
    phone             = { category = 'tool', equip = 'phone' },
    iphone            = { category = 'tool', equip = 'phone' },
    samsungphone      = { category = 'tool', equip = 'phone' },
    radio             = { category = 'tool', equip = 'radio' },

    -- Never leave the owner
    id_card        = { category = 'misc', noTrade = true },
    driver_license = { category = 'misc', noTrade = true },
}

-- Rarity for every weapon by default; specific weapons can still be overridden above.
Config.WeaponRarity = 'uncommon'
