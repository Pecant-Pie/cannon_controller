------------------------------------
-- SIMULATION FUNCTIONS
------------------------------------

function stepDisplacement(velocity, displacement)
    displacement = displacement + velocity
    return displacement
end

function stepVelocity(velocity)
    velocity = velocity + GRAVITY
    velocity = velocity * DRAG
    return velocity
end

-- Simulates a shot in the XY plane.
-- Returns the result, and then the distance a shot lands from the target.
-- Result is 0 if a shot with the given velocity will land within
-- tolerance blocks of the target. Result is -1 if the shot will
-- fall short of the target. Result is 1 if the shot will go past
-- the target. 
-- length input is the length of the cannon, makes calculations more precise.
function simShot(velocity, target, tolerance, length, debug)
    velocity =  velocity / 20 -- Account for 20 ticks per second
    if (length) then
        displacement = velocity:normalize() * length
    else
        displacement = vector.new(0,0,0)
    end
    distance = displacement.x
    result = 0
    while (not (displacement.y <= target.y and velocity.y <= 0)) do
        displacement = stepDisplacement(velocity, displacement)
        distance = distance + velocity.x
        velocity = stepVelocity(velocity)
        -- if (debug) then
        --     print("Shot is at position ".. displacement:tostring() .. " with velocity " .. velocity:tostring())
        --     sleep(0.5)
        -- end
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
-- highAngle mode makes it lower the cannon to increase distance, good for
-- doing a 'pop fly' kind of shot. False will raise the cannon to increase
-- distance, good for trying to penetrate through the wall of a structure.
-- The guess for pitch should be above 45 for highAngle mode, and below 45
-- for normal mode.
-- Returns a degree between 90 and -90 if it found a successful shot,
--  or returns nil if none was found within 10 iterations.
-- length input is the length of the cannon, makes calculations more precise.
function refineShot(pitch, speed, target, tolerance, highAngle, length, tries, debug)
    local MAX_PITCH = 60
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
            -- TODO: Improve this section using last_result and last_distance
            -- This line is what adjusts the aim up or down.
            if (pitch > math.rad(30)) then
                pitch = (pitch + result * increment) 
            else 
                pitch = (pitch - result * increment)
            end
            pitch = math.min(math.rad(MAX_PITCH), pitch)
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
        return math.deg(pitch)
    else
        return nil
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
function getHorizAngle(target)
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
function aimCannon(pitch, yaw)
    tiltSeconds = getTiltSeconds(pitch)
    tiltDown = pitch <= 0
    turnSeconds = getTurnSeconds(yaw)
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
        rs.setOutput(TILT_GEARSHIFT, true)
    end
    rs.setOutput(TILT_CLUTCH, true)
end


function startTurning(turnRight)
    if (turnRight) then
        rs.setOutput(TURN_GEARSHIFT, true)
    end
    rs.setOutput(TURN_CLUTCH, true)
end

function stopCannonTilt()
    rs.setOutput(TILT_GEARSHIFT, false)
    rs.setOutput(TILT_CLUTCH, false)
end

function stopCannonTurn()
    rs.setOutput(TURN_GEARSHIFT, false)
    rs.setOutput(TURN_CLUTCH, false)
end

function getTiltSeconds(pitch)
    return math.abs(pitch / DPS)
end

function getTurnSeconds(yaw)
    return math.abs(yaw / DPS)
end

------------------------------------
-- CONSTANTS 
------------------------------------

rpm = 3 -- RPM of the rotation connected to the cannon mount
dumb_cannon_rpm_factor = 1/8 -- Cannons turn at 1/8th speed
DPS = 360 * rpm / 60 * dumb_cannon_rpm_factor -- degrees per second
DPRT = DPS / 10 -- degrees per redstone tick


CHARGES = 8 -- number of powder charges
SPEED = 20 * CHARGES
GRAVITY = vector.new(0,-0.05,0)
DRAG = 0.99

TILT_GEARSHIFT = "left"
TILT_CLUTCH = "bottom"
TURN_GEARSHIFT = "right"
TURN_CLUTCH = "back"
------------------------------------
-- INFO
------------------------------------
-- A max length nethersteel cannon can shoot
-- up to 550 blocks away, at the same y value.

------------------------------------
-- TESTING
------------------------------------


mount_xyz = vector.new(0.5, 31.5, 6.5)
target_xyz = vector.new(0.5, 11.5, 606.5)
target = target_xyz - mount_xyz
tolerance = 2 -- acceptable distance from target
length = 31.5 -- length of the cannon past the middle of the cannon mount
tries = 15 -- how many iterations of refinement to go through
print("Target is " .. target:tostring())
print("Speed is " .. SPEED)
yaw = getHorizAngle(target)
pitch = refineShot(0, SPEED, target, tolerance, false, length, tries, true)
print("Shoot at pitch " .. pitch .. " to hit target.")
aimCannon(pitch, yaw)