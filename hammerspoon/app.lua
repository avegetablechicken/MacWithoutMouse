require "utils"

local applicationConfigs
if hs.fs.attributes("config/application.json") ~= nil then
  applicationConfigs = hs.json.read("config/application.json")
end

hs.application.enableSpotlightForNameSearches(true)


-- # appkeys

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
  elseif type(hint) == "string" then
    appObject = findApplication(hint)
  else
    appObject = hint
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

local function getParallelsVMPath(osname)
  local PVMDir = os.getenv("HOME") .. "/Parallels"
  local path = string.format(PVMDir .. "/%s.pvm/%s.app", osname, osname)
  if hs.fs.attributes(path) ~= nil then return path end

  for filename in hs.fs.dir(PVMDir) do
    if filename:sub(-4) == '.pvm' and filename:sub(1, osname:len()) == osname then
      local stem = filename:sub(1, -5)
      path = string.format(PVMDir .. "/%s.pvm/%s.app", stem, stem)
      if hs.fs.attributes(path) ~= nil then return path end
    end
  end
end

local appHotkeys = {}

local function registerAppHotkeys()
  for _, hotkey in ipairs(appHotkeys) do
    hotkey:delete()
  end
  appHotkeys = {}
  HyperModal.hyperMode.keys = hs.fnutils.filter(HyperModal.hyperMode.keys,
      function(hotkey) return hotkey.idx ~= nil end)

  for name, config in pairs(KeybindingConfigs.hotkeys.appkeys or {}) do
    local appPath
    if config.bundleID then
      if type(config.bundleID) == "string" then
        appPath = hs.application.pathForBundleID(config.bundleID)
        if appPath == "" then appPath = nil end
      elseif type(config.bundleID) == "table" then
        for _, bundleID in ipairs(config.bundleID) do
          appPath = hs.application.pathForBundleID(bundleID)
          if appPath == "" then appPath = nil end
          if appPath ~= nil then break end
        end
      end
    end
    if appPath == nil and config.vm ~= nil then
      if config.vm == "com.parallels.desktop.console" then
        appPath = getParallelsVMPath(name)
      else
        hs.alert("Unsupported Virtual Machine : " .. config.vm)
      end
    end
    if appPath == nil and config.appPath ~= nil then
      if type(config.appPath) == "string" then
        appPath = config.appPath
      else
        for _, path in ipairs(config.appPath) do
          if hs.fs.attributes(path) ~= nil then
            appPath = path
            break
          end
        end
      end
    end
    if appPath ~= nil then
      local appName, status_ok = hs.execute(string.format("mdls -name kMDItemDisplayName -raw '%s'", appPath))
      if status_ok then
        if appName:sub(-4) == '.app' then
          appName = appName:sub(1, -5)
        else
          appName = hs.application.infoForBundlePath(appPath).CFBundleName
        end
        local hotkey = bindHotkeySpec(config, "Toggle " .. appName,
            hs.fnutils.partial(config.fn or focusOrHide, config.bundleID or (config.appPath or appName)))
        hotkey.kind = HK.APPKEY
        if config.bundleID then
          hotkey.bundleID = config.bundleID
        elseif config.appPath then
          hotkey.appPath = config.appPath
        elseif config.vm then
          hotkey.appPath = appPath
        end
        table.insert(appHotkeys, hotkey)
      end
    end
  end
end

registerAppHotkeys()


-- # hotkeys in specific application
local appHotKeyCallbacks

local function applicationVersion(bundleID)
  local version = hs.execute(string.format('mdls -r -name kMDItemVersion "%s"',
    hs.application.pathForBundleID(bundleID)))
  version = hs.fnutils.split(version, "%.")
  local major, minor, patch
  major = tonumber(version[1]:match("%d+"))
  minor = #version > 1 and tonumber(version[2]:match("%d+")) or 0
  patch = #version > 2 and tonumber(version[3]:match("%d+")) or 0
  return major, minor, patch
end

local function versionCompare(versionStr, comp)
  return function(appObject)
    local appMajor, appMinor, appPatch = applicationVersion(appObject:bundleID())
    local version = hs.fnutils.split(versionStr, "%.")
    local major, minor, patch
    major = tonumber(version[1]:match("%d+"))
    minor = #version > 1 and tonumber(version[2]:match("%d+")) or 0
    patch = #version > 2 and tonumber(version[3]:match("%d+")) or 0
    if comp == "==" then
      return appMajor == major and appMinor == minor and appPatch == patch
    elseif comp == "~=" then
      return appMajor ~= major or appMinor ~= minor or appPatch ~= patch
    elseif comp == "<" or comp == "<=" then
      if appMajor < major then return true end
      if appMajor == major and appMinor < minor then return true end
      if appMajor == major and appMinor == minor and appPatch < patch then return true end
      if comp == "<=" and appMajor == major and appMinor == minor and appPatch == patch then return true end
      return false
    elseif comp == ">" or comp == ">=" then
      if appMajor > major then return true end
      if appMajor == major and appMinor > minor then return true end
      if appMajor == major and appMinor == minor and appPatch > patch then return true end
      if comp == ">=" and appMajor == major and appMinor == minor and appPatch == patch then return true end
      return false
    end
  end
end

local function versionEqual(version)
  return versionCompare(version, "==")
end

local function versionNotEqual(version)
  return versionCompare(version, "~=")
end

local function versionLessThan(version)
  return versionCompare(version, "<")
end

local function versionGreaterThan(version)
  return versionCompare(version, ">")
end

local function versionGreaterEqual(version)
  return versionCompare(version, ">=")
end

local function versionLessEqual(version)
  return versionCompare(version, "<=")
end

-- ## function utilities for hotkey configs of specific application

-- ### Finder
local function getFinderSidebarItemTitle(idx)
  return function(appObject)
    local appUIObj = hs.axuielement.applicationElement(appObject)
    local outlineUIObj = getAXChildren(appUIObj, "AXWindow", activatedWindowIndex(),
        "AXSplitGroup", 1, "AXScrollArea", 1, "AXOutline", 1)
    if outlineUIObj == nil then return end
    local header
    local cnt = 0
    for _, rowUIObj in ipairs(outlineUIObj:childrenWithRole("AXRow")) do
      if rowUIObj.AXChildren == nil then hs.timer.usleep(0.3 * 1000000) end
      if rowUIObj.AXChildren[1]:childrenWithRole("AXStaticText")[1].AXIdentifier ~= nil then
        header = rowUIObj.AXChildren[1]:childrenWithRole("AXStaticText")[1].AXValue
      else
        cnt = cnt + 1
        if cnt == idx then
          local itemTitle = rowUIObj.AXChildren[1]:childrenWithRole("AXStaticText")[1].AXValue
          return header .. ' > ' .. itemTitle
        end
      end
    end
  end
end

local function getFinderSidebarItem(idx)
  return function(appObject)
    if appObject:focusedWindow() == nil
        or appObject:focusedWindow():role() == 'AXSheet' then return false end
    local outlineUIObj = getAXChildren(hs.axuielement.windowElement(appObject:focusedWindow()),
        "AXSplitGroup", 1, "AXScrollArea", 1, "AXOutline", 1)
    if outlineUIObj == nil then return false end
    local cnt = 0
    for _, rowUIObj in ipairs(outlineUIObj:childrenWithRole("AXRow")) do
      if rowUIObj.AXChildren[1]:childrenWithRole("AXStaticText")[1].AXIdentifier == nil then
        cnt = cnt + 1
      end
      if cnt == idx then
        return true, rowUIObj.AXChildren[1]
      end
    end
    return false
  end
end

local function openFinderSidebarItem(cellUIObj, appObject)
  local go = localizedString("Go", appObject:bundleID())
  local itemTitle = cellUIObj:childrenWithRole("AXStaticText")[1].AXValue
  if appObject:findMenuItem({ go, itemTitle }) ~= nil then
    appObject:selectMenuItem({ go, itemTitle })
  else
    local flags = hs.eventtap.checkKeyboardModifiers()
    if not (flags['cmd'] or flags['alt'] or flags['ctrl']) then
      cellUIObj:performAction("AXOpen")
    else
      local tapper
      tapper = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
        tapper:stop()
        hs.timer.doAfter(0.01, function()
          local newFlags = hs.eventtap.checkKeyboardModifiers()
          if newFlags['cmd'] or newFlags['alt'] or newFlags['ctrl'] then
            event:setFlags({}):post()
            hs.timer.doAfter(0.01, function()
              cellUIObj:performAction("AXOpen")
            end)
          else
            cellUIObj:performAction("AXOpen")
          end
        end)
        return false
      end):start()
      local event = hs.eventtap.event.newEvent()
      event:setType(hs.eventtap.event.types.flagsChanged)
      event:setFlags({}):post()
    end
  end
end

-- ### Messages
local function deleteSelectedMessage(appObject, menuItem, force)
  if menuItem == nil then
    local appUIObj = hs.axuielement.applicationElement(appObject)
    local button = getAXChildren(appUIObj, "AXWindow", activatedWindowIndex(),
        "AXGroup", 1, "AXGroup", 1, "AXGroup", 2, "AXGroup", 1, "AXButton", 2)
    if button ~= nil then
      button:performAction("AXPress")
      if force ~= nil then
        hs.timer.usleep(0.1 * 1000000)
        hs.eventtap.keyStroke("", "Tab", nil, appObject)
        hs.timer.usleep(0.1 * 1000000)
        hs.eventtap.keyStroke("", "Space", nil, appObject)
      end
      return
    end
  end
  if menuItem == nil then
    local _, menuItemPath = findMenuItem(appObject, {
      getOSVersion() < OS.Ventura and "File" or "Conversation",
      "Delete Conversation…"
    })
    menuItem = menuItemPath
  end
  appObject:selectMenuItem(menuItem)
  if force ~= nil then
    hs.timer.usleep(0.1 * 1000000)
    hs.eventtap.keyStroke("", "Return", nil, appObject)
  end
end

local function deleteAllMessages(appObject)
  local appUIObj = hs.axuielement.applicationElement(appObject)
  appUIObj:elementSearch(
    function(msg, results, count)
      if count ~= 1 then return end

      local messageItems = results[1].AXChildren
      if messageItems == nil or #messageItems == 0
          or (#messageItems == 1 and (messageItems[1].AXDescription == nil
            or messageItems[1].AXDescription:sub(4) ==
               localizedString('New Message', appObject:bundleID()))) then
        return
      end

      for _, messageItem in ipairs(messageItems) do
        messageItem:performAction("AXPress")
        hs.timer.usleep(0.1 * 1000000)
        deleteSelectedMessage(appObject, nil, true)
        hs.timer.usleep(1 * 1000000)
      end
      deleteAllMessages(appObject)
    end,
    function(element)
      return element.AXIdentifier == "ConversationList"
    end
  )
end

-- ### FaceTime
local function deleteMousePositionCall(winObj)
  local winUIObj = hs.axuielement.windowElement(winObj)
  local collection = getAXChildren(winUIObj, "AXGroup", 1, "AXGroup", 1, "AXGroup", 1, "AXGroup", 2)
  if collection ~= nil and collection.AXDescription ==
      localizedString("Recent Calls", winObj:application():bundleID()) then
    local section = collection:childrenWithRole("AXButton")[1]
    if section ~= nil then
      if not rightClick(hs.mouse.absolutePosition(), winObj:application():name()) then return end
      local popup = getAXChildren(winUIObj, "AXGroup", 1, "AXMenu", 1)
      local maxTime, time = 0.5, 0
      while popup == nil and time < maxTime do
        hs.timer.usleep(0.01 * 1000000)
        time = time + 0.01
        popup = getAXChildren(winUIObj, "AXGroup", 1, "AXMenu", 1)
      end
      if popup == nil then
        if not rightClick(hs.mouse.absolutePosition(), winObj:application():name()) then return end
        popup = getAXChildren(winUIObj, "AXGroup", 1, "AXMenu", 1)
        time = 0
        while popup == nil and time < maxTime do
          hs.timer.usleep(0.01 * 1000000)
          time = time + 0.01
          popup = getAXChildren(winUIObj, "AXGroup", 1, "AXMenu", 1)
        end
        if popup == nil then return end
      end
      local menuItem = popup:childrenWithRole("AXMenuItem")[5]
      if menuItem ~= nil then
        menuItem:performAction("AXPress")
      end
    end
    return
  end
  winUIObj:elementSearch(
    function(msg, results, count)
      if count == 0 then return end

      local sectionList = results[1].AXChildren[1]:childrenWithRole("AXGroup")
      if #sectionList == 0 then return end

      local section = sectionList[1]
      if not rightClick(hs.mouse.absolutePosition(), winObj:application():name()) then return end
      local popups = section:childrenWithRole("AXMenu")
      local maxTime, time = 0.5, 0
      while #popups == 0 and time < maxTime do
        hs.timer.usleep(0.01 * 1000000)
        time = time + 0.01
        popups = section:childrenWithRole("AXMenu")
      end
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
    end,
    { count = 1 }
  )
end

local function deleteAllCalls(winObj)
  local winUIObj = hs.axuielement.windowElement(winObj)
  local collection = getAXChildren(winUIObj, "AXGroup", 1, "AXGroup", 1, "AXGroup", 1, "AXGroup", 2)
  if collection ~= nil and collection.AXDescription ==
      localizedString("Recent Calls", winObj:application():bundleID()) then
    local section = collection:childrenWithRole("AXButton")[1]
    if section ~= nil then
      local position = { section.AXPosition.x + 50, section.AXPosition.y + 10 }
      if not rightClick(position, winObj:application():name()) then return end
      local popup = getAXChildren(winUIObj, "AXGroup", 1, "AXMenu", 1)
      local maxTime, time = 0.5, 0
      while popup == nil and time < maxTime do
        hs.timer.usleep(0.01 * 1000000)
        time = time + 0.01
        popup = getAXChildren(winUIObj, "AXGroup", 1, "AXMenu", 1)
      end
      if popup == nil then
        if not rightClick(position, winObj:application():name()) then return end
        popup = getAXChildren(winUIObj, "AXGroup", 1, "AXMenu", 1)
        time = 0
        while popup == nil and time < maxTime do
          hs.timer.usleep(0.01 * 1000000)
          time = time + 0.01
          popup = getAXChildren(winUIObj, "AXGroup", 1, "AXMenu", 1)
        end
        if popup == nil then return end
      end
      local menuItem = popup:childrenWithRole("AXMenuItem")[5]
      if menuItem ~= nil then
        menuItem:performAction("AXPress")
      end
      hs.timer.usleep(0.1 * 1000000)
      deleteAllCalls(winObj)
    end
    return
  end
  winUIObj:elementSearch(
    function(msg, results, count)
      if count == 0 then return end

      local sectionList = results[1].AXChildren[1]:childrenWithRole("AXGroup")
      if #sectionList == 0 then return end

      local section = sectionList[1]
      if not rightClickAndRestore(section.AXPosition, winObj:application():name()) then
        return
      end
      local popups = section:childrenWithRole("AXMenu")
      local maxTime, time = 0.5, 0
      while #popups == 0 and time < maxTime do
        hs.timer.usleep(0.01 * 1000000)
        time = time + 0.01
        popups = section:childrenWithRole("AXMenu")
      end
      for _, popup in ipairs(popups) do
        for _, menuItem in ipairs(popup:childrenWithRole("AXMenuItem")) do
          if menuItem.AXIdentifier == "menuRemovePersonFromRecents:" then
            menuItem:performAction("AXPress")
            hs.timer.usleep(0.1 * 1000000)
            break
          end
        end
      end
      deleteAllCalls(winUIObj)
    end,
    function(element)
      return element.AXSubrole == "AXCollectionList"
          and element.AXChildren ~= nil and #element.AXChildren > 0
          and element.AXChildren[1].AXSubrole == "AXSectionList"
    end,
    { count = 1 }
  )
end

