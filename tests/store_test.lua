dofile('shared/config.lua'); dofile('shared/schema.lua')
local affected, calls = 2, {}
json = { encode=function() return '{}' end }
pr_lib = { database={ query=function(sql,args) calls[#calls+1]={sql,args}; return {} end,
    update=function(sql,args) calls[#calls+1]={sql,args}; return affected end,
    transaction=function(ops) calls[#calls+1]=ops; return true end } }
dofile('server/store.lua'); local Store=ForgeDK.Store
assert(Store.initialize() and #calls==2)
local r={new=true,serial='s',owner='o',typeKey='d',subject='o',scope='x',kind='official',createdAt=1,expiresAt=0,snapshot={}}
assert(Store.reserve(r,{copyId='c'},100,'cash')); assert(#calls[#calls]==2)
assert(Store.delivered(r,{copyId='c'})); assert(calls[#calls][1]:find("c.status = 'delivering'",1,true))
assert(calls[#calls][1]:find("d.status IN ('pending', 'valid')",1,true))
affected=0; assert(not Store.delivered(r,{copyId='c'}))
assert(not Store.stage('c','delivered')); Store.pending('s'); assert(calls[#calls][1]:find("NOT IN ('delivered', 'failed')",1,true))
print('Forge DK store: 6 assertions passed (SQL contracts, no live database)')
