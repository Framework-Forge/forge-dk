local DK = ForgeDK
local S = {}
DK.Schema = S
function S.clone(v)
    if type(v) ~= 'table' then return v end
    local result = {}
    for k, item in pairs(v) do result[k] = S.clone(item) end
    return result
end
function S.text(v, limit)
    return type(v) == 'string' and v:gsub('%z', ''):sub(1, limit or 160) or ''
end
function S.key(v)
    return type(v) == 'string' and #v > 0 and #v <= 64 and v:match('^[%w_%-]+$') ~= nil
end
function S.number(v, minimum, maximum, fallback)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return fallback end
    return math.max(minimum, math.min(maximum, v))
end
function S.colour(v, fallback)
    return type(v) == 'string' and v:match('^#%x%x%x%x%x%x$') and v or fallback
end
function S.asset(v)
    v = S.text(v, 512)
    return (v == '' or v:match('^https://[%w%.%-]+/')) and v or ''
end
function S.pngAsset(v)
    if type(v) ~= 'string' then return '' end
    if #v <= 98304 and v:match('^data:image/png;base64,iVBORw0KGgo[%w+/=]+$') then return v end
    if #v <= 512 and v:match('^images/[%w_/%-%.]+%.png$') and not v:find('..', 1, true) then return v end
    return S.asset(v)
