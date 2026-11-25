Radar = {}

local FLAGS = 1
local MOTORCYCLE = 8
local SIGHT_MS = 300
local SIGHT_STALE_MS = 1000
local PROBES_PER_SAMPLE = 4
local PICK_DEPTH = 3
local RELOCK_MS = 20000

local function antenna(mode)
    return {
        xmit = true,
        mode = mode,
        target = nil,
        fast = nil,
        dir = nil,
        fastDir = nil,
        vehicle = nil,
        fastVehicle = nil,
        locked = false,
        lockTarget = nil,
        lockFast = nil,
        lockDir = nil,
        lockFastDir = nil,
        lockVehicle = nil,
        clock = nil,
        released = nil,
        plate = nil,
        plateLocked = false,
    }
end

Radar.antennas = {
    front = antenna(Config.radar.frontMode),
    rear = antenna(Config.radar.rearMode),
}
Radar.patrol = 0.0
Radar.fastLimit = Config.radar.fastLimit
Radar.autoLock = Config.radar.autoLock
Radar.reads = {}
Radar.sentAt = {}
Radar.diag = { front = {}, rear = {}, samples = 0 }
Radar.onClock = nil

local pool, poolAt = {}, 0
local sentCount = 0
local sight = {}
local probes = 0
local areas = {}

local function refreshPool(origin, own, reach)
    local now = GetGameTimer()
    if now - poolAt < Config.radar.poolMs then return end
    poolAt = now
    local out, kept = {}, {}
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if vehicle ~= own and #(GetEntityCoords(vehicle) - origin) <= reach then
            out[#out + 1] = vehicle
            kept[vehicle] = sight[vehicle]
        end
    end
    pool, sight = out, kept
end

function Radar.resetPool()
    pool, poolAt, sight = {}, 0, {}
end

local function laneMatches(mode, same)
    if mode == 'both' then return true end
    if mode == 'same' then return same end
    return not same
end

local function areaOf(vehicle)
    local model = GetEntityModel(vehicle)
    local area = areas[model]
    if area then return area end
    local low, high = GetModelDimensions(model)
    area = math.max(1.0, (high.x - low.x) * (high.z - low.z))
    areas[model] = area
    return area
end

function Radar.modelLabel(vehicle)
    local name = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = GetLabelText(name)
    if label == 'NULL' or label == '' then label = name end
    return label
end

local function recordRead(cam, vehicle, plate)
    local entry = {
        plate = plate,
        cam = cam,
        label = Radar.modelLabel(vehicle),
        style = GetVehicleNumberPlateTextIndex(vehicle),
        at = GetGameTimer(),
        netId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil,
    }
    local reads = Radar.reads
    for i = #reads, 1, -1 do
        if reads[i].plate == plate then
            entry.hit = entry.hit or reads[i].hit
            table.remove(reads, i)
        end
    end
    table.insert(reads, 1, entry)
    local i = #reads
    while #reads > Config.reader.history and i > 0 do
        local p = reads[i].plate
        local held = false
        for _, a in pairs(Radar.antennas) do
            if a.plateLocked and a.plate and a.plate.plate == p then held = true end
        end
        if not held then table.remove(reads, i) end
        i = i - 1
    end
    return entry
end

function Radar.findRead(plate)
    for _, r in ipairs(Radar.reads) do
        if r.plate == plate then return r end
    end
    return nil
end

function Radar.roadAt(coords)
    local a, b = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local road = GetStreetNameFromHashKey(a)
    local cross = b ~= 0 and GetStreetNameFromHashKey(b) or nil
    if cross == '' then cross = nil end
    return road, cross
end

function Radar.streetAt(coords)
    local road, cross = Radar.roadAt(coords)
    if cross then return ('%s / %s'):format(road, cross) end
    return road
end

function Radar.send(cam, vehicle, plate)
    if not NetworkGetEntityIsNetworked(vehicle) then return end
    local now = GetGameTimer()
    local last = Radar.sentAt[plate]
    if last and now - last < Config.reader.resendSeconds * 1000 then return end
    sentCount = sentCount + 1
    if sentCount > 200 then
        local kept, count = {}, 0
        for key, at in pairs(Radar.sentAt) do
            if now - at < Config.reader.resendSeconds * 1000 then kept[key] = at; count = count + 1 end
        end
        Radar.sentAt, sentCount = kept, count + 1
    end
    Radar.sentAt[plate] = now
    TriggerServerEvent('cortex-alpr:server:read', cam, NetworkGetNetworkIdFromEntity(vehicle), Radar.streetAt(GetEntityCoords(vehicle)))
    if Radar.onSend then Radar.onSend(cam, vehicle, plate) end
end

local function plateCandidate(cam, origin, axis, vehicle, best)
    local c = GetEntityCoords(vehicle)
    local inside, along = Geo.inBeam(origin, axis, c, Config.reader.range, Config.reader.halfAngle, 1.6)
    if not inside then return best end
    if best and along >= best.along then return best end
    local facing = Geo.plateFacing(GetEntityForwardVector(vehicle), c - origin, Config.reader.plateAngle)
    if not facing then return best end
    if facing == 'front' and GetVehicleClass(vehicle) == MOTORCYCLE then return best end
    return { vehicle = vehicle, along = along, coords = c }
end

local function clearSight(own, from, to, vehicle)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, FLAGS, own, 7)
    local status, hit, _, _, entity = GetShapeTestResult(handle)
    local d = Radar.diag
    d.status, d.hit, d.entity = status, hit, entity
    return status == 2 and (hit == 0 or entity == vehicle)
