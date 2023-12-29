OS = {
  Yosemite = "10.10",
  ["El Capitan"] = "10.11",
  Sierra = "10.12",
  ["High Sierra"] = "10.13",
  Mojave = "10.14",
  Catalina = "10.15",
  ["Big Sur"] = "11",
  Monterey = "12",
  Ventura = "13",
  Sonoma = "14",
}

function getOSVersion()
  local osVersion = hs.host.operatingSystemVersion()
  local v = osVersion.major
  if v < 11 then
    return tostring(v) .. "." .. tostring(osVersion.minor)
  else
    return tostring(v)
  end
end

function keyCode(modifiers, key)
  return function()
    hs.eventtap.keyStroke(modifiers, key)
  end
end

function remapKey(modifiers, key, keyCode, message)
  return bindSuspend(modifiers, key, message, keyCode, nil, keyCode)
end

function selectMenuItem(appObject, menuItemTitle, show)
  if appObject:findMenuItem(menuItemTitle.en) ~= nil then
    if show then
      appObject:selectMenuItem({menuItemTitle.en[1]})
    end
    appObject:selectMenuItem(menuItemTitle.en)
  else
    if show then
      appObject:selectMenuItem({menuItemTitle.zh[1]})
    end
    appObject:selectMenuItem(menuItemTitle.zh)
  end
end

function inFullscreenWindow()
  local focusedWindow = hs.application.frontmostApplication():focusedWindow()
  return focusedWindow ~= nil
      and focusedWindow:id() ~= 0
      and hs.spaces.spaceType(hs.spaces.windowSpaces(focusedWindow)[1]) ~= "user"
end

function activatedWindowIndex()
  if inFullscreenWindow() then
    return #hs.application.frontmostApplication():visibleWindows()
  else
    return 1
  end
end

function aWinFor(bundleID)
  return string.format(
      'window %d of (first application process whose bundle identifier is "%s")\n',
      activatedWindowIndex(), bundleID)
end

function menuBarVisible()
  if inFullscreenWindow() then
    local thisAppAutohide = hs.execute("defaults read "
        .. hs.application.frontmostApplication():bundleID() .. " AppleMenuBarVisibleInFullscreen | tr -d '\\n'")
    if thisAppAutohide == "0" then
      return false
    elseif thisAppAutohide == "" then
      local autohide = hs.execute("defaults read -globalDomain AppleMenuBarVisibleInFullscreen | tr -d '\\n'")
      if autohide == "0" then
        return false
      end
    end
  end
  return true
end

function showMenuItemWrapper(fn)
  return function()
    if menuBarVisible() then
      fn()
    else
      hs.eventtap.keyStroke('fn⌃', 'F2')
      hs.timer.doAfter(0.1, function() fn() end)
    end
  end
end

local function filterParallels(appObjects)
  return hs.fnutils.find(appObjects, function(app)
    return string.find(app:bundleID(), "com.parallels") == nil
  end)
end

function findApplication(hint, exact)
  if exact == nil then exact = true end
  return filterParallels{hs.application.find(hint, exact)}
end

function quitApplication(app)
  local appObject = findApplication(app, true)
  if appObject ~= nil then
    appObject:kill()
    return true
  end
  return false
end

function applicationLocales(bundleID)
  local locales, ok = hs.execute(
      string.format("(defaults read %s AppleLanguages || defaults read -globalDomain AppleLanguages) | tr -d '()\" \\n'", bundleID))
  return hs.fnutils.split(locales, ',')
end

