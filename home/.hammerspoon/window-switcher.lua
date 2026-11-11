-- Use Hammerspoon's built-in switcher for previews and delayed display.
local filter = hs.window.filter.new():setDefaultFilter({ visible = true, allowTitles = 0 })
local switcher = hs.window.switcher.new(filter, {
    backgroundColor = { 0.10, 0.11, 0.14, 0.96 },
    highlightColor = { 0.34, 0.48, 0.76, 0.72 },
    textColor = { 0.94, 0.95, 0.98 },
    titleBackgroundColor = { 0.10, 0.11, 0.14, 0.0 },
    textSize = 13,
    thumbnailSize = 170,
    showTitles = true,
    -- Window snapshots are captured only for the mouse-hover preview.
    showThumbnails = false,
    showSelectedThumbnail = false,
    showSelectedTitle = false,
})

-- The built-in switcher has no mouse selection API. Use its current item
-- frames and close its drawings after a click, mirroring its exit behavior.
local preview, previewTimer, previewIndex
local mouseWatcher, lastMouseX, lastMouseY
local transparentSnapshots = {}
local snapshotTTL = 60

local function getTransparentSnapshot(window)
    if not window then return nil end
    local id = window:id()
    if not id then return nil end
    local now = hs.timer.secondsSinceEpoch()
    local cached = transparentSnapshots[id]
    if cached and now - cached.time < snapshotTTL then return cached.image end
    transparentSnapshots[id] = nil
    local ok, image = pcall(function() return window:snapshot(true) end)
    if not ok or not image then return nil end
    transparentSnapshots[id] = { image = image, time = now }
    return image
end
local function hidePreview()
    if preview then preview:delete(); preview = nil end
    previewIndex = nil
end
local function cleanupInteraction()
    hidePreview()
    lastMouseX, lastMouseY = nil, nil
    if mouseWatcher then mouseWatcher:stop() end
    if previewTimer then previewTimer:stop(); previewTimer = nil end
end

local function showPreview(index)
    if previewIndex == index then return end
    hidePreview()
    local window = switcher.windows and switcher.windows[index]
    if not window then return end
    local image = getTransparentSnapshot(window)
    if not image then return end
    local item = switcher.drawings[index].highlightFrame
    local screen = hs.screen.mainScreen():frame()
    local padding = 10
    local maxWidth, maxHeight = math.min(440, screen.w - 40), math.min(300, screen.h - 40)
    local imageSize = image:size()
    if not imageSize or imageSize.w <= 0 or imageSize.h <= 0 then return end
    local scale = math.min((maxWidth - padding * 2) / imageSize.w, (maxHeight - padding * 2) / imageSize.h)
    local width = imageSize.w * scale + padding * 2
    local height = imageSize.h * scale + padding * 2
    local x = math.max(screen.x + 10, math.min(item.x + item.w / 2 - width / 2, screen.x + screen.w - width - 10))
    local gap = 20
    local y = item.y - height - gap
    if y < screen.y + 10 then y = item.y + item.h + gap end
    y = math.max(screen.y + 10, math.min(y, screen.y + screen.h - height - 10))
    preview = hs.canvas.new({ x = x, y = y, w = width, h = height }):level(hs.canvas.windowLevels.overlay)
    preview:appendElements({
        type = 'rectangle', action = 'fill', roundedRectRadii = { xRadius = 16, yRadius = 16 },
        fillColor = { red = 0.10, green = 0.11, blue = 0.14, alpha = 0.96 },
    }, {
        type = 'image', image = image, imageScaling = 'scaleProportionally',
        frame = { x = 10, y = 10, w = width - 20, h = height - 20 },
    })
    previewIndex = index
    preview:show()
end

