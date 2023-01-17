local filesystem = require "system.filesystem"
local process = require "system.process"
local util = require "system.util"
local args = assert(util.argparse({
    userspec = true,
    ["skip-chdir"] = false
}, ...))
if process.getuser() ~= "root" then error("This program requires root.") end
local path = table.remove(args, 1)
if not path then error("Usage: chroot [options] <path> [program] [args...]") end
if #args == 0 then args[1], args[2] = process.getenv().SHELL or "/bin/sh", "-i" end
filesystem.chroot(path)
if not args["skip-chdir"] then process.chdir("/") end
if args.userspec then process.setuser(args.userspec) end
return process.execp(table.unpack(args))
