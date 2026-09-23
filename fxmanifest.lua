fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-medical'
author 'DelPerroSands'
version '0.1.0'
description 'Patient records and illness for DPS. Reads wasabi_ambulance; never modifies it.'

-- Scope note, because it is the whole design:
--   TRAUMA belongs to wasabi_ambulance_v2. It models 6 limbs x 7 injury types and
--   applies every consequence itself (bleed, stun, knockout). We subscribe to the
--   events it already broadcasts from its own bridge/listeners and we apply NO
--   effects of our own to trauma - so nothing here can ever disagree with what the
--   player is actually feeling.
--   ILLNESS is ours. Nothing on the server modelled it before this resource.

shared_script '@ox_lib/init.lua'

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

-- The chart UI. Deliberately NOT declared as ui_page: it is served to
-- lb-tablet's app frame at https://cfx-nui-dps-medical/ui/index.html, so this
-- resource never takes NUI focus of its own.
files {
    'ui/index.html',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
}
