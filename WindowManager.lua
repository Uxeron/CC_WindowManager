local glasses = peripheral.wrap("back")
local canvas = glasses.canvas()
canvas.clear()

local titlebarHeight = 8  -- Height of the titlebar, same for every window
local nextWindowID = 1 -- ID for the next created window, constantly incrementing

local windows = {} -- Table of windows, stored as ID:Window

programGroups = {} -- Table storing newly create groups, used to pass them from the WM to programs

local clickWithinClose = -1 -- Close happens on release, make sure the press was also on the same close button
local active = -1 -- ID of window currently active (will have key/mouse inputs passed into it)
local selected = -1 -- ID of window being dragged
local lastPosX = 0  -- Mouse x position from the previous drag event
local lastPosY = 0  -- Mouse y position from the previous drag event


-- Check if the (x, y) point is within the given rectangle
function inSquare(x, y, startX, startY, width, height)
    return ((x > startX and x < startX + width) and (y > startY and y < startY + height))
end

-- Check if click happened in the given window (rectangle)
function clickedInWindow(clickX, clickY, group, window)
    local groupX, groupY = group.getPosition()

    local winX, winY = window.getPosition()
    local winW, winH = window.getSize()
    return inSquare(clickX, clickY, winX + groupX, winY + groupY, winW, winH)
end

-- Create a window with the given title, position and size (size does not include the titlebar)
local function addWindow(title, id, posX, posY, sizeX, sizeY)
    -- Draw the window
    local group = canvas.addGroup({posX, posY})
    local window = group.addRectangle(0, titlebarHeight, sizeX, sizeY, 0x222222FF)
    local titlebar = group.addRectangle(0, 0, sizeX, titlebarHeight, 0x111111FF)
    local title = group.addText({1, 1}, title, 0x444444FF, 0.8)
    
    -- Draw the close button
    local closeButtonX = sizeX - titlebarHeight
    local close = group.addRectangle(closeButtonX, 0, titlebarHeight, titlebarHeight, 0x111111FF)
    group.addLine({closeButtonX + 2, 2}, {sizeX - 2, titlebarHeight - 2}, 0x444444FF, 5)
    group.addLine({closeButtonX + 2, titlebarHeight - 2}, {sizeX - 2, 2}, 0x444444FF, 5)

    -- Add the group for the program to draw to
    local programGroup = group.addGroup({0, titlebarHeight})

    -- Add it to the table of windows
    windows[id] = {
        Group = group,
        ProgramGroup = programGroup,
        Window = window,
        Titlebar = titlebar,
        Title = title,
        Close = close
    }
end

local function deselectWindow()
    if active == -1 then
        return
    end

    local window = windows[active]
    if window ~= nil and window["Selection"] ~= nil then
        window["Selection"].remove()
        window["Selection"] = nil
    end

    active = -1
end

local function selectWindow(id)
    if active == id then
        return
    end

    if active ~= -1 then
        deselectWindow()
    end

    local window = windows[id]
    local sizeX, sizeY = windows[id]["Window"].getSize()
    local selection = windows[id]["Group"].addLines({0, 0}, {sizeX, 0}, {sizeX, sizeY + titlebarHeight}, {0, sizeY + titlebarHeight}, 0xFFFFFFFF, 1)
    windows[id]["Selection"] = selection

    active = id
end

-- Launch a new program with the given name
local function launchProgram(name)
    -- Launch program
    local tempID = multishell.launch(getfenv(), name, nextWindowID)

    -- Switch to the opened program and back, otherwise the program would close with "Press any key to continue" message
    multishell.setFocus(tempID)
    multishell.setFocus(multishell.getCurrent())

    -- Increment ID
    nextWindowID = nextWindowID + 1
end

-- Try to find if the mouse event happened within any of the open windows and retransmit the event to it
local function retransmitMouseEvent(name, index, x, y, id)
    id = id or -1 -- Default value

    -- Search for a window
    if id == -1 then
        for ID, window in pairs(windows) do
            if clickedInWindow(x, y, window["Group"], window["Window"]) then
                id = ID
                break
            end
        end
    end

    -- No window was found
    if id == -1 then
        return -1
    end

    local groupX, groupY = windows[id]["Group"].getPosition()
    os.queueEvent(name, id, index, x - groupX, y - groupY)
    return id
end

-- Handle the "glasses_click" event
local function handleGlassesClick(index, x, y)
    if index == 1 then
        -- Clear the values in case glasses_up wasn't caught
        clickWithinClose = -1
        selected = -1
        lastPosX = 0
        lastPosY = 0
    end

    for ID, window in pairs(windows) do
        -- Clicked on the X button, mark it for when glasses_up event arrives
        if index == 1 and clickedInWindow(x, y, window["Group"], window["Close"]) then
            selectWindow(ID)
            clickWithinClose = ID
            return
        end

        -- Clicked on the titlebar, prepare for dragging
        if index == 1 and clickedInWindow(x, y, window["Group"], window["Titlebar"]) then
            selectWindow(ID)
            selected = ID
            lastPosX = x
            lastPosY = y
            return
        end
    end

    local id = retransmitMouseEvent("wm_glasses_click", index, x, y)
    if id ~= -1 then
        selectWindow(id)
    else
        deselectWindow()
    end
