--[[
MIT License

Copyright (c) 2019-2023 JackMacWindows

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]--

local filesystem = require "system.filesystem"
local process = require "system.process"
local serialization = require "system.serialization"
local terminal = require "system.terminal"
local util = require "system.util"

local args = assert(util.argparse({c = false, i = false, s = false}, ...))
local commandPath, commandString
if args.c then commandString = table.remove(args, 1) end
if not args.s then commandPath = table.remove(args, 1) end
if not args.c and not args.s and util.syscall.istty() then args.i = true end

local shell = {}
local start_time = os.time()
local running = true
local shell_retval = 0
local execCommand
local pausedJob
local env = process.getenv()

if table.maxn == nil then table.maxn = function(t) local i = 1 while t[i] ~= nil do i = i + 1 end return i - 1 end end -- what

local function trim(s) return string.match(s, '^()%s*$') and '' or string.match(s, '^%s*(.*%S)') end

env.HOME = env.HOME or "/"
env.SHELL = process.getname()
env.PATH = env.PATH or "/bin:/sbin:/usr/bin"
env.USER = process.getuser()
env.EDITOR = env.EDITOR or "nano"
env.OLDPWD = process.getcwd()
env.PWD = env.OLDPWD
env.SHLVL = env.SHLVL and env.SHLVL + 1 or 1
env.TERM = env.TERM or "craftos"
env.COLORTERM = env.COLORTERM or "16color"

local vars = {
    PS1 = "\\s-\\v\\$ ",
    PS2 = "> ",
    IFS = "\n",
    CASH = env.SHELL,
    CASH_VERSION = "0.4.1",
    RANDOM = function() return math.random(0, 32767) end,
    SECONDS = function() return math.floor((os.time() - start_time) / 1000) end,
    HOSTNAME = "localhost", -- TODO
    TERMINATE_QUIT = "no",
    ["*"] = table.concat(args, " "),
    ["@"] = function() return table.concat(args, " ") end,
    ["#"] = #args,
    ["?"] = 0,
    ["0"] = env.SHELL,
    _ = env.SHELL,
    ["$"] = process.getpid(),
}

local opts = {}

local aliases = {}
local completion = {}
local if_table, if_statement = {}, 0
local while_table, while_statement = {}, 0
local case_table, case_statement = {}, 0
local function_name = nil
local functions = {}
local history = {}
local historyfile
local run_tokens, execv
local function_running = false
local should_break = false
local no_funcs = false
local dirstack = {}
local jobs = {}
local completed_jobs = {}

local function print(...)
    io.write(...)
    io.write("\n")
end

local builtins
builtins = {
    [":"] = function() return 0 end,
    ["."] = function(path)
        local file = io.open(path, "r")
        if not file then return 1 end
        vars.LINENUM = 1
        for line in file:lines() do 
            shell.run(line) 
            vars.LINENUM = vars.LINENUM + 1
        end
        vars.LINENUM = nil
        file:close()
    end,
    echo = function(...) print(...); return 0 end,
    builtin = function(name, ...) return builtins[name](...) end,
    cd = function(dir)
        dir = dir or "/"
        if not dir:match "^/" then dir = filesystem.combine(env.PWD, dir) end
        local ok, err = process.chdir(dir)
        if not ok then
            io.stderr:write("cash: cd: " .. dir .. ": " .. err .. "\n")
            return 1
        end
        env.OLDPWD = env.PWD
        env.PWD = dir
    end,
    command = function(...) no_funcs = true; shell.run(...); no_funcs = false; return vars["?"] end,
    complete = function() end, -- TODO
    eval = function(...) shell.run(...); return vars["?"] end,
    exec = function(...) execCommand = table.concat({...}, ' '); shell.exit() end,
    exit = function(...) return shell.exit(...) end,
    export = function(...)
        local vars = {...}
        if #vars == 0 or vars[1] == "-p" then for k,v in pairs(env) do if type(v) == "string" or type(v) == "number" then print("export " .. k .. "=" .. v) end end else
            for k,v in ipairs(vars) do
                local kk, vv = string.match(v, "(.+)=(.+)")
                if not (kk == nil or vv == nil) and (env[kk] == nil or type(env[kk]) == "string" or type(env[kk]) == "number") then env[kk] = vv end
            end
        end
    end,
    history = function(...)
        if ({...})[1] == "-c" then
            historyfile.close()
            historyfile = filesystem.open(".cash_history", "w")
            history = {}
            return
        end
        local lines = {}
        for k,v in ipairs(history) do print(" " .. k .. string.rep(" ", math.floor(math.log10(#history)) - math.floor(math.log10(k)) + 2) .. v) end
        --textutils.tabulate(table.unpack(lines))
    end,
    jobs = function(...)
        local filter = {...}
        for k,v in pairs(jobs) do if v.cmd ~= "jobs" then
            if #filter == 0 then print("[" .. k .. "]+  " .. (v.paused and "Paused" or "Running") .. "  " .. v.cmd) 
            else for l,w in ipairs(filter) do 
                if k == w then print("[" .. k .. "]+  " .. (v.paused and "Paused" or "Running") .. "  " .. v.cmd) end 
            end end 
        end end
    end,
    pushd = function(newdir)
        if newdir then
            if not newdir:match "^/" then newdir = filesystem.combine(env.PWD, newdir) end
            local ok, err = process.chdir(newdir)
            if not ok then
                io.stderr:write("cash: pushd: " .. newdir .. ": " .. err .. "\n")
                return 1
            end
        end
        table.insert(dirstack, env.PWD)
        if newdir then
            env.OLDPWD = env.PWD
            env.PWD = newdir
        end
        io.write((env.PWD == "" and "/" or env.PWD) .. " ")
        for i = #dirstack, 1, -1 do io.write((dirstack[i] == "" and "/" or dirstack[i]) .. " ") end
        print()
    end,
    popd = function()
        if #dirstack == 0 then
            io.stderr:write("cash: popd: directory stack empty\n")
            return -1
        end
        local ok, err = process.chdir(dirstack[#dirstack])
        if not ok then
            io.stderr:write("cash: popd: " .. dirstack[#dirstack] .. ": " .. err .. "\n")
            return 1
        end
        env.PWD = table.remove(dirstack, #dirstack)
        io.write((env.PWD == "" and "/" or env.PWD) .. " ")
        for i = #dirstack, 1, -1 do io.write((dirstack[i] == "" and "/" or dirstack[i]) .. " ") end
        print()
    end,
    dirs = function()
        io.write((env.PWD == "" and "/" or env.PWD) .. " ")
        for i = #dirstack, 1, -1 do io.write((dirstack[i] == "" and "/" or dirstack[i]) .. " ") end
        print()
    end,
    pwd = function() print(env.PWD) end,
    read = function(var) -- TODO: expand
        vars[var] = io.read()
    end,
    set = function(...)
        local lvars = {...}
        if #lvars == 0 then for k,v in pairs(vars) do print(k .. "=" .. v) end else
            for k,v in ipairs(lvars) do
                if v:match "^%-" then
                    for c in v:sub(2):gmatch "." do opts[c] = true end
                elseif string.find(v, "=") then
                    local kk, vv = string.match(v, "(.+)=(.+)")
                    vars[kk] = vv
                end
            end
        end
    end,
    alias = function(...)
        local vars = {...}
        if #vars == 0 or vars[1] == "-p" then for k,v in pairs(aliases) do print("alias " .. k .. "=" .. v) end else
            for k,v in ipairs(vars) do
                local kk, vv = string.match(v, "(.+)=(.+)")
                aliases[kk] = vv
            end
        end
    end,
    sleep = function(time)
        util.sleep(tonumber(time) or 0)
    end,
    test = function(...) -- TODO: add and/or
        local args = {...}
        if #args < 1 then
            io.stderr:write("cash: test: unary operator expected\n")
            return -1
        end
        local function n(v) return v end
        if args[1] == "!" then
            table.remove(args, 1)
            n = function(v) return not v end
        end
        if string.sub(args[1], 1, 1) == "-" then
            if args[2] == nil then return n(true)
            elseif args[1] == "-d" then return n((filesystem.stat(args[2]) or {}).type == "directory")
            elseif args[1] == "-e" then return n(filesystem.stat(args[2]) ~= nil)
            elseif args[1] == "-f" then return n((filesystem.stat(args[2]) or {}).type == "file")
            elseif args[1] == "-n" then return n(#args[2] > 0)
            elseif args[1] == "-s" then return n(filesystem.stat(args[2]) > 0)
            elseif args[1] == "-u" then return n((filesystem.stat(args[2]) or {}).permissions.setuid) -- TODO
            elseif args[1] == "-w" then
                local stat = filesystem.stat(args[2])
                if not stat then return n(false) end
                return n((stat.permissions[process.getuser()] or stat.worldPermissions).write)
            elseif args[1] == "-x" then
                local stat = filesystem.stat(args[2])
                if not stat then return n(false) end
                return n((stat.permissions[process.getuser()] or stat.worldPermissions).execute)
            elseif args[1] == "-z" then return n(#args[2] == 0)
            else return n(false) end
        elseif args[3] and string.sub(args[2], 1, 1) == "-" then
            if args[2] == "-eq" then return n(tonumber(args[1]) == tonumber(args[3]))
            elseif args[2] == "-ne" then return n(tonumber(args[1]) ~= tonumber(args[3]))
            elseif args[2] == "-lt" then return n(tonumber(args[1]) < tonumber(args[3]))
            elseif args[2] == "-gt" then return n(tonumber(args[1]) > tonumber(args[3]))
            elseif args[2] == "-le" then return n(tonumber(args[1]) <= tonumber(args[3]))
            elseif args[2] == "-ge" then return n(tonumber(args[1]) >= tonumber(args[3]))
            else return n(false) end
        elseif args[2] == "=" then return n(args[1] == args[3])
        elseif args[2] == "!=" then return n(args[1] ~= args[3])
        else
            io.stderr:write("cash: test: unary operator expected\n")
            return 2
        end
    end,
    time = function(...)
        if not ... then io.stderr:write("cash: time: missing program path\n") return false end
        local start = os.time()
        local v = {vars = {}, [0] = ..., select(2, ...)}
        local path, islocal = shell.resolveProgram(v[0])
        path = path or v[0]
        if not (islocal and string.find(v[0], "/") == nil) then v[0] = path end
        local pinfo = execv(v)
        if not pinfo then pinfo = {cputime = 0, systime = 0} end
        print(table.concat({...}, " "), ("%.2f user %.2f sys %.3f total"):format(pinfo.cputime, pinfo.systime, (os.time() - start) / 1000))
        return vars["?"]
    end,
    ["true"] = function() return 0 end,
    ["false"] = function() return 1 end,
    unalias = function(...) for k,v in ipairs({...}) do aliases[v] = nil end end,
    unset = function(...)
        for k,v in ipairs({...}) do
            if v:match "^%-" then
                for c in v:sub(2):gmatch "." do opts[c] = nil end
            else vars[v] = nil end
        end
    end,
    wait = function(job)
        if job then while jobs[tonumber(job)] ~= nil do sleep(0.1) end
        else while table.maxn(jobs) ~= 0 do sleep(0.1) end end
    end,
    --[[lua = function(...)
        if #({...}) > 0 then
            if filesystem.stat(...) then
                local args = {...}
                table.remove(args, 1)
                shell.run(..., table.unpack(args))
            else
                local s = table.concat({...}, " ")
                local tEnv = setmetatable({_echo = function(...) return ... end}, {__index = _ENV})
                local nForcePrint = 0
                local func, e = load( s, "lua", "t", tEnv )
                local func2, e2 = load( "return _echo("..s..");", "lua", "t", tEnv )
                if not func then
                    if func2 then
                        func = func2
                        e = nil
                        nForcePrint = 1
                    end
                else
                    if func2 then
                        func = func2
                    end
                end
                if func then
                    local tResults = table.pack( pcall( func ) )
                    if tResults[1] then
                        local n = 1
                        while n < tResults.n or (n <= nForcePrint) do
                            local value = tResults[ n + 1 ]
                            if type( value ) == "table" then
                                local metatable = getmetatable( value )
                                if type(metatable) == "table" and type(metatable.__tostring) == "function" then
                                    print( tostring( value ) )
                                else
                                    local ok, serialised = pcall( util.syscall.serialize, value )
                                    if ok then
                                        print( serialised )
                                    else
                                        print( tostring( value ) )
                                    end
                                end
                            else
                                print( tostring( value ) )
                            end
                            n = n + 1
                        end
                    else
                        io.stderr:write( tResults[2] .. "\n" )
                    end
                else
                    io.stderr:write( e .. "\n" )
                end
            end
        else shell.run("/bin/lua.lua") end
    end,]]
    cat = function(...)
        for k,v in ipairs({...}) do
            local file = filesystem.open(v, "r")
            if file ~= nil then
                print(file.readAll())
                file.close()
            end
        end
    end,
    which = function(name) local name, v = shell.resolveProgram(name); if not v and name then print(name) end end,
    ["if"] = function(...)
        shell.run(...)
        table.insert(if_table, {cond = vars["?"] == 0, inv = false})
    end,
    ["then"] = function(...) 
        if if_statement >= table.maxn(if_table) then
            io.stderr:write("cash: syntax error near unexpected token `then'\n")
            return -1
        end
        if_statement = if_statement + 1
        shell.run(...) 
        return vars["?"]
    end,
    ["else"] = function(...)
        if if_statement < 1 or if_table[if_statement].inv then
            io.stderr:write("cash: syntax error near unexpected token `else'\n")
            return -1
        end
        if_table[if_statement].inv = true
        if_table[if_statement].cond = not if_table[if_statement].cond
        shell.run(...)
        return vars["?"]
    end,
    fi = function()
        if if_statement < 1 then
            io.stderr:write("cash: syntax error near unexpected token `fi'\n")
            return -1
        end
        table.remove(if_table, if_statement)
        if_statement = if_statement - 1
    end,
    ["while"] = function(...)
        table.insert(while_table, {cond = {...}, lines = {}})
    end,
    ["do"] = function(...)
        if table.maxn(while_table) == 0 then
            io.stderr:write("cash: syntax error near unexpected token `do'\n")
            return -1
        end
        while_statement = while_statement + 1
    end,
    done = function()
        if while_statement < 1 then
            io.stderr:write("cash: syntax error near unexpected token `done'\n")
            return -1
        end
        while_statement = while_statement - 1
        if while_statement == 0 then
            local last = table.remove(while_table, while_statement + 1)
            if type(last.cond) == "function" then last.cond()
            else shell.run(table.unpack(last.cond)) end
            local cond = vars["?"]
            should_break = false
            while cond == 0 and not should_break do
                for k,v in ipairs(last.lines) do 
                    if type(v) == "function" then v()
                    else shell.run(v) end
                end
                if type(last.cond) == "function" then last.cond()
                else shell.run(table.unpack(last.cond)) end
                cond = vars["?"]
            end
        end
    end,
    ["break"] = function() should_break = true end,
    ["for"] = function(...)
        local args = {...}
        if args[2] ~= "in" then
            io.stderr:write("cash: missing `in' in for loop\n")
            return -1
        end
        local i = 2
        table.insert(while_table, {cond = function() i = i + 1; vars["?"] = args[i] ~= nil and 0 or 1 end, lines = {function() vars[args[1]] = args[i] end}})
    end,
    ["function"] = function(name, p)
        if function_name ~= nil then
            io.stderr:write("cash: syntax error near unexpected token `function'\n")
            return -1
        end
        if p ~= "{" then
            io.stderr:write("cash: syntax error near token `" .. name .. "'\n")
            return -1
        end
        function_name = name
        functions[function_name] = {}
    end,
    ["}"] = function() 
        if function_name == nil then
            io.stderr:write("cash: syntax error near unexpected token `}'\n")
            return -1
        end
        function_name = nil 
    end,
    ["return"] = function(var)
        if function_running == false then
            io.stderr:write("cash: syntax error near unexpected token `return'\n")
            return -1
        end
        function_running = false
        return var
    end,
    bg = function(t)
        if pausedJob then
            jobs[pausedJob].isfg = false
            jobs[pausedJob].paused = false
            if CCKernel2 then kernel.signal(signal.SIGCONT, jobs[pausedJob].pid) end
            pausedJob = nil
            return 0
        elseif tonumber(t) and jobs[tonumber(t)] then
            local task = tonumber(t)
            jobs[task].isfg = false
            jobs[task].paused = false
            if CCKernel2 then kernel.signal(signal.SIGCONT, jobs[task].pid) end
            return 0
        else
            io.stderr:write("cash: bg: current: no such job\n")
            return 1
        end
    end,
    fg = function(t)
        if pausedJob then 
            jobs[pausedJob].isfg = true
            jobs[pausedJob].paused = false
            if CCKernel2 then kernel.signal(signal.SIGCONT, jobs[pausedJob].pid) end
            pausedJob = nil
            return 0
        elseif tonumber(t) and jobs[tonumber(t)] then
            local task = tonumber(t)
            jobs[task].isfg = true
            jobs[task].paused = false
            if CCKernel2 then kernel.signal(signal.SIGCONT, jobs[task].pid) end
            return 0
        else
            io.stderr:write("cash: fg: current: no such job\n")
            return 1
        end
    end,
}
builtins["["] = builtins.test

function shell.exit(retval)
    running = false
    shell_retval = retval or 0
end

function shell.resolveProgram(name)
    if builtins[name] ~= nil then return name end
    if aliases[name] ~= nil then name = aliases[name] end
    for path in string.gmatch(env.PATH, "[^:]+") do
        local p = filesystem.combine(path, name)
        local stat = filesystem.stat(p)
        if stat and stat.type == "file" and (stat.permissions[process.getuser()] or stat.worldPermissions).execute then return p
        else
            p = filesystem.combine(path, name .. ".lua")
            stat = filesystem.stat(p)
            if stat and stat.type == "file" and (stat.permissions[process.getuser()] or stat.worldPermissions).execute then return p end
        end
    end
    if (filesystem.stat(name) or {}).type == "file" then return name, string.find(name, "/") == nil end
    if (filesystem.stat(name .. ".lua") or {}).type == "file" then return name .. ".lua", string.find(name, "/") == nil end
    return nil
end

local function expandVar(var)
    if string.sub(var, 1, 1) ~= "$" then return nil end
    if string.sub(var, 2, 2) == "{" then
        local varname = string.sub(string.match(var, "%b{}"), 2, -2)
        local retval = env[varname] or vars[varname]
        if type(retval) == "function" then return retval(), #varname + 2 else return retval or "", #varname + 2 end
    elseif string.sub(var, 2, 3) == "((" then
        local expr = string.gsub(string.sub(string.match(string.sub(var, 3), "%b()"), 2, -2), "%$", "")
        local fn = loadstring("return " .. expr)
        local varenv = setmetatable({}, {__index = _ENV})
        for k,v in pairs(vars) do varenv[k] = v end
        setfenv(fn, varenv)
        return tostring(fn()), #expr + 4
    elseif tonumber(string.sub(var, 2, 2)) then
        local varname = tonumber(string.match(string.sub(var, 2, 2), "[0-9]+"))
        if varname == 0 then return vars["0"], 1 else return args[varname] or "", math.floor(math.log10(varname)) + 1 end
    else
        local varname = ""
        for c in string.gmatch(string.sub(var, 2), ".") do
            if c == " " then return "", #varname end
            varname = varname .. c
            if env[varname] or vars[varname] then
                local retval = env[varname] or vars[varname]
                if type(retval) == "function" then return retval(), #varname else return retval or "", #varname end
            end
        end
        return "", #var - 1
    end
end

local function splitSemicolons(cmdline)
    local escape = false
    local quoted = false
    local j = 1
    local retval = {""}
    local lastc, lastc2
    for c in string.gmatch(cmdline, ".") do
        if lastc == '&' and c ~= '&' and lastc2 ~= '&' and not quoted and not escape then
            j=j+1
            retval[j] = ""
        end
        local setescape = false
        if c == '"' or c == '\'' and not escape then quoted = not quoted
        elseif c == '\\' and not quoted and not escape then 
            setescape = true
            escape = true
        end
        if c == ';' and not quoted and not escape then
            j=j+1
            retval[j] = ""
        elseif not (c == ' ' and retval[j] == "") then retval[j] = retval[j] .. c end
        if not setescape then escape = false end
        lastc2 = lastc
        lastc = c
    end
    return retval
end

local function tokenize(cmdline, noexpand)
    -- Expand vars
    local singleQuote = false
    local escape = false
    local expstr = ""
    local i = 1
    local function tostr(v)
        if type(v) == "boolean" then return v and "true" or "false"
        elseif v == nil then return "nil"
        elseif type(v) == "table" then return serialization.lua.encode(v)
        elseif type(v) == "string" then return v
        else return tostring(v) end
    end
    if noexpand then expstr = cmdline else
        while i <= #cmdline do
            local c = string.sub(cmdline, i, i)
            if c == '$' and not escape and not singleQuote then
                local s, n = expandVar(string.sub(cmdline, i))
                s = tostr(s)
                expstr = expstr .. s
                i = i + n
            else
                if c == '\'' and not escape then singleQuote = not singleQuote end
                escape = c == '\\' and not escape
                expstr = expstr .. c
            end
            i=i+1
        end
    end
    -- Tokenize
    local retval = {{[0] = ""}}
    i = 0
    local j = 1
    local quoted = false
    escape = false
    local lastc, filepath
    for c in string.gmatch(expstr, ".") do
        if filepath then
            if c == ';' then
                j=j+1
                i=0
                retval[j] = {[0] = ""}
            elseif lastc == '&' and c == '&' then
                retval[j][filepath] = string.sub(retval[j][filepath], 1, -2)
                j=j+1
                i=0
                retval[j] = {[0] = "", last = 0}
            elseif lastc == '|' and c == '|' then
                retval[j][filepath] = string.sub(retval[j][filepath], 1, -2)
                j=j+1
                i=0
                retval[j] = {[0] = "", last = 1}
            elseif lastc == '2' and c == '>' then
                retval[j].stderr = ""
                filepath = "stderr"
            elseif c == '>' then
                retval[j].stdout = ""
                filepath = "stdout"
            elseif c == '<' then
                retval[j].stdin = ""
                filepath = "stdin"
            elseif c ~= ' ' or retval[j][filepath] ~= "" then
                retval[j][filepath] = retval[j][filepath] .. c
            end
        elseif not escape then
            if (c == '"' or c == '\'') and not escape then quoted = not quoted
            elseif not quoted then
                if c == ' ' then
                    if #retval[j][i] > 0 then
                        i=i+1
                        retval[j][i] = ""
                    end
                elseif c == ';' then
                    if retval[j][i] == "" then retval[j][i] = nil end
                    j=j+1
                    i=0
                    retval[j] = {[0] = ""}
                elseif lastc == '&' and c == '&' then
                    retval[j][i] = string.sub(retval[j][i], 1, -2)
                    if retval[j][i] == "" then retval[j][i] = nil end
                    j=j+1
                    i=0
                    retval[j] = {[0] = "", last = 0}
                elseif lastc == '|' and c == '|' then
                    retval[j][i] = string.sub(retval[j][i], 1, -2)
                    if retval[j][i] == "" then retval[j][i] = nil end
                    j=j+1
                    i=0
                    retval[j] = {[0] = "", last = 1}
                elseif lastc == '2' and c == '>' then
                    if retval[j][i] == "" then retval[j][i] = nil end
                    retval[j].stderr = ""
                    filepath = "stderr"
                elseif c == '>' then
                    if retval[j][i] == "" then retval[j][i] = nil end
                    retval[j].stdout = ""
                    filepath = "stdout"
                elseif c == '<' then
                    if retval[j][i] == "" then retval[j][i] = nil end
                    retval[j].stdin = ""
                    filepath = "stdin"
                elseif c ~= '\\' then retval[j][i] = retval[j][i] .. c end
            else retval[j][i] = retval[j][i] .. c end
        else retval[j][i] = retval[j][i] .. c end
        escape = c == '\\' and not quoted and not escape
        lastc = c
    end
    if lastc == '&' then retval.async = true end
    for k,v in ipairs(retval) do if v[0] ~= "" then
        local path, islocal = shell.resolveProgram(v[0])
        path = path or v[0]
        if not (islocal and string.find(v[0], "/") == nil) then v[0] = path end
        v.vars = {}
        while v[0] and string.find(v[0], "=") do
            local l = string.sub(v[0], 1, string.find(v[0], "=") - 1)
            v.vars[l] = string.sub(v[0], string.find(v[0], "=") + 1)
            v.vars[l] = tonumber(v.vars[l]) or v.vars[l]
            v[0] = nil
            for i = 1, table.maxn(v) do v[i-1] = v[i]; v[i] = nil end
        end
    end end
    return retval
end

local junOff = 31 + 28 + 31 + 30 + 31 + 30
local function dayToString(day)
    if day <= 31 then return "Jan " .. day
    elseif day > 31 and day <= 31 + 28 then return "Feb " .. day - 31
    elseif day > 31 + 28 and day <= 31 + 28 + 31 then return "Mar " .. day - 31 - 28
    elseif day > 31 + 28 + 31 and day <= 31 + 28 + 31 + 30 then return "Apr " .. day - 31 - 28 - 31
    elseif day > 31 + 28 + 31 + 30 and day <= 31 + 28 + 31 + 30 + 31 then return "May " .. day - 31 - 28 - 31 - 30
    elseif day > 31 + 28 + 31 + 30 + 31 and day <= junOff then return "Jun " .. day - 31 - 28 - 31 - 30 - 31
    elseif day > junOff and day <= junOff + 31 then return "Jul " .. day - junOff
    elseif day > junOff + 31 and day <= junOff + 31 + 31 then return "Aug " .. day - junOff - 31
    elseif day > junOff + 31 + 31 and day <= junOff + 31 + 31 + 30 then return "Sep " .. day - junOff - 31 - 31
    elseif day > junOff + 31 + 31 + 30 and day <= junOff + 31 + 31 + 30 + 31 then return "Oct " .. day - junOff - 31 - 31 - 30
    elseif day > junOff + 31 + 31 + 30 + 31 and day <= junOff + 31 + 31 + 30 + 31 + 30 then return "Nov " .. day - junOff - 31 - 31 - 30 - 31
    else return "Dec " .. day - junOff - 31 - 31 - 30 - 31 - 30 end
end

local function getPrompt()
    local retval = (if_statement > 0 or while_statement > 0 or case_statement > 0) and vars.PS2 or vars.PS1 or "\\$ "
    for k,v in pairs({
        ["\\d"] = dayToString(0), -- TODO
        ["\\e"] = string.char(0x1b),
        ["\\h"] = string.sub("localhost", 1, string.find("localhost", "%.")),
        ["\\H"] = "localhost",
        ["\\n"] = "\n",
        ["\\s"] = string.gsub(vars["0"]:match("[^/]+$"), ".lua", ""),
        ["\\t"] = "00:00", --textutils.formatTime(os.time(), true),
        ["\\T"] = "00:00", --textutils.formatTime(os.time(), false),
        ["\\u"] = env.USER,
        ["\\v"] = vars.CASH_VERSION,
        ["\\V"] = vars.CASH_VERSION,
        ["\\w"] = env.PWD,
        ["\\W"] = env.PWD:match("[^/]+$") == "." and "/" or env.PWD:match("[^/]+$"),
        ["\\%#"] = vars.LINENUM,
        ["\\%$"] = env.USER == "root" and "#" or "$",
        ["\\([0-7][0-7][0-7])"] = function(n) return string.char(tonumber(n, 8)) end,
        ["\\\\"] = "\\",
        ["\\%[.+\\%]"] = ""
    }) do retval = string.gsub(retval, k, v) end
    return retval
end

function execv(tokens)
    local path = tokens[0]
    if path == nil then return end
    if #tokens == 0 and string.find(path, "=") ~= nil then
        local k = string.sub(path, 1, string.find(path, "=") - 1)
        vars[k] = string.sub(path, string.find(path, "=") + 1)
        vars[k] = tonumber(vars[k]) or vars[k]
        return
    end
    local oldenv = {}
    for k,v in pairs(tokens.vars) do
        oldenv[k] = _ENV[k]
        _ENV[k] = v
    end
    if if_statement > 0 and not if_table[if_statement].cond and path ~= "else" and path ~= "elif" and path ~= "fi" then return end
    if opts.x then print("- " .. table.concat(tokens, " ", 0)) end
    local pinfo
    if builtins[path] ~= nil then
        local input, output = io.input(), io.output()
        if tokens.stdin then io.input(tokens.stdin) end
        if tokens.stdout then io.output(tokens.stdout) end
        vars["?"] = builtins[path](table.unpack(tokens))
        if tokens.stdin then io.input():close() io.input(input) end
        if tokens.stdout then io.output():close() io.output(output) end
        if vars["?"] == nil or vars["?"] == true then vars["?"] = 0
        elseif vars["?"] == false then vars["?"] = 1 end
    elseif functions[path] ~= nil and not no_funcs then
        local oldargs = args
        args = tokens
        function_running = true
        for k,v in ipairs(functions[path]) do
            shell.run(v)
            if not function_running then break end
        end
        args = oldargs
    else
        local stat = filesystem.stat(path)
        if not stat then
            io.stderr:write("cash: " .. path .. ": No such file or directory\n")
            vars["?"] = -1
            return
        elseif not (stat.permissions[process.getuser()] or stat.worldPermissions).execute then
            io.stderr:write("cash: " .. path .. ": Permission denied\n")
            vars["?"] = -1
            return
        end
        if tokens.stdin then tokens.stdin = filesystem.open(tokens.stdin, "rb") end
        if tokens.stdout then tokens.stdout = filesystem.open(tokens.stdout, "wb") end
        if tokens.stderr then tokens.stderr = filesystem.open(tokens.stderr, "wb") end
        local _old = vars._
        vars._ = path
        if execCommand then
            if tokens.stdin then util.syscall.stdin(tokens.stdin) end
            if tokens.stdout then util.syscall.stdout(tokens.stdout) end
            if tokens.stderr then util.syscall.stderr(tokens.stderr) end
            process.exec(path, table.unpack(tokens))
            return -- the program will never reach this
        end
        local pid = process.fork(function()
            if tokens.stdin then util.syscall.stdin(tokens.stdin)
            elseif tokens.async then util.syscall.stdin(nil) end
            if tokens.stdout then util.syscall.stdout(tokens.stdout) end
            if tokens.stderr then util.syscall.stderr(tokens.stderr) end
            process.exec(path, table.unpack(tokens))
        end)
        while true do
            local name, params = coroutine.yield()
            if name == "process_complete" and params.pid == pid then
                vars["?"] = params.return_value
                break
            end
            pinfo = process.getpinfo(pid)
        end
        if tokens.stdin then tokens.stdin.close() end
        if tokens.stdout then tokens.stdout.close() end
        if tokens.stderr then tokens.stderr.close() end
        if vars["?"] == nil or vars["?"] == true then vars["?"] = 0
        elseif vars["?"] == false then vars["?"] = 1 end
        vars._ = _old
    end
    for k,v in pairs(tokens.vars) do _ENV[k] = oldenv[k] end
    return pinfo
end

function run_tokens(tokens, isAsync)
    if tokens.async and not isAsync then
        local pid = process.fork(function() return run_tokens(tokens, true) end, "cash")
        local id = #jobs + 1
        jobs[id] = {cmd = tokens[1][0] .. " " .. table.concat(tokens[1], " "), pid = pid, isfg = false, start = true}
        print("[" .. (id) .. "] " .. (pid or ""))
    else
        for _,tok in ipairs(tokens) do
            if tok[0] then
                if trim(tok[0]) ~= "" and (tok.last == 0 and vars["?"] == 0) or (tok.last == 1 and vars["?"] ~= 0) or tok.last == nil then
                    execv(tok)
                end
            else
                for k,v in pairs(tok.vars) do vars[k] = tonumber(v) or v end
            end
        end
    end
    return vars["?"] == 0
end

local run_tokens_async = function(tokens)
    local pid = process.fork(function() return run_tokens(tokens, true) end, "cash")
    local id = #jobs + 1
    jobs[id] = {cmd = tokens[1][0] and (tokens[1][0] .. " " .. table.concat(tokens[1], " ")) or "cash", pid = pid, isfg = not tokens.async, start = true}
    if tokens.async then print("[" .. (id) .. "] " .. (pid or "")) end
end

function shell.run(...)
    local cmd = table.concat({...}, " ")
    if cmd == "" or string.sub(cmd, 1, 1) == "#" then return end
    if function_name ~= nil then
        if string.find(cmd, "}") then function_name = nil
        else table.insert(functions[function_name], cmd) end
        return true
    elseif while_statement > 0 then
        local tokens = splitSemicolons(cmd)
        for k,line in ipairs(tokens) do 
            line = string.sub(line, #string.match(line, "^ *") + 1)
            if line == "do" or line == "done" or string.find(line, "^do ") or string.find(line, "^done ") then run_tokens(tokenize(line)) end
            if while_statement > 0 then table.insert(while_table[1].lines, line) end
        end
        return true
    end
    local lines = splitSemicolons(cmd)
    for k,v in ipairs(lines) do run_tokens(tokenize(v, string.sub(v, 1, 6) == "while ")) end
    return vars["?"] == 0
end

function shell.runAsync(...)
    local cmd = table.concat({...}, " ")
    if cmd == "" or string.sub(cmd, 1, 1) == "#" then return end
    if function_name ~= nil then
        if string.find(cmd, "}") then function_name = nil
        else table.insert(functions[function_name], cmd) end
        return true
    elseif while_statement > 0 then
        local tokens = splitSemicolons(cmd)
        for k,line in ipairs(tokens) do 
            line = string.sub(line, #string.match(line, "^ *") + 1)
            if line == "do" or line == "done" or string.find(line, "^do ") or string.find(line, "^done ") then run_tokens(tokenize(line)) end
            if while_statement > 0 then table.insert(while_table[1].lines, line) end
        end
        return true
    end
    local lines = splitSemicolons(cmd)
    for k,v in ipairs(lines) do run_tokens_async(tokenize(v, string.sub(v, 1, 6) == "while ")) end
    return vars["?"] == 0
end

--if topshell == nil then shell.run("rom/startup.lua") end

if filesystem.stat("/etc/cashrc") then
    local file, err = io.open("/etc/cashrc", "r")
    if not file then io.stderr:write("Could not open /etc/cashrc:", err)
    else
        for line in file:lines() do shell.run(line) end
        file:close()
    end
end
if filesystem.stat(filesystem.combine(env.HOME, ".cashrc")) then
    local file, err = io.open(filesystem.combine(env.HOME, ".cashrc"), "r")
    if not file then io.stderr:write("Could not open .cashrc:", err)
    else
        for line in file:lines() do shell.run(line) end
        file:close()
    end
end
if filesystem.stat(filesystem.combine(env.HOME, ".cash_history")) then
    local file, err = io.open(filesystem.combine(env.HOME, ".cash_history"), "r")
    if not file then io.stderr:write("Could not open .cashhistory:", err)
    else
        for line in file:lines() do table.insert(history, 1, line) end
        file:close()
    end
    historyfile = filesystem.open(filesystem.combine(env.HOME, ".cash_history"), "a")
else historyfile = filesystem.open(filesystem.combine(env.HOME, ".cash_history"), "w") end

if commandString then
    vars["0"] = commandPath
    vars.LINENUM = 1
    shell.run(commandString)
    vars.LINENUM = nil
    return shell_retval
end

if commandPath then
    if commandPath == "-" then
        vars.LINENUM = 1
        for line in io.lines() do
            shell.run(line)
            vars.LINENUM = vars.LINENUM + 1
            if not running then break end
        end
        vars.LINENUM = nil
        return shell_retval
    else
        local file = io.open(commandPath, "r")
        if not file then
            file = io.open(shell.resolveProgram(commandPath), "r")
            if not file then return 1 end
        end
        vars["0"] = commandPath
        vars.LINENUM = 1
        for line in file:lines() do
            shell.run(line)
            vars.LINENUM = vars.LINENUM + 1
            if not running then break end
        end
        file:close()
        vars.LINENUM = nil
        return shell_retval
    end
end

--[=[ TODO
local function readCommand()
    if term.getGraphicsMode and term.getGraphicsMode() then term.setGraphicsMode(false) end
    local prompt = getPrompt()
    ansiWrite(prompt)
    local str = ""
    local ox, oy = term.getCursorPos()
    local coff = 0
    local histpos = table.maxn(history) + 1
    local lastlen = 0
    local waitTab = false
    local ly = ({term.getCursorPos()})[2]
    local function redrawStr()
        term.setCursorPos(ox, oy)
        local x, y
        local i = 0
        for c in string.gmatch(str, ".") do
            if term.getCursorPos() == term.getSize() then
                if select(2, term.getCursorPos()) == select(2, term.getSize()) then
                    term.scroll(1)
                    oy = oy - 1
                    term.setCursorPos(1, select(2, term.getCursorPos()))
                else term.setCursorPos(1, select(2, term.getCursorPos()) + 1) end
            end
            if i == coff then x, y = term.getCursorPos() end
            term.write(c)
            i=i+1
        end
        if x == nil then x, y = term.getCursorPos() end
        for i = 0, lastlen - #str - 1 do write(" ") end
        if term.getCursorPos() == 1 and lastlen > #str then
            term.write(" ")
        end
        lastlen = #str
        ly = ({term.getCursorPos()})[2]
        term.setCursorPos(x, y)
    end
    term.setCursorBlink(true)
    while true do
        local ev = {os.pullEventRaw()}
        if ev[1] == "key" then
            if ev[2] == keys.enter then break
            elseif ev[2] == keys.up and history[histpos-1] ~= nil then 
                histpos = histpos - 1
                str = history[histpos]
                coff = #str
                waitTab = false
            elseif ev[2] == keys.down and history[histpos+1] ~= nil then 
                histpos = histpos + 1
                str = history[histpos]
                coff = #str
                waitTab = false
            elseif ev[2] == keys.down and histpos == table.maxn(history) then
                histpos = histpos + 1
                str = ""
                coff = 0
                waitTab = false
            elseif ev[2] == keys.left and coff > 0 then 
                coff = coff - 1
                waitTab = false
            elseif ev[2] == keys.right and coff < #str then 
                coff = coff + 1
                waitTab = false
            elseif ev[2] == keys.backspace and coff > 0 then
                str = string.sub(str, 1, coff - 1) .. string.sub(str, coff + 1)
                coff = coff - 1
                waitTab = false
            elseif ev[2] == keys.tab and coff == #str then
                local tokens = tokenize(str)[1]
                -- TODO: FIX THIS
                if completion[tokens[0]] ~= nil then
                    local t = {}
                    for i = 1, table.maxn(tokens) - 1 do t[i] = tokens[i] end
                    local res = completion[tokens[0]].fnComplete(shell, table.maxn(tokens), tokens[table.maxn(tokens)], t)
                    if res and #res > 0 then
                        local longest = res[1]
                        local function getLongest(a, b)
                            for i = 1, math.min(#a, #b) do if string.sub(a, i, i) ~= string.sub(b, i, i) then return string.sub(a, 1, i-1) end end
                            return a 
                        end
                        for k,v in ipairs(res) do longest = getLongest(longest, v) end
                        if longest == "" then
                            if not waitTab then waitTab = true else
                                for k,v in ipairs(res) do res[k] = tokens[table.maxn(tokens)] .. v end
                                print("")
                                textutils.pagedTabulate(res)
                                ansiWrite(getPrompt())
                                ox, oy = term.getCursorPos()
                            end
                        else
                            str = str .. longest
                            coff = #str
                            waitTab = false
                        end
                    end
                elseif tokens[1] == nil then
                    local res = shell.completeProgram(tokens[0])
                    if res and #res > 0 then
                        local longest = res[1]
                        local function getLongest(a, b)
                            for i = 1, math.min(#a, #b) do if string.sub(a, i, i) ~= string.sub(b, i, i) then return string.sub(a, 1, i-1) end end
                            return a 
                        end
                        for k,v in ipairs(res) do longest = getLongest(longest, v) end
                        if longest == "" then
                            if not waitTab then waitTab = true else
                                for k,v in ipairs(res) do res[k] = string.gsub(fs.getName(tokens[0]), "%.lua", "") .. v end
                                print("")
                                textutils.pagedTabulate(res)
                                ansiWrite(getPrompt())
                                ox, oy = term.getCursorPos()
                            end
                        else
                            str = str .. string.gsub(longest, "%.lua", "")
                            coff = #str
                            waitTab = false
                        end
                    end
                else
                    local res = fs.complete(tokens[table.maxn(tokens)], env.PWD, true, true)
                    if res and #res > 0 then
                        local longest = res[1]
                        local function getLongest(a, b)
                            for i = 1, math.min(#a, #b) do if string.sub(a, i, i) ~= string.sub(b, i, i) then return string.sub(a, 1, i-1) end end
                            return a 
                        end
                        for k,v in ipairs(res) do longest = getLongest(longest, v) end
                        if longest == "" then
                            if not waitTab then waitTab = true else
                                for k,v in ipairs(res) do res[k] = fs.getName(tokens[table.maxn(tokens)]) .. v end
                                print("")
                                textutils.pagedTabulate(res)
                                ansiWrite(getPrompt())
                                ox, oy = term.getCursorPos()
                            end
                        else
                            str = str .. longest
                            coff = #str
                            waitTab = false
                        end
                    end
                end
            end
        elseif ev[1] == "char" then
            str = string.sub(str, 1, coff) .. ev[2] .. string.sub(str, coff + 1)
            coff = coff + 1
            waitTab = false
        elseif ev[1] == "paste" then
            str = string.sub(str, 1, coff) .. ev[2] .. string.sub(str, coff + 1)
            coff = coff + #ev[2]
            waitTab = false
        elseif ev[1] == "terminate" then
            if vars.TERMINATE_QUIT == "yes" or vars.terminate_quit == 1 then running = false end
            str = ""
            break
        end
        redrawStr()
    end
    if ly >= ({term.getSize()})[2] then
        term.scroll(1)
        ly = ly - 1
    end
    term.setCursorPos(1, ly + 1)
    term.setCursorBlink(false)
    if str ~= "" and str ~= history[#history] then
        table.insert(history, str)
        historyfile.writeLine(str)
        historyfile.flush()
    end
    return str
end

local function jobManager()
    while running do
        if CCKernel2 then
            local e = {os.pullEventRaw()}
            if e[1] == "process_complete" then
                for k,v in pairs(jobs) do if v.pid == e[2] then 
                    jobs[k] = nil
                    completed_jobs[k] = {err = "Done", cmd = v.cmd}
                    break
                end end
            end
        else
            local delete = {}
            local e = {os.pullEventRaw()}
            for k,v in pairs(jobs) do
                if not v.paused and (v.filter == nil or v.filter == e[1]) and (v.isfg or v.start or not (
                    e[1] == "key" or e[1] == "char" or e[1] == "key_up" or e[1] == "paste" or
                    e[1] == "mouse_click" or e[1] == "mouse_up" or e[1] == "mouse_drag" or 
                    e[1] == "mouse_scroll" or e[1] == "monitor_touch")) then
                    local oldterm = term.current()
                    if v.term then term.redirect(v.term) end
                    local ok, filter = coroutine.resume(v.coro, table.unpack(e))
                    v.term = term.redirect(oldterm)
                    if coroutine.status(v.coro) == "dead" then
                        table.insert(delete, k)
                        completed_jobs[k] = {err = "Done", cmd = v.cmd, isfg = v.isfg}
                        os.queueEvent("job_complete", k)
                    elseif not ok then
                        table.insert(delete, k)
                        completed_jobs[k] = {err = filter, cmd = v.cmd, isfg = v.isfg}
                        os.queueEvent("job_complete", k)
                    end
                    v.filter = filter
                    v.start = false
                end
            end
            for k,v in ipairs(delete) do jobs[v] = nil end
        end
    end
end

parallel.waitForAny(function()
    while running do 
        for k,v in pairs(completed_jobs) do if not v.isfg then print("[" .. k .. "]+  " .. v.err .. "  " .. v.cmd) end end
        completed_jobs = {}
        shell.runAsync(readCommand())
        while #jobs > 0 do
            local b = true
            for k,v in pairs(jobs) do if v.isfg and not v.paused then b = false; break end end
            if b then break end
            if os.pullEventRaw() == "terminate" then
                for k,v in pairs(jobs) do if v.isfg and not v.paused then
                    jobs[k] = nil
                    print("^T")
                    b = true
                    break
                end end
            end
            if b then break end
        end
    end
end, function()
    local ctrlHeld = false
    while running do
        local ev = {os.pullEventRaw()}
        if ev[1] == "key" and (ev[2] == keys.leftCtrl or ev[2] == keys.rightCtrl) then ctrlHeld = true
        elseif ev[1] == "key_up" and (ev[2] == keys.leftCtrl or ev[2] == keys.rightCtrl) then ctrlHeld = false
        elseif ctrlHeld and ev[1] == "key" and ev[2] == keys.z then
            print("^Z")
            for k,v in pairs(jobs) do if v.isfg and not v.paused then 
                v.paused = true
                if CCKernel2 then kernel.signal(signal.SIGSTOP, v.pid) end
                pausedJob = k
                print("[" .. k .. "]+  Paused  " .. v.cmd)
                os.queueEvent("job_paused")
                break
            end end
        end
    end
end, jobManager)
]=]

while running do
    if args.i then
        local prompt = getPrompt()
        io.stdout:write(prompt)
    end
    local str = terminal.readline2(history, function(partial)
        if partial:find " " then
            local path = partial:match "%S*$"
            local pathopts = filesystem.find(path .. "*")
            for i, v in ipairs(pathopts) do
                if filesystem.isDir(v) then pathopts[i] = v:gsub("^" .. path:gsub("[%^%$%(%)%[%]%%%.%*%+%-%?]", "%%%1"), "") .. "/"
                else pathopts[i] = v:gsub("^" .. path:gsub("[%^%$%(%)%[%]%%%.%*%+%-%?]", "%%%1"), "") .. " " end
            end
            table.sort(pathopts)
            return pathopts
        else
            local cmdopts = {}
            for k in pairs(builtins) do if k:sub(1, #partial) == partial then cmdopts[#cmdopts+1] = k:sub(#partial + 1) .. " " end end
            for k in pairs(functions) do if k:sub(1, #partial) == partial then cmdopts[#cmdopts+1] = k:sub(#partial + 1) .. " " end end
            for path in env.PATH:gmatch "[^:]+" do
                path = filesystem.combine(path, partial)
                local pathopts = filesystem.find(path .. "*")
                for _, v in ipairs(pathopts) do cmdopts[#cmdopts+1] = v:gsub("^" .. path:gsub("[%^%$%(%)%[%]%%%.%*%+%-%?]", "%%%1"), ""):gsub("%.lua$", "") .. " " end
            end
            table.sort(cmdopts)
            return cmdopts
        end
    end)
    if args.i then
        if historyfile and str ~= "" and str ~= history[1] then
            table.insert(history, 1, str)
            historyfile.writeLine(str)
            historyfile.flush()
        end
    end
    shell.run(str)
end

if execCommand then shell.run(execCommand); return vars["?"] end

historyfile.close()
return shell_retval