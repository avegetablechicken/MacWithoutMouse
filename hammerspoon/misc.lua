local misc = keybindingConfigs.hotkeys.global

-- call `ShortCuts` to copy to PC
bindSpecSuspend(misc["copyToPC"], "Copy to PC",
function()
  hs.eventtap.keyStroke("⌘", "C")
  hs.shortcuts.run("粘贴到PC")
end)

-- call `ShortCuts` to paste from PC
bindSpecSuspend(misc["pasteFromPC"], "Paste from PC",
function()
  hs.shortcuts.run("复制自PC")
  hs.timer.doAfter(1, function() hs.eventtap.keyStroke("⌘", "V") end)
end)

-- hold command and double tap C to prepend to pasteboard
pasteboardKeyDown = false
pasteboardKeyUp = false
pasteboardBuffer = nil
prependPasteboardTapper = hs.eventtap.new({hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp},
function(ev)
  if ev:getKeyCode() ~= hs.keycodes.map["c"] or not ev:getFlags():containExactly({"cmd"}) then
    return false
  end
  local nowKeyDown = ev:getType() == hs.eventtap.event.types.keyDown
  local nowKeyUp = ev:getType() == hs.eventtap.event.types.keyUp
  if not pasteboardKeyDown and not pasteboardKeyUp and nowKeyDown then
    if hs.fnutils.contains(hs.pasteboard.contentTypes(), "public.utf8-plain-text") then
      pasteboardBuffer = hs.pasteboard.getContents()
      pasteboardKeyDown = true
      prependPasteboardTimer = hs.timer.doAfter(0.3, function()
        pasteboardKeyDown = false
        pasteboardKeyUp = false
        pasteboardBuffer = nil
      end)
    end
  elseif pasteboardKeyDown and not pasteboardKeyUp and nowKeyUp then
    pasteboardKeyUp = true
    pasteboardKeyDown = false
  elseif not pasteboardKeyDown and pasteboardKeyUp and nowKeyDown then
    pasteboardKeyDown = true
    return true
  elseif pasteboardKeyDown and pasteboardKeyUp and nowKeyUp then
    pasteboardKeyDown = false
    pasteboardKeyUp = false
    prependPasteboardTimer:stop()
    prependPasteboardTimer = nil
    if hs.fnutils.contains(hs.pasteboard.contentTypes(), "public.utf8-plain-text") then
      hs.pasteboard.setContents(hs.pasteboard.getContents() .. " " .. pasteboardBuffer)
    end
    pasteboardBuffer = nil
  else
    pasteboardKeyDown = false
    pasteboardKeyUp = false
    pasteboardBuffer = nil
    if prependPasteboardTimer ~= nil then
      prependPasteboardTimer:stop()
      prependPasteboardTimer = nil
    end
  end
  return false
end):start()

-- detect clipboard change and remove suffix added by website
local filterPattern = {
  "(.*) 作者：.*https://www.bilibili.com/.*出处：bilibili$",
  "(.*)\n\n作者：.*链接：https://.*zhihu.com.*来源：知乎.*$",
  "^作者：.*链接：https://.*zhihu.com.*来源：知乎\n著作权.*注明出处。\n\n(.*)$",
}

generalPBWatcher = hs.pasteboard.watcher.new(
function(v)
  if hs.fnutils.contains(hs.pasteboard.contentTypes(), "public.utf8-plain-text") then
    for _, pattern in ipairs(filterPattern) do
      local match = string.match(v, pattern)
      if match ~= nil then
        hs.pasteboard.setContents(match)
        break
      end
    end
  end
end)

-- show all hammerspoon keybinds
HSKeybindings = {}
HSKeybindings.__index = HSKeybindings
HSKeybindings.buffer = nil

function HSKeybindings:init()
  self.sheetView = nil
  self:reset()
end

function HSKeybindings:reset()
  HSKeybindings.buffer = nil
  self.validOnly = true
  self.showHS = true
  self.showKara = false
  self.showApp = false
  self.evFlags = nil
  self.appHotkeysLoaded = false
end

local modifiersShowReverseOrder =
{
  "command", "cmd",
  "option", "alt",
  "control", "ctrl",
  "shift",
  "fn",
  "touchbar:bottom-right",
  "touchbar:bottom-left",
  "touchbar:top-right",
  "touchbar:top-left",
}

local modifierSymbols = { "⌘", "⌥", "⌃", "⇧", "🌐", "✧", "⌟", "⌞", "⌝", "⌜" }

local modifierSymbolMap = {
  command = "⌘",
  control = "⌃",
  option = "⌥",
  shift = "⇧",
  cmd = "⌘",
  ctrl = "⌃",
  alt = "⌥",
  fn = "🌐",
  hyper = "✧",
  ["touchbar:top-left"] = "⌜",
  ["touchbar:top-right"] = "⌝",
  ["touchbar:bottom-left"] = "⌞",
  ["touchbar:bottom-right"] = "⌟",
}

local function loadKarabinerKeyBindings(filePath)
  local json = hs.json.read(filePath)
  local keyBindings = {}
  for _, item in ipairs(json) do
    local mods = item.mods
    if type(mods) == "string" then mods = {mods} end
    local modsRepr = ""
    for _, mod in ipairs(modifiersShowReverseOrder) do
      if hs.fnutils.contains(mods, mod) then modsRepr = modsRepr .. modifierSymbolMap[mod] end
    end
    local key = string.upper(item.key) == hyper and 'hyper' or item.key
    local key = modifierSymbolMap[key] or string.upper(key)
    local idx = modsRepr .. key
    local msg = idx .. ": " .. item.message
    local kind = HK[item.kind]
    local subkind
    if item.kind ~= nil and item.subkind ~= nil then
      if type(item.subkind) == 'number' then
        subkind = item.subkind
      else
        subkind = HK[item.kind .. "_"][item.subkind]
      end
    end
    local keyBinding = {
      idx = idx,
      msg = msg,
      kind = kind,
      subkind = subkind,
    }
    table.insert(keyBindings, keyBinding)
  end
  return keyBindings
end

