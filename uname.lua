local util = require "system.util"
local args = assert(util.argparse({a = false, m = false, n = false, r = false, s = false, v = false}, ...))
if next(args) == nil then args.s = true end
if args.a then args.m, args.n, args.r, args.s, args.v = true, true, true, true, true end
local fields = {}
if args.s then fields[#fields+1] = "Phoenix" end
if args.n then fields[#fields+1] = util.syscall.devinfo("/").name end
if args.r then fields[#fields+1] = util.syscall.version() end
if args.v then fields[#fields+1] = util.syscall.version(true) end
if args.m then fields[#fields+1] = util.syscall.cchost() end
print(table.concat(fields, " "))