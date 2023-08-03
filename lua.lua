local pretty = require "system.pretty"
local terminal = require "system.terminal"
local util = require "system.util"

local args = assert(util.argparse({h = false, help = false, e = true, l = true, i = false, v = false}, ...))
for i, v in ipairs(args) do if v == "--" then table.remove(args, i) break end end

if args.h then
    print[=[
usage: lua [options] [script [args]].
Available options are:
  -e stat  execute string 'stat'
  -l name  require library 'name'
  -i       enter interactive mode after executing 'script'
  -v       show version information
  --       stop handling options
  -        execute stdin and stop handling options
]=]
    return 0
elseif args.v then
    print(_VERSION, "Copyright (C) 2021 JackMacWindows")
    return 0
end

if args.l then _ENV[args.l] = require(args.l) end
if args.e then assert(load(args.e, "=(command line)", "t"))() end

if args[1] then
    local fn
    if args[1] == "-" then fn = assert(load(function() return io.stdin:read("*L") end, "=stdin"))
    else fn = assert(load(args[1], "@" .. args[1])) end
    fn(table.unpack(args, 2, #args))
    if not args.i then return 0 end
end

exit = setmetatable({}, {__tostring = function() return "Press Ctrl+D or Ctrl+C to exit" end})
quit = exit

print(_VERSION, "Copyright (C) 2021 JackMacWindows")
local history = {}
while true do
    local buf = ""
    local fn, err
    repeat
        if buf == "" then io.stdout:write("> ")
        else io.stdout:write(">> ") end
        local inp = terminal.readline2(history)
        if not inp then print() return 0 end
        buf = buf .. inp .. "\n"
        fn, err = load("return " .. buf, "=stdin")
        if not fn then fn, err = load(buf, "=stdin") end
    until fn or not err:match("<eof>")
    if fn then
        local res = table.pack(pcall(fn))
        if res[1] then for i = 2, res.n do pretty.print(pretty.pretty(res[i], {function_source = true, function_args = true})) end
        else io.stderr:write(res[2] .. "\n") end
    else io.stderr:write(err .. "\n") end
    table.insert(history, 1, buf:sub(1, -2))
end
