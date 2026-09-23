# dps-medical

Patient records, illness and diagnostic tests for Del Perro Sands (Qbox).
A companion to **wasabi_ambulance_v2** — it reads what wasabi already knows about
a body and adds the half wasabi does not model: what a patient has *caught*, how
a medic finds out, and the chart that follows the patient around.

Version 0.1.0. `CHANGES.md` is the review brief for this import; this file is
how the thing works.

## The one design rule

- **Trauma belongs to wasabi_ambulance_v2.** It models 6 limbs × 7 injury types
  (gunshot, cut, brokenbone, burn, taser, blunt, fist) and applies every
  consequence itself — bleeding, stun, knockout. This resource subscribes to the
  events wasabi already re-broadcasts from its un-escrowed `bridge/listeners/`
  and applies **no effects of its own** to trauma. Nothing here can ever
  disagree with what the player is actually feeling.
- **Illness belongs to this resource.** Incubation, symptoms, contagion,
  treatment, immunity, and the tie-in where untreated trauma turns into illness.
- **Symptoms are ambiguous on purpose.** Flu and the respiratory virus share
  fever/cough/fatigue; concussion and food poisoning share nausea. A test returns
  a *finding* ("Temperature 39.1°C"), never the answer. The medic interprets it,
  and the tests that settle it are hospital-only — so transport matters.

## Requirements

| Resource | Why |
|---|---|
| `ox_lib` | callbacks, context menus, commands, notifications |
| `oxmysql` | the three tables below |
| `qbx_core` | jobs, citizen ids, player load/unload |
| `wasabi_ambulance_v2` | source of all trauma data and the inspection UI the diagnostics menu hangs off |
| `ox_inventory` | the seven items in `install/items.lua` |
| `lb-tablet` (optional) | hosts the chart as a tablet app; everything also works from the commands without it |

## Install

1. Drop the folder in `[dps]` (or anywhere after `qbx_core`; `fxmanifest.lua`
   declares `ox_lib`, `oxmysql` and `qbx_core` as dependencies).
2. **Database** — `mariadb qbox < install/install.sql`. The resource does not
   create its tables itself.
3. **Items** — merge `install/items.lua` into `ox_inventory/data/items.lua`.
   Item images are not shipped yet (see Known gaps).
4. **Jobs** — `install/jobs-sams-omc.lua` is the block that replaced the stock
   `ambulance` job on DPS. Whatever your medical jobs are called, put them in
   `Config.MedicalJobs` *and* in wasabi_ambulance's `ambulanceJobs`; the two
   lists must match or a medic wasabi trusts will be refused here.
5. **Tablet app** (optional) — the two snippets in `install/lb-tablet-config.lua`
   register the "DPS Medical" custom app and whitelist it to the medical jobs.
   The app loads `https://cfx-nui-dps-medical/ui/index.html` straight from this
   resource; nothing is copied into lb-tablet.
6. **Hospitals** — build at least one facility in wasabi with `/facilitypanel`
   (name, allowed jobs, centre, check-in, beds, staff points), then run
   `/reloadfacilities` or restart. Until a facility exists, every hospital-only
   test refuses with a message saying so.
7. Restart the server. Boot should show
   `[dps-medical] ready - 5 conditions defined, tick 60s, contagion 90s` and
   `[dps-medical] client ready - reading wasabi_ambulance, applying nothing`.

## How it works

### Illness lifecycle

`contract(citizenid, key)` inserts a row in `dps_medical_conditions` at stage
`incubating`. A server timer (`Config.TickSeconds`, 60 s) advances every open
row: incubation ends → `symptomatic`; severity climbs toward `severityMax`;
untreated conditions resolve on their own after `durationMinutes`; recovery
grants immunity for `immunityMinutes` where the definition says so. Treatment
is an inventory item named in the condition (`antiviral`, `antibiotics`,
`antiemetic`); concussion has none — rest only.

The patient sees **symptoms**, never the condition name, until a medic records
a diagnosis. That is what keeps a doctor a doctor.

### Contagion

Every `Config.ContagionSeconds` (90 s) the server reads the coordinates of
players who are currently contagious — only those — and rolls
`ContagionBaseChance × contagionModifier` against anyone within
`ContagionDistance` (4 m). Immunity and an existing case both block a new one.
It is a slow timer over a short list, not a scanner.

### Trauma → illness (`onsetFrom`)

The only place wasabi's world feeds ours. A condition can declare which injury
types, in which zones, left untreated for how long, may cause it:

- **Wound infection** — an open gunshot, cut or burn left 25 min, 35 % chance.
- **Concussion** — blunt or fist trauma to the head, immediate, 45 % chance.

The check runs off wasabi's `OnInjuryUpdate` event and the tick, and reads
wasabi's limb data; it never writes to it.

### Diagnostic tests

