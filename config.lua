-- dps-medical configuration.
--
-- The design rule that makes illness worth playing: SYMPTOMS MUST BE AMBIGUOUS.
-- If a cough tells you it is covid, there is no doctor - just a lookup. Several
-- conditions here deliberately share symptoms, and only a TEST separates them.

Config = {}

-- ===========================================================================
-- Who is medical staff
-- ===========================================================================

-- Mirrors wasabi_ambulance's own ambulanceJobs list so the two never disagree
-- about who is a medic. Keep them in step.
Config.MedicalJobs = { 'sams', 'omc', 'rmc' }

-- Jobs that may also read a chart without being able to treat (front desk, etc).
Config.RecordReadJobs = { 'sams', 'omc', 'rmc' }

-- ===========================================================================
-- Illness engine
-- ===========================================================================

-- How often the server advances illness: incubation ending, symptoms worsening,
-- recovery, immunity expiry. This is a slow server-side timer, not a scanner.
Config.TickSeconds = 60

-- How often we look for contagion. Only players who ARE contagious are
-- considered, and only their own coords are read, so this stays cheap.
Config.ContagionSeconds = 90

-- How close two players must be for airborne transmission, in metres.
Config.ContagionDistance = 4.0

-- Base chance per contagion check when in range, before per-condition modifiers.
Config.ContagionBaseChance = 0.12

-- Carriers still incubating spread at this fraction of the normal chance. A
-- 45-minute silent window at full strength seeded a room before anyone knew.
Config.ContagionDuringIncubation = 0.25

-- One carrier can start at most this many new cases per contagion pass.
Config.MaxNewInfectionsPerPass = 2

-- Severity climbs one step every this many minutes while symptomatic and
-- untreated, up to the condition's severityMax. A condition may override with
-- its own severityStepMinutes. At severityMax it no longer clears on its own.
Config.SeverityStepMinutes = 30

-- How the patient hears a symptom at each severity. Never the illness name.
Config.SeverityWords = { [1] = 'mild', [2] = 'getting worse', [3] = 'severe', [4] = 'critical' }

-- How close a medic must be to give a patient a medication, in metres.
Config.AdministerDistance = 3.0

-- Set true to print every infection and progression to the server console.
Config.Debug = false

-- ===========================================================================
-- Symptoms
-- ===========================================================================
--
-- What the PATIENT feels. Deliberately non-specific: the player sees these,
-- never the condition name, until a medic diagnoses them.
Config.Symptoms = {
    fever       = { label = 'Fever',          patient = 'You feel hot and shivery.' },
    cough       = { label = 'Cough',          patient = "You can't stop coughing." },
    fatigue     = { label = 'Fatigue',        patient = 'You feel drained and heavy.' },
    nausea      = { label = 'Nausea',         patient = 'Your stomach is turning.' },
    headache    = { label = 'Headache',       patient = 'Your head is pounding.' },
    blurred     = { label = 'Blurred vision', patient = 'Your vision keeps swimming.' },
    anosmia     = { label = 'Loss of taste',  patient = "You can't taste or smell anything." },
    sitepain    = { label = 'Localised pain', patient = 'One of your old wounds is throbbing and hot.' },
    breathless  = { label = 'Breathlessness', patient = 'You are short of breath.' },
}

