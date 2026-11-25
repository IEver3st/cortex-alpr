local RESOURCE = GetCurrentResourceName()

local function warn(path, expected, value, fallback)
    print(('^3[%s] config.lua: %s expected %s, got %s; using %s^0'):format(
        RESOURCE, path, expected, type(value) == 'string' and ('"%s"'):format(value) or tostring(value), tostring(fallback)))
end

local function want(path, value, expected, fallback)
    if type(value) == expected then return value end
    if value ~= nil then warn(path, expected, value, fallback) end
    return fallback
end

local function number(path, value, fallback, min, max)
    if type(value) ~= 'number' or value ~= value then
        if value ~= nil then warn(path, 'number', value, fallback) end
        return fallback + 0.0
    end
    if (min and value < min) or (max and value > max) then
        warn(path, ('number %s..%s'):format(min or '-inf', max or 'inf'), value, fallback)
        return fallback + 0.0
    end
    return value + 0.0
end

local function oneOf(path, value, allowed, fallback)
    for _, v in ipairs(allowed) do if v == value then return value end end
    if value ~= nil then warn(path, table.concat(allowed, '|'), value, fallback) end
    return fallback
end

local function list(path, value, each)
    if type(value) ~= 'table' then
        if value ~= nil then warn(path, 'table', value, '{}') end
        return {}
    end
    local out = {}
    for i, v in ipairs(value) do
        local item = each(('%s[%d]'):format(path, i), v)
        if item ~= nil then out[#out + 1] = item end
    end
    return out
end

local function table_(path, value)
    if type(value) == 'table' then return value end
    if value ~= nil then warn(path, 'table', value, '{}') end
    return {}
end

local MODES = { 'any', 'emergency', 'models', 'extra', 'modkit' }
local LANES = { 'same', 'opp', 'both' }

Config.locale = want('Config.locale', Config.locale, 'string', 'en')
Config.units = oneOf('Config.units', Config.units, { 'mph', 'kmh' }, 'mph')
Config.records = oneOf('Config.records', Config.records, { 'auto', 'mdt', 'hotlist' }, 'auto')
Config.mdt = want('Config.mdt', Config.mdt, 'string', 'cortex-mdt')
Config.dispatch = want('Config.dispatch', Config.dispatch, 'string', 'cortex-dispatch')
Config.polcam = want('Config.polcam', Config.polcam, 'string', 'cortex-polcam')

Config.jobs = table_('Config.jobs', Config.jobs)
Config.jobs.types = list('Config.jobs.types', Config.jobs.types, function(p, v) return want(p, v, 'string', nil) end)
Config.jobs.names = list('Config.jobs.names', Config.jobs.names, function(p, v) return want(p, v, 'string', nil) end)
Config.jobs.requireDuty = want('Config.jobs.requireDuty', Config.jobs.requireDuty, 'boolean', true)
if Config.jobs.ace == '' then Config.jobs.ace = false end
if Config.jobs.ace ~= false then Config.jobs.ace = want('Config.jobs.ace', Config.jobs.ace, 'string', 'cortexalpr.officer') end

Config.hotlist = table_('Config.hotlist', Config.hotlist)
Config.hotlist.expireHours = number('Config.hotlist.expireHours', Config.hotlist.expireHours, 72, 0, 8760)
Config.hotlist.max = math.floor(number('Config.hotlist.max', Config.hotlist.max, 200, 1, 2000))
Config.hotlist.fileGrade = math.floor(number('Config.hotlist.fileGrade', Config.hotlist.fileGrade, 0, 0, 100))
Config.hotlist.clearGrade = math.floor(number('Config.hotlist.clearGrade', Config.hotlist.clearGrade, 0, 0, 100))
Config.hotlist.cooldownSeconds = math.floor(number('Config.hotlist.cooldownSeconds', Config.hotlist.cooldownSeconds, 60, 0, 3600))
Config.hotlist.prefix = want('Config.hotlist.prefix', Config.hotlist.prefix, 'string', 'B'):gsub('[^%w]', ''):sub(1, 4)
if Config.hotlist.prefix == '' then Config.hotlist.prefix = 'B' end
if Config.hotlist.command == '' then Config.hotlist.command = false end
if Config.hotlist.command ~= false then Config.hotlist.command = want('Config.hotlist.command', Config.hotlist.command, 'string', 'hotlist') end
Config.hotlist.wraithEvents = want('Config.hotlist.wraithEvents', Config.hotlist.wraithEvents, 'boolean', false)

Config.install = table_('Config.install', Config.install)
Config.install.modes = list('Config.install.modes', Config.install.modes, function(p, v) return oneOf(p, v, MODES, nil) end)
if #Config.install.modes == 0 then Config.install.modes = { 'emergency' } end
Config.install.models = list('Config.install.models', Config.install.models, function(p, v)
    if type(v) == 'string' then return joaat(v) end
    if type(v) == 'number' then return math.floor(v) end
    warn(p, 'string', v, 'skipped')
end)
Config.install.extra = math.floor(number('Config.install.extra', Config.install.extra, 5, 0, 20))
Config.install.modkit = table_('Config.install.modkit', Config.install.modkit)
Config.install.modkit.type = math.floor(number('Config.install.modkit.type', Config.install.modkit.type, 43, 0, 49))
if Config.install.modkit.indices ~= nil then
    Config.install.modkit.indices = list('Config.install.modkit.indices', Config.install.modkit.indices, function(p, v)
        return type(v) == 'number' and math.floor(v) or warn(p, 'number', v, 'skipped')
    end)
end
local perModel = {}
for model, spec in pairs(table_('Config.install.modkit.models', Config.install.modkit.models)) do
    local path = ('Config.install.modkit.models.%s'):format(tostring(model))
    if type(spec) == 'table' and type(spec.type) == 'number' then
        local hash = type(model) == 'string' and joaat(model) or tonumber(model)
        if hash then
            perModel[hash] = {
                type = math.floor(spec.type),
                indices = type(spec.indices) == 'table' and spec.indices or (type(spec.index) == 'number' and { math.floor(spec.index) }) or nil,
            }
        end
    else
        warn(path, '{ type = number, indices = { ... } }', spec, 'skipped')
    end
end
Config.install.modkit.models = perModel
Config.install.seats = list('Config.install.seats', Config.install.seats, function(p, v)
    return type(v) == 'number' and math.floor(v) or warn(p, 'number', v, 'skipped')
end)
if #Config.install.seats == 0 then Config.install.seats = { -1, 0 } end

Config.radar = table_('Config.radar', Config.radar)
Config.radar.range = number('Config.radar.range', Config.radar.range, 180.0, 20.0, 600.0)
Config.radar.halfAngle = number('Config.radar.halfAngle', Config.radar.halfAngle, 9.0, 1.0, 45.0)
Config.radar.nearWidth = number('Config.radar.nearWidth', Config.radar.nearWidth, 3.0, 0.5, 10.0)
Config.radar.sampleMs = math.floor(number('Config.radar.sampleMs', Config.radar.sampleMs, 100, 50, 1000))
Config.radar.poolMs = math.floor(number('Config.radar.poolMs', Config.radar.poolMs, 400, 100, 2000))
Config.radar.verticalAngle = number('Config.radar.verticalAngle', Config.radar.verticalAngle, 5.0, 1.0, 45.0)
Config.radar.nearHeight = number('Config.radar.nearHeight', Config.radar.nearHeight, 2.5, 0.5, 20.0)
Config.radar.lineOfSight = want('Config.radar.lineOfSight', Config.radar.lineOfSight, 'boolean', true)
Config.radar.cosine = want('Config.radar.cosine', Config.radar.cosine, 'boolean', true)
Config.radar.sizeBias = number('Config.radar.sizeBias', Config.radar.sizeBias, 1.0, 0.0, 3.0)
Config.radar.autoLock = want('Config.radar.autoLock', Config.radar.autoLock, 'boolean', true)
Config.radar.fastLimit = math.floor(number('Config.radar.fastLimit', Config.radar.fastLimit, 60, 0, 250))
Config.radar.frontMode = oneOf('Config.radar.frontMode', Config.radar.frontMode, LANES, 'same')
Config.radar.rearMode = oneOf('Config.radar.rearMode', Config.radar.rearMode, LANES, 'same')

Config.clock = table_('Config.clock', Config.clock)
Config.clock.enabled = want('Config.clock.enabled', Config.clock.enabled, 'boolean', true)
if Config.clock.limits ~= false then Config.clock.limits = want('Config.clock.limits', Config.clock.limits, 'string', 'cortex-radar') end
Config.clock.defaultLimit = math.floor(number('Config.clock.defaultLimit', Config.clock.defaultLimit, 0, 0, 250))
Config.clock.keepSeconds = math.floor(number('Config.clock.keepSeconds', Config.clock.keepSeconds, 3600, 60, 86400))

Config.tone = table_('Config.tone', Config.tone)
Config.tone.enabled = want('Config.tone.enabled', Config.tone.enabled, 'boolean', true)
Config.tone.default = want('Config.tone.default', Config.tone.default, 'boolean', false)
Config.tone.volume = math.floor(number('Config.tone.volume', Config.tone.volume, 40, 0, 100))

Config.display = table_('Config.display', Config.display)
Config.display.layout = oneOf('Config.display.layout', Config.display.layout, { 'slots', 'stack', 'lead', 'row' }, 'slots')
Config.display.plates = math.floor(number('Config.display.plates', Config.display.plates, 2, 1, 5))
Config.display.readSeconds = math.floor(number('Config.display.readSeconds', Config.display.readSeconds, 12, 4, 40))
Config.display.details = want('Config.display.details', Config.display.details, 'boolean', true)

Config.reader = table_('Config.reader', Config.reader)
Config.reader.range = number('Config.reader.range', Config.reader.range, 32.0, 5.0, 120.0)
Config.reader.halfAngle = number('Config.reader.halfAngle', Config.reader.halfAngle, 7.0, 1.0, 45.0)
Config.reader.plateAngle = number('Config.reader.plateAngle', Config.reader.plateAngle, 50.0, 5.0, 89.0)
Config.reader.resendSeconds = math.floor(number('Config.reader.resendSeconds', Config.reader.resendSeconds, 30, 5, 600))
Config.reader.history = math.floor(number('Config.reader.history', Config.reader.history, 8, 1, 30))

Config.air = table_('Config.air', Config.air)
Config.air.enabled = want('Config.air.enabled', Config.air.enabled, 'boolean', true)
Config.air.baseRange = number('Config.air.baseRange', Config.air.baseRange, 140.0, 20.0, 1000.0)
Config.air.maxRange = number('Config.air.maxRange', Config.air.maxRange, 650.0, Config.air.baseRange, 2000.0)
Config.air.referenceFov = number('Config.air.referenceFov', Config.air.referenceFov, 50.0, 5.0, 100.0)
Config.air.plateAngle = number('Config.air.plateAngle', Config.air.plateAngle, 60.0, 5.0, 89.0)
Config.air.maxElevation = number('Config.air.maxElevation', Config.air.maxElevation, 72.0, 10.0, 89.0)
Config.air.centreFraction = number('Config.air.centreFraction', Config.air.centreFraction, 0.6, 0.1, 1.0)
Config.air.sampleMs = math.floor(number('Config.air.sampleMs', Config.air.sampleMs, 250, 100, 2000))
Config.air.labelSeconds = math.floor(number('Config.air.labelSeconds', Config.air.labelSeconds, 20, 3, 120))

Config.network = table_('Config.network', Config.network)
Config.network.blipSeconds = math.floor(number('Config.network.blipSeconds', Config.network.blipSeconds, 90, 0, 900))
Config.network.blip = table_('Config.network.blip', Config.network.blip)
Config.network.blip.sprite = math.floor(number('Config.network.blip.sprite', Config.network.blip.sprite, 225, 1, 900))
Config.network.blip.colour = math.floor(number('Config.network.blip.colour', Config.network.blip.colour, 1, 0, 85))
Config.network.blip.scale = number('Config.network.blip.scale', Config.network.blip.scale, 0.9, 0.3, 2.0)
Config.network.dispatch = want('Config.network.dispatch', Config.network.dispatch, 'boolean', true)
Config.network.dispatchCode = want('Config.network.dispatchCode', Config.network.dispatchCode, 'string', 'ALPR')
Config.network.dispatchWindowSeconds = math.floor(number('Config.network.dispatchWindowSeconds', Config.network.dispatchWindowSeconds, 180, 0, 3600))
Config.network.sightingWindowSeconds = math.floor(number('Config.network.sightingWindowSeconds', Config.network.sightingWindowSeconds, 180, 0, 3600))

Config.keys = table_('Config.keys', Config.keys)
for _, key in ipairs({ 'toggle', 'lockFront', 'lockRear', 'bolo', 'cite', 'layout', 'hotlist' }) do
    Config.keys[key] = want('Config.keys.' .. key, Config.keys[key], 'string', '')
end

Config.sounds = table_('Config.sounds', Config.sounds)
for _, key in ipairs({ 'lock', 'unlock', 'hit', 'sighting', 'clock' }) do
    local s = Config.sounds[key]
    if s ~= false and (type(s) ~= 'table' or type(s.name) ~= 'string' or type(s.set) ~= 'string') then
        if s ~= nil then warn('Config.sounds.' .. key, '{ name, set } or false', s, 'false') end
        Config.sounds[key] = false
    end
end

Config.sender = table_('Config.sender', Config.sender)
Config.sender.id = want('Config.sender.id', Config.sender.id, 'string', 'cortex-alpr')
Config.sender.label = want('Config.sender.label', Config.sender.label, 'string', 'Plate reader')
Config.sender.color = want('Config.sender.color', Config.sender.color, 'string', '#9bbcd3')
Config.sender.icon = want('Config.sender.icon', Config.sender.icon, 'string', 'P')

Config.server = table_('Config.server', Config.server)
Config.server.readsPerSecond = math.floor(number('Config.server.readsPerSecond', Config.server.readsPerSecond, 12, 1, 60))
Config.server.readSlack = number('Config.server.readSlack', Config.server.readSlack, 25.0, 0.0, 200.0)
Config.server.angleSlack = number('Config.server.angleSlack', Config.server.angleSlack, 20.0, 0.0, 60.0)
Config.server.airOriginSlack = number('Config.server.airOriginSlack', Config.server.airOriginSlack, 25.0, 5.0, 200.0)
Config.server.ledgerSeconds = math.floor(number('Config.server.ledgerSeconds', Config.server.ledgerSeconds, 600, 30, 7200))
Config.server.clocksPerMinute = math.floor(number('Config.server.clocksPerMinute', Config.server.clocksPerMinute, 12, 1, 120))
Config.server.speedSlack = number('Config.server.speedSlack', Config.server.speedSlack, 4.0, 0.5, 30.0)
