fx_version 'cerulean'

game "gta5"

name 'Forge DK'
author 'Forge — original assets by Byte Labs'
version '2.0.2'
description 'Forge DK — documents and citizen services'

lua54 'yes'

dependencies { 'pr_bridge', 'ox_inventory' }
ui_page 'web/build/index.html'
-- ui_page 'http://localhost:3000/' --for dev

shared_scripts { '@pr_bridge/init.lua', 'shared/config.lua', 'shared/schema.lua' }

server_script {
    'server/store.lua',
    'server/service.lua',
    'server/init.lua'
}

client_script {
    'client/world.lua',
    'client/init.lua',
}

files {
    'images/**',
    'locales/*.json',
    'web/build/**',
    'client/**',
    'shared/**'
}

server_script 'server/version.lua'
