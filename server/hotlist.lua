Hot = {}

local KEY = 'cortex-alpr:hotlist'
local SEQ_KEY = 'cortex-alpr:hotlist:seq'
local PRIORITY = { low = 1, normal = 2, high = 3, critical = 4 }
local KINDS = { bolo = true, stolen = true }
local MAX_SIGHTINGS = 12
local SIGHTING_WRITE_SECONDS = 30
local RATE_SECONDS = 5
local SAVE_MS = 2000
local LOOKUP_SECONDS = 60
local LOOKUP_KEEP = 500
local SEEN_KEEP = 200
local PAGE_ROWS = 40
local DETAIL_SIGHTINGS = 5
local MIN_EXPIRE_SECONDS = 60
local WEBHOOK_MS = 2500
local WEBHOOK_LINES = 20
local WEBHOOK_CHARS = 1800
local WEBHOOK_QUEUE = 400
local LOOKUP_WAIT_MS = 2000
local CHAT_ROWS = 20

local entries = {}
local count = 0
local seq = 0
local saving = false
local seenAt = {}
local ratedAt = {}
local lookups = {}
local lookupCount = 0
local outbox = {}
local posting = false

local function now()
    return os.time()
end

local function expired(entry, at)
    return type(entry.expires) == 'number' and entry.expires > 0 and at >= entry.expires
end

