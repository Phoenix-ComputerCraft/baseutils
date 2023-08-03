local filesystem = require "system.filesystem"
local util = require "system.util"

local args = util.argparse({A = false, C = false, F = false, H = false, L = false, R = false, S = false, a = false, c = false, d = false, f = false, g = false, i = false, k = false, l = false, m = false, n = false, o = false, p = false, q = false, r = false, s = false, t = false, u = false, x = false, ["1"] = false}, ...)
if not args[1] then args[1] = "." end
if args.f then args.a, args.r, args.S, args.t = true, false, false, false end
if args.a then args.A = true end
if args.g or args.n or args.o then args.l = true end

local typemap = {file = '-', directory = 'd', fifo = 'p', link = 'l'}

-- TODO: Align columns

local function printInfo(name, stat, w)
    if args.p and stat.type == "directory" then name = name .. "/"
    elseif args.F then
        if stat.type == "directory" then name = name .. "/"
        elseif stat.type == "fifo" then name = name .. "|"
        elseif stat.type == "link" then name = name .. "@"
        elseif stat.worldPermissions.execute then name = name .. "*" end
    end
    if args.q then name = name:gsub("[\0-\31\127-\255]", "?") end
    if args.s then io.stdout:write(math.ceil(stat.size / (args.k and 1024 or 512)) .. " ") end
    if args.l then
        local aperm = stat.worldPermissions
        local uperm = stat.permissions[stat.owner] or stat.worldPermissions
        local all = (aperm.read and 'r' or '-') .. (aperm.write and 'w' or '-') .. (aperm.execute and 'x' or '-')
        local mode = ("%s%s%s%s%s%s"):format(typemap[stat.type], uperm.read and 'r' or '-', uperm.write and 'w' or '-', uperm.execute and (stat.setuser and 's' or 'x') or '-', all, all)
        local date = os.time() - stat.modified > 15552000000 and os.date("%b %e  %Y", stat.modified / 1000) or os.date("%b %e %H:%M", stat.modified / 1000)
        print(("%s %u %s %s\t%" .. w .. "u %s %s%s"):format(mode, 0 --[[TODO]], args.g and "" or stat.owner, "", math.ceil(stat.size / (args.k and 1024 or 512)), date, name, stat.type == "link" and " -> " .. stat.link or ""))
    elseif args.m then
        io.stdout:write(name .. ", ")
    elseif args.C then

    elseif args.x then

    else
        print(name)
    end
end

for _, path in ipairs(args) do
    if #args > 1 then print(path .. ":") end
    local stat, err = filesystem.stat(path, true)
    local files
    if stat then
        if stat.type == "directory" then files = filesystem.list(path)
        else path, files = filesystem.dirname(path), {filesystem.basename(path)} end
        local stats = {}
        if args.a then
            files[#files+1] = "."
            files[#files+1] = ".."
        end
        for _, f in ipairs(files) do
            if args.A or not f:match "^%." then
                local s = filesystem.stat(filesystem.combine(path, f), true)
                if s then stats[#stats+1] = {name = f, stat = s} end
            end
        end
        local cmp
        if args.r then cmp = function(a, b) return a >= b end else cmp = function(a, b) return a < b end end
        if args.S then table.sort(stats, function(a, b) if a.stat.size == b.stat.size then return cmp(a.name, b.name) else return not cmp(a.stat.size, b.stat.size) end end)
        elseif args.t then table.sort(stats, function(a, b) if a.stat.modified == b.stat.modified then return cmp(a.name, b.name) else return not cmp(a.stat.modified, b.stat.modified) end end)
        elseif not args.f then table.sort(stats, function(a, b) return cmp(a.name, b.name) end) end
        if args.l or args.s then
            local size = 0
            for _, v in ipairs(stats) do size = size + math.ceil(v.stat.size / (args.k and 1024 or 512)) end
            print("total " .. size)
        end
        local width = 0
        for _, v in ipairs(stats) do width = math.max(width, math.ceil(math.log(v.stat.size / (args.k and 1024 or 512), 10))) end
        for _, v in ipairs(stats) do printInfo(v.name, v.stat, width) end
        if args.m then print() end
    else io.stderr:write("ls: cannot access '" .. path .. "': " .. (err or "") .. "\n") end
end