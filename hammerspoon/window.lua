local windowParams = KeybindingConfigs["parameters"] or {}
local moveStep = windowParams.windowMoveStep or 20
local resizeStep = windowParams.windowResizeStep or 100
local windowZoomToCenterSize = windowParams.windowZoomToCenterSize or { w = 830, h = 750 }

local function newWindow(...)
  local hotkey = newHotkeySpec(...)
  if hotkey == nil then return nil end
  hotkey.kind = HK.WIN_OP
  return hotkey
end

local function bindWindow(...)
  local hotkey = bindHotkeySpec(...)
  if hotkey == nil then return nil end
  hotkey.kind = HK.WIN_OP
  return hotkey
end

local frameCacheMaximize = {}
local frameCacheZoomToCenter = {}
local function bindMoveWindow(spec, message, fn, repeatable)
  local newFn = function()
    fn()
    local win = hs.window.focusedWindow()
    frameCacheMaximize[win:id()] = nil
    frameCacheZoomToCenter[win:id()] = nil
  end
  local repeatedFn = repeatable and newFn or nil
  local hotkey = bindWindow(spec, message, newFn, nil, repeatedFn)
  hotkey.subkind = HK.WIN_OP_.MOVE
  return hotkey
end

local function bindResizeWindow(spec, message, fn, repeatable)
  local newFn = function()
    fn()
    local win = hs.window.focusedWindow()
    frameCacheMaximize[win:id()] = nil
    frameCacheZoomToCenter[win:id()] = nil
  end
  local repeatedFn = repeatable and newFn or nil
  local hotkey = bindWindow(spec, message, newFn, nil, repeatedFn)
  hotkey.subkind = HK.WIN_OP_.RESIZE
  return hotkey
end

local winHK = KeybindingConfigs.hotkeys.global

-- continuously move the focused window

-- move towards top-left
bindMoveWindow(winHK["moveTowardsTopLeft"], "Move towards Top-Left",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.x = f.x - moveStep
  f.y = f.y - moveStep
  win:setFrame(f)
end, true)

-- move towards top
bindMoveWindow(winHK["moveTowardsTop"], "Move towards Top",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.y = f.y - moveStep
  win:setFrame(f)
end, true)

-- move towards top-right
bindMoveWindow(winHK["moveTowardsTopRight"], "Move towards Top-Right",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.x = f.x + moveStep
  f.y = f.y - moveStep
  win:setFrame(f)
end, true)

-- move towards left
bindMoveWindow(winHK["moveTowardsLeft"], "Move towards Left",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.x = f.x - moveStep
  win:setFrame(f)
end, true)

-- move towards right
bindMoveWindow(winHK["moveTowardsRight"], "Move towards Right",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.x = f.x + moveStep
  win:setFrame(f)
end, true)

-- move towards bottom-left
bindMoveWindow(winHK["moveTowardsBottomLeft"], "Move towards Bottom-Left",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.x = f.x - moveStep
  f.y = f.y + moveStep
  win:setFrame(f)
end, true)

-- move towards bottom
bindMoveWindow(winHK["moveTowardsBottom"], "Move towards Bottom",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.y = f.y + moveStep
  win:setFrame(f)
end, true)

-- move towards bottom-right
bindMoveWindow(winHK["moveTowardsBottomRight"], "Move towards Bottom-Right",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.x = f.x + moveStep
  f.y = f.y + moveStep
  win:setFrame(f)
end, true)


-- move and zoom to left
bindResizeWindow(winHK["zoomToLeft"], "Zoom to Left",
function()
  hs.window.focusedWindow():moveToUnit(hs.layout.left50)
end)

-- move and zoom to right
bindResizeWindow(winHK["zoomToRight"], "Zoom to Right",
function()
  hs.window.focusedWindow():moveToUnit(hs.layout.right50)
end)

-- move and zoom to top-left
bindResizeWindow(winHK["zoomToTopLeft"], "Zoom to Top-Left",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x
  f.y = max.y
  f.w = max.w / 2
  f.h = max.h / 2
  win:setFrame(f)
end)

-- move and zoom to top-right
bindResizeWindow(winHK["zoomToTopRight"], "Zoom to Top-Right",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x + max.w / 2
  f.y = max.y
  f.w = max.w / 2
  f.h = max.h / 2
  win:setFrame(f)
end)

-- move and zoom to bottom-left
bindResizeWindow(winHK["zoomToBottomLeft"], "Zoom to Bottom-Left",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x
  f.y = max.y + max.h / 2
  f.w = max.w / 2
  f.h = max.h / 2
  win:setFrame(f)
end)

-- move and zoom to bottom-right
bindResizeWindow(winHK["zoomToBottomRight"], "Zoom to Bottom-Right",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x + max.w / 2
  f.y = max.y + max.h / 2
  f.w = max.w / 2
  f.h = max.h / 2
  win:setFrame(f)
end)

-- move and zoom to left 1/3
bindResizeWindow(winHK["zoomToLeftThird"], "Zoom to Left Third",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x
  f.y = max.y
  f.w = max.w / 3
  f.h = max.h
  win:setFrame(f)
end)

