Config = Config or {}

-- ───────────────────────────── General ─────────────────────────────
Config.Debug = false
Config.UseTarget = GetConvar('UseTarget', 'false') == 'true'

-- Player inventory size (a backpack adds on top of this)
Config.MaxWeight = 120000                -- grams
Config.MaxSlots = 40

-- Defaults for stashes created without explicit size
Config.StashSize = { maxweight = 2000000, slots = 100 }

-- Ground drops
Config.DropSize = { maxweight = 1000000, slots = 50 }
Config.DropLifetime = 15                 -- minutes before an unattended drop despawns
Config.DropModel = `bkr_prop_duffel_bag_01a`
Config.DropRenderDistance = 50.0         -- clients only spawn props within this range
Config.DropOpenDistance = 2.5            -- TAB near a drop opens it

-- Keys (players can rebind in GTA settings → Key Bindings → FiveM)
Config.Keybinds = {
    Open = 'TAB',
    Hotbar = 'Z',
    Wheel = 'F2',                        -- quick-wheel (hotbar + equipped + favourites)
}
Config.HotbarSlots = 5                   -- keys 1..5 use slots 1..5
Config.DisableWeaponWheel = true         -- block GTA weapon wheel / number weapon select

-- ───────────────────────────── Security ─────────────────────────────
Config.MovesPerSecond = 15               -- excess move requests are ignored
Config.MaxOpenDistance = 6.0             -- metres you can walk from a stash/trunk before it auto-closes
Config.ExportOpenRadius = 15.0           -- same, for inventories opened by other resources (apartments, houses…)
Config.OtherPlayerDistance = 5.0         -- search / rob range
Config.GiveDistance = 3.0
Config.TradeDistance = 4.0
Config.AdminPermission = { 'admin', 'god' } -- admins can search players from any distance

-- ───────────────────────────── Saving ─────────────────────────────
Config.SaveInterval = 5                  -- minutes between flushes of changed stashes

-- ───────────────────────────── Equipment ─────────────────────────────
-- Equipped items live in reserved slots of PlayerData.items, so HasItem & co still see them.
-- 'accepts' is a list of item names or item types; Config.ItemMeta[x].equip also works.
Config.EquipSlots = {
    { id = 'backpack', slot = 101, label = 'Backpack',  icon = 'backpack' },
    { id = 'armor',    slot = 102, label = 'Armor',     icon = 'shield',  accepts = { 'armor', 'heavyarmor' } },
    { id = 'phone',    slot = 103, label = 'Phone',     icon = 'phone',   accepts = { 'phone', 'iphone', 'samsungphone' } },
    { id = 'radio',    slot = 104, label = 'Radio',     icon = 'radio',   accepts = { 'radio' } },
    { id = 'primary',  slot = 105, label = 'Primary',   icon = 'rifle',   accepts = { 'weapon' } },
    { id = 'secondary',slot = 106, label = 'Secondary', icon = 'pistol',  accepts = { 'weapon' } },
}

-- ───────────────────────────── Durability ─────────────────────────────
Config.Decay = {
    enabled = true,
    removeWhenSpoiled = false,           -- true = items at 0% vanish, false = they stay but can't be used
}

-- ───────────────────────────── Vending ─────────────────────────────
Config.VendingObjects = {
    'prop_vend_soda_01',
    'prop_vend_soda_02',
    'prop_vend_water_01',
    'prop_vend_coffe_01',
}
Config.VendingItems = {
    { name = 'kurkakola',    price = 4, amount = 50 },
    { name = 'water_bottle', price = 4, amount = 50 },
}

-- Shops: which accounts can pay (first one is the default in the UI)
Config.ShopPayments = { 'cash', 'bank' }
Config.ShopDistance = 10.0

-- ───────────────────────────── UI ─────────────────────────────
Config.Theme = {
    accent = '#22e4ff',
    accent2 = '#a855ff',
    danger = '#ff3d71',
    success = '#2bffb1',
    serverName = 'MEZOS',
    sounds = true,
}
Config.ShowcaseCamera = true             -- frame your character between the panels while open
Config.Blur = true                       -- soft background blur while open

-- Item categories shown as filter chips. Items get one by Config.ItemMeta[x].category,
-- otherwise by the rules in shared/utils.lua (weapons, ammo, food, drinks, drugs…).
Config.Categories = {
    { id = 'weapon',  label = 'Weapons' },
    { id = 'ammo',    label = 'Ammo' },
    { id = 'food',    label = 'Food' },
    { id = 'drink',   label = 'Drinks' },
    { id = 'medical', label = 'Medical' },
    { id = 'tool',    label = 'Tools' },
    { id = 'drug',    label = 'Drugs' },
    { id = 'valuable',label = 'Valuables' },
    { id = 'misc',    label = 'Misc' },
}

-- Rarity tiers drive the slot glow colour
Config.Rarities = {
    common    = '#8fa3b8',
    uncommon  = '#2bffb1',
    rare      = '#22a8ff',
    epic      = '#a855ff',
    legendary = '#ffb02e',
}
