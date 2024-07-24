---@diagnostic disable: lowercase-global

OS = {
  Cheetah = "10.00",
  Puma = "10.01",
  Jaguar = "10.02",
  Panther = "10.03",
  Tiger = "10.04",
  Leopard = "10.05",
  ["Snow Leopard"] = "10.06",
  Lion = "10.07",
  ["Mountain Lion"] = "10.08",
  Mavericks = "10.09",
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
  Sequoia = "15",
}

function getOSVersion()
  local osVersion = hs.host.operatingSystemVersion()
  local v = osVersion.major
  if v < 11 then
    local vminor = (osVersion.minor < 10 and "0" or "") .. tostring(osVersion.minor)
    return tostring(v) .. "." .. tostring(vminor)
  else
    return tostring(v)
  end
end

function get(table, key, ...)
  if table == nil or key == nil then return table end
  return get(table[key], ...)
end

function getAXChildren(element, role, index, ...)
  if element == nil or role == nil then return element end
  local children = element:childrenWithRole(role)[index]
  return getAXChildren(children, ...)
end

function inFullscreenWindow()
  local focusedWindow = hs.application.frontmostApplication():focusedWindow()
  if focusedWindow ~= nil and focusedWindow:id() ~= 0 then
    local spaces = hs.spaces.windowSpaces(focusedWindow)
    if #spaces == 0 then
      hs.timer.usleep(0.1 * 1000000)
      spaces = hs.spaces.windowSpaces(focusedWindow)
    end
    return hs.spaces.spaceType(spaces[1]) ~= "user"
  end
  return false
end

function activatedWindowIndex()
  if inFullscreenWindow() then
    return #hs.application.frontmostApplication():visibleWindows()
  else
    return 1
  end
end

function aWinFor(bundleID_or_appObject)
  local bundleID
  if type(bundleID_or_appObject) == 'string' then bundleID = bundleID_or_appObject
  else bundleID = bundleID_or_appObject:bundleID() end
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

SPECIAL_KEY_SIMBOL_MAP = {
  ['\b'] = '⌫',
  ['\t'] = '⇥',
  ['\n'] = '↵',
  ['\r'] = '↵',
  ['\x1b'] = '⎋',
  [' '] = '␣',
  ['\xef\x9c\x80'] = '↑',
  ['\xef\x9c\x81'] = '↓',
  ['\xef\x9c\x82'] = '←',
  ['\xef\x9c\x83'] = '→',
  ['\xef\x9c\x84'] = 'F1',
  ['\xef\x9c\x85'] = 'F2',
  ['\xef\x9c\x86'] = 'F3',
  ['\xef\x9c\x87'] = 'F4',
  ['\xef\x9c\x88'] = 'F5',
  ['\xef\x9c\x89'] = 'F6',
  ['\xef\x9c\x8a'] = 'F7',
  ['\xef\x9c\x8b'] = 'F8',
  ['\xef\x9c\x8c'] = 'F9',
  ['\xef\x9c\x8d'] = 'F10',
  ['\xef\x9c\x8e'] = 'F11',
  ['\xef\x9c\x8f'] = 'F12',
  ['\xef\x9c\xa9'] = '↖',
  ['\xef\x9c\xab'] = '↘',
  ['\xef\x9c\xac'] = '⇞',
  ['\xef\x9c\xad'] = '⇟',
  ['\xf0\x9f\x8e\xa4'] = '🎤︎',
}

function getMenuItems(appObject)
  local menuItems
  local maxTryTime = 3
  local tryInterval = 0.05
  local tryTimes = 1
  while tryTimes <= maxTryTime / tryInterval do
    menuItems = appObject:getMenuItems()
    if menuItems ~= nil then return menuItems end
    hs.timer.usleep(tryInterval * 1000000)
    tryTimes = tryTimes + 1
  end
  return { { AXTitle = appObject:name() }}
end

function findMenuItem(appObject, menuItemTitle, params)
  if #menuItemTitle > 0 then
    local menuItem = appObject:findMenuItem(menuItemTitle)
    if menuItem ~= nil then return menuItem, menuItemTitle end
    local targetMenuItem = {}
    local locStr = localizedMenuBarItem(menuItemTitle[1], appObject:bundleID())
    table.insert(targetMenuItem, locStr or menuItemTitle[1])
    for i=#menuItemTitle,2,-1 do
      locStr = localizedString(menuItemTitle[i], appObject:bundleID(), params)
      table.insert(targetMenuItem, 2, locStr or menuItemTitle[i])
    end
    return appObject:findMenuItem(targetMenuItem), targetMenuItem
  else
    for _, title in pairs(menuItemTitle) do
      local menuItem = appObject:findMenuItem(title)
      if menuItem ~= nil then
        return menuItem, title
      end
    end
  end
end

function selectMenuItem(appObject, menuItemTitle, params, show)
  if type(params) == "boolean" then
    show = params params = nil
  end

  if show then
    local menuItem, targetMenuItem = findMenuItem(appObject, menuItemTitle, params)
    if menuItem ~= nil then
      showMenuItemWrapper(function()
        appObject:selectMenuItem({targetMenuItem[1]})
      end)()
      return appObject:selectMenuItem(targetMenuItem)
    end
  elseif #menuItemTitle > 0 then
    if appObject:selectMenuItem(menuItemTitle) then return true end
    local targetMenuItem = {}
    local locStr = localizedMenuBarItem(menuItemTitle[1], appObject:bundleID())
    table.insert(targetMenuItem, locStr or menuItemTitle[1])
    for i=#menuItemTitle,2,-1 do
      locStr = localizedString(menuItemTitle[i], appObject:bundleID(), params)
      table.insert(targetMenuItem, 2, locStr or menuItemTitle[i])
    end
    return appObject:selectMenuItem(targetMenuItem)
  else
    for _, title in pairs(menuItemTitle) do
      if appObject:selectMenuItem(title) then return true end
    end
  end
end

local function findMenuItemByKeyBindingImpl(mods, key, menuItem)
  if menuItem.AXChildren == nil then return end
  for _, subItem in ipairs(menuItem.AXChildren[1]) do
    local cmdChar = subItem.AXMenuItemCmdChar
    if cmdChar ~= "" and (string.byte(cmdChar, 1) <= 32 or string.byte(cmdChar, 1) > 127) then
      cmdChar = SPECIAL_KEY_SIMBOL_MAP[key] or cmdChar
    end
    if (cmdChar == key
        or (subItem.AXMenuItemCmdGlyph ~= "" and hs.application.menuGlyphs[subItem.AXMenuItemCmdGlyph] == key))
        and #subItem.AXMenuItemCmdModifiers == #mods then
      local match = true
      for _, mod in ipairs(mods) do
        if not hs.fnutils.contains(subItem.AXMenuItemCmdModifiers, mod) then
          match = false
          break
        end
      end
      if match then
        return { subItem.AXTitle }, subItem.AXEnabled
      end
    end
    local menuItemPath, enabled = findMenuItemByKeyBindingImpl(mods, key, subItem)
    if menuItemPath ~= nil then
      table.insert(menuItemPath, 1, subItem.AXTitle)
      return menuItemPath, enabled
    end
  end
end

local modifierSymbolMap = {
  command = 'cmd',
  control = 'ctrl',
  option = 'alt',
  ["⌘"] = 'cmd',
  ["⌃"] = 'ctrl',
  ["⌥"] = 'alt',
  ["⇧"] = 'shift'
}

