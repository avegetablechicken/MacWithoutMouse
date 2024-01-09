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

function findMenuItem(appObject, menuItemTitle, params)
  local targetMenuItem
  if menuItemTitle.en or menuItemTitle.zh then
    if menuItemTitle.en and appObject:findMenuItem(menuItemTitle.en) ~= nil then
      targetMenuItem = menuItemTitle.en
    elseif menuItemTitle.zh and appObject:findMenuItem(menuItemTitle.zh) ~= nil then
      targetMenuItem = menuItemTitle.zh
    else
      return nil
    end
  else
    local menuItem = appObject:findMenuItem(menuItemTitle)
    if menuItem ~= nil then return menuItem, menuItemTitle end
    targetMenuItem = {}
    for _, title in ipairs(menuItemTitle) do
      local locStr = localizedString(title, appObject:bundleID(), params)
      if locStr == nil then return nil end
      table.insert(targetMenuItem, locStr)
    end
  end
  return appObject:findMenuItem(targetMenuItem), targetMenuItem
end

function selectMenuItem(appObject, menuItemTitle, params, show)
  if type(params) == "boolean" then
    show = params params = nil
  end

  local targetMenuItem
  if menuItemTitle.en and appObject:findMenuItem(menuItemTitle.en) ~= nil then
    targetMenuItem = menuItemTitle.en
  elseif menuItemTitle.zh and appObject:findMenuItem(menuItemTitle.zh) ~= nil then
    targetMenuItem = menuItemTitle.zh
  else
    targetMenuItem = {}
    for _, title in ipairs(menuItemTitle) do
      table.insert(targetMenuItem, localizedString(title, appObject:bundleID(), params))
    end
  end
  if show then
    showMenuItemWrapper(function()
      appObject:selectMenuItem({targetMenuItem[1]})
    end)()
  end
  appObject:selectMenuItem(targetMenuItem)
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

function findMenuItemByKeyBinding(appObject, mods, key)
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
  for i=#menuItems,1,-1 do
    local menuItem = menuItems[i]
    local menuItemPath, enabled = findMenuItemByKeyBindingImpl(mods, key, menuItem)
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

function applicationLocales(bundleID)
  local locales, ok = hs.execute(
      string.format("(defaults read %s AppleLanguages || defaults read -globalDomain AppleLanguages) | tr -d '()\" \\n'", bundleID))
  return hs.fnutils.split(locales, ',')
end

local function getResourceDir(bundleID, localeFile)
  local resourceDir
  local framework = {}
  local appContentPath = hs.application.pathForBundleID(bundleID) .. "/Contents"
  if localeFile ~= nil and localeFile:sub(-10) == ".framework" then
    resourceDir = appContentPath .. "/Frameworks/"
        .. localeFile .. "/Resources"
    framework.chromium = true
  else
    local frameworkDir = appContentPath .. "/Frameworks"
    for _, fw in ipairs{"Electron Framework", "Chromium Embedded Framework"} do
      if hs.fs.attributes(frameworkDir .. '/' .. fw .. ".framework") ~= nil then
        resourceDir = frameworkDir .. '/' .. fw .. ".framework/Resources"
        framework.chromium = true
        break
      end
    end
    if resourceDir == nil then
      local monoLocaleDirs, status = hs.execute(string.format(
          "find '%s' -type f -path '*/locale/*/LC_MESSAGES/*.mo'" ..
          " | awk -F'/locale/' '{print $1}' | uniq | tr -d '\\n'", appContentPath))
      if status and monoLocaleDirs ~= "" then
        monoLocaleDirs = hs.fnutils.split(monoLocaleDirs, '\n')
        if #monoLocaleDirs == 1 then
          resourceDir = monoLocaleDirs[1] .. "/locale"
          framework.mono = true
        end
      end
    end
    if resourceDir == nil then
      resourceDir = appContentPath .. "/Resources"
    end
  end
  return resourceDir, framework
end

