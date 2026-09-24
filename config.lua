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

-- Transfer (B3). A medic moves a CONSCIOUS patient onto a free station:
-- target the station, "Transfer patient here", the nearest player within this
-- distance is the patient. Downed players go on wasabi's stretcher, not this.
Config.TransferDistance = 3.0

-- No staff on duty (B4). When nobody from Config.MedicalJobs is on duty, a
-- patient lying on a bed can ask the desk for treatment. The desk runs a
-- generic workup (a finding line, never a condition name), charges up front,
-- and clears each condition after severity * minutesPerSeverity on the bed.
-- The clock only runs while the patient is on the bed. The option is hidden
-- the moment a medic goes on duty; a medic treating the patient ends the stay.
Config.Npc = {
    minutesPerSeverity = 10,
    costPerSeverity = 250,
    workup = 'Desk workup: %s. Admitted for observation.',
}

-- Breadcrumbs. Staff below this job grade get a hint on every refusal telling
-- them what to do instead; from this grade up the system assumes they know.
Config.HintsBelowGrade = 3

Config.Hints = {
    station = 'Hospital tests run on the equipment: have the patient lie on the bed or sit at the lab (target the prop), then run the test standing next to it.',
    confirm = 'You can suspect it, but the chart only takes a diagnosis a test has confirmed. Run the blood panel or the right scan first, then /diagnose.',
    treat_undiagnosed = 'Medication only goes on a diagnosed condition. Confirm it with a test, /diagnose it, then treat.',
    transfer = 'Stand next to the patient, target the free station and pick "Transfer patient here". Downed patients go on the stretcher instead.',
}

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
--   'field'      - portable, works anywhere. A medic can carry it in the bag.
--   <station kind> - needs that piece of equipment: the PATIENT has to be on a
--                station of this kind (Config.Stations) with the medic beside
--                it. No station of that kind on the server = that test does
--                not exist here. This is what makes transport, hospitals and
--                equipment matter.
--
-- Rule: no condition is confirmable by more than one station kind.
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

    -- ---- Hospital only: each needs its station -----------------------------
    bloodtest = {
        label = 'Blood panel',
        item = 'bloodtest_kit',
        where = 'bloodlab',
        duration = 9000,
        finding = 'Panel returned: %s',
        confirms = { 'flu', 'covid', 'infection' },
    },
    xray = {
        label = 'X-ray',
        item = false,                          -- fixed equipment, no item to carry
        where = 'xray',
        duration = 12000,
        finding = 'Imaging shows %s',
        confirmsInjury = { 'brokenbone' },      -- reads wasabi's limb data, not an illness
    },
    ctscan = {
        label = 'CT scan',
        item = false,
        where = 'ct',
        duration = 15000,
        finding = 'Scan shows %s',
        confirms = { 'concussion', 'internal_bleed' },
    },
    mri = {
        label = 'MRI',
        item = false,
        where = 'mri',
        duration = 18000,
        finding = 'MRI shows %s',
        confirms = { 'soft_tissue' },
    },
}

-- How close to a facility location counts as "at the hospital", in metres.
-- Used by the atFacility export only; tests gate on stations now.
Config.FacilityRadius = 30.0

-- ===========================================================================
-- Stations
-- ===========================================================================
--
-- A hospital is not a radius. It is equipment: a bed, a blood lab, an X-ray,
-- a CT, an MRI. Each is a STATION - one real prop in the map, one patient at
-- a time - and a hospital-only test runs only when the PATIENT is on a station
-- of the right kind. No working MRI on the server means soft-tissue injuries
-- stay undiagnosed. That is the point.
--
-- facility        : must match the facility's name in wasabi (wsb_ambulance_facilities)
-- kind            : key of Config.StationKinds; a test's `where`
-- prop            : model name of the real map object the station is (targetable)
-- coords          : where that prop is
-- slot            : where the patient is placed, with heading
-- anim            : optional; overrides the kind's default
-- transferSeconds : how long a medic's transfer takes
-- wasabiBed       : true = one of wasabi's own facility beds (from its
--                   /facilitypanel bed list). wasabi runs lying down, check-in
--                   and healing there; we add NO menu of our own and read who
--                   is in it from wasabi (getPlayerBed). One bed, one system.
--
-- CAPTURE, no typing: stand where the patient should lie or sit, look straight
-- at the prop, and run  /stationcapture <kind> <facility name>  (admin). The
-- block lands in station_captures.txt inside this resource; paste it below.
Config.StationInteractDistance = 3.0