function findMenuItemByKeyBinding(appObject, mods, key)
  local menuItems = getMenuItems(appObject)
  if menuItems == nil then return end
  if mods == '' then mods = {} end
  if type(mods) == 'string' and string.byte(mods, 1, 1) < 127 then
    mods = { mods }
  end
  local newMods = {}
  if type(mods) == 'string' then
    for i=1,utf8.len(mods) do
      local mod = string.sub(mods, i*3-2, i*3)
      table.insert(newMods, modifierSymbolMap[mod] or mod)
    end
  else
    for _, mod in ipairs(mods) do
      table.insert(newMods, modifierSymbolMap[mod] or mod)
    end
  end
  for i=#menuItems,1,-1 do
    local menuItem = menuItems[i]
    local menuItemPath, enabled = findMenuItemByKeyBindingImpl(newMods, key, menuItem)
    if menuItemPath ~= nil then
      table.insert(menuItemPath, 1, menuItem.AXTitle)
      return menuItemPath, enabled
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

local localeTmpDir = hs.fs.temporaryDirectory() .. 'org.hammerspoon.Hammerspoon/locale/'

function systemLocales()
  local locales, ok = hs.execute("defaults read -globalDomain AppleLanguages | tr -d '()\" \\n'")
  return hs.fnutils.split(locales, ',')
end

function applicationLocales(bundleID)
  local locales, ok = hs.execute(
      string.format("(defaults read %s AppleLanguages || defaults read -globalDomain AppleLanguages) | tr -d '()\" \\n'", bundleID))
  return hs.fnutils.split(locales, ',')
end

local function getResourceDir(bundleID, frameworkName)
  local resourceDir
  local framework = {}
  local appContentPath = hs.application.pathForBundleID(bundleID) .. "/Contents"
  if hs.fs.attributes(appContentPath) == nil then
    resourceDir = hs.application.pathForBundleID(bundleID) .. "/WrappedBundle/.."
  elseif frameworkName ~= nil and frameworkName:sub(-10) == ".framework" then
    resourceDir = appContentPath .. "/Frameworks/" .. frameworkName .. "/Resources"
  elseif bundleID == "com.google.Chrome" then
    resourceDir = appContentPath .. "/Frameworks/Google Chrome Framework.framework/Resources"
    framework.chromium = true
  elseif bundleID == "com.microsoft.edgemac" then
    resourceDir = appContentPath .. "/Frameworks/Microsoft Edge Framework.framework/Resources"
    framework.chromium = true
  elseif bundleID == "com.tencent.meeting" then
    resourceDir = appContentPath .. "/Frameworks/WeMeetFramework.framework/Versions/Current/Frameworks"
        .. "/WeMeet.framework/Versions/A/Resources"
        .. "/WeMeetResource.bundle/Contents/Resources"
  else
    local frameworkDir = appContentPath .. "/Frameworks"
    for _, fw in ipairs{"Electron Framework", "Chromium Embedded Framework"} do
      if hs.fs.attributes(frameworkDir .. '/' .. fw .. ".framework") ~= nil then
        resourceDir = frameworkDir .. '/' .. fw .. ".framework/Resources"
        framework.chromium = true
        goto END_GET_RESOURCE_DIR
      end
    end

    if hs.fs.attributes(appContentPath .. "/Frameworks") ~= nil then
      local chromiumDirs, status = hs.execute(string.format(
        "find '%s' -type f -path '*/Resources/*/locale.pak'" ..
        " | awk -F'/Versions/' '{print $1}' | uniq",
        appContentPath .. "/Frameworks"))
      if status and chromiumDirs:sub(1, -2) ~= "" then
        chromiumDirs = hs.fnutils.split(chromiumDirs:sub(1, -2), '\n')
        if #chromiumDirs == 1 then
          resourceDir = chromiumDirs[1] .. "/Resources"
          framework.chromium = true
          goto END_GET_RESOURCE_DIR
        end
      end
    end

    if hs.fs.attributes(appContentPath .. "/Resources/qt.conf") ~= nil then
      resourceDir = appContentPath .. "/Resources"
      framework.qt = true
      goto END_GET_RESOURCE_DIR
    end

    local monoLocaleDirs, status = hs.execute(string.format(
        "find '%s' -type f -path '*/locale/*/LC_MESSAGES/*.mo'" ..
        " | awk -F'/locale/' '{print $1}' | uniq", appContentPath))
    if status and monoLocaleDirs:sub(1, -2) ~= "" then
      monoLocaleDirs = hs.fnutils.split(monoLocaleDirs:sub(1, -2), '\n')
      if #monoLocaleDirs == 1 then
        resourceDir = monoLocaleDirs[1] .. "/locale"
        framework.mono = true
        goto END_GET_RESOURCE_DIR
      end
    end

    if resourceDir == nil then
      resourceDir = appContentPath .. "/Resources"
    end
  end

  ::END_GET_RESOURCE_DIR::
  return resourceDir, framework
end

local function getMatchedLocale(appLocale, localeSource, mode)
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
  if type(localeSource) == 'string' then
    local resourceDir = localeSource
    localeSource = {}
    for file in hs.fs.dir(resourceDir) do
      table.insert(localeSource, file)
    end
  end
  for _, loc in ipairs(localeSource) do
    if (mode == 'lproj' and loc:sub(-6) == ".lproj")
        or (mode == 'strings' and loc:sub(-8) == ".strings")
        or mode == nil then
      local locale
      if mode == nil then locale = loc
      elseif mode == 'lproj' then locale = loc:sub(1, -7)
      else locale = loc:sub(1, -9) end
      local newLocale = string.gsub(locale, '_', '-')
      local thisLocale = hs.host.locale.details(newLocale)
      local thisLanguage = thisLocale.languageCode
      local thisScript = thisLocale.scriptCode
      local thisCountry = thisLocale.countryCode
      if thisScript == nil then
        local localeItems = hs.fnutils.split(newLocale, '-')
        if #localeItems == 3 or (#localeItems == 2 and localeItems[2] ~= thisCountry) then
          thisScript = localeItems[2]
        end
      end
      if thisLanguage == language
          and (script == nil or thisScript == nil or thisScript == script)
          and (country == nil or thisCountry == nil or thisCountry == country) then
        return locale
      end
    end
  end
end

function getQtMatchedLocale(appLocale, resourceDir)
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
  language = language:lower()
  if script ~= nil then script = script:lower() end
  if country ~= nil then country = country:lower() end
  local dirs = { resourceDir }
  for file in hs.fs.dir(resourceDir) do
    if hs.fs.attributes(resourceDir .. '/' .. file, 'mode') == 'directory' then
      table.insert(dirs, resourceDir .. '/' .. file)
    end
  end
  for _, dir in ipairs(dirs) do
    local languageMatches = {}
    for file in hs.fs.dir(dir) do
      if file:sub(-3) == '.qm' then
        local lowerFile = file:sub(1, -4):lower()
        local fileSplits = hs.fnutils.split(lowerFile:gsub('_', '-'), '-')
        if hs.fnutils.contains(fileSplits, language) then
          table.insert(languageMatches, { fileSplits, dir .. '/' .. file, language })
        end
      end
    end
    if #languageMatches == 1 then
      return languageMatches[1][3], languageMatches[1][2]
    elseif #languageMatches > 1 then
      local countryMatches = {}
      for _, item in ipairs(languageMatches) do
        if country ~= nil and hs.fnutils.contains(item[1], country) then
          table.insert(item, country)
          table.insert(countryMatches, item)
        end
      end
      if #countryMatches == 1 then
        return countryMatches[1][3] .. '-' .. countryMatches[1][4]:upper(), languageMatches[1][2]
      elseif #countryMatches > 1 then
        for _, item in ipairs(countryMatches) do
          if script ~= nil and hs.fnutils.contains(item[1], script) then
            local capitalScript = script:sub(1, 1):upper() .. script:sub(2)
            return item[3] .. '-' .. capitalScript .. '-' .. item[4]:upper(), item[2]
          end
        end
        local allFiles = hs.fnutils.imap(countryMatches, function(item) return item[2] end)
        return countryMatches[1][3] .. '-' .. countryMatches[1][4]:upper(), allFiles
      end
    end
  end
