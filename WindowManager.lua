local glasses = peripheral.wrap("back")
local canvas = glasses.canvas()
canvas.clear()

local titlebarHeight = 8  -- Height of the titlebar, same for every window
local nextWindowID = 1 -- ID for the next created window, constantly incrementing

programGroups = {} -- Table storing newly created groups, used to pass them from the WM to programs. Stored as ID:Group
local windows = {} -- Table of windows. Stored as ID:Window
local launchedPrograms = {} -- Table storing program paths and their ID's, so the WM would know which exact program is requesting a window to be created. Stored as ID:Path
local windowPositions = {} -- Table storing saved window positions. Stored as Filename:{x, y}

local clickWithinClose = -1 -- Close happens on mouse release, this makes sure the press was also on the same close button
local activeID = -1 -- ID of the currently active window (will have key inputs passed into it)
local draggingID = -1 -- ID of window being dragged
local lastPosX = 0  -- Mouse x position from the previous drag event
local lastPosY = 0  -- Mouse y position from the previous drag event

local autosaveTimerID = 0 -- ID of the timer used for autosaving
local autosaveInterval = 5 -- Saves the window position and open program data every n seconds

local ctrlDown = false -- Used for shortcuts (currently only ctrl + r -> Run)

local debug = ...
if debug == nil then debug = false else debug = true end

--                  = = = = = = = = = = = = = = = = = = = = = = = =  P U B L I C   F U N C T I O N S  = = = = = = = = = = = = = = = = = = = = = = = =

-- Checks if the (x, y) point is within the given rectangle.
-- IN: Point x, y, Rectangle start x, y, Rectangle width, height.
-- OUT: Bool is point within rectangle.
function inRectangle(x, y, startX, startY, width, height)
    return ((x > startX and x < startX + width) and (y > startY and y < startY + height))
end


-- Check if click happened in the given window (rectangle).
-- IN: Click x, y, group that window belongs to, window itself.
-- OUT: Bool is click within window.
function clickedInWindow(clickX, clickY, group, window)
    local groupX, groupY = group.getPosition()

    local winX, winY = window.getPosition()
    local winW, winH = window.getSize()
    return inRectangle(clickX, clickY, winX + groupX, winY + groupY, winW, winH)
end


-- Extract the filename from the given path.
-- IN: File path.
-- OUT: Filename.
function filenameFromPath(path)
    return string.match(path, "([^/]-)$")
end

-- Extract the path from the given path+filename string.
-- IN: File path + filename.
-- OUT: Path.
function pathFromFullPath(path)
    return string.match(path, "(.-)[^/]-[^/%.]+$")
end

--                 = = = = = = = = = = = = = = = = = = = = = = = =  W I N D O W   F U N C T I O N S  = = = = = = = = = = = = = = = = = = = = = = = =