-- canLeave = false holds the patient until the scan completes or a medic
-- releases them ("Release patient" on the prop).
Config.StationKinds = {
    bed      = { label = 'bed',         patientLabel = 'Lie down',          canLeave = true,
                 anim = { dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 } },
    bloodlab = { label = 'blood lab',   patientLabel = 'Sit for a sample',  canLeave = true,
                 anim = { scenario = 'PROP_HUMAN_SEAT_CHAIR' } },
    xray     = { label = 'X-ray table', patientLabel = 'Lie on the table',  canLeave = false,
                 anim = { dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 } },
    ct       = { label = 'CT scanner',  patientLabel = 'Lie on the table',  canLeave = false,
                 anim = { dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 } },
    mri      = { label = 'MRI',         patientLabel = 'Lie on the table',  canLeave = false,
                 anim = { dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 } },
}

-- /stationcapture writes new entries. The beds below were not typed or
-- captured: they are wasabi's own bed list for the facility, read out of
-- wsb_ambulance_facilities on 2026-09-23 (model 1570477186 = lit1_hospital,
-- the OMC map's custom bed), so the two systems agree bed for bed.
Config.Stations = {
    -- ---- Ocean Medical Center: wards (wasabi beds) --------------------------
    bed_ocean_medical_center_1 = {
        facility = 'Ocean Medical Center',
        kind = 'bed',
        prop = 'lit1_hospital',
        coords = vec4(-1865.75, -332.10, 48.76, 137.5),
        slot = vec4(-1865.75, -332.10, 50.13, 137.5),
        wasabiBed = true,        -- wasabi owns lying down here; we only read it
        transferSeconds = 20,
    },
    bed_ocean_medical_center_2 = {
        facility = 'Ocean Medical Center',
        kind = 'bed',
        prop = 'lit1_hospital',
        coords = vec4(-1868.59, -329.93, 48.76, 141.6),
        slot = vec4(-1868.59, -329.93, 50.13, 141.6),
        wasabiBed = true,        -- wasabi owns lying down here; we only read it
        transferSeconds = 20,
    },
    bed_ocean_medical_center_3 = {
        facility = 'Ocean Medical Center',
        kind = 'bed',
        prop = 'lit1_hospital',
        coords = vec4(-1865.70, -325.47, 48.76, 321.3),
        slot = vec4(-1865.70, -325.47, 50.15, 321.3),
        wasabiBed = true,        -- wasabi owns lying down here; we only read it
        transferSeconds = 20,
    },
    bed_ocean_medical_center_4 = {
        facility = 'Ocean Medical Center',
        kind = 'bed',
        prop = 'lit1_hospital',
        coords = vec4(-1872.32, -326.92, 48.76, 142.3),
        slot = vec4(-1872.32, -326.92, 50.13, 142.3),
        wasabiBed = true,        -- wasabi owns lying down here; we only read it
        transferSeconds = 20,
    },
    bed_ocean_medical_center_5 = {
        facility = 'Ocean Medical Center',
        kind = 'bed',
        prop = 'lit1_hospital',
        coords = vec4(-1868.81, -323.12, 48.76, 321.9),
        slot = vec4(-1868.81, -323.12, 50.13, 321.9),
        wasabiBed = true,        -- wasabi owns lying down here; we only read it
        transferSeconds = 20,
    },
    bed_ocean_medical_center_6 = {
        facility = 'Ocean Medical Center',
        kind = 'bed',
        prop = 'lit1_hospital',
        coords = vec4(-1875.22, -324.74, 48.76, 142.2),
        slot = vec4(-1875.22, -324.74, 50.13, 142.2),
        wasabiBed = true,        -- wasabi owns lying down here; we only read it
        transferSeconds = 20,
    },
    bed_ocean_medical_center_7 = {
        facility = 'Ocean Medical Center',
        kind = 'bed',
        prop = 'lit1_hospital',
        coords = vec4(-1871.96, -320.60, 48.76, 322.2),
        slot = vec4(-1871.96, -320.60, 50.13, 322.2),
        wasabiBed = true,        -- wasabi owns lying down here; we only read it
        transferSeconds = 20,
    },
    bed_ocean_medical_center_8 = {
        facility = 'Ocean Medical Center',
        kind = 'bed',
        prop = 'lit1_hospital',
        coords = vec4(-1878.53, -322.07, 48.76, 141.5),
        slot = vec4(-1878.53, -322.07, 50.13, 141.5),
        wasabiBed = true,        -- wasabi owns lying down here; we only read it
        transferSeconds = 20,
    },
    bed_ocean_medical_center_9 = {
        facility = 'Ocean Medical Center',
        kind = 'bed',
        prop = 'lit1_hospital',
        coords = vec4(-1875.24, -318.05, 48.76, 321.7),
        slot = vec4(-1875.24, -318.05, 50.13, 321.7),
        wasabiBed = true,        -- wasabi owns lying down here; we only read it
        transferSeconds = 20,
    },

    -- ---- Ocean Medical Center: lab and imaging ------------------------------
    -- Captured in game with /stationcapture; paste the blocks from
    -- station_captures.txt here. Until a kind exists its tests refuse.
}

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
-- requiresConfirmation : true = a medic can GUESS it, but /diagnose refuses
--                     until a test that `confirms` it has been run on this
--                     patient, and medication does nothing until it is
--                     diagnosed. false = obvious enough to treat on sight.
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
        requiresConfirmation = true,   -- blood panel
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
        requiresConfirmation = true,   -- blood panel
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
        requiresConfirmation = false,  -- obvious; treat on sight
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
        requiresConfirmation = true,   -- blood panel
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
        requiresConfirmation = true,   -- CT scan
        onsetFrom = {
            injuryTypes = { 'blunt', 'fist' },
            zones = { 'head' },
            untreatedMinutes = 0,     -- immediate on head trauma
            chance = 0.45,
        },
    },

    -- The two conditions the CT and MRI stations exist for. Placeholder
    -- numbers - TUNE. Neither has a pill: they clear with rest while severity
    -- is below max, and at max they wait for a doctor.
    internal_bleed = {
        label = 'Internal Bleeding',
        symptoms = { 'fatigue', 'nausea', 'breathless' },
        incubationMinutes = 5,
        durationMinutes = 120,
        contagious = false,
        treatment = nil,
        immunityMinutes = false,
        severityMax = 4,
        severityStepMinutes = 15,
        requiresConfirmation = true,   -- CT scan
        onsetFrom = {
            injuryTypes = { 'blunt', 'gunshot' },
            zones = { 'body' },
            untreatedMinutes = 10,
            chance = 0.30,
        },
    },

    soft_tissue = {
        label = 'Soft Tissue Injury',
        symptoms = { 'sitepain', 'fatigue' },
        incubationMinutes = 15,
        durationMinutes = 90,
        contagious = false,
        treatment = nil,
        immunityMinutes = false,
        severityMax = 2,
        requiresConfirmation = true,   -- MRI
        onsetFrom = {
            injuryTypes = { 'blunt', 'fist' },
            untreatedMinutes = 15,
            chance = 0.25,
        },
    },
}