local function getValidMessage(hotkeyInfo)
  local windowFilter = hs.window.filter.new(false):setAppFilter(
    hotkeyInfo.appName, hotkeyInfo.filter)
  if not windowFilter:isWindowAllowed(hs.application.frontmostApplication():focusedWindow()) then
    if hotkeyInfo.previous then
      return getValidMessage(hotkeyInfo.previous)
    else
      return false, nil
    end
  else
    return true, hotkeyInfo.message
  end
end

local function menuItemHotkeyIdx(mods, key)
  local idx = ""
  for _, mod in ipairs{"cmd", "alt", "ctrl", "shift"} do
    if hs.fnutils.contains(mods, mod) then idx = idx .. modifierSymbolMap[mod] end
  end
  idx = idx .. (string.byte(key, 1) < 127 and string.upper(key) or key)
  return idx
end

local function getSubMenuHotkeys(t, menuItem, titleAsEntry, titlePrefix)
  if menuItem.AXChildren == nil then return end
  if titleAsEntry == true then
    table.insert(t, menuItem.AXTitle)
  end
  for _, subItem in ipairs(menuItem.AXChildren[1]) do
    local title = subItem.AXTitle
    if titlePrefix ~= nil then
      if type(titlePrefix) == 'string' then
        title = titlePrefix .. " > " .. title
      end
    end
    if subItem.AXMenuItemCmdChar ~= "" or subItem.AXMenuItemCmdGlyph ~= "" then
      local idx
      if subItem.AXMenuItemCmdChar ~= "" then
        if subItem.AXTitle == "表情与符号" or subItem.AXTitle == "Emoji & Symbols" then
          idx = "🌐" .. subItem.AXMenuItemCmdChar
        elseif subItem.AXTitle == "进入全屏幕" or subItem.AXTitle == "Enter Full Screen" then
          idx = "🌐" .. subItem.AXMenuItemCmdChar
        else
          idx = menuItemHotkeyIdx(subItem.AXMenuItemCmdModifiers or {}, subItem.AXMenuItemCmdChar)
        end
      elseif hs.application.menuGlyphs[subItem.AXMenuItemCmdGlyph] ~= nil then
        idx = menuItemHotkeyIdx(subItem.AXMenuItemCmdModifiers or {}, hs.application.menuGlyphs[subItem.AXMenuItemCmdGlyph])
      end
      if idx ~= nil then
        table.insert(t, { idx = idx, msg = idx .. ": " .. title,
                          kind = HK.IN_APP, valid = subItem.AXEnabled })
      end
    end
    getSubMenuHotkeys(t, subItem, false, titlePrefix and title or nil)
  end
end

local function loadAppHotkeys(t)
  HSKeybindings.appHotkeysLoaded = true
  local appHotkeys = {}
  local menuItems = hs.application.frontmostApplication():getMenuItems() or {}
  for _, menuItem in ipairs(menuItems) do
    getSubMenuHotkeys(appHotkeys, menuItem, true, true)
  end
  for _, hotkey in ipairs(appHotkeys) do
    if type(hotkey) == 'table' then
      hotkey.source = 2
      if hotkey.valid then
        local frontWin = hs.window.frontmostWindow()
        local activeApp = hs.application.frontmostApplication()
        if (frontWin ~= nil and activeApp:focusedWindow() ~= nil
            and frontWin:application():bundleID() ~= activeApp:bundleID())
            or (frontWin == nil and activeApp:focusedWindow() ~= nil
            and windowCreatedSince[frontWin:id()]) then
          hotkey.valid = false
        end
        if hotkey.valid and hs.fnutils.find(t, function(hk)
            return hk.valid and hk.idx == hotkey.idx end) then
          hotkey.valid = false
        end
      end
    end
  end
  local insertIdx = 1
  for i, hotkey in ipairs(t) do
    if hotkey.kind and hotkey.kind > HK.IN_APP then insertIdx = i break end
  end
  for i=#appHotkeys,1,-1 do
    table.insert(t, insertIdx, appHotkeys[i])
  end
end

local function testValid(entry)
  local pos = string.find(entry.msg, ": ")
  local valid = pos ~= nil
      and not (entry.suspendable and hotkeySuspended)
  local actualMsg
  if valid then
    valid = valid and (entry.enabled == nil or entry.enabled == true)
        and (entry.condition == nil or entry.condition())
    if valid and (entry.kind == HK.APP_MENU or entry.kind == HK.IN_APP) then
      valid = hs.window.frontmostWindow() == nil or hs.application.frontmostApplication():focusedWindow() == nil
          or hs.window.frontmostWindow():application():bundleID() == hs.application.frontmostApplication():bundleID()
    end
    if valid and entry.kind == HK.IN_APPWIN then
      local bundleID
      if hs.window.frontmostWindow() == nil
          or hs.window.frontmostWindow():application():bundleID() == hs.application.frontmostApplication():bundleID()
      then
        bundleID = hs.application.frontmostApplication():bundleID()
      else
        bundleID = hs.window.frontmostWindow():application():bundleID()
      end
      if inWinHotkeyInfoChain ~= nil and inWinHotkeyInfoChain[bundleID] ~= nil then
        local hotkeyInfo = inWinHotkeyInfoChain[bundleID][entry.idx]
        if hotkeyInfo then
          valid, actualMsg = getValidMessage(hotkeyInfo)
        end
      elseif not entry.notActivateApp then
        valid = false
      end
    end
    entry.valid = valid
    if actualMsg ~= nil then
      entry.msg = string.sub(entry.msg, 1, pos - 1) .. ": " .. string.sub(entry.msg, pos + 2)
    end
  else
    entry.valid = false
  end
end