-- move and zoom to right 1/3
bindResizeWindow(winHK["zoomToRightThird"], "Zoom to Right Third",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x + max.w / 3 * 2
  f.y = max.y
  f.w = max.w / 3
  f.h = max.h
  win:setFrame(f)
end)

-- move and zoom to left 2/3
bindResizeWindow(winHK["zoomToLeftTwoThirds"], "Zoom to Left Two Thirds",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x
  f.y = max.y
  f.w = max.w / 3 * 2
  f.h = max.h
  win:setFrame(f)
end)

-- move and zoom to right 2/3
bindResizeWindow(winHK["zoomToRightTwoThirds"], "Zoom to Right Two Thirds",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x + max.w / 3
  f.y = max.y
  f.w = max.w / 3 * 2
  f.h = max.h
  win:setFrame(f)
end)

-- expand on left
bindResizeWindow(winHK["leftExpand"], "Left Border Expand",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  local r = f.x + f.w
  f.x = math.max(max.x, f.x - resizeStep)
  f.w = r - f.x
  win:setFrame(f)
end, true)

-- shrink on left
bindResizeWindow(winHK["leftShrink"], "Left Border Shrink",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  local r = f.x + f.w
  f.w = math.max(resizeStep, f.w - resizeStep)
  f.x = r - f.w
  win:setFrame(f)
end, true)

-- expand on right
bindResizeWindow(winHK["rightExpand"], "Right Border Expand",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.w = math.min(max.x + max.w - f.x, f.w + resizeStep)
  win:setFrame(f)
end, true)

-- shrink on right
bindResizeWindow(winHK["rightShrink"], "Right Border Shrink",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.w = math.max(resizeStep, f.w - resizeStep)
  win:setFrame(f)
end, true)

-- expand on bottom
bindResizeWindow(winHK["topExpand"], "Top Border Expand",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  local b = f.y + f.h
  f.y = math.max(max.y, f.y - resizeStep)
  f.h = b - f.y
  win:setFrame(f)
end, true)

-- shrink on bottom
bindResizeWindow(winHK["topShrink"], "Top Border Shrink",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  local b = f.y + f.h
  f.h = math.max(resizeStep, f.h - resizeStep)
  f.y = b - f.h
  win:setFrame(f)
end, true)

-- expand on bottom
bindResizeWindow(winHK["bottomExpand"], "Bottom Border Expand",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.h = math.min(max.y + max.h - f.y, f.h + resizeStep)
  win:setFrame(f)
end, true)

-- shrink on bottom
bindResizeWindow(winHK["bottomShrink"], "Bottom Border Shrink",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.h = math.max(resizeStep, f.h - resizeStep)
  win:setFrame(f)
end, true)

-- maximize
bindWindow(winHK["toggleMaximize"], "Toggle Maximize",
function()
  local win = hs.window.focusedWindow()
  if frameCacheMaximize[win:id()] then
      win:setFrame(frameCacheMaximize[win:id()])
      frameCacheMaximize[win:id()] = nil
  else
      frameCacheMaximize[win:id()] = win:frame()
      win:maximize()
  end
  frameCacheZoomToCenter[win:id()] = nil
end).subkind = 0

-- move to top-left
bindMoveWindow(winHK["moveToTopLeft"], "Move to Top-Left",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x
  f.y = max.y
  win:setFrame(f)
end)

-- move to top
bindMoveWindow(winHK["moveToTop"], "Move to Top",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.y = max.y
  win:setFrame(f)
end)

-- move to top-right
bindMoveWindow(winHK["moveToTopRight"], "Move to Top-Right",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x + max.w - f.w
  f.y = max.y
  win:setFrame(f)
end)

-- move to left
bindMoveWindow(winHK["moveToLeft"], "Move to Left",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x
  win:setFrame(f)
end)

-- move to center
bindMoveWindow(winHK["moveToCenter"], "Move to Center",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = (max.x + max.x + max.w - f.w) / 2
  f.y = (max.y + max.y + max.h - f.h) / 2
  win:setFrame(f)
end)

-- move and zoom to center
bindWindow(winHK["toggleZoomToCenter"], "Toggle Zoom to Center",
function()
  local win = hs.window.focusedWindow()
  if frameCacheZoomToCenter[win:id()] then
    win:setFrame(frameCacheZoomToCenter[win:id()])
    frameCacheZoomToCenter[win:id()] = nil
  else
    frameCacheZoomToCenter[win:id()] = win:frame()

    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()

    f.w = windowZoomToCenterSize.w
    f.h = windowZoomToCenterSize.h
    f.x = (max.x + max.x + max.w - f.w) / 2
    f.y = (max.y + max.y + max.h - f.h) / 2
    win:setFrame(f)
  end
  frameCacheMaximize[win:id()] = nil
end).subkind = 0

-- move to right
bindMoveWindow(winHK["moveToRight"], "Move to Right",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x + max.w - f.w
  win:setFrame(f)
end)

-- move to bottom-left
bindMoveWindow(winHK["moveToBottomLeft"], "Move to Bottom-Left",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x
  f.y = max.y + max.h - f.h
  win:setFrame(f)
end)

