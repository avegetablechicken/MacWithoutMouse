require "utils"

local applicationConfigs = hs.json.read("config/application.json")
local misc = keybindingConfigs.hotkeys.global


hs.application.enableSpotlightForNameSearches(true)

-- launch or hide applications
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
    if appObject ~= nil and appObject:bundleID() == "com.apple.finder"
        and hs.fnutils.find(appObject:visibleWindows(), function(win)
          return win:isStandard()
        end) == nil then
      selectMenuItem(appObject,
          { en = {"File", "New Finder Window"}, zh = {"文件", "新建“访达”窗口"} })
    end
  else
    if appObject ~= nil and appObject:bundleID() == "com.apple.finder" then
      if hs.fnutils.find(appObject:visibleWindows(), function(win)
          return win:isStandard()
        end) == nil then
        selectMenuItem(appObject,
            { en = {"File", "New Finder Window"}, zh = {"文件", "新建“访达”窗口"} })
      elseif not hs.window.focusedWindow():isStandard() then
        hs.application.open(hint)
        hs.window.focusedWindow():focus()
      else
        appObject:hide()
      end
    else
      appObject:hide()
    end
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
  if findApplication("pl.maketheweb.TopNotch") == nil then
    hs.application.open("pl.maketheweb.TopNotch")
  end
  local appObject = findApplication("pl.maketheweb.TopNotch")
  clickRightMenuBarItem("pl.maketheweb.TopNotch")
  local appUIObj = hs.axuielement.applicationElement("pl.maketheweb.TopNotch")
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

local appConfigs = keybindingConfigs.hotkeys.appkeys
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
local function klatexformulaRender()
  hs.osascript.applescript([[
    tell application "System Events
      tell ]] .. aWinFor("org.klatexformula.klatexformula") .. [[
        click button 2 of splitter group 1
      end tell
    end tell
  ]])
end

function deleteSelectedMessage(appObject, force)
  local osVersion = getOSVersion()
  if osVersion < OS.Ventura then
    selectMenuItem(appObject, { en = {"File", "Delete Conversation…"}, zh = {"文件", "删除对话…"} })
  else
    selectMenuItem(appObject, { en = {"Conversations", "Delete Conversation…"}, zh = {"对话", "删除对话…"} })
  end
  if force ~= nil then
    hs.timer.usleep(0.1 * 1000000)
    hs.eventtap.keyStroke("", "Tab", nil, appObject)
    hs.timer.usleep(0.1 * 1000000)
    hs.eventtap.keyStroke("", "Space", nil, appObject)
  end
end

function deleteAllMessages(appObject)
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
        deleteSelectedMessage(appObject, true)
        hs.timer.usleep(1 * 1000000)
      end
      deleteAllMessages(appObject)
    end,
    function(element)
      return element.AXIdentifier == "ConversationList"
    end
  )
end

function confirmDeleteConditionForAppleApps(bundleID)
  local ok, button = hs.osascript.applescript([[
    tell application "System Events"
      tell ]] .. aWinFor(bundleID) .. [[
        if exists sheet 1 then
          if exists button "Delete" of sheet 1 then
            return "Delete"
          else if exists button "删除" of sheet 1 then
            return "删除"
          else
            return false
          end if
        else
          return false
        end if
      end tell
    end tell
  ]])
  if ok and button ~= false then
    return true, button
  else
    return false
  end
end

function confirmDeleteForAppleApps(button, appObject)
  hs.osascript.applescript([[
    tell application "System Events"
      tell ]] .. aWinFor(appObject:bundleID()) .. [[
        click button "]] .. button .. [[" of sheet 1
      end tell
    end tell
  ]])
end

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