end

local preferentialStringsFilePatterns = { "(.-)MainMenu(.-)", "Menu", "MenuBar",
  "MenuItems", "Localizable", "Main", "MainWindow" }

local function parseStringsFile(file, keepOrder, keepAll)
  if keepOrder == nil then keepOrder = true end
  local jsonStr = hs.execute(string.format("plutil -convert json -o - '%s'", file))
  local jsonDict = hs.json.decode(jsonStr)
  if keepOrder then return jsonDict end
  local localesDict = {}
  for k, v in pairs(jsonDict) do
    if localesDict[v] == nil then
      localesDict[v] = k
    elseif keepAll then
      if type(localesDict[v]) == 'string' then
        localesDict[v] = { localesDict[v], k }
      else
        table.insert(localesDict[v], k)
      end
    end
  end
  return localesDict
end

local function localizeByLoctableImpl(str, filePath, fileStem, locale, localesDict)
  if localesDict[fileStem] == nil then localesDict[fileStem] = {} end
  if localesDict[fileStem][str] ~= nil then
    return localesDict[fileStem][str]
  end

  local output, status = hs.execute(string.format(
      "/usr/bin/python3 scripts/loctable_localize.py '%s' '%s' %s",
      filePath, str, locale))
  if status and output ~= "" then
    localesDict[fileStem][str] = output
    return output
  end
end

local function localizeByLoctable(str, resourceDir, localeFile, loc, localesDict)
  if localeFile ~= nil then
    local fullPath = resourceDir .. '/' .. localeFile .. '.loctable'
    if hs.fs.attributes(fullPath) ~= nil then
      return localizeByLoctableImpl(str, fullPath, localeFile, loc, localesDict)
    end
  else
    local stringsFiles = {}
    local preferentialStringsFiles = {}
    for file in hs.fs.dir(resourceDir) do
      if file:sub(-9) == ".loctable" then
        table.insert(stringsFiles, file)
      end
    end
    if #stringsFiles > 10 then
      for i = #stringsFiles, 1, -1 do
        for _, p in ipairs(preferentialStringsFilePatterns) do
          local pattern = "^" .. p .. "%.loctable$"
          if string.match(stringsFiles[i], pattern) ~= nil then
            table.insert(preferentialStringsFiles, stringsFiles[i])
            table.remove(stringsFiles, i)
            break
          end
        end
      end
    end
    for _, file in ipairs(preferentialStringsFiles) do
      local fullPath = resourceDir .. '/' .. file
      local fileStem = file:sub(1, -10)
      local result = localizeByLoctableImpl(str, fullPath, fileStem, loc, localesDict)
      if result ~= nil then return result end
    end
    for _, file in ipairs(stringsFiles) do
      local fullPath = resourceDir .. '/' .. file
      local fileStem = file:sub(1, -10)
      local result = localizeByLoctableImpl(str, fullPath, fileStem, loc, localesDict)
      if result ~= nil then return result end
    end
  end
end

local function localizeByStrings(str, localeDir, localeFile, locale, localesDict, localesInvDict)
  local resourceDir = localeDir .. '/..'
  local searchFunc = function(str, stringsFiles, localeDir)
    if type(stringsFiles) == 'string' then
      stringsFiles = {stringsFiles}
    end
    for _, file in ipairs(stringsFiles) do
      local fileStem = file:sub(1, -9)
      local jsonDict = localesDict[fileStem]
      if jsonDict == nil
          or (locale == 'en' and string.find(localeDir, 'en.lproj') == nil) then
        local fullPath = localeDir .. '/' .. file
        if hs.fs.attributes(fullPath) ~= nil then
          jsonDict = parseStringsFile(fullPath)
        end
      end
      if jsonDict ~= nil and jsonDict[str] ~= nil then
        localesDict[fileStem] = jsonDict
        return jsonDict[str]
      end
    end
  end

  local stringsFiles = {}
  local preferentialStringsFiles = {}
  for file in hs.fs.dir(localeDir) do
    if file:sub(-8) == ".strings" then
      table.insert(stringsFiles, file)
    end
  end
  if #stringsFiles > 10 then
    for i = #stringsFiles, 1, -1 do
      for _, p in ipairs(preferentialStringsFilePatterns) do
        local pattern = "^" .. p .. "%.strings$"
        if string.match(stringsFiles[i], pattern) ~= nil then
          table.insert(preferentialStringsFiles, stringsFiles[i])
          table.remove(stringsFiles, i)
          break
        end
      end
    end
  end
  local result
  if localeFile ~= nil then
    result = searchFunc(str, localeFile .. '.strings', localeDir)
    if result ~= nil then return result end
  else
    result = searchFunc(str, preferentialStringsFiles, localeDir)
    if result ~= nil then return result end
  end
  if locale == 'en' then
    for _, _localeDir in ipairs{
        resourceDir .. "/English.lproj",
        resourceDir .. "/Base.lproj",
        resourceDir .. "/en_GB.lproj"} do
      if hs.fs.attributes(_localeDir) ~= nil then
        if localeFile ~= nil then
          result = searchFunc(str, localeFile .. '.strings', _localeDir)
          if result ~= nil then return result end
        else
          result = searchFunc(str, preferentialStringsFiles, _localeDir)
          if result ~= nil then return result end
        end
      end
    end
  end

  local invSearchFunc = function(str, stringsFiles, localeDir)
    for _, enLocaleDir in ipairs{
        resourceDir .. "/en.lproj",
        resourceDir .. "/English.lproj",
        resourceDir .. "/Base.lproj",
        resourceDir .. "/en_GB.lproj"} do
      if hs.fs.attributes(enLocaleDir) ~= nil then
        if localeFile ~= nil then
          if localesInvDict[localeFile] == nil then
            local fullPath = enLocaleDir .. '/' .. localeFile .. '.strings'
            if hs.fs.attributes(fullPath) ~= nil then
              localesInvDict[localeFile] = parseStringsFile(fullPath, false)
            end
          end
          if localesInvDict[localeFile] ~= nil
              and localesInvDict[localeFile][str] ~= nil then
            local result = searchFunc(localesInvDict[localeFile][str],
                                      localeFile .. '.strings', localeDir)
            if result ~= nil then return result end
          end
          localesInvDict[localeFile] = nil
        else
          for _, file in ipairs(stringsFiles) do
            local fileStem = file:sub(1, -9)
            if localesInvDict[fileStem] == nil then
              local fullPath = enLocaleDir .. '/' .. file
              if hs.fs.attributes(fullPath) ~= nil then
                localesInvDict[fileStem] = parseStringsFile(fullPath, false)
              end
            end
            if localesInvDict[fileStem] ~= nil
                and localesInvDict[fileStem][str] ~= nil then
              local result = searchFunc(localesInvDict[fileStem][str], file, localeDir)
              if result ~= nil then return result end
            end
            localesInvDict[fileStem] = nil
          end
        end
      end
    end
  end
  result = invSearchFunc(str, preferentialStringsFiles, localeDir)
  if result ~= nil then return result end

  if localeFile ~= nil then
    result = searchFunc(str, localeFile .. '.strings', localeDir)
    if result ~= nil then return result end
  else
    result = searchFunc(str, stringsFiles, localeDir)
    if result ~= nil then return result end
  end
  if locale == 'en' then
    for _, _localeDir in ipairs{
        resourceDir .. "/English.lproj",
        resourceDir .. "/Base.lproj",
        resourceDir .. "/en_GB.lproj"} do
      if hs.fs.attributes(_localeDir) ~= nil then
        if localeFile ~= nil then
          result = searchFunc(str, localeFile .. '.strings', _localeDir)
          if result ~= nil then return result end
        else
          result = searchFunc(str, stringsFiles, _localeDir)
          if result ~= nil then return result end
        end
      end
    end
  end
  result = invSearchFunc(str, stringsFiles, localeDir)
  if result ~= nil then return result end
