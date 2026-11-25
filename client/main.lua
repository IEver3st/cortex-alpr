local RESOURCE = GetCurrentResourceName()
local SETTINGS_TAB = 'cortex-alpr'

State = {
    vehicle = 0,
    on = false,
    hidden = false,
    officer = false,
    air = false,
}

local scanGen = 0
local pushChrome
local blips = {}
local prefs = {
    show = true,
    units = Config.units,
    beeps = true,
    fastLimit = Config.radar.fastLimit,
    frontMode = Config.radar.frontMode,
    rearMode = Config.radar.rearMode,
    autoLock = Config.radar.autoLock,
    tone = Config.tone.default,
    toneVolume = Config.tone.volume,
    layout = Config.display.layout,
    plates = Config.display.plates,
    readSeconds = Config.display.readSeconds,
    details = Config.display.details,
}

local function sound(key)
    local s = Config.sounds[key]
    if not s or not prefs.beeps then return end
    for i = 1, (s.repeats or 1) do
        PlaySoundFrontend(-1, s.name, s.set, true)
        if i < (s.repeats or 1) then Wait(180) end
    end
end

local function notify(data)
    data.sender = Config.sender.id
    lib.notify(data)
end

local function readerOn()
    return State.on and not State.hidden
end

local function pushState()
    Radar.dirty = false
    Nui.send('state', {
        visible = Layout.editing or (readerOn() and prefs.show),
        layout = Layout.get(),
        display = { layout = prefs.layout, plates = tonumber(prefs.plates) or Config.display.plates, seconds = tonumber(prefs.readSeconds) or Config.display.readSeconds, details = prefs.details ~= false },
        tone = { on = Config.tone.enabled and prefs.tone == true and readerOn(), volume = (tonumber(prefs.toneVolume) or 0) / 100 },
        radar = Radar.snapshot(),
    })
end

Layout.onChange = pushState

local function startScan()
    scanGen = scanGen + 1
    local mine = scanGen
    CreateThread(function()
        local lastPush = 0
        while mine == scanGen do
            local vehicle = State.vehicle
            if vehicle ~= 0 and DoesEntityExist(vehicle) and readerOn() then
                Radar.sample(vehicle)
            end
            local now = GetGameTimer()
            if Radar.dirty or now - lastPush > 1000 then
                lastPush = now
                pushState()
            end
            Wait(Config.radar.sampleMs)
        end
    end)
end

local function stopScan()
    scanGen = scanGen + 1
end

local refreshActions

local function unitOn(vehicle)
    State.vehicle = vehicle
    if State.on then return end
    State.on = true
    Radar.antennas.front.mode = prefs.frontMode
    Radar.antennas.rear.mode = prefs.rearMode
    Radar.fastLimit = prefs.fastLimit
    Radar.units = prefs.units
    Radar.autoLock = prefs.autoLock == true
    Radar.clear()
    startScan()
    refreshActions()
    pushChrome()
    pushState()
end

local function unitOff()
    if not State.on then return end
    State.on = false
    State.vehicle = 0
    stopScan()
    Radar.clear()
    refreshActions()
    pushState()
end

local officerCheckedAt = -5000

local function watch()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local now = GetGameTimer()
    if now - officerCheckedAt > 5000 then
        officerCheckedAt = now
        State.officer = Install.officer()
    end
    local eligible = vehicle ~= 0 and State.officer and not IsEntityDead(ped)
        and not Install.isAircraft(vehicle) and Install.seated(vehicle, ped) and Install.fitted(vehicle)
    if eligible then
        if not State.on or State.vehicle ~= vehicle then
            if State.on then unitOff() end
            unitOn(vehicle)
        end
    elseif State.on then
        unitOff()
    end
    local air = State.officer and vehicle ~= 0 and Install.isAircraft(vehicle)
    if air ~= State.air then
        State.air = air
        refreshActions()
    end
    if air then Air.watch() elseif Air.active then Air.stop() end
end

CreateThread(function()
    while true do
        watch()
        Wait(State.air and 300 or 500)
    end
end)

local function menuOpen()
    if IsPauseMenuActive() then return true end
    local ok, open = pcall(function() return lib.getOpenMenu() end)
    return ok and open ~= nil and open ~= false
end

