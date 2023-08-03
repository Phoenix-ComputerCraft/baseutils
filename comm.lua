local util = require "system.util"
local args = assert(util.argparse({["1"] = false, ["2"] = false, ["3"] = false}, ...))
if #args < 2 then error("Usage: comm [-123] <file1> <file2>") end
local left = args[1] == "-" and io.input() or assert(io.open(args[1], "r"))
local right = args[2] == "-" and io.input() or assert(io.open(args[2], "r"))
local a, b = left, right
local al = a:read("*l")
while al do
    local bl = b:read("*l")
    if not bl then break end
    if al < bl then
        if a == left then if not args["1"] then print(al) end
        elseif not args["2"] then print((args["1"] and "" or "\t") .. al) end
        a, b = b, a
        al = bl
    elseif al == bl then
        if not args["3"] then print((args["1"] and "" or "\t") .. (args["2"] and "" or "\t") .. al) end
        al = a:read("*l")
        if not al then a, al = b, bl break end
    else -- al > bl
        if b == left then if not args["1"] then print(bl) end
        elseif not args["2"] then print((args["1"] and "" or "\t") .. bl) end
    end
end
while al do
    if a == left then if not args["1"] then print(al) end
    elseif not args["2"] then print((args["1"] and "" or "\t") .. al) end
    al = a:read("*l")
end
left:close()
if left ~= right then right:close() end