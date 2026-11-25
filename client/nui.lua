Nui = { ready = false }

local onReady = {}

function Nui.send(action, data)
    if Nui.ready then SendNUIMessage({ action = action, data = data }) end
end

function Nui.whenReady(fn)
    onReady[#onReady + 1] = fn
    if Nui.ready then fn() end
end

RegisterNUICallback('ready', function(_, cb)
    Nui.ready = true
    cb({ ok = true })
    Nui.send('locale', LocaleTable('ui_'))
    for _, fn in ipairs(onReady) do pcall(fn) end
end)
