Bridge = {}

function Bridge.job(src)
    local fw = Framework()
    if fw then
        local name, grade, onDuty, _, kind = fw.job(src)
        return name, tonumber(grade) or 0, onDuty, kind
    end
    if GetResourceState('qbx_core') == 'started' then
        local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        local job = ok and type(player) == 'table' and type(player.PlayerData) == 'table' and player.PlayerData.job
        if type(job) == 'table' then
            return job.name, type(job.grade) == 'table' and tonumber(job.grade.level) or 0, job.onduty, job.type
        end
    end
    return nil, 0, false, nil
end

function Bridge.officer(src)
    if Config.jobs.ace and IsPlayerAceAllowed(src, Config.jobs.ace) then return true end
    local name, _, onDuty, kind = Bridge.job(src)
    return JobAllowed(name, onDuty, kind)
end

function Bridge.grade(src)
    local name, grade, onDuty, kind = Bridge.job(src)
    return JobAllowed(name, onDuty, kind) and grade or 0
end

function Bridge.unit(src)
    local fw = Framework()
    if fw then
        local callsign = fw.meta(src, 'callsign')
        if type(callsign) == 'string' and callsign ~= '' and callsign ~= 'NO CALLSIGN' then return callsign end
        local name = fw.characterName(src)
        if type(name) == 'string' and name ~= '' then return name end
    end
    return GetPlayerName(src)
end

function Bridge.identity(src)
    local fw = Framework()
    local id = fw and fw.characterId(src) or nil
    return id or GetPlayerIdentifierByType(src, 'license') or tostring(src)
end

function Bridge.lookup(plate)
    return nil
end

function Bridge.dispatch(alert)
    if GetResourceState(Config.dispatch) ~= 'started' then return false end
    local call = exports[Config.dispatch]:CustomAlert({
        code = alert.code,
        dispatchCode = alert.dispatchCode,
        title = alert.title,
        message = alert.message,
        priority = alert.priority,
        coords = alert.coords,
        street = alert.street,
        jobs = alert.jobs,
        vehicle = alert.vehicle,
    })
    return call ~= nil and call ~= false
end
