local filesystem = require "system.filesystem"
local util = require "system.util"
local args = assert(util.argparse({
    k = false, apropos = "@k",
    P = true, pager = "@P",
    M = true, manpath = "@M",
    S = true, s = "@S", sections = "@S",
    r = true, prompt = "@r",
    u = false, update = "@u"
}, ...))
local manpath = args.M or os.getenv("MANPATH") or "/usr/share/man"
local sects = args.S or os.getenv("MANSECT") or "1 8 3 2 5 4 9 6 7"
local keywords = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["until"] = true,
    ["while"] = true,
}
local constants = {
    ["false"] = true,
    ["nil"] = true,
    ["true"] = true,
}
if args.u then
    for path in manpath:gmatch "[^:]+" do
        local db = assert(io.open(filesystem.combine(path, ".mandb"), "w"))
        for _, v in ipairs(filesystem.list(path)) do if v:match "^man" then
            for _, w in ipairs(filesystem.list(filesystem.combine(path, v))) do
                local text = w:match("^[^%.]+") .. "(" .. v:sub(4) .. "): "
                local file = io.open(filesystem.combine(path, v, w), "r")
                if file then
                    for line in file:lines() do
                        local summary = line:match("<summary>(.-)</summary>")
                        if summary then text = text .. summary break end
                    end
                    file:close()
                end
                db:write(text .. "\n")
            end
        end end
        db:close()
    end
    return true
elseif args.k then
    for _, arg in ipairs(args) do
        for path in manpath:gmatch "[^:]+" do
            local db = io.open(filesystem.combine(path, ".mandb"), "r")
            if db then
                for line in db:lines() do
                    if line:match(arg) then print(line) end
                end
                db:close()
            end
        end
    end
    return true
end
if #args > 1 and args[1]:match("^%d") then sects = table.remove(args, 1) end
for _, arg in ipairs(args) do
    for path in manpath:gmatch "[^:]+" do
        local found = nil
        for sect in sects:gmatch "[0-9a-z]+" do
            if filesystem.exists(filesystem.combine(path, "man" .. sect, arg .. ".md")) then
                found = filesystem.combine(path, "man" .. sect, arg .. ".md")
                break
            elseif filesystem.exists(filesystem.combine(path, "man" .. sect, arg)) then
                found = filesystem.combine(path, "man" .. sect, arg)
                break
            end
        end
        if found then
            local text = ""
            local newline = true
            local code = false
            for line in io.lines(found) do
                if code then
                    if line == "```" then
                        code = false
                        newline = true
                        text = text .. "\x1b[0m\n"
                    else
                        if code == "lua" then
                            line = line:gsub("%f[%d](%d+)%f[%D]", "\x1b[94m%1\x1b[37m")
                                       :gsub("%-%-.*$", "\x1b[32m%0\x1b[37m")
                                       :gsub("%f[\\'\"]['\"].*%f[\\'\"]['\"]", "\x1b[31m%0\x1b[37m")
                            for k in pairs(keywords) do line = line:gsub("%f[0-9A-Za-z_]" .. k .. "%f[^0-9A-Za-z_]", "\x1b[93m%0\x1b[37m") end
                            for k in pairs(constants) do line = line:gsub("%f[0-9A-Za-z_]" .. k .. "%f[^0-9A-Za-z_]", "\x1b[34m%0\x1b[37m") end
                        end
                        text = text .. line .. "\n"
                    end
                else
                    if line:match "^#" then
                        if not newline then text = text .. "\n" end
                        text = text .. "\x1b[92m" .. line:match "^#+%s*(.*)$" .. "\x1b[0m\n"
                        newline = true
                    elseif line:match "^%s*[%-%*]%s+" then
                        if not newline then text = text .. "\n" end
                        text = text .. line:match "^(%s*)" .. " \7 " .. line:match "^%s*[%-%*]%s+(.*)$" .. "\n"
                        newline = true
                    elseif line:match "^%d+%.%s" then
                        if not newline then text = text .. "\n" end
                        text = text .. line .. "\n"
                        newline = true
                    elseif line:match "^>%s" then
                        if not newline then text = text .. "\n" end
                        text = text .. "\x1b[47m\x1b[30m\x95\x1b[49m\x1b[37m " .. line:match "^>%s+(.*)$" .. "\x1b[0m\n"
                        newline = true
                    elseif line:match "^%-%-%-" then
                        if not newline then text = text .. "\n" end
                        text = text .. "\x8C\x8C\x8C\x8C\x8C\x8C\x8C\x8C\x8C\x8C\n"
                        newline = true
                    elseif line:match "<summary>.*</summary>" then -- nothing
                    elseif line:match "^```" then
                        if line == "```lua" then code = "lua" else code = true end
                        if not newline then text = text .. "\n" end
                        text = text .. "\x1b[37m"
                    else
                        line = line:gsub("%f[\\%*]%*%*(%S.-)%f[\\%*]%*%*", "\x1b[94m%1\x1b[0m")
                                   :gsub("%f[\\%*]%*(%S.-)%f[\\%*]%*", "\x1b[92m%1\x1b[0m")
                                   :gsub("%f[\\`]`(.-)%f[\\`]`", "\x1b[37m%1\x1b[0m")
                                   :gsub("\\x(%x%x)", function(s) return string.char(tonumber(s, 16)) end)
                                   :gsub("\\e", "\x1b")
                        text = text .. line .. " "
                        newline = false
                    end
                    if not newline then
                        if line:match "^%s*$" then text = text .. "\n\n" newline = true
                        elseif line:match "%s%s$" then text = text .. "\n" newline = true end
                    end
                end
            end
            io.popen(args.P or ("/bin/less -P '" .. (args.r or ("Manual page " .. arg)) .. "'"), "w"):write(text .. "\n"):close()
            break
        end
    end
end
