-- Run after service_test.lua in the same isolated Lua runtime.
local callbacks, exportsMap, invoking, clock = {}, {}, 'untrusted', 1000
GetInvokingResource=function() return invoking end
GetGameTimer=function() clock=clock+1000; return clock end
CreateThread=function() end; AddEventHandler=function() end
pr_lib.cache.get=function(_,fallback) return fallback end
pr_lib.cache.set=function() end
pr_lib.cache.clear=function() end; pr_lib.cache.clearPrefix=function() end
pr_lib.ace.isPrincipalAceAllowed=function() return false end
pr_lib.callback={register=function(name,cb) callbacks[name]=cb end}
pr_lib.locale=function() return {getAll=function() return {} end} end
pr_lib.addExports=function(name,cb) exportsMap[name]=cb end
pr_lib.addCommand=function(_,properties) assert(type(properties.canAccess)=='function') end
dofile('server/init.lua')
local ok,err=exportsMap.CanIssueDocument(1,'id_card'); assert(not ok and err=='resource_not_authorized')
invoking='forge-core'; assert(exportsMap.CanIssueDocument(1,'id_card'))
ok,err=callbacks['forge-dk:server:admin'](2); assert(not ok and err=='no_permission')
assert(callbacks['forge-dk:server:admin'](1))
ok,err=callbacks['forge-dk:server:permission'](2,{target=1,typeKey='weapon_license',enabled=true}); assert(not ok and err=='no_permission')
assert(exportsMap.RegisterSubjectValidator('vehicle',function() return true end))
assert(ForgeDK.Service.validators.vehicle.resource=='forge-core')
assert(type(exportsMap.RevokeDocument)=='function' and type(exportsMap.GetDeliveryReceipts)=='function')
invoking='untrusted'; ok,err=exportsMap.GetDocumentItems(); assert(not ok and err=='resource_not_authorized')
invoking='qbx_core'; local classified; ok,classified=exportsMap.GetDocumentItems(); assert(ok and classified.id_card and classified.weaponlicense)
ForgeDK.Service.initialized=false; ok,err=exportsMap.GetDocumentItems(); assert(not ok and err=='starting'); ForgeDK.Service.initialized=true
print('Forge DK exports: 11 access-control assertions passed')
