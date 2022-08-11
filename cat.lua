local filesystem = require "system.filesystem"
local args = {...}
if args[1] == "-u" then table.remove(args, 1) end
if #args == 0 then args[1] = "-" end
for _, v in ipairs(args) do
    if v == "-" then
        io.stdout:write(io.stdin:read("*a"))
    else
        local file, err = filesystem.open(v, "rb")
        if not file then error("cat: " .. v .. ": " .. err) end
        io.stdout:write(file.readAll())
        file.close()
    end
end