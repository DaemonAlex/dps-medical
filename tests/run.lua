-- lua5.4 tests/run.lua   (from the resource folder)
local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; print('FAIL ' .. name) end
end

vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
vec3 = function(x, y, z) return { x = x, y = y, z = z } end
dofile('config.lua')
dofile('shared/rules.lua')

-- Every condition must have a way out: it clears by itself, or something cures it.
for key, def in pairs(Config.Conditions) do
    local step = Rules.stepMinutes(def, Config.SeverityStepMinutes)
    local endMin = (def.incubationMinutes or 0) + def.durationMinutes
    local sevAtEnd = Rules.severityAt(def, def.durationMinutes, Config.SeverityStepMinutes)
    local selfClears = Rules.recovers(def, sevAtEnd, endMin)
    check(key .. ': step is positive', step >= 1)
    check(key .. ': clears alone or needs a doctor', selfClears or def.needsDoctor == true)
    if def.treatment == nil then
        check(key .. ': no pill, so rest must treat it',
            Rules.restTreats(def, { stage = 'symptomatic', diagnosed_at = 'x' }))
    end
    for _, s in ipairs(def.symptoms) do
        check(key .. ': symptom ' .. s .. ' is defined', Config.Symptoms[s] ~= nil)
    end
end

-- A condition that needs a test must have a test that confirms it, on a station kind that exists.
local kinds = {}
for _, st in pairs(Config.Stations) do kinds[st.kind] = true end
for key, def in pairs(Config.Conditions) do
    if def.requiresConfirmation then
        local found = false
        for _, t in pairs(Config.Tests) do
            if Rules.listHas(t.confirms, key) and (t.where == 'field' or kinds[t.where]) then found = true end
        end
        check(key .. ': a test confirms it', found)
    end
end

local flu = Config.Conditions.flu
check('severity starts at 1', Rules.severityAt(flu, 0, 30) == 1)
check('severity climbs', Rules.severityAt(flu, 31, 30) == 2)
check('severity caps', Rules.severityAt(flu, 9999, 30) == flu.severityMax)
check('own step wins', Rules.severityAt({ severityMax = 4, severityStepMinutes = 15 }, 30, 30) == 3)
check('max 1 never climbs', Rules.severityAt({ severityMax = 1 }, 500, 30) == 1)

check('not before its time', not Rules.recovers(flu, 1, 10))
check('flu clears at max when time is up', Rules.recovers(flu, flu.severityMax, 20 + 90))
local nd = { durationMinutes = 60, severityMax = 3, needsDoctor = true }
check('needsDoctor stays at max', not Rules.recovers(nd, 3, 600))
check('needsDoctor below max clears', Rules.recovers(nd, 2, 600))
check('no duration never clears', not Rules.recovers({}, 1, 9999))

check('rest seconds', Rules.restSeconds(3, 10) == 1800)
check('rest seconds floor', Rules.restSeconds(0, 10) == 600)
check('rest: pill conditions refused', not Rules.restTreats({ treatment = 'antiviral' }, { stage = 'symptomatic' }))
check('rest: incubating refused', not Rules.restTreats({}, { stage = 'incubating' }))
local ok, why = Rules.restTreats({ requiresConfirmation = true }, { stage = 'symptomatic' })
check('rest: undiagnosed refused with reason', ok == false and why == 'undiagnosed')

check('zone any', Rules.zoneMatches({}, 5))
check('zone head', Rules.zoneMatches({ zones = { 'head' } }, 1) and not Rules.zoneMatches({ zones = { 'head' } }, 2))
check('zone body', Rules.zoneMatches({ zones = { 'body' } }, 2))
check('listHas', Rules.listHas({ 'a', 'b' }, 'b') and not Rules.listHas(nil, 'b'))

print(('%d passed, %d failed'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
