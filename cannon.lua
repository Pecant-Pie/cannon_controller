
local const = {
    DEBUG = false
}

local data = {}
------------------------------------
-- CANNON CONTROL FUNCTIONS
------------------------------------

local function startTilting(tiltDown)
    if (const.DEBUG) then
        log("tiltDown: " .. (tiltDown and "true" or "false"))
    end
    if (tiltDown) then
        rs.setOutput(data.TILT_GEARSHIFT, true)
    end
    rs.setOutput(data.TILT_CLUTCH, true)
end


local function startTurning(turnRight)
    if (const.DEBUG) then
        log("turnRight: " .. (turnRight and "true" or "false"))
    end
    if (turnRight) then
        rs.setOutput(data.TURN_GEARSHIFT, true)
    end
    rs.setOutput(data.TURN_CLUTCH, true)
end

local function stopCannonTilt()    
    if (const.DEBUG) then
    log("stopping tilt")
end
    rs.setOutput(data.TILT_CLUTCH, false)
    rs.setOutput(data.TILT_GEARSHIFT, false)
end

local function stopCannonTurn()
    if (const.DEBUG) then
        log("stopping turn")
    end
    rs.setOutput(data.TURN_CLUTCH, false)
    rs.setOutput(data.TURN_GEARSHIFT, false)
end

local function getTiltSeconds(pitch, dps)
    return math.abs(pitch / dps)
end

local function getTurnSeconds(yaw, dps)
    return math.abs(yaw / dps)
end

local function startSequencedGearshiftTilt(gearshift, pitch)
    if (pitch ~= 0) then
        gearshift.rotate(math.abs(pitch) * 8, pitch < 0 and -1 or 1)
    end
end

local function startSequencedGearshiftTurn(gearshift, yaw)
    if (yaw ~= 0) then
        gearshift.rotate(math.abs(yaw) * 8, yaw < 0 and -1 or 1)
    end
end

local function isReadyToFire(gearshift1, gearshift2)
    return not gearshift1.isRunning() and not gearshift2.isRunning()
end

-- THIS FUNCTION MAY TAKE MULTIPLE SECONDS TO RETURN
-- It starts aiming the cannon at the given pitch and
-- yaw, and queues two timer events that will go off
-- once the cannon is in position. Then the function
-- stops the cannon's motion and returns true.
local function aim(pitch, yaw, rpm)
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


------------------------------------
-- CANNON SETUP
------------------------------------
local function saveData(filename)
    f = io.open(filename, "w")
    if (f) then
        f:write(textutils.serialiseJSON(data))
        f:close()
        return true
    else
        return false
    end
end

local function loadData(filename)
    f = io.open(shell.resolve(filename), "r")
    if (f) then
        temp = textutils.unserialiseJSON(f:read("a"))
        f:close()
        for k,v in pairs(temp) do
            data[k] = v
        end
        return true
    else
        return false
    end
end

-- call using setData{} and include charges = 4, etc. in the table
local function setData(t)
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

local function getVec() 
    return vector.new(data.mount_xyz.x, data.mount_xyz.y, data.mount_xyz.z)
end

return {aim = aim, setData = setData, loadData = loadData, saveData = saveData, data = data, getVec = getVec}