local World = {}
ForgeDK.World = World
local lastNativeError = -5000

function World.exists(entity)
    -- Never pass tables, booleans, NaN, fractional/out-of-range handles to natives.
    if type(entity) ~= 'number' or entity <= 0 or entity > 2147483647 or entity % 1 ~= 0 then return false end
    local ok, exists = pcall(DoesEntityExist, entity)
    if not ok then
        local now = GetGameTimer()
        if now - lastNativeError >= 5000 then
            lastNativeError = now
            print(('[Forge DK] Entity validation failed (handle=%s): %s\n%s'):format(entity, tostring(exists), debug.traceback('', 2)))
        end
    end
    -- Generic FiveM BOOL wrappers return 1/false; typed wrappers return true/false.
    return ok and (exists == true or exists == 1)
end
function World.ped()
    local ped = pr_lib.cache.ped
    if not World.exists(ped) then ped = PlayerPedId() end
    return World.exists(ped) and IsEntityAPed(ped) and ped or nil
end
function World.placement(value)
    if type(value) ~= 'table' and type(value) ~= 'vector4' then return nil end
    local c = type(value) == 'vector4' and value or (value.coords or value.position or value)
    if type(c) ~= 'table' and type(c) ~= 'vector3' and type(c) ~= 'vector4' then return nil end
    local heading = type(value) == 'table' and value.heading or nil
    if heading == nil and (type(c) == 'table' or type(c) == 'vector4') then heading = c.w end
    local x, y, z = ForgeDK.Schema.number(c.x, -10000, 10000), ForgeDK.Schema.number(c.y, -10000, 10000), ForgeDK.Schema.number(c.z, -500, 2500)
    heading = ForgeDK.Schema.number(heading, -360, 360)
    if not x or not y or not z or not heading then return nil end
    return { coords = {x=x,y=y,z=z}, heading = (heading % 360.0) + 0.0 }
end
function World.canReach(entity, walls)
    local ped = World.ped()
    if not ped or not World.exists(entity) then return false end
    if not walls then return true end
    return pr_lib.cache.remember('forge-dk:los:' .. entity, function()
        if not World.exists(ped) or not World.exists(entity) then return false end
        local from = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
        local to = GetPedBoneCoords(entity, 31086, 0.0, 0.0, 0.0)
        local ok, hit, hitEntity = pcall(pr_lib.raycast.fromCoords, from, to, 511, 4, ped)
        return ok and (not hit or hitEntity == entity)
    end, 150)
end
function World.startPhoto(ped)
    if not World.exists(ped) then return nil end
    local camera = pr_lib.fivem.editorCamera
    if camera.active or camera.isFreecamActive() then return nil end
    local state = {ped=ped, model=GetEntityModel(ped), frozen=IsEntityPositionFrozen(ped), active=true}
    local ok = pcall(function()
        FreezeEntityPosition(ped, true)
        local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
        local front = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.95, 0.0)
        state.camera = camera.startFreecam({playerPed=ped, coords=vector3(front.x,front.y,head.z),
            heading=(GetEntityHeading(ped)+180.0)%360.0, cameraHeight=0.0, cameraPitch=0.0, fov=38.0})
        if not state.camera then error('photo_camera_failed') end
    end)
    if not ok then World.stopPhoto(state); return nil end
    CreateThread(function()
        while state.active do
            if not World.exists(ped) or GetEntityModel(ped) ~= state.model then state.cancelled=true; World.stopPhoto(state); break end
            DisablePlayerFiring(PlayerId(), true)
            for _, control in ipairs({24,25,30,31,37,44,75,140,141,142}) do DisableControlAction(0,control,true) end
            HideHudAndRadarThisFrame()
            if IsControlJustPressed(0,200) then state.cancelled=true end
            Wait(0)
        end
    end)
    return state
end
function World.stopPhoto(state)
    if not state or not state.active then return end
    state.active = false
    if state.camera then pcall(pr_lib.fivem.editorCamera.stopFreecam, state.camera); state.camera = nil end
    if World.exists(state.ped) and GetEntityModel(state.ped) == state.model then FreezeEntityPosition(state.ped, state.frozen) end
end