local function getMatchedLocale(appLocale, resourceDir, mode)
  if mode == nil then mode = 'lproj' end
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
    if (mode == 'lproj' and file:sub(-6) == ".lproj")
        or (mode == 'strings' and file:sub(-8) == ".strings")
        or mode == 'mono' then
      local fileStem
      if mode == 'mono' then fileStem = file
      elseif mode == 'lproj' then fileStem = file:sub(1, -7)
      else fileStem = file:sub(1, -9) end
      local newFileStem = string.gsub(fileStem, '_', '-')
      local fileLocale = hs.host.locale.details(newFileStem)
      local fileLanguage = fileLocale.languageCode
      local fileScript = fileLocale.scriptCode
      local fileCountry = fileLocale.countryCode
      if fileScript == nil then
        local localeItems = hs.fnutils.split(newFileStem, '-')
        if #localeItems == 3 or (#localeItems == 2 and localeItems[2] ~= fileCountry) then
          fileScript = localeItems[2]
        end
      end
      if fileLanguage == language
          and (script == nil or fileScript == nil or fileScript == script)
          and (country == nil or fileCountry == nil or fileCountry == country) then
        local localeDir
        if mode == 'strings' then
          localeDir = resourceDir
        else
          localeDir = resourceDir .. "/" .. file
        end
        return fileStem, localeDir
      end
    end
  end
end

local function parseStringsFile(file, keepOrder)
  if keepOrder == nil then keepOrder = true end
  local jsonStr = hs.execute(string.format("plutil -convert json -o - '%s'", file))
  local jsonDict = hs.json.decode(jsonStr)
  if keepOrder then return jsonDict end
  local localesDict = {}
  for k, v in pairs(jsonDict) do
    localesDict[v] = k
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
    for file in hs.fs.dir(resourceDir) do
      if file:sub(-9) == ".loctable" then
        local fullPath = resourceDir .. '/' .. file
        local fileStem = file:sub(1, -10)
        local result = localizeByLoctableImpl(str, fullPath, fileStem, loc, localesDict)
        if result ~= nil then return result end
      end
    end
  end
end

local function localizeByQt(str, localeDir, localesDict)
  for file in hs.fs.dir(localeDir) do
    if file:sub(-3) == ".qm" then
      local fileStem = file:sub(1, -4)
      if localesDict[fileStem] ~= nil and localesDict[fileStem][str] ~= nil then
        return localesDict[fileStem][str]
      end
      local output, status = hs.execute(string.format(
          "zsh scripts/qm_localize.sh '%s' '%s'",
          localeDir .. '/' .. file, str))
      if status and output ~= "" then
        if localesDict[fileStem] == nil then localesDict[fileStem] = {} end
        localesDict[fileStem][str] = output
        return output
      end
    end
  end
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
          local enTmpdir = hs.fs.temporaryDirectory()
              .. string.format('/hs-localization-%s-%s-%s', bundleID, enLocale, fileStem)
          if hs.fs.attributes(enTmpdir) == nil then
            hs.execute(string.format(
                "scripts/pak -u '%s' '%s'", fullPath, enTmpdir))
          end
          local output, status = hs.execute("grep -lrE '^" .. str .. "$' '" .. enTmpdir .. "' | tr -d '\\n'")
          if status and output ~= "" then
            if hs.fs.attributes(localeDir .. '/' .. file) then
              local matchFile = output:match("^.*/(.*)$")
              local tmpdir = hs.fs.temporaryDirectory()
                  .. string.format('/hs-localization-%s-%s-%s', bundleID, locale, fileStem)
              if hs.fs.attributes(tmpdir) == nil then
                hs.execute(string.format(
                    "scripts/pak -u '%s' '%s'", localeDir .. '/' .. file, tmpdir))
              end
              local matchFullPath = tmpdir .. '/' .. matchFile
              if hs.fs.attributes(matchFullPath) ~= nil then
                local file = io.open(matchFullPath, "r")
                local content = file:read("*a")
                file:close()
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
  return nil
end