local function selectByMouse(index)
    local windows, drawings = switcher.windows, switcher.drawings
    if not windows or not windows[index] then return end
    local window = windows[index]
    cleanupInteraction()
    if switcher.modsTimer then switcher.modsTimer:stop() end
    if switcher.drawDelayed then switcher.drawDelayed:stop() end
    for _, key in ipairs({ 'background', 'highlightRect', 'selRect', 'selThumb', 'selIcon', 'selTitleRect', 'selTitleText' }) do
        if drawings[key] then drawings[key]:hide() end
    end
    for i = 1, #windows do
        local item = drawings[i]
        for _, key in ipairs({ 'icon', 'thumb', 'titleRect', 'titleText' }) do
            if item[key] then item[key]:hide() end
        end
    end
    switcher.windows, switcher.selected, switcher.modsTimer = nil, nil, nil
    window:unminimize()
    window:focus()
end

mouseWatcher = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.mouseMoved }, function(event)
    if not switcher.windows then cleanupInteraction(); return false end
    -- Ignore clicks while the built-in delayed-display timer is pending.
    if switcher.drawDelayed and switcher.drawDelayed:running() then return false end
    local point = event:location()
    for i = 1, #switcher.windows do
        local frame = switcher.drawings[i].highlightFrame
        if frame and point.x >= frame.x and point.x <= frame.x + frame.w
            and point.y >= frame.y and point.y <= frame.y + frame.h then
            if event:getType() == hs.eventtap.event.types.mouseMoved then
                if point.x == lastMouseX and point.y == lastMouseY then return false end
                lastMouseX, lastMouseY = point.x, point.y
                -- Never loop indefinitely if the built-in switcher fails to advance.
                local steps = (i - switcher.selected) % #switcher.windows
                for _ = 1, steps do switcher:next() end
                showPreview(i)
                return false
            end
            selectByMouse(i)
            return true
        end
    end
    if event:getType() == hs.eventtap.event.types.mouseMoved then
        lastMouseX, lastMouseY = nil, nil
        hidePreview()
    end
    return false
end)

local function move(direction)
    hidePreview()
    lastMouseX, lastMouseY = nil, nil
    local fresh = not switcher.windows
    if fresh then
        -- Remove snapshots for closed or expired windows to bound memory use.
        local now = hs.timer.secondsSinceEpoch()
        for id, cached in pairs(transparentSnapshots) do
            if now - cached.time >= snapshotTTL then transparentSnapshots[id] = nil end
        end
        -- The built-in renderer mutates title frames during drawing. Restore
        -- their original bounds without rebuilding every item frame.
        for _, item in ipairs(switcher.drawings) do
            if item.baseTitleFrame then item.titleFrame = hs.geometry.copy(item.baseTitleFrame) end
        end
    end
    if direction > 0 then switcher:next() else switcher:previous() end
    if switcher.windows and fresh then
        if switcher.drawDelayed and switcher.drawDelayed:running() then
            switcher.drawDelayed:setNextTrigger(0.05)
        end
        -- Fit the panel to the item bounds with equal insets and matching corners.
        local drawings = switcher.drawings
        local first = drawings[1].highlightFrame
        local last = drawings[#switcher.windows].highlightFrame
        local inset, itemRadius = 10, 12
        drawings.background:setFrame({
            x = first.x - inset,
            y = first.y - inset,
            w = last.x + last.w - first.x + inset * 2,
            h = first.h + inset * 2,
        }):setRoundedRectRadii(itemRadius + inset, itemRadius + inset)
        drawings.highlightRect:setRoundedRectRadii(itemRadius, itemRadius)
        for i = 1, #switcher.windows do
            local item = drawings[i]
            if item.titleFrame then item.baseTitleFrame = hs.geometry.copy(item.titleFrame) end
        end
        mouseWatcher:start()
        if not previewTimer then
            previewTimer = hs.timer.doEvery(0.05, function()
                if not switcher.windows then
                    cleanupInteraction()
                end
            end)
        end
    end
end
hs.hotkey.bind({ 'alt' }, 'tab', function() move(1) end, nil, function() move(1) end)
hs.hotkey.bind({ 'alt', 'shift' }, 'tab', function() move(-1) end, nil, function() move(-1) end)
