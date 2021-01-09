local interface = peripheral.wrap("back")
local canvas = interface.canvas()
canvas.clear()

local titlebarHeight = 8  -- Height of the titlebar, same for every window
local nextWindowID = 0 -- ID for the next created window, constantly incrementing

windows = {} -- Table of windows, stored as ID:Window

-- Check if the (x, y) point is within the given rectangle
function inSquare(x, y, startX, startY, width, height)
    return ((x > startX and x < startX + width) and (y > startY and y < startY + height))
end

local clickWithinClose = -1 -- Close happens on release, make sure the press was also on the same close button
local selected = -1 -- ID of window being dragged
local lastPosX = 0  -- Mouse x position from the previous drag event
local lastPosY = 0  -- Mouse y position from the previous drag event

-- Create a window with the given title, position and size (size does not include the titlebar)
function addWindow(title, posX, posY, sizeX, sizeY)
    -- Draw the window
    local group = canvas.addGroup({posX, posY})
    local window = group.addRectangle(0, titlebarHeight, sizeX, sizeY, 0x222222FF)
    local titlebar = group.addRectangle(0, 0, sizeX, titlebarHeight, 0x111111FF)
    local title = group.addText({1, 1}, title, 0x444444FF, 0.8)
    local buttonClose = group.addRectangle(sizeX - titlebarHeight + 1, 1, titlebarHeight - 2, titlebarHeight - 2, 0x111111FF)
    group.addLine({sizeX - titlebarHeight + 2, 2}, {sizeX - 2, titlebarHeight - 2}, 0x444444FF, 5)
    group.addLine({sizeX - titlebarHeight + 2, titlebarHeight - 2}, {sizeX - 2, 2}, 0x444444FF, 5)

    -- Add it to the table of windows
    windows[nextWindowID] = {
        Group = group,
        Window = window,
        Titlebar = titlebar,
        Title = title,
        ButtonClose = buttonClose
    }

    -- Increment the ID
    nextWindowID = nextWindowID + 1
    return nextWindowID - 1
end

addWindow("Title", 10, 10, 80, 40)
addWindow("Title2", 100, 10, 40, 40)
addWindow("Title3", 10, 60, 40, 80)

while true do
    local name, index, x, y = os.pullEvent()

    if name == "glasses_click" and index == 1 then
        -- Clear the selected value in case glasses_up wasn't caught
        selected = -1
        lastPosX = 0
        lastPosY = 0

        for ID, window in pairs(windows) do
            local groupX, groupY = window["Group"].getPosition()
    
            local butX, butY = window["ButtonClose"].getPosition()
            local butW, butH = window["ButtonClose"].getSize()
            if inSquare(x, y, butX + groupX, butY + groupY, butW, butH) then
                clickWithinClose = ID
                break
            else
                local titleX, titleY = window["Titlebar"].getPosition()
                local titleW, titleH = window["Titlebar"].getSize()
                if inSquare(x, y, titleX + groupX, titleY + groupY, titleW, titleH) then
                    selected = ID
                    lastPosX = x
                    lastPosY = y
                    break
                end
            end
        end        

    end

    if name == "glasses_up" and index == 1 then
        -- Clear the selected value
        selected = -1
        lastPosX = 0
        lastPosY = 0

        if clickWithinClose ~= -1 then
            local groupX, groupY = windows[clickWithinClose]["Group"].getPosition()

            local butX, butY = windows[clickWithinClose]["ButtonClose"].getPosition()
            local butW, butH = windows[clickWithinClose]["ButtonClose"].getSize()
            if inSquare(x, y, butX + groupX, butY + groupY, butW, butH) then
                windows[clickWithinClose]["Group"].remove() -- close this window
                windows[clickWithinClose] = nil
            end

            clickWithinClose = -1
        end
    end

    if name == "glasses_drag" and index == 1 and selected ~= -1 then
        local groupX, groupY = windows[selected]["Group"].getPosition()

        local deltaX = x - lastPosX
        local deltaY = y - lastPosY

        windows[selected]["Group"].setPosition(groupX + deltaX, groupY + deltaY)

        lastPosX = x
        lastPosY = y
    end
end    


-- A window is a table with the following values:
--   Group - the window group itself
--   Window - reference to the background rectangle, which is used to display the window's size (and for input events)
--   Titlebar - reference to the window's titlebar
--   ButtonClose - reference to the close button
--
-- On a glasses_click event, the window manager goes over every window group's Window, and checks if the input event happened within it
--   If it did, it checks if it happened within that window's Titlebar
--     If it did, it checks if it happened within that window's Close Button
--       If it did, it sends the close event to that program and removes that window
--       If it did not, it marks that window as "selected", and starts listening for glasses_drag events, moving the window according to their coordinates
--     If it did not, it sends the event and all the glasses_* events after it to the program that window belongs to, until a glasses_up event is received (event positions are adjusted to be relative to the window)
--   If it did not, the event is ignored
--
-- Window manager events:
-- program_terminate id - sent by the window manager when a window is closed, index is the program's associated with that window ID
-- window_close id - sent by the program to window manager, requesting to close the window with ID
-- glasses_down, glasses_drag, glasses_up, glasses_scroll, key, key_up - retransmitted to the program of the active window if did not happen on the titlebar or close button