local function lockCam(cam)
    if not readerOn() or menuOpen() then return end
    local locked = Radar.toggleLock(cam)
    if locked == nil then return end
    CreateThread(function() sound(locked and 'lock' or 'unlock') end)
    pushState()
    refreshActions()
end

Radar.onClock = function(cam, shot)
    if not Config.clock.enabled then return Radar.failClock(cam, shot.seq) end
    local vehicle = shot.vehicle
    if not NetworkGetEntityIsNetworked(vehicle) then return Radar.failClock(cam, shot.seq) end
    local coords = GetEntityCoords(vehicle)
    local road, cross = Radar.roadAt(coords)
    TriggerServerEvent('cortex-alpr:server:clock', cam, NetworkGetNetworkIdFromEntity(vehicle), shot.speed + 0.0, {
        road = road,
        cross = cross,
        zone = GetNameOfZone(coords.x, coords.y, coords.z),
        model = Radar.modelLabel(vehicle),
        direction = shot.dir,
    }, shot.auto, shot.seq)
end

Radar.onAutoLock = function()
    CreateThread(function() sound('clock') end)
end

RegisterNetEvent('cortex-alpr:client:clock', function(cam, clock, _, seq)
    if cam ~= 'front' and cam ~= 'rear' then return end
    if type(clock) == 'table' and type(clock.id) == 'string' then
        Radar.setClock(cam, {
            id = clock.id,
            speed = tonumber(clock.speed),
            limit = tonumber(clock.limit),
            plate = type(clock.plate) == 'string' and clock.plate or nil,
            auto = clock.auto == true,
            unfiled = clock.filed ~= true,
        }, clock.seq)
    else
        Radar.failClock(cam, seq)
    end
    pushState()
    refreshActions()
end)

local function cite()
    if not readerOn() or not Config.clock.enabled or menuOpen() or HotList.available() then return end
    local clock = Radar.clockFor('front') or Radar.clockFor('rear')
    if not clock then
        return notify({ type = 'warning', title = L('cite_failed_title'), description = L('error_no_clock') })
    end
    if clock.unfiled or GetResourceState(Config.mdt) ~= 'started' then
        return notify({ type = 'error', title = L('cite_failed_title'), description = L('error_mdt_offline') })
    end
    local ok = pcall(function() exports[Config.mdt]:OpenCitation({ clock = clock.id, plate = clock.plate }) end)
    if not ok then notify({ type = 'error', title = L('cite_failed_title'), description = L('error_mdt_error') }) end
end

RegisterCommand('cortexalpr_cite', function() CreateThread(cite) end, false)
RegisterKeyMapping('cortexalpr_cite', L('key_cite'), 'keyboard', Config.keys.cite)

local function moveUnit()
    if not State.officer then return end
    local ok, why = Layout.begin()
    if not ok and why == 'moving' then
        notify({ type = 'warning', title = L('layout_title'), description = L('error_layout_moving') })
    end
end

RegisterCommand('cortexalpr_layout', function() moveUnit() end, false)
RegisterKeyMapping('cortexalpr_layout', L('key_layout'), 'keyboard', Config.keys.layout)

RegisterCommand('cortexalpr_toggle', function()
    if not State.on then return end
    State.hidden = not State.hidden
    if State.hidden then Radar.clear() end
    pushState()
end, false)
RegisterKeyMapping('cortexalpr_toggle', L('key_toggle'), 'keyboard', Config.keys.toggle)

RegisterCommand('cortexalpr_lockfront', function() lockCam('front') end, false)
RegisterKeyMapping('cortexalpr_lockfront', L('key_lock_front'), 'keyboard', Config.keys.lockFront)

RegisterCommand('cortexalpr_lockrear', function() lockCam('rear') end, false)
RegisterKeyMapping('cortexalpr_lockrear', L('key_lock_rear'), 'keyboard', Config.keys.lockRear)

local PRIORITY_OPTIONS = { 'low', 'normal', 'high', 'critical' }

