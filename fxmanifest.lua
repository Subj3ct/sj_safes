fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sj_safes'
description 'Placeable Safe System'
author 'Subj3ct'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'web/dist/index.html'

files {
    'web/dist/**/*'
}

dependencies {
    'ox_lib',
    'ox_inventory'
} 