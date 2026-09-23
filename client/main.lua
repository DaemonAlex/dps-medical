-- dps-medical, client.
--
-- Listens to wasabi_ambulance and keeps a local picture of the player's body.
-- It applies NOTHING: wasabi already runs every consequence (bleed, stun,
-- knockout), so this half only ever reads and reports. That is deliberate -
-- it means nothing here can contradict what the player is actually feeling.

local limbs = {}        -- limbIndex -> { injuries = { [type] = count } }, straight from wasabi
local statuses = {}     -- 'bleed'|'stun'|... -> amount
local myConditions = {} -- id -> row, pushed by the server
local knownSymptoms = {}

-- wasabi indexes limbs 1..6 in this documented order.
local LIMB_NAMES = { 'head', 'body', 'leftarm', 'rightarm', 'leftleg', 'rightleg' }
local LIMB_LABELS = { 'Head', 'Torso', 'Left arm', 'Right arm', 'Left leg', 'Right leg' }

-- ===========================================================================
-- wasabi listeners
-- ===========================================================================
-- Fired by wasabi's own bridge/listeners/client.lua. We changed nothing in it.

AddEventHandler('wasabi_ambulance:Client:Listeners:OnInjuryUpdate', function(newLimbs)
    limbs = newLimbs or {}
end)

AddEventHandler('wasabi_ambulance:Client:Listeners:OnStatusChange', function(statusType, amount)
    statuses[statusType] = amount
end)

-- ===========================================================================
-- Job gate
-- ===========================================================================
--
-- Every menu this resource offers is tied to the job it serves. Nothing below
-- registers, draws or opens for a player who is not medical staff, and the
-- answer is re-checked whenever their job changes rather than cached at spawn.

local myJob = nil

---@return boolean
local function isMedic()
    if not myJob then return false end
    for i = 1, #Config.MedicalJobs do
        if Config.MedicalJobs[i] == myJob then return true end
    end
    return false
end

local function refreshJob()
    local data = QBX and QBX.PlayerData or exports.qbx_core:GetPlayerData()
    myJob = data and data.job and data.job.name or nil
end

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    myJob = job and job.name or nil
end)

RegisterNetEvent('qbx_core:client:onJobUpdate', function(job)
    myJob = job and job.name or nil
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then refreshJob() end
end)

CreateThread(function()
    Wait(1500) -- let qbx_core hand over player data after a join
    refreshJob()
end)

-- ===========================================================================
-- Stations
-- ===========================================================================
--
-- Beds, the blood lab, imaging tables: real props in the map, one patient at
-- a time. The server owns who is on what; this half offers the target options
-- on the props and puts the ped on the slot.

local stationOccupied = {}   -- stationId -> server id of the occupant, pushed by the server
local myStation = nil        -- stationId I am on

RegisterNetEvent('dps-medical:client:stations', function(map)
    stationOccupied = map or {}
end)

---The station this map object IS: same model, within a couple of metres.
---@param entity number
---@return string? id, table? station
local function stationForEntity(entity)
    if not entity or entity == 0 then return nil end
    local model = GetEntityModel(entity)
    local pos = GetEntityCoords(entity)
    local bestId, best, bestD = nil, nil, 2.5
    for id, st in pairs(Config.Stations) do
        local h = type(st.prop) == 'number' and st.prop or joaat(st.prop)
        -- wasabi's own facility beds keep wasabi's menu; we never add ours on top.
        if h == model and not st.wasabiBed then
            local d = #(pos - vec3(st.coords.x, st.coords.y, st.coords.z))
            if d < bestD then bestId, best, bestD = id, st, d end
        end
    end
    return bestId, best
end

local function placeOnStation(st, anim)
    local ped, slot = PlayerPedId(), st.slot
    SetEntityCoords(ped, slot.x, slot.y, slot.z, false, false, false, false)
    SetEntityHeading(ped, slot.w)
    if not anim then return end
    if anim.scenario then
        TaskStartScenarioAtPosition(ped, anim.scenario, slot.x, slot.y, slot.z, slot.w, 0, true, false)
    elseif anim.dict and anim.clip then
        lib.requestAnimDict(anim.dict)
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, -1, anim.flag or 1, 0, false, false, false)
    end
end

local function occupyStation(id, st)
    local res = lib.callback.await('dps-medical:occupy', false, id)
    if not res or not res.ok then
        lib.notify({ description = res and res.line or 'No.', type = 'error' })
        return
    end
    myStation = id
    placeOnStation(st, res.anim)
    local kind = Config.StationKinds[st.kind] or {}
    lib.notify({ description = ('%s - %s'):format(kind.label or st.kind, st.facility or ''), type = 'inform' })
