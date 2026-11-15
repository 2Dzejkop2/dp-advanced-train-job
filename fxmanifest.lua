fx_version 'cerulean'
game 'gta5'

name 'DP - Advanced Train Job'
author 'Dzejkop'
description 'DP - Advanced Train Job | Framework-agnostic Metro/Train Job for QB, ESX, Qbox'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/**/*.lua',
    'config/*.lua'
}

client_scripts {
    'bridges/client/init.lua',
    'bridges/client/qb.lua',
    'bridges/client/qbox.lua',
    'bridges/client/esx.lua',
    'client/ui_provider.lua',
    'client/core.lua',
    'client/route.lua',
    'client/nui.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridges/server/init.lua',
    'bridges/server/qb.lua',
    'bridges/server/qbox.lua',
    'bridges/server/esx.lua',
    'server/storage.lua',
    'server/service.lua',
    'server/main.lua'
}

ui_page 'UI/index.html'

files {
    'data/trains.xml',
    'config/config-interactions.lua',
    'config/config-core.lua',
    'config/config-gameplay.lua',
    'config/config-metro.lua',
    'config/config-progression.lua',
    'config/config-economy.lua',
    'config/config-quests.lua',
    'config/config-train.lua',
    'config/config-webhook.lua',
    'UI/index.html',
    'UI/style.css',
    'UI/app.js',
    'UI/assets/*',
    'UI/fonts/*'
}

data_file 'TRAINCONFIGS_FILE' 'data/trains.xml'

dependencies {
    'ox_lib'
}
