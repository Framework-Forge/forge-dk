local DK, S = ForgeDK, ForgeDK.Schema
local F, I, C = pr_lib.framework, pr_lib.inventory, pr_lib.cache
local Service = { config = nil, registered = {}, validators = {}, locks = {}, initialized = false }
DK.Service = Service
local function identifier(source) return F.GetIdentifier(tonumber(source)) end
local function cacheKey(source) return 'forge-dk:session:' .. tostring(source) end
local function token() return pr_lib.string.random(string.rep('.', 24)) end
local function itemAvailable(name)
    local item = I.Items(name)
    return item and item.active ~= false and item.disabled ~= true and item.stack ~= true
        and (not item.consume or item.consume == 0)
        and not (type(item.client) == 'table' and item.client.export)
        and not (type(item.server) == 'table' and item.server.export)
end
Service.token = token
function Service.admin(source)
    if source == 0 then return true end
    return pr_lib.ace.isPlayerAceAllowed(source, DK.Config.adminAce) == true
        or pr_lib.ace.isPlayerAceAllowed(source, 'group.admin') == true
end
function Service.profile(source)
    local p = F.GetPlayerData(source)
    if not p or not p.citizenid or type(p.charinfo) ~= 'table' then return nil end
    local info = p.charinfo
    return { identifier = p.citizenid, metadata = p.metadata or {},
        identity = { id = p.citizenid, firstName = tostring(info.firstname or ''), lastName = tostring(info.lastname or ''),
            dob = tostring(info.birthdate or ''), sex = (info.gender == 0 or info.gender == 'm') and 'M' or 'F' } }
end
function Service.seed(source)
    local p = Service.profile(source)
    if not p then return end
    local state, changed = S.permissions(p.metadata), false
    for _, doc in pairs(Service.config.types) do
        if doc.permissionSource == 'documents' and state.permissions[doc.permissionKey] == nil then
            state.permissions[doc.permissionKey], changed = false, true
        end
        if doc.category ~= '' then
            state.categories[doc.permissionKey] = state.categories[doc.permissionKey] or {}
            if state.categories[doc.permissionKey][doc.category] == nil then
                state.categories[doc.permissionKey][doc.category], changed = false, true
            end
        end
    end
    if changed then F.setPlayerMetadata(source, 'documents', state) end
end
function Service.initialize()
    local raw = pr_lib.loadJsonRecovery('data/config.json') or S.clone(DK.Config.default)
    local config, err = S.configuration(raw)
    if not config then error('Forge DK invalid configuration: ' .. tostring(err)) end
    Service.config, Service.initialized = config, true
    Service.registerItems()
end
function Service.public()
    return S.clone(Service.config)
end
function Service.documentItems()
    local items = {}
    -- Disabled types still identify physical documents, not ordinary starter items.
    for _, definition in pairs(Service.config.types) do items[definition.item] = true end
    for name in pairs(Service.config.retiredItems or {}) do items[name] = true end
    for name, registered in pairs(Service.registered) do
        if registered then items[name] = true end
    end
    return true, items
end
function Service.catalogue()
    local list = {}
    for key, item in pairs(I.Items() or {}) do
        if item.active ~= false and item.disabled ~= true then
            list[#list + 1] = { name = key, label = item.label or key, stack = item.stack,
                conflict = item.consume ~= nil and item.consume ~= 0 or
                    type(item.client) == 'table' and item.client.export ~= nil or
                    type(item.server) == 'table' and item.server.export ~= nil }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end
