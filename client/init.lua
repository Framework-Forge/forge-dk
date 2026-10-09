local DK, N, streaming, World = ForgeDK, pr_lib.nui, pr_lib.fivem.streaming, ForgeDK.World
local config, ready, open, busyBefore, timer = DK.Config.default, false, false, nil, nil
local npcs, props, pendingPhoto, generation, npcGeneration = {}, {}, nil, 0, 0
local operation
local showing
local function stopPresentation()
    local previous = showing
    showing = nil
    if not previous then return end
    if previous.cleanupTimer then previous.cleanupTimer:forceEnd(false); previous.cleanupTimer = nil end
    if previous.object and props[previous.object] then
        if World.exists(previous.object) then streaming.deleteEntity(previous.object) end
        props[previous.object] = nil
    end
    if previous.started and World.exists(previous.ped) then
        StopAnimTask(previous.ped, previous.preset.dict, previous.preset.anim, 2.0)
    end
end
local function endDisplay()
    generation = generation + 1
    if timer then timer:forceEnd(false); timer = nil end
    stopPresentation()
end
local function suspend(reason)
    if operation then return nil end
    local token = { reason = reason, generation = generation }
    operation = token
    N.focus(false, false, false)
    N.send('forge-dk:suspend', { hidden = true, reason = reason })
    return token
end
local function resume(token)
    if operation ~= token then return end
    operation = nil
    if token.generation ~= generation then return end
    N.send('forge-dk:suspend', { hidden = false })
    if open then N.focus(true, true, false) end
end
local function rpc(name, data)
    local success, ok, result = pcall(pr_lib.callback.await, 'forge-dk:server:' .. name, 30000, data or {})
    if not success then return { ok = false, error = 'connection_failed' } end
    return { ok = ok == true, data = ok and result or nil, error = not ok and result or nil }
end
local function focus(value)
    -- A passive document overlay must not release another resource's NUI focus when its timer ends.
    if not value and not open then return end
    if value and not open then
        if LocalPlayer.state.invOpen and pr_lib.inventory.closeInventory then pr_lib.inventory.closeInventory() end
        busyBefore = LocalPlayer.state.invBusy
        LocalPlayer.state:set('invBusy', true, true)
    elseif not value and open then
        LocalPlayer.state:set('invBusy', busyBefore == true, true)
        busyBefore = nil
    end
    open = value
    N.focus(value, value, false)
end
local function close()
    generation = generation + 1
    if timer then timer:forceEnd(false); timer = nil end
    stopPresentation()
    if pendingPhoto then pendingPhoto.cancelled = true; World.stopPhoto(pendingPhoto.scene) end
    if operation and operation.reason == 'placement' then pcall(pr_lib.devtools.stop) end
    operation = nil
    focus(false)
    N.send('forge-dk:close', {})
end
local function send(action, data)
    if ready then N.send(action, data) end
end
local function openAdmin()
    if operation then return { ok = false, error = 'busy' } end
    local current = generation
    local result = rpc('admin')
    if not result.ok then return result end
    if current ~= generation or operation then return { ok = false, error = 'busy' } end
    endDisplay()
    focus(true)
    send('forge-dk:admin', result.data)
    return result
end
local function openService(npcId)
    if operation then return { ok = false, error = 'busy' } end
    local current = generation
    local result = rpc('open', { npcId = npcId })
    if current ~= generation or operation then return { ok = false, error = 'busy' } end
    if result.ok then endDisplay(); focus(true); send('forge-dk:service', result.data) end
    return result
end
local function clearNpcs()
    for _, entry in pairs(npcs) do
        if entry.kind == 'target' then pr_lib.target.removeLocalEntity(entry.entity, { entry.name })
        elseif entry.interaction then pr_lib.interact.RemoveInteraction(entry.interaction) end
        if World.exists(entry.entity) then streaming.deleteEntity(entry.entity) end
    end
    npcs = {}