local appLocaleMap = {}
local appLocaleDir = {}
local appLocaleInversedMap = {}
function localizedString(string, bundleID, locale, localeFile)
  if localeFile == nil then
    localeFile = locale
    locale = nil
  end
  if appLocaleMap[bundleID] == nil then
    appLocaleMap[bundleID] = {}
    appLocaleDir[bundleID] = {}
  end
  local locales = applicationLocales(bundleID)
  local appLocale = locales[1]
  if appLocaleMap[bundleID][appLocale] == nil then
    appLocaleMap[bundleID][appLocale] = {}
  end
  local localesDict = appLocaleMap[bundleID][appLocale]

  local resourceDir = hs.application.pathForBundleID(bundleID) .. "/Contents/Resources"
  local localeDir
  if locale == nil then locale = appLocaleDir[bundleID][appLocale] end
  if locale ~= nil then
    localeDir = resourceDir .. "/" .. locale .. ".lproj"
  else
    local localDetails = hs.host.locale.details(appLocale)
    local language = localDetails.languageCode
    local script = localDetails.scriptCode
    local country = localDetails.countryCode
    if script == nil then
      local localeItems = hs.fnutils.split(appLocale, '-')
      if #localeItems == 3 or (#localeItems == 2 and localeItems[2] ~= country) then
        script = localeItems[2]
      end
    end
    for file in hs.fs.dir(resourceDir) do
      if file:sub(-6) == ".lproj" then
        local fileLocale = hs.host.locale.details(file:sub(1, -7))
        local fileLanguage = fileLocale.languageCode
        local fileScript = fileLocale.scriptCode
        local fileCountry = fileLocale.countryCode
        if fileScript == nil then
          local localeItems = hs.fnutils.split(file:sub(1, -7), '-')
          if #localeItems == 3 or (#localeItems == 2 and localeItems[2] ~= fileCountry) then
            fileScript = localeItems[2]
          end
        end
        if fileLanguage == language
            and (script == nil or fileScript == nil or fileScript == script)
            and (country == nil or fileCountry == nil or fileCountry == country) then
          localeDir = resourceDir .. "/" .. file
          appLocaleDir[bundleID][appLocale] = file:sub(1, -7)
          break
        end
      end
    end
  end

  local searchFunc = function(string)
    if localeFile ~= nil then
      if localesDict[localeFile] == nil then
        local fullPath = localeDir .. '/' .. localeFile .. '.strings'
        local jsonStr = hs.execute('plutil -convert json -o - "' .. fullPath .. '"')
        localesDict[localeFile] = hs.json.decode(jsonStr)
      end
      if localesDict[localeFile][string] ~= nil then
        return localesDict[localeFile][string]
      end
    else
      for file in hs.fs.dir(localeDir) do
        if file:sub(-8) == ".strings" then
          local fileStem = file:sub(1, -9)
          if localesDict[fileStem] == nil then
            local fullPath = localeDir .. '/' .. file
            local jsonStr = hs.execute('plutil -convert json -o - "' .. fullPath .. '"')
            localesDict[fileStem] = hs.json.decode(jsonStr)
          end
          if localesDict[fileStem][string] ~= nil then
            return localesDict[fileStem][string]
          end
        end
      end
    end
  end
  local result = searchFunc(string)
  if result ~= nil then return result end

  if appLocaleInversedMap[bundleID] == nil then
    appLocaleInversedMap[bundleID] = {}
  end
  localesInvDict = appLocaleInversedMap[bundleID]
  for _, localeDir in ipairs({resourceDir .. "/en.lproj", resourceDir .. "/Base.lproj"}) do
    if hs.fs.attributes(localeDir) ~= nil then
      if localeFile ~= nil then
        if localesInvDict[localeFile] == nil then
          localesInvDict[localeFile] = {}
          local fullPath = localeDir .. '/' .. localeFile .. '.strings'
          local jsonStr = hs.execute('plutil -convert json -o - "' .. fullPath .. '"')
          local jsonDict = hs.json.decode(jsonStr)
          for k, v in pairs(jsonDict) do
            localesInvDict[localeFile][v] = k
          end
        end
        if localesInvDict[localeFile][string] ~= nil then
          local result = searchFunc(localesInvDict[localeFile][string])
          if result ~= nil then return result end
        end
      else
        for file in hs.fs.dir(localeDir) do
          if file:sub(-8) == ".strings" then
            local fileStem = file:sub(1, -9)
            if localesInvDict[fileStem] == nil then
              localesInvDict[fileStem] = {}
              local fullPath = localeDir .. '/' .. file
              local jsonStr = hs.execute('plutil -convert json -o - "' .. fullPath .. '"')
              local jsonDict = hs.json.decode(jsonStr)
              for k, v in pairs(jsonDict) do
                localesInvDict[fileStem][v] = k
              end
            end
            if localesInvDict[fileStem][string] ~= nil then
              local result = searchFunc(localesInvDict[fileStem][string])
              if result ~= nil then return result end
            end
          end
        end
      end
    end
  end
end

