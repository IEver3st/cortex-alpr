# Changelog

## 1.0.0 (2026-11-24)

First release.

### Added
- Moving radar on two antennas, front and rear: strongest target, fastest target, same, opposite or both lanes, a fast limit, manual and automatic locks. Line of sight, beam height and target size decide what it reads.
- Plate reader on two cameras, with plate cards drawn in the 13 Grand Theft Auto V plate styles.
- Hot list: plates every reader looks for, with a reason, a priority, an expiry and the last 12 sightings of each. Officers manage it from `/hotlist` or the Actions wheel; other resources use `AddHotPlate`, `RemoveHotPlate`, `IsHotPlate` and `GetHotPlates`.
- A hit locks the camera, alerts the officer, sends every on-duty officer a sighting with a map blip, and raises one dispatch call per plate.
- Air reader: with Cortex PolCam on, the helicopter camera reads plates and labels hits in the feed.
- Speed locks checked by the server against the vehicle's real speed, with the posted limit when Cortex Radar is running.
- Cortex MDT link: BOLOs, stolen reports and warrants come from the MDT, sightings are written onto the BOLO, and a locked speed opens a citation with the reading attached.
- Five ways to decide which cars have the unit: emergency class, a model list, a vehicle extra, a mod-kit part, or every vehicle.
- Four on-screen layouts (Slots, Stack, Lead, Row), move and resize, and a settings tab for plates shown, read time, vehicle names, units, tones, fast limit, auto-lock and the Doppler tone.
- `bridge/server.lua` and `bridge/client.lua`, left readable, for the job check, unit names, dispatch and your own plate records.
- Server events `cortex-alpr:hit`, `cortex-alpr:clocked` and `cortex-alpr:hotlistChanged`.
- Staff commands `alpr_hot` and `alpr_sightings`, and a Discord webhook for hot list changes.
- Optional Wraith ARS 2X plate events for MDTs that listen for them.