end
local function configure(value)
    npcGeneration = npcGeneration + 1
    local current = npcGeneration
    config = value
    clearNpcs()
    for _, npc in ipairs(config.npcs) do
        if npc.enabled then
            local coords = vector3(npc.coords.x, npc.coords.y, npc.coords.z)
            local heading = (DK.Schema.number(npc.heading, -360, 360, 0.0) % 360.0) + 0.0
            local entity = streaming.createPed(npc.model, coords, heading,
                { networked = false, missionEntity = true, freeze = true, invincible = true, timeout = 5000 })
            if current ~= npcGeneration then if World.exists(entity) then streaming.deleteEntity(entity) end; return end
            if World.exists(entity) then
                -- Placement stores the surface Z. Match the bridge's ped preview origin adjustment.
                streaming.setEntityTransform(entity, coords, heading, { noOffset = false })
                local id = npc.id
                local name, walls = 'forge-dk:service:' .. id, npc.wallDetection ~= false
                local function allowed() return not open and not operation and World.canReach(entity, walls) end
                local function select() if allowed() then openService(id) end end
                if npc.interaction == 'target' then
                    pr_lib.target.addLocalEntity(entity, {{ name = name, label = npc.label, icon = 'fa-solid fa-id-card',
                        distance = npc.distance, wallDetection = walls, ignoreLos = not walls,
                        canInteract = allowed, onSelect = select }})
                    npcs[id] = { entity = entity, kind = 'target', name = name }
                else
                    local interaction = pr_lib.interact.AddLocalEntityInteraction({
                        id = 'forge-dk:' .. id, entity = entity, distance = math.max(8.0, npc.distance), interactDst = npc.distance,
                        wallDetection = walls, ignoreLos = not walls,
                        options = {{ name = name, label = npc.label, canInteract = allowed, action = select }},
                    })
                    npcs[id] = { entity = entity, interaction = interaction, kind = 'interact' }
                end
            else print('[Forge DK] NPC model could not be loaded: ' .. npc.model) end
        end
    end
    send('forge-dk:configuration', config)
end
RegisterNetEvent('forge-dk:client:configuration', configure)
RegisterNetEvent('forge-dk:client:admin', openAdmin)
RegisterNetEvent('forge-dk:client:service', function(data)
    if operation then return end
    endDisplay()
    focus(true)
    send('forge-dk:service', data)
end)
RegisterNetEvent('forge-dk:client:document', function(snapshot, slot, presenter, popupMs)
    if operation then return end
    local own = presenter == pr_lib.cache.serverId
    if not own and open then return end
    generation = generation + 1
    local current = generation
    if timer then timer:forceEnd(false); timer = nil end
    stopPresentation()
    -- A timed presentation is an overlay, not an interactive menu. Keep movement and input available.
    if own then
        if LocalPlayer.state.invOpen and pr_lib.inventory.closeInventory then pr_lib.inventory.closeInventory() end
        focus(false)
    end
    send('forge-dk:document', { document = snapshot, slot = own and slot or nil, own = own })
    local duration = math.floor(DK.Schema.number(popupMs, 1000, 120000, 10000))
    timer = pr_lib.timer(duration, function() if generation == current then close() end end, true)
    if own and snapshot.animation then
        local ped = World.ped()
        if not ped then return end
        local preset = DK.Schema.presentation(snapshot)
        local entry = { ped = ped, preset = preset }
        showing = entry
        local object = streaming.createObject(preset.model, GetEntityCoords(ped),
            { networked = true, missionEntity = true, collision = false, timeout = 3000 })
        if showing ~= entry or current ~= generation then
            if World.exists(object) then streaming.deleteEntity(object) end
            return
        end
        if World.exists(object) and World.exists(ped) then
            entry.object = object
            AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, preset.bone),
                preset.pos[1], preset.pos[2], preset.pos[3], preset.rot[1], preset.rot[2], preset.rot[3],
                true, true, false, true, preset.rotationOrder, true)
            props[object] = true
            local animationDuration = math.min(duration, math.floor(DK.Schema.number(snapshot.animationMs, 250, 10000, 2500)))
            local played = streaming.playAnim({ ped = ped, dict = preset.dict, clip = preset.anim,
                duration = animationDuration, flags = preset.flags, wait = false })
            entry.started = played ~= false
            if showing ~= entry or current ~= generation then
                if entry.started and World.exists(ped) then StopAnimTask(ped, preset.dict, preset.anim, 2.0) end
                return
            end
            if not entry.started then stopPresentation()
            else entry.cleanupTimer = pr_lib.timer(animationDuration, function()
                if showing == entry then stopPresentation() end
            end, true) end
        elseif World.exists(object) then streaming.deleteEntity(object)
        end
    end
end)
N.register('loaded', function(_, reply)
    ready = true
    reply(rpc('configuration'))
end)
N.register('close', function(_, reply) close(); reply({ ok = true }) end)
for _, name in ipairs({ 'save', 'issue', 'quote', 'records', 'record', 'permission', 'revoke', 'present' }) do
    local action = name
    N.register(action, function(data, reply) reply(rpc(action, data)) end)