-- move to bottom
bindMoveWindow(winHK["moveToBottom"], "Move to Bottom",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.y = max.y + max.h - f.h
  win:setFrame(f)
end)

-- move to bottom-right
bindMoveWindow(winHK["moveToBottomRight"], "Move to Bottom-Right",
function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  f.x = max.x + max.w - f.w
  f.y = max.y + max.h - f.h
  win:setFrame(f)
end)

-- hide all windows
bindWindow(winHK["hideAllWindows"], "Hide All Windows",
function()
  local allWindows = hs.window.filter.new():getWindows()
  for i, window in ipairs(allWindows) do
    if window:isVisible() and not window:isFullScreen()
        and window:application() ~= nil
        and window:application():bundleID() ~= "com.apple.finder" then
      window:application():hide()
    end
  end
  local finderWindows = findApplication("com.apple.finder"):visibleWindows()
  for i, window in ipairs(finderWindows) do
    if window:isFullScreen() then
      window:minimize()
    end
  end
end)

-- hide all windows on current space
bindWindow(winHK["hideAllWindowsCurrentSpace"], "Hide All Windows on Current Space",
function()
  local space = hs.spaces.focusedSpace()
  local allWindows = hs.window.filter.new():getWindows()
  allWindows = hs.fnutils.filter(allWindows, function(window)
    return hs.fnutils.contains(hs.spaces.windowSpaces(window), space)
  end)
  for i, window in ipairs(allWindows) do
    if window:isVisible() and not window:isFullScreen()
        and window:application() ~= nil
        and window:application():bundleID() ~= "com.apple.finder" then
      window:application():hide()
    end
  end
  local finderWindows = findApplication("com.apple.finder"):visibleWindows()
  finderWindows = hs.fnutils.filter(finderWindows, function(window)
    return hs.fnutils.contains(hs.spaces.windowSpaces(window), space)
  end)
  for i, window in ipairs(finderWindows) do
    if window:isFullScreen() then
      window:minimize()
    end
  end
end)

-- toggle full-screen
bindWindow(winHK["toggleFullScreen"], "Toggle Full-Screen",
function()
  local win = hs.window.focusedWindow()
  win:toggleFullScreen()
end)

-- window-based switcher like Windows

local misc = KeybindingConfigs.hotkeys.global

local function newWindowMisc(...)
  local hotkey = newHotkeySpec(...)
  if hotkey == nil then return nil end
  hotkey.kind = HK.SWITCH
  return hotkey
end

local function bindWindowMisc(...)
  local hotkey = bindHotkeySpec(...)
  if hotkey == nil then return nil end
  hotkey.kind = HK.SWITCH
  return hotkey
end

local function runningAppDisplayNames(bundleIDs)
  local appNames = {}
  for _, bundleID in ipairs(bundleIDs) do
    local appObj = findApplication(bundleID)
    if appObj ~= nil then
      table.insert(appNames, appObj:name())
    end
  end
  return appNames
end

-- visible windows on all user spaces (wallpaper apps excluded)
-- fixme: full screen space will be ignored if not once focused
local ignoredApps = {
  "com.apple.controlcenter",
  "com.apple.notificationcenterui",
  "com.pigigaldi.pock",
  "whbalzac.Dongtaizhuomian",
  "com.macosgame.iwallpaper",
}
local switcher

local hotkeyEnabledByWindowSwitcher = false
local function enabledByWindowSwitcherFunc()
  return hotkeyEnabledByWindowSwitcher
end

local windowSwitcherWindowIdx = nil
local windowSwitcherWindowNumber = nil
local nextWindowHotkey, lastWindowHotkey
local anotherLastWindowHotkey
local anotherLastWindowModifierTap

