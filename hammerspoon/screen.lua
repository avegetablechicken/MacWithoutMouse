local function newWindow(...)
  local hotkey = newHotkeySpec(...)
  if hotkey == nil then return nil end
  hotkey.kind = HK.WIN_OP
  hotkey.subkind = HK.WIN_OP_.SPACE_SCREEN
  return hotkey
end

local function bindWindow(...)
  local hotkey = bindHotkeySpec(...)
  if hotkey == nil then return nil end
  hotkey.kind = HK.WIN_OP
  hotkey.subkind = HK.WIN_OP_.SPACE_SCREEN
  return hotkey
end

local ssHK = KeybindingConfigs.hotkeys.global

-- # monitor ops

-- move cursor to other monitor

local function isInScreen(screen, win)
  return win:screen() == screen
end

local function focusScreen(screen)
  -- Get windows within screen, ordered from front to back.
  -- If no windows exist, bring focus to desktop. Otherwise, set focus on
  -- front-most application window.
  local windows = hs.fnutils.filter(
      hs.window.orderedWindows(),
      hs.fnutils.partial(isInScreen, screen))
  local windowToFocus = #windows > 0 and windows[1] or hs.window.desktop()
  windowToFocus:focus()

  -- move cursor to center of screen
  local pt = hs.geometry.rectMidPoint(screen:fullFrame())
  hs.mouse.absolutePosition(pt)
  if (#windows == 0) then
    hs.eventtap.leftClick(pt)
  end

  local screenName = screen:name()
  hs.alert.show("Focus on \"" .. screenName .. "\"")
end

local function checkAndMoveCursurToMonitor(monitor)
  if #hs.screen.allScreens() > 1 then
    local monitorToFocus = monitor == "r" and hs.screen.mainScreen():next() or hs.screen.mainScreen():previous()
    focusScreen(monitorToFocus)
  else
    hs.alert.show("Only ONE Monitor")
  end
end

-- move window (along with cursor) to other monitor

local function centerMouse(scrn)
    local rect = scrn:fullFrame()
    local center = hs.geometry.rectMidPoint(rect)
    hs.mouse.absolutePosition(center)
end

local consistencyDelay = 0.9 -- seconds
local function moveToScreen(win, screen)
  if win:isFullScreen() then
    win:setFullScreen(false)
    -- a sleep is required to let the window manager register the new state
    hs.timer.doAfter(consistencyDelay, function()
        win:moveToScreen(screen, false, true)
    end)
    hs.timer.doAfter(consistencyDelay, function()
        win:setFullScreen(true)
    end)
  else
    win:moveToScreen(screen, true, true, 0.0)
  end

  centerMouse(screen)

  local screenName = screen:name()
  hs.alert.show("Move \"" .. win:title() .. "\" to \"" .. screenName .. "\"")
end

local function checkAndMoveWindowToMonitor(monitor)
  local win = hs.window.focusedWindow()
  if win == nil then return end
  if #hs.screen.allScreens() > 1 then
    local monitorToMoveTo = monitor == "r" and win:screen():next() or win:screen():previous()
    moveToScreen(win, monitorToMoveTo)
  else
    hs.alert.show("Only ONE Monitor")
  end
end

-- move cursor to next monitor
local adjacentMonitorHotkeys = {}
local image = hs.image.imageFromPath("static/display.png")
table.insert(adjacentMonitorHotkeys, newHotkeySpec(ssHK["focusNextScreen"], "Focus on Next Monitor",
    hs.fnutils.partial(checkAndMoveCursurToMonitor, "r")))
-- move cursor to previous monitor
table.insert(adjacentMonitorHotkeys, newHotkeySpec(ssHK["focusPrevScreen"], "Focus on Previous Monitor",
    hs.fnutils.partial(checkAndMoveCursurToMonitor, "l")))

-- move window to next monitor
table.insert(adjacentMonitorHotkeys, newWindow(ssHK["moveToNextScreen"], "Move to Next Monitor",
    hs.fnutils.partial(checkAndMoveWindowToMonitor, "r")))
-- move window to previous monitor
table.insert(adjacentMonitorHotkeys, newWindow(ssHK["moveToPrevScreen"], "Move to Previous Monitor",
    hs.fnutils.partial(checkAndMoveWindowToMonitor, "l")))

for _, hotkey in ipairs(adjacentMonitorHotkeys) do
  hotkey.icon = image
end

local focusMonitorHotkeys = {}
local moveToScreenHotkeys = {}
local function registerMonitorHotkeys()
  if #moveToScreenHotkeys > 0 or #focusMonitorHotkeys > 0 then
    for _, hotkey in ipairs(focusMonitorHotkeys) do
      hotkey:delete()
    end
    for _, hotkey in ipairs(moveToScreenHotkeys) do
      hotkey:delete()
    end
  end
  focusMonitorHotkeys = {}
  moveToScreenHotkeys = {}

  local nscreens = #hs.screen.allScreens()
  if nscreens <= 1 then
    for _, hotkey in ipairs(adjacentMonitorHotkeys) do
      hotkey:disable()
    end
    return
  end

  for _, hotkey in ipairs(adjacentMonitorHotkeys) do
    hotkey:enable()
  end

  -- move window to screen by idx
  for i=1,nscreens do
    local hotkey
    hotkey = bindWindow(ssHK["moveToScreen" .. i], "Move to Monitor " .. i,
        function()
          local win = hs.window.focusedWindow()
          if win == nil then return end
          if win:screen():id() ~= hs.screen.allScreens()[i]:id() then
            moveToScreen(win, hs.screen.allScreens()[i])
          end
        end)
    table.insert(moveToScreenHotkeys, hotkey)
    hotkey = bindHotkeySpec(ssHK["focusScreen" .. i], "Focus on Monitor " .. i,
        function()
          local win = hs.window.focusedWindow()
          if win == nil then return end
          if win:screen():id() ~= hs.screen.allScreens()[i]:id() then
            focusScreen(hs.screen.allScreens()[i])
          end
        end)
    hotkey.icon = image
    table.insert(focusMonitorHotkeys, hotkey)
  end
end
registerMonitorHotkeys()


-- # space ops

local function getUserSpaces()
  local user_spaces = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local spaces = hs.spaces.spacesForScreen(screen) or {}
    for _, space in ipairs(spaces) do
      if hs.spaces.spaceType(space) == "user" then
        table.insert(user_spaces, space)
      end
    end
  end
  return user_spaces
end

local function checkAndMoveWindowToSpace(space)
  local user_spaces = getUserSpaces()
  local nspaces = #user_spaces
  if nspaces > 1 then
    local curSpaceID = hs.spaces.focusedSpace()
    local index = hs.fnutils.indexOf(user_spaces, curSpaceID)
    local targetIdx = space == "r" and index + 1 or index - 1
    if 1 <= targetIdx and targetIdx <= nspaces then
      local win = hs.window.focusedWindow()
      if win == nil then return end
      hs.spaces.moveWindowToSpace(win, user_spaces[targetIdx])
      hs.spaces.gotoSpace(user_spaces[targetIdx])
      local screenUUID = hs.spaces.spaceDisplay(user_spaces[targetIdx])
      if win:screen():getUUID() ~= screenUUID then
        focusScreen(hs.screen.find(screenUUID))
      end
      win:focus()
    end
  else
    hs.alert.show("Only ONE User Space")
  end
end

-- move window to next space
local adjacentSpaceHotkeys = {}
table.insert(adjacentSpaceHotkeys, newWindow(ssHK["moveToNextSpace"], "Move to Next Space",
    hs.fnutils.partial(checkAndMoveWindowToSpace, "r")))
-- move window to previous space
table.insert(adjacentSpaceHotkeys, newWindow(ssHK["moveToPrevSpace"], "Move to Previous Space",
    hs.fnutils.partial(checkAndMoveWindowToSpace, "l")))

for _, hotkey in ipairs(adjacentSpaceHotkeys) do
  hotkey.icon = image
end

local moveToSpaceHotkeys = {}
local function registerMoveToSpaceHotkeys()
  if #moveToSpaceHotkeys > 0 then
    for _, hotkey in ipairs(moveToSpaceHotkeys) do
      hotkey:delete()
    end
  end
  moveToSpaceHotkeys = {}

  local user_spaces = getUserSpaces()
  local nspaces = #user_spaces
  if nspaces <= 1 then
    for _, hotkey in ipairs(adjacentSpaceHotkeys) do
      hotkey:disable()
    end
    return
  end

  for _, hotkey in ipairs(adjacentSpaceHotkeys) do
    hotkey:enable()
  end

  -- move window to space by idx
  for i=1,nspaces do
    local hotkey = bindWindow(ssHK["moveToSpace" .. i], "Move to Space " .. i,
      function()
        local win = hs.window.focusedWindow()
        if win == nil then return end
        local user_spaces = getUserSpaces()
        hs.spaces.moveWindowToSpace(win, user_spaces[i])
        hs.spaces.gotoSpace(user_spaces[i])
        local screenUUID = hs.spaces.spaceDisplay(user_spaces[i])
        if win:screen():getUUID() ~= screenUUID then
          focusScreen(hs.screen.find(screenUUID))
        end
        win:focus()
      end)
    hotkey.icon = image
    table.insert(moveToSpaceHotkeys, hotkey)
  end
end
registerMoveToSpaceHotkeys()


-- watch screen changes

function Screen_monitorChangedCallback()
  registerMonitorHotkeys()
  registerMoveToSpaceHotkeys()
end

-- watch space changes

-- detect number of user spaces
ExecContinuously(function()
  local user_spaces = getUserSpaces()
  local nspaces = #user_spaces
  if nspaces ~= #moveToSpaceHotkeys then
    registerMoveToSpaceHotkeys()
  end
end)