end
N.register('photo', function(data, reply) reply(rpc('photo', data)) end)
N.register('photoResolved', function(data, reply)
    if pendingPhoto and type(data) == 'table' and data.token == pendingPhoto.token then
        pendingPhoto.image, pendingPhoto.resolved = data.image, true
    end
    reply({ ok = true })
end)
N.register('placeNpc', function(data, reply)
    if type(data) ~= 'table' or not DK.Schema.key(data.model) then reply({ ok = false, error = 'invalid_npc' }); return end
    local current = generation
    local allowed = rpc('admin')
    if not allowed.ok then reply(allowed); return end
    if not open or current ~= generation then reply({ ok = false, error = 'busy' }); return end
    local token = suspend('placement')
    if not token then reply({ ok = false, error = 'busy' }); return end
    local success, started = pcall(pr_lib.devtools.placePed, data.model, 1, function(placement)
        if operation ~= token or token.generation ~= generation then return end
        local result = World.placement(placement)
        if result then result.npcId = data.npcId; send('forge-dk:placement', result) end
        resume(token)
    end, { preview = true, freezePlayer = true, confirmOnPlace = true, heightOffset = 0.0, modelTimeout = 5000,
        heading = ((DK.Schema.number(data.heading, -360, 360, 0.0) % 360.0) + 0.0) })
    if not success or not started then resume(token) end
    reply({ ok = success and started == true, error = (not success or not started) and 'placement_failed' or nil })
end)
pr_lib.callback.register('forge-dk:client:photo', function()
    if pendingPhoto or operation then return nil end
    local ped = World.ped()
    if not ped or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then return nil end
    local token = suspend('photo')
    local scene = World.startPhoto(ped)
    if not scene then resume(token); return nil end
    local drawable, texture, palette = GetPedDrawableVariation(ped, 1), GetPedTextureVariation(ped, 1), GetPedPaletteVariation(ped, 1)
    local handle
    local state = { token = tostring(GetGameTimer()), resolved = false, ped = ped, scene = scene,
        model = GetEntityModel(ped), drawable = drawable, texture = texture, palette = palette }
    pendingPhoto = state
    local ok, image = pcall(function()
        if drawable ~= 0 then SetPedComponentVariation(ped, 1, 0, 0, 2) end
        for _ = 1, 12 do
            Wait(100)
            if state.cancelled or scene.cancelled or not World.exists(ped) then error('cancelled') end
        end
        handle = RegisterPedheadshotTransparent(ped)
        if not handle or handle == 0 then handle = RegisterPedheadshot_3(ped) end
        state.handle = handle
        if type(handle) ~= 'number' or handle <= 0 then error('headshot_failed') end
        pr_lib.waitFor(function()
            if state.cancelled or scene.cancelled or not World.exists(ped) then error('cancelled') end
            return IsPedheadshotReady(handle) and IsPedheadshotValid(handle) or nil
        end, 'headshot_timeout', 3000)
        send('forge-dk:photo', { txd = GetPedheadshotTxdString(handle), token = state.token })
        pr_lib.waitFor(function() return state.resolved or state.cancelled or scene.cancelled or nil end, 'photo_timeout', 5000)
        return not state.cancelled and not scene.cancelled and state.image or nil
    end)
    if state.handle and state.handle ~= 0 then UnregisterPedheadshot(state.handle); state.handle = nil end
    World.stopPhoto(scene)
    if World.exists(ped) and GetEntityModel(ped) == state.model and drawable ~= 0 then SetPedComponentVariation(ped, 1, drawable, texture, palette) end
    pendingPhoto = nil
    resume(token)
    return ok and image or nil
end)
pr_lib.addKeybind({ name = 'forge-dk:close', description = 'Forge DK', defaultKey = config.general.closeKey,
    onPressed = function() close() end })
pr_lib.addExports('OpenAdminPanel', openAdmin)
pr_lib.addExports('OpenDocumentService', openService)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    close()
    npcGeneration = npcGeneration + 1
    clearNpcs()
    for object in pairs(props) do if World.exists(object) then streaming.deleteEntity(object) end end
    props = {}
    if pendingPhoto then
        if pendingPhoto.handle and pendingPhoto.handle ~= 0 then UnregisterPedheadshot(pendingPhoto.handle); pendingPhoto.handle = nil end
        if World.exists(pendingPhoto.ped) and GetEntityModel(pendingPhoto.ped) == pendingPhoto.model and pendingPhoto.drawable ~= 0 then
            SetPedComponentVariation(pendingPhoto.ped, 1, pendingPhoto.drawable, pendingPhoto.texture, pendingPhoto.palette)
        end
    end
    pr_lib.addKeybind.remove('forge-dk:close')
end)
CreateThread(function()
    for _ = 1, 20 do
        local result = rpc('configuration')
        if result.ok then configure(result.data.config); send('forge-dk:bootstrap', result.data); return end
        Wait(1000)
    end
    print('[Forge DK] Could not receive configuration.')
end)
