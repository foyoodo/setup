local settings = {
    displayDelay = 0.15,
    previewDelay = 0.15,
    rowHeight = 52,
    maxRows = 10,
    iconSize = 28,
    textSize = 13,
    snapshotTTL = 60,
    snapshotLimit = 4,
}

-- Magpie's windowless WebKit helper can stall accessibility enumeration.
hs.window.filter.ignoreAlways['magpie Web Content'] = true
local filter = hs.window.filter.new():setDefaultFilter({ visible = true, allowTitles = 0 })

local active, mouseWatcher
local icons = {}
local presentationCache = setmetatable({}, { __mode = 'k' })
local textSizer = hs.canvas.new({ x = 0, y = 0, w = 1, h = 1 })
if textSizer then textSizer:canvasDefaultFor('textSize', settings.textSize) end

local function layout(screen, count)
    local margin, padding, gap, heading = 24, 14, 16, 32
    local availableWidth = math.max(1, screen.w - margin * 2)
    local availableHeight = math.max(1, screen.h - margin * 2)
    local horizontal = availableWidth >= 800
    local listWidth, previewWidth, previewHeight, rows

    if horizontal then
        listWidth = math.min(680, math.floor((availableWidth - gap) * 0.60))
        previewWidth = math.min(440, availableWidth - listWidth - gap)
        previewHeight = math.min(340, availableHeight)
        rows = math.max(1, math.floor((availableHeight - padding * 2 - heading) / settings.rowHeight))
    else
        listWidth = math.min(680, availableWidth)
        previewWidth = listWidth
        previewHeight = math.min(240, math.floor(availableHeight * 0.30))
        local roomForOne = availableHeight - gap - padding * 2 - heading - settings.rowHeight
        previewHeight = math.max(1, math.min(previewHeight, roomForOne))
        rows = math.max(1, math.floor((availableHeight - previewHeight - gap - padding * 2 - heading) / settings.rowHeight))
    end

    rows = math.min(count, settings.maxRows, rows)
    local listHeight = padding * 2 + heading + rows * settings.rowHeight
    local width, height, listY, previewX, previewY
    if horizontal then
        width = listWidth + gap + previewWidth
        height = math.max(listHeight, previewHeight)
        listY = (height - listHeight) / 2
        previewX, previewY = listWidth + gap, (height - previewHeight) / 2
    else
        width = listWidth
        height = listHeight + gap + previewHeight
        listY, previewX, previewY = 0, 0, listHeight + gap
    end
    return {
        frame = { x = screen.x + (screen.w - width) / 2, y = screen.y + (screen.h - height) / 2, w = width, h = height },
        list = { x = 0, y = listY, w = listWidth, h = listHeight },
        preview = { x = previewX, y = previewY, w = previewWidth, h = previewHeight },
        rows = rows, padding = padding, heading = heading,
    }
end

local function loadPresentation(window, refresh)
    local saved = presentationCache[window]
    if saved and not refresh then return saved end
    local okTitle, title = pcall(function() return window:title() end)
    if not okTitle and saved then return saved end
    title = okTitle and title or ''
    if saved and title == saved.title then return saved end
    local icon = saved and saved.icon
    if not icon then
        local okBundle, bundle = pcall(function()
            local app = window:application()
            return app and app:bundleID()
        end)
        if okBundle and bundle then
            if icons[bundle] == nil then
                local ok, image = pcall(hs.image.imageFromAppBundle, bundle)
                if ok and image then icons[bundle] = image end
            end
            icon = icons[bundle]
        end
    end
    local okSize, size = pcall(function() return textSizer and textSizer:minimumTextSize(title) end)
    saved = { title = title, icon = icon, textSize = okSize and size or nil }
    presentationCache[window] = saved
    return saved
end

local pendingWindows, queuedWindows = {}, {}
local warmTimer

local function presentation(session, index)
    return session.presentations[session.windows[index]] or { title = '…' }
end