local function registerWindowSwitcher()
  anotherLastWindowHotkey =
  newWindowMisc(misc["switchWindowBackTriggered"], 'Previous Window',
  function()
    if windowSwitcherWindowNumber > 0 then
      windowSwitcherWindowIdx = windowSwitcherWindowIdx - 1
      if windowSwitcherWindowIdx == 0 then
        windowSwitcherWindowIdx = windowSwitcherWindowNumber
      end
    end
    switcher:previous()
  end, nil,
  function()
    if windowSwitcherWindowIdx > 1 then
      windowSwitcherWindowIdx = windowSwitcherWindowIdx - 1
      switcher:previous()
    end
  end,
  { fn = enabledByWindowSwitcherFunc, or_ = true })

  local _lastWindowMods = misc["switchWindow"].mods
  if type(_lastWindowMods) == 'string' then
    _lastWindowMods = { _lastWindowMods }
  end
  local lastWindowMods = {}
  for _, mod in ipairs(_lastWindowMods) do
    if mod == 'command' then
      table.insert(lastWindowMods, 'cmd')
    elseif mod == 'option' then
      table.insert(lastWindowMods, 'alt')
    elseif mod == 'control' then
      table.insert(lastWindowMods, 'ctrl')
    elseif mod == 'shift' then
      table.insert(lastWindowMods, 'shift')
    end
  end

  anotherLastWindowModifierTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged },
  function(event)
    local flags = event:getFlags()
    if not flags:contain(lastWindowMods) then
      hotkeyEnabledByWindowSwitcher = false
      F_hotkeySuspended = false
      if anotherLastWindowHotkey ~= nil then
        anotherLastWindowHotkey:disable()
      end
      anotherLastWindowModifierTap:stop()
      switcher = nil
      windowSwitcherWindowIdx = nil
      windowSwitcherWindowNumber = nil
    end
    return false
  end)

  nextWindowHotkey = bindWindowMisc(misc["switchWindow"], 'Next Window',
  function()
    if not anotherLastWindowModifierTap:isEnabled() then
      hotkeyEnabledByWindowSwitcher = true
      F_hotkeySuspended = true
      if anotherLastWindowHotkey ~= nil then
        anotherLastWindowHotkey:enable()
      end
      anotherLastWindowModifierTap:start()
    end
    if switcher == nil then
      local filter = hs.window.filter.new()
      for _, appName in ipairs(runningAppDisplayNames(ignoredApps)) do
        filter:rejectApp(appName)
      end
      switcher = hs.window.switcher.new(filter)
    end
    switcher:next()
    if windowSwitcherWindowIdx == nil then
      windowSwitcherWindowNumber = 0
      for k, v in pairs(switcher.wf.windows) do
        windowSwitcherWindowNumber = windowSwitcherWindowNumber + 1
      end
      if windowSwitcherWindowNumber > 1 then
        windowSwitcherWindowIdx = 2
      else
        windowSwitcherWindowIdx = windowSwitcherWindowNumber
      end
    else
      windowSwitcherWindowIdx = windowSwitcherWindowIdx + 1
      if windowSwitcherWindowIdx > windowSwitcherWindowNumber then
        windowSwitcherWindowIdx = 1
      end
    end
  end,
  nil,
  function()
    if windowSwitcherWindowIdx ~= windowSwitcherWindowNumber then
      windowSwitcherWindowIdx = windowSwitcherWindowIdx + 1
      switcher:next()
    end
  end,
  { fn = enabledByWindowSwitcherFunc, or_ = true })

  lastWindowHotkey = bindWindowMisc(misc["switchWindowBack"], 'Previous Window',
  function()
    if not anotherLastWindowModifierTap:isEnabled() then
      hotkeyEnabledByWindowSwitcher = true
      F_hotkeySuspended = true
      if anotherLastWindowHotkey ~= nil then
        anotherLastWindowHotkey:enable()
      end
      anotherLastWindowModifierTap:start()
    end
    if switcher == nil then
      local filter = hs.window.filter.new()
      for _, appName in ipairs(runningAppDisplayNames(ignoredApps)) do
        filter:rejectApp(appName)
      end
      switcher = hs.window.switcher.new(filter)
    end
    switcher:previous()
    if windowSwitcherWindowIdx == nil then
      windowSwitcherWindowNumber = 0
      for k, v in pairs(switcher.wf.windows) do
        windowSwitcherWindowNumber = windowSwitcherWindowNumber + 1
      end
      windowSwitcherWindowIdx = windowSwitcherWindowNumber
    else
      if windowSwitcherWindowNumber > 1 then
        windowSwitcherWindowIdx = windowSwitcherWindowIdx - 1
        if windowSwitcherWindowIdx == 0 then
          windowSwitcherWindowIdx = windowSwitcherWindowNumber
        end
      end
    end
  end,
  nil,
  function()
    if windowSwitcherWindowIdx > 1 then
      windowSwitcherWindowIdx = windowSwitcherWindowIdx - 1
      switcher:previous()
    end
  end,
  { fn = enabledByWindowSwitcherFunc, or_ = true })
end

local function unregisterWindowSwitcher()
  if nextWindowHotkey ~= nil then
    nextWindowHotkey:delete()
    nextWindowHotkey = nil
  end
  if lastWindowHotkey ~= nil then
    lastWindowHotkey:delete()
    lastWindowHotkey = nil
  end
  if anotherLastWindowHotkey ~= nil then
    anotherLastWindowHotkey:delete()
    anotherLastWindowHotkey = nil
  end
  windowSwitcherWindowIdx = nil
  windowSwitcherWindowNumber = nil
  switcher = nil
  if anotherLastWindowModifierTap ~= nil then
    anotherLastWindowModifierTap:stop()
    anotherLastWindowModifierTap = nil
  end
end

if misc["switchWindow"] ~= nil and findApplication("com.lwouis.alt-tab-macos") == nil then
  registerWindowSwitcher()
end

if misc["switchWindow"] ~= nil then
  AltTabWatcher = hs.timer.new(1, function()
    local appObject = findApplication("com.lwouis.alt-tab-macos")
    if appObject == nil and nextWindowHotkey == nil then
      registerWindowSwitcher()
    elseif appObject ~= nil and nextWindowHotkey ~= nil then
      unregisterWindowSwitcher()
    end
  end):start()
end

-- visible windows of all browsers on all user spaces
-- fixme: full screen space will be ignored if not once focused
local browserBundleIDs = {
  "com.apple.Safari",
  "com.google.Chrome",
  "com.microsoft.edgemac",
  "com.microsoft.edgemac.Dev",
}
local switcher_browsers

local anotherLastBrowserHotkey
local anotherLastBrowserModifierTap

