require "utils"

local applicationConfigs
if hs.fs.attributes("config/application.json") ~= nil then
  applicationConfigs = hs.json.read("config/application.json")
end


-- launch or hide applications
local function focusOrHideFinder(appObject)
  local windowFilter = hs.window.filter.new(false):setAppFilter(appObject:name())
  local windows = windowFilter:getWindows()
  local standard = hs.fnutils.find(windows, function(win) return win:isStandard() end)
  if standard == nil then
    appObject = hs.application.open(appObject:bundleID())
  elseif hs.window.focusedWindow() ~= nil
      and hs.window.focusedWindow():application() == appObject then
    if not hs.window.focusedWindow():isStandard() then
      hs.application.open(appObject:bundleID())
      hs.window.focusedWindow():focus()
    else
      appObject:hide()
    end
  else
    if appObject:focusedWindow() ~= nil then
      appObject:focusedWindow():focus()
    else
      appObject:activate()
    end
  end
end

local function focusOrHide(hint)
  local appObject = nil

  if type(hint) == "table" then
    for _, h in ipairs(hint) do
      appObject = findApplication(h)
      if appObject ~= nil then break end
    end
  else
    appObject = findApplication(hint)
  end

  if appObject ~= nil and appObject:bundleID() == "com.apple.finder" then
    focusOrHideFinder(appObject)
    return
  end

  if appObject == nil
    or hs.window.focusedWindow() == nil
    or hs.window.focusedWindow():application() ~= appObject then
    if type(hint) == "table" then
      for _, h in ipairs(hint) do
        appObject = hs.application.open(h, 0.5)
        if appObject ~= nil then break end
      end
    else
      appObject = hs.application.open(hint)
    end
  else
    appObject:hide()
  end
end

local function toggleBarrierConnect()
  local stdout, status = hs.execute("ps -ax | grep Barrier.app/Contents/MacOS/barrier | grep -v grep")
  if status ~= true then
    hs.application.launchOrFocusByBundleID("barrier")
    hs.timer.doAfter(2, function()
      local ok, ret = hs.osascript.applescript([[
        tell application "System Events"
          tell ]] .. aWinFor("barrier") .. [[
            click button "Start"
            delay 0.5
            click button 4
          end tell
        end tell
      ]])

      if ok then
        hs.alert("Barrier started")
      else
        hs.alert("Error occurred")
      end
    end)
  else
    local script = [[
      tell application "System Events"
        set popupMenu to menu 1 of menu bar item 1 of menu bar 2 of ¬
            (first application process whose bundle identifier is "barrier")
        if value of attribute "AXEnabled" of menu item "Start" of popupMenu is true then
          set ret to 0
          click menu item "Start" of popupMenu
        else
          click menu item "Stop" of popupMenu
          set ret to 1
        end if
      end tell

      return ret
    ]]
    if hiddenByBartender("barrier") and hasTopNotch(hs.screen.mainScreen()) then
      script = [[
        tell application id "com.surteesstudios.Bartender" to activate "barrier-Item-0"
        delay 0.2
      ]] .. script
    else
      script = [[
        ignoring application responses
          tell application "System Events"
            click menu bar item 1 of menu bar 2 of ¬
                (first application process whose bundle identifier is "barrier")
          end tell
        end ignoring

        delay 1
        do shell script "killall System\\ Events"
      ]] .. script
    end
    local ok, ret = hs.osascript.applescript(script)
    if ok then
      if ret == 0 then
        hs.alert("Barrier started")
      else
        hs.alert("Barrier stopped")
      end
    else
      hs.alert("Error occurred")
    end
  end
end

local function toggleTopNotch()
  local bundleID = "pl.maketheweb.TopNotch"
  if findApplication(bundleID) == nil then
    hs.application.open(bundleID)
  end
  local appObject = findApplication(bundleID)
  clickRightMenuBarItem(bundleID)
  local appUIObj = hs.axuielement.applicationElement(bundleID)
  appUIObj:elementSearch(
    function(msg, results, count)
      local state = results[1].AXValue
      results[1]:performAction("AXPress")
      if state == 'off' then
        hs.eventtap.keyStroke("", "Escape", nil, appObject)
      else
        hs.timer.usleep(0.05 * 1000000)
        hs.eventtap.keyStroke("", "Space", nil, appObject)
      end
    end,
    function(element)
      return element.AXSubrole == "AXSwitch"
    end)
end

local function getParallelsVMPath(osname)
  osname = string.lower(osname)
  local versions, pathTpl
  if osname == "windows" then
    versions = {"10", "11"}
    pathTpl = os.getenv("HOME") .. "/Parallels/Windows %s.pvm/Windows %s.app"
  elseif osname == "ubuntu" then
    versions = {"16.04", "18.04", "20.04", "22.04", "22.04 ARM64"}
    pathTpl = os.getenv("HOME") .. "/Parallels/Ubuntu %s.pvm/Ubuntu %s.app"
  else
    return nil
  end
  for _, version in ipairs(versions) do
    local path = string.format(pathTpl, version, version)
    if hs.fs.attributes(path) ~= nil then return path end
  end
end

local appConfigs = keybindingConfigs.hotkeys.appkeys or {}
appHotkeys = {}

hyperModal = require('modal/hyper')
hyperModal.install(hyper)
table.insert(hyperModalList, hyperModal)

local function registerAppHotkeys()
  for _, hotkey in ipairs(appHotkeys) do
    hotkey:delete()
  end
  appHotkeys = {}
  hyperModal.hyperMode.keys = hs.fnutils.filter(hyperModal.hyperMode.keys,
      function(hotkey) return hotkey.idx ~= nil end)

  for appname, config in pairs(appConfigs) do
    local flag = false
    if config.appPath then
      if type(config.appPath) == "string" then
        flag = hs.fs.attributes(config.appPath) ~= nil
      elseif type(config.appPath) == "table" then
        flag = hs.fnutils.some(config.appPath, function(appPath)
          return hs.fs.attributes(appPath) ~= nil
        end)
      end
    elseif config.bundleID then
      if type(config.bundleID) == "string" then
        flag = (hs.application.pathForBundleID(config.bundleID) ~= nil
            and hs.application.pathForBundleID(config.bundleID) ~= "")
      elseif type(config.bundleID) == "table" then
        flag = hs.fnutils.some(config.bundleID, function(bundleID)
          return (hs.application.pathForBundleID(bundleID) ~= nil
              and hs.application.pathForBundleID(bundleID) ~= "")
        end)
      end
    elseif config.vm then
      if config.vm == "com.parallels.desktop.console" then
        config.appPath = getParallelsVMPath(appname)
        flag = config.appPath ~= nil
      else
        hs.alert("Unsupported Virtual Machine : " .. config.vm)
      end
    end
    if flag then
      local hotkey = bindSpecSuspend(config, "Toggle " .. appname,
          hs.fnutils.partial(config.fn or focusOrHide, config.bundleID or (config.appPath or appname)))
      hotkey.kind = HK.APPKEY
      if config.bundleID then
        hotkey.bundleID = config.bundleID
      elseif config.appPath then
        hotkey.appPath = config.appPath
      end
      table.insert(appHotkeys, hotkey)
    end
  end
end

registerAppHotkeys()


-- # hotkeys in specific application

-- pipeline of copying latex to `klatexformula` and rendering
function klatexformulaRender()
  hs.osascript.applescript([[
    tell application "System Events"
      tell ]] .. aWinFor("org.klatexformula.klatexformula") .. [[
        click button 2 of splitter group 1
      end tell
    end tell
  ]])
end

function deleteSelectedMessage(appObject, menuItem, force)
  appObject:selectMenuItem(menuItem)
  if force ~= nil then
    hs.timer.usleep(0.1 * 1000000)
    hs.eventtap.keyStroke("", "Tab", nil, appObject)
    hs.timer.usleep(0.1 * 1000000)
    hs.eventtap.keyStroke("", "Space", nil, appObject)
  end
end

