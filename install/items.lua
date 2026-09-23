-- ox_inventory/data/items.lua — the seven items this resource needs, exactly as
-- merged on 2026-09-22. Config.Tests and Config.Conditions reference them by key.
--
-- Images are NOT yet present in ox_inventory/web/images/ for any of these; the
-- items function but render blank. Known gap, see CHANGES.md.
--
-- wasabi_ambulance_v2's own items (medkit, firstaidkit, painkillers, ifak,
-- forceps, suture, splint, traumakit, medbag) were merged in the same pass from
-- its _invItems/ folder; they are wasabi's definitions, not ours, so they are
-- not repeated here.

	-- ---- dps-medical: diagnostic instruments -------------------------------
	-- Field kit. These return a finding for the medic to interpret.
	['thermometer'] = {
		label = 'Thermometer',
		description = 'Reads a patient temperature. Narrows things down; proves nothing.',
		weight = 20,
		stack = true,
		close = true,
		consume = 0,
	},
	['pulseox'] = {
		label = 'Pulse Oximeter',
		description = 'Clips to a finger and reads blood oxygen.',
		weight = 30,
		stack = true,
		close = true,
		consume = 0,
	},
	['penlight'] = {
		label = 'Pen Light',
		description = 'Checks pupil response. Suggestive of a head injury, not proof.',
		weight = 10,
		stack = true,
		close = true,
		consume = 0,
	},
	['bloodtest_kit'] = {
		label = 'Blood Test Kit',
		description = 'Draws a sample for a lab panel. Needs hospital equipment to run.',
		weight = 60,
		stack = true,
		close = true,
	},

	-- ---- dps-medical: medications ------------------------------------------
	['antiviral'] = {
		label = 'Antivirals',
		description = 'Course of antivirals. Treats influenza and respiratory viruses.',
		weight = 15,
		stack = true,
		close = true,
		server = { export = 'dps-medical.useMedication' },
	},
	['antibiotics'] = {
		label = 'Antibiotics',
		description = 'Course of antibiotics. Treats a wound infection.',
		weight = 15,
		stack = true,
		close = true,
		server = { export = 'dps-medical.useMedication' },
	},
	['antiemetic'] = {
		label = 'Antiemetics',
		description = 'Settles the stomach. Treats food poisoning.',
		weight = 15,
		stack = true,
		close = true,
		server = { export = 'dps-medical.useMedication' },
	},