end

local function localizeByQtImpl(str, dir, file, localesDict)
  local fileStem = file:sub(1, -4)
  if localesDict[fileStem] ~= nil and localesDict[fileStem][str] ~= nil then
    return localesDict[fileStem][str]
  end
  local output, status = hs.execute(string.format(
      "zsh scripts/qm_localize.sh '%s' '%s'", dir .. '/' .. file, str))
  if status and output ~= "" then
    if localesDict[fileStem] == nil then localesDict[fileStem] = {} end
    localesDict[fileStem][str] = output
    return output
  end
end

local function localizeByQt(str, localeDir, localesDict)
  if type(localeDir) == 'table' then
    for _, filepath in ipairs(localeDir) do
      local dir, file = filepath:match("^(.*)/(.*)$")
      local result = localizeByQtImpl(str, dir, file, localesDict)
      if result ~= nil then return result end
    end
  elseif hs.fs.attributes(localeDir, 'mode') == 'file' then
    local dir, file = localeDir:match("^(.*)/(.*)$")
    return localizeByQtImpl(str, dir, file, localesDict)
  else
    for file in hs.fs.dir(localeDir) do
      if file:sub(-3) == ".qm" then
        local result = localizeByQtImpl(str, localeDir, file, localesDict)
        if result ~= nil then return result end
      end
    end
  end
end

local function dirNotExistOrEmpty(dir)
  if hs.fs.attributes(dir) == nil then return true end
  for file in hs.fs.dir(dir) do
    if string.sub(file, 1, 1) ~= '.' then return false end
  end
  return true
end

local function localizeByChromium(str, localeDir, localesDict, bundleID)
  local resourceDir = localeDir .. '/..'
  local locale = localeDir:match("^.*/(.*)%.lproj$")
  for _, enLocale in ipairs{"en", "English", "Base", "en_GB"} do
    if hs.fs.attributes(resourceDir .. '/' .. enLocale .. '.lproj') ~= nil then
      for file in hs.fs.dir(resourceDir .. '/' .. enLocale .. '.lproj') do
        if file:sub(-4) == ".pak" then
          local fullPath = resourceDir .. '/' .. enLocale .. '.lproj/' .. file
          local fileStem = file:sub(1, -5)
          local enTmpdir = string.format(localeTmpDir .. '%s-%s-%s', bundleID, enLocale, fileStem)
          if dirNotExistOrEmpty(enTmpdir) then
            hs.execute(string.format(
                "scripts/pak -u '%s' '%s'", fullPath, enTmpdir))
          end
          local output, status = hs.execute("grep -lrE '^" .. str .. "$' '" .. enTmpdir .. "' | tr -d '\\n'")
          if status and output ~= "" then
            if hs.fs.attributes(localeDir .. '/' .. file) then
              local matchFile = output:match("^.*/(.*)$")
              local tmpdir = string.format(localeTmpDir .. '%s-%s-%s', bundleID, locale, fileStem)
              if dirNotExistOrEmpty(tmpdir) then
                hs.execute(string.format(
                    "scripts/pak -u '%s' '%s'", localeDir .. '/' .. file, tmpdir))
              end
              local matchFullPath = tmpdir .. '/' .. matchFile
              if hs.fs.attributes(matchFullPath) ~= nil then
                local f = io.open(matchFullPath, "r")
                if f ~= nil then
                  local content = f:read("*a")
                  f:close()
                  if localesDict[fileStem] == nil then
                    localesDict[fileStem] = {}
                  end
                  localesDict[fileStem][str] = content
                  return content
                end
              end
            end
          end
        end
      end
    end
  end
  return nil
end

local appLocaleMap = {}
local appLocaleDir = {}
local appLocaleAssetBuffer = {}
local appLocaleAssetBufferInverse = {}
local localeTmpFile = localeTmpDir .. 'strings.json'
if hs.fs.attributes(localeTmpFile) ~= nil then
  local json = hs.json.read(localeTmpFile)
  appLocaleDir = json.locale
  appLocaleMap = json.map
end