function deleteAllMessages(appObject)
  local menuItemTitle = getOSVersion() < OS.Ventura and "File" or "Conversations"
  local appLocale = applicationLocales(appObject:bundleID())[1]
  local subMenuItem = appLocale:sub(1, 2) == "zh" and "删除对话…" or "Delete Conversation…"
  local menuItem, menuItemPath = findMenuItem(appObject, { menuItemTitle, subMenuItem })
  if menuItem == nil then return end
  appUIObj = hs.axuielement.applicationElement(appObject)
  appUIObj:elementSearch(
    function(msg, results, count)
      assert(#results == 1)

      local messageItems = results[1].AXChildren
      if messageItems == nil or #messageItems == 0
        or (#messageItems == 1 and messageItems[1].AXDescription == nil) then
        return
      end

      for _, messageItem in ipairs(messageItems) do
        messageItem:performAction("AXPress")
        hs.timer.usleep(0.1 * 1000000)
        deleteSelectedMessage(appObject, menuItemPath, true)
        hs.timer.usleep(1 * 1000000)
      end
      deleteAllMessages(appObject)
    end,
    function(element)
      return element.AXIdentifier == "ConversationList"
    end
  )
end

local function deleteMousePositionCall(appObject)
  appUIObj = hs.axuielement.applicationElement(appObject)
  appUIObj:elementSearch(
    function(msg, results, count)
      if count == 0 then return end

      local collectionList = results[1].AXChildren
      if collectionList == nil or #collectionList == 0 then return end
      local sectionList = collectionList[1]:childrenWithRole("AXGroup")
      if #sectionList == 0 then return end

      local section = sectionList[1]
      hs.eventtap.rightClick(hs.mouse.absolutePosition())
      local popups = section:childrenWithRole("AXMenu")
      for _, popup in ipairs(popups) do
        for _, menuItem in ipairs(popup:childrenWithRole("AXMenuItem")) do
          if menuItem.AXIdentifier == "menuRemovePersonFromRecents:" then
            menuItem:performAction("AXPress")
            break
          end
        end
      end
    end,
    function(element)
      return element.AXSubrole == "AXCollectionList"
          and element.AXChildren ~= nil and #element.AXChildren > 0
          and element.AXChildren[1].AXSubrole == "AXSectionList"
    end
  )
end

function deleteAllCalls(appObject)
  appUIObj = hs.axuielement.applicationElement(appObject)
  appUIObj:elementSearch(
    function(msg, results, count)
      if count == 0 then return end

      local collectionList = results[1].AXChildren
      if collectionList == nil or #collectionList == 0 then return end
      local sectionList = collectionList[1]:childrenWithRole("AXGroup")
      if #sectionList == 0 then return end

      local section = sectionList[1]
      rightClickAndRestore(section.AXPosition)
      local popups = section:childrenWithRole("AXMenu")
      for _, popup in ipairs(popups) do
        for _, menuItem in ipairs(popup:childrenWithRole("AXMenuItem")) do
          if menuItem.AXIdentifier == "menuRemovePersonFromRecents:" then
            menuItem:performAction("AXPress")
            break
          end
        end
      end
      deleteAllCalls(appObject)
    end,
    function(element)
      return element.AXSubrole == "AXCollectionList"
          and element.AXChildren ~= nil and #element.AXChildren > 0
          and element.AXChildren[1].AXSubrole == "AXSectionList"
    end
  )
end

function confirmDeleteConditionForAppleApps(appObject)
  local ok, result = hs.osascript.applescript([[
    tell application "System Events"
      tell ]] .. aWinFor(appObject) .. [[
        if exists sheet 1 then
          repeat with btn in buttons of sheet 1
            if (exists attribute "AXIdentifier" of btn) ¬
                and (the value of attribute "AXIdentifier" of btn is "DontSaveButton") then
              return true
            end if
          end repeat
        end if
        return false
      end tell
    end tell
  ]])
  return ok and result
end

function confirmDeleteForAppleApps(appObject)
  hs.osascript.applescript([[
    tell application "System Events"
      tell ]] .. aWinFor(appObject) .. [[
        repeat with btn in buttons of sheet 1
          if (exists attribute "AXIdentifier" of btn) ¬
              and (the value of attribute "AXIdentifier" of btn is "DontSaveButton") then
            click btn
          end if
        end repeat
      end tell
    end tell
  ]])
end

local specialCommonHotkeyConfigs = {
  ["closeWindow"] = {
    mods = "⌘", key = "W",
    message = "Close Window",
    repeatable = true,
    condition = function(appObject)
      return appObject:focusedWindow() ~= nil, appObject:focusedWindow()
    end,
    fn = function(winObj) winObj:close() end
  },
  ["minimize"] = {
    mods = "⌘", key = "M",
    message = "Minimize",
    repeatable = true,
    condition = function(appObject)
      return appObject:focusedWindow() ~= nil, appObject:focusedWindow()
    end,
    fn = function(winObj) winObj:minimize() end
  },
  ["hide"] = {
    mods = "⌘", key = "H",
    message = "Hide",
    fn = function(appObject) appObject:hide() end
  },
  ["confirmDelete"] = {
    message = "Confirm Delete",
    condition = confirmDeleteConditionForAppleApps,
    fn = confirmDeleteForAppleApps
  }
}

local function VSCodeToggleSideBarSection(sidebar, section)
  local focusedWindow = hs.application.frontmostApplication():focusedWindow()
  if focusedWindow == nil then return end
  local commonPath = [[group 2 of group 1 of group 2 of group 2 of ¬
    group 1 of group 1 of group 1 of group 1 of UI element 1 of ¬
    group 1 of group 1 of group 1 of UI element 1]]
  local commonPathOld = [[group 2 of group 1 of group 2 of group 2 of ¬
    group 1 of group 1 of group 1 of group 1 of UI element 1]]
  local sidebarAction = [[
    set tabs to radio buttons of tab group 1 of group 1 of group 1 of ¬
        %s
    repeat with tab in tabs
      if title of tab starts with "]] .. sidebar .. [["  ¬
          or value of attribute "AXDescription" of tab starts with "]] .. sidebar .. [[" then
        perform action 1 of tab
        exit repeat
      end if
    end repeat
    delay 0.1
  ]]
  local sectionExpand = [[
    set sections to every group of group 2 of group 1 of group 2 of group 2 of ¬
          %s
      repeat with sec in sections
        if title of UI element 2 of button 1 of group 1 of sec is "]] .. section .. [[" then
          if (count value of attribute "AXChildren" of group 1 of sec) is 1 then
            perform action 1 of button 1 of group 1 of sec
          end if
          exit repeat
        end if
      end repeat
  ]]
  local sectionFold = [[
    set sections to every group of group 2 of group 1 of group 2 of group 2 of ¬
          %s
      repeat with sec in sections
        if title of UI element 2 of button 1 of group 1 of sec is "]] .. section .. [[" then
          perform action 1 of button 1 of group 1 of sec
          exit repeat
        end if
      end repeat
  ]]
  hs.osascript.applescript([[
    tell application "System Events"
      tell ]] .. aWinFor("com.microsoft.VSCode") .. [[
        if (exists UI element 1 of group 1 of group 1 of group 2 of ¬
              ]] .. commonPath .. [[) ¬
            and (title of UI element 1 of group 1 of group 1 of group 2 of ¬
              ]] .. commonPath .. [[ ¬
              starts with "]] .. sidebar .. [[") then
          ]] .. string.format(sectionFold, commonPath) .. [[
        else if (exists UI element 1 of group 1 of group 1 of group 2 of ¬
              ]] .. commonPathOld .. [[) ¬
            and (title of UI element 1 of group 1 of group 1 of group 2 of ¬
              ]] .. commonPathOld .. [[ ¬
              starts with "]] .. sidebar .. [[") then
          ]] .. string.format(sectionFold, commonPathOld) .. [[
        else if (not exists ]] .. commonPath .. [[) ¬
            or (title of UI element 1 of group 1 of group 1 of group 2 of ¬
              ]] .. commonPath .. [[ ¬
              does not start with "]] .. sidebar .. [[") then
          ]] .. string.format(sidebarAction, commonPath) .. [[
          ]] .. string.format(sectionExpand, commonPath) .. [[
        else if (not exists ]] .. commonPathOld .. [[) ¬
            or (title of UI element 1 of group 1 of group 1 of group 2 of ¬
              ]] .. commonPathOld .. [[ ¬
              does not start with "]] .. sidebar .. [[") then
          ]] .. string.format(sidebarAction, commonPathOld) .. [[
          ]] .. string.format(sectionExpand, commonPathOld) .. [[
        end if
      end tell
    end tell
  ]])
end

local function iCopySelectHotkeyRemapRequired()
  local version = hs.execute(string.format('mdls -r -name kMDItemVersion "%s"',
      hs.application.pathForBundleID("cn.better365.iCopy")))
  local major, minor, patch = string.match(version, "(%d+)%.(%d+)%.(%d+)")
  major = tonumber(major)
  minor = tonumber(minor)
  patch = tonumber(patch)
  return major < 1 or (major == 1 and minor < 1) or (major == 1 and minor == 1 and patch < 3)
end

local function iCopySelectHotkeyMod()
  local version = hs.execute(string.format('mdls -r -name kMDItemVersion "%s"',
      hs.application.pathForBundleID("cn.better365.iCopy")))
  local major, minor, patch = string.match(version, "(%d+)%.(%d+)%.(%d+)")
  major = tonumber(major)
  minor = tonumber(minor)
  patch = tonumber(patch)
  local mods
  if major < 1 or (major == 1 and minor < 1) or (major == 1 and minor == 1 and patch < 1) then
    mods = ""
  else
    mods = "⌃"
  end
  return mods
end
local iCopyMod

local function iCopySelectHotkeyRemap(winObj, idx)
  if iCopyMod == nil then
    iCopyMod = iCopySelectHotkeyMod()
  end
  hs.eventtap.keyStroke(iCopyMod, tostring(idx), nil, winObj:application())
end

local function localizedMessage(message, params, sep)
  return function(appObject)
    local bundleID = appObject:bundleID()
    if type(message) == 'string' then
      return localizedString(message, bundleID, params)
    else
      if sep == nil then sep = ' > ' end
      local str
      local appMenus = getMenuItems(appObject)
      if appMenus == nil then return end
      for i=2,#appMenus do
        local title = delocalizedMenuItem(appMenus[i].AXTitle, appObject:bundleID(), params)
        if message[1] == title then
          str = appMenus[i].AXTitle
          break
        end
      end
      if str == nil then
        str = localizedString(message[1], bundleID, params)
      end
      for i=2,#message do
        str = str .. sep .. localizedString(message[i], bundleID, params)
      end
      return str
    end
  end
end

local function menuItemMessage(mods, key, titleIndex, sep)
  return function(appObject)
    if type(titleIndex) == 'number' then
      return findMenuItemByKeyBinding(appObject, mods, key)[titleIndex]
    else
      if sep == nil then sep = ' > ' end
      local menuItem = findMenuItemByKeyBinding(appObject, mods, key)
      local str = menuItem[titleIndex[1]]
      for i=2,#titleIndex do
        str = str .. sep .. menuItem[titleIndex[i]]
      end
    end
  end
end

function checkMenuItem(menuItemTitle, params)
  return function(appObject)
    local menuItem, menuItemTitle = findMenuItem(appObject, menuItemTitle, params)
    return menuItem ~= nil and menuItem.enabled, menuItemTitle
  end
end

function checkMenuItemByKeybinding(mods, key)
  return function(appObject)
    local menuItem, enabled = findMenuItemByKeyBinding(appObject, mods, key)
    return menuItem ~= nil and enabled, menuItem
  end
end

function receiveMenuItem(menuItemTitle, appObject)
  appObject:selectMenuItem(menuItemTitle)
end

appHotKeyCallbacks = {
  ["com.apple.finder"] =
  {
    ["goToDownloads"] = {
      message = localizedMessage({ "Go", "Downloads" }, "MenuBar"),
      fn = function(appObject)
        selectMenuItem(appObject, { "Go", "Downloads" }, { localeFile = "MenuBar" })
      end
    },
    ["showPrevTab"] = {
      message = menuItemMessage({ 'shift', 'ctrl' }, "⇥", 2),
      repeatable = true,
      condition = checkMenuItemByKeybinding({ 'shift', 'ctrl' }, "⇥"),
      fn = receiveMenuItem
    },
    ["showNextTab"] = {
      message = menuItemMessage({ 'ctrl' }, "⇥", 2),
      repeatable = true,
      condition = checkMenuItemByKeybinding({ 'ctrl' }, "⇥"),
      fn = receiveMenuItem
    }
  },

  ["com.apple.MobileSMS"] =
  {
    ["deleteConversation"] = {
      message = function(appObject)
        local appLocale = applicationLocales(appObject:bundleID())[1]
        return appLocale:sub(1, 2) == "zh" and "删除对话…" or "Delete Conversation…"
      end,
      condition = function(appObject)
        local menuItemTitle = getOSVersion() < OS.Ventura and "File" or "Conversations"
        local appLocale = applicationLocales(appObject:bundleID())[1]
        local subItemTitle = appLocale:sub(1, 2) == "zh" and "删除对话…" or "Delete Conversation…"
        return checkMenuItem({ menuItemTitle, subItemTitle })(appObject)
      end,
      fn = function(menuItemTitle, appObject) deleteSelectedMessage(appObject, menuItemTitle) end
    },
    ["deleteAllConversations"] = {
      message = "Delete All Conversations",
      fn = deleteAllMessages
    },
    ["goToPreviousConversation"] = {
      message = menuItemMessage({ 'shift', 'ctrl' }, "⇥", 2),
      repeatable = true,
      condition = checkMenuItemByKeybinding({ 'shift', 'ctrl' }, "⇥"),
      fn = receiveMenuItem
    },
    ["goToNextConversation"] = {
      message = menuItemMessage({ 'ctrl' }, "⇥", 2),
      repeatable = true,
      condition = checkMenuItemByKeybinding({ 'ctrl' }, "⇥"),
      fn = receiveMenuItem
    }
  },

  ["com.apple.FaceTime"] = {
    ["deleteMousePositionCall"] = {
      message = "Delete Call at Mouse Position",
      fn = deleteMousePositionCall
    },
    ["deleteAllCalls"] = {
      message = "Delete All Calls",
      fn = deleteAllCalls
    }
  },

  ["com.apple.ScriptEditor2"] =
  {
    ["confirmDelete"] = specialCommonHotkeyConfigs["confirmDelete"]
  },

  ["com.apple.AppStore"] =
  {
    ["back"] = {
      mods = "⌘", key = "[",
      message = localizedMessage("Back", "Localizable"),
      repeatable = true,
      condition = function(appObject)
        local menuItem, menuItemTitle = findMenuItem(appObject, { "Store", "Back" },
                                                     { localeFile = "Localizable" })
        if menuItem ~= nil and menuItem.enabled then
          return true, menuItemTitle
        else
          local ok, result = hs.osascript.applescript([[
            tell application "System Events"
              tell ]] .. aWinFor(appObject) .. [[
                if exists button 1 of last group of splitter group 1 then
                  return 1
                else if exists (button 1 of group 1 ¬
                    whose value of attribute "AXIdentifier" is "UIA.AppStore.NavigationBackButton") then
                  return 2
                else if exists (button 1 of group 1 ¬
                    whose value of attribute "AXIdentifier" is "AppStore.backButton") then
                  return 2
                else
                  return 0
                end if
              end tell
            end tell
          ]])
          return ok and (result ~= 0), result
        end
      end,
      fn = function(result, appObject)
        if type(result) == 'table' then
          appObject:selectMenuItem(result)
        elseif result == 1 then
          hs.osascript.applescript([[
            tell application "System Events"
              tell ]] .. aWinFor(appObject) .. [[
                perform action "AXPress" of button 1 of last group of splitter group 1
              end tell
            end tell
          ]])
        else
          hs.osascript.applescript([[
            tell application "System Events"
              tell ]] .. aWinFor(appObject) .. [[
                perform action "AXPress" of button 1 of group 1
              end tell
            end tell
          ]])
        end
      end
    }
  },

  ["com.apple.Safari"] =
  {
    ["revealInFinder"] = {
      message = "Reveal in Finder",
      condition = function(appObject)
        local aWin = activatedWindowIndex()
        local ok, url = hs.osascript.applescript([[
          tell application id "]] .. appObject:bundleID() .. [["
            return URL of current tab of window ]] .. aWin .. [[

          end tell
        ]])
        if ok and string.sub(url, 1, 7) == "file://" then
          return true, url
        else
          return false
        end
      end,
      fn = function(url) hs.execute('open -R "' .. url .. '"') end
    }
  },

  ["com.apple.Preview"] =
  {
    ["revealInFinder"] = {
      message = "Reveal in Finder",
      condition = function(appObject)
        local ok, filePath = hs.osascript.applescript([[
          tell application id "]] .. appObject:bundleID() .. [[" to get path of front document
        ]])
        if ok then
          return true, filePath
        else
          return false
        end
      end,
      fn = function(filePath) hs.execute("open -R '" .. filePath .. "'") end
    }
  },

  ["com.google.Chrome"] =
  {
    ["revealInFinder"] = {
      message = "Reveal in Finder",
      condition = function(appObject)
        local aWin = activatedWindowIndex()
        local ok, url = hs.osascript.applescript([[
          tell application id "]] .. appObject:bundleID() .. [["
            return URL of active tab of window ]] .. aWin .. [[

          end tell
        ]])
        if ok and string.sub(url, 1, 7) == "file://" then
          return true, url
        else
          return false
        end
      end,
      fn = function(url) hs.execute('open -R "' .. url .. '"') end
    }
  },

  ["com.microsoft.VSCode"] =
  {
    ["view:toggleOutline"] = {
      message = "View: Toggle Outline",
      condition = function(appObject) return appObject:focusedWindow() ~= nil end,
      fn = function() VSCodeToggleSideBarSection("EXPLORER", "OUTLINE") end
    }
  },

  ["com.readdle.PDFExpert-Mac"] =
  {
    ["showInFinder"] = {
      message = localizedMessage("Show in Finder", "MainMenu"),
      condition = checkMenuItem({ "File", "Show in Finder" }, { localeFile = "MainMenu" }),
      fn = receiveMenuItem
    }
  },

  ["abnerworks.Typora"] =
  {
    ["openFileLocation"] = {
      message = localizedMessage("Open File Location","Menu"),
      condition = checkMenuItem({ "File", "Open File Location" }, { localeFile = "Menu" }),
      fn = receiveMenuItem
    },
    ["pasteAsPlainText"] = {
      message = localizedMessage("Paste as Plain Text", "Menu"),
      repeatable = true,
      fn = function(appObject)
        selectMenuItem(appObject, { "Edit", "Paste as Plain Text" },
                       { localeFile = "Menu" })
      end
    },
    ["confirmDelete"] = specialCommonHotkeyConfigs["confirmDelete"]
  },

  ["com.vallettaventures.Texpad"] =
  {
    ["confirmDelete"] = specialCommonHotkeyConfigs["confirmDelete"]
  },

  ["com.superace.updf.mac"] =
  {
    ["showInFinder"] = {
      message = localizedMessage("Show in Finder", "Localizable"),
      condition = checkMenuItem({ "File", "Show in Finder" }, { localeFile = "Localizable" }),
      fn = receiveMenuItem
    }
  },

  ["com.kingsoft.wpsoffice.mac"] =
  {
    ["newWorkspace"] = {
      message = menuItemMessage({ 'ctrl', 'alt' }, "N", 2),
      repeatable = true,
      condition = checkMenuItemByKeybinding({ 'ctrl', 'alt' }, "N"),
      fn = receiveMenuItem
    },
    ["closeWorkspace"] = {
      message = "关闭工作区",
      repeatable = true,
      condition = checkMenuItem({ zh = { "工作区", "关闭工作区" }}),
      fn = receiveMenuItem
    },
    ["previousWindow"] = {
      message = menuItemMessage({ 'shift', 'ctrl' }, "⇥", 2),
      repeatable = true,
      condition = checkMenuItemByKeybinding({ 'shift', 'ctrl' }, "⇥"),
      fn = receiveMenuItem
    },
    ["nextWindow"] = {
      message = menuItemMessage({ 'ctrl' }, "⇥", 2),
      repeatable = true,
      condition = checkMenuItemByKeybinding({ 'ctrl' }, "⇥"),
      fn = receiveMenuItem
    },
    ["closeDoNotSave"] = {
      message = "不保存",
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
        if winUIObj.AXSubrole == "AXDialog" then
          local buttons = winUIObj:childrenWithRole("AXButton")
          for _, button in ipairs(buttons) do
            if button.AXTitle == "不保存" then
              return true, button
            end
          end
        end
        return false
      end,
      fn = function(button) button:performAction("AXPress") end
    },
    ["closeCancel"] = {
      message = "取消",
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
        if winUIObj.AXSubrole == "AXDialog" then
          local buttons = winUIObj:childrenWithRole("AXButton")
          for _, button in ipairs(buttons) do
            if button.AXTitle == "取消" then
              return true, button
            end
          end
        end
        return false
      end,
      fn = function(button) button:performAction("AXPress") end
    },
    ["closeSave"] = {
      message = "保存",
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
        if winUIObj.AXSubrole == "AXDialog" then
          local buttons = winUIObj:childrenWithRole("AXButton")
          for _, button in ipairs(buttons) do
            if button.AXTitle == "保存" then
              return true, button
            end
          end
        end
        return false
      end,
      fn = function(button) button:performAction("AXPress") end
    },
    ["goToFileTop"] = {
      message = "Go to File Top",
      fn = function(appObject) hs.eventtap.keyStroke("⌘", "Home", nil, appObject) end
    },
    ["goToFileBottom"] = {
      message = "Go to File Bottom",
      fn = function(appObject) hs.eventtap.keyStroke("⌘", "End", nil, appObject) end
    },
    ["selectToFileTop"] = {
      message = "Select to File Top",
      fn = function(appObject) hs.eventtap.keyStroke("⇧⌘", "Home", nil, appObject) end
    },
    ["selectToFileBottom"] = {
      message = "Select to File Bottom",
      fn = function(appObject) hs.eventtap.keyStroke("⇧⌘", "End", nil, appObject) end
    },
    ["openFileLocation"] = {
      message = "打开文件位置",
      fn = function(appObject)
        local aWin = activatedWindowIndex()
        local appUIObj = hs.axuielement.applicationElement(appObject)
        local buttons = appUIObj:childrenWithRole("AXWindow")[aWin]
            :childrenWithRole("AXButton")
        if #buttons == 0 then return end
        local mousePosition = hs.mouse.absolutePosition()
        local ok, position = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor(appObject) .. [[
              repeat with i from 1 to count (UI elements)
                if value of attribute "AXRole" of UI element i is "AXGroup" then
                  return position of UI element (i-1)
                end if
              end repeat
            end tell
          end tell
        ]])
        if not ok then return end
        hs.eventtap.rightClick(hs.geometry(position))
        hs.osascript.applescript([[
          tell application "System Events"
            tell first application process whose bundle identifier is "]] .. appObject:bundleID() .. [["
              set totalDelay to 0.0
              repeat until totalDelay > 0.5
                repeat with e in ui elements
                  if exists menu item "打开文件位置" of menu 1 of e then
                    perform action 1 of menu item "打开文件位置" of menu 1 of e
                    return true
                  end if
                end repeat
                delay 0.05
                set totalDelay to totalDelay + 0.05
              end repeat
              return false
            end tell
          end tell
        ]])
        hs.mouse.absolutePosition(mousePosition)
      end
    }
  },

  ["com.apple.iWork.Keynote"] =
  {
    ["exportToPDF"] = {  -- File > Export To > PDF…
      message = localizedMessage({ "Export To", "PDF…" }, "MainMenu"),
      condition = checkMenuItem({ "File", "Export To", "PDF…" }, { localeFile = "MainMenu" }),
      fn = function(menuItemTitle, appObject)
        appObject:selectMenuItem({ menuItemTitle[1], menuItemTitle[2] })
        appObject:selectMenuItem(menuItemTitle)
      end
    },
    ["exportToPPT"] = {  -- File > Export To > PowerPoint…
      message = localizedMessage({ "Export To", "PowerPoint…" }, "MainMenu"),
      condition = checkMenuItem({ "File", "Export To", "PowerPoint…" }, { localeFile = "MainMenu" }),
      fn = function(menuItemTitle, appObject)
        appObject:selectMenuItem({ menuItemTitle[1], menuItemTitle[2] })
        appObject:selectMenuItem(menuItemTitle)
      end
    },
    ["pasteAndMatchStyle"] = {  -- Edit > Paste and Match Style
      message = localizedMessage("Paste and Match Style", "MainMenu"),
      repeatable = true,
      condition = checkMenuItem({ "Edit", "Paste and Match Style" }, { localeFile = "MainMenu" }),
      fn = receiveMenuItem
    },
    ["paste"] = {  -- Edit > Paste
      message = localizedMessage("Paste", "MainMenu"),
      repeatable = true,
      condition = checkMenuItem({ "Edit", "Paste" }, { localeFile = "MainMenu" }),
      fn = receiveMenuItem
    },
    ["showBuildOrder"] = {  -- View > Show Build Order
      message = localizedMessage("Show Build Order", "MainMenu"),
      condition = checkMenuItem({ "View", "Show Build Order" }, { localeFile = "MainMenu" }),
      fn = receiveMenuItem
    },
    ["play"] = {  -- Play > Play Slideshow
      message = localizedMessage("Play Slideshow", "MainMenu"),
      condition = checkMenuItem({ "Play", "Play Slideshow" }, { localeFile = "MainMenu" }),
      fn = receiveMenuItem
    },
    ["insertEquation"] = {  -- Insert > Equation…
      message = localizedMessage({ "Insert", "Equation..." }, "MainMenu"),
      condition = checkMenuItem({ "Insert", "Equation..." }, { localeFile = "MainMenu" }),
      fn = receiveMenuItem
    },
    ["revealInFinder"] = {
      message = "Reveal in Finder",
      condition = function(appObject)
        local ok, filePath = hs.osascript.applescript([[
          tell application id "]] .. appObject:bundleID() .. [[" to get file of front document
        ]])
        if ok and filePath ~= nil then
          local pos = string.find(filePath, ":", 1)
          filePath = string.sub(filePath, pos)
          filePath = string.gsub(filePath, ":", "/")
          return true, filePath
        else
          return false
        end
      end,
      fn = function(filePath) hs.execute("open -R '" .. filePath .. "'") end
    },
    ["confirmDelete"] = specialCommonHotkeyConfigs["confirmDelete"]
  },

  ["net.xmind.vana.app"] =
  {
    ["export"] = {
      message = "Export",
      fn = function(appObject)
        selectMenuItem(appObject, { en = {"File", "Export"}, zh = {"文件", "导出"} }, true)
      end
    },
    ["insertEquation"] = {
      message = "Insert Equation",
      condition = checkMenuItem({ en = {"Insert", "Equation"}, zh = {"插入", "方程"} }),
      fn = receiveMenuItem
    }
  },

  ["org.klatexformula.klatexformula"] =
  {
    ["render"] = {
      message = "Render",
      fn = klatexformulaRender
    },
    ["renderClipboardInKlatexformula"] = {
      message = "Render Clipboard in klatexformula",
      fn = function(appObject)
        appObject:mainWindow():focus()
        appObject:selectMenuItem({"Shortcuts", "Activate Editor and Select All"})
        hs.eventtap.keyStroke("⌘", "V", nil, appObject)

        klatexformulaRender()
      end
    }
  },

  ["cn.edu.idea.paper"] =
  {
    ["showPrevTab"] = {
      message = "Show Previous Tab",
      repeatable = true,
      fn = function(appObject) hs.eventtap.keyStroke("⌘", "Left", nil, appObject) end
    },
    ["showNextTab"] = {
      message = "Show Next Tab",
      repeatable = true,
      fn = function(appObject) hs.eventtap.keyStroke("⌘", "Right", nil, appObject) end
    },
    ["minimize"] = specialCommonHotkeyConfigs["minimize"]
  },

  ["com.tencent.xinWeChat"] =
  {
    ["back"] = {
      message = localizedMessage("Common.Navigation.Back", { localeFir = "Localizable", key = true }),
      repeatable = true,
      condition = function(appObject)
        local bundleID = appObject:bundleID()
        local params = { localeFir = "Localizable", key = true }
        local back = localizedString("Common.Navigation.Back", bundleID, params)
        local lastPage = localizedString("WebView.Previous.Item", bundleID, params)
        local moments = localizedString("SNS_Feed_Window_Title", bundleID, params)
        local detail = localizedString("SNS_Feed_Detail_Title", bundleID, params)
        local ok, result = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor(appObject) .. [[
              -- Official Accounts
              if exists button "]] .. back .. [[" of splitter group 1 of splitter group 1 then
                return 1
              end if

              -- Minimized Groups
              if exists splitter group 1 then
                set bt to every button of splitter group 1 whose description is "]] .. back .. [["
                if (count bt) > 0 then
                  return 2
                end if
              end if

              -- Push Notifications
              set bts to every button
              repeat with bt in bts
                if value of attribute "AXHelp" of bt is "]] .. lastPage .. [[" ¬
                    and value of attribute "AXEnabled" of bt is True then
                  return 3
                end if
              end repeat

              -- Moments
              if (exists image 1) and ((ui element 1) is (image 1)) ¬
                  and (exists scroll area 1) and ((ui element 2) is (scroll area 1)) ¬
                  and (exists image 2) and ((ui element 3) is (image 2)) ¬
                  and (exists image 2) and ((ui element 4) is (button 1)) then
                return position of button 1
              end if

              -- Moments Details
              if name is "]] .. moments .. '-' .. detail .. [[" then
                return position of button 1
              end if

              return false
            end tell
          end tell
        ]])
        if ok and result ~= false then
          if result == 1 then
            return true, { 1, back}
          elseif result == 2 then
            return true, { 2 }
          elseif result == 3 then
            return true, { 3, lastPage }
          else
            return true, { 4, result }
          end
        else
          return false
        end
      end,
      fn = function(result, appObject)
        if type(result[2]) == "table" then
          leftClickAndRestore(result[2])
        else
          local script = [[
            tell application "System Events"
              tell ]] .. aWinFor(appObject) .. [[
                %s
              end tell
            end tell
          ]]
          if result[1] == 1 then
            script = string.format(script, [[
              click button "]] .. result[2] .. [[" of splitter group 1 of splitter group 1
            ]])
          elseif result[1] == 2 then
            script = string.format(script, [[
              key code 123
            ]])
          else
            script = string.format(script, [[
              set bts to every button
              repeat with bt in bts
                if value of attribute "AXHelp" of bt is "]] .. result[2] .. [[" ¬
                    and value of attribute "AXEnabled" of bt is True then
                  click bt
                  exit repeat
                end if
              end repeat
            ]])
          end
          hs.osascript.applescript(script)
        end
      end
    },
    ["forward"] = {
      message = localizedMessage("WebView.Next.Item", { localeFir = "Localizable", key = true }),
      repeatable = true,
      condition = function(appObject)
        local bundleID = appObject:bundleID()
        local nextPage = localizedString("WebView.Next.Item", bundleID, { localeFir = "Localizable", key = true })
        local ok, valid = hs.osascript.applescript([[
          tell application "System Events"
            -- Push Notifications
            set bts to every button of ]] .. aWinFor(appObject) .. [[
            repeat with bt in bts
              if value of attribute "AXHelp" of bt is "]] .. nextPage .. [[" ¬
                  and value of attribute "AXEnabled" of bt is True then
                return true
              end if
            end repeat
            return false
          end tell
        ]])
        return ok and valid, nextPage
      end,
      fn = function(nextPage, appObject)
        hs.osascript.applescript([[
          tell application "System Events"
            -- Push Notifications
            set bts to every button of ]] .. aWinFor(appObject) .. [[
            repeat with bt in bts
              if value of attribute "AXHelp" of bt is "]] .. nextPage .. [[" ¬
                  and value of attribute "AXEnabled" of bt is True then
                click bt
                return
              end if
            end repeat
          end tell
        ]])
      end
    }
  },

  ["com.tencent.QQMusicMac"] =
  {
    ["back"] = {
      message = "Back",
      condition = function(appObject)
        local bundleID = appObject:bundleID()
        local version = hs.execute(string.format('mdls -r -name kMDItemVersion "%s"',
            hs.application.pathForBundleID(bundleID)))
        local major, minor, patch = string.match(version, "(%d+)%.(%d+)%.(%d+)")
        if tonumber(major) < 9 then
          local song = localizedString("COMMON_SONG", bundleID,
                                      { localeDir = false, key = true })
          local detail = localizedString("COMMON_DETAIL", bundleID,
                                        { localeDir = false, key = true })
          local ok, valid = hs.osascript.applescript([[
            tell application "System Events"
              tell ]] .. aWinFor(appObject) .. [[
                set btCnt to count (every button)
                return (exists button "]] .. song .. detail .. [[") and btCnt > 4
              end tell
            end tell
          ]])
          return ok and valid
        else
          local ok, valid = hs.osascript.applescript([[
              tell application "System Events"
                tell (first process whose bundle identifier is "]] .. appObject:bundleID() .. [[")
                  if number of windows is greater than or equal to 2 then
                    set aWin to window 1
                    set mWin to (window 1 whose value of attribute "AXMain" is true)
                    if aWin is not mWin then
                      set aWinPos to value of attribute "AXPosition" of aWin
                      set mWinPos to value of attribute "AXPosition" of mWin
                      set aWinSz to value of attribute "AXSize" of aWin
                      set mWinSz to value of attribute "AXSize" of mWin
                      if aWinPos is equal to mWinPos ¬
                          and aWinSz is equal to mWinSz then
                        return true
                      end if
                    end if
                  end if
                  return false
                end tell
              end tell
          ]])
          return ok and valid
        end
      end,
      fn = function(code, appObject)
        hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor(appObject) .. [[
              set btCnt to count (every button)
              click button (btCnt - 2)
            end tell
          end tell
        ]])
      end
    }
  },

  ["barrier"] =
  {
    ["toggleBarrierConnect"] = {
      message = "Toggle Barrier Connect",
      fn = toggleBarrierConnect,
    },
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.objective-see.lulu.app"] =
  {
    ["allowConnection"] = {
      message = "Allow Connection",
      windowFilter = {
        allowTitles = "^LuLu Alert$"
      },
      fn = function(winObj)
        hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor(winObj:application()) .. [[
              click button "Allow"
            end tell
          end tell
        ]])
      end
    },
    ["blockConnection"] = {
      message = "Block Connection",
      windowFilter = {
        allowTitles = "^LuLu Alert$"
      },
      fn = function(winObj)
        hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor(winObj:application()) .. [[
              click button "Block"
            end tell
          end tell
        ]])
      end
    }
  },

  ["com.surteesstudios.Bartender"] =
  {
    ["toggleMenuBar"] = {
      message = "Toggle Menu Bar",
      kind = HK.MENUBAR,
      fn = function(appObject)
        local bundleID = appObject:bundleID()
        local hasShowed = hs.fnutils.some(appObject:allWindows(), function(w) return w:title() == "Bartender Bar" end)
        local script = string.format([[
          tell application id "%s" to toggle bartender
        ]], bundleID)
        if not hasShowed then
          script = script .. string.format([[
            tell application "System Events"
              tell (first process whose bundle identifier is "%s")
                set icons to window "Bartender Bar"'s scroll area 1's list 1's list 1
                return {value of attribute "AXPosition", value of attribute "AXDescription"} of image 1 of groups of icons
              end tell
            end tell
          ]], bundleID)
        end
        local ok, ret = hs.osascript.applescript(script)
        if not hasShowed and ok and #ret[1] > 0 then
          local positions, appNames = ret[1], ret[2]
          if bartenderBarHotkeys == nil then bartenderBarHotkeys = {} end
          local maxCnt = math.min(#positions, 10)
          for i = 1, maxCnt do
            table.insert(bartenderBarHotkeys, bindSuspend("", i == 10 and "0" or tostring(i), "Click " .. appNames[i], function()
              leftClickAndRestore(positions[i])
            end))
          end
          for i = 1, maxCnt do
            table.insert(bartenderBarHotkeys, bindSuspend("⌥", i == 10 and "0" or tostring(i), "Right-click " .. appNames[i], function()
              rightClickAndRestore(positions[i])
            end))
          end
          if bartenderBarFilter == nil then
            bartenderBarFilter = hs.window.filter.new(false):setAppFilter(appObject:name(),
                { allowTitles = "Bartender Bar" })
          end
          bartenderBarFilter:subscribe(hs.window.filter.windowDestroyed, function()
            for _, v in ipairs(bartenderBarHotkeys) do v:delete() end
            bartenderBarHotkeys = nil
            bartenderBarFilter:unsubscribeAll()
          end)
        end
      end
    },
    ["searchMenuBar"] = {
      message = "Search Menu Bar",
      kind = HK.MENUBAR,
      fn = function()
        hs.osascript.applescript([[tell application id "com.surteesstudios.Bartender" to quick search]])
      end
    },
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.gaosun.eul"] =
  {
    ["showSystemStatus"] = {
      message = "Show System Status",
      kind = HK.MENUBAR,
      fn = function(appObject) clickRightMenuBarItem(appObject:bundleID()) end
    }
  },

  ["whbalzac.Dongtaizhuomian"] =
  {
    ["invokeInAppScreenSaver"] = {
      message = localizedString("In-app ScreenSaver", "whbalzac.Dongtaizhuomian",
                                { localeFir = "HotkeyWindowController" }),
      fn = function(appObject)
        clickRightMenuBarItem(appObject:bundleID(),
                             { "In-app ScreenSaver",
                               strings = "HotkeyWindowController" })
      end
    }
  },

  ["pl.maketheweb.TopNotch"] =
  {
    ["toggleTopNotch"] = {
      message = "Toggle Top Notch",
      fn = toggleTopNotch,
    }
  },

  ["com.jetbrains.toolbox"] =
  {
    ["toggleJetbrainsToolbox"] = {
      message = "Toggle Jetbrains Toolbox",
      fn = hs.fnutils.partial(focusOrHide, "com.jetbrains.toolbox"),
    }
  },

  ["com.mathpix.snipping-tool-noappstore"] =
  {
    ["OCRForLatex"] = {
      message = "OCR for LaTeX",
      fn = function()
        local bundleID = "com.mathpix.snipping-tool-noappstore"
        local action = function()
          runningAppHotKeys[bundleID][1]:disable()
          hs.eventtap.keyStroke("⌃⌘", "M")
          hs.timer.doAfter(1, function() runningAppHotKeys[bundleID][1]:enable() end)
        end
        if findApplication(bundleID) == nil then
          hs.application.open(bundleID)
          hs.timer.doAfter(1, action)
        else
          action()
        end
      end
    }
  },

  ["com.macosgame.iwallpaper"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"],
    ["minimize"] = specialCommonHotkeyConfigs["minimize"],
    ["hide"] = specialCommonHotkeyConfigs["hide"]
  },

  ["org.pqrs.Karabiner-EventViewer"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.pigigaldi.pock"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.tencent.LemonUpdate"] =
  {
    ["minimize"] = specialCommonHotkeyConfigs["minimize"],
    ["hide"] = specialCommonHotkeyConfigs["hide"]
  },

  ["com.apple.CaptiveNetworkAssistant"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.parallels.desktop.console"] =
  {
    ["new..."] = {
      mods = "⌘", key = "N",
      message = localizedMessage("New..."),
      repeatable = true,
      fn = function(appObject)
        selectMenuItem(appObject, { "File", "New..." })
      end
    },
    ["open..."] = {
      mods = "⌘", key = "O",
      message = localizedMessage("Open..."),
      repeatable = true,
      fn = function(appObject)
        selectMenuItem(appObject, { "File", "Open..." })
      end
    },
    ["hide"] = specialCommonHotkeyConfigs["hide"],
    ["minimize"] = {
      mods = "⌘", key = "M",
      message = localizedMessage("Minimize"),
      repeatable = true,
      fn = function(appObject)
        selectMenuItem(appObject, { "Window", "Minimize" })
      end
    },
    ["closeWindow"] = {
      mods = "⌘", key = "W",
      message = localizedMessage("Close Window"),
      repeatable = true,
      condition = function(appObject)
        local menuItem, menuItemTitle = findMenuItem(appObject, { "File", "Close Window" })
        if menuItem ~= nil and menuItem.enabled then
          return true, menuItemTitle
        elseif appObject:focusedWindow() ~= nil then
          return true, appObject:focusedWindow()
        else
          return false
        end
      end,
      fn = function(result, appObject)
        if type(result) == 'table' then
          appObject:selectMenuItem(result)
        else
          result:close()
        end
      end
    }
  },

  ["com.apple.Terminal"] =
  {
    ["tmuxPreviousPane"] = {
      -- previous pane
      message = "Previous Pane",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "o", nil, winObj:application())
      end
    },
    ["tmuxNextPane"] = {
      -- next pane
      message = "Next Pane",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", ";", nil, winObj:application())
      end
    },
    ["tmuxAbovePane"] = {
      -- above pane
      message = "Above Pane",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "Up", nil, winObj:application())
      end
    },
    ["tmuxBelowPane"] = {
      -- below pane
      message = "Below Pane",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "Down", nil, winObj:application())
      end
    },
    ["tmuxLeftPane"] = {
      -- left pane
      message = "Left Pane",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "Left", nil, winObj:application())
      end
    },
    ["tmuxRightPane"] = {
      -- right pane
      message = "Right Pane",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "Right", nil, winObj:application())
      end
    },
    ["tmuxNewHorizontalPane"] = {
      -- new pane (horizontal)
      message = "New Pane (Horizontal)",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("⇧", "5", nil, winObj:application())  -- %
      end
    },
    ["tmuxNewVerticalPane"] = {
      -- new pane (vertical)
      message = "New Pane (Vertical)",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("⇧", "'", nil, winObj:application())  -- "
      end
    },
    ["tmuxClosePane"] = {
      -- close pane
      message = "Close Pane",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "x", nil, winObj:application())
      end
    },
    ["tmuxPreviousWindow"] = {
      -- previous window
      message = "Previous Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "p", nil, winObj:application())
      end
    },
    ["tmuxNextWindow"] = {
      -- next window
      message = "Next Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "n", nil, winObj:application())
      end
    },
    ["tmuxWindow0"] = {
      -- 0th window
      message = "0th Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "0", nil, winObj:application())
      end
    },
    ["tmuxWindow1"] = {
      -- 1st window
      message = "1st Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "1", nil, winObj:application())
      end
    },
    ["tmuxWindow2"] = {
      -- 2nd window
      message = "2nd Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "2", nil, winObj:application())
      end
    },
    ["tmuxWindow3"] = {
      -- 3rd window
      message = "3rd Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "3", nil, winObj:application())
      end
    },
    ["tmuxWindow4"] = {
      -- 4th window
      message = "4th Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "4", nil, winObj:application())
      end
    },
    ["tmuxWindow5"] = {
      -- 5th window
      message = "5th Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "5", nil, winObj:application())
      end
    },
    ["tmuxWindow6"] = {
      -- 6th window
      message = "6th Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "6", nil, winObj:application())
      end
    },
    ["tmuxWindow7"] = {
      -- 7th window
      message = "7th Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "7", nil, winObj:application())
      end
    },
    ["tmuxWindow8"] = {
      -- 8th window
      message = "8th Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "8", nil, winObj:application())
      end
    },
    ["tmuxWindow9"] = {
      -- 9th window
      message = "9th Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "9", nil, winObj:application())
      end
    },
    ["tmuxNewWindow"] = {
      message = "New Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "c", nil, winObj:application())
      end
    },
    ["tmuxCloseWindow"] = {
      message = "Close Window",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("⇧", "7", nil, winObj:application())  -- &
      end
    },
    ["tmuxDetachSession"] = {
      message = "Detach Session",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "D", nil, winObj:application())
      end
    },
    ["tmuxEnterCopyMode"] = {
      message = "Copy Mode",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "[", nil, winObj:application())
      end
    },
    ["tmuxSearch"] = {
      message = "Search",
      fn = function(winObj)
        hs.eventtap.keyStroke("⌃", "B", nil, winObj:application())
        hs.eventtap.keyStroke("", "[", nil, winObj:application())
        hs.eventtap.keyStroke("⌃", "s", nil, winObj:application())  -- emacs mode
      end
    }
  },

  ["com.jetbrains.CLion"] =
  {
    ["newProject"] = {
      message = "New Project",
      fn = function(appObject)
        local ok, pos = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor(appObject) .. [[
              if exists button 1 of button 2 then
                return position of button 1 of button 2
              else
                return position of button 1 of button 1 of group 2
              end if
            end tell
          end tell
        ]])
        leftClickAndRestore(pos)
      end
    },
    ["open..."] = {
      message = "Open...",
      fn = function(winObj)
        winObj:application():selectMenuItem({"File", "Open..."})
      end
    }
  },

  ["com.jetbrains.CLion-EAP"] =
  {
    ["newProject"] = {
      message = "New Project",
      fn = function(appObject)
        local ok, pos = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor(appObject) .. [[
              if exists button 1 of button 2 then
                return position of button 1 of button 2
              else
                return position of button 1 of button 1 of group 2
              end if
            end tell
          end tell
        ]])
        leftClickAndRestore(pos)
      end
    },
    ["open..."] = {
      message = "Open...",
      fn = function(winObj)
        winObj:application():selectMenuItem({"File", "Open..."})
      end
    }
  },

  ["com.jetbrains.intellij"] =
  {
      ["newProject"] = {
        message = "New Project",
        fn = function(appObject)
          local ok, pos = hs.osascript.applescript([[
            tell application "System Events"
              tell ]] .. aWinFor(appObject) .. [[
                set bt to button 1 of button 2
                return position of bt
              end tell
            end tell
          ]])
          leftClickAndRestore(pos)
        end
      },
      ["open..."] = {
        message = "Open...",
        fn = function(winObj)
          winObj:application():selectMenuItem({"File", "Open..."})
        end
      }
  },

  ["com.jetbrains.pycharm"] =
  {
    ["newProject"] = {
      message = "New Project",
      fn = function(appObject)
        local ok, pos = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor(appObject) .. [[
              set bt to button 1 of button 2
              return position of bt
            end tell
          end tell
        ]])
        leftClickAndRestore(pos)
      end
    },
    ["open..."] = {
      message = "Open...",
      fn = function(winObj)
        winObj:application():selectMenuItem({"File", "Open..."})
      end
    }
  },

  ["cn.better365.iShotPro"] =
  {
    ["OCR"] = {
      message = "OCR",
      fn = function()
        local bundleID = "cn.better365.iShotPro"
        local action = function()
          runningAppHotKeys[bundleID][1]:disable()
          hs.eventtap.keyStroke("⌃⌘", "O")
          hs.timer.doAfter(1, function() runningAppHotKeys[bundleID][1]:enable() end)
        end
        if findApplication(bundleID) == nil then
          hs.application.open(bundleID)
          hs.timer.doAfter(1, action)
        else
          action()
        end
      end
    }
  },

  ["cn.better365.iCopy"] =
  {
    {
      filter = { allowRegions = {
        hs.geometry.rect(
          0, hs.screen.mainScreen():fullFrame().y + hs.screen.mainScreen():fullFrame().h - 400,
          hs.screen.mainScreen():fullFrame().w, 400)
        }
      },
      hotkeys =
      {
        {
          mods = "⌘", key = "1",
          message = "Select 1st Item",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 1) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "2",
          message = "Select 2nd Item",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 2) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "3",
          message = "Select 3rd Item",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 3) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "4",
          message = "Select 4th Item",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 4) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "5",
          message = "Select 5th Item",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 5) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "6",
          message = "Select 6th Item",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 6) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "7",
          message = "Select 7th Item",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 7) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "8",
          message = "Select 8th Item",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 8) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "9",
          message = "Select 9th Item",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 9) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "[",
          message = "Next Category",
          fn = function(winObj) hs.eventtap.keyStroke("", "Left", nil, winObj:application()) end
        },
        {
          mods = "⌘", key = "]",
          message = "Previous Category",
          fn = function(winObj) hs.eventtap.keyStroke("", "Right", nil, winObj:application()) end
        },
        {
          mods = "", key = "Left",
          message = "Previous Item",
          fn = function(winObj) hs.eventtap.keyStroke("", "Up", nil, winObj:application()) end
        },
        {
          mods = "", key = "Right",
          message = "Next Item",
          fn = function(winObj) hs.eventtap.keyStroke("", "Down", nil, winObj:application()) end
        },
        {
          mods = "", key = "Up",
          message = "Cancel Up",
          fn = function() end
        },
        {
          mods = "", key = "Down",
          message = "Cancel Down",
          fn = function() end
        },
        {
          mods = "", key = "Tab",
          message = "Cancel Tab",
          fn = function() end
        },
      }
    }
  }
}

