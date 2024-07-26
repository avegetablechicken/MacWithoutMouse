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

HYPER = nil
KeybindingConfigs = nil
local function loadKeybindings(filePath)
  KeybindingConfigs = hs.json.read(filePath)
  for k, hp in pairs(KeybindingConfigs.hyper or {}) do
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
      KeybindingConfigs.hyper[k] = modsRepr
    end
  end
  if KeybindingConfigs.hyper ~= nil then
    HYPER = KeybindingConfigs.hyper.hyper
  end

  if KeybindingConfigs.hotkeys == nil then
    KeybindingConfigs.hotkeys = {}
  end
  for kind, cfg in pairs(KeybindingConfigs.hotkeys) do
    if kind ~= "menuBarItems" then
      for k, spec in pairs(cfg) do
        if type(spec.mods) == 'string' then
          spec.mods = string.gsub(spec.mods, "%${(.-)}", function(key)
            local pos = 0
            local buf = KeybindingConfigs
            while true do
              local newPos = string.find(key, "%.", pos + 1)
              if newPos then
                buf = buf[string.sub(key, pos + 1, newPos - 1)]
              else
                buf = buf[string.sub(key, pos + 1)]
                break
              end
              pos = newPos
            end
            return buf
          end)
        end
      end
    end
  end
end
loadKeybindings("config/keybindings.json")

HyperModalList = {}
DoubleTapModalList = {}

local hyper = require('modal/hyper')
HyperModal = hyper.install(HYPER)
table.insert(HyperModalList, HyperModal)

FORGIVEN_APPS = {
  "com.devolutions.remotedesktopmanager", "com.devolutions.remotedesktopmanager.free",
  "com.parallels.macvm",
}

---@diagnostic disable-next-line: lowercase-global
function forgiveWrapper(fn, mods, key)
  if fn ~= nil then
    local oldFn = fn
    fn = function()
      if not hs.fnutils.contains(FORGIVEN_APPS, hs.application.frontmostApplication():bundleID()) then
        oldFn()
      elseif mods ~= nil and key ~= nil then
        selectMenuItemOrKeyStroke(hs.window.frontmostWindow():application(), mods, key)
      end
    end
  end
  return fn
end

---@diagnostic disable-next-line: lowercase-global
function suspendWrapper(fn, mods, key, predicates)
  if fn ~= nil then
    local oldFn = fn
    fn = function()
      local enabled = not F_hotkeySuspended
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

---@diagnostic disable-next-line: lowercase-global
function newHotkeyImpl(mods, key, message, pressedfn, releasedfn, repeatfn)
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
  local validHyperModal = hs.fnutils.find(HyperModalList, function(modal)
    return modal.hyper == mods
  end)
  if validHyperModal ~= nil then
    hotkey = validHyperModal:bind("", key, message, pressedfn, releasedfn, repeatfn)
  else
    hotkey = hs.hotkey.new(mods, key, pressedfn, releasedfn, repeatfn)
  end
  if message ~= nil then
    if mods == HYPER then
      hotkey.msg = string.gsub(hotkey.msg, HyperModal.hyper, "✧", 1)
    else
      hotkey.msg = hotkey.idx .. ": " .. message
    end
  end
  return hotkey
end

---@diagnostic disable-next-line: lowercase-global
function newHotkey(mods, key, message, pressedfn, releasedfn, repeatfn, predicates)
  if message == nil or getFunc(message) then
    predicates = repeatfn
    repeatfn=releasedfn releasedfn=pressedfn pressedfn=message message=nil -- shift down arguments
  end
  pressedfn = getFunc(pressedfn)
  releasedfn = getFunc(releasedfn)
  repeatfn = getFunc(repeatfn)
  pressedfn = suspendWrapper(pressedfn, mods, key, predicates)
  releasedfn = suspendWrapper(releasedfn, mods, key, predicates)
  repeatfn = suspendWrapper(repeatfn, mods, key, predicates)
  local hotkey = newHotkeyImpl(mods, key, message, pressedfn, releasedfn, repeatfn)
  hotkey.suspendable = true
  return hotkey
end

