local strings = {}

local function load()
    local name = GetCurrentResourceName()
    local raw = LoadResourceFile(name, ('locales/%s.json'):format(Config.locale or 'en'))
        or LoadResourceFile(name, 'locales/en.json') or '{}'
    local ok, decoded = pcall(json.decode, raw)
    strings = ok and type(decoded) == 'table' and decoded or {}
end

load()

function L(key, ...)
    local s = strings[key]
    if type(s) ~= 'string' then return key end
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        return ok and out or s
    end
    return s
end

function ErrorText(key)
    local name = 'error_' .. tostring(key)
    return type(strings[name]) == 'string' and strings[name] or L('error_nil')
end

function LocaleTable(prefix)
    local out = {}
    for key, value in pairs(strings) do
        if not prefix or key:sub(1, #prefix) == prefix then out[key] = value end
    end
    return out
end
