local filesystem = require "system.filesystem"
local hardware = require "system.hardware"
local process = require "system.process"
local terminal = require "system.terminal"
local util = require "system.util"

local logo = {
    "\x1b[30;40m                \x1b[0m",
    "\x1b[30;40m  \x1b[33;106m\x88\x1b[96;43m\x8F\x1b[96;40m\x90 \x1b[30;106m\x9F\x1b[96;40m\x90   \x1b[30;106m\x9F\x1b[96;43m\x8F\x1b[33;106m\x84\x1b[30;40m  \x1b[0m",
    "\x1b[96;40m \x9A\x1b[33;106m\x89\x84\x1b[33;41m\x82\x1b[33;40m\x94\x1b[30;106m\x95 \x1b[96;40m\x90 \x1b[30;43m\x97\x1b[33;41m\x81\x1b[33;106m\x88\x86\x1b[30;106m\x9A\x1b[30;40m \x1b[0m",
    "\x1b[30;106m\x9F\x1b[96;43m\x9B\x8C\x1b[96;41m\x95 \x1b[33;40m\x95\x1b[30;106m\x95 \x96\x1b[30;40m \x1b[30;43m\x95\x1b[96;41m \x1b[31;106m\x95\x1b[96;43m\x8C\x1b[33;106m\x98\x1b[96;40m\x90\x1b[0m",
    "\x1b[30;106m\x95\x1b[33;106m\x8C\x84\x1b[96;41m\x95 \x1b[30;43m\x8A\x1b[30;106m\x95\x1b[96;100m\x8F\x8F\x1b[96;40m\x95\x1b[30;43m\x85\x1b[96;41m \x1b[31;106m\x95\x1b[33;106m\x88\x8C\x1b[96;40m\x95\x1b[0m",
    "\x1b[96;40m\x8A\x1b[96;43m\x9C\x8E\x1b[31;106m\x82\x1b[33;41m \x82\x1b[90;106m\x95\x1b[33;106m\x90\x1b[96;43m\x9F\x1b[96;100m\x95\x1b[33;41m\x81 \x1b[31;106m\x81\x1b[96;43m\x8D\x1b[33;106m\x93\x1b[96;40m\x85\x1b[0m",
    "\x1b[30;40m \x1b[96;43m\x9E\x1b[33;106m\x8C\x1b[96;43m\x9B\x1b[31;106m\x82\x1b[96;41m\x90\x1b[90;106m\x95\x1b[33;106m\x85\x8A\x1b[96;100m\x95\x1b[31;106m\x9F\x81\x1b[33;106m\x98\x8C\x92\x1b[30;40m \x1b[0m",
    "\x1b[96;40m \x82\x1b[33;106m\x86\x99\x99\x1b[96;100m\x95\x1b[33;106m\x8A\x88\x81\x85\x1b[90;106m\x95\x1b[96;43m\x99\x99\x1b[33;106m\x89\x1b[106;40m\x81 \x1b[0m",
    "\x1b[33;40m  \x82\x8B\x1b[90;106m \x96 \x1b[33;106m\x95\x1b[96;43m\x95\x1b[96;106m \x1b[96;100m\x96\x1b[96;106m \x1b[33;40m\x87\x81  \x1b[0m",
    "\x1b[96;40m     \x83\x8B\x8F\x8F\x87\x83     \x1b[0m",
    "\x1b[30;40m                \x1b[0m"
}

local function time(n)
    local h = math.floor(n / 3600)
    local m = math.floor(n / 60) % 60
    local s = n % 60
    local retval = s .. "s"
    if m > 0 or h > 0 then retval = m .. "m " .. retval end
    if h > 0 then retval = h .. "h " .. retval end
    return retval
end

local function space(n)
    if n >= 1073741824 then return ("%.3g GiB"):format(n / 1073741824)
    elseif n >= 1048576 then return ("%.3g MiB"):format(n / 1048576)
    elseif n >= 1024 then return ("%.3g kiB"):format(n / 1024)
    else return ("%.3g B"):format(n) end
end

local lines = {"\x1b[96m" .. process.getuser() .. "\x1b[0m@\x1b[96m" .. (hardware.call("/", "getLabel") or ("Computer " .. hardware.info("/").id))}
lines[#lines+1] = ("-"):rep(#lines[1] - 14)
local function addLine(name, value) lines[#lines+1] = "\x1b[96m" .. name .. "\x1b[0m: " .. value end
addLine("OS", "Phoenix " .. util.syscall.version())
addLine("Uptime", time(util.syscall.uptime()))
addLine("Runtime", util.syscall.cchost():match("%b()"):sub(2, -2))
addLine("Lua", _VERSION)
addLine("CC Version", util.syscall.cchost():match("ComputerCraft [%d%.]+"))
addLine("Resolution", table.concat({terminal.termsize()}, "x"))
local stat = filesystem.stat("/")
addLine("Disk Space", space(stat.freeSpace) .. " / " .. space(stat.capacity))
if collectgarbage then addLine("Memory", space(collectgarbage("count") * 1024)) end
lines[#lines+1] = ""
lines[#lines+1] = "\x1b[40m   \x1b[41m   \x1b[42m   \x1b[43m   \x1b[44m   \x1b[45m   \x1b[46m   \x1b[47m   \x1b[0m"
lines[#lines+1] = "\x1b[100m   \x1b[101m   \x1b[102m   \x1b[103m   \x1b[104m   \x1b[105m   \x1b[106m   \x1b[107m   \x1b[0m"
lines[#lines+1] = ""

local w = terminal.termsize() - 18
for i = 1, math.max(#logo, #lines) do
    local s = lines[i] or ""
    local l, e = 0, false
    for c, p in s:gmatch "(.)()" do
        if e then if c == 'm' then e = false end
        elseif c == '\x1b' then e = true
        else
            l = l + 1
            if l == w then s = s:sub(1, p) e = true break end
        end
    end
    if e then io.write((logo[i] or "                ") .. "  " .. s)
    else print((logo[i] or "                ") .. "  " .. s) end
end