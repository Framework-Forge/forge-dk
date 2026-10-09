local DK, S = ForgeDK, ForgeDK.Schema
local Store = { ready = false }
DK.Store = Store
local db = pr_lib.database
local function query(sql, args)
    local result = db.query(sql, args or {})
    if type(result) ~= 'table' then error('Forge DK database query failed') end
    return result
end
local function write(sql, args)
    local result = db.update(sql, args or {})
    if type(result) ~= 'number' then error('Forge DK database write failed') end
    return result
end
function Store.initialize()
    local ok, err = pcall(function()
        query([[CREATE TABLE IF NOT EXISTS forge_dk_documents (
            serial VARCHAR(64) NOT NULL PRIMARY KEY,
            owner_identifier VARCHAR(64) NOT NULL,
            type_key VARCHAR(64) NOT NULL,
            subject_key VARCHAR(96) NOT NULL,
            scope_key VARCHAR(255) NOT NULL UNIQUE,
            kind VARCHAR(16) NOT NULL,
            status VARCHAR(16) NOT NULL,
            copies INT UNSIGNED NOT NULL DEFAULT 0,
            snapshot LONGTEXT NOT NULL,
            created_at BIGINT NOT NULL,
            expires_at BIGINT NOT NULL DEFAULT 0,
            INDEX owner_type (owner_identifier, type_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        query([[CREATE TABLE IF NOT EXISTS forge_dk_document_copies (
            copy_id VARCHAR(64) NOT NULL PRIMARY KEY,
            serial VARCHAR(64) NOT NULL,
            status VARCHAR(16) NOT NULL,
            snapshot LONGTEXT NOT NULL,
            fee BIGINT NOT NULL,
            account VARCHAR(16) NOT NULL,
            created_at BIGINT NOT NULL,
            INDEX document_serial (serial)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    end)
    Store.ready = ok
    if not ok then print('[Forge DK] Database unavailable: ' .. tostring(err)) end
    return ok
end
function Store.scope(scope)
    return query('SELECT * FROM forge_dk_documents WHERE scope_key = ? LIMIT 1', { scope })[1]
end
function Store.document(serial)
    return query('SELECT * FROM forge_dk_documents WHERE serial = ? LIMIT 1', { serial })[1]
end
function Store.copy(copyId)
    return query([[SELECT c.*, d.kind, d.status AS document_status, d.expires_at,
        d.owner_identifier, d.type_key FROM forge_dk_document_copies c
        JOIN forge_dk_documents d ON d.serial = c.serial WHERE c.copy_id = ? LIMIT 1]], { copyId })[1]
end
function Store.pending(serial)
    return query("SELECT copy_id FROM forge_dk_document_copies WHERE serial = ? AND status NOT IN ('delivered', 'failed') LIMIT 1", { serial })[1]
end
function Store.reserve(record, snapshot, fee, account)
    local recordJson, copyJson = json.encode(record.snapshot), json.encode(snapshot)
    local operations = {}
    if record.new then
        operations[#operations + 1] = { query = [[INSERT INTO forge_dk_documents
            (serial, owner_identifier, type_key, subject_key, scope_key, kind, status, snapshot, created_at, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)]],
            values = { record.serial, record.owner, record.typeKey, record.subject, record.scope,
                record.kind, recordJson, record.createdAt, record.expiresAt } }
    end
    operations[#operations + 1] = { query = [[INSERT INTO forge_dk_document_copies
        (copy_id, serial, status, snapshot, fee, account, created_at) VALUES (?, ?, 'reserved', ?, ?, ?, ?)]],
        values = { snapshot.copyId, record.serial, copyJson, fee, account, os.time() } }
    return db.transaction(operations) == true
end
function Store.delivered(record, snapshot)
    -- One InnoDB statement: both rows change together, once, only while not revoked.
    return write([[UPDATE forge_dk_documents d JOIN forge_dk_document_copies c ON c.serial = d.serial
        SET c.status = 'delivered', d.status = 'valid', d.copies = d.copies + 1,
            d.snapshot = ?, d.expires_at = ?
        WHERE c.copy_id = ? AND c.status = 'delivering' AND d.status IN ('pending', 'valid')]],
        { json.encode(record.snapshot), record.expiresAt, snapshot.copyId }) > 0
end
function Store.stage(copyId, stage)
    if stage ~= 'charged' and stage ~= 'delivering' and stage ~= 'review' then return false end
    return write("UPDATE forge_dk_document_copies SET status = ? WHERE copy_id = ? AND status NOT IN ('delivered', 'failed')", { stage, copyId }) > 0
end
function Store.failed(copyId)
    write("UPDATE forge_dk_document_copies SET status = 'failed' WHERE copy_id = ? AND status <> 'delivered'", { copyId })
end
function Store.revoke(serial)
    local changed = write("UPDATE forge_dk_documents SET status = 'revoked' WHERE serial = ? AND status <> 'revoked'", { serial })
    return changed > 0
end
function Store.list(identifier)
    if identifier then return query([[SELECT serial, owner_identifier, type_key, subject_key, kind, status,
        copies, created_at, expires_at,
        (SELECT COUNT(*) FROM forge_dk_document_copies c WHERE c.serial = forge_dk_documents.serial AND c.status NOT IN ('delivered', 'failed')) AS pending_deliveries
        FROM forge_dk_documents WHERE owner_identifier = ? ORDER BY created_at DESC LIMIT 100]], { identifier }) end
    return query([[SELECT serial, owner_identifier, type_key, subject_key, kind, status,
        copies, created_at, expires_at,
        (SELECT COUNT(*) FROM forge_dk_document_copies c WHERE c.serial = forge_dk_documents.serial AND c.status NOT IN ('delivered', 'failed')) AS pending_deliveries
        FROM forge_dk_documents ORDER BY created_at DESC LIMIT 100]])
end
function Store.receipts(serial)
    return query('SELECT copy_id, serial, status, fee, account, created_at FROM forge_dk_document_copies WHERE serial = ? ORDER BY created_at DESC', { serial })
end
