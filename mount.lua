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
        print(("%s on %s type %s (%s)"):format(v.source, v.path, v.type, table.concat(opts, ",")))
    end
    return
end
local fstab = {}
local fstab_f = filesystem.open("/etc/fstab", "r")
if fstab_f then
    for line in fstab_f.readLine do
        local src, dest, type, opts, _, check = line:gsub("#.*", ""):match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        if src then
            src = src:gsub("\\([0-3][0-7][0-7])", function(c) return string.char(tonumber(c, 8)) end):gsub("\\x(%x%x)", function(c) return string.char(tonumber(c, 16)) end)
            dest = dest:gsub("\\([0-3][0-7][0-7])", function(c) return string.char(tonumber(c, 8)) end):gsub("\\x(%x%x)", function(c) return string.char(tonumber(c, 16)) end)
            local options = {}
            for arg in opts:gmatch "[^,]+" do
                local k, v = arg:match "([^=]+)=?(.*)"
                if k == "defaults" then
                    options.rw = true
                    options.suid = true
                    options.dev = true
                    options.exec = true
                    options.auto = true
                    options.owner = true
                    options.async = true
                else
                    if not k then k, v = arg, true end
                    options[k] = v
                end
            end
            fstab[src] = {
                src = src,
                dest = dest,
                type = type,
                options = options,
                check = tonumber(check)
            }
            fstab[#fstab+1] = fstab[src]
        end
    end
end
local args = assert(util.argparse({t = true, o = true, a = false}, ...))
if args.a then
    local retval = true
    for _, v in ipairs(fstab) do
        if v.options.auto and not v.options.noauto then
            local ok, err = pcall(filesystem.mount, v.type, v.src, v.dest, v.options)
            if not ok and not v.options.nofail then
                io.stderr:write("mount: could not mount " .. v.src .. ": " .. err .. "\n")
                retval = false
            end
        end
    end
    return retval
end
if args[1] and not args[2] and fstab[args[1]] then args[2] = fstab[args[1]].dest end
if #args < 2 then error("Usage: mount [-t type] [-o options] device [mountpoint]\n       mount -a") end
local type = args.t or (fstab[args[1]] and fstab[args[1]].type) or "craftos"
local options = (fstab[args[1]] and fstab[args[1]].options) or {
    rw = true,
    suid = true,
    dev = true,
    exec = true,
    auto = true,
    owner = true,
    async = true
}
if args.o then
    for arg in args.o:gmatch "[^,]+" do
        local k, v = arg:match "([^=]+)=?(.*)"
        if not k then k, v = arg, true end
        options[k] = v
    end
end
return filesystem.mount(type, args[1], args[2], options)