local function flush()
    saving = false
    local list = {}
    for _, entry in pairs(entries) do list[#list + 1] = entry end
    SetResourceKvp(KEY, json.encode(list))
    SetResourceKvpInt(SEQ_KEY, seq)
end

local function save()
    if saving then return end
    saving = true
    SetTimeout(SAVE_MS, function()
        if saving then flush() end
    end)
end

local function coordsOf(value)
    if type(value) ~= 'table' then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function sightingOf(value)
    if type(value) ~= 'table' or type(value.at) ~= 'number' then return nil end
    return {
        at = math.floor(value.at),
        street = Records.clean(value.street, 96),
        coords = coordsOf(value.coords),
        unit = Records.clean(value.unit, 48),
        cam = (value.cam == 'front' or value.cam == 'rear' or value.cam == 'air') and value.cam or nil,
    }
end

local function restore(raw)
    if type(raw) ~= 'table' then return nil end
    local plate = Geo.plate(raw.plate)
    if not plate or not plate:match('^%w+$') or type(raw.number) ~= 'string' then return nil end
    local entry = {
        plate = plate,
        number = raw.number:sub(1, 16),
        kind = KINDS[raw.kind] and raw.kind or 'bolo',
        title = Records.clean(raw.title, 80),
        priority = PRIORITY[raw.priority] and raw.priority or 'normal',
        model = Records.clean(raw.model, 48),
        colour = Records.clean(raw.colour, 32),
        by = Records.clean(raw.by, 48),
        byId = Records.clean(raw.byId, 80),
        origin = Records.clean(raw.origin, 64),
        at = type(raw.at) == 'number' and math.floor(raw.at) or now(),
        expires = type(raw.expires) == 'number' and math.floor(raw.expires) or 0,
        lastSeen = sightingOf(raw.lastSeen),
        sightings = {},
    }
    for _, s in ipairs(type(raw.sightings) == 'table' and raw.sightings or {}) do
        local sighting = sightingOf(s)
        if sighting and #entry.sightings < MAX_SIGHTINGS then entry.sightings[#entry.sightings + 1] = sighting end
    end
    return entry
end

local function readSaved()
    seq = GetResourceKvpInt(SEQ_KEY) or 0
    local raw = GetResourceKvpString(KEY)
    if not raw or raw == '' then return end
    local ok, list = pcall(json.decode, raw)
    if not ok or type(list) ~= 'table' then
        print('^3[cortex-alpr] the saved hot list could not be read and starts empty^0')
        return
    end
    local at = now()
    for _, item in ipairs(list) do
        local entry = restore(item)
        if entry and not expired(entry, at) and not entries[entry.plate] and count < Config.hotlist.max then
            entries[entry.plate] = entry
            count = count + 1
        end
    end
end

local function webhook()
    local hook = GetConvar('cortex_alpr_webhook', '')
    return hook:sub(1, 8) == 'https://' and hook or nil
end

local function post()
    posting = false
    local hook = webhook()
    if not hook then
        outbox = {}
        return
    end
    local lines, size = {}, 0
    while outbox[1] and #lines < WEBHOOK_LINES and size + #outbox[1] < WEBHOOK_CHARS do
        size = size + #outbox[1] + 1
        lines[#lines + 1] = table.remove(outbox, 1)
    end
    if #lines == 0 then
        outbox = {}
        return
    end
    PerformHttpRequest(hook, function() end, 'POST', json.encode({
        username = 'Cortex ALPR',
        content = table.concat(lines, '\n'),
        allowed_mentions = { parse = {} },
        flags = 4,
    }), { ['Content-Type'] = 'application/json' })
    if outbox[1] then
        posting = true
        SetTimeout(WEBHOOK_MS, post)
    end
end

local function audit(action, actor, entry, note)
    local line = ('hot list %s: %s %s%s by %s%s'):format(
        action, entry.plate, entry.number, entry.title and (' "%s"'):format(entry.title) or '',
        Records.clean(actor, 48) or 'console', note and (' (%s)'):format(note) or '')
    print(('[cortex-alpr] %s'):format(line))
    if not webhook() or #outbox >= WEBHOOK_QUEUE then return end
    outbox[#outbox + 1] = (line:gsub('@', '@ '):gsub('[%[%]%*_~`|]', '\\%0'):sub(1, 400))
    if posting then return end
    posting = true
    SetTimeout(WEBHOOK_MS, post)
end

local function view(entry)
    return {
        plate = entry.plate, number = entry.number, kind = entry.kind, title = entry.title, priority = entry.priority,
        model = entry.model, colour = entry.colour, by = entry.by, origin = entry.origin, at = entry.at, expires = entry.expires,
        lastSeen = entry.lastSeen, sightings = entry.sightings,
    }
end

local function summary(entry)
    return {
        plate = entry.plate, number = entry.number, kind = entry.kind, title = entry.title, priority = entry.priority, at = entry.at,
        lastSeen = entry.lastSeen and { at = entry.lastSeen.at, street = entry.lastSeen.street } or nil,
    }
end

local function newestFirst(a, b)
    if a.at ~= b.at then return a.at > b.at end
    return a.plate < b.plate
end

local function remove(plate)
    if not entries[plate] then return nil end
    local entry = entries[plate]
    entries[plate] = nil
    count = count - 1
    save()
    for _, src in ipairs(Records.officers()) do
        TriggerClientEvent('cortex-alpr:client:cleared', src, plate)
    end
    return entry
end

local function prune()
    local at = now()
    for plate, entry in pairs(entries) do
        if expired(entry, at) then
            remove(plate)
            audit('expired', 'the timer', entry)
            TriggerEvent('cortex-alpr:hotlistChanged', 'expired', view(entry))
        end
    end
end

function Hot.get(plate)
    local entry = entries[plate]
    if not entry then return nil end
    if expired(entry, now()) then
        remove(plate)
        audit('expired', 'the timer', entry)
        TriggerEvent('cortex-alpr:hotlistChanged', 'expired', view(entry))
        return nil
    end
    return entry
end

function Hot.has(plate)
    return Hot.get(plate) ~= nil
end

function Hot.forget(plate)
    for _, memory in pairs(seenAt) do
        if memory.plates[plate] then
            memory.plates[plate] = nil
            memory.count = memory.count - 1
        end
    end
    if lookups[plate] then
        lookups[plate] = nil
        lookupCount = lookupCount - 1
    end
end

function Hot.add(data, actor)
    data = type(data) == 'table' and data or {}
    local plate = Geo.plate(data.plate)
    if not plate or not plate:match('^%w+$') then return nil, 'bad_plate' end
    local existing = Hot.get(plate)
    if existing then return { number = existing.number, title = existing.title, priority = existing.priority, existing = true } end
    if count >= Config.hotlist.max then prune() end
    if count >= Config.hotlist.max then return nil, 'full' end

    actor = type(actor) == 'table' and actor or {}
    local kind = KINDS[data.kind] and data.kind or 'bolo'
    local hours = tonumber(data.hours) or Config.hotlist.expireHours
    if hours ~= hours or hours < 0 then hours = Config.hotlist.expireHours end
    hours = math.min(hours, 8760)
    local at = now()
    seq = seq % 999999 + 1
    local entry = {
        plate = plate,
        number = ('%s-%04d'):format(Config.hotlist.prefix, seq),
        kind = kind,
        title = Records.clean(data.title, 80) or (kind == 'bolo' and L('hot_default_title', plate) or nil),
        priority = PRIORITY[data.priority] and data.priority or (kind == 'stolen' and 'high' or 'normal'),
        model = Records.clean(data.model, 48),
        colour = Records.clean(data.colour, 32),
        by = Records.clean(actor.name, 48),
        byId = Records.clean(actor.id, 80),
        origin = Records.clean(actor.origin, 64),
        at = at,
        expires = hours > 0 and at + math.max(MIN_EXPIRE_SECONDS, math.floor(hours * 3600)) or 0,
        lastSeen = sightingOf(type(data.lastSeen) == 'table' and {
            at = at, street = data.lastSeen.street, coords = data.lastSeen.coords, unit = data.lastSeen.unit, cam = data.lastSeen.cam,
        } or nil),
        sightings = {},
    }
    if entry.lastSeen and not entry.lastSeen.street and not entry.lastSeen.coords then entry.lastSeen = nil end
    entries[plate] = entry
    count = count + 1
    save()
    Hot.forget(plate)
    audit('added', entry.by or entry.origin, entry)
    TriggerEvent('cortex-alpr:hotlistChanged', 'added', view(entry))
    return { number = entry.number, title = entry.title, priority = entry.priority }
end

function Hot.drop(plate, actor)
    plate = Geo.plate(plate)
    local entry = plate and remove(plate) or nil
    if not entry then return false end
    Hot.forget(plate)
    audit('cleared', actor, entry)
    TriggerEvent('cortex-alpr:hotlistChanged', 'cleared', view(entry))
    return true
end

function Hot.list(identity, canClear)
    prune()
    local out = {}
    for _, entry in pairs(entries) do
        local item = view(entry)
        if identity then item.clearable = canClear == true or (entry.byId ~= nil and entry.byId == identity) end
        out[#out + 1] = item
    end
    table.sort(out, newestFirst)
    return out
end

function Hot.page(page)
    prune()
    local all = {}
    for _, entry in pairs(entries) do all[#all + 1] = entry end
    table.sort(all, newestFirst)
    local pages = math.max(1, math.ceil(#all / PAGE_ROWS))
    page = math.min(math.max(math.tointeger(tonumber(page)) or 1, 1), pages)
    local rows = {}
    for i = (page - 1) * PAGE_ROWS + 1, math.min(page * PAGE_ROWS, #all) do rows[#rows + 1] = summary(all[i]) end
    return rows, page, pages, #all
end

function Hot.detail(plate, identity, canClear)
    plate = Geo.plate(plate)
    local entry = plate and Hot.get(plate) or nil
    if not entry then return nil end
    local item = view(entry)
    item.sightings = {}
    for i = 1, math.min(#entry.sightings, DETAIL_SIGHTINGS) do item.sightings[i] = entry.sightings[i] end
    item.clearable = canClear == true or (entry.byId ~= nil and entry.byId == identity)
    return item
end

local function admit(src, plate, always)
    local cooldown = Config.hotlist.cooldownSeconds
    local at = now()
    local memory = seenAt[src]
    if not memory then
        memory = { plates = {}, count = 0 }
        seenAt[src] = memory
    end
    local last = memory.plates[plate]
    if last and at - last < cooldown and not always then return false end
    if not last then
        memory.count = memory.count + 1
        if memory.count > SEEN_KEEP then
            local kept, n = {}, 0
            for key, seen in pairs(memory.plates) do
                if at - seen < cooldown then kept[key] = seen; n = n + 1 end
            end
            memory.plates, memory.count = kept, n + 1
        end
    end
    memory.plates[plate] = at
    return true
end

function Hot.mark(src, plate)
    admit(src, plate, true)
end

local function lookup(plate)
    local at = now()
    local known = lookups[plate]
    if known and at - known.at < LOOKUP_SECONDS then
        local deadline = GetGameTimer() + LOOKUP_WAIT_MS
        while known.pending and GetGameTimer() < deadline do Wait(50) end
        return known.value or nil
    end
    if not known then
        lookupCount = lookupCount + 1
        if lookupCount > LOOKUP_KEEP then
            local kept, n = {}, 0
            for key, item in pairs(lookups) do
                if at - item.at < LOOKUP_SECONDS then kept[key] = item; n = n + 1 end
            end
            lookups, lookupCount = kept, n + 1
        end
    end
    local slot = { at = at, value = false, pending = true }
    lookups[plate] = slot
    local found = Records.bridge('lookup', plate)
    local value = false
    if type(found) == 'table' then
        local lines = {}
        for _, line in ipairs(type(found.lines) == 'table' and found.lines or {}) do
            local text = Records.clean(line, 120)
            if text and #lines < 4 then lines[#lines + 1] = text end
        end
        if found.stolen == true or #lines > 0 then
            value = {
                stolen = found.stolen == true,
                lines = lines,
                lock = found.lock == true,
                severe = found.kind == 'error',
                label = Records.clean(found.label, 48),
                colour = Records.clean(found.colour, 32),
            }
        end
    end
    slot.value = value
    slot.pending = nil
    return value or nil
end

local function noteSighting(entry, where)
    local at = now()
    if entry.lastSeen and at - entry.lastSeen.at < SIGHTING_WRITE_SECONDS then return end
    local sighting = sightingOf({ at = at, street = where.street, coords = where.coords, unit = where.unit, cam = where.cam })
    entry.lastSeen = sighting
    table.insert(entry.sightings, 1, sighting)
    while #entry.sightings > MAX_SIGHTINGS do table.remove(entry.sightings) end
    save()
end

function Hot.read(src, plate, where)
    local extra = lookup(plate)
    if not GetPlayerName(src) then return { plate = plate, clean = true } end
    local entry = Hot.get(plate)
    if not entry and not extra then return { plate = plate, clean = true } end
    if not admit(src, plate) then return { plate = plate, cooldown = true } end

    local lines, bolos = {}, {}
    local stolen = (entry ~= nil and entry.kind == 'stolen') or (extra ~= nil and extra.stolen)
    if entry and entry.kind == 'bolo' then
        bolos[1] = { number = entry.number, title = entry.title, priority = entry.priority }
        lines[#lines + 1] = L('hit_line_bolo', entry.number, ((entry.title or L('hot_default_title', plate)):gsub('[%.%s]+$', '')))
    end
    if stolen then
        local note = entry and entry.kind == 'stolen' and entry.title or nil
        lines[#lines + 1] = note and L('hit_line_stolen_note', (note:gsub('[%.%s]+$', ''))) or L('hit_line_stolen')
    end
    for _, line in ipairs(extra and extra.lines or {}) do lines[#lines + 1] = line end

    local label = entry and entry.model or extra and extra.label or nil
    local alarm = #bolos > 0 or stolen
    local priority = entry and PRIORITY[entry.priority] or 0
    if stolen then priority = math.max(priority, 3) end

    local recipients = {}
    if alarm then
        local numbers = {}
        for i, bolo in ipairs(bolos) do numbers[i] = bolo.number end
        for _, other in ipairs(Records.officers()) do
            if other ~= src then recipients[#recipients + 1] = { source = other, bolos = numbers, stolen = stolen } end
        end
        if entry then noteSighting(entry, where) end
    end

    return {
        plate = plate,
        shown = { bolos = bolos, stolen = stolen },
        label = label,
        model = entry and entry.model or nil,
        colour = entry and entry.colour or extra and extra.colour or nil,
        reader = {
            kind = (alarm or (extra ~= nil and extra.severe)) and 'error' or 'warning',
            text = ('%s. %s'):format(label and ('%s, %s'):format(plate, label) or plate, table.concat(lines, ' ')),
            lock = alarm or (extra ~= nil and extra.lock),
            bolo = alarm,
        },
        stolen = stolen,
        bolos = bolos,
        priority = priority,
        recipients = recipients,
    }
end

local function allowed(src, grade)
    if not Records.officer(src) then return false, 'not_on_duty' end
    if grade > 0 and Records.grade(src) < grade and not IsPlayerAceAllowed(src, 'cortexalpr.admin') then
        return false, 'no_permission'
    end
    return true
end

function Hot.file(src, data)
    local ok, why = allowed(src, Config.hotlist.fileGrade)
    if not ok then return nil, why end
    data = type(data) == 'table' and data or {}
    local plate = Geo.plate(data.plate)
    if not plate or not plate:match('^%w+$') then return nil, 'bad_plate' end
    local existing = Hot.get(plate)
    if existing then return { number = existing.number, existing = true } end
    local at = now()
    if ratedAt[src] and at - ratedAt[src] < RATE_SECONDS then return nil, 'too_fast' end
    ratedAt[src] = at
    return Hot.add({
        plate = plate,
        kind = data.kind,
        title = data.title,
        priority = data.priority,
        model = type(data.vehicle) == 'table' and data.vehicle.model or data.model,
        colour = type(data.vehicle) == 'table' and data.vehicle.colour or data.colour,
        lastSeen = data.lastSeen,
    }, { name = Records.unit(src), id = Records.identity(src) })
end

function Hot.clear(src, plate)
    if not Records.officer(src) then return false, 'not_on_duty' end
    plate = Geo.plate(plate)
    local entry = plate and Hot.get(plate) or nil
    if not entry then return false, 'not_listed' end
    local mine = entry.byId ~= nil and entry.byId == Records.identity(src)
    if not mine then
        local ok, why = allowed(src, Config.hotlist.clearGrade)
        if not ok then return false, why end
    end
    return Hot.drop(plate, Records.unit(src))
end

function Hot.dropPlayer(src)
    seenAt[src] = nil
    ratedAt[src] = nil
end

lib.callback.register('cortex-alpr:hot:list', function(src, page)
    if Records.provider() ~= 'hotlist' then return { ok = false, error = 'mdt_active' } end
    if not Records.officer(src) then return { ok = false, error = 'not_on_duty' } end
    local rows, at, pages, total = Hot.page(page)
    return {
        ok = true,
        now = now(),
        canFile = allowed(src, Config.hotlist.fileGrade) == true,
        entries = rows,
        page = at,
        pages = pages,
        total = total,
    }
end)

lib.callback.register('cortex-alpr:hot:entry', function(src, plate)
    if Records.provider() ~= 'hotlist' then return { ok = false, error = 'mdt_active' } end
    if not Records.officer(src) then return { ok = false, error = 'not_on_duty' } end
    local entry = Hot.detail(plate, Records.identity(src), allowed(src, Config.hotlist.clearGrade) == true)
    if not entry then return { ok = false, error = 'not_listed' } end
    return { ok = true, now = now(), entry = entry }
end)

lib.callback.register('cortex-alpr:hot:add', function(src, fields)
    if Records.provider() ~= 'hotlist' then return { ok = false, error = 'mdt_active' } end
    fields = type(fields) == 'table' and fields or {}
    local result, err = Hot.file(src, {
        plate = fields.plate, title = fields.title, priority = fields.priority, model = fields.model,
        kind = fields.stolen == true and 'stolen' or 'bolo',
    })
    if not result then return { ok = false, error = err or 'refused' } end
    return { ok = true, number = result.number, existing = result.existing == true }
end)

lib.callback.register('cortex-alpr:hot:clear', function(src, plate)
    if Records.provider() ~= 'hotlist' then return { ok = false, error = 'mdt_active' } end
    local ok, err = Hot.clear(src, plate)
    return { ok = ok == true, error = err }
end)

exports('AddHotPlate', function(plate, data)
    data = type(data) == 'table' and data or {}
    local result, err = Hot.add({
        plate = plate, kind = data.kind, title = data.title, priority = data.priority, model = data.model,
        colour = data.colour, hours = data.hours, lastSeen = data.lastSeen,
    }, { origin = GetInvokingResource() or 'console' })
    if not result then return nil, err end
    return result.number, result.existing == true
end)

exports('RemoveHotPlate', function(plate)
    return Hot.drop(plate, GetInvokingResource() or 'console')
end)

exports('GetHotPlates', function()
    return Hot.list()
end)

exports('IsHotPlate', function(plate)
    plate = Geo.plate(plate)
    return plate ~= nil and Hot.has(plate)
end)

RegisterCommand('alpr_hot', function(src, args)
    local action = args[1]
    if action == 'clear' then
        if args[2] == 'all' then
            local cleared = 0
            for _, entry in ipairs(Hot.list()) do
                if Hot.drop(entry.plate, src == 0 and 'console' or GetPlayerName(src)) then cleared = cleared + 1 end
            end
            Records.say(src, ('cleared %d plates from the hot list'):format(cleared))
        elseif args[2] then
            local done = Hot.drop(args[2], src == 0 and 'console' or GetPlayerName(src))
            Records.say(src, ('%s'):format(done and 'cleared' or 'that plate is not on the hot list'))
        else
            Records.say(src, 'usage: alpr_hot clear <plate|all>')
        end
        return
    end
    if action == 'add' and args[2] then
        local stolen = args[3] == 'stolen'
        local result, err = Hot.add({ plate = args[2], kind = stolen and 'stolen' or 'bolo', title = table.concat(args, ' ', stolen and 4 or 3) },
            { name = src ~= 0 and GetPlayerName(src) or nil, origin = 'console' })
        Records.say(src, ('%s'):format(result and ('%s as %s'):format(result.existing and 'already listed' or 'added', result.number) or ('not added: %s'):format(tostring(err))))
        return
    end
    local list = Hot.list()
    Records.say(src, ('hot list (%s): %d of %d plates'):format(Records.provider(), #list, Config.hotlist.max))
    local at = now()
    for i, entry in ipairs(list) do
        Records.say(i <= CHAT_ROWS and src or 0, ('%s %s %s %s | by %s | %s | %s'):format(
            entry.plate, entry.number, entry.kind == 'stolen' and 'stolen' or entry.priority, entry.title or '',
            entry.by or entry.origin or '?',
            entry.expires > 0 and ('expires in %d h'):format(math.max(0, math.ceil((entry.expires - at) / 3600))) or 'never expires',
            entry.lastSeen and ('last seen %d min ago, %s'):format(math.floor((at - entry.lastSeen.at) / 60), entry.lastSeen.street or 'unknown street') or 'not seen yet'))
    end
    if src > 0 and #list > CHAT_ROWS then
        TriggerClientEvent('chat:addMessage', src, { args = { Config.sender.label, ('and %d more in the server console'):format(#list - CHAT_ROWS) } })
    end
end, true)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and saving then flush() end
end)

CreateThread(function()
    while true do
        Wait(600000)
        prune()
    end
end)

readSaved()
