dofile('shared/config.lua'); dofile('shared/schema.lua')
local messages, callbacks, netEvents, handlers, timers, removed, focusCalls = {}, {}, {}, {}, {}, {}, 0
local state={invBusy=false}; state.set=function(self,key,v) self[key]=v end; LocalPlayer={state=state}
local time, attachment, animation, stopCount = 1, nil, nil, 0
GetGameTimer=function() time=time+1; return time end
GetCurrentResourceName=function() return 'forge-dk' end
CreateThread=function() end
RegisterNetEvent=function(name,cb) netEvents[name]=cb end
AddEventHandler=function(name,cb) handlers[name]=cb end
vector3=function(x,y,z) return {x=x,y=y,z=z} end
GetEntityCoords=function() return vector3(0,0,0) end
GetPedBoneIndex=function(_,bone) assert(bone==57005); return 1 end
AttachEntityToEntity=function(...) attachment={...} end
StopAnimTask=function() stopCount=stopCount+1 end
GetPedDrawableVariation=function() return 5 end; GetPedTextureVariation=function() return 2 end
GetPedPaletteVariation=function() return 1 end
local mask, unregistered = {}, 0
SetPedComponentVariation=function(_,_,d,t,p) mask={d,t,p} end
RegisterPedheadshotTransparent=function() return 9 end
RegisterPedheadshot_3=function() return 10 end
IsPedheadshotReady=function() return true end; IsPedheadshotValid=function() return true end
GetPedheadshotTxdString=function() return 'txd' end
UnregisterPedheadshot=function() unregistered=unregistered+1 end
-- FiveM's generic BOOL wrapper can return native integer 1, not Lua true.
DoesEntityExist=function() return 1 end
PlayerPedId=function() return 1 end; IsEntityAPed=function() return true end
IsEntityDead=function() return false end; IsPedInAnyVehicle=function() return false end
GetEntityModel=function() return 123 end; GetEntityHeading=function() return 90 end
GetPedBoneCoords=function() return vector3(0,0,1) end
GetOffsetFromEntityInWorldCoords=function() return vector3(0,1,1) end
IsEntityPositionFrozen=function() return false end; FreezeEntityPosition=function() end
Wait=function() end
local photoHandler, keybind
local interactions, targets, targetRemoved, cameraStopped, transforms = {}, {}, 0, 0, {}
pr_lib={
    nui={focus=function() focusCalls=focusCalls+1 end,
        register=function(name,handler) callbacks[name]=handler end,
        send=function(action,data)
            messages[#messages+1]={action=action,data=data}
            if action=='forge-dk:photo' then callbacks.photoResolved({token=data.token,image='png'},function() end) end
        end},
    cache={ped=1,serverId=1,remember=function(_,fn) return fn() end},
    raycast={fromCoords=function() return false,0 end},
    callback={register=function(_,cb) photoHandler=cb end,await=function(name)
        if name:find('configuration') or name:find('admin') then return true,{config=ForgeDK.Config.default,translations={}} end
        return true,{}
    end},
    fivem={streaming={createObject=function() return 88 end,createPed=function(_,_,heading)
        assert(math.type(heading)=='float', 'NPC heading must be a float at the native boundary'); return 99 end,
        setEntityTransform=function(entity,coords,heading,options)
            assert(math.type(heading)=='float')
            assert(options.noOffset==false, 'NPC surface coordinates must use the same ped-origin adjustment as the PR Bridge preview')
            transforms[#transforms+1]={entity=entity,coords=coords,heading=heading}; return true end,
        deleteEntity=function(id) removed[id]=true end,playAnim=function(anim) assert(anim.wait==false); animation=anim; return true end},
        editorCamera={isFreecamActive=function() return false end,startFreecam=function() return {} end,
            stopFreecam=function() cameraStopped=cameraStopped+1 end}},
    timer=function(duration,cb) local value={duration=duration,cb=cb,forceEnd=function() end}; timers[#timers+1]=value; return value end,
    interact={AddLocalEntityInteraction=function(data) interactions[#interactions+1]=data; return 'npc' end,RemoveInteraction=function() end},
    target={addLocalEntity=function(_,data) targets[#targets+1]=data end,removeLocalEntity=function() targetRemoved=targetRemoved+1 end},
    addKeybind=setmetatable({remove=function(name) assert(name=='forge-dk:close') end},{__call=function(_,data) keybind=data end}),
    addExports=function() end,waitFor=function(fn) assert(fn()) end,
    devtools={placePed=function(_,_,cb) cb({coords={x=1,y=2,z=3},heading=55}); return true end,stop=function() end},
}
dofile('client/world.lua')
dofile('client/init.lua')
callbacks.loaded({},function(result) assert(result.ok) end)
netEvents['forge-dk:client:document']({animation=true,prop='prop_franklin_dl'},1,1,10000)
assert(not state.invBusy and messages[#messages].action=='forge-dk:document')
assert(attachment[4]==0.1493 and attachment[7]==80.900 and attachment[14]==2)
assert(animation.flags==49 and animation.duration==2500)
callbacks.close({},function() end); assert(not state.invBusy)
for _,style in ipairs({'police','citizen'}) do
    for _,format in ipairs({'card','a4'}) do
        netEvents['forge-dk:client:document']({animation=true,format=format,presentationStyle=style},1,1,6000)
        local preset=ForgeDK.Presentations[style][format]
        assert(animation.dict==preset.dict and animation.clip==preset.anim and animation.flags==preset.flags)
        assert(attachment[4]==preset.pos[1] and attachment[6]==preset.pos[3] and attachment[9]==preset.rot[3])
        local displayTimer,animTimer=timers[#timers-1],timers[#timers]
        assert(displayTimer.duration==6000 and animTimer.duration==2500 and animation.duration==2500)
        local count=#messages; animTimer.cb()
        assert(removed[88] and not state.invBusy and #messages==count and messages[#messages].action=='forge-dk:document')
        displayTimer.cb(); assert(messages[#messages].action=='forge-dk:close')
    end
end
assert(stopCount==5)
netEvents['forge-dk:client:document']({animation=true,animationMs=1500},1,1,30000)
local displayTimer,earlyTimer=timers[#timers-1],timers[#timers]
assert(displayTimer.duration==30000 and earlyTimer.duration==1500)
netEvents['forge-dk:client:document']({animation=true,animationMs=1800},1,1,20000)
local stops=stopCount; earlyTimer.cb(); assert(stopCount==stops, 'old animation cleanup must not stop a newer presentation')
callbacks.close({},function() end)
netEvents['forge-dk:client:document']({animation=false},1,1,0)
local oldTimer=timers[#timers]; netEvents['forge-dk:client:admin'](); oldTimer.cb()
assert(messages[#messages].action=='forge-dk:admin', 'a stale presentation timer must not close the admin panel')
callbacks.close({},function() end)
state.invBusy=true; netEvents['forge-dk:client:admin'](); callbacks.close({},function() end); assert(state.invBusy)
assert(photoHandler()=='png' and unregistered==1 and mask[1]==5 and mask[2]==2 and mask[3]==1)
assert(cameraStopped==1 and messages[#messages].action=='forge-dk:suspend' and messages[#messages].data.hidden==false)
netEvents['forge-dk:client:admin']()
callbacks.placeNpc({model='a_m_m_business_01',npcId='official'},function(result) assert(result.ok) end)
assert(messages[#messages-1].action=='forge-dk:placement' and messages[#messages-1].data.heading==55)
assert(messages[#messages-1].data.npcId=='official' and state.invBusy)
local placement
pr_lib.devtools.placePed=function(_,_,cb,options) placement=cb; assert(options.heading==72 and math.type(options.heading)=='float' and options.confirmOnPlace); return true end
callbacks.placeNpc({model='ped',npcId='test',heading=72},function(result) assert(result.ok) end)
assert(messages[#messages].data.hidden and state.invBusy)
placement(nil); assert(messages[#messages].data.hidden==false and state.invBusy)
callbacks.placeNpc({model='ped',heading=72},function(result) assert(result.ok) end)
callbacks.close({},function() end); local count=#messages; placement({x=1,y=2,z=3,heading=99}); assert(#messages==count)
netEvents['forge-dk:client:admin']()
pr_lib.devtools.placePed=function() error('editor failure') end
callbacks.placeNpc({model='ped'},function(result) assert(not result.ok) end)
assert(messages[#messages].data.hidden==false)
callbacks.close({},function() end); state.invBusy=false
local c=ForgeDK.Schema.clone(ForgeDK.Config.default)
c.npcs={{id='one',model='ped',enabled=true,coords={x=1,y=2,z=3},heading=5,distance=2,label='One',interaction='interact',wallDetection=true}}
netEvents['forge-dk:client:configuration'](c)
assert(transforms[#transforms].heading==5 and transforms[#transforms].coords.x==1)
assert(transforms[#transforms].coords.z==3 and c.npcs[1].coords.z==3, 'saved surface Z must remain unchanged')
assert(interactions[1].wallDetection and interactions[1].options[1].canInteract())
pr_lib.raycast.fromCoords=function() return true,999 end; assert(not interactions[1].options[1].canInteract())
c.npcs[1].interaction='target'; netEvents['forge-dk:client:configuration'](c)
assert(targets[1][1].wallDetection and not targets[1][1].canInteract())
c.npcs[1].wallDetection=false; c.npcs[1].heading=150; c.npcs[1].coords.z=84.08; netEvents['forge-dk:client:configuration'](c)
assert(transforms[#transforms].heading==150 and math.type(transforms[#transforms].heading)=='float')
assert(transforms[#transforms].coords.z==84.08 and c.npcs[1].coords.z==84.08)
assert(targets[2][1].ignoreLos and targets[2][1].canInteract() and targetRemoved==1)
Wait=function() callbacks.close({},function() end) end
assert(photoHandler()==nil and cameraStopped==2)
handlers.onResourceStop('forge-dk'); assert(removed[88])
assert(targetRemoved==2)
print('Forge DK client: lifecycle, current-preview placement/surface Z/float heading 150, cancellation/failure, cinematic cancellation and both LOS adapters passed')
