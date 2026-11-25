Air = { active = false, labels = {}, lastRead = nil }

local gen = 0

local function polcamActive()
    if not Config.air.enabled or GetResourceState(Config.polcam) ~= 'started' then return false end
    local ok, active = pcall(function() return exports[Config.polcam]:IsPolCamActive() end)
    return ok and active == true
end

function Air.target()
    if GetResourceState(Config.polcam) ~= 'started' then return nil end
    local ok, entity = pcall(function() return exports[Config.polcam]:GetCurrentTarget() end)
    if not ok or type(entity) ~= 'number' or entity == 0 or not DoesEntityExist(entity) then return nil end
    if GetEntityType(entity) == 1 then
        local vehicle = GetVehiclePedIsIn(entity, false)
        entity = vehicle ~= 0 and vehicle or 0
    end
    if entity == 0 or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

local function rangeFor(fov)
    local scaled = Config.air.baseRange * (Config.air.referenceFov / math.max(1.0, fov))
    return math.min(Config.air.maxRange, math.max(Config.air.baseRange, scaled))
end

local function candidate(camPos, axis, fov, own)
    local range = rangeFor(fov)
    local limit = fov * 0.5 * Config.air.centreFraction
    local best, bestAngle = nil, nil
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if vehicle ~= own then
            local c = GetEntityCoords(vehicle)
            local rel = c - camPos
            local dist = #rel
            if dist <= range and dist > 5.0 then
                local angle = Geo.angleBetween(axis, rel)
                if angle <= limit then
                    local flat = math.sqrt(rel.x * rel.x + rel.y * rel.y)
                    local elevation = math.deg(math.atan(math.abs(rel.z), math.max(0.01, flat)))
                    if elevation <= Config.air.maxElevation then
                        local facing = Geo.plateFacing(GetEntityForwardVector(vehicle), rel, Config.air.plateAngle)
                        if facing and not (facing == 'front' and GetVehicleClass(vehicle) == 8) then
                            local plate = Geo.plate(GetVehicleNumberPlateText(vehicle))
                            local fresh = plate and (not Radar.sentAt[plate] or GetGameTimer() - Radar.sentAt[plate] >= Config.reader.resendSeconds * 1000)
                            if fresh and (not bestAngle or angle < bestAngle) then best, bestAngle = vehicle, angle end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function pump(own)
    local camPos = GetFinalRenderedCamCoord()
    local axis = Geo.directionFromRotation(GetFinalRenderedCamRot(2))
    local fov = GetFinalRenderedCamFov()
    local rot = GetFinalRenderedCamRot(2)
    Air.diag = { cam = { x = camPos.x, y = camPos.y, z = camPos.z }, pitch = rot.x, heading = rot.z, fov = fov, range = rangeFor(fov) }
    local vehicle = candidate(camPos, axis, fov, own)
    Air.diag.candidate = vehicle
    if not vehicle then return end
    local to = GetEntityCoords(vehicle) + vector3(0.0, 0.0, 0.6)
    if not Radar.clearSight(own, camPos, to, vehicle) then return end
    local plate = Geo.plate(GetVehicleNumberPlateText(vehicle))
    if not plate then return end
    Air.lastRead = { plate = plate, vehicle = vehicle, label = Radar.modelLabel(vehicle), at = GetGameTimer() }
    Radar.send('air', vehicle, plate)
end

function Air.start()
    if Air.active then return end
    Air.active = true
    gen = gen + 1
    local mine = gen
    CreateThread(function()
        while mine == gen do
            local own = GetVehiclePedIsIn(PlayerPedId(), false)
            pump(own)
            Wait(Config.air.sampleMs)
        end
    end)
end

function Air.stop()
    if not Air.active then return end
    Air.active = false
    gen = gen + 1
end

function Air.watch()
    if polcamActive() then Air.start() else Air.stop() end
end

function Air.addLabel(netId, data)
    Air.labels[netId] = {
        plate = data.plate,
        text = data.text,
        bolo = data.bolos and data.bolos[1] and data.bolos[1].number or nil,
        stolen = data.stolen,
        kind = data.kind,
        expires = GetGameTimer() + Config.air.labelSeconds * 1000,
    }
    Air.drawLabels()
end

local drawing = false

function Air.drawLabels()
    if drawing then return end
    drawing = true
    CreateThread(function()
        while next(Air.labels) do
            local now = GetGameTimer()
            local out = {}
            for netId, label in pairs(Air.labels) do
                local entity = NetworkDoesEntityExistWithNetworkId(netId) and NetToVeh(netId) or 0
                if now > label.expires or entity == 0 then
                    Air.labels[netId] = nil
                else
                    local c = GetEntityCoords(entity)
                    local onScreen, x, y = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + 1.4)
                    if onScreen then
                        out[#out + 1] = { id = netId, x = x, y = y, plate = label.plate, bolo = label.bolo, stolen = label.stolen, kind = label.kind }
                    end
                end
            end
            Nui.send('labels', out)
            Wait(#out > 0 and 0 or 200)
        end
        Nui.send('labels', {})
        drawing = false
    end)
end
