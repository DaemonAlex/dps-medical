-- dps-medical rules: the decisions that are plain arithmetic, kept apart from
-- the server so they can be tested without a game (tests/run.lua).

Rules = {}

---Is `value` in the array `list`?
---@param list table?
---@param value any
---@return boolean
function Rules.listHas(list, value)
    for i = 1, #(list or {}) do
        if list[i] == value then return true end
    end
    return false
end

---Does an onsetFrom rule apply to this limb? No `zones` means any limb.
---wasabi indexes limbs 1..6: 1 head, 2 body.
---@param onset table
---@param limbIndex number?
---@return boolean
function Rules.zoneMatches(onset, limbIndex)
    if not onset.zones then return true end
    for _, z in ipairs(onset.zones) do
        if (z == 'head' and limbIndex == 1) or (z == 'body' and limbIndex == 2) then
            return true
        end
    end
    return false
end

---Minutes between severity steps for a condition.
---@param def table
---@param defaultStep number?
---@return number
function Rules.stepMinutes(def, defaultStep)
    return math.max(1, def.severityStepMinutes or defaultStep or 30)
end

---Severity after `minutes` of symptoms. The tick's SQL uses the same formula.
---@param def table
---@param minutes number minutes since symptoms began
---@param defaultStep number?
---@return number
function Rules.severityAt(def, minutes, defaultStep)
    local max = def.severityMax or 1
    if max <= 1 then return 1 end
    local sev = 1 + math.floor(math.max(0, minutes) / Rules.stepMinutes(def, defaultStep))
    return math.min(max, sev)
end

---Has an untreated condition run its course?
---A condition marked needsDoctor stays once it has reached its worst; every
---other condition clears when its time is up, however bad it got.
---@param def table
---@param severity number
---@param minutesSinceContract number
---@return boolean
function Rules.recovers(def, severity, minutesSinceContract)
    if not def.durationMinutes then return false end
    if minutesSinceContract < (def.incubationMinutes or 0) + def.durationMinutes then return false end
    if def.needsDoctor and severity >= (def.severityMax or 1) then return false end
    return true
end

---Seconds on a bed to clear a condition (the desk, and a medic's rest order).
---@param severity number
---@param minutesPerSeverity number?
---@return number
function Rules.restSeconds(severity, minutesPerSeverity)
    return math.max(1, tonumber(severity) or 1) * (minutesPerSeverity or 10) * 60
end

---Can a medic order bed rest for this condition? Rest is the cure for the
---conditions with no medication, once they are diagnosed where that is needed.
---@param def table
---@param row table { stage, diagnosed_at }
---@return boolean ok, string? why 'undiagnosed'
function Rules.restTreats(def, row)
    if def.treatment ~= nil then return false end
    if row.stage ~= 'symptomatic' then return false end
    if def.requiresConfirmation and not row.diagnosed_at then return false, 'undiagnosed' end
    return true
end

return Rules