local function snapshot(session, window, capture)
    local now = hs.timer.secondsSinceEpoch()
    local cached = session.snapshots[window]
    if cached and now - cached.time < settings.snapshotTTL then return cached.image end
    if not capture then return nil end
    session.snapshots[window] = nil
    local ok, image = pcall(function() return window:snapshot(true) end)
    if not ok or not image then return nil end
    for i = #session.snapshotOrder, 1, -1 do
        if session.snapshotOrder[i] == window then table.remove(session.snapshotOrder, i) end
    end
    session.snapshots[window] = { image = image, time = now }
    session.snapshotOrder[#session.snapshotOrder + 1] = window
    if #session.snapshotOrder > settings.snapshotLimit then
        session.snapshots[table.remove(session.snapshotOrder, 1)] = nil
    end
    return image
end

local function viewportRows(session)
    return session.layout and session.layout.rows or math.min(#session.windows, settings.maxRows)
end

local function viewportLast(session)
    return math.min(#session.windows, session.first + viewportRows(session) - 1)
end

local function updateViewport(session)
    local rows = viewportRows(session)
    if session.selected < session.first then
        session.first = session.selected
    elseif session.selected >= session.first + rows then
        session.first = session.selected - rows + 1
    end
    session.first = math.max(1, math.min(session.first, #session.windows - rows + 1))
end

local function rowOrigin(layoutInfo)
    local list, padding = layoutInfo.list, layoutInfo.padding
    return list.x + padding, list.y + padding + layoutInfo.heading, list.w - padding * 2
end

local function render(session)
    if active ~= session or not session.panel then return end
    local layoutInfo = session.layout
    local list, preview, padding = layoutInfo.list, layoutInfo.preview, layoutInfo.padding
    local elements = {
        { type = 'rectangle', action = 'fill', frame = list,
          roundedRectRadii = { xRadius = 16, yRadius = 16 },
          fillColor = { red = 0.10, green = 0.11, blue = 0.14, alpha = 0.97 } },
        { type = 'rectangle', action = 'fill', frame = preview,
          roundedRectRadii = { xRadius = 16, yRadius = 16 },
          fillColor = { red = 0.10, green = 0.11, blue = 0.14, alpha = 0.97 } },
        { type = 'text', text = 'Windows', textSize = 13,
          textColor = { red = 0.75, green = 0.77, blue = 0.82, alpha = 1 },
          frame = { x = list.x + padding, y = list.y + padding, w = list.w - padding * 2, h = 20 } },
        { type = 'text', text = string.format('%d / %d', session.selected, #session.windows),
          textSize = 12, textAlignment = 'right',
          textColor = { red = 0.75, green = 0.77, blue = 0.82, alpha = 1 },
          frame = { x = list.x + padding, y = list.y + padding, w = list.w - padding * 2, h = 20 } },
    }
    local rowX, firstRowY, rowWidth = rowOrigin(layoutInfo)
    for row = 1, layoutInfo.rows do
        local index = session.first + row - 1
        local item = presentation(session, index)
        local rowY = firstRowY + (row - 1) * settings.rowHeight
        if index == session.selected then
            elements[#elements + 1] = {
                type = 'rectangle', action = 'fill',
                frame = { x = rowX, y = rowY, w = rowWidth, h = settings.rowHeight },
                roundedRectRadii = { xRadius = 8, yRadius = 8 },
                fillColor = { red = 0.34, green = 0.48, blue = 0.76, alpha = 0.72 },
            }
        end
        if item.icon then
            elements[#elements + 1] = {
                type = 'image', image = item.icon, imageScaling = 'scaleProportionally',
                frame = { x = rowX + 8, y = rowY + (settings.rowHeight - settings.iconSize) / 2,
                    w = settings.iconSize, h = settings.iconSize },
            }
        end
        local textWidth = math.max(1, rowWidth - settings.iconSize - 28)
        local textHeight = settings.rowHeight - 16
        if item.textSize and item.textSize.w + 4 <= textWidth and item.textSize.h <= textHeight then
            textHeight = math.min(textHeight, math.ceil(item.textSize.h) + 4)
        end
        elements[#elements + 1] = {
            type = 'text', text = item.title, textSize = settings.textSize, textAlignment = 'left',
            textLineBreak = 'wordWrap', textColor = { red = 0.94, green = 0.95, blue = 0.98, alpha = 1 },
            frame = { x = rowX + settings.iconSize + 20, y = rowY + (settings.rowHeight - textHeight) / 2,
                w = textWidth, h = textHeight },
        }
    end
    local selected = presentation(session, session.selected)
    local titleHeight = math.min(42, math.max(1, preview.h - 30))
    elements[#elements + 1] = {
        type = 'text', text = selected.title, textSize = 12, textAlignment = 'center',
        textLineBreak = 'wordWrap', textColor = { red = 0.94, green = 0.95, blue = 0.98, alpha = 1 },
        frame = { x = preview.x + padding, y = preview.y + padding,
            w = math.max(1, preview.w - padding * 2), h = titleHeight },
    }
    local imageFrame = { x = preview.x + padding, y = preview.y + padding + titleHeight,
        w = math.max(1, preview.w - padding * 2), h = math.max(1, preview.h - padding * 2 - titleHeight) }
    if session.previewImage then
        elements[#elements + 1] = { type = 'image', image = session.previewImage,
            imageScaling = 'scaleProportionally', frame = imageFrame }
    else
        elements[#elements + 1] = { type = 'text', text = session.previewFailed and 'Preview unavailable' or 'Loading preview…',
            textSize = 12, textAlignment = 'center', textColor = { white = 0.65, alpha = 1 },
            frame = { x = imageFrame.x, y = imageFrame.y + math.max(0, (imageFrame.h - 20) / 2), w = imageFrame.w, h = 20 } }
    end
    session.panel:replaceElements(elements)
end

-- Keep the current rows stable until their complete visible batch is ready.
local function commitPresentations(session)
    local last = viewportLast(session)
    for i = session.first, last do
        local window = session.windows[i]
        local queued = queuedWindows[window]
        if not presentationCache[window] or (queued and queued.refresh) then return false end
    end
    local changed = false
    for i = session.first, last do
        local window = session.windows[i]
        local item = presentationCache[window]
        if session.presentations[window] ~= item then
            session.presentations[window] = item
            changed = true
        end
    end
    return changed
end

local function warmNextPresentation()
    warmTimer = nil
    local item
    repeat
        item = table.remove(pendingWindows, 1)
    until not item or queuedWindows[item.window] == item
    if not item then return end
    queuedWindows[item.window] = nil
    loadPresentation(item.window, item.refresh)
    local session = active
    if session and session.panel and commitPresentations(session) then render(session) end
    if #pendingWindows > 0 and not warmTimer then warmTimer = hs.timer.doAfter(0.02, warmNextPresentation) end
end

local function queuePresentation(window, refresh, priority)
    if not window then return end
    local item = queuedWindows[window]
    if item then
        item.refresh = item.refresh or refresh
    elseif refresh or not presentationCache[window] then
        item = { window = window, refresh = refresh }
        queuedWindows[window] = item
        pendingWindows[#pendingWindows + 1] = item
    end
    if priority and item and pendingWindows[1] ~= item then
        for i = 2, #pendingWindows do
            if pendingWindows[i] == item then
                table.remove(pendingWindows, i)
                table.insert(pendingWindows, 1, item)
                break
            end
        end
    end
    if #pendingWindows > 0 and not warmTimer then
        warmTimer = hs.timer.doAfter(0.02, warmNextPresentation)
    end
end

local function prepareVisible(session)
    updateViewport(session)
    local last = viewportLast(session)
    for i = last, session.first, -1 do queuePresentation(session.windows[i], false, true) end
    queuePresentation(session.windows[session.selected], false, true)
    if session.panel then commitPresentations(session) end
end

local function isVisible(session, window)
    if not session then return false end
    local last = viewportLast(session)
    for i = session.first, last do
        if session.windows[i] == window then return true end
    end
    return false
end

local function stopSessionTimer(session, field)
    local timer = session[field]
    session[field] = nil
    if timer then timer:stop() end
end

local function finish(session, shouldFocus)
    if active ~= session then return end
    active = nil
    stopSessionTimer(session, 'displayTimer')
    stopSessionTimer(session, 'previewTimer')
    stopSessionTimer(session, 'cleanupTimer')
    if mouseWatcher then mouseWatcher:stop() end
    if session.panel then session.panel:delete(); session.panel = nil end
    local window = session.windows[session.selected]
    if shouldFocus ~= false and window then
        local ok, err = pcall(function() window:focus() end)
        if not ok then print('window-switcher: focus failed: ' .. tostring(err)) end
    end
end

local function schedulePreview(session)
    stopSessionTimer(session, 'previewTimer')
    local window = session.windows[session.selected]
    session.previewImage, session.previewFailed = snapshot(session, window), false
    if session.previewImage then return end
    session.previewTimer = hs.timer.doAfter(settings.previewDelay, function()
        session.previewTimer = nil
        if active ~= session or not session.panel or session.windows[session.selected] ~= window then return end
        if not hs.eventtap.checkKeyboardModifiers().alt then finish(session); return end
        local image = snapshot(session, window, true)
        if active ~= session or not session.panel or session.windows[session.selected] ~= window then return end
        session.previewImage, session.previewFailed = image, not image
        render(session)
    end)
end

local function setSelection(session, index)
    if active ~= session or index == session.selected then return end
    session.selected = index
    prepareVisible(session)
    if session.panel then
        schedulePreview(session)
        render(session)
    end
end

local function show(session)
    if active ~= session then return end
    session.displayTimer = nil
    if not hs.eventtap.checkKeyboardModifiers().alt then finish(session); return end
    local screen = hs.screen.mainScreen()
    if not screen then finish(session); return end
    session.screen = screen:frame()
    session.layout = layout(session.screen, #session.windows)
    session.panel = hs.canvas.new(session.layout.frame)
    if not session.panel then finish(session); return end
    session.panel:level(hs.canvas.windowLevels.overlay)
    session.panel:canvasDefaultFor('textSize', settings.textSize)
    local point = hs.mouse.absolutePosition()
    session.mouseX, session.mouseY = point.x, point.y
    prepareVisible(session)
    render(session)
    session.panel:show()
    schedulePreview(session)
end

local function removeWindow(window)
    local session = active
    if not session then return end
    local index
    for i, candidate in ipairs(session.windows) do
        if candidate == window then index = i; break end
    end
    if not index then return end

    local selected = session.windows[session.selected]
    table.remove(session.windows, index)
    session.presentations[window] = nil
    if #session.windows == 0 then finish(session, false); return end
    if index < session.selected then session.selected = session.selected - 1 end
    session.selected = math.min(session.selected, #session.windows)

    if session.panel then
        local newLayout = layout(session.screen, #session.windows)
        if newLayout.rows ~= session.layout.rows then
            session.layout = newLayout
            session.panel:frame(newLayout.frame)
        end
    end
    prepareVisible(session)
    if session.panel then
        if session.windows[session.selected] ~= selected then schedulePreview(session) end
        render(session)
    end
end

local function contains(frame, point)
    return point.x >= frame.x and point.x < frame.x + frame.w
        and point.y >= frame.y and point.y < frame.y + frame.h
end

mouseWatcher = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.mouseMoved,
    hs.eventtap.event.types.scrollWheel,
    hs.eventtap.event.types.flagsChanged,
}, function(event)
    local session = active
    if not session then return false end
    local kind = event:getType()
    if kind == hs.eventtap.event.types.flagsChanged then
        if not event:getFlags().alt then finish(session) end
        return false
    end
    if not session.panel then return false end
    local point = event:location()
    local frame = session.layout.frame
    local localPoint = { x = point.x - frame.x, y = point.y - frame.y }
    if kind == hs.eventtap.event.types.scrollWheel then
        if not contains(session.layout.list, localPoint) then return false end
        local momentum = hs.eventtap.event.properties.scrollWheelEventMomentumPhase
        if momentum and (event:getProperty(momentum) or 0) ~= 0 then return true end
        local delta = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1) or 0
        local now = hs.timer.secondsSinceEpoch()
        if delta ~= 0 and now - (session.lastScroll or -math.huge) >= 0.08 then
            session.lastScroll = now
            local direction = delta < 0 and 1 or -1
            setSelection(session, math.max(1, math.min(#session.windows, session.selected + direction)))
        end
        return true
    end
    if kind == hs.eventtap.event.types.mouseMoved then
        if session.mouseX == point.x and session.mouseY == point.y then return false end
        session.mouseX, session.mouseY = point.x, point.y
    end
    local rowX, firstRowY, rowWidth = rowOrigin(session.layout)
    local row = math.floor((localPoint.y - firstRowY) / settings.rowHeight) + 1
    if row >= 1 and row <= session.layout.rows and localPoint.x >= rowX and localPoint.x < rowX + rowWidth then
        setSelection(session, session.first + row - 1)
        if kind == hs.eventtap.event.types.leftMouseDown then
            finish(session)
            return true
        end
    end
    return false
end)

local function move(direction)
    local session = active
    if not session then
        local windows = filter:getWindows(hs.window.filter.sortByFocusedLast)
        if #windows == 0 then return end
        local presentations = {}
        for _, window in ipairs(windows) do presentations[window] = presentationCache[window] end
        session = {
            windows = windows, selected = ((direction % #windows) + 1), first = 1,
            presentations = presentations, snapshots = {}, snapshotOrder = {},
        }
        active = session
        mouseWatcher:start()
        session.displayTimer = hs.timer.doAfter(settings.displayDelay, function() show(session) end)
        session.cleanupTimer = hs.timer.doEvery(0.05, function()
            if active == session and not hs.eventtap.checkKeyboardModifiers().alt then finish(session) end
        end)
        prepareVisible(session)
    else
        setSelection(session, ((session.selected - 1 + direction) % #session.windows) + 1)
    end
    if active == session and not hs.eventtap.checkKeyboardModifiers().alt then finish(session) end
end

-- Move once per Tab press so a missed key release cannot start endless cycling.
hs.hotkey.bind({ 'alt' }, 'tab', function() move(1) end)
hs.hotkey.bind({ 'alt', 'shift' }, 'tab', function() move(-1) end)

filter:subscribe({
    [hs.window.filter.windowAllowed] = function(window) queuePresentation(window, false) end,
    [hs.window.filter.windowTitleChanged] = function(window) queuePresentation(window, true, isVisible(active, window)) end,
    [hs.window.filter.windowRejected] = function(window)
        if window then
            presentationCache[window] = nil
            queuedWindows[window] = nil
            removeWindow(window)
        end
    end,
}, true)