local function processHotkeys(validOnly, showHS, showKara, showApp, evFlags)
  local allKeys = {}
  local enabledAltMenuHotkeys = {}

  if HSKeybindings.buffer ~= nil then
    goto L_endCollect
  end

  for i, modal in ipairs(doubleTapModalList) do
    table.insert(allKeys, { idx = modal.idx, msg = modal.msg,
                            condition = modal.condition, enabled = modal.enabled,
                            kind = modal.kind, subkind = modal.subkind,
                            notActivateApp = modal.notActivateApp,
                            suspendable = modal.suspendable, source = 0 })
  end

  for _, modal in ipairs(hyperModalList) do
    if modal.hyperMode.Entered == false then
      for i, hotkey in ipairs(modal.hyperMode.keys) do
        table.insert(allKeys, { idx = hotkey.idx, msg = hotkey.msg,
                                condition = hotkey.condition,
                                kind = hotkey.kind, subkind = hotkey.subkind,
                                notActivateApp = modal.notActivateApp,
                                suspendable = hotkey.suspendable, source = 0 })
      end
    end
  end

  for _, modal in ipairs(touchModalList) do
    for _, hotkeys in pairs(modal.keys) do
      for _, hotkey in ipairs(hotkeys) do
        table.insert(allKeys, { idx = hotkey.idx, msg = hotkey.msg, source = 0 })
      end
    end
  end

  for _, entry in ipairs(hs.hotkey.getHotkeys()) do
    if entry.idx ~= nil then  -- weird bug
      local newEntry = { idx = entry.idx, msg = entry.msg,
                         condition = entry.condition,
                         kind = entry.kind, subkind = entry.subkind,
                         notActivateApp = entry.notActivateApp,
                         suspendable = entry.suspendable, source = 0 }
      if entry.kind ~= HK.APP_MENU then
        table.insert(allKeys, newEntry)
      else
        table.insert(enabledAltMenuHotkeys, newEntry)
      end
    else
      
    end
  end

  if karaHotkeys == nil then
    karaHotkeys = loadKarabinerKeyBindings("static/karabiner-keybindings.json")
  end
  hs.fnutils.each(karaHotkeys, function(hotkey) hotkey.source = 1 end)
  allKeys = hs.fnutils.concat(allKeys, karaHotkeys)

  for _, entry in ipairs(allKeys) do
    testValid(entry)
  end
  for _, entry in ipairs(enabledAltMenuHotkeys) do
    testValid(entry)
  end

  for _, entry in ipairs(allKeys) do
    local pos = string.find(entry.msg, ": ")
    if pos ~= nil then
      local actualMsg = string.sub(entry.msg, pos + 2)
      local hkRepr = string.sub(entry.msg, 1, pos - 1)
      hkRepr = string.gsub(hkRepr, "ESCAPE", "⎋")
      hkRepr = string.gsub(hkRepr, "TAB", "⇥")
      hkRepr = string.gsub(hkRepr, "SPACE", "␣")
      hkRepr = string.gsub(hkRepr, "DELETE", "⌫")
      hkRepr = string.gsub(hkRepr, "RETURN", "⏎")
      hkRepr = string.gsub(hkRepr, "LEFT", "←")
      hkRepr = string.gsub(hkRepr, "RIGHT", "→")
      hkRepr = string.gsub(hkRepr, "UP", "↑")
      hkRepr = string.gsub(hkRepr, "DOWN", "↓")
      hkRepr = string.gsub(hkRepr, "HOME", "↖")
      hkRepr = string.gsub(hkRepr, "END", "↘")
      hkRepr = string.gsub(hkRepr, "PAGEUP", "⇞")
      hkRepr = string.gsub(hkRepr, "PAGEDOWN", "⇟")
      entry.msg = hkRepr .. ": " .. actualMsg
      entry.idx = hkRepr
    end
  end

  table.sort(allKeys, function(a, b)
    if a.kind ~= nil and b.kind ~= nil then
      if a.kind == b.kind then
        if a.subkind ~= nil and b.subkind ~= nil then
          if a.subkind == b.subkind then
            return a.idx < b.idx
          else
            return a.subkind < b.subkind
          end
        elseif a.subkind ~= nil then
          return true
        elseif b.subkind ~= nil then
          return false
        else
          return a.idx < b.idx
        end
      else
        return a.kind < b.kind
      end
    elseif a.kind ~= nil then
      return true
    elseif b.kind ~= nil then
      return false
    else
      return a.idx < b.idx
    end
  end)
  if #enabledAltMenuHotkeys ~= 0 then
    local insertIdx = 1
    for i, hotkey in ipairs(allKeys) do
      if hotkey.kind > HK.APP_MENU then insertIdx = i break end
    end
    for i, hk in ipairs(altMenuItemHotkeys) do
      local entry = hs.fnutils.find(enabledAltMenuHotkeys, function(menuHK)
        return menuHK.idx == hk.idx
      end)
      if entry ~= nil then
        table.insert(allKeys, insertIdx + i - 1, entry)
      end
    end
    enabledAltMenuHotkeys = nil
  end

  HSKeybindings.buffer = allKeys

  ::L_endCollect::

  if showApp and not HSKeybindings.appHotkeysLoaded then
    loadAppHotkeys(HSKeybindings.buffer)
  end

  local evFlagsRepr
  if evFlags ~= nil then
    evFlagsRepr = ""
    if evFlags.hyper then
      evFlagsRepr = "✧"
    else
      for _, mod in ipairs(modifiersShowReverseOrder) do
        if evFlags[mod] then
          evFlagsRepr = modifierSymbolMap[mod] .. evFlagsRepr
        end
      end
    end
  end
  local menu = ""
  local col = 0
  local ix = 0
  local kind = HK.PRIVELLEGE
  for i, entry in ipairs(HSKeybindings.buffer) do
    if type(entry) == 'string' and showApp then
      local canShow = false
      local j = i + 1
      while j <= #HSKeybindings.buffer and type(HSKeybindings.buffer[j]) ~= 'string' do
        if HSKeybindings.buffer[j].kind == kind
            and (HSKeybindings.buffer[j].valid or not validOnly) then
          canShow = true
          break
        else
          j = j + 1
        end
      end
      if canShow then
        ix = ix + 1
        if ((ix - 1) % 15) == 0 then
          if ix > 1 then
            menu = menu .. "</ul>"
          end
          col = col + 1
          menu = menu .. "<ul class='col col" .. col .. "'>"
        end
        menu = menu .. "<li><div class='menutext'>" .. " " .. entry .. "</div></li>"
      end
    elseif ((entry.source == 0 and showHS) or (entry.source == 1 and showKara) or (entry.source == 2 and showApp))
        and (entry.valid or (not validOnly and string.find(entry.msg, ": ") ~= nil)) then
      local msg
      if entry.kind ~= kind then
        if entry.kind == HK.SWITCH then
          msg = "Misc for Switching"
        elseif entry.kind == HK.APPKEY then
          msg = "AppKeys"
        elseif entry.kind == HK.BACKGROUND then
          msg = "Background Apps"
        elseif entry.kind == HK.MENUBAR then
          msg = "Menu Bar Apps"
        elseif kind < HK.APP_MENU and (entry.kind == HK.APP_MENU
            or entry.kind == HK.IN_APP or entry.kind == HK.IN_APPWIN) then
          msg = hs.application.frontmostApplication():name()
        elseif (entry.kind == HK.IN_APP or entry.kind == HK.IN_APPWIN) then
          msg = nil
        elseif entry.kind == HK.IN_WIN then
          msg = "Frontmost Window: " .. hs.window.frontmostWindow():application():name()
        elseif entry.kind == HK.WIN_OP then
          msg = "Window Operations"
        else
          msg = "Others"
        end
        kind = entry.kind
        if msg ~= nil then
          ix = ix + 1
          if ((ix - 1) % 15) == 0 then
            if ix > 1 then
              menu = menu .. "</ul>"
            end
            col = col + 1
            menu = menu .. "<ul class='col col" .. col .. "'>"
          end
          menu = menu .. "<li><div class='typetext'>" .. " " .. msg .. "</div></li>"
        end
      end

      ix = ix + 1
      if ((ix - 1) % 15) == 0 then
        if ix > 1 then
          menu = menu .. "</ul>"
        end
        col = col + 1
        menu = menu .. "<ul class='col col" .. col .. "'>"
      end
      local modsLen, modsByteLen = 0, 0
      for _, mod in ipairs(modifierSymbols) do
        if string.find(entry.idx, mod) then
          modsLen = modsLen + 1
          if mod == "🌐" then
            modsByteLen = modsByteLen + 4
          else
            modsByteLen = modsByteLen + 3
          end
        end
      end
      if modsByteLen == string.len(entry.idx) then
        modsByteLen = utf8.offset(entry.idx, modsLen) - 1
      end
      local key = string.sub(entry.idx, modsByteLen + 1)
      local mods = string.sub(entry.idx, 1, modsByteLen)
      local modsRepr = mods
      if utf8.len(modsRepr) == 0 then
        modsRepr = "&nbsp;"
      elseif utf8.len(modsRepr) ~= 1 then
        modsRepr = ""
        for _, repr in ipairs(modifierSymbols) do
          if string.find(mods, repr) then
            modsRepr = repr .. modsRepr
          end
        end
      end
      local pos = string.find(entry.msg, ": ")
      local actualMsg = string.sub(entry.msg, pos + 2)
      if not entry.valid then
        if evFlagsRepr ~= modsRepr and (modsRepr ~= "&nbsp;" or evFlagsRepr ~= key) then
          menu = menu .. "<li><font color='grey'><div class='modstext'>" .. modsRepr .. "</div><div class='keytext'>" .. key .. "</div><div class='cmdtext'>" .. actualMsg .. "</div></font></li>"
        else
          menu = menu .. "<li><font color='grey'><div class='modstext highlight'>" .. modsRepr .. "</div><div class='keytext highlight'>" .. key .. "</div><div class='cmdtext highlightcmd'>" .. actualMsg .. "</div></font></li>"
        end
      else
        if evFlagsRepr ~= modsRepr and (modsRepr ~= "&nbsp;" or evFlagsRepr ~= key) then
          menu = menu .. "<li><div class='modstext'>" .. modsRepr .. "</div><div class='keytext'>" .. key .. "</div><div class='cmdtext'>" .. actualMsg .. "</div></li>"
        else
          menu = menu .. "<li><div class='modstext highlight'>" .. modsRepr .. "</div><div class='keytext highlight'>" .. key .. "</div><div class='cmdtext highlightcmd'>" .. actualMsg .. "</div></li>"
        end
      end
    end
  end

  menu = menu .. "</ul>"
  return menu
