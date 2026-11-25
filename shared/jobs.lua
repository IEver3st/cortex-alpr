function JobAllowed(name, onDuty, kind)
    if type(name) ~= 'string' or name == '' then return false end
    if Config.jobs.requireDuty and onDuty == false then return false end
    for _, t in ipairs(Config.jobs.types) do
        if kind == t then return true end
    end
    for _, n in ipairs(Config.jobs.names) do
        if name == n then return true end
    end
    return false
end

function Framework()
    local ok, fw = pcall(function() return lib.framework end)
    if ok and type(fw) == 'table' and type(fw.job) == 'function' then return fw end
    return nil
end
