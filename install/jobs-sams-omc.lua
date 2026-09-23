-- qbx_core/shared/jobs.lua — the block that REPLACED ['ambulance'] on 2026-09-22.
-- Exact copy of what is live. Both jobs are type 'ems' so every resource that
-- gates on job type (wasabi_ambulance, wasabi_mdt, dispatch) treats them as
-- medical. 'rmc' (Roxwood Medical Center) already existed and is unchanged.

    ['sams'] = { -- San Andreas Medical Services: the ambulance service, field care.
        label = 'San Andreas Medical Services',
        type = 'ems',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'EMT Trainee', payment = 75 },
            [1] = { name = 'EMT', payment = 95 },
            [2] = { name = 'Advanced EMT', payment = 115 },
            [3] = { name = 'Paramedic', payment = 135 },
            [4] = { name = 'Senior Paramedic', payment = 155 },
            [5] = { name = 'Field Supervisor', payment = 180 },
            [6] = { name = 'Chief of EMS', isboss = true, bankAuth = true, payment = 205 },
        },
    },
    ['omc'] = { -- Ocean Medical Center: the Los Santos hospital, clinical staff.
        label = 'Ocean Medical Center',
        type = 'ems',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Orderly', payment = 70 },
            [1] = { name = 'Nurse', payment = 110 },
            [2] = { name = 'Charge Nurse', payment = 140 },
            [3] = { name = 'Physician', payment = 180 },
            [4] = { name = 'Surgeon', payment = 215 },
            [5] = { name = 'Chief of Medicine', isboss = true, bankAuth = true, payment = 245 },
        },
    },
