local DK, S, Service = ForgeDK, ForgeDK.Schema, ForgeDK.Service
DK.Lang = pr_lib.locale()
local function response(callback, source, request)
    if not Service.initialized then return false, 'starting' end
    local ok, a, b = pcall(callback, source, request)
    if not ok then print('[Forge DK] Callback failed: ' .. tostring(a)); return false, 'operation_failed' end
    return a, b
end
local function register(name, handler, interval)
    pr_lib.callback.register('forge-dk:server:' .. name, function(source, request)
        local key, now = 'forge-dk:rate:' .. source .. ':' .. name, GetGameTimer()
        local last = pr_lib.cache.get(key, -100000)
        if now - last < (interval or 250) then return false, 'rate_limited' end
        pr_lib.cache.set(key, now, 60000)
        return response(handler, source, request)
    end)
end
register('configuration', function() return true, { config = Service.public(), translations = DK.Lang:getAll() } end)
register('admin', function(source)
    if not Service.admin(source) then return false, 'no_permission' end
    return true, { config = Service.public(), catalogue = Service.catalogue(), translations = DK.Lang:getAll() }
end)
register('save', Service.save, 750)
register('open', function(source, request)
    return Service.open(source, type(request) == 'table' and request.npcId or nil)
end)
register('photo', function(source, request)
    return Service.photo(source, type(request) == 'table' and request.nonce or nil)
end, 1500)
register('issue', function(source, request) return Service.issue(source, request, false) end, 1000)
register('quote', Service.quote, 250)
register('present', function(source, request)
    if type(request) ~= 'table' then return false, 'invalid_request' end
    return Service.present(source, request.slot, request.nearby == true)
end, 750)
register('records', function(source, request)
    if not Service.admin(source) then return false, 'no_permission' end
    if not DK.Store.ready then return false, 'database_unavailable' end
    local owner = type(request) == 'table' and S.text(request.identifier, 64) or ''
    return true, DK.Store.list(owner ~= '' and owner or nil)
end, 500)
register('permission', function(source, request)
    -- Admin-only operations never trust the frontend's access flags.
    if not Service.admin(source) then return false, 'no_permission' end
    if type(request) ~= 'table' then return false, 'invalid_request' end
    return Service.permission(tonumber(request.target), request.typeKey, request.enabled == true,
        request.category ~= '' and request.category or nil)
end, 500)
register('record', function(source, request)
    if not Service.admin(source) then return false, 'no_permission' end
    if not DK.Store.ready or type(request) ~= 'table' or not S.key(request.serial) then return false, 'invalid_request' end
    local row = DK.Store.document(request.serial)
    if not row then return false, 'document_missing' end
    return true, { document = json.decode(row.snapshot), receipts = DK.Store.receipts(row.serial), kind = row.kind, status = row.status }
end, 500)
register('revoke', function(source, request)
    if not Service.admin(source) then return false, 'no_permission' end
    if not DK.Store.ready or type(request) ~= 'table' or not S.key(request.serial) then return false, 'invalid_request' end
    local row = DK.Store.document(request.serial)
    if not row then return false, 'document_missing' end
    return Service.lock(row.owner_identifier, function() return DK.Store.revoke(row.serial) end)
end, 500)
local function trusted()
    local resource = GetInvokingResource()
    if not resource then return false end
    return DK.Config.trustedResources[resource] == true
        or pr_lib.ace.isPrincipalAceAllowed('resource.' .. resource, DK.Config.integrationAce) == true
end
local function integration(callback)
    return function(...)
        if not trusted() then return false, 'resource_not_authorized' end
        if not Service.initialized then return false, 'starting' end
        local ok, a, b = pcall(callback, ...)
        if not ok then print('[Forge DK] Export failed: ' .. tostring(a)); return false, 'operation_failed' end
        return a, b
    end
end
pr_lib.addExports('CanIssueDocument', integration(Service.canIssue))
pr_lib.addExports('GetDocumentItems', integration(Service.documentItems))
pr_lib.addExports('IssueDocument', integration(function(source, request) return Service.issue(source, request, true) end))
pr_lib.addExports('GrantDocumentPermission', integration(function(source, key, category) return Service.permission(source, key, true, category) end))
pr_lib.addExports('RevokeDocumentPermission', integration(function(source, key, category) return Service.permission(source, key, false, category) end))
pr_lib.addExports('VerifyDocument', integration(Service.verify))
pr_lib.addExports('RevokeDocument', integration(function(serial)
    if not DK.Store.ready or not S.key(serial) then return false, 'invalid_request' end
    local row = DK.Store.document(serial)
    if not row then return false, 'document_missing' end
    return Service.lock(row.owner_identifier, function() return DK.Store.revoke(serial) end)
end))
pr_lib.addExports('GetDeliveryReceipts', integration(function(serial)
    if not DK.Store.ready or not S.key(serial) then return false, 'invalid_request' end
    return true, DK.Store.receipts(serial)
end))
pr_lib.addExports('GetDocument', integration(function(serial)
    if not DK.Store.ready or not S.key(serial) then return false, 'invalid_request' end
    return true, DK.Store.document(serial)
end))
pr_lib.addExports('GetDocuments', integration(function(owner)
    if not DK.Store.ready or type(owner) ~= 'string' or #owner > 64 then return false, 'invalid_request' end
    return true, DK.Store.list(owner)
end))
pr_lib.addExports('RegisterSubjectValidator', integration(function(kind, callback)
    if (kind ~= 'vehicle' and kind ~= 'business') or type(callback) ~= 'function' then return false, 'invalid_request' end
    Service.validators[kind] = { callback = callback, resource = GetInvokingResource() }
    return true
end))
pr_lib.addExports('OpenDocumentService', integration(function(source, npcId)
    local ok, data = Service.open(source, npcId)
    if ok then pr_lib.triggerClientEvent('forge-dk:client:service', source, data) end
    return ok, data
end))
pr_lib.addCommand('forgedk', { help = 'Forge DK', canAccess = Service.admin }, function(source)
    if source > 0 and Service.admin(source) then pr_lib.triggerClientEvent('forge-dk:client:admin', source) end
end)
AddEventHandler('playerDropped', function()
    pr_lib.cache.clear('forge-dk:session:' .. source)
    pr_lib.cache.clearPrefix('forge-dk:rate:' .. source .. ':')
end)
AddEventHandler('onResourceStop', function(resource)
    for kind, provider in pairs(Service.validators) do
        if provider.resource == resource then Service.validators[kind] = nil end
    end
end)
AddEventHandler('forge-core:server:inventory:reloaded', function()
    if Service.initialized then Service.registerItems() end
end)
CreateThread(function()
    local ok, err = pcall(Service.initialize)
    if not ok then print('[Forge DK] Initialization stopped: ' .. tostring(err)); return end
    local available = pcall(pr_lib.waitFor, function() return pr_lib.database.isReady() or nil end, 'Forge DK database timeout', 30000)
    if available and DK.Store.initialize() then
        print('[Forge DK] Ready. Use /forgedk to configure documents and service NPCs.')
    else print('[Forge DK] Database unavailable. Issuance is blocked; fix the database and restart forge-dk.') end
end)
