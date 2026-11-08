local helper = {}
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/")
local src = dir .. "/focus-space.m"

-- Run external operations without blocking Hammerspoon's event loop.
local activeTask
local function runTask(path, args, callback)
    local task = hs.task.new(path, function(code, output, err)
        activeTask = nil
        callback(code == 0, output, err)
    end, args)
    if not task then callback(false, nil, "could not create task"); return end
    activeTask = task
    if not task:start() then
        activeTask = nil
        callback(false, nil, "could not start task")
    end
end

local function binaryAsync(callback)
    local cacheDir = os.getenv("HOME") .. "/Library/Caches/hammerspoon"
    local bin = cacheDir .. "/focus-space"
    local source = hs.fs.attributes(src)
    if not source then callback(nil); return end
    local built = hs.fs.attributes(bin)
    if built and built.modification >= source.modification then callback(bin); return end
    hs.fs.mkdir(cacheDir)
    runTask("/usr/bin/clang", {"-fobjc-arc", "-framework", "Cocoa", "-F/System/Library/PrivateFrameworks", "-framework", "SkyLight", "-O2", "-o", bin, src}, function(ok, _, err)
        if not ok then print("focus-space: compile failed: " .. (err or "")) end
        callback(ok and bin or nil)
    end)
end

local busy = false
function helper.moveWindowAsync(winID, spaceID, callback)
    if busy then return false end
    busy = true
    local function finish(ok)
        busy = false
        callback(ok)
    end
    binaryAsync(function(bin)
        if not bin then finish(false); return end
        runTask(bin, {"move", tostring(winID), tostring(spaceID)}, function(ok, _, err)
            if not ok then print("focus-space: move failed: " .. (err or "")) end
            finish(ok)
        end)
    end)
    return true
end

return helper
