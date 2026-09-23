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
-- Diagnostics, opened from wasabi's own inspection
-- ===========================================================================
--
-- We do not rebuild wasabi's injury list - its HEALTH INSPECTION panel already
-- shows trauma, in our accent colour. This adds only what wasabi has no concept
-- of: diagnostic tests and illness.

local inspecting = nil -- server id of the patient currently being inspected

local function openDiagnostics(targetServerId)
    if not isMedic() then return end

    local avail = lib.callback.await('dps-medical:testAvailability', false) or {}
    local options = {}

    for key, test in pairs(Config.Tests) do
        local hospitalOnly = test.where == 'facility'
        local blocked = hospitalOnly and not avail.atFacility
        options[#options + 1] = {
            title = test.label,
            description = blocked
                and (avail.anyFacilities and 'Hospital only - bring them in'
                     or 'Hospital only - no facilities set up yet')
                or (hospitalOnly and 'Hospital equipment' or 'Field kit'),
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
                        description = res and res.line or 'No result.',
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