-- Create a window.
-- IN: Window title, unique ID, position x, y, width, height (height is for main window, doesn't include titlebar).
-- OUT: -
-- SE: Adds the created window to the [windows] table.
local function addWindow(title, id, posX, posY, width, height)
    -- Draw the window
    local group = canvas.addGroup({posX, posY})
    local window = group.addRectangle(0, titlebarHeight, width, height, 0x222222FF)
    local titlebar = group.addRectangle(0, 0, width, titlebarHeight, 0x111111FF)
    local title = group.addText({1, 1}, title, 0x444444FF, 0.8)
    
    -- Draw the close button
    local closeButtonX = width - titlebarHeight
    local close = group.addRectangle(closeButtonX, 0, titlebarHeight, titlebarHeight, 0x111111FF)
    group.addLine({closeButtonX + 2, 2}, {width - 2, titlebarHeight - 2}, 0x444444FF, 5)
    group.addLine({closeButtonX + 2, titlebarHeight - 2}, {width - 2, 2}, 0x444444FF, 5)

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


-- Close window.
-- IN: Window ID.
-- OUT: -
-- SE: Closes and removes window from [windows] table.
--     Saves closed window's position.
local function closeWindow(id)
    windowPositions[filenameFromPath(windows[id]["Path"])] = {windows[id]["Group"].getPosition()} -- Save last window position
    windows[id]["Group"].remove() -- Remove window from UI
    windows[id] = nil -- Remove window from windows table
end


-- Clears the active window. The active window receives key inputs.
-- IN: -
-- OUT: -
-- SE: Updates the [activeID] index.
--     Removes the highlight from the active window.
local function clearActiveWindow()
    if activeID == -1 then
        return
    end

    local window = windows[activeID]
    if window ~= nil and window["Active"] ~= nil then
        window["Active"].remove()
        window["Active"] = nil
    end

    activeID = -1
end


-- Sets the active window. The active window receives key inputs.
-- IN: New active window id.
-- OUT: -
-- SE: Updates the [activeID] index.
--     Adds the highlight to the active window.
local function setActiveWindow(id)
    if activeID == id then
        return
    end

    if activeID ~= -1 then
        clearActiveWindow()
    end

    local window = windows[id]
    local sizeX, sizeY = windows[id]["Window"].getSize()
    windows[id]["Active"] = windows[id]["Group"].addLines({0, 0}, {sizeX, 0}, {sizeX, sizeY + titlebarHeight}, {0, sizeY + titlebarHeight}, 0xFFFFFFFF, 1)

    activeID = id
end

--          = = = = = = = = = = = = = = = = = = = = = = = =  P R O G R A M   L A U N C H   F U N C T I O N S  = = = = = = = = = = = = = = = = = = = = = = = =

-- Launch a new program.
-- IN: Program's full path.
-- OUT: -
-- SE: Launches a new program.
--     Saves the program's path in [launchedPrograms].
local function launchProgram(path)
    -- Launch program
    local tempID = multishell.launch(getfenv(), path, nextWindowID)
    launchedPrograms[nextWindowID] = path

    -- Switch to the opened program and back, otherwise the program would close with "Press any key to continue" message
    -- This will also not show program error messages, so don't do this in debug mode
    if not debug then 
        multishell.setFocus(tempID)
        multishell.setFocus(multishell.getCurrent())
    end

    -- Increment ID
    nextWindowID = nextWindowID + 1
end

--      = = = = = = = = = = = = = = = = = = = = = = = =  S A V I N G   A N D   L O A D I N G   F U N C T I O N S  = = = = = = = = = = = = = = = = = = = = = = = =

-- Loads all saved window positions.
-- IN: -
-- OUT: -
-- SE: Clears and fills the [windowPositions] table.
local function loadWindowPositions()
    if not fs.exists("WindowPositions") then
        return
    end

    windowPositions = {}

    local file = fs.open("WindowPositions", "r")
    local line = file.readLine()
    while line ~= nil do
        local program, x, y = string.match(line, "(%S+)%s+(%d+)%s+(%d+)") -- Extracts data in format (path x y)
        if program ~= nil and x ~= nil and y ~= nil then
            windowPositions[program] = {tonumber(x), tonumber(y)}
        end

        line = file.readLine()
    end

    file.close()
end


-- Updates the [windowPositions] table with currently open window positions.
-- IN: -
-- OUT: -
-- SE: Updates [windowPositions] table.
local function updateWindowPositions()
    for ID, window in pairs(windows) do
        windowPositions[filenameFromPath(window["Path"])] = {window["Group"].getPosition()}
    end
end


-- Saves the contents of [windowPositions] to a file.
-- IN: -
-- OUT: -
-- SE: Writes to file "WindowPositions".
local function saveWindowPositions()
    updateWindowPositions()

    local file = fs.open("WindowPositions", "w")

    for program, position in pairs(windowPositions) do
        file.writeLine(program .. " " .. tostring(position[1]) .. " " .. tostring(position[2]))
    end

    file.close()
end


-- Recovers all programs that were open before WM shutdown.
-- IN: -
-- OUT: -
-- SE: Launches multiple programs.
local function loadOpenPrograms()
    if not fs.exists("OpenedPrograms") then
        return
    end

    local file = fs.open("OpenedPrograms", "r")
    local line = file.readLine()
    while line ~= nil do
        if fs.exists(line) then
            launchProgram(line)
        end

        line = file.readLine()
    end

    file.close()
end


-- Saves the currently open programs to a file.
-- IN: -
-- OUT: -
-- SE: Writes to file "OpenedPrograms".
local function saveOpenPrograms()
    local file = fs.open("OpenedPrograms", "w")

    for ID, window in pairs(windows) do
        file.writeLine(window["Path"])
    end

    file.close()
end

--       = = = = = = = = = = = = = = = = = = = = = = = =  E V E N T   H A N D L I N G   F U N C T I O N S  = = = = = = = = = = = = = = = = = = = = = = = =

-- Retransmit mouse events to open windows.
-- This function goes over every open window and sends the mouse event to the one that the event happened in.
-- IN: Event name, mouse button index, event position x, y, [window id].
-- OUT: Returns the found window's ID, or -1 if no window was found.
-- SE: Sends out events to programs.
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

    -- Send the event to the program
    local groupX, groupY = windows[id]["Group"].getPosition()
    os.queueEvent(name, id, index, x - groupX, y - groupY)
    return id
end


-- Handle the "glasses_click" event.
-- IN: Mouse button index, event position x, y.
-- OUT: -
-- SE: Sets/clears active windows.
--     Sets/clears [draggingID] value.
local function handleGlassesClick(index, x, y)
    if index == 1 then
        -- Clear the values in case glasses_up wasn't caught
        clickWithinClose = -1
        draggingID = -1
        lastPosX = 0
        lastPosY = 0
    end

    for ID, window in pairs(windows) do
        -- Clicked on the X button, mark it for when glasses_up event arrives
        if index == 1 and clickedInWindow(x, y, window["Group"], window["Close"]) then
            setActiveWindow(ID)
            clickWithinClose = ID
            return
        end

        -- Clicked on the titlebar, prepare for dragging
        if index == 1 and clickedInWindow(x, y, window["Group"], window["Titlebar"]) then
            setActiveWindow(ID)
            draggingID = ID
            lastPosX = x
            lastPosY = y
            return
        end
    end

    local id = retransmitMouseEvent("wm_glasses_click", index, x, y)
    if id ~= -1 then
        setActiveWindow(id)
    else
        clearActiveWindow()
    end
end


-- Handle the "glasses_up" event.
-- IN: Mouse button index, event position x, y.
-- OUT: -
-- SE: Closes windows.
--     Sets/clears [draggingID] value.
local function handleGlassesUp(index, x, y)
    -- Stop dragging
    if index == 1 and draggingID ~= -1 then
        draggingID = -1
        lastPosX = 0
        lastPosY = 0
        return -- Do not retransmit the release to the programs because the click happened on the titlebar
    end

    -- Try to check if release happened within the same close button as the click
    if index == 1 and clickWithinClose ~= -1 then
        local window = windows[clickWithinClose]
        if clickedInWindow(x, y, window["Group"], window["Close"]) then
            os.queueEvent("wm_terminate", clickWithinClose)
            closeWindow(clickWithinClose)
        end

        clickWithinClose = -1
        return -- Do not retransmit the release to the programs because the click happened on the close button
    end

    retransmitMouseEvent("wm_glasses_up", index, x, y)
end


-- Handle the "glasses_drag" event.
-- IN: Mouse button index, event position x, y.
-- OUT: -
-- SE: Moves windows.
local function handleGlassesDrag(index, x, y)
    -- Do the dragging
    if index == 1 and draggingID ~= -1 then
        local groupX, groupY = windows[draggingID]["Group"].getPosition()

        local deltaX = x - lastPosX
        local deltaY = y - lastPosY

        windows[draggingID]["Group"].setPosition(groupX + deltaX, groupY + deltaY)

        lastPosX = x
        lastPosY = y

        return
    end

    retransmitMouseEvent("wm_glasses_drag", index, x, y)
end


-- Creates a new window in response to a program's request.
-- IN: Program's ID, requested window size x, y, title.
-- OUT: -
-- SE: Creates new window.
--     Sets the window active if it's the Run.lua program.
--     Notifies the program that it's window is ready.
local function createWindowForProgram(id, sizeX, sizeY, title)
    -- Find real program name
    local programPath = launchedPrograms[id]
    local programName = filenameFromPath(launchedPrograms[id])

    -- Try to load the last saved position for this program
    local posX, posY = 0, 0
    if windowPositions[programName] ~= nil then
        posX = windowPositions[programName][1]
        posY = windowPositions[programName][2]
    end

    -- Create the window
    addWindow(title, id, posX, posY, sizeX, sizeY)
    windows[id]["Path"] = programPath

    -- If this is the "Run" program, make it active
    if programName == "Run.lua" then
        setActiveWindow(id)
    end

    -- Notify the program that it's window has been created
    programGroups[id] = windows[id]["ProgramGroup"]
    os.queueEvent("wm_created", id)
end


-- Resizes window in response to a program's request.
-- It does this by removing the old window and creating a new one.
-- IN: Program's ID, new window size x, y.
-- OUT: -
-- SE: Deletes old window, creates a new one.
--     Notifies the program that it's window is ready. 
local function resizeWindow(id, sizeX, sizeY)
    -- Save position and title
    local posX, posY = windows[id]["Group"].getPosition()
    local title = windows[id]["Title"].getText()

    -- Delete existing window
    windows[id]["Group"].remove()
    windows[id] = nil

    -- Create the new window
    addWindow(title, id, posX, posY, sizeX, sizeY)
    windows[id]["Path"] = launchedPrograms[id]

    -- Notify the program that it's window has been created
    programGroups[id] = windows[id]["ProgramGroup"]
    os.queueEvent("wm_created", id)
end

--               = = = = = = = = = = = = = = = = = = = = = = = =  M A I N   F U N C T I O N S  = = = = = = = = = = = = = = = = = = = = = = = =

-- Main event handler.
-- IN: -
-- OUT: True if program should close, False if it can continue.
-- SE: Touches every part of the program, as this is the main event loop.
local function handleEvents()
    local name, index, x, y, extra = os.pullEventRaw()

    -- Terminate event - send terminate events to all running programs and then stop the WM
    if name == "terminate" then
        saveWindowPositions()
        saveOpenPrograms()

        for ID, window in pairs(windows) do
            os.queueEvent("wm_terminate", ID)
        end
        canvas.clear()

        return true
    end

    -- Autosave timer event
    if name == "timer" and index == autosaveTimerID then
        saveWindowPositions()
        saveOpenPrograms()

        autosaveTimerID = os.startTimer(autosaveInterval)
        return false
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
        -- Left ctrl pressed
        if index == 29 and not ctrlDown then
            ctrlDown = true
        end

        -- R pressed
        if index == 19 and ctrlDown then
            local path = pathFromFullPath(shell.getRunningProgram())
            launchProgram(path .. "Run.lua")
            return false
        end

        if activeID ~= -1 then
            os.queueEvent("wm_key", activeID, index, x)
        end
        return false
    end

    if name == "key_up" then
        -- Left ctrl released
        if index == 29 and ctrlDown then
            ctrlDown = false
        end

        if activeID ~= -1 then
            os.queueEvent("wm_key_up", activeID, index)
        end
        return false
    end

    if name == "char" then
        if activeID ~= -1 then
            os.queueEvent("wm_char", activeID, index)
        end
        return false
    end
    
    -- Program events
    if name == "program_create" then
        createWindowForProgram(index, x, y, extra)
        return false
    end

    if name == "program_close" then
        closeWindow(index)
        return false
    end

    if name == "program_resize" then
        resizeWindow(index, x, y)
        return false
    end

    if name == "program_launch" then
        launchProgram(index)
        return false
    end

    return false
end    

-- Program starts here, load saved data and start autosave timer
loadWindowPositions()
loadOpenPrograms()
autosaveTimerID = os.startTimer(autosaveInterval)

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
--   Active* - active window mark (added by the select/deselect functions)
--   Path* - associated program's full pathname (added after opening window)
--
-- Events:
--   Events sent by the program to the WM:
--     program_create id sizeX sizeY title - request to create a new window with given id, size and title
--     program_close id - request to close the window with ID
--     program_resize id sizeX sizeY - request to resize the window with given id to size
--     program_launch name - request to launch a program
--   Events sent by the WM to the programs:
--     wm_created id - sent when a window is created, the group is stored in the global programGroups variable
--     wm_terminate id - sent when a window is closed, requesting program to close
--     wm_glasses_click, wm_glasses_drag, wm_glasses_up, wm_glasses_scroll, wm_key, wm_key_up, wm_char - 
--                                    retransmitted to the program of the active window if did not happen on the titlebar. 
--                                    Same arguments as the regular function, but the first one is id of window it is directed at.
--
-- Global WM functions:
--   inRectangle
--   clickedInWindow
--   filenameFromPath
--   pathFromFullPath
--
-- Global WM variables:
--   programGroups
--
-- TODO: Add some way to support loading multiple of the same window with different locations after shutdown?