if misc["switchBrowserWindow"] ~= nil then
  anotherLastBrowserHotkey =
  newWindowMisc(misc["switchBrowserWindowBackTriggered"], 'Previous Browser Window',
  function()
    if windowSwitcherWindowNumber > 0 then
      windowSwitcherWindowIdx = windowSwitcherWindowIdx - 1
      if windowSwitcherWindowIdx == 0 then
        windowSwitcherWindowIdx = windowSwitcherWindowNumber
      end
    end
    switcher_browsers:previous()
  end, nil,
  function()
    if windowSwitcherWindowIdx > 1 then
      windowSwitcherWindowIdx = windowSwitcherWindowIdx - 1
      switcher_browsers:previous()
    end
  end,
  { fn = enabledByWindowSwitcherFunc, or_ = true })

  local _lastBrowserWindowMods = misc["switchBrowserWindow"].mods
  if type(_lastBrowserWindowMods) == 'string' then
    _lastBrowserWindowMods = { _lastBrowserWindowMods }
  end
  local lastBrowserWindowMods = {}
  for _, mod in ipairs(_lastBrowserWindowMods) do
    if mod == 'command' then
      table.insert(lastBrowserWindowMods, 'cmd')
    elseif mod == 'option' then
      table.insert(lastBrowserWindowMods, 'alt')
    elseif mod == 'control' then
      table.insert(lastBrowserWindowMods, 'ctrl')
    elseif mod == 'shift' then
      table.insert(lastBrowserWindowMods, 'shift')
    end
  end

  anotherLastBrowserModifierTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged },
  function(event)
    local flags = event:getFlags()
    if not flags:contain(lastBrowserWindowMods) then
      hotkeyEnabledByWindowSwitcher = false
      F_hotkeySuspended = false
      if anotherLastBrowserHotkey ~= nil then
        anotherLastBrowserHotkey:disable()
      end
      anotherLastBrowserModifierTap:stop()
      switcher_browsers = nil
      windowSwitcherWindowIdx = nil
      windowSwitcherWindowNumber = nil
    end
    return false
  end)

  bindWindowMisc(misc["switchBrowserWindow"], 'Next Browser Window',
  function()
    if not anotherLastBrowserModifierTap:isEnabled() then
      hotkeyEnabledByWindowSwitcher = true
      F_hotkeySuspended = true
      if anotherLastBrowserHotkey ~= nil then
        anotherLastBrowserHotkey:enable()
      end
      anotherLastBrowserModifierTap:start()
    end
    if switcher_browsers == nil then
      switcher_browsers = hs.window.switcher.new(runningAppDisplayNames(browserBundleIDs))
    end
    switcher_browsers:next()
    if windowSwitcherWindowIdx == nil then
      windowSwitcherWindowNumber = 0
      for k, v in pairs(switcher_browsers.wf.windows) do
        windowSwitcherWindowNumber = windowSwitcherWindowNumber + 1
      end
      if windowSwitcherWindowNumber > 1 then
        windowSwitcherWindowIdx = 2
      else
        windowSwitcherWindowIdx = windowSwitcherWindowNumber
      end
    else
      if windowSwitcherWindowNumber > 1 then
        windowSwitcherWindowIdx = windowSwitcherWindowIdx + 1
        if windowSwitcherWindowIdx > windowSwitcherWindowNumber then
          windowSwitcherWindowIdx = 1
        end
      end
    end
  end,
  nil,
  function()
    if windowSwitcherWindowIdx ~= windowSwitcherWindowNumber then
      windowSwitcherWindowIdx = windowSwitcherWindowIdx + 1
      switcher_browsers:next()
    end
  end,
  { fn = enabledByWindowSwitcherFunc, or_ = true })

  bindWindowMisc(misc["switchBrowserWindowBack"], 'Previous Browser Window',
  function()
    if not anotherLastBrowserModifierTap:isEnabled() then
      hotkeyEnabledByWindowSwitcher = true
      F_hotkeySuspended = true
      if anotherLastBrowserHotkey ~= nil then
        anotherLastBrowserHotkey:enable()
      end
      anotherLastBrowserModifierTap:start()
    end
    if switcher_browsers == nil then
      switcher_browsers = hs.window.switcher.new(runningAppDisplayNames(browserBundleIDs))
    end
    switcher_browsers:previous()
    if windowSwitcherWindowIdx == nil then
      windowSwitcherWindowNumber = 0
      for k, v in pairs(switcher_browsers.wf.windows) do
        windowSwitcherWindowNumber = windowSwitcherWindowNumber + 1
      end
      windowSwitcherWindowIdx = windowSwitcherWindowNumber
    else
      if windowSwitcherWindowNumber > 0 then
        windowSwitcherWindowIdx = windowSwitcherWindowIdx - 1
        if windowSwitcherWindowIdx == 0 then
          windowSwitcherWindowIdx = windowSwitcherWindowNumber
        end
      end
    end
  end,
  nil,
  function()
    if windowSwitcherWindowIdx > 1 then
      windowSwitcherWindowIdx = windowSwitcherWindowIdx - 1
      switcher_browsers:previous()
    end
  end,
  { fn = enabledByWindowSwitcherFunc, or_ = true })
