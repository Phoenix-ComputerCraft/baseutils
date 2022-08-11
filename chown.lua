local util = require "system.util"
local filesystem = require "system.filesystem"
local args = assert(util.argparse({h = false, H = false, L = false, P = false, R = false}, ...))
if #args < 2 then error("usage: chown [-h] [-R [-H|-L|-P]] <owner> <file...>") end
local function recurse(path, user)
    filesystem.chown(path, user)
    if filesystem.stat(path).type == "directory" then
        for _, v in ipairs(filesystem.list(path)) do
            recurse(filesystem.combine(path, v), user)
        end
    end
end
local user = args[1]:gsub(":.*", "")
-- TODO: handle links
for i = 2, #args do
    if args.R then recurse(args[i], user)
    else filesystem.chown(args[i], user) end
end