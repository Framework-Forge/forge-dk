-- Lua 5.4, run from forge-dk. No database, framework or inventory writes.
local total = 0
local function test(name, fn) fn(); total = total + 1; print('PASS ' .. name) end
dofile('shared/config.lua'); dofile('shared/schema.lua')
local S = ForgeDK.Schema
local players, slots, handlers, events, cache = {}, {}, {}, {}, {}
local rows, copies, queries, nextToken, balance = {}, {}, 0, 0, 10000
local addFails, addThrows, refundFails, commitFails, removeFails, staleSource, allowCarry = false, false, false, false, false, false, true
local player = { citizenid = 'OWNER', charinfo = { firstname = 'Pierre', lastname = 'Moraes', birthdate = '1990-01-01', gender = 0 },
    metadata = { licences = { id = true, driver = true, weapon = false }, skills = { test = 4 } } }
players[1] = player
local items = { id_card = { stack = false, consume = 0 }, weaponlicense = { stack = false, consume = 0 }, cnh_a = { stack = false } }
local vec = {}; vec.__sub = function(a, b) return setmetatable({ x=a.x-b.x, y=a.y-b.y, z=a.z-b.z }, vec) end
vec.__len = function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
vector3 = function(x,y,z) return setmetatable({x=x,y=y,z=z},vec) end
GetPlayerPed = function(id) return players[id] and id or 0 end
GetPlayerRoutingBucket = function() return 0 end
GetPlayers = function() return { '1', '2' } end
local encoded, n = {}, 0
json = { encode = function(v) n=n+1; local key='json'..n; encoded[key]=S.clone(v); return key end,
    decode = function(key) return S.clone(encoded[key]) end }
