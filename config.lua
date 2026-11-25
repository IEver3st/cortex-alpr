Config = {}

Config.locale = 'en'

Config.units = 'mph'

Config.records = 'auto'

Config.mdt = 'cortex-mdt'
Config.dispatch = 'cortex-dispatch'
Config.polcam = 'cortex-polcam'

Config.jobs = {
    types = { 'leo' },
    names = { 'police' },
    requireDuty = true,
    ace = 'cortexalpr.officer',
}

Config.hotlist = {
    expireHours = 72,
    max = 200,
    fileGrade = 0,
    clearGrade = 0,
    cooldownSeconds = 60,
    prefix = 'B',
    command = 'hotlist',
    wraithEvents = false,
}

Config.install = {
    modes = { 'emergency' },
    models = { 'police', 'police2', 'police3', 'police4', 'policeb', 'policet', 'sheriff', 'sheriff2', 'fbi', 'fbi2', 'pranger' },
    extra = 5,
    modkit = {
        type = 43,
        indices = nil,
        models = {},
    },
    seats = { -1, 0 },
}

Config.radar = {
    range = 180.0,
    halfAngle = 9.0,
    nearWidth = 3.0,
    verticalAngle = 5.0,
    nearHeight = 2.5,
    lineOfSight = true,
    cosine = true,
    sizeBias = 1.0,
    sampleMs = 100,
    poolMs = 400,
    fastLimit = 60,
    autoLock = true,
    frontMode = 'same',
    rearMode = 'same',
}

Config.clock = {
    enabled = true,
    limits = 'cortex-radar',
    defaultLimit = 0,
    keepSeconds = 3600,
}

Config.tone = {
    enabled = true,
    default = false,
    volume = 40,
}

Config.display = {
    layout = 'slots',
    plates = 2,
    readSeconds = 12,
    details = true,
}

Config.reader = {
    range = 32.0,
    halfAngle = 7.0,
    plateAngle = 50.0,
    resendSeconds = 30,
    history = 8,
}

Config.air = {
    enabled = true,
    baseRange = 140.0,
    maxRange = 650.0,
    referenceFov = 50.0,
    plateAngle = 60.0,
    maxElevation = 72.0,
    centreFraction = 0.6,
    sampleMs = 250,
    labelSeconds = 20,
}

Config.network = {
    blipSeconds = 90,
    blip = { sprite = 225, colour = 1, scale = 0.9 },
    dispatch = true,
    dispatchCode = 'ALPR',
    dispatchWindowSeconds = 180,
    sightingWindowSeconds = 180,
}

Config.keys = {
    toggle = 'F7',
    lockFront = 'UP',
    lockRear = 'DOWN',
    bolo = '',
    cite = 'RIGHT',
    layout = '',
    hotlist = '',
}

Config.sounds = {
    lock = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    unlock = { name = 'BACK', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    hit = { name = 'TIMER_STOP', set = 'HUD_MINI_GAME_SOUNDSET', repeats = 2 },
    sighting = { name = 'Event_Message_Purple', set = 'GTAO_FM_Events_Soundset' },
    clock = { name = 'CHECKPOINT_NORMAL', set = 'HUD_MINI_GAME_SOUNDSET' },
}

Config.sender = {
    id = 'cortex-alpr',
    label = 'Plate reader',
    color = '#9bbcd3',
    icon = 'P',
}

Config.server = {
    readsPerSecond = 12,
    readSlack = 25.0,
    angleSlack = 20.0,
    airOriginSlack = 25.0,
    ledgerSeconds = 600,
    clocksPerMinute = 12,
    speedSlack = 4.0,
}
