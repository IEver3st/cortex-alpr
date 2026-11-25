Bridge = {}

function Bridge.job()
    local fw = Framework()
    if fw then
        local name, grade, onDuty, _, kind = fw.job()
        return name, tonumber(grade) or 0, onDuty, kind
    end
    if GetResourceState('qbx_core') == 'started' then
        local ok, data = pcall(function() return exports.qbx_core:GetPlayerData() end)
        local job = ok and type(data) == 'table' and data.job
        if type(job) == 'table' then
            return job.name, type(job.grade) == 'table' and tonumber(job.grade.level) or 0, job.onduty, job.type
        end
    end
    return nil, 0, false, nil
end

function Bridge.officer()
    if LocalPlayer.state['cortex-alpr:ace'] == true then return true end
    local name, _, onDuty, kind = Bridge.job()
    return JobAllowed(name, onDuty, kind)
end
