local filesystem = require "system.filesystem"
local p = false
local function rmdir(path)
    if not filesystem.isDir(path) or #filesystem.list(path) > 0 then error("rmdir: " .. path .. ": directory not empty") end
    filesystem.remove(path)
    if p and path:find "/" then return rmdir(filesystem.dirname(path)) end
end
for _, v in ipairs{...} do
    if v == "-p" then p = true
    else rmdir(v) end
end