runningAppHotKeys = {}
inAppHotKeys = {}
inWinHotKeys = {}

local runningAppWatchers = {}
local function registerRunningAppHotKeys(bid, appObject)
  if appHotKeyCallbacks[bid] == nil then return end
  local keyBindings = keybindingConfigs.hotkeys[bid]
  if keyBindings == nil then
    keyBindings = {}
  end

  if appObject == nil then
    appObject = findApplication(bid)
  end

  if runningAppHotKeys[bid] ~= nil then
    for _, hotkey in ipairs(runningAppHotKeys[bid]) do
      hotkey:delete()
    end
  end
  runningAppHotKeys[bid] = {}

  local allPersist = true
  for hkID, cfg in pairs(appHotKeyCallbacks[bid]) do
    local keyBinding = keyBindings[hkID]
    if keyBinding == nil then
      keyBinding = {
        mods = cfg.mods,
        key = cfg.key,
      }
    end
    if (cfg.bindCondition == nil or cfg.bindCondition()) and keyBinding.background == true
        and (appObject ~= nil or (keyBinding.persist == true
        and (hs.application.pathForBundleID(bid) ~= nil
             and hs.application.pathForBundleID(bid) ~= ""))) then
      local fn = hs.fnutils.partial(cfg.fn, appObject)
      local repeatedFn = cfg.repeatable and fn or nil
      local msg
      if type(cfg.message) == 'string' then
        msg = cfg.message
      elseif keyBinding.persist ~= true then
        msg = cfg.message(appObject)
      end
      if msg ~= nil then
        local hotkey = bindSpecSuspend(keyBinding, msg, fn, nil, repeatedFn)
        if keyBinding.persist == true then
          hotkey.persist = true
        else
          allPersist = false
        end
        hotkey.kind = cfg.kind or HK.BACKGROUND
        hotkey.bundleID = bid
        table.insert(runningAppHotKeys[bid], hotkey)
      end
    end
  end

  if not allPersist and runningAppWatchers[bid] == nil then
    runningAppWatchers[bid] = hs.timer.new(1, function()
      local runningApps = hs.application.runningApplications()
      local invalidIdx = {}
      for i, hotkey in ipairs(runningAppHotKeys[bid]) do
        if hotkey.persist ~= true then
          local appObject = hs.fnutils.find(runningApps, function(app)
            return app:bundleID() == bid
          end)
          if appObject == nil then
            hotkey:delete()
            table.insert(invalidIdx, i)
          end
        end
      end
      for i=#invalidIdx, 1, -1 do
        table.remove(runningAppHotKeys[bid], invalidIdx[i])
      end
      if #runningAppHotKeys[bid] == 0 then
        runningAppHotKeys[bid] = nil
        runningAppWatchers[bid]:stop()
        runningAppWatchers[bid] = nil
      end
    end):start()
  end