function localizedString(str, bundleID, params)
  local appLocale, localeFile, localeDir, localeFramework, key
  if type(params) == "table" then
    appLocale = params.locale
    localeFile = params.localeFile
    localeDir = params.localeDir
    localeFramework = params.framework
    key = params.key
  else
    localeFile = params
  end

  if appLocale == nil then
    local locales = applicationLocales(bundleID)
    appLocale = locales[1]
  end
  local localeDetails = hs.host.locale.details(appLocale)
  if localeDetails.languageCode == 'en' and key ~= true then
    return str
  end

  local result = get(appLocaleMap, bundleID, appLocale, str)
  if result == false then return nil
  elseif result ~= nil then return result end

  if hs.application.pathForBundleID(bundleID) == nil
      or hs.application.pathForBundleID(bundleID) == "" then
    return nil
  end

  local resourceDir, framework = getResourceDir(bundleID, localeFramework)
  if framework.chromium then
    if findApplication(bundleID) then
      local menuItems = getMenuItems(findApplication(bundleID))
      table.remove(menuItems, 1)
      for _, title in ipairs{ 'File', 'Edit', 'Window', 'Help' } do
        if hs.fnutils.find(menuItems, function(item) return item.AXTitle == title end) ~= nil then
          return str
        end
      end
    end
  end

  if appLocaleMap[bundleID] == nil then
    appLocaleMap[bundleID] = {}
  end
  if appLocaleMap[bundleID][appLocale] == nil then
    appLocaleMap[bundleID][appLocale] = {}
  end
  if appLocaleDir[bundleID] == nil then
    appLocaleDir[bundleID] = {}
  end
  if appLocaleAssetBuffer[bundleID] == nil then
    appLocaleAssetBuffer[bundleID] = {}
  end
  if appLocaleAssetBuffer[bundleID][appLocale] == nil then
    appLocaleAssetBuffer[bundleID][appLocale] = {}
  end
  local localesDict = appLocaleAssetBuffer[bundleID][appLocale]

  local locale
  if localeDir == nil or localeDir == false then
    local mode = localeDir == nil and 'lproj' or 'strings'
    if locale == nil then
      locale = appLocaleDir[bundleID][appLocale]
      if locale == false then return nil end
    end
    if locale == nil then
      locale = getMatchedLocale(appLocale, resourceDir, mode)
      if locale == nil and framework.qt then
        locale, localeDir = getQtMatchedLocale(appLocale, resourceDir)
      end
      if locale == nil then
        appLocaleDir[bundleID][appLocale] = false
        appLocaleMap[bundleID][appLocale] = nil
        return nil
      end
    end
    appLocaleDir[bundleID][appLocale] = locale
    if mode == 'strings' then
      localeDir = resourceDir
      if localeFile == nil then localeFile = locale end
    elseif localeDir == nil then
      localeDir = resourceDir .. "/" .. locale .. ".lproj"
    end
    if framework.qt and type(localeDir) == 'string'
        and hs.fs.attributes(localeDir) == nil then
      _, localeDir = getQtMatchedLocale(appLocale, resourceDir)
    end
  end

  if framework.chromium then
    result = localizeByChromium(str, localeDir, localesDict, bundleID)
    goto L_END_LOCALIZED
  end

  if framework.qt then
    result = localizeByQt(str, localeDir, localesDict)
    goto L_END_LOCALIZED
  end

  if locale ~= nil then
    result = localizeByLoctable(str, resourceDir, localeFile, locale, localesDict)
    if result ~= nil then goto L_END_LOCALIZED end

    if appLocaleAssetBufferInverse[bundleID] == nil then
      appLocaleAssetBufferInverse[bundleID] = {}
    end
    if LOCALE_KEY_MAP[bundleID] ~= nil then
      local key = hs.fnutils.indexOf(LOCALE_KEY_MAP[bundleID], str)
      if key ~= nil then
        result = localizeByStrings(key, localeDir, localeFile, locale, localesDict,
                                  appLocaleAssetBufferInverse[bundleID])
        if result ~= nil then goto L_END_LOCALIZED end
      end
    end
    result = localizeByStrings(str, localeDir, localeFile, locale, localesDict,
                               appLocaleAssetBufferInverse[bundleID])
    if result ~= nil then goto L_END_LOCALIZED end
  end

  if result == nil and
      (string.sub(str, -3) == "..." or string.sub(str, -3) == "…") then
    result = localizedString(string.sub(str, 1, -4), bundleID, params)
    if result ~= nil then
      result = result .. string.sub(str, -3)
    end
  end

  ::L_END_LOCALIZED::
  if result ~= nil then
    if hs.fs.attributes(localeTmpDir) == nil then
      hs.execute(string.format("mkdir -p '%s'", localeTmpDir))
    end
    appLocaleMap[bundleID][appLocale][str] = result
    hs.json.write({ locale = appLocaleDir, map = appLocaleMap },
                  localeTmpFile, false, true)
  else
    appLocaleMap[bundleID][appLocale][str] = false
  end
  return result
end


local function delocalizeByLoctableImpl(str, filePath, locale)
  local output, status = hs.execute(string.format(
      "/usr/bin/python3 scripts/loctable_delocalize.py '%s' '%s' %s",
      filePath, str, locale))
  if status and output ~= "" then return output end
end

local function delocalizeByLoctable(str, resourceDir, localeFile, locale)
  if localeFile ~= nil then
    local fullPath = resourceDir .. '/' .. localeFile .. '.loctable'
    if hs.fs.attributes(fullPath) ~= nil then
      return delocalizeByLoctableImpl(str, fullPath, locale)
    end
  else
    local loctableFiles = {}
    for file in hs.fs.dir(resourceDir) do
      if file:sub(-9) == ".loctable" then
        table.insert(loctableFiles, file)
      end
    end
    if #loctableFiles > 10 then
      loctableFiles = hs.fnutils.filter(loctableFiles, function(file)
        for _, pattern in ipairs(preferentialStringsFilePatterns) do
          local pattern = "^" .. pattern  .. "%.loctable$"
          if string.match(file, pattern) ~= nil then return true end
        end
        return false
      end)
    end
    for _, file in ipairs(loctableFiles) do
      local result = delocalizeByLoctableImpl(str, resourceDir .. '/' .. file, locale)
      if result ~= nil then return result end
    end
  end
end

local function delocalizeByQtImpl(str, file)
  local output, status = hs.execute(string.format(
      "zsh scripts/qm_delocalize.sh '%s' '%s'", file, str))
  if status and output ~= "" then return output end
end

local function delocalizeByQt(str, localeDir)
  if type(localeDir) == 'table' then
    for _, file in ipairs(localeDir) do
      local result = delocalizeByQtImpl(str, file)
      if result ~= nil then return result end
    end
  elseif hs.fs.attributes(localeDir, 'mode') == 'file' then
    return delocalizeByQtImpl(str, localeDir)
  else
    for file in hs.fs.dir(localeDir) do
      if file:sub(-3) == ".qm" then
        local result = delocalizeByQtImpl(str, localeDir .. '/' .. file)
        if result ~= "" then return result end
      end
    end
  end
end

local function delocalizeByMono(str, localeDir)
  for file in hs.fs.dir(localeDir .. '/LC_MESSAGES') do
    if file:sub(-3) == ".mo" then
      local output, status = hs.execute(string.format(
          "zsh scripts/mono_delocalize.sh '%s' '%s'",
          localeDir .. '/LC_MESSAGES/' .. file, str))
      if status and output ~= "" then return output end
    end
  end
end

local function delocalizeByChromium(str, localeDir, bundleID)
  local resourceDir = localeDir .. '/..'
  local locale = localeDir:match("^.*/(.*)%.lproj$")
  for file in hs.fs.dir(localeDir) do
    if file:sub(-4) == ".pak" then
      local fileStem = file:sub(1, -5)
      local tmpdir = string.format(localeTmpDir .. '%s-%s-%s', bundleID, locale, fileStem)
      if dirNotExistOrEmpty(tmpdir) then
        hs.execute(string.format(
          "scripts/pak  -u '%s' '%s'", localeDir .. '/' .. file, tmpdir))
      end
      local pattern = '^' .. str .. '$'
      local output, status = hs.execute(string.format(
            "grep -lrE '%s' '%s' | tr -d '\\n'", pattern, tmpdir))
      if status and output ~= "" then
        local matchFile = output:match("^.*/(.*)$")
        for _, enLocale in ipairs{"en", "English", "Base", "en_GB"} do
          local fullPath = resourceDir .. '/' .. enLocale .. '.lproj/' .. file
          if hs.fs.attributes(fullPath) ~= nil then
            local enTmpdir = string.format(localeTmpDir .. '%s-%s-%s', bundleID, enLocale, fileStem)
            if dirNotExistOrEmpty(enTmpdir) then
              hs.execute(string.format(
                "scripts/pak  -u '%s' '%s'", fullPath, enTmpdir))
            end
            local matchFullPath = enTmpdir .. '/' .. matchFile
            if hs.fs.attributes(matchFullPath) ~= nil then
              local f = io.open(matchFullPath, "r")
              if f ~= nil then
                local content = f:read("*a")
                f:close()
                return content
              end
            end
          end
        end
      end
    end
  end
  return nil
end

