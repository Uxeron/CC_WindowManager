local programSizeX = 40
local programSizeY = 40
local title = "Prog!"
local programGroup = nil
local label = nil
local button = nil
local buttonPressed = false
local ID = ...

if ID == nil then error("No ID given") end

local function drawProgram(group)
    group.addRectangle(5, 5, programSizeX - 10, programSizeY - 10, 0xEE0000FF)
    group.addRectangle(10, 10, programSizeX - 20, programSizeY - 20, 0x00EE00FF)
    group.addRectangle(15, 15, programSizeX - 30, programSizeY - 30, 0x0000EEFF)
    label = group.addText({0, 0}, "Enter text", 0xFFFFFFFF, 0.6)
    button = group.addRectangle(15, 33, 10, 5, 0xEEEE00FF)
    group.addText({15.1, 34}, "Click!", 0x000000FF, 0.4)
end

local function handleEvents()
    local name, index, val1, val2, val3 = os.pullEvent()

    if index ~= ID then
        return false
    end

    if name == "wm_created" then
        programGroup = programGroups[ID]
        programGroups[ID] = nil
        drawProgram(programGroup)
        return false
    end

    if name == "wm_terminate" then
        return true
    end

    if name == "wm_key" then
        if val1 == 14 then
            label.setText(label.getText():sub(1, -2))
        end
        return false
    end

    if name == "wm_char" then
        label.setText(label.getText() .. val1)
    end

    if name == "wm_glasses_click" and val1 == 1 then
        if clickedInWindow(val2, val3, programGroup, button) then
            buttonPressed = not buttonPressed
            if buttonPressed then
                button.setColor(0x00EEEEFF)
            else
                button.setColor(0xEEEE00FF)
            end
        end
        return false
    end

    return false
end

os.queueEvent("program_create", ID, programSizeX, programSizeY, title)

while true do 
    if handleEvents() then break end
end