-- ===========================================================================
-- Diagnostic tests
-- ===========================================================================
--
-- This is what makes a doctor a doctor. A test does not hand over the answer;
-- it returns a FINDING, and the medic interprets it. `detects` narrows to a
-- symptom; `confirms` names a condition outright - note the overlaps.
--
-- `where` is the field/hospital split:
--   'field'    - portable, works anywhere. A medic can carry it in the bag.
--   'facility' - needs the equipment of a hospital, so the patient has to be
--                brought in. This is what makes transport and hospitals matter.
--
-- Facility locations are NOT defined here. They are read from wasabi's own
-- `wsb_ambulance_facilities` table (set up in game with /facilitypanel) so the
-- two systems can never disagree about where a hospital is.
Config.Tests = {
    -- ---- Field kit -------------------------------------------------------
    thermometer = {
        label = 'Thermometer',
        item = 'thermometer',
        where = 'field',
        duration = 4000,
        finding = 'Temperature %s°C',
        detects = { 'fever' },                 -- narrows, never confirms
    },
    pulseox = {
        label = 'Pulse oximeter',
        item = 'pulseox',
        where = 'field',
        duration = 3000,
        finding = 'SpO2 %s%%',
        detects = { 'breathless' },
    },
    penlight = {
        label = 'Pen light',
        item = 'penlight',
        where = 'field',
        duration = 3000,
        finding = 'Pupils %s',
        detects = { 'blurred' },               -- suggestive of a head injury, not proof
    },

    -- ---- Hospital only ---------------------------------------------------
    bloodtest = {
        label = 'Blood panel',
        item = 'bloodtest_kit',
        where = 'facility',
        duration = 9000,
        finding = 'Panel returned: %s',
        confirms = { 'flu', 'covid', 'infection' },
    },
    xray = {
        label = 'X-ray',
        item = false,                          -- fixed equipment, no item to carry
        where = 'facility',
        duration = 12000,
        finding = 'Imaging shows %s',
        confirmsInjury = { 'brokenbone' },      -- reads wasabi's limb data, not an illness
    },
    ctscan = {
        label = 'CT scan',
        item = false,
        where = 'facility',
        duration = 15000,
        finding = 'Scan shows %s',
        confirms = { 'concussion' },
    },
}

-- How close to a facility location counts as "at the hospital", in metres.
Config.FacilityRadius = 30.0

-- ===========================================================================
-- Conditions
-- ===========================================================================
--
-- incubationMinutes : how long before symptoms show. The patient has it the
--                     whole time and can already spread it - that is the point.
-- durationMinutes   : how long symptomatic if never treated.
-- contagious        : can pass to another player in range.
-- treatment         : item that cures it. nil = rest and time only.
-- immunityMinutes   : how long they are immune after recovery; false = none.
-- onsetFrom         : hooks that let TRAUMA cause illness, tying the two halves
--                     together - an untreated gunshot can go septic.
-- severityMax       : how far severity climbs. At max it will NOT clear on its
--                     own any more - someone has to treat it.
-- severityStepMinutes : optional; overrides Config.SeverityStepMinutes.
Config.Conditions = {
    flu = {
        label = 'Influenza',
        symptoms = { 'fever', 'cough', 'fatigue' },
        incubationMinutes = 20,
        durationMinutes = 90,
        contagious = true,
        contagionModifier = 1.0,
        treatment = 'antiviral',
        immunityMinutes = 720,
        severityMax = 3,
    },

    covid = {
        label = 'Respiratory Virus',
        -- Shares fever/cough/fatigue with flu on purpose. Only anosmia hints,
        -- and only a blood panel confirms.
        symptoms = { 'fever', 'cough', 'fatigue', 'anosmia', 'breathless' },
        incubationMinutes = 45,
        durationMinutes = 180,
        contagious = true,
        contagionModifier = 1.6,
        treatment = 'antiviral',
        immunityMinutes = 1440,
        severityMax = 4,
    },

    food_poisoning = {
        label = 'Food Poisoning',
        symptoms = { 'nausea', 'fatigue' },
        incubationMinutes = 10,
        durationMinutes = 45,
        contagious = false,
        treatment = 'antiemetic',
        immunityMinutes = false,
        severityMax = 2,
    },

    infection = {
        label = 'Wound Infection',
        -- Caused by trauma left untreated: the tie-in between wasabi and us.
        symptoms = { 'fever', 'sitepain', 'fatigue' },
        incubationMinutes = 30,
        durationMinutes = 150,
        contagious = false,
        treatment = 'antibiotics',
        immunityMinutes = false,
        severityMax = 4,
        onsetFrom = {
            -- An open wound of these types, left on the body this long, may go septic.
            injuryTypes = { 'gunshot', 'cut', 'burn' },
            untreatedMinutes = 25,
            chance = 0.35,
        },
    },

    concussion = {
        label = 'Concussion',
        symptoms = { 'headache', 'blurred', 'nausea' },
        incubationMinutes = 2,
        durationMinutes = 60,
        contagious = false,
        treatment = nil,              -- rest only; there is no pill for this
        immunityMinutes = false,
        severityMax = 3,
        onsetFrom = {
            injuryTypes = { 'blunt', 'fist' },
            zones = { 'head' },
            untreatedMinutes = 0,     -- immediate on head trauma
            chance = 0.45,
        },
    },
}