pr_lib = { framework = {
    GetIdentifier = function(id) return staleSource and 'DIFFERENT' or players[id] and players[id].citizenid end,
    GetPlayerData = function(id) return players[id] end,
    GetCoords = function() return vector3(0,0,0) end,
    setPlayerMetadata = function(id, key, value) players[id].metadata[key] = S.clone(value); return true end,
    getPlayerMoney = function() return balance end,
    removePlayerMoney = function(_,_,amount) if balance < amount then return false end; balance=balance-amount; return true end,
    addPlayerMoney = function(_,_,amount) if refundFails then return false end; balance=balance+amount; return true end,
}, inventory = {
    Items = function(name) return name and items[name] or items end,
    CanCarryItem = function() return allowCarry end,
    AddItem = function(_,name,_,metadata)
        if addThrows then error('uncertain inventory outcome') end
        if addFails then return false end
        slots[1] = { name = name, slot = 1, metadata = S.clone(metadata) }; return true
    end,
    RemoveItem = function() if removeFails then return false end; slots[1]=nil; return true end,
    GetSlot = function(_,slot) return slots[slot] end,
    RegisterUsableItem = function(name, handler) handlers[name]=handler; return true end,
}, cache = { get=function(key) return cache[key] end, set=function(key,v) cache[key]=v end },
    ace = { isPlayerAceAllowed=function(id) return id == 1 end },
    string = { random = function() nextToken=nextToken+1; return 'token'..nextToken end },
    triggerClientEvent = function(...) events[#events+1]={...} end,
    loadJsonRecovery=function() return nil end, saveJsonRecovery=function() return true end,
    notify = { NotifyPlayer = function() end },
}
ForgeDK.Store = { ready = true,
    scope = function(scope) queries=queries+1; return rows[scope] end,
    pending = function(serial)
        queries=queries+1
        for _,c in pairs(copies) do if c.serial==serial and c.status~='failed' and c.status~='delivered' then return c end end
    end,
    reserve = function(r,s,fee,account)
        if r.new then rows[r.scope]={ serial=r.serial, owner_identifier=r.owner, status='pending', copies=0,
            created_at=r.createdAt, expires_at=r.expiresAt, snapshot=json.encode(s), kind=r.kind, type_key=r.typeKey } end
        copies[s.copyId]={ serial=r.serial, status='reserved', snapshot=json.encode(s), fee=fee, account=account,
            owner_identifier=r.owner, kind=r.kind, document_status='valid', expires_at=r.expiresAt, type_key=r.typeKey }; return true
    end,
    stage = function(id,stage) copies[id].status=stage; return true end,
    delivered = function(r,s)
        if commitFails then return false end
        local row=rows[r.scope]; row.status='valid'; row.copies=row.copies+1; row.snapshot=json.encode(s)
        copies[s.copyId].status='delivered'; return true
    end,
    failed = function(id) copies[id].status='failed' end,
    copy = function(id) queries=queries+1; return copies[id] end,
}
ForgeDK.Lang = { t = function(_,key) return key end }
dofile('server/service.lua')
local V = ForgeDK.Service; V.initialize()
local photo = 'data:image/png;base64,iVBORw0KGgoAAAA'
local function issue(key, extra)
    local request = { typeKey=key or 'id_card', photo=photo, account='bank' }
    for k,v in pairs(extra or {}) do request[k]=v end
    return V.issue(1,request,true)
end
local function clear()
    rows,copies,slots={}, {}, {}; balance=10000
    addFails,addThrows,refundFails,commitFails,removeFails,staleSource,allowCarry=false,false,false,false,false,false,true
end
test('ID free access; weapon requires legacy authorization',function()
    assert(V.canIssue(1,'id_card')); local ok,err=V.canIssue(1,'weapon_license'); assert(not ok and err=='authorization_required')
end)
test('schema rejects duplicate item bindings and malformed NPCs',function()
    local c=S.clone(ForgeDK.Config.default); c.types.weapon_license.item='id_card'; assert(not S.configuration(c))
    c=S.clone(ForgeDK.Config.default); c.npcs={{id='npc',model='ped',coords={x=0,y=0}}}; assert(not S.configuration(c))
end)
test('date masks normalize server-side and reject invalid calendar dates',function()
    assert(S.date('10/05/1991')=='1991-05-10' and S.date('1991-05-10')=='1991-05-10')
    assert(S.date('29/02/2000')=='2000-02-29')
    for _,v in ipairs({'29/02/1900','31/04/2026','00/01/2026','01/01/0000','1/1/2026'}) do assert(not S.date(v)) end
    local d={fields={{key='date',label='Data',type='date',source='input'}}}
    assert(S.fields(d,{}, {date='10/05/1991'},false)[1].value=='1991-05-10')
    assert(not S.fields(d,{}, {date='31/04/2026'},false))
end)
test('NPC adapters and wall blocking migrate safely and persist separately',function()
    local c=S.clone(ForgeDK.Config.default)
    c.npcs={{id='desk',model='ped',coords={x=1,y=2,z=3},heading=75}}
    local normalized=assert(S.configuration(c)); assert(normalized.npcs[1].interaction=='interact' and normalized.npcs[1].wallDetection)
    c.npcs[1].interaction='target'; c.npcs[1].wallDetection=false
    normalized=assert(S.configuration(c)); assert(normalized.npcs[1].interaction=='target' and not normalized.npcs[1].wallDetection and normalized.npcs[1].heading==75)
end)
test('seal image validation and public visual snapshot separation',function()
    assert(S.pngAsset('images/seal.png')=='images/seal.png'); assert(S.pngAsset('images/../secret.png')=='')
    assert(S.pngAsset('javascript:alert(1)')==''); assert(S.pngAsset('data:image/svg+xml;base64,AAAA')=='')
    assert(S.pngAsset(photo)==photo)
    local a={stampImage='images/seal.png',forgedStampImage='images/fake.png',forgedStampText='F0rge'}
    local official,fake=S.visualAppearance(a,false),S.visualAppearance(a,true)
    assert(official.stampImage=='images/seal.png' and fake.stampImage=='images/fake.png')
    assert(not official.forgedStampImage and not fake.forgedStampText and fake.stampText=='F0rge')
    assert(official.stampStyle=='double' and fake.stampStyle=='single' and a.forgedStampImage=='images/fake.png')
end)
test('non-finite numbers and identity input spoofing rejected',function()
    local d=S.clone(V.config.types.id_card); d.fields={{key='id',label='ID',source='identity',type='text'}}
    assert(S.fields(d,player.charinfo,{id='SPOOF'},false)[1].value=='')
    d.fields={{key='foo',label='Foo',source='identity',type='text'}}; assert(not S.document(d))
    d.fields={{key='a',label='A',source='input',type='number'}}; assert(not S.fields(d,{}, {a='1e9999'},false))
end)
test('metadata migration preserves licences and unrelated skills',function()
    V.seed(1); assert(player.metadata.licences.id and player.metadata.licences.driver)
    assert(player.metadata.skills.test==4 and player.metadata.documents.schemaVersion==1)
end)
test('category grants enable master; revocation preserves siblings',function()
    local d=S.clone(V.config.types.id_card); d.key='cnh_a'; d.item='cnh_a'; d.requiresAuthorization=true
    d.permissionSource='licences'; d.permissionKey='driver'; d.category='A'; V.config.types.cnh_a=d
    assert(not V.canIssue(1,'cnh_a')); assert(V.permission(1,'cnh_a',true)); assert(V.canIssue(1,'cnh_a'))
    assert(V.permission(1,'cnh_a',true,'B')); assert(V.permission(1,'cnh_a',false))
    assert(not V.canIssue(1,'cnh_a') and player.metadata.licences.driver and player.metadata.documents.categories.driver.B)
    V.config.types.cnh_a=nil
end)
test('first issuance stores snapshot and verifies it',function()
    clear(); local ok,s=issue(); assert(ok and s.identity.id=='OWNER' and s.copyNumber==1)
    assert(V.verify(slots[1].metadata)); assert(balance==10000)
end)
test('second issuance fee comes from registry, not item possession',function()
    slots={}; local ok,s=issue(); assert(ok and s.copyNumber==2 and balance==9900)
end)
test('copied snapshot with edited identity fails verification',function()
    local fake=S.clone(slots[1].metadata); fake.document.identity.id='OTHER'; local ok,err=V.verify(fake); assert(not ok and err=='altered')
end)
test('showing item snapshots never queries registry and preserves owner',function()
    players[2]={citizenid='HOLDER',charinfo=player.charinfo,metadata={}}
    local before=queries; assert(V.present(2,1,true)); assert(queries==before)
    assert(events[#events][3].identity.id=='OWNER' and #events[#events][2]==2)
end)
test('inactive template still allows already issued document to be shown',function()
    local before=queries; V.config.types.id_card.active=false; handlers.id_card(1,{slot=1}); assert(queries==before)
    V.config.types.id_card.active=true
end)
test('blank item is not silently rewritten with holder identity',function()
    slots[1]={name='id_card',slot=1,metadata={}}; assert(not V.documentItem(1,1)); handlers.id_card(1,{slot=1}); assert(not slots[1].metadata.document)
end)
test('forgery must be enabled and never grants permission',function()
    clear(); local ok,err=issue('weapon_license',{forged=true}); assert(not ok and err=='forgery_disabled')
    V.config.types.weapon_license.allowForgery=true; V.config.types.weapon_license.forgeableIdentity={firstName=true}
    ok=issue('weapon_license',{forged=true,fields={firstName='Fake',id='SPOOF'}}); assert(ok)
    assert(not player.metadata.licences.weapon and slots[1].metadata.document.identity.firstName=='Fake')
    assert(slots[1].metadata.document.identity.id=='OWNER'); local valid,why=V.verify(slots[1].metadata); assert(not valid and why=='forged')
end)
test('forgery does not count as official first issuance',function()
    assert(V.permission(1,'weapon_license',true)); local before=balance; local ok,s=issue('weapon_license')
    assert(ok and s.copyNumber==1 and before-balance==100)
end)
test('authorization is checked again after reservation',function()
    clear(); local reserve=ForgeDK.Store.reserve
    ForgeDK.Store.reserve=function(...) local ok=reserve(...); player.metadata.licences.weapon=false; return ok end
    local ok,err=issue('weapon_license'); assert(not ok and err=='authorization_required' and balance==10000)
    ForgeDK.Store.reserve=reserve
end)
test('missing or disabled inventory item blocks issue',function()
    items.id_card.disabled=true; local ok,err=issue(); assert(not ok and err=='document_unavailable'); items.id_card.disabled=nil
end)
test('missing required photo blocks before reservation',function()
    clear(); local ok,err=issue('id_card',{photo=''}); assert(not ok and err=='photo_required' and next(copies)==nil)
end)
test('inventory full blocks before debit',function()
    clear(); allowCarry=false; local ok,err=issue(); assert(not ok and err=='inventory_full' and balance==10000)
end)
test('insufficient balance blocks before delivery',function()
    clear(); balance=0; local ok,err=issue('weapon_license',{forged=true}); assert(not ok and err=='insufficient_funds' and not slots[1])
end)
test('failed AddItem refunds exactly and retries first issuance',function()
    clear(); addFails=true; local ok,err=issue('weapon_license',{forged=true}); assert(not ok and err=='inventory_full' and balance==10000)
    for _,c in pairs(copies) do assert(c.status=='failed') end
end)
test('uncertain inventory exception blocks retry with receipt',function()
    clear(); player.metadata.licences.weapon=true; addThrows=true; local ok,err=issue('weapon_license')
    assert(not ok and err=='delivery_pending'); addThrows=false; ok,err=issue('weapon_license'); assert(not ok and err=='delivery_pending' and balance==9900)
end)
test('failed registry commit removes item and refunds',function()
    clear(); commitFails=true; local ok,err=issue('weapon_license'); assert(not ok and err=='database_unavailable' and balance==10000 and not slots[1])
end)
test('failed compensation retains pending receipt',function()
    clear(); commitFails=true; removeFails=true; local ok,err=issue('weapon_license'); assert(not ok and err=='delivery_pending' and balance==9900)
end)
test('source reuse cannot debit another character',function()
    clear(); local reserve=ForgeDK.Store.reserve
    ForgeDK.Store.reserve=function(...) local ok=reserve(...); staleSource=true; return ok end
    local ok,err=issue('weapon_license'); assert(not ok and err=='session_expired' and balance==10000)
    ForgeDK.Store.reserve=reserve; staleSource=false
end)
test('vehicle and business require trusted ownership validators',function()
    clear(); local d=V.config.types.id_card; d.subject='vehicle'; local ok,err=issue('id_card',{subjectKey='ABC1234'})
    assert(not ok and err=='subject_provider_required'); V.validators.vehicle={callback=function(_,key) return key=='OWNED' end}
    ok,err=issue('id_card',{subjectKey='OTHER'}); assert(not ok and err=='subject_not_authorized')
    assert(issue('id_card',{subjectKey='OWNED'})); d.subject='person'
end)
test('database offline rejects issue but still shows item',function()
    ForgeDK.Store.ready=false; local ok,err=issue(); assert(not ok and err=='database_unavailable'); assert(V.present(1,1,false)); ForgeDK.Store.ready=true
end)
test('expired and revoked official registrations block reissue',function()
    clear(); assert(issue()); local row=next(rows) and select(2,next(rows)); row.status='revoked'; local ok,err=issue(); assert(not ok and err=='document_revoked')
    row.status='valid'; row.expires_at=os.time()-1; ok,err=issue(); assert(not ok and err=='document_expired')
end)
test('concurrent owner operations are rejected',function()
    V.locks.OWNER=true; local ok,err=issue(); assert(not ok and err=='busy'); V.locks.OWNER=nil
end)
test('admin save enforces permission and revision',function()
    local ok,err=V.save(2,V.public()); assert(not ok and err=='no_permission')
    local c=V.public(); c.revision=999; ok,err=V.save(1,c); assert(not ok and err=='revision_conflict')
    c=V.public(); assert(V.save(1,c)); assert(V.config.revision==2)
end)
test('client cannot forge without a nearby forged service',function()
    clear(); local ok,err=V.issue(1,{typeKey='weapon_license',forged=true,photo=photo},false); assert(not ok and err=='session_expired')
end)
test('quoted fee is mandatory for NPC requests',function()
    V.config.npcs={{id='npc',enabled=true,mode='official',coords={x=0,y=0,z=0},distance=2,services={'id_card'}}}
    local ok,data=V.open(1,'npc'); assert(ok)
    cache['forge-dk:session:1'].photo=photo
    local request={typeKey='id_card',nonce=data.nonce,expectedFee=999}; ok,data=V.issue(1,request,false)
    assert(not ok and data=='quote_changed' and balance==10000)
end)
test('document catalogue includes disabled types and preserves registered bindings',function()
    local definition=S.clone(V.config.types.id_card); definition.item='custom_document'; definition.active=false
    V.config.types.custom_document=definition; V.registered.previous_document=true
    local ok,items=V.documentItems()
    assert(ok and items.id_card and items.weaponlicense and items.custom_document and items.previous_document and not items.water)
    items.id_card=nil; assert(select(2,V.documentItems()).id_card, 'return an isolated item set')
    V.config.types.custom_document=nil; V.registered.previous_document=nil
end)
test('issued forgeries select the configured fake PNG and validate masked birth dates',function()
    clear(); player.metadata.licences.weapon=false; local d=V.config.types.weapon_license
    d.appearance.stampImage='images/seal.png'; d.appearance.forgedStampImage='images/fake.png'; d.forgeableIdentity.dob=true
    local ok,err=issue('weapon_license',{forged=true,fields={dob='31/04/2026'}})
    assert(not ok and err=='invalid_field:dob' and balance==10000)
    local snapshot; ok,snapshot=issue('weapon_license',{forged=true,fields={dob='10/05/1991'}})
    assert(ok and snapshot.identity.dob=='1991-05-10' and snapshot.appearance.stampImage=='images/fake.png')
    assert(not snapshot.appearance.forgedStampImage and not snapshot.appearance.forgedStampText)
    assert(not player.metadata.licences.weapon and not V.verify(slots[1].metadata))
end)
test('layout, pattern, heading and presentation settings validate and migrate old definitions',function()
    local c=S.clone(ForgeDK.Config.default); c.general.popupMs=0
    local d=c.types.id_card
    d.layout={card={id={x=200,y=-10,width=1000,fontSize=99,align='evil'},['field:purpose']={x=5,y=6,width=30}},a4={stamp={x=70,y=80,width=15}}}
    d.presentationStyle='citizen'; d.appearance.patternStyle='guilloche'; d.appearance.headerTitle='IRG'; d.appearance.stampText='Original'
    local normalized=assert(S.configuration(c)); d=normalized.types.id_card
    assert(normalized.general.popupMs==5000 and d.presentationStyle=='citizen')
    assert(d.layout.card.id.x==98 and d.layout.card.id.width==2 and d.layout.card.id.y==0 and d.layout.card.id.fontSize==8)
    assert(d.layout.card.id.align=='left' and d.layout.a4.stamp.x==70 and d.layout.card['field:purpose'].y==6)
    assert(d.appearance.patternStyle=='guilloche' and S.visualAppearance(d.appearance,false).stampText=='Original')
    local old=assert(S.document(ForgeDK.Config.default.types.id_card)); assert(old.layout.card and old.presentationStyle=='police')
    for _,style in ipairs({'police','citizen'}) do
        for _,format in ipairs({'card','a4'}) do
            local p=S.presentation({presentationStyle=style,format=format})
            assert(p.bone==57005 and p.rotationOrder==2)
            assert(p.model==(format=='a4' and 'h4_prop_h4_files_paper_01b' or 'prop_franklin_dl'))
        end
    end
end)
test('using an item automatically presents nearby without querying or rewriting the registry snapshot',function()
    clear(); local ok,issued=issue(); assert(ok)
    local d=V.config.types.id_card; local previous=S.clone(d)
    d.appearance.stampText='Original'; d.appearance.headerTitle='IRG'; d.appearance.stampImage='images/current.png'
    d.layout.card.stamp={x=55,y=70,width=12}; d.presentationStyle='citizen'; d.body='Current template'
    local before=queries; handlers.id_card(1,{slot=1}); assert(queries==before)
    local event=events[#events]; assert(#event[2]==2 and event[6]==10000)
    assert(event[3].appearance.stampImage=='images/current.png' and event[3].appearance.stampText=='Original')
    assert(event[3].identity.id==issued.identity.id and event[3].layout.card.stamp.x==55 and event[3].body=='Current template')
    assert(event[3].presentationStyle=='citizen' and not slots[1].metadata.document.layout.card.stamp)
    assert(V.verify(slots[1].metadata)); V.config.types.id_card=previous
end)
test('automatic presentation respects range and routing bucket while preserving custom field values',function()
    clear(); local d=V.config.types.id_card
    d.fields={{key='purpose',label='Old heading',source='input',type='text',default='Recorded value'}}
    local ok=issue(); assert(ok); d.fields[1].label='New heading'
    local oldPlayers,oldCoords,oldBucket=GetPlayers,pr_lib.framework.GetCoords,GetPlayerRoutingBucket
    GetPlayers=function() return {'1','2','3','4'} end
    players[3]=players[2]; players[4]=players[2]
    pr_lib.framework.GetCoords=function(id) return vector3(id==3 and 4 or id==2 and 2.9 or 0,0,0) end
    GetPlayerRoutingBucket=function(id) return id==4 and 5 or 0 end
    local before=queries; assert(V.present(1,1,true)); assert(queries==before)
    local event=events[#events]; assert(#event[2]==2 and event[2][2]==2)
    assert(event[3].fields[1].label=='New heading' and event[3].fields[1].value=='Recorded value')
    assert(slots[1].metadata.document.fields[1].label=='Old heading' and V.verify(slots[1].metadata))
    GetPlayers,pr_lib.framework.GetCoords,GetPlayerRoutingBucket=oldPlayers,oldCoords,oldBucket
    players[3],players[4]=nil,nil; d.fields={}
end)
test('forged appearance and independent timing persist safely without changing official documents',function()
    local raw=S.clone(V.config.types.id_card); raw.allowForgery=true
    raw.animationMs=1500; raw.displayMs=30000
    raw.appearance.emblemImage='images/logo.png'; raw.appearance.fontFamily='sans'
    raw.appearance.forged={enabled=true,background='#eeddbc',text='#333333',fontFamily='serif',emblemImage='images/fake-logo.png',patternStyle='waves'}
    local d=assert(S.document(raw)); assert(d.animationMs==1500 and d.displayMs==30000)
    local normal,fake=S.visualAppearance(d.appearance,false),S.visualAppearance(d.appearance,true)
    assert(normal.background==raw.appearance.background and fake.background=='#eeddbc' and fake.text=='#333333')
    assert(fake.fontFamily=='serif' and normal.fontFamily=='sans' and fake.emblemImage=='images/fake-logo.png')
    assert(not normal.forged and not fake.forged and fake.patternStyle=='waves')
    local previous=V.config.types.id_card; V.config.types.id_card=d; clear()
    local ok,snapshot=issue('id_card',{forged=true}); assert(ok and snapshot.appearance.background=='#eeddbc' and not snapshot.appearance.forged)
    local before=queries; assert(V.present(1,1,true)); assert(queries==before)
    assert(events[#events][6]==30000 and events[#events][3].animationMs==1500)
    assert(events[#events][3].appearance.emblemImage=='images/fake-logo.png')
    raw.appearance.forged.fontFamily='url(evil)'; raw.appearance.emblemImage='javascript:evil'
    local sanitized=assert(S.document(raw)); assert(sanitized.appearance.fontFamily=='sans' and sanitized.appearance.forged.fontFamily=='sans')
    assert(sanitized.appearance.emblemImage=='')
    raw.animationMs=90000; raw.displayMs=1; sanitized=assert(S.document(raw)); assert(sanitized.animationMs==10000 and sanitized.displayMs==1000)
    assert(S.document(ForgeDK.Config.default.types.id_card).displayMs==0)
    V.config.types.id_card=previous
end)
test('deletion requires permission, persists historical items and never deletes registrations or metadata',function()
    local function same(a,b)
        if type(a)~='table' then return a==b end
        if type(b)~='table' then return false end
        for k,v in pairs(a) do if not same(v,b[k]) then return false end end
        for k in pairs(b) do if a[k]==nil then return false end end
        return true
    end
    local previous=S.clone(V.config); clear(); assert(issue())
    local rowBefore,copiesBefore,metadataBefore=S.clone(rows),S.clone(copies),S.clone(slots[1].metadata)
    local before=queries; local draft=V.public(); draft.types.id_card=nil
    draft.npcs[1].services={'weapon_license'}; draft.npcs[1].heading=150; draft.npcs[1].model='a_m_m_business_01'
    draft.retiredItems={water=true} -- Clients cannot write the server-owned historical item set.
    local ok,err=V.save(2,draft); assert(not ok and err=='no_permission' and V.config.types.id_card)
    local saveRecovery=pr_lib.saveJsonRecovery
    pr_lib.saveJsonRecovery=function() return false,'save_failed' end
    ok,err=V.save(1,draft); assert(not ok and err=='save_failed' and V.config.types.id_card and not V.saving)
    local written
    pr_lib.saveJsonRecovery=function(_,data) written=S.clone(data); return true end
    assert(V.save(1,draft)); assert(not V.config.types.id_card and V.config.retiredItems.id_card and not V.config.retiredItems.water)
    assert(written.retiredItems.id_card and written.npcs[1].heading==150 and V.config.npcs[1].heading==150)
    assert(queries==before and same(slots[1].metadata,metadataBefore))
    assert(same(rows,rowBefore) and same(copies,copiesBefore))
    assert(V.verify(slots[1].metadata))
    ok,err=V.canIssue(1,'id_card'); assert(not ok and err=='document_unavailable')
    local oldRegistered,oldHandlers=V.registered,handlers
    V.registered={}; handlers={}; V.config=assert(S.configuration(written)); V.registerItems()
    assert(handlers.id_card and V.registered.id_card, 'historical item use must work after resource restart')
    before=queries; handlers.id_card(1,{slot=1}); assert(queries==before and events[#events][3].serial==metadataBefore.document.serial)
    local known=select(2,V.documentItems()); assert(known.id_card and known.weaponlicense and not known.water)
    V.config=previous; V.registered,handlers=oldRegistered,oldHandlers; pr_lib.saveJsonRecovery=saveRecovery
end)
test('removing the final template is supported and reusing an item retires no active binding',function()
    local previous,prSave=S.clone(V.config),pr_lib.saveJsonRecovery
    local draft=V.public(); draft.types={}; draft.npcs[1].services={}; draft.npcs[1].model='a_m_m_business_01'; assert(V.save(1,draft))
    assert(next(V.config.types)==nil and V.config.retiredItems.id_card and V.config.retiredItems.weaponlicense)
    draft=V.public(); draft.types.id_card=S.clone(previous.types.id_card); assert(V.save(1,draft))
    assert(not V.config.retiredItems.id_card and V.config.retiredItems.weaponlicense)
    V.config=previous; pr_lib.saveJsonRecovery=prSave
end)
print(('Forge DK service: %d tests passed'):format(total))
