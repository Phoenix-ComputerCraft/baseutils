local filesystem = require "system.filesystem"
local util = require "system.util"
if select("#", ...) == 0 then
    for _, v in ipairs(filesystem.mountlist()) do
        local opts = {}
        for k, p in pairs(v.options) do
            if p == true then opts[#opts+1] = k
            elseif type(p) == "string" then opts[#opts+1] = p
            elseif type(p) == "number" then opts[#opts+1] = tostring(p) end
        end
        print(("%s on /%s type %s (%s)"):format(v.source, v.path, v.type, table.concat(opts, ",")))
    end
    return
end
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