-- ### Visual Studio Code
local function VSCodeToggleSideBarSection(appObject, sidebar, section)
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
      tell ]] .. aWinFor(appObject) .. [[
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

-- ### JabRef
local function JabRefShowLibraryByIndex(idx)
  return function(appObject)
    if appObject:focusedWindow() == nil then return false end
    local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
    local tab = getAXChildren(winUIObj, "AXTabGroup", 1, "AXRadioButton", idx)
    if tab ~= nil then
      return true, { x = tab.AXPosition.x + 10, y = tab.AXPosition.y + 10 }
    else
      return false
    end
  end
end

-- ### Bartender
local bartenderBarItemNames
local bartenderBarItemIDs
local bartenderBarWindowFilter = { allowTitles = "^Bartender Bar$" }
local bartenderBarFilter
local function getBartenderBarItemTitle(index, rightClick)
  return function(appObject)
    if bartenderBarItemNames == nil then
      local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
      local icons = getAXChildren(winUIObj, "AXScrollArea", 1, "AXList", 1, "AXList", 1)
      local appNames = hs.fnutils.map(icons:childrenWithRole("AXGroup"), function(g)
        return getAXChildren(g, "AXImage", 1).AXDescription
      end)
      if #appNames > 0 then
        local bundleID = appObject:bundleID()
        local _, items = hs.osascript.applescript(string.format([[
          tell application id "%s" to list menu bar items
        ]], bundleID))
        local itemList = hs.fnutils.split(items, "\n")
        local splitterIndex = hs.fnutils.indexOf(itemList, bundleID .. "-statusItem")
        local barSplitterIndex = hs.fnutils.indexOf(appNames, appObject:name())
        if barSplitterIndex ~= nil then
          splitterIndex = splitterIndex - (#appNames - (barSplitterIndex - 1))
        end
        bartenderBarItemNames = {}
        bartenderBarItemIDs = {}
        local missedItemCnt = 0
        local plistPath = hs.fs.pathToAbsolute(string.format(
            "~/Library/Preferences/%s.plist", bundleID))
        if plistPath ~= nil then
          local plist = hs.plist.read(plistPath)
          local allwaysHidden = get(plist, "ProfileSettings", "activeProfile", "AlwaysHide")
          local itemIDIdx = splitterIndex + #appNames
          while hs.fnutils.contains(allwaysHidden, itemList[itemIDIdx]) and itemIDIdx > splitterIndex do
            itemIDIdx = itemIDIdx - 1
          end
          missedItemCnt = #appNames - (itemIDIdx - splitterIndex)
        end
        if missedItemCnt == 0 then
          for i = 1, #appNames do
            local appName = appNames[i]
            local itemID = itemList[splitterIndex + 1 + #appNames - i]
            local bid, idx = string.match(itemID, "(.-)%-Item%-(%d+)$")
            if bid ~= nil then
              if idx == "0" then
                table.insert(bartenderBarItemNames, appName)
              else
                table.insert(bartenderBarItemNames, string.format("%s (Item %s)", appName, idx))
              end
              table.insert(bartenderBarItemIDs, itemID)
            else
              local app = findApplication(appName)
              if app == nil or app:bundleID() ~= itemID:sub(1, #app:bundleID()) then
                table.insert(bartenderBarItemNames, appName)
                table.insert(bartenderBarItemIDs, itemID)
              elseif app ~= nil then
                local itemShortName = itemID:sub(#app:bundleID() + 2)
                table.insert(bartenderBarItemNames, string.format("%s (%s)", appName, itemShortName))
                table.insert(bartenderBarItemIDs, itemID)
              end
            end
          end
        else
          for i = 1, #appNames do
            table.insert(bartenderBarItemNames, appNames[i])
            table.insert(bartenderBarItemIDs, i)
          end
        end
        bartenderBarFilter = hs.window.filter.new(false):setAppFilter(
            appObject:name(), bartenderBarWindowFilter)
        bartenderBarFilter:subscribe(
            { hs.window.filter.windowDestroyed, hs.window.filter.windowUnfocused },
            function()
              bartenderBarItemNames = nil
              bartenderBarItemIDs = nil
              bartenderBarFilter:unsubscribeAll()
              bartenderBarFilter = nil
            end)
      end
    end
    if bartenderBarItemNames ~= nil and index <= #bartenderBarItemNames then
      return (rightClick and "Right-click " or "Click ") .. bartenderBarItemNames[index]
    end
  end
end

local function clickBartenderBarItem(index, rightClick)
  return function(winObj)
    local bundleID = winObj:application():bundleID()
    local itemID = bartenderBarItemIDs[index]
    if type(itemID) == 'string' then
      local script = string.format('tell application id "%s" to activate "%s"',
          bundleID, bartenderBarItemIDs[index])
      if rightClick then
        script = script .. " with right click"
      end
      hs.osascript.applescript(script)
      hs.timer.doAfter(0.1, function()
        hs.osascript.applescript(string.format([[
          tell application id "%s" to toggle bartender
        ]], bundleID))
      end)
    else
      local winUIObj = hs.axuielement.windowElement(findApplication(bundleID):focusedWindow())
      local icon = getAXChildren(winUIObj, "AXScrollArea", 1, "AXList", 1, "AXList", 1, "AXGroup", itemID, "AXImage", 1)
      if icon ~= nil then
        local position = { icon.AXPosition.x + 10, icon.AXPosition.y + 10 }
        if rightClick then
          rightClickAndRestore(position, winObj:application():name())
        else
          leftClickAndRestore(position, winObj:application():name())
        end
      end
    end
  end
end

-- ### iCopy
local function iCopySelectHotkeyMod(appObject)
  return versionLessThan("1.1.1")(appObject) and "" or "⌃"
end
local iCopyMod

local function iCopySelectHotkeyRemap(idx)
  return function(winObj)
    if iCopyMod == nil then
      iCopyMod = iCopySelectHotkeyMod(winObj:application())
    end
    hs.eventtap.keyStroke(iCopyMod, tostring(idx), nil, winObj:application())
  end
end

local iCopyWindowFilter = {
  allowRegions = {
    hs.geometry.rect(
        0, hs.screen.mainScreen():fullFrame().y + hs.screen.mainScreen():fullFrame().h - 400,
        hs.screen.mainScreen():fullFrame().w, 400)
  }
}

-- ### browsers
local function getTabSource(appObject)
  local ok, source
  if appObject:bundleID() == "com.apple.Safari" then
    ok, source = hs.osascript.applescript([[
      tell application id "com.apple.Safari"
        do JavaScript "document.body.innerHTML" in front document
      end tell
    ]])
  else  -- assume chromium-based browsers
    ok, source = hs.osascript.applescript(string.format([[
      tell application id "%s"
        execute active tab of front window javascript "document.documentElement.outerHTML"
      end tell
    ]], appObject:bundleID()))
  end
  if ok then return source end
end

local function getTabUrl(appObject)
  local ok, url
  if appObject:bundleID() == "com.apple.Safari" then
    ok, url = hs.osascript.applescript([[
      tell application id "com.apple.Safari" to get URL of front document
    ]])
  else  -- assume chromium-based browsers
    ok, url = hs.osascript.applescript(string.format([[
      tell application id "%s" to get URL of active tab of front window
    ]], appObject:bundleID()))
  end
  if ok then return url end
end

local function weiboNavigateToSideBarCondition(idx, isCommon)
  return function(appObject)
    if idx == 1 and isCommon then
      return true, ""
    end
    local source = getTabSource(appObject)
    if source == nil then return end
    local start, stop
    if isCommon then
      local header = [[<h2 class="Nav_title_[^>]-">首页</h2>]]
      local tailer = [[<div class="[^>]-Home_split_[^>]-">]]
      _, start = source:find(header)
      if start == nil then
        hs.timer.usleep(1 * 1000000)
        source = getTabSource(appObject)
        if source == nil then return end
        _, start = source:find(header)
      end
      if start == nil then return false end
      stop = source:find(tailer, start + 1) or source:len()
    else
      local header = [[<h3 class="Home_title_[^>]-">自定义分组</h3>]]
      local tailer = [[<button class="[^>]-Home_btn_[^>]-">]]
      _, start = source:find(header)
      if start == nil then
        hs.timer.usleep(1 * 1000000)
        source = getTabSource(appObject)
        if source == nil then return end
        _, start = source:find(header)
      end
      if start == nil then return false end
      stop = source:find(tailer, start + 1) or source:len()
    end
    source = source:sub(start + 1, stop - 1)
    local cnt = isCommon and 1 or 0
    for url in string.gmatch(source, [[<a class="ALink_none[^>]-href="/(mygroup.-)">]]) do
      cnt = cnt + 1
      if cnt == idx then return true, url end
    end
    return false
  end
end

local function weiboNavigateToSideBar(result, url, appObject)
  local schemeEnd = url:find("//")
  local domainEnd = url:find("/", schemeEnd + 2)
  local fullUrl = url:sub(1, domainEnd) .. result
  if appObject:bundleID() == "com.apple.Safari" then
    hs.osascript.applescript(string.format([[
      tell application id "com.apple.Safari"
        set URL of front document to "%s"
      end tell
    ]], fullUrl))
  else  -- assume chromium-based browsers
    hs.osascript.applescript(string.format([[
      tell application id "%s"
        set URL of active tab of front window to "%s"
      end tell
    ]], appObject:bundleID(), fullUrl))
  end
end

local function weiboNavigateToCustomGroupCondition(idx)
  return weiboNavigateToSideBarCondition(idx, false)
end

local function weiboNavigateToCommonGroupCondition(idx)
  return weiboNavigateToSideBarCondition(idx, true)
end

local function douyinNavigateToTabCondition(idx)
  return function(appObject)
    local source = getTabSource(appObject)
    if source == nil then return end
    local cnt = 0
    local lastURL = ""
    for url in string.gmatch(source, [[<div class="tab\-[^>]-><a href="(.-)"]]) do
      if url ~= lastURL then cnt = cnt + 1 end
      if cnt == idx then return true, url end
      lastURL = url
    end
    return false
  end
end

local function douyinNavigateToTab(result, url, appObject)
  local fullUrl
  if result:sub(1, 2) == '//' then
    local schemeEnd = url:find("//")
    fullUrl = url:sub(1, schemeEnd - 1) .. result
  else
    fullUrl = result
  end
  if appObject:bundleID() == "com.apple.Safari" then
    hs.osascript.applescript(string.format([[
      tell application id "com.apple.Safari"
        set URL of front document to "%s"
      end tell
    ]], fullUrl))
  else  -- assume chromium-based browsers
    hs.osascript.applescript(string.format([[
      tell application id "%s"
        set URL of active tab of front window to "%s"
      end tell
    ]], appObject:bundleID(), fullUrl))
  end
end

-- ## functin utilities for hotkey configs

-- some apps save key bindings in plist files
-- we need to parse them and remap specified key bindings to them
local function parsePlistKeyBinding(mods, key)
  mods = tonumber(mods) key = tonumber(key)
  if mods == nil or key == nil then return end
  key = hs.keycodes.map[key]
  local modList = {}
  if mods >= (1 << 17) then
    if mods >= (1 << 23) then table.insert(modList, "fn") end
    if (mods % (1 << 23)) >= (1 << 20) then table.insert(modList, "command") end
    if (mods % (1 << 20)) >= (1 << 19) then table.insert(modList, "option") end
    if (mods % (1 << 19)) >= (1 << 18) then table.insert(modList, "control") end
    if (mods % (1 << 18)) >= (1 << 17) then table.insert(modList, "shift") end
  else
    if mods >= (1 << 12) then table.insert(modList, "control") end
    if (mods % (1 << 12)) >= (1 << 11) then table.insert(modList, "option") end
    if (mods % (1 << 11)) >= (1 << 9) then table.insert(modList, "shift") end
    if (mods % (1 << 9)) >= (1 << 8) then table.insert(modList, "command") end
  end
  return modList, key
end

-- dump specified key bindings to plist files
local function dumpPlistKeyBinding(mode, mods, key)
  local modIdx = 0
  if mode == 1 then
    if hs.fnutils.contains(mods, "command") then modIdx = (1 << 8) end
    if hs.fnutils.contains(mods, "option") then modIdx = modIdx + (1 << 11) end
    if hs.fnutils.contains(mods, "control") then modIdx = modIdx + (1 << 12) end
    if hs.fnutils.contains(mods, "shift") then modIdx = modIdx + (1 << 9) end
  elseif mode == 2 then
    if key:lower():match("^f(%d+)$") then modIdx = 1 << 23 end
    if hs.fnutils.contains(mods, "command") then modIdx = modIdx + (1 << 20) end
    if hs.fnutils.contains(mods, "option") then modIdx = modIdx + (1 << 19) end
    if hs.fnutils.contains(mods, "control") then modIdx = modIdx + (1 << 18) end
    if hs.fnutils.contains(mods, "shift") then modIdx = modIdx + (1 << 17) end
  end
  key = hs.keycodes.map[key]
  return modIdx, key
end

-- fetch localized string as hotkey message after activating the app
local function commonLocalizedMessage(message)
  if message == "Hide" or message == "Quit" then
    return function(appObject)
      local appLocale = applicationLocales(appObject:bundleID())[1]
      local appLocalesSupported = hs.application.localizationsForBundleID(appObject:bundleID()) or {}
      local locale = getMatchedLocale(appLocale, appLocalesSupported)
      if locale ~= nil then
        local result = localizedString(message .. ' App Store', 'com.apple.AppStore',
                                       { locale = appLocale })
        if result ~= nil then
          return result:gsub('App Store', appObject:name())
        end
      end
      return message .. ' ' .. appObject:name()
    end
  elseif message == "Back" then
    return function(appObject)
      local appLocale = applicationLocales(appObject:bundleID())[1]
      local appLocalesSupported = hs.application.localizationsForBundleID(appObject:bundleID()) or {}
      local locale = getMatchedLocale(appLocale, appLocalesSupported)
      if locale ~= nil then
        local result = localizedString(message, 'com.apple.AppStore',
                                       { locale = appLocale })
        if result ~= nil then
          return result
        end
      end
      return message
    end
  else
    return function(appObject)
      local appLocale = applicationLocales(appObject:bundleID())[1]
      local appLocalesSupported = hs.application.localizationsForBundleID(appObject:bundleID()) or {}
      local locale = getMatchedLocale(appLocale, appLocalesSupported)
      if locale ~= nil then
        local resourceDir = '/System/Library/Frameworks/AppKit.framework/Resources'
        locale = getMatchedLocale(locale, resourceDir, 'lproj')
        if locale ~= nil then
          for _, stem in ipairs{ 'MenuCommands', 'Menus', 'Common' } do
            local result = localizeByLoctable(message, resourceDir, stem, locale, {})
            if result ~= nil then
              return result:gsub('“%%@”', ''):gsub('%%@', '')
            end
          end
        end
      end
      return message
    end
  end
end

local function localizedMessage(message, params, sep)
  return function(appObject)
    local bundleID = appObject:bundleID()
    if type(message) == 'string' then
      return localizedString(message, bundleID, params) or message
    else
      if sep == nil then sep = ' > ' end
      local str = localizedMenuBarItem(message[1], bundleID, params) or message[1]
      for i=2,#message do
        str = str .. sep .. (localizedString(message[i], bundleID, params) or message[i])
      end
      return str
    end
  end
end

-- fetch title of menu item as hotkey message by key binding
local function menuItemMessage(mods, key, titleIndex, sep)
  return function(appObject)
    if type(titleIndex) == 'number' then
      return findMenuItemByKeyBinding(appObject, mods, key)[titleIndex]
    else
      if sep == nil then sep = ' > ' end
      local menuItem = findMenuItemByKeyBinding(appObject, mods, key)
      assert(menuItem)
      local str = menuItem[titleIndex[1]]
      for i=2,#titleIndex do
        str = str .. sep .. menuItem[titleIndex[i]]
      end
    end
  end
end

-- check if the menu item whose path is specified is enabled
-- if so, return the path of the menu item
local function checkMenuItem(menuItemTitle, params)
  return function(appObject)
    local menuItem, menuItemTitle = findMenuItem(appObject, menuItemTitle, params)
    return menuItem ~= nil and menuItem.enabled, menuItemTitle
  end
end

-- possible reasons for failure of hotkey condition
local COND_FAIL = {
  NOT_FRONTMOST_WINDOW = "NOT_FRONTMOST_WINDOW",
  MENU_ITEM_SELECTED = "MENU_ITEM_SELECTED",
  NO_MENU_ITEM_BY_KEYBINDING = "NO_MENU_ITEM_BY_KEYBINDING",
  WINDOW_FILTER_NOT_SATISFIED = "WINDOW_FILTER_NOT_SATISFIED",
  WEBSITE_FILTER_NOT_SATISFIED = "WEBSITE_FILTER_NOT_SATISFIED",
}

-- check whether the menu bar item is selected
-- if a menu is extended, hotkeys with no modifiers are disabled
local function noSelectedMenuBarItem(appObject)
  local appUIObj = hs.axuielement.applicationElement(appObject)
  local menuBar
  local maxTryTime = 3
  local tryInterval = 0.05
  local tryTimes = 1
  while tryTimes <= maxTryTime / tryInterval do
    menuBar = appUIObj:childrenWithRole("AXMenuBar")[1]
    if menuBar ~= nil then break end
    hs.timer.usleep(tryInterval * 1000000)
    tryTimes = tryTimes + 1
  end
  if menuBar == nil then return true end
  for i, menuBarItem in ipairs(menuBar:childrenWithRole("AXMenuBarItem")) do
    if i > 1 and menuBarItem.AXSelected then
      return false
    end
  end
  return true
end

local function noSelectedMenuBarItemFunc(fn)
  return function(obj)
    local appObject = obj.application ~= nil and obj:application() or obj
    local satisfied = noSelectedMenuBarItem(appObject)
    if satisfied then
      if fn ~= nil then
        return fn(obj)
      else
        return true
      end
    else
      return false, COND_FAIL.MENU_ITEM_SELECTED
    end
  end
end

-- check if the menu item whose key binding is specified is enabled
-- if so, return the path of the menu item
local function checkMenuItemByKeybinding(mods, key)
  return function(appObject)
    local menuItem, enabled = findMenuItemByKeyBinding(appObject, mods, key)
    if menuItem ~= nil and enabled then
      return true, menuItem
    else
      return false, COND_FAIL.NO_MENU_ITEM_BY_KEYBINDING
    end
  end
end

-- select the menu item returned by the condition
-- work as hotkey callback
local function receiveMenuItem(menuItemTitle, appObject)
  appObject:selectMenuItem(menuItemTitle)
end

-- show the menu item returned by the condition
-- work as hotkey callback
local function showMenuItem(menuItemTitle, appObject)
  local fn = function()
    appObject:selectMenuItem({ menuItemTitle[1] })
    if #menuItemTitle > 1 then
      appObject:selectMenuItem(menuItemTitle)
    end
  end
  fn = showMenuItemWrapper(fn)
  fn()
end

-- click the position returned by the condition
-- work as hotkey callback
local function receivePosition(position, appObject)
  leftClickAndRestore(position, appObject:name())
end

-- click the button returned by the condition
-- work as hotkey callback
local function receiveButton(button)
  button:performAction("AXPress")
end

-- send key strokes to the app. but if the key binding is found, select corresponding menu item
---@diagnostic disable-next-line: lowercase-global
function selectMenuItemOrKeyStroke(appObject, mods, key)
  local menuItemPath, enabled = findMenuItemByKeyBinding(appObject, mods, key)
  if menuItemPath ~= nil and enabled then
    appObject:selectMenuItem(menuItemPath)
  else
    hs.eventtap.keyStroke(mods, key, nil, appObject)
  end
end

-- get hotkey idx like how Hammerspoon does that
local function hotkeyIdx(mods, key)
  local idx = string.upper(key)
  if type(mods) == 'string' then
    if mods == "shift" then idx = "⇧" .. idx
    elseif mods == "option" or mods == "alt" then idx = "⌥" .. idx
    elseif mods == "control" or mods == "ctrl" then idx = "⌃" .. idx
    elseif mods == "command" or mods == "cmd" then idx = "⌘" .. idx
    else
      if string.find(mods, "⇧") then idx = "⇧" .. idx end
      if string.find(mods, "⌥") then idx = "⌥" .. idx end
      if string.find(mods, "⌃") then idx = "⌃" .. idx end
      if string.find(mods, "⌘") then idx = "⌘" .. idx end
    end
  else
    if hs.fnutils.contains(mods, "shift") then idx = "⇧" .. idx end
    if hs.fnutils.contains(mods, "option") or hs.fnutils.contains(mods, "alt") then
      idx = "⌥" .. idx
    end
    if hs.fnutils.contains(mods, "control") or hs.fnutils.contains(mods, "ctrl") then
      idx = "⌃" .. idx
    end
    if hs.fnutils.contains(mods, "command") or hs.fnutils.contains(mods, "cmd") then
      idx = "⌘" .. idx
    end
  end
  return idx
end

-- send key strokes to the system. but if the key binding is registered, disable it temporally
local function safeGlobalKeyStroke(mods, key)
  local idx = hotkeyIdx(mods, key)
  local conflicted = hs.fnutils.filter(hs.hotkey.getHotkeys(), function(hk)
    return hk.idx == idx
  end)
  if conflicted[1] ~= nil then
    conflicted[1]:disable()
  end
  hs.eventtap.keyStroke(mods, key)
  if conflicted[1] ~= nil then
    hs.timer.doAfter(1, function() conflicted[1]:enable() end)
  end
end


-- ## hotkey configs for apps

-- hotkey configs that cound be used in various application
local specialCommonHotkeyConfigs = {
  ["closeWindow"] = {
    mods = "⌘", key = "W",
    message = commonLocalizedMessage("Close Window"),
    condition = function(appObject)
      local winObj = appObject:focusedWindow()
      return winObj ~= nil and winObj:role() == "AXWindow", winObj
    end,
    repeatable = true,
    fn = function(winObj) winObj:close() end
  },
  ["minimize"] = {
    mods = "⌘", key = "M",
    message = commonLocalizedMessage("Minimize"),
    condition = function(appObject)
      local winObj = appObject:focusedWindow()
      return winObj ~= nil and winObj:role() == "AXWindow", winObj
    end,
    repeatable = true,
    fn = function(winObj) winObj:minimize() end
  },
  ["hide"] = {
    mods = "⌘", key = "H",
    message = commonLocalizedMessage("Hide"),
    fn = function(appObject) appObject:hide() end
  },
  ["quit"] = {
    mods = "⌘", key = "Q",
    message = commonLocalizedMessage("Quit"),
    fn = function(appObject) appObject:kill() end
  },
  ["showPrevTab"] = {
    mods = "⇧⌘", key = "[",
    message = menuItemMessage('⇧⌃', "⇥", 2),
    condition = checkMenuItemByKeybinding('⇧⌃', "⇥"),
    repeatable = true,
    fn = receiveMenuItem
  },
  ["showNextTab"] = {
    mods = "⇧⌘", key = "]",
    message = menuItemMessage('⌃', "⇥", 2),
    condition = checkMenuItemByKeybinding('⌃', "⇥"),
    repeatable = true,
    fn = receiveMenuItem
  },
}

appHotKeyCallbacks = {
  ["com.apple.finder"] =
  {
    ["openRecent"] = {
      message = localizedMessage("Recent Folders"),
      condition = checkMenuItem({ "Go", "Recent Folders" }),
      fn = showMenuItem
    },
    ["open1stSidebarItem"] = {
      message = getFinderSidebarItemTitle(1),
      condition = getFinderSidebarItem(1),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    },
    ["open2ndSidebarItem"] = {
      message = getFinderSidebarItemTitle(2),
      condition = getFinderSidebarItem(2),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    },
    ["open3rdSidebarItem"] = {
      message = getFinderSidebarItemTitle(3),
      condition = getFinderSidebarItem(3),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    },
    ["open4thSidebarItem"] = {
      message = getFinderSidebarItemTitle(4),
      condition = getFinderSidebarItem(4),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    },
    ["open5thSidebarItem"] = {
      message = getFinderSidebarItemTitle(5),
      condition = getFinderSidebarItem(5),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    },
    ["open6thSidebarItem"] = {
      message = getFinderSidebarItemTitle(6),
      condition = getFinderSidebarItem(6),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    },
    ["open7thSidebarItem"] = {
      message = getFinderSidebarItemTitle(7),
      condition = getFinderSidebarItem(7),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    },
    ["open8thSidebarItem"] = {
      message = getFinderSidebarItemTitle(8),
      condition = getFinderSidebarItem(8),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    },
    ["open9thSidebarItem"] = {
      message = getFinderSidebarItemTitle(9),
      condition = getFinderSidebarItem(9),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    },
    ["open10thSidebarItem"] = {
      message = getFinderSidebarItemTitle(10),
      condition = getFinderSidebarItem(10),
      fn = openFinderSidebarItem,
      deleteOnDisable = true
    }
  },

  ["com.apple.ActivityMonitor"] =
  {
    ["search"] = {
      message = commonLocalizedMessage("Search"),
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
        local searchField = getAXChildren(winUIObj, "AXToolbar", 1, "AXGroup", 2, "AXTextField", 1)
        if searchField == nil then return false end
        return true, searchField
      end,
      fn = function(searchField, appObject)
        local position = { searchField.AXPosition.x + 10, searchField.AXPosition.y + 2 }
        leftClickAndRestore(position, appObject:name())
      end
    }
  },

  ["com.apple.MobileSMS"] =
  {
    ["deleteConversation"] = {
      message = localizedMessage("Delete Conversation…"),
      condition = checkMenuItem({
        getOSVersion() < OS.Ventura and "File" or "Conversation",
        "Delete Conversation…"
      }),
      fn = function(menuItemTitle, appObject) deleteSelectedMessage(appObject, menuItemTitle) end
    },
    ["deleteAllConversations"] = {
      message = "Delete All Conversations",
      fn = deleteAllMessages
    },
    ["goToPreviousConversation"] = {
      message = menuItemMessage('⇧⌃', "⇥", 2),
      condition = checkMenuItemByKeybinding('⇧⌃', "⇥"),
      repeatable = true,
      fn = receiveMenuItem
    },
    ["goToNextConversation"] = {
      message = menuItemMessage('⌃', "⇥", 2),
      condition = checkMenuItemByKeybinding('⌃', "⇥"),
      repeatable = true,
      fn = receiveMenuItem
    }
  },

  ["com.apple.FaceTime"] = {
    ["removeFromRecents"] = {
      message = localizedMessage("Remove from Recents",
                                 { framework = "ConversationKit.framework" }),
      condition = function(appObject)
        return appObject:focusedWindow() ~= nil, appObject:focusedWindow()
      end,
      fn = deleteMousePositionCall
    },
    ["clearAllRecents"] = {
      message = localizedMessage("Clear All Recents"),
      condition = function(appObject)
        return appObject:focusedWindow() ~= nil, appObject:focusedWindow()
      end,
      fn = deleteAllCalls
    }
  },

  ["com.apple.AppStore"] =
  {
    ["back"] = {
      message = localizedMessage("Back"),
      condition = function(appObject)
        local menuItem, menuItemTitle = findMenuItem(appObject, { "Store", "Back" })
        if menuItem ~= nil and menuItem.enabled then
          return true, menuItemTitle
        else
          if appObject:focusedWindow() == nil then return false end
          local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
          local button
          button = getAXChildren(winUIObj, "AXSplitGroup", 1, "AXGroup", 2, "AXButton", 1)
          if button ~= nil then return true, button end
          local g = getAXChildren(winUIObj, "AXGroup", 1)
          if g == nil then return false end
          button = hs.fnutils.find(g:childrenWithRole("AXButton"), function(b)
            return b.AXIdentifier == "UIA.AppStore.NavigationBackButton"
                or b.AXIdentifier == "AppStore.backButton"
          end)
          return button ~= nil, button
        end
      end,
      repeatable = true,
      fn = function(result, appObject)
        if type(result) == 'table' then
          appObject:selectMenuItem(result)
        else
          local button = result
          button:performAction("AXPress")
        end
      end
    }
  },

  ["com.apple.Safari"] =
  {
    ["showInFinder"] = {
      message = commonLocalizedMessage("Show in Finder"),
      condition = function(appObject)
        local ok, url = hs.osascript.applescript([[
          tell application id "]] .. appObject:bundleID() .. [[" to return URL of front document
        ]])
        if ok and string.sub(url, 1, 7) == "file://" then
          return true, url
        else
          return false
        end
      end,
      fn = function(url) hs.execute('open -R "' .. url .. '"') end
    },
    ["openRecent"] = {
      message = localizedMessage("Recently Closed"),
      condition = checkMenuItem({ "History", "Recently Closed" }),
      fn = showMenuItem
    }
  },

  ["com.apple.Preview"] =
  {
    ["showInFinder"] = {
      message = commonLocalizedMessage("Show in Finder"),
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
    ["showInFinder"] = {
      message = commonLocalizedMessage("Show in Finder"),
      condition = function(appObject)
        local ok, url = hs.osascript.applescript([[
          tell application id "]] .. appObject:bundleID() .. [[" to return URL of active tab of front window
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
      condition = function(appObject)
        if appObject:focusedWindow() == nil then
          return false
        else
          local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
          return winUIObj:attributeValue("AXIdentifier") ~= "open-panel"
        end
      end,
      repeatable = true,
      fn = function(appObject)
        VSCodeToggleSideBarSection(appObject, "EXPLORER", "OUTLINE")
      end
    },
    ["toggleSearchEditorWholeWord"] = {
      message = "Search Editor: Toggle Match Whole Word",
      condition = function(appObject)
        if appObject:focusedWindow() == nil then
          return false
        else
          local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
          return winUIObj:attributeValue("AXIdentifier") ~= "open-panel"
        end
      end,
      repeatable = true,
      fn = function(appObject) hs.eventtap.keyStroke("⌘⌥", "W", nil, appObject) end
    },
    ["openRecent"] = {
      message = "Open Recent",
      condition = function(appObject)
        local enabled, menuItem = checkMenuItem({ "File", "Open Recent", "More…" })(appObject)
        if enabled then
          return true, menuItem
        else
          return checkMenuItem({ "File", "Open Recent" })(appObject)
        end
      end,
      fn = function(menuItemTitle, appObject)
        if #menuItemTitle == 3 then
          appObject:selectMenuItem(menuItemTitle)
        else
          showMenuItem(menuItemTitle, appObject)
        end
      end
    }
  },

  ["com.readdle.PDFExpert-Mac"] =
  {
    ["showInFinder"] = {
      message = localizedMessage("Show in Finder"),
      condition = checkMenuItem({ "File", "Show in Finder" }),
      fn = receiveMenuItem
    },
    ["remapPreviousTab"] = {
      message = localizedMessage("Go to Previous Tab"),
      condition = checkMenuItem({ "Window", "Go to Previous Tab" }),
      repeatable = true,
      fn = receiveMenuItem
    }
  },

  ["com.vallettaventures.Texpad"] =
  {
    ["openRecent"] = {
      message = localizedMessage("Recent Documents"),
      condition = checkMenuItem({ "File", "Recent Documents" }),
      fn = showMenuItem
    },
    ["revealPDFInFinder"] = {
      message = localizedMessage("Reveal PDF in Finder..."),
      condition = checkMenuItem({ "File", "Reveal PDF in Finder..." }),
      fn = receiveMenuItem
    }
  },

  ["abnerworks.Typora"] =
  {
    ["openFileLocation"] = {
      message = localizedMessage("Open File Location"),
      condition = checkMenuItem({ "File", "Open File Location" }),
      fn = receiveMenuItem
    },
    ["pasteAsPlainText"] = {
      message = localizedMessage("Paste as Plain Text"),
      repeatable = true,
      fn = function(appObject)
        selectMenuItem(appObject, { "Edit", "Paste as Plain Text" })
      end
    },
  },

  ["com.superace.updf.mac"] =
  {
    ["showPrevTab"] = specialCommonHotkeyConfigs["showPrevTab"],
    ["showNextTab"] = specialCommonHotkeyConfigs["showNextTab"],
    ["showInFinder"] = {
      message = localizedMessage("Show in Finder"),
      condition = checkMenuItem({ "File", "Show in Finder" }),
      fn = receiveMenuItem
    }
  },

  ["com.kingsoft.wpsoffice.mac"] =
  {
    ["previousWindow"] = specialCommonHotkeyConfigs["showPrevTab"],
    ["nextWindow"] = specialCommonHotkeyConfigs["showNextTab"],
    ["goToFileTop"] = {
      mods = "", key = "Home",
      message = "将光标移动到文档的开头",
      repeatable = true,
      fn = function(appObject) hs.eventtap.keyStroke("⌘", "Home", nil, appObject) end
    },
    ["goToFileBottom"] = {
      mods = "", key = "End",
      message = "将光标移动到文档的结尾",
      fn = function(appObject) hs.eventtap.keyStroke("⌘", "End", nil, appObject) end
    },
    ["selectToFileTop"] = {
      mods = "⇧", key = "Home",
      message = "从当前位置选择到文档的开头",
      fn = function(appObject) hs.eventtap.keyStroke("⇧⌘", "Home", nil, appObject) end
    },
    ["selectToFileBottom"] = {
      mods = "⇧", key = "End",
      message = "从当前位置选择到文档的结尾",
      fn = function(appObject) hs.eventtap.keyStroke("⇧⌘", "End", nil, appObject) end
    },
    ["exportToPDF"] = {
      message = "输出为PDF...",
      condition = function(appObject)
        local menuItemPath = { "文件", "输出为PDF..." }
        local menuItem = appObject:findMenuItem(menuItemPath)
        if menuItem ~= nil then
          return menuItem.enabled, menuItemPath
        end
        menuItemPath[2] = "输出为PDF格式..."
        menuItem = appObject:findMenuItem(menuItemPath)
        return menuItem ~= nil and menuItem.enabled, menuItemPath
      end,
      fn = receiveMenuItem
    },
    ["insertTextBox"] = {
      message = "插入文本框",
      condition = function(appObject)
        local menuItemPath = { "插入", "文本框", "横向" }
        local menuItem = appObject:findMenuItem(menuItemPath)
        if menuItem ~= nil then
          return menuItem.enabled, menuItemPath
        end
        menuItemPath[3] = "横向文本框"
        menuItem = appObject:findMenuItem(menuItemPath)
        return menuItem ~= nil and menuItem.enabled, menuItemPath
      end,
      fn = receiveMenuItem
    },
    ["insertEquation"] = {
      message = "插入LaTeX公式...",
      condition = checkMenuItem({ "插入", "LaTeX公式..." }),
      fn = receiveMenuItem
    },
    ["pdfHightlight"] = {
      message = "高亮",
      condition = checkMenuItem({ "批注", "高亮" }),
      fn = receiveMenuItem
    },
    ["pdfUnderline"] = {
      message = "下划线",
      condition = checkMenuItem({ "批注", "下划线" }),
      fn = receiveMenuItem
    },
    ["pdfStrikethrough"] = {
      message = "删除线",
      condition = checkMenuItem({ "批注", "删除线" }),
      fn = receiveMenuItem
    },
    ["openFileLocation"] = {
      message = "打开文件位置",
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local winObj = appObject:focusedWindow()
        local winUIObj = hs.axuielement.windowElement(winObj)
        for i=1,#winUIObj.AXChildren - 1 do
          if winUIObj.AXChildren[i].AXRole == "AXButton"
              and winUIObj.AXChildren[i + 1].AXRole == "AXGroup" then
            return true, winUIObj.AXChildren[i].AXPosition
          end
        end
        return false
      end,
      fn = function(position, appObject)
        if not rightClickAndRestore(position, appObject:name()) then return end
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
      end
    }
  },

  ["com.apple.iWork.Keynote"] =
  {
    ["exportToPDF"] = {  -- File > Export To > PDF…
      message = localizedMessage({ "Export To", "PDF…" }),
      condition = checkMenuItem({ "File", "Export To", "PDF…" }),
      fn = function(menuItemTitle, appObject)
        appObject:selectMenuItem({ menuItemTitle[1], menuItemTitle[2] })
        appObject:selectMenuItem(menuItemTitle)
      end
    },
    ["exportToPPT"] = {  -- File > Export To > PowerPoint…
      message = localizedMessage({ "Export To", "PowerPoint…" }),
      condition = checkMenuItem({ "File", "Export To", "PowerPoint…" }),
      fn = function(menuItemTitle, appObject)
        appObject:selectMenuItem({ menuItemTitle[1], menuItemTitle[2] })
        appObject:selectMenuItem(menuItemTitle)
      end
    },
    ["pasteAndMatchStyle"] = {  -- Edit > Paste and Match Style
      message = localizedMessage("Paste and Match Style"),
      condition = checkMenuItem({ "Edit", "Paste and Match Style" }),
      repeatable = true,
      fn = receiveMenuItem
    },
    ["paste"] = {  -- Edit > Paste
      message = localizedMessage("Paste"),
      condition = checkMenuItem({ "Edit", "Paste" }),
      repeatable = true,
      fn = receiveMenuItem
    },
    ["showBuildOrder"] = {  -- View > Show Build Order
      message = localizedMessage("Show Build Order"),
      condition = checkMenuItem({ "View", "Show Build Order" }),
      fn = receiveMenuItem
    },
    ["play"] = {  -- Play > Play Slideshow
      message = localizedMessage("Play Slideshow"),
      condition = checkMenuItem({ "Play", "Play Slideshow" }),
      fn = receiveMenuItem
    },
    ["insertTextBox"] = {  -- Insert > Text Box
      message = localizedMessage({ "Insert", "Text Box" }),
      condition = checkMenuItem({ "Insert", "Text Box" }),
      fn = receiveMenuItem
    },
    ["insertShape"] = {  -- Insert > Shape
      message = localizedMessage({ "Insert", "Shape" }),
      condition = checkMenuItem({ "Insert", "Shape" }),
      fn = showMenuItem
    },
    ["insertLine"] = {  -- Insert > Line
      message = localizedMessage({ "Insert", "Line" }),
      condition = checkMenuItem({ "Insert", "Line" }),
      fn = showMenuItem
    },
    ["showInFinder"] = {
      message = commonLocalizedMessage("Show in Finder"),
      condition = function(appObject)
        local ok, filePath = hs.osascript.applescript([[
          tell application id "]] .. appObject:bundleID() .. [[" to get file of front document
        ]])
        if ok and filePath ~= nil then
          local pos = string.find(filePath, ":", 1)
          assert(pos)
          filePath = string.sub(filePath, pos)
          filePath = string.gsub(filePath, ":", "/")
          return true, filePath
        else
          return false
        end
      end,
      fn = function(filePath) hs.execute("open -R '" .. filePath .. "'") end
    },
  },

  ["com.apple.iWork.Pages"] =
  {
    ["exportToPDF"] = {  -- File > Export To > PDF…
      message = localizedMessage({ "Export To", "PDF…" }),
      condition = checkMenuItem({ "File", "Export To", "PDF…" }),
      fn = function(menuItemTitle, appObject)
        appObject:selectMenuItem({ menuItemTitle[1], menuItemTitle[2] })
        appObject:selectMenuItem(menuItemTitle)
      end
    },
    ["exportToWord"] = {  -- File > Export To > Word…
      message = localizedMessage({ "Export To", "Word…" }),
      condition = checkMenuItem({ "File", "Export To", "Word…" }),
      fn = function(menuItemTitle, appObject)
        appObject:selectMenuItem({ menuItemTitle[1], menuItemTitle[2] })
        appObject:selectMenuItem(menuItemTitle)
      end
    },
    ["pasteAndMatchStyle"] = {  -- Edit > Paste and Match Style
      message = localizedMessage("Paste and Match Style"),
      condition = checkMenuItem({ "Edit", "Paste and Match Style" }),
      repeatable = true,
      fn = receiveMenuItem
    },
    ["paste"] = {  -- Edit > Paste
      message = localizedMessage("Paste"),
      condition = checkMenuItem({ "Edit", "Paste" }),
      repeatable = true,
      fn = receiveMenuItem
    },
    ["showInFinder"] = {
      message = commonLocalizedMessage("Show in Finder"),
      condition = function(appObject)
        local ok, filePath = hs.osascript.applescript([[
          tell application id "]] .. appObject:bundleID() .. [[" to get file of front document
        ]])
        if ok and filePath ~= nil then
          local pos = string.find(filePath, ":", 1)
          assert(pos)
          filePath = string.sub(filePath, pos)
          filePath = string.gsub(filePath, ":", "/")
          return true, filePath
        else
          return false
        end
      end,
      fn = function(filePath) hs.execute("open -R '" .. filePath .. "'") end
    },
  },

  ["com.apple.iWork.Numbers"] =
  {
    ["exportToPDF"] = {  -- File > Export To > PDF…
      message = localizedMessage({ "Export To", "PDF…" }),
      condition = checkMenuItem({ "File", "Export To", "PDF…" }),
      fn = function(menuItemTitle, appObject)
        appObject:selectMenuItem({ menuItemTitle[1], menuItemTitle[2] })
        appObject:selectMenuItem(menuItemTitle)
      end
    },
    ["exportToExcel"] = {  -- File > Export To > Excel…
      message = localizedMessage({ "Export To", "Excel…" }),
      condition = checkMenuItem({ "File", "Export To", "Excel…" }),
      fn = function(menuItemTitle, appObject)
        appObject:selectMenuItem({ menuItemTitle[1], menuItemTitle[2] })
        appObject:selectMenuItem(menuItemTitle)
      end
    },
    ["pasteAndMatchStyle"] = {  -- Edit > Paste and Match Style
      message = localizedMessage("Paste and Match Style"),
      condition = checkMenuItem({ "Edit", "Paste and Match Style" }),
      repeatable = true,
      fn = receiveMenuItem
    },
    ["paste"] = {  -- Edit > Paste
      message = localizedMessage("Paste"),
      condition = checkMenuItem({ "Edit", "Paste" }),
      repeatable = true,
      fn = receiveMenuItem
    },
    ["showInFinder"] = {
      message = commonLocalizedMessage("Show in Finder"),
      condition = function(appObject)
        local ok, filePath = hs.osascript.applescript([[
          tell application id "]] .. appObject:bundleID() .. [[" to get file of front document
        ]])
        if ok and filePath ~= nil then
          local pos = string.find(filePath, ":", 1)
          assert(pos)
          filePath = string.sub(filePath, pos)
          filePath = string.gsub(filePath, ":", "/")
          return true, filePath
        else
          return false
        end
      end,
      fn = function(filePath) hs.execute("open -R '" .. filePath .. "'") end
    },
  },

  ["net.xmind.vana.app"] =
  {
    ["exportToPDF"] = {
      message = localizedMessage({ "Export", "PDF" }),
      condition = checkMenuItem({ "File", "Export", "PDF" }),
      fn = receiveMenuItem
    },
    ["insertEquation"] = {
      message = localizedMessage({ "Insert", "Equation" }),
      condition = checkMenuItem({ 'Insert', "Equation" }),
      fn = receiveMenuItem
    }
  },

  ["com.eusoft.freeeudic"] =
  {
    ["navigateToSearchField"] = {
      message = commonLocalizedMessage("Search"),
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
        local searchField = getAXChildren(winUIObj, 'AXToolbar', 1, 'AXGroup', 1, 'AXTextField', 1)
        if searchField == nil then return false end
        return true, searchField
      end,
      fn = function(searchField)
        searchField:performAction('AXConfirm')
      end
    },
  },

  ["com.openai.chat"] =
  {
    ["toggleSidebar"] = {
      message = localizedMessage("Toggle Sidebar"),
      fn = function(appObject)
        selectMenuItem(appObject, { "View", "Toggle Sidebar" })
      end
    },
    ["back"] = {
      message = commonLocalizedMessage("Back"),
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
        if winUIObj:attributeValue("AXIdentifier") ~= "ChatGPTSettingsAppWindow" then
          return false
        end
        local button = getAXChildren(winUIObj, "AXToolbar", 1, "AXButton", 1, "AXButton", 1)
        return button ~= nil and button.AXEnabled, button
      end,
      fn = receiveButton
    }
  },

  ["JabRef"] =
  {
    ["preferences"] = {
      message = "Preferences",
      condition = checkMenuItem({ "File", "Preferences" }),
      fn = receiveMenuItem
    },
    ["newLibrary"] = {
      message = "New Library",
      condition = checkMenuItem({ "File", "New library" }),
      fn = receiveMenuItem
    },
    ["openRecent"] = {
      message = "Recent Libraries",
      condition = checkMenuItem({ "File", "Recent libraries" }),
      fn = showMenuItem
    },
    ["remapPrevLibrary"] = {
      mods = get(KeybindingConfigs.hotkeys.appCommon, "remapPreviousTab", "mods"),
      key = get(KeybindingConfigs.hotkeys.appCommon, "remapPreviousTab", "key"),
      message = "Previous Library",
      condition = JabRefShowLibraryByIndex(2),
      repeatable = true,
      fn = function(appObject) hs.eventtap.keyStroke('⇧⌃', 'Tab', nil, appObject) end
    },
    ["showPrevLibrary"] = {
      mods = specialCommonHotkeyConfigs["showPrevTab"].mods,
      key = specialCommonHotkeyConfigs["showPrevTab"].key,
      message = "Previous Library",
      condition = JabRefShowLibraryByIndex(2),
      repeatable = true,
      fn = function(appObject) hs.eventtap.keyStroke('⇧⌃', 'Tab', nil, appObject) end
    },
    ["showNextLibrary"] = {
      mods = specialCommonHotkeyConfigs["showNextTab"].mods,
      key = specialCommonHotkeyConfigs["showNextTab"].key,
      message = "Next Library",
      condition = JabRefShowLibraryByIndex(2),
      repeatable = true,
      fn = function(appObject) hs.eventtap.keyStroke('⌃', 'Tab', nil, appObject) end
    },
    ["1stLibrary"] = {
      message = "First Library",
      condition = JabRefShowLibraryByIndex(1),
      fn = receivePosition
    },
    ["2ndLibrary"] = {
      message = "Second Library",
      condition = JabRefShowLibraryByIndex(2),
      fn = receivePosition
    },
    ["3rdLibrary"] = {
      message = "Third Library",
      condition = JabRefShowLibraryByIndex(3),
      fn = receivePosition
    },
    ["4thLibrary"] = {
      message = "Forth Library",
      condition = JabRefShowLibraryByIndex(4),
      fn = receivePosition
    },
    ["5thLibrary"] = {
      message = "Fifth Library",
      condition = JabRefShowLibraryByIndex(5),
      fn = receivePosition
    },
    ["6thLibrary"] = {
      message = "Sixth Library",
      condition = JabRefShowLibraryByIndex(6),
      fn = receivePosition
    },
    ["7thLibrary"] = {
      message = "Seventh Library",
      condition = JabRefShowLibraryByIndex(7),
      fn = receivePosition
    },
    ["8thLibrary"] = {
      message = "Eighth Library",
      condition = JabRefShowLibraryByIndex(8),
      fn = receivePosition
    },
    ["9thLibrary"] = {
      message = "Nineth Library",
      condition = JabRefShowLibraryByIndex(9),
      fn = receivePosition
    },
    ["10thLibrary"] = {
      message = "Tenth Library",
      condition = JabRefShowLibraryByIndex(10),
      fn = receivePosition
    },
    ["discardChanges"] = {
      message = "Discard changes",
      windowFilter = {
        allowTitles = "^Save before closing$"
      },
      fn = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local button = getAXChildren(winUIObj, "AXUnknown", 1, nil, 1, 'AXButton', 1)
        if button ~= nil then
          button:performAction("AXPress")
        end
      end
    },
    ["minimize"] = specialCommonHotkeyConfigs["minimize"]
  },

  ["org.klatexformula.klatexformula"] =
  {
    ["render"] = {
      message = "Render",
      windowFilter = {
        allowTitles = "^KLatexFormula$"
      },
      fn = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local button = getAXChildren(winUIObj, "AXSplitGroup", 1, "AXButton", 2)
        if button ~= nil then
          button:performAction("AXPress")
        end
      end
    },
    ["renderClipboardInKlatexformula"] = {
      message = "Render Clipboard in klatexformula",
      fn = function(appObject)
        appObject:mainWindow():focus()
        appObject:selectMenuItem({"Shortcuts", "Activate Editor and Select All"})
        hs.eventtap.keyStroke("⌘", "V", nil, appObject)

        local winUIObj = hs.axuielement.windowElement(appObject:mainWindow())
        local button = getAXChildren(winUIObj, "AXSplitGroup", 1, "AXButton", 2)
        if button ~= nil then
          button:performAction("AXPress")
        end
      end
    },
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"],
    ["minimize"] = specialCommonHotkeyConfigs["minimize"]
  },

  ["com.apple.iMovieApp"] =
  {
    ["export"] = {
      message = localizedMessage({ "Share", "File…" }),
      condition = checkMenuItem({ "File", "Share", "File…" }),
      fn = receiveMenuItem
    },
    ["openRecent"] = {
      message = localizedMessage("Open Library"),
      condition = checkMenuItem({ "File", "Open Library" }),
      fn = showMenuItem
    }
  },

  ["com.tencent.xinWeChat"] =
  {
    ["back"] = {
      message = localizedMessage("Common.Navigation.Back"),
      condition = function(appObject)
        local exBundleID = "com.tencent.xinWeChat.WeChatAppEx"
        local exAppObject = findApplication(exBundleID)
        if exAppObject ~= nil then
          local menuItemPath = {
            localizedMenuBarItem('File', exBundleID),
            localizedString('Back', exBundleID)
          }
          local menuItem = appObject:findMenuItem(menuItemPath)
          if menuItem ~= nil and menuItem.enabled then
            return true, { 0, menuItemPath }
          end
        end
        if appObject:focusedWindow() == nil then return false end
        local bundleID = appObject:bundleID()
        local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
        -- Moments
        if string.find(appObject:focusedWindow():title(), appObject:name()) == nil then
          local album = localizedString("Album_WindowTitle", bundleID)
          local moments = localizedString("SNS_Feed_Window_Title", bundleID)
          local detail = localizedString("SNS_Feed_Detail_Title", bundleID)
          if string.find(appObject:focusedWindow():title(), album .. '-') == 1
              or appObject:focusedWindow():title() == moments .. '-' .. detail then
            return true, { 2, winUIObj:childrenWithRole("AXButton")[1].AXPosition }
          end
          return false
        end
        local back = localizedString("Common.Navigation.Back", bundleID)
        -- Official Accounts
        local g = getAXChildren(winUIObj, "AXSplitGroup", 1, "AXSplitGroup", 1)
        if g ~= nil then
          for _, bt in ipairs(g:childrenWithRole("AXButton")) do
            if bt.AXTitle == back then
              return true, { 1, bt }
            end
          end
        end
        return false
      end,
      fn = function(result, appObject)
        if result[1] == 0 then
          appObject:selectMenuItem(result[2])
        elseif result[1] == 1 then
          result[2]:performAction("AXPress")
        elseif result[1] == 2 then
          leftClickAndRestore(result[2], appObject:name())
        end
      end
    },
    ["openInDefaultBrowser"] = {
      message = localizedMessage("Open in Default Browser"),
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
        local g = getAXChildren(winUIObj, "AXGroup", 1)
        return g ~= nil and g.AXDOMClassList ~= nil
      end,
      fn = function(appObject)
        local frame = appObject:focusedWindow():frame()
        local position = { frame.x + frame.w - 60, frame.y + 23 }
        leftClickAndRestore(position, appObject:name())
      end
    }
  },

  ["com.tencent.QQMusicMac"] =
  {
    ["back"] = {
      message = "上一页",
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local appUIObj = hs.axuielement.applicationElement(appObject)
        local frame = appObject:focusedWindow():frame()
        local titleBarUIObj = appUIObj:elementAtPosition(frame.x + 100, frame.y + 10)
        for _, button in ipairs(titleBarUIObj.AXChildren or {}) do
          if button.AXHelp == "后退" then
            return true, button:attributeValue("AXPosition")
          end
        end
        return false
      end,
      repeatable = true,
      fn = receivePosition
    },
    ["forward"] = {
      message = "下一页",
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local appUIObj = hs.axuielement.applicationElement(appObject)
        local frame = appObject:focusedWindow():frame()
        local titleBarUIObj = appUIObj:elementAtPosition(frame.x + 100, frame.y + 10)
        for _, button in ipairs(titleBarUIObj.AXChildren or {}) do
          if button.AXHelp == "前进" then
            return true, button:attributeValue("AXPosition")
          end
        end
        return false
      end,
      repeatable = true,
      fn = receivePosition
    },
    ["refresh"] = {
      message = "刷新",
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        local appUIObj = hs.axuielement.applicationElement(appObject)
        local frame = appObject:focusedWindow():frame()
        local titleBarUIObj = appUIObj:elementAtPosition(frame.x + 100, frame.y + 10)
        local refreshButtonPosition, searchButtonPosition
        for _, button in ipairs(titleBarUIObj.AXChildren or {}) do
          if button.AXHelp == "刷新" then
            refreshButtonPosition = button:attributeValue("AXPosition")
          elseif button.AXHelp == nil then
            searchButtonPosition = button:attributeValue("AXPosition")
          end
        end
        return refreshButtonPosition ~= nil and searchButtonPosition ~= nil
            and refreshButtonPosition.x ~= searchButtonPosition.x, refreshButtonPosition
      end,
      fn = receivePosition
    },
    ["playBarCloseSingleSong"] = {
      message = "关闭单曲",
      condition = function(appObject)
        if appObject:focusedWindow() == nil then return false end
        if versionLessThan("9")(appObject) then
          local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
          local buttons = winUIObj:childrenWithRole("AXButton")
          return #buttons > 4 and getAXChildren(winUIObj, "AXButton", '歌曲详情') ~= nil
        else
          if #appObject:visibleWindows() < 2 then return false end
          local fWin, mWin = appObject:focusedWindow(), appObject:mainWindow()
          local fFrame, mFrame = fWin:frame(), mWin:frame()
          return fWin:id() ~= mWin:id()
              and fFrame.x == mFrame.x and fFrame.y == mFrame.y
              and fFrame.w == mFrame.w and fFrame.h == mFrame.h
        end
      end,
      fn = function(appObject)
        local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
        local buttons = winUIObj:childrenWithRole("AXButton")
        buttons[#buttons - 2]:performAction("AXPress")
      end
    }
  },

  ["com.tencent.tenvideo"] =
  {
    ["openRecent"] = {
      message = "最近打开",
      fn = function(appObject)
        local appUIObj = hs.axuielement.applicationElement(appObject)
        local menuBarItems = appUIObj:childrenWithRole('AXMenuBar')[1]:childrenWithRole('AXMenuBarItem')
        local menuBarItem = hs.fnutils.find(menuBarItems, function(item)
          return item.AXChildren ~= nil and #item.AXChildren > 0 and item.AXTitle == '文件'
        end)
        if menuBarItem == nil then return end
        local menuItem = hs.fnutils.find(menuBarItem:childrenWithRole('AXMenu')[1]
                                                    :childrenWithRole('AXMenuItem'),
                                         function(item) return item.AXTitle == '最近打开' end)
        if menuItem ~= nil then
          menuBarItem:performAction('AXPress')
          menuItem:performAction('AXPress')
        end
      end
    }
  },

  ["com.tencent.meeting"] =
  {
    ["preferences"] = {
      message = localizedMessage("Preferences"),
      fn = function(appObject)
        local thisSpec = appHotKeyCallbacks[appObject:bundleID()]["preferences"]
        appObject:selectMenuItem({ appObject:name(), thisSpec.message(appObject) })
      end
    }
  },

  ["com.tencent.LemonMonitor"] =
  {
    ["closeWindow"] = {
      message = commonLocalizedMessage("Close Window"),
      windowFilter = {},
      background = true,
      fn = function(winUIObj)
        leftClickAndRestore({ x = winUIObj.AXPosition.x + winUIObj.AXSize.w/2,
                              y = winUIObj.AXPosition.y })
      end
    }
  },

  ["barrier"] =
  {
    ["toggleBarrierConnect"] = {
      message = "Toggle Barrier Connect",
      fn = function(appObject)
        local appUIObj = hs.axuielement.applicationElement(appObject)
        local menu = getAXChildren(appUIObj, "AXMenuBar", 2, "AXMenuBarItem", 1, "AXMenu", 1)
        if menu == nil then
          clickRightMenuBarItem(appObject:bundleID())
          menu = getAXChildren(appUIObj, "AXMenuBar", 2, "AXMenuBarItem", 1, "AXMenu", 1)
        end
        local start = getAXChildren(menu, "AXMenuItem", "Start")
        assert(start)
        if start.AXEnabled then
          start:performAction("AXPress")
          hs.alert("Barrier started")
        else
          local stop = getAXChildren(menu, "AXMenuItem", "Stop")
          assert(stop)
          stop:performAction("AXPress")
          hs.alert("Barrier stopped")
        end
      end,
      fnOnLaunch = function(appObject)
        if appObject:focusedWindow() == nil then
          hs.alert("Error occurred")
        else
          local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
          local start = getAXChildren(winUIObj, "AXButton", "Start")
          assert(start)
          start:performAction("AXPress")
          hs.alert("Barrier started")
          hs.timer.usleep(0.5 * 1000000)
          local close = getAXChildren(winUIObj, "AXButton", 4)
          assert(close)
          close:performAction("AXPress")
        end
      end
    },
    ["reload"] = {
      message = "Reload",
      windowFilter = {
        allowTitles = "^Barrier$"
      },
      condition = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local reload = getAXChildren(winUIObj, "AXButton", "Reload")
        return reload ~= nil and #reload:actionNames() > 0, reload
      end,
      fn = receiveButton
    },
    ["start"] = {
      message = "Start",
      windowFilter = {
        allowTitles = "^Barrier$"
      },
      condition = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local start = getAXChildren(winUIObj, "AXButton", "Start")
        return start ~= nil and #start:actionNames() > 0, start
      end,
      fn = receiveButton
    },
    ["stop"] = {
      message = "Stop",
      windowFilter = {
        allowTitles = "^Barrier$"
      },
      condition = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local stop = getAXChildren(winUIObj, "AXButton", "Stop")
        return stop ~= nil and #stop:actionNames() > 0, stop
      end,
      fn = receiveButton
    },
    ["configureServer"] = {
      message = "Configure Server...",
      windowFilter = {
        allowTitles = "^Barrier$"
      },
      condition = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local configure = getAXChildren(winUIObj, "AXCheckBox", 1, "AXButton", "Configure Server...")
        return configure ~= nil and #configure:actionNames() > 0, configure
      end,
      fn = receiveButton
    },
    ["browse"] = {
      message = "Browse",
      windowFilter = {
        allowTitles = "^Barrier$"
      },
      condition = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local browse = getAXChildren(winUIObj, "AXCheckBox", 1, "AXButton", "Browse...")
        return browse ~= nil and #browse:actionNames() > 0, browse
      end,
      fn = receiveButton
    },
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.objective-see.lulu.app"] =
  {
    ["allowConnection"] = {
      message = "Allow Connection",
      bindCondition = versionLessThan("2.9.1"),
      windowFilter = {
        allowTitles = "^LuLu Alert$"
      },
      condition = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local button = getAXChildren(winUIObj, "AXButton", "Allow")
        return button ~= nil, button
      end,
      fn = receiveButton
    },
    ["blockConnection"] = {
      message = "Block Connection",
      bindCondition = versionLessThan("2.9.1"),
      windowFilter = {
        allowTitles = "^LuLu Alert$"
      },
      condition = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local button = getAXChildren(winUIObj, "AXButton", "Block")
        return button ~= nil, button
      end,
      fn = receiveButton
    }
  },

  ["com.runningwithcrayons.Alfred-Preferences"] =
  {
    ["saveInSheet"] = {
      message = "Save",
      windowFilter = {
        allowSheet = true
      },
      condition = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local button = getAXChildren(winUIObj, "AXButton", "Save")
        return button ~= nil and button.AXEnabled == true, button
      end,
      fn = receiveButton
    }
  },

  ["com.surteesstudios.Bartender"] =
  {
    ["toggleMenuBar"] = {
      message = "Toggle Menu Bar",
      kind = HK.MENUBAR,
      fn = function(appObject)
        hs.osascript.applescript(string.format([[
          tell application id "%s" to toggle bartender
        ]], appObject:bundleID()))
      end
    },
    ["click1stBartenderBarItem"] = {
      message = getBartenderBarItemTitle(1),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(1)
    },
    ["rightClick1stBartenderBarItem"] = {
      message = getBartenderBarItemTitle(1, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(1, true)
    },
    ["click2ndBartenderBarItem"] = {
      message = getBartenderBarItemTitle(2),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(2)
    },
    ["rightClick2ndBartenderBarItem"] = {
      message = getBartenderBarItemTitle(2, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(2, true)
    },
    ["click3rdBartenderBarItem"] = {
      message = getBartenderBarItemTitle(3),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(3)
    },
    ["rightClick3rdBartenderBarItem"] = {
      message = getBartenderBarItemTitle(3, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(3, true)
    },
    ["click4thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(4),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(4)
    },
    ["rightClick4thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(4, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(4, true)
    },
    ["click5thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(5),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(5)
    },
    ["rightClick5thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(5, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(5, true)
    },
    ["click6thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(6),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(6)
    },
    ["rightClick6thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(6, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(6, true)
    },
    ["click7thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(7),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(7)
    },
    ["rightClick7thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(7, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(7, true)
    },
    ["click8thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(8),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(8)
    },
    ["rightClick8thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(8, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(8, true)
    },
    ["click9thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(9),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(9)
    },
    ["rightClick9thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(9, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(9, true)
    },
    ["click10thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(10),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(10)
    },
    ["rightClick10thBartenderBarItem"] = {
      message = getBartenderBarItemTitle(10, true),
      windowFilter = bartenderBarWindowFilter,
      background = true,
      fn = clickBartenderBarItem(10, true)
    },
    ["searchMenuBar"] = {
      message = "Search Menu Bar",
      kind = HK.MENUBAR,
      fn = function(appObject)
        hs.osascript.applescript(string.format([[
          tell application id "%s" to quick search
        ]], appObject:bundleID()))
      end
    },
    ["keyboardNavigate"] = {
      message = "Navigate Menu Bar",
      kind = HK.MENUBAR,
      bindCondition = function(appObject)
        local _, ok = hs.execute(string.format(
            "defaults read '%s' hotkeyKeyboardNav", appObject:bundleID()))
        return ok
      end,
      fn = function(appObject)
        local output = hs.execute(string.format(
            "defaults read '%s' hotkeyKeyboardNav", appObject:bundleID()))
        local spec = hs.fnutils.split(output, "\n")
        local mods = string.match(spec[4], "modifierFlags = (%d+)")
        local key = string.match(spec[3], "keyCode = (%d+)")
        mods, key = parsePlistKeyBinding(mods, key)
        safeGlobalKeyStroke(mods, key)
      end
    },
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"],
    ["minimize"] = specialCommonHotkeyConfigs["minimize"],
    ["quit"] = specialCommonHotkeyConfigs["quit"]
  },

  ["com.app.menubarx"] =
  {
    ["toggleMenuBarX"] = {
      message = "Toggle MenuBarX",
      kind = HK.MENUBAR,
      fn = function(appObject)
        local bundleID = appObject:bundleID()
        local output = hs.execute(string.format(
            "defaults read '%s' KeyboardShortcuts_toggleX | tr -d '\\n'", bundleID))
        if output == "0" then
          local spec = KeybindingConfigs.hotkeys[bundleID]["toggleMenuBarX"]
          local mods, key = dumpPlistKeyBinding(1, spec.mods, spec.key)
          local _, ok = hs.execute(string.format(
              [[defaults write '%s' KeyboardShortcuts_toggleX -string '{"carbonKeyCode":%d,"carbonModifiers":%d}']],
              bundleID, key, mods))
          appObject:kill()
          hs.timer.doAfter(1, function()
            hs.application.open(bundleID)
            hs.timer.doAfter(1, function()
              safeGlobalKeyStroke(spec.mods, spec.key)
            end)
          end)
        else
          local json = hs.json.decode(output)
          local mods, key = parsePlistKeyBinding(json["carbonModifiers"], json["carbonKeyCode"])
          if mods == nil or key == nil then return end
          safeGlobalKeyStroke(mods, key)
        end
      end
    }
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
      message = localizedString("In-app Screensaver", "whbalzac.Dongtaizhuomian",
                                { localeFile = "HotkeyWindowController" }),
      fn = function(appObject)
        local thisSpec = appHotKeyCallbacks[appObject:bundleID()]["invokeInAppScreenSaver"]
        clickRightMenuBarItem(appObject:bundleID(), thisSpec.message)
      end
    }
  },

  ["pl.maketheweb.TopNotch"] =
  {
    ["toggleTopNotch"] = {
      message = "Toggle Top Notch",
      fn = function(appObject)
        clickRightMenuBarItem(appObject:bundleID())
        local appUIObj = hs.axuielement.applicationElement(appObject)
        hs.timer.usleep(1 * 1000000)
        local switch = getAXChildren(appUIObj, "AXMenuBar", 1, "AXMenuBarItem", 1,
            "AXPopover", 1, "AXGroup", 3, "AXButton", 1)
        local state = switch.AXValue
        switch:performAction("AXPress")
        if state == 'off' then
          hs.eventtap.keyStroke("", "Escape", nil, appObject)
        else
          hs.timer.usleep(0.05 * 1000000)
          hs.eventtap.keyStroke("", "Space", nil, appObject)
        end
      end
    }
  },

  ["com.jetbrains.toolbox"] =
  {
    ["toggleJetbrainsToolbox"] = {
      message = "Toggle Jetbrains Toolbox",
      fn = focusOrHide
    }
  },

  ["com.mathpix.snipping-tool-noappstore"] =
  {
    ["OCRForLatex"] = {
      message = "OCR for LaTeX",
      bindCondition = function()
        local bundleID = "com.mathpix.snipping-tool-noappstore"
        local enabled = hs.execute(string.format(
            "defaults read '%s' getLatexShortcutEnabledKey | tr -d '\\n'", bundleID))
        return enabled == "1"
      end,
      fn = function(appObject)
        local mods = hs.execute(string.format(
            "defaults read '%s' getLatexHotKeyModifiersKey | tr -d '\\n'", appObject:bundleID()))
        local key = hs.execute(string.format(
            "defaults read '%s' getLatexHotKeyKey | tr -d '\\n'", appObject:bundleID()))
        mods, key = parsePlistKeyBinding(mods, key)
        if mods == nil or key == nil then return end
        safeGlobalKeyStroke(mods, key)
      end
    },
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"],
    ["hidePopover"] = {
      mods = "", key = "Escape",
      message = "Hide Popover",
      windowFilter = {
        allowPopover = true
      },
      fn = function(winObj)
        clickRightMenuBarItem(winObj:application():bundleID())
      end,
      deleteOnDisable = true
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

  ["com.apple.Image_Capture"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.apple.VoiceOverUtility"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.apple.DigitalColorMeter"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.apple.CaptiveNetworkAssistant"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.apple.CertificateAssistant"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.apple.displaycalibrator"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.apple.DeskCam"] =
  {
    ["closeWindow"] = specialCommonHotkeyConfigs["closeWindow"]
  },

  ["com.apple.Chess"] =
  {
    ["openRecent"] = {
      message = localizedMessage("Open Recent"),
      condition = checkMenuItem({ "Game", "Open Recent" }),
      fn = showMenuItem
    },
  },

  ["com.apple.ScreenSharing"] =
  {
    ["openRecent"] = {
      message = localizedMessage("Open Recent"),
      condition = checkMenuItem({ "Connect", "Open Recent" }),
      fn = showMenuItem
    },
  },

  ["com.parallels.desktop.console"] =
  {
    ["new..."] = {
      mods = "⌘", key = "N",
      message = localizedMessage("New..."),
      condition = checkMenuItem({ "File", "New..." }),
      fn = receiveMenuItem
    },
    ["open..."] = {
      mods = "⌘", key = "O",
      message = localizedMessage("Open..."),
      condition = checkMenuItem({ "File", "Open..." }),
      fn = receiveMenuItem
    },
    ["showControlCenter"] = {
      message = localizedMessage("Control Center"),
      condition = checkMenuItem({ "Window", "Control Center" }),
      fn = receiveMenuItem
    },
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
      repeatable = true,
      fn = function(result, appObject)
        if type(result) == 'table' then
          appObject:selectMenuItem(result)
        else
          result:close()
        end
      end
    }
  },

  ["org.wireshark.Wireshark"] =
  {
    ["closeWindow"] = {
      mods = "⌘", key = "W",
      message = localizedMessage("Close"),
      condition = function(appObject)
        local menuItem, menuItemTitle = findMenuItem(appObject, { "File", "Close" })
        if menuItem ~= nil and menuItem.enabled then
          return true, menuItemTitle
        else
          local winObj = appObject:focusedWindow()
          return winObj ~= nil and winObj:role() == "AXWindow", winObj
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

  ["com.torusknot.SourceTreeNotMAS"] =
  {
    ["showInFinder"] = {
      message = localizedMessage("Show In Finder"),
      fn = function(appObject)
        selectMenuItem(appObject, { "Actions", "Show In Finder" })
      end
    }
  },

  ["com.apple.dt.Xcode"] =
  {
    ["showInFinder"] = {
      message = "Show in Finder",
      condition = checkMenuItem({ "File", "Show in Finder" }),
      fn = receiveMenuItem
    }
  },

  ["com.jetbrains.CLion"] =
  {
    ["newProject"] = {
      message = "New Project",
      fn = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local button = getAXChildren(winUIObj, "AXButton", 2, "AXButton", 1)
        if button == nil then
          button = getAXChildren(winUIObj, "AXGroup", 2, "AXButton", 1, "AXButton", 1)
        end
        if button ~= nil then
          leftClickAndRestore(button.AXPosition, winObj:application():name())
        end
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
      fn = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local button = getAXChildren(winUIObj, "AXButton", 2, "AXButton", 1)
        if button == nil then
          button = getAXChildren(winUIObj, "AXGroup", 2, "AXButton", 1, "AXButton", 1)
        end
        if button ~= nil then
          leftClickAndRestore(button.AXPosition, winObj:application():name())
        end
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
      fn = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local button = getAXChildren(winUIObj, "AXButton", 2, "AXButton", 1)
        if button == nil then
          button = getAXChildren(winUIObj, "AXGroup", 2, "AXButton", 1, "AXButton", 1)
        end
        if button ~= nil then
          leftClickAndRestore(button.AXPosition, winObj:application():name())
        end
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
      fn = function(winObj)
        local winUIObj = hs.axuielement.windowElement(winObj)
        local button = getAXChildren(winUIObj, "AXButton", 2, "AXButton", 1)
        if button == nil then
          button = getAXChildren(winUIObj, "AXGroup", 2, "AXButton", 1, "AXButton", 1)
        end
        if button ~= nil then
          leftClickAndRestore(button.AXPosition, winObj:application():name())
        end
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
      bindCondition = function()
        local bundleID2 = "cn.better365.iShotProHelper"
        local _, ok = hs.execute(string.format(
            "defaults read '%s' dicOfShortCutKey | grep OCRRecorder", bundleID2))
        return ok
      end,
      fn = function()
        local bundleID2 = "cn.better365.iShotProHelper"
        local output = hs.execute(string.format(
          "defaults read '%s' dicOfShortCutKey | grep OCRRecorder -A4", bundleID2))
        local spec = hs.fnutils.split(output, "\n")
        local mods = string.match(spec[5], "modifierFlags = (%d+);")
        local key = string.match(spec[4], "keyCode = (%d+);")
        mods, key = parsePlistKeyBinding(mods, key)
        if mods == nil or key == nil then return end
        safeGlobalKeyStroke(mods, key)
      end
    }
  },

  ["cn.better365.iCopy"] =
  {
    ["select1stItem"] = {
      mods = "⌘", key = "1",
      message = "Select 1st Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(1)
    },
    ["select2ndItem"] = {
      mods = "⌘", key = "2",
      message = "Select 2nd Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(2)
    },
    ["select3rdItem"] = {
      mods = "⌘", key = "3",
      message = "Select 3rd Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(3)
    },
    ["select4thItem"] = {
      mods = "⌘", key = "4",
      message = "Select 4th Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(4)
    },
    ["select5thItem"] = {
      mods = "⌘", key = "5",
      message = "Select 5th Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(5)
    },
    ["select6thItem"] = {
      mods = "⌘", key = "6",
      message = "Select 6th Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(6)
    },
    ["select7thItem"] = {
      mods = "⌘", key = "7",
      message = "Select 7th Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(7)
    },
    ["select8thItem"] = {
      mods = "⌘", key = "8",
      message = "Select 8th Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(8)
    },
    ["select9thItem"] = {
      mods = "⌘", key = "9",
      message = "Select 9th Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(9)
    },
    ["select10thItem"] = {
      mods = "⌘", key = "0",
      message = "Select 10th Item",
      bindCondition = versionLessThan("1.1.3"),
      windowFilter = iCopyWindowFilter,
      fn = iCopySelectHotkeyRemap(10)
    },
    ["previousItem"] = {
      mods = "", key = "Left",
      message = "Previous Item",
      windowFilter = iCopyWindowFilter,
      repeatable = true,
      fn = function(winObj) hs.eventtap.keyStroke("", "Up", nil, winObj:application()) end
    },
    ["nextItem"] = {
      mods = "", key = "Right",
      message = "Next Item",
      windowFilter = iCopyWindowFilter,
      repeatable = true,
      fn = function(winObj) hs.eventtap.keyStroke("", "Down", nil, winObj:application()) end
    },
    ["cancelUp"] = {
      mods = "", key = "Up",
      message = "Cancel Up",
      windowFilter = iCopyWindowFilter,
      fn = function() end
    },
    ["cancelDown"] = {
      mods = "", key = "Down",
      message = "Cancel Down",
      windowFilter = iCopyWindowFilter,
      fn = function() end
    },
    ["cancelTap"] = {
      mods = "", key = "Tab",
      message = "Cancel Tab",
      windowFilter = iCopyWindowFilter,
      fn = function() end
    }
  }
}

local browserTabHotKeyCallbacks = {
  ["weiboNavigate1stCommonGroup"] = {
    message = "全部关注",
    condition = weiboNavigateToCommonGroupCondition(1),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate2ndCommonGroup"] = {
    message = "最新微博",
    condition = weiboNavigateToCommonGroupCondition(2),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate3rdCommonGroup"] = {
    message = "特别关注",
    condition = weiboNavigateToCommonGroupCondition(3),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate4thCommonGroup"] = {
    message = "好友圈",
    condition = weiboNavigateToCommonGroupCondition(4),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate1stCustomGroup"] = {
    message = "自定义分组1",
    condition = weiboNavigateToCustomGroupCondition(1),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate2ndCustomGroup"] = {
    message = "自定义分组2",
    condition = weiboNavigateToCustomGroupCondition(2),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate3rdCustomGroup"] = {
    message = "自定义分组3",
    condition = weiboNavigateToCustomGroupCondition(3),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate4thCustomGroup"] = {
    message = "自定义分组4",
    condition = weiboNavigateToCustomGroupCondition(4),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate5thCustomGroup"] = {
    message = "自定义分组5",
    condition = weiboNavigateToCustomGroupCondition(5),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate6thCustomGroup"] = {
    message = "自定义分组6",
    condition = weiboNavigateToCustomGroupCondition(6),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate7thCustomGroup"] = {
    message = "自定义分组7",
    condition = weiboNavigateToCustomGroupCondition(7),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate8thCustomGroup"] = {
    message = "自定义分组8",
    condition = weiboNavigateToCustomGroupCondition(8),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate9thCustomGroup"] = {
    message = "自定义分组9",
    condition = weiboNavigateToCustomGroupCondition(9),
    fn = weiboNavigateToSideBar
  },
  ["weiboNavigate10thCustomGroup"] = {
    message = "自定义分组10",
    condition = weiboNavigateToCustomGroupCondition(10),
    fn = weiboNavigateToSideBar
  },

  ["douyinNavigate1stTab"] = {
    message = "Tab 1",
    condition = douyinNavigateToTabCondition(1),
    fn = douyinNavigateToTab
  },
  ["douyinNavigate2ndTab"] = {
    message = "Tab 2",
    condition = douyinNavigateToTabCondition(2),
    fn = douyinNavigateToTab
  },
  ["douyinNavigate3rdTab"] = {
    message = "Tab 3",
    condition = douyinNavigateToTabCondition(3),
    fn = douyinNavigateToTab
  },
  ["douyinNavigate4thTab"] = {
    message = "Tab 4",
    condition = douyinNavigateToTabCondition(4),
    fn = douyinNavigateToTab
  },
  ["douyinNavigate5thTab"] = {
    message = "Tab 5",
    condition = douyinNavigateToTabCondition(5),
    fn = douyinNavigateToTab
  },
  ["douyinNavigate6thTab"] = {
    message = "Tab 6",
    condition = douyinNavigateToTabCondition(6),
    fn = douyinNavigateToTab
  },
  ["douyinNavigate7thTab"] = {
    message = "Tab 7",
    condition = douyinNavigateToTabCondition(7),
    fn = douyinNavigateToTab
  },
  ["douyinNavigate8thTab"] = {
    message = "Tab 8",
    condition = douyinNavigateToTabCondition(8),
    fn = douyinNavigateToTab
  },
  ["douyinNavigate9thTab"] = {
    message = "Tab 9",
    condition = douyinNavigateToTabCondition(9),
    fn = douyinNavigateToTab
  },
  ["douyinNavigate10thTab"] = {
    message = "Tab 10",
    condition = douyinNavigateToTabCondition(10),
    fn = douyinNavigateToTab
  }
}
local supportedBrowsers = {
  "com.apple.Safari", "com.google.Chrome",
  "com.microsoft.edgemac", "com.microsoft.edgemac.Dev"
}
for _, bid in ipairs(supportedBrowsers) do
  if appHotKeyCallbacks[bid] == nil then
    appHotKeyCallbacks[bid] = {}
  end
  for k, v in pairs(browserTabHotKeyCallbacks) do
    appHotKeyCallbacks[bid][k] = v
  end
  if KeybindingConfigs.hotkeys[bid] == nil then
    KeybindingConfigs.hotkeys[bid] = {}
  end
  for k, v in pairs(KeybindingConfigs.hotkeys.browsers or {}) do
    KeybindingConfigs.hotkeys[bid][k] = v
  end
end

local runningAppHotKeys = {}
local inAppHotKeys = {}
local inWinHotKeys = {}

-- hotkeys for background apps
local function registerRunningAppHotKeys(bid, appObject)
  if appHotKeyCallbacks[bid] == nil then return end
  local keybindings = KeybindingConfigs.hotkeys[bid] or {}

  if appObject == nil then
    appObject = findApplication(bid)
  end

  if runningAppHotKeys[bid] ~= nil then
    for _, hotkey in pairs(runningAppHotKeys[bid]) do
      hotkey:delete()
    end
  end
  runningAppHotKeys[bid] = {}

  -- do not support "condition" property currently
  for hkID, cfg in pairs(appHotKeyCallbacks[bid]) do
    -- prefer properties specified in configuration file than in code
    local keybinding = keybindings[hkID] or { mods = cfg.mods, key = cfg.key }
    local isBackground = keybinding.background ~= nil and keybinding.background or cfg.background
    local isPersistent = keybinding.persist ~= nil and keybinding.persist or cfg.persist
    local appInstalled = hs.application.pathForBundleID(bid) ~= nil and hs.application.pathForBundleID(bid) ~= ""
    local isForWindow = keybinding.windowFilter ~= nil or cfg.windowFilter ~= nil
    local bindable = function()
      return cfg.bindCondition == nil or ((appObject ~= nil and cfg.bindCondition(appObject))
        or (appObject == nil and isPersistent and cfg.bindCondition()))
    end
    if isBackground and not isForWindow
        and (appObject ~= nil or (isPersistent and appInstalled)) -- runninng / installed and persist
        and bindable() then                                       -- bindable
      local fn
      if isPersistent then
        fn = function()
          local newAppObject = findApplication(bid)
          if newAppObject then
            cfg.fn(newAppObject)
          else
            newAppObject = hs.application.open(bid)
            hs.timer.doAfter(1, function()
              if newAppObject then
                local cb = cfg.fnOnLaunch or cfg.fn
                cb(newAppObject)
              end
            end)
          end
        end
      else
        fn = hs.fnutils.partial(cfg.fn, appObject)
      end
      local repeatable = keybinding.repeatable ~= nil and keybinding.repeatable or cfg.repeatable
      local repeatedFn = repeatable and fn or nil
      local msg
      if type(cfg.message) == 'string' then
        msg = cfg.message
      elseif not isPersistent then
        msg = cfg.message(appObject)
      end
      if msg ~= nil then
        local hotkey = bindHotkeySpec(keybinding, msg, fn, nil, repeatedFn)
        if isPersistent then
          hotkey.persist = true
        end
        hotkey.kind = cfg.kind or HK.BACKGROUND
        hotkey.deleteOnDisable = cfg.deleteOnDisable
        hotkey.bundleID = bid
        runningAppHotKeys[bid][hkID] = hotkey
      end
    end
  end
end

local function unregisterRunningAppHotKeys(bid, force)
  if appHotKeyCallbacks[bid] == nil then return end

  if force then
    for _, hotkey in pairs(runningAppHotKeys[bid] or {}) do
      hotkey:delete()
    end
    runningAppHotKeys[bid] = nil
  else
    for _, hotkey in pairs(runningAppHotKeys[bid] or {}) do
      if hotkey.persist ~= true then
        hotkey:disable()
        if hotkey.deleteOnDisable then
          hotkey:delete()
          runningAppHotKeys[bid][hotkey] = nil
        end
      end
    end
  end
end

-- record windows created and alive since last app switch
-- we have to record them because key strokes must be sent to frontmost window instead of frontmost app
-- and some windows may be make frontmost silently
WindowCreatedSince = {}
local windowCreatedSinceWatcher = hs.window.filter.new(true):subscribe(
{hs.window.filter.windowCreated, hs.window.filter.windowFocused, hs.window.filter.windowDestroyed},
function(winObj, appName, eventType)
  if winObj == nil or winObj:application() == nil
      or winObj:application():bundleID() == hs.application.frontmostApplication():bundleID() then
    return
  end
  if eventType == hs.window.filter.windowCreated or eventType == hs.window.filter.windowFocused then
    WindowCreatedSince[winObj:id()] = winObj:application():bundleID()
  else
    for wid, bid in pairs(WindowCreatedSince) do
      if hs.window.get(wid) == nil or hs.window.get(wid):application():bundleID() ~= bid then
        WindowCreatedSince[wid] = nil
      end
    end
  end
end)

local function resendToFrontmostWindow(cond)
  return function(obj)
    if obj.application == nil and obj.focusedWindow == nil then return true end
    local appObject = obj.application ~= nil and obj:application() or obj
    local frontWin = hs.window.frontmostWindow()
    if frontWin ~= nil and appObject:focusedWindow() ~= nil
        and frontWin:application():bundleID() ~= appObject:bundleID() then
      return false, COND_FAIL.NOT_FRONTMOST_WINDOW
    elseif frontWin ~= nil and appObject:focusedWindow() == nil
        and WindowCreatedSince[frontWin:id()] then
      return false, COND_FAIL.NOT_FRONTMOST_WINDOW
    end
    if cond ~= nil then
      return cond(obj)
    else
      return true
    end
  end
end

local KEY_MODE = {
  PRESS = 1,
  REPEAT = 2,
}

local prevWebsiteCallbacks = {}
local prevWindowCallbacks = {}
function WrapCondition(appObject, mods, key, func, condition)
  local prevWebsiteCallback, prevWindowCallback
  local cond, windowFilter, mode, websiteFilter
  if type(condition) == 'table' then
    cond = condition.condition
    windowFilter = condition.windowFilter
    mode = condition.mode
    websiteFilter = condition.websiteFilter
  else
    cond = condition
  end
  if windowFilter ~= nil then
    local bid = appObject:bundleID()
    local hkIdx = hotkeyIdx(mods, key)
    if prevWindowCallbacks[bid] ~= nil and prevWindowCallbacks[bid][hkIdx] ~= nil then
      prevWindowCallback = prevWindowCallbacks[bid][hkIdx][mode]
    end
    local actualFilter
    if type(windowFilter) == 'table' then
      for k, v in pairs(windowFilter) do
        if k ~= "allowSheet" and k ~= "allowPopover" then
          if actualFilter == nil then actualFilter = {} end
          actualFilter[k] = v
        end
      end
      if actualFilter == nil then actualFilter = false end
    else
      actualFilter = windowFilter
    end
    local oldCond = cond
    cond = function(winObj)
      if winObj == nil then return false end
      local wf = hs.window.filter.new(false):setAppFilter(
        winObj:application():name(), actualFilter)
      if wf:isWindowAllowed(winObj)
          or (type(windowFilter) == 'table' and windowFilter.allowSheet and winObj:role() == "AXSheet")
          or (type(windowFilter) == 'table' and windowFilter.allowPopover and winObj:role() == "AXPopover") then
        if oldCond ~= nil then
          local satisfied, result = oldCond(winObj)
          if not satisfied then
            result = COND_FAIL.WINDOW_FILTER_NOT_SATISFIED
          end
          return satisfied, result
        else
          return true
        end
      else
        return false, COND_FAIL.WINDOW_FILTER_NOT_SATISFIED
      end
    end
  end
  if websiteFilter ~= nil then
    local hkIdx = hotkeyIdx(mods, key)
    if prevWebsiteCallbacks[hkIdx] ~= nil then
      prevWebsiteCallback = prevWebsiteCallbacks[hkIdx][mode]
    end
    local oldCond = cond
    cond = function(obj)
      local url = getTabUrl(appObject)
      if url ~= nil then
        local allowURLs = websiteFilter.allowURLs
        if type(allowURLs) == 'string' then
          allowURLs = { allowURLs }
        end
        for _, v in ipairs(allowURLs) do
          if string.match(url, v) ~= nil then
            if oldCond ~= nil then
              local satisfied, result = oldCond(obj)
              if not satisfied then
                return false, result
              elseif result ~= nil then
                return true, result, url
              else
                return true, url
              end
            else
              return true, url
            end
          end
        end
        return false, COND_FAIL.WEBSITE_FILTER_NOT_SATISFIED
      end
    end
  end
  -- if a menu is extended, hotkeys with no modifiers are disabled
  if mods == nil or mods == "" or #mods == 0 then
    cond = noSelectedMenuBarItemFunc(cond)
  end
  -- send key strokes to frontmost window instead of frontmost app
  cond = resendToFrontmostWindow(cond)
  local fn = func
  fn = function(...)
    local obj = windowFilter == nil and appObject or appObject:focusedWindow()
    if obj == nil then  -- no window focused when triggering window-specific hotkeys
      selectMenuItemOrKeyStroke(appObject, mods, key)
      return
    end
    local satisfied, result, url = cond(obj)
    if satisfied then
      if result ~= nil then  -- condition function can pass result to callback function
        if url ~= nil then
          func(result, url, obj, ...)
        else
          func(result, obj, ...)
        end
      else
        func(obj, ...)
      end
      return
    elseif result == COND_FAIL.NO_MENU_ITEM_BY_KEYBINDING
        or result == COND_FAIL.MENU_ITEM_SELECTED then
      hs.eventtap.keyStroke(mods, key, nil, appObject)
      return
    elseif result == COND_FAIL.WINDOW_FILTER_NOT_SATISFIED then
      if prevWindowCallback ~= nil then
        prevWindowCallback()
        return
      end
    elseif result == COND_FAIL.WEBSITE_FILTER_NOT_SATISFIED then
      if prevWebsiteCallback ~= nil then
        prevWebsiteCallback()
        return
      end
    elseif result == COND_FAIL.NOT_FRONTMOST_WINDOW then
      selectMenuItemOrKeyStroke(hs.window.frontmostWindow():application(), mods, key)
      return
    end
    -- most of the time, directly selecting menu item costs less time than key strokes
    selectMenuItemOrKeyStroke(appObject, mods, key)
  end
  return fn, cond
end

InWebsiteHotkeyInfoChain = {}
InWinHotkeyInfoChain = {}
local function wrapInfoChain(appObject, mods, key, message, condition)
  local cond, windowFilter, mode, websiteFilter
  if type(condition) == 'table' then
    cond = condition.condition
    windowFilter = condition.windowFilter
    mode = condition.mode
    websiteFilter = condition.websiteFilter
  else
    cond = condition
  end
  if windowFilter ~= nil then
    local bid = appObject:bundleID()
    if InWinHotkeyInfoChain[bid] == nil then InWinHotkeyInfoChain[bid] = {} end
    local hkIdx = hotkeyIdx(mods, key)
    if mode == 1 then
      local prevHotkeyInfo = InWinHotkeyInfoChain[bid][hkIdx]
      InWinHotkeyInfoChain[bid][hkIdx] = {
        condition = cond,
        message = message,
        previous = prevHotkeyInfo
      }
    end
  elseif websiteFilter ~= nil then
    local hkIdx = hotkeyIdx(mods, key)
    local prevWebsiteHotkeyInfo = InWebsiteHotkeyInfoChain[hkIdx]
    InWebsiteHotkeyInfoChain[hkIdx] = {
      condition = cond,
      message = message,
      previous = prevWebsiteHotkeyInfo
    }
  end
end

-- multiple website-specified hotkeys may share a common keybinding
-- they are cached in a linked list.
-- each website filter will be tested until one matched target tab
local function inAppHotKeysWrapper(appObject, mods, key, message, mode, fn, cond, websiteFilter)
  fn, cond = WrapCondition(appObject, mods, key, fn,
                           { condition = cond, websiteFilter = websiteFilter, mode = mode })
  if websiteFilter ~= nil then
    local hkIdx = hotkeyIdx(mods, key)
    if prevWebsiteCallbacks[hkIdx] == nil then prevWebsiteCallbacks[hkIdx] = { nil, nil } end
    prevWebsiteCallbacks[hkIdx][mode] = fn
  end
  wrapInfoChain(nil, mods, key, message, { condition = cond, websiteFilter = websiteFilter })
  return fn, cond
end

local callBackExecuting
function AppBind(appObject, mods, key, message, pressedfn, repeatedfn, cond, websiteFilter, ...)
  local newCond
  pressedfn, newCond = inAppHotKeysWrapper(appObject, mods, key, message,
                                           KEY_MODE.PRESS, pressedfn, cond, websiteFilter)
  if repeatedfn == nil and (cond ~= nil or websiteFilter ~= nil) then
    repeatedfn = function() end
  end
  if repeatedfn ~= nil then
    repeatedfn = inAppHotKeysWrapper(appObject, mods, key, message,
                                     KEY_MODE.REPEAT, repeatedfn, cond, websiteFilter)
  end
  if cond ~= nil then
    -- in current version of Hammerspoon, if a callback lasts kind of too long,
    -- keeping pressing a hotkey may lead to unexpected repeated triggering of callback function
    -- a workaround is to check if callback function is executing, if so, do nothing
    -- note that this workaround may not work when the callback lasts really too long
    local oldFn = pressedfn
    pressedfn = function()
      if callBackExecuting then return end
      hs.timer.doAfter(0, function()
        callBackExecuting = true
        oldFn()
        callBackExecuting = false
      end)
    end
  end
  return bindHotkey(mods, key, message, pressedfn, nil, repeatedfn, ...), newCond
end

function AppBindSpec(appObject, spec, ...)
  return AppBind(appObject, spec.mods, spec.key, ...)
end

-- hotkeys for active app
local function registerInAppHotKeys(appObject)
  local bid = appObject:bundleID()
  if appHotKeyCallbacks[bid] == nil then return end
  local keybindings = KeybindingConfigs.hotkeys[bid] or {}
  prevWebsiteCallbacks = {}

  if not inAppHotKeys[bid] then
    inAppHotKeys[bid] = {}
  end
  for hkID, cfg in pairs(appHotKeyCallbacks[bid]) do
    if type(hkID) == 'number' then break end
    if inAppHotKeys[bid][hkID] ~= nil then
      inAppHotKeys[bid][hkID]:enable()
    else
      -- prefer properties specified in configuration file than in code
      local keybinding = keybindings[hkID] or { mods = cfg.mods, key = cfg.key }
      local isBackground = keybinding.background ~= nil and keybinding.background or cfg.background
      local isForWindow = keybinding.windowFilter ~= nil or cfg.windowFilter ~= nil
      local bindable = function()
        return cfg.bindCondition == nil or cfg.bindCondition(appObject)
      end
      if not isBackground and not isForWindow and bindable() then
        local msg = type(cfg.message) == 'string' and cfg.message or cfg.message(appObject)
        if msg ~= nil then
          local repeatable = keybinding.repeatable ~= nil and keybinding.repeatable or cfg.repeatable
          local repeatedfn = repeatable and cfg.fn or nil
          local websiteFilter = keybinding.websiteFilter or cfg.websiteFilter
          local hotkey, cond = AppBindSpec(appObject, keybinding, msg,
                                           cfg.fn, repeatedfn, cfg.condition, websiteFilter)
          hotkey.kind = HK.IN_APP
          if websiteFilter ~= nil then hotkey.subkind = HK.IN_APP_.WEBSITE
          else hotkey.condition = cond end
          hotkey.deleteOnDisable = cfg.deleteOnDisable
          inAppHotKeys[bid][hkID] = hotkey
        end
      end
    end
  end
end

local function unregisterInAppHotKeys(bid, delete)
  if appHotKeyCallbacks[bid] == nil then return end

  if delete then
    for _, hotkey in pairs(inAppHotKeys[bid]) do
      hotkey:delete()
    end
    inAppHotKeys[bid] = nil
  else
    local allDeleted = true
    for hkID, hotkey in pairs(inAppHotKeys[bid]) do
      hotkey:disable()
      if hotkey.deleteOnDisable then
        hotkey:delete()
        inAppHotKeys[bid][hkID] = nil
      else
        allDeleted = false
      end
    end
    if allDeleted then
      inAppHotKeys[bid] = nil
    end
  end
end

-- multiple window-specified hotkeys may share a common keybinding
-- they are cached in a linked list.
-- each window filter will be tested until one matched target window
local function inWinHotKeysWrapper(appObject, mods, key, message, mode, fn, windowFilter, cond)
  fn, cond = WrapCondition(appObject, mods, key, fn,
                           { condition = cond, windowFilter = windowFilter, mode = mode })
  if windowFilter ~= nil then
    local bid = appObject:bundleID()
    if prevWindowCallbacks[bid] == nil then prevWindowCallbacks[bid] = {} end
    local hkIdx = hotkeyIdx(mods, key)
    if prevWindowCallbacks[bid][hkIdx] == nil then prevWindowCallbacks[bid][hkIdx] = { nil, nil } end
    prevWindowCallbacks[bid][hkIdx][mode] = fn
  end
  wrapInfoChain(appObject, mods, key, message,
                { condition = cond, windowFilter = windowFilter, mode = mode })
  return fn
end

function WinBind(appObject, mods, key, message, pressedfn, repeatedfn, windowFilter, cond, ...)
  pressedfn = inWinHotKeysWrapper(appObject, mods, key, message,
                                  KEY_MODE.PRESS, pressedfn, windowFilter, cond)
  if repeatedfn == nil then
    repeatedfn = function() end
  end
  repeatedfn = inWinHotKeysWrapper(appObject, mods, key, message,
                                   KEY_MODE.REPEAT, repeatedfn, windowFilter, cond)
  return bindHotkey(mods, key, message, pressedfn, nil, repeatedfn, ...)
end

function WinBindSpec(appObject, spec, ...)
  return WinBind(appObject, spec.mods, spec.key, ...)
end

-- hotkeys for focused window of active app
local function registerInWinHotKeys(appObject)
  local bid = appObject:bundleID()
  if appHotKeyCallbacks[bid] == nil then return end
  local keybindings = KeybindingConfigs.hotkeys[bid] or {}

  if not inWinHotKeys[bid] then
    inWinHotKeys[bid] = {}
  end
  for hkID, cfg in pairs(appHotKeyCallbacks[bid]) do
    if inWinHotKeys[bid][hkID] == nil then
      -- prefer properties specified in configuration file than in code
      local keybinding = keybindings[hkID] or { mods = cfg.mods, key = cfg.key }
      local isForWindow = keybinding.windowFilter ~= nil or cfg.windowFilter ~= nil
      local isBackground = keybinding.background ~= nil and keybinding.background or cfg.background
      local bindable = function()
        return cfg.bindCondition == nil or cfg.bindCondition(appObject)
      end
      if isForWindow and not isBackground and bindable() then  -- only consider windows of active app
        local msg = type(cfg.message) == 'string' and cfg.message or cfg.message(appObject)
        if msg ~= nil then
          local repeatable = keybinding.repeatable ~= nil and keybinding.repeatable or cfg.repeatable
          local repeatedFn = repeatable and cfg.fn or nil
          local windowFilter = keybinding.windowFilter or cfg.windowFilter
          local hotkey = WinBindSpec(appObject, keybinding, msg, cfg.fn, repeatedFn,
                                     windowFilter, cfg.condition)
          hotkey.kind = HK.IN_APP
          hotkey.subkind = HK.IN_APP_.WINDOW
          hotkey.deleteOnDisable = cfg.deleteOnDisable
          inWinHotKeys[bid][hkID] = hotkey
        end
      end
    else
      inWinHotKeys[bid][hkID]:enable()
    end
  end
end

local function unregisterInWinHotKeys(bid, delete)
  if appHotKeyCallbacks[bid] == nil or inWinHotKeys[bid] == nil then return end

  local hasDeleteOnDisable = hs.fnutils.some(inWinHotKeys[bid], function(_, hotkey)
    return hotkey.deleteOnDisable
  end)
  if delete or hasDeleteOnDisable then
    for _, hotkey in pairs(inWinHotKeys[bid]) do
      hotkey:delete()
    end
    inWinHotKeys[bid] = nil
    prevWindowCallbacks[bid] = nil
    InWinHotkeyInfoChain[bid] = nil
  else
    for _, hotkey in pairs(inWinHotKeys[bid]) do
      hotkey:disable()
    end
  end
end

-- check if a window filter is the same as another
-- if a value is a list, the order of elements matters
local function sameFilter(a, b)
  if type(a) ~= "table" then return a == b end
  if a == b then return true end
  for k, av in pairs(a) do
    local bv = b[k]
    if type(av) == 'table' then
      if type(bv) ~= 'table' then return false end
      for i=1,#av do
        if av[i].equals then
          if not av[i]:equals(bv[i]) then return false end
        else
          if av[i] ~= bv[i] then return false end
        end
      end
    else
      if av.equals then
        if not av:equals(bv) then return false end
      else
        if av ~= bv then return false end
      end
    end
  end
  for k, _ in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

-- hotkeys for frontmost window belonging to unactivated app
local inWinOfUnactivatedAppHotKeys = {}
local inWinOfUnactivatedAppWatchers = {}
local function inWinOfUnactivatedAppWatcherEnableCallback(bid, filter, winObj)
  if inWinOfUnactivatedAppHotKeys[bid] == nil then
    inWinOfUnactivatedAppHotKeys[bid] = {}
  end
  for hkID, cfg in pairs(appHotKeyCallbacks[bid]) do
    local appObject = findApplication(bid)
    local filterCfg = get(KeybindingConfigs.hotkeys[bid], hkID) or cfg
    local isBackground = filterCfg.background ~= nil and filterCfg.background or cfg.background
    local windowFilter = filterCfg.windowFilter or cfg.windowFilter
    local isForWindow = windowFilter ~= nil
    local bindable = function()
      return cfg.bindCondition == nil or cfg.bindCondition(appObject)
    end
    if isForWindow and isBackground and bindable() and sameFilter(windowFilter, filter) then
      local msg = type(cfg.message) == 'string' and cfg.message or cfg.message(appObject)
      if msg ~= nil then
        local keybinding = get(KeybindingConfigs.hotkeys[bid], hkID) or cfg
        local repeatable = keybinding.repeatable ~= nil and keybinding.repeatable or cfg.repeatable
        local cond = resendToFrontmostWindow()
        local wrapper = function(func)
          return function()
            if cond(winObj) then
              func(winObj)
            else
              selectMenuItemOrKeyStroke(hs.window.frontmostWindow():application(), keybinding.mods, keybinding.key)
            end
          end
        end
        local fn = wrapper(cfg.fn)
        local repeatedFn = wrapper(repeatable and cfg.fn or function() end)
        local hotkey = bindHotkeySpec(keybinding, msg, fn, nil, repeatedFn)
        hotkey.kind = HK.IN_WIN
        hotkey.condition = hs.fnutils.partial(cond, winObj)
        table.insert(inWinOfUnactivatedAppHotKeys[bid], hotkey)
      end
    end
  end
end
local function registerSingleWinFilterForDaemonApp(appObject, filter)
  local bid = appObject:bundleID()
  if filter.allowSheet or filter.allowPopover or bid == "com.tencent.LemonMonitor" then
    local appUIObj = hs.axuielement.applicationElement(appObject)
    local observer = hs.axuielement.observer.new(appObject:pid())
    observer:addWatcher(
      appUIObj,
      hs.axuielement.observer.notifications.focusedWindowChanged
    )
    observer:callback(function(observer, element, notification)
      inWinOfUnactivatedAppWatcherEnableCallback(bid, filter, element)
      local closeObserver = hs.axuielement.observer.new(appObject:pid())
      closeObserver:addWatcher(
        element,
        hs.axuielement.observer.notifications.uIElementDestroyed
      )
      closeObserver:callback(function(obs)
        if inWinOfUnactivatedAppHotKeys[bid] ~= nil then -- fix weird bug
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
        obs:stop()
        obs = nil
      end)
      closeObserver:start()
    end)
    observer:start()
    inWinOfUnactivatedAppWatchers[bid][filter] = { observer }
    return
  end
  local filterEnable = hs.window.filter.new(false):setAppFilter(appObject:name(), filter):subscribe(
      {hs.window.filter.windowCreated, hs.window.filter.windowFocused},
      hs.fnutils.partial(inWinOfUnactivatedAppWatcherEnableCallback, bid, filter)
  )
  local filterDisable = hs.window.filter.new(false):setAppFilter(appObject:name(), filter):subscribe(
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
  for hkID, cfg in pairs(appConfig) do
    local keybinding = get(KeybindingConfigs.hotkeys[bid], hkID) or {}
    local isForWindow = keybinding.windowFilter ~= nil or cfg.windowFilter ~= nil
    local isBackground = keybinding.background ~= nil and keybinding.background or cfg.background
    local bindable = function()
      return cfg.bindCondition == nil or cfg.bindCondition(appObject)
    end
    if isForWindow and isBackground and bindable() then
      if inWinOfUnactivatedAppWatchers[bid] == nil then
        if inWinOfUnactivatedAppWatchers[bid] == nil then
          inWinOfUnactivatedAppWatchers[bid] = {}
        end
        local windowFilter = keybinding.windowFilter or cfg.windowFilter
        if #hs.fnutils.filter(inWinOfUnactivatedAppWatchers[bid],
            function(f) return sameFilter(f, windowFilter) end) == 0 then
          -- a window filter can be shared by multiple hotkeys
          registerSingleWinFilterForDaemonApp(appObject, windowFilter)
        end
      end
    end
  end
end


-- ## function utilities for process management on app switching

-- for apps whose launching can be detected by Hammerspoon
local processesOnLaunch = {}
-- for apps that launch silently
local processesOnLaunchMonitored = {}
local hasLaunched = {}
local appsLaunchSilently = applicationConfigs.launchSilently or {}
local function execOnLaunch(bundleID, action, onlyFirstTime)
  if hs.fnutils.contains(appsLaunchSilently, bundleID) then
    if processesOnLaunchMonitored[bundleID] == nil then
      processesOnLaunchMonitored[bundleID] = {}
    end
  else
    if processesOnLaunch[bundleID] == nil then
      processesOnLaunch[bundleID] = {}
    end
  end

  if onlyFirstTime then
    local idx
    if hs.fnutils.contains(appsLaunchSilently, bundleID) then
      idx = #processesOnLaunchMonitored[bundleID] + 1
    else
      idx = #processesOnLaunch[bundleID] + 1
    end
    local oldAction = action
    action = function(appObject)
      oldAction(appObject)
      table.remove(processesOnLaunch[bundleID], idx)
    end
  end

  if hs.fnutils.contains(appsLaunchSilently, bundleID) then
    table.insert(processesOnLaunchMonitored[bundleID], action)
    if ExtraAppLaunchWatcher == nil then
      ExtraAppLaunchWatcher = hs.timer.new(1, function()
        for bid, processes in pairs(processesOnLaunchMonitored) do
          local appObject = findApplication(bid)
          if hasLaunched[bid] == false and appObject ~= nil then
            for _, proc in ipairs(processes) do
              proc(appObject)
            end
          end
          hasLaunched[bid] = appObject ~= nil
        end
      end, true):start()
    end
  else
    table.insert(processesOnLaunch[bundleID], action)
  end
end

local processesOnActivated = {}
local function execOnActivated(bundleID, action)
  if processesOnActivated[bundleID] == nil then
    processesOnActivated[bundleID] = {}
  end
  table.insert(processesOnActivated[bundleID], action)
end

local observersStopOnDeactivated = {}
local function stopOnDeactivated(bundleID, observer, action)
  if observersStopOnDeactivated[bundleID] == nil then
    observersStopOnDeactivated[bundleID] = {}
  end
  table.insert(observersStopOnDeactivated[bundleID], { observer, action })
end

local observersStopOnQuit = {}
local function stopOnQuit(bundleID, observer, action)
  if observersStopOnQuit[bundleID] == nil then
    observersStopOnQuit[bundleID] = {}
  end
  table.insert(observersStopOnQuit[bundleID], { observer, action })
end

-- register hotkeys for background apps
for bid, appConfig in pairs(appHotKeyCallbacks) do
  registerRunningAppHotKeys(bid)
  local keybindings = KeybindingConfigs.hotkeys[bid] or {}
  for hkID, cfg in pairs(appConfig) do
    local keybinding = keybindings[hkID] or {}
    local isBackground = keybinding.background ~= nil and keybinding.background or cfg.background
    local isPersistent = keybinding.persist ~= nil and keybinding.persist or cfg.persist
    local isForWindow = keybinding.windowFilter ~= nil or cfg.windowFilter ~= nil
    if type(cfg) ~= 'number' and not isForWindow and isBackground and not isPersistent then
      execOnLaunch(bid, hs.fnutils.partial(registerRunningAppHotKeys, bid))
      break
    end
  end
end

-- register hotkeys for active app
registerInAppHotKeys(hs.application.frontmostApplication())

-- register hotkeys for focused window of active app
registerInWinHotKeys(hs.application.frontmostApplication())

-- register hotkeys for frontmost window belonging to unactivated app
local frontWin = hs.window.frontmostWindow()
if frontWin ~= nil then
  local frontWinAppBid = frontWin:application():bundleID()
  if inWinOfUnactivatedAppWatchers[frontWinAppBid] ~= nil then
    for filter, _ in pairs(inWinOfUnactivatedAppWatchers[frontWinAppBid]) do
      local filterEnable = hs.window.filter.new(false):setAppFilter(frontWin:application():title(), filter)
      if filterEnable:isWindowAllowed(frontWin) then
        inWinOfUnactivatedAppWatcherEnableCallback(frontWinAppBid, filter, frontWin)
      end
    end
  end
end

-- register watchers for frontmost window belonging to unactivated app
for bid, appConfig in pairs(appHotKeyCallbacks) do
  local appObject = findApplication(bid)
  if appObject ~= nil then
    registerWinFiltersForDaemonApp(appObject, appConfig)
  else
    local keybindings = KeybindingConfigs.hotkeys[bid] or {}
    for hkID, cfg in pairs(appConfig) do
      local keybinding = keybindings[hkID] or {}
      local isForWindow = keybinding.windowFilter ~= nil or cfg.windowFilter ~= nil
      local isBackground = keybinding.background ~= nil and keybinding.background or cfg.background
      if type(cfg) ~= 'number' and isForWindow and isBackground then
        execOnLaunch(bid, function(appObject)
          registerWinFiltersForDaemonApp(appObject, appConfig)
        end)
      end
    end
  end
end


-- ## hotkeys or configs shared by multiple apps

-- basically aims to remap ctrl+` to shift+ctrl+tab to make it more convenient for fingers
local remapPreviousTabHotkey
local function remapPreviousTab(appObject)
  if remapPreviousTabHotkey then
    remapPreviousTabHotkey:delete()
    remapPreviousTabHotkey = nil
  end
  local bundleID = appObject:bundleID()
  local spec = get(KeybindingConfigs.hotkeys.appCommon, "remapPreviousTab")
  local specApp = get(appHotKeyCallbacks[bundleID], "remapPreviousTab")
  if specApp ~= nil or spec == nil or hs.fnutils.contains(spec.excluded or {}, bundleID) then
    return
  end
  local menuItemPath = findMenuItemByKeyBinding(appObject, '⇧⌃', '⇥')
  if menuItemPath ~= nil then
    local fn = function()
      appObject:selectMenuItem(menuItemPath)
    end
    local cond = function()
      local menuItemCond = appObject:findMenuItem(menuItemPath)
      return menuItemCond ~= nil and menuItemCond.enabled
    end
    remapPreviousTabHotkey, cond = AppBindSpec(appObject, spec, menuItemPath[#menuItemPath], fn, fn, cond)
    remapPreviousTabHotkey.condition = cond
    remapPreviousTabHotkey.kind = HK.IN_APP
    remapPreviousTabHotkey.subkind = HK.IN_APP_.APP
  end
end

local frontmostApplication = hs.application.frontmostApplication()
remapPreviousTab(frontmostApplication)

-- register hotkey to open recent when it is available
local openRecentHotkey
local function registerOpenRecent(appObject)
  if openRecentHotkey then
    openRecentHotkey:delete()
    openRecentHotkey = nil
  end
  local bundleID = appObject:bundleID()
  local spec = get(KeybindingConfigs.hotkeys.appCommon, "openRecent")
  local specApp = get(appHotKeyCallbacks[bundleID], "openRecent")
  if specApp ~= nil or spec == nil or hs.fnutils.contains(spec.excluded or {}, bundleID) then
    return
  end

  local menuItems = getMenuItems(appObject)
  local localizedFile = localizedMenuBarItem("File", appObject:bundleID())
  if #hs.fnutils.ifilter(menuItems, function(v) return v.AXTitle == localizedFile end) == 0 then
    return
  end
  local menuItem, menuItemPath = findMenuItem(appObject, { "File",  "Open Recent" })
  if menuItem ~= nil then
    local fn = function() showMenuItem(menuItemPath, appObject) end
    local cond = function()
      local menuItemCond = appObject:findMenuItem(menuItemPath)
      return menuItemCond ~= nil and menuItemCond.enabled
    end
    openRecentHotkey, cond = AppBindSpec(appObject, spec, menuItemPath[2], fn, nil, cond)
    openRecentHotkey.condition = cond
    openRecentHotkey.kind = HK.IN_APP
    openRecentHotkey.subkind = HK.IN_APP_.APP
  end
end
registerOpenRecent(frontmostApplication)

-- bind hotkeys for open or save panel that are similar in `Finder`
-- & hotkeys to confirm delete or save
local openSavePanelHotkeys = {}

-- specialized for `WPS Office`
local function WPSCloseDialog(winUIObj)
  local btnNames = {
    closeDoNotSave = "不保存",
    closeCancel = "取消",
    closeSave = "保存"
  }
  local bundleID = "com.kingsoft.wpsoffice.mac"
  local appConfig = appHotKeyCallbacks[bundleID]
  if winUIObj.AXSubrole == "AXDialog" then
    local buttons = winUIObj:childrenWithRole("AXButton")
    for _, button in ipairs(buttons) do
      for hkID, btnName in pairs(btnNames) do
        if button.AXTitle == btnName then
          local spec = get(KeybindingConfigs.hotkeys, bundleID, hkID) or appConfig[hkID]
          if spec ~= nil then
            local fn, cond = WrapCondition(findApplication(bundleID), spec.mods, spec.key, function()
              button:performAction("AXPress")
            end)
            local hotkey = bindHotkeySpec(spec, btnName, fn)
            hotkey.kind = HK.IN_APP
            hotkey.subkind = HK.IN_APP_.WINDOW
            hotkey.condition = cond
            table.insert(openSavePanelHotkeys, hotkey)
          end
        end
      end
    end
  end
end

local function registerForOpenSavePanel(appObject)
  if appObject:bundleID() == "com.apple.finder" then return end
  local appUIObj = hs.axuielement.applicationElement(appObject)
  if not appUIObj:isValid() then
    hs.timer.doAfter(0.1, function() registerForOpenSavePanel(appObject) end)
    return
  end

  local getUIObj = function(winUIObj)
    local windowIdent = winUIObj:attributeValue("AXIdentifier")
    local dontSaveButton, sidebarCells = nil, {}
    if windowIdent == "save-panel" then
      for _, button in ipairs(winUIObj:childrenWithRole("AXButton")) do
        if button.AXIdentifier == "DontSaveButton" then
          dontSaveButton = button
          break
        end
      end
    end
    if windowIdent == "open-panel" or windowIdent == "save-panel" then
      local outlineUIObj = getAXChildren(winUIObj,
          "AXSplitGroup", 1, "AXScrollArea", 1, "AXOutline", 1)
      if outlineUIObj ~= nil then
        for _, rowUIObj in ipairs(outlineUIObj:childrenWithRole("AXRow")) do
          if rowUIObj.AXChildren == nil then hs.timer.usleep(0.3 * 1000000) end
          table.insert(sidebarCells, rowUIObj.AXChildren[1])
        end
      end
    end
    return dontSaveButton, sidebarCells
  end

  local actionFunc = function(winUIObj)
    local dontSaveButton, sidebarCells = getUIObj(winUIObj)
    local header
    local i = 1
    for _, cell in ipairs(sidebarCells) do
      if i > 10 then break end
      if cell:childrenWithRole("AXStaticText")[1].AXIdentifier ~= nil then
        header = cell:childrenWithRole("AXStaticText")[1].AXValue
      else
        local suffix
        if i == 1 then suffix = "st"
        elseif i == 2 then suffix = "nd"
        elseif i == 3 then suffix = "rd"
        else suffix = "th" end
        local hkID = "open" .. tostring(i) .. suffix .. "SidebarItem"
        local spec = get(KeybindingConfigs.hotkeys["com.apple.finder"], hkID)
        if spec ~= nil then
          local folder = cell:childrenWithRole("AXStaticText")[1].AXValue
          local fn, cond = WrapCondition(appObject, spec.mods, spec.key, function()
            cell:performAction("AXOpen")
          end)
          local hotkey = bindHotkeySpec(spec, header .. ' > ' .. folder, fn)
          hotkey.kind = HK.IN_APP
          hotkey.subkind = HK.IN_APP_.WINDOW
          hotkey.condition = cond
          table.insert(openSavePanelHotkeys, hotkey)
          i = i + 1
        end
      end
    end
    if dontSaveButton ~= nil then
      local spec = get(KeybindingConfigs.hotkeys.appCommon, "confirmDelete")
      if spec ~= nil then
        local fn, cond = WrapCondition(appObject, spec.mods, spec.key, function()
          local action = dontSaveButton:actionNames()[1]
          dontSaveButton:performAction(action)
        end)
        local hotkey = bindHotkeySpec(spec, dontSaveButton.AXTitle, fn)
        hotkey.kind = HK.IN_APP
        hotkey.subkind = HK.IN_APP_.WINDOW
        hotkey.condition = cond
        table.insert(openSavePanelHotkeys, hotkey)
      end
    end
  end
  if appObject:focusedWindow() ~= nil then
    actionFunc(hs.axuielement.windowElement(appObject:focusedWindow()))
  end

  local observer = hs.axuielement.observer.new(appObject:pid())
  observer:addWatcher(
    hs.axuielement.applicationElement(appObject),
    hs.axuielement.observer.notifications.focusedWindowChanged
  )
  observer:callback(function(observer, element, notifications)
    for _, hotkey in ipairs(openSavePanelHotkeys) do
      hotkey:delete()
    end
    openSavePanelHotkeys = {}
    if hs.application.frontmostApplication():bundleID()
        == "com.kingsoft.wpsoffice.mac" then
      WPSCloseDialog(element)
    else
      actionFunc(element)
    end
  end)
  observer:start()
  stopOnDeactivated(appObject:bundleID(), observer, function()
    for _, hotkey in ipairs(openSavePanelHotkeys) do
      hotkey:delete()
    end
    openSavePanelHotkeys = {}
  end)
end
registerForOpenSavePanel(frontmostApplication)

-- bind `alt+?` hotkeys to select left menu bar items
AltMenuBarItemHotkeys = {}

local function bindAltMenu(appObject, mods, key, message, fn)
  fn = showMenuItemWrapper(fn)
  local hotkey, cond = AppBind(appObject, mods, key, message, fn)
  hotkey.kind = HK.IN_APP
  hotkey.subkind = HK.IN_APP_.MENU
  hotkey.condition = cond
  return hotkey
end

local function searchHotkeyByNth(itemTitles, alreadySetHotkeys, index)
  local notSetItems = {}
  for _, title in pairs(itemTitles) do
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

local function altMenuBarItem(appObject)
  -- delete previous hotkeys
  for _, hotkeyObject in ipairs(AltMenuBarItemHotkeys) do
    hotkeyObject:delete()
  end
  AltMenuBarItemHotkeys = {}

  if appObject:bundleID() == nil then return end
  -- check whether called by window filter (possibly with delay)
  if appObject:bundleID() ~= hs.application.frontmostApplication():bundleID() then
    return
  end

  local enableIndex = get(KeybindingConfigs.hotkeys.menuBarItems, "enableIndex")
  local enableLetter = get(KeybindingConfigs.hotkeys.menuBarItems, "enableLetter")
  if enableIndex == nil then enableIndex = false end
  if enableLetter == nil then enableLetter = true end
  local excludedForLetter = get(KeybindingConfigs.hotkeys.menuBarItems, 'excludedForLetter')
  if excludedForLetter ~= nil and hs.fnutils.contains(excludedForLetter,
                                                      appObject:bundleID()) then
    enableLetter = false
  end
  if enableIndex == false and enableLetter == false then return end

  if appObject:bundleID() == "com.microsoft.VSCode"
      or appObject:bundleID() == "com.google.Chrome" then
    hs.timer.usleep(0.5 * 100000)
  end
  local menuBarItemTitles
  if appObject:bundleID() == "com.mathworks.matlab" and appObject:focusedWindow() ~= nil then
    local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
    if #winUIObj:childrenWithRole("AXMenuBar") > 0 then
      local menuObj = winUIObj:childrenWithRole("AXMenuBar")[1]:childrenWithRole("AXMenu")
      menuBarItemTitles = hs.fnutils.map(menuObj, function(item)
        return item:attributeValue("AXTitle"):match("(.-)%s")
      end)
      table.insert(menuBarItemTitles, 1, "MATLAB")
    end
  end
  local menuBarItemActualIndices = {}
  if menuBarItemTitles == nil then
    local menuItems = getMenuItems(appObject)
    if menuItems == nil then return end
    local ignoredItems = {}
    menuBarItemTitles = {}
    for i, item in ipairs(menuItems) do
      if ignoredItems[item.AXTitle] then
        menuBarItemActualIndices[item.AXTitle] = i + 1
      end
      if i == 1 or item.AXChildren == nil then
        ignoredItems[item.AXTitle] = true
      end
      if item.AXChildren ~= nil then
        table.insert(menuBarItemTitles, item.AXTitle)
      end
    end
    menuBarItemTitles = hs.fnutils.filter(menuBarItemTitles, function(item)
      return item ~= nil and item ~= ""
    end)
  end
  if menuBarItemTitles == nil or #menuBarItemTitles == 0 then return end

  local clickMenuCallback = function(title)
    local index = menuBarItemActualIndices[title]
    if index then
      local appUIObj = hs.axuielement.applicationElement(appObject)
      local menubarItem = getAXChildren(appUIObj, "AXMenuBar", 1, "AXMenuBarItem", index)
      if menubarItem then
        menubarItem:performAction("AXPress")
      end
    else
      appObject:selectMenuItem({ title })
    end
  end

  -- by initial or otherwise second letter in title
  local alreadySetHotkeys = {}
  if enableLetter == true then
    local itemTitles = {}
    for i=2,#menuBarItemTitles do
      local title, letter = menuBarItemTitles[i]:match("(.-)%s*%((.-)%)")
      if letter then
        alreadySetHotkeys[letter] = {menuBarItemTitles[i], title}
      else
        table.insert(itemTitles, menuBarItemTitles[i])
      end
    end

    -- process localized titles
    itemTitles = delocalizeMenuBarItems(itemTitles, appObject:bundleID())

    local notSetItems = {}
    for _, title in ipairs(itemTitles) do
      if hs.fnutils.contains({ 'File', 'Edit', 'View', 'Window', 'Help' }, title[2]) then
        local hotkey = string.sub(title[2], 1, 1)
        alreadySetHotkeys[hotkey] = title[1]
      else
        table.insert(notSetItems, title)
      end
    end
    notSetItems, alreadySetHotkeys = searchHotkeyByNth(notSetItems, alreadySetHotkeys, 1)
    -- if there are still items not set, set them by first letter of second word
    notSetItems, alreadySetHotkeys = searchHotkeyByNth(notSetItems, alreadySetHotkeys, nil)
    -- if there are still items not set, set them by second letter
    notSetItems, alreadySetHotkeys = searchHotkeyByNth(notSetItems, alreadySetHotkeys, 2)
    -- if there are still items not set, set them by third letter
    notSetItems, alreadySetHotkeys = searchHotkeyByNth(notSetItems, alreadySetHotkeys, 3)
    -- if there are still items not set, set them by fourth letter
    searchHotkeyByNth(notSetItems, alreadySetHotkeys, 4)
    local invMap = {}
    for key, title in pairs(alreadySetHotkeys) do
      local menuBarItem = type(title) == 'table' and title[1] or title
      local msg = type(title) == 'table' and title[2] or title
      invMap[menuBarItem] = {key, msg}
    end
    for i=2,#menuBarItemTitles do
      local spec = invMap[menuBarItemTitles[i]]
      if spec ~= nil then
        local fn
        if appObject:bundleID() == "com.mathworks.matlab" and #menuBarItemTitles > 3 then
          fn = function()
            local winUIObj = hs.axuielement.windowElement(appObject:focusedWindow())
            local menuObj = winUIObj:childrenWithRole("AXMenuBar")[1]:childrenWithRole("AXMenu")
            local targetMenuObj = hs.fnutils.find(menuObj, function(item)
              return item:attributeValue("AXTitle"):match("(.-)%s") == spec[2]
            end)
            targetMenuObj:performAction("AXPick")
          end
        else
          fn = hs.fnutils.partial(clickMenuCallback, menuBarItemTitles[i])
        end
        local hotkeyObject = bindAltMenu(appObject, "⌥", spec[1], spec[2], fn)
        table.insert(AltMenuBarItemHotkeys, hotkeyObject)
      end
    end
  end

  -- by index
  if enableIndex == true then
    local itemTitles = hs.fnutils.copy(menuBarItemTitles)

    local hotkeyObject = bindAltMenu(appObject, "⌥", "`", itemTitles[1] .. " Menu",
        function() appObject:selectMenuItem({itemTitles[1]}) end)
    hotkeyObject.subkind = 0
    table.insert(AltMenuBarItemHotkeys, hotkeyObject)
    local maxMenuBarItemHotkey = #itemTitles > 11 and 10 or (#itemTitles - 1)
    for i=1,maxMenuBarItemHotkey do
      hotkeyObject = bindAltMenu(appObject, "⌥", tostring(i % 10), itemTitles[i+1] .. " Menu",
          hs.fnutils.partial(clickMenuCallback, itemTitles[i+1]))
      table.insert(AltMenuBarItemHotkeys, hotkeyObject)
    end
  end
end
altMenuBarItem(frontmostApplication)

-- some apps may change their menu bar items irregularly
local appswatchMenuBarItems = get(applicationConfigs.menuBarItemsMayChange, 'basic') or {}
local appsMenuBarItemsWatchers = {}

local getMenuBarItemTitlesString = function(appObject)
  local menuItems = getMenuItems(appObject)
  if menuItems == nil or #menuItems == 0 then return "" end
  local menuBarItemTitles = {}
  for _, item in ipairs(menuItems) do
    table.insert(menuBarItemTitles, item.AXTitle)
  end
  return table.concat(menuBarItemTitles, "|")
end

local function watchMenuBarItems(appObject)
  local menuBarItemTitlesString = getMenuBarItemTitlesString(appObject)
  if appsMenuBarItemsWatchers[appObject:bundleID()] == nil then
    local watcher = hs.timer.new(1, function()
      local newMenuBarItemTitlesString = getMenuBarItemTitlesString(appObject)
      if newMenuBarItemTitlesString ~= appsMenuBarItemsWatchers[appObject:bundleID()][2] then
        appsMenuBarItemsWatchers[appObject:bundleID()][2] = newMenuBarItemTitlesString
        altMenuBarItem(appObject)
      end
    end)
    appsMenuBarItemsWatchers[appObject:bundleID()] = { watcher, menuBarItemTitlesString }
  else
    appsMenuBarItemsWatchers[appObject:bundleID()][2] = menuBarItemTitlesString
  end
  appsMenuBarItemsWatchers[appObject:bundleID()][1]:start()
  stopOnDeactivated(appObject:bundleID(), appsMenuBarItemsWatchers[appObject:bundleID()][1],
      function(bundleID) appsMenuBarItemsWatchers[bundleID][2] = nil end)
end

-- some apps may change their menu bar items based on the focused window
local appsMayChangeMenuBar = get(applicationConfigs.menuBarItemsMayChange, 'window') or {}

local function appMenuBarChangeCallback(appObject)
  altMenuBarItem(appObject)
  local menuBarItemStr = getMenuBarItemTitlesString(appObject)
  hs.timer.doAfter(1, function()
    if hs.application.frontmostApplication():bundleID() ~= appObject:bundleID() then
      return
    end
    local newMenuBarItemTitlesString = getMenuBarItemTitlesString(appObject)
    if newMenuBarItemTitlesString ~= menuBarItemStr then
      altMenuBarItem(appObject)
    end
  end)
end

local function registerObserverForMenuBarChange(appObject)
  if appObject:bundleID() == nil then return end

  if hs.fnutils.contains(appswatchMenuBarItems, appObject:bundleID()) then
    watchMenuBarItems(appObject)
  end

  if not hs.fnutils.contains(appsMayChangeMenuBar, appObject:bundleID()) then
    return
  end

  local observer, windowFilter
  observer = hs.axuielement.observer.new(appObject:pid())
  observer:addWatcher(
    hs.axuielement.applicationElement(appObject),
    hs.axuielement.observer.notifications.focusedWindowChanged
  )
  observer:addWatcher(
    hs.axuielement.applicationElement(appObject),
    hs.axuielement.observer.notifications.windowMiniaturized
  )
  observer:callback(hs.fnutils.partial(appMenuBarChangeCallback, appObject))
  observer:start()

  windowFilter = hs.window.filter.new(appObject:name())
      :subscribe(hs.window.filter.windowDestroyed,
        function(winObj)
          if winObj == nil or winObj:application() == nil then return end
          appMenuBarChangeCallback(winObj:application())
        end)
  stopOnDeactivated(appObject:bundleID(), observer,
    function()
      if windowFilter ~= nil then
        windowFilter:unsubscribeAll()
        windowFilter = nil
      end
    end)
end
registerObserverForMenuBarChange(frontmostApplication)

-- auto hide or quit apps with no windows (including pseudo windows suck as popover or sheet)
local function processAppWithNoWindows(appObject, quit, delay)
  hs.timer.doAfter(delay or 0, function()
    if #appObject:visibleWindows() == 0
      or (appObject:bundleID() == "com.app.menubarx"
          and #hs.fnutils.filter(appObject:visibleWindows(),
              function(win) return win:title() ~= "" end) == 0) then
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
  end)
end

local appPseudoWindowObservers = {}
local function registerPseudoWindowDestroyWatcher(appObject, roles, windowFilter, quit, delay)
  local observer = appPseudoWindowObservers[appObject:bundleID()]
  local appUIObj = hs.axuielement.applicationElement(appObject)
  if observer ~= nil then observer:start() return end
  observer = hs.axuielement.observer.new(appObject:pid())
  observer:addWatcher(
    appUIObj,
    hs.axuielement.observer.notifications.focusedUIElementChanged
  )
  if windowFilter ~= nil then
    windowFilter = hs.window.filter.new(false):allowApp(appObject:name(), windowFilter)
  end
  local criterion = function(element) return hs.fnutils.contains(roles, element.AXRole) end
  local params = { count = 1, depth = 2 }
  local pseudoWindowObserver
  local observerCallback = function()
    appUIObj:elementSearch(function(msg, results, count)
      if count > 0 then
        if pseudoWindowObserver ~= nil then
          pseudoWindowObserver:stop()
          pseudoWindowObserver = nil
        end
        pseudoWindowObserver = hs.axuielement.observer.new(appObject:pid())
        pseudoWindowObserver:addWatcher(
          results[1],
          hs.axuielement.observer.notifications.uIElementDestroyed
        )
        local pseudoWindowObserverCallback = function()
          appUIObj:elementSearch(function(newMsg, newResults, newCount)
              if newCount == 0 then
                local windows = appObject:visibleWindows()
                if windowFilter ~= nil then
                  windows = hs.fnutils.filter(windows, function(win)
                    return windowFilter:isWindowAllowed(win)
                  end)
                end
                if #windows == 0 then
                  if quit == true then
                    local wFilter = hs.window.filter.new(appObject:name())
                    if #wFilter:getWindows() == 0 then
                      appObject:kill()
                    end
                  else
                    appObject:hide()
                  end
                  pseudoWindowObserver:stop()
                  pseudoWindowObserver = nil
                end
              end
            end,
            criterion, params)
        end
        pseudoWindowObserver:callback(function()
          hs.timer.doAfter(delay or 0, pseudoWindowObserverCallback)
        end)
        pseudoWindowObserver:start()
        stopOnDeactivated(appObject:bundleID(), pseudoWindowObserver)
      end
    end,
    criterion, params)
  end
  observer:callback(observerCallback)
  observer:start()
  appPseudoWindowObservers[appObject:bundleID()] = observer
  stopOnQuit(appObject:bundleID(), observer,
      function(bundleID) appPseudoWindowObservers[bundleID] = nil end)
end

local appsAutoHideWithNoWindowsLoaded = applicationConfigs.autoHideWithNoWindow
local appsAutoQuitWithNoWindowsLoaded = applicationConfigs.autoQuitWithNoWindow
local appsAutoHideWithNoWindows = {}
local appsAutoQuitWithNoWindows = {}
-- account for pseudo windows such as popover or sheet
local appsAutoHideWithNoPseudoWindows = {}
local appsAutoQuitWithNoPseudoWindows = {}
-- some apps may first close a window before create a targeted one, so delay is needed before checking
local appsWithNoWindowsDelay = {}
for _, item in ipairs(appsAutoHideWithNoWindowsLoaded or {}) do
  if type(item) == 'string' then
    appsAutoHideWithNoWindows[item] = true
  else
    for k, v in pairs(item) do
      appsAutoHideWithNoWindows[k] = v
      if v.allowPopover or v.allowSheet then
        appsAutoHideWithNoPseudoWindows[k] = {}
        if v.allowPopover then
          table.insert(appsAutoHideWithNoPseudoWindows[k], "AXPopover")
          appsAutoHideWithNoWindows[k].allowPopover = nil
        end
        if v.allowSheet then
          table.insert(appsAutoHideWithNoPseudoWindows[k], "AXSheet")
          appsAutoHideWithNoWindows[k].allowSheet = nil
        end
      end
      if v.delay then
        appsWithNoWindowsDelay[k] = v.delay
        v.delay = nil
      end
    end
  end
end
for _, item in ipairs(appsAutoQuitWithNoWindowsLoaded or {}) do
  if type(item) == 'string' then
    appsAutoQuitWithNoWindows[item] = true
  else
    for k, v in pairs(item) do
      appsAutoQuitWithNoWindows[k] = v
      if v.allowPopover or v.allowSheet then
        appsAutoQuitWithNoPseudoWindows[k] = {}
        if v.allowPopover then
          table.insert(appsAutoQuitWithNoPseudoWindows[k], "AXPopover")
          appsAutoQuitWithNoWindows[k].allowPopover = nil
        end
        if v.allowSheet then
          table.insert(appsAutoQuitWithNoPseudoWindows[k], "AXSheet")
          appsAutoQuitWithNoWindows[k].allowSheet = nil
        end
      end
      if v.delay then
        appsWithNoWindowsDelay[k] = v.delay
        v.delay = nil
      end
    end
  end
end

local windowFilterAutoHide = hs.window.filter.new(false)
    :setAppFilter("Hammerspoon", true)  -- Hammerspoon overlook itself by default, so add it here
for bundleID, cfg in pairs(appsAutoHideWithNoWindows) do
  local func = function(appObject)
    windowFilterAutoHide:setAppFilter(appObject:name(), cfg)
  end
  local appObject = findApplication(bundleID)
  if appObject ~= nil then
    func(appObject)
  else
    execOnLaunch(bundleID, func, true)
  end
end
windowFilterAutoHide:subscribe(hs.window.filter.windowDestroyed,
  function(winObj)
    if winObj == nil or winObj:application() == nil then return end
    local bundleID = winObj:application():bundleID()
    processAppWithNoWindows(winObj:application(), false, appsWithNoWindowsDelay[bundleID])
  end)

local windowFilterAutoQuit = hs.window.filter.new(false)
for bundleID, cfg in pairs(appsAutoQuitWithNoWindows) do
  local func = function(appObject)
    windowFilterAutoQuit:setAppFilter(appObject:name(), cfg)
  end
  local appObject = findApplication(bundleID)
  if appObject ~= nil then
    func(appObject)
  else
    execOnLaunch(bundleID, func, true)
  end
end
windowFilterAutoQuit:subscribe(hs.window.filter.windowDestroyed,
  function(winObj)
    if winObj == nil or winObj:application() == nil then return end
    local bundleID = winObj:application():bundleID()
    processAppWithNoWindows(winObj:application(), true, appsWithNoWindowsDelay[bundleID])
  end)

-- Hammerspoon only account standard windows, so add watchers for pseudo windows here
for bundleID, rules in pairs(appsAutoHideWithNoPseudoWindows) do
  local func = function(appObject)
    registerPseudoWindowDestroyWatcher(appObject, rules,
        appsAutoHideWithNoWindows[bundleID], false, appsWithNoWindowsDelay[bundleID])
  end
  local appObject = findApplication(bundleID)
  if appObject ~= nil then
    func(appObject)
  else
    execOnLaunch(bundleID, func, true)
  end
end
for bundleID, rules in pairs(appsAutoQuitWithNoPseudoWindows) do
  local func = function(appObject)
    registerPseudoWindowDestroyWatcher(appObject, rules,
        appsAutoHideWithNoWindows[bundleID], true, appsWithNoWindowsDelay[bundleID])
  end
  local appObject = findApplication(bundleID)
  if appObject ~= nil then
    func(appObject)
  else
    execOnLaunch(bundleID, func, true)
  end
end


-- ## configure specific apps

-- ### Mountain Duck
-- connect to servers on launch
local function connectMountainDuckEntries(appObject, connection)
  local script = string.format([[
    tell application "System Events"
      tell first application process whose bundle identifier is "%s"
        set li to menu 1 of last menu bar
  ]], appObject:bundleID())

  if type(connection) == 'string' then
    script = script .. string.format([[
        if exists menu item "%s" of li then
          click menu item 1 of menu 1 of menu item "%s" of li
        end
    ]], connection, connection)
  else
    local fullfilled = connection.condition(appObject)
    if fullfilled == nil then return end
    local connects = connection[connection.locations[fullfilled and 1 or 2]]
    local disconnects = connection[connection.locations[fullfilled and 2 or 1]]
    for _, item in ipairs(connects) do
      script = script .. string.format([[
          if exists menu item "%s" of li then
            click menu item 1 of menu 1 of menu item "%s" of li
          end
      ]], item, item)
    end
    for _, item in ipairs(disconnects) do
      script = script .. string.format([[
          if exists menu item "%s" of li then
            click menu item "%s" of menu 1 of menu item "%s" of li
          end
      ]], item, localizedString('Disconnect', appObject:bundleID()), item)
    end
  end

  script = script .. [[
      end tell
    end tell
  ]]

  hs.osascript.applescript(script)
end
local mountainDuckConfig = applicationConfigs["io.mountainduck"]
if mountainDuckConfig ~= nil and mountainDuckConfig.connections ~= nil then
  for _, connection in ipairs(mountainDuckConfig.connections) do
    if type(connection) == 'table' then
      local shell_command = get(connection, "condition", "shell_command")
      if shell_command ~= nil then
        connection.condition = function()
          local _, _, _, rc = hs.execute(shell_command)
          if rc == 0 then
            return true
          elseif rc == 1 then
            return false
          else
            return nil
          end
        end
      else
        connection.condition = nil
      end
    end
  end
  execOnLaunch("io.mountainduck", function(appObject)
    for _, connection in ipairs(mountainDuckConfig.connections) do
      connectMountainDuckEntries(appObject, connection)
    end
  end)
  local mountainDuckObject = findApplication("io.mountainduck")
  if mountainDuckObject ~= nil then
    for _, connection in ipairs(mountainDuckConfig.connections) do
      connectMountainDuckEntries(mountainDuckObject, connection)
    end
  end
end

-- ## Barrier
-- barrier window may not be focused when it is created, so focus it
if hs.application.pathForBundleID("barrier") ~= nil
    and hs.application.pathForBundleID("barrier") ~= "" then
  local appObject = findApplication("barrier")
  if appObject == nil then
    execOnLaunch("barrier", function(appObject)
      hs.window.filter.new(false):allowApp(appObject:name()):subscribe(
        hs.window.filter.windowCreated, function(winObj) winObj:focus() end
      )
    end)
  else
    hs.window.filter.new(false):allowApp(appObject:name()):subscribe(
      hs.window.filter.windowCreated, function(winObj) winObj:focus() end
    )
  end
end

-- ## remote desktop apps
-- remap modifier keys for specified windows of remote desktop apps
local remoteDesktopsMappingModifiers = get(KeybindingConfigs, 'remoteDesktopModifiers') or {}
local modifiersShort = {
  control = "ctrl",
  option = "alt",
  command = "cmd",
  shift = "shift",
  fn = "fn"
}
for _, rules in pairs(remoteDesktopsMappingModifiers) do
  for _, r in ipairs(rules) do
    local newMap = {}
    for k, v in pairs(r.map) do
      k = modifiersShort[k]
      if k ~= nil then newMap[k] = modifiersShort[v] end
    end
    r.map = newMap
  end
end

local microsoftRemoteDesktopWindowFilter
if hs.application.nameForBundleID("com.microsoft.rdc.macos") == "Windows App" then
  microsoftRemoteDesktopWindowFilter = { rejectTitles = {} }
  local preLocalizeWindowsApp = function ()
    for _, title in ipairs { "Favorites", "Devices", "Apps",
      "Settings", "About", "Device View Options", "App View Options" } do
      local locTitle = "^" .. localizedString(title, "com.microsoft.rdc.macos") .. "$"
      if not hs.fnutils.contains(microsoftRemoteDesktopWindowFilter.rejectTitles, locTitle) then
        table.insert(microsoftRemoteDesktopWindowFilter.rejectTitles, locTitle)
      end
    end
  end
  if findApplication("com.microsoft.rdc.macos") ~= nil then
    preLocalizeWindowsApp()
  end
  execOnActivated("com.microsoft.rdc.macos", preLocalizeWindowsApp)
else
  microsoftRemoteDesktopWindowFilter = {
    rejectTitles = {
      "^Microsoft Remote Desktop$",
      "^Preferences$",
    }
  }
end

local function isDefaultRemoteDesktopWindow(window)
  local bundleID = window:application():bundleID()
  if bundleID == "com.realvnc.vncviewer" then
    local winUIObj = hs.axuielement.windowElement(window)
    return hs.fnutils.find(winUIObj:childrenWithRole("AXButton"),
      function(child) return child.AXHelp == "Session informatioon" end) ~= nil
  elseif bundleID == "com.microsoft.rdc.macos" then
    local wFilter = hs.window.filter.new(false):setAppFilter(
        window:application():name(), microsoftRemoteDesktopWindowFilter)
    local result = wFilter:isWindowAllowed(window)
    if result then
      local winUIObj = hs.axuielement.windowElement(window)
      local title = "Cancel"
      if window:application():name() == "Windows App" then
        title = localizedString(title, "com.microsoft.rdc.macos") or title
      end
      for _, bt in ipairs(winUIObj:childrenWithRole("AXButton")) do
        if bt.AXTitle == title then
          return false
        end
      end
    end
    return result
  end
  return true
end

local function remoteDesktopWindowFilter(appObject)
  local bundleID = appObject:bundleID()
  local rules = remoteDesktopsMappingModifiers[bundleID]
  local winObj = appObject:focusedWindow()
  for _, r in ipairs(rules or {}) do
    local valid = false
    if winObj == nil or winObj:role() == "AXSheet" or winObj:role() == "AXPopover" then
      valid = r.type == 'restore'
    elseif r.condition == nil then
      local isRDW = isDefaultRemoteDesktopWindow(winObj)
      valid = (r.type == 'restore' and not isRDW) or (r.type ~= 'restore' and isRDW)
    else
      if r.condition.windowFilter ~= nil then  -- currently only support window filter
        local wFilter = hs.window.filter.new(false):setAppFilter(appObject:name(), r.condition.windowFilter)
        valid = wFilter:isWindowAllowed(winObj)
      end
    end
    if valid then
      return r
    end
  end
  return nil
end
local justModifiedRemoteDesktopModifiers = false
local remoteDesktopModifierTapper = hs.eventtap.new({
  hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp},
function(ev)
  local rule = remoteDesktopWindowFilter(hs.application.frontmostApplication())
  if rule ~= nil then
    if not justModifiedRemoteDesktopModifiers then
      justModifiedRemoteDesktopModifiers = true
      local evFlags =	ev:getFlags()
      local newEvFlags = {}
      for k, _ in pairs(evFlags) do
        if rule.map[k] == nil then
          newEvFlags[k] = true
        else
          newEvFlags[rule.map[k]] = true
        end
      end
      ev:setFlags(newEvFlags)
      ev:post()
      return true
    else
      justModifiedRemoteDesktopModifiers = false
    end
  end
  return false
end)

if remoteDesktopsMappingModifiers[frontmostApplication:bundleID()] then
  remoteDesktopModifierTapper:start()
end

local function suspendHotkeysInRemoteDesktop(appObject)
  local winObj = appObject:focusedWindow()
  if winObj ~= nil then
    if isDefaultRemoteDesktopWindow(winObj) then
      FLAGS["SUSPEND_IN_REMOTE_DESKTOP"] = not FLAGS["SUSPEND"]
      FLAGS["SUSPEND"] = true
      return
    end
  end
  if FLAGS["SUSPEND_IN_REMOTE_DESKTOP"] ~= nil then
    FLAGS["SUSPEND"] = not FLAGS["SUSPEND_IN_REMOTE_DESKTOP"]
    FLAGS["SUSPEND_IN_REMOTE_DESKTOP"] = nil
  end
end

local remoteDesktopAppsRequireSuspendHotkeys = applicationConfigs.suspendHotkeysInRemoteDesktop or {}
for _, bundleID in ipairs(remoteDesktopAppsRequireSuspendHotkeys) do
  if frontmostApplication:bundleID() == bundleID then
    suspendHotkeysInRemoteDesktop(frontmostApplication)
  end
  execOnActivated(bundleID, suspendHotkeysInRemoteDesktop)
end

local remoteDesktopObserver
local function watchForRemoteDesktopWindow(appObject)
  local appUIObj = hs.axuielement.applicationElement(appObject)
  local observer = hs.axuielement.observer.new(appObject:pid())
  observer:addWatcher(
    appUIObj,
    hs.axuielement.observer.notifications.focusedWindowChanged
  )
  observer:callback(
      hs.fnutils.partial(suspendHotkeysInRemoteDesktop, appObject))
  observer:start()
  stopOnDeactivated(appObject:bundleID(), observer)
  stopOnQuit(appObject:bundleID(), observer)
  remoteDesktopObserver = observer
end

for _, bundleID in ipairs(remoteDesktopAppsRequireSuspendHotkeys) do
  if frontmostApplication:bundleID() == bundleID then
    watchForRemoteDesktopWindow(frontmostApplication)
  end
  execOnActivated(bundleID, watchForRemoteDesktopWindow)
end

-- ## iOS apps
-- disable cmd+w to close window for iOS apps because it will quit them
local iOSAppHotkey
local function deactivateCloseWindowForIOSApps(appObject)
  if appObject:bundleID() == nil then return end
  if hs.fs.attributes(hs.application.pathForBundleID(
      appObject:bundleID()) .. '/WrappedBundle') ~= nil then
    if iOSAppHotkey == nil then
      iOSAppHotkey = newHotkey("⌘", "w", "Cancel ⌘W", function() end)
      iOSAppHotkey.kind = HK.IN_APP
      iOSAppHotkey.subkind = HK.IN_APP_.APP
    end
    iOSAppHotkey:enable()
  elseif iOSAppHotkey ~= nil then
    iOSAppHotkey:disable()
  end
end
deactivateCloseWindowForIOSApps(frontmostApplication)


-- # callbacks

-- ## application callbacks

-- specify input source for apps
local appsInputSourceMap = applicationConfigs.inputSource or {}
local function selectInputSourceInApp(appObject)
  local inputSource = appsInputSourceMap[appObject:bundleID()]
  if inputSource ~= nil then
    local currentSourceID = hs.keycodes.currentSourceID()
    if type(inputSource) == 'string' then
      if currentSourceID ~= inputSource then
        hs.keycodes.currentSourceID(inputSource)
      end
    else
      for _, source in ipairs(inputSource) do
        if currentSourceID == source then
          return
        end
        if hs.keycodes.currentSourceID(source) then
          break
        end
      end
    end
  end
end

-- some apps may have slow launch time, so need to wait until fully launched to bind menu bar item hotkeys
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

local function altMenuBarItemAfterLaunch(appObject)
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
      altMenuBarItem(appObject)
    else
      -- try until fully launched
      tryTimes[bid] = tryTimes[bid] + 1
      if tryTimes[bid] > maxTryTimes then
        tryTimes[bid] = nil
      else
        hs.timer.doAfter(tryInterval, function()
          altMenuBarItemAfterLaunch(appObject)
        end)
      end
    end
  end
end

local appLocales = {}  -- if app locale changes, it may change its menu bar items, so need to rebind
function App_applicationCallback(appName, eventType, appObject)
  local bundleID = appObject:bundleID()
  if eventType == hs.application.watcher.launched then
    for _, proc in ipairs(processesOnLaunch[bundleID] or {}) do
      proc(appObject)
    end
    altMenuBarItemAfterLaunch(appObject)
  elseif eventType == hs.application.watcher.activated then
    WindowCreatedSince = {}
    if bundleID == nil then return end
    if bundleID == "cn.better365.iShotProHelper" then
      unregisterInWinHotKeys("cn.better365.iShotPro")
      return
    end
    if remoteDesktopObserver ~= nil then
      if FLAGS["SUSPEND_IN_REMOTE_DESKTOP"] ~= nil then
        FLAGS["SUSPEND"] = not FLAGS["SUSPEND_IN_REMOTE_DESKTOP"]
        FLAGS["SUSPEND_IN_REMOTE_DESKTOP"] = nil
      end
    end
    for _, proc in ipairs(processesOnActivated[bundleID] or {}) do
      proc(appObject)
    end
    deactivateCloseWindowForIOSApps(appObject)
    selectInputSourceInApp(appObject)
    FLAGS["NO_RESHOW_KEYBINDING"] = true
    hs.timer.doAfter(3, function()
      FLAGS["NO_RESHOW_KEYBINDING"] = false
    end)
    hs.timer.doAfter(0, function()
      local appLocale = applicationLocales(bundleID)[1]
      local oldAppLocale = appLocales[bundleID] or systemLocales()[1]
      if oldAppLocale ~= appLocale then
        if getMatchedLocale(oldAppLocale, { appLocale }) ~= appLocale then
          unregisterRunningAppHotKeys(bundleID, true)
          registerRunningAppHotKeys(bundleID)
          localizeCommonMenuItemTitles(appLocale)
        end
        appLocales[bundleID] = appLocale
      end
      registerForOpenSavePanel(appObject)
      registerInAppHotKeys(appObject)
      registerInWinHotKeys(appObject)
      hs.timer.doAfter(0, function()
        altMenuBarItem(appObject)
        hs.timer.doAfter(0, function()
          remapPreviousTab(appObject)
          registerOpenRecent(appObject)
          registerObserverForMenuBarChange(appObject)
          if HSKeybindings ~= nil and HSKeybindings.isShowing then
            local validOnly = HSKeybindings.validOnly
            local showHS = HSKeybindings.showHS
            local showApp = HSKeybindings.showApp
            HSKeybindings:reset()
            HSKeybindings:update(validOnly, showHS, showApp, true)
          end
          FLAGS["NO_RESHOW_KEYBINDING"] = false
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
      if bundleID then
        unregisterInAppHotKeys(bundleID)
        unregisterInWinHotKeys(bundleID)
        for _, ob in ipairs(observersStopOnDeactivated[bundleID] or {}) do
          local observer, func = ob[1], ob[2]
          observer:stop()
          if func ~= nil then func(bundleID, observer) end
        end
        observersStopOnDeactivated[bundleID] = nil
      end
    else
      for bid, obs in pairs(observersStopOnQuit) do
        if findApplication(bid) == nil then
          for _, ob in ipairs(obs) do
            local observer, func = ob[1], ob[2]
            observer:stop()
            if func ~= nil then func(bid, observer) end
          end
          observersStopOnQuit[bid] = nil
        end
      end
      for bid, _ in pairs(runningAppHotKeys) do
        if findApplication(bid) == nil then
          unregisterRunningAppHotKeys(bid)
        end
      end
      for bid, _ in pairs(inAppHotKeys) do
        if findApplication(bid) == nil then
          unregisterInAppHotKeys(bid, true)
        end
      end
      for bid, _ in pairs(inWinHotKeys) do
        if findApplication(bid) == nil then
          unregisterInWinHotKeys(bid, true)
        end
      end
      for bid, _ in pairs(appLocales) do
        if findApplication(bid) == nil then
          appLocales[bid] = nil
        end
      end
    end
    if remoteDesktopsMappingModifiers[hs.application.frontmostApplication():bundleID()] == nil then
      if remoteDesktopModifierTapper:isEnabled() then
        remoteDesktopModifierTapper:stop()
      end
    end
  end
end

function App_applicationInstalledCallback(files, flagTables)
  registerAppHotkeys()
end

-- ## monitor callbacks

-- launch applications automatically when connected to an external monitor
local builtinMonitor = "Built-in Retina Display"

function App_monitorChangedCallback()
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
      hs.execute([[open -g -b "me.guillaumeb.MonitorControl"]])
    end
  elseif builtinMonitorEnable and #screens == 1 then
    quitApplication("me.guillaumeb.MonitorControl")
  end
end

-- ## usb callbacks

-- launch `MacDroid` automatically when connected to android phone
local phones = {{"ANA-AN00", "HUAWEI"}}
local attached_android_count = 0

function App_usbChangedCallback(device)
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
