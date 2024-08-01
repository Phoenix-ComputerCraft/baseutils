local network = require "system.network"
local serialization = require "system.serialization"
local util = require "system.util"

local function urlencode(str)
    return str:gsub("[^A-Za-z0-9%-_%.~]", function(c) return ("%%%02X"):format(c:byte()) end)
end

local statuses = {
    [100] = "Continue",
    [101] = "Switching Protocols",
    [102] = "Processing",
    [200] = "OK",
    [201] = "Created",
    [202] = "Accepted",
    [203] = "Non-authoritative Information",
    [204] = "No Content",
    [205] = "Reset Content",
    [206] = "Partial Content",
    [207] = "Multi-Status",
    [208] = "Already Reported",
    [226] = "IM Used",
    [300] = "Multiple Choices",
    [301] = "Moved Permanently",
    [302] = "Found",
    [303] = "See Other",
    [304] = "Not Modified",
    [305] = "Use Proxy",
    [307] = "Temporary Redirect",
    [308] = "Permanent Redirect",
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [402] = "Payment Required",
    [403] = "Forbidden",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [406] = "Not Acceptable",
    [407] = "Proxy Authentication Required",
    [408] = "Request Timeout",
    [409] = "Conflict",
    [410] = "Gone",
    [411] = "Length Required",
    [412] = "Precondition Failed",
    [413] = "Payload Too Large",
    [414] = "Request-URI Too Long",
    [415] = "Unsupported Media Type",
    [416] = "Requested Range Not Satisfiable",
    [417] = "Expectation Failed",
    [418] = "I'm a teapot",
    [421] = "Misdirected Request",
    [422] = "Unprocessable Entity",
    [423] = "Locked",
    [424] = "Failed Dependency",
    [426] = "Upgrade Required",
    [428] = "Precondition Required",
    [429] = "Too Many Requests",
    [431] = "Request Header Fields Too Large",
    [444] = "Connection Closed Without Response",
    [451] = "Unavailable For Legal Reasons",
    [499] = "Client Closed Request",
    [500] = "Internal Server Error",
    [501] = "Not Implemented",
    [502] = "Bad Gateway",
    [503] = "Service Unavailable",
    [504] = "Gateway Timeout",
    [505] = "HTTP Version Not Supported",
    [506] = "Variant Also Negotiates",
    [507] = "Insufficient Storage",
    [508] = "Loop Detected",
    [510] = "Not Extended",
    [511] = "Network Authentication Required",
    [599] = "Network Connect Timeout Error"
}

local args = assert(util.argparse({
    [""] = {
        stopProcessingOnPositionalArgument = true
    },
    A = true, ["user-agent"] = "@A",
    b = true, cookie = "@b",
    c = true, ["cookie-jar"] = "@c",
    d = "multiple", data = "@d", ["data-ascii"] = "@d",
    D = true, ["dump-header"] = "@D",
    e = true, referer = "@e",
    G = false, get = "@G",
    H = "multiple", header = "@H",
    I = false, head = "@I",
    i = false, include = "@i",
    J = false, ["remote-header-name"] = "@J",
    L = false, location = "@L",
    o = true, output = "@o",
    O = false, ["remote-name"] = "@O",
    r = true, range = "@r",
    R = false, run = "@R",
    s = false, silent = "@s",
    S = false, ["show-error"] = "@S",
    T = true, ["upload-file"] = "@T",
    u = true, user = "@u",
    v = false, verbose = "@v",
    X = true, request = "@X",
    ["#"] = false, ["progress-bar"] = "@#",
    basic = false,
    ["data-binary"] = "multiple",
    ["data-raw"] = "multiple",
    ["data-urlencode"] = "multiple",
    digest = false,
    ["disallow-username-in-url"] = false,
    ["doh-url"] = true,
    json = true,
    ["location-trusted"] = false,
    ["oauth2-bearer"] = true,
    ["output-dir"] = true,
    post301 = false, post302 = false, post303 = false,
    retry = "number",
    ["retry-delay"] = "number",
    h = false, help = "@h"
}, ...))

if args.h then
    print[[
Usage: curl [options...] URL
Options:
  -o, --output <path>     Path to write to
  -H, --header <header>   Add a header to the request
      --run               Run the file as a Lua script
  -h, --help              Show this help
]]
    return
end

local url = args[1]
if not url then error("curl: Missing URL.") end
local headers = {}
if args.H then for _, v in ipairs(args.H) do
    local k, vv = v:match("^([^:]+):%s*(.+)$")
    if not k then error("curl: Malformed header " .. v) end
    headers[k] = vv
end end
if args.A then headers["User-Agent"] = args.A end
if args.b then

end
if args.c then

end
if args.e then headers["Referer"] = args.e end
if args.u then
    if not args.u:find ":" then
        io.stdout:write("Password: ")
        terminal.termctl({echo = false})
        args.u = args.u .. ":" .. io.stdin:read()
        terminal.termctl({echo = true})
        print()
    end
    if args.basic then headers["Authorization"] = "Basic " .. serialization.base64.encode(args.u)
    elseif args.digest then -- todo
    elseif args["oauth2-bearer"] then headers["Authorization"] = "Bearer " .. args["oauth2-bearer"]
    else url = url:gsub("^(https?://)", "%1" .. args.u) end
