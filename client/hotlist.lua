HotList = {}

local MENU = 'cortex_alpr_hotlist'
local ENTRY_MENU = 'cortex_alpr_hot_entry'
local PRIORITIES = { 'low', 'normal', 'high', 'critical' }
local SIGHTING_ROWS = 5

local function notify(data)
    data.sender = Config.sender.id
    lib.notify(data)
end

function HotList.available()
    return GlobalState['cortex-alpr:records'] == 'hotlist'
end

local function ago(seconds)
    seconds = math.max(0, seconds)
    if seconds < 60 then return L('ago_now') end
    if seconds < 3600 then return L('ago_minutes', math.floor(seconds / 60)) end
    if seconds < 172800 then return L('ago_hours', math.floor(seconds / 3600)) end
    return L('ago_days', math.floor(seconds / 86400))
end

local function kindText(entry)
    if entry.kind == 'stolen' then return L('hot_kind_stolen', entry.number) end
    return L('hot_kind_bolo', entry.number, L('priority_' .. tostring(entry.priority)))
end

local function rowText(entry, now)
    local seen = entry.lastSeen
    if not seen then return L('hot_row_unseen', kindText(entry)) end
    return L('hot_row_seen', kindText(entry), seen.street or L('unknown_street'), ago(now - seen.at))
end

local function failed(title, result)
    local key = type(result) == 'table' and result.error or 'timeout'
    notify({ type = 'error', title = title, description = ErrorText(key) })
end

local function mark(sighting)
    local c = type(sighting) == 'table' and sighting.coords
    if type(c) ~= 'table' or not tonumber(c.x) or not tonumber(c.y) then return end
    SetNewWaypoint(tonumber(c.x) + 0.0, tonumber(c.y) + 0.0)
    notify({ type = 'success', title = L('hot_marked_title'), description = L('hot_marked_body', sighting.street or L('unknown_street')) })
end

local function addPlate()
    local options = {}
    for i, p in ipairs(PRIORITIES) do options[i] = { value = p, label = L('priority_' .. p) } end
    local values = lib.contextMenu({
        title = L('hot_add_title'),
        labels = { confirm = L('hot_add_confirm'), cancel = L('bolo_cancel') },
        values = { priority = 'normal', stolen = false },
        fields = {
            { name = 'plate', type = 'input', label = L('hot_field_plate'), required = true },
            { name = 'title', type = 'input', label = L('hot_field_reason'), required = true },
            { name = 'model', type = 'input', label = L('hot_field_vehicle') },
            { name = 'priority', type = 'select', label = L('bolo_field_priority'), required = true, options = options },
            { name = 'stolen', type = 'checkbox', label = L('hot_field_stolen'), description = L('hot_field_stolen_desc') },
        },
    })
    if not values then return false end
    local result = lib.callback.await('cortex-alpr:hot:add', false, values)
    if type(result) ~= 'table' or not result.ok then
        failed(L('bolo_failed_title'), result)
        return false
    end
    local plate = Geo.plate(values.plate) or tostring(values.plate)
    notify({
        type = 'success',
        title = result.existing and L('bolo_existing_title', result.number or '') or L('bolo_filed_title', result.number or ''),
        description = L('bolo_filed_body', plate),
    })
    Radar.sentAt[plate] = nil
    return true
end

local function clearPlate(entry)
    local answer = lib.alertDialog({
        header = L('hot_clear_title', entry.plate),
        content = L('hot_clear_body', entry.number),
        labels = { confirm = L('hot_clear_confirm'), cancel = L('bolo_cancel') },
    })
    if answer ~= 'confirm' then return false end
    local result = lib.callback.await('cortex-alpr:hot:clear', false, entry.plate)
    if type(result) ~= 'table' or not result.ok then
        failed(L('hot_clear_failed_title'), result)
        return false
    end
    notify({ type = 'success', title = L('hot_cleared_title', entry.plate), description = L('hot_cleared_body') })
    return true
end

local function show(menu, onSelect)
    if lib.registerMenu(menu, onSelect) == false then
        return notify({ type = 'error', title = L('hot_title'), description = ErrorText(nil) })
    end
    lib.showMenu(menu.id)
end

local function openEntry(entry, now, page)
    local data = { now = now }
    local options = {
        {
            label = entry.title or L('hot_default_title', entry.plate),
            description = L(entry.expires > 0 and 'hot_filed_expires' or 'hot_filed', entry.by or entry.origin or L('hot_unknown_filer'),
                ago(data.now - entry.at), math.max(1, math.ceil((entry.expires - data.now) / 3600))),
            icon = 'flag',
            disabled = true,
        },
    }
    local sightings = type(entry.sightings) == 'table' and entry.sightings or {}
    if #sightings == 0 and entry.lastSeen then sightings = { entry.lastSeen } end
    for i = 1, math.min(#sightings, SIGHTING_ROWS) do
        local s = sightings[i]
        options[#options + 1] = {
            label = L('hot_sighting', s.street or L('unknown_street'), ago(data.now - s.at)),
            description = L('hot_sighting_by', s.unit or '?', L('cam_' .. tostring(s.cam or 'front'))),
            icon = 'pin',
            disabled = type(s.coords) ~= 'table',
            args = { sighting = i },
        }
    end
    if entry.clearable then
        options[#options + 1] = { label = L('hot_clear'), description = L('hot_clear_desc'), icon = 'trash', args = { clear = true } }
    end
    show({
        id = ENTRY_MENU,
        title = entry.model and ('%s, %s'):format(entry.plate, entry.model) or entry.plate,
        options = options,
        onClose = function(reason)
            if reason == nil or reason == 'Escape' or reason == 'Backspace' then CreateThread(function() HotList.open(page) end) end
        end,
    }, function(_, _, args)
        CreateThread(function()
            if args.sighting then
                mark(sightings[args.sighting])
            elseif args.clear then
                clearPlate(entry)
                HotList.open(page)
            end
        end)
    end)
end

function HotList.open(page)
    local provider = GlobalState['cortex-alpr:records']
    if provider ~= 'hotlist' then
        return notify({ type = 'warning', title = L('hot_title'), description = L(provider == 'offline' and 'error_mdt_offline' or 'error_mdt_active') })
    end
    if not Install.officer() then
        return notify({ type = 'warning', title = L('hot_title'), description = L('error_not_on_duty') })
    end
    local data = lib.callback.await('cortex-alpr:hot:list', false, tonumber(page) or 1)
    if type(data) ~= 'table' or not data.ok then return failed(L('hot_title'), data) end
    local entries = type(data.entries) == 'table' and data.entries or {}
    local at, pages = tonumber(data.page) or 1, tonumber(data.pages) or 1
    local options, rows = {}, {}
    if data.canFile then
        options[#options + 1] = { label = L('hot_add'), description = L('hot_add_desc'), icon = 'flag', args = { add = true } }
    end
    for _, entry in ipairs(entries) do
        options[#options + 1] = {
            label = entry.title and ('%s  %s'):format(entry.plate, entry.title) or entry.plate,
            description = rowText(entry, data.now),
            icon = 'car',
            args = { row = #rows + 1 },
        }
        rows[#rows + 1] = entry
    end
    if #entries == 0 then
        options[#options + 1] = { label = L('hot_empty'), description = L('hot_empty_desc'), disabled = true }
    end
    if at < pages then
        options[#options + 1] = { label = L('hot_next'), description = L('hot_page', at + 1, pages), args = { page = at + 1 } }
    end
    if at > 1 then
        options[#options + 1] = { label = L('hot_prev'), description = L('hot_page', at - 1, pages), args = { page = at - 1 } }
    end
    show({ id = MENU, title = pages > 1 and L('hot_title_page', at, pages) or L('hot_title'), options = options }, function(_, _, args)
        CreateThread(function()
            if args.add then
                addPlate()
                HotList.open(1)
            elseif args.page then
                HotList.open(args.page)
            elseif args.row and rows[args.row] then
                local found = lib.callback.await('cortex-alpr:hot:entry', false, rows[args.row].plate)
                if type(found) ~= 'table' or not found.ok or type(found.entry) ~= 'table' then
                    failed(L('hot_title'), found)
                    return HotList.open(at)
                end
                openEntry(found.entry, tonumber(found.now) or data.now, at)
            end
        end)
    end)
end

RegisterCommand('cortexalpr_hotlist', function() CreateThread(function() HotList.open(1) end) end, false)
RegisterKeyMapping('cortexalpr_hotlist', L('key_hotlist'), 'keyboard', Config.keys.hotlist)

if Config.hotlist.command then
    RegisterCommand(Config.hotlist.command, function() CreateThread(function() HotList.open(1) end) end, false)
end