local menuItemLocaleMap = {}
local menuItemAppLocaleMap = {}
function delocalizedMenuItem(string, bundleID, locale, localeFile)
  if localeFile == nil then
    localeFile = locale
    locale = nil
  end
  local locales = applicationLocales(bundleID)
  local appLocale = locales[1]
  if menuItemAppLocaleMap[bundleID] ~= appLocale then
    menuItemLocaleMap[bundleID] = {}
  end
  menuItemAppLocaleMap[bundleID] = appLocale
  if menuItemLocaleMap[bundleID][string] == 'nil' then
    return nil
  end

  local resourceDir = hs.application.pathForBundleID(bundleID) .. "/Contents/Resources"
  local localeDir
  if locale ~= nil then
    localeDir = resourceDir .. "/" .. locale .. ".lproj"
  else
    local localDetails = hs.host.locale.details(appLocale)
    local language = localDetails.languageCode
    local script = localDetails.scriptCode
    local country = localDetails.countryCode
    if script == nil then
      local localeItems = hs.fnutils.split(appLocale, '-')
      if #localeItems == 3 or (#localeItems == 2 and localeItems[2] ~= country) then
        script = localeItems[2]
      end
    end
    for file in hs.fs.dir(resourceDir) do
      if file:sub(-6) == ".lproj" then
        local fileLocale = hs.host.locale.details(file:sub(1, -7))
        local fileLanguage = fileLocale.languageCode
        local fileScript = fileLocale.scriptCode
        local fileCountry = fileLocale.countryCode
        if fileScript == nil then
          local localeItems = hs.fnutils.split(file:sub(1, -7), '-')
          if #localeItems == 3 or (#localeItems == 2 and localeItems[2] ~= fileCountry) then
            fileScript = localeItems[2]
          end
        end
        if fileLanguage == language
            and (script == nil or fileScript == nil or fileScript == script)
            and (country == nil or fileCountry == nil or fileCountry == country) then
          localeDir = resourceDir .. "/" .. file
          break
        end
      end
    end
  end

  local searchFunc = function(string)
    for _, localeDir in ipairs({resourceDir .. "/en.lproj", resourceDir .. "/Base.lproj"}) do
      if hs.fs.attributes(localeDir) ~= nil then
        if localeFile ~= nil then
          local fullPath = localeDir .. '/' .. localeFile .. '.strings'
          local jsonStr = hs.execute('plutil -convert json -o - "' .. fullPath .. '"')
          local jsonDict = hs.json.decode(jsonStr)
          return jsonDict[string]
        else
          local stringsFiles = {}
          for file in hs.fs.dir(localeDir) do
            if file:sub(-8) == ".strings" then
              table.insert(stringsFiles, file)
            end
          end
          if #stringsFiles > 10 then
            stringsFiles = { "MainMenu.strings", "Menu.strings", "Localizable.strings", "MenuItems.strings" }
          end
          for _, file in ipairs(stringsFiles) do
            local fullPath = localeDir .. '/' .. file
            if hs.fs.attributes(fullPath) ~= nil then
              local jsonStr = hs.execute('plutil -convert json -o - "' .. fullPath .. '"')
              local jsonDict = hs.json.decode(jsonStr)
              if jsonDict[string] ~= nil then
                return jsonDict[string]
              end
            end
          end
        end
      end
    end
  end

  local localesDict = menuItemLocaleMap[bundleID]
  if localeFile ~= nil then
    if localesDict[string] == nil then
      local fullPath = localeDir .. '/' .. localeFile .. '.strings'
      local jsonStr = hs.execute('plutil -convert json -o - "' .. fullPath .. '"')
      local jsonDict = hs.json.decode(jsonStr)
      for k, v in pairs(jsonDict) do
        localesDict[v] = k
      end
    end
    if localesDict[string] ~= nil then
      return searchFunc(localesDict[string])
    end
  else
    local stringsFiles = {}
    for file in hs.fs.dir(localeDir) do
      if file:sub(-8) == ".strings" then
        table.insert(stringsFiles, file)
      end
    end
    if #stringsFiles > 10 then
      stringsFiles = { "MainMenu.strings", "Menu.strings", "Localizable.strings", "MenuItems.strings" }
    end
    for _, file in ipairs(stringsFiles) do
      local fullPath = localeDir .. '/' .. file
      if hs.fs.attributes(fullPath) ~= nil then
        if localesDict[string] == nil then
          local jsonStr = hs.execute('plutil -convert json -o - "' .. fullPath .. '"')
          local jsonDict = hs.json.decode(jsonStr)
          for k, v in pairs(jsonDict) do
            localesDict[v] = k
          end
        end
        if localesDict[string] ~= nil then
          local result = searchFunc(localesDict[string])
          if result ~= nil then return result end
        end
      end
    end
  end

  localesDict[string] = 'nil'
