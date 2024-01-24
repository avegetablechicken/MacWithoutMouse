HK = {
  PRIVELLEGE = -1,
  SWITCH = 0,
  APP_MENU = 1,
  IN_APP = 2,
  IN_APPWIN = 3,
  IN_WIN = 4,
  APPKEY = 5,
  BACKGROUND = 6,
  MENUBAR = 7,
  MENUBAR_ = { CONTROL_CENTER = 0 },
  WIN_OP = 8,
  WIN_OP_ = { MOVE = 1, RESIZE = 2, SPACE_SCREEN = 3 },
}

hyper = nil
keybindingConfigs = nil
local function loadKeybindings(filePath)
  keybindingConfigs = hs.json.read(filePath)
  for k, hp in pairs(keybindingConfigs.hyper or {}) do
    if type(hp) == "string" then
      if hs.fnutils.contains({"fn", "shift", "option", "control", "command"}) then
        hp = {hp}
      end
    end
    if type(hp) ~= "string" then
      local modsRepr = ""
      if hs.fnutils.contains(hp, "command") then modsRepr = "⌘" end
      if hs.fnutils.contains(hp, "control") then modsRepr = modsRepr .. "⌃" end
      if hs.fnutils.contains(hp, "option") then modsRepr = modsRepr .. "⌥" end
      if hs.fnutils.contains(hp, "shift") then modsRepr = modsRepr .. "⇧" end
      if hs.fnutils.contains(hp, "fn") then modsRepr = "fn" .. modsRepr end
      keybindingConfigs.hyper[k] = modsRepr
    end
  end
  if keybindingConfigs.hyper ~= nil then
    hyper = keybindingConfigs.hyper.hyper
  end

  if keybindingConfigs.hotkeys == nil then
    keybindingConfigs.hotkeys = {}
  end
  for kind, cfg in pairs(keybindingConfigs.hotkeys) do
    if kind ~= "menuBarItems" then
      for k, spec in pairs(cfg) do
        if type(spec.mods) == 'string' then
          spec.mods = string.gsub(spec.mods, "%${(.-)}", function(key)
            local pos = 0
            local buf = keybindingConfigs
            while true do
              local oldPos = pos
              pos = string.find(key, "%.", oldPos + 1)
              if pos then
                buf = buf[string.sub(key, oldPos + 1, pos - 1)]
              else
                buf = buf[string.sub(key, oldPos + 1)]
                break
              end
            end
            return buf
          end)
        end
      end
    end
  end
end
loadKeybindings("config/keybindings.json")

hyperModalList = {}
doubleTapModalList = {}
touchModalList = {}

forgivenApps = {
  "com.devolutions.remotedesktopmanager", "com.devolutions.remotedesktopmanager.free",
  "com.parallels.macvm",
}

function forgiveWrapper(fn, mods, key)
  if fn ~= nil then
    local oldFn = fn
    fn = function()
      if not hs.fnutils.contains(forgivenApps, hs.application.frontmostApplication():bundleID()) then
        oldFn()
      elseif mods ~= nil and key ~= nil then
        selectMenuItemOrKeyStroke(hs.window.frontmostWindow():application(), mods, key)
      end
    end
  end
  return fn
end

function suspendWrapper(fn, mods, key, predicates)
  if fn ~= nil then
    local oldFn = fn
    fn = function()
      local enabled = not hotkeySuspended
      if predicates ~= nil then
        if enabled and predicates.and_ == true then
          if not(predicates.fn)() then
            enabled = false
          end
        elseif not enabled and predicates.or_ == true then
          if (predicates.fn)() then
            enabled = true
          end
        end
      end

      if enabled then
        oldFn()
      elseif mods ~= nil and key ~= nil then
        hs.eventtap.keyStroke(mods, key, nil, hs.window.frontmostWindow():application())
      end
    end
  end
  return fn
end

local function getFunc(f)
  if f == nil then return nil end
  if type(f) == 'function' then return f end
  if type(f) == 'table' then
    local m = getmetatable(f)
    if m and m.__call and type(m.__call) == 'function' then
      return function() m.__call(f) end
    end
  end
  return nil
end

function newHotkey(mods, key, message, pressedfn, releasefn, repeatfn)
  if message == nil or getFunc(message) then
    repeatfn=releasedfn releasedfn=pressedfn pressedfn=message message=nil -- shift down arguments
  end
  pressedfn = getFunc(pressedfn)
  releasedfn = getFunc(releasedfn)
  repeatfn = getFunc(repeatfn)
  pressedfn = forgiveWrapper(pressedfn, mods, key)
  releasedfn = forgiveWrapper(releasedfn, mods, key)
  repeatfn = forgiveWrapper(repeatfn, mods, key)
  local hotkey
  local validHyperModal = hs.fnutils.find(hyperModalList, function(modal)
    return modal.hyper == mods
  end)
  if validHyperModal ~= nil then
    hotkey = validHyperModal.bindSuspend("", key, message, pressedfn, releasedfn, repeatfn)
  else
    hotkey = hs.hotkey.new(mods, key, pressedfn, releasedfn, repeatfn)
  end
  if message ~= nil then
    if mods == hyper then
      hotkey.msg = string.gsub(hotkey.msg, hyperModal.hyper, "✧", 1)
    else
      hotkey.msg = hotkey.idx .. ": " .. message
    end
  end
  return hotkey
end