local appLocaleMap = {}
local appLocaleDir = {}
local appLocaleAssetBuffer = {}
local appLocaleAssetBufferInverse = {}
function localizedString(str, bundleID, params)
  if hs.application.pathForBundleID(bundleID) == nil
      or hs.application.pathForBundleID(bundleID) == "" then
    return nil
  end

  local locale, localeFile, localeDir
  if type(params) == "table" then
    locale = params.locale
    localeFile = params.localeFile
    localeDir = params.localeDir
  else
    localeFile = params
  end

  if appLocaleMap[bundleID] == nil then
    appLocaleMap[bundleID] = {}
    appLocaleAssetBuffer[bundleID] = {}
    appLocaleDir[bundleID] = {}
  end
  local locales = applicationLocales(bundleID)
  local appLocale = locales[1]
  if appLocaleMap[bundleID][appLocale] == nil then
    appLocaleMap[bundleID][appLocale] = {}
    appLocaleAssetBuffer[bundleID][appLocale] = {}
  elseif appLocaleMap[bundleID][appLocale][str] == false then
    return nil
  elseif appLocaleMap[bundleID][appLocale][str] ~= nil then
    return appLocaleMap[bundleID][appLocale][str]
  end
  local localesDict = appLocaleAssetBuffer[bundleID][appLocale]

  if bundleID == "com.google.Chrome" then
    localeFile = "Google Chrome Framework.framework"
  elseif bundleID == "com.microsoft.edgemac" then
    localeFile = "Microsoft Edge Framework.framework"
  end

  local resourceDir, framework = getResourceDir(bundleID, localeFile)

  if localeDir == nil or localeDir == false then
    if locale == nil then locale = appLocaleDir[bundleID][appLocale] end
    if locale ~= nil then
      if localeDir == false then
        localeDir = resourceDir
        if localeFile == nil then localeFile = locale end
      else
        localeDir = resourceDir .. "/" .. locale .. ".lproj"
      end
    else
      local mode = localeDir == nil and 'lproj' or 'strings'
      locale, localeDir = getMatchedLocale(appLocale, resourceDir, mode)
      if locale ~= nil then
        appLocaleDir[bundleID][appLocale] = locale
      end
    end
  end
  if localeDir == nil or localeDir == false then
    return nil
  end

  local result

  if framework.chromium then
    result = localizeByChromium(str, localeDir, localesDict, bundleID)
    if result ~= nil then
      appLocaleMap[bundleID][appLocale][str] = result
      return result
    end
  end

  result = localizeByQt(str, localeDir, localesDict)
  if result ~= nil then
    appLocaleMap[bundleID][appLocale][str] = result
    return result
  end

  if locale ~= nil then
    result = localizeByLoctable(str, resourceDir, localeFile, locale, localesDict)
    if result ~= nil then
      appLocaleMap[bundleID][appLocale][str] = result
      return result
    end
  end

  local searchFunc = function(str)
    if localeFile ~= nil then
      local jsonDict = localesDict[localeFile]
      if jsonDict == nil
          or (appLocaleDir[bundleID][appLocale] == 'en' and string.find(localeDir, 'en.lproj') == nil) then
        local fullPath = localeDir .. '/' .. localeFile .. '.strings'
        if hs.fs.attributes(fullPath) ~= nil then
          jsonDict = parseStringsFile(fullPath)
        end
      end
      if jsonDict ~= nil and jsonDict[str] ~= nil then
        localesDict[localeFile] = jsonDict
        return jsonDict[str]
      end
    else
      for file in hs.fs.dir(localeDir) do
        if file:sub(-8) == ".strings" then
          local fileStem = file:sub(1, -9)
          local jsonDict = localesDict[fileStem]
          if jsonDict == nil
              or (appLocaleDir[bundleID][appLocale] == 'en' and string.find(localeDir, 'en.lproj') == nil) then
            local fullPath = localeDir .. '/' .. file
            jsonDict = parseStringsFile(fullPath)
          end
          if jsonDict[str] ~= nil then
            localesDict[fileStem] = jsonDict
            return jsonDict[str]
          end
        end
      end
    end
  end
  local result = searchFunc(str)
  if result ~= nil then
    appLocaleMap[bundleID][appLocale][str] = result
    return result
  end
  if appLocaleDir[bundleID][appLocale] == 'en' then
    for _, _localeDir in ipairs{
        resourceDir .. "/English.lproj",
        resourceDir .. "/Base.lproj",
        resourceDir .. "/en_GB.lproj"} do
      if hs.fs.attributes(_localeDir) ~= nil then
        localeDir = _localeDir
        result = searchFunc(str)
        if result ~= nil then
          appLocaleMap[bundleID][appLocale][str] = result
          return result
        end
      end
    end
  end

  if appLocaleAssetBufferInverse[bundleID] == nil then
    appLocaleAssetBufferInverse[bundleID] = {}
  end
  localesInvDict = appLocaleAssetBufferInverse[bundleID]
  for _, localeDir in ipairs{
      resourceDir .. "/en.lproj",
      resourceDir .. "/English.lproj",
      resourceDir .. "/Base.lproj",
      resourceDir .. "/en_GB.lproj"} do
    if hs.fs.attributes(localeDir) ~= nil then
      if localeFile ~= nil then
        if localesInvDict[localeFile] == nil then
          local fullPath = localeDir .. '/' .. localeFile .. '.strings'
          if hs.fs.attributes(fullPath) ~= nil then
            localesInvDict[localeFile] = parseStringsFile(fullPath, false)
          end
        end
        if localesInvDict[localeFile] ~= nil
            and localesInvDict[localeFile][str] ~= nil then
          local result = searchFunc(localesInvDict[localeFile][str])
          if result ~= nil then
            appLocaleMap[bundleID][appLocale][str] = result
            return result
          end
        end
        localesInvDict[localeFile] = nil
      else
        for file in hs.fs.dir(localeDir) do
          if file:sub(-8) == ".strings" then
            local fileStem = file:sub(1, -9)
            if localesInvDict[fileStem] == nil then
              local fullPath = localeDir .. '/' .. file
              localesInvDict[fileStem] = parseStringsFile(fullPath, false)
            end
            if localesInvDict[fileStem] ~= nil
                and localesInvDict[fileStem][str] ~= nil then
              local result = searchFunc(localesInvDict[fileStem][str])
              if result ~= nil then
                appLocaleMap[bundleID][appLocale][str] = result
                return result
              end
            end
            localesInvDict[fileStem] = nil
          end
        end
      end
    end
  end
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
    for file in hs.fs.dir(resourceDir) do
      if file:sub(-9) == ".loctable" then
        local result = delocalizeByLoctableImpl(str, resourceDir .. '/' .. file, locale)
        if result ~= nil then return result end
      end
    end
  end