local function boloFor(plate, vehicle, labelText)
    if not plate then return end
    local options = {}
    for i, p in ipairs(PRIORITY_OPTIONS) do options[i] = { value = p, label = L('priority_' .. p) } end
    local values = lib.contextMenu({
        title = L('bolo_dialog_title', plate),
        labels = { confirm = L('bolo_confirm'), cancel = L('bolo_cancel') },
        values = { title = labelText and L('bolo_default_title', labelText) or L('bolo_default_title_plate', plate), priority = 'normal' },
        fields = {
            { name = 'title', type = 'input', label = L('bolo_field_title'), required = true },
            { name = 'priority', type = 'select', label = L('bolo_field_priority'), required = true, options = options },
        },
    })
    if not values then return end
    local result = lib.callback.await('cortex-alpr:bolo', false, plate, {
        title = values.title,
        priority = values.priority,
        model = labelText,
    })
    if type(result) ~= 'table' then
        return notify({ type = 'error', title = L('bolo_failed_title'), description = L('error_timeout') })
    end
    if not result.ok then
        return notify({ type = 'error', title = L('bolo_failed_title'), description = ErrorText(result.error) })
    end
    notify({
        type = 'success',
        title = result.existing and L('bolo_existing_title', result.number or '') or L('bolo_filed_title', result.number or ''),
        description = L('bolo_filed_body', plate),
    })
    Radar.sentAt[plate] = nil
end

local function boloCam(cam)
    local a = Radar.antennas[cam]
    if not a or not a.plate then return end
    boloFor(a.plate.plate, nil, a.plate.label)
end

local function boloAir()
    local target = Air.target()
    if target then
        local plate = Geo.plate(GetVehicleNumberPlateText(target))
        if plate then
            Radar.sentAt[plate] = nil
            Radar.send('air', target, plate)
            Wait(400)
            return boloFor(plate, target, Radar.modelLabel(target))
        end
    end
    local last = Air.lastRead
    if last then return boloFor(last.plate, last.vehicle, last.label) end
    notify({ type = 'warning', title = L('bolo_failed_title'), description = L('error_no_air_target') })
end

local function boloAny()
    if State.air then return boloAir() end
    local front, rear = Radar.antennas.front, Radar.antennas.rear
    if front.plateLocked and front.plate then return boloCam('front') end
    if rear.plateLocked and rear.plate then return boloCam('rear') end
    if front.plate then return boloCam('front') end
    if rear.plate then return boloCam('rear') end
    notify({ type = 'warning', title = L('bolo_failed_title'), description = L('error_not_read') })
end

RegisterCommand('cortexalpr_bolo', function() CreateThread(boloAny) end, false)
RegisterKeyMapping('cortexalpr_bolo', L('key_bolo'), 'keyboard', Config.keys.bolo)

local MODE_LABEL = { same = 'mode_same', opp = 'mode_opp', both = 'mode_both' }

local function setFastLimit()
    local values = lib.contextMenu({
        title = L('fast_limit_title'),
        labels = { confirm = L('save'), cancel = L('bolo_cancel') },
        values = { limit = tostring(Radar.fastLimit) },
        fields = { { name = 'limit', type = 'input', inputType = 'number', label = L('fast_limit_field', L('unit_' .. Radar.units)), min = 0, max = 250, step = 5, required = true } },
    })
    local n = values and tonumber(values.limit)
    if not n then return end
    Radar.fastLimit = math.floor(n)
    prefs.fastLimit = Radar.fastLimit
    Radar.dirty = true
end