local function delocalizeZoteroMenu(str, appLocale)
  local resourceDir = hs.application.pathForBundleID("org.zotero.zotero") .. "/Contents/Resources"
  local locales, status = hs.execute("unzip -l \"" .. resourceDir .. "/zotero.jar\" 'chrome/locale/*/' | grep -Eo 'chrome/locale/[^/]*' | grep -Eo '[a-zA-Z-]*$' | uniq")
  if status ~= true then return nil end
  local locale = getMatchedLocale(appLocale, hs.fnutils.split(locales, '\n'))
  if locale == nil then return nil end
  local localeFile = 'chrome/locale/' .. locale .. '/zotero/standalone.dtd'
  local enLocaleFile = 'chrome/locale/en-US/zotero/standalone.dtd'
  local key, status = hs.execute("unzip -p \"" .. resourceDir .. "/zotero.jar\" \"" .. localeFile .. "\""
      .. " | awk '/<!ENTITY .* \"" .. str .. "\">/ { gsub(/<!ENTITY | \"" .. str .. "\">/, \"\"); printf \"%s\", $0 }'")
  if status ~= true then return nil end
  local enValue, status = hs.execute("unzip -p \"" .. resourceDir .. "/zotero.jar\" \"" .. enLocaleFile .. "\""
      .. " | grep '" .. key .. "' | cut -d '\"' -f 2 | tr -d '\\n'")
  if status ~= true then return nil end

  return enValue, locale
end

local function delocalizeMATLABFigureMenu(str, appLocale)
  local resourceDir = hs.application.pathForBundleID("com.mathworks.matlab") .. "/resources/MATLAB"
  local locale = getMatchedLocale(appLocale, resourceDir)
  if locale == nil then return nil end
  local localeFile = resourceDir .. '/' .. locale .. '/uistring/figuremenu.xml'
  local enLocaleFile = resourceDir .. '/en/uistring/figuremenu.xml'
  local shell_pattern = 'key="([^"]*?)">' .. str .. '\\(&amp;[A-Z]\\)</entry>'
  local key, status = hs.execute(string.format(
      "grep -Eo '%s' '%s' | cut -d '\"' -f 2 | tr -d '\\n'", shell_pattern, localeFile))
  if status and key ~= "" then
    local inverse_pattern = 'key="' .. key .. '">&amp;([^<]*?)</entry>'
    local enValue, status = hs.execute(string.format(
        "grep -Eo '%s' '%s' | cut -d ';' -f 2  | cut -d '<' -f 1 | tr -d '\\n'", inverse_pattern, enLocaleFile))
    if status and enValue ~= "" then return enValue, locale end
  end
  return nil
end

local menuItemLocaleMap = {}
local menuItemLocaleDir = {}
local menuItemLocaleInversedMap = {}
local menuItemTmpFile = localeTmpDir .. 'menuitems.json'
if hs.fs.attributes(menuItemTmpFile) ~= nil then
  local json = hs.json.read(menuItemTmpFile)
  menuItemLocaleDir = json.locale
  menuItemLocaleMap = json.map
