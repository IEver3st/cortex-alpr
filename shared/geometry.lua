Geo = {}

Geo.SPEED = { mph = 2.236936, kmh = 3.6 }

function Geo.forwardFromHeading(heading)
    local h = math.rad(heading)
    return vector3(-math.sin(h), math.cos(h), 0.0)
end

function Geo.directionFromRotation(rot)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

function Geo.flat(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y)
    if len < 0.0001 then return vector3(0.0, 0.0, 0.0), 0.0 end
    return vector3(v.x / len, v.y / len, 0.0), len
end

function Geo.dot2(a, b)
    return a.x * b.x + a.y * b.y
end

function Geo.angleBetween(a, b)
    local la = math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
    local lb = math.sqrt(b.x * b.x + b.y * b.y + b.z * b.z)
    if la < 0.0001 or lb < 0.0001 then return 180.0 end
    local d = (a.x * b.x + a.y * b.y + a.z * b.z) / (la * lb)
    return math.deg(math.acos(math.max(-1.0, math.min(1.0, d))))
end

function Geo.inBeam(origin, axis, point, range, halfAngle, nearWidth)
    local rel = point - origin
    local along = rel.x * axis.x + rel.y * axis.y
    if along <= 1.0 or along > range then return false, along end
    local lateral = math.abs(rel.x * axis.y - rel.y * axis.x)
    local width = math.max(nearWidth, math.tan(math.rad(halfAngle)) * along)
    return lateral <= width, along, lateral
end

function Geo.inHeight(rel, up, along, angle, near)
    local height = math.abs(rel.x * up.x + rel.y * up.y + rel.z * up.z)
    return height <= math.max(near, math.tan(math.rad(angle)) * along)
end

function Geo.beamSpeed(velocity, own, rel, cosine)
    local length = math.sqrt(rel.x * rel.x + rel.y * rel.y + rel.z * rel.z)
    local ground = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
    if length < 0.001 then return ground, nil end
    local lx, ly, lz = rel.x / length, rel.y / length, rel.z / length
    local radial = velocity.x * lx + velocity.y * ly + velocity.z * lz
    local rate = radial - (own.x * lx + own.y * ly + own.z * lz)
    local direction = rate < -0.7 and 'closing' or rate > 0.7 and 'away' or nil
    return cosine and math.abs(radial) or ground, direction
end

function Geo.plateFacing(targetForward, losDirection, maxAngle)
    local f = Geo.flat(targetForward)
    local l = Geo.flat(losDirection)
    local d = Geo.dot2(f, l)
    local limit = math.cos(math.rad(maxAngle))
    if d >= limit then return 'rear' end
    if d <= -limit then return 'front' end
    return nil
end

function Geo.plate(text)
    if type(text) ~= 'string' then return nil end
    local p = text:upper():gsub('%s+', '')
    if p == '' or #p > 8 then return nil end
    return p
end
