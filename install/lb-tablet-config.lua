-- lb-tablet/config/config.lua — the two snippets that wire the chart into the
-- tablet, exactly as live on 2026-09-23.

-- 1. Job whitelist (around line 184). Must agree with Config.MedicalJobs in
--    dps-medical/config.lua; the resource gates inside itself as well.
Config.WhitelistApps = {
    ["DPS Medical"] = { "sams", "omc", "rmc" }, -- DPS: medical staff only
    -- ["Calculator"] = { "police", "ambulance" }
}

-- 2. The app itself (around line 369). `ui` points straight at this resource's
--    page, so nothing is duplicated into the tablet.
Config.CustomApps = {
    -- DPS Medical (dps-medical). The chart a medic works from: live trauma read
    -- out of wasabi_ambulance, illness, and the patient's history. The app frame
    -- is served straight from our own resource, so nothing is duplicated here.
    -- Job-gated above in Config.WhitelistApps as well as inside the resource.
    {
        identifier = 'dps-medical',
        name = 'DPS Medical',
        description = 'Patient charts, conditions and treatment history',
        developer = 'Del Perro Sands',
        size = 140,
        defaultApp = true,
        ui = 'https://cfx-nui-dps-medical/ui/index.html',
    },
}

-- Related, same file: Config.DispatchEnabled = false (wasabi_mdt owns dispatch)
-- and the tablet's own MDT list (mdts.json) was emptied for the same reason.