end

-- Handle the "glasses_up" event
local function handleGlassesUp(index, x, y)
    -- Stop dragging
    if index == 1 and selected ~= -1 then
        selected = -1
        lastPosX = 0
        lastPosY = 0
        return -- Do not retransmit the release to the programs because the click happened on the titlebar
    end

    -- Try to check if release happened within the same close button as the click
    if index == 1 and clickWithinClose ~= -1 then
        local window = windows[clickWithinClose]
        if clickedInWindow(x, y, window["Group"], window["Close"]) then
            os.queueEvent("wm_terminate", clickWithinClose)
            window["Group"].remove() -- close this window
            windows[clickWithinClose] = nil
        end

        clickWithinClose = -1
        return -- Do not retransmit the release to the programs because the click happened on the close button
    end

    retransmitMouseEvent("wm_glasses_up", index, x, y)
end

-- Handle the "glasses_drag" event
local function handleGlassesDrag(index, x, y)
    -- Do the dragging
    if index == 1 and selected ~= -1 then
        local groupX, groupY = windows[selected]["Group"].getPosition()

        local deltaX = x - lastPosX
        local deltaY = y - lastPosY

        windows[selected]["Group"].setPosition(groupX + deltaX, groupY + deltaY)

        lastPosX = x
        lastPosY = y

        return
    end

    retransmitMouseEvent("wm_glasses_drag", index, x, y)
end


-- Event handler
local function handleEvents()
    local name, index, x, y, extra = os.pullEventRaw()

    -- Terminate event - send terminate events to all running programs and then stop the WM
    if name == "terminate" then
        for ID, window in pairs(windows) do
            os.queueEvent("wm_terminate", ID)
        end
        canvas.clear()

        return true
    end

    -- Mouse events
    if name == "glasses_click" then
        handleGlassesClick(index, x, y)
        return false
    end

    if name == "glasses_up" then
        handleGlassesUp(index, x, y)
        return false
    end

    if name == "glasses_drag" then
        handleGlassesDrag(index, x, y)
        return false
    end

    if name == "glasses_scroll" then
        retransmitMouseEvent("wm_glasses_scroll", index, x, y)
        return false
    end

    -- Keyboard events
    if name == "key" then
        if active ~= -1 then
            os.queueEvent("wm_key", active, index, x)
        end
        return false
    end

    if name == "key_up" then
        if active ~= -1 then
            os.queueEvent("wm_key_up", active, index)
        end
        return false
    end

    if name == "char" then
        if active ~= -1 then
            os.queueEvent("wm_char", active, index)
        end
        return false
    end
    
    -- Program events
    if name == "program_create" then
        addWindow(extra, index, 0, 0, x, y)
        programGroups[index] = windows[index]["ProgramGroup"]
        os.queueEvent("wm_created", index)
        return false
    end

    if name == "program_close" then
        windows[index]["Group"].remove()
        windows[index] = nil
        return false
    end

    if name == "program_resize" then
        local title = windows[index]["Title"].getText()
        windows[index]["Group"].remove()
        windows[index] = nil
        addWindow(title, index, 0, 0, x, y)
        programGroups[index] = windows[index]["ProgramGroup"]
        os.queueEvent("wm_created", index)
    end

    return false
end    

launchProgram("TestProgram.lua")

-- Main event loop
while true do 
    if handleEvents() then break end
end


-- A window is a table with the following values:
--   Group - the window group itself
--   ProgramGroup - group to which the program can draw
--   Window - reference to the background rectangle, which is used to display the window's size (and for input events)
--   Titlebar - reference to the window's titlebar
--   Title - reference to the window's title
--   Close - reference to the close button
--
-- On a glasses_click event, the window manager goes over every window group's Window, and checks if the input event happened within it
--   If it did, it checks if it happened within that window's Titlebar
--     If it did, it checks if it happened within that window's Close Button
--       If it did, it sends the close event to that program and removes that window
--       If it did not, it marks that window as "selected", and starts listening for glasses_drag events, moving the window according to their coordinates
--     If it did not, it sends the event and all the glasses_* events after it to the program that window belongs to, until a glasses_up event is received (event positions are adjusted to be relative to the window)
--   If it did not, the event is ignored
--
-- Events:
--   Events sent by the program to the WM:
--     program_create id sizeX sizeY title - request to create a new window with given id, size and title
--     program_close id - request to close the window with ID
--     program_resize id sizeX sizeY - request to resize the window with given id to size
--   Events sent by the WM to the programs:
--     wm_created id - sent when a window is created, the group is stored in the global programGroups variable
--     wm_terminate id - sent when a window is closed, requesting program to close
--     wm_glasses_click, wm_glasses_drag, wm_glasses_up, wm_glasses_scroll, wm_key, wm_key_up, wm_char - 
--                                    retransmitted to the program of the active window if did not happen on the titlebar or close button. 
--                                    Same arguments as the regular function, but the first one is id of window it is directed at
--
-- Global WM functions:
--   inSquare
--   clickedInWindow
--
-- Global WM variables:
--   programGroups
