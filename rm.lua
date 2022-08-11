local filesystem = require "system.filesystem"
local util = require "system.util"
local args = assert(util.argparse({f = false, i = false, R = "@r", r = false, ["no-preserve-root"] = false}, ...))
local retval = true
for _, v in ipairs(args) do
    local stat = filesystem.stat(v)
    if not args["no-preserve-root"] and filesystem.combine(v) == "/" then
        io.stderr:write("rm: refusing to remove root directory")
    elseif not stat then
        if not args.f then io.stderr:write("rm: " .. v .. ": No such file or directory\n") end
        retval = false
    elseif stat.type == "directory" then
        if args.r then
            filesystem.remove(v)
        else
            io.stderr:write("rm: -r not specified, skipping directory " .. v .. "\n")
            retval = false
        end
    else
        filesystem.remove(v)
    end
end
return retval