end

-- show a dialog to specify a window title from all visible windows, use it to switch to a window
-- fixme: full screen space will be ignored if not once focused
bindWindowMisc(misc["searchWindow"], 'Switch to Window',
function()
  local wFilter = hs.window.filter.new()
  for _, appName in ipairs(runningAppDisplayNames(ignoredApps)) do
    wFilter:rejectApp(appName)
  end
  local allWindows = wFilter:getWindows()
  local choices = {}
  for _, window in ipairs(allWindows) do
    table.insert(choices,
        {
          text = window:title(),
          subText = window:application():name(),
          image = window:snapshot(),
          window = window
        })
  end

  if #choices == 0 then
    hs.alert.show("NO VALID WINDOWS")
    return
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    choice.window:focus()
  end)
  chooser:searchSubText(true)
  chooser:choices(choices)
  chooser:show()
end)

require 'utils'

local function browserChooser()
  local choices = {}
  -- get URLs and titles of all tabs of all browsers
  for _, browser in ipairs(browserBundleIDs) do
    local appObject = findApplication(browser)
    if appObject ~= nil then
      local title, tabIDCmd
      if browser == "com.apple.Safari" then
        title = 'name'
        tabIDCmd = 'set theID to j\n'
      else
        title = 'title'
        tabIDCmd = 'set theID to id of atab\n'
      end
      local script = [[
        set theResult to ""
        tell application id "]] .. browser .. [["
          set windowList to every window
          repeat with aWindow in windowList
            set theWinID to ID of aWindow
            set tabList to every tab of aWindow
            repeat with j from 1 to count tabList
              set atab to item j of tabList
              ]] .. tabIDCmd .. [[
              set theUrl to URL of atab
              set theTitle to ]] .. title .. [[ of atab
              set theResult to theResult & theWinID & "|||" & theID & "|||" & theUrl & "|||" & theTitle & "|||"
            end repeat
          end repeat
        end tell
        return theResult
      ]]
      local ok, result = hs.osascript.applescript(script)
      -- parse the result and add them to choices
      if ok then
        for winID, id, url, title in string.gmatch(result, "(.-)%|%|%|(.-)%|%|%|(.-)%|%|%|(.-)%|%|%|") do
          table.insert(choices,
              {
                text = title,
                subText = url,
                image = hs.image.imageFromAppBundle(appObject:bundleID()),
                id = id,
                winID = winID,
                browser = browser
              })
        end
      end
    end
  end

  if #choices == 0 then
    hs.alert.show("NO VALID TABS")
    return
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    local findTabCmd, focusTabCmd, titleField
    if choice.browser == "com.apple.Safari" then
      findTabCmd = 'j is ' .. choice.id
      focusTabCmd = [[
        tell aWindow to set current tab to tab j
      ]]
      titleField = 'name'
    else
      findTabCmd = [[
        (id of item j of tabList is "]] .. tostring(choice.id) .. [[") or ¬
        (id of item j of tabList is ]] .. choice.id .. [[)]]
      focusTabCmd = [[
        tell aWindow to set active tab index to j
      ]]
      titleField = 'title'
    end

    local script = [[
      tell application id "]] .. choice.browser .. [["
        set aWindow to window id ]] .. choice.winID .. [[

        set tabList to every tab of aWindow
        repeat with j from 1 to count of tabList
          if ]] .. findTabCmd .. [[ then
            ]] .. focusTabCmd .. [[
            return ]] .. titleField .. [[ of aWindow
          end if
        end repeat
      end tell
    ]]
    local ok, result = hs.osascript.applescript(script)

    if not ok then return end
    local appObject = findApplication(choice.browser)
    appObject:activate()
    local windowMenuItem = localizedMenuBarItem('Window', appObject:bundleID())
    if windowMenuItem == nil then return end
    hs.timer.doAfter(0.1, function()
      hs.eventtap.keyStroke('fn⌃', 'F2')
      appObject:selectMenuItem({ windowMenuItem, result })
    end)
  end)
  chooser:searchSubText(true)
  chooser:choices(choices)
  chooser:show()
end