end


-- helpers for click menubar to the right

function hasTopNotch(screen)
  if screen:name() == "Built-in Retina Display" then
    local displaySize = screen:fullFrame()
    if displaySize.w * 10 < displaySize.h * 16 then
      return true
    end
  end
  return false
end

function hiddenByBartender(id)
  if findApplication("com.surteesstudios.Bartender") == nil then
    return false
  end
  local ok, hiddenItems = hs.osascript.applescript([[
    tell application id "com.surteesstudios.Bartender" to list menu bar items
  ]])
  local hiddenItemList = hs.fnutils.split(hiddenItems, "\n")
  for _, item in ipairs(hiddenItemList) do
    if string.sub(item, 1, string.len(id)) == id then
      return false
    elseif item == "com.surteesstudios.Bartender-statusItem" then
      return true
    end
  end
end

function leftClickAndRestore(position)
  if position.x == nil then position = hs.geometry.point(position) end
  local mousePosition = hs.mouse.absolutePosition()
  hs.eventtap.leftClick(hs.geometry.point(position))
  hs.mouse.absolutePosition(mousePosition)
end

function rightClickAndRestore(position)
  if position.x == nil then position = hs.geometry.point(position) end
  local mousePosition = hs.mouse.absolutePosition()
  hs.eventtap.rightClick(hs.geometry.point(position))
  hs.mouse.absolutePosition(mousePosition)
end

function clickAppRightMenuBarItem(bundleID, menuItem, subMenuItem)
  -- only menu bar item
  if menuItem == nil then
    local status_code = hs.osascript.applescript(string.format([[
      tell application "System Events"
        set ap to first application process whose bundle identifier is "%s"
        set c to count of menu bar of ap
        click menu bar item 1 of menu bar c of ap
      end tell
    ]], bundleID))
    return status_code
  end

  -- firstly click menu bar item
  local clickMenuBarItemCmd = string.format([[
    tell application "System Events"
      set ap to first application process whose bundle identifier is "%s"
      set c to count of menu bar of ap
    end tell

    ignoring application responses
      tell application "System Events"
        click menu bar item 1 of menu bar c of ap
      end tell
    end ignoring

    delay 1
    do shell script "killall System\\ Events"

  ]], bundleID)

  if type(menuItem) == "number" then
    menuItem = tostring(menuItem)
  elseif type(menuItem) == "string" then
    menuItem = '"'..menuItem..'"'
  else
    for lang, item in pairs(menuItem) do
      if lang == 'localized' then
        item = localizedString(item, bundleID, menuItem.strings)
      end
      menuItem[lang] = '"'..item..'"'
    end
  end

  if subMenuItem ~= nil then
    if type(subMenuItem) == "number" then
      subMenuItem = tostring(subMenuItem)
    elseif type(subMenuItem) == "string" then
      subMenuItem = '"'..subMenuItem..'"'
    else
      for lang, item in pairs(subMenuItem) do
        if lang == 'localized' then
          item = localizedString(item, bundleID, menuItem.strings)
        end
        subMenuItem[lang] = '"'..item..'"'
      end
    end
  end

  -- secondly click menu item of popup menu
  if type(menuItem) ~= "table" then
    local clickMenuItemCmd = string.format([[
      set menuitem to menu item %s of menu 1 of menu bar item 1 of menu bar c of ap
      click menuitem
    ]], menuItem)

    -- thirdly click menu item of popup menu of clicked click menu item of popup menu
    local clickSubMenuItemCmd = ""
    if subMenuItem ~= nil then
      if type(subMenuItem) ~= "table" then
        clickSubMenuItemCmd = string.format([[
          set submenuitem to menu item %s of menu %s of menuitem
          click submenuitem
        ]], subMenuItem, menuItem)
      else
        for lang, subitem in pairs(subMenuItem) do
          local else_ = ""
          if clickSubMenuItemCmd ~= "" then
            else_ = "else "
          end

          clickSubMenuItemCmd = clickSubMenuItemCmd .. string.format([[
              %sif exists submenuitem to menu item %s of menu %s of menuitem
                set submenuitem to menu item %s of menu %s of menuitem
                click submenuitem
            ]],
            else_, subitem, menuItem, subitem, menuItem)
        end
        clickSubMenuItemCmd = clickSubMenuItemCmd .. [[
          end if
        ]]
      end
    end

    local status_code = hs.osascript.applescript(string.format([[
        %s
        tell application "System Events"
          %s
          %s
        end tell
      ]],
      clickMenuBarItemCmd,
      clickMenuItemCmd,
      clickSubMenuItemCmd)
    )
    return status_code
  else
    local clickMenuItemCmd = ""
    for lang, item in pairs(menuItem) do
      local clickSubMenuItemCmd = ""
      if subMenuItem ~= nil then
        if type(subMenuItem) ~= "table" then
          clickSubMenuItemCmdFmt = string.format([[
            set submenuitem to menu item %s of menu %s of menuitem
            click submenuitem
          ]], subMenuItem, item)
        else
          for lang, subitem in pairs(subMenuItem) do
            local else_ = ""
            if clickSubMenuItemCmd ~= "" then
              else_ = "else "
            end

            clickSubMenuItemCmd = clickSubMenuItemCmd .. string.format([[
                %sif exists submenuitem to menu item %s of menu %s of menuitem
                  set submenuitem to menu item %s of menu %s of menuitem
                  click submenuitem
              ]],
              else_, subitem, item, subitem, item)
          end
          clickSubMenuItemCmd = clickSubMenuItemCmd .. [[
            end if
          ]]
        end
      end

      local else_ = ""
      if clickMenuItemCmd ~= "" then
        else_ = "else "
      end

      clickMenuItemCmd = clickMenuItemCmd .. string.format([[
        %sif exists menu item %s of menu 1 of menu bar item 1 of menu bar c of ap
            set menuitem to menu item %s of menu 1 of menu bar item 1 of menu bar c of ap
            click menuitem
            %s
      ]],
      else_, item, item, clickSubMenuItemCmd)
    end
    clickMenuItemCmd = clickMenuItemCmd .. [[
      end if
    ]]

    local status_code = hs.osascript.applescript(string.format([[
        %s
        tell application "System Events"
          %s
        end tell
      ]],
      clickMenuBarItemCmd,
      clickMenuItemCmd)
    )
    return status_code
  end
