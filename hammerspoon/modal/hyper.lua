local This = {}

This.hyperMode = hs.hotkey.modal.new()
This.hyperMode.Entered = false

-- Enter Hyper Mode when Hyper is pressed
function enterHyperMode()
  This.hyperMode:enter()
  This.hyperMode.Entered = true

  -- hyper key up may be captured by `Parallels Desktop`
  -- we need to check if hyper key is still pressed
  hyperPressed = true
  hyperTapper = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(e)
    if e:getKeyCode() == hs.keycodes.map[This.hyper] then
      hyperPressed = true
    end
  end):start()
  hyperTimer = hs.timer.doEvery(1, function()
    if not hyperPressed then
      exitHyperMode()
    end
    hyperPressed = false
  end):start()
end

-- Leave Hyper Mode when Hyper is pressed
function exitHyperMode()
  This.hyperMode:exit()
  This.hyperMode.Entered = false
  hyperTapper:stop()
  hyperTapper = nil
  hyperTimer:stop()
  hyperTimer = nil
end

-- Utility to bind handler to Hyper+modifiers+key
function This.bind(mods, key, message, pressedfn, releasedfn, repeatfn)
  pressedfn = forgiveWrapper(pressedfn, mods, key)
  releasedfn = forgiveWrapper(releasedfn, mods, key)
  repeatfn = forgiveWrapper(repeatfn, mods, key)
  local hotkey = hs.hotkey.new(mods, key, pressedfn, releasedfn, repeatfn)
  hotkey.msg = This.hyper .. hotkey.idx .. ": " .. message
  table.insert(This.hyperMode.keys, hotkey)
  return hotkey
end

function This.bindSuspend(...)
  local hotkey = newSuspend(...)
  hotkey.msg = This.hyper .. hotkey.msg
  table.insert(This.hyperMode.keys, hotkey)
  return hotkey
end

-- Binds the enter/exit functions of the Hyper modal to all combinations of modifiers
function This.install(hotKey)
  This.hyper = hotKey
  local hotkey = hs.hotkey.bind("", hotKey, enterHyperMode, exitHyperMode)
end

return This