end

local function leaveStation()
    local res = lib.callback.await('dps-medical:leave', false)
    if not res or not res.ok then
        lib.notify({ description = res and res.line or 'No.', type = 'error' })
        return
    end
    myStation = nil
    ClearPedTasks(PlayerPedId())
end

RegisterNetEvent('dps-medical:client:released', function()
    myStation = nil
    ClearPedTasks(PlayerPedId())
    lib.notify({ description = 'You can get up.', type = 'inform' })
end)

-- Only runs while I am on a station; idles otherwise. An imaging table holds
-- the patient (movement off); walking away from a bed counts as getting up.
CreateThread(function()
    while true do
        if myStation then
            local st = Config.Stations[myStation]
            local kind = st and Config.StationKinds[st.kind] or {}
            if kind.canLeave == false then
                DisableControlAction(0, 30, true) -- move left/right
                DisableControlAction(0, 31, true) -- move forward/back
                DisableControlAction(0, 22, true) -- jump
                DisableControlAction(0, 23, true) -- enter vehicle
                Wait(0)
            else
                if st and #(GetEntityCoords(PlayerPedId()) - vec3(st.slot.x, st.slot.y, st.slot.z)) > 3.0 then
                    leaveStation()
                end
                Wait(500)
            end
        else
            Wait(1000)
        end
    end
end)

