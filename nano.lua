local filesystem = require "system.filesystem"
local framebuffer = require "system.framebuffer"
local keys = require "system.keys"
local terminal = require "system.terminal"
local util = require "system.util"

local VERSION = "0.1"
local args = assert(util.argparse({}, ...))

local shiftMap = {
    [keys.leftBracket] = '{',
    [keys.rightBracket] = '}',
    [keys.minus] = '_',
    [keys.nine] = '(',
    [keys.zero] = ')',
    [keys.semicolon] = ':',
    [keys.up] = '\24',
    [keys.down] = '\25',
    [keys.left] = '\27',
    [keys.right] = '\26'
}

local shortcuts, mainShortcuts
local term = assert(terminal.openterm())
local oldctl = terminal.termctl()
terminal.termctl{raw = true}
local width, height = term.getSize()
local filename = args[1]
local lines = {}
local topLine = 1
local cursorX, cursorY = 1, 1
local win = framebuffer.window(term, 1, 2, width, height-4)
local modified = false
local message, messageTimer
local isPrompt = false
local inputBuffer, inputCursor = "", 1
local inputCallback
local running = true
local cutBuffer = {}

local function fittosize(str, w, trunc)
    if #str < w then return (trunc and "" or (' '):rep(math.ceil((w-#str)/2))) .. str .. (' '):rep(math.floor((w-#str)/(trunc and 1 or 2)))
    elseif #str == w then return str
    elseif trunc then return str:sub(1, w)
    else return "..." .. str:sub(-w+3) end
end

local function makeShortcut(s)
    local retval = ""
    if s.key == keys.delete and s.shift then retval = "Sh-" end
    if s.ctrl then retval = retval .. "^"
    elseif s.alt then retval = retval .. "M-" end
    if shiftMap[s.key] then retval = retval .. shiftMap[s.key]
    else retval = retval .. keys.getCharacter(s.key):upper() end
    return retval
end