appHotKeyCallbacks = {
  ["com.apple.finder"] =
  {
    ["goToDownloads"] = {
      message = "Go to Downloads",
      fn = function(appObject) hs.eventtap.keyStroke("⌥⌘", "L", nil, appObject) end
    },
    ["showPrevTab"] = {
      message = "Show Previous Tab",
      condition = function()
        local appObject = hs.application("com.apple.finder")
        local menuPath = {"Window", "Show Previous Tab"}
        local menuItem = appObject:findMenuItem(menuPath)
        if menuItem == nil then
          menuPath = {"窗口", "显示上一个标签页"}
          menuItem = appObject:findMenuItem(menuPath)
        end
        if menuItem ~= nil and menuItem.enabled then
          return true, menuPath
        else
          return false
        end
      end,
      fn = function(menuPath, appObject) appObject:selectMenuItem(menuPath) end
    },
    ["showNextTab"] = {
      message = "Show Next Tab",
      condition = function()
        local appObject = hs.application("com.apple.finder")
        local menuPath = {"Window", "Show Next Tab"}
        local menuItem = appObject:findMenuItem(menuPath)
        if menuItem == nil then
          menuPath = {"窗口", "显示下一个标签页"}
          menuItem = appObject:findMenuItem(menuPath)
        end
        if menuItem ~= nil and menuItem.enabled then
          return true, menuPath
        else
          return false
        end
      end,
      fn = function(menuPath, appObject) appObject:selectMenuItem(menuPath) end
    }
  },

  ["com.apple.MobileSMS"] =
  {
    ["deleteSelectedMessage"] = {
      message = "Delete Selected Message",
      fn = function(appObject) deleteSelectedMessage(appObject) end
    },
    ["deleteAllMessages"] = {
      message = "Delete All Messages",
      fn = function(appObject) deleteAllMessages(appObject) end
    },
    ["goToPreviousConversation"] = {
      message = "Go to Previous Conversation",
      fn = function(appObject) hs.eventtap.keyStroke("⇧⌃", "Tab", nil, appObject) end
    },
    ["goToNextConversation"] = {
      message = "Go to Next Conversation",
      fn = function(appObject) hs.eventtap.keyStroke("⌃", "Tab", nil, appObject) end
    }
  },

  ["com.apple.ScriptEditor2"] =
  {
    ["confirmDelete"] = {
      message = "Confirm Delete",
      condition = hs.fnutils.partial(confirmDeleteConditionForAppleApps,
                                     "com.apple.ScriptEditor2"),
      fn = confirmDeleteForAppleApps
    }
  },

  ["com.apple.AppStore"] =
  {
    ["back"] = {
      mods = "⌘", key = "[",
      message = "Back",
      condition = function()
        local appObject = findApplication("com.apple.AppStore")
        local backMenuItem = appObject:findMenuItem({"Store", "Back"})
        if backMenuItem ~= nil and backMenuItem.enabled then
          return true, {"Store", "Back"}
        end
        if backMenuItem == nil then
          backMenuItem = appObject:findMenuItem({"商店", "返回"})
        end
        if backMenuItem ~= nil and backMenuItem.enabled then
          return true, {"商店", "返回"}
        else
          local ok, valid = hs.osascript.applescript([[
            tell application "System Events"
              tell ]] .. aWinFor("com.apple.AppStore") .. [[
                return exists button 1 of last group of splitter group 1
              end tell
            end tell
          ]])
          return ok and valid
        end
      end,
      fn = function(result, appObject)
        if result ~= nil then
          appObject:selectMenuItem(result)
        else
          hs.osascript.applescript([[
            tell application "System Events"
              tell ]] .. aWinFor("com.apple.AppStore") .. [[
                perform action "AXPress" of button 1 of last group of splitter group 1
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
      condition = function()
        local aWin = activatedWindowIndex()
        local ok, url = hs.osascript.applescript([[
          tell application id "com.apple.Safari"
            return URL of current tab of window ]] .. aWin .. [[

          end tell
        ]])
        if ok and string.sub(url, 1, 7) == "file://" then
          return true, url
        else
          return false
        end
      end,
      fn = function(url) hs.execute("open -R " .. url) end
    }
  },

  ["com.apple.Preview"] =
  {
    ["revealInFinder"] = {
      message = "Reveal in Finder",
      condition = function()
        local ok, filePath = hs.osascript.applescript([[
          tell application id "com.apple.Preview" to get path of front document
        ]])
        if ok then
          return true, filePath
        else
          return false
        end
      end,
      fn = function(filePath, appObject)
        hs.execute("open -R '" .. filePath .. "'")
      end
    }
  },

  ["com.google.Chrome"] =
  {
    ["revealInFinder"] = {
      message = "Reveal in Finder",
      condition = function()
        local aWin = activatedWindowIndex()
        local ok, url = hs.osascript.applescript([[
          tell application id "com.google.Chrome"
            return URL of active tab of window ]] .. aWin .. [[

          end tell
        ]])
        if ok and string.sub(url, 1, 7) == "file://" then
          return true, url
        else
          return false
        end
      end,
      fn = function(url) hs.execute("open -R " .. url) end
    }
  },

  ["com.sublimetext.4"] =
  {
    ["openRecent"] = {
      message = "Open Recent",
      fn = function(appObject)
        showMenuItemWrapper(function()
          appObject:selectMenuItem({"File"})
          appObject:selectMenuItem({"File", "Open Recent"})
        end)()
      end
    }
  },

  ["com.microsoft.VSCode"] =
  {
    ["view:toggleOutline"] = {
      message = "View: Toggle Outline",
      fn = function() VSCodeToggleSideBarSection("EXPLORER", "OUTLINE") end
    }
  },

  ["com.readdle.PDFExpert-Mac"] =
  {
    ["showInFinder"] = {
      message = "Show in Finder",
      fn = function(appObject)
        selectMenuItem(appObject,
          { en = {"File", "Show in Finder"}, zh = {"文件", "在 Finder 中显示"} })
      end
    }
  },

  ["abnerworks.Typora"] =
  {
    ["openFileLocation"] = {
      message = "Open File Location",
      fn = function(appObject)
        selectMenuItem(appObject,
          { en = {"File", "Open File Location"}, zh = {"文件", "打开文件位置"} })
      end
    },
    ["openRecent"] = {
      message = "Open Recent",
      fn = function(appObject)
        showMenuItemWrapper(function()
          selectMenuItem(appObject,
            { en = {"File", "Open Recent"}, zh = {"文件", "打开最近文件"} },
            true)
        end)()
      end
    },
    ["previousTab"] = {
      message = "Previous Tab",
      fn = function(appObject)
        hs.eventtap.keyStroke("⇧⌃", "Tab", nil, appObject)
      end
    },
    ["nextTab"] = {
      message = "Next Tab",
      fn = function(appObject)
        hs.eventtap.keyStroke("⌃", "Tab", nil, appObject)
      end
    },
    ["pasteAsPlainText"] = {
      message = "Paste as Plain Text",
      fn = function(appObject)
        selectMenuItem(appObject,
          { en = {"Edit", "Paste as Plain Text"}, zh = {"编辑", "粘贴为纯文本"} })
      end
    }
  },

  ["com.vallettaventures.Texpad"] =
  {
    ["confirmDelete"] = {
      message = "Confirm Delete",
      condition = hs.fnutils.partial(confirmDeleteConditionForAppleApps,
                                     "com.vallettaventures.Texpad"),
      fn = confirmDeleteForAppleApps
    }
  },

  ["com.superace.updf.mac"] =
  {
    ["showInFinder"] = {
      message = "Show in Finder",
      fn = function(appObject)
        selectMenuItem(appObject,
          { en = {"File", "Show in Finder"}, zh = {"文件", "在访达中显示"} })
      end
    }
  },

  ["com.kingsoft.wpsoffice.mac"] =
  {
    ["newWorkspace"] = {
      message = "New Workspace",
      fn = function(appObject) hs.eventtap.keyStroke("⌃⌥", "N", nil, appObject) end
    },
    ["closeWorkspace"] = {
      message = "Close Workspace",
      condition = function()
        local appObject = findApplication("com.kingsoft.wpsoffice.mac")
        local menuItem = appObject:findMenuItem({"工作区", "关闭工作区"})
        if menuItem ~= nil and menuItem.enabled == true then
          return true
        else
          return false
        end
      end,
      fn = function(dumb, appObject) appObject:selectMenuItem({"工作区", "关闭工作区"}) end
    },
    ["previousTab"] = {
      message = "Previous Tab",
      fn = function(appObject) hs.eventtap.keyStroke("⇧⌃", "Tab", nil, appObject) end
    },
    ["nextTab"] = {
      message = "Next Tab",
      fn = function(appObject) hs.eventtap.keyStroke("⌃", "Tab", nil, appObject) end
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
      message = "Open File Location",
      fn = function(appObject)
        local aWin = activatedWindowIndex()
        local appUIObj = hs.axuielement.applicationElement(appObject)
        local buttons = appUIObj:childrenWithRole("AXWindow")[aWin]
            :childrenWithRole("AXButton")
        if #buttons == 0 then return end
        local mousePosition = hs.mouse.absolutePosition()
        local ok, position = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor("com.kingsoft.wpsoffice.mac") .. [[
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
            tell first application process whose bundle identifier is "com.kingsoft.wpsoffice.mac"
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
    ["export"] = {
      message = "Export",
      fn = function(appObject)
        selectMenuItem(appObject, { en = {"File", "Export"}, zh = {"文件", "导出为"} })
        selectMenuItem(appObject, { en = {"File", "Export To", "PDF…"}, zh = {"文件", "导出为", "PDF…"} })
      end
    },
    ["pasteAndMatchStyle"] = {
      message = "Paste and Match Style",
      fn = function(appObject)
        selectMenuItem(appObject,
          { en = {"Edit", "Paste and Match Style"}, zh = {"编辑", "粘贴并匹配样式"} })
      end
    },
    ["paste"] = {
      message = "Paste",
      fn = function(appObject)
        selectMenuItem(appObject,
          { en = {"Edit", "Paste"}, zh = {"编辑", "粘贴"} })
      end
    },
    ["play"] = {
      message = "Play",
      fn = function(appObject) hs.eventtap.keyStroke("⌥⌘", "P", nil, appObject) end
    },
    ["insertEquation"] = {
      message = "Insert Equation",
      fn = function(appObject)
        selectMenuItem(appObject,
          { en = {"Insert", "Equation..."}, zh = {"插入", "方程..."} })
      end
    },
    ["revealInFinder"] = {
      message = "Reveal in Finder",
      fn = function()
        local ok, filePath = hs.osascript.applescript([[
          tell application id "com.apple.iWork.Keynote" to get file of front document
        ]])
        if ok and filePath ~= nil then
          local pos = string.find(filePath, ":", 1)
          filePath = string.sub(filePath, pos)
          filePath = string.gsub(filePath, ":", "/")
          hs.execute("open -R '" .. filePath .. "'")
        end
      end
    },
    ["confirmDelete"] = {
      message = "Confirm Delete",
      condition = hs.fnutils.partial(confirmDeleteConditionForAppleApps,
                                     "com.apple.iWork.Keynote"),
      fn = confirmDeleteForAppleApps
    }
  },

  ["net.xmind.vana.app"] =
  {
    ["export"] = {
      message = "Export",
      fn = function(appObject)
        selectMenuItem(appObject, { en = {"File"}, zh = {"文件"} })
        selectMenuItem(appObject, { en = {"File", "Export"}, zh = {"文件", "导出"} })
      end
    },
    ["insertEquation"] = {
      message = "Insert Equation",
      fn = function(appObject)
        selectMenuItem(appObject,
          { en = {"Insert", "Equation"}, zh = {"插入", "方程"} })
      end
    }
  },

  ["org.klatexformula.klatexformula"] =
  {
    ["render"] = {
      message = "Render",
      fn = function() klatexformulaRender() end
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
    ["minimize"] = {
      mods = "⌘", key = "M",
      message = "Minimize",
      condition = function()
        local appObject = findApplication("cn.edu.idea.paper")
        return appObject:focusedWindow() ~= nil, appObject:focusedWindow()
      end,
      fn = function(winObj) winObj:minimize() end
    },
    ["hide"] = {
      mods = "⌘", key = "H",
      message = "Hide",
      fn = function(appObject) appObject:hide() end
    }
  },

  ["com.tencent.xinWeChat"] =
  {
    ["back"] = {
      message = "Back",
      condition = function()
        local ok, result = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor("com.tencent.xinWeChat") .. [[
              -- 公众号
              if exists button "返回" of splitter group 1 of splitter group 1 then
                return 1
              end if

              -- 折叠的群聊
              if exists splitter group 1 then
                set bt to every button of splitter group 1 whose description is "返回"
                if (count bt) > 0 then
                  return 2
                end if
              end if

              -- 推送
              set bts to every button
              repeat with bt in bts
                if value of attribute "AXHelp" of bt is "上一页" ¬
                    and value of attribute "AXEnabled" of bt is True then
                  return 3
                end if
              end repeat

              -- 朋友圈
              if (exists image 1) and ((ui element 1) is (image 1)) ¬
                  and (exists scroll area 1) and ((ui element 2) is (scroll area 1)) ¬
                  and (exists image 2) and ((ui element 3) is (image 2)) ¬
                  and (exists image 2) and ((ui element 4) is (button 1)) then
                return position of button 1
              end if

              -- 朋友圈详情
              if name is "朋友圈-详情" then
                return position of button 1
              end if

              return false
            end tell
          end tell
        ]])
        if ok and result ~= false then
          return true, result
        else
          return false
        end
      end,
      fn = function(result)
        if type(result) == "table" then
          leftClickAndRestore(result)
        else
          local script = [[
            tell application "System Events"
              tell ]] .. aWinFor("com.tencent.xinWeChat") .. [[
                %s
              end tell
            end tell
          ]]
          if result == 1 then
            script = string.format(script, [[
              click button "返回" of splitter group 1 of splitter group 1
            ]])
          elseif result == 2 then
            script = string.format(script, [[
              key code 123
            ]])
          else
            script = string.format(script, [[
              set bts to every button
              repeat with bt in bts
                if value of attribute "AXHelp" of bt is "上一页" ¬
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
      message = "Forward",
      condition = function()
        local ok, valid = hs.osascript.applescript([[
          tell application "System Events"
            -- 推送
            set bts to every button of ]] .. aWinFor("com.tencent.xinWeChat") .. [[
            repeat with bt in bts
              if value of attribute "AXHelp" of bt is "下一页" ¬
                  and value of attribute "AXEnabled" of bt is True then
                return true
              end if
            end repeat
            return false
          end tell
        ]])
        return ok and valid
      end,
      fn = function()
        hs.osascript.applescript([[
          tell application "System Events"
            -- 推送
            set bts to every button of ]] .. aWinFor("com.tencent.xinWeChat") .. [[
            repeat with bt in bts
              if value of attribute "AXHelp" of bt is "下一页" ¬
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
      condition = function()
        local ok, valid = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor("com.tencent.QQMusicMac") .. [[
              set btCnt to count (every button)
              return (exists button "歌曲详情") and btCnt > 4
            end tell
          end tell
        ]])
        return ok and valid
      end,
      fn = function()
        local ok, valid = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor("com.tencent.QQMusicMac") .. [[
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
    ["closeWindow"] = {
      mods = "⌘", key = "W",
      message = "Close Window",
      fn = function(appObject) appObject:focusedWindow():close() end
    }
  },

  ["com.surteesstudios.Bartender"] =
  {
    ["toggleMenuBar"] = {
      message = "Toggle Menu Bar",
      kind = HK.MENUBAR,
      fn = function(appObject)
        local bundleID = "com.surteesstudios.Bartender"
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
    ["closeWindow"] = {
      mods = "⌘", key = "W",
      message = "Close Window",
      fn = function(appObject) appObject:focusedWindow():close() end
    }
  },

  ["com.gaosun.eul"] =
  {
    ["showSystemStatus"] = {
      message = "Show System Status",
      kind = HK.MENUBAR,
      fn = function()
        local bundleID = "com.gaosun.eul"
        if hiddenByBartender(bundleID) and hasTopNotch(hs.screen.mainScreen()) then
          hs.osascript.applescript([[tell application id "com.surteesstudios.Bartender" to activate "]] .. bundleID .. [[-Item-0"]])
        end
        clickRightMenuBarItem(bundleID)
      end
    }
  },

  ["whbalzac.Dongtaizhuomian"] =
  {
    ["invokeInAppScreenSaver"] = {
      message = "Invoke in-app ScreenSaver",
      fn = function()
        local bundleID = "whbalzac.Dongtaizhuomian"
        if hiddenByBartender(bundleID) and hasTopNotch(hs.screen.mainScreen()) then
          hs.osascript.applescript([[tell application id "com.surteesstudios.Bartender" to activate "]] .. bundleID .. [[-Item-0"]])
        end
        clickRightMenuBarItem(bundleID, "软件内动态屏保")
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

  ["org.pqrs.Karabiner-EventViewer"] =
  {
    ["closeWindow"] = {
      mods = "⌘", key = "W",
      message = "Close Window",
      fn = function(appObject) appObject:focusedWindow():close() end
    }
  },

  ["com.pigigaldi.pock"] =
  {
    ["closeWindow"] = {
      mods = "⌘", key = "W",
      message = "Close Window",
      fn = function(appObject) appObject:focusedWindow():close() end
    }
  },

  ["com.tencent.LemonUpdate"] =
  {
    ["minimizeWindow"] = {
      mods = "⌘", key = "M",
      message = "Minize",
      fn = function(appObject) appObject:focusedWindow():minimize() end
    },
    ["hideApp"] = {
      mods = "⌘", key = "H",
      message = "Hide LemonUpdate",
      fn = function(appObject) appObject:hide() end
    }
  },

  ["com.apple.CaptiveNetworkAssistant"] =
  {
    ["closeWindow"] = {
      mods = "⌘", key = "W",
      message = "Close Window",
      fn = function(appObject) appObject:focusedWindow():close() end
    }
  },

  ["com.parallels.desktop.console"] =
  {
    ["closeWindow"] = {
      mods = "⌘", key = "W",
      message = "Close Window",
      windowFilter = {
        allowTitles = "^Control Center$"
      },
      fn = function(winObj) winObj:close() end
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
      fn = function()
        local ok, pos = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor("com.jetbrains.CLion") .. [[
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
      fn = function()
        local ok, pos = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor("com.jetbrains.CLion-EAP") .. [[
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
        fn = function()
          local ok, pos = hs.osascript.applescript([[
            tell application "System Events"
              tell ]] .. aWinFor("com.jetbrains.intellij") .. [[
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
      fn = function()
        local ok, pos = hs.osascript.applescript([[
          tell application "System Events"
            tell ]] .. aWinFor("com.jetbrains.pycharm") .. [[
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
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 1) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "2",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 2) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "3",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 3) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "4",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 4) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "5",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 5) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "6",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 6) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "7",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 7) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "8",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 8) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "9",
          fn = function(winObj) iCopySelectHotkeyRemap(winObj, 9) end,
          bindCondition = iCopySelectHotkeyRemapRequired
        },
        {
          mods = "⌘", key = "[",
          fn = function(winObj) hs.eventtap.keyStroke("", "Left", nil, winObj:application()) end
        },
        {
          mods = "⌘", key = "]",
          fn = function(winObj) hs.eventtap.keyStroke("", "Right", nil, winObj:application()) end
        },
        {
          mods = "", key = "Left",
          fn = function(winObj) hs.eventtap.keyStroke("", "Up", nil, winObj:application()) end
        },
        {
          mods = "", key = "Right",
          fn = function(winObj) hs.eventtap.keyStroke("", "Down", nil, winObj:application()) end
        },
        {
          mods = "", key = "Up",
          fn = function() end
        },
        {
          mods = "", key = "Down",
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
      local hotkey = bindSpecSuspend(keyBinding, cfg.message, hs.fnutils.partial(cfg.fn, appObject))
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
      if force == true or hotkey.persist ~= true then
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
            local satisfied, result = cfg.condition()
            if satisfied then
              cfg.fn(result, appObject, appName, eventType)
            else
              hs.eventtap.keyStroke(keyBinding.mods, keyBinding.key, nil, appObject)
            end
          end
        end
        local hotkey = bindSpecSuspend(keyBinding, cfg.message,
            inAppHotKeysWrapper(appObject, keyBinding,
                                hs.fnutils.partial(fn, appObject, appName, eventType)))
        hotkey.kind = HK.IN_APP
        hotkey.condition = cfg.condition
        table.insert(inAppHotKeys[bid], hotkey)
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
          windowFilter = spec.windowFilter,
        }
      end
      if type(hkID) ~= 'number' then
        if keyBinding.windowFilter ~= nil and (spec.bindCondition == nil or spec.bindCondition())
            and not spec.notActivateApp then
          local hotkey = bindSpecSuspend(keyBinding, spec.message,
              inWinHotKeysWrapper(appObject, keyBinding.windowFilter, keyBinding, spec.message, spec.fn))
          hotkey.kind = HK.IN_APPWIN
          table.insert(inWinHotKeys[bid], hotkey)
        end
      else
        local cfg = spec[1]
        for _, spec in ipairs(cfg) do
          if (spec.bindCondition == nil or spec.bindCondition()) and not spec.notActivateApp then
            local hotkey = bindSpecSuspend(spec, spec.message,
                inWinHotKeysWrapper(appObject, cfg.filter, spec, spec.message, spec.fn))
            hotkey.kind = HK.IN_APPWIN
            table.insert(inWinHotKeys[bid], hotkey)
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
          windowFilter = spec.windowFilter,
        }
      end
      if type(hkID) ~= 'number' then
        if keyBinding.windowFilter ~= nil then
          local hkIdx = hotkeyIdx(keyBinding.mods, keyBinding.key)
          local prevHotkeyInfo = inWinHotkeyInfoChain[bid][hkIdx]
          inWinHotkeyInfoChain[bid][hkIdx] = {
            appName = appObject:name(),
            filter = keyBinding.windowFilter,
            message = spec.message,
            previous = prevHotkeyInfo
          }
        end
      else
        local cfg = spec[1]
        for _, spec in ipairs(cfg) do
          local hkIdx = hotkeyIdx(spec.mods, spec.key)
          local prevHotkeyInfo = inWinHotkeyInfoChain[bid][hkIdx]
          inWinHotkeyInfoChain[bid][hkIdx] = {
            appName = appObject:name(),
            filter = cfg.filter,
            message = spec.message,
            previous = prevHotkeyInfo
          }
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
        local hotkey = bindSpecSuspend(keybindingConfigs.hotkeys[bid][hkID], spec.message, spec.fn)
        hotkey.kind = HK.IN_WIN
        hotkey.notActivateApp = spec.notActivateApp
        table.insert(inWinOfUnactivatedAppHotKeys[bid], hotkey)
      end
    else
      local cfg = spec[1]
      if sameFilter(cfg.filter, filter) then
        for _, spec in ipairs(cfg) do
          if (spec.bindCondition == nil or spec.bindCondition()) then
            local hotkey = bindSuspend(spec.mods, spec.key, spec.message, spec.fn)
            hotkey.kind = HK.IN_WIN
            hotkey.notActivateApp = cfg.notActivateApp
            table.insert(inWinOfUnactivatedAppHotKeys[bid], hotkey)
          end
        end
      end
    end
  end
end
local function registerInWinOfUnactivatedAppWatchers(bid, appName, filter)
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
  local appName = hs.application.nameForBundleID(bid)
  if appName ~= nil then
    for hkID, spec in pairs(appConfig) do
      if spec.notActivateApp then
        local filter
        if type(hkID) ~= 'number' then
          filter = keybindingConfigs.hotkeys[bid][hkID].windowFilter
        else
          local cfg = spec[1]
          filter = cfg.filter
        end
        if inWinOfUnactivatedAppWatchers[bid] == nil
          or inWinOfUnactivatedAppWatchers[bid][filter] == nil then
          if inWinOfUnactivatedAppWatchers[bid] == nil then
            inWinOfUnactivatedAppWatchers[bid] = {}
          end
          if type(hkID) ~= 'number' then
            registerInWinOfUnactivatedAppWatchers(bid, appName, filter)
          else
            local cfg = spec[1]
            for _, spec in ipairs(cfg) do
              registerInWinOfUnactivatedAppWatchers(bid, appName, filter)
            end
          end
        end
      end
    end
  end
end

-- simplify switching to previous tab
function isAppPreviousTabHotkeyImpl(menuItem)
  if menuItem.AXChildren == nil then return end
  for _, subItem in ipairs(menuItem.AXChildren[1]) do
    if subItem.AXMenuItemCmdGlyph ~= ""
        and hs.application.menuGlyphs[subItem.AXMenuItemCmdGlyph] == "⇥"
        and #subItem.AXMenuItemCmdModifiers == 2
        and hs.fnutils.contains(subItem.AXMenuItemCmdModifiers, 'shift')
        and hs.fnutils.contains(subItem.AXMenuItemCmdModifiers, 'ctrl') then
      return { subItem.AXTitle }, subItem.AXEnabled
    end
    local menuItemPath, enabled = isAppPreviousTabHotkeyImpl(subItem)
    if menuItemPath ~= nil then
      table.insert(menuItemPath, 1, subItem.AXTitle)
      return menuItemPath, enabled
    end
  end
end

function isAppPreviousTabHotkey(appObject)
  local menuItems = appObject:getMenuItems() or {}
  for i=#menuItems,1,-1 do
    local menuItem = menuItems[i]
    local menuItemPath, enabled = isAppPreviousTabHotkeyImpl(menuItem)
    if menuItemPath ~= nil then
      table.insert(menuItemPath, 1, menuItem.AXTitle)
      return menuItemPath, enabled
    end
  end
end

function remapPreviousTab()
  if remapPreviousTabHotkey then
    remapPreviousTabHotkey:delete()
    remapPreviousTabHotkey = nil
  end
  local appObject = hs.application.frontmostApplication()
  local menuItemPath, enabled = isAppPreviousTabHotkey(appObject)
  if menuItemPath ~= nil and enabled then
    remapPreviousTabHotkey = bindSuspend("⌃", "`", menuItemPath[#menuItemPath],
        inAppHotKeysWrapper(appObject, "⌃", "`", function()
          appObject:selectMenuItem(menuItemPath)
        end))
    remapPreviousTabHotkey.kind = HK.IN_APP
  end
end
remapPreviousTab()

-- bind `alt+?` hotkeys to menu bar 1 functions
-- to be registered in application callback
local menuBarTitleLocalizationMap = hs.json.read("config/localization/menuitem.json")
altMenuItemHotkeys = {}

local function bindAltMenu(appObject, mods, key, message, fn)
  fn = showMenuItemWrapper(fn)
  fn = inAppHotKeysWrapper(appObject, mods, key, fn)
  local hotkey = bindSuspend(mods, key, message, fn)
  hotkey.kind = HK.APP_MENU
  return hotkey
end

local function bindHotkeyByNth(appObject, itemTitles, alreadySetHotkeys, index)
  local notSetItems = {}
  for i, title in pairs(itemTitles) do
    local hotkey
    local showTitle
    if type(title) == "table" then
      showTitle = title[1]
      if index == nil then
        index = string.find(title[2], " ")
        if index ~= nil then
          index = index + 1
        end
      end
      if index ~= nil then
        hotkey = string.upper(string.sub(title[2], index, index))
      end
    else
      showTitle = title
      if index == nil then
        index = string.find(title, " ")
        if index ~= nil then
          index = index + 1
        end
      end
      if index ~= nil then
        hotkey = string.upper(string.sub(title, index, index))
      end
    end

    if hotkey ~= nil and not alreadySetHotkeys[hotkey] then
      hotkeyObject = bindAltMenu(appObject, "⌥", hotkey, showTitle, function()
        appObject:selectMenuItem({showTitle})
      end)
      alreadySetHotkeys[hotkey] = true
      altMenuItemHotkeys[i] = hotkeyObject
    else
      notSetItems[i] = title
    end
  end
  return notSetItems, alreadySetHotkeys
end

function altMenuItem(appObject)
  -- delete previous hotkeys
  for _, hotkeyObject in ipairs(altMenuItemHotkeys) do
    hotkeyObject:delete()
  end
  altMenuItemHotkeys = {}

  local enableIndex = keybindingConfigs.hotkeys.menuItems.enableIndex
  local enableLetter = keybindingConfigs.hotkeys.menuItems.enableLetter
  if enableIndex == false and enableLetter == false then return end

  if appObject:name() == "Code" then
    hs.timer.usleep(0.5 * 100000)
  end
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
  if #menuItems == 0 then return end

  -- by initial or otherwise second letter in title
  if enableLetter == true then
    local itemTitles = {}
    for i=2,#menuItems do
      table.insert(itemTitles, menuItems[i].AXTitle)
    end

    -- process localized titles
    if menuBarTitleLocalizationMap ~= nil then
      local defaultTitleMap = menuBarTitleLocalizationMap.common
      local titleMap = menuBarTitleLocalizationMap[appObject:bundleID()]
      for i=#itemTitles,1,-1 do
        -- remove titles starting with non-ascii characters
        if string.byte(itemTitles[i], 1) > 127 then
          local substituted = false
          if titleMap ~= nil then
            if titleMap[itemTitles[i]] ~= nil then
              itemTitles[i] = {itemTitles[i], titleMap[itemTitles[i]]}
              substituted = true
            end
          end
          if not substituted and defaultTitleMap ~= nil then
            if defaultTitleMap[itemTitles[i]] ~= nil then
              itemTitles[i] = {itemTitles[i], defaultTitleMap[itemTitles[i]]}
              substituted = true
            end
          end
          if not substituted then
            table.remove(itemTitles, i)
          end
        end
      end
    end

    local alreadySetHotkeys = {}
    local notSetItems = {}
    for i, title in ipairs(itemTitles) do
      notSetItems[i] = title
    end
    notSetItems, alreadySetHotkeys = bindHotkeyByNth(appObject, notSetItems, alreadySetHotkeys, 1)
    -- if there are still items not set, set them by first letter of second word
    notSetItems, alreadySetHotkeys = bindHotkeyByNth(appObject, notSetItems, alreadySetHotkeys, nil)
    -- if there are still items not set, set them by second letter
    notSetItems, alreadySetHotkeys = bindHotkeyByNth(appObject, notSetItems, alreadySetHotkeys, 2)
    -- if there are still items not set, set them by third letter
    bindHotkeyByNth(appObject, notSetItems, alreadySetHotkeys, 3)
  end

  -- by index
  if enableIndex == true then
    local itemTitles = {}
    for _, item in ipairs(menuItems) do
      table.insert(itemTitles, item.AXTitle)
    end

    local hotkeyObject = bindAltMenu(appObject, "⌥", "`", itemTitles[1] .. " Menu",
        function() appObject:selectMenuItem({itemTitles[1]}) end)
    hotkeyObject.subkind = 0
    altMenuItemHotkeys[#altMenuItemHotkeys + 1] = hotkeyObject
    local maxMenuItemHotkey = #itemTitles > 11 and 10 or (#itemTitles - 1)
    for i=1,maxMenuItemHotkey do
      hotkeyObject = bindAltMenu(appObject, "⌥", tostring(i % 10), itemTitles[i+1] .. " Menu",
          function() appObject:selectMenuItem({itemTitles[i+1]}) end)
      altMenuItemHotkeys[#altMenuItemHotkeys + 1] = hotkeyObject
    end
  end
end
local frontmostApplication = hs.application.frontmostApplication()
altMenuItem(frontmostApplication)

appsWatchMenuItems = applicationConfigs.menuItemsMayChange.basic
appsMenuItemsWatchers = {}

local function watchMenuItems(appObject)
  local getMenuItemTitlesString = function(appObject)
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
    if #menuItems == 0 then return "" end
    local menuItemTitles = {}
    for _, item in ipairs(menuItems) do
      table.insert(menuItemTitles, item.AXTitle)
    end
    return table.concat(menuItemTitles, "|")
  end
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


local appsMayChangeMenu = applicationConfigs.menuItemsMayChange.window
local windowFilterAppsMayChangeMenu = hs.window.filter.new():subscribe(
  {hs.window.filter.windowCreated, hs.window.filter.windowDestroyed,
   hs.window.filter.windowFocused, hs.window.filter.windowUnfocused},  -- may fail
function(winObj)
  if winObj == nil or winObj:application() == nil then return end
  local bundleID = winObj:application():bundleID()
  if hs.fnutils.contains(appsMayChangeMenu, bundleID) then
    altMenuItem(winObj:application())
  end
end)

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
  elseif appObject:bundleID() == "com.apple.finder" and #appObject:visibleWindows() == 1
      and #hs.window.visibleWindows() > #hs.screen.allScreens() then
    appObject:hide()
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

remoteDesktopsMappingModifiers = keybindingConfigs.remap
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

local appsInputSource = applicationConfigs.inputSource
local appsInputSourceMap = {}
for inputSource, appBundleIDs in pairs(appsInputSource) do
  for _, appBundleID in ipairs(appBundleIDs) do
    appsInputSourceMap[appBundleID] = inputSource
  end
end

function selectInputSourceInApp(bid)
  if appsInputSourceMap[bid] ~= nil then
    hs.keycodes.currentSourceID(appsInputSourceMap[bid])
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
local tryInterval = 3
local maxTryTimes = 10

function altMenuItemHelper(appObject, eventType)
  if eventType == hs.application.watcher.activated then
    altMenuItem(appObject)
  elseif eventType == hs.application.watcher.launched then
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
            altMenuItemHelper(appObject, eventType)
          end)
        end
      end
    end
  end
end

function app_applicationCallback(appName, eventType, appObject)
  if eventType == hs.application.watcher.launched then
    if appObject:bundleID() == "com.apple.finder" then
      selectMenuItem(appObject,
        { en = {"File", "New Finder Window"}, zh = {"文件", "新建“访达”窗口"} })
    end
    altMenuItemHelper(appObject, eventType)
  elseif eventType == hs.application.watcher.activated then
    windowCreatedSince = {}
    if appObject:bundleID() == "cn.better365.iShotProHelper" then
      unregisterInWinHotKeys("cn.better365.iShotPro")
      return
    end
    altMenuItem(appObject)
    local frontAppBid = hs.fnutils.find(appsWatchMenuItems, function(bid)
      return bid == appObject:bundleID()
    end)
    if frontAppBid ~= nil then
      watchMenuItems(appObject)
    end
    remapPreviousTab()
    registerRunningAppHotKeys(appObject:bundleID(), appObject)
    registerInAppHotKeys(appName, eventType, appObject)
    registerInWinHotKeys(appObject)
    selectInputSourceInApp(appObject:bundleID())
    if remoteDesktopsMappingModifiers[appObject:bundleID()] then
      if not remoteDesktopModifierTapper:isEnabled() then
        remoteDesktopModifierTapper:start()
      end
    end
  elseif eventType == hs.application.watcher.deactivated then
    if appName ~= nil then
      local bid = appObject:bundleID()
      unregisterInAppHotKeys(bid, eventType)
      unregisterInWinHotKeys(bid)
      if appsMenuItemsWatchers[bid] ~= nil then
        appsMenuItemsWatchers[bid][1]:stop()
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
    local evFlags = HSKeybindings.evFlags
    HSKeybindings:reset()
    HSKeybindings:update(validOnly, showHS, showKara, showApp, evFlags)
  end
end

function app_applicationInstalledCallback(files, flagTables)
  registerAppHotkeys()
end

-- wifi callbacks

-- launch `Mountain Duck` automatically when connected to laboratory wifi
local labproxyConfig = hs.json.read("config/labproxy.json")
local labWifis = labproxyConfig and labproxyConfig.ssid or {}
local lastWifi = hs.wifi.currentNetwork()

function app_wifiChangedCallback()
  local curWifi = hs.wifi.currentNetwork()
  if curWifi == nil then return end

  if hs.fnutils.contains(labWifis, curWifi) and not hs.fnutils.contains(labWifis, lastWifi) then
    -- hs.application.launchOrFocusByBundleID("io.mountainduck")
  elseif not hs.fnutils.contains(labWifis, curWifi) then
    -- quitApplication("io.mountainduck")
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
