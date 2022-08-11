local util = require "system.util"
local args = assert(util.argparse({l = false, s = false}, ...))
if #args < 2 then error("usage: cmp [-ls] <file1> <file2>") end
local fileA, fileB
if args[1] == "-" then fileA = io.stdin
else fileA = io.open(args[1], "rb") end
if args[2] == "-" then fileB = io.stdin
else fileB = io.open(args[2], "rb") end
local function close(n)
    if fileA ~= io.stdin then fileA:close() end
    if fileB ~= io.stdin then fileB:close() end
    return n
end
if fileA == fileB then return close(0) end
local line, retval = 1, 0
for i = 1, math.huge do
    local a = fileA:read(1)
    local b = fileB:read(1)
    if a ~= b then
        retval = 1
        if not a then
            if not args.s then io.stderr:write("cmp: EOF on " .. args[1] .. "\n") end
        elseif not b then
            if not args.s then io.stderr:write("cmp: EOF on " .. args[2] .. "\n") end
        elseif not args.s then
            if args.l then io.write(i .. " " .. a .. " " .. b .. "\n")
            else io.write(("%s %s differ: char %d, line %d\n"):format(args[1], args[2], i, line)) end
        end
        if not args.l then return close(1) end
    end
    if a == "\n" then line = line + 1 end
    if not a or not b then break end
end
return close(retval)