local programSizeX = 100
local programSizeY = 15
local title = "Run"
local entry = nil
local status = nil
local programGroup = nil
local ID = ...
if ID == nil then error("No ID given") end

local function drawProgram(group)
    --group.addText({0.2, 1}, "Run: ", 0xEEEEEEFF, 0.8)
    group.addRectangle(1, 1, programSizeX - 2, programSizeY - 6, 0xEEEEEEFF)
    entry = group.addText({1.2, 1.5}, "", 0x000000FF, 0.8)
    status = group.addText({1.2, 10.8}, "Enter filename", 0xDD0000FF, 0.4)
end

local function validateFilename()
    if entry.getText() == "" then
        status.setColor(0xDD0000FF)
        status.setText("Enter filename")
        return false
    end

    if not fs.exists(entry.getText()) then
        status.setColor(0xDD0000FF)
        status.setText("File not found")
        return false
    else
        status.setColor(0x00DD00FF)
        status.setText("File exists")
        return true
    end
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
        if val1 == 14 then -- Backspace
            entry.setText(entry.getText():sub(1, -2))
            validateFilename()
        end

        if val1 == 28 then
            if validateFilename() then
                os.queueEvent("program_launch", entry.getText())
                os.queueEvent("program_close", ID)
                return true
            else
                return false
            end
        end

        return false
    end

    if name == "wm_char" then
        entry.setText(entry.getText() .. val1)
        validateFilename()
    end

    return false
end

os.queueEvent("program_create", ID, programSizeX, programSizeY, title)

while true do 
    if handleEvents() then break end
end