end

local jsPath = "static/isotope.pkgd.min.js"
local jsFile = io.open(jsPath, 'r')
local js = ""
if jsFile then
    js = jsFile:read("*all")
    jsFile:close()
end
local function generateHtml(validOnly, showHS, showKara, showApp, evFlags)
  local title
  if showHS == true and showKara == false and showApp == false then
    title = "Keybindings of Hammerspoon"
  elseif showHS == false and showKara == true and showApp == false then
    title = "Keybindings of Karabiner-Elements"
  elseif showHS == false and showKara == false and showApp == true then
    title = "Keybindings of Activated Application: " .. hs.application.frontmostApplication():name()
  else
    title = "Keybindings of Hammerspoon, Karabiner-Elements and Activated Application"
  end
  local allmenuitems = processHotkeys(validOnly, showHS, showKara, showApp, evFlags)

  local html = [[
      <!DOCTYPE html>
      <html>
      <head>
      <style type="text/css">
          *{margin:0; padding:0;}
          html, body{
            background-color:#eee;
            font-family: arial;
            font-size: 13px;
          }
          a{
            text-decoration:none;
            color:#000;
            font-size:12px;
          }
          li.title{ text-align:center;}
          ul, li{list-style: inside none; padding: 0 0 5px;}
          footer{
            position: fixed;
            left: 0;
            right: 0;
            height: 48px;
            background-color:#eee;
          }
          header{
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            height:48px;
            text-align:center;
            background-color:#eee;
            z-index:99;
          }
          header hr{
            border: 0;
            height: 0;
            border-top: 1px solid rgba(0, 0, 0, 0.1);
            border-bottom: 1px solid rgba(255, 255, 255, 0.3);
          }
          .title{
            font-size: 18px;
            padding:15px;
          }
          li.title{padding: 0  10px 15px}
          .content{
            padding: 0 0 15px;
            font-size:14px;
            overflow:hidden;
          }
          .content.maincontent{
          position: relative;
            height: 577px;
            margin-top: 46px;
          }
          .content > .col{
            width: ]] .. HSKeybindings.colRatio .. [[%;
            padding:20px 0 20px 20px;
          }

          li:after{
            visibility: hidden;
            display: block;
            font-size: 0;
            content: " ";
            clear: both;
            height: 0;
          }
          .cmdtext{
            float: left;
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
            width: 220px;
            line-height: 1.3;
          }
          .modstext{
            float: left;
            text-align: right;
            overflow: hidden;
            width: 50px;
            line-height: 1.3;
          }
          .keytext{
            float: left;
            text-align: center;
            overflow: hidden;
            width: 30px;
            line-height: 1.3;
          }
          .highlightcmd{
            font-style: oblique;
          }
          .highlight{
            color: DeepSkyBlue;
          }
          .typetext{
            text-align: center;
            overflow: hidden;
            width: 300px;
            line-height: 1.3;
            background: darkgray;
          }
          .menutext{
            text-align: center;
            overflow: hidden;
            width: 300px;
            line-height: 1.3;
            background: lightgray;
          }
      </style>
      </head>
        <body>
          <header>
            <div class="title"><strong>]] .. title .. [[</strong></div>
            <hr />
          </header>
          <div class="content maincontent">]] .. allmenuitems .. [[</div>
          <br>

        <script type="text/javascript">]] .. js .. [[</script>
        <script type="text/javascript">
          var elem = document.querySelector('.content');
          var iso = new Isotope( elem, {
            // options
            itemSelector: '.col',
            layoutMode: 'masonry'
          });
        </script>
        </body>
      </html>
      ]]
  return html
