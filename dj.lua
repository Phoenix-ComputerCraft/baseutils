local hardware = require "system.hardware"
local args = {...}
local drive = args[2] and hardware.wrap(args[2]) or hardware.find("drive")
if not drive then
    if args[2] then error("Could not find drive named " .. args[2])
    else error("Could not find any attached drives") end
end
if args[1] == "play" then
    local info = drive.state
    if not info then error("No disc in drive")
    elseif not info.audio then error("Disc in drive is not a record") end
    drive.play()
    print("Playing '" .. info.audio .. "'")
elseif args[1] == "stop" then
    drive.stop()
else error("Usage: dj <play|stop> [drive]") end