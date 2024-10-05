local targeting = require("aim")
local cannon = require("cannon")

------------------------------------
-- INTERFACE
------------------------------------

local const = {
    CHARGE_POWER = 40,
    AIM_TRIES = 20,
    CANNON_FILE = "cannon_data.json",
    DEBUG = true
}

local function queryAim()
    if (not cannon.loadData(const.CANNON_FILE)) then
        error("Missing cannon datafile: " .. const.CANNON_FILE)
    end
    
    print("Enter the true coordinates (X, Y, Z) you would like to shoot at:")

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
    target = vector.new(x, y, z) - cannon.getVec()
    targeting.targetAim(guess, cannon.data.charges * const.CHARGE_POWER, target, cannon.data.length, const.AIM_TRIES, true)
end


local function queryData() 
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
local function targetAim(guess, speed, target, length, tries, manual)
    if (manual) then
        print("Aiming Cannon")
    end
    local tolerance = 1
    local yaw = targeting.getHorizAngle(target)
    repeat 
        pitch, dist, result = targeting.refineShot(guess, speed, target, tolerance, length, tries)
        tolerance = tolerance + 1
    until (pitch ~= nil or tolerance > 5)
    if (pitch and yaw) then
        if (const.DEBUG) then
            log("Aiming cannon with pitch: " .. pitch .. ", yaw: " .. yaw .. ".")
        end
        cannon.aimCannon(pitch, yaw, data.rpm)
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

-- Aims the cannon at the target (which is a RELATIVE position vector),
-- taking the current pitch and yaw into consideration
local function aimAgain(speed, target, length, currentPitch, currentYaw, tries, simulate)
    local tolerance = 0.5
    local yaw = targeting.getTrueHorizAngle(target) - currentYaw
    repeat
        pitch, dist, result = targeting.refineShot(30, speed, target, tolerance, length, tries)
        tolerance = tolerance + 1
    until (pitch ~= nil or tolerance > 5)
    if (pitch and yaw) then
        pitch = pitch - currentPitch
        if (const.DEBUG) then
            log("Aiming cannon with pitch: " .. pitch .. ", yaw: " .. yaw .. ".")
        end
        if (simulate) then
            return result, dist, pitch, yaw
        else
            cannon.aimCannon(pitch, yaw, data.rpm)
            os.queueEvent("cannon_aim_success", result, dist)
            return true
        end
    else 
        if (simulate) then
            return result, dist
        else
            os.queueEvent("cannon_aim_failure", result, dist)
            return false
        end
    end
end

------------------------------------
-- LOGGING CODE
------------------------------------

local function init_log(filename)
    const.LOG = io.open(filename, "w")
    log(os.date())
end


local function log(str)
    const.LOG:write(str .. "\n")
end

local function stop_log()
    const.LOG:close()
end

------------------------------------
-- MAIN PROGRAM CODE
------------------------------------

-- cli [target x] [target y] [target z] [0 for low arc, 1 for high arc] ["relative" or "exact" (exact is default)]

local function main(args)
    print("loading cannon data...")
    local temp = cannon.load_data(const.CANNON_FILE)
    if (temp) then
        print("loaded cannon data.")
    else print("failed to load cannon data.") end

    -- Initialize log
    init_log("latest.log")

    if (#args > 0) then
        if (#args >= 3 and tonumber(args[1]) ~= nil) then

            -- default aim mode is exact
            if (args[5] ~= nil and args[5] == "relative") then
                target = vector.new(args[1], args[2], args[3])
            else
                target = vector.new(args[1], args[2], args[3]) - cannon.getVec()
            end     
            -- default initial trajectory is low
            if (args[4] ~= nil and args[4] == "1") then
                guess = 60
            else
                guess = 0
            end

            targetAim(guess, cannon.data.charges * const.CHARGE_POWER, target, cannon.data.length, const.AIM_TRIES, false)
        elseif (#args >= 1) then
            if (string.lower(args[1]) == "setup") then
                if (#args > 1) then
                    cannon.set_data{
                        charges = tonumber(args[2]), 
                        length = tonumber(args[3]),
                        rpm = tonumber(args[4]),
                        x = tonumber(args[5]),
                        y = tonumber(args[6]),
                        z = tonumber(args[7]),
                        facing = args[8]}
                    cannon.saveData(const.CANNON_FILE)
                else 
                    local arr = queryData()
                    cannon.setData{
                        charges = tonumber(arr[1]), 
                        length = tonumber(arr[2]),
                        rpm = tonumber(arr[3]),
                        x = tonumber(arr[4]),
                        y = tonumber(arr[5]),
                        z = tonumber(arr[6]),
                        facing = arr[7]}
                    cannon.saveData(const.CANNON_FILE)
                end
            end
        end
    else 
        queryAim()
    end

    stop_log()

end

return {queryAim = queryAim, targetAim = targetAim, cli = main, const = const}