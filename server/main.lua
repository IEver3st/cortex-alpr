local CAMS = { front = true, rear = true, air = true }
local MDT_PRIORITY_TO_DISPATCH = { [4] = 1, [3] = 1, [2] = 2, [1] = 3 }

local readBudget = {}
local ledger = {}
local dispatchedAt = {}
local fannedAt = {}
local sightings = {}
local sightingPlates = 0
local SIGHTING_KEEP = 7200
local SIGHTING_PLATES = 4000
local mdtWarned = false
local mdtErrorAt = -10000

Alpr = {}

local function started(name)
    return GetResourceState(name) == 'started'
end

local function now()
    return os.time()
end

local function budget(src)
    local t = GetGameTimer()
    local b = readBudget[src]
    if not b or t - b.start >= 1000 then
        b = { start = t, count = 0 }
        readBudget[src] = b
    end
    b.count = b.count + 1
    return b.count <= Config.server.readsPerSecond
end

local cleanText = Records.clean

local function vehicleOf(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return 0 end
    return GetVehiclePedIsIn(ped, false)
end

local function seatedIn(src, vehicle)
    local ped = GetPlayerPed(src)
    for _, seat in ipairs(Config.install.seats) do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return true end
    end
    return false
end

local function modelAllowed(vehicle)
    local modes = Config.install.modes
    local onlyModels = #modes == 1 and modes[1] == 'models'
    if not onlyModels then return true end
    local model = GetEntityModel(vehicle)
    for _, hash in ipairs(Config.install.models) do
        if hash == model then return true end
    end
    return false
end

local function groundReadValid(src, cam, target, beam)
    beam = beam or Config.reader
    local vehicle = vehicleOf(src)
    if vehicle == 0 or vehicle == target then return false, 'not_in_vehicle' end
    if not seatedIn(src, vehicle) then return false, 'wrong_seat' end
    if not modelAllowed(vehicle) then return false, 'not_installed' end
    local origin = GetEntityCoords(vehicle)
    local forward = Geo.forwardFromHeading(GetEntityHeading(vehicle))
    if cam == 'rear' then forward = -forward end
    local point = GetEntityCoords(target)
    local range = beam.range + Config.server.readSlack
    local half = math.min(60.0, beam.halfAngle + Config.server.angleSlack)
    local rel = point - origin
    local dist = #rel
    if dist > range then return false, 'out_of_range' end
    if dist > 8.0 and Geo.angleBetween(vector3(forward.x, forward.y, 0.0), vector3(rel.x, rel.y, 0.0)) > half then
        return false, 'out_of_beam'
    end
    return true, nil, vehicle
end

local function airFeedFor(src)
    if not started(Config.polcam) then return nil end
    local ok, feeds = pcall(function() return exports[Config.polcam]:GetActiveAirFeeds() end)
    if not ok or type(feeds) ~= 'table' then return nil end
    for _, feed in ipairs(feeds) do
        if type(feed) == 'table' and tonumber(feed.operatorSource) == src and feed.cameraActive ~= false then return feed end
    end
    return nil
end

local function vec(t)
    if type(t) ~= 'table' and type(t) ~= 'vector3' then return nil end
    local x, y, z = tonumber(t.x), tonumber(t.y), tonumber(t.z)
    if not x or not y or not z then return nil end
    return vector3(x, y, z)
end

local function airReadValid(src, target)
    local feed = airFeedFor(src)
    if not feed then return false, 'no_air_feed' end
    local point = GetEntityCoords(target)
    local preview = type(feed.preview) == 'table' and feed.preview or {}
    local heli = tonumber(feed.heliNetId) and NetworkGetEntityFromNetworkId(tonumber(feed.heliNetId)) or 0
    if heli == 0 or not DoesEntityExist(heli) or heli == target then return false, 'no_air_feed' end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= heli then return false, 'not_in_heli' end
    local heliPos = GetEntityCoords(heli)
    local reported = vec(preview.coords)
    local originSlack = Config.server.airOriginSlack + GetEntitySpeed(heli) * 0.5
    if reported and #(reported - heliPos) > originSlack then return false, 'bad_origin' end
    local camPos = reported or heliPos
    local dist = #(point - heliPos)
    if dist > Config.air.maxRange + Config.server.readSlack then return false, 'out_of_range' end
    local rot = vec(preview.rotation)
    local fov = tonumber(preview.fov)
    if rot and fov then
        local axis = Geo.directionFromRotation(rot)
        if Geo.angleBetween(axis, point - camPos) > fov * 0.5 + 15.0 then return false, 'out_of_view' end
    end
    return true, nil, feed
end

local function remember(src, plate, entry)
    local book = ledger[src]
    if not book then
        book = {}
        ledger[src] = book
    end
    book[plate] = entry
    local cutoff = now() - Config.server.ledgerSeconds
    for key, e in pairs(book) do
        if e.at < cutoff then book[key] = nil end
    end
end

local function recall(src, plate)
    local book = ledger[src]
    local entry = book and book[plate]
    if not entry or now() - entry.at > Config.server.ledgerSeconds then return nil end
    return entry
end

local function recallVehicle(src, netId, seen)
    if not seen then return nil end
    local entry = recall(src, seen)
    if entry and entry.netId == netId then return seen end
    return nil
end

local function addSighting(plate, entry)
    local list = sightings[plate]
    if not list then
        if sightingPlates >= SIGHTING_PLATES then return end
        sightingPlates = sightingPlates + 1
        list = {}
        sightings[plate] = list
    end
    table.insert(list, 1, entry)
    while #list > 20 do table.remove(list) end
end

CreateThread(function()
    while true do
        Wait(300000)
        local cutoff = now() - SIGHTING_KEEP
        for plate, list in pairs(sightings) do
            while #list > 0 and list[#list].at < cutoff do table.remove(list) end
            if #list == 0 then
                sightings[plate] = nil
                sightingPlates = sightingPlates - 1
            end
        end
        for plate, at in pairs(dispatchedAt) do
            if now() - at > Config.network.dispatchWindowSeconds then dispatchedAt[plate] = nil end
        end
        for plate, book in pairs(fannedAt) do
            for who, at in pairs(book) do
                if now() - at > Config.network.sightingWindowSeconds then book[who] = nil end
            end
            if not next(book) then fannedAt[plate] = nil end
        end
    end
end)

local function unitLabel(src, cam, feed)
    if cam == 'air' and feed then
        local label = cleanText(feed.label, 32) or cleanText(feed.callsign, 32)
        if label then return label end
    end
    return Records.unit(src)
end

local function raiseDispatch(result, where)
    if not Config.network.dispatch then return end
    if #result.bolos == 0 and not result.stolen then return end
    local last = dispatchedAt[result.plate]
    if last and now() - last < Config.network.dispatchWindowSeconds then return end
    dispatchedAt[result.plate] = now()
    local first
    for _, bolo in ipairs(result.bolos) do
        if not bolo.restricted then first = bolo; break end
    end
    local vehicleText = result.label or result.model or L('unknown_vehicle')
    local by, cam = where.unit or '', L('cam_' .. where.cam)
    local title, message
    if first then
        title = L('dispatch_title_bolo', first.number or '')
        message = L('dispatch_message_bolo', result.plate, vehicleText, first.title or '', by, cam)
    elseif result.stolen then
        title = L('dispatch_title_stolen')
        message = L('dispatch_message_stolen', result.plate, vehicleText, by, cam)
    else
        title = L('dispatch_title_bolo_plain')
        message = L('dispatch_message_bolo_plain', result.plate, vehicleText, by, cam)
    end
    local sent = Records.bridge('dispatch', {
        code = Config.network.dispatchCode,
        dispatchCode = ('%s:%s'):format(Config.network.dispatchCode, result.plate),
        title = title,
        message = message,
        priority = MDT_PRIORITY_TO_DISPATCH[result.priority] or 2,
        coords = where.coords,
        street = where.street,
        jobs = result.jobs,
        vehicle = { plate = result.plate, model = vehicleText, colour = result.colour },
    })
    if not sent then dispatchedAt[result.plate] = nil end
end

local function fanOut(src, result, where, netId)
    local book = fannedAt[result.plate] or {}
    fannedAt[result.plate] = book
    local payload = {
        plate = result.plate,
        label = result.label or result.model,
        stolen = result.stolen,
        coords = { x = where.coords.x, y = where.coords.y, z = where.coords.z },
        street = where.street,
        unit = where.unit,
        cam = where.cam,
        netId = netId,
        at = now(),
    }
    for _, r in ipairs(result.recipients or {}) do
        local p = {}
        for k, v in pairs(payload) do p[k] = v end
        p.bolos = r.bolos
        p.stolen = r.stolen
        local last = book[r.source]
        p.quiet = last ~= nil and now() - last < Config.network.sightingWindowSeconds
        if not p.quiet then book[r.source] = now() end
        TriggerClientEvent('cortex-alpr:client:sighting', r.source, p)
    end
end

Clocks = {}

local clocks = {}
local clockBudget = {}
local clockSeq = 0
local clockWarned = false

local function clockAllowed(src)
    local t = GetGameTimer()
    local b = clockBudget[src]
    if not b or t - b.start >= 60000 then
        b = { start = t, count = 0 }
        clockBudget[src] = b
    end
    b.count = b.count + 1
    return b.count <= Config.server.clocksPerMinute
end

local function postedLimit(road, zone)
    local source = Config.clock.limits
    if source and road and started(source) then
        local ok, limit, unit = pcall(function() return exports[source]:GetPostedLimit(road, zone) end)
        if ok and type(limit) == 'number' and limit > 0 then
            return limit / (unit == 'kmh' and Geo.SPEED.kmh or Geo.SPEED.mph)
        end
    end
    if Config.clock.defaultLimit > 0 then return Config.clock.defaultLimit / Geo.SPEED[Config.units] end
    return nil
end

local function fileClock(src, clock)
    if Records.provider() ~= 'mdt' then return false end
    local ok, filed = pcall(function() return exports[Config.mdt]:AlprClock(src, clock) end)
    if ok then return filed ~= nil and filed ~= false end
    if not clockWarned and tostring(filed):find('No such export', 1, true) then
        clockWarned = true
        print(('^3[cortex-alpr] %s has no AlprClock export, so speed locks are not kept for citations. Update %s.^0'):format(Config.mdt, Config.mdt))
    end
    return false
end

local function clockPayload(clock, seq)
    return {
        id = clock.id, cam = clock.cam, speed = clock.speed, limit = clock.limit, plate = clock.plate,
        auto = clock.auto, filed = clock.filed, seq = seq,
    }
end

local function clockView(clock)
    return {
        id = clock.id, at = clock.at, cam = clock.cam, speed = clock.speed, checked = clock.checked, limit = clock.limit,
        plate = clock.plate, street = clock.street, coords = clock.coords, direction = clock.direction, model = clock.model,
        unit = clock.unit, auto = clock.auto, filed = clock.filed,
    }
end

function Clocks.plateRead(src, netId, plate)
    for _, clock in ipairs(clocks[src] or {}) do
        if clock.netId == netId and not clock.plate and clock.seen == plate then
            clock.plate = plate
            clock.filed = fileClock(src, clock)
            TriggerClientEvent('cortex-alpr:client:clock', src, clock.cam, clockPayload(clock))
        end
    end
end

function Clocks.take(src, cam, netId, claimed, where, auto)
    if not Config.clock.enabled then return nil, 'disabled' end
    if cam ~= 'front' and cam ~= 'rear' then return nil, 'bad_cam' end
    netId = math.tointeger(tonumber(netId))
    if not netId then return nil, 'bad_net_id' end
    claimed = tonumber(claimed)
    if not claimed or claimed ~= claimed or claimed < 0.9 or claimed > 150.0 then return nil, 'bad_speed' end
    local target = NetworkGetEntityFromNetworkId(netId)
    if target == 0 or not DoesEntityExist(target) or GetEntityType(target) ~= 2 then return nil, 'no_vehicle' end
    if GetEntityRoutingBucket(target) ~= GetPlayerRoutingBucket(src) then return nil, 'other_bucket' end
    local ok, why, own = groundReadValid(src, cam, target, Config.radar)
    if not ok then return nil, why end
    if Records.provider() == 'offline' then return nil, 'mdt_offline' end
    if not Records.officer(src) then return nil, 'not_on_duty' end

    local velocity = GetEntityVelocity(target)
    local actual = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
    local slack = Config.server.speedSlack
    if actual < 0.9 or claimed > actual + slack or claimed < actual * 0.5 - slack then return nil, 'mismatch' end

    local seen = Geo.plate(GetVehicleNumberPlateText(target))
    where = type(where) == 'table' and where or {}
    local road = cleanText(where.road, 48)
    local cross = cleanText(where.cross, 48)
    local zone = cleanText(where.zone, 8)
    local coords = GetEntityCoords(target)
    clockSeq = clockSeq % 9999 + 1
    local clock = {
        id = ('%x%04d'):format(now(), clockSeq),
        at = now(),
        cam = cam,
        netId = netId,
        speed = math.min(claimed, actual),
        checked = actual,
        seen = seen,
        limit = postedLimit(road, zone),
        patrol = GetEntitySpeed(own),
        direction = where.direction == 'closing' and 'closing' or where.direction == 'away' and 'away' or nil,
        street = road and (cross and ('%s / %s'):format(road, cross) or road) or nil,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        model = cleanText(where.model, 48),
        unit = unitLabel(src, cam),
        auto = auto == true,
        plate = recallVehicle(src, netId, seen),
    }
    clock.filed = fileClock(src, clock)

    local list = clocks[src] or {}
    clocks[src] = list
    table.insert(list, 1, clock)
    local cutoff = now() - Config.clock.keepSeconds
    while #list > 12 or (list[#list] and list[#list].at < cutoff) do table.remove(list) end
    TriggerEvent('cortex-alpr:clocked', src, clockView(clock))
    return clock
end

RegisterNetEvent('cortex-alpr:server:clock', function(cam, netId, claimed, where, auto, seq)
    local src = source
    seq = math.tointeger(tonumber(seq))
    if not clockAllowed(src) then
        if cam == 'front' or cam == 'rear' then TriggerClientEvent('cortex-alpr:client:clock', src, cam, nil, 'rate', seq) end
        return
    end
    if type(cam) ~= 'string' then return end
    local clock, why = Clocks.take(src, cam, netId, claimed, where, auto)
    if not clock then
        if Debug then Debug('clock refused %s %s: %s', tostring(cam), tostring(netId), tostring(why)) end
        if cam == 'front' or cam == 'rear' then TriggerClientEvent('cortex-alpr:client:clock', src, cam, nil, why, seq) end
        return
    end
    TriggerClientEvent('cortex-alpr:client:clock', src, cam, clockPayload(clock, seq))
end)

function Alpr.read(src, cam, netId, street)
    if not CAMS[cam] then return nil, 'bad_cam' end
    netId = math.tointeger(tonumber(netId))
    if not netId then return nil, 'bad_net_id' end
    local target = NetworkGetEntityFromNetworkId(netId)
    if target == 0 or not DoesEntityExist(target) or GetEntityType(target) ~= 2 then return nil, 'no_vehicle' end
    if GetEntityRoutingBucket(target) ~= GetPlayerRoutingBucket(src) then return nil, 'other_bucket' end

    local ok, why, feed
    if cam == 'air' then
        ok, why, feed = airReadValid(src, target)
    else
        ok, why = groundReadValid(src, cam, target)
    end
    if not ok then return nil, why end

    local plate = Geo.plate(GetVehicleNumberPlateText(target))
    if not plate then return nil, 'no_plate' end

    local coords = GetEntityCoords(target)
    local where = {
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        street = cleanText(street, 64),
        cam = cam,
    }
    local provider = Records.provider()
    if provider == 'offline' then return nil, 'mdt_offline' end
    if provider == 'hotlist' and not Records.officer(src) then return nil, 'not_on_duty' end
    where.unit = unitLabel(src, cam, feed)

    local result, err
    if provider == 'mdt' then
        local okCall
        okCall, result, err = pcall(function() return exports[Config.mdt]:AlprRead(src, plate, cam, where) end)
        if not okCall then
            local missing = tostring(result):find('No such export', 1, true) ~= nil
            if missing and not mdtWarned then
                mdtWarned = true
                print(("^1[cortex-alpr] %s has no AlprRead export. Update %s, or set Config.records to 'hotlist'.^0"):format(Config.mdt, Config.mdt))
            elseif not missing and GetGameTimer() - mdtErrorAt > 10000 then
                mdtErrorAt = GetGameTimer()
                print(('^3[cortex-alpr] MDT read failed: %s^0'):format(tostring(result)))
            end
            return nil, 'mdt_error'
        end
        if not result then return nil, err end
        if not GetPlayerName(src) then return nil, 'bad_source' end
        if Hot.has(plate) then
            local quiet = result.clean or result.cooldown or (not result.stolen and #(result.bolos or {}) == 0)
            if quiet then
                local hot = Hot.read(src, plate, where)
                if hot.reader then
                    local also = result.reader and type(result.reader.text) == 'string' and result.reader.text:gsub('^[^%.]*%.%s*', '', 1) or ''
                    if also ~= '' then hot.reader.text = ('%s %s'):format(hot.reader.text, also) end
                    result = hot
                elseif not result.reader then
                    result = hot
                end
            else
                Hot.mark(src, plate)
            end
        end
    else
        result = Hot.read(src, plate, where)
    end
    if not GetPlayerName(src) then return nil, 'bad_source' end

    remember(src, plate, { at = now(), netId = netId, cam = cam, coords = where.coords, street = where.street, unit = where.unit })
    Clocks.plateRead(src, netId, plate)
    if result.clean then return result end
    addSighting(plate, { at = now(), cam = cam, coords = where.coords, street = where.street, unit = where.unit, by = src })
    if result.cooldown then return result end

    if result.reader then
        TriggerClientEvent('cortex-alpr:client:hit', src, {
            cam = cam,
            netId = netId,
            plate = plate,
            label = result.label or result.model,
            kind = result.reader.kind,
            text = result.reader.text,
            lock = result.reader.lock == true,
            alarm = result.reader.bolo == true,
            bolos = result.shown and result.shown.bolos or {},
            stolen = result.shown and result.shown.stolen == true,
        })
    end
    if #result.bolos > 0 or result.stolen then
        fanOut(src, result, where, netId)
        raiseDispatch(result, where)
    end
    if result.reader or #result.bolos > 0 or result.stolen then
        TriggerEvent('cortex-alpr:hit', src, {
            plate = plate, cam = cam, netId = netId, coords = where.coords, street = where.street, unit = where.unit,
            label = result.label or result.model, stolen = result.stolen == true, bolos = result.bolos,
            text = result.reader and result.reader.text or nil,
        })
    end
    return result
end

RegisterNetEvent('cortex-alpr:server:read', function(cam, netId, street)
    local src = source
    if not budget(src) then return end
    if type(cam) ~= 'string' then return end
    local _, why = Alpr.read(src, cam, netId, street)
    if why and Debug then Debug('read refused %s %s: %s', tostring(cam), tostring(netId), why) end
end)

lib.callback.register('cortex-alpr:bolo', function(src, plate, fields)
    plate = Geo.plate(plate)
    if not plate then return { ok = false, error = 'bad_plate' } end
    local entry = recall(src, plate)
    if not entry then return { ok = false, error = 'not_read' } end
    local provider = Records.provider()
    if provider == 'offline' then return { ok = false, error = 'mdt_offline' } end
    fields = type(fields) == 'table' and fields or {}
    local data = {
        plate = plate,
        title = cleanText(fields.title, 80),
        priority = fields.priority,
        vehicle = { model = cleanText(fields.model, 48), colour = cleanText(fields.colour, 32) },
        lastSeen = { street = entry.street, coords = entry.coords, unit = entry.unit, cam = entry.cam },
        unit = entry.unit,
    }
    local result, err
    if provider == 'mdt' then
        local ok
        ok, result, err = pcall(function() return exports[Config.mdt]:AlprCreateBolo(src, data) end)
        if not ok then return { ok = false, error = 'mdt_error' } end
    else
        result, err = Hot.file(src, data)
    end
    if not result then return { ok = false, error = err or 'refused' } end
    if result.existing ~= true then
        dispatchedAt[plate] = nil
        fannedAt[plate] = nil
    end
    return { ok = true, number = result.number, existing = result.existing == true }
end)

local function forget(src)
    readBudget[src] = nil
    ledger[src] = nil
    clocks[src] = nil
    clockBudget[src] = nil
    Records.forget(src)
    Hot.dropPlayer(src)
end

AddEventHandler('playerDropped', function()
    forget(source)
end)

for _, name in ipairs({ 'qbx_core:server:playerLoggedOut', 'QBCore:Server:OnPlayerUnload', 'esx:playerLogout' }) do
    AddEventHandler(name, function(src)
        local origin = source
        src = math.tointeger(tonumber(src))
        if not src then return end
        if origin ~= nil and origin ~= '' and origin ~= 0 and math.tointeger(tonumber(origin)) ~= src then return end
        forget(src)
    end)
end

AddEventHandler('cortex-alpr:hotlistChanged', function(action, entry)
    if action ~= 'added' or type(entry) ~= 'table' or type(entry.plate) ~= 'string' then return end
    dispatchedAt[entry.plate] = nil
    fannedAt[entry.plate] = nil
end)

exports('GetClocks', function(src)
    local out = {}
    for i, clock in ipairs(clocks[math.tointeger(tonumber(src)) or -1] or {}) do
        out[i] = {
            id = clock.id, at = clock.at, cam = clock.cam, speed = clock.speed, checked = clock.checked, limit = clock.limit,
            plate = clock.plate, street = clock.street, direction = clock.direction, auto = clock.auto, filed = clock.filed,
        }
    end
    return out
end)

exports('GetSightings', function(plate)
    plate = Geo.plate(plate)
    if not plate then return {} end
    local out = {}
    for i, e in ipairs(sightings[plate] or {}) do
        out[i] = { at = e.at, cam = e.cam, coords = e.coords, street = e.street, unit = e.unit }
    end
    return out
end)

RegisterCommand('alpr_sightings', function(src, args)
    local plate = Geo.plate(args[1])
    if not plate then return Records.say(src, 'usage: alpr_sightings <plate>') end
    local list = sightings[plate] or {}
    Records.say(src, ('%s: %d reads in the last 2 hours'):format(plate, #list))
    for _, e in ipairs(list) do
        Records.say(src, ('%s  %s camera  %s  %s'):format(os.date('%H:%M:%S', e.at), e.cam, e.unit or '?', e.street or 'unknown street'))
    end
end, true)

exports('ReportRead', function(src, cam, netId, street)
    src = math.tointeger(tonumber(src))
    if not src or GetPlayerPed(src) == 0 then return nil, 'bad_source' end
    if type(cam) ~= 'string' then return nil, 'bad_cam' end
    return Alpr.read(src, cam, netId, street)
end)