end
function S.date(v)
    if type(v) ~= 'string' then return nil end
    local y, m, d = v:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not y then d, m, y = v:match('^(%d%d)/(%d%d)/(%d%d%d%d)$') end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or y < 1 or y > 9999 or m < 1 or m > 12 or d < 1 then return nil end
    local days = {31, (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 29 or 28, 31,30,31,30,31,31,30,31,30,31}
    if d > days[m] then return nil end
    return ('%04d-%02d-%02d'):format(y,m,d)
end
function S.visualAppearance(appearance, forged)
    local result = S.clone(appearance)
    local alternate = appearance.forged
    if forged and type(alternate) == 'table' and alternate.enabled == true then
        for _, key in ipairs({'background','secondary','text','accent','fontFamily','patternStyle','patternOpacity'}) do
            if alternate[key] ~= nil then result[key] = alternate[key] end
        end
        if alternate.emblemImage and alternate.emblemImage ~= '' then result.emblemImage = alternate.emblemImage end
    end
    result.stampImage = forged and (appearance.forgedStampImage or '') or (appearance.stampImage or '')
    result.stampText = forged and (appearance.forgedStampText or '') or (appearance.stampText or '')
    result.stampStyle = forged and 'single' or 'double'
    result.forgedStampImage, result.forgedStampText = nil, nil
    result.forged = nil
    return result
end
function S.font(v)
    return ({sans=true,serif=true,mono=true})[v] and v or 'sans'
end
function S.pattern(v)
    return ({diagonal=true,grid=true,waves=true,dots=true,guilloche=true})[v] and v or 'diagonal'
end
function S.layout(value)
    local result, fixed = { card = {}, a4 = {} }, {}
    for _, key in ipairs({'logo','cityName','title','divider','photo','id','firstName','lastName','dob','sex',
        'issuedAt','expiresAt','category','body','signature','serial','profileStamp','stamp','stampText'}) do fixed[key] = true end
    for _, format in ipairs({'card','a4'}) do
        for key, raw in pairs(type(value) == 'table' and type(value[format]) == 'table' and value[format] or {}) do
            local field = type(key) == 'string' and key:match('^field:(.+)$')
            if (fixed[key] or field and S.key(field)) and type(raw) == 'table' then
                local x = S.number(raw.x, 0, 98, 0)
                result[format][key] = { x = x, y = S.number(raw.y, 0, 98, 0),
                    width = S.number(raw.width, 1, 100 - x, 20), fontSize = S.number(raw.fontSize, 0.5, 8, 2),
                    hidden = raw.hidden == true, align = (raw.align == 'center' or raw.align == 'right') and raw.align or 'left' }
            end
        end
    end
    return result
end
function S.presentation(snapshot)
    local style = snapshot.presentationStyle == 'citizen' and 'citizen' or 'police'
    local format = snapshot.format == 'a4' and 'a4' or 'card'
    local result = S.clone(DK.Presentations[style][format])
    if S.key(snapshot.prop) and not (format == 'a4' and snapshot.prop == 'prop_franklin_dl') then result.model = snapshot.prop end
    return result
end
function S.document(v)
    if type(v) ~= 'table' or not S.key(v.key) or not S.key(v.item) then return nil, 'invalid_type' end
    local fields, used = {}, {}
    for i, f in ipairs(type(v.fields) == 'table' and v.fields or {}) do
        if type(f) ~= 'table' or i > 32 or not S.key(f.key) or used[f.key] then return nil, 'invalid_fields' end
        used[f.key] = true
        if f.source ~= 'input' and f.source ~= 'identity' then return nil, 'invalid_field_source' end
        if f.source == 'identity' and not ({ id = true, firstName = true, lastName = true, dob = true, sex = true })[f.key] then
            return nil, 'invalid_field_source'
        end
        local inputType = f.type or 'text'
        if inputType ~= 'text' and inputType ~= 'number' and inputType ~= 'date' and inputType ~= 'textarea' then return nil, 'invalid_field_type' end
        fields[#fields + 1] = { key = f.key, label = S.text(f.label, 80), source = f.source, type = inputType,
            required = f.required == true, forgeable = f.forgeable == true, default = S.text(f.default, 2000) }
    end
    local a, labels, forgeable = type(v.appearance) == 'table' and v.appearance or {}, {}, {}
    for _, k in ipairs({ 'id', 'firstName', 'lastName', 'dob', 'sex' }) do
        forgeable[k] = type(v.forgeableIdentity) == 'table' and v.forgeableIdentity[k] == true
    end
    for k in pairs(DK.Config.default.general.labels) do
        if type(v.labels) == 'table' and v.labels[k] ~= nil then labels[k] = S.text(v.labels[k], 80) end
    end
    local subject = v.subject or 'person'
    if subject ~= 'person' and subject ~= 'vehicle' and subject ~= 'business' then return nil, 'invalid_subject' end
    local alternate = type(a.forged) == 'table' and a.forged or {}
    return { key = v.key, item = v.item, label = S.text(v.label, 80), format = v.format == 'a4' and 'a4' or 'card',
        active = v.active ~= false, requiresAuthorization = v.requiresAuthorization == true,
        permissionSource = v.permissionSource == 'licences' and 'licences' or 'documents',
        permissionKey = S.key(v.permissionKey) and v.permissionKey or v.key, category = S.text(v.category, 40), subject = subject,
        firstFee = math.floor(S.number(v.firstFee, 0, 100000000, 0)), reissueFee = math.floor(S.number(v.reissueFee, 0, 100000000, 0)),
        forgeryFee = math.floor(S.number(v.forgeryFee, 0, 100000000, 0)), allowForgery = v.allowForgery == true,
        requirePhoto = v.requirePhoto == true, validityDays = S.number(v.validityDays, 0, 36500, 0),
        animation = v.animation ~= false, presentationStyle = v.presentationStyle == 'citizen' and 'citizen' or 'police',
        animationMs = math.floor(S.number(v.animationMs, 250, 10000, 2500)),
        displayMs = (v.displayMs == nil or tonumber(v.displayMs) == 0) and 0 or math.floor(S.number(v.displayMs, 1000, 120000, 0)),
        prop = S.key(v.prop) and v.prop or '', layout = S.layout(v.layout),
        body = S.text(v.body, 8000), fields = fields, labels = labels, forgeableIdentity = forgeable,
        appearance = { background = S.colour(a.background, '#172a40'), secondary = S.colour(a.secondary, '#29455f'),
            text = S.colour(a.text, '#ffffff'), accent = S.colour(a.accent, '#e59a32'), pattern = a.pattern == true,
            stamp = a.stamp == true, profileStamp = a.profileStamp == true, signature = a.signature == true,
            stampImage = S.pngAsset(a.stampImage), forgedStampImage = S.pngAsset(a.forgedStampImage),
            stampText = S.text(a.stampText, 80), forgedStampText = S.text(a.forgedStampText, 80),
            headerCity = S.text(a.headerCity, 80), headerTitle = S.text(a.headerTitle, 80), emblem = S.text(a.emblem, 24),
            emblemImage = S.pngAsset(a.emblemImage), fontFamily = S.font(a.fontFamily),
            patternStyle = S.pattern(a.patternStyle), patternOpacity = S.number(a.patternOpacity, 0, 1, 0.18),
            forged = { enabled = alternate.enabled == true,
                background = S.colour(alternate.background, S.colour(a.background, '#172a40')),
                secondary = S.colour(alternate.secondary, S.colour(a.secondary, '#29455f')),
                text = S.colour(alternate.text, S.colour(a.text, '#ffffff')),
                accent = S.colour(alternate.accent, S.colour(a.accent, '#e59a32')),
                fontFamily = S.font(alternate.fontFamily or a.fontFamily), emblemImage = S.pngAsset(alternate.emblemImage),
                patternStyle = S.pattern(alternate.patternStyle or a.patternStyle),
                patternOpacity = S.number(alternate.patternOpacity, 0, 1, S.number(a.patternOpacity, 0, 1, 0.18)) } } }
end
function S.configuration(v)
    if type(v) ~= 'table' then return nil, 'invalid_config' end
    local g, defaults, labels = type(v.general) == 'table' and v.general or {}, DK.Config.default.general, {}
    for k, default in pairs(defaults.labels) do labels[k] = S.text(type(g.labels) == 'table' and g.labels[k] or default, 80) end
    local result = { schemaVersion = 1, revision = math.floor(S.number(v.revision, 1, 1000000000, 1)),
        general = { cityName = S.text(g.cityName, 80), logo = S.asset(g.logo), locale = S.text(g.locale, 20),
            range = S.number(g.range, 0.5, 10, 3), popupMs = math.floor(S.number(g.popupMs, 5000, 10000, 10000)),
            closeKey = S.text(g.closeKey, 20), labels = labels }, types = {}, npcs = {}, retiredItems = {} }
    if result.general.cityName == '' then result.general.cityName = defaults.cityName end
    if result.general.locale == '' then result.general.locale = defaults.locale end
    if result.general.closeKey == '' then result.general.closeKey = 'BACK' end
    local bound, count, sealBytes = {}, 0, 0
    for k, raw in pairs(type(v.types) == 'table' and v.types or {}) do
        local doc, err = S.document(raw)
        if not doc or k ~= doc.key or bound[doc.item] then return nil, err or 'duplicate_item' end
        count = count + 1
        if count > 150 then return nil, 'too_many_types' end
        sealBytes = sealBytes + #doc.appearance.stampImage + #doc.appearance.forgedStampImage
            + #doc.appearance.emblemImage + #doc.appearance.forged.emblemImage
        if sealBytes > 2097152 then return nil, 'seal_assets_too_large' end
        bound[doc.item], result.types[k] = true, doc
    end
    local seen = {}
    local retiredCount = 0
    for name, retired in pairs(type(v.retiredItems) == 'table' and v.retiredItems or {}) do
        if retired == true and S.key(name) then
            retiredCount = retiredCount + 1
            if retiredCount > 1000 then return nil, 'too_many_retired_items' end
            result.retiredItems[name] = true
        end
    end
    for i, raw in ipairs(type(v.npcs) == 'table' and v.npcs or {}) do
        if type(raw) ~= 'table' or i > 100 or not S.key(raw.id) or seen[raw.id] or not S.key(raw.model) then return nil, 'invalid_npc' end
        seen[raw.id] = true
        local c = type(raw.coords) == 'table' and raw.coords or {}
        local x, y, z = S.number(c.x, -10000, 10000), S.number(c.y, -10000, 10000), S.number(c.z, -500, 2500)
        if not x or not y or not z then return nil, 'invalid_coords' end
        local services = {}
        for _, k in ipairs(type(raw.services) == 'table' and raw.services or {}) do
            if not result.types[k] then return nil, 'unknown_document' end
            services[#services + 1] = k
        end
        result.npcs[#result.npcs + 1] = { id = raw.id, model = raw.model, label = S.text(raw.label, 100),
            coords = { x = x, y = y, z = z }, heading = S.number(raw.heading, -360, 360, 0),
            enabled = raw.enabled ~= false, mode = raw.mode == 'forgery' and 'forgery' or 'official',
            distance = S.number(raw.distance, 1, 5, 2), services = services,
            interaction = raw.interaction == 'target' and 'target' or 'interact', wallDetection = raw.wallDetection ~= false }
    end
    return result
end
function S.permissions(metadata)
    local v = S.clone(type(metadata.documents) == 'table' and metadata.documents or {})
    v.schemaVersion = 1
    v.permissions = type(v.permissions) == 'table' and v.permissions or {}
    v.categories = type(v.categories) == 'table' and v.categories or {}
    return v
end
function S.authorized(metadata, doc)
    if not doc.requiresAuthorization then return true end
    local state, allowed = S.permissions(metadata)
    if doc.permissionSource == 'licences' then allowed = type(metadata.licences) == 'table' and metadata.licences[doc.permissionKey] == true
    else allowed = state.permissions[doc.permissionKey] == true end
    if not allowed then return false end
    if doc.category ~= '' then
        local categories = state.categories[doc.permissionKey]
        return type(categories) == 'table' and categories[doc.category] == true
    end
    return true
end
function S.fields(doc, identity, input, forged)
    input = type(input) == 'table' and input or {}
    local values = {}
    for _, f in ipairs(doc.fields) do
        local value
        if f.source == 'identity' then value = identity[f.key] else value = input[f.key] end
        if forged and f.forgeable and input[f.key] ~= nil then value = input[f.key] end
        if forged and not f.forgeable then value = identity[f.key] or f.default end
        if value == nil then value = f.default end
        value = S.text(tostring(value or ''), f.type == 'textarea' and 2000 or 160)
        if f.required and value == '' then return nil, 'missing_field:' .. f.key end
        if f.type == 'number' and value ~= '' and not tonumber(value) then return nil, 'invalid_field:' .. f.key end
        if f.type == 'number' and value ~= '' then
            local n = tonumber(value)
            if n ~= n or n == math.huge or n == -math.huge then return nil, 'invalid_field:' .. f.key end
        end
        if f.type == 'date' and value ~= '' then
            value = S.date(value)
            if not value then return nil, 'invalid_field:' .. f.key end
        end
        values[#values + 1] = { key = f.key, label = f.label, value = value }
    end
    return values
end
