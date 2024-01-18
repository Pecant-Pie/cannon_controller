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


const = {}
-- NOTE: DEFAULT CHARGE POWER WAS INCREASED FROM 20m/s TO 40m/s
const.CHARGE_POWER = 40 -- Base added speed of a powder charge is 40m/s
const.GRAVITY = vector.new(0,-0.05,0)
const.DRAG = 0.99
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
    velocity = velocity * const.DRAG
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
-- Returns a degree between 90 and -90 if it found a successful shot,
--  or returns nil if none was found within 10 iterations.
-- length input is the length of the cannon, makes calculations more precise.

-- Sometimes can have trouble if the shot moves through the target from one tick to another
local function refineShot(pitch, speed, target, tolerance, length, tries)
    local MAX_PITCH = 60
    local MIN_PITCH = -30
    xy_target = vector.new(getHorizDistance(target), target.y, 0)
    increment = math.rad(20) -- starting angle increment value
    last_result = nil
    last_distance = nil
    try = 0
    -- convert degrees to radians to reduce headache
    pitch = math.rad(pitch)
    if (const.DEBUG) then
        log("Trying to hit " .. table.concat(target) .. " with " .. tolerance .. " block tolerance.")
    end
    repeat 
        direction = vector.new(math.cos(pitch), math.sin(pitch), 0)
        velocity = direction * speed
        result, distance = simShot(velocity, xy_target, tolerance, length)
        
        if (result ~= 0) then
            direction1 = vector.new(math.cos(pitch - increment), math.sin(pitch - increment), 0)
            velocity1 = direction1 * speed
            result1, distance1 = simShot(velocity1, xy_target, tolerance, length)
            
            
            direction2 = vector.new(math.cos(pitch + increment), math.sin(pitch + increment), 0)
            velocity2 = direction2 * speed
            result2, distance2 = simShot(velocity2, xy_target, tolerance, length)

            min_distance = math.min(distance, math.min(distance1, distance2))
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
        return math.deg(pitch), distance
    else
        return nil, distance, result
    end
end 
------------------------------------
-- VECTOR HELPER FUNCTIONS
------------------------------------

-- Returns the distance to target parallel to the XZ plane
function getHorizDistance(target)
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

------------------------------------
-- CANNON CONTROL FUNCTIONS
------------------------------------

-- THIS FUNCTION MAY TAKE MULTIPLE SECONDS TO RETURN
-- It starts aiming the cannon at the given pitch and
-- yaw, and queues two timer events that will go off
-- once the cannon is in position. Then the function
-- stops the cannon's motion and returns true.
function aimCannon(pitch, yaw, rpm)
    -- cannon controller and yaw controller move at 1/8 speed
    -- of the rpm, hence the (1/8) factor in the equation for dps
    local dps = 360 * rpm / 60 * (1/8)
    local tiltSeconds = getTiltSeconds(pitch, dps)
    local tiltDown = pitch <= 0
    local turnSeconds = getTurnSeconds(yaw, dps)
    local turnRight = yaw <= 0

    
    if (tiltSeconds > 0) then
        startTilting(tiltDown)
    end
    tiltID = os.startTimer(tiltSeconds)
    if (const.DEBUG) then
        log("tilting for ".. tiltSeconds .. "seconds...")
    end
    if (turnSeconds > 0) then
        startTurning(turnRight)
    end
    turnID = os.startTimer(turnSeconds)
    if (const.DEBUG) then
        log("turning for ".. turnSeconds .. "seconds...")
    end


    local function waitCannonTilt()
        repeat
            event, id = os.pullEvent("timer")
        until id == tiltID
        stopCannonTilt()
    end

    local function waitCannonTurn()
        repeat
            event, id = os.pullEvent("timer")
        until id == turnID
        stopCannonTurn()
    end
    parallel.waitForAll(waitCannonTilt, waitCannonTurn)
    --print("Cannon aimed!") -- DEBUG
    return true
end