-- Target options on every station prop. One "use" option per kind so the
-- label reads right ("Lie down" on a bed, "Sit for a sample" at the lab).
CreateThread(function()
    local models, seen = {}, {}
    for _, st in pairs(Config.Stations) do
        -- Beds that wasabi already runs (wasabiBed) get no options from us:
        -- "Lay in Bed" is wasabi's, and two lie-down menus on one bed is the
        -- parallel-system mistake this resource exists to avoid.
        if st.prop and not st.wasabiBed and not seen[st.prop] then
            seen[st.prop] = true
            models[#models + 1] = type(st.prop) == 'number' and st.prop or joaat(st.prop)
        end
    end
    if #models == 0 then return end

    stationOccupied = lib.callback.await('dps-medical:stations', false) or {}
    local me = GetPlayerServerId(PlayerId())
    local options = {}

    for kindKey, kind in pairs(Config.StationKinds) do
        options[#options + 1] = {
            name = 'dps_medical_station_use_' .. kindKey,
            icon = 'fas fa-procedures',
            label = kind.patientLabel or ('Use ' .. (kind.label or kindKey)),
            distance = Config.StationInteractDistance or 3.0,
            canInteract = function(entity)
                if myStation then return false end
                local id, st = stationForEntity(entity)
                return id ~= nil and st.kind == kindKey and stationOccupied[id] == nil
            end,
            onSelect = function(data)
                local id, st = stationForEntity(data.entity)
                if id then occupyStation(id, st) end
            end,
        }
    end

    options[#options + 1] = {
        name = 'dps_medical_station_leave',
        icon = 'fas fa-walking',
        label = 'Get up',
        distance = Config.StationInteractDistance or 3.0,
        canInteract = function(entity)
            local id = stationForEntity(entity)
            return id ~= nil and id == myStation
        end,
        onSelect = function() leaveStation() end,
    }

    options[#options + 1] = {
        name = 'dps_medical_station_release',
        icon = 'fas fa-user-nurse',
        label = 'Release patient',
        distance = Config.StationInteractDistance or 3.0,
        canInteract = function(entity)
            if not isMedic() then return false end
            local id = stationForEntity(entity)
            local occ = id and stationOccupied[id]
            return occ ~= nil and occ ~= me
        end,
        onSelect = function(data)
            local id = stationForEntity(data.entity)
            local occ = id and stationOccupied[id]
            if not occ then return end
            local res = lib.callback.await('dps-medical:release', false, occ)
            lib.notify({ description = res and res.line or 'No.', type = (res and res.ok) and 'success' or 'error' })
        end,
    }

    exports.ox_target:addModel(models, options)
end)

-- /stationcapture <kind> <facility name>: stand where the patient should be,
-- look at the prop, run it. The prop name comes from the game (same raycast
-- idea as dps-whatobject), so nothing is typed by hand. Admin only, checked
-- server side.
RegisterCommand('stationcapture', function(_, args)
    local kind = args[1]
    local facility = table.concat(args, ' ', 2) -- optional: the server uses the wasabi facility you stand in
    if not kind or not Config.StationKinds[kind] then
        lib.notify({ description = 'Usage: /stationcapture <bed|bloodlab|xray|ct|mri> [facility name]', type = 'error', duration = 8000 })
        return
    end
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local fwd = vector3(
        -math.sin(math.rad(rot.z)) * math.abs(math.cos(math.rad(rot.x))),
         math.cos(math.rad(rot.z)) * math.abs(math.cos(math.rad(rot.x))),
         math.sin(math.rad(rot.x)))
    local dest = cam + fwd * 15.0
    local ray = StartShapeTestRay(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, 16, PlayerPedId(), 4)
    local _, hit, _, _, entity = GetShapeTestResult(ray)
    if hit ~= 1 or not entity or entity == 0 or GetEntityType(entity) ~= 3 then
        lib.notify({ description = 'Look straight at the prop (bed, chair, table) and try again.', type = 'error' })
        return
    end
    local name = GetEntityArchetypeName(entity)
    if type(name) ~= 'string' or name == '' then name = ('hash %d'):format(GetEntityModel(entity)) end
    local p, ped = GetEntityCoords(entity), PlayerPedId()
    local s = GetEntityCoords(ped)
    TriggerServerEvent('dps-medical:stationCapture', {
        kind = kind, facility = facility, prop = name,
        prop_x = p.x, prop_y = p.y, prop_z = p.z, prop_h = GetEntityHeading(entity),
        slot_x = s.x, slot_y = s.y, slot_z = s.z, slot_h = GetEntityHeading(ped),
    })
    print(('[dps-medical] station capture: %s at %s, prop %s'):format(kind, facility, name))
end, false)

-- ===========================================================================
-- Diagnostics, opened from wasabi's own inspection
-- ===========================================================================
--
-- We do not rebuild wasabi's injury list - its HEALTH INSPECTION panel already
-- shows trauma, in our accent colour. This adds only what wasabi has no concept
-- of: diagnostic tests and illness.

local inspecting = nil -- server id of the patient currently being inspected

local function openDiagnostics(targetServerId)
    if not isMedic() then return end

    local avail = lib.callback.await('dps-medical:testAvailability', false, targetServerId) or {}
    local options = {}

    for key, test in pairs(Config.Tests) do
        local hospitalOnly = test.where ~= 'field'
        local kind = hospitalOnly and Config.StationKinds[test.where] or nil
        local kindLabel = kind and kind.label or test.where
        local blocked = hospitalOnly and avail.patientKind ~= test.where
        options[#options + 1] = {
            title = test.label,
            description = blocked
                and ((avail.kinds and avail.kinds[test.where])
                     and ('Needs the patient on a %s'):format(kindLabel)
                     or ('No %s set up on this server'):format(kindLabel))
                or (hospitalOnly and ('On the %s'):format(kindLabel) or 'Field kit'),
            icon = blocked and 'lock' or 'stethoscope',
            disabled = blocked,
            onSelect = function()
                if lib.progressBar({
                    duration = test.duration or 4000,
                    label = ('%s...'):format(test.label),
                    useWhileDead = false, canCancel = true,
                    disable = { move = true, combat = true },
                }) then
                    local res = lib.callback.await('dps-medical:runTest', false, targetServerId, key)
                    lib.notify({
                        title = res and res.label or test.label,
                        description = (res and res.line or 'No result.')
                            .. ((res and res.hint) and ('\n' .. res.hint) or ''),
                        type = (res and res.ok) and (res.abnormal and 'warning' or 'success') or 'error',
                        duration = 9000,
                    })
                end
            end,
        }
    end

    table.sort(options, function(a, b) return a.title < b.title end)

    lib.registerContext({
        id = 'dps_medical_diagnostics',
        title = 'Diagnostics',
        options = options,
    })
    lib.showContext('dps_medical_diagnostics')
end

-- Fires the moment a medic inspects someone with wasabi. We use their
-- interaction as the entry point rather than adding a competing one.
AddEventHandler('wasabi_ambulance:Client:Listeners:OnInspectionOpen', function(targetServerId, _, viewOnly)
    inspecting = targetServerId
    TriggerEvent('dps-medical:client:inspectionOpened', targetServerId, viewOnly)
    -- Keep the tablet chart on whoever is actually in front of the medic.
    if isMedic() then
        SendNUIMessage({ action = 'dpsMedical:chart',
                         data = lib.callback.await('dps-medical:getChartFor', false, targetServerId) })
    end
end)

AddEventHandler('wasabi_ambulance:Client:Listeners:OnInspectionClose', function()
    inspecting = nil
end)

-- ===========================================================================
-- The tablet app
-- ===========================================================================
--
-- The chart lives on lb-tablet. This half only serves it data: the app frame
-- asks us when it opens, and we push an update whenever the medic inspects
-- someone new, so the chart follows the patient in front of them.

---@param targetServerId number?
local function chartFor(targetServerId)
    if not isMedic() or not targetServerId then return nil end
    return lib.callback.await('dps-medical:getChartFor', false, targetServerId)
end

-- Called by the app when its frame loads inside the tablet.
RegisterNUICallback('uiReady', function(_, cb)
    cb(chartFor(inspecting) or {})
end)

-- Push a fresh chart into the app when the patient changes.
local function pushChart(targetServerId)
    SendNUIMessage({ action = 'dpsMedical:chart', data = chartFor(targetServerId) })
end

exports('pushChart', pushChart)

-- Opens the diagnostics menu for whoever is currently being inspected.
RegisterCommand('diagnostics', function()
    if not isMedic() then
        lib.notify({ description = 'Only medical staff can run diagnostics.', type = 'error' })
        return
    end
    if not inspecting then
        lib.notify({ description = 'Inspect a patient first.', type = 'inform' })
        return
    end
    openDiagnostics(inspecting)
end, false)

RegisterKeyMapping('diagnostics', 'Medical: diagnostics on inspected patient', 'keyboard', '')

-- ===========================================================================
-- Conditions from the server
-- ===========================================================================

RegisterNetEvent('dps-medical:client:conditions', function(rows)
    myConditions = rows or {}
end)

---Tell the player when a NEW symptom appears. Never names the illness - that
---is what a doctor is for.
local function announceSymptoms(symptoms)
    for i = 1, #symptoms do
        local s = symptoms[i]
        if not knownSymptoms[s.key] then
            knownSymptoms[s.key] = true
            lib.notify({ description = s.patient, type = 'inform', duration = 7000 })
        end
    end
end

-- ===========================================================================
-- The patient's own view
-- ===========================================================================

---Everything the player is entitled to know about themselves.
---@return table
local function myState()
    local body = {}
    for i = 1, 6 do
        local limb = limbs[i]
        local count, detail = 0, {}
        if type(limb) == 'table' and type(limb.injuries) == 'table' then
            for injuryType, n in pairs(limb.injuries) do
                if n and n > 0 then
                    count = count + n
                    detail[#detail + 1] = { type = injuryType, count = n }
                end
            end
        end
        body[i] = { key = LIMB_NAMES[i], label = LIMB_LABELS[i], count = count, injuries = detail }
    end

    local server = lib.callback.await('dps-medical:getMyState', false) or {}
    if server.symptoms then announceSymptoms(server.symptoms) end

    return {
        body = body,
        bleeding = statuses.bleed or 0,
        stunned = statuses.stun or 0,
        symptoms = server.symptoms or {},
        diagnosed = server.diagnosed or {},
    }
end

exports('getMyState', myState)

-- Until the phone app lands, this is how we look at it in game.
RegisterCommand('health', function()
    local state = myState()

    local hurt = {}
    for i = 1, #state.body do
        if state.body[i].count > 0 then
            local parts = {}
            for _, inj in ipairs(state.body[i].injuries) do
                parts[#parts + 1] = ('%dx %s'):format(inj.count, inj.type)
            end
            hurt[#hurt + 1] = { label = state.body[i].label, value = table.concat(parts, ', ') }
        end
    end

    local options = {}
    if #hurt == 0 then
        options[#options + 1] = { title = 'No injuries', description = 'Nothing broken or bleeding.', disabled = true }
    else
        for _, h in ipairs(hurt) do
            options[#options + 1] = { title = h.label, description = h.value, disabled = true }
        end
    end

    if state.bleeding > 0 then
        options[#options + 1] = { title = 'Bleeding', description = ('Stage %s - get this stopped.'):format(state.bleeding), disabled = true }
    end

    for _, s in ipairs(state.symptoms) do
        -- Severity scales the wording, never names the illness.
        local word = Config.SeverityWords and Config.SeverityWords[s.severity or 1]
        options[#options + 1] = {
            title = word and ('%s - %s'):format(s.label, word) or s.label,
            description = s.patient, disabled = true,
        }
    end
    for _, d in ipairs(state.diagnosed) do
        options[#options + 1] = { title = ('Diagnosed: %s'):format(d.label), description = 'Confirmed by a medic.', disabled = true }
    end

    lib.registerContext({ id = 'dps_medical_self', title = 'How you feel', options = options })
    lib.showContext('dps_medical_self')
end, false)

RegisterKeyMapping('health', 'Check how you feel', 'keyboard', '')

print('[dps-medical] client ready - reading wasabi_ambulance, applying nothing')
