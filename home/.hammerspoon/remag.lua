-- Each layout changes the window size; centering is shared below.
-- Adjust these functions or add another binding to customize the shortcuts.
local function center(frame, screen)
    return frame, hs.window.animationDuration
end

local function fitWidth(frame, screen)
    frame.w = math.floor((screen.w - 10) * 0.8)
    frame.h = screen.h - 10
    return frame
end

local function fitSixtyByEighty(frame, screen)
    frame.w = math.floor(screen.w * 0.6)
    frame.h = math.floor(screen.h * 0.8)
    return frame
end

-- The ratio defines the bounding box. preserveWindowRatio fits the existing
-- window inside that box; otherwise the window takes the box's aspect ratio.
local function fitAspect(options)
    return function(frame, screen)
        local w, h = options.width, options.height
        local unit
        if options.screenWidth then
            unit = math.floor((screen.w * options.screenWidth + w - 1) / w)
        else
            unit = math.floor((screen.h * options.screenHeight + h - 1) / h)
        end
        unit = math.min(unit, math.floor(screen.w / w), math.floor(screen.h / h))
        local maxW, maxH = unit * w, unit * h
        if options.preserveWindowRatio then
            if frame.w <= 0 or frame.h <= 0 then return nil end
            local aspect = frame.h / frame.w
            if maxW * aspect <= maxH then
                frame.w, frame.h = maxW, math.floor(maxW * aspect + 0.5)
            else
                frame.w, frame.h = math.floor(maxH / aspect + 0.5), maxH
            end
        else
            frame.w, frame.h = maxW, maxH
        end
        return frame
    end
end

local function bindLayout(key, calculate)
    hs.hotkey.bind({"ctrl", "alt"}, key, function()
        local win = hs.window.focusedWindow()
        if not win then return end
        local screen = win:screen()
        if not screen then return end
        local bounds = screen:frame()
        local frame, duration = calculate(win:frame(), bounds)
        if not frame then return end
        frame.x = math.floor(bounds.x + (bounds.w - frame.w) / 2)
        frame.y = math.floor(bounds.y + (bounds.h - frame.h) / 2)
        win:setFrame(frame, duration or 0)
    end)
end

local function maximize()
    local win = hs.window.focusedWindow()
    if win then win:maximize(0) end
end

local function toggleFullScreen()
    local win = hs.window.focusedWindow()
    if win then win:toggleFullScreen() end
end

local spaceHelper = require "lib.focus-space"
local function userSpaces(screen)
    local result = {}
    for _, sid in ipairs(hs.spaces.spacesForScreen(screen) or {}) do
        if hs.spaces.spaceType(sid) == "user" then result[#result + 1] = sid end
    end
    return result
end

-- Move the window, then focus it to follow to its new Space.
local function moveToAdjacentSpace(delta)
    local win = hs.window.focusedWindow()
    if not win or win:isFullScreen() then return end
    local screen = win:screen()
    if not screen then return end
    local current = hs.spaces.activeSpaceOnScreen(screen)
    local spaces = userSpaces(screen)
    local index
    for i, sid in ipairs(spaces) do
        if sid == current then index = i; break end
    end
    if not index then return end
    local function move(target)
        spaceHelper.moveWindowAsync(win:id(), target, function(ok)
            if ok then win:focus() end
        end)
    end
    if #spaces > 1 then
        move(spaces[((index - 1 + delta) % #spaces) + 1])
        return
    end

    hs.spaces.openMissionControl()
end

hs.hotkey.bind({"shift", "alt"}, "left", function() moveToAdjacentSpace(-1) end)
hs.hotkey.bind({"shift", "alt"}, "right", function() moveToAdjacentSpace(1) end)

bindLayout("C", center)
bindLayout("V", fitAspect({width = 16, height = 9, screenWidth = 0.9}))
bindLayout("T", fitWidth)
bindLayout("F", fitAspect({width = 3, height = 2, screenHeight = 0.9}))
bindLayout("B", fitSixtyByEighty)
hs.hotkey.bind({"ctrl", "alt"}, "return", maximize)
hs.hotkey.bind({"ctrl", "cmd"}, "f", toggleFullScreen)
