Install = {}

local modelSet = {}
for _, hash in ipairs(Config.install.models) do modelSet[hash] = true end

function Install.officer()
    local ok, officer = pcall(Bridge.officer)
    return ok and officer == true
end

local function modkitFitted(vehicle)
    local spec = Config.install.modkit.models[GetEntityModel(vehicle)] or Config.install.modkit
    local installed = GetVehicleMod(vehicle, spec.type)
    if installed < 0 then return false end
    if not spec.indices then return true end
    for _, index in ipairs(spec.indices) do
        if installed == index then return true end
    end
    return false
end

local CHECKS = {
    any = function() return true end,
    emergency = function(vehicle) return GetVehicleClass(vehicle) == 18 end,
    models = function(vehicle) return modelSet[GetEntityModel(vehicle)] == true end,
    extra = function(vehicle)
        local extra = Config.install.extra
        return DoesExtraExist(vehicle, extra) and IsVehicleExtraTurnedOn(vehicle, extra)
    end,
    modkit = modkitFitted,
}

function Install.fitted(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    for _, mode in ipairs(Config.install.modes) do
        local check = CHECKS[mode]
        if check and check(vehicle) then return true end
    end
    return false
end

function Install.seated(vehicle, ped)
    for _, seat in ipairs(Config.install.seats) do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return true end
    end
    return false
end

function Install.isAircraft(vehicle)
    local class = GetVehicleClass(vehicle)
    return class == 15 or class == 16
end
