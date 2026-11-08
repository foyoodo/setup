local function launchOrFocusByBundleID(bundleId)
    return function()
        local app = hs.application.get(bundleId)
        if app then
            local win = app:focusedWindow() or app:mainWindow()
            if not win then
                for _, candidate in ipairs(app:allWindows()) do
                    if candidate:isStandard() and not candidate:isMinimized() then
                        win = candidate
                        break
                    end
                end
            end
            if win then
                win:focus()
                return
            end
        end
        hs.application.launchOrFocusByBundleID(bundleId)
    end
end

hs.hotkey.bind({"alt"}, "1", launchOrFocusByBundleID("com.apple.finder"))
hs.hotkey.bind({"alt"}, "2", launchOrFocusByBundleID("net.imput.helium"))
hs.hotkey.bind({"alt"}, "3", launchOrFocusByBundleID("com.apple.Safari"))
hs.hotkey.bind({"alt"}, "R", launchOrFocusByBundleID("com.superlogical.rex"))
hs.hotkey.bind({"alt"}, "T", launchOrFocusByBundleID("com.mitchellh.ghostty"))
hs.hotkey.bind({"alt"}, "E", launchOrFocusByBundleID("com.sublimetext.4"))
hs.hotkey.bind({"alt"}, "F", launchOrFocusByBundleID("org.mozilla.firefox"))
hs.hotkey.bind({"alt"}, "G", launchOrFocusByBundleID("com.openai.codex"))
hs.hotkey.bind({"alt"}, "X", launchOrFocusByBundleID("com.apple.dt.Xcode"))
hs.hotkey.bind({"alt"}, "Z", launchOrFocusByBundleID("dev.zed.Zed"))
hs.hotkey.bind({"alt"}, "C", launchOrFocusByBundleID("com.todesktop.230313mzl4w4u92")) -- Cursor
hs.hotkey.bind({"alt"}, "V", launchOrFocusByBundleID("com.sublimemerge"))

require "window-switcher"
