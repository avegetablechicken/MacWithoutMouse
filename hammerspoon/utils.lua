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

function getMenuItems(appObject)
  local menuItems = appObject:getMenuItems()
  if menuItems == nil then
    hs.timer.usleep(0.1 * 1000000)
    menuItems = appObject:getMenuItems()
    if menuItems == nil then
      hs.timer.usleep(0.1 * 1000000)
      menuItems = appObject:getMenuItems()
      if menuItems == nil then
        return
      end
    end
  end
  return menuItems
end

function findMenuItem(appObject, menuItemTitle, params)
  if #menuItemTitle > 0 then
    local menuItem = appObject:findMenuItem(menuItemTitle)
    if menuItem ~= nil then return menuItem, menuItemTitle end
    local targetMenuItem = {}
    local appMenus = getMenuItems(appObject)
    if appMenus == nil then return end
    for i=2,#appMenus do
      local title = delocalizedMenuItem(appMenus[i].AXTitle, appObject:bundleID(), params)
      if menuItemTitle[1] == title then
        table.insert(targetMenuItem, appMenus[i].AXTitle)
        break
      end
    end
    if #targetMenuItem == 0 then
      table.insert(targetMenuItem, menuItemTitle[1])
    end
    for i=#menuItemTitle,2,-1 do
      local locStr = localizedString(menuItemTitle[i], appObject:bundleID(), params)
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
    local appMenus = getMenuItems(appObject)
    if appMenus == nil then return end
    for i=2,#appMenus do
      local title = delocalizedMenuItem(appMenus[i].AXTitle, appObject:bundleID(), params)
      if menuItemTitle[1] == title then
        table.insert(targetMenuItem, 1, appMenus[i].AXTitle)
        break
      end
    end
    if #targetMenuItem == 0 then
      table.insert(targetMenuItem, menuItemTitle[1])
    end
    for i=#menuItemTitle,2,-1 do
      local locStr = localizedString(menuItemTitle[i], appObject:bundleID(), params)
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
    if (subItem.AXMenuItemCmdChar == key
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

function applicationLocales(bundleID)
  local locales, ok = hs.execute(
      string.format("(defaults read %s AppleLanguages || defaults read -globalDomain AppleLanguages) | tr -d '()\" \\n'", bundleID))
  return hs.fnutils.split(locales, ',')
end

local function getResourceDir(bundleID, frameworkName)
  local resourceDir
  local framework = {}
  local appContentPath = hs.application.pathForBundleID(bundleID) .. "/Contents"
  if frameworkName ~= nil and frameworkName:sub(-10) == ".framework" then
    resourceDir = appContentPath .. "/Frameworks/" .. frameworkName .. "/Resources"
  elseif bundleID == "com.google.Chrome" then
    resourceDir = appContentPath .. "/Frameworks/Google Chrome Framework.framework/Resources"
    framework.chromium = true
  elseif bundleID == "com.microsoft.edgemac" then
    resourceDir = appContentPath .. "/Frameworks/Microsoft Edge Framework.framework/Resources"
    framework.chromium = true
  else
    local frameworkDir = appContentPath .. "/Frameworks"
    for _, fw in ipairs{"Electron Framework", "Chromium Embedded Framework"} do
      if hs.fs.attributes(frameworkDir .. '/' .. fw .. ".framework") ~= nil then
        resourceDir = frameworkDir .. '/' .. fw .. ".framework/Resources"
        framework.chromium = true
        goto END_GET_RESOURCE_DIR
      end
    end

    if hs.fs.attributes(appContentPath .. "/Resources/qt.conf") ~= nil then
      resourceDir = appContentPath .. "/Resources"
      framework.qt = true
      goto END_GET_RESOURCE_DIR
    end

    local monoLocaleDirs, status = hs.execute(string.format(
        "find '%s' -type f -path '*/locale/*/LC_MESSAGES/*.mo'" ..
        " | awk -F'/locale/' '{print $1}' | uniq | tr -d '\\n'", appContentPath))
    if status and monoLocaleDirs ~= "" then
      monoLocaleDirs = hs.fnutils.split(monoLocaleDirs, '\n')
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
  for _, enLocale in ipairs{"en", "English", "Base", "en-GB"} do
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
  if hs.fs.attributes(localeTmpDir) == nil then
    hs.execute(string.format("mkdir -p '%s'", localeTmpDir))
  end

  if hs.application.pathForBundleID(bundleID) == nil
      or hs.application.pathForBundleID(bundleID) == "" then
    return nil
  end

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
    local localeDetails = hs.host.locale.details(appLocale)
    if localeDetails.languageCode == 'en' and key ~= true then
      return str
    end
  end

  if appLocaleMap[bundleID] == nil then
    appLocaleMap[bundleID] = {}
    appLocaleDir[bundleID] = {}
  end
  if appLocaleAssetBuffer[bundleID] == nil then
    appLocaleAssetBuffer[bundleID] = {}
  end
  if appLocaleAssetBuffer[bundleID][appLocale] == nil then
    appLocaleAssetBuffer[bundleID][appLocale] = {}
  end
  if appLocaleMap[bundleID][appLocale] == nil then
    appLocaleMap[bundleID][appLocale] = {}
  elseif appLocaleMap[bundleID][appLocale][str] == false then
    return nil
  elseif appLocaleMap[bundleID][appLocale][str] ~= nil then
    return appLocaleMap[bundleID][appLocale][str]
  end
  local localesDict = appLocaleAssetBuffer[bundleID][appLocale]

  local resourceDir, framework = getResourceDir(bundleID, localeFramework)

  local locale
  if localeDir == nil or localeDir == false then
    local mode = localeDir == nil and 'lproj' or 'strings'
    if locale == nil then
      locale = appLocaleDir[bundleID][appLocale]
    end
    if locale == nil then
      locale = getMatchedLocale(appLocale, resourceDir, mode)
      if locale == nil and framework.qt then
        locale, localeDir = getQtMatchedLocale(appLocale, resourceDir)
      end
      if locale ~= nil then
        appLocaleDir[bundleID][appLocale] = locale
      else
        appLocaleMap[bundleID][appLocale][str] = false
        return nil
      end
    end
    if mode == 'strings' then
      localeDir = resourceDir
      if localeFile == nil then localeFile = locale end
    elseif localeDir == nil then
      localeDir = resourceDir .. "/" .. locale .. ".lproj"
    end
    if framework.qt and hs.fs.attributes(localeDir) == nil then
      _, localeDir = getQtMatchedLocale(appLocale, resourceDir)
    end
  end

  local result

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
    if localizationMapByKey[bundleID] ~= nil then
      local key = hs.fnutils.indexOf(localizationMapByKey[bundleID], str)
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

  ::L_END_LOCALIZED::
  if result ~= nil then
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
        for _, enLocale in ipairs{"en", "English", "Base", "en-GB"} do
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
function delocalizedMenuItemString(str, bundleID, params)
  if hs.fs.attributes(localeTmpDir) == nil then
    hs.execute(string.format("mkdir -p '%s'", localeTmpDir))
  end

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
    local localeDetails = hs.host.locale.details(appLocale)
    if localeDetails.languageCode == 'en' then return end
  end

  if menuItemLocaleMap[bundleID] == nil then
    menuItemLocaleMap[bundleID] = {}
    menuItemLocaleDir[bundleID] = {}
  end
  if menuItemLocaleInversedMap[bundleID] == nil then
    menuItemLocaleInversedMap[bundleID] = {}
  end
  if menuItemLocaleDir[bundleID][appLocale] == nil then
    menuItemLocaleMap[bundleID] = {}
    menuItemLocaleInversedMap[bundleID] = {}
  end

  if menuItemLocaleMap[bundleID][str] == false then
    return nil
  elseif menuItemLocaleMap[bundleID][str] ~= nil then
    return menuItemLocaleMap[bundleID][str]
  end

  local locale, resourceDir, framework, localeDir, mode, result, searchFunc

  if bundleID == "org.zotero.zotero" then
    result, locale = delocalizeZoteroMenu(str, appLocale)
    if menuItemLocaleDir[bundleID][appLocale] ~= nil
        and menuItemLocaleDir[bundleID][appLocale] ~= locale then
      menuItemLocaleMap[bundleID] = {}
    end
    goto L_END_DELOCALIZED
  elseif bundleID == "com.mathworks.matlab" then
    result, locale = delocalizeMATLABFigureMenu(str, appLocale)
    if menuItemLocaleDir[bundleID][appLocale] ~= nil
        and menuItemLocaleDir[bundleID][appLocale] ~= locale then
      menuItemLocaleMap[bundleID] = {}
    end
    goto L_END_DELOCALIZED
  end

  resourceDir, framework = getResourceDir(bundleID, localeFramework)

  if not framework.mono then mode = 'lproj' end
  if locale == nil then
    locale = menuItemLocaleDir[bundleID][appLocale]
  end
  if locale == nil then
    locale = getMatchedLocale(appLocale, resourceDir, mode)
    if locale == nil and framework.qt then
      locale, localeDir = getQtMatchedLocale(appLocale, resourceDir)
    end
    if locale == nil then
      menuItemLocaleMap[bundleID][str] = false
      return nil
    end
  end
  if localeDir == nil then
    if mode == 'lproj' then
      localeDir = resourceDir .. "/" .. locale .. ".lproj"
    else
      localeDir = resourceDir .. "/" .. locale
    end
    if framework.qt and hs.fs.attributes(localeDir) == nil then
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
        elseif localizationMapByKey[bundleID] ~= nil then
          result = localizationMapByKey[bundleID][k]
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
          elseif localizationMapByKey[bundleID] ~= nil then
            result = localizationMapByKey[bundleID][k]
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
    result = delocalizedMenuItemString(str, bundleID,
                                       { framework = "XUCore.framework" })
    if result ~= nil then return result end
  end

  ::L_END_DELOCALIZED::
  if result ~= nil then
    menuItemLocaleMap[bundleID][str] = result
    menuItemLocaleDir[bundleID][appLocale] = locale
    hs.json.write({ locale = menuItemLocaleDir, map = menuItemLocaleMap },
        menuItemTmpFile, false, true)
  else
    menuItemLocaleMap[bundleID][str] = false
  end
  return result
end

function delocalizedMenuItem(title, bundleID, params)
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
  local newTitle = delocalizedMenuItemString(title, bundleID, params)
  return newTitle
end

menuBarTitleLocalizationMap = {}
if hs.fs.attributes("config/menuitem-localization.json") ~= nil then
  menuBarTitleLocalizationMap = hs.json.read("config/menuitem-localization.json")
end
localizationMapByKey = {}
if hs.fs.attributes("static/localization-keys.json") ~= nil then
  localizationMapByKey = hs.json.read("static/localization-keys.json")
end
menuBarTitleLocalizationMap.common = {}
local finderObject = findApplication("com.apple.finder")
if finderObject ~= nil then
  local finderMenuItems = finderObject:getMenuItems()
  for i=2,#finderMenuItems do
    local title = finderMenuItems[i].AXTitle
    local enTitle = delocalizedMenuItemString(title, "com.apple.finder")
    if enTitle ~= nil then
      menuBarTitleLocalizationMap.common[title] = enTitle
    end
  end
end
for _, title in ipairs{ 'File', 'Edit', 'View', 'Window', 'Help' } do
  if not hs.fnutils.contains(menuBarTitleLocalizationMap.common, title) then
    local localizedTitle = localizedString(title, "com.apple.finder")
    if localizedTitle ~= nil then
      menuBarTitleLocalizationMap.common[localizedTitle] = title
    end
  end
end
local localizedTitle = localizedString('Format', "com.apple.Notes")
if localizedTitle ~= nil then
  menuBarTitleLocalizationMap.common[localizedTitle] = 'Format'
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

  if hiddenByBartender(bundleID) and hasTopNotch(hs.screen.mainScreen()) then
    clickMenuBarItemCmd = [[
      tell application id "com.surteesstudios.Bartender" to activate "]] .. bundleID .. [[-Item-0"

    ]] .. clickMenuBarItemCmd
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
  if panel == "Control Center" then
    return findApplication("com.apple.controlcenter"):name()
  end
  panel = panel:gsub("%s+", "")
  return localizedString(key, "com.apple.controlcenter", panel)
end

function clickRightMenuBarItem(menuBarName, menuItem, subMenuItem)
  if menuBarName == "Control Center" then
    return clickControlCenterMenuBarItem(menuBarName)
  end
  local resourceDir = findApplication("com.apple.controlcenter"):path() .. "/Contents/Resources/en.lproj"
  if hs.fs.attributes(resourceDir .. '/' .. menuBarName:gsub("%s+", "") .. '.strings') ~= nil then
    return clickControlCenterMenuBarItem(menuBarName)
  end
  return clickAppRightMenuBarItem(menuBarName, menuItem, subMenuItem)
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
