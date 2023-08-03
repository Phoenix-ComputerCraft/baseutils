local hardware = require "system.hardware"
if ... then
    local drive = assert(hardware.wrap(...), "No such device")
    local st = drive.state
    if st and st.id then print("This drive has disk #" .. st.id)
    else error("No disk in drive") end
else
    print("This is computer #" .. hardware.info("/").metadata.id)
end