function Service.save(source, draft)
    if not Service.admin(source) then return false, 'no_permission' end
    if type(draft) ~= 'table' then return false, 'invalid_config' end
    if Service.saving then return false, 'busy' end
    Service.saving = true
    local ok, result, err = pcall(function()
        if tonumber(draft.revision) ~= Service.config.revision then return false, 'revision_conflict' end
        local config, errorCode = S.configuration(draft)
        if not config then return false, errorCode end
        -- Keep only server-owned history. Removing a template never deletes physical documents or SQL records.
        config.retiredItems = S.clone(Service.config.retiredItems or {})
        for key, previous in pairs(Service.config.types) do
            if not config.types[key] or config.types[key].item ~= previous.item then config.retiredItems[previous.item] = true end
        end
        for _, doc in pairs(config.types) do
            config.retiredItems[doc.item] = nil
            local item = I.Items(doc.item)
            if not item or item.disabled or item.active == false then return false, 'item_missing:' .. doc.item end
            if item.stack == true then return false, 'document_must_not_stack:' .. doc.item end
            if item.consume and item.consume ~= 0 or type(item.client) == 'table' and item.client.export
                or type(item.server) == 'table' and item.server.export then
                return false, 'item_action_conflict:' .. doc.item
            end
        end
        local retiredCount = 0
        for _ in pairs(config.retiredItems) do retiredCount = retiredCount + 1 end
        if retiredCount > 1000 then return false, 'too_many_retired_items' end
        config.revision = Service.config.revision + 1
        local saved, saveError = pr_lib.saveJsonRecovery('data/config.json', config)
        if not saved then return false, saveError end
        Service.config = config
        Service.registerItems()
        pr_lib.triggerClientEvent('forge-dk:client:configuration', -1, Service.public())
        return true, Service.public()
    end)
    Service.saving = false
    if not ok then print('[Forge DK] Save failed: ' .. tostring(result)); return false, 'save_failed' end
    return result, err
end
function Service.npc(source, id)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local coords = F.GetCoords(source)
    for _, npc in ipairs(Service.config.npcs) do
        if npc.id == id and npc.enabled and GetPlayerRoutingBucket(source) == 0 then
            local distance = #(coords - vector3(npc.coords.x, npc.coords.y, npc.coords.z))
            if distance <= npc.distance + 1.0 then return npc end
        end
    end
end
function Service.session(source, nonce)
    local session = C.get(cacheKey(source))
    if not session or session.nonce ~= nonce or session.expires < os.time()
        or session.owner ~= identifier(source) or not Service.npc(source, session.npcId) then return nil end
    return session
