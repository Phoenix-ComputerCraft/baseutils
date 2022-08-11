local filesystem = require "system.filesystem"
local util = require "system.util"
local args = assert(util.argparse({i = false, f = false}, ...))
if #args < 2 then error("mv: missing operand") end
local dest = table.remove(args)
local deststat = filesystem.stat(dest)
if #args == 1 and (not deststat or deststat.type ~= "directory") then
    if deststat and not args.f and ((not filesystem.effectivePermissions(deststat).write and util.syscall.istty()) or args.i) then
        io.stderr:write("mv: overwrite " .. deststat.type .. " " .. dest .. "? ")
        local p = io.read()
        if p:lower() ~= "y" then return false end
    end
    filesystem.move(args[1], dest)
    return
end
if not deststat or deststat.type ~= "directory" then error("mv: " .. dest .. ": not a directory") end
for _, v in ipairs(args) do
    local d = filesystem.combine(dest, filesystem.basename(v))
    deststat = filesystem.stat(d)
    if deststat and not args.f and ((not filesystem.effectivePermissions(deststat).write and util.syscall.istty()) or args.i) then
        io.stderr:write("mv: overwrite " .. deststat.type .. " " .. d .. "? ")
        local p = io.read()
        if p:lower() ~= "y" then return false end
    end
    filesystem.move(v, d)
end
