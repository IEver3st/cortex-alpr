fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cortex-alpr'
description 'Cortex ALPR - in-car traffic radar and plate reader'
author 'GSDMODS/CORTEX'
version '1.0.0'

dependency 'cortex-lib'

shared_scripts {
    '@cortex-lib/init.lua',
    'config.lua',
    'shared/locale.lua',
    'shared/validate.lua',
    'shared/geometry.lua',
    'shared/jobs.lua',
}

client_scripts {
    '@cortex-lib/presentation-client.lua',
    'bridge/client.lua',
    'client/install.lua',
    'client/nui.lua',
    'client/layout.lua',
    'client/radar.lua',
    'client/air.lua',
    'client/hotlist.lua',
    'client/main.lua',
}

server_scripts {
    'bridge/server.lua',
    'server/records.lua',
    'server/hotlist.lua',
    'server/main.lua',
}


ui_page 'web/dist/index.html'

files {
    'locales/*.json',
    'web/dist/index.html',
    'web/dist/assets/*',
}

escrow_ignore {
    'fxmanifest.lua',
    'config.lua',
    'bridge/*.lua',
    'locales/*.json',
}