end
function Service.open(source, npcId)
    local npc, p = Service.npc(source, npcId), Service.profile(source)
    if not npc or not p then return false, 'not_near_service' end
    Service.seed(source)
    local session = { owner = p.identifier, npcId = npcId, nonce = token(), expires = os.time() + 600 }
    C.set(cacheKey(source), session, 600000)
    local services = {}
    for _, key in ipairs(npc.services) do
        local doc = Service.config.types[key]
        if doc and doc.active and (npc.mode ~= 'forgery' or doc.allowForgery) then
            local allowed = npc.mode == 'forgery' or S.authorized(p.metadata, doc)
            services[#services + 1] = { definition = S.clone(doc), allowed = allowed }
        end
    end
    return true, { mode = npc.mode, npc = S.clone(npc), nonce = session.nonce,
        services = services, identity = p.identity, general = S.clone(Service.config.general) }
end
function Service.photo(source, nonce)
    local session = Service.session(source, nonce)
    if not session then return false, 'session_expired' end
    local image = pr_lib.callback.await('forge-dk:client:photo', source)
    if not Service.session(source, nonce) then return false, 'session_expired' end
    if type(image) ~= 'string' or #image > DK.Config.maxPhotoBytes or
        not image:match('^data:image/png;base64,iVBORw0KGgo[%w+/=]+$') then return false, 'photo_failed' end
    session.photo = image
    C.set(cacheKey(source), session, 600000)
    return true, image
end
function Service.canIssue(source, key, subject)
    local doc, p = Service.config.types[key], Service.profile(source)
    if not doc or not doc.active or not itemAvailable(doc.item) then return false, 'document_unavailable' end
    if not p then return false, 'player_missing' end
    if not S.authorized(p.metadata, doc) then return false, 'authorization_required' end
    if doc.subject ~= 'person' then
        local provider = Service.validators[doc.subject]
        if not provider then return false, 'subject_provider_required' end
        if type(subject) ~= 'string' or #subject == 0 or #subject > 96 then return false, 'invalid_subject' end
        local ok, result = pcall(provider.callback, source, subject, S.clone(doc))
        if not ok or result ~= true then return false, 'subject_not_authorized' end
    end
    return true
end
function Service.quote(source, request)
    if not DK.Store.ready then return false, 'database_unavailable' end
    if type(request) ~= 'table' then return false, 'invalid_request' end
    local session = Service.session(source, request.nonce)
    if not session then return false, 'session_expired' end
    local npc, p, doc = Service.npc(source, session.npcId), Service.profile(source), Service.config.types[request.typeKey]
    if not p or not doc or not doc.active or not itemAvailable(doc.item) then return false, 'document_unavailable' end
    local listed = false
    for _, key in ipairs(npc.services) do if key == doc.key then listed = true end end
    if not listed then return false, 'service_unavailable' end
    if npc.mode == 'forgery' then
        if not doc.allowForgery then return false, 'forgery_disabled' end
        return true, { fee = doc.forgeryFee, copyNumber = 1, photoAvailable = session.photo ~= nil }
    end
    local subject = doc.subject == 'person' and p.identifier or S.text(request.subjectKey, 96)
    local allowed, errorCode = Service.canIssue(source, doc.key, subject)
    if not allowed then return false, errorCode end
    local scope = 'official:' .. p.identifier .. ':' .. doc.key .. ':' .. subject
    local row = DK.Store.scope(scope)
    if row and row.status == 'revoked' then return false, 'document_revoked' end
    if row and DK.Store.pending(row.serial) then return false, 'delivery_pending' end
    if row and tonumber(row.expires_at) > 0 and tonumber(row.expires_at) <= os.time() then return false, 'document_expired' end
    local previous = row and json.decode(row.snapshot)
    local copies = row and tonumber(row.copies) or 0
    return true, { fee = copies > 0 and doc.reissueFee or doc.firstFee, copyNumber = copies + 1,
        photoAvailable = session.photo ~= nil or previous and previous.photo ~= nil and previous.photo ~= '' or false }
end
local function visual(doc, p, input, forged, image)
    local identity = S.clone(p.identity)
    if forged then
        for key, allowed in pairs(doc.forgeableIdentity or {}) do
            if allowed and type(input[key]) == 'string' then identity[key] = S.text(input[key], 80) end
        end
        if doc.forgeableIdentity.dob and input.dob ~= nil and input.dob ~= '' then
            identity.dob = S.date(input.dob)
            if not identity.dob then return nil, 'invalid_field:dob' end
        end
    end
    local fields, err = S.fields(doc, identity, input, forged)
    if not fields then return nil, err end
    local g = Service.config.general
    local labels = S.clone(g.labels)
    for key, label in pairs(doc.labels) do labels[key] = label end
    return { schemaVersion = 1, typeKey = doc.key, item = doc.item, label = doc.label, format = doc.format,
        cityName = g.cityName, logo = g.logo, labels = labels, appearance = S.visualAppearance(doc.appearance, forged),
        identity = identity, photo = image or '', fields = fields, body = doc.body,
        category = doc.category, animation = doc.animation, prop = doc.prop,
        presentationStyle = doc.presentationStyle, layout = S.clone(doc.layout), animationMs = doc.animationMs, displayMs = doc.displayMs }
end
local function metadata(snapshot)
    return { document = snapshot, label = snapshot.label, firstName = snapshot.identity.firstName,
        lastName = snapshot.identity.lastName, id = snapshot.identity.id, dob = snapshot.identity.dob,
        sex = snapshot.identity.sex, imageURL = snapshot.photo }
end
Service.metadata = metadata
function Service.lock(owner, callback)
    if Service.locks[owner] then return false, 'busy' end
    Service.locks[owner] = true
    local ok, a, b = pcall(callback)
    Service.locks[owner] = nil
    if not ok then print('[Forge DK] Operation failed: ' .. tostring(a)); return false, 'operation_failed' end
    return a, b
end
function Service.issue(source, request, integration)
    if not DK.Store.ready then return false, 'database_unavailable' end
    if type(request) ~= 'table' then return false, 'invalid_request' end
    local p = Service.profile(source)
    if not p then return false, 'player_missing' end
    return Service.lock(p.identifier, function()
        local session, npc, doc = nil, nil, Service.config.types[request.typeKey]
        if not doc or not doc.active or not itemAvailable(doc.item) then return false, 'document_unavailable' end
        if not integration then
            session = Service.session(source, request.nonce)
            if not session then return false, 'session_expired' end
            npc = Service.npc(source, session.npcId)
            local listed = false
            for _, key in ipairs(npc.services) do if key == doc.key then listed = true end end
            if not listed then return false, 'service_unavailable' end
        end
        local forged = npc and npc.mode == 'forgery' or integration and request.forged == true
        if forged and not doc.allowForgery then return false, 'forgery_disabled' end
        local subject = doc.subject == 'person' and p.identifier or S.text(request.subjectKey, 96)
        if not forged then
            local allowed, err = Service.canIssue(source, doc.key, subject)
            if not allowed then return false, err end
        end
        local scope = forged and 'forged:' .. token() or 'official:' .. p.identifier .. ':' .. doc.key .. ':' .. subject
        local previous = DK.Store.scope(scope)
        if previous and DK.Store.pending(previous.serial) then return false, 'delivery_pending' end
        if previous and previous.status == 'revoked' then return false, 'document_revoked' end
        if previous and tonumber(previous.expires_at) > 0 and tonumber(previous.expires_at) <= os.time() then return false, 'document_expired' end
        local old = previous and json.decode(previous.snapshot) or nil
        local image = session and session.photo or integration and request.photo
        if not image and old then image = old.photo end
        if image == '' then image = nil end
        if image and (type(image) ~= 'string' or #image > DK.Config.maxPhotoBytes or not image:match('^data:image/png;base64,iVBORw0KGgo[%w+/=]+$')) then return false, 'photo_failed' end
        if doc.requirePhoto and not image then return false, 'photo_required' end
        local snapshot, err = visual(doc, p, type(request.fields) == 'table' and request.fields or {}, forged, image)
        if not snapshot then return false, err end
        local serial = previous and previous.serial or 'DK-' .. token()
        local created = previous and tonumber(previous.created_at) or os.time()
        local expires = previous and tonumber(previous.expires_at) or doc.validityDays > 0 and created + math.floor(doc.validityDays * 86400) or 0
        snapshot.serial, snapshot.copyId = serial, token()
        snapshot.issuedAt, snapshot.expiresAt, snapshot.copyIssuedAt = created, expires, os.time()
        snapshot.copyNumber = previous and tonumber(previous.copies) + 1 or 1
        local record = { new = previous == nil, serial = serial, owner = p.identifier, typeKey = doc.key,
            subject = subject, scope = scope, kind = forged and 'forged' or 'official', createdAt = created,
            expiresAt = expires, snapshot = S.clone(snapshot) }
        local fee = forged and doc.forgeryFee or previous and tonumber(previous.copies) > 0 and doc.reissueFee or doc.firstFee
        if not integration and tonumber(request.expectedFee) ~= fee then return false, 'quote_changed' end
        local account = request.account == 'bank' and 'bank' or 'cash'
        local itemMetadata = metadata(snapshot)
        if not I.CanCarryItem(source, doc.item, 1, itemMetadata) then return false, 'inventory_full' end
        if fee > 0 and F.getPlayerMoney(source, account) < fee then return false, 'insufficient_funds' end
        if not DK.Store.reserve(record, snapshot, fee, account) then return false, 'database_unavailable' end
        if identifier(source) ~= p.identifier or not integration and not Service.session(source, request.nonce) then
            DK.Store.failed(snapshot.copyId); return false, 'session_expired'
        end
        if not forged then
            local allowed, reason = Service.canIssue(source, doc.key, subject)
            if not allowed then DK.Store.failed(snapshot.copyId); return false, reason end
        end
        local function pending()
            pcall(DK.Store.stage, snapshot.copyId, 'review')
            print('[Forge DK] DELIVERY RECONCILIATION REQUIRED owner=' .. p.identifier .. ' copy=' .. snapshot.copyId)
            return false, 'delivery_pending'
        end
        local function refund()
            if fee == 0 then return true end
            if identifier(source) ~= p.identifier then return false end
            local ok, refunded = pcall(F.addPlayerMoney, source, account, fee, 'forge-dk:refund')
            return ok and refunded == true
        end
        if fee > 0 then
            local charged, removed = pcall(F.removePlayerMoney, source, account, fee, 'forge-dk:issue')
            if not charged then return pending() end -- An exception makes the debit outcome uncertain.
            if not removed then DK.Store.failed(snapshot.copyId); return false, 'insufficient_funds' end
        end
        local marked, staged = pcall(DK.Store.stage, snapshot.copyId, 'charged')
        if not marked or not staged then
            if not refund() then return pending() end
            pcall(DK.Store.failed, snapshot.copyId); return false, 'database_unavailable'
        end
        if identifier(source) ~= p.identifier then return pending() end
        marked, staged = pcall(DK.Store.stage, snapshot.copyId, 'delivering')
        if not marked or not staged then
            if not refund() then return pending() end
            pcall(DK.Store.failed, snapshot.copyId); return false, 'database_unavailable'
        end
        -- Both database checkpoints can yield. Never deliver to a reused source id.
        if identifier(source) ~= p.identifier then return pending() end
        if not integration and not Service.session(source, request.nonce) then
            if not refund() then return pending() end
            pcall(DK.Store.failed, snapshot.copyId); return false, 'session_expired'
        end
        if not forged then
            local allowed, reason = Service.canIssue(source, doc.key, subject)
            if not allowed then
                if not refund() then return pending() end
                pcall(DK.Store.failed, snapshot.copyId); return false, reason
            end
        end
        local ok, delivered = pcall(I.AddItem, source, doc.item, 1, itemMetadata)
        if not ok then return pending() end -- The inventory might already have delivered before throwing.
        if not delivered then
            if not refund() then return pending() end
            DK.Store.failed(snapshot.copyId); return false, 'inventory_full'
        end
        local persisted, committed = pcall(DK.Store.delivered, record, snapshot)
        if not persisted or not committed then
            local read, receipt = pcall(DK.Store.copy, snapshot.copyId)
            if read and receipt and receipt.status == 'delivered' then return true, snapshot end
            if not read or identifier(source) ~= p.identifier then return pending() end
            local rolledBack, removed = pcall(I.RemoveItem, source, doc.item, 1, itemMetadata)
            if rolledBack and removed then
                if not refund() then return pending() end
                pcall(DK.Store.failed, snapshot.copyId)
                return false, 'database_unavailable'
            end
            return pending()
        end
        return true, snapshot
    end)
end
function Service.permission(source, key, enabled, category)
    local doc, p = Service.config.types[key], Service.profile(source)
    if not doc or not p or type(enabled) ~= 'boolean' then return false, 'invalid_request' end
    return Service.lock(p.identifier, function()
        local latest = Service.profile(source)
        if not latest or latest.identifier ~= p.identifier then return false, 'player_missing' end
        local state = S.permissions(latest.metadata)
        category = S.text(category == nil and doc.category or category, 40)
        if category ~= '' then
            state.categories[doc.permissionKey] = state.categories[doc.permissionKey] or {}
            state.categories[doc.permissionKey][category] = enabled
        end
        -- Granting one category enables its parent gate. Revoking it leaves sibling categories intact.
        if (category == '' or enabled) and doc.permissionSource == 'licences' then
            local licences = S.clone(latest.metadata.licences or {})
            licences[doc.permissionKey] = enabled
            F.setPlayerMetadata(source, 'licences', licences)
        elseif category == '' or enabled then state.permissions[doc.permissionKey] = enabled end
        F.setPlayerMetadata(source, 'documents', state)
        return true
    end)
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
function Service.verify(value)
    if not DK.Store.ready then return false, 'database_unavailable' end
    local doc = type(value) == 'table' and (value.document or value) or nil
    if not doc or not S.key(doc.copyId) then return false, 'unregistered' end
    local row = DK.Store.copy(doc.copyId)
    if not row or row.status ~= 'delivered' then return false, 'unregistered' end
    if row.kind ~= 'official' then return false, 'forged' end
    if row.document_status ~= 'valid' then return false, row.document_status end
    if tonumber(row.expires_at) > 0 and tonumber(row.expires_at) <= os.time() then return false, 'expired' end
    if not same(doc, json.decode(row.snapshot)) then return false, 'altered' end
    return true, { serial = row.serial, owner = row.owner_identifier, typeKey = row.type_key, expiresAt = row.expires_at }
end
function Service.documentItem(source, slot)
    slot = tonumber(slot)
    if not slot or slot ~= math.floor(slot) then return nil end
    local item = I.GetSlot(source, slot)
    local value = item and item.metadata and item.metadata.document
    if type(value) ~= 'table' or value.item ~= item.name or value.schemaVersion ~= 1 then return nil end
    return item, S.clone(value)
end
function Service.present(source, slot, nearby)
    local item, snapshot = Service.documentItem(source, slot)
    if not item then return false, 'invalid_document' end
    -- Cosmetic changes apply to already issued documents. Never rewrite the registered item snapshot.
    local definition = Service.config.types[snapshot.typeKey]
    if definition then
        local forged = snapshot.appearance and snapshot.appearance.stampStyle == 'single'
        snapshot.appearance = S.visualAppearance(definition.appearance, forged)
        snapshot.layout = S.clone(definition.layout)
        snapshot.cityName, snapshot.logo = Service.config.general.cityName, Service.config.general.logo
        snapshot.label, snapshot.animation, snapshot.prop = definition.label, definition.animation, definition.prop
        snapshot.body = definition.body
        snapshot.presentationStyle = definition.presentationStyle
        snapshot.animationMs, snapshot.displayMs = definition.animationMs, definition.displayMs
        snapshot.labels = S.clone(Service.config.general.labels)
        for key, value in pairs(definition.labels) do snapshot.labels[key] = value end
        local fieldLabels = {}
        for _, field in ipairs(definition.fields) do fieldLabels[field.key] = field.label end
        for _, field in ipairs(snapshot.fields or {}) do field.label = fieldLabels[field.key] or field.label end
    end
    local targets = { source }
    if nearby then
        local coords, bucket = F.GetCoords(source), GetPlayerRoutingBucket(source)
        for _, player in ipairs(GetPlayers()) do
            player = tonumber(player)
            if player ~= source and GetPlayerRoutingBucket(player) == bucket and GetPlayerPed(player) ~= 0 then
                if #(F.GetCoords(player) - coords) <= Service.config.general.range then targets[#targets + 1] = player end
            end
        end
    end
    pr_lib.triggerClientEvent('forge-dk:client:document', targets, snapshot, source == tonumber(source) and slot or nil, source,
        snapshot.displayMs and snapshot.displayMs > 0 and snapshot.displayMs
            or math.floor(S.number(Service.config.general.popupMs, 5000, 10000, 10000)))
    return true
end
function Service.registerItems()
    local names = S.clone(Service.config.retiredItems or {})
    for _, definition in pairs(Service.config.types) do names[definition.item] = true end
    for name in pairs(names) do
        if not Service.registered[name] and I.Items(name) then
            local registered = I.RegisterUsableItem(name, function(source, itemData)
                -- Re-read the actual slot. Never replace missing metadata with the current holder's identity.
                local item = Service.documentItem(source, itemData.slot)
                if not item then
                    pr_lib.notify.NotifyPlayer(source, { title = 'Forge DK', description = DK.Lang:t('ui.noRegistration'), type = 'error' })
                    return false
                end
                Service.present(source, itemData.slot, true)
                return false
            end, { cancelUse = true })
            Service.registered[name] = registered == true
        end
    end
end
