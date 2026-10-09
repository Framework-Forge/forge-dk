-- Pure mocks: no game entities, database, or live server changes.
dofile('shared/config.lua'); dofile('shared/schema.lua')
local checks, nativeCalls, existsError, blocked, cameraStopped = 0, 0, false, false, 0
local numericNativeResult = true
local function test(name, fn) fn(); checks=checks+1; print('PASS '..name) end
local entities={[1]=true,[2]=true}
DoesEntityExist=function(handle)
  nativeCalls=nativeCalls+1; if existsError then error('native failure') end
  local exists=entities[handle]==true
  if numericNativeResult then return exists and 1 or false end
  return exists
end
PlayerPedId=function() return 1 end; IsEntityAPed=function() return true end
GetGameTimer=function() return 1 end; GetEntityModel=function() return 123 end
GetPedBoneCoords=function(e) return {x=e,y=0,z=1} end
vector3=function(x,y,z) return {x=x,y=y,z=z} end
GetOffsetFromEntityInWorldCoords=function() return {x=5,y=6,z=7} end
GetEntityHeading=function() return 90 end
IsEntityPositionFrozen=function() return false end
local frozen, cameraOptions
FreezeEntityPosition=function(_,value) frozen=value end
CreateThread=function() end
pr_lib={cache={ped=1,remember=function(_,fn) return fn() end},raycast={fromCoords=function() return blocked, blocked and 99 or 0 end},
  fivem={editorCamera={isFreecamActive=function() return false end,
    startFreecam=function(options) cameraOptions=options; return {camera=9} end,
    stopFreecam=function() cameraStopped=cameraStopped+1 end}}}
dofile('client/world.lua'); local W=ForgeDK.World
test('malformed entity handles never enter the native',function()
  for _,value in ipairs({{},true,false,0,-1,1.5,math.huge,0/0,2147483648,'1'}) do assert(not W.exists(value)) end
  assert(nativeCalls==0); assert(W.exists(1)); assert(not W.exists(3))
end)
test('native failures are contained and ped lookup falls back safely',function()
  existsError=true; assert(not W.exists(1)); existsError=false
  pr_lib.cache.ped={}; assert(W.ped()==1); pr_lib.cache.ped=1
end)
test('entity checks accept native 1 and boolean true, reject 0/false/nil',function()
  assert(W.exists(1)); numericNativeResult=false; assert(W.exists(1)); assert(not W.exists(3)); numericNativeResult=true
  local native=DoesEntityExist
  for _,result in ipairs({0,false,2,'1'}) do DoesEntityExist=function() return result end; assert(not W.exists(1)) end
  DoesEntityExist=function() return nil end; assert(not W.exists(1)); DoesEntityExist=native
end)
test('placement uses bridge coordinates and heading, never invents missing heading',function()
  assert(W.placement({x=1,y=2,z=3,heading=65}).heading==65)
  local integerHeading=W.placement({x=1,y=2,z=3,heading=150})
  assert(integerHeading.heading==150 and math.type(integerHeading.heading)=='float')
  assert(W.placement({x=1,y=2,z=3,heading=-10}).heading==350)
  assert(W.placement({coords={x=1,y=2,z=3,w=80}}).heading==80)
  assert(W.placement({position={x=1,y=2,z=3},heading=0}).heading==0)
  assert(not W.placement({coords=12})); assert(not W.placement({x=1,y=2,z=3}))
  assert(not W.placement({x=0/0,y=2,z=3,heading=9}))
end)
test('LOS blocks walls for both adapters and can be disabled per service',function()
  blocked=true; assert(not W.canReach(2,true)); assert(W.canReach(2,false))
  blocked=false; assert(W.canReach(2,true)); assert(not W.canReach(999,false))
end)
test('photo camera frames the face through PR Bridge and restores freeze once',function()
  local scene=W.startPhoto(1); assert(scene and frozen)
  assert(cameraOptions.coords.z==1 and cameraOptions.heading==270 and cameraOptions.fov==38)
  W.stopPhoto(scene); assert(not frozen and cameraStopped==1); W.stopPhoto(scene); assert(cameraStopped==1)
end)
test('failed or conflicting camera does not leave the player frozen',function()
  pr_lib.fivem.editorCamera.active=true; assert(not W.startPhoto(1)); pr_lib.fivem.editorCamera.active=false
  pr_lib.fivem.editorCamera.startFreecam=function() error('camera unavailable') end
  assert(not W.startPhoto(1)); assert(not frozen)
end)
print(('Forge DK world: %d scenarios passed'):format(checks))
