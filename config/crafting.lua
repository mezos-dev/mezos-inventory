-- Crafting benches. Players walk up, press E (or use qb-target) and get the crafting tab in the inventory.
--
-- bench = {
--   label, coords = vector4(x, y, z, heading), prop = model or nil (nil = no prop spawned),
--   job = { police = 0 } / gang = { ballas = 0 } (minimum grade) or nil for everyone,
--   recipes = { recipe ids from Config.Recipes }, repair = true (can repair items with quality)
-- }
--
-- recipe = {
--   item, amount, time (seconds), ingredients = { name = amount }, tools = { name = true } (not consumed),
--   info = { … } extra metadata for the result, label = custom title
-- }

Config.Recipes = {
    lockpick        = { item = 'lockpick', amount = 2, time = 5, ingredients = { metalscrap = 6, plastic = 4 } },
    advancedlockpick= { item = 'advancedlockpick', amount = 1, time = 8, ingredients = { lockpick = 2, steel = 4, aluminum = 2 }, tools = { screwdriverset = true } },
    screwdriverset  = { item = 'screwdriverset', amount = 1, time = 6, ingredients = { metalscrap = 10, plastic = 8 } },
    electronickit   = { item = 'electronickit', amount = 1, time = 10, ingredients = { metalscrap = 8, plastic = 10, copper = 6 } },
    repairkit       = { item = 'repairkit', amount = 1, time = 8, ingredients = { metalscrap = 12, steel = 4, rubber = 4 } },
    bandage         = { item = 'bandage', amount = 3, time = 4, ingredients = { plastic = 2, rubber = 1 } },
    mz_repairkit    = { item = 'mz_repairkit', amount = 1, time = 10, ingredients = { steel = 6, aluminum = 4, rubber = 4 }, tools = { screwdriverset = true } },
    backpack_small  = { item = 'backpack_small', amount = 1, time = 12, ingredients = { rubber = 10, plastic = 12 } },
    backpack_large  = { item = 'backpack_large', amount = 1, time = 20, ingredients = { backpack_small = 1, rubber = 14, steel = 4 } },
    wallet          = { item = 'wallet', amount = 1, time = 5, ingredients = { rubber = 3, plastic = 2 } },
    duffelbag       = { item = 'duffelbag', amount = 1, time = 12, ingredients = { rubber = 12, plastic = 8 } },
    pistol_ammo     = { item = 'pistol_ammo', amount = 1, time = 6, ingredients = { metalscrap = 6, copper = 4, iron = 2 } },
}

Config.Benches = {
    {
        label = 'Public Workbench',
        coords = vector4(2747.94, 3472.71, 55.67, 245.0), -- YouTool, Senora Fwy
        prop = `prop_tool_bench02`,
        recipes = { 'lockpick', 'screwdriverset', 'electronickit', 'repairkit', 'bandage', 'backpack_small', 'wallet', 'duffelbag', 'mz_repairkit' },
        repair = true,
    },
    {
        label = 'Advanced Workbench',
        coords = vector4(1173.83, -1323.73, 34.90, 175.0),
        prop = `gr_prop_gr_bench_04b`,
        recipes = { 'advancedlockpick', 'backpack_large', 'pistol_ammo', 'mz_repairkit' },
        repair = true,
    },
}

-- Repairing an item with quality (weapons, tools…) at a bench with repair = true.
-- Per-item cost can be overridden in Config.ItemMeta[x].repair.
Config.Repair = {
    items = { mz_repairkit = 1 },        -- default cost
    time = 6,                            -- seconds
    restore = 100,                       -- quality after repair
}

Config.BenchDistance = 2.5