end

local function unregisterRunningAppHotKeys(bid, force)
  if appHotKeyCallbacks[bid] == nil then return end

  if runningAppHotKeys[bid] then
    local allDeleted = true
    for _, hotkey in ipairs(runningAppHotKeys[bid]) do
      if hotkey.persist ~= true then
        hotkey:disable()
      end
      if force == true then
        hotkey:delete()
      else
        allDeleted = false
      end
    end
    if allDeleted then
      runningAppHotKeys[bid] = nil
    end
  end
  if runningAppWatchers[bid] ~= nil and findApplication(bid) == nil then
    runningAppWatchers[bid]:stop()
    runningAppWatchers[bid] = nil
  end
end

windowCreatedSince = {}
windowWatcher = hs.window.filter.new(true):subscribe(
{hs.window.filter.windowCreated, hs.window.filter.windowFocused, hs.window.filter.windowDestroyed},
function(winObj, appName, eventType)
  if winObj == nil or winObj:application() == nil
      or winObj:application():bundleID() == hs.application.frontmostApplication():bundleID() then
    return
  end
  if eventType == hs.window.filter.windowCreated or eventType == hs.window.filter.windowFocused then
    windowCreatedSince[winObj:id()] = winObj:application():bundleID()
  else
    for wid, bid in pairs(windowCreatedSince) do
      if hs.window.get(wid) == nil or hs.window.get(wid):application():bundleID() ~= bid then
        windowCreatedSince[wid] = nil
      end
    end
  end
end)

