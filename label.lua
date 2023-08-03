local hardware = require "system.hardware"
local args = {...}
if args[1] == "set" and not args[3] then args[3], args[2] = args[2], nil end
local device
if args[2] then device = assert(hardware.wrap(args[2]), "No such device '" .. args[2] .. "'")
else device = hardware.wrap("/") end
if not device.getLabel then error("Device does not support labels") end
if args[1] == "get" then
    local l = device.label
    if l then print((args[2] or "Computer") .. " is labeled '" .. l .. "'")
    else print("No " .. (args[2] or "computer") .. " label") end
elseif args[1] == "set" then
    device.label = args[3]
    print("Set " .. (args[2] or "computer") .. " label to '" .. args[3] .. "'")
elseif args[1] == "clear" then
    device.label = nil
    print("Cleared " .. (args[2] or "computer") .. " label")
else error("Usage: label <get|set|clear> [drive] [label]") end