end
function delocalizedString(str, bundleID, params)
  local appLocale, localeFile, localeFramework
  if type(params) == "table" then
    appLocale = params.locale
    localeFile = params.localeFile
    localeFramework = params.framework
  else
    localeFile = params
  end

  if appLocale == nil then
    local locales = applicationLocales(bundleID)
    appLocale = locales[1]
  end
  local localeDetails = hs.host.locale.details(appLocale)
  if localeDetails.languageCode == 'en' then return str end

  local result = get(menuItemLocaleMap, bundleID, str)
  if result == false then return nil
  elseif result ~= nil then return result end

  local resourceDir, framework = getResourceDir(bundleID, localeFramework)
  if framework.chromium then
    if findApplication(bundleID) then
      local menuItems = getMenuItems(findApplication(bundleID))
      table.remove(menuItems, 1)
      for _, title in ipairs{ 'File', 'Edit', 'Window', 'Help' } do
        if hs.fnutils.find(menuItems, function(item) return item.AXTitle == title end) ~= nil then
          return str
        end
      end
    end
  end

  if menuItemLocaleMap[bundleID] == nil then
    menuItemLocaleMap[bundleID] = {}
  end
  if menuItemLocaleInversedMap[bundleID] == nil then
    menuItemLocaleInversedMap[bundleID] = {}
  end
  if menuItemLocaleDir[bundleID] == nil then
    menuItemLocaleDir[bundleID] = {}
  end
  if menuItemLocaleDir[bundleID][appLocale] == nil then
    menuItemLocaleDir[bundleID] = {}
    menuItemLocaleMap[bundleID] = {}
    menuItemLocaleInversedMap[bundleID] = {}
  end

  local locale, localeDir, mode, searchFunc

  if bundleID == "org.zotero.zotero" then
    result, locale = delocalizeZoteroMenu(str, appLocale)
    if menuItemLocaleDir[bundleID][appLocale] ~= nil
        and menuItemLocaleDir[bundleID][appLocale] ~= locale then
      menuItemLocaleMap[bundleID] = {}
    end
    menuItemLocaleDir[bundleID][appLocale] = locale
    goto L_END_DELOCALIZED
  elseif bundleID == "com.mathworks.matlab" then
    result, locale = delocalizeMATLABFigureMenu(str, appLocale)
    if menuItemLocaleDir[bundleID][appLocale] ~= nil
        and menuItemLocaleDir[bundleID][appLocale] ~= locale then
      menuItemLocaleMap[bundleID] = {}
    end
    menuItemLocaleDir[bundleID][appLocale] = locale
    goto L_END_DELOCALIZED
  end

  if not framework.mono then mode = 'lproj' end
  if locale == nil then
    locale = menuItemLocaleDir[bundleID][appLocale]
    if locale == false then return nil end
  end
  if locale == nil then
    locale = getMatchedLocale(appLocale, resourceDir, mode)
    if locale == nil and framework.qt then
      locale, localeDir = getQtMatchedLocale(appLocale, resourceDir)
    end
    if locale == nil then
      menuItemLocaleDir[bundleID][appLocale] = false
      menuItemLocaleMap[bundleID][appLocale] = nil
      return nil
    end
  end
  menuItemLocaleDir[bundleID][appLocale] = locale
  if localeDir == nil then
    if mode == 'lproj' then
      localeDir = resourceDir .. "/" .. locale .. ".lproj"
    else
      localeDir = resourceDir .. "/" .. locale
    end
    if framework.qt and type(localeDir) == 'string'
        and hs.fs.attributes(localeDir) == nil then
      _, localeDir = getQtMatchedLocale(appLocale, resourceDir)
    end
  end

  if framework.chromium then
    result = delocalizeByChromium(str, localeDir, bundleID)
    goto L_END_DELOCALIZED
  end

  if framework.mono then
    result = delocalizeByMono(str, localeDir)
    if result ~= nil then
      if bundleID == "com.microsoft.visual-studio" then
        result = result:gsub('_', '')
      end
    end
    goto L_END_DELOCALIZED
  end

  if framework.qt then
    result = delocalizeByQt(str, localeDir)
    goto L_END_DELOCALIZED
  end

  result = delocalizeByLoctable(str, resourceDir, localeFile, locale)
  if result ~= nil then goto L_END_DELOCALIZED end

  searchFunc = function(str)
    for _, localeDir in ipairs {
        resourceDir .. "/en.lproj",
        resourceDir .. "/English.lproj",
        resourceDir .. "/Base.lproj",
        resourceDir .. "/en_GB.lproj" } do
      if hs.fs.attributes(localeDir) ~= nil then
        if localeFile ~= nil then
          local fullPath = localeDir .. '/' .. localeFile .. '.strings'
          if hs.fs.attributes(fullPath) ~= nil then
            local jsonDict = parseStringsFile(fullPath)
            return jsonDict[str]
          end
        else
          local stringsFiles = {}
          for file in hs.fs.dir(localeDir) do
            if file:sub(-8) == ".strings" then
              table.insert(stringsFiles, file)
            end
          end
          if #stringsFiles > 10 then
            stringsFiles = hs.fnutils.filter(stringsFiles, function(file)
              for _, pattern in ipairs(preferentialStringsFilePatterns) do
                local pattern = "^" .. pattern .. "%.strings$"
                if string.match(file, pattern) ~= nil then return true end
              end
              return false
            end)
          end
          for _, file in ipairs(stringsFiles) do
            local fullPath = localeDir .. '/' .. file
            local jsonDict = parseStringsFile(fullPath)
            if jsonDict[str] ~= nil then
              return jsonDict[str]
            end
          end
        end
      end
    end
  end

  if localeFile ~= nil then
    if menuItemLocaleInversedMap[bundleID][str] == nil then
      local fullPath = localeDir .. '/' .. localeFile .. '.strings'
      if hs.fs.attributes(fullPath) ~= nil then
        menuItemLocaleInversedMap[bundleID] = parseStringsFile(fullPath, false, true)
      end
    end
    if menuItemLocaleInversedMap[bundleID] ~= nil
        and menuItemLocaleInversedMap[bundleID][str] ~= nil then
      local keys = menuItemLocaleInversedMap[bundleID][str]
      if type(keys) == 'string' then keys = {keys} end
      for _, k in ipairs(keys) do
        result = searchFunc(k)
        if result ~= nil then
          goto L_END_DELOCALIZED
        elseif LOCALE_KEY_MAP[bundleID] ~= nil then
          result = LOCALE_KEY_MAP[bundleID][k]
          if result ~= nil then goto L_END_DELOCALIZED end
        end
      end
      for _, k in ipairs(keys) do
        if not(string.match(k, "[^%a ]")) then
          result = k
          goto L_END_DELOCALIZED
        end
      end
    end
  else
    local stringsFiles = {}
    for file in hs.fs.dir(localeDir) do
      if file:sub(-8) == ".strings" then
        table.insert(stringsFiles, file)
      end
    end
    if #stringsFiles > 10 then
      stringsFiles = hs.fnutils.filter(stringsFiles, function(file)
        for _, pattern in ipairs(preferentialStringsFilePatterns) do
          local pattern = "^" .. pattern .. "%.strings$"
          if string.match(file, pattern) ~= nil then return true end
        end
        return false
      end)
    end
    for _, file in ipairs(stringsFiles) do
      if menuItemLocaleInversedMap[bundleID][str] == nil then
        local fullPath = localeDir .. '/' .. file
        menuItemLocaleInversedMap[bundleID] = parseStringsFile(fullPath, false, true)
      end
      if menuItemLocaleInversedMap[bundleID][str] ~= nil then
        local keys = menuItemLocaleInversedMap[bundleID][str]
        if type(keys) == 'string' then keys = {keys} end
        for _, k in ipairs(keys) do
          localeFile = file:sub(1, -9)
          result = searchFunc(k)
          if result ~= nil then
            goto L_END_DELOCALIZED
          elseif LOCALE_KEY_MAP[bundleID] ~= nil then
            result = LOCALE_KEY_MAP[bundleID][k]
            if result ~= nil then goto L_END_DELOCALIZED end
          end
        end
        for _, k in ipairs(keys) do
          if not(string.match(k, "[^%a ]")) then
            result = k
            goto L_END_DELOCALIZED
          end
        end
      end
    end
  end

  if bundleID:match("^com%.charliemonroe%..*$") and localeFramework == nil then
    result = delocalizedString(str, bundleID,
                                       { framework = "XUCore.framework" })
    if result ~= nil then return result end
  end

  if result == nil and
      (string.sub(str, -3) == "..." or string.sub(str, -3) == "…") then
    result = delocalizedString(string.sub(str, 1, -4), bundleID, params)
    if result ~= nil then
      result = result .. string.sub(str, -3)
    end
  end

  ::L_END_DELOCALIZED::
  if result ~= nil then
    if hs.fs.attributes(localeTmpDir) == nil then
      hs.execute(string.format("mkdir -p '%s'", localeTmpDir))
    end
    menuItemLocaleMap[bundleID][str] = result
    hs.json.write({ locale = menuItemLocaleDir, map = menuItemLocaleMap },
        menuItemTmpFile, false, true)
  else
    menuItemLocaleMap[bundleID][str] = false
  end
  return result
end

local menuBarTitleLocalizationMap
function delocalizedMenuBarItem(title, bundleID, params)
  local defaultTitleMap, titleMap
  if menuBarTitleLocalizationMap ~= nil then
    defaultTitleMap = menuBarTitleLocalizationMap.common
    titleMap = menuBarTitleLocalizationMap[bundleID]
  end
  if titleMap ~= nil then
    if titleMap[title] ~= nil then
      return titleMap[title]
    end
  end
  if defaultTitleMap ~= nil then
    if defaultTitleMap[title] ~= nil then
      return defaultTitleMap[title]
    elseif hs.fnutils.indexOf(defaultTitleMap, title) ~= nil then
      return title
    end
  end
  local newTitle = delocalizedString(title, bundleID, params)
  return newTitle
end

function delocalizeMenuBarItems(itemTitles, bundleID, localeFile)
  if menuBarTitleLocalizationMap[bundleID] == nil then
    menuBarTitleLocalizationMap[bundleID] = {}
  end
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
      if titleMap[title] ~= nil then
        table.insert(result, { title, titleMap[title] })
        goto L_CONTINUE
      end
      if defaultTitleMap ~= nil then
        if defaultTitleMap[title] ~= nil then
          table.insert(result, { title, defaultTitleMap[title] })
          titleMap[title] = defaultTitleMap[title]
          goto L_CONTINUE
        end
      end
      local newTitle = delocalizedString(title, bundleID, localeFile)
      if newTitle ~= nil then
        table.insert(result, { title, newTitle })
        titleMap[title] = newTitle
      end
      ::L_CONTINUE::
    end
  end
  return result
end

local menuBarTitleLocalizationMapLoaded = {}
menuBarTitleLocalizationMap = {}
if hs.fs.attributes("config/menuitem-localization.json") ~= nil then
  menuBarTitleLocalizationMapLoaded = hs.json.read("config/menuitem-localization.json")
  menuBarTitleLocalizationMap = hs.fnutils.copy(menuBarTitleLocalizationMapLoaded)
end
LOCALE_KEY_MAP = {}
if hs.fs.attributes("static/localization-keys.json") ~= nil then
  LOCALE_KEY_MAP = hs.json.read("static/localization-keys.json")
end
menuBarTitleLocalizationMap.common = {}
local systemLocale = systemLocales()[1]
for _, title in ipairs{ 'File', 'Edit', 'Format', 'View', 'Window', 'Help' } do
  local localizedTitle = localizedString(title, "com.apple.Notes",
                                          { locale = systemLocale })
  if localizedTitle ~= nil then
    menuBarTitleLocalizationMap.common[localizedTitle] = title
  end
end
local localizedTitle = localizedString('View', "com.apple.finder",
                                      { locale = systemLocale })
