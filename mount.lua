local filesystem = require "system.filesystem"
local util = require "system.util"
local args = assert(util.argparse({t = true, o = true}, ...))
if #args < 2 then error("Usage: mount [-t type] [-o options] device mountpoint") end
local type = args.t or "craftos"
local options = {}
if args.o then
    for arg in args.o:gmatch "[^,]+" do
        local k, v = arg:match "([^=]+)=(.+)"
        if not k then k, v = arg, true end
        options[k] = v
    end
end
return filesystem.mount(type, args[1], args[2], options)