local alert  = require("hs.alert")
local timer  = require("hs.timer")
local eventtap = require("hs.eventtap")

local events   = eventtap.event.types

local module   = {}

-- double tap this key to trigger the action
module.key = nil
module.mods = {}
module.idx = nil

-- how quickly must the two single **KEY** taps occur?
module.timeFrame = 0.5

-- what to do when the double tap of **KEY** occurs
module.action = nil
module.enabled = false

local function getIndex(keycode) -- key for hotkeys table
  if keycode == hs.keycodes.map[hyper] then return "✧" end
  local key = hs.keycodes.map[keycode]
  key = key and string.upper(key) or '[#'..keycode..']'
  return key
end

local modifiers = {
  command = "⌘",
  control = "⌃",
  option = "⌥",
  shift = "⇧",
  cmd = "⌘",
  ctrl = "⌃",
  alt = "⌥",
  fn = "🌐",
  hyper = "✧"
}

local functionKeycodes = {}
for i=1,20 do
  table.insert(functionKeycodes, hs.keycodes.map['f' .. tostring(i)])
end

function module.install(mods, key)
  if key == nil then
    key = mods mods = nil
  end
  if mods == nil then
    if key == 'cmd' or key == 'command' or key == '⌘' then
      module.key = 'cmd'
      module.idx = '⌘⌘'
    elseif key == 'ctrl' or key == 'control' or key == '⌃' then
      module.key = 'ctrl'
      module.idx = '⌃⌃'
    elseif key == 'alt' or key == 'option' or key == '⌥' then
      module.key = 'alt'
      module.idx = '⌥⌥'
    elseif key == 'shift' or key == '⇧' then
      module.key = 'shift'
      module.idx = '⇧⇧'
    else
      module.key = hs.keycodes.map[key]
      local keyRepr = getIndex(module.key)
      module.idx = keyRepr .. keyRepr
      if hs.fnutils.contains(functionKeycodes, module.key) then
        module.mods = {'fn'}
      end
    end
  else
    if type(mods) == 'string' then mods = {mods} end
    local idx, modsRepr = "", {}
    if hs.fnutils.contains(mods, "command") then
      idx = modifiers.command
      table.insert(modsRepr, 'cmd')
    end
    if hs.fnutils.contains(mods, "control") then
      idx = idx .. modifiers.control
      table.insert(modsRepr, 'ctrl')
    end
    if hs.fnutils.contains(mods, "option") then
      idx = idx .. modifiers.option
      table.insert(modsRepr, 'alt')
    end
    if hs.fnutils.contains(mods, "shift") then
      idx = idx .. modifiers.shift
      table.insert(modsRepr, 'shift')
    end
    if hs.fnutils.contains(functionKeycodes, module.key) then
      table.insert(modsRepr, 'fn')
    end
    module.key = hs.keycodes.map[key]
    module.mods = modsRepr
    local keyRepr = getIndex(module.key)
    module.idx = idx .. keyRepr .. keyRepr
  end
end

function module.bind(msg, func)
  if func == nil then
    func = msg msg = nil
  end
  func = forgiveWrapper(func)
  module.action = function()
    if module.enabled then
      func()
    end
  end
  module.enabled = true
  if msg then module.msg = module.idx .. ": " .. msg end
  return module
end

function module.bindSuspend(msg, func)
  if func == nil then
    func = msg msg = nil
  end
  func = suspendWrapper(func)
  module.bind(msg, func)
  module.suspendable = true
end

function module.enable()
  module.enabled = true
  return module
end

function module.disable()
  module.enabled = false
  return module
end


-- Synopsis:

-- what we're looking for is 4 events within a set time period and no intervening other key events:
--  flagsChanged with only **KEY** = true
--  flagsChanged with all = false
--  flagsChanged with only **KEY** = true
--  flagsChanged with all = false


local timeFirstKeyDown, firstDown, secondDown = 0, false, false

-- verify that no keyboard flags are being pressed
local noFlags = function(ev)
  return ev:getFlags():containExactly({})
end

-- verify that *only* the **KEY** key flag is being pressed
local onlyTargetKey = function(ev)
  if hs.fnutils.contains({'cmd', 'ctrl', 'alt', 'shift'}, module.key) then
    return ev:getFlags():containExactly({module.key})
  else
    return ev:getFlags():containExactly(module.mods) and ev:getKeyCode() == module.key
  end
end

-- the actual workhorse

module.eventWatcher = eventtap.new({events.flagsChanged, events.keyDown, events.keyUp}, function(ev)
  -- if it's been too long; previous state doesn't matter
  if (timer.secondsSinceEpoch() - timeFirstKeyDown) > module.timeFrame then
    timeFirstKeyDown, firstDown, secondDown = 0, false, false
  end

  if hs.fnutils.contains({'cmd', 'ctrl', 'alt', 'shift'}, module.key) then
    if ev:getType() == events.flagsChanged then
      if noFlags(ev) and firstDown and secondDown then  -- **KEY** up and we've seen two, so do action
        if module.action then module.action() end
        timeFirstKeyDown, firstDown, secondDown = 0, false, false
      elseif onlyTargetKey(ev) and not firstDown then   -- **KEY** down and it's a first
        firstDown = true
        timeFirstKeyDown = timer.secondsSinceEpoch()
      elseif onlyTargetKey(ev) and firstDown then       -- **KEY** down and it's the second
        secondDown = true
      elseif not noFlags(ev) then                       -- otherwise reset and start over
        timeFirstKeyDown, firstDown, secondDown = 0, false, false
      end
    else -- it was a key press, so not a lone **KEY** char -- we don't care about it
      timeFirstKeyDown, firstDown, secondDown = 0, false, false
    end
  else
    if ev:getType() == events.flagsChanged then -- it was a flag change, so not a lone **KEY** char -- we don't care about it
      timeFirstKeyDown, firstDown, secondDown = 0, false, false
    else
      if ev:getType() == events.keyDown and onlyTargetKey(ev) and not firstDown then  -- **KEY** down and it's a first
        firstDown = true
        timeFirstKeyDown = timer.secondsSinceEpoch()
      elseif ev:getType() == events.keyDown and onlyTargetKey(ev) and firstDown then      -- **KEY** down and it's the second
        secondDown = true
      elseif ev:getType() == events.keyUp and onlyTargetKey(ev) and firstDown and secondDown then
        -- **KEY** up and we've seen two, so do action
        if module.action then module.action() end
        timeFirstKeyDown, firstDown, secondDown = 0, false, false
      elseif not (ev:getType() == events.keyUp and firstDown) then                        -- otherwise reset and start over
        timeFirstKeyDown, firstDown, secondDown = 0, false, false
      end
    end
  end
  return false
end):start()

return module