local process = require "system.process"
local util = require "system.util"
local args = assert(util.argparse({n = "number"}, ...))
if not args[1] then error("Usage: nice [-n <increment>] <program> [args...]") end
local pid = process.fork(function()
    process.nice(args.n or 10)
    process.execp(table.unpack(args))
end, args[1])
local event, param
repeat event, param = coroutine.yield()
until event == "process_complete" and param.id == pid
return param.value
