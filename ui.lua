------------------------------------
-- MONITORS
------------------------------------

------------------------------------
-- BUTTONS CODE
------------------------------------
-- Credit: I watched Direwolf20's Button API
-- video before writing this, and this is based
-- off of his implementation. I have generalized
-- it so I can use it alongside the window API
-- to compartmentalize the output screen.
------------------------------------

function makeButton(handler, name, text, func, bgcolor, x, y, w, h, txtcolor)
    txtcolor = txtcolor or colors.white
    handler[name] = {}
    handler[name].text = text
    handler[name].func = func
    handler[name].txtcolor = txtcolor
    handler[name].bgcolor = bgcolor
    handler[name].x = x
    handler[name].y = y
    handler[name].w = w
    handler[name].h = h
    handler[name].active = true
end

function drawButtons(handler, output)
    for name, data in pairs(handler) do
        if (data.active) then
            drawButton(data, output)
        end
    end
end

function drawButton(data, output)
    local oldbg = output.getBackgroundColor()
    local oldtc = output.getTextColor()
    local midy = math.floor(data.y + data.h / 2)
    output.setBackgroundColor(data.bgcolor)
    output.setTextColor(data.txtcolor)
    if (data.bgcolor == data.txtcolor) then
        output.setTextColor(oldbg)
    end
    -- Mode for a single line text entry
    if (not data.text:find("\n")) then
        for j = data.y, data.y + data.h - 1 do
            output.setCursorPos(data.x, j)
            if (j == midy) then
                for i = 1, data.w - #(data.text) + 1 do
                    if (i == math.floor((data.w - #(data.text)) / 2) + 1) then
                        output.write(data.text)
                    else
                        output.write(" ")
                    end
                end
            else
                for i = 1, data.w do
                    output.write(" ")
                end
            end
        end
    else -- Mode for a multi-line text entry
        local numLines = countC(data.text, "\n") + 1
        local lines = {}
        local count = 1
        for line in string.gmatch(data.text, "([^\n]+)") do
            lines[count] = line
            count = count + 1
        end
        for j = data.y, data.y + data.h - 1 do
            output.setCursorPos(data.x, j)
            -- this part is a mess, I am so sorry (I spent like 30 minutes messing with numbers until this worked)
            if (j >= midy - math.ceil(numLines / 2) and j <= midy + math.floor(numLines / 2) - 1) then
                local line_index = j - (midy - math.ceil(numLines / 2)) + 1
                for i = 1, data.w - #(lines[line_index]) + 1 do
                    if (i == math.floor((data.w - #(lines[line_index])) / 2) + 1) then
                        output.write(lines[line_index])
                    else
                        output.write(" ")
                    end
                end
            else
                for i = 1, data.w do
                    output.write(" ")
                end
            end
        end

    end
    output.setTextColor(oldtc)
    output.setBackgroundColor(oldbg)
end

-- TODO: add filter to check for click on a specific monitor
-- Calls the function associated with a button and passes it
-- the output terminal, and relative x and y of the touch.
function checkButtons(handler, output)
    local event, side, x, y = os.pullEvent("monitor_touch")
    for name, data in pairs(handler) do
        if (x >= data.x and x <= data.x + data.w - 1) then
            if (y >= data.y and y <= data.y + data.h - 1) then
                data.func(output, x - data.x, y - data.y)
            end
        end
    end
end

function demoButtons()
    mon = peripheral.find("monitor")
    mon.clear()
    buttons = {}

    mon.setTextColor(colors.white)
    mon.setBackgroundColor(colors.black)

    local function test(output, relx, rely)
        term.redirect(output)
        print(string.format("Clicked button at %d, %d.", relx, rely))
    end

    makeButton(buttons, "1", "Demo", test, colors.green, 2, 2, 9, 3)

    makeButton(buttons, "error", "oh no!", test, colors.red, 20, 5, 8, 3)

    makeButton(buttons, "party", "Party time!", test, colors.pink, 40, 5, 19, 5)
    drawButtons(buttons, mon)
    while true do
        checkButtons(buttons, term.native())
    end
end

------------------------------------
-- UTILITY FUNCTIONS
------------------------------------

function countC(s, c)
    local count = 0
    for i in string.gmatch(s, c) do
        count = count + 1
    end
    return count
end

------------------------------------
-- MENUS 
------------------------------------

-- Deactivates the menu when the q key is pressed.
-- Note: This may not completely exit the program if
-- menu_init() was called inside something else.
function checkQuit(menu, output)
    event, key = os.pullEvent("key_up")
    if (key == keys.q) then
        quit(menu, output)
    end
end

function quit(menu, output)
    menu.active = false
    output.clear()
    term.clear()
    term.setCursorPos(1,1)
end


-- This output argument can be used ANYWHERE in the following code,
-- make a 'local output' if you want a different one
function menu_init(output) 

    ---- HELPER STUFF ----
    ----------------------

    -- first class functions !!

    -- Returns a function that swaps from one menu to another
    function swap_menu_f(cur, other)
        return function (output)
            cur.close(output)
            other.open(output)
        end
    end

    -- Returns a function that will open the given menu.
    -- Before updating the screen, it will call extra(output)
    function generic_open(menu, extra)
        return function (output)
            menu.active = true
            if (extra) then
                extra(output)
            end
            menu.update(output)

            -- wait for quit or button press
            while menu.active do 
                parallel.waitForAny(
                    function () checkQuit(menu, output) end,

                    -- Instead of 'output', you can set a different screen
                    -- where button output will appear, like term.native()
                    -- for logging purposes.
                    function () checkButtons(menu.buttons, output) end 
                )
            end 
            
        end
    end

    function generic_update(menu, extra)
        return function (output)
            output.setTextColor(colors.white)
            output.setBackgroundColor(colors.black)
            output.clear()
            drawButtons(menu.buttons, output)
            if (menu.header) then
                menu.header()
            end
            if (menu.footer) then
                menu.footer()
            end
            if (extra) then
                extra(output)
            end
        end

    end

    function generic_header(text, tcolor, bcolor)
        return function ()
            local oldbg = output.getBackgroundColor()
            local oldtc = output.getTextColor()
            local width, height = output.getSize()
            local startx = math.floor(width / 2 - (#text / 2))
            output.setBackgroundColor(bcolor or colors.black)
            output.setTextColor(tcolor or colors.white)
            output.setCursorPos(1, 1)
            for i = 1, width  do
                output.write(" ")                
            end
            output.setCursorPos(startx, 1)
            output.write(text)
            output.setBackgroundColor(oldbg)
            output.setTextColor(oldtc)
        end
    end
    
    function generic_footer(text, tcolor, bcolor)
        return function ()
            local oldbg = output.getBackgroundColor()
            local oldtc = output.getTextColor()
            local width, height = output.getSize()
            local startx = math.floor(width / 2 - (#text / 2))
            output.setBackgroundColor(bcolor or colors.black)
            output.setTextColor(tcolor or colors.white)
            output.setCursorPos(1, height)
            for i = 1, width  do
                output.write(" ")                
            end
            output.setCursorPos(startx, height)
            output.write(text)
            output.setBackgroundColor(oldbg)
            output.setTextColor(oldtc)
        end
    end

    function generic_close(menu)
        return function (output)
            menu.active = false
            output.clear()
        end
    end

    -------------------
    ---- MENU INIT ----

    main_menu = {}
    aim_menu = {}
    setup_menu = {}

    -------------------
    ---- MAIN MENU ----
    
    main_menu.header = generic_header("Cannon Controller", colors.red)
    main_menu.footer = generic_footer("Version: Bromeliad", colors.yellow)
    main_menu.active = false
    main_menu.buttons = {}
    local btns = main_menu.buttons

    makeButton(btns, "setup", "Setup", function () print("setup") end,
            colors.lime, 6, 9, 9, 3)
    makeButton(btns, "aim", "Aim", swap_menu_f(main_menu, aim_menu),
            colors.red, 17, 8, 7, 5)
    makeButton(btns, "history", "History", function () print("history") end,
            colors.lightBlue, 26, 9, 9, 3)

    makeButton(btns, "quit", "Quit", function () quit(main_menu, output) end,
            colors.gray, 2, 16, 6, 3)

    main_menu.open = generic_open(main_menu)

    main_menu.close = generic_close(main_menu)

    main_menu.update = generic_update(main_menu)

    ------------------
    ---- AIM MENU ---- 

    aim_menu.active = false
    aim_menu.buttons = {}
    aim_menu.selected = nil
    aim_menu.aim_mode = "exact"
    aim_menu.target = vector.new(0, 0, 0)
    btns = aim_menu.buttons

    local function num_panel(o, x, y)
        if (aim_menu.selected) then
            local btn = aim_menu.buttons[aim_menu.selected]
            local num = aim_menu.target[aim_menu.selected]
            local add = math.floor(x / 2 + 0.5) + 3 * (y - 1)
            if (add > 9) then
                add = 0
            end

            if (#tostring(num) < 7) then
                num = num * 10 + (num >= 0 and add or (add * -1))
            end
            aim_menu.target[aim_menu.selected] = num

            btn.text = string.sub(btn.text, 1, 2) .. 
            string.rep(" ", 7 - #tostring(num)) .. num
            aim_menu.update(output)
        end
    end

    local function clear_f(o)
        if (aim_menu.selected) then
            local btn = aim_menu.buttons[aim_menu.selected]

            aim_menu.target[aim_menu.selected] = 0
            btn.text = string.sub(btn.text, 1, 2) .. string.rep(" ", 6) .. 0
            aim_menu.update(output)
        end
    end

    local function backspace_f(o)
        if (aim_menu.selected) then
            local btn = aim_menu.buttons[aim_menu.selected]

            num = aim_menu.target[aim_menu.selected]

            if (num >= 0) then
                num = math.floor(aim_menu.target[aim_menu.selected] / 10)
            else 
                num = math.ceil(aim_menu.target[aim_menu.selected] / 10)
            end
            
            aim_menu.target[aim_menu.selected] = num
            
            btn.text = string.sub(btn.text, 1, 2) .. 
            string.rep(" ", 7 - #tostring(num)) .. num
            aim_menu.update(output)

        end
    end

    local function negate_f(o)
        if (aim_menu.selected) then
            local btn = aim_menu.buttons[aim_menu.selected]

            num = aim_menu.target[aim_menu.selected] * -1

            aim_menu.target[aim_menu.selected] = num

            btn.text = string.sub(btn.text, 1, 2) .. 
            string.rep(" ", 7 - #tostring(num)) .. num
            aim_menu.update(output)

        end
    end

    local function exact_f(o)
        aim_menu.aim_mode = "exact"
        aim_menu.buttons.exact.bgcolor = colors.white
        aim_menu.buttons.relative.bgcolor = colors.gray
        aim_menu.update(output)
    end

    local function relative_f(o)
        aim_menu.aim_mode = "relative"
        aim_menu.buttons.relative.bgcolor = colors.white
        aim_menu.buttons.exact.bgcolor = colors.gray
        aim_menu.update(output)
    end

    -- This is where the magic happens
    local function aim_f(o)
        x, y, z = aim_menu.target.x, aim_menu.target.y, aim_menu.target.z
        shell.execute("aim.lua", tostring(x), tostring(y), tostring(z),
                      "0", aim_menu.aim_mode or "exact")
        
        local failed = false
        -- Wait 1 second to see if the cannon failed to aim.
        parallel.waitForAny(
            function ()
                sleep(1)
            end,
            function () 
                local done = false
                    while (not done) do
                    event, result, dist = os.pullEvent()
                    if(event == "cannon_aim_failure") then
                        print("Couldn't aim at that target.")
                        print("Fake shot landed " .. dist .. 
                        (result == 1 and " past it." or " short."))
                        done = true
                    end
                    failed = true -- does Lua scope work like this?
                end
            end
        )
        -- Then wait for the cannon to aim successfully
        if (not failed) then
            local done = false
            while (not done) do
                event, result, dist = os.pullEvent()
                if(event == "cannon_aim_success") then
                    print("Cannon aimed at target.")
                    done = true
                end 
            end
        end

    end

    local function select_f(coord) 
        return function (o)
            local allbtns = 
            {aim_menu.buttons.x, aim_menu.buttons.y, aim_menu.buttons.z}
            for i, b in ipairs(allbtns) do
                b.txtcolor = colors.white
            end
            aim_menu.buttons[coord].txtcolor = colors.black
            aim_menu.selected = coord
            aim_menu.update(output)
        end

    end


    makeButton(btns, "relative", "Relative", relative_f,
               colors.gray, 8, 3, 10, 3)
    makeButton(btns, "exact", "Exact", exact_f,
               colors.gray, 23, 3, 9, 3)
    makeButton(btns, "x", "X:      0", select_f("x"),
               colors.red, 3, 7, 11, 3)
    makeButton(btns, "y", "Y:      0", select_f("y"),
               colors.green, 15, 7, 11, 3)
    makeButton(btns, "z", "Z:      0", select_f("z"),
               colors.blue, 27, 7, 11, 3)
    makeButton(btns, "numbers", "1 2 3\n4 5 6\n7 8 9\n  0  ", num_panel,
               colors.white, 17, 11, 7, 6)
    makeButton(btns, "negate", "Negate", negate_f,
               colors.gray, 25, 11, 8, 1)
    makeButton(btns, "backsp", "Backspace", backspace_f,
               colors.gray, 25, 13, 11, 1)
    makeButton(btns, "clear", "Clear", clear_f,
               colors.gray, 25, 15, 7, 1)
                                  
    makeButton(btns, "fire", "Aim at\nTarget", aim_f,
               colors.orange, 5, 12, 10, 4)

    makeButton(btns, "back", "Back", swap_menu_f(aim_menu, main_menu),
               colors.red, 1, 18, 4, 3)

    
    aim_menu.open = generic_open(aim_menu, 
    function (o) 
        aim_menu.selected = nil 
        aim_menu.aim_mode = nil 
        aim_menu.buttons.relative.bgcolor = colors.gray
        aim_menu.buttons.exact.bgcolor = colors.gray
    end)

    aim_menu.close = generic_close(aim_menu)

    aim_menu.update = generic_update(aim_menu)

    ------------------------
    ---- OPEN MAIN MENU ----
    main_menu.open(output)
end

------------------------------------
-- MAIN PROGRAM CODE
------------------------------------

-- TODO: Add terminal mode that can take keyboard input

mon = peripheral.find("monitor")
print("Press 'q' to quit.")
menu_init(mon)
-- demoButtons()
