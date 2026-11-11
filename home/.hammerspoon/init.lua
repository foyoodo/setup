require "focus"
require "window-switcher"
require "remag"

hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall:asyncUpdateAllRepos()

if not hspoonList then
    hspoonList = {
        "ReloadConfiguration",
    }
end

for _, v in pairs(hspoonList) do
    spoon.SpoonInstall:andUse(v, {
        start = (v == "ReloadConfiguration"),
    })
end
