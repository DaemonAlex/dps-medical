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