end

local controlCenterIdentifiers = hs.json.read("static/controlcenter-identifies.json")
local controlCenterMenuBarItemIdentifiers = controlCenterIdentifiers.menubar
function clickControlCenterMenuBarItemSinceBigSur(menuItem)
  local osVersion = getOSVersion()
  local succ = hs.osascript.applescript(string.format([[
    tell application "System Events"
      set controlitems to menu bar 1 of application process "ControlCenter"
      set controlcenter to ¬
        (first menu bar item whose value of attribute "AXIdentifier" contains "%s") of controlitems
      perform action 1 of controlcenter
    end tell
  ]], controlCenterMenuBarItemIdentifiers[menuItem]))
  return succ
end

function clickControlCenterMenuBarItem(menuItem)
  local osVersion = getOSVersion()
  if osVersion >= OS["Big Sur"] then
    return clickControlCenterMenuBarItemSinceBigSur(menuItem)
  end
  return false
end

function controlCenterLocalized(panel, key)
  if key == nil then
    key = panel == "WiFi" and "Wi‑Fi" or panel
  end
  if controlCenterSubMenuBarItems == nil then return key end
  if panel == "Control Center" then
    return controlCenterSubMenuBarItems.InfoPlist.CFBundleName
  end
  panel = panel:gsub("%s+", "")
  return localizedString(key, "com.apple.controlcenter", panel)
end


function clickRightMenuBarItem(menuBarName, menuItem, subMenuItem)
  if menuBarName == "Control Center"
      or controlCenterSubMenuBarItems[menuBarName:gsub("%s+", "")] ~= nil then
    return clickControlCenterMenuBarItem(menuBarName)
  else
    return clickAppRightMenuBarItem(menuBarName, menuItem, subMenuItem)
  end
end


curNetworkService = nil
function getCurrentNetworkService()
  local interfacev4, interfacev6 = hs.network.primaryInterfaces()
  if interfacev4 then
    local networkservice, status = hs.execute([[
        networksetup -listallhardwareports \
        | awk "/]] .. interfacev4 .. [[/ {print prev} {prev=\$0;}" \
        | awk -F: '{print $2}' | awk '{$1=$1};1']])
    curNetworkService = '"' .. networkservice:gsub("\n", "") .. '"'
  else
    curNetworkService = nil
  end
  return curNetworkService
end