function startTilting(tiltDown)
    if (const.DEBUG) then
        log("tiltDown: " .. (tiltDown and "true" or "false"))
    end
    if (tiltDown) then
        rs.setOutput(data.TILT_GEARSHIFT, true)
    end
    rs.setOutput(data.TILT_CLUTCH, true)
end


function startTurning(turnRight)
    if (const.DEBUG) then
        log("turnRight: " .. (turnRight and "true" or "false"))
    end
    if (turnRight) then
        rs.setOutput(data.TURN_GEARSHIFT, true)
    end
    rs.setOutput(data.TURN_CLUTCH, true)
end

function stopCannonTilt()    
    if (const.DEBUG) then
    log("stopping tilt")
end
    rs.setOutput(data.TILT_CLUTCH, false)
    rs.setOutput(data.TILT_GEARSHIFT, false)
end

function stopCannonTurn()
    if (const.DEBUG) then
        log("stopping turn")
    end
    rs.setOutput(data.TURN_CLUTCH, false)
    rs.setOutput(data.TURN_GEARSHIFT, false)
end

function getTiltSeconds(pitch, dps)
    return math.abs(pitch / dps)
end

function getTurnSeconds(yaw, dps)
    return math.abs(yaw / dps)
end

------------------------------------
-- CANNON SETUP
------------------------------------
function save_data()
    f = io.open("cannon_data.json", "w")
    if (f) then
        f:write(textutils.serialiseJSON(data))
        f:close()
        return true
    else
        return false
    end
end

function load_data()
    f = io.open("cannon_data.json", "r")
    if (f) then
        temp = textutils.unserialiseJSON(f:read("a"))
        f:close()
        return temp
    else
        return nil
    end
end

-- call using set_data{} and include charges = 4, etc. in the table
function set_data(t)
    if (t.charges) then
        data.charges = t.charges
    end
    if (t.length) then
        data.length = t.length
    end
    if (t.rpm) then
        data.rpm = t.rpm
    end
    if (t.x and t.y and t.z) then
        data.mount_xyz = vector.new(t.x, t.y, t.z)
    end
    if (t.facing) then
        data.facing = t.facing
    end
    if (not data.TURN_GEARSHIFT) then
        data.TURN_GEARSHIFT = "right"
    end
    if (not data.TURN_CLUTCH) then
        data.TURN_CLUTCH = "back"
    end
    if (not data.TILT_GEARSHIFT) then
        data.TILT_GEARSHIFT = "left"
    end
    if (not data.TILT_CLUTCH) then
        data.TILT_CLUTCH = "top"
    end
end

------------------------------------
-- INTERFACE
------------------------------------

function queryAim()
    print("Enter the coordinates (X, Y, Z) you would like to shoot at:")

    print("X: ")
    local x = tonumber(io.read()) 

    print("Y: ")
    local y = tonumber(io.read()) 

    print("Z: ")
    local z = tonumber(io.read()) 

    print("Aim high or low? (0 for low, 1 for high)")
    local high = tonumber(io.read()) 
    local guess
    if (high == 1) then
        guess = 60
    else
        guess = 0
    end
    target = vector.new(x, y, z) - data.mount_xyz
    targetAim(guess, data.charges * const.CHARGE_POWER, target, data.length, const.AIM_TRIES, true)
end


function queryData() 
    print("Enter the charge, length, rpm, mount x, \
    mount y, mount z, and facing values on a single line, separated by spaces.")
    local str = io.read()
    local arr = {}
    local count = 1
    for v in string.gmatch(str, "%-?%d+%.?%d*") do
        arr[count] = v
        count = count + 1
    end
    return arr
end