local function inAppHotKeysWrapper(appObject, mods, key, func)
  if func == nil then
    func = key key = mods.key mods = mods.mods
  end
  return function()
    if hs.window.frontmostWindow() ~= nil and appObject:focusedWindow() ~= nil
        and hs.window.frontmostWindow():application():bundleID() ~= appObject:bundleID() then
      hs.eventtap.keyStroke(mods, key, nil, hs.window.frontmostWindow():application())
    elseif hs.window.frontmostWindow() ~= nil and appObject:focusedWindow() == nil
        and windowCreatedSince[hs.window.frontmostWindow():id()] then
      hs.eventtap.keyStroke(mods, key, nil, hs.window.frontmostWindow():application())
    else
      func()
    end
  end
end

local function registerInAppHotKeys(appName, eventType, appObject)
  local bid = appObject:bundleID()
  if appHotKeyCallbacks[bid] == nil then return end
  local keyBindings = keybindingConfigs.hotkeys[bid]
  if keyBindings == nil then
    keyBindings = {}
  end

  if not inAppHotKeys[bid] then
    inAppHotKeys[bid] = {}
    for hkID, cfg in pairs(appHotKeyCallbacks[bid]) do
      if type(hkID) == 'number' then break end
      local keyBinding = keyBindings[hkID]
      if keyBinding == nil then
        keyBinding = {
          mods = cfg.mods,
          key = cfg.key,
        }
      end
      if (cfg.bindCondition == nil or cfg.bindCondition()) and keyBinding.background ~= true then
        local fn = cfg.fn
        if cfg.condition ~= nil then
          fn = function(appObject, appName, eventType)
            local satisfied, result = cfg.condition(appObject)
            if satisfied then
              if result ~= nil then
                cfg.fn(result, appObject, appName, eventType)
              else
                cfg.fn(appObject, appName, eventType)
              end
            else
              hs.eventtap.keyStroke(keyBinding.mods, keyBinding.key, nil, appObject)
            end
          end
        end
        fn = inAppHotKeysWrapper(appObject, keyBinding,
                                 hs.fnutils.partial(fn, appObject, appName, eventType))
        local repeatedFn = cfg.repeatable and fn or nil
        local msg = type(cfg.message) == 'string' and cfg.message or cfg.message(appObject)
        if msg ~= nil then
          local hotkey = bindSpecSuspend(keyBinding, msg, fn, nil, repeatedFn)
          hotkey.kind = HK.IN_APP
          hotkey.condition = cfg.condition
          table.insert(inAppHotKeys[bid], hotkey)
        end
      end
    end
  else
    for _, hotkey in ipairs(inAppHotKeys[bid]) do
      hotkey:enable()
    end
  end
end

local function unregisterInAppHotKeys(bid, eventType, delete)
  if appHotKeyCallbacks[bid] == nil then return end

  for _, hotkey in ipairs(inAppHotKeys[bid]) do
    hotkey:disable()
  end
  if delete ~= nil and delete then
    for _, hotkey in ipairs(inAppHotKeys[bid]) do
      hotkey:delete()
    end
    inAppHotKeys[bid] = nil
  end
end

local inWinCallbackChain = {}
inWinHotkeyInfoChain = {}

local function hotkeyIdx(mods, key)
  local idx = string.upper(key)
  if type(mods) == 'string' then
    mods = {mods}
  end
  if hs.fnutils.contains(mods, "shift") then idx = "⇧" .. idx end
  if hs.fnutils.contains(mods, "option") then idx = "⌥" .. idx end
  if hs.fnutils.contains(mods, "control") then idx = "⌃" .. idx end
  if hs.fnutils.contains(mods, "command") then idx = "⌘" .. idx end
  if hs.fnutils.contains(mods, "fn") then idx = "fn" .. idx end
  return idx
end

