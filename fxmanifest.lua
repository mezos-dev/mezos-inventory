fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mezos-inventory'
author 'Mezos'
description 'Next-gen inventory for QBCore: holo-glass UI, equipment & backpacks, containers, durability, crafting, secure trading, weapon attachments, shops and drops'
version '1.0.0'

-- Drop-in replacement: every resource that talks to qb-inventory keeps working
provide 'qb-inventory'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'locales/en.lua',
    'config/config.lua',
    'config/items.lua',
    'config/vehicles.lua',
    'config/crafting.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/main.lua',
    'client/nui.lua',
    'client/camera.lua',
    'client/hotbar.lua',
    'client/drops.lua',
    'client/vehicles.lua',
    'client/crafting.lua',
    'client/trade.lua',
    'client/compat.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/hooks.lua',
    'server/core.lua',
    'server/decay.lua',
    'server/equipment.lua',
    'server/sessions.lua',
    'server/moves.lua',
    'server/use.lua',
    'server/drops.lua',
    'server/shops.lua',
    'server/crafting.lua',
    'server/trade.lua',
    'server/compat.lua',
    'server/commands.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/js/views/*.js',
    'html/fonts/*',
    'html/images/*',
}

dependencies {
    'qb-core',
    'oxmysql',
}
