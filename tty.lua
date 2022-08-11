local process = require "system.process"
local info = process.getpinfo(process.getpid())
if info.stdout then print("tty" .. info.stdout) end