fx_version 'cerulean'
game 'rdr3'
lua54 'yes'

author 'OpenAI'
description 'VORP crafting with skill tree, blueprints and cinematic NUI'
version '1.1.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

dependencies {
    'vorp_core',
    'vorp_inventoryApi'
}