end

local data
if args.d then for _, v in ipairs(args.d) do
    if data then data = data .. "&" else data = "" end
    if v:sub(1, 1) == "@" then
        local path = v:sub(2):gsub("[\r\n]", "")
        local file, err = io.open(path, "r")
        if not file then error("curl: Could not open " .. path .. ": " .. err) end
        data = data .. file:read("*a")
        file:close()
    else data = data .. v end
end end
if args["data-raw"] then for _, v in ipairs(args["data-raw"]) do
    if data then data = data .. "&" else data = "" end
    data = data .. v
end end
if args["data-binary"] then for _, v in ipairs(args["data-binary"]) do
    if data then data = data .. "&" else data = "" end
    if v:sub(1, 1) == "@" then
        local path = v:sub(2):gsub("[\r\n]", "")
        local file, err = io.open(path, "rb")
        if not file then error("curl: Could not open " .. path .. ": " .. err) end
        data = data .. file:read("*a")
        file:close()
    else data = data .. v end
end end
if args["data-urlencode"] then for _, v in ipairs(args["data-urlencode"]) do
    if data then data = data .. "&" else data = "" end
    local name, content = v:match "^([^=]+)=(.+)$"
    local fname, path = v:match "^([^@]*)@(.*)$"
    if name then
        data = data .. name .. "=" .. urlencode(content)
    elseif fname then
        if fname ~= "" then data = data .. fname .. "=" end
        local file, err = io.open(path, "r")
        if not file then error("curl: Could not open " .. path .. ": " .. err) end
        data = data .. urlencode(file:read("*a"))
        file:close()
    else data = data .. v end
end end
if args.json then
    if data then data = data .. "&" else data = "" end
    if args.json:sub(1, 1) == "@" then
        local path = args.json:sub(2):gsub("[\r\n]", "")
        local file, err = io.open(path, "rb")
        if not file then error("curl: Could not open " .. path .. ": " .. err) end
        data = data .. file:read("*a")
        file:close()
    else data = data .. args.json end
    headers["Content-Type"] = "application/json"
    headers["Accept"] = "application/json"
end

local method
if args.X then method = args.X:upper()
elseif args.G then
    method = "GET"
    if data then url = url .. "?" .. data end
elseif args.I then method = "HEAD"
elseif args.T then
    method = "PUT"
    local file, err = io.open(args.T, "rb")
    if not file then error("curl: Could not open " .. args.T .. ": " .. err) end
    data = file:read("*a")
    file:close()
elseif data then method = "POST"
else method = "GET" end

if args.v then
    io.stderr:write("* Opening connection to " .. url:match("^https?://([^/]+)") .. "\n")
    io.stderr:write("> GET " .. url:match("^https?://[^/]+(/[^#]+)") .. " HTTP/1.1\n")
    for k, v in pairs(headers) do io.stderr:write("> " .. k .. ": " .. v .. "\n") end
    io.stderr:write("> \n")
end

local handle
for _ = 0, args.retry or 0 do
    handle = network.connect{url = url, method = method, headers = headers, redirect = args.L}
    handle:write(data)
    local ok = false
    while true do
        local event, param = coroutine.yield()
        if event == "handle_status_change" and param.id == handle.id then
            if param.status == "open" then ok = true break
            elseif param.status == "error" then
                io.stderr:write(select(2, handle:status()))
                handle = nil
                break
            end
        end
    end
    if ok then break end
end
if not handle then return false end

local code = handle:responseCode()
local inheaders = handle:responseHeaders()

if args.o then io.output(args.o)
elseif args.O then
    local name = url:gsub("%?.*$", ""):gsub("#.*$", ""):match("([^/]+)/*$")
    if args.J then name = inheaders["Content-Disposition"] or name end
    if args["output-dir"] then name = args["output-dir"] .. "/" .. name end
    io.output(name)
end
if args.v or args.i then
    local p = function(s) return io.write(s) end
    if args.v then p = function(s) return io.stderr:write("< ".. s) end end
    p("HTTP/1.1 " .. code .. " " .. (statuses[code] or "Unknown"))
    for k, v in pairs(inheaders) do p(k .. ": " .. v) end
    p("")
end
if args.D then
    local file, err = io.open(args.D, "w")
    if file then
        for k, v in pairs(inheaders) do file:write(k .. ": " .. v .. "\n") end
        file:close()
    else io.stderr:write("curl: Could not open header dump file: " .. err .. "\n") end
end
if args.R then
    if math.floor(code / 100) ~= 2 then error("curl: Got HTTP response " .. code .. ", not running data.") end
    local name = url:gsub("%?.*$", ""):gsub("#.*$", ""):match("([^/]+)/*$")
    if args.J then name = inheaders["Content-Disposition"] or name end
    local fn, err = load(function() return handle:read("*L") end, "=" .. name)
    if not fn then error("curl: Could not load file: " .. err) end
    return fn(table.unpack(args, 2, args.n))
end
io.write(handle:read("*a"))
handle:close()
io.output():close()