local function redrawMessage()
    if message then
        term.setTextColor(terminal.colors.black)
        term.setBackgroundColor(terminal.colors.white)
        if isPrompt then
            term.setCursorPos(1, height - 2)
            term.clearLine()
            term.write(message)
            local w = width - #message - 1
            if #inputBuffer > w then
                if inputCursor < w - 1 then
                    term.write(inputBuffer:sub(1, w - 1) .. ">")
                    term.setCursorPos(#message + inputCursor, height - 2)
                else
                    local start = math.floor((inputCursor - w + 1) / (w - 8) + 1) * (w - 8) + 2
                    term.write("<" .. inputBuffer:sub(start, start + w - 3))
                    if #inputBuffer > start + width - 1 then term.write(">")
                    else term.write(inputBuffer:sub(start + w - 3, start + w - 2)) end
                    term.setCursorPos(#message + (inputCursor - start) + 2, height - 2)
                end
            else
                term.write(inputBuffer)
                term.setCursorPos(#message + inputCursor, height - 2)
            end
        else
            term.setCursorPos(math.floor((width - #message) / 2) + 1, height - 2)
            term.write(message)
        end
        term.setTextColor(terminal.colors.white)
        term.setBackgroundColor(terminal.colors.black)
    end
end

local redrawText
local function redrawAll()
    term.setBackgroundColor(terminal.colors.black)
    term.clear()
    term.setCursorBlink(false)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(terminal.colors.white)
    term.setTextColor(terminal.colors.black)
    if width >= #VERSION + #filename + 26 then
        -- |  CC nano x.y filename Modified  |
        -- |  CC nano x.y filename           |
        term.write("  Phoenix nano " .. VERSION .. fittosize(filename, width - #VERSION - 26) .. (modified and " Modified  " or (' '):rep(11)))
    elseif width >= #filename + 13 then
        -- |  filename Modified  |
        -- |  filename           |
        term.write("  " .. fittosize(filename, width - 13) .. (modified and " Modified  " or (' '):rep(11)))
    elseif width >= #filename + 4 and not modified then
        -- |  filename  |
        term.write("  " .. fittosize(filename, width - 4) .. "  ")
    else
        -- |filename|
        -- |filename Modified|
        term.write(fittosize(filename, modified and width - 9 or width) .. (modified and " Modified" or ""))
    end
    redrawMessage()
    local msgx, msgy = term.getCursorPos()
    term.setCursorPos(1, height - 1)
    local columnCount = math.floor(width / 20) + 2
    local columnWidth = math.floor(width / columnCount)
    for i = 1, columnCount do
        if not shortcuts[1][i] then break end
        local s = makeShortcut(shortcuts[1][i])
        local str = fittosize(s .. " " .. shortcuts[1][i].description, i == columnCount and width - (columnWidth * (i - 1)) or columnWidth, true)
        term.blit(str, ('f'):rep(#s) .. ('0'):rep(#str-#s), ('0'):rep(#s) .. ('f'):rep(#str-#s))
    end
    term.setCursorPos(1, height)
    for i = 1, columnCount do
        if not shortcuts[2][i] then break end
        local s = makeShortcut(shortcuts[2][i])
        local str = fittosize(s .. " " .. shortcuts[2][i].description, i == columnCount and width - (columnWidth * (i - 1)) or columnWidth, true)
        term.blit(str, ('f'):rep(#s) .. ('0'):rep(#str-#s), ('0'):rep(#s) .. ('f'):rep(#str-#s))
    end
    redrawText()
    if message and isPrompt then term.setCursorPos(msgx, msgy) end
end

redrawText = function()
    win.setBackgroundColor(terminal.colors.black)
    win.setTextColor(terminal.colors.white)
    win.clear()
    win.setCursorBlink(false)
    local x, y
    for i = 1, height - 4 do
        win.setCursorPos(1, i)
        if lines[topLine+i-1] == nil then break end
        if i + topLine - 1 == cursorY and #lines[topLine+i-1] > width then
            if cursorX < width - 1 then
                win.write(lines[topLine+i-1]:sub(1, width - 1))
                win.blit(">", "f", "0")
                win.setBackgroundColor(terminal.colors.black)
                win.setTextColor(terminal.colors.white)
            else
                local start = math.floor((cursorX - width + 1) / (width - 8) + 1) * (width - 8) + 2
                win.blit("<", "f", "0")
                win.setBackgroundColor(terminal.colors.black)
                win.setTextColor(terminal.colors.white)
                win.write(lines[topLine+i-1]:sub(start, start + width - 3))
                if #lines[topLine+i-1] > start + width - 1 then
                    win.blit(">", "f", "0")
                    win.setBackgroundColor(terminal.colors.black)
                    win.setTextColor(terminal.colors.white)
                else win.write(lines[topLine+i-1]:sub(start + width - 3, start + width - 2)) end
                x, y = cursorX - start + 2, cursorY - topLine + 1
            end
        elseif #lines[topLine+i-1] > width then
            win.write(lines[topLine+i-1]:sub(1, width-1))
            win.blit(">", "f", "0")
            win.setBackgroundColor(terminal.colors.black)
            win.setTextColor(terminal.colors.white)
        else win.write(lines[topLine+i-1]) end
    end
    if x == nil then x, y = cursorX, cursorY - topLine + 1 end
    win.setCursorPos(x, y)
    win.setCursorBlink(true)
end

local function showMessage(msg)
    message = msg
    isPrompt = false
    messageTimer = 20
    redrawAll()
end

local function showInput(msg, shortcut, fn)
    message = msg
    messageTimer = nil
    isPrompt = true
    shortcuts = shortcut or shortcuts
    inputBuffer = ""
    inputCursor = 1
    inputCallback = fn
    redrawAll()
end

local function save(shouldExit)
    local nlMode = 1
    local modemsgs = {
        "File Name to Write: ",
        "File Name to Write [DOS Format]: ",
        "File Name to Write [Mac Format]: "
    }
    showInput("File Name to Write: ", {
        {
            {key = keys.g, ctrl = true, description = "Help"},
            {key = keys.d, alt = true, description = "DOS Format", action = function()
                if nlMode == 2 then nlMode = 1
                else nlMode = 2 end
                message = modemsgs[nlMode]
                redrawMessage()
            end},
            {key = keys.a, alt = true, description = "Append"},
            {key = keys.b, alt = true, description = "Backup File"}
        }, {
            {key = keys.c, ctrl = true, description = "Cancel", action = function()
                shortcuts = mainShortcuts
                showMessage "[ Cancelled ]"
            end},
            {key = keys.m, alt = true, description = "Mac Format", action = function()
                if nlMode == 3 then nlMode = 1
                else nlMode = 3 end
                message = modemsgs[nlMode]
                redrawMessage()
            end},
            {key = keys.p, alt = true, description = "Prepend"},
            {key = keys.t, ctrl = true, description = "Browse"}
        }
    }, function(path)
        local file, err = filesystem.open(path, "w")
        if not file then
            showMessage("[ Could not write file: " .. err .. " ]")
            return
        end
        local nl = ({"\n", "\r\n", "\r"})[nlMode]
        for _, v in ipairs(lines) do file.write(v .. nl) end
        file.close()
        modified = false
        if shouldExit then running = false
        else showMessage("[ Wrote " .. #lines .. " lines ]") end
    end)
    if args[1] then
        inputBuffer = filename
        inputCursor = #filename + 1
        redrawMessage()
    end
end

mainShortcuts = {
    {
        {key = keys.g, ctrl = true, description = "Get Help"},
        {key = keys.o, ctrl = true, description = "Write Out", action = save},
        {key = keys.w, ctrl = true, description = "Where Is"},
        {key = keys.k, ctrl = true, description = "Cut Text", action = function()
            if cursorY == #lines then showMessage("[ Nothing was cut ]")
            else
                cutBuffer[#cutBuffer+1] = table.remove(lines, cursorY)
                cursorX = math.min(cursorX, #lines[cursorY] + 1)
                if not modified then
                    modified = true
                    redrawAll()
                else redrawText() end
            end
        end},
        {key = keys.j, ctrl = true, description = "Justify"},
        {key = keys.c, ctrl = true, description = "Cur Pos", action = function()
            local c = 0
            for y = 1, cursorY - 1 do c = c + #lines[y] end
            local n = c
            for y = cursorY, #lines do n = n + #lines[y] end
            showMessage(("[ line %d/%d, col %d/%d, char %d/%d ]"):format(
                cursorY, #lines, --cursorY / #lines * 100,
                cursorX, #lines[cursorY], --cursorX / #lines[cursorY] * 100,
                c + cursorX - 1, n --, (c + cursorX - 1) / n * 100
            ))
        end},
        {key = keys.u, alt = true, description = "Undo"},
        {key = keys.a, alt = true, description = "Mark Text"},
        {key = keys.rightBracket, alt = true, description = "To Bracket"},
        {key = keys.q, alt = true, description = "Previous"},
        {key = keys.b, ctrl = true, description = "Back"},
        {key = keys.left, ctrl = true, description = "Prev Word"},
        {key = keys.a, ctrl = true, description = "Home"},
        {key = keys.p, ctrl = true, description = "Prev Line"},
        {key = keys.up, alt = true, description = "Scroll Up"},
        {key = keys.up, ctrl = true, description = "Prev Block"},
        {key = keys.nine, shift = true, alt = true, description = "Beg of Par"},
        {key = keys.y, ctrl = true, description = "Prev Page"},
        {key = keys.backslash, alt = true, description = "First Line"},
        {key = keys.left, alt = true, description = "Prev File"},
        {key = keys.i, ctrl = true, description = "Tab"},
        {key = keys.h, ctrl = true, description = "Backspace"},
        {key = keys.delete, shift = true, ctrl = true, description = "Chop Left"},
        {key = keys.t, alt = true, description = "CutTillEnd"},
        {key = keys.d, alt = true, description = "Word Count"},
        {key = keys.l, ctrl = true, description = "Refresh"},
        {key = keys.rightBracket, shift = true, alt = true, description = "Indent"},
        {key = keys.three, alt = true, description = "Comment Lines"},
        {key = keys.semicolon, shift = true, alt = true, description = "Record"},
        {key = keys.delete, alt = true, description = "Zap Text"},
        {key = keys.f, alt = true, description = "Formatter"}
    }, {
        {key = keys.x, ctrl = true, description = "Exit"},
        {key = keys.r, ctrl = true, description = "Read File"},
        {key = keys.backslash, ctrl = true, description = "Replace"},
        {key = keys.u, ctrl = true, description = "Paste Text", action = function()
            if #cutBuffer == 0 then showMessage("[ Nothing was pasted ]")
            else
                for i = #cutBuffer, 1, -1 do table.insert(lines, cursorY, cutBuffer[i]) end
                cutBuffer = {}
                if not modified then
                    modified = true
                    redrawAll()
                else redrawText() end
            end
        end},
        {key = keys.t, ctrl = true, description = "To Spell"},
        {key = keys.minus, shift = true, ctrl = true, description = "Go To Line", action = function()
            showInput("Enter line number, column number: ", {
                {
                    {key = keys.g, ctrl = true, description = "Help"},
                    {key = keys.w, ctrl = true, description = "Begin of Paragr."},
                    {key = keys.y, ctrl = true, description = "First Line"},
                    {key = keys.t, ctrl = true, description = "Go To Text"}
                }, {
                    {key = keys.c, ctrl = true, description = "Cancel", action = function()
                        shortcuts = mainShortcuts
                        showMessage "[ Cancelled ]"
                    end},
                    {key = keys.o, ctrl = true, description = "End of Paragraph"},
                    {key = keys.v, ctrl = true, description = "Last Line"}
                }
            }, function(msg)
                local num = tonumber(msg)
                if num and num <= #lines then
                    cursorY = num
                    if cursorY < topLine then topLine = cursorY
                    elseif cursorY - height + 5 > topLine then topLine = cursorY - height + 5 end
                else
                    showMessage "[ Invalid line or column number ]"
                end
            end)
        end},
        {key = keys.e, alt = true, description = "Redo"},
        {key = keys.six, alt = true, description = "Copy Text"},
        {key = keys.q, ctrl = true, description = "Where Was"},
        {key = keys.w, alt = true, description = "Next"},
        {key = keys.f, ctrl = true, description = "Forward"},
        {key = keys.right, ctrl = true, description = "Next Word"},
        {key = keys.e, ctrl = true, description = "End"},
        {key = keys.n, ctrl = true, description = "Next Line"},
        {key = keys.down, alt = true, description = "Scroll Down"},
        {key = keys.down, ctrl = true, description = "Next Block"},
        {key = keys.zero, shift = true, alt = true, description = "End of Par"},
        {key = keys.v, ctrl = true, description = "Next Page"},
        {key = keys.slash, alt = true, description = "Last Line"},
        {key = keys.right, alt = true, description = "Next File"},
        {key = keys.m, ctrl = true, description = "Enter"},
        {key = keys.d, ctrl = true, description = "Delete"},
        {key = keys.delete, ctrl = true, description = "Chop Right"},
        {key = keys.j, alt = true, description = "FullJstify"},
        {key = keys.v, alt = true, description = "Verbatim"},
        {key = keys.z, ctrl = true, description = "Suspend"},
        {key = keys.leftBracket, shift = true, alt = true, description = "Unindent"},
        {key = keys.rightBracket, ctrl = true, description = "Complete"},
        {key = keys.semicolon, alt = true, description = "Run Macro"},
        {key = keys.b, alt = true, description = "To Linter"},
        {key = keys.s, ctrl = true, description = "Save"}
    }
}

shortcuts = mainShortcuts

if filename then
    if filesystem.stat(filename) then
        for l in io.lines(filename) do table.insert(lines, l) end
        showMessage("[ Read " .. #lines .. " lines ]")
    else showMessage "[ New File ]" end
else
    filename = "New Buffer"
    showMessage "[ Welcome to nano. For basic help, type Ctrl+G. ]"
end

redrawAll()

while running do
    local event, param = coroutine.yield()
    if message and isPrompt then
        if event == "key" then
            if param.keycode == keys.left and inputCursor > 1 then
                inputCursor = inputCursor - 1
                redrawMessage()
            elseif param.keycode == keys.right and inputCursor <= #inputBuffer then
                inputCursor = inputCursor + 1
                redrawMessage()
            elseif param.keycode == keys.backspace and inputCursor > 1 then
                inputBuffer = inputBuffer:sub(1, inputCursor - 2) .. inputBuffer:sub(inputCursor)
                inputCursor = inputCursor - 1
                redrawMessage()
            elseif param.keycode == keys.delete then
                inputBuffer = inputBuffer:sub(1, inputCursor - 1) .. inputBuffer:sub(inputCursor + 1)
                redrawMessage()
            elseif param.keycode == keys.enter then
                message, isPrompt = nil
                shortcuts = mainShortcuts
                inputCallback(inputBuffer)
                redrawAll()
            else
                local found
                for _, v in ipairs(shortcuts[1]) do
                    if param.keycode == v.key and param.ctrlHeld == (v.ctrl or false) and param.altHeld == (v.alt or false) and param.shiftHeld == (v.shift or false) then
                        if v.action then v.action() end
                        found = true
                        break
                    end
                end
                if not found then
                    for _, v in ipairs(shortcuts[2]) do
                        if param.keycode == v.key and param.ctrlHeld == (v.ctrl or false) and param.altHeld == (v.alt or false) and param.shiftHeld == (v.shift or false) then
                            if v.action then v.action() end
                            found = true
                            break
                        end
                    end
                end
            end
        elseif event == "char" then
            inputBuffer = inputBuffer:sub(1, inputCursor-1) .. param.character .. inputBuffer:sub(inputCursor)
            inputCursor = inputCursor + 1
            redrawMessage()
        end
    else
        if event == "key" then
            if param.keycode == keys.up and cursorY > 1 then
                cursorY = cursorY - 1
                if cursorY < topLine then topLine = cursorY end
                if not lines[cursorY] then cursorX = 1
                elseif cursorX > #lines[cursorY] + 1 then cursorX = #lines[cursorY] + 1 end
                redrawText()
            elseif param.keycode == keys.down and cursorY <= #lines then
                cursorY = cursorY + 1
                if cursorY - height + 5 > topLine then topLine = cursorY - height + 5 end
                if not lines[cursorY] then cursorX = 1
                elseif cursorX > #lines[cursorY] + 1 then cursorX = #lines[cursorY] + 1 end
                redrawText()
            elseif param.keycode == keys.right and lines[cursorY] then
                if #lines[cursorY] < cursorX then
                    cursorY = cursorY + 1
                    cursorX = 1
                else cursorX = cursorX + 1 end
                redrawText()
            elseif param.keycode == keys.left and (cursorX > 1 or cursorY > 1) then
                if cursorX == 1 then
                    cursorY = cursorY - 1
                    cursorX = #lines[cursorY] + 1
                else cursorX = cursorX - 1 end
                redrawText()
            elseif param.keycode == keys.backspace then
                if cursorX == 1 then
                    if cursorY ~= 1 then
                        cursorX = #lines[cursorY-1] + 1
                        lines[cursorY-1] = lines[cursorY-1] .. (table.remove(lines, cursorY) or "")
                        cursorY = cursorY - 1
                        if cursorY < topLine then topLine = cursorY end
                    end
                else
                    lines[cursorY] = lines[cursorY]:sub(1, cursorX-2) .. lines[cursorY]:sub(cursorX)
                    cursorX = cursorX - 1
                end
                if not modified then
                    modified = true
                    redrawAll()
                else redrawText() end
            elseif param.keycode == keys.delete and lines[cursorY] then
                if cursorX == #lines[cursorY] + 1 then
                    lines[cursorY] = lines[cursorY] .. (table.remove(lines, cursorY + 1) or "")
                else
                    lines[cursorY] = lines[cursorY]:sub(1, cursorX - 1) .. lines[cursorY]:sub(cursorX + 1)
                end
                if not modified then
                    modified = true
                    redrawAll()
                else redrawText() end
            elseif param.keycode == keys.enter then
                local text = (lines[cursorY] or ""):sub(cursorX)
                lines[cursorY] = (lines[cursorY] or ""):sub(1, cursorX - 1)
                table.insert(lines, cursorY + 1, text)
                cursorX = 1
                cursorY = cursorY + 1
                if cursorY - height + 5 > topLine then topLine = cursorY - height + 5 end
                if not modified then
                    modified = true
                    redrawAll()
                else redrawText() end
            elseif param.keycode == keys.x and param.ctrlHeld then
                local exit = true
                if modified then
                    term.setCursorPos(1, height - 2)
                    term.setBackgroundColor(terminal.colors.white)
                    term.setTextColor(terminal.colors.black)
                    term.clearLine()
                    term.write("Save modified buffer?")
                    term.setBackgroundColor(terminal.colors.black)
                    term.setTextColor(terminal.colors.white)
                    term.setCursorPos(1, height - 1)
                    term.clearLine()
                    term.blit(" Y Yes", "ff0000", "00ffff")
                    term.setCursorPos(1, height)
                    term.clearLine()
                    term.blit(" N No       ^C Cancel", "ff0000000000ff0000000", "00ffffffffff00fffffff")
                    term.setCursorBlink(false)
                    while true do
                        event, param = coroutine.yield()
                        if event == "key" and param.keycode == keys.c and param.ctrlHeld then exit = false break
                        elseif event == "char" then
                            if param.character == "y" then save(true) exit = false break
                            elseif param.character == "n" then break end
                        end
                    end
                end
                if exit then break end
                if not isPrompt then showMessage "[ Cancelled ]" end
            else
                local found
                for _, v in ipairs(shortcuts[1]) do
                    if param.keycode == v.key and param.ctrlHeld == (v.ctrl or false) and param.altHeld == (v.alt or false) and param.shiftHeld == (v.shift or false) then
                        if v.action then v.action() end
                        found = true
                        break
                    end
                end
                if not found then
                    for _, v in ipairs(shortcuts[2]) do
                        if param.keycode == v.key and param.ctrlHeld == (v.ctrl or false) and param.altHeld == (v.alt or false) and param.shiftHeld == (v.shift or false) then
                            if v.action then v.action() end
                            found = true
                            break
                        end
                    end
                end
            end
        elseif event == "char" then
            if lines[cursorY] then lines[cursorY] = lines[cursorY]:sub(1, cursorX-1) .. param.character .. lines[cursorY]:sub(cursorX)
            else lines[cursorY] = param.character end
            cursorX = cursorX + 1
            if not modified then
                modified = true
                redrawAll()
            else redrawText() end
        end
    end
    if messageTimer then
        messageTimer = messageTimer - 1
        if messageTimer == 0 then
            message, messageTimer = nil
            redrawAll()
        end
    end
end

term.setBackgroundColor(terminal.colors.black)
term.setTextColor(terminal.colors.white)
term.clear()
term.setCursorPos(1, 1)
term.close()
terminal.termctl(oldctl)