end

--- HSKeybindings:show()
--- Method
--- Show current application's keybindings in a webview
---

function HSKeybindings:show()
  self.sheetView = hs.webview.new({x=0, y=0, w=0, h=0})
  self.sheetView:windowTitle("HSKeybindings")
  self.sheetView:windowStyle("utility")
  self.sheetView:allowGestures(true)
  self.sheetView:allowNewWindows(false)
  self.sheetView:level(hs.drawing.windowLevels.modalPanel)

  local cscreen = hs.screen.mainScreen()
  local cres = cscreen:fullFrame()
  local w = math.min(cres.w * 0.8, 1440)
  local h = math.min(cres.h * 0.75, 830)
  self.sheetView:frame({
      x = cres.x + (cres.w - w) / 2,
      y = cres.y + (cres.h - h) / 2,
      w = w,
      h = h
  })
  if w >= 1320 then
    self.colRatio = 23
  elseif w >= 984 then
    self.colRatio = 31
  else
    self.colRatio = 47
  end
  if validOnly == nil then validOnly = true end
  if showHS == nil then showHS = true end
  if showKara == nil then showKara = false end
  if showApp == nil then showApp = false end
  self:update(true, true, false, false)
  loadAppHotkeys(self.buffer)
end

function HSKeybindings:update(validOnly, showHS, showKara, showApp)
  if validOnly ~= nil then self.validOnly = validOnly end
  if showHS ~= nil then self.showHS = showHS end
  if showKara ~= nil then self.showKara = showKara end
  if showApp ~= nil then self.showApp = showApp end
  local webcontent = generateHtml(self.validOnly, self.showHS, self.showKara, self.showApp, self.evFlags)
  self.sheetView:html(webcontent)
  self.sheetView:show()
end

function HSKeybindings:highlight(evFlags)
  self.evFlags = evFlags
  self:update()
end

--- HSKeybindings:hide()
--- Method
--- Hide the cheatsheet webview
---

function HSKeybindings:hide()
    self.sheetView:hide()
    self.sheetView:delete()
end

