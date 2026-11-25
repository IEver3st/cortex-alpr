Records = {}

local OFFICER_SECONDS = 5
local ACE_REFRESH_MS = 60000
local STATE_KEY = 'cortex-alpr:records'
local ACE_KEY = 'cortex-alpr:ace'

local officers = {}
local bridgeWarned = {}

function Records.bridge(name, ...)
    local fn = Bridge and Bridge[name]
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    if not bridgeWarned[name] then
        bridgeWarned[name] = true
        print(('^3[cortex-alpr] bridge/server.lua: Bridge.%s failed: %s^0'):format(name, tostring(a)))
    end
    return nil
end

function Records.say(src, text)
    print(('[cortex-alpr] %s'):format(text))
    if type(src) == 'number' and src > 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { Config.sender.label, text } })
    end
end

function Records.clean(value, max)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    value = value:sub(1, max)
    for _ = 1, 3 do
        if utf8.len(value) then break end
        value = value:sub(1, -2)
    end
    if not utf8.len(value) then value = value:gsub('[\128-\255]', '') end
    if value == '' then return nil end
    return value
end

function Records.provider()
    if Config.records == 'hotlist' then return 'hotlist' end
    if GetResourceState(Config.mdt) == 'started' then return 'mdt' end
    return Config.records == 'mdt' and 'offline' or 'hotlist'
end

local function publish()
    local provider = Records.provider()
    if GlobalState[STATE_KEY] ~= provider then GlobalState[STATE_KEY] = provider end
end

Records.publish = publish

function Records.officer(src)
    local provider = Records.provider()
    if provider == 'mdt' then
        local ok, officer = pcall(function() return exports[Config.mdt]:AlprIsOfficer(src) end)
        return ok and officer == true
    end
    if provider ~= 'hotlist' then return false end
    local now = os.time()
    local known = officers[src]
    if known and now - known.at < OFFICER_SECONDS then return known.value end
    local value = Records.bridge('officer', src) == true
    officers[src] = { at = now, value = value }
    return value
end

function Records.officers()
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and Records.officer(src) then out[#out + 1] = src end
    end
    return out
end

function Records.unit(src)
    if Records.provider() == 'mdt' then
        local ok, unit = pcall(function() return exports[Config.mdt]:AlprUnit(src) end)
        if ok and type(unit) == 'table' then
            local label = unit.callsign or unit.name
            if label then return label end
        end
    else
        local label = Records.clean(Records.bridge('unit', src), 32)
        if label then return label end
    end
    return GetPlayerName(src)
end

function Records.grade(src)
    return tonumber(Records.bridge('grade', src)) or 0
end

function Records.identity(src)
    local id = Records.bridge('identity', src)
    return type(id) == 'string' and id ~= '' and id or tostring(src)
end

function Records.forget(src)
    officers[src] = nil
end

local function syncAce(src)
    local ace = Config.jobs.ace
    local allowed = ace ~= false and Records.provider() == 'hotlist' and IsPlayerAceAllowed(src, ace) == true
    local state = Player(src).state
    if (state[ACE_KEY] == true) ~= allowed then state:set(ACE_KEY, allowed, true) end
end

AddEventHandler('playerJoining', function()
    local src = source
    pcall(syncAce, src)
    SetTimeout(5000, function()
        if GetPlayerName(src) then pcall(syncAce, src) end
    end)
end)

for _, name in ipairs({ 'onResourceStart', 'onResourceStop' }) do
    AddEventHandler(name, function(resource)
        if resource ~= Config.mdt then return end
        SetTimeout(2000, Records.refresh)
    end)
end

function Records.refresh()
    publish()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src then pcall(syncAce, src) end
    end
end

CreateThread(function()
    while true do
        Records.refresh()
        Wait(ACE_REFRESH_MS)
    end
end)
