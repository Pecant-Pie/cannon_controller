------------------------------------
-- CONSTANTS 
------------------------------------

data = {}
data.TILT_GEARSHIFT = "left"
data.TILT_CLUTCH = "bottom"
data.TURN_GEARSHIFT = "right"
data.TURN_CLUTCH = "back"

----- These settings are now set using the "setup" cmd line argument.
-----
-- data.length = 31.5
-- data.charges = 8 -- number of powder charges
-- data.rpm = 8

-- Position of the center of the top part of the cannon mount
-- data.mount_xyz = vector.new(0.5, 11.5, 6.5) 
----
----

const = {}
const.CHARGE_POWER = 20 -- Base added speed of a powder charge is 20m/s
const.GRAVITY = vector.new(0,-0.05,0)
const.DRAG = 0.99

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
local function simShot(velocity, target, tolerance, length, debug)
    velocity = velocity / 20 -- Account for 20 ticks per second
    if (length) then
        displacement = velocity:normalize() * length
    else
        displacement = vector.new(0,0,0)
    end
    -- distance = displacement.x
    result = 0
    while (not (displacement.y <= target.y and velocity.y <= 0)) do
        displacement = stepDisplacement(velocity, displacement)
        -- distance = distance + velocity.x
        velocity = stepVelocity(velocity)
    end

    if ((displacement - target):length() > tolerance) then
        result = displacement:length() < target:length() and -1 or 1 
    end
    return result, (displacement - target):length()
end

-- Given a starting "guess" for pitch, simulate shots on the target,
-- changing the pitch until the shot hits within tolerance blocks
-- of the target. Tolerance >= 2 should suffice. Target is the relative 
-- XYZ coordinate with the cannon mount as the origin.
-- The guess for pitch should be above 30 to shoot at a high angle.
-- Returns a degree between 90 and -90 if it found a successful shot,
--  or returns nil if none was found within 10 iterations.
-- length input is the length of the cannon, makes calculations more precise.

-- Sometimes can have trouble if the shot moves through the target from one tick to another
local function refineShot(pitch, speed, target, tolerance, length, tries, debug)
    local MAX_PITCH = 60
    local MIN_PITCH = -30
    xy_target = vector.new(getHorizDistance(target), target.y, 0)
    increment = math.rad(20) -- starting angle increment value
    last_result = nil
    last_distance = nil
    try = 0
    -- convert degrees to radians to reduce headache
    pitch = math.rad(pitch)
    repeat 
        direction = vector.new(math.cos(pitch), math.sin(pitch), 0)
        velocity = direction * speed
        result, distance = simShot(velocity, xy_target, tolerance, length, debug)
        if (last_result and last_result ~= result or last_distance and last_distance < distance) then
            increment = increment / 2
        end
        last_result = result
        last_distance = distance
        
        if (result ~= 0) then
            if (pitch > math.rad(30)) then -- magic 30 degrees shoots farthest at same y level
                pitch = (pitch + result * increment) 
            else 
                pitch = (pitch - result * increment)
            end
            pitch = math.max(math.min(math.rad(MAX_PITCH), pitch), math.rad(MIN_PITCH))
        end
        try = try + 1
        if (debug) then
            if (result ~= 0) then
                print("Shot landed ".. distance .. (result == -1 and " short of " or " past ") .. "the target.")
                print("Changing pitch to " .. math.deg(pitch) .. " degrees.")
            else
                print("Hit target with pitch of " .. math.deg(pitch) .. " degrees.")
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
    -- TODO: add a 'facing' parameter
    if (target.z > 0) then
        angle = math.deg(math.atan(target.x / target.z))
    else 
        angle = nil
    end
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
    dps = 360 * rpm / 60 * (1/8)
    tiltSeconds = getTiltSeconds(pitch, dps)
    tiltDown = pitch <= 0
    turnSeconds = getTurnSeconds(yaw, dps)
    turnRight = yaw <= 0

    startTilting(tiltDown)
    tiltID = os.startTimer(tiltSeconds)
    print("tilting for ".. tiltSeconds .. "seconds...") -- DEBUG
    startTurning(turnRight)
    turnID = os.startTimer(turnSeconds)
    print("turning for ".. turnSeconds .. "seconds...") -- DEBUG

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
    print("Cannon aimed!") -- DEBUG
    return true
end

function startTilting(tiltDown)
    if (tiltDown) then
        rs.setOutput(data.TILT_GEARSHIFT, true)
    end
    rs.setOutput(data.TILT_CLUTCH, true)
end


function startTurning(turnRight)
    if (turnRight) then
        rs.setOutput(data.TURN_GEARSHIFT, true)
    end
    rs.setOutput(data.TURN_CLUTCH, true)
end

function stopCannonTilt()
    rs.setOutput(data.TILT_CLUTCH, false)
    rs.setOutput(data.TILT_GEARSHIFT, false)
end

function stopCannonTurn()
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

-- ALL ARGUMENTS SHOULD BE EITHER NUMBERS OR NIL
function set_data(charges, length, rpm, x, y, z)
    if (charges) then
        data.charges = charges;
    end
    if (length) then
        data.length = length;
    end
    if (rpm) then
        data.rpm = rpm;
    end
    if (x ~= nil and y ~= nil and z ~= nil) then
        data.mount_xyz = vector.new(x, y, z);
    end

end

------------------------------------
-- INTERFACE
------------------------------------

function queryUser()
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
    targetAim(guess, data.charges * const.CHARGE_POWER, target, data.length, 15, false, true)
end

function queryData() 
    print("Enter the charge, length, rpm, mount x, \
    mount y, and mount z values on a single line, separated by spaces.")
    local str = io.read()
    local arr = {}
    local count = 1
    for v in string.gmatch(str, "%-?%d+%.?%d*") do
        arr[count] = v
        count = count + 1
    end
    return arr
end

function targetAim(guess, speed, target, length, tries, debug, manual)
    if (manual) then
        print("Aiming Cannon")
    end
    local tolerance = 1
    repeat 
        pitch, dist, result = refineShot(guess, speed, target, tolerance, length, tries, debug)
        tolerance = tolerance + 1
    until (pitch ~= nil or tolerance > 5)
    if (pitch) then
        local yaw = getHorizAngle(target)
        aimCannon(pitch, yaw, data.rpm)
        os.queueEvent("cannon_aim_success", result, dist)
        if (manual) then
            print("Ready to Fire ".. dist .. " blocks from target!")
        end
        return true
    else 
        os.queueEvent("cannon_aim_failure", result, dist)
        if (manual) then
            print("Could not aim close enough to target, sorry!")
        end
        return false
    end
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
    


args = {...}
if (args) then
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

        targetAim(guess, data.charges * const.CHARGE_POWER, target, data.length, 15, false, false)
    elseif (#args >= 1) then
        if (string.lower(args[1]) == "setup") then
            if (#args > 1) then
                set_data(tonumber(args[2]), 
                         tonumber(args[3]),
                         tonumber(args[4]),
                         tonumber(args[5]),
                         tonumber(args[6]),
                         tonumber(args[7]))
                save_data()
            else 
                local arr = queryData()
                set_data(tonumber(arr[1]), 
                         tonumber(arr[2]),
                         tonumber(arr[3]),
                         tonumber(arr[4]),
                         tonumber(arr[5]),
                         tonumber(arr[6]))
                save_data()
            end
        end
    end
else 
    queryUser()
end

------------------------------------
-- INFO
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
