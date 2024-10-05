------------------------------------
-- PROGRAM INFO
------------------------------------

-- TODO:
-- find out why its always a couple blocks to the right

-- This program can be used to aim a cannon from Create: Big Cannons.
-- The cannon must be assembled and in its starting position
-- before making an aim call with this program. 

-- You must make a setup call to create the cannon_data.json file
-- before it can be used for aim calls.

-- Template format: (arg) is required, [arg] is optional. 
-- To provide an optional argument, all the previous optional
-- arguments must be included as well.
-- (for higher accuracy, add +0.5 to all x, y, z values)
-- (-5 + 0.5 = -4.5, NOT -5.5)

-- template setup call:
-- aim setup (# of charges) (length of cannon (# of blocks past mount + 0.5)) (rpm of input) (mount x) (mount y) (mount z) (facing direction)
-- (facing direction can be any of: [north, east, south, west])

-- After calling setup, if you want to change any of these settings,
-- you can easily change it by hand in the cannon_data.json file.

-- template aim call:
-- aim (target x) (target y) (target z) [0 for low arc, 1 for high arc, (0 is default)] ["relative" or "exact" (exact is default)]

-- (relative: target is a position relative to the cannon mount)
-- (exact: target is the actual x y z coordinates of the target in world)

-- After aim finishes, if it succeeded it will push the "cannon_aim_success" event
-- with args (result, dist) where result is 0 and dist is the approximate distance
-- it will be from the target when it passes. (dist should always be less than 5)

-- If aim failed (the cannon is unable to fire at the target), it will push the 
-- "cannon_aim_failure" event with args (result, dist). Result is -1 if the
-- shot would fall short of the target, or 1 if the shot would fall past the target.
-- Dist is the distance the shot would be from the target at the targets y level.

-- You can also call this program by itself for an input query aiming mode. Only
-- exact coordinates are supported in this mode.
-- You can also call this program with 'setup' as the only argument
-- for an input query setup.

-- For safety reasons, cannons can only fire in a 180 degree horizontal arc
-- around their facing position, so that it cannot fire on its loading
-- mechanisms. This can be changed in getHorizAngle() if you wish.

------------------------------------
-- CONSTANTS 
------------------------------------

-- These data settings are the default values, but can be manually changed in the
-- cannon_data.json file that is created after calling this program with "setup".
-- You can also change these defaults in the set_data() function.

-- data.TILT_GEARSHIFT = "left"
-- data.TILT_CLUTCH = "bottom"
-- data.TURN_GEARSHIFT = "right"
-- data.TURN_CLUTCH = "back"


local const = {}
-- NOTE: DEFAULT CHARGE POWER WAS INCREASED FROM 20m/s TO 40m/s
const.CHARGE_POWER = 40 -- Base added speed of a powder charge is 40m/s
const.GRAVITY = vector.new(0,-0.05,0)
const.DRAG = 0.001
const.AIM_TRIES = 12
const.DEBUG = true

------------------------------------
-- SIMULATION FUNCTIONS
------------------------------------

local function stepDisplacement(velocity, displacement)
    displacement = displacement + velocity
    return displacement
end

local function stepVelocity(velocity)
    velocity = velocity + const.GRAVITY
    velocity = ((velocity * velocity) / 2) * const.DRAG 
    return velocity
end

-- Simulates a shot in the XY plane.
-- Returns the result, and then the distance a shot lands from the target.
-- Result is 0 if a shot with the given velocity will land within
-- tolerance blocks of the target. Result is -1 if the shot will
-- fall short of the target. Result is 1 if the shot will go past
-- the target. 
-- length input is the length of the cannon, makes calculations more precise.
--
local function simShot(velocity, target, tolerance, length)
    velocity = velocity / 20 -- Account for 20 ticks per second
    if (length) then
        displacement = velocity:normalize() * length
    else
        displacement = vector.new(0,0,0)
    end
    
    local dist
    local result = 0
    local old_displacement = nil
    while (not (displacement.y <= target.y - tolerance and velocity.y <= 0) and not (displacement.x >= target.x + tolerance)) do
        old_displacement = displacement
        displacement = stepDisplacement(velocity, displacement)
        velocity = stepVelocity(velocity)
    end

    if (not old_displacement) then 
        -- This would only happen if the target was above the cannon and
        -- the cannon simulated a shot pointing downwards
        result = -1
        dist = (displacement - target):length()
    else
        -- calculates the distance the target is from the line
        -- between old_displacement and displacement,
        -- to get the true distance from the shot's path.
        local a, b, c, topsum, botsum
        a = displacement.y - old_displacement.y
        b = old_displacement.x - displacement.x
        c = old_displacement.y * displacement.x - displacement.y * old_displacement.x
        topsum = math.abs(a * target.x + b * target.y + c)
        botsum = math.sqrt(a * a + b * b)
        dist = topsum / botsum
        if ((displacement - target):length() <= tolerance) then
            result = 0
        elseif (displacement.y <= target.y - tolerance and velocity.y <= 0) then
            result = -1
            dist = (displacement - target):length()
        elseif (displacement.x + tolerance > target.x) then
            if (dist <= tolerance) then
                result = 0
            else
                local slope = (displacement.y - old_displacement.y) / (displacement.x - old_displacement.x)
                local intercept = displacement.y - (slope * displacement.x)
                -- uses slope intercept form to see if the target is below or above the line of displacement.
                result = (slope * target.x + intercept < target.y - tolerance) and -1 or 1
            end
            if (const.DEBUG and result == 1) then
                log("shot y: " .. displacement.y, "target y: " .. target.y)
            end
        else
            result = displacement:length() < target:length() and -1 or 1 
            dist = (displacement - target):length()
        end
    end
    return result, dist
end

-- Given a starting "guess" for pitch, simulate shots on the target,
-- changing the pitch until the shot hits within tolerance blocks
-- of the target. Target is the relative 
-- XYZ coordinate with the cannon mount as the origin.
-- The guess for pitch should be 60 to try to shoot at a high angle.
-- Returns a degree between MAX_PITCH and MIN_PITCH if it found a successful shot,
--  or returns nil if none was found within 10 iterations.
-- length input is the length of the cannon, makes calculations more precise.

-- Sometimes can have trouble if the shot moves through the target from one tick to another
local function refineShot(guess, speed, target, tolerance, length, tries)
    local MAX_PITCH = 60
    local MIN_PITCH = -30
    local xy_target = vector.new(getHorizDistance(target), target.y, 0)
    local increment = math.rad(20) -- starting angle increment value
    local last_result = nil
    local last_distance = nil
    local try = 0
    -- convert degrees to radians to reduce headache
    local pitch = math.rad(guess)
    if (const.DEBUG) then
        log("Trying to hit " .. table.concat(target) .. " with " .. tolerance .. " block tolerance.")
    end

    -- initial attempt tries the first guess for pitch
    direction = vector.new(math.cos(pitch), math.sin(pitch), 0)
    velocity = direction * speed
    result, distance = simShot(velocity, xy_target, tolerance, length)

    repeat 

        -- if the previous shot didn't hit, then simulate two shots, one
        -- at pitch - increment, and one at pitch + increment.
        -- whichever is closer, between these two and the previous pitch, will
        -- be used as the pitch for the next iteration. If the previous pitch
        -- is used, then the increment gets cut in half.
        if (result ~= 0) then
            local direction1 = vector.new(math.cos(pitch - increment), math.sin(pitch - increment), 0)
            local velocity1 = direction1 * speed
            local result1, distance1 = simShot(velocity1, xy_target, tolerance, length)
            
            
            local direction2 = vector.new(math.cos(pitch + increment), math.sin(pitch + increment), 0)
            local velocity2 = direction2 * speed
            local result2, distance2 = simShot(velocity2, xy_target, tolerance, length)

            local min_distance = math.min(distance, math.min(distance1, distance2))
            local new_pitch
            if (distance == min_distance) then
                new_pitch = pitch
                increment = increment / 2
            elseif(distance1 == min_distance) then
                new_pitch = pitch - increment
            else
                new_pitch = pitch + increment
            end
            pitch = math.max(math.min(math.rad(MAX_PITCH), new_pitch), math.rad(MIN_PITCH))
            distance = min_distance
        end
        try = try + 1
        if (const.DEBUG) then
            if (result ~= 0) then
                log("Shot " .. try .. " landed ".. distance .. " from the target.")
                log("Changing pitch to " .. math.deg(pitch) .. " degrees.")
            else
                log("Hit target with pitch of " .. math.deg(pitch) .. " degrees.")
            end
        end
    until (result == 0 or try >= tries)

    if (result == 0) then
        return math.deg(pitch), distance, 0
    else
        return nil, distance, result
    end
end 
------------------------------------
-- VECTOR HELPER FUNCTIONS
------------------------------------

-- Returns the distance to target parallel to the XZ plane
local function getHorizDistance(target)
    return vector.new(target.x, 0, target.z):length()
end

-- Returns the angle to the target from the line z = 0 on the
-- XY plane, with right as -90 (degrees) and left as 90 (degrees)
-- with positive x and no z being 0 degrees.
local function getHorizAngle(target)
    -- TODO: ADD CUSTOMIZATION FOR MAXIMUM TURN RADIUS
    -- TODO: TEST WITH EACH FACING VALUE
    if (data.facing == "north") then
        if (target.z > 0) then
            angle = math.deg(math.atan(target.x / target.z))
        else 
            angle = nil
        end
    elseif (data.facing == "east") then
        if (target.x > 0) then
            angle = math.deg(math.atan(target.z / target.x))
        else
            angle = nil
        end
    elseif (data.facing == "south") then
        if (target.z < 0) then
            angle = math.deg(math.atan(target.x / target.z))
        else 
            angle = nil
        end
    elseif (data.facing == "west") then
        if (target.x < 0) then
            angle = -1 * math.deg(math.atan(target.z / target.x))
        else
            angle = nil
        end
        
    else error("NO FACING DATA") end

    return angle
end

local function getTrueHorizAngle(target)
    if (target.z > 0) then
        angle = math.deg(math.atan(target.x / target.z))
    elseif (target.z < 0) then
        angle = math.deg(math.atan(target.x / target.z))
    elseif (target.x > 0) then
        angle = 0
    else
        angle = 180
    end
    return angle
end

local function getHorizAngleBetween(current, target)
    return getTrueHorizAngle(target) - getTrueHorizAngle(current)
end

return {const = const, getTrueHorizAngle = getTrueHorizAngle, refineShot = refineShot}