---@diagnostic disable-next-line: lowercase-global
function newHotkeySpec(spec, ...)
  if spec == nil then return nil end
  return newHotkey(spec.mods, spec.key, ...)
end

---@diagnostic disable-next-line: lowercase-global
function bindHotkeySpecImpl(spec, ...)
  local hotkey = newHotkeyImpl(spec.mods, spec.key, ...)
  if hotkey ~= nil then
    local validHyperModal = hs.fnutils.find(HyperModalList, function(modal)
      return modal.hyper == spec.mods
    end)
    if validHyperModal == nil then
      hotkey:enable()
    end
  end
  return hotkey
end

---@diagnostic disable-next-line: lowercase-global
function bindHotkey(mods, ...)
  local hotkey = newHotkey(mods, ...)
  if hotkey ~= nil then
    local validHyperModal = hs.fnutils.find(HyperModalList, function(modal)
      return modal.hyper == mods
    end)
    if validHyperModal == nil then
      hotkey:enable()
    end
  end
  return hotkey
end

---@diagnostic disable-next-line: lowercase-global
function bindHotkeySpec(spec, ...)
  if spec == nil then return nil end
  return bindHotkey(spec.mods, spec.key, ...)
end

local misc = KeybindingConfigs.hotkeys.global

-- toggle hotkeys
F_hotkeySuspended = false
HSKeybindings = nil
local toggleHotkey = bindHotkeySpecImpl(misc["toggleHotkeys"], function()
  F_hotkeySuspended = not F_hotkeySuspended
  if F_hotkeySuspended then
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
bindHotkeySpec(misc["reloadHammerspoon"], "Reload Hammerspoon", function()
  hs.reload()
end).kind = HK.PRIVELLEGE

-- toggle hamerspoon console
bindHotkeySpec(misc["toggleConsole"], "Toggle Hammerspoon Console",
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

local function reloadConfig(files)
  if hs.fnutils.some(files, function(file) return file:sub(-4) == ".lua" end) then
    hs.reload()
  end
end

local function applicationCallback(appName, eventType, appObject)
  App_applicationCallback(appName, eventType, appObject)
  System_applicationCallback(appName, eventType, appObject)
end

local function applicationInstalledCallback(files, flagTables)
  files = hs.fnutils.filter(files, function(file) return file:sub(-4) == ".app" end)
  if #files ~= 0 then
    App_applicationInstalledCallback(files, flagTables)
    System_applicationInstalledCallback(files, flagTables)
    File_applicationInstalledCallback(files, flagTables)
  end
end

local function monitorChangedCallback()
  App_monitorChangedCallback()
  System_monitorChangedCallback()
  Screen_monitorChangedCallback()
end

local function usbChangedCallback(device)
  App_usbChangedCallback(device)
end

local function networkChangedCallback(storeObj, changedKeys)
  System_networkChangedCallback(storeObj, changedKeys)
end

ConfigWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()
AppWatcher = hs.application.watcher.new(applicationCallback):start()
MonitorWatcher = hs.screen.watcher.new(monitorChangedCallback):start()
UsbWatcher = hs.usb.watcher.new(usbChangedCallback):start()
AppInstalledWatchers = {}
local appDirs =
{
  "/Applications",
  os.getenv("HOME") .. "/Applications",
  os.getenv("HOME") .. "/Applications/JetBrains Toolbox",
  os.getenv("HOME") .. "/Parallels",
}
for _, appDir in ipairs(appDirs) do
  local watcher = hs.pathwatcher.new(appDir, applicationInstalledCallback):start()
  AppInstalledWatchers[appDir] = watcher
end

NetworkMonitorKeys = { "State:/Network/Global/IPv4" }
NetworkWatcher = hs.network.configuration.open()
NetworkWatcher:monitorKeys(NetworkMonitorKeys)
NetworkWatcher:setCallback(networkChangedCallback)
NetworkWatcher:start()

hs.urlevent.bind("alert", function(eventName, params)
  hs.alert.show(params["text"])
end)

-- manage app
require "app"

-- change system preferences
require "system"

-- move window in current space
require "window"

-- move cursor or window to other monitor
require "screen"

-- manage filesystem
require "fs"

-- miscellaneous function
require "misc"
