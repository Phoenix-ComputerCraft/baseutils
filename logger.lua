-- syntax:
-- logger log [-n <log>] [-c <category>] [-l debug|info|notice|warning|error|critical] [-m <module>] <message...>
-- logger create [-F <path>] [-s] <log>
-- logger delete [-p] <log>
-- logger view <log>
-- logger follow [-f <filter>] <log>

local log = require "system.log"
local process = require "system.process"
local util = require "system.util"

local loglevels = {
    [0] = "Debug",
    "Info",
    "Notice",
    "Warning",
    "Error",
    "Critical",
    "Panic"
}

local logcolors = {[0] = '\27[90m', '\27[97m', '\27[36m', '\27[93m', '\27[31m', '\27[95m', '\27[96m'}

local args = {...}
local cmd = table.remove(args, 1)
if cmd == "log" then
    args = assert(util.argparse({c = true, l = true, m = true, n = true}, table.unpack(args)))
    log.log({name = args.n, level = args.l, category = args.c, module = args.m}, table.unpack(args))
elseif cmd == "create" then
    args = assert(util.argparse({F = true, s = false}, table.unpack(args)))
    if not args[1] then error("Usage: logger create [-F <file>] [-s] <log>") end
    log.create(args[1], args.s, args.F)
elseif cmd == "delete" then
    args = assert(util.argparse({p = true}, table.unpack(args)))
    if not args[1] then error("Usage: logger delete [-p] <log>") end
    log.remove(args[1])
    if args.p then os.remove("/var/log/" .. args[1] .. ".log") end
elseif cmd == "view" then
    if not args[1] then error("Usage: logger view <log>") end
    process.run("/bin/less", "/var/log/" .. args[1] .. ".log")
elseif cmd == "follow" then
    args = assert(util.argparse({f = true}, table.unpack(args)))
    if not args[1] then error("Usage: logger follow [-f <filter>] <log>") end
    log.open(args[1], args.f)
    print("Listening for messages...")
    while true do
        local event, options = coroutine.yield()
        if event == "syslog" then
            if options.traceback then
                options.message = options.message:gsub("\t", "  ")
                         :gsub("([^\n]+):(%d+):", "\27[96m%1\27[37m:\27[95m%2\27[37m:")
                         :gsub("'([^']+)'\n", "\27[93m'%1'\27[37m\n")
            end
            local info = process.getpinfo(options.process)
            print(("%s[%s]%s %s[%d%s]%s [%s]: %s\27[0m"):format(
                logcolors[options.level],
                os.date("%b %d %X", options.time / 1000),
                options.category and " <" .. options.category .. ">" or "",
                info and info.name or "(unknown)",
                options.process,
                options.thread and ":" .. options.thread or "",
                options.module and " (" .. options.module .. ")" or "",
                loglevels[options.level],
                options.message
            ))
        end
    end
else
    error("Usage: logger <log|create|delete|view|follow> ...")
end