local function inWinHotKeysWrapper(appObject, filter, mods, key, message, fn)
  if fn == nil then
    fn = message message = key key = mods.key mods = mods.mods
  end
  local bid = appObject:bundleID()
  if inWinCallbackChain[bid] == nil then inWinCallbackChain[bid] = {} end
  if inWinHotkeyInfoChain[bid] == nil then inWinHotkeyInfoChain[bid] = {} end
  local prevCallback = inWinCallbackChain[bid][hotkeyIdx(mods, key)]
  local prevHotkeyInfo = inWinHotkeyInfoChain[bid][hotkeyIdx(mods, key)]
  local wrapper = function(winObj)
    if winObj == nil then winObj = appObject:focusedWindow() end
    if winObj == nil then return end
    local windowFilter = hs.window.filter.new(false):setAppFilter(
        appObject:name(), filter)
    if windowFilter:isWindowAllowed(winObj) then
      fn(winObj)
    elseif prevCallback ~= nil then
      prevCallback(winObj)
    else
      hs.eventtap.keyStroke(mods, key, nil, appObject)
    end
  end
  inWinCallbackChain[bid][hotkeyIdx(mods, key)] = wrapper
  inWinHotkeyInfoChain[bid][hotkeyIdx(mods, key)] = {
    appName = appObject:name(),
    filter = filter,
    message = message,
    previous = prevHotkeyInfo
  }
  return inAppHotKeysWrapper(appObject, mods, key, wrapper)
end

local function registerInWinHotKeys(appObject)
  local bid = appObject:bundleID()
  if appHotKeyCallbacks[bid] == nil then return end
  local keyBindings = keybindingConfigs.hotkeys[bid]
  if keyBindings == nil then
    keyBindings = {}
  end

  if not inWinHotKeys[bid] then
    inWinHotKeys[bid] = {}
    for hkID, spec in pairs(appHotKeyCallbacks[bid]) do
      local keyBinding = keyBindings[hkID]
      if keyBinding == nil then
        keyBinding = {
          mods = spec.mods,
          key = spec.key,
        }
      end
      if keyBinding.windowFilter == nil and spec.windowFilter ~= nil then
        keyBinding.windowFilter = spec.windowFilter
        for k, v in pairs(keyBinding.windowFilter) do
          if type(v) == 'function' then
            keyBinding.windowFilter[k] = v(appObject)
          end
        end
      end
      if type(hkID) ~= 'number' then
        if keyBinding.windowFilter ~= nil and (spec.bindCondition == nil or spec.bindCondition())
            and not spec.notActivateApp then
          local msg = type(spec.message) == 'string' and spec.message or spec.message(appObject)
          if msg ~= nil then
            local fn = inWinHotKeysWrapper(appObject, keyBinding.windowFilter, keyBinding, msg, spec.fn)
            local repeatedFn = spec.repeatable and fn or nil
            local hotkey = bindSpecSuspend(keyBinding, msg, fn, nil, repeatedFn)
            hotkey.kind = HK.IN_APPWIN
            table.insert(inWinHotKeys[bid], hotkey)
          end
        end
      else
        local cfg = spec
        for _, spec in ipairs(cfg.hotkeys) do
          if (spec.bindCondition == nil or spec.bindCondition()) and not spec.notActivateApp then
            local msg = type(spec.message) == 'string' and spec.message or spec.message(appObject)
            if msg ~= nil then
              local fn = inWinHotKeysWrapper(appObject, cfg.filter, spec, msg, spec.fn)
              local repeatedFn = spec.repeatable and fn or nil
              local hotkey = bindSpecSuspend(spec, msg, fn, nil, repeatedFn)
              hotkey.kind = HK.IN_APPWIN
              table.insert(inWinHotKeys[bid], hotkey)
            end
          end
        end
      end
    end
  else
    for _, hotkey in ipairs(inWinHotKeys[bid]) do
      hotkey:enable()
    end
    for hkID, spec in pairs(appHotKeyCallbacks[bid]) do
      local keyBinding = keyBindings[hkID]
      if keyBinding == nil then
        keyBinding = {
          mods = spec.mods,
          key = spec.key,
        }
      end
      if keyBinding.windowFilter == nil and spec.windowFilter ~= nil then
        keyBinding.windowFilter = spec.windowFilter
        for k, v in pairs(keyBinding.windowFilter) do
          if type(v) == 'function' then
            keyBinding.windowFilter[k] = v(appObject)
          end
        end
      end
      if type(hkID) ~= 'number' then
        if keyBinding.windowFilter ~= nil then
          local hkIdx = hotkeyIdx(keyBinding.mods, keyBinding.key)
          local prevHotkeyInfo = inWinHotkeyInfoChain[bid][hkIdx]
          local msg = type(spec.message) == 'string' and spec.message or spec.message(appObject)
          if msg ~= nil then
            inWinHotkeyInfoChain[bid][hkIdx] = {
              appName = appObject:name(),
              filter = keyBinding.windowFilter,
              message = msg,
              previous = prevHotkeyInfo
            }
          end
        end
      else
        local cfg = spec
        for _, spec in ipairs(cfg.hotkeys) do
          local hkIdx = hotkeyIdx(spec.mods, spec.key)
          local prevHotkeyInfo = inWinHotkeyInfoChain[bid][hkIdx]
          local msg = type(spec.message) == 'string' and spec.message or spec.message(appObject)
          if msg ~= nil then
            inWinHotkeyInfoChain[bid][hkIdx] = {
              appName = appObject:name(),
              filter = cfg.filter,
              message = msg,
              previous = prevHotkeyInfo
            }
          end
        end
      end
    end
  end
end

local function unregisterInWinHotKeys(bid, delete)
  if appHotKeyCallbacks[bid] == nil or inWinHotKeys[bid] == nil then return end

  for _, hotkey in ipairs(inWinHotKeys[bid]) do
    hotkey:disable()
  end
  if delete ~= nil and delete then
    for _, hotkey in ipairs(inWinHotKeys[bid]) do
      hotkey:delete()
    end
    inWinHotKeys[bid] = nil
    inWinCallbackChain[bid] = nil
    inWinHotkeyInfoChain[bid] = nil
  end
end

local function sameFilter(a, b)
  for k, v in pairs(a) do
    if b[k] ~= v then
      return false
    end
  end
  for k, v in pairs(b) do
    if a[k] ~= v then
      return false
    end
  end
  return true
end

local inWinOfUnactivatedAppHotKeys = {}
local inWinOfUnactivatedAppWatchers = {}
local function inWinOfUnactivatedAppWatcherEnableCallback(bid, filter, winObj, appName)
  if inWinOfUnactivatedAppHotKeys[bid] == nil then
    inWinOfUnactivatedAppHotKeys[bid] = {}
  end
  for hkID, spec in pairs(appHotKeyCallbacks[bid]) do
    if type(hkID) ~= 'number' then
      if (spec.bindCondition == nil or spec.bindCondition()) and sameFilter(keybindingConfigs.hotkeys[bid][hkID].windowFilter, filter) then
        local msg = type(spec.message) == 'string' and spec.message or spec.message(winObj:application())
        if msg ~= nil then
          local hotkey = bindSpecSuspend(keybindingConfigs.hotkeys[bid][hkID], msg,
                                        spec.fn, nil, spec.repeatable and spec.fn or nil)
          hotkey.kind = HK.IN_WIN
          hotkey.notActivateApp = spec.notActivateApp
          table.insert(inWinOfUnactivatedAppHotKeys[bid], hotkey)
        end
      end
    else
      local cfg = spec[1]
      if sameFilter(cfg.filter, filter) then
        for _, spec in ipairs(cfg) do
          if (spec.bindCondition == nil or spec.bindCondition()) then
            local msg = type(spec.message) == 'string' and spec.message or spec.message(winObj:application())
            if msg ~= nil then
              local hotkey = bindSuspend(spec.mods, spec.key, msg,
                                        spec.fn, nil, spec.repeatable and spec.fn or nil)
              hotkey.kind = HK.IN_WIN
              hotkey.notActivateApp = cfg.notActivateApp
              table.insert(inWinOfUnactivatedAppHotKeys[bid], hotkey)
            end
          end
        end
      end
    end
  end
end
local function registerSingleWinFilterForDaemonApp(appObject, filter)
  local bid = appObject:bundleID()
  local appName = appObject:name()
  local filterEnable = hs.window.filter.new(false):setAppFilter(appName, filter):subscribe(
      {hs.window.filter.windowCreated, hs.window.filter.windowFocused},
      hs.fnutils.partial(inWinOfUnactivatedAppWatcherEnableCallback, bid, filter)
  )
  local filterDisable = hs.window.filter.new(false):setAppFilter(appName, filter):subscribe(
      {hs.window.filter.windowDestroyed, hs.window.filter.windowUnfocused}, function(winObj, appName)
    if inWinOfUnactivatedAppHotKeys[bid] ~= nil then  -- fix weird bug
      for i, hotkey in ipairs(inWinOfUnactivatedAppHotKeys[bid]) do
        if hotkey.idx ~= nil then
          hotkey:delete()
          inWinOfUnactivatedAppHotKeys[bid][i] = nil
        end
      end
      if #inWinOfUnactivatedAppHotKeys[bid] == 0 then
        inWinOfUnactivatedAppHotKeys[bid] = nil
      end
    end
    if #inWinOfUnactivatedAppWatchers[bid][filter] == 0 then
      inWinOfUnactivatedAppWatchers[bid][filter] = nil
    end
  end)
  inWinOfUnactivatedAppWatchers[bid][filter] = { filterEnable, filterDisable }
end

local function registerWinFiltersForDaemonApp(appObject, appConfig)
  local bid = appObject:bundleID()
  for hkID, spec in pairs(appConfig) do
    if spec.notActivateApp then
      local filter
      if type(hkID) ~= 'number' then
        filter = keybindingConfigs.hotkeys[bid][hkID].windowFilter or spec.windowFilter
      else
        local cfg = spec[1]
        filter = cfg.filter
      end
      for k, v in pairs(filter) do
        if type(v) == 'function' then
          filter[k] = v(appObject)
        end
      end
      if inWinOfUnactivatedAppWatchers[bid] == nil
        or inWinOfUnactivatedAppWatchers[bid][filter] == nil then
        if inWinOfUnactivatedAppWatchers[bid] == nil then
          inWinOfUnactivatedAppWatchers[bid] = {}
        end
        if type(hkID) ~= 'number' then
          registerSingleWinFilterForDaemonApp(appObject, filter)
        else
          local cfg = spec[1]
          for _, spec in ipairs(cfg) do
            registerSingleWinFilterForDaemonApp(appObject, filter)
          end
        end
      end
    end
  end
end

for bid, _ in pairs(appHotKeyCallbacks) do
  registerRunningAppHotKeys(bid)
end

registerInAppHotKeys(hs.application.frontmostApplication():title(),
  hs.application.watcher.activated,
  hs.application.frontmostApplication())

local frontWin = hs.window.frontmostWindow()
if frontWin ~= nil then
  registerInWinHotKeys(frontWin:application())

  local frontWinAppBid = frontWin:application():bundleID()
  if inWinOfUnactivatedAppWatchers[frontWinAppBid] ~= nil then
    local frontWinAppName = frontWin:application():title()
    for filter, _ in pairs(inWinOfUnactivatedAppWatchers[frontWinAppBid]) do
      local filterEnable = hs.window.filter.new(false):setAppFilter(frontWinAppName, filter)
      if filterEnable:isWindowAllowed(frontWin) then
        inWinOfUnactivatedAppWatcherEnableCallback(frontWinAppBid, filter, frontWin, frontWinAppName)
      end
    end
  end
end

for bid, appConfig in pairs(appHotKeyCallbacks) do
  local appObject = findApplication(bid)
  if appObject ~= nil then
    registerWinFiltersForDaemonApp(appObject, appConfig)
  end
end