local function PDFChooser()
  local choices = {}

  -- `PDF Expert`
  local allWindowsPDFExpert, winTabTitlesPDFExpert
  if findApplication("com.readdle.PDFExpert-Mac") ~= nil then
    local appObject = findApplication("com.readdle.PDFExpert-Mac")
    local allWindows = hs.window.filter.new(false):allowApp(appObject:name()):getWindows()
    local winTabTitles = {}
    local winTitles = {}
    local winPaths = {}
    for _, win in ipairs(allWindows) do
      local winUIObj = hs.axuielement.windowElement(win)
      local filePath = ""
      if #winUIObj:childrenWithRole("AXUnknown") ~= 0 then
        local winIdent = winUIObj:childrenWithRole("AXUnknown")[1]:attributeValue("AXIdentifier")
        filePath = string.match(winIdent, "PDFTabContentView (.*%.pdf)$")
      end
      local toolbar = nil
      if win:isFullScreen() then
        toolbar = winUIObj:childrenWithRole("AXGroup")[1]:childrenWithRole("AXToolbar")[1]
      else
        toolbar = winUIObj:childrenWithRole("AXToolbar")[1]
      end
      local tabList = toolbar:childrenWithRole("AXGroup")[1]:childrenWithRole("AXTabGroup")[1]
          :childrenWithRole("AXScrollArea")[1]:childrenWithRole("AXGroup")
      local tabTitles = {}
      for _, tab in ipairs(tabList) do
        table.insert(tabTitles, tab:attributeValue("AXHelp"))
      end
      table.insert(winTitles, win:title())
      table.insert(winPaths, filePath)
      table.insert(winTabTitles, tabTitles)
    end
    for winID, winTitle in ipairs(winTitles) do
      local tabTitles = winTabTitles[winID]
      for tabID, tabTitle in ipairs(tabTitles) do
        local choice =
            {
              text = tabTitle,
              image = hs.image.imageFromAppBundle(appObject:bundleID()),
              id = tabID,
              winID = winID,
              app = "com.readdle.PDFExpert-Mac"
            }
        if winTitle == tabTitle then
          choice.subText = winPaths[winID]
        else
          choice.subText = 'INACTIVE in WINDOW: "' .. winTitle .. '"'
        end
        table.insert(choices, choice)
      end
    end
    allWindowsPDFExpert = allWindows
    winTabTitlesPDFExpert = winTabTitles
  end

  -- `UPDF`
  local allWindowsUPDF
  if findApplication("com.superace.updf.mac") ~= nil then
    local appObject = findApplication("com.superace.updf.mac")
    local allWindows = hs.window.filter.new(false):allowApp(appObject:name()):getWindows()
    local winTabTitles = {}
    local menuItems = getMenuItems(appObject)
    for _, menuItem in ipairs(menuItems or {}) do
      if menuItem.AXTitle == localizedMenuBarItem('Tab', "com.superace.updf.mac") then
        local subMenuItems = menuItem.AXChildren[1]
        local winTitles = {}
        local tabTitles = {}
        for i=5,#subMenuItems do
          local subMenuItem = subMenuItems[i]
          if subMenuItem.AXTitle ~= "" then
            if subMenuItem.AXMenuItemMarkChar == "✓" then
              table.insert(winTitles, subMenuItem.AXTitle)
            end
            table.insert(tabTitles, subMenuItem.AXTitle)
          else
            table.insert(winTabTitles, tabTitles)
            tabTitles = {}
          end
        end
        table.insert(winTabTitles, tabTitles)
        for i, winTitle in ipairs(winTitles) do
        tabTitles = winTabTitles[i]
        for _, tabTitle in ipairs(tabTitles) do
          local choice =
              {
                text = tabTitle,
                image = hs.image.imageFromAppBundle(appObject:bundleID()),
                winTitle = winTitle,
                app = "com.superace.updf.mac"
              }
          if winTitle ~= tabTitle then
            choice.subText = 'INACTIVE in WINDOW: "' .. winTitle .. '"'
          end
          table.insert(choices, choice)
        end
      end
      end
    end
    allWindowsUPDF = allWindows
  end

  -- `Preview`
  if findApplication("com.apple.Preview") ~= nil then
    local ok, results = hs.osascript.applescript([[
      tell application id "com.apple.Preview" to get {id, name} of (every window whose name ends with ".pdf")
    ]])
    if ok and #results[1] > 0 then
      for i=1,#results[1] do
        table.insert(choices,
            {
              text = results[2][i],
              image = hs.image.imageFromAppBundle("com.apple.Preview"),
              id = results[1][i],
              app = "com.apple.Preview"
            })
      end
    end
  end

  -- browsers
  for _, browser in ipairs({"com.apple.Safari", "com.google.Chrome",
                            "com.microsoft.edgemac", "com.microsoft.edgemac.Dev"}) do
    local appObject = findApplication(browser)
    if appObject ~= nil then
      local title, tabIDCmd
      if browser == "com.apple.Safari" then
        title = 'name'
        tabIDCmd = 'set theID to j\n'
      else
        title = 'title'
        tabIDCmd = 'set theID to id of atab\n'
      end
      local script = [[
        set theResult to ""
        tell application id "]] .. browser .. [["
          set windowList to every window
          repeat with aWindow in windowList
            set theWinID to ID of aWindow
            set tabList to every tab of aWindow
            repeat with j from 1 to count tabList
              set atab to item j of tabList
              set theUrl to URL of atab
              if theUrl ends with ".pdf" then
                ]] .. tabIDCmd .. [[
                set theTitle to ]] .. title .. [[ of atab
                set theResult to theResult & theWinID & "|||" & theID & "|||" & theUrl & "|||" & theTitle & "|||"
              end if
            end repeat
          end repeat
        end tell
        return theResult
      ]]
      local ok, result = hs.osascript.applescript(script)
      -- parse the result and add them to choices
      if ok then
        for winID, id, url, title in string.gmatch(result, "(.-)%|%|%|(.-)%|%|%|(.-)%|%|%|(.-)%|%|%|") do
          table.insert(choices,
              {
                text = title,
                subText = url,
                image = hs.image.imageFromAppBundle(appObject:bundleID()),
                id = id,
                winID = winID,
                app = browser
              })
        end
      end
    end
  end

  if #choices == 0 then
    hs.alert.show("NO VALID TABS")
    return
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    if choice.app == "com.readdle.PDFExpert-Mac" then
      allWindowsPDFExpert[choice.winID]:focus()
      if not hs.fnutils.contains(hs.spaces.activeSpaces(),
          hs.spaces.windowSpaces(allWindowsPDFExpert[choice.winID])[1]) then
        hs.timer.usleep(0.5 * 1000000)
      end
      if allWindowsPDFExpert[choice.winID]:title() ~= winTabTitlesPDFExpert[choice.winID][choice.id] then
        local appObject = findApplication(choice.app)
        local isFullScreen = allWindowsPDFExpert[choice.winID]:isFullScreen()
        if not isFullScreen or findMenuItem(appObject, { 'View', 'Always Show Toolbar' }).ticked then
          local locationExtra = isFullScreen and " of group 1\n" or "\n"
          local ok, result = hs.osascript.applescript([[
            tell application "System Events"
              tell ]] .. aWinFor(choice.app) .. [[
                set tabList to the value of attribute "AXChildren" of ¬
                    scroll area 1 of tab group 1 of group 1 of toolbar 1]] .. locationExtra .. [[
                set atab to item ]] .. choice.id .. [[ of tabList
                return the value of attribute "AXPosition" of atab
              end tell
            end tell
          ]])
          if ok then
            if leftClickAndRestore({ x = result.x + 10, y = result.y }, appObject:name()) then
              return
            end
          end
        end
        local activeIdx = hs.fnutils.indexOf(winTabTitlesPDFExpert[choice.winID],
            allWindowsPDFExpert[choice.winID]:title()) or 0
        if activeIdx < choice.id then
          for i=1,choice.id-activeIdx do
            selectMenuItem(appObject, { "Window", "Go to Next Tab" })
          end
        else
          for i=1,activeIdx-choice.id do
            selectMenuItem(appObject, { "Window", "Go to Previous Tab" })
          end
        end
      end
    elseif choice.app == "com.superace.updf.mac" then
      local appObject = findApplication(choice.app)
      for _, window in ipairs(allWindowsUPDF) do
        if window:title() == choice.winTitle then
          window:focus()
          selectMenuItem(appObject, { 'Tab', choice.text })
          return
        end
      end
      appObject:activate()
      hs.timer.doAfter(0.1, function()
        hs.eventtap.keyStroke('fn⌃', 'F2')
        selectMenuItem(appObject, { 'Tab', choice.text })
      end)
    elseif choice.app == "com.apple.Preview" then
      local ok, result = hs.osascript.applescript([[
        tell application id "com.apple.Preview"
          activate
          set aWindow to window id ]] .. choice.id .. [[

          set index of aWindow to 1
        end tell
      ]])
    else
      local findTabCmd, focusTabCmd, titleField
      if choice.app == "com.apple.Safari" then
        findTabCmd = 'j is ' .. choice.id
        focusTabCmd = [[
          tell aWindow to set current tab to tab j
        ]]
        titleField = 'name'
      else
        findTabCmd = [[
          (id of item j of tabList is "]] .. tostring(choice.id) .. [[") or ¬
          (id of item j of tabList is ]] .. choice.id .. [[)]]
        focusTabCmd = [[
          tell aWindow to set active tab index to j
        ]]
        titleField = 'title'
      end
      local script = [[
        tell application id "]] .. choice.app .. [["
          set aWindow to window id ]] .. choice.winID .. [[

          set tabList to every tab of aWindow
          repeat with j from 1 to count of tabList
            if ]] .. findTabCmd .. [[ then
              ]] .. focusTabCmd .. [[
              return ]] .. titleField .. [[ of aWindow
            end if
          end repeat
        end tell
      ]]
      local ok, result = hs.osascript.applescript(script)

      if not ok then return end
      local appObject = findApplication(choice.app)
      appObject:activate()
      local windowMenuItem = localizedMenuBarItem('Window', appObject:bundleID())
      if windowMenuItem == nil then return end
      hs.timer.doAfter(0.1, function()
        hs.eventtap.keyStroke('fn⌃', 'F2')
        appObject:selectMenuItem({ windowMenuItem, result })
      end)
    end
  end)
  chooser:choices(choices)
  chooser:show()
end

-- show a dialog to specify a tab title from all windows of browsers or `PDF Expert`
-- use it to switch to a tab
bindWindowMisc(misc["searchTab"], 'Switch to Tab',
function()
  if hs.fnutils.contains({ "com.readdle.PDFExpert-Mac", "com.superace.updf.mac" },
      hs.application.frontmostApplication():bundleID()) then
    PDFChooser()
    return
  end

  if hs.application.frontmostApplication():bundleID() == "com.apple.Preview" then
    local aWin = activatedWindowIndex()
    local ok, results = hs.osascript.applescript([[
      tell application id "com.apple.Preview" to get name of window ]] .. aWin .. [[ ends with ".pdf"
    ]])
    if ok and results == true then
      PDFChooser()
      return
    end
  end

  browserChooser()
end)
