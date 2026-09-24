# dps-medical — review brief

Everything medical that changed on Del Perro Sands on 2026-09-22/23, in one place so
a second pair of eyes can review it without access to the live server. The resource
itself is at the root of this repo; everything that had to change in *other*
resources is under `install/`, as exact copies of what is live.

## What this is

A companion to **wasabi_ambulance_v2** that adds what wasabi does not model:
patient records, illness, and diagnostic tests — surfaced as a chart inside the
lb-tablet app frame and as a couple of ox_lib context menus.

The design rule, stated in `fxmanifest.lua` and worth holding the review to:

- **Trauma is wasabi's.** It models 6 limbs × 7 injury types (gunshot, cut,
  brokenbone, burn, taser, blunt, fist) and applies every consequence itself.
  We *subscribe* to the events it already re-broadcasts from its un-escrowed
  `bridge/listeners/` and apply **no effects of our own** to trauma, so nothing
  here can disagree with what the player is feeling.
- **Illness is ours.** Nothing on the server modelled it before this.
- **Symptoms are ambiguous by design.** Several conditions share symptoms; only a
  test separates them, and a test returns a *finding*, not the answer. A blood
  panel is hospital-only, so transport matters.

## Files

| Path | Lines | What |
|---|---|---|
| `fxmanifest.lua` | — | No `ui_page`: the chart is served to lb-tablet at `https://cfx-nui-dps-medical/ui/index.html`, so this resource never takes NUI focus. |
| `config.lua` | 216 | Medical jobs, symptoms, tests (`where = field / facility`), conditions with incubation / contagion / treatment / immunity, and `onsetFrom` hooks that let untreated trauma cause illness. |
| `server/main.lua` | 734 | Illness engine (60 s tick, 90 s contagion pass, 4 m airborne range), wasabi listener handlers, facility lookup, callbacks, commands, DB writes. |
| `client/main.lua` | 281 | Listens to wasabi client events, `/diagnostics` menu (medics), `/health` self-view (everyone), pushes the chart into wasabi's inspection UI when it opens. |
| `ui/index.html` | 200 | The chart page the tablet app loads. |
| `install/install.sql` | — | The three tables, copied from `SHOW CREATE TABLE` on the live DB. The resource does **not** create them itself. |
| `install/jobs-sams-omc.lua` | — | The block that replaced `['ambulance']` in `qbx_core/shared/jobs.lua`. |
| `install/items.lua` | — | The seven item definitions added to `ox_inventory/data/items.lua` for this resource. |
| `install/lb-tablet-config.lua` | — | The two snippets in `lb-tablet/config/config.lua`: the custom app and its job whitelist. |

## Interface surface (what a reviewer should trace)

**Consumed from wasabi_ambulance_v2** (server): `OnDeath`, `OnRevive`,
`OnHealingItemUsed`, `OnFacilityHeal`, `OnInjuryUpdate`. (client):
`OnInjuryUpdate`, `OnStatusChange`, `OnInspectionOpen`, `OnInspectionClose`.
All under `wasabi_ambulance:{Server,Client}:Listeners:*`.

**Consumed from qbx_core:** `qbx_core:server:playerLoaded` / `playerUnloaded`,
`qbx_core:client:onJobUpdate` (and the QBCore-named alias).

**Callbacks (ox_lib):** `dps-medical:runTest`, `testAvailability`, `getMyState`,
`getChartFor` (by server id), `getChart` (by citizenid).

**Commands:** `/diagnostics` (medic menu), `/health` (patient self-view),
`/runtest`, `/diagnose`, `/givecondition`, `/curecondition`, `/reloadfacilities`.
Job-gating is inside the resource (`Config.MedicalJobs`) *and* in lb-tablet's
whitelist; both must agree.

**Exports:** server `recordVisit`, `contract`, `atFacility`; client `pushChart`,
`getMyState`.

**Facilities:** read from wasabi's own `wsb_ambulance_facilities` table (built in
game with `/facilitypanel`) so the two systems can never disagree about where a
hospital is. `Config.FacilityRadius = 30.0`.

## Changes made outside this resource

