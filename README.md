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
   `/reloadfacilities` or restart.
7. **Stations** — inside that facility, `/stationcapture bed` at each bed,
   `/stationcapture bloodlab` at the lab chair, and so on; paste the blocks
   from `station_captures.txt` into `Config.Stations`; restart. Until a station
   of a kind exists, that kind's tests refuse with a message saying so.
8. Restart the server. Boot should show
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
| `bloodtest` | bloodtest_kit | **bloodlab** station | confirms flu / respiratory virus / infection |
| `xray` | fixed equipment | **xray** station | confirms a broken bone (reads wasabi's limbs) |
| `ctscan` | fixed equipment | **ct** station | confirms concussion / internal bleeding |
| `mri` | fixed equipment | **mri** station | confirms soft tissue injury |

A hospital is not a radius; it is equipment. `where` names a **station kind**,
and the test runs only when the *patient* is on a station of that kind with the
medic standing beside it (`Config.StationInteractDistance`, 3 m). No station of
that kind on the server means that test does not exist here — no MRI, no
soft-tissue diagnoses. That is the point. Rule: no condition is confirmable by
more than one station kind.

A test appends a `diagnosis` row to the patient's chart with the finding and
who ran it, and a confirming hit stamps the condition **confirmed** — which is
what `/diagnose` and the medications check (see *Guess, don't diagnose*).

### Stations

`Config.Stations` is the registry: one real prop in the map, one patient at a
time. Kinds are `bed`, `bloodlab`, `xray`, `ct`, `mri` (`Config.StationKinds`,
each with its own target label and lying/sitting animation). Every station
belongs to a wasabi facility — this is an add-on to wasabi_ambulance, and it
refuses to attach a station anywhere wasabi does not call a hospital.

Wasabi's own facility beds are stations too, marked `wasabiBed = true`, and
they come straight out of wasabi's bed list for the facility — same prop, same
coordinates, so the two systems agree bed for bed. Those beds keep wasabi's
menu (lay, check in, heal); this resource adds nothing on top and reads who is
in one from wasabi's `getPlayerBed` export. One bed, one system.

For everything else nothing is typed by hand. Stand where the patient should
lie or sit, look straight at the prop, and run **`/stationcapture <kind>`**
(admin). The facility
is resolved from the wasabi facility you are standing in; the prop name comes
from the game; the block lands in `station_captures.txt` inside the resource,
ready to paste into `Config.Stations`. Restart, and the prop grows target
options: "Lie down" / "Sit for a sample" when it is free, "Get up" for the
occupant, "Release patient" for staff. Imaging tables hold the patient until
the scan completes or a medic releases them; beds let go when the patient walks
away. Downed players are refused — that is wasabi's stretcher.

### Guess, don't diagnose

A condition with `requiresConfirmation = true` (everything but food poisoning)
can be *suspected* freely, but `/diagnose` refuses it until a test that
`confirms` it has been run on this patient, and medication — the patient's own
or `/administer` — does nothing, and is not consumed, until it is diagnosed.
Symptoms overlap on purpose; the panel or the scan is what separates them.

### Breadcrumbs

Staff below `Config.HintsBelowGrade` get a hint on every refusal telling them
what to do instead ("have the patient lie on the bed, then run the test next to
it"). From that grade up the system assumes they know.

### Transfer

A medic moves a conscious patient onto a free station: stand next to the
patient, target the station, **Transfer patient here**. The nearest player
within `Config.TransferDistance` is the patient; the server re-checks the
station is still free after the `transferSeconds` progress bar, then places
the patient on the slot with the station's animation and writes a `transfer`
visit row. Dead patients are refused (wasabi's stretcher moves the downed);
wasabi's own beds are refused (wasabi owns lying down there).

### The desk (no staff on duty)

When nobody from `Config.MedicalJobs` is on duty, a symptomatic patient lying
on a bed — ours or one of wasabi's — gets **Request treatment** on the bed.
The desk reads the symptoms back as a workup line (never a condition name),
charges `severity × Config.Npc.costPerSeverity` for every active condition,
bank first then cash, and clears each condition after
`severity × Config.Npc.minutesPerSeverity` minutes spent *on the bed*: leaving
pauses the clock and says so. The option disappears the moment a medic goes on
duty (the server pushes the on-duty state; nothing polls). A medic treating
the patient ends the stay early because the conditions are simply gone.
Visits: `admission` (with cost and minutes) and `discharge`, staff `Desk`.

### Conditions shipped

| Key | Label | Symptoms | Incubation | Contagious | Treatment |
|---|---|---|---|---|---|
| `flu` | Influenza | fever, cough, fatigue | 20 min | yes | antiviral |
| `covid` | Respiratory Virus | fever, cough, fatigue, loss of taste, breathlessness | 45 min | yes (×1.6) | antiviral |
| `food_poisoning` | Food Poisoning | nausea, fatigue | 10 min | no | antiemetic |
| `infection` | Wound Infection | fever, localised pain, fatigue | 30 min | no | antibiotics |
| `concussion` | Concussion | headache, blurred vision, nausea | 2 min | no | rest |
| `internal_bleed` | Internal Bleeding | fatigue, nausea, breathlessness | 5 min | no | rest (placeholder — TUNE) |
| `soft_tissue` | Soft Tissue Injury | localised pain, fatigue | 15 min | no | rest (placeholder — TUNE) |

Severity climbs one step every `SeverityStepMinutes` while symptomatic and
untreated, up to `severityMax`; **at max a condition no longer clears on its
own** — someone has to treat it.

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
- `/diagnose <id> <condition>` — record a diagnosis. Refused until the
  confirming test has been run, for conditions that require one. From then on
  the patient sees the condition's name.
- `/administer <id> <item>` — give a medication from your own inventory to a
  patient within 3 m. Refused, unconsumed, if it treats nothing they have or
  the condition is not diagnosed yet.
- On station props: "Release patient" lets anyone off a bed or table.
- The **DPS Medical** tablet app — the chart: live trauma from wasabi, active
  conditions, and the visit history from `dps_medical_visits`.

**Admin** (`group.admin`)

- `/givecondition <id> <condition>` — infect a player (source `admin`).
- `/curecondition <id> <condition>` — resolve it as treated.
- `/reloadfacilities` — re-read hospital points after `/facilitypanel`.
- `/stationcapture <kind> [facility]` — capture the prop you are looking at as
  a station (see *Stations*).

## Configuration (`config.lua`)

- `Config.TransferDistance` — medic-to-patient reach for a transfer (3 m).
- `Config.Npc` — `minutesPerSeverity`, `costPerSeverity`, `workup` (the desk's
  finding line; `%s` is the symptom list).

| Key | Default | Meaning |
|---|---|---|
| `MedicalJobs` | `sams, omc, rmc` | who can run tests and diagnose; mirror wasabi's `ambulanceJobs` |
| `RecordReadJobs` | same | who may read a chart without treating |
| `TickSeconds` | 60 | illness engine tick |
| `ContagionSeconds` | 90 | contagion pass |
| `ContagionDistance` | 4.0 m | airborne range |
| `ContagionBaseChance` | 0.12 | per-check chance before the condition's modifier |
| `ContagionDuringIncubation` | 0.25 | multiplier while a carrier is still incubating |
| `MaxNewInfectionsPerPass` | 2 | cap per carrier per contagion pass |
| `SeverityStepMinutes` | 30 | one severity step per this many minutes symptomatic; per-condition override `severityStepMinutes` |
| `SeverityWords` | mild … critical | how the patient hears each severity |
| `AdministerDistance` | 3.0 m | `/administer` reach |
| `FacilityRadius` | 30.0 m | used by the `atFacility` export only |
| `StationInteractDistance` | 3.0 m | how close to a station a medic or patient must be |
| `StationKinds` | 5 | label, target text, animation and `canLeave` per kind |
| `Stations` | empty | the registry; filled from `/stationcapture` |
| `HintsBelowGrade` / `Hints` | 3 | breadcrumbs for junior staff |
| `Symptoms` | 9 | label + what the patient reads |
| `Tests` | 7 | see above; `detects` narrows, `confirms` names, `where` is a station kind |
| `Conditions` | 7 | see above; `onsetFrom` is the trauma hook, `requiresConfirmation` the diagnosis gate |
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
- No stations are captured yet on DPS (the hospitals are still being built in
  wasabi), so the station path has not been exercised in game.
- The wound-age clock for slow onsets (infection, internal bleeding) restarts
  on relog: wasabi's limb data carries no timestamps.
- Where the patient self-view lives long-term (phone app, hotkey, both) is an
  open decision; `/health` is the interim.
- No test suite.

See `CHANGES.md` for the full review brief and the questions still open.
