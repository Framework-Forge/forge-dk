ForgeDK = ForgeDK or {}
-- Presentation presets supplied for the two document formats. Attachment is always relative to the right hand.
ForgeDK.Presentations = {
    police = {
        card = { dict = 'paper_1_rcm_alt1-9', anim = 'player_one_dual-9', flags = 49,
            model = 'prop_franklin_dl', bone = 57005, pos = {0.1493, 0.0700, -0.0125}, rot = {80.900, -20.970, 112.350}, rotationOrder = 2 },
        a4 = { dict = 'paper_1_rcm_alt1-9', anim = 'player_one_dual-9', flags = 1,
            model = 'h4_prop_h4_files_paper_01b', bone = 57005, pos = {0.0104, 0.0111, -0.1080}, rot = {20.850, 147.840, -43.250}, rotationOrder = 2 },
    },
    citizen = {
        card = { dict = 'mp_common', anim = 'givetake1_a', flags = 1,
            model = 'prop_franklin_dl', bone = 57005, pos = {0.1840, 0.0401, -0.0052}, rot = {18.930, 10.010, -178.700}, rotationOrder = 2 },
        a4 = { dict = 'mp_common', anim = 'givetake1_a', flags = 1,
            model = 'h4_prop_h4_files_paper_01b', bone = 57005, pos = {0.2685, 0.0336, -0.0763}, rot = {-11.080, 99.010, 94.840}, rotationOrder = 2 },
    },
}
-- Bootstrap only: administration saves data/config.json through the Forge DK NUI.
ForgeDK.Config = {
    adminAce = 'forge-core.admin', integrationAce = 'forge-dk.integration',
    trustedResources = { ['forge-police'] = true, ['forge-core'] = true, ['qbx_core'] = true }, maxPhotoBytes = 98304,
    default = {
        schemaVersion = 1, revision = 1,
        general = { cityName = 'Forge', logo = '', locale = 'pt-br', range = 3.0, popupMs = 10000, closeKey = 'BACK',
            labels = { id = 'IRG', firstName = 'Nome', lastName = 'Sobrenome', dob = 'Nascimento',
                sex = 'Sexo', issuedAt = 'Expedição', expiresAt = 'Validade' } },
        types = {
            id_card = {
                key = 'id_card', item = 'id_card', label = 'Identidade', format = 'card', active = true,
                requiresAuthorization = false, permissionSource = 'documents', permissionKey = 'id_card', category = '',
                firstFee = 0, reissueFee = 100, forgeryFee = 500, allowForgery = false,
                requirePhoto = true, validityDays = 0, subject = 'person', animation = true,
                prop = 'prop_franklin_dl', body = '', fields = {},
                appearance = { background = '#172a40', secondary = '#29455f', text = '#f5f7fb', accent = '#e59a32',
                    pattern = true, stamp = true, profileStamp = true, signature = true },
            },
            weapon_license = {
                key = 'weapon_license', item = 'weaponlicense', label = 'Porte de arma', format = 'card', active = true,
                requiresAuthorization = true, permissionSource = 'licences', permissionKey = 'weapon', category = '',
                firstFee = 100, reissueFee = 200, forgeryFee = 1000, allowForgery = false,
                requirePhoto = true, validityDays = 0, subject = 'person', animation = true,
                prop = 'prop_franklin_dl', body = '', fields = {},
                appearance = { background = '#40201b', secondary = '#6b3830', text = '#fff6ef', accent = '#e59a32',
                    pattern = true, stamp = true, profileStamp = false, signature = true },
            },
        }, npcs = {},
    },
}
