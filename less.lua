local filesystem = require "system.filesystem"
local keys = require "system.keys"
local process = require "system.process"
local terminal = require "system.terminal"
local util = require "system.util"

local args = {...}
local filename = nil
local parseargs = true
local foldLines = true
if not terminal.istty() then filename = "-" end
for i,s in ipairs(args) do
    if string.sub(s, 1, 2) == "--" and parseargs then
        if s == "--version" then print("less for Phoenix v1.0"); return
        elseif s == "--help" then print("..."); return -- TODO
        elseif s == "--" then parseargs = false
        elseif s == "--chop-long-lines" then foldLines = false
        end
    elseif string.sub(s, 1, 1) == '-' and parseargs then
        for a in string.gmatch(string.sub(s, 2), "[a-zA-Z0-9~]") do
            if a == 'S' then foldLines = false
            elseif a == '' then
            end
        end
    elseif filename == nil then filename = s end
end
if filename == nil then error("Missing filename (\"less --help\" for help)") end

local stdin_buf
local term = assert(terminal.openterm())
local lines = {}
local pos, hpos = 1, 1
local w, h = term.getSize()
local message = nil
h=h-1

local function readFile()
    lines = {}
    if filename == "-" then
        if not stdin_buf then
            stdin_buf = {}
            repeat
                local line = io.stdin:read()
                stdin_buf[#stdin_buf+1] = line
            until not line
        end
        for i, v in ipairs(stdin_buf) do lines[i] = v end
    else
        local file = filesystem.open(filename, "r")
        if file == nil then error("Could not open file " .. filename) end
        local line = file.readLine()
        while line do
            table.insert(lines, ({string.gsub(line, "\t", "    ")})[1])
            line = file.readLine()
        end
        file.close()
    end
    if foldLines and hpos == 1 then for i = 1, #lines do if #lines[i] > w then
        table.insert(lines, i+1, string.sub(lines[i], w) or "")
        lines[i] = string.sub(lines[i], 1, w - 1)
    end end end
end

local function redrawScreen()
    term.clear()
    term.setCursorPos(1, 1)
    term.setCursorBlink(false)
    for i = pos, pos + h - 1 do
        if lines[i] ~= nil then term.write(string.sub(lines[i], hpos)) end
        term.setCursorPos(1, i - pos + 2)
    end
    term.setCursorPos(1, h+1)
    if message then term.blit(message, string.rep("f", #message), string.rep("0", #message))
    elseif pos >= #lines - h then term.blit("(END)", "fffff", "00000")
    else term.write(":") end
    term.setCursorBlink(true)
end

local function readCommand(prompt, fg, bg)
    term.setCursorPos(1, h+1)
    term.clearLine()
    term.blit(prompt, fg or string.rep("0", #prompt), bg or string.rep("f", #prompt))
    local str = ""
    local c = 1
    while true do
        term.setCursorPos(#prompt + 1, h + 1)
        term.write(str .. string.rep(" ", w - #str - #prompt - 2))
        term.setCursorPos(#prompt + c, h + 1)
        term.setCursorBlink(true)
        local event, param = coroutine.yield()
        if event == "key" then
            if param.keycode == keys.backspace then if str == "" then return nil elseif c > 1 then
                str = string.sub(str, 1, c-2) .. string.sub(str, c)
                c=c-1
            end
            elseif param.keycode == keys.left and c > 1 then c = c - 1
            elseif param.keycode == keys.right and c < #str + 1 then c = c + 1
            elseif param.keycode == keys.enter then return str
            end
        elseif event == "char" then
            str = string.sub(str, 1, c-1) .. param.character .. string.sub(str, c)
            c=c+1
        end
    end
end

local function flashScreen()
    local br, bg, bb = term.getPaletteColor(terminal.colors.black)
    term.setPaletteColor(terminal.colors.black, term.getPaletteColor(terminal.colors.lightGray))
    util.sleep(0.1)
    term.setPaletteColor(terminal.colors.black, term.getPaletteColor(terminal.colors.gray))
    util.sleep(0.05)
    term.setPaletteColor(terminal.colors.black, br, bg, bb)
    util.sleep(0.05)
end

readFile()

local lastQuery = nil

while true do
    redrawScreen()
    local event, param = coroutine.yield()
    local oldMessage = message
    message = nil
    if event == "key" then
        if param.keycode == keys.left and hpos > w / 2 then hpos = hpos - w / 2
        elseif param.keycode == keys.right then hpos = hpos + w / 2
        elseif param.keycode == keys.up then if pos > 1 then pos = pos - 1 else flashScreen() end
        elseif (param.keycode == keys.down or param.keycode == keys.enter) then if pos < #lines - h then pos = pos + 1 else flashScreen() end
        elseif param.keycode == keys.space then if pos < #lines - h then pos = pos + (pos < #lines - 2*h + 1 and h or (#lines - h) - pos) else flashScreen() end
        end
    elseif event == "char" then
        if param.character == "q" then break
        elseif param.character == "f" then if pos < #lines - h then pos = pos + (pos < #lines - 2*h + 1 and h or (#lines - h) - pos) else flashScreen() end
        elseif param.character == "b" then if pos > 1 then pos = pos - (pos > h + 1 and h or pos - 1) else flashScreen() end
        elseif param.character == "d" then if pos < #lines - h then pos = pos + (pos < #lines - (1.5*h) + 1 and h / 2 or (#lines - h) - pos) else flashScreen() end
        elseif param.character == "u" then if pos > 1 then pos = pos - (pos > (h / 2) + 1 and (h / 2) or pos - 1) else flashScreen() end
        elseif param.character == "g" or param.character == "<" then pos = 1
        elseif param.character == "G" or param.character == ">" then pos = #lines - h
        elseif param.character == "e" or param.character == "j" then if pos < #lines - h then pos = pos + 1 else flashScreen() end
        elseif param.character == "y" or param.character == "k" then if pos > 1 then pos = pos - 1 else flashScreen() end
        elseif param.character == "K" or param.character == "Y" then pos = pos - 1
        elseif param.character == "J" then pos = pos + 1
        elseif param.character == "/" then
            local query = readCommand("/")
            if query == "" then query = lastQuery end
            if query ~= nil then
                lastQuery = query
                local found = false
                for i = pos + 1, #lines do if string.match(lines[i], query) then
                    pos = i
                    found = true
                    break
                end end
                if pos > #lines - h then pos = #lines - h end
                if not found then message = "Pattern not found" end
            end
        elseif param.character == "?" then
            local query = readCommand("?")
            if query == "" then query = lastQuery end
            if query ~= nil then
                lastQuery = query
                local found = false
                for i = pos - 1, 1, -1 do if string.match(lines[i], query) then
                    pos = i
                    found = true
                    break
                end end
                if pos > #lines - h then pos = #lines - h end
                if not found then message = "Pattern not found" end
            end
        elseif param.character == "n" then
            local found = false
            for i = pos + 1, #lines do if string.match(lines[i], lastQuery) then
                pos = i
                found = true
                break
            end end
            if pos > #lines - h then pos = #lines - h end
            if not found then message = "Pattern not found" end
        elseif param.character == "N" then
            local found = false
            for i = pos - 1, 1, -1 do if string.match(lines[i], lastQuery) then
                pos = i
                found = true
                break
            end end
            if pos > #lines - h then pos = #lines - h end
            if not found then message = "Pattern not found" end
        elseif param.character == "v" then
            local pid = process.start(EDITOR or "/bin/vi", filename)
            repeat local event, param = coroutine.yield() until event == "process_complete" and param.id == pid
            readFile()
        elseif param.character == "!" then
            local cmd = readCommand("!")
            if cmd then
                local pid = process.start(string.gsub(cmd, "%%", filename))
                repeat local event, param = coroutine.yield() until event == "process_complete" and param.id == pid
            end
        end
    elseif event == "term_resize" then
        w, h = term.getSize()
        h=h-1
        readFile()
    elseif event == "mouse_scroll" then
        if param.direction == 1 and pos < #lines - h then pos = pos + 1
        elseif param.direction == -1 and pos > 1 then pos = pos - 1 end
    else
        message = oldMessage
    end
end
term.clear()
term.setCursorPos(1, 1)
term.close()