doubleTapModal = require('modal/doubletap')
doubleTapModal.install(hyper)
table.insert(doubleTapModalList, doubleTapModal)
doubleTapModal.bindSuspend("Show Keybindings",
function()
  local cancelFunc = function()
    HSKeybindings:hide()
    HSKeybindings:reset()
    hkHideKeybindings:delete()
    hkKeybindingsAll:delete()
    hkKeybindingsHS:delete()
    hkKeybindingsKara:delete()
    hkKeybindingsApp:delete()
    hkShowInvalid:delete()
    hkKeybindingsWatcher:stop()
    hkKeybindingsLastModifier = {}
    hkHideKeybindingsWatcher:stop()
    doubleTapModal.enable()
    hkHideKeybindings = nil
    hkKeybindingsWatcher = nil
  end
  hkHideKeybindings = hs.hotkey.bind("", "Escape", cancelFunc)
  hkKeybindingsAll = hs.hotkey.bind("⌘", "0",
  function()
    hkKeybindingsAll:disable()
    hkKeybindingsHS:enable()
    hkKeybindingsKara:enable()
    hkKeybindingsApp:enable()
    HSKeybindings:update(true, true, true, true)
  end)
  hkKeybindingsHS = hs.hotkey.new("⌘", "1",
  function()
    hkKeybindingsAll:enable()
    hkKeybindingsHS:disable()
    hkKeybindingsKara:enable()
    hkKeybindingsApp:enable()
    HSKeybindings:update(true, true, false, false)
  end)
  hkKeybindingsKara = hs.hotkey.bind("⌘", "2",
  function()
    hkKeybindingsAll:enable()
    hkKeybindingsHS:enable()
    hkKeybindingsKara:disable()
    hkKeybindingsApp:enable()
    HSKeybindings:update(true, false, true, false)
  end)
  hkKeybindingsApp = hs.hotkey.bind("⌘", "3",
  function()
    hkKeybindingsAll:enable()
    hkKeybindingsHS:enable()
    hkKeybindingsKara:enable()
    hkKeybindingsApp:disable()
    HSKeybindings:update(true, false, false, true)
  end)
  
  -- disable all modals activated by this modal
  doubleTapModal.disable()
  local enteredModal = hs.fnutils.find(hyperModalList,
      function(modal) return modal.hyper == hyper end)
  if enteredModal then
    enteredModal.hyperMode:exit()
    enteredModal.hyperMode.Entered = false
  end

  HSKeybindings:show(true, true, false, false)
  hkKeybindingsOptionDown = false
  hkKeybindingsLastModifier = {}
  hkKeybindingsWatcher = hs.eventtap.new({hs.eventtap.event.types.flagsChanged,
      hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp,
      hs.eventtap.event.types.gesture},
  function(ev)
    local evFlags = ev:getFlags()
    if ev:getType() == hs.eventtap.event.types.gesture then
      if hkKeybindingsLastModifier.hyper then
        return false
      else
        local touches = ev:getTouches()
        if touches ~= nil and #touches == 1
          and touches[1].touching == true and touches[1].type == 'indirect' then
          local tpos = touches[1].normalizedPosition
          if tpos.x < 0.25 and tpos.y > 0.75 then
            evFlags["touchbar:top-left"] = true
          elseif tpos.x > 0.75 and tpos.y > 0.75 then
            evFlags["touchbar:top-right"] = true
          elseif tpos.x < 0.25 and tpos.y < 0.25 then
            evFlags["touchbar:bottom-left"] = true
          elseif tpos.x > 0.75 and tpos.y < 0.25 then
            evFlags["touchbar:bottom-right"] = true
          end
        end
      end
    elseif ev:getType() == hs.eventtap.event.types.keyDown then
      if ev:getKeyCode() == hs.keycodes.map[hyper] then
        evFlags.hyper = true
      end
    elseif ev:getType() == hs.eventtap.event.types.keyUp then
      if ev:getKeyCode() == hs.keycodes.map[hyper] then
        evFlags.hyper = nil
      end
    end
    local sameFlags = true
    for k, v in pairs(evFlags) do
      if hkKeybindingsLastModifier[k] ~= v then
        sameFlags = false
        break
      end
    end
    for k, v in pairs(hkKeybindingsLastModifier) do
      if evFlags[k] ~= v then
        sameFlags = false
        break
      end
    end
    if not sameFlags then
      HSKeybindings:highlight(evFlags)
      hkKeybindingsLastModifier = evFlags
    end
    return false
  end):start()
  hkShowInvalid = hs.hotkey.bind("", "Space",
      function()
        HSKeybindings:update(false, HSKeybindings.showHS,
                             HSKeybindings.showKara, HSKeybindings.showApp)
      end,
      function()
        HSKeybindings:update(true, HSKeybindings.showHS,
                             HSKeybindings.showKara, HSKeybindings.showApp)
      end)
  hkHideKeybindingsWatcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown},
      function(ev) cancelFunc() return false end)
  hs.timer.doAfter(0.3, function() hkHideKeybindingsWatcher:start() end)
end)
doubleTapModal.kind = HK.PRIVELLEGE


-- show info of current window
function getCurrentWindow()
  local win = hs.window.frontmostWindow()
  if not win then return false end
  local title = win:title()
  local id = win:id()
  local role = win:role()
  local subrole = win:subrole()
  local pid = win:pid()
  local frame = win:frame()
  return win, title, id, role, subrole, pid, frame
end

function getCurrentApplication()
  local app = hs.window.frontmostWindow():application()
  local bundleID = app:bundleID()
  local appName = app:name()
  return app, appName, bundleID
end