function newSuspend(mods, key, message, pressedfn, releasefn, repeatfn, predicates)
  if message == nil or getFunc(message) then
    predicate = repeatfn
    repeatfn=releasedfn releasedfn=pressedfn pressedfn=message message=nil -- shift down arguments
  end
  pressedfn = getFunc(pressedfn)
  releasedfn = getFunc(releasedfn)
  repeatfn = getFunc(repeatfn)
  pressedfn = suspendWrapper(pressedfn, mods, key, predicates)
  releasedfn = suspendWrapper(releasedfn, mods, key, predicates)
  repeatfn = suspendWrapper(repeatfn, mods, key, predicates)
  local hotkey = newHotkey(mods, key, message, pressedfn, releasedfn, repeatfn)
  hotkey.suspendable = true
  return hotkey
end

function newSpecSuspend(spec, ...)
  if spec == nil then return nil end
  return newSuspend(spec.mods, spec.key, ...)
end

function bindHotkeySpec(spec, ...)
  local hotkey = newHotkey(spec.mods, spec.key, ...)
  if hotkey ~= nil then
    local validHyperModal = hs.fnutils.find(hyperModalList, function(modal)
      return modal.hyper == spec.mods
    end)
    if validHyperModal == nil then
      hotkey:enable()
    end
  end
  return hotkey
end

function bindSuspend(mods, ...)
  local hotkey = newSuspend(mods, ...)
  if hotkey ~= nil then
    local validHyperModal = hs.fnutils.find(hyperModalList, function(modal)
      return modal.hyper == mods
    end)
    if validHyperModal == nil then
      hotkey:enable()
    end
  end
  return hotkey
end

function bindSpecSuspend(spec, ...)
  if spec == nil then return nil end
  return bindSuspend(spec.mods, spec.key, ...)
end

local misc = keybindingConfigs.hotkeys.global

-- toggle hotkeys
hotkeySuspended = false
HSKeybindings = nil
local toggleHotkey = bindHotkeySpec(misc["toggleHotkeys"], function()
  hotkeySuspended = not hotkeySuspended
  if hotkeySuspended then
    hs.alert.show("Hammerspoon Hotkeys Suspended")
  else
    hs.alert.show("Hammerspoon Hotkeys Resumed")
  end
  if HSKeybindings ~= nil and HSKeybindings.isShowing then
    local validOnly = HSKeybindings.validOnly
    local showHS = HSKeybindings.showHS
    local showKara = HSKeybindings.showKara
    local showApp = HSKeybindings.showApp
    HSKeybindings:reset()
    HSKeybindings:update(validOnly, showHS, showKara, showApp)
  end
end)
toggleHotkey.msg = toggleHotkey.idx .. ": Toggle Hotkeys"
toggleHotkey.kind = HK.PRIVELLEGE

-- reload
bindSpecSuspend(misc["reloadHammerspoon"], "Reload Hammerspoon", function() hs.reload() end).kind = HK.PRIVELLEGE

-- toggle hamerspoon console
bindSpecSuspend(misc["toggleConsole"], "Toggle Hammerspoon Console",
function()
  local consoleWin = hs.console.hswindow()
  if consoleWin and consoleWin:isVisible() then
    consoleWin:close()
  elseif consoleWin and consoleWin:isMinimized() then
    consoleWin:unminimize()
  else
    hs.toggleConsole()
  end
end).kind = HK.PRIVELLEGE

function reloadConfig(files)
  if hs.fnutils.some(files, function(file) return file:sub(-4) == ".lua" end) then
    hs.reload()
  end
end

function applicationCallback(appName, eventType, appObject)
  app_applicationCallback(appName, eventType, appObject)
  system_applicationCallback(appName, eventType, appObject)
end

function applicationInstalledCallback(files, flagTables)
  local files = hs.fnutils.filter(files, function(file) return file:sub(-4) == ".app" end)
  if #files ~= 0 then
    app_applicationInstalledCallback(files, flagTables)
    system_applicationInstalledCallback(files, flagTables)
    fs_applicationInstalledCallback(files, flagTables)
  end
end

function wifiChangedCallback()
  app_wifiChangedCallback()
  system_wifiChangedCallback()
end

function monitorChangedCallback()
  app_monitorChangedCallback()
  system_monitorChangedCallback()
  screen_monitorChangedCallback()
end

function usbChangedCallback(device)
  app_usbChangedCallback(device)
end

configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()
appWatcher = hs.application.watcher.new(applicationCallback):start()
wifiWatcher = hs.wifi.watcher.new(wifiChangedCallback):start()
monitorWatcher = hs.screen.watcher.new(monitorChangedCallback):start()
usbWatcher = hs.usb.watcher.new(usbChangedCallback):start()
appInstalledWatchers = {}
local appDirs =
{
  "/Applications",
  os.getenv("HOME") .. "/Applications",
  os.getenv("HOME") .. "/Applications/JetBrains Toolbox",
  os.getenv("HOME") .. "/Parallels",
}
for _, appDir in ipairs(appDirs) do
  local watcher = hs.pathwatcher.new(appDir, applicationInstalledCallback):start()
  appInstalledWatchers[appDir] = watcher
end

hs.urlevent.bind("alert", function(eventName, params)
  hs.alert.show(params["text"])
end)

-- change system preferences
require "system"

-- move window in current space
require "window"

-- move cursor or window to other monitor
require "screen"

-- manage app
require "app"

-- manage filesystem
require "fs"

-- miscellaneous function
require "misc"