end

local function delocalizeByQt(str, localeDir)
  for file in hs.fs.dir(localeDir) do
    if file:sub(-3) == ".qm" then
      local output, status = hs.execute(string.format(
          "zsh scripts/qm_delocalize.sh '%s' '%s'",
          localeDir .. '/' .. file, str))
      if status and output ~= "" then return output end
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
      local tmpdir = hs.fs.temporaryDirectory()
          .. string.format('/hs-localization-%s-%s-%s', bundleID, locale, fileStem)
      if hs.fs.attributes(tmpdir) == nil then
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
            local enTmpdir = hs.fs.temporaryDirectory()
                .. string.format('/hs-localization-%s-%s-%s', bundleID, enLocale, fileStem)
            if hs.fs.attributes(enTmpdir) == nil then
              hs.execute(string.format(
                "scripts/pak  -u '%s' '%s'", fullPath, enTmpdir))
            end
            local matchFullPath = enTmpdir .. '/' .. matchFile
            if hs.fs.attributes(matchFullPath) ~= nil then
              local file = io.open(matchFullPath, "r")
              local content = file:read("*a")
              file:close()
              return content
            end
          end
        end
      end
    end
  end
  return nil
end

local function parseZoteroJarFile(str, appLocale)
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

  local resourceDir = hs.application.pathForBundleID("org.zotero.zotero") .. "/Contents/Resources"
  local locales, status = hs.execute("unzip -l \"" .. resourceDir .. "/zotero.jar\" 'chrome/locale/*/' | grep -Eo 'chrome/locale/[^/]*' | grep -Eo '[a-zA-Z-]*$' | uniq")
  if status ~= true then return nil end
  local localeFile
  for _, loc in ipairs(hs.fnutils.split(locales, '\n')) do
    local fileLocale = hs.host.locale.details(loc)
    local fileLanguage = fileLocale.languageCode
    local fileScript = fileLocale.scriptCode
    local fileCountry = fileLocale.countryCode
    if fileScript == nil then
      local newLoc = loc:gsub('_', '-')
      local localeItems = hs.fnutils.split(newLoc, '-')
      if #localeItems == 3 or (#localeItems == 2 and localeItems[2] ~= fileCountry) then
        fileScript = localeItems[2]
      end
    end
    if fileLanguage == language
        and (script == nil or fileScript == nil or fileScript == script)
        and (country == nil or fileCountry == nil or fileCountry == country) then
      localeFile = 'chrome/locale/' .. loc .. '/zotero/standalone.dtd'
      break
    end
  end
  if localeFile == nil then return nil end
  local enLocaleFile = 'chrome/locale/en-US/zotero/standalone.dtd'
  local key, status = hs.execute("unzip -p \"" .. resourceDir .. "/zotero.jar\" \"" .. localeFile .. "\""
      .. " | awk '/<!ENTITY .* \"" .. str .. "\">/ { gsub(/<!ENTITY | \"" .. str .. "\">/, \"\"); printf \"%s\", $0 }'")
  if status ~= true then return nil end
  local enValue, status = hs.execute("unzip -p \"" .. resourceDir .. "/zotero.jar\" \"" .. enLocaleFile .. "\""
      .. " | grep '" .. key .. "' | cut -d '\"' -f 2 | tr -d '\\n'")
  if status ~= true then return nil end

  return enValue