| Key | Item | Where | Reports on |
|---|---|---|---|
| `thermometer` | thermometer | field | fever |
| `pulseox` | pulseox | field | breathlessness |
| `penlight` | penlight | field | blurred vision (suggests a head injury, does not prove it) |
| `bloodtest` | bloodtest_kit | **facility** | confirms flu / respiratory virus / infection |
| `xray` | fixed equipment | **facility** | confirms a broken bone (reads wasabi's limbs) |
| `ctscan` | fixed equipment | **facility** | confirms concussion |

`where = 'facility'` means the medic must be within `Config.FacilityRadius`
(30 m) of a point belonging to a wasabi facility. Facility points are read from
wasabi's own `wsb_ambulance_facilities` table — every coordinate in a facility's
`locations` JSON counts as part of the building — so there is exactly one
definition of "hospital" on the server.

A test appends a `diagnosis` row to the patient's chart with the finding and
who ran it.

### Conditions shipped

| Key | Label | Symptoms | Incubation | Contagious | Treatment |
|---|---|---|---|---|---|
| `flu` | Influenza | fever, cough, fatigue | 20 min | yes | antiviral |
| `covid` | Respiratory Virus | fever, cough, fatigue, loss of taste, breathlessness | 45 min | yes (×1.6) | antiviral |
| `food_poisoning` | Food Poisoning | nausea, fatigue | 10 min | no | antiemetic |
| `infection` | Wound Infection | fever, localised pain, fatigue | 30 min | no | antibiotics |
| `concussion` | Concussion | headache, blurred vision, nausea | 2 min | no | rest |

## In game

**Anyone**

- `/health` (bindable: *Check how you feel*) — an ox_lib menu of your injured
  limbs and bleeding stage from wasabi, your current symptoms in plain words,
  and any diagnosis a medic has recorded. Until the phone app lands this is the
  patient view.

**Medical staff** (`Config.MedicalJobs`)

- Inspect a patient in wasabi's inspection UI; the chart is pushed into it.
- `/diagnostics` (bindable: *Medical: diagnostics on inspected patient*) —
  menu of tests for the patient you are inspecting. Hospital-only tests are
  greyed out unless you are at a facility.
- `/runtest <id> <test>` — the same thing by command.
- `/diagnose <id> <condition>` — record a diagnosis. From then on the patient
  sees the condition's name.
- The **DPS Medical** tablet app — the chart: live trauma from wasabi, active
  conditions, and the visit history from `dps_medical_visits`.

**Admin** (`group.admin`)

- `/givecondition <id> <condition>` — infect a player (source `admin`).
- `/curecondition <id> <condition>` — resolve it as treated.
- `/reloadfacilities` — re-read hospital points after `/facilitypanel`.

## Configuration (`config.lua`)

| Key | Default | Meaning |
|---|---|---|
| `MedicalJobs` | `sams, omc, rmc` | who can run tests and diagnose; mirror wasabi's `ambulanceJobs` |
| `RecordReadJobs` | same | who may read a chart without treating |
| `TickSeconds` | 60 | illness engine tick |
| `ContagionSeconds` | 90 | contagion pass |
| `ContagionDistance` | 4.0 m | airborne range |
| `ContagionBaseChance` | 0.12 | per-check chance before the condition's modifier |
| `FacilityRadius` | 30.0 m | "at the hospital" |
| `Symptoms` | 9 | label + what the patient reads |
| `Tests` | 6 | see above; `detects` narrows, `confirms` names |
| `Conditions` | 5 | see above; `onsetFrom` is the trauma hook |
| `Debug` | false | print every infection and progression |

## API

**Server exports**

```lua
exports['dps-medical']:recordVisit(citizenid, {
    event_type = 'note', notes = 'Discharged against advice',
    staff_citizenid = ..., staff_name = ..., staff_job = ...,
})
exports['dps-medical']:contract(citizenid, 'flu', { source_kind = 'environment' }) --> row id, or nil if immune / already has it
exports['dps-medical']:atFacility(src) --> facility name, or nil
```

**Client exports**

```lua
exports['dps-medical']:getMyState()          --> { body, bleeding, symptoms, diagnosed }
exports['dps-medical']:pushChart(serverId)   -- re-send a patient's chart to the UI
```

**ox_lib callbacks** — `dps-medical:runTest(patientSrc, testKey)`,
`dps-medical:testAvailability()`, `dps-medical:getMyState()`,
`dps-medical:getChartFor(serverId)`, `dps-medical:getChart(citizenid)`.

**Events consumed** — `wasabi_ambulance:Server:Listeners:{OnDeath, OnRevive,
OnHealingItemUsed, OnFacilityHeal, OnInjuryUpdate}`,
`wasabi_ambulance:Client:Listeners:{OnInjuryUpdate, OnStatusChange,
OnInspectionOpen, OnInspectionClose}`, `qbx_core:server:playerLoaded`,
`qbx_core:server:playerUnloaded`, `qbx_core:client:onJobUpdate`.

## Database

| Table | Holds |
|---|---|
| `dps_medical_visits` | the permanent chart: one row per event (injury, treatment, diagnosis, condition, note) with who did it |
| `dps_medical_conditions` | every case, open or resolved, with stage, severity, source and timestamps |
| `dps_medical_immunity` | one row per citizen per condition, with expiry |

All keyed on `citizenid`, so a record survives character reloads and is
readable by anything else on the server.

## The chart UI

`ui/index.html` is deliberately **not** declared as `ui_page`. lb-tablet loads
it inside its app frame, and wasabi's inspection UI receives it by
`SendNUIMessage`, so this resource never takes NUI focus of its own.

## Known gaps

- The seven item images are missing from `ox_inventory/web/images/`; the items
  work but render blank.
- No hospital facility is built yet on DPS, so the facility-only path has not
  been exercised in game.
- Where the patient self-view lives long-term (phone app, hotkey, both) is an
  open decision; `/health` is the interim.
- No test suite.

See `CHANGES.md` for the full review brief and the questions still open.
