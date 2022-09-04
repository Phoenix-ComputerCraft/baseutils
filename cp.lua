local util = require "system.util"
local filesystem = require "system.filesystem"

local args = assert(util.argparse({P = false, f = false, i = false, p = false, R = false, H = false, L = false, n = false}, ...))
if #args < 2 then error("cp: missing operand") end

local function copy(from, to)
    local fromstat = filesystem.stat(from)
    if not fromstat then error("cp: " .. from .. ": No such file or directory") end
    local tostat = filesystem.stat(to)
    if fromstat.type == "directory" then
        local create = false
        if not args.R then io.stderr:write("cp: -R not specified, omitting directory '" .. from .. "'\n") return false end
        if tostat then if tostat.type ~= "directory" then io.stderr:write("cp: omitting existing " .. tostat.type .. " '" .. to .. "'\n") return false end
        else
            filesystem.mkdir(to)
            create = true
        end
        local list = filesystem.list(from)
        local retval = true
        for _, v in ipairs(list) do retval = copy(filesystem.combine(from, v), filesystem.combine(to, v)) and retval end
        if create then
            filesystem.chmod(to, nil, fromstat.worldPermissions)
            for k, v in pairs(fromstat.permissions) do filesystem.chmod(to, k, v) end
            if fromstat.owner then filesystem.chown(to, fromstat.owner) end
        end
        return retval
    else
        if tostat then
            if args.i then
                io.stderr:write("overwrite " .. tostat.type .. " " .. to .. "? ")
                local p = io.read()
                if p:lower() ~= "y" then return false end
            elseif args.n then return false end
        end
        local fromfile, err = filesystem.open(from, "rb")
        if not fromfile then error("cp: " .. from .. ": " .. err, 2) end
        local tofile, err = filesystem.open(to, "wb")
        if not tofile then
            if args.f and tostat then
                filesystem.remove(to)
                tofile, err = filesystem.open(to, "wb")
            end
            if not tofile then
                fromfile.close()
                error(err, 2)
            end
        end
        repeat
            local buf = fromfile.read(512)
            if buf then tofile.write(buf) end
        until not buf
        tofile.close()
        fromfile.close()
        if args.p then
            filesystem.chmod(to, nil, fromstat.worldPermissions)
            for k, v in pairs(fromstat.permissions) do filesystem.chmod(to, k, v) end
            if fromstat.owner then filesystem.chown(to, fromstat.owner) end
        end
        return true
    end
end

local dest = table.remove(args)
if #args == 1 and not filesystem.isDir(dest) then
    return copy(args[1], dest)
else
    if not filesystem.isDir(dest) then error("cp: target is not a directory") end
    local retval = true
    for _, v in ipairs(args) do
        retval = copy(v, filesystem.combine(dest, filesystem.basename(v))) and retval
    end
    return retval
end
