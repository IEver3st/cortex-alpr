Layout = { editing = false, onChange = nil }

local KEY = 'cortex-alpr:layout'
local MIN_SCALE, MAX_SCALE = 0.6, 1.8
local PAUSE_CONTROLS = { 199, 200, 202, 322 }
local saved = nil

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function finite(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value + 0.0
end

local function sanitize(data)
    if type(data) ~= 'table' then return nil end
    local x, y = finite(data.x), finite(data.y)
    local scale = clamp(finite(data.scale) or 1.0, MIN_SCALE, MAX_SCALE)
    if not x or not y then
        if scale == 1.0 then return nil end
        return { scale = scale }
    end
    return { x = clamp(x, 0.0, 1.0), y = clamp(y, 0.0, 1.0), scale = scale }
end

function Layout.load()
    local raw = GetResourceKvpString(KEY)
    if not raw or raw == '' then saved = nil; return end
    local ok, data = pcall(json.decode, raw)
    saved = ok and sanitize(data) or nil
end

function Layout.get()
    return saved
end

local function holdPauseMenu()
    CreateThread(function()
        local stop = GetGameTimer() + 500
        while GetGameTimer() < stop do
            for _, control in ipairs(PAUSE_CONTROLS) do DisableControlAction(0, control, true) end
            DisableFrontendThisFrame()
            Wait(0)
        end
    end)
end

function Layout.finish(data)
    if not Layout.editing then return end
    Layout.editing = false
    SetNuiFocus(false, false)
    if data ~= nil then
        saved = sanitize(data)
        if saved then SetResourceKvp(KEY, json.encode(saved)) else DeleteResourceKvp(KEY) end
    end
    Nui.send('layoutEdit', { active = false })
    holdPauseMenu()
    if Layout.onChange then Layout.onChange() end
end

function Layout.begin()
    if Layout.editing then return true end
    if not Nui.ready or IsPauseMenuActive() or IsNuiFocused() then return false, 'busy' end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped and GetEntitySpeed(vehicle) > 1.0 then return false, 'moving' end
    Layout.editing = true
    if Layout.onChange then Layout.onChange() end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    Nui.send('layoutEdit', { active = true })
    CreateThread(function()
        while Layout.editing do
            if IsPauseMenuActive() or IsEntityDead(PlayerPedId()) then Layout.finish(nil) end
            Wait(200)
        end
    end)
    return true
end

function Layout.stop()
    if not Layout.editing then return end
    Layout.editing = false
    SetNuiFocus(false, false)
end

RegisterNUICallback('layoutSave', function(body, cb)
    cb({ ok = true })
    Layout.finish(type(body) == 'table' and body or {})
end)

RegisterNUICallback('layoutCancel', function(_, cb)
    cb({ ok = true })
    Layout.finish(nil)
end)

Layout.load()