-- simplify switching to previous tab
function remapPreviousTab(bundleID)
  if keybindingConfigs.hotkeys.appCommon == nil
      or keybindingConfigs.hotkeys.appCommon["remapPreviousTab"] == nil
      or hs.fnutils.contains(keybindingConfigs.hotkeys.appCommon["remapPreviousTab"].excluded or {},
                             bundleID) then
    return
  end
  local spec = keybindingConfigs.hotkeys.appCommon["remapPreviousTab"]
  if remapPreviousTabHotkey then
    remapPreviousTabHotkey:delete()
    remapPreviousTabHotkey = nil
  end
  local appObject = hs.application.frontmostApplication()
  local menuItemPath = findMenuItemByKeyBinding(appObject, { 'shift', 'ctrl' }, '⇥')
  if menuItemPath ~= nil then
    local cond = function(appObject)
      local menuItemCond = appObject:findMenuItem(menuItemPath)
      return menuItemCond ~= nil and menuItemCond.enabled
    end
    local fn = inAppHotKeysWrapper(appObject, spec.mods, spec.key,
        function()
          if cond(appObject) then appObject:selectMenuItem(menuItemPath)
          else hs.eventtap.keyStroke(spec.mods, spec.key, nil, appObject) end
        end)
    remapPreviousTabHotkey = bindSpecSuspend(spec, menuItemPath[#menuItemPath],
                                             fn, nil, fn)
    remapPreviousTabHotkey.condition = cond
    remapPreviousTabHotkey.kind = HK.IN_APP
  end
end

local frontmostApplication = hs.application.frontmostApplication()
remapPreviousTab(frontmostApplication:bundleID())

function registerOpenRecent(bundleID)
  if (appHotKeyCallbacks[bundleID] ~= nil
      and appHotKeyCallbacks[bundleID]["openRecent"] ~= nil)
      or keybindingConfigs.hotkeys.appCommon == nil
      or keybindingConfigs.hotkeys.appCommon["openRecent"] == nil
      or hs.fnutils.contains(keybindingConfigs.hotkeys.appCommon["openRecent"].excluded or {},
                              bundleID) then
    return
  end
  local spec = keybindingConfigs.hotkeys.appCommon["openRecent"]
  if openRecentHotkey then
    openRecentHotkey:delete()
    openRecentHotkey = nil
  end
  local appObject = hs.application.frontmostApplication()
  local menuItem, menuItemPath = findMenuItem(appObject, { "File",  "Open Recent" })
  if menuItem ~= nil then
    local cond = function(appObject)
      local menuItemCond = appObject:findMenuItem(menuItemPath)
      return menuItemCond ~= nil and menuItemCond.enabled
    end
    local fn = inAppHotKeysWrapper(appObject, spec.mods, spec.key,
        function()
          if cond(appObject) then
            showMenuItemWrapper(function()
              appObject:selectMenuItem({menuItemPath[1]})
              appObject:selectMenuItem(menuItemPath)
            end)()
          else hs.eventtap.keyStroke(spec.mods, spec.key, nil, appObject) end
        end)
    openRecentHotkey = bindSpecSuspend(spec, menuItemPath[2], fn)
    openRecentHotkey.condition = cond
    openRecentHotkey.kind = HK.IN_APP
  end
end
registerOpenRecent(frontmostApplication:bundleID())

-- bind `alt+?` hotkeys to menu bar 1 functions
-- to be registered in application callback
altMenuItemHotkeys = {}

local function bindAltMenu(appObject, mods, key, message, fn)
  fn = showMenuItemWrapper(fn)
  fn = inAppHotKeysWrapper(appObject, mods, key, fn)
  local hotkey = bindSuspend(mods, key, message, fn)
  hotkey.kind = HK.APP_MENU
  return hotkey
end

local function searchHotkeyByNth(appObject, itemTitles, alreadySetHotkeys, index)
  local notSetItems = {}
  for i, title in pairs(itemTitles) do
    if index == nil then
      index = string.find(title[2], " ")
      if index ~= nil then
        index = index + 1
      end
    end
    local hotkey
    if index ~= nil then
      hotkey = string.upper(string.sub(title[2], index, index))
    end

    if hotkey ~= nil and alreadySetHotkeys[hotkey] == nil then
        alreadySetHotkeys[hotkey] = title[1]
    else
      table.insert(notSetItems, title)
    end
  end
  return notSetItems, alreadySetHotkeys
end

function delocalizeMenuItems(itemTitles, bundleID, localeFile)
  local defaultTitleMap, titleMap
  if menuBarTitleLocalizationMap ~= nil then
    defaultTitleMap = menuBarTitleLocalizationMap.common
    titleMap = menuBarTitleLocalizationMap[bundleID]
  end
  local result = {}
  for _, title in ipairs(itemTitles) do
    -- remove titles starting with non-ascii characters
    local splits = hs.fnutils.split(title, ' ')
    if string.byte(title, 1) <= 127
        and (string.len(title) < 2 or string.byte(title, 2) <= 127)
        and (string.len(title) < 3 or string.byte(title, 3) <= 127)
        and (#splits == 1 or string.byte(splits[2], 1) <= 127) then
      table.insert(result, { title, title })
    else
      if titleMap ~= nil then
        if titleMap[title] ~= nil then
          table.insert(result, { title, titleMap[title] })
          goto L_CONTINUE
        end
      end
      if defaultTitleMap ~= nil then
        if defaultTitleMap[title] ~= nil then
          table.insert(result, { title, defaultTitleMap[title] })
          goto L_CONTINUE
        end
      end
      local newTitle = delocalizedMenuItemString(title, bundleID, localeFile)
      if newTitle ~= nil then
        table.insert(result, { title, newTitle })
      end
      ::L_CONTINUE::
    end
  end
  return result
end

function altMenuItem(appObject)
  -- check whether called by window filter (possibly with delay)
  if appObject:bundleID() ~= hs.application.frontmostApplication():bundleID() then
    return
  end

  -- delete previous hotkeys
  for _, hotkeyObject in ipairs(altMenuItemHotkeys) do
    hotkeyObject:delete()
  end
  altMenuItemHotkeys = {}

  local enableIndex, enableLetter
  if keybindingConfigs.hotkeys.menuItems ~= nil then
    if keybindingConfigs.hotkeys.menuItems.enableIndex ~= nil then
      enableIndex = keybindingConfigs.hotkeys.menuItems.enableIndex
    end
    if keybindingConfigs.hotkeys.menuItems.enableLetter ~= nil then
      enableLetter = keybindingConfigs.hotkeys.menuItems.enableLetter
    end
  else
    enableIndex = false
    enableLetter = true
  end
  if keybindingConfigs.hotkeys.menuItems.excludedForLetter ~= nil
      and hs.fnutils.contains(keybindingConfigs.hotkeys.menuItems.excludedForLetter,
        appObject:bundleID()) then
    enableLetter = false
  end
  if enableIndex == false and enableLetter == false then return end

  if appObject:bundleID() == "com.microsoft.VSCode"
      or appObject:bundleID() == "com.google.Chrome" then
    hs.timer.usleep(0.5 * 100000)
  end
  local menuItemTitles
  if appObject:bundleID() == "com.mathworks.matlab" and appObject:focusedWindow() ~= nil then
    local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
    if #winUIObj:childrenWithRole("AXMenuBar") > 0 then
      local menuObj = winUIObj:childrenWithRole("AXMenuBar")[1]:childrenWithRole("AXMenu")
      menuItemTitles = hs.fnutils.map(menuObj, function(item)
        return item:attributeValue("AXTitle"):match("(.-)%s")
      end)
      table.insert(menuItemTitles, 1, "MATLAB")
    end
  end
  if menuItemTitles == nil then
    local menuItems = getMenuItems(appObject)
    if menuItems == nil then return end
    menuItemTitles = hs.fnutils.map(menuItems, function(item)
      return item.AXTitle
    end)
    menuItemTitles = hs.fnutils.filter(menuItemTitles, function(item)
      return item ~= nil and item ~= ""
    end)
  end
  if menuItemTitles == nil or #menuItemTitles == 0 then return end

  -- by initial or otherwise second letter in title
  local alreadySetHotkeys = {}
  if enableLetter == true then
    local itemTitles = {}
    for i=2,#menuItemTitles do
      local title, letter = menuItemTitles[i]:match("(.-)%s*%((.-)%)")
      if letter then
        alreadySetHotkeys[letter] = {menuItemTitles[i], title}
      else
        table.insert(itemTitles, menuItemTitles[i])
      end
    end

    -- process localized titles
    itemTitles = delocalizeMenuItems(itemTitles, appObject:bundleID())

    local notSetItems = {}
    for i, title in ipairs(itemTitles) do
      if hs.fnutils.contains({ 'File', 'Edit', 'View', 'Window', 'Help' }, title[2]) then
        local hotkey = string.sub(title[2], 1, 1)
        alreadySetHotkeys[hotkey] = title[1]
      else
        table.insert(notSetItems, title)
      end
    end
    notSetItems, alreadySetHotkeys = searchHotkeyByNth(appObject, notSetItems, alreadySetHotkeys, 1)
    -- if there are still items not set, set them by first letter of second word
    notSetItems, alreadySetHotkeys = searchHotkeyByNth(appObject, notSetItems, alreadySetHotkeys, nil)
    -- if there are still items not set, set them by second letter
    notSetItems, alreadySetHotkeys = searchHotkeyByNth(appObject, notSetItems, alreadySetHotkeys, 2)
    -- if there are still items not set, set them by third letter
    searchHotkeyByNth(appObject, notSetItems, alreadySetHotkeys, 3)
    local invMap = {}
    for key, title in pairs(alreadySetHotkeys) do
      local menuItem = type(title) == 'table' and title[1] or title
      local msg = type(title) == 'table' and title[2] or title
      invMap[menuItem] = {key, msg}
    end
    for i=2,#menuItemTitles do
      local spec = invMap[menuItemTitles[i]]
      if spec ~= nil then
        local fn
        if appObject:bundleID() == "com.mathworks.matlab" and #menuItemTitles > 3 then
          fn = function()
            local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
            local menuObj = winUIObj:childrenWithRole("AXMenuBar")[1]:childrenWithRole("AXMenu")
            local targetMenuObj = hs.fnutils.find(menuObj, function(item)
              return item:attributeValue("AXTitle"):match("(.-)%s") == spec[2]
            end)
            targetMenuObj:performAction("AXPick")
          end
        else
          fn = function() appObject:selectMenuItem({ menuItemTitles[i] }) end
        end
        local hotkeyObject = bindAltMenu(appObject, "⌥", spec[1], spec[2], fn)
        table.insert(altMenuItemHotkeys, hotkeyObject)
      end
    end
  end

  -- by index
  if enableIndex == true then
    local itemTitles = hs.fnutils.copy(menuItemTitles)

    local hotkeyObject = bindAltMenu(appObject, "⌥", "`", itemTitles[1] .. " Menu",
        function() appObject:selectMenuItem({itemTitles[1]}) end)
    hotkeyObject.subkind = 0
    table.insert(altMenuItemHotkeys, hotkeyObject)
    local maxMenuItemHotkey = #itemTitles > 11 and 10 or (#itemTitles - 1)
    for i=1,maxMenuItemHotkey do
      hotkeyObject = bindAltMenu(appObject, "⌥", tostring(i % 10), itemTitles[i+1] .. " Menu",
          function() appObject:selectMenuItem({itemTitles[i+1]}) end)
      table.insert(altMenuItemHotkeys, hotkeyObject)
    end
  end
end
altMenuItem(frontmostApplication)

local appsWatchMenuItems
if applicationConfigs ~= nil and applicationConfigs.menuItemsMayChange ~= nil then
  appsWatchMenuItems = applicationConfigs.menuItemsMayChange.basic or {}
end
appsMenuItemsWatchers = {}

local getMenuItemTitlesString = function(appObject)
  local menuItems = getMenuItems(appObject)
  if menuItems == nil or #menuItems == 0 then return "" end
  local menuItemTitles = {}
  for _, item in ipairs(menuItems) do
    table.insert(menuItemTitles, item.AXTitle)
  end
  return table.concat(menuItemTitles, "|")
end

local function watchMenuItems(appObject)
  local menuItemTitlesString = getMenuItemTitlesString(appObject)
  if appsMenuItemsWatchers[appObject:bundleID()] == nil then
    local watcher = hs.timer.new(1, function()
      local newMenuItemTitlesString = getMenuItemTitlesString(appObject)
      if newMenuItemTitlesString ~= appsMenuItemsWatchers[appObject:bundleID()][2] then
        appsMenuItemsWatchers[appObject:bundleID()][2] = newMenuItemTitlesString
        altMenuItem(appObject)
      end
    end)
    appsMenuItemsWatchers[appObject:bundleID()] = { watcher, menuItemTitlesString }
  else
    appsMenuItemsWatchers[appObject:bundleID()][2] = menuItemTitlesString
  end
  appsMenuItemsWatchers[appObject:bundleID()][1]:start()
end
local frontAppBid = hs.fnutils.find(appsWatchMenuItems, function(bid)
  return bid == frontmostApplication:bundleID()
end)
if frontAppBid ~= nil then
  watchMenuItems(frontmostApplication)
end


local appsMayChangeMenu
if applicationConfigs ~= nil and applicationConfigs.menuItemsMayChange ~= nil then
  appsMayChangeMenu = applicationConfigs.menuItemsMayChange.window
end
local curAppMenuItemWatcher
if appsMayChangeMenu ~= nil then
  local windowFilterAppsMayChangeMenu = hs.window.filter.new():subscribe(
    {hs.window.filter.windowCreated, hs.window.filter.windowDestroyed,
    hs.window.filter.windowFocused, hs.window.filter.windowUnfocused},  -- may fail
  function(winObj)
    if winObj == nil or winObj:application() == nil then return end
    local bundleID = winObj:application():bundleID()
    if hs.fnutils.contains(appsMayChangeMenu, bundleID) then
      local appObject = winObj:application()
      altMenuItem(appObject)
      local menuItemStr = getMenuItemTitlesString(appObject)
      curAppMenuItemWatcher = hs.timer.doAfter(1, function()
        if hs.application.frontmostApplication():bundleID() ~= appObject:bundleID() then
          return
        end
        local newMenuItemTitlesString = getMenuItemTitlesString(appObject)
        if newMenuItemTitlesString ~= menuItemStr then
          altMenuItem(winObj:application())
        end
      end)
    end
  end)
end

local function processAppWithNoWindows(appObject, quit)
  if #appObject:visibleWindows() == 0 then
    if quit == true then
      local wFilter = hs.window.filter.new(appObject:name())
      if #wFilter:getWindows() == 0 then
        appObject:kill()
      end
    else
      appObject:hide()
    end
  elseif appObject:bundleID() == "com.apple.finder" then
    local wFilter = hs.window.filter.new(appObject:name())
    local windows = wFilter:getWindows()
    local standard = hs.fnutils.find(windows, function(win) return win:isStandard() end)
    if standard == nil then
      appObject:hide()
    end
  end
end

local appsAutoHideWithNoWindows = applicationConfigs.autoHideWithNoWindow
local appsAutoQuitWithNoWindows = applicationConfigs.autoQuitWithNoWindow
local windowFilterAutoHideQuit = hs.window.filter.new():subscribe(hs.window.filter.windowDestroyed,
function(winObj)
  if winObj == nil or winObj:application() == nil then return end
  local bundleID = winObj:application():bundleID()
  if hs.fnutils.contains(appsAutoHideWithNoWindows, bundleID) then
    processAppWithNoWindows(winObj:application(), false)
  end
  if hs.fnutils.contains(appsAutoQuitWithNoWindows, bundleID) then
    processAppWithNoWindows(winObj:application(), true)
  end
end)

barrierWindowFilter = hs.window.filter.new(false):allowApp("Barrier"):subscribe(
  hs.window.filter.windowCreated, function(winObj) winObj:focus() end
)

function parseVerificationCodeFromFirstMessage()
  local ok, content = hs.osascript.applescript([[
    tell application "System Events"
      tell window 1 of (first application process ¬
          whose bundle identifier is "com.apple.notificationcenterui")
        return value of static text 2 of group 1 of UI element 1 of scroll area 1
      end tell
    end tell
  ]])
  if ok then
    if string.find(content, '验证码')
        or string.find(string.lower(content), 'verification')
        or (string.find(content, 'Microsoft') and string.find(content, '安全代码'))
        or (string.find(content, '【Facebook】') and string.find(content, '输入')) then
      return string.match(content, '%d%d%d%d+')
    end
  end
end

newMessageWindowFilter = hs.window.filter.new(false):
    allowApp(findApplication("com.apple.notificationcenterui"):name()):
    subscribe(hs.window.filter.windowCreated,
        function()
          local code = parseVerificationCodeFromFirstMessage()
          if code then
            hs.alert(string.format('Copy verification code "%s" to pasteboard', code))
            hs.pasteboard.writeObjects(code)
          end
        end)

remoteDesktopsMappingModifiers = keybindingConfigs.remap or {}
local modifiersShort = {
  control = "ctrl",
  option = "alt",
  command = "cmd",
  shift = "shift",
  fn = "fn"
}
for bid, rules in pairs(remoteDesktopsMappingModifiers) do
  for _, r in ipairs(rules) do
    local newMap = {}
    for k, v in pairs(r.map) do
      k = modifiersShort[k]
      if k ~= nil then newMap[k] = modifiersShort[v] end
    end
    r.map = newMap
  end
end
local justModifiedRemoteDesktopModifiers = false
remoteDesktopModifierTapper = hs.eventtap.new({hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp},
function(ev)
  local evFlags =	ev:getFlags()
  local appObject = hs.application.frontmostApplication()
  local winObj = appObject:focusedWindow()
  local rules = remoteDesktopsMappingModifiers[appObject:bundleID()]
  if rules == nil then return false end
  for _, r in ipairs(rules) do
    local valid = false
    if r.condition == nil then
      valid = true
    else
      if appObject:focusedWindow() == nil then
        valid = r.condition.noWindow == true
      elseif appObject:focusedWindow():title() == "" then
        valid = r.condition.noTitle == true
      elseif r.condition.windowFilter ~= nil then
        local wFilter = hs.window.filter.new(false):setAppFilter(appObject:name(), r.condition.windowFilter)
        if wFilter:isWindowAllowed(appObject:focusedWindow()) then
          valid = true
        end
      end
    end
    if valid then
      if not justModifiedRemoteDesktopModifiers then
        justModifiedRemoteDesktopModifiers = true
        local newEvFlags = {}
        for k, v in pairs(evFlags) do
          if r.map[k] == nil then
            newEvFlags[k] = true
          else
            newEvFlags[r.map[k]] = true
          end
        end
        ev:setFlags(newEvFlags)
        ev:post()
        return true
      else
        justModifiedRemoteDesktopModifiers = false
      end
      break
    end
  end
  return false
end)

if remoteDesktopsMappingModifiers[hs.application.frontmostApplication():bundleID()] then
  remoteDesktopModifierTapper:start()
end


-- # callbacks

-- application callbacks

local appsInputSourceMap = applicationConfigs.inputSource
function selectInputSourceInApp(bid)
  local inputSource = appsInputSourceMap[bid]
  if inputSource ~= nil then
    if type(inputSource) == 'string' then
      hs.keycodes.currentSourceID(inputSource)
    else
      for _, source in ipairs(inputSource) do
        if hs.keycodes.currentSourceID(source) then
          break
        end
      end
    end
  end
end

local appsLaunchSlow = {
  {
    bundleID = "com.jetbrains.CLion",
    criterion = function(appObject)
      return appObject:getMenuItems() ~= nil and #appObject:getMenuItems() > 10
    end
  },
  {
    bundleID = "com.jetbrains.CLion-EAP",
    criterion = function(appObject)
      return appObject:getMenuItems() ~= nil and #appObject:getMenuItems() > 10
    end
  },

  {
    bundleID = "com.jetbrains.intellij",
    criterion = function(appObject)
      return appObject:getMenuItems() ~= nil and #appObject:getMenuItems() > 10
    end
  },

  {
    bundleID = "com.jetbrains.pycharm",
    criterion = function(appObject)
      return appObject:getMenuItems() ~= nil and #appObject:getMenuItems() > 10
    end
  }
}

local tryTimes = {}
local tryInterval = 1
local maxTryTimes = 15

function altMenuItemAfterLaunch(appObject)
  local app = hs.fnutils.find(appsLaunchSlow, function(app)
    return appObject:bundleID() == app.bundleID
  end)
  if app == nil then
    app = hs.fnutils.find(appsLaunchSlow, function(app)
      return appObject:path() == app.appPath
    end)
  end
  if app ~= nil then
    local bid = appObject:bundleID()
    -- app was killed
    if findApplication(bid) == nil then
      tryTimes[bid] = nil
      return
    end

    -- start counting
    if tryTimes[bid] == nil then
      tryTimes[bid] = 0
    end

    if app.criterion(appObject) then
      tryTimes[bid] = nil
      altMenuItem(appObject)
    else
      -- try until fully launched
      tryTimes[bid] = tryTimes[bid] + 1
      if tryTimes[bid] > maxTryTimes then
        tryTimes[bid] = nil
      else
        hs.timer.doAfter(tryInterval, function()
          altMenuItemAfterLaunch(appObject)
        end)
      end
    end
  else
    altMenuItem(appObject)
  end
end

local appLocales = {}
function app_applicationCallback(appName, eventType, appObject)
  local bundleID = appObject:bundleID()
  if eventType == hs.application.watcher.launched then
    if bundleID == "com.apple.finder" then
      selectMenuItem(appObject, { "File", "New Finder Window" },
                     { localeFile = "MenuBar" })
    end
    altMenuItemAfterLaunch(appObject)
    if appHotKeyCallbacks[bundleID] ~= nil then
      registerWinFiltersForDaemonApp(appObject, appHotKeyCallbacks[bundleID])
    end
  elseif eventType == hs.application.watcher.activated then
    windowCreatedSince = {}
    if bundleID == "cn.better365.iShotProHelper" then
      unregisterInWinHotKeys("cn.better365.iShotPro")
      return
    end
    selectInputSourceInApp(bundleID)
    hs.timer.doAfter(0, function()
      local locales = applicationLocales(bundleID)
      local appLocale = locales[1]
      if appLocales[bundleID] ~= nil and appLocales[bundleID] ~= appLocale then
        unregisterRunningAppHotKeys(bundleID, true)
        unregisterInAppHotKeys(bundleID, eventType, true)
        unregisterInWinHotKeys(bundleID, true)
      end
      appLocales[bundleID] = appLocale
      registerRunningAppHotKeys(bundleID, appObject)
      registerInAppHotKeys(appName, eventType, appObject)
      registerInWinHotKeys(appObject)
      hs.timer.doAfter(0, function()
        altMenuItem(appObject)
        if curAppMenuItemWatcher ~= nil then
          curAppMenuItemWatcher:stop()
          curAppMenuItemWatcher = nil
        end
        local frontAppBid = hs.fnutils.find(appsWatchMenuItems, function(bid)
          return bid == bundleID
        end)
        if frontAppBid ~= nil then
          watchMenuItems(appObject)
        end
        hs.timer.doAfter(0, function()
          remapPreviousTab(bundleID)
          registerOpenRecent(bundleID)
        end)
      end)
    end)
    if remoteDesktopsMappingModifiers[bundleID] then
      if not remoteDesktopModifierTapper:isEnabled() then
        remoteDesktopModifierTapper:start()
      end
    end
  elseif eventType == hs.application.watcher.deactivated then
    if appName ~= nil then
      unregisterInAppHotKeys(bundleID, eventType)
      unregisterInWinHotKeys(bundleID)
      if appsMenuItemsWatchers[bundleID] ~= nil then
        appsMenuItemsWatchers[bundleID][1]:stop()
      end
    else
      for bid, _ in pairs(runningAppHotKeys) do
        if findApplication(bid) == nil then
          unregisterRunningAppHotKeys(bid)
        end
      end
      for bid, _ in pairs(inAppHotKeys) do
        if findApplication(bid) == nil then
          unregisterInAppHotKeys(bid, eventType, true)
        end
      end
      for bid, _ in pairs(inWinHotKeys) do
        if findApplication(bid) == nil then
          unregisterInWinHotKeys(bid, true)
        end
      end
      for bid, _ in pairs(appsMenuItemsWatchers) do
        if findApplication(bid) == nil then
          appsMenuItemsWatchers[bid][1]:stop()
          appsMenuItemsWatchers[bid] = nil
        end
      end
    end
    if remoteDesktopsMappingModifiers[hs.application.frontmostApplication():bundleID()] == nil then
      if remoteDesktopModifierTapper:isEnabled() then
        remoteDesktopModifierTapper:stop()
      end
    end
  end
  if hkHideKeybindings ~= nil and HSKeybindings ~= nil then
    local validOnly = HSKeybindings.validOnly
    local showHS = HSKeybindings.showHS
    local showKara = HSKeybindings.showKara
    local showApp = HSKeybindings.showApp
    HSKeybindings:reset()
    HSKeybindings:update(validOnly, showHS, showKara, showApp)
  end
end

function app_applicationInstalledCallback(files, flagTables)
  registerAppHotkeys()
end

-- wifi callbacks

-- launch `Mountain Duck` automatically when connected to laboratory wifi
local labproxyConfig
if hs.fs.attributes("config/private-proxy.json") ~= nil then
  labproxyConfig = hs.json.read("config/private-proxy.json")
end
if labproxyConfig ~= nil then
  labProxyConfig = labproxyConfig["Lab Proxy"]
end
local lastWifi = hs.wifi.currentNetwork()

function app_wifiChangedCallback()
  if labProxyConfig == nil or labProxyConfig.condition == nil then return end

  local curWifi = hs.wifi.currentNetwork()
  if curWifi == nil then
    lastWifi = nil
    return
  end

  if lastWifi == nil then
    hs.timer.waitUntil(
        function()
          getCurrentNetworkService()
          return curNetworkService ~= nil
        end,
        function()
          local _, status_ok = hs.execute(labProxyConfig.condition.shell_command)
          if status_ok then
            -- hs.application.launchOrFocusByBundleID("io.mountainduck")
          else
            -- quitApplication("io.mountainduck")
          end
        end)
  end

  lastWifi = curWifi
end

-- monitor callbacks

-- launch applications automatically when connected to an external monitor
local builtinMonitor = "Built-in Retina Display"

function app_monitorChangedCallback()
  local screens = hs.screen.allScreens()

  -- only for built-in monitor
  local builtinMonitorEnable = hs.fnutils.some(screens, function(screen)
    return screen:name() == builtinMonitor
  end)
  if builtinMonitorEnable then
    -- hs.application.launchOrFocusByBundleID("pl.maketheweb.TopNotch")
  else
    quitApplication("pl.maketheweb.TopNotch")
  end

  -- for external monitors
  if (builtinMonitorEnable and #screens > 1)
    or (not builtinMonitorEnable and #screens > 0) then
    if findApplication("me.guillaumeb.MonitorControl") == nil then
      hs.application.launchOrFocusByBundleID("me.guillaumeb.MonitorControl")
      hs.timer.waitUntil(
        function()
          return findApplication("me.guillaumeb.MonitorControl") ~= nil
        end,
        function()
          findApplication("me.guillaumeb.MonitorControl"):hide()
        end)
    end
  elseif builtinMonitorEnable and #screens == 1 then
    quitApplication("me.guillaumeb.MonitorControl")
  end
end

-- usb callbacks

-- launch `MacDroid` automatically when connected to android phone
local phones = {{"ANA-AN00", "HUAWEI"}}
local attached_android_count = 0

function app_usbChangedCallback(device)
  if device.eventType == "added" then
    attached_android_count = attached_android_count + 1
    for _, phone in ipairs(phones) do
      if device.productName == phone[1] and device.vendorName == phone[2] then
        hs.application.launchOrFocus('MacDroid')
        break
      end
    end
  elseif device.eventType == "removed" then
    attached_android_count = attached_android_count - 1
    if attached_android_count == 0 then
      quitApplication('MacDroid Extension')
      quitApplication('MacDroid')
    end
  end
end