-- Aims the cannon at the target (which is a RELATIVE position vector)
function targetAim(guess, speed, target, length, tries, manual)
    if (manual) then
        print("Aiming Cannon")
    end
    local tolerance = 1
    local yaw = getHorizAngle(target)
    repeat 
        pitch, dist, result = refineShot(guess, speed, target, tolerance, length, tries)
        tolerance = tolerance + 1
    until (pitch ~= nil or tolerance > 5)
    if (pitch and yaw) then
        if (const.DEBUG) then
            log("Aiming cannon with pitch: " .. pitch .. ", yaw: " .. yaw .. ".")
        end
        aimCannon(pitch, yaw, data.rpm)
        os.queueEvent("cannon_aim_success", result, dist)
        if (manual) then
            print("Ready to Fire ".. dist .. " blocks from target!")
        end
        return true
    else 
        os.queueEvent("cannon_aim_failure", result, dist)
        if (manual) then
            if (not yaw) then print("Not facing target!") end
            if (not pitch) then print("Target out of range!") end
        end
        return false
    end
end

------------------------------------
-- LOGGING CODE
------------------------------------

function init_log(filename)
    const.LOG = io.open(filename, "w")
    log(os.date())
end


function log(str)
    const.LOG:write(str .. "\n")
end

function stop_log()
    const.LOG:close()
end

------------------------------------
-- MAIN PROGRAM CODE
------------------------------------

local temp = load_data()
print("loading cannon data...")
if (temp) then
    data = temp
    print("loaded cannon data.")
else print("failed to load cannon data.") end

-- Initialize log
init_log("latest.log")

-- aim [target x] [target y] [target z] [0 for low arc, 1 for high arc] ["relative" or "exact" (exact is default)]
args = {...}
if (#args > 0) then
    if (#args >= 3 and tonumber(args[1]) ~= nil) then

        -- default aim mode is exact
        if (args[5] ~= nil and args[5] == "relative") then
            target = vector.new(args[1], args[2], args[3])
        else
            target = vector.new(args[1], args[2], args[3]) - data.mount_xyz
        end     
        -- default initial trajectory is low
        if (args[4] ~= nil and args[4] == "1") then
            guess = 60
        else
            guess = 0
        end

        targetAim(guess, data.charges * const.CHARGE_POWER, target, data.length, const.AIM_TRIES, false)
    elseif (#args >= 1) then
        if (string.lower(args[1]) == "setup") then
            if (#args > 1) then
                data = load_data() or {}
                set_data{
                    charges = tonumber(args[2]), 
                    length = tonumber(args[3]),
                    rpm = tonumber(args[4]),
                    x = tonumber(args[5]),
                    y = tonumber(args[6]),
                    z = tonumber(args[7]),
                    facing = args[8]}
                save_data()
            else 
                local arr = queryData()
                set_data{
                    charges = tonumber(arr[1]), 
                    length = tonumber(arr[2]),
                    rpm = tonumber(arr[3]),
                    x = tonumber(arr[4]),
                    y = tonumber(arr[5]),
                    z = tonumber(arr[6]),
                    facing = arr[7]}
                save_data()
            end
        end
    end
else 
    queryAim()
end

stop_log()

------------------------------------
-- INFO (OUTDATED)
------------------------------------
-- A max length nethersteel cannon can shoot
-- up to 550 blocks away, at the same y value, at
-- 30 degrees. (using 8 powder charges)
-- It can shoot 585 away at y value 50 lower.
-- 610 away at 100 lower, 655 at 200, 672 at 250
-- 
-- A max length steel cannon can shoot up to 370
-- blocks away, at the same y value, at 30 degrees.
-- (using 6 powder charges)
-- It can shoot 403 blocks away at y value 50 lower.
-- 428 blocks away at 100 lower, 470 at 200, 486 at 250
------------------------------------
-- TESTING
------------------------------------

-- target_xyz = vector.new(33.00, 0.00, 111.07)
-- target = target_xyz - mount_xyz
-- tolerance = 3 -- acceptable distance from target
-- length = 31.5 -- length of the cannon past the middle of the cannon mount
-- tries = 20 -- how many iterations of refinement to go through
-- speed = data.CHARGES * const.CHARGE_POWER
-- print("Target is " .. target:tostring())
-- print("Speed is " .. speed)
-- yaw = getHorizAngle(target)
-- pitch = refineShot(0, speed, target, tolerance, length, tries, true)
-- print("Shoot at pitch " .. pitch .. " to hit target.")
-- aimCannon(pitch, yaw, 4)