1. **Job split** (`qbx_core/shared/jobs.lua`): `ambulance` removed; `sams`
   (San Andreas Medical Services — field EMS, 7 grades) and `omc` (Ocean Medical
   Center — hospital, 6 grades) added, both `type = 'ems'`. `rmc` (Roxwood
   Medical Center) unchanged. Existing `ambulance` players were migrated to
   `sams` at the same grade. Every reference to `ambulance` in other resources'
   configs was updated on 2026-09-22 — **reviewer: worth a fresh grep**, in
   particular wasabi_ambulance's `ambulanceJobs` list, which `Config.MedicalJobs`
   mirrors and must stay in step with.
2. **Items** (`ox_inventory/data/items.lua`): the seven in `install/items.lua`.
   In the same pass, wasabi_ambulance's and wasabi_police's shipped `_invItems`
   (never merged at install) were added — `medkit firstaidkit painkillers ifak
   forceps suture splint traumakit medbag` and 14 police items — and 97
   duplicate item keys were removed from the file.
3. **lb-tablet:** custom app `dps-medical` (default app) and
   `Config.WhitelistApps["DPS Medical"] = { "sams", "omc", "rmc" }`. The tablet's
   own MDT was removed (`mdts.json` emptied) because wasabi_mdt owns MDT and
   dispatch.
4. **Database:** the three tables in `install/install.sql`, applied by hand.

## Known gaps — please do not report these as new

- **The seven item images are missing** from `ox_inventory/web/images/`
  (`thermometer pulseox penlight bloodtest_kit antiviral antibiotics
  antiemetic`). The items work; they show blank in the inventory grid.
- **No hospital facilities are built yet** (`wsb_ambulance_facilities` was empty
  at the time of writing; Ocean Medical Center was mid-setup in `/facilitypanel`).
  Until one exists, every `where = 'facility'` test reports "not at a facility",
  which is correct behaviour but means the hospital path is untested in game.
- **Where the patient self-view lives** is undecided: it is `/health` today;
  phone app vs. hotkey vs. both is an open call.
- `Config.Debug = false`; there is no test suite in this repo yet.

## Review round 1 — fixed 2026-09-23

Four findings from the first outside read, all confirmed in code and fixed in
`server/main.lua` (plus three item lines):

1. **Memory never caught up with the tick.** The tick flipped `stage` to
   `symptomatic` with SQL, but every reader (`runTest`, `getMyState`,
   contagion) works from the in-memory cache, which still said `incubating`
   until the player relogged. Added `syncConditions()` — after the tick's SQL
   it re-reads stage/severity/diagnosis for every online unwell player. Same
   class of bug from the other side: players already online when the resource
   (re)started had an empty cache; a start-up pass now hydrates them.
2. **Treatment items did nothing.** No use hook existed. The three medications
   now carry `server = { export = 'dps-medical.useMedication' }`
   (`install/items.lua`); the export refuses the item (not consumed) if the
   player has nothing it treats, otherwise resolves the matching condition(s)
   as `treated` and writes a `treatment` row to the chart.
3. **Wound infection could never fire.** Only `untreatedMinutes == 0` was ever
   checked. `woundSince` now records when each open wound was first seen
   (wasabi's limb data has no timestamps); the tick rolls each wound **once**
   per condition when it crosses the age line. Clock resets on relog — known.
4. **Severity never moved.** The tick now raises it one step every
   `durationMinutes / severityMax` minutes while symptomatic, capped at
   `severityMax`, via SQL; `syncConditions()` mirrors it into memory.

**Round 1b — the deltas from the written spec (same day):**

- `resolve()` now stamps `treated_at` when `how == 'treated'`, and the immunity
  row's `reason` records `treated` vs `recovered` instead of always `recovered`.
- Severity step is config: `Config.SeverityStepMinutes` (30) with a per-condition
  `severityStepMinutes` override. **At `severityMax` a condition no longer clears
  on its own** — someone has to treat it. Severity rides on every symptom in
  `getMyState`, and `/health` scales the wording with `Config.SeverityWords`.
- Medications: `client = { usetime = 4000 }` gives a progress bar on self-use.
  `applyTreatment()` is shared by self-use and the new **`/administer <id> <item>`**
  (and `dps-medical:administer` callback) — medic within
  `Config.AdministerDistance` (3 m), item comes out of the medic's inventory,
  refused unconsumed if the patient has nothing it treats, chart row records
  who gave it.
- Contagion guards, both config: `ContagionDuringIncubation = 0.25` multiplier
  while a carrier is still incubating, `MaxNewInfectionsPerPass = 2` per carrier
  per pass.

## Part B step 3 — stations (B1 + B2), plus three asks from the same session

**Stations replace the radius.** `Config.Stations` is the registry: one real
map prop, one patient at a time, `kind` ∈ `Config.StationKinds`
(`bed bloodlab xray ct mri`). A hospital-only test's `where` is now a station
kind, and `runTest` gates on the *patient* occupying a station of that kind
with the medic beside it (`Config.StationInteractDistance`). No station of a
kind on the server = that test does not exist here. `Config.FacilityRadius`
remains only for the `atFacility` export. `confirmsInjury` (X-ray → broken
bone from wasabi's limb data) was declared but never evaluated; it is now.

**Occupancy** lives server-side (`stationOccupant` / `patientStation`), is
broadcast to clients, cleared on disconnect. Target options on every station
prop: one "use" option per kind ("Lie down", "Sit for a sample"…), "Get up",
and "Release patient" for medics. Imaging kinds (`canLeave = false`) hold the
patient until the scan completes or a medic releases them; beds let go when
the patient walks off. Downed players are refused — that is wasabi's stretcher.

**Add-on to wasabi, enforced:** a station must belong to a wasabi facility.
`/stationcapture <kind> [facility]` (admin) raycasts the prop being looked at,
takes the admin's position as the slot, resolves the facility from the wasabi
facility the admin is standing in when none is named (refuses outside one),
and appends a paste-ready block to `station_captures.txt`. Boot warns about any
station naming a facility wasabi does not have.

**Ocean Medical Center's nine beds are in.** Not captured: generated from
wasabi's own bed list in `wsb_ambulance_facilities` (model `lit1_hospital`),
flagged `wasabiBed = true`. Those beds keep wasabi's own menu — we register no
target options on them — and occupancy is read from wasabi's `getPlayerBed`
export matched by position (`stationOfPatient`). Lab and imaging stations for
OMC still need `/stationcapture` in game.

**Guess, don't diagnose.** Conditions carry `requiresConfirmation`. A
`confirms` hit in a test stamps `confirmed_at` (new column, in
`install/install.sql`). `/diagnose` refuses an unconfirmed condition that
requires it; medication (self-use and `/administer`) refuses, unconsumed, a
condition that requires confirmation and is not yet diagnosed. Food poisoning
is the one treat-on-sight condition. Two placeholder conditions were added so
the CT and MRI stations confirm something: `internal_bleed`, `soft_tissue` —
numbers marked TUNE.

**Breadcrumbs.** `Config.HintsBelowGrade` / `Config.Hints`: staff below the
grade get a hint on every refusal (station, confirm, treat_undiagnosed)
explaining what to do instead; above it, nothing.

## Verify

```
luac5.4 -p client/main.lua server/main.lua config.lua
```
Boot: `Started resource dps-medical` with no script errors; `/reloadfacilities`
prints the facility count; `/health` opens for any player; `/diagnostics` opens
only for `sams` / `omc` / `rmc`.

## Questions for the reviewer

1. Is subscribing to wasabi's `bridge/listeners` events a stable contract, or
   does an update to wasabi_ambulance_v2 risk silently breaking us?
2. The contagion pass reads coords for contagious players every 90 s. Is that
   acceptable at 64+ players, or should it be event-driven?
3. `onsetFrom` (untreated gunshot → infection, head blunt → concussion) is the
   only place trauma feeds illness. Does the timing (`untreatedMinutes`) read
   right for RP pacing?
4. Anything in `server/main.lua` that should be an export for a future
   disease-outbreak module, rather than a command?
