local This = {}
This.keys = {}
This.eventtapper = nil

local trackpad = {
  ["top-left"] = "⌜",
  ["top-right"] = "⌝",
  ["bottom-left"] = "⌞",
  ["bottom-right"] = "⌟",
}

function This.bind(mods, key, message, pressedfn, releasedfn, repeatfn)
  local modsCode = 0
  if type(mods) == 'string' then mods = {mods} end
  for i=#mods,1,-1 do
    if mods[i] == "top-left" then
      modsCode = modsCode + 1
      table.remove(mods, i)
    elseif mods[i] == "top-right" then
      modsCode = modsCode + 2
      table.remove(mods, i)
    elseif mods[i] == "bottom-left" then
      modsCode = modsCode + 4
      table.remove(mods, i)
    elseif mods[i] == "bottom-right" then
      modsCode = modsCode + 8
      table.remove(mods, i)
    end
  end
  if This.keys[modsCode] == nil then
    This.keys[modsCode] = {}
  end
  local hotkey = newHotkey(mods, key, message, pressedfn, releasedfn, repeatfn)
  local modsRepr = ""
  if (modsCode // 8) % 2 == 1 then modsRepr = trackpad["bottom-right"] end
  if (modsCode // 4) % 2 == 1 then modsRepr = trackpad["bottom-left"] .. modsRepr end
  if (modsCode // 2) % 2 == 1 then modsRepr = trackpad["top-right"] .. modsRepr end
  if modsCode % 2 == 1 then modsRepr = trackpad["top-left"] .. modsRepr end
  hotkey.msg = modsRepr .. hotkey.msg
  table.insert(This.keys[modsCode], hotkey)
  if This.eventtapper == nil then
    This.eventtapper = hs.eventtap.new({hs.eventtap.event.types.gesture},
    function(ev)
      local touches = ev:getTouches()
      local modsCodeInvoked = 0
      if touches ~= nil and hs.fnutils.every(touches,
          function(t) return t.touching == true and t.type == 'indirect' end) then
        for _, t in ipairs(touches) do
          local tpos = t.normalizedPosition
          if tpos.x < 0.25 and tpos.y > 0.75 then
            modsCodeInvoked = modsCodeInvoked + 1
          elseif tpos.x > 0.75 and tpos.y > 0.75 then
            modsCodeInvoked = modsCodeInvoked + 2
          elseif tpos.x < 0.25 and tpos.y < 0.25 then
            modsCodeInvoked = modsCodeInvoked + 4
          elseif tpos.x > 0.75 and tpos.y < 0.25 then
            modsCodeInvoked = modsCodeInvoked + 8
          else
            modsCodeInvoked = 0
            break
          end
        end
      end
      for k, hotkeys in pairs(This.keys) do
        if k == modsCodeInvoked then
          for _, hk in ipairs(hotkeys) do
            hk:enable()
          end
        else
          for _, hk in ipairs(hotkeys) do
            hk:disable()
          end
        end
      end
      return false
    end):start()
  end
  return hotkey
end

return This