end

local function parseMATLABFigureMenu(str, appLocale)
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

  local resourceDir = hs.application.pathForBundleID("com.mathworks.matlab") .. "/resources/MATLAB"
  local locales = {}
  for file in hs.fs.dir(resourceDir) do
    table.insert(locales, file)
  end
  for file in hs.fs.dir(resourceDir) do
    local fileLocale = hs.host.locale.details(file)
    local fileLanguage = fileLocale.languageCode
    local fileScript = fileLocale.scriptCode
    local fileCountry = fileLocale.countryCode
    if fileScript == nil then
      local newFile = file:gsub('_', '-')
      local localeItems = hs.fnutils.split(newFile, '-')
      if #localeItems == 3 or (#localeItems == 2 and localeItems[2] ~= fileCountry) then
        fileScript = localeItems[2]
      end
    end
    if fileLanguage == language
        and (script == nil or fileScript == nil or fileScript == script)
        and (country == nil or fileCountry == nil or fileCountry == country) then
      localeFile = resourceDir .. '/' .. file .. '/uistring/figuremenu.xml'
      break
    end
  end
  if localeFile == nil then return nil end
  local enLocaleFile = resourceDir .. '/en/uistring/figuremenu.xml'
  local shell_pattern = 'key="([^"]*?)">' .. str .. '\\(&amp;[A-Z]\\)</entry>'
  local key, status = hs.execute(string.format(
      "grep -Eo '%s' '%s' | cut -d '\"' -f 2 | tr -d '\\n'", shell_pattern, localeFile))
  if status and key ~= "" then
    local inverse_pattern = 'key="' .. key .. '">&amp;([^<]*?)</entry>'
    local enValue, status = hs.execute(string.format(
        "grep -Eo '%s' '%s' | cut -d ';' -f 2  | cut -d '<' -f 1 | tr -d '\\n'", inverse_pattern, enLocaleFile))
    if status and enValue ~= "" then return enValue end
  end
  return nil
end

local menuItemLocaleMap = {}
local menuItemLocaleDir = {}
local menuItemLocaleInversedMap = {}
local stringsFilePatterns = { "(.-)MainMenu(.-)", "Menu", "MenuBar",
                              "MenuItems", "Localizable", "Main", "MainWindow" }
function delocalizedMenuItem(str, bundleID, locale, localeFile)
  if localeFile == nil then
    localeFile = locale
    locale = nil
  end

  if menuItemLocaleMap[bundleID] == nil then
    menuItemLocaleMap[bundleID] = {}
    menuItemLocaleDir[bundleID] = {}
  end
  local locales = applicationLocales(bundleID)
  local appLocale = locales[1]
  if menuItemLocaleDir[bundleID][appLocale] == nil then
    menuItemLocaleMap[bundleID] = {}
    menuItemLocaleInversedMap[bundleID] = {}
  end

  if menuItemLocaleMap[bundleID][str] == false then
    return nil
  elseif menuItemLocaleMap[bundleID][str] ~= nil then
    return menuItemLocaleMap[bundleID][str]
  end

  if bundleID == "org.zotero.zotero" then
    local result = parseZoteroJarFile(str, appLocale)
    menuItemLocaleMap[bundleID][str] = result or false
    return result
  elseif bundleID == "com.mathworks.matlab" then
    local result = parseMATLABFigureMenu(str, appLocale)
    menuItemLocaleMap[bundleID][str] = result or false
    return result
  end

  if bundleID == "com.google.Chrome" then
    localeFile = "Google Chrome Framework.framework"
  elseif bundleID == "com.microsoft.edgemac" then
    localeFile = "Microsoft Edge Framework.framework"
  end

  local resourceDir, framework = getResourceDir(bundleID, localeFile)

  local localeDir
  if locale == nil then locale = menuItemLocaleDir[bundleID][appLocale] end
  if locale ~= nil then
    localeDir = resourceDir .. "/" .. locale
    if not framework.mono then localeDir = localeDir .. ".lproj" end
  else
    local mode = framework.mono and 'mono' or 'lproj'
    locale, localeDir = getMatchedLocale(appLocale, resourceDir, mode)
    if locale ~= nil then
      menuItemLocaleDir[bundleID][appLocale] = locale
    end
  end
  if localeDir == nil then
    menuItemLocaleMap[bundleID][str] = false
    return nil
  end

  local result

  if framework.chromium then
    result = delocalizeByChromium(str, localeDir, bundleID)
    if result ~= nil then
      menuItemLocaleMap[bundleID][str] = result
      return result
    end
  end

  if framework.mono then
    result = delocalizeByMono(str, localeDir)
    if result ~= nil then
      if bundleID == "com.microsoft.visual-studio" then
        result = result:gsub('_', '')
      end
      menuItemLocaleMap[bundleID][str] = result
      return result
    end
  end

  result = delocalizeByLoctable(str, resourceDir, localeFile, locale)
  if result ~= nil then
    menuItemLocaleMap[bundleID][str] = result
    return result
  end

  result = delocalizeByQt(str, localeDir)
  if result ~= nil then
    menuItemLocaleMap[bundleID][str] = result
    return result
  end

  local searchFunc = function(str)
    for _, localeDir in ipairs{
        resourceDir .. "/en.lproj",
        resourceDir .. "/English.lproj",
        resourceDir .. "/Base.lproj",
        resourceDir .. "/en_GB.lproj"} do
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
              for _, pattern in ipairs(stringsFilePatterns) do
                local pattern = "^" .. pattern  .. "%.strings$"
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
        menuItemLocaleInversedMap[bundleID] = parseStringsFile(fullPath, false)
      end
    end
    if menuItemLocaleInversedMap[bundleID] ~= nil
        and menuItemLocaleInversedMap[bundleID][str] ~= nil then
      local result = searchFunc(menuItemLocaleInversedMap[bundleID][str])
      if result ~= nil then
        menuItemLocaleMap[bundleID][str] = result
        return result
      elseif not (string.match(menuItemLocaleInversedMap[bundleID][str], "[^%a]")) then
        menuItemLocaleMap[bundleID][str] = menuItemLocaleInversedMap[bundleID][str]
        return menuItemLocaleMap[bundleID][str]
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
        for _, pattern in ipairs(stringsFilePatterns) do
          local pattern = "^" .. pattern  .. "%.strings$"
          if string.match(file, pattern) ~= nil then return true end
        end
        return false
      end)
    end
    for _, file in ipairs(stringsFiles) do
      if menuItemLocaleInversedMap[bundleID][str] == nil then
        local fullPath = localeDir .. '/' .. file
        menuItemLocaleInversedMap[bundleID] = parseStringsFile(fullPath, false)
      end
      if menuItemLocaleInversedMap[bundleID][str] ~= nil then
        local result = searchFunc(menuItemLocaleInversedMap[bundleID][str])
        if result ~= nil then
          menuItemLocaleMap[bundleID][str] = result
          return result
        end
      end
    end
    if menuItemLocaleInversedMap[bundleID][str] ~= nil
        and not string.match(menuItemLocaleInversedMap[bundleID][str], "[^%a]") then
      menuItemLocaleMap[bundleID][str] = menuItemLocaleInversedMap[bundleID][str]
      return menuItemLocaleMap[bundleID][str]
    end
  end

  menuItemLocaleMap[bundleID][str] = false
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
    menuItem = '"'..menuItem..'"'
  else
    for lang, item in pairs(menuItem) do
      if lang == 'localized' then
        item = localizedString(item, bundleID, menuItem.strings)
      end
      if lang ~= 'strings' then
        menuItem[lang] = '"'..item..'"'
      end
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