end

Radar.clearSight = clearSight

local function inSight(own, origin, entry)
    if not Config.radar.lineOfSight then return true end
    local now = GetGameTimer()
    local known = sight[entry.vehicle]
    if known and now - known.at < SIGHT_MS then return known.clear end
    if probes >= PROBES_PER_SAMPLE then
        if known and now - known.at < SIGHT_STALE_MS then return known.clear end
        return false
    end
    probes = probes + 1
    local from = origin + vector3(0.0, 0.0, 0.9)
    local to = entry.coords + vector3(0.0, 0.0, 0.5)
    local clear = clearSight(own, from, to, entry.vehicle)
    sight[entry.vehicle] = { at = now, clear = clear }
    return clear
end

local function pick(own, origin, list, key, diag)
    if #list == 0 then return nil end
    table.sort(list, function(x, y) return x[key] > y[key] end)
    for i = 1, math.min(#list, PICK_DEPTH) do
        if inSight(own, origin, list[i]) then return list[i] end
        diag.blocked = (diag.blocked or 0) + 1
    end
    return nil
end

local function pumpPlate(cam, a, own, origin, candidate)
    Radar.diag[cam].candidate = candidate and candidate.vehicle or nil
    if not candidate then return end
    local vehicle = candidate.vehicle
    local plate = Geo.plate(GetVehicleNumberPlateText(vehicle))
    if not plate then return end
    local last = Radar.findRead(plate)
    if last and GetGameTimer() - last.at < 1000 then return end
    local from = origin + vector3(0.0, 0.0, 0.9)
    local to = candidate.coords + vector3(0.0, 0.0, 0.5)
    Radar.diag[cam].started = (Radar.diag[cam].started or 0) + 1
    if not clearSight(own, from, to, vehicle) then return end
    Radar.diag[cam].done = (Radar.diag[cam].done or 0) + 1
    local entry = recordRead(cam, vehicle, plate)
    if not a.plateLocked then
        a.plate = { plate = plate, label = entry.label, style = entry.style, at = entry.at, hit = entry.hit, netId = entry.netId }
    end
    Radar.send(cam, vehicle, plate)
    Radar.dirty = true
end

local function sameValue(a, b)
    if a == nil or b == nil then return a == b end
    return math.floor(a * 10) == math.floor(b * 10)
end

local function captured(a)
    if a.fast then return a.fastVehicle, a.fast, a.fastDir end
    return a.vehicle, a.target, a.dir
end

local clockSeq = 0

function Radar.lock(cam, auto)
    local a = Radar.antennas[cam]
    if not a or a.locked then return false end
    if a.target == nil and a.fast == nil then
        if auto or a.plate == nil then return false end
        a.plateLocked = true
        Radar.dirty = true
        return true
    end
    local vehicle, speed, dir = captured(a)
    a.locked = true
    a.lockTarget, a.lockFast, a.lockDir, a.lockFastDir, a.lockVehicle = a.target, a.fast, a.dir, a.fastDir, vehicle
    if not auto then a.plateLocked = Radar.plateOf(a, vehicle) end
    clockSeq = clockSeq + 1
    a.clock = { pending = true, seq = clockSeq, speed = speed, auto = auto == true }
    Radar.dirty = true
    if Radar.onClock and vehicle and DoesEntityExist(vehicle) then
        Radar.onClock(cam, { vehicle = vehicle, speed = speed, dir = dir, auto = auto == true, seq = clockSeq })
    else
        Radar.failClock(cam, clockSeq)
    end
    return true
end

function Radar.plateOf(a, vehicle)
    if not a.plate or not a.plate.netId or not vehicle or vehicle == 0 then return false end
    if not DoesEntityExist(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then return false end
    return NetworkGetNetworkIdFromEntity(vehicle) == a.plate.netId
end

function Radar.clearHit(plate)
    for _, read in ipairs(Radar.reads) do
        if read.plate == plate then read.hit = nil end
    end
    for _, a in pairs(Radar.antennas) do
        if a.plate and a.plate.plate == plate then
            a.plate.hit = nil
            if not a.locked then a.plateLocked = false end
        end
    end
    Radar.sentAt[plate] = nil
    Radar.dirty = true
end

function Radar.unlock(cam)
    local a = Radar.antennas[cam]
    if not a or not (a.locked or a.plateLocked) then return false end
    if a.lockVehicle then a.released = { vehicle = a.lockVehicle, at = GetGameTimer() } end
    a.locked, a.lockTarget, a.lockFast, a.lockDir, a.lockFastDir, a.lockVehicle = false, nil, nil, nil, nil, nil
    a.plateLocked, a.clock = false, nil
    if a.plate then a.plate.hit = nil end
    Radar.dirty = true
    return true
end

function Radar.toggleLock(cam)
    local a = Radar.antennas[cam]
    if not a then return nil end
    if a.locked or a.plateLocked then
        Radar.unlock(cam)
        return false
    end
    return Radar.lock(cam, false)
end

function Radar.setClock(cam, clock, seq)
    local a = Radar.antennas[cam]
    if not a or not a.locked or not a.clock then return false end
    if a.clock.pending then
        if a.clock.seq ~= seq then return false end
    elseif a.clock.id ~= clock.id then
        return false
    end
    a.clock = clock
    Radar.dirty = true
    return true
end

function Radar.failClock(cam, seq)
    local a = Radar.antennas[cam]
    if not a or not a.clock or not a.clock.pending or a.clock.seq ~= seq then return end
    a.clock = { speed = a.clock.speed, auto = a.clock.auto, unfiled = true }
    Radar.dirty = true
end

function Radar.clockFor(cam)
    local a = Radar.antennas[cam]
    local clock = a and a.locked and a.clock or nil
    if clock and clock.id then return clock end
    return nil
end

local function shouldAutoLock(a, unit)
    if not Radar.autoLock or a.locked or Radar.fastLimit <= 0 then return false end
    local vehicle, speed = captured(a)
    if not speed or speed * unit < Radar.fastLimit then return false end
    local released = a.released
    if released and released.vehicle == vehicle and GetGameTimer() - released.at < RELOCK_MS then return false end
    return true
end

function Radar.sample(own)
    local origin = GetEntityCoords(own)
    local forward = GetEntityForwardVector(own)
    local up = GetOffsetFromEntityInWorldCoords(own, 0.0, 0.0, 1.0) - origin
    local ownVelocity = GetEntityVelocity(own)
    local axes = { front = vector3(forward.x, forward.y, 0.0), rear = vector3(-forward.x, -forward.y, 0.0) }
    local reach = math.max(Config.radar.range, Config.reader.range) + 10.0
    refreshPool(origin, own, reach)
    probes = 0
    local diag = Radar.diag
    diag.samples = diag.samples + 1
    diag.pool = #pool
    diag.front.blocked, diag.rear.blocked = 0, 0
    diag.front.height, diag.rear.height = 0, 0

    local patrol = GetEntitySpeed(own)
    if not sameValue(patrol, Radar.patrol) then Radar.patrol = patrol; Radar.dirty = true end

    local found = { front = { list = {} }, rear = { list = {} } }
    local radar = Config.radar
    for _, vehicle in ipairs(pool) do
        if DoesEntityExist(vehicle) then
            local c = GetEntityCoords(vehicle)
            local rel = c - origin
            local same = Geo.dot2(GetEntityForwardVector(vehicle), forward) > 0.0
            for cam, axis in pairs(axes) do
                local a = Radar.antennas[cam]
                if a.xmit then
                    local inside, along = Geo.inBeam(origin, axis, c, radar.range, radar.halfAngle, radar.nearWidth)
                    if inside and laneMatches(a.mode, same) then
                        if Geo.inHeight(rel, up, along, radar.verticalAngle, radar.nearHeight) then
                            local speed, dir = Geo.beamSpeed(GetEntityVelocity(vehicle), ownVelocity, rel, radar.cosine)
                            if speed > 0.9 then
                                local list = found[cam].list
                                list[#list + 1] = {
                                    vehicle = vehicle, coords = c, along = along, speed = speed, dir = dir,
                                    signal = areaOf(vehicle) ^ radar.sizeBias / (along * along),
                                }
                            end
                        else
                            diag[cam].height = diag[cam].height + 1
                        end
                    end
                    found[cam].plate = plateCandidate(cam, origin, axis, vehicle, found[cam].plate)
                end
            end
        end
    end

    local unit = Geo.SPEED[Radar.units or Config.units]
    for cam, a in pairs(Radar.antennas) do
        local list = found[cam].list
        local strong = a.xmit and pick(own, origin, list, 'signal', diag[cam]) or nil
        local fastest = a.xmit and pick(own, origin, list, 'speed', diag[cam]) or nil
        if fastest and strong and (fastest.vehicle == strong.vehicle or fastest.speed - strong.speed < 0.5) then fastest = nil end
        if fastest and fastest.speed * unit < Radar.fastLimit then fastest = nil end
        local target, dir = strong and strong.speed or nil, strong and strong.dir or nil
        local fast, fastDir = fastest and fastest.speed or nil, fastest and fastest.dir or nil
        if not sameValue(target, a.target) or not sameValue(fast, a.fast) or dir ~= a.dir or fastDir ~= a.fastDir then
            Radar.dirty = true
        end
        a.target, a.dir, a.vehicle = target, dir, strong and strong.vehicle or nil
        a.fast, a.fastDir, a.fastVehicle = fast, fastDir, fastest and fastest.vehicle or nil
        diag[cam].candidates = #list
        diag[cam].strong = strong and { speed = strong.speed, along = strong.along, signal = strong.signal } or nil
        if shouldAutoLock(a, unit) and Radar.lock(cam, true) and Radar.onAutoLock then Radar.onAutoLock(cam) end
        if a.xmit then pumpPlate(cam, a, own, origin, found[cam].plate) end
    end
end

function Radar.lockPlate(cam, hit)
    local a = Radar.antennas[cam]
    if not a or not a.plate then return end
    a.plateLocked = true
    a.plate.hit = hit
    Radar.dirty = true
end

function Radar.cycleMode(cam)
    local a = Radar.antennas[cam]
    local order = { same = 'opp', opp = 'both', both = 'same' }
    a.mode = order[a.mode] or 'same'
    Radar.dirty = true
    return a.mode
end

function Radar.clear()
    for _, a in pairs(Radar.antennas) do
        a.target, a.fast, a.dir, a.fastDir, a.vehicle, a.fastVehicle = nil, nil, nil, nil, nil, nil
        a.locked, a.lockTarget, a.lockFast, a.lockDir, a.lockFastDir, a.lockVehicle = false, nil, nil, nil, nil, nil
        a.clock, a.released = nil, nil
        a.plate, a.plateLocked = nil, false
    end
    Radar.patrol = 0.0
    Radar.resetPool()
    Radar.dirty = true
end

local function toUnits(v, unit)
    if not v then return nil end
    return math.floor(v * unit + 0.5)
end

local function clockView(clock, unit)
    if not clock then return nil end
    local speed, limit = toUnits(clock.speed, unit), toUnits(clock.limit, unit)
    return {
        id = clock.id,
        speed = speed,
        limit = limit,
        over = limit and speed and speed > limit and speed - limit or nil,
        plate = clock.plate,
        auto = clock.auto == true,
        pending = clock.pending == true,
        unfiled = clock.unfiled == true,
    }
end

function Radar.snapshot()
    local unit = Geo.SPEED[Radar.units or Config.units]
    local now = GetGameTimer()
    local function paired(a)
        return Radar.plateOf(a, a.locked and a.lockVehicle or a.vehicle)
    end
    local function side(a)
        return {
            xmit = a.xmit,
            mode = a.mode,
            target = toUnits(a.locked and a.lockTarget or a.target, unit),
            fast = toUnits(a.locked and a.lockFast or a.fast, unit),
            dir = a.locked and a.lockDir or a.dir,
            fastDir = a.locked and a.lockFastDir or a.fastDir,
            live = a.locked and toUnits(a.target, unit) or nil,
            locked = a.locked,
            clock = a.locked and clockView(a.clock, unit) or nil,
            plateLocked = a.plateLocked,
            plate = a.plate and {
                plate = a.plate.plate,
                label = a.plate.label,
                style = a.plate.style,
                age = math.floor((now - a.plate.at) / 1000),
                hit = a.plate.hit,
                paired = paired(a),
            } or nil,
        }
    end
    local reads = {}
    for i, r in ipairs(Radar.reads) do
        reads[i] = { plate = r.plate, cam = r.cam, label = r.label, style = r.style, age = math.floor((now - r.at) / 1000), hit = r.hit }
    end
    local front, rear = Radar.antennas.front, Radar.antennas.rear
    local heard = (front.xmit and front.target) or (rear.xmit and rear.target) or nil
    return {
        units = Radar.units or Config.units,
        patrol = toUnits(Radar.patrol, unit),
        fastLimit = Radar.fastLimit,
        tone = heard and heard * Geo.SPEED.mph or nil,
        front = side(front),
        rear = side(rear),
        reads = reads,
    }
end
