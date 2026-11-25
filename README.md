# Cortex ALPR

[![Cortex ALPR](https://raw.githubusercontent.com/IEver3st/gsd-tebex-media/main/heroes/alpr.jpg)](https://gsdmods.com/scripts/cortex-alpr?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr)

**[Download Latest Release (v1.0.0)](https://github.com/IEver3st/cortex-alpr/releases/latest)** · [Product Page](https://gsdmods.com/scripts/cortex-alpr?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) · [All 36 Cortex Scripts](https://gsdmods.com/scripts?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) · [Docs](https://gsdmods.com/docs?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) · [Discord](https://discord.com/invite/gsdmods)

> **Free direct download — no Tebex checkout or Asset Escrow required.** Download the ready-to-drop `cortex-alpr-1.0.0.zip` from [GitHub Releases](https://github.com/IEver3st/cortex-alpr/releases/latest) and extract `cortex-alpr` into your FiveM `resources/` folder.

A traffic radar and plate reader for patrol cars and the police helicopter. Put a plate on the hot list and every equipped car, and the helicopter camera, starts looking for it. The first read puts the car on every unit's map, raises a dispatch call and stamps the sighting on the entry.

It runs on its own with a built-in hot list. With the Cortex MDT installed, BOLOs, stolen reports, warrants and citations come from the MDT instead.

## Requirements

| Resource | Needed | Notes |
|---|---|---|
| cortex-lib 4.0.0 or newer | Yes | Free. QBCore and ESX need 4.1.0 or newer |
| Qbox (`qbx_core`) | One framework, or none | Tested |
| QBCore, ESX | | Read through cortex-lib's framework layer. Not yet tested with this script |
| cortex-mdt | Optional | BOLOs, stolen reports, warrants and speed citations |
| cortex-dispatch | Optional | A dispatch call for each hit |
| cortex-polcam 2.6.0 or newer | Optional | The air reader. Filing a BOLO on the camera's locked vehicle needs 2.7.0 |
| cortex-radar | Optional | Posted speed limits on speed locks |

There is no database to import. The hot list is saved in the server's own key-value store and survives restarts.

## Install

1. Put the `cortex-alpr` folder in your resources.
2. Add it to `server.cfg` after cortex-lib and after the optional resources you use:

```
ensure cortex-lib
ensure cortex-mdt
ensure cortex-dispatch
ensure cortex-polcam
ensure cortex-alpr
```

3. Set who counts as police in `config.lua` under `Config.jobs`. The defaults cover a job of type `leo` or a job named `police`, on duty.
4. Leave `Config.records` on `'auto'`: the reader uses the Cortex MDT when the resource named in `Config.mdt` is running, and its own hot list when it is not. `'hotlist'` keeps the hot list even next to the MDT, and `'mdt'` refuses reads while the MDT is down.
5. Optional, in `server.cfg`:

```
add_ace group.admin command.alpr_hot allow
add_ace group.admin command.alpr_sightings allow
add_ace group.admin cortexalpr.admin allow
add_ace group.police cortexalpr.officer allow
set cortex_alpr_webhook "https://discord.com/api/webhooks/..."
```

- `cortexalpr.officer` makes a player an officer whatever their job is. On a server without a framework it is the only way in. While the Cortex MDT is the records source, the MDT's sign-in decides who is an officer and this ACE is ignored.
- `cortexalpr.admin` lets an officer add and clear hot list plates whatever their grade is.
- `cortex_alpr_webhook` posts every hot list change to a Discord channel, a few lines at a time. Leave it out and changes only go to the server console.

### Config at a glance

| Setting | Does |
|---|---|
| `Config.records` | `'auto'`, `'mdt'` or `'hotlist'`: where hits come from |
| `Config.mdt`, `Config.dispatch`, `Config.polcam` | The resource names of the optional Cortex resources, if you renamed them |
| `Config.jobs.types`, `Config.jobs.names` | Job types and job names that count as police |
| `Config.jobs.requireDuty` | `false` lets off-duty officers use the unit |
| `Config.jobs.ace` | The ACE that makes anyone an officer while the hot list is the records source. `false` turns it off |
| `Config.hotlist.max` | How many plates the hot list holds (200) |
| `Config.hotlist.expireHours` | Hours before an entry clears itself. 0 keeps it |
| `Config.hotlist.fileGrade`, `clearGrade` | The job grade needed to add a plate, and to clear someone else's |
| `Config.hotlist.cooldownSeconds` | How long before the same plate alerts the same officer again. Next to the Cortex MDT, keep it equal to the MDT's plate reader cooldown |
| `Config.hotlist.prefix` | The letters in front of entry numbers (`B-0001`) |
| `Config.hotlist.command` | The chat command that opens the hot list. `false` removes it |
| `Config.units` | `'mph'` or `'kmh'`, the default for new players |
| `Config.install` | Which cars have the unit, see below |
| `Config.keys` | Default keys |

## Using it

- **Turning it on:** get in an equipped car as driver or front passenger while on duty, and the unit comes up. `F7` shows or hides it.
- **Speeds:** each antenna shows the strongest moving target, which is the biggest and closest vehicle it can actually see: a truck further out beats a small car beside you, and a vehicle behind a building, over a crest or on a bridge above you is not read. The fastest one shows beside it once it passes the fast limit. The triangle points up for a vehicle pulling away and down for one closing on you. Speed is measured along the beam, so a car crossing at an angle reads low, as it does on a real unit.
- **Locks:** `Up` and `Down` lock the front and rear. A lock holds the speeds and the plate on screen. With auto-lock on, a vehicle over the fast limit locks itself with a short tone, then leaves the antenna free again for 20 seconds after you unlock it.
- **Plates:** the cameras read the plate ahead and behind. A plate on the hot list turns the card red, locks it and alerts you.
- **Sightings:** every on-duty officer gets a sighting and a blip. Later reads of the same plate within 3 minutes move the blip without a popup. Dispatch gets one call per plate per 3 minutes.
- **Filing a BOLO:** use the Actions wheel (`M`) > Plate reader > BOLO, or bind a key to `Plate reader: BOLO the read plate`. Confirm the title and priority. Every reader is armed at once.
- **Air reader:** with PolCam on, the camera reads plates of cars near the centre of its view, and range grows with zoom. Hits label the car in the camera feed. BOLO from the wheel files the car PolCam has locked.
- **Doppler tone:** off by default. Turn it on in settings for a quiet tone that rises with the target's speed.
- **Moving and resizing:** Actions wheel > Plate reader > Move and resize, or bind `Plate reader: move and resize`. Drag the unit anywhere, drag the handle or scroll to resize it, `R` puts it back, `Enter` saves. On the left half of the screen it mirrors itself. Each player's layout is saved on their own PC.
- **Missed reads:** the Look key (`Z`) shows the last five reads.
- **Settings:** Settings > Plate reader covers show, the layout (Slots, Stack, Lead or Row), how many plates show and for how long, vehicle names, units, tones, fast limit, auto-lock and the Doppler tone with its volume. The wheel cycles the lane modes (same, opposite, both).

## The hot list

The hot list is what the readers look for when the Cortex MDT is not installed.

- **Opening it:** `/hotlist`, the Actions wheel > Plate reader > Hot list, or bind `Plate reader: open the hot list`. Officers only. It shows 40 plates a page, newest first.
- **Adding a plate:** Add a plate takes the plate, a reason, the vehicle and a priority, and can mark it as stolen. You do not need to have read the plate. Filing a BOLO from a plate the reader has read adds it too, with the model and where it was read filled in.
- **Each entry** shows who added it, when it clears itself, and its last five sightings. Selecting a sighting marks it on your map.
- **Clearing:** by default any officer can clear a plate. Raise `Config.hotlist.clearGrade` to keep that for a job grade and up; the officer who added a plate can always clear their own.
- **Expiry:** entries clear themselves after `Config.hotlist.expireHours` (72 by default, 0 keeps them until cleared).

With the Cortex MDT running, BOLOs live in the MDT and the hot list menu is hidden. Plates another resource adds through `AddHotPlate` are still checked.

## Speed locks and citations

Every lock is checked by the server against the vehicle's real speed and kept for an hour with the posted limit (from cortex-radar when it is running), the street and the plate once a camera reads it.

With the Cortex MDT, `Right` opens the MDT on the registered owner with the citation already filled in: plate, location and the speeding charge that matches how far over the limit the vehicle was. With no plate or owner, the MDT asks who was driving. The reading is saved on the citation and goes on one citation only.

Without the MDT the lock still shows the checked speed and the limit, the cite key stays hidden, and other resources read the lock from `GetClocks` or the `cortex-alpr:clocked` event.

## Which cars have it

Set `Config.install.modes`. A car qualifies when any listed mode matches.

| Mode | A car qualifies when |
|---|---|
| `emergency` | It is vehicle class 18 |
| `models` | Its model is in `Config.install.models` (also checked by the server) |
| `extra` | Extra `Config.install.extra` is on |
| `modkit` | Mod slot `Config.install.modkit.type` holds a part, optionally one of `indices`. Per-model overrides go in `modkit.models` |
| `any` | Every vehicle |

With mod-kit mode, the radar is a part a mechanic fits, and only cars with that part have the unit. Pick a slot your police models actually have parts in. The default slot, 43 (aerials), is empty on the vanilla Police Cruiser.

## Keys

All of them can be rebound under FiveM key bindings. The defaults are in `Config.keys`.

| Binding | Default |
|---|---|
| Show or hide the unit | `F7` |
| Lock front | `Up` |
| Lock rear | `Down` |
| Cite the locked speed | `Right` |
| BOLO the read plate | unbound |
| Move and resize the unit | unbound |
| Open the hot list | unbound |

## Staff commands

Run them from the server console, or in game with the ACE lines above.

| Command | Does |
|---|---|
| `alpr_hot` | Lists the hot list with who added each plate, when it expires and where it was last seen |
| `alpr_hot add <plate> <reason>` | Adds a plate. Put `stolen` before the reason to list it as a stolen vehicle |
| `alpr_hot clear <plate>` | Clears one plate |
| `alpr_hot clear all` | Clears the list |
| `alpr_sightings <plate>` | Lists the reads of a flagged plate in the last 2 hours |

In game the answer comes back in chat. Every add, clear and expiry is printed to the server console, and posted to `cortex_alpr_webhook` when it is set.

## Connecting other resources

### Server exports

```lua
local number = exports['cortex-alpr']:AddHotPlate('46EEK572', {
    title = 'Taken from Legion Square',
    kind = 'stolen',        -- 'bolo' (default) or 'stolen'
    priority = 'high',      -- low, normal, high or critical
    model = 'Sultan RS',
    colour = 'Blue',
    hours = 24,             -- 0 keeps it until cleared
})

exports['cortex-alpr']:RemoveHotPlate('46EEK572')
local listed = exports['cortex-alpr']:IsHotPlate('46EEK572')
local plates = exports['cortex-alpr']:GetHotPlates()
```

- `GetSightings(plate)`: reads of a flagged plate in the last 2 hours, newest first.
- `GetClocks(source)`: the speeds that officer locked in the last hour, newest first, in metres per second with the posted limit, street, plate and time.
- `ReportRead(source, cam, netId, street)`: feed a read from another resource through the same checks.

### Server events

```lua
AddEventHandler('cortex-alpr:hit', function(source, hit)
    -- hit.plate, hit.cam, hit.netId, hit.coords, hit.street, hit.unit, hit.label, hit.stolen, hit.bolos, hit.text
end)

AddEventHandler('cortex-alpr:clocked', function(source, clock)
    -- clock.id, clock.speed and clock.limit in m/s, clock.plate, clock.street, clock.coords, clock.cam, clock.direction
end)

AddEventHandler('cortex-alpr:hotlistChanged', function(action, entry)
    -- action is 'added', 'cleared' or 'expired'
end)
```

### Client exports

- `isActive()`, `toggle()`
- `getLocks()`: front and rear lock state, plates and the locked speed record.
- `getReads()`: the read history.

### The bridge

`bridge/server.lua` and `bridge/client.lua` are not escrowed. They hold everything that touches your framework and your other resources:

| Function | File | Change it to |
|---|---|---|
| `Bridge.job`, `Bridge.officer` | both | Decide who is police another way |
| `Bridge.grade` | server | Change the grade the hot list limits compare against |
| `Bridge.unit` | server | Change the name on sightings and dispatch calls. The default is the callsign, then the character name |
| `Bridge.identity` | server | Change what marks an entry as an officer's own. The default is the character id |
| `Bridge.dispatch(alert)` | server | Send hits to another dispatch resource. Return `true` when the call was sent |
| `Bridge.lookup(plate)` | server | Flag plates from your own records |

`Bridge.officer` exists in both files and the two have to agree. The client one decides whether the unit shows in the car; the server one decides whether its reads count. Change only one and you get a unit that reads nothing, or officers with no unit.

`Bridge.dispatch` gets `alert.code`, `alert.title`, `alert.message`, `alert.priority`, `alert.coords`, `alert.street` and `alert.vehicle` (`plate`, `model`, `colour`). `alert.jobs` is only set by the Cortex MDT, so give your dispatch its own job list when it is `nil`.

`Bridge.lookup` runs once a minute at most for each plate. Return `nil` for a clean plate, or:

```lua
function Bridge.lookup(plate)
    local row = exports.oxmysql:single_async('SELECT stolen, owner_wanted FROM my_vehicle_flags WHERE plate = ?', { plate })
    if not row then return nil end
    return {
        stolen = row.stolen == 1,
        lines = row.owner_wanted == 1 and { 'The owner is wanted.' } or {},
        lock = true,            -- lock the camera on it
        label = 'Sultan RS',
    }
end
```

A stolen plate alerts every officer and raises a dispatch call. Lines alone only alert the officer whose camera read it.

### Wraith ARS 2X events

Set `Config.hotlist.wraithEvents = true` and the reader also sends `wk:onPlateScanned` for each read and locks the camera when your MDT answers with `wk:togglePlateLock`, the way Wraith ARS 2X does. It only applies while the hot list is the records source, and was tested against the Cortex MDT's Wraith handler only.

## Trust

- **Ground reads:** the client only names a vehicle. The server reads the plate itself, then checks the routing bucket and the seat, range and cone against its own view of the officer's car. Only on-duty officers are recorded.
- **Air reads:** accepted only while PolCam's server feed names that player as operator. Range is measured from the helicopter's server position, and the vehicle must be inside the camera's field of view.
- **Hot list:** only officers can read it, and plates are letters and digits only. Adding needs `Config.hotlist.fileGrade`, clearing someone else's entry needs `Config.hotlist.clearGrade`, and one officer can add one plate every 5 seconds.
- **Departments (Cortex MDT):** a hit shows each officer only the BOLOs their MDT departments and permissions allow. When a BOLO is hidden from some departments, its dispatch call leaves out the BOLO number and title, because cortex-dispatch routes by role.
- **Client text:** the street name and model label come from the client. They are length-capped and credited to the officer.
- **Filing a BOLO from a read:** needs a plate the server itself read for that officer in the last 10 minutes.
- **Speed locks:** the client names the vehicle and the speed it showed. The server refuses the lock unless that vehicle is in the antenna's beam from its own view of the patrol car and the vehicle is really moving, with the claimed speed within `Config.server.speedSlack` of its real speed. The speed kept is never higher than the real one. The plate on a lock only ever comes from a read the server made of that same vehicle. Limited to 12 locks a minute per officer.
- **Install checks:** the `emergency`, `extra`, `modkit` and `any` modes are checked on the client. A modified client can fit a reader to its own car, but it still only reads cars really around it, within 12 reads per second.
- **Wraith events:** when turned on, the plate in `wk:onPlateScanned` comes from the client, as it does with Wraith ARS 2X itself.

## Living next to other readers

- **Wraith ARS 2X:** it can stay installed. With the Cortex MDT, both readers share the MDT's per-officer cooldown, so one plate never alerts twice. A plate Wraith reads first alerts only that officer, with no sightings, dispatch call or last seen for that minute, so removing Wraith is recommended.
- **gawk_alpr:** its fixed cameras keep working on their own.

## Support

Documentation: https://gsdmods.com/docs

For help, use the GSD Modifications Discord. Include the resource version, your framework and cortex-lib versions, the steps that reproduce the problem and any server or F8 errors.

## More from Cortex

Cortex ALPR is free and stays free. All 36 Cortex scripts share one free library ([`cortex-lib`](https://github.com/IEver3st/cortex-lib)) and one consistent UI, with native cross-script integrations and zero conflicts.

### Flagship Paid Suites & Scripts

| Police & Tactical | Economy & World | Core UI & Vehicles |
| --- | --- | --- |
| [**Cortex MDT**](https://gsdmods.com/scripts/cortex-mdt?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): Full police MDT + Dispatch included free | [**Cortex Banking**](https://gsdmods.com/scripts/cortex-banking?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): 4 banks, rebuilt 3D ATMs, cards, credit scores & loans | [**Cortex HUD**](https://gsdmods.com/scripts/cortex-hud?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): HUD Studio with Cortex, Lore Friendly & VI layouts |
| [**Cortex PolCam**](https://gsdmods.com/scripts/cortex-polcam?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): FLIR helicopter camera with tracking & ground link | [**Cortex Vending**](https://gsdmods.com/scripts/cortex-vending?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): Player-owned vending machines with 105 3D products | [**Cortex Handling**](https://gsdmods.com/scripts/cortex-handling?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): Live in-game vehicle handling editor & exporter |
| [**Cortex Dispatch**](https://gsdmods.com/scripts/cortex-dispatch?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): Live alerts, unit routing & panic calls | [**Cortex Caseboard**](https://gsdmods.com/scripts/cortex-caseboard?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): Detective corkboards with red strings & 18 card types | [**Cortex Multicharacter**](https://gsdmods.com/scripts/cortex-multicharacter?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): Character roster, dossier & ID registration |
| [**Cortex Radar**](https://gsdmods.com/scripts/cortex-radar?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): Handheld 3D police radar gun | [**Cortex Whiteboard**](https://gsdmods.com/scripts/cortex-whiteboard?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): 28 drawable boards with city maps & physics | [**Cortex Rewind**](https://gsdmods.com/scripts/cortex-rewind?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): Forza-style vehicle rewind in FiveM |
| [**Cortex Arges**](https://gsdmods.com/scripts/cortex-arges?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) · [**Radio**](https://gsdmods.com/scripts/cortex-radio?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) · [**SceneKit**](https://gsdmods.com/scripts/cortex-scenekit?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) | [**Cortex Computer**](https://gsdmods.com/scripts/cortex-computer?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr): In-world playable computers & monitors | [**Cortex Chat**](https://gsdmods.com/scripts/cortex-chat?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) · [**Spawn**](https://gsdmods.com/scripts/cortex-spawn?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) · [**Emote Studio**](https://gsdmods.com/scripts/cortex-emote-studio?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) |

### Save with Bundles (One-Time or All-Access)

- [**Cortex Complete**](https://gsdmods.com/scripts/cortex-complete?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) — One-time lifetime bundle, no subscription.
- [**Cortex LEO Kit**](https://gsdmods.com/scripts/cortex-leo-kit?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) — Complete unified police stack (`MDT`, `Dispatch`, `PolCam`, `Radar`, `ALPR`, `Arges`, `Radio`, `SceneKit`, `Caseboard`, `Whiteboard`, `Flashlight`, `Binoculars`).
- [**Cortex Interface Kit**](https://gsdmods.com/scripts/cortex-interface-kit?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) — Complete core UI stack (`HUD`, `Chat`, `Spawn`, `Multicharacter`, `Loading Screen`).
- [**Cortex All-Access**](https://gsdmods.com/scripts/cortex-all-access?utm_source=github&utm_medium=readme&utm_campaign=cortex-alpr) — Every current paid script + every future release on day one.

### All Free Cortex Scripts on GitHub

[`cortex-pause`](https://github.com/IEver3st/cortex-pause) · [`cortex-alpr`](https://github.com/IEver3st/cortex-alpr) · [`cortex-newspaper`](https://github.com/IEver3st/cortex-newspaper) · [`cortex-gunsmith`](https://github.com/IEver3st/cortex-gunsmith) · [`cortex-echo`](https://github.com/IEver3st/cortex-echo) · [`cortex-drone`](https://github.com/IEver3st/cortex-drone) · [`cortex-droneraces`](https://github.com/IEver3st/cortex-droneraces) · [`cortex-thrusters`](https://github.com/IEver3st/cortex-thrusters) · [`cortex-megaphone`](https://github.com/IEver3st/cortex-megaphone) · [`cortex-minigames`](https://github.com/IEver3st/cortex-minigames) · [`cortex-admin`](https://github.com/IEver3st/cortex-admin-releases) · [`cortex-atmrobbery`](https://github.com/IEver3st/cortex-atmrobbery) · [`cortex-vendrobbery`](https://github.com/IEver3st/cortex-vendrobbery) · [`cortex-lib`](https://github.com/IEver3st/cortex-lib)