refreshActions = function()
    local keys = lib.keys
    if not keys or not keys.available then return end
    if not State.on and not State.air then
        keys.removeAction('alpr')
        return
    end
    local items = {}
    if State.air then
        items[#items + 1] = { id = 'bolo_air', label = L('action_bolo_target'), icon = 'flag' }
    else
        local front, rear = Radar.antennas.front, Radar.antennas.rear
        local clock = Config.clock.enabled and (Radar.clockFor('front') or Radar.clockFor('rear')) or nil
        if clock and not clock.unfiled then
            local speed = math.floor((clock.speed or 0) * Geo.SPEED[Radar.units or Config.units] + 0.5)
            items[#items + 1] = { id = 'cite', label = L('action_cite', speed, L('unit_' .. (Radar.units or Config.units))), icon = 'gauge' }
        end
        if front.plate then items[#items + 1] = { id = 'bolo_front', label = L('action_bolo_plate', front.plate.plate), icon = 'flag' } end
        if rear.plate then items[#items + 1] = { id = 'bolo_rear', label = L('action_bolo_plate', rear.plate.plate), icon = 'flag' } end
        items[#items + 1] = { id = 'mode_front', label = L('action_mode_front', L(MODE_LABEL[front.mode])), icon = 'car' }
        items[#items + 1] = { id = 'mode_rear', label = L('action_mode_rear', L(MODE_LABEL[rear.mode])), icon = 'car' }
        items[#items + 1] = { id = 'fast_limit', label = L('action_fast_limit', Radar.fastLimit), icon = 'gauge' }
        items[#items + 1] = { id = 'auto_lock', label = L('action_auto_lock', L(Radar.autoLock and 'on' or 'off')), icon = 'gauge' }
        if HotList.available() then items[#items + 1] = { id = 'hotlist', label = L('action_hotlist'), icon = 'flag' } end
        items[#items + 1] = { id = 'layout', label = L('action_layout'), icon = 'car' }
        items[#items + 1] = { id = 'power', label = State.hidden and L('action_power_on') or L('action_power_off'), icon = 'bolt' }
    end
    keys.addAction('alpr', { label = L('actions_label'), icon = 'car', where = 'vehicle', order = 40, items = items }, function(item)
        if item == 'bolo_front' then CreateThread(function() boloCam('front') end)
        elseif item == 'bolo_rear' then CreateThread(function() boloCam('rear') end)
        elseif item == 'bolo_air' then CreateThread(boloAir)
        elseif item == 'mode_front' then prefs.frontMode = Radar.cycleMode('front'); refreshActions()
        elseif item == 'mode_rear' then prefs.rearMode = Radar.cycleMode('rear'); refreshActions()
        elseif item == 'fast_limit' then CreateThread(function() setFastLimit(); refreshActions() end)
        elseif item == 'cite' then CreateThread(cite)
        elseif item == 'auto_lock' then
            prefs.autoLock = not Radar.autoLock
            Radar.autoLock = prefs.autoLock
            refreshActions()
        elseif item == 'hotlist' then CreateThread(function() HotList.open(1) end)
        elseif item == 'layout' then CreateThread(moveUnit)
        elseif item == 'power' then ExecuteCommand('cortexalpr_toggle'); refreshActions()
        end
    end)
end

local lastActionPlates = ''

CreateThread(function()
    while true do
        Wait(1000)
        if State.on then
            local f, r = Radar.antennas.front.plate, Radar.antennas.rear.plate
            local fc, rc = Radar.clockFor('front'), Radar.clockFor('rear')
            local key = (f and f.plate or '') .. '|' .. (r and r.plate or '') .. '|' .. (fc and fc.id or '') .. '|' .. (rc and rc.id or '')
            if key ~= lastActionPlates then
                lastActionPlates = key
                refreshActions()
            end
        end
    end
end)

RegisterNetEvent('cortex-alpr:client:hit', function(data)
    if type(data) ~= 'table' or type(data.plate) ~= 'string' then return end
    local hit = { kind = data.kind, text = data.text, bolos = data.bolos, stolen = data.stolen }
    local read = Radar.findRead(data.plate)
    if read then read.hit = hit end
    if data.cam == 'air' then
        if type(data.netId) == 'number' then Air.addLabel(data.netId, data) end
    else
        local a = Radar.antennas[data.cam]
        if a and a.plate and a.plate.plate == data.plate then
            if data.lock then Radar.lockPlate(data.cam, hit) else a.plate.hit = hit end
        end
        if type(data.netId) == 'number' then Air.addLabel(data.netId, data) end
    end
    pushState()
    CreateThread(function() sound('hit') end)
    notify({
        type = data.kind == 'error' and 'error' or 'warning',
        title = data.bolos and data.bolos[1] and L('hit_title_bolo', data.bolos[1].number or '') or L('hit_title'),
        description = data.text,
        important = true,
        duration = 12000,
    })
end)

local scanned = {}

local function wraithEvents()
    return Config.hotlist.wraithEvents and HotList.available()
end

Radar.onSend = function(cam, vehicle, plate)
    if cam == 'air' or not wraithEvents() then return end
    scanned[cam] = plate
    TriggerServerEvent('wk:onPlateScanned', cam, plate, GetVehicleNumberPlateTextIndex(vehicle))
end

RegisterNetEvent('wk:togglePlateLock', function(cam)
    if (cam ~= 'front' and cam ~= 'rear') or not State.on or not wraithEvents() then return end
    local read = scanned[cam] and Radar.findRead(scanned[cam]) or nil
    if not read or read.hit then return end
    local hit = { kind = 'error', text = L('hit_external') }
    read.hit = hit
    local a = Radar.antennas[cam]
    if not a.plateLocked then
        a.plate = { plate = read.plate, label = read.label, style = read.style, at = read.at, netId = read.netId }
        Radar.lockPlate(cam, hit)
    end
    pushState()
    refreshActions()
    CreateThread(function() sound('hit') end)
end)

AddStateBagChangeHandler('cortex-alpr:records', 'global', function()
    SetTimeout(0, refreshActions)
end)

local function clearBlip(key)
    local b = blips[key]
    if b and DoesBlipExist(b.handle) then RemoveBlip(b.handle) end
    blips[key] = nil
end

RegisterNetEvent('cortex-alpr:client:cleared', function(plate)
    if type(plate) ~= 'string' then return end
    Radar.clearHit(plate)
    clearBlip(plate)
    for netId, label in pairs(Air.labels) do
        if label.plate == plate then Air.labels[netId] = nil end
    end
    pushState()
    refreshActions()
end)

RegisterNetEvent('cortex-alpr:client:sighting', function(data)
    if type(data) ~= 'table' or type(data.plate) ~= 'string' or type(data.coords) ~= 'table' then return end
    local x, y, z = tonumber(data.coords.x), tonumber(data.coords.y), tonumber(data.coords.z)
    if not x or not y or not z then return end
    local key = data.plate
    clearBlip(key)
    if Config.network.blipSeconds > 0 then
        local blip = AddBlipForCoord(x + 0.0, y + 0.0, z + 0.0)
        SetBlipSprite(blip, Config.network.blip.sprite)
        SetBlipColour(blip, Config.network.blip.colour)
        SetBlipScale(blip, Config.network.blip.scale)
        if not data.quiet then
            SetBlipFlashes(blip, true)
            SetBlipFlashTimer(blip, 8000)
        end
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(L('blip_name', data.plate))
        EndTextCommandSetBlipName(blip)
        local stamp = GetGameTimer()
        blips[key] = { handle = blip, at = stamp }
        SetTimeout(Config.network.blipSeconds * 1000, function()
            if blips[key] and blips[key].at == stamp then clearBlip(key) end
        end)
    end
    if data.quiet then return end
    local reason = data.bolos and data.bolos[1] and L('sighting_bolo', data.bolos[1]) or L('sighting_stolen')
    CreateThread(function() sound('sighting') end)
    notify({
        type = 'warning',
        title = L('sighting_title', data.plate),
        description = L('sighting_body', reason, data.label or L('unknown_vehicle'), data.unit or '?', L('cam_' .. tostring(data.cam)), data.street or L('unknown_street')),
        important = true,
        duration = 10000,
    })
end)

local function registerSettings()
    if GetResourceState('cortex-lib') ~= 'started' then return end
    local fields = {
        { key = 'show', type = 'toggle', label = L('setting_show'), description = L('setting_show_desc'), default = true },
        { key = 'units', type = 'select', label = L('setting_units'), description = L('setting_units_desc'), default = Config.units, options = {
            { value = 'mph', label = L('unit_mph') }, { value = 'kmh', label = L('unit_kmh') } } },
        { key = 'layout', type = 'select', label = L('setting_layout'), description = L('setting_layout_desc'), default = Config.display.layout, options = {
            { value = 'slots', label = L('layout_slots') }, { value = 'stack', label = L('layout_stack') },
            { value = 'lead', label = L('layout_lead') }, { value = 'row', label = L('layout_row') } } },
        { key = 'plates', type = 'slider', label = L('setting_plates'), description = L('setting_plates_desc'), min = 1, max = 5, step = 1, default = Config.display.plates },
        { key = 'readSeconds', type = 'slider', label = L('setting_read_seconds'), description = L('setting_read_seconds_desc'), min = 4, max = 40, step = 4, default = Config.display.readSeconds },
        { key = 'details', type = 'toggle', label = L('setting_details'), description = L('setting_details_desc'), default = Config.display.details },
        { key = 'beeps', type = 'toggle', label = L('setting_beeps'), description = L('setting_beeps_desc'), default = true },
        { key = 'fastLimit', type = 'slider', label = L('setting_fast_limit'), description = L('setting_fast_limit_desc'), min = 0, max = 150, step = 5, default = Config.radar.fastLimit },
        { key = 'autoLock', type = 'toggle', label = L('setting_auto_lock'), description = L('setting_auto_lock_desc'), default = Config.radar.autoLock },
    }
    if Config.tone.enabled then
        fields[#fields + 1] = { key = 'tone', type = 'toggle', label = L('setting_tone'), description = L('setting_tone_desc'), default = Config.tone.default }
        fields[#fields + 1] = { key = 'toneVolume', type = 'slider', label = L('setting_tone_volume'), description = L('setting_tone_volume_desc'), min = 0, max = 100, step = 5, default = Config.tone.volume, showWhen = { tone = true } }
    end
    local defaults = {}
    for _, f in ipairs(fields) do defaults[f.key] = f.default end
    pcall(function()
        exports['cortex-lib']:registerSettings(SETTINGS_TAB, L('settings_label'), 'cortex-alpr:', fields, defaults, { group = 'Equipment' })
    end)
    for _, f in ipairs(fields) do
        local ok, value = pcall(function() return exports['cortex-lib']:getTabSetting(SETTINGS_TAB, f.key) end)
        if ok and value ~= nil then prefs[f.key] = value end
    end
    Radar.units = prefs.units
    Radar.fastLimit = prefs.fastLimit
    Radar.autoLock = prefs.autoLock == true
end

AddEventHandler('cortex-lib:settingChanged', function(key, value, tab)
    if tab ~= SETTINGS_TAB or prefs[key] == nil then return end
    prefs[key] = value
    if key == 'units' then Radar.units = value end
    if key == 'fastLimit' then Radar.fastLimit = tonumber(value) or Radar.fastLimit end
    if key == 'autoLock' then Radar.autoLock = value == true end
    Radar.dirty = true
    pushState()
end)

CreateThread(function()
    Wait(500)
    if lib.registerSender then
        pcall(lib.registerSender, Config.sender.id, { label = Config.sender.label, color = Config.sender.color, icon = Config.sender.icon })
    end
    registerSettings()
end)

AddEventHandler('onClientResourceStart', function(name)
    if name == 'cortex-lib' then
        Wait(500)
        registerSettings()
        refreshActions()
    end
end)

local ARROWS = { UP = '↑', DOWN = '↓', LEFT = '←', RIGHT = '→' }

local function keyLabel(command, fallback)
    local label = GetControlInstructionalButton(0, joaat('+' .. command) | 0x80000000, true)
    if type(label) ~= 'string' or label:sub(1, 2) ~= 't_' then
        label = GetControlInstructionalButton(0, joaat(command) | 0x80000000, true)
    end
    if type(label) == 'string' and label:sub(1, 2) == 't_' then
        local name = label:sub(3)
        return ARROWS[name:upper()] or name
    end
    return ARROWS[fallback] or fallback
end

function pushChrome()
    Nui.send('keys', {
        front = keyLabel('cortexalpr_lockfront', Config.keys.lockFront),
        rear = keyLabel('cortexalpr_lockrear', Config.keys.lockRear),
        cite = Config.clock.enabled and keyLabel('cortexalpr_cite', Config.keys.cite) or '',
    })
    Nui.send('layout', { safe = (1.0 - GetSafeZoneSize()) * 0.5 })
end

AddEventHandler('cortex-lib:peek', function(active)
    Nui.send('peek', active == true)
end)

Nui.whenReady(pushChrome)
Nui.whenReady(pushState)

AddEventHandler('onResourceStop', function(name)
    if name ~= RESOURCE then return end
    for key in pairs(blips) do pcall(clearBlip, key) end
    pcall(Layout.stop)
    pcall(stopScan)
    pcall(Air.stop)
end)

exports('isActive', function() return State.on and not State.hidden end)
exports('toggle', function() ExecuteCommand('cortexalpr_toggle') end)
exports('getLocks', function()
    local out = {}
    for cam, a in pairs(Radar.antennas) do
        local clock = Radar.clockFor(cam)
        out[cam] = {
            locked = a.locked, target = a.lockTarget, fast = a.lockFast,
            plate = a.plateLocked and a.plate and a.plate.plate or nil,
            clock = clock and { id = clock.id, speed = clock.speed, limit = clock.limit, plate = clock.plate } or nil,
        }
    end
    return out
end)
exports('getReads', function() return Radar.snapshot().reads end)