bindSpecSuspend(misc["showCurrentWindowInfo"], "Show Info of Current Window", function()
  local win, title, id, role, subrole, pid, frame = getCurrentWindow()
  if not win then return end
  local app, appName, bundleID = getCurrentApplication()
  hs.focus()
  hs.dialog.blockAlert("Current Window",
    string.format([[
      Window: %s (#%d)
      Role: %s (%s)
      Process: #%s
      Position: (%d, %d)
      Size: %dx%d

      App: %s (%s)]],
    title, id, role, subrole, pid, frame.x, frame.y, frame.w, frame.h,
    appName, bundleID))
end)

local searchHotkey = bindSpecSuspend(misc["searchHotkeys"], "Search Hotkey", function()
  local allKeys = {}

  for i, modal in ipairs(doubleTapModalList) do
    table.insert(allKeys, { modalType = 2,
                            idx = modal.idx, msg = modal.msg,
                            condition = modal.condition, enabled = modal.enabled,
                            kind = modal.kind, subkind = modal.subkind,
                            icon = modal.icon })
  end

  for _, modal in ipairs(hyperModalList) do
    if modal.hyperMode.Entered == false then
      for i, hotkey in ipairs(modal.hyperMode.keys) do
        table.insert(allKeys, { modalType = 1, hyper = _,
                                idx = hotkey.idx, msg = hotkey.msg,
                                condition = hotkey.condition,
                                kind = hotkey.kind, subkind = hotkey.subkind,
                                bundleID = hotkey.bundleID, appPath = hotkey.appPath,
                                icon = hotkey.icon })
      end
    end
  end

  for _, entry in ipairs(hs.hotkey.getHotkeys()) do
    if entry.idx ~= nil then  -- weird bug
      table.insert(allKeys, { modalType = 0,
                              idx = entry.idx, msg = entry.msg,
                              condition = entry.condition,
                              kind = entry.kind, subkind = entry.subkind,
                              bundleID = entry.bundleID, appPath = entry.appPath,
                              icon = entry.icon })
    end
  end

  for _, entry in ipairs(allKeys) do
    local pos = string.find(entry.msg, ": ")
    local valid = pos ~= nil
        and not (entry.suspendable and hotkeySuspended)
    local actualMsg
    if valid then
      valid = valid and (entry.enabled == nil or entry.enabled == true)
          and (entry.condition == nil or entry.condition())
      if valid and (entry.kind == HK.APP_MENU or entry.kind == HK.IN_APP) then
        valid = hs.window.frontmostWindow() == nil or hs.application.frontmostApplication():focusedWindow() == nil
            or hs.window.frontmostWindow():application():bundleID() == hs.application.frontmostApplication():bundleID()
      end
      if valid and entry.kind == HK.IN_APPWIN then
        local bundleID
        if hs.window.frontmostWindow() == nil
            or hs.window.frontmostWindow():application():bundleID() == hs.application.frontmostApplication():bundleID()
        then
          bundleID = hs.application.frontmostApplication():bundleID()
        else
          bundleID = hs.window.frontmostWindow():application():bundleID()
        end
        if inWinHotkeyInfoChain ~= nil and inWinHotkeyInfoChain[bundleID] ~= nil then
          local hotkeyInfo = inWinHotkeyInfoChain[bundleID][entry.idx]
          if hotkeyInfo then
            valid, actualMsg = getValidMessage(hotkeyInfo)
          end
        elseif not entry.notActivateApp then
          valid = false
        end
      end
      entry.valid = valid
      if actualMsg ~= nil then
        entry.msg = string.sub(entry.msg, 1, pos - 1) .. ": " .. string.sub(entry.msg, pos + 2)
      end
    else
      entry.valid = false
    end
  end

  for _, entry in ipairs(allKeys) do
    local pos = string.find(entry.msg, ": ")
    if pos ~= nil then
      local actualMsg = string.sub(entry.msg, pos + 2)
      local hkRepr = string.sub(entry.msg, 1, pos - 1)
      hkRepr = string.gsub(hkRepr, "ESCAPE", "⎋")
      hkRepr = string.gsub(hkRepr, "TAB", "⇥")
      hkRepr = string.gsub(hkRepr, "SPACE", "␣")
      hkRepr = string.gsub(hkRepr, "DELETE", "⌫")
      hkRepr = string.gsub(hkRepr, "RETURN", "⏎")
      hkRepr = string.gsub(hkRepr, "LEFT", "←")
      hkRepr = string.gsub(hkRepr, "RIGHT", "→")
      hkRepr = string.gsub(hkRepr, "UP", "↑")
      hkRepr = string.gsub(hkRepr, "DOWN", "↓")
      hkRepr = string.gsub(hkRepr, "HOME", "↖")
      hkRepr = string.gsub(hkRepr, "END", "↘")
      hkRepr = string.gsub(hkRepr, "PAGEUP", "⇞")
      hkRepr = string.gsub(hkRepr, "PAGEDOWN", "⇟")
      entry.msg = hkRepr .. ": " .. actualMsg
      entry.pretty_idx = hkRepr
    else
      entry.pretty_idx = entry.idx
    end
  end

  table.sort(allKeys, function(a, b)
    if a.kind ~= nil and b.kind ~= nil then
      if a.kind == b.kind then
        if a.subkind ~= nil and b.subkind ~= nil then
          if a.subkind == b.subkind then
            return a.pretty_idx < b.pretty_idx
          else
            return a.subkind < b.subkind
          end
        elseif a.subkind ~= nil then
          return true
        elseif b.subkind ~= nil then
          return false
        else
          return a.pretty_idx < b.pretty_idx
        end
      else
        return a.kind < b.kind
      end
    elseif a.kind ~= nil then
      return true
    elseif b.kind ~= nil then
      return false
    else
      return a.pretty_idx < b.pretty_idx
    end
  end)

  local appHotkeys = {}
  for _, menuItem in ipairs(hs.application.frontmostApplication():getMenuItems()) do
    getSubMenuHotkeys(appHotkeys, menuItem, false, true)
  end
  for _, hotkey in ipairs(appHotkeys) do
    hotkey.modalType = 0
    if hotkey.valid then
      local frontWin = hs.window.frontmostWindow()
      local activeApp = hs.application.frontmostApplication()
      if (frontWin ~= nil and activeApp:focusedWindow() ~= nil
          and frontWin:application():bundleID() ~= activeApp:bundleID())
          or (frontWin == nil and activeApp:focusedWindow() ~= nil
          and windowCreatedSince[frontWin:id()]) then
        hotkey.valid = false
      end
      if hotkey.valid and hs.fnutils.find(allKeys, function(hk)
          return hk.valid and hk.idx == hotkey.idx end) then
        hotkey.valid = false
      end
    end
  end
  local insertIdx
  for i, hotkey in ipairs(allKeys) do
    if hotkey.kind > HK.IN_APP then insertIdx = i break end
  end
  for i=#appHotkeys,1,-1 do
    table.insert(allKeys, insertIdx, appHotkeys[i])
  end

  local choices = {}
  local msg = nil
  local HSImage = hs.image.imageFromAppBundle("org.hammerspoon.Hammerspoon")
  local kind = HK.PRIVELLEGE
  for _, entry in ipairs(allKeys) do
    if string.find(entry.msg, ": ") == nil then
      goto continue
    end

    local image = entry.icon
    if image == nil then
      if entry.kind == HK.PRIVELLEGE then
        image = HSImage
      elseif entry.bundleID then
        if type(entry.bundleID) == "table" then
          local bundleID = hs.fnutils.find(entry.bundleID, function(bundleID)
                return (hs.application.pathForBundleID(bundleID) ~= nil
                    and hs.application.pathForBundleID(bundleID) ~= "")
              end)
          image = hs.image.imageFromAppBundle(bundleID)
        else
          image = hs.image.imageFromAppBundle(entry.bundleID)
        end
      elseif entry.appPath then
        local iconFile = hs.application.infoForBundlePath(entry.appPath).CFBundleIconFile
        if iconFile then
          image = hs.image.imageFromPath(entry.appPath .. "/Contents/Resources/" .. iconFile)
        end
      elseif entry.kind == HK.APP_MENU or entry.kind == HK.IN_APP or entry.kind == HK.IN_APPWIN then
        image = hs.image.imageFromAppBundle(hs.application.frontmostApplication():bundleID())
      elseif entry.kind == HK.IN_WIN then
        if hs.window.frontmostWindow() then
          image = hs.image.imageFromAppBundle(hs.window.frontmostWindow():application():bundleID())
        else
          image = hs.image.imageFromAppBundle(hs.application.frontmostApplication():bundleID())
        end
      elseif entry.kind == HK.MENUBAR and entry.subkind == HK.MENUBAR_.CONTROL_CENTER then
        image = hs.image.imageFromAppBundle("com.apple.controlcenter")
      elseif entry.kind == HK.WIN_OP then
        if entry.subkind == 0 or entry.subkind == HK.WIN_OP_.MOVE or entry.subkind == HK.WIN_OP_.RESIZE then
          image = hs.image.imageFromPath("static/rectangle.png")
        elseif entry.subkind == HK.WIN_OP_.SPACE_SCREEN then
          image = hs.image.imageFromPath("static/display.png")
        end
      end
    end

    if entry.kind ~= kind then
      kind = entry.kind
      if kind == HK.SWITCH then
        msg = "Misc for Switching"
      elseif kind == HK.APPKEY then
        msg = "AppKeys"
      elseif kind == HK.BACKGROUND then
        msg = "for Background Apps"
      elseif kind == HK.MENUBAR then
        msg = "for Menu Bar Apps"
      elseif kind == HK.APP_MENU or kind == HK.IN_APP or kind == HK.IN_APPWIN then
        msg = "for Active App"
      elseif kind == HK.IN_WIN then
        msg = "for Frontmost Window"
      elseif kind == HK.WIN_OP then
        msg = "Window Operations"
      else
        msg = "Others"
      end
    end

    local modsLen, modsByteLen = 0, 0
    for _, mod in ipairs(modifierSymbols) do
      if string.find(entry.idx, mod) then
        modsLen = modsLen + 1
        if mod == "🌐" then
          modsByteLen = modsByteLen + 4
        else
          modsByteLen = modsByteLen + 3
        end
      end
    end
    if modsByteLen == string.len(entry.idx) then
      modsByteLen = utf8.offset(entry.idx, modsLen) - 1
    end
    local key = string.sub(entry.idx, modsByteLen + 1)
    local mods = string.sub(entry.idx, 1, modsByteLen)

    local pos = string.find(entry.msg, ": ")
    local actualMsg
    if pos ~= nil then
      actualMsg = string.sub(entry.msg, pos + 2)
    else
      actualMsg = "(no message)"
    end
    local idx = entry.idx
    local thisHyper
    if entry.modalType == 1 then
      if hyperModalList[entry.hyper].hyper == hyper then
        thisHyper = "✧"
        idx = thisHyper .. idx
      else
        thisHyper = hyperModalList[entry.hyper].hyper
        idx = thisHyper .. idx
      end
    elseif entry.modalType == 0 then
      local pos = string.find(entry.msg, ": ")
      idx = string.sub(entry.msg, 1, pos - 1)
      if string.len(idx) ~= string.len(entry.idx) then
        thisHyper = string.sub(idx, 1, string.len(idx) - string.len(entry.idx))
      end
    end
    table.insert(choices,
        {
          text = actualMsg,
          subText = idx
              .. (msg and " -- " .. msg or "")
              .. (entry.valid and "" or " (DISABLED in current context)"),
          image = image,
          mods = mods,
          key = key,
          modalType = entry.modalType,
          hyper = thisHyper,
          hyperModalIdx = entry.hyper,
        })

    ::continue::
  end
  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    if choice.modalType == 0 then
      if choice.hyper ~= nil then
        if choice.hyper == "✧" then
          for _, hotkey in ipairs(hyperModal.hyperMode.keys) do
            hotkey:enable()
          end
          hs.eventtap.keyStroke(choice.mods, choice.key)
          hs.timer.doAfter(0.2, function()
            for _, hotkey in ipairs(hyperModal.hyperMode.keys) do
              hotkey:disable()
            end
          end)
        else
          for _, modal in ipairs(hyperModalList) do
            if modal.hyper == choice.hyper then
              for _, hotkey in ipairs(modal.hyperMode.keys) do
                hotkey:enable()
              end
              hs.eventtap.keyStroke(choice.mods, choice.key)
              hs.timer.doAfter(0.2, function()
                for _, hotkey in ipairs(modal.hyperMode.keys) do
                  hotkey:disable()
                end
              end)
              break
            end
          end
        end
      else
        hs.eventtap.keyStroke(choice.mods, choice.key)
      end
    elseif choice.modalType == 1 then
      local modal = hyperModalList[choice.hyperModalIdx]
      for _, hotkey in ipairs(modal.hyperMode.keys) do
        hotkey:enable()
      end
      hs.eventtap.keyStroke(choice.mods, choice.key)
      hs.timer.doAfter(0.2, function()
        for _, hotkey in ipairs(modal.hyperMode.keys) do
          hotkey:disable()
        end
      end)
    elseif choice.modalType == 2 then
      if hs.fnutils.contains({ "⌘", "⌥", "⌃", "⇧" }, choice.key) then
        local flag
        if choice.key == "⌘" then
          flag = 'cmd'
        elseif choice.key == "⌥" then
          flag = 'alt'
        elseif choice.key == "⌃" then
          flag = 'ctrl'
        elseif choice.key == "⇧" then
          flag = 'shift'
        end
        local event = hs.eventtap.event.newEvent()
        event:setType(hs.eventtap.event.types.flagsChanged)
        event:setFlags({ [flag] = true }):post()
        event:setFlags({}):post()
        event:setFlags({ [flag] = true }):post()
        event:setFlags({}):post()
      else
        local keycode
        if choice.key == "✧" then
          keycode = hs.keycodes.map[hyper]
        else
          local keyLen = string.len(choice.key)
          keycode = string.sub(choice.key, 1, keyLen / 2)
        end
        hs.eventtap.event.newKeyEvent("", keycode, true):post()
        hs.eventtap.event.newKeyEvent("", keycode, false):post()
        hs.eventtap.event.newKeyEvent("", keycode, true):post()
        hs.eventtap.event.newKeyEvent("", keycode, false):post()
      end
    end
  end)
  chooser:searchSubText(true)
  chooser:choices(choices)
  chooser:show()
end)
searchHotkey.kind = HK.PRIVELLEGE
