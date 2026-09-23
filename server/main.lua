-- dps-medical, server.
--
-- Two jobs:
--   1. Keep the patient RECORD, built from the events wasabi_ambulance already
--      broadcasts. We subscribe; we never modify wasabi.
--   2. Run ILLNESS, which nothing else on the server models - incubation,
--      progression, contagion and recovery, ticking whether or not any player
--      has a phone or tablet open.

local conditions = {}   -- citizenid -> { [id] = row }  active conditions, mirrored from the DB
local contagious = {}   -- citizenid -> true            fast lookup for the contagion pass
local lastLimbs  = {}   -- citizenid -> limbs table     latest trauma, cached from wasabi's listener
local woundSince = {}   -- citizenid -> { ["limb:type"] = { since = os.time(), rolled = {} } }  how long each wound has been open

---@param src number
---@return string? citizenid
local function cidOf(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

---@param src number
---@return string name, string? job
local function whoIs(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return 'Unknown', nil end
    local pd = player.PlayerData
    local ci = pd.charinfo or {}
    return ('%s %s'):format(ci.firstname or '?', ci.lastname or '?'), pd.job and pd.job.name or nil
end

local function debug(fmt, ...)
    if Config.Debug then print(('[dps-medical] ' .. fmt):format(...)) end
end

-- ===========================================================================
-- The chart
-- ===========================================================================

---Append one row to a patient's permanent record.
---@param citizenid string
---@param row table
local function recordVisit(citizenid, row)
    if not citizenid then return end
    MySQL.insert([[
        INSERT INTO dps_medical_visits
            (citizenid, event_type, zone, injury_type, condition_key, item,
             staff_citizenid, staff_name, staff_job, notes, data)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ]], {
        citizenid, row.event_type, row.zone, row.injury_type, row.condition_key, row.item,
        row.staff_citizenid, row.staff_name, row.staff_job, row.notes,
        row.data and json.encode(row.data) or nil,
    })
end

exports('recordVisit', recordVisit)

-- ===========================================================================
-- Illness
-- ===========================================================================

---@param citizenid string
---@param key string
---@return boolean
local function isImmune(citizenid, key)
    local row = MySQL.single.await(
        'SELECT expires_at FROM dps_medical_immunity WHERE citizenid = ? AND condition_key = ?',
        { citizenid, key })
    if not row then return false end
    if row.expires_at == nil then return true end -- permanent
    return MySQL.scalar.await('SELECT NOW() < ?', { row.expires_at }) == 1
end

---@param citizenid string
---@param key string
---@return boolean
local function hasCondition(citizenid, key)
    local mine = conditions[citizenid]
    if not mine then return false end
    for _, row in pairs(mine) do
        if row.condition_key == key and not row.resolved_at then return true end
    end
    return false
end

---Give someone an illness. Returns the new row id, or nil if they were immune
---or already had it.
---@param citizenid string
---@param key string
---@param origin? table { source_citizenid, source_kind }
---@return number?
local function contract(citizenid, key, origin)
    local def = Config.Conditions[key]
    if not def or not citizenid then return end
    if hasCondition(citizenid, key) then return end
    if isImmune(citizenid, key) then
        debug('%s is immune to %s', citizenid, key)
        return
    end

    origin = origin or {}
    local id = MySQL.insert.await([[
        INSERT INTO dps_medical_conditions
            (citizenid, condition_key, severity, stage, contagious,
             source_citizenid, source_kind, incubating_until)
        VALUES (?,?,?,?,?,?,?, DATE_ADD(NOW(), INTERVAL ? MINUTE))
    ]], {
        citizenid, key, 1, 'incubating', def.contagious and 1 or 0,
        origin.source_citizenid, origin.source_kind or 'environment',
        def.incubationMinutes or 0,
    })

    conditions[citizenid] = conditions[citizenid] or {}
    conditions[citizenid][id] = {
        id = id, condition_key = key, severity = 1, stage = 'incubating',
        contagious = def.contagious and 1 or 0,
    }
    if def.contagious then contagious[citizenid] = true end

    recordVisit(citizenid, {
        event_type = 'condition', condition_key = key,
        notes = ('Contracted (%s)'):format(origin.source_kind or 'environment'),
    })
    debug('%s contracted %s', citizenid, key)
    return id
end

exports('contract', contract)

---Resolve a condition and grant immunity if the definition says so.
---@param citizenid string
---@param id number
---@param how string 'treated'|'recovered'
local function resolve(citizenid, id, how)
    local mine = conditions[citizenid]
    local row = mine and mine[id]
    if not row then return end
    local def = Config.Conditions[row.condition_key]

    MySQL.update('UPDATE dps_medical_conditions SET stage = ?, resolved_at = NOW() WHERE id = ?',
        { 'resolved', id })

    if def and def.immunityMinutes then
        MySQL.insert([[
            INSERT INTO dps_medical_immunity (citizenid, condition_key, reason, expires_at)
            VALUES (?,?,?, DATE_ADD(NOW(), INTERVAL ? MINUTE))
            ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at), reason = VALUES(reason)
        ]], { citizenid, row.condition_key, how == 'treated' and 'recovered' or 'recovered',
              def.immunityMinutes })
    end

    recordVisit(citizenid, {
        event_type = 'condition', condition_key = row.condition_key,
        notes = how == 'treated' and 'Resolved after treatment' or 'Resolved - recovered',
    })

    mine[id] = nil
    -- Recompute the contagious flag from what is left.
    contagious[citizenid] = nil
    for _, r in pairs(mine) do
        if r.contagious == 1 and r.stage ~= 'resolved' then contagious[citizenid] = true end
    end
    debug('%s resolved %s (%s)', citizenid, row.condition_key, how)
end

---Load a player's active conditions into memory on join.
---@param citizenid string
local function loadConditions(citizenid)
    local rows = MySQL.query.await([[
        SELECT id, condition_key, severity, stage, contagious, diagnosed_at
        FROM dps_medical_conditions
        WHERE citizenid = ? AND resolved_at IS NULL
    ]], { citizenid }) or {}

    conditions[citizenid] = {}
    for i = 1, #rows do
        conditions[citizenid][rows[i].id] = rows[i]
        if rows[i].contagious == 1 then contagious[citizenid] = true end
    end
    debug('loaded %d conditions for %s', #rows, citizenid)
end

---@param list table?
---@param value any
---@return boolean
local function listHas(list, value)
    for i = 1, #(list or {}) do
        if list[i] == value then return true end
    end
    return false
end

---Does an onsetFrom rule apply to this limb? No `zones` means any limb.
---wasabi indexes limbs 1..6 in its documented order: 1 head, 2 body.
---@param onset table
---@param limbIndex number
---@return boolean
local function zoneMatches(onset, limbIndex)
    if not onset.zones then return true end
    for _, z in ipairs(onset.zones) do
        if (z == 'head' and limbIndex == 1) or (z == 'body' and limbIndex == 2) then
            return true
        end
    end
    return false
end

---Pull stage, severity and diagnosis back out of the DB for one player.
---
---Every reader - runTest, the patient's own view, the contagion pass - works
---from the in-memory cache, but the tick changes rows with plain SQL. Without
---this the cache still said 'incubating' after incubation had ended, so nobody
---ever became symptomatic until they relogged.
---@param citizenid string
local function syncConditions(citizenid)
    local mine = conditions[citizenid]
    if not mine or not next(mine) then return end
    local rows = MySQL.query.await([[
        SELECT id, stage, severity, diagnosed_at FROM dps_medical_conditions
        WHERE citizenid = ? AND resolved_at IS NULL
    ]], { citizenid }) or {}

    local seen = {}
    for i = 1, #rows do
        local r = rows[i]
        seen[r.id] = true
        local row = mine[r.id]
        if row then
            row.stage, row.severity, row.diagnosed_at = r.stage, r.severity, r.diagnosed_at
        end
    end
    -- Anything resolved behind our back (an admin in SQL, say) drops out too.
    for id in pairs(mine) do
        if not seen[id] then mine[id] = nil end
    end
    contagious[citizenid] = nil
    for _, r in pairs(mine) do
        if r.contagious == 1 and r.stage ~= 'resolved' then contagious[citizenid] = true end
    end
end

-- ===========================================================================
-- Progression - the slow server tick
-- ===========================================================================

CreateThread(function()
    while true do
        Wait(Config.TickSeconds * 1000)

        -- Incubation finishing: the patient starts feeling it.
        MySQL.update([[
            UPDATE dps_medical_conditions
            SET stage = 'symptomatic'
            WHERE stage = 'incubating' AND resolved_at IS NULL
              AND incubating_until IS NOT NULL AND incubating_until <= NOW()
        ]])

        -- Severity climbs while symptomatic: one step every
        -- durationMinutes / severityMax minutes, capped at severityMax. Rows
        -- were inserted at 1 and never moved; this is the number an ICU stay
        -- or a bill should scale from, so it has to.
        for key, def in pairs(Config.Conditions) do
            local max = def.severityMax or 1
            if max > 1 and def.durationMinutes then
                local step = math.max(1, math.floor(def.durationMinutes / max))
                MySQL.update([[
                    UPDATE dps_medical_conditions
                    SET severity = LEAST(?, 1 + FLOOR(TIMESTAMPDIFF(MINUTE, COALESCE(incubating_until, contracted_at), NOW()) / ?))
                    WHERE condition_key = ? AND resolved_at IS NULL AND stage = 'symptomatic'
                ]], { max, step, key })
            end
        end

        -- Old wounds going bad. onsetFrom with untreatedMinutes > 0 was never
        -- checked anywhere - the injury handler only rolled immediate onsets -
        -- so "gunshot goes septic" could not happen. Each open wound is rolled
        -- ONCE per condition when it crosses the age line, at the configured
        -- chance; it is not re-rolled every tick.
        for cid, wounds in pairs(woundSince) do
            for key, def in pairs(Config.Conditions) do
                local onset = def.onsetFrom
                if onset and (onset.untreatedMinutes or 0) > 0 and not hasCondition(cid, key) then
                    for wkey, w in pairs(wounds) do
                        local limbIndex, injuryType = wkey:match('^(%d+):(.+)$')
                        limbIndex = tonumber(limbIndex)
                        if not w.rolled[key] and zoneMatches(onset, limbIndex)
                            and listHas(onset.injuryTypes, injuryType)
                            and os.time() - w.since >= onset.untreatedMinutes * 60 then
                            w.rolled[key] = true
                            if math.random() < (onset.chance or 0) then
                                contract(cid, key, { source_kind = 'trauma' })
                                debug('%s: %s left %d min -> %s', cid, wkey, onset.untreatedMinutes, key)
                            end
                        end
                    end
                end
            end
        end

        -- Natural recovery once a condition has run its course untreated.
        for key, def in pairs(Config.Conditions) do
            if def.durationMinutes then
                local done = MySQL.query.await([[
                    SELECT id, citizenid FROM dps_medical_conditions
                    WHERE condition_key = ? AND resolved_at IS NULL AND stage = 'symptomatic'
                      AND contracted_at <= DATE_SUB(NOW(), INTERVAL ? MINUTE)
                ]], { key, (def.incubationMinutes or 0) + def.durationMinutes }) or {}
                for i = 1, #done do
                    resolve(done[i].citizenid, done[i].id, 'recovered')
                end
            end
        end

        -- Mirror what the SQL above changed back into memory, then push fresh
        -- state to everyone who is online and unwell.
        for _, src in ipairs(GetPlayers()) do
            local cid = cidOf(tonumber(src))
            if cid and conditions[cid] and next(conditions[cid]) then
                syncConditions(cid)
                TriggerClientEvent('dps-medical:client:conditions', tonumber(src),
                    lib.table.deepclone(conditions[cid]))
            end
        end
    end
end)

-- ===========================================================================
-- Contagion
-- ===========================================================================

CreateThread(function()
    while true do
        Wait(Config.ContagionSeconds * 1000)
        if next(contagious) then
            local players = GetPlayers()
            -- Only carriers are considered, and only their own coords are read.
            for _, carrierSrc in ipairs(players) do
                carrierSrc = tonumber(carrierSrc)
                local carrierCid = cidOf(carrierSrc)
                if carrierCid and contagious[carrierCid] then
                    local cPed = GetPlayerPed(carrierSrc)
                    local cCoords = GetEntityCoords(cPed)

                    for _, nearSrc in ipairs(players) do
                        nearSrc = tonumber(nearSrc)
                        if nearSrc ~= carrierSrc then
                            local nCoords = GetEntityCoords(GetPlayerPed(nearSrc))
                            if #(cCoords - nCoords) <= Config.ContagionDistance then
                                local nearCid = cidOf(nearSrc)
                                if nearCid then
                                    for _, row in pairs(conditions[carrierCid] or {}) do
                                        local def = Config.Conditions[row.condition_key]
                                        if def and def.contagious and row.stage ~= 'resolved' then
                                            local chance = Config.ContagionBaseChance
                                                * (def.contagionModifier or 1.0)
                                            if math.random() < chance then
                                                contract(nearCid, row.condition_key, {
                                                    source_citizenid = carrierCid,
                                                    source_kind = 'contact',
                                                })
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ===========================================================================
-- Treatment items
-- ===========================================================================
--
-- ox_inventory calls this for every item whose definition carries
-- `server = { export = 'dps-medical.useMedication' }` (see install/items.lua).
-- 'usingItem' fires before the item is consumed and returning false refuses
-- it; 'usedItem' fires after. Which condition an item treats is read from
-- Config.Conditions[*].treatment, so a new medication is config plus an item.

---@param citizenid string
---@param itemName string
---@return table ids of open conditions this item treats
local function treatableBy(citizenid, itemName)
    local out = {}
    for id, row in pairs(conditions[citizenid] or {}) do
        local def = Config.Conditions[row.condition_key]
        if def and def.treatment == itemName then out[#out + 1] = id end
    end
    return out
end

exports('useMedication', function(event, item, inventory, slot)
    local src = inventory.id
    local cid = cidOf(src)
    if not cid then return false end

    if event == 'usingItem' then
        if #treatableBy(cid, item.name) == 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                description = ('%s would not do anything for you right now.'):format(item.label),
                type = 'inform',
            })
            return false -- refused, so it is not consumed
        end
    elseif event == 'usedItem' then
        local ids = treatableBy(cid, item.name)
        for i = 1, #ids do resolve(cid, ids[i], 'treated') end
        recordVisit(cid, {
            event_type = 'treatment', item = item.name,
            notes = ('Took %s'):format(item.label),
        })
        TriggerClientEvent('ox_lib:notify', src, {
            description = ('You take the %s.'):format(item.label), type = 'success',
        })
        TriggerClientEvent('dps-medical:client:conditions', src,
            lib.table.deepclone(conditions[cid] or {}))
    end
end)

-- ===========================================================================
-- wasabi_ambulance listeners
-- ===========================================================================
--
-- These events are fired by wasabi's own bridge/listeners/server.lua. Nothing
-- in wasabi was edited to make this work - it already broadcasts them.

AddEventHandler('wasabi_ambulance:Server:Listeners:OnDeath', function(src, deathData)
    local cid = cidOf(src)
    if not cid then return end
    recordVisit(cid, {
        event_type = 'death',
        notes = 'Died',
        data = { cause = deathData and deathData.causeOfDeath, killer = deathData and deathData.killer },
    })
end)

AddEventHandler('wasabi_ambulance:Server:Listeners:OnRevive', function(src, reviver, method)
    local cid = cidOf(src)
    if not cid then return end
    local staffName, staffJob, staffCid
    if reviver and reviver ~= 0 then
        staffName, staffJob = whoIs(reviver)
        staffCid = cidOf(reviver)
    end
    recordVisit(cid, {
        event_type = 'revive', item = method,
        staff_citizenid = staffCid, staff_name = staffName, staff_job = staffJob,
        notes = ('Revived (%s)'):format(method or 'unknown'),
    })
end)

AddEventHandler('wasabi_ambulance:Server:Listeners:OnHealingItemUsed', function(src, itemName, healAmount, healerId)
    local cid = cidOf(src)
    if not cid then return end
    local staffName, staffJob, staffCid
    if healerId and healerId ~= 0 and healerId ~= src then
        staffName, staffJob = whoIs(healerId)
        staffCid = cidOf(healerId)
    end
    recordVisit(cid, {
        event_type = 'treatment', item = itemName,
        staff_citizenid = staffCid, staff_name = staffName, staff_job = staffJob,
        notes = staffName and ('Treated by %s'):format(staffName) or 'Self-treated',
        data = { healAmount = healAmount },
    })
end)

AddEventHandler('wasabi_ambulance:Server:Listeners:OnFacilityHeal', function(src, facilityId, facilityName, cost)
    local cid = cidOf(src)
    if not cid then return end
    recordVisit(cid, {
        event_type = 'facility',
        notes = ('Treated at %s'):format(facilityName or ('facility ' .. tostring(facilityId))),
        data = { cost = cost },
    })
end)

-- Trauma can cause illness. This is the join between wasabi's half and ours:
-- a head impact may concuss, and an open wound left untreated may go septic.
AddEventHandler('wasabi_ambulance:Server:Listeners:OnInjuryUpdate', function(src, limbs, previousLimbs)
    local cid = cidOf(src)
    if not cid or type(limbs) ~= 'table' then return end

    -- Keep the latest limb state so a medic's tablet can show trauma without
    -- having to ask the patient's own client for it.
    lastLimbs[cid] = limbs

    -- Track how long each wound has been open. wasabi's limb data carries no
    -- timestamps, so the first time we see a wound is when its clock starts;
    -- when it heals (count back to 0) the clock is dropped. The tick reads
    -- this for the slow onsets (untreatedMinutes > 0).
    woundSince[cid] = woundSince[cid] or {}
    local wounds, open = woundSince[cid], {}
    for limbIndex, limb in pairs(limbs) do
        if type(limb) == 'table' and type(limb.injuries) == 'table' then
            for injuryType, count in pairs(limb.injuries) do
                if (tonumber(count) or 0) > 0 then
                    local wkey = ('%d:%s'):format(limbIndex, injuryType)
                    open[wkey] = true
                    if not wounds[wkey] then wounds[wkey] = { since = os.time(), rolled = {} } end
                end
            end
        end
    end
    for wkey in pairs(wounds) do
        if not open[wkey] then wounds[wkey] = nil end
    end

    -- Immediate onsets (untreatedMinutes == 0): roll the moment a matching
    -- wound APPEARS, once, at the configured chance.
    for key, def in pairs(Config.Conditions) do
        local onset = def.onsetFrom
        if onset and (onset.untreatedMinutes or 0) == 0 and not hasCondition(cid, key) then
            for limbIndex, limb in pairs(limbs) do
                if zoneMatches(onset, limbIndex) and type(limb) == 'table' and limb.injuries then
                    for _, injuryType in ipairs(onset.injuryTypes or {}) do
                        local now = limb.injuries[injuryType] or 0
                        local before = previousLimbs and previousLimbs[limbIndex]
                            and previousLimbs[limbIndex].injuries
                            and previousLimbs[limbIndex].injuries[injuryType] or 0
                        if now > before and math.random() < (onset.chance or 0) then
                            contract(cid, key, { source_kind = 'trauma' })
                        end
                    end
                end
            end
        end
    end
end)

-- ===========================================================================
-- Player lifecycle
-- ===========================================================================

AddEventHandler('qbx_core:server:playerLoaded', function(player)
    local cid = player and player.PlayerData and player.PlayerData.citizenid
    if cid then loadConditions(cid) end
end)

AddEventHandler('qbx_core:server:playerUnloaded', function(source, citizenid)
    if citizenid then
        conditions[citizenid] = nil
        contagious[citizenid] = nil
        woundSince[citizenid] = nil
    end
end)

-- Same class of bug from the other side: playerLoaded only fires for people
-- who join AFTER this resource starts. Anyone already online when it (re)starts
-- had an empty cache until they relogged. Hydrate them now.
CreateThread(function()
    Wait(2000) -- let oxmysql settle
    local n = 0
    for _, src in ipairs(GetPlayers()) do
        local cid = cidOf(tonumber(src))
        if cid then
            loadConditions(cid)
            n = n + 1
        end
    end
    if n > 0 then debug('hydrated conditions for %d online players', n) end
end)

-- ===========================================================================
-- Facilities - where the hospital-only tests can be run
-- ===========================================================================
--
-- Read from wasabi's own table so there is exactly one definition of "hospital"
-- on this server. Set them up in game with /facilitypanel; this picks them up
-- on restart, or on demand with /reloadfacilities.

local facilities = {} -- { { name = string, coords = vector3 } }

local function loadFacilities()
    facilities = {}
    local rows = MySQL.query.await('SELECT name, locations FROM wsb_ambulance_facilities') or {}
    for i = 1, #rows do
        local ok, locs = pcall(json.decode, rows[i].locations or '')
        if ok and type(locs) == 'table' then
            -- wasabi stores several point types per facility; take anything that
            -- carries coordinates and treat it as part of the building.
            local function harvest(node)
                if type(node) ~= 'table' then return end
                local x = node.x or node[1]
                local y = node.y or node[2]
                local z = node.z or node[3]
                if type(x) == 'number' and type(y) == 'number' and type(z) == 'number' then
                    facilities[#facilities + 1] = { name = rows[i].name, coords = vec3(x, y, z) }
                    return
                end
                for _, child in pairs(node) do harvest(child) end
            end
            harvest(locs)
        end
    end
    debug('loaded %d facility points', #facilities)
    return #facilities
end

---Is this player standing in a hospital?
---@param src number
---@return string? facilityName
local function atFacility(src)
    if #facilities == 0 then return nil end
    local coords = GetEntityCoords(GetPlayerPed(src))
    for i = 1, #facilities do
        if #(coords - facilities[i].coords) <= Config.FacilityRadius then
            return facilities[i].name
        end
    end
    return nil
end

exports('atFacility', atFacility)

CreateThread(function()
    Wait(2000) -- let oxmysql settle
    loadFacilities()
end)

lib.addCommand('reloadfacilities', {
    help = 'Reload hospital locations from wasabi after using /facilitypanel',
    restricted = 'group.admin',
}, function(source)
    local n = loadFacilities()
    TriggerClientEvent('ox_lib:notify', source, {
        description = ('Loaded %d facility points.'):format(n),
        type = n > 0 and 'success' or 'warning',
    })
end)

-- ===========================================================================
-- Running a diagnostic test
-- ===========================================================================

---Is this player medical staff?
---@param src number
---@return boolean, string? job
local function isMedic(src)
    local _, job = whoIs(src)
    for _, j in ipairs(Config.MedicalJobs) do
        if j == job then return true, job end
    end
    return false, job
end

---Run one diagnostic test. Shared by the inspection menu and the command, so
---the field/hospital rule can only ever be written once.
---@param staffSrc number
---@param patientSrc number
---@param testKey string
---@return table result { ok = boolean, line = string, abnormal = boolean }
local function runTest(staffSrc, patientSrc, testKey)
    local ok, job = isMedic(staffSrc)
    if not ok then return { ok = false, line = 'You are not medical staff.' } end

    local test = Config.Tests[testKey]
    if not test then return { ok = false, line = 'No such test.' } end

    if test.where == 'facility' and not atFacility(staffSrc) then
        return { ok = false, line = #facilities == 0
            and ('%s needs a hospital, and none are set up yet (/facilitypanel).'):format(test.label)
            or ('%s can only be run at a hospital.'):format(test.label) }
    end

    local cid = cidOf(patientSrc)
    if not cid then return { ok = false, line = 'No such patient.' } end

    -- Build the finding from what the patient actually has. A test reports a
    -- result; it does not hand over a diagnosis.
    local hits = {}
    for _, row in pairs(conditions[cid] or {}) do
        if row.stage == 'symptomatic' then
            local def = Config.Conditions[row.condition_key]
            if def then
                for _, c in ipairs(test.confirms or {}) do
                    if c == row.condition_key then hits[#hits + 1] = def.label end
                end
                for _, s in ipairs(test.detects or {}) do
                    for _, has in ipairs(def.symptoms or {}) do
                        if has == s then hits[#hits + 1] = Config.Symptoms[s].label end
                    end
                end
            end
        end
    end

    local result = #hits > 0 and table.concat(hits, ', ') or 'nothing abnormal'
    local line = test.finding and test.finding:format(result) or result
    local staffName = whoIs(staffSrc)

    recordVisit(cid, {
        event_type = 'diagnosis', item = test.item or testKey,
        staff_citizenid = cidOf(staffSrc), staff_name = staffName, staff_job = job,
        notes = ('%s: %s'):format(test.label, line),
    })

    return { ok = true, line = line, abnormal = #hits > 0, label = test.label }
end

-- Called by the diagnostics menu that opens with wasabi's inspection.
lib.callback.register('dps-medical:runTest', function(src, patientSrc, testKey)
    return runTest(src, patientSrc, testKey)
end)

-- Tells the menu which tests to grey out before the medic picks one.
lib.callback.register('dps-medical:testAvailability', function(src)
    return { atFacility = atFacility(src) ~= nil, anyFacilities = #facilities > 0 }
end)

lib.addCommand('runtest', {
    help = 'Run a diagnostic test on a patient (the inspection menu is the normal way)',
    params = {
        { name = 'id', type = 'playerId', help = 'Patient server id' },
        { name = 'test', type = 'string', help = 'thermometer | pulseox | penlight | bloodtest | xray | ctscan' },
    },
}, function(source, args)
    local res = runTest(source, args.id, args.test)
    TriggerClientEvent('ox_lib:notify', source, {
        title = res.label, description = res.line,
        type = not res.ok and 'error' or (res.abnormal and 'warning' or 'success'),
        duration = 9000,
    })
end)

-- ===========================================================================
-- Data for the phone and the tablet
-- ===========================================================================

-- What the PATIENT is allowed to know: their symptoms, never the diagnosis,
-- unless a medic has actually diagnosed them.
lib.callback.register('dps-medical:getMyState', function(src)
    local cid = cidOf(src)
    if not cid then return {} end

    local out = { symptoms = {}, diagnosed = {} }
    local seen = {}
    for _, row in pairs(conditions[cid] or {}) do
        if row.stage == 'symptomatic' then
            local def = Config.Conditions[row.condition_key]
            if def then
                for _, s in ipairs(def.symptoms or {}) do
                    if not seen[s] then
                        seen[s] = true
                        out.symptoms[#out.symptoms + 1] = {
                            key = s,
                            label = Config.Symptoms[s] and Config.Symptoms[s].label or s,
                            patient = Config.Symptoms[s] and Config.Symptoms[s].patient or '',
                        }
                    end
                end
                if row.diagnosed_at then
                    out.diagnosed[#out.diagnosed + 1] = { key = row.condition_key, label = def.label }
                end
            end
        end
    end
    return out
end)

-- Everything the tablet needs about one patient, addressed by their server id.
-- Medical staff only; the client gate is convenience, this is the real check.
lib.callback.register('dps-medical:getChartFor', function(src, targetSrc)
    local ok = isMedic(src)
    if not ok or not targetSrc then return nil end

    local cid = cidOf(targetSrc)
    if not cid then return nil end

    local name = whoIs(targetSrc)

    -- Trauma, shaped the way the tablet renders it.
    local body = {}
    local limbs = lastLimbs[cid] or {}
    for i = 1, 6 do
        local limb, count, detail = limbs[i], 0, {}
        if type(limb) == 'table' and type(limb.injuries) == 'table' then
            for injuryType, n in pairs(limb.injuries) do
                if n and n > 0 then
                    count = count + n
                    detail[#detail + 1] = { type = injuryType, count = n }
                end
            end
        end
        body[i] = { count = count, injuries = detail }
    end

    -- Conditions. An undiagnosed illness must NOT reveal its name - the tablet
    -- shows "Undiagnosed illness" until someone actually tests for it.
    local rows = MySQL.query.await([[
        SELECT id, condition_key, severity, stage, diagnosed_at, contracted_at
        FROM dps_medical_conditions
        WHERE citizenid = ? AND resolved_at IS NULL AND stage = 'symptomatic'
    ]], { cid }) or {}
    local conds = {}
    for i = 1, #rows do
        local def = Config.Conditions[rows[i].condition_key]
        conds[#conds + 1] = {
            condition_key = rows[i].diagnosed_at and rows[i].condition_key or nil,
            label = rows[i].diagnosed_at and (def and def.label or rows[i].condition_key) or nil,
            diagnosed_at = rows[i].diagnosed_at,
            contracted_at = rows[i].contracted_at,
            severity = rows[i].severity,
        }
    end

    return {
        patient = { name = name, citizenid = cid },
        body = body,
        bleeding = 0,
        conditions = conds,
        visits = MySQL.query.await([[
            SELECT event_type, item, staff_name, notes, created_at
            FROM dps_medical_visits WHERE citizenid = ?
            ORDER BY created_at DESC LIMIT 25
        ]], { cid }) or {},
    }
end)

-- The full chart by citizenid, for record lookups rather than a live patient.
lib.callback.register('dps-medical:getChart', function(src, targetCitizenId)
    local _, job = whoIs(src)
    local allowed = false
    for _, j in ipairs(Config.RecordReadJobs) do if j == job then allowed = true end end
    if not allowed or not targetCitizenId then return nil end

    return {
        visits = MySQL.query.await([[
            SELECT event_type, zone, injury_type, condition_key, item, staff_name, notes, created_at
            FROM dps_medical_visits WHERE citizenid = ?
            ORDER BY created_at DESC LIMIT 50
        ]], { targetCitizenId }) or {},
        conditions = MySQL.query.await([[
            SELECT condition_key, severity, stage, diagnosed_at, contracted_at
            FROM dps_medical_conditions WHERE citizenid = ? AND resolved_at IS NULL
        ]], { targetCitizenId }) or {},
    }
end)

-- ===========================================================================
-- Staff and admin commands
-- ===========================================================================

lib.addCommand('diagnose', {
    help = 'Record a diagnosis against a patient (medical staff only)',
    params = {
        { name = 'id', type = 'playerId', help = 'Patient server id' },
        { name = 'condition', type = 'string', help = 'Condition key' },
    },
}, function(source, args)
    local _, job = whoIs(source)
    local allowed = false
    for _, j in ipairs(Config.MedicalJobs) do if j == job then allowed = true end end
    if not allowed then return end

    local cid = cidOf(args.id)
    local def = Config.Conditions[args.condition]
    if not cid or not def then return end

    MySQL.update([[
        UPDATE dps_medical_conditions SET diagnosed_at = NOW(), diagnosed_by = ?
        WHERE citizenid = ? AND condition_key = ? AND resolved_at IS NULL
    ]], { cidOf(source), cid, args.condition })

    local staffName = whoIs(source)
    recordVisit(cid, {
        event_type = 'diagnosis', condition_key = args.condition,
        staff_citizenid = cidOf(source), staff_name = staffName, staff_job = job,
        notes = ('Diagnosed as %s'):format(def.label),
    })
    if conditions[cid] then
        for _, row in pairs(conditions[cid]) do
            if row.condition_key == args.condition then row.diagnosed_at = os.date('%Y-%m-%d %H:%M:%S') end
        end
    end
end)

lib.addCommand('givecondition', {
    help = 'Admin: infect a player with a condition',
    params = {
        { name = 'id', type = 'playerId' },
        { name = 'condition', type = 'string' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local cid = cidOf(args.id)
    if not cid then return end
    local id = contract(cid, args.condition, { source_kind = 'admin' })
    TriggerClientEvent('ox_lib:notify', source, {
        description = id and ('Gave %s to that player.'):format(args.condition)
                      or 'They are immune or already have it.',
        type = id and 'success' or 'inform',
    })
end)

lib.addCommand('curecondition', {
    help = 'Admin: clear a condition from a player',
    params = {
        { name = 'id', type = 'playerId' },
        { name = 'condition', type = 'string' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local cid = cidOf(args.id)
    if not cid or not conditions[cid] then return end
    for id, row in pairs(conditions[cid]) do
        if row.condition_key == args.condition then resolve(cid, id, 'treated') end
    end
end)

print(('[dps-medical] ready - %d conditions defined, tick %ds, contagion %ds')
    :format(#(function() local n = {} for k in pairs(Config.Conditions) do n[#n+1] = k end return n end)(),
            Config.TickSeconds, Config.ContagionSeconds))