if localizedTitle ~= nil then
  menuBarTitleLocalizationMap.common[localizedTitle] = 'View'
end

function localizedMenuBarItem(title, bundleID, params)
  local appLocale = applicationLocales(bundleID)[1]
  if menuItemLocaleDir[bundleID] ~= nil
      and menuItemLocaleDir[bundleID][appLocale] == nil then
    menuBarTitleLocalizationMap[bundleID] = menuBarTitleLocalizationMapLoaded[bundleID]
  end
  local locTitle = hs.fnutils.indexOf(menuBarTitleLocalizationMap[bundleID] or {}, title)
  if locTitle ~= nil then
    if title == 'View' and findApplication(bundleID) then
      local menuItems = getMenuItems(findApplication(bundleID))
      table.remove(menuItems, 1)
      if hs.fnutils.find(menuItems, function(item) return item.AXTitle == locTitle end) ~= nil then
        return locTitle
      end
    else
      return locTitle
    end
  end
  if findApplication(bundleID) then
    local menuItems = getMenuItems(findApplication(bundleID))
    table.remove(menuItems, 1)
    if hs.fnutils.find(menuItems, function(item) return item.AXTitle == title end) ~= nil then
      return title
    end
  end
  if appLocale == systemLocale then
    locTitle = hs.fnutils.indexOf(menuBarTitleLocalizationMap.common, title)
    if locTitle ~= nil then return locTitle end
  end
  locTitle = localizedString(title, bundleID, params)
  if locTitle ~= nil then
    if menuBarTitleLocalizationMap[bundleID] == nil then
      menuBarTitleLocalizationMap[bundleID] = {}
    end
    menuBarTitleLocalizationMap[bundleID][locTitle] = title
    return locTitle
  end
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

function leftClick(position, appName)
  if position.x == nil then position = hs.geometry.point(position) end
  if appName ~= nil then
    local appHere = hs.axuielement.systemElementAtPosition(position)
    while appHere ~= nil and appHere.AXParent ~= nil do
      appHere = appHere.AXParent
    end
    if appHere.AXTitle ~= appName then return false end
  end
  hs.eventtap.leftClick(hs.geometry.point(position))
  return true
end

function leftClickAndRestore(position, appName)
  local mousePosition = hs.mouse.absolutePosition()
  if leftClick(position, appName) then
    hs.mouse.absolutePosition(mousePosition)
    return true
  end
  return false
end

function rightClick(position, appName)
  if position.x == nil then position = hs.geometry.point(position) end
  if appName ~= nil then
    local appHere = hs.axuielement.systemElementAtPosition(position)
    while appHere.AXParent ~= nil do
      appHere = appHere.AXParent
    end
    if appHere.AXTitle ~= appName then return false end
  end
  hs.eventtap.rightClick(hs.geometry.point(position))
  return true
end

function rightClickAndRestore(position, appName)
  local mousePosition = hs.mouse.absolutePosition()
  if rightClick(position, appName) then
    hs.mouse.absolutePosition(mousePosition)
    return true
  end
  return false
end

function clickAppRightMenuBarItem(bundleID, menuItem, subMenuItem, show)
  if menuItem == nil and subMenuItem == nil and show == nil then
    show = true
  end

  local initCmd = string.format([[
      tell application "System Events"
        set ap to first application process whose bundle identifier is "%s"
      end tell
    ]], bundleID)

  -- firstly click menu bar item if necessary
  local clickMenuBarItemCmd = ""
  if show == true then
    if hiddenByBartender(bundleID) then
      clickMenuBarItemCmd = [[
        tell application id "com.surteesstudios.Bartender" to activate "]] .. bundleID .. [[-Item-0"

      ]]
    else
      clickMenuBarItemCmd = [[
        ignoring application responses
          tell application "System Events"
            click menu bar item 1 of last menu bar of ap
          end tell
        end ignoring

        delay 0.2
        do shell script "killall System\\ Events"
      ]]
    end
  end

  if menuItem == nil then
    local status_code = hs.osascript.applescript(initCmd .. clickMenuBarItemCmd)
    return status_code
  end

  if type(menuItem) == "number" then
    menuItem = tostring(menuItem)
  elseif type(menuItem) == "string" then
    local localized = localizedString(menuItem, bundleID)
    if localized ~= nil then
      menuItem = localized
    end
    menuItem = '"'..menuItem..'"'
  else
    if #menuItem > 0 then
      menuItem['localized'] = '"'..localizedString(menuItem[1], bundleID, menuItem.strings)..'"'
      menuItem[1] = nil
      menuItem.strings = nil
    end
    for lang, item in pairs(menuItem) do
      if lang ~= 'strings' and lang ~= 'localized' then
        menuItem[lang] = '"'..item..'"'
      end
    end
  end

  if subMenuItem ~= nil then
    if type(subMenuItem) == "number" then
      subMenuItem = tostring(subMenuItem)
    elseif type(subMenuItem) == "string" then
      local localized = localizedString(subMenuItem, bundleID)
      if localized ~= nil then
        subMenuItem = localized
      end
      subMenuItem = '"'..subMenuItem..'"'
    else
      if #subMenuItem > 0 then
        subMenuItem['localized'] = '"' ..localizedString(subMenuItem[1], bundleID, subMenuItem.strings).. '"'
        subMenuItem[1] = nil
        subMenuItem.strings = nil
      end
      for lang, item in pairs(subMenuItem) do
        if lang ~= 'strings' and lang ~= 'localized' then
          subMenuItem[lang] = '"' .. item .. '"'
        end
      end
    end
  end

  -- secondly click menu item of popup menu
  if type(menuItem) ~= "table" then
    local clickMenuItemCmd = string.format([[
      set menuitem to menu item %s of menu 1 of menu bar item 1 of last menu bar of ap
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
        %s
        tell application "System Events"
          %s
          %s
        end tell
      ]],
      initCmd,
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
          clickSubMenuItemCmd = string.format([[
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
        %sif exists menu item %s of menu 1 of menu bar item 1 of last menu bar of ap
            set menuitem to menu item %s of menu 1 of menu bar item 1 of last menu bar of ap
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
        %s
        tell application "System Events"
          %s
        end tell
      ]],
      initCmd,
      clickMenuBarItemCmd,
      clickMenuItemCmd)
    )
    return status_code
  end
end

local controlCenterIdentifiers = hs.json.read("static/controlcenter-identifies.json")
local controlCenterMenuBarItemIdentifiers = controlCenterIdentifiers.menubar
function clickControlCenterMenuBarItemSinceBigSur(menuItem)
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
    key = panel
  end
  if panel == "Users" and key == "Users" then
    key = "User"
  end
  panel = panel:gsub(" ", ""):gsub("‑", "")
  return localizedString(key, "com.apple.controlcenter", panel)
end

function clickRightMenuBarItem(menuBarName, menuItem, subMenuItem, show)
  if menuBarName == "Control Center" then
    return clickControlCenterMenuBarItem(menuBarName)
  end
  local resourceDir = findApplication("com.apple.controlcenter"):path() .. "/Contents/Resources/en.lproj"
  local newName = menuBarName:gsub(" ", ""):gsub("‑", "")
  if hs.fs.attributes(resourceDir .. '/' .. newName .. '.strings') ~= nil then
    return clickControlCenterMenuBarItem(menuBarName)
  end
  return clickAppRightMenuBarItem(menuBarName, menuItem, subMenuItem, show)
end
