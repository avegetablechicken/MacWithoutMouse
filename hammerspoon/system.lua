require "utils"

-- menubar for caffeine
caffeine = hs.menubar.new()

function setCaffeineDisplay(state)
  if state then
    caffeine:setTitle("AWAKE")
  else
    caffeine:setTitle("SLEEPY")
  end
end

function caffeineClicked()
  setCaffeineDisplay(hs.caffeinate.toggle("displayIdle"))
end

if caffeine then
  caffeine:setClickCallback(caffeineClicked)
  setCaffeineDisplay(hs.caffeinate.get("displayIdle"))
end

-- system proxy helpers
local function proxy_info(networkservice)
  networkservice = networkservice or curNetworkService
  autodiscovery = hs.execute("networksetup -getproxyautodiscovery " .. networkservice)
  autoproxyurl = hs.execute("networksetup -getautoproxyurl " .. networkservice)
  webproxy = hs.execute("networksetup -getwebproxy " .. networkservice)
  securewebproxy = hs.execute("networksetup -getsecurewebproxy " .. networkservice)
  socksproxy = hs.execute("networksetup -getsocksfirewallproxy " .. networkservice)
  return { autodiscovery, autoproxyurl, webproxy, securewebproxy, socksproxy }
end

local function disable_proxy(networkservice)
  networkservice = networkservice or curNetworkService
  hs.execute("networksetup -setproxyautodiscovery " .. networkservice .. ' off')
  hs.execute("networksetup -setautoproxystate " .. networkservice .. ' off')
  hs.execute("networksetup -setwebproxystate " .. networkservice .. ' off')
  hs.execute("networksetup -setsecurewebproxystate " .. networkservice .. ' off')
  hs.execute("networksetup -setsocksfirewallproxystate " .. networkservice .. ' off')
end

local function enable_proxy_PAC(client, networkservice, location)
  networkservice = networkservice or curNetworkService
  hs.execute("networksetup -setproxyautodiscovery " .. networkservice .. ' off')
  hs.execute("networksetup -setwebproxystate " .. networkservice .. ' off')
  hs.execute("networksetup -setsecurewebproxystate " .. networkservice .. ' off')
  hs.execute("networksetup -setsocksfirewallproxystate " .. networkservice .. ' off')

  if client ~= nil then
    local PACFile
    if location == nil then
      PACFile = ProxyConfigs[client].PAC
    else
      PACFile = ProxyConfigs[client][location].PAC
    end
    hs.execute("networksetup -setautoproxyurl " .. networkservice .. ' ' .. PACFile)
  end
  hs.execute("networksetup -setautoproxystate " .. networkservice .. ' on')
end

local function enable_proxy_global(client, networkservice, location)
  networkservice = networkservice or curNetworkService
  hs.execute("networksetup -setproxyautodiscovery " .. networkservice .. ' off')
  hs.execute("networksetup -setautoproxystate " .. networkservice .. ' off')

  if client ~= nil then
    local addrs
    if location == nil then
      addrs = ProxyConfigs[client].global
    else
      addrs = ProxyConfigs[client][location].global
    end
    hs.execute("networksetup -setwebproxy " .. networkservice .. ' ' .. addrs[1] .. ' ' .. addrs[2])
    hs.execute("networksetup -setsecurewebproxy " .. networkservice .. ' ' .. addrs[3] .. ' ' .. addrs[4])
    hs.execute("networksetup -setsocksfirewallproxy " .. networkservice .. ' ' .. addrs[5] .. ' ' .. addrs[6])
  end

  hs.execute("networksetup -setwebproxystate " .. networkservice .. ' on')
  hs.execute("networksetup -setsecurewebproxystate " .. networkservice .. ' on')
  hs.execute("networksetup -setsocksfirewallproxystate " .. networkservice .. ' on')
end

local proxyAppBundleIDs = {
  V2RayX = "cenmrev.V2RayX",
  V2rayU = "net.yanue.V2rayU",
  MonoCloud = "com.MonoCloud.MonoProxyMac",
}

-- toggle connect/disconnect VPN using `V2RayX`
local function toggleV2RayX(enable, alert)
  local bundleID = proxyAppBundleIDs.V2RayX

  local script = ""
  if findApplication(bundleID) == nil then
    script = [[
      tell application id "]] .. bundleID .. [[" to activate
    ]]
  end

  if hiddenByBartender(bundleID) and hasTopNotch(hs.screen.mainScreen()) then
    script = script .. [[
      tell application id "com.surteesstudios.Bartender" to activate "]] .. bundleID .. [[-Item-0"
    ]]
  end

  script = script .. [[
    ignoring application responses
      tell application "System Events"
        click menu bar item 1 of menu bar 2 of ¬
            (first application process whose bundle identifier is "]] .. bundleID .. [[")
      end tell
    end ignoring

    delay 1
    do shell script "killall System\\ Events"

    tell application "System Events"
      set popupMenu to menu 1 of menu bar item 1 of menu bar 2 of ¬
          (first application process whose bundle identifier is "]] .. bundleID .. [[")
      %s
    end tell

    return ret
  ]]

  if enable == true then
    script = string.format(script, [[
      if exists menu item "Load core" of popupMenu then
        click menu item "Load core" of popupMenu
      end if
      set ret to 0
    ]])
  elseif enable == false then
    script = string.format(script, [[
      if exists menu item "Unload core" of popupMenu then
        click menu item "Unload core" of popupMenu
      end if
      set ret to 1
    ]])
  else
    script = string.format(script, [[
      if exists menu item "Load core" of popupMenu then
        click menu item "Load core" of popupMenu
        set ret to 0
      else
        click menu item "Unload core" of popupMenu
        set ret to 1
      end if
    ]])
  end

  local ok, ret = hs.osascript.applescript(script)
  if ok then
    if alert ~= nil and alert == true then
      if ret == 0 then
        hs.alert("V2Ray core loaded in \"V2RayX\"")
      else
        hs.alert("V2Ray core unloaded in \"V2RayX\"")
      end
    end
  else
    if alert ~= nil and alert ~= false then
      hs.alert("Error occurred while loading/unloading V2ray core in \"V2RayX\"")
    end
  end

  return ok
end

-- toggle connect/disconnect VPN using `V2rayU`
local function toggleV2RayU(enable, alert)
  local bundleID = proxyAppBundleIDs.V2rayU

  local script = ""
  if findApplication(bundleID) == nil then
    script = [[
      tell application id "]] .. bundleID .. [[" to activate
    ]]
  end

  if hiddenByBartender(bundleID) and hasTopNotch(hs.screen.mainScreen()) then
    script = script .. [[
      tell application id "com.surteesstudios.Bartender" to activate "]] .. bundleID .. [[-Item-0"
    ]]
  end

  script = script .. [[
    ignoring application responses
      tell application "System Events"
        click menu bar item 1 of menu bar 2 of ¬
            (first application process whose bundle identifier is "]] .. bundleID .. [[")
      end tell
    end ignoring

    delay 1
    do shell script "killall System\\ Events"

    tell application "System Events"
      set popupMenu to menu 1 of menu bar item 1 of menu bar 2 of ¬
          (first application process whose bundle identifier is "]] .. bundleID .. [[")
      %s
    end tell

    return ret
  ]]

  if enable == true then
    script = string.format(script, [[
      if exists menu item "Turn v2ray-core On" of popupMenu then
        click menu item "Turn v2ray-core On" of popupMenu
      end if
      set ret to 0
    ]])
  elseif enable == false then
    script = string.format(script, [[
      if exists menu item "Turn v2ray-core Off" of popupMenu then
        click menu item "Turn v2ray-core Off" of popupMenu
      end if
      set ret to 1
    ]])
  else
    script = string.format(script, [[
      if exists menu item "Turn v2ray-core On" of popupMenu then
        click menu item "Turn v2ray-core On" of popupMenu
        set ret to 0
      else
        click menu item "Turn v2ray-core Off" of popupMenu
        set ret to 1
      end if
    ]])
  end

  local ok, ret = hs.osascript.applescript(script)
  if ok then
    if alert ~= nil and alert == true then
      if ret == 0 then
        hs.alert("V2Ray core loaded in \"V2rayU\"")
      else
        hs.alert("V2Ray core unloaded in \"V2rayU\"")
      end
    end
  else
    if alert ~= nil and alert ~= false then
      hs.alert("Error occurred while loading/unloading V2ray core in \"V2rayU\"")
    end
  end

  return ok
end

-- toggle connect/disconnect VPN using `MonoProxyMac`
local function toggleMonoCloud(enable, alert)
  local bundleID = proxyAppBundleIDs.MonoCloud

  local script = ""
  if findApplication(bundleID) == nil then
    script = [[
      tell application id "]] .. bundleID .. [[" to activate
    ]]
  end

  if hiddenByBartender(bundleID) and hasTopNotch(hs.screen.mainScreen()) then
    script = script .. [[
      tell application id "com.surteesstudios.Bartender" to activate "]] .. bundleID .. [[-Item-0"
    ]]
  end

  script = script .. [[
    ignoring application responses
      tell application "System Events"
        click menu bar item 1 of menu bar 1 of ¬
            (first application process whose bundle identifier is "]] .. bundleID .. [[")
      end tell
    end ignoring

    delay 1
    do shell script "killall System\\ Events"

    tell application "System Events"
      set popupMenu to menu 1 of menu bar item 1 of menu bar 1 of ¬
          (first application process whose bundle identifier is "]] .. bundleID .. [[")
      set menuitem to menu item "Set As System Proxy" of popupMenu
      set ticked to value of attribute "AXMenuItemMarkChar" of menuitem
      %s
    end tell

    return ret
  ]]

  if enable == true then
    script = string.format(script, [[
      if ticked is not "✓" then
        click menuitem
      end if
      set ret to 0
    ]])
  elseif enable == false then
    script = string.format(script, [[
      if ticked is "✓" then
        click menuitem
      end if
      set ret to 1
    ]])
  else
    script = string.format(script, [[
      click menuitem
      if ticked is "✓" then
        set ret to 1
      else
        set ret to 0
      end if
    ]])
  end

  local ok, ret = hs.osascript.applescript(script)
  if ok then
    if alert ~= nil and alert == true then
      if ret == 0 then
        hs.alert("Set MonoProxyMac as system proxy")
      else
        hs.alert("Unset MonoProxyMac as system proxy")
      end
    end
  else
    if alert ~= nil and alert ~= false then
      hs.alert("Error occurred. Please retry")
    end
  end

  return ok
end

-- menubar for proxy
proxy = hs.menubar.new()
proxy:setTitle("PROXY")
proxyMenu = {}

-- load proxy configs
ProxyConfigs = {}

function parseProxyConfigurations(configs)
  for name, config in pairs(configs) do
    ProxyConfigs[name] = {}
    if config.condition ~= nil then
      ProxyConfigs[name].condition = config.condition
      ProxyConfigs[name].locations = config.locations
      for i, loc in ipairs(config.locations) do
        local spec = config[loc]
        local httpIp, httpPort = string.match(spec.global.http, "(.+):(%d+)")
        local httpsIp, httpsPort = string.match(spec.global.https, "(.+):(%d+)")
        local socksIp, socksPort = string.match(spec.global.socks5, "(.+):(%d+)")
        ProxyConfigs[name][loc] = {
          PAC = spec.pac,
          global = { httpIp, httpPort, httpsIp, httpsPort, socksIp, socksPort }
        }
      end
    else
      local spec = config
        local httpIp, httpPort = string.match(spec.global.http, "(.+):(%d+)")
        local httpsIp, httpsPort = string.match(spec.global.https, "(.+):(%d+)")
        local socksIp, socksPort = string.match(spec.global.socks5, "(.+):(%d+)")
        ProxyConfigs[name] = {
          PAC = spec.pac,
          global = { httpIp, httpPort, httpsIp, httpsPort, socksIp, socksPort }
        }
    end
  end
end

local proxyConfigs
if hs.fs.attributes("config/proxy.json") ~= nil then
  proxyConfigs = hs.json.read("config/proxy.json")
end
if proxyConfigs ~= nil then
  parseProxyConfigurations(proxyConfigs)
end

local privateProxyConfigs
if hs.fs.attributes("config/private-proxy.json") ~= nil then
  privateProxyConfigs = hs.json.read("config/private-proxy.json")
end
if privateProxyConfigs ~= nil then
  parseProxyConfigurations(privateProxyConfigs)
end

proxyMenuItemCandidates =
{
  {
    appname = "V2RayX",
    shortcut = 'x',
    items = {
      {
        title = "    Global Mode",
        fn = function()
          if toggleV2RayX(true) then
            clickRightMenuBarItem(proxyAppBundleIDs.V2RayX, "Global Mode")
            enable_proxy_global("V2RayX")
          end
        end
      },

      {
        title = "    PAC Mode",
        fn = function()
          if toggleV2RayX(true) then
            clickRightMenuBarItem(proxyAppBundleIDs.V2RayX, "PAC Mode")
            enable_proxy_PAC("V2RayX")
          end
        end
      }
    }
  },

  {
    appname = "V2rayU",
    shortcut = 'u',
    items = {
      {
        title = "    Global Mode",
        fn = function()
          if toggleV2RayU(true) then
            clickRightMenuBarItem(proxyAppBundleIDs.V2rayU,
                                 { localized = "Global Mode", strings = "MainMenu" })
            enable_proxy_global("V2rayU")
          end
        end
      },

      {
        title = "    PAC Mode",
        fn = function()
          if toggleV2RayU(true) then
            clickRightMenuBarItem(proxyAppBundleIDs.V2rayU,
                                  { localized = "Pac Mode", strings = "MainMenu" })
            enable_proxy_PAC("V2rayU")
          end
        end
      }
    }
  },

  {
    appname = "MonoCloud",
    shortcut = 'm',
    items = {
      {
        title = "    Global Mode",
        fn = function()
          toggleMonoCloud(false)
          clickRightMenuBarItem(proxyAppBundleIDs.MonoCloud, "Outbound Mode", 2)
          enable_proxy_global("MonoCloud")
        end
      },

      {
        title = "    PAC Mode",
        fn = function()
          toggleMonoCloud(false)
          clickRightMenuBarItem(proxyAppBundleIDs.MonoCloud, "Outbound Mode", 3)
          enable_proxy_global("MonoCloud")
        end
      }
    }
  },
}

function updateProxyWrapper(wrapped, appname)
  local fn = function(mod, item)
    wrapped.fn(mod, item)
    local newProxyMenu = {}
    for i, _item in ipairs(proxyMenu) do
      _item.checked = false
      item.checked = true
      if not string.find(_item.title, "Proxy:")
          and not string.find(_item.title, "PAC File:")then
        table.insert(newProxyMenu, _item)
      end
      if _item.title == appname then
        if string.match(item.title, "PAC") then
          local PACFile = hs.execute("networksetup -getautoproxyurl " .. curNetworkService
                                          .. " | grep URL: | awk '{print $2}'")
          table.insert(newProxyMenu, { title = "PAC File: " .. PACFile, disabled = true })
        else
          local httpAddr = hs.execute("networksetup -getwebproxy " .. curNetworkService
                                          .. " | grep Server: | awk '{print $2}'")
          local httpPort = hs.execute("networksetup -getwebproxy " .. curNetworkService
                                          .. " | grep Port: | awk '{print $2}'")
          local socksAddr = hs.execute("networksetup -getsocksfirewallproxy " .. curNetworkService
                                          .. " | grep Server: | awk '{print $2}'")
          local socksPort = hs.execute("networksetup -getsocksfirewallproxy " .. curNetworkService
                                          .. " | grep Port: | awk '{print $2}'")
          table.insert(newProxyMenu, { title = "HTTP Proxy: " .. httpAddr .. ":" .. httpPort, disabled = true })
          table.insert(newProxyMenu, { title = "SOCKS5 Proxy: " .. socksAddr .. ":" .. socksPort, disabled = true })
        end
      end
    end
    proxyMenu = newProxyMenu
    proxy:setMenu(proxyMenu)
  end

  return {
    title = wrapped.title,
    fn = fn,
    shortcut = wrapped.shortcut,
    checked = wrapped.checked,
  }
end

local function parseProxyInfo(info, require_mode)
  if require_mode == nil then require_mode = true end
  local enabledProxy = ""
  local mode = nil
  if string.match(info[2], "Enabled: Yes") then
    for appname, config in pairs(ProxyConfigs) do
      if config.PAC ~= nil then
        if string.match(info[2], config.PAC) then
          enabledProxy = appname
          mode = "PAC"
        end
      else
        for loc, spec in pairs(config) do
          if spec.PAC ~= nil and string.match(info[2], spec.PAC) then
            enabledProxy = appname
            mode = "PAC"
            break
          end
        end
      end
      if mode ~= nil then break end
    end
  elseif string.match(info[3], "Enabled: Yes") then
    for appname, config in pairs(ProxyConfigs) do
      if config.global ~= nil then
        if string.match(info[3], config.global[1])
            and string.match(info[3], tostring(config.global[2])) then
          enabledProxy = appname
        end
      else
        for loc, spec in pairs(config) do
          if spec.global ~= nil and string.match(info[3], spec.global[1])
              and string.match(info[3], tostring(spec.global[2])) then
            enabledProxy = appname
            break
          end
        end
      end
      if enabledProxy ~= "" then
        if enabledProxy ~= "MonoCloud" then
          mode = "Global"
        elseif require_mode then
          local bundleID = proxyAppBundleIDs.MonoCloud
          local script = ""
          local appObject = findApplication(bundleID)
          if hiddenByBartender(bundleID) and hasTopNotch(hs.screen.mainScreen()) then
            script = [[
              tell application id "com.surteesstudios.Bartender"
                activate "]] .. bundleID .. [[-Item-0"
              end tell
            ]]
          end
          script = script .. [[
            ignoring application responses
              tell application "System Events"
                click menu bar item 1 of menu bar 1 of ¬
                    (first application process whose bundle identifier is  "]] .. bundleID .. [[")
              end tell
            end ignoring

            delay 0.2
            do shell script "killall System\\ Events"

            tell application "System Events"
              set menuitem to menu item "Outbound Mode" of menu 1 of menu bar item 1 of menu bar 1 of ¬
                  (first application process whose bundle identifier is  "]] .. bundleID .. [[")
              click menuitem

              set submenuitem to menu item 2 of menu "Outbound Mode" of menuitem
              set ticked to value of attribute "AXMenuItemMarkChar" of submenuitem
              if ticked is "✓" then
                set ret to 0
              else
                set submenuitem to menu item 3 of menu "Outbound Mode" of menuitem
                set ticked to value of attribute "AXMenuItemMarkChar" of submenuitem
                if ticked is "✓" then
                  set ret to 1
                else
                  set ret to -1
                end if
              end if
              key code 53
            end tell
            return ret
          ]]
          local ok, result = hs.osascript.applescript(script)
          if not ok then
            ok, result = hs.osascript.applescript(script)
          end
          if ok then
            if result == 0 then
              mode = "Global"
            elseif result == 1 then
              mode = "PAC"
            end
          end
        end
        break
      end
    end
  end
  if require_mode then
    return enabledProxy, mode
  else
    return enabledProxy
  end
end

local function registerProxyMenuImpl()
  local enabledProxy, mode = parseProxyInfo(proxy_info())

  proxyMenu =
  {
    {
      title = "Information",
      fn = function()
        local info = proxy_info()
        local enabledProxy, mode = parseProxyInfo(proxy_info())
        local info_str
        if enabledProxy ~= "" then
          info_str = "Enabled: " .. enabledProxy
          if mode ~= nil then
            info_str = info_str .. " (" .. mode .. ")"
          end
        else
          info_str = "No Proxy Enabled"
        end
        info_str = info_str .. [[


          Details:

          ]] .. info[1] .. [[

          Auto Proxy:
          ]] .. info[2] .. [[

          HTTP Proxy:
          ]] .. info[3] .. [[

          HTTPS Proxy:
          ]] .. info[4] .. [[

          SOCKS Proxy:
          ]] .. info[5]
        hs.focus()
        hs.dialog.blockAlert("Proxy Configuration", info_str)
      end,
      shortcut = 'i',
    },

    updateProxyWrapper({
      title = "Disable",
      fn = function() disable_proxy() end,
      shortcut = '0',
      checked = enabledProxy == ""
    }),
  }

  local proxyMenuIdx = 1
  for _, candidate in ipairs(proxyMenuItemCandidates) do
    local bundleID = proxyAppBundleIDs[candidate.appname]
    if hs.application.pathForBundleID(bundleID) ~= nil
        and hs.application.pathForBundleID(bundleID) ~= "" then
      local appname = candidate.appname == "MonoCloud" and "MonoProxyMac" or candidate.appname
      table.insert(proxyMenu, { title = "-" })
      table.insert(proxyMenu, {
        title = candidate.appname,
        fn = function()
          local actionFunc = function()
            if findApplication("com.surteesstudios.Bartender") ~= nil then
              hs.osascript.applescript([[
                tell application id "com.surteesstudios.Bartender"
                  activate "]] .. findApplication(appname):bundleID() .. [[-Item-0"
                end tell
              ]])
            else
              clickRightMenuBarItem(appname)
            end
          end
          if findApplication(bundleID) == nil then
            hs.application.launchOrFocusByBundleID(bundleID)
            hs.timer.waitUntil(
              function() return findApplication(appname) ~= nil end,
              actionFunc)
          else
            actionFunc()
          end
        end,
        shortcut = candidate.shortcut
      })
      if candidate.appname == enabledProxy and mode ~= nil then
        if mode == "PAC" and ProxyConfigs[candidate.appname]["PAC"] ~= nil then
          local PACFile = ProxyConfigs[candidate.appname]["PAC"]
          table.insert(proxyMenu, { title = "PAC File: " .. PACFile, disabled = true })
        elseif ProxyConfigs[candidate.appname]["global"] ~= nil then
          local addr = ProxyConfigs[candidate.appname]["global"]
          table.insert(proxyMenu, { title = "HTTP Proxy: " .. addr[1] .. ":" .. addr[2], disabled = true })
          table.insert(proxyMenu, { title = "SOCKS5 Proxy: " .. addr[5] .. ":" .. addr[6], disabled = true })
        end
      end

      for _, menuItem in ipairs(candidate.items) do
        menuItem.shortcut = tostring(proxyMenuIdx)
        local checked = (candidate.appname == enabledProxy)
            and mode and string.match(menuItem.title, mode) ~= nil
        menuItem.checked = checked
        table.insert(proxyMenu, updateProxyWrapper(menuItem, candidate.appname))
        proxyMenuIdx = proxyMenuIdx + 1
      end
    end
  end

  local otherProxies = {}
  for name, _ in pairs(ProxyConfigs) do
    if hs.fnutils.find(proxyMenuItemCandidates, function(item) return item.appname == name end) == nil then
      table.insert(otherProxies, name)
    end
  end
  for _, name in ipairs(otherProxies) do
    local config, loc
    if ProxyConfigs[name].condition == nil then
      config = ProxyConfigs[name]
    else
      local locations = ProxyConfigs[name].locations
      local _, status_ok = hs.execute(ProxyConfigs[name].condition.shell_command)
      loc = status_ok and locations[1] or locations[2]
      config = ProxyConfigs[name][loc]
    end
    if config ~= nil then
      table.insert(proxyMenu, { title = "-" })
      table.insert(proxyMenu, { title = name, disabled = true })
      if enabledProxy == name and mode ~= nil then
        if mode == "PAC" then
          local PACFile = config.PAC
          table.insert(proxyMenu, { title = "PAC File: " .. PACFile, disabled = true })
        else
          local addr = config.global
          table.insert(proxyMenu, { title = "HTTP Proxy: " .. addr[1] .. ":" .. addr[2], disabled = true })
          table.insert(proxyMenu, { title = "SOCKS5 Proxy: " .. addr[5] .. ":" .. addr[6], disabled = true })
        end
      end
      table.insert(proxyMenu, updateProxyWrapper({
        title = "    Global Mode",
        fn = function() enable_proxy_global(name, nil, loc) end,
        shortcut = tostring(proxyMenuIdx),
        checked = enabledProxy == name and mode ~= nil and mode == "Global"
      }, name))
      proxyMenuIdx = proxyMenuIdx + 1
      table.insert(proxyMenu, updateProxyWrapper({
        title = "    PAC Mode",
        fn = function() enable_proxy_PAC(name, nil, loc) end,
        shortcut = tostring(proxyMenuIdx),
        checked = enabledProxy == name and mode ~= nil and mode == "PAC"
      }, name))
    end
  end

  table.insert(proxyMenu, { title = "-" })
  table.insert(proxyMenu, {
    title = "Proxy Settings",
    fn = function()
      local osVersion = getOSVersion()
      if osVersion < OS.Ventura then
        local ok, position = hs.osascript.applescript([[
          tell application id "com.apple.systempreferences"
            activate
            set current pane to pane "com.apple.preference.network"
            repeat until anchor "Proxies" of current pane exists
              delay 0.1
            end repeat
            reveal anchor "Proxies" of current pane
          end tell

          delay 1
          tell application "System Events"
            tell ]] .. aWinFor("com.apple.systempreferences") .. [[
              set tb to table 1 of scroll area 1 of group 1 of tab group 1 of sheet 1
              repeat with r in every row of tb
                if value of checkbox 1 of r is 1 then
                  return position of text field 1 of r
                end if
              end repeat
              return false
            end tell
          end tell
        ]])
        if ok and type(position) == "table" then
          leftClickAndRestore(position)
        end
      else
        hs.osascript.applescript([[
          tell application id "com.apple.systempreferences"
            activate
            reveal pane id "com.apple.wifi-settings-extension"
            repeat until anchor "General_Details" of current pane exists
              delay 0.1
            end repeat
            reveal anchor "General_Details" of current pane
            tell application "System Events"
              set ntry to 0 -- resolve weird bug that the anchor cannot be activated
              repeat until sheet 1 of ]] .. aWinFor("com.apple.systempreferences") .. [[ exists
                if ntry = 50 then
                  return
                end if
                set ntry to ntry + 1
                delay 0.1
              end repeat
              key code 125
              key code 125
              key code 125
              key code 125
              key code 125
            end tell
          end tell
        ]])
      end
    end,
    shortcut = 'p'
  })

  proxy:setMenu(proxyMenu)
end

function registerProxyMenu(retry)
  getCurrentNetworkService()
  if not curNetworkService then
    proxy:setMenu({{
      title = "No Network Access",
      disabled = true
    }})
    if not retry then
      return false
    else
      hs.timer.waitUntil(
        function()
          getCurrentNetworkService()
          return curNetworkService ~= nil
        end,
        function() registerProxyMenu(false) end,
        3
      )
      return false
    end
  else
    registerProxyMenuImpl()
    return true
  end
end

networkInterfaceWatcher = hs.network.configuration.open()
local function registerProxyMenuWrapper(storeObj, changedKeys)
  local Ipv4State = networkInterfaceWatcher:contents("State:/Network/Global/IPv4")["State:/Network/Global/IPv4"]
  if Ipv4State ~= nil then
    local curNetID = Ipv4State["PrimaryService"]
    networkInterfaceWatcher:monitorKeys({"State:/Network/Global/IPv4", "Setup:/Network/Service/" .. curNetID .. "/Proxies"})
    registerProxyMenu(true)
  else
    hs.timer.waitUntil(
      function()
        local Ipv4State = networkInterfaceWatcher:contents("State:/Network/Global/IPv4")["State:/Network/Global/IPv4"]
        return Ipv4State ~= nil
      end,
      function()
        local Ipv4State = networkInterfaceWatcher:contents("State:/Network/Global/IPv4")["State:/Network/Global/IPv4"]
        local curNetID = Ipv4State["PrimaryService"]
        networkInterfaceWatcher:monitorKeys({"State:/Network/Global/IPv4", "Setup:/Network/Service/" .. curNetID .. "/Proxies"})
        registerProxyMenu(true)
      end
    )
  end
  networkInterfaceWatcher:stop()
  hs.timer.doAfter(3, function()
    registerProxyMenu()
    networkInterfaceWatcher:start()
  end)
end

registerProxyMenuWrapper()
networkInterfaceWatcher:setCallback(registerProxyMenuWrapper)
networkInterfaceWatcher:start()

local menubarHK = keybindingConfigs.hotkeys.global

local proxyHotkey = bindSpecSuspend(menubarHK["showProxyMenu"], "Show Proxy Menu",
function()
  if findApplication("com.surteesstudios.Bartender") ~= nil then
    hs.osascript.applescript([[
      tell application id "com.surteesstudios.Bartender"
        activate "org.hammerspoon.Hammerspoon-Item-2"
      end tell
    ]])
  else
    hs.osascript.applescript([[
      ignoring application responses
        tell application "System Events"
          click menu bar item "PROXY" of menu bar 2 of application process "Hammerspoon"
        end tell
      end ignoring

      delay 0.2
      do shell script "killall System\\ Events"
    ]])
  end
end)
proxyHotkey.kind = HK.MENUBAR
proxyHotkey.icon = hs.image.imageFromAppBundle("com.apple.systempreferences")

-- toggle system proxy
local function toggleSystemProxy(networkservice)
  networkservice = networkservice or curNetworkService
  autodiscovery = hs.execute("networksetup -getproxyautodiscovery " .. networkservice)
  autoproxyurl = hs.execute("networksetup -getautoproxyurl " .. networkservice)
  webproxy = hs.execute("networksetup -getwebproxy " .. networkservice)
  securewebproxy = hs.execute("networksetup -getsecurewebproxy " .. networkservice)
  socksproxy = hs.execute("networksetup -getsocksfirewallproxy " .. networkservice)

  if string.match(autodiscovery, "On")
    or string.match(webproxy, "Yes")
    or string.match(securewebproxy, "Yes")
    or string.match(socksproxy, "Yes") then
    disable_proxy(networkservice)
    hs.alert("System proxy disabled")
  elseif string.match(autoproxyurl, "Yes") then
    enable_proxy_global(nil, networkservice)
    hs.alert("System proxy enabled (global mode)")
  else
    enable_proxy_PAC(nil, networkservice)
    hs.alert("System proxy enabled (auto mode)")
    end
end

local function newControlCenter(...)
  local hotkey = newSuspend(...)
  if hotkey == nil then return nil end
  hotkey.kind = HK.MENUBAR
  hotkey.subkind = HK.MENUBAR_.CONTROL_CENTER
  return hotkey
end

local function bindControlCenter(...)
  local hotkey = bindSpecSuspend(...)
  if hotkey == nil then return nil end
  hotkey.kind = HK.MENUBAR
  hotkey.subkind = HK.MENUBAR_.CONTROL_CENTER
  return hotkey
end

-- toggle show `Widgets` panel
local clockHotkey = bindControlCenter(menubarHK["showClock"], "Show " .. controlCenterLocalized("Clock"),
    function() hs.eventtap.keyStroke("fn", "N") end)

-- toggle show `Control Center`
local controlCenterHotkey = bindControlCenter(menubarHK["showControlCenter"], "Show " .. controlCenterLocalized("Control Center"),
    function() clickRightMenuBarItem("Control Center") end)

local controlCenterIdentifiers = hs.json.read("static/controlcenter-identifies.json")
local controlCenterSubPanelIdentifiers = controlCenterIdentifiers.subpanel
local controlCenterMenuBarItemIdentifiers = controlCenterIdentifiers.menubar
local controlCenterAccessibiliyIdentifiers = controlCenterIdentifiers.accessibility

controlCenterHotKeys = nil
controlCenterSubPanelWatcher = nil

local function checkAndRegisterControlCenterHotKeys(hotkey)
  if controlCenterHotKeys == nil then
    hotkey:delete()
    return false
  else
    hotkey:enable()
    table.insert(controlCenterHotKeys, hotkey)
    return true
  end
end

local function popupControlCenterSubPanel(panel, allowReentry)
  local ident = controlCenterSubPanelIdentifiers[panel]
  local winObj = findApplication("com.apple.controlcenter"):mainWindow()
  local osVersion = getOSVersion()
  local pane = osVersion < OS.Ventura and "window 1" or "group 1 of window 1"

  local function mayLocalize(value)
    return controlCenterLocalized("Now Playing", value)
  end

  local enter = nil
  local enterTemplate = [[
    set panelFound to false
    set totalDelay to 0.0
    repeat until totalDelay > 0.9
      repeat with ele in (every %s of pane)
        if (exists attribute "AXIdentifier" of ele) ¬
            and (the value of attribute "AXIdentifier" of ele contains "%s") then
          set panelFound to true
          perform action %d of ele
          exit repeat
        end if
      end repeat
      if panelFound then
        exit repeat
      else
        delay 0.1
        set totalDelay to totalDelay + 0.1
      end if
    end repeat
  ]]
  if hs.fnutils.contains({"WiFi", "Focus", "Bluetooth", "AirDrop"}, panel) then
    enter = string.format(enterTemplate, "checkbox", ident, 2)
  elseif panel == "Screen Mirroring" then
    if osVersion < OS.Ventura then
      enter = string.format(enterTemplate, "checkbox", ident, 2)
    else
      enter = string.format(enterTemplate, "button", ident, 1)
    end
  elseif panel == "Display" then
    enter = string.format(enterTemplate, osVersion < OS.Ventura and "static text" or "group", ident, 1)
  elseif panel == "Sound" then
    enter = string.format(enterTemplate, "static text", ident, 1)
  elseif panel == "Keyboard Brightness" then
    enter = string.format(enterTemplate, "button", ident, 1)
  elseif panel == "Now Playing" then
    enter = [[
      set panelFound to true
      perform action 1 of last image of pane
    ]]
  end

  local ok, result
  if winObj == nil then
    local _ok, menuBarItemIndex = hs.osascript.applescript(string.format([[
      tell application "System Events"
        set controlitems to menu bar 1 of application process "ControlCenter"
        repeat with i from 1 to (count of menu bar items of controlitems)
          if value of attribute "AXIdentifier" of menu bar item i of controlitems contains "%s" then
            return i
          end if
        end repeat
        return 0
      end tell
    ]], controlCenterMenuBarItemIdentifiers[panel]))
    if _ok and menuBarItemIndex ~= 0 then
      if findApplication("com.surteesstudios.Bartender") ~= nil then
        ok, result = hs.osascript.applescript(string.format([[
          tell application id "com.surteesstudios.Bartender"
            activate "com.apple.controlcenter-%s"
          end tell
        ]], string.gsub(panel, " ", "")))
      else
        ok, result = hs.osascript.applescript(string.format([[
          tell application "System Events"
            click menu bar item %d of menu bar 1 ¬
              of application process "ControlCenter"
          end tell
        ]], menuBarItemIndex))
      end
    else
      local delayCmd = menuBarVisible() and "" or "delay 0.3"
      ok, result = hs.osascript.applescript([[
        tell application "System Events"
          set controlitems to menu bar 1 of application process "ControlCenter"
          set controlcenter to (first menu bar item whose ¬
              value of attribute "AXIdentifier" contains "controlcenter") of controlitems
          perform action 1 of controlcenter

          ]] .. delayCmd .. [[

          set pane to ]] .. pane .. [[ of application process "ControlCenter"
          ]] .. enter .. [[
          if panelFound then
            return 1
          else
            return 0
          end if
        end tell
      ]])
    end
  else
    local already = nil
    local alreadyTemplate = [[
      repeat with ele in (every %s of pane)
        if (exists attribute "AXIdentifier" of ele) ¬
            and (the value of attribute "AXIdentifier" of ele contains "%s") then
          set already to true
          exit repeat
        end if
      end repeat
    ]]
    if hs.fnutils.contains({"WiFi", "Focus", "Bluetooth", "AirDrop", "Keyboard Brightness", "Screen Mirroring"}, panel) then
      already = string.format(alreadyTemplate, "static text", ident)
    elseif panel == "Display" then
      already = [[
        if exists scroll area 1 of pane then
        ]] .. string.format(alreadyTemplate, "slider of scroll area 1", ident) .. [[
        end if
      ]]
    elseif panel == "Sound" then
      already = string.format(alreadyTemplate, "slider", ident)
    elseif panel == "Now Playing" then
      if osVersion < OS.Ventura then
        already = [[
          if (exists button "]] .. mayLocalize("rewind") .. [[" of pane) or  ¬
              (exists button "]] .. mayLocalize("previous") .. [[" of pane) or ¬
              (number of (buttons of pane whose title is "]] .. mayLocalize("play") .. [[" or ¬
                  title is "]] .. mayLocalize("pause") .. [[") > 1)
            set already to true
          end if
        ]]
      else
        already = [[
          set already to ((exists image of pane) and ¬
              (number of buttons of pane > 2))
        ]]
      end
    end

    if allowReentry == nil then
      allowReentry = "false"
    else
      allowReentry = tostring(allowReentry)
    end
    ok, result = hs.osascript.applescript([[
      tell application "System Events"
        set pane to ]] .. pane .. [[ of application process "ControlCenter"
        set wifi to false
        set bluetooth to false
        repeat with ele in (every checkbox of pane)
          if (exists attribute "AXIdentifier" of ele) then
            if (the value of attribute "AXIdentifier" of ele contains ¬
                "]] .. controlCenterSubPanelIdentifiers["WiFi"] .. [[") then
              set wifi to true
            else if (the value of attribute "AXIdentifier" of ele contains ¬
                "]] .. controlCenterSubPanelIdentifiers["Bluetooth"] .. [[") then
              set bluetooth to true
            end if
          end if
        end repeat
        if wifi and bluetooth then
          ]] .. enter .. [[
          return 1
        else
          set already to false
          ]] .. already .. [[
          if already and not ]] .. allowReentry .. [[ then
            return 0
          else
            set controlitems to menu bar 1 of application process "ControlCenter"
            set controlcenter to (first menu bar item whose ¬
                value of attribute "AXIdentifier" contains "controlcenter") of controlitems
            perform action 1 of controlcenter

            delay 0.5
            set pane to ]] .. pane .. [[ of application process "ControlCenter"
            ]] .. enter .. [[
            if panelFound then
              return -1
            else
              return 0
            end if
          end if
        end if
      end tell
    ]])
  end

  if ok and result ~= 0 then
    registerControlCenterHotKeys(panel)
  end
end

function registerControlCenterHotKeys(panel)
  local osVersion = getOSVersion()
  local pane = osVersion < OS.Ventura and "window 1" or "group 1 of window 1"

  local function mayLocalize(value)
    return controlCenterLocalized(panel, value)
  end

  if controlCenterHotKeys ~= nil then
    for _, hotkey in ipairs(controlCenterHotKeys) do
      hotkey:delete()
    end
  end
  controlCenterHotKeys = {}

  controlCenterSubPanelWatcher = hs.window.filter.new(findApplication("com.apple.controlcenter"):name())
    :subscribe(hs.window.filter.windowDestroyed, function()
      if selectNetworkWatcher ~= nil then
        selectNetworkWatcher:stop()
        selectNetworkWatcher = nil
      end
      if controlCenterHotKeys ~= nil then
        for _, hotkey in ipairs(controlCenterHotKeys) do
          hotkey:delete()
        end
        controlCenterHotKeys = nil
      end
      hotkeyMainBack = nil
      hotkeyMainForward = nil
      hotkeyShow = nil
      hotkeyHide = nil
      if controlCenterSubPanelWatcher ~= nil then
        controlCenterSubPanelWatcher:unsubscribeAll()
        controlCenterSubPanelWatcher = nil
      end
    end)
  
  -- back to main panel
  hotkeyMainBack = newControlCenter("⌘", "[", "Back",
    function()
      hotkeyMainBack:disable()
      for _, hotkey in ipairs(controlCenterHotKeys) do
        hotkey:delete()
      end
      controlCenterHotKeys = {}
      if controlCenterSubPanelWatcher ~= nil then
        controlCenterSubPanelWatcher:unsubscribeAll()
        controlCenterSubPanelWatcher = nil
      end

      clickRightMenuBarItem("Control Center")
      hotkeyMainForward = newControlCenter("⌘", "]", "Forward",
        function()
          hotkeyMainForward:disable()
          popupControlCenterSubPanel(panel)
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkeyMainForward) then return end
    end)
  if not checkAndRegisterControlCenterHotKeys(hotkeyMainBack) then return end

  -- jump to related panel in `System Preferences`
  if hs.fnutils.contains({"WiFi", "Bluetooth", "Focus", "Keyboard Brightness", "Screen Mirroring", "Display", "Sound"}, panel) then
    if osVersion < OS.Ventura then
      local ok, result = hs.osascript.applescript([[
        tell application "System Events"
          repeat until button 1 of ]] .. pane .. [[ of application process ¬
            "ControlCenter" whose title contains "…" exists
            delay 0.1
          end repeat
          set bt to every button of ]] .. pane .. [[ of application process ¬
            "ControlCenter" whose title contains "…"
          if (count bt) is not 0 then
            return title of last item of bt
          else
            return false
          end if
        end tell
      ]])
      if ok and result ~= false then
        local hotkey = newControlCenter("⌘", ",", result,
          function()
            hs.osascript.applescript([[
              tell application "System Events"
                set bt to last button of ]] .. pane .. [[ of application process ¬
                  "ControlCenter" whose title contains "…"
                perform action 1 of bt
              end tell
            ]])
          end)
        if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
      end
    else
      local hotkey = newControlCenter("⌘", ",", "Settings",
        function()
          hs.osascript.applescript([[
            tell application "System Events"
              set bt to last button of ]] .. pane .. [[ of application process "ControlCenter"
              perform action 1 of bt
            end tell
          ]])
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
    end
  end

  -- pandel with a switch-off button
  if hs.fnutils.contains({"WiFi", "Bluetooth", "AirDrop"}, panel) then
    local hotkey = newControlCenter("", "Space", "Toggle " .. panel,
      function()
        hs.osascript.applescript([[
          tell application "System Events"
            repeat with cb in checkboxes of window 1 of application process "ControlCenter"
              if (attribute "AXIdentifier" of cb exists) ¬
                  and (value of attribute "AXIdentifier" of cb contains "-header") then
                perform action 1 of cb
              end if
            end repeat
          end tell
        ]])
      end)
    if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
  end

  -- panel with a slider
  if hs.fnutils.contains({"Display", "Sound", "Keyboard Brightness"}, panel) then
    local specs = nil
    if panel == "Sound" then
      specs = {["="] = {"Volume Up", "increment slid\n"},
               ["-"] = {"Volume Down", "decrement slid\n"},
               ["["] = {"Volume Min", "set value of slid to 0\n"},
               ["]"] = {"Volume Max", "set value of slid to 100\n"}}
    else
      specs = {["="] = {"Brightness Up", "increment slid\n"},
               ["-"] = {"Brightness Down", "decrement slid\n"},
               ["["] = {"Brightness Min", "set value of slid to 0\n"},
               ["]"] = {"Brightness Max", "set value of slid to 100\n"}}
    end
  
    local pos = nil
    if panel == "Display" then
      if osVersion < OS.Ventura then
        pos = "scroll area 1 of"
      else
        pos = "group 1 of"
      end
    else
      pos = ""
    end

    for key, spec in pairs(specs) do
      local hotkey = newControlCenter("", key, spec[1],
        function()
          hs.osascript.applescript([[
            tell application "System Events"
              set enabledSliders to sliders of ]] .. pos .. " " .. pane .. [[ of application process "ControlCenter" ¬
                  whose value of attribute "AXEnabled" is true
              if (count enabledSliders) is 1 then
                set slid to item 1 of enabledSliders
                ]] .. spec[2] .. [[
              end if
            end tell
          ]])
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
    end
  end

  -- panel with a list of devices
  if hs.fnutils.contains({"Bluetooth", "Sound", "Screen Mirroring"}, panel) then
    local cbField
    if osVersion < OS.Ventura then
      cbField = "title"
    else
      cbField = "the value of attribute \"AXIdentifier\""
    end
    local ok, devices = hs.osascript.applescript([[
      tell application "System Events"
        set totalDelay to 0.0
        repeat until checkbox 1 of scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter" exists
          delay 0.1
          set totalDelay to totalDelay + 0.1
          if totalDelay > 0.5 then
            return 0
          end if
        end repeat
        set sa to scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter"
        return {]] .. cbField.. [[, value} of checkboxes of sa
      end tell
    ]])
    if ok and type(devices) == 'table' then
      for i=1, math.min(#devices[1], 10) do
        local name, enabled = devices[1][i], devices[2][i]
        if cbField ~= "title" then
          local _, nameIdx = string.find(name, "device-", 1, true)
          name = string.sub(name, nameIdx + 1, -1)
        end
        local msg = "Connect to " .. name
        if enabled == nil or enabled == 1 then
          local newName = string.match(name, "(.-), %d+%%$")
          if newName ~= nil then name = newName end
          msg = "Disconnect to " .. name
        end
        local hotkey = newControlCenter("", tostring(i%10), msg,
          function()
            hs.osascript.applescript([[
              tell application "System Events"
                set sa to scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter"
                set cb to checkbox ]] .. tostring(i) .. [[ of sa
                perform action 1 of cb
              end tell
            ]])
          end)
        if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
      end
    end
  end

  if panel == "WiFi" then
    local ok, result = hs.osascript.applescript([[
      tell application "System Events"
        set cnt to 0
        repeat until cnt >= 10
          if exists scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter" then
            set sa to scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter"
            set uiitems to the value of attribute "AXChildren" of sa
            repeat with ele in (UI elements of sa)
              if value of attribute "AXRole" of ele is "AXDisclosureTriangle" then
                return value of ele
              end if
            end repeat
          end if
          set cnt to cnt + 1
        end repeat
        return -1
      end tell
    ]])
    if ok and result ~= -1 then
      local actionFunc = function()
        hs.osascript.applescript([[
          tell application "System Events"
            set sa to scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter"
            repeat with ele in (UI elements of sa)
              if value of attribute "AXRole" of ele is "AXDisclosureTriangle" then
                perform action 1 of ele
                exit repeat
              end if
            end repeat
          end tell
        ]])
      end
      if result == 0 then
        hotkeyShow = newControlCenter("", "Right", "Show Other Networks",
          function()
            hotkeyShow:disable()
            actionFunc()
            if hotkeyHide == nil then
              hotkeyHide = newControlCenter("", "Left", "Hide Other Networks",
                function()
                  hotkeyHide:disable()
                  hotkeyShow:enable()
                  actionFunc()
                end)
              if not checkAndRegisterControlCenterHotKeys(hotkeyHide) then return end
            else
              hotkeyHide:enable()
            end
          end)
        if not checkAndRegisterControlCenterHotKeys(hotkeyShow) then return end
      else
        hotkeyHide = newControlCenter("", "Left", "Hide Other Networks",
          function()
            hotkeyHide:disable()
            actionFunc()
            if hotkeyShow == nil then
              hotkeyShow = newControlCenter("", "Right", "Show Other Networks",
                function()
                  hotkeyShow:disable()
                  hotkeyHide:enable()
                  actionFunc()
                end)
              if not checkAndRegisterControlCenterHotKeys(hotkeyShow) then return end
            else
              hotkeyShow:enable()
            end
          end)
        if not checkAndRegisterControlCenterHotKeys(hotkeyHide) then return end
      end
    end

    -- select network
    selectNetworkHotkeys = {}
    availableNetworksString = ""
    local selectNetworkActionFunc = function()
      local cbField
      if osVersion < OS.Ventura then
        cbField = "title"
      else
        cbField = "the value of attribute \"AXIdentifier\""
      end
      local ok, result = hs.osascript.applescript([[
        tell application "System Events"
          set sa to scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter"
          return ]] .. cbField .. [[ of (every checkbox of sa)
        end tell
      ]])
      if ok then
        local availableNetworks = {}
        for idx, titleFull in ipairs(result) do
          if idx > 10 then break end
          local title
          if osVersion < OS.Ventura then
            title = string.match(titleFull, "([^,]+)")
          else
            title = string.sub(titleFull, string.len("wifi-network-") + 1, -1)
          end
          table.insert(availableNetworks, title)
        end
        local newAvailableNetworksString = table.concat(availableNetworks, "|")
        if newAvailableNetworksString ~= availableNetworksString then
          availableNetworksString = newAvailableNetworksString
          for _, hotkey in ipairs(selectNetworkHotkeys) do
            hotkey:disable()
          end
          selectNetworkHotkeys = {}
          for idx, title in ipairs(availableNetworks) do
            local ok, selected = hs.osascript.applescript([[
              tell application "System Events"
                set sa to scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter"
                set ret to value of checkbox ]] .. tostring(idx) .. [[ of sa
              end tell
            ]])
            local msg = "Connect to " .. title
            if ok and (selected == nil or selected == 1) then
              msg = "Disconnect to " .. title
            end
            local hotkey = newControlCenter("", tostring(idx % 10), msg,
              function()
                hs.osascript.applescript([[
                  tell application "System Events"
                    set sa to scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter"
                    set cb to checkbox ]] .. tostring(idx) .. [[ of sa
                    perform action 1 of cb
                  end tell
                ]])
              end)
            if checkAndRegisterControlCenterHotKeys(hotkey) then
              table.insert(selectNetworkHotkeys, hotkey)
            else return end
          end
        end
      end
    end
    selectNetworkActionFunc()
    selectNetworkWatcher = hs.timer.new(1, selectNetworkActionFunc):start()
  elseif panel == "AirDrop" then
    local ok, toggleNames
    if osVersion < OS.Ventura then
      ok, toggleNames = hs.osascript.applescript([[
        tell application "System Events"
          repeat until checkbox 3 of ]] .. pane .. [[ of application process "ControlCenter" exists
            delay 0.1
          end repeat
          return {title of checkbox 2 of ]] .. pane .. [[ of application process "ControlCenter", ¬
                  title of checkbox 3 of ]] .. pane .. [[ of application process "ControlCenter"}
        end tell
      ]])
    else
      ok, toggleIdents = hs.osascript.applescript([[
        tell application "System Events"
          repeat until checkbox 3 of ]] .. pane .. [[ of application process "ControlCenter" exists
            delay 0.1
          end repeat
          set pane to ]] .. pane .. [[ of application process "ControlCenter"
          return {value of attribute "AXIdentifier" of checkbox 2 of pane, ¬
                  value of attribute "AXIdentifier" of checkbox 3 of pane}
        end tell
      ]])
      if ok then
        toggleNames = {}
        hs.fnutils.each(toggleIdents, function(ele)
          for k, v in pairs(controlCenterAccessibiliyIdentifiers["AirDrop"]) do
            if v == ele then table.insert(toggleNames, mayLocalize(k)) end
          end
        end)
      end
    end
    if ok then
      for i=1,2 do
        local hotkey = newControlCenter("", tostring(i), toggleNames[i],
          function()
            hs.osascript.applescript([[
              tell application "System Events"
                set cb to checkbox ]] .. tostring(i+1) .. [[ of ]] .. pane .. [[ of application process "ControlCenter"
                perform action 1 of cb
              end tell
            ]])
          end)
        if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
      end
    end
  elseif panel == "Focus" then
    local ok, toggleNames
    if osVersion < OS.Ventura then
      ok, toggleNames = hs.osascript.applescript([[
        tell application "System Events"
          repeat until checkbox 2 of ]] .. pane .. [[ of application process "ControlCenter" exists
            delay 0.1
          end repeat
          return {title of checkbox 1 of ]] .. pane .. [[ of application process "ControlCenter", ¬
                  title of checkbox 2 of ]] .. pane .. [[ of application process "ControlCenter"}
        end tell
      ]])
    else
      ok, toggleIdents = hs.osascript.applescript([[
        tell application "System Events"
          repeat until checkbox 2 of ]] .. pane .. [[ of application process "ControlCenter" exists
            delay 0.1
          end repeat
          set pane to ]] .. pane .. [[ of application process "ControlCenter"
          return {value of attribute "AXIdentifier" of checkbox 1 of pane, ¬
                  value of attribute "AXIdentifier" of checkbox 2 of pane}
        end tell
      ]])
      if ok then
        toggleNames = {}
        hs.fnutils.each(toggleIdents, function(ele)
          for k, v in pairs(controlCenterAccessibiliyIdentifiers["Focus"]) do
            if v == ele then table.insert(toggleNames, controlCenterLocalized("accessibility", k)) end
          end
        end)
      end
    end
    if ok then
      for i=1,2 do
        local hotkey = newControlCenter("", tostring(i), "Toggle " .. toggleNames[i],
          function()
            hs.osascript.applescript([[
              tell application "System Events"
                set cb to checkbox ]] .. tostring(i) .. [[ of ]] .. pane .. [[ of application process "ControlCenter"
                perform action 1 of cb
              end tell
            ]])
          end)
        if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
      end
    end
    for i=1,2 do
      local hotkey = newControlCenter("⌘", tostring(i), toggleNames[1] .. " " .. i,
        function()
          hs.osascript.applescript([[
            tell application "System Events"
              set bt to button ]] .. tostring(i) .. [[ of ]] .. pane .. [[ of application process "ControlCenter"
              perform action 1 of bt
            end tell
          ]])
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
    end
  elseif panel == "Display" then
    local ok, idx = hs.osascript.applescript([[
      tell application "System Events"
        set totalDelay to 0.0
        repeat until scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter" exists
          set totalDelay to totalDelay + 0.1
          if totalDelay > 0.2 then
            return false
          end
        end
        set sa to scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter"
        repeat with i from 1 to count (UI elements of sa)
          set ele to ui element i of sa
          if value of attribute "AXRole" of ele is "AXDisclosureTriangle" then
            return i
          end if
        end repeat
      end tell
    ]])
    if ok and idx ~= false then
      local hotkey = newControlCenter("", "Space", "Toggle Showing Display Presets",
        function()
          hs.osascript.applescript([[
            tell application "System Events"
              set sa to scroll area 1 of ]] .. pane .. [[ of application process "ControlCenter"
              perform action 1 of ui element ]] .. tostring(idx) .. [[ of sa
            end tell
          ]])
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
    end

    local area = osVersion < OS.Ventura and "scroll area 1 of window 1" or "group 1 of window 1"
    local ok, result = hs.osascript.applescript([[
      tell application "System Events"
        repeat until checkbox 3 of ]] .. area.. [[ of application process "ControlCenter" exists
          delay 0.1
        end repeat
        set sa to ]] .. area.. [[ of application process "ControlCenter"
        return {value of attribute "AXIdentifier" of checkbox of sa, value of checkbox of sa}
      end tell
    ]])
    cbIdents = result[1]
    enableds = result[2]
    for i=1,3 do
      local cbIdent = cbIdents[i]
      local checkbox = hs.fnutils.find({"Dark Mode", "Night Shift", "True Tone"},
        function(ele)
          return cbIdent == controlCenterAccessibiliyIdentifiers["Display"][ele]
        end)
      local op = enableds[i] == 0 and "Enable" or "Disable"
      local hotkey = newControlCenter("", tostring(i), op .. " " .. mayLocalize(checkbox),
        function()
          hs.osascript.applescript([[
            tell application "System Events"
              set sa to ]] .. area.. [[ of application process "ControlCenter"
              set cb to (first checkbox of sa whose value of ¬
                  attribute "AXIdentifier" is "]] .. cbIdent ..[[")
              click cb
            end tell
          ]])
          enableds[i] = 1 - enableds[i]

          if checkbox == "Dark Mode" then
            local bundleID = hs.application.frontmostApplication():bundleID()
            if hs.fnutils.contains({"com.google.Chrome", "com.microsoft.edgemac", "com.microsoft.edgemac.Dev"}, bundleID) then
              local scheme = bundleID == "com.google.Chrome" and "chrome" or "edge"
              local darkMode = enableds[i] == 1 and "Enabled" or "Disabled"
              local getOptionParentCmd = nil
              if bundleID == "com.google.Chrome" then
                getOptionParentCmd = [[
                  set win to ]] .. aWinFor(bundleID) .. [[
                  set g to group 1 of group 4 of group 1 of group 2 of UI element "Experiments" of group 1 of group 1 of group 1 of group 1 of win
                ]]
              else
                local experiments = localizedString("Experiments", bundleID)
                getOptionParentCmd = [[
                  set win to ]] .. aWinFor(bundleID) .. [[
                  set g to group 1 of group 3 of group 1 of group 2 of group 1 of UI element "]] .. experiments .. [[" of group 1 of group 1 of group 1 of group 1 of win
                ]]
              end
              local aWin = activatedWindowIndex()
              hs.osascript.applescript([[
                tell application id "]] .. bundleID .. [["
                  set tabCount to count of tabs of window ]] .. aWin .. [[

                  set tabFound to false
                  repeat with i from 1 to tabCount
                    set tabURL to URL of tab i of window ]] .. aWin .. [[

                    if tabURL contains "]] .. scheme .. [[://flags/#enable-force-dark" then
                      set tabFound to true
                      exit repeat
                    end if
                  end repeat
                  if tabFound is false then
                    tell window ]] .. aWin .. [[

                      set newTab to make new tab at the end of tabs ¬
                          with properties {URL:"]] .. scheme .. [[://flags/#enable-force-dark"}
                      delay 0.5
                    end tell
                  else
                    tell window ]] .. aWin .. [[

                      set active tab index to i
                    end tell
                  end if
                end tell

                tell application "System Events"
                  ]] .. getOptionParentCmd .. [[
                  set options to the value of attribute "AXChildren" of g
                  repeat with opt in options
                    set optTitle to UI element 1 of opt
                    if title of optTitle contains "Auto Dark Mode" then
                      set bt to pop up button 1 of group 2 of opt
                      perform action 1 of bt
                      exit repeat
                    end if
                  end repeat

                  set g to group 1 of group 1 of group 1 of group 1 of win
                  perform action 2 of menu item "]] .. darkMode .. [[" of menu 1 of g
                end tell
              ]])
            end
          end
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
    end
    for i=4,#result[1] do
      if i - 3 > 10 then break end
      local _, nameIdx = string.find(result[1][i], "device-", 1, true)
      local device = string.sub(result[1][i], nameIdx + 1, -1)
      local msg
      if result[2][i] == 0 then
        msg = "Connect to " .. device
      else
        msg = "Disconnect to " .. device
      end
      local hotkey = newControlCenter("⌘", tostring((i-3)%10), msg,
        function()
          hs.osascript.applescript([[
            tell application "System Events"
              set sa to ]] .. area.. [[ of application process "ControlCenter"
              set cb to checkbox ]] .. tostring(i) .. [[ of sa
              perform action 1 of cb
            end tell
          ]])
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
    end
  elseif panel == "Now Playing" then
    local ok, result
    if osVersion < OS.Ventura then
      ok, result = hs.osascript.applescript([[
        tell application "System Events"
          repeat until button 3 of ]] .. pane .. [[ of application process "ControlCenter" exists
            delay 0.1
          end repeat
          return title of (every button of ]] .. pane .. [[ of application process "ControlCenter")
        end tell
      ]])
    else
      ok, result = hs.osascript.applescript([[
        tell application "System Events"
          repeat until button 3 of ]] .. pane .. [[ of application process "ControlCenter" exists
            delay 0.1
          end repeat
          return number of buttons of ]] .. pane .. [[ of application process "ControlCenter"
        end tell
      ]])
    end
    if ok and ((type(result) == "number" and result == 3) or (type(result) == "table" and #result == 3)) then
      if type(result) == "number" then
        result = {
          mayLocalize("previous"),
          mayLocalize("play") .. "/" .. mayLocalize("pause"),
          mayLocalize("next")
        }
      end
      local hotkey
      hotkey = newControlCenter("", "Space", result[2],
        function()
          hs.osascript.applescript([[
            tell application "System Events"
              set bt to button 2 of ]] .. pane .. [[ of application process "ControlCenter"
              perform action 1 of bt
            end tell
          ]])
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
      hotkey = newControlCenter("", "Left", result[1],
        function()
          hs.osascript.applescript([[
            tell application "System Events"
              set bt to button 1 of ]] .. pane .. [[ of application process "ControlCenter"
              perform action 1 of bt
            end tell
          ]])
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
      hotkey = newControlCenter("", "Right", result[3],
        function()
          hs.osascript.applescript([[
            tell application "System Events"
              set bt to button 3 of ]] .. pane .. [[ of application process "ControlCenter"
              perform action 1 of bt
            end tell
          ]])
        end)
      if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
    elseif ok and ((type(result) == "number" and result > 3) or (type(result) == "table" and #result > 3)) then
      local nEntries
      if type(result) == "number" then
        nEntries = result / 2
      else
        nEntries = #result / 2
      end
      local hotkey
      for i = 1, nEntries do
        local buttonLabel = mayLocalize("play") .. "/" .. mayLocalize("pause")
        hotkey = newControlCenter("", tostring(i), type(result) == "number" and buttonLabel or result[2 * i - 1],
          function()
            hs.osascript.applescript([[
              tell application "System Events"
                set bt to button ]] .. tostring(2 * i - 1) .. [[ of ]] .. pane .. [[ of application process "ControlCenter"
                perform action 1 of bt
              end tell
            ]])
          end)
        if not checkAndRegisterControlCenterHotKeys(hotkey) then return end
      end
    end
  end
end

local controlCenterPanelConfigs = keybindingConfigs.hotkeys.ControlCenterAppKeys
for panel, spec in pairs(controlCenterPanelConfigs) do
  local localizedPanel = controlCenterLocalized(panel)
  bindControlCenter(spec, "Show " .. localizedPanel .. " Panel",
      hs.fnutils.partial(popupControlCenterSubPanel, panel))
end

local function getActiveControlCenterPanel()
  local osVersion = getOSVersion()
  local pane = osVersion < OS.Ventura and "window 1" or "group 1 of window 1"

  local function mayLocalize(value)
    return controlCenterLocalized("Now Playing", value)
  end

  local alreadyTemplate = [[
    repeat with ele in (every %s of pane)
      if (exists attribute "AXIdentifier" of ele) ¬
          and (the value of attribute "AXIdentifier" of ele contains "%s") then
        return "%s"
      end if
    end repeat
  ]]
  local script = [[
    tell application "System Events"
      set pane to ]] .. pane .. [[ of application process "ControlCenter"
  ]]
  for panel, ident in pairs(controlCenterSubPanelIdentifiers) do
    local already = nil
    if hs.fnutils.contains({"WiFi", "Focus", "Bluetooth", "AirDrop", "Keyboard Brightness", "Screen Mirroring"}, panel) then
      already = string.format(alreadyTemplate, "static text", ident, panel)
    elseif panel == "Display" then
      already = [[
        if exists scroll area 1 of pane then
        ]] .. string.format(alreadyTemplate, "slider of scroll area 1", ident, panel) .. [[
        end if
      ]]
    elseif panel == "Sound" then
      already = string.format(alreadyTemplate, "slider", ident, panel)
    end
    if already then
      script = script .. [[
        ]] .. already .. [[
      ]]
    end
  end
  if osVersion < OS.Ventura then
    already = [[
      if (exists button "]] .. mayLocalize("rewind") .. [[" of pane) or  ¬
          (exists button "]] .. mayLocalize("previous") .. [[" of pane) or ¬
          (number of (buttons of pane whose title is "]] .. mayLocalize("play") .. [[" or ¬
              title is "]] .. mayLocalize("pause") .. [[") > 1) then
        return "Now Playing"
      end if
    ]]
  else
    already = [[
      if ((exists image of pane) and ¬
          (number of buttons of pane > 2)) then
        return "Now Playing"
      end if
    ]]
  end
  script = script .. [[
    ]] .. already .. [[
  ]]

  script = script .. [[
    end tell
  ]]
  local ok, panel = hs.osascript.applescript(script)
  return panel
end

if hs.window.focusedWindow() ~= nil
    and hs.window.focusedWindow():application():bundleID() == "com.apple.controlcenter"
    and hs.window.focusedWindow():subrole() == "AXSystemDialog" then
  registerControlCenterHotKeys(getActiveControlCenterPanel())
end

controlCenterPanelHotKeys = {}
controlCenterWatcher = hs.window.filter.new(findApplication("com.apple.controlcenter"):name())
controlCenterWatcher:subscribe(hs.window.filter.windowCreated,
function()
  for panel, spec in pairs(controlCenterPanelConfigs) do
    local localizedPanel = controlCenterLocalized(panel)
    local hotkey = bindControlCenter({ mods = "", key = spec.key },
        "Show " .. localizedPanel .. " Panel",
        hs.fnutils.partial(popupControlCenterSubPanel, panel))
    table.insert(controlCenterPanelHotKeys, hotkey)
    timeTapperForExtraInfo = os.time()
    tapperForExtraInfo = hs.eventtap.new({hs.eventtap.event.types.flagsChanged},
      function(event)
        if event:getFlags():containExactly({"alt"}) and os.time() - timeTapperForExtraInfo > 2 then
          timeTapperForExtraInfo = os.time()
          local panel = getActiveControlCenterPanel()
          if panel == "WiFi" or panel == "Bluetooth" then
            popupControlCenterSubPanel(panel, true)
          end
        end
        return false
      end):start()
  end
end)
controlCenterWatcher:subscribe(hs.window.filter.windowDestroyed,
function()
  tapperForExtraInfo:stop()
  tapperForExtraInfo = nil
  for _, hotkey in ipairs(controlCenterPanelHotKeys) do
    hotkey:delete()
  end
  controlCenterPanelHotKeys = {}
  hotkeyMainBack = nil
  hotkeyMainForward = nil
  hotkeyShow = nil
  hotkeyHide = nil
end)

-- # callbacks

-- application event callbacks
function system_applicationCallback(appName, eventType, appObject)
  if eventType == hs.application.watcher.deactivated then
    if appName == nil and curNetworkService ~= nil then
      local enabledProxy = parseProxyInfo(proxy_info(), false)
      for _, proxyApp in ipairs(proxyMenuItemCandidates) do
        if enabledProxy == proxyApp.appname then
          local appname = enabledProxy == "MonoCloud" and "MonoProxyMac" or enabledProxy
          if findApplication(appname) == nil then
            disable_proxy()
          end
          break
        end
      end
    end
  end
end

-- application installation/uninstallation callbacks
function system_applicationInstalledCallback(files, flagTables)
  for i=1,#files do
    if string.match(files[i], "V2RayX")
      or string.match(files[i], "V2rayU")
      or string.match(files[i], "MonoProxyMac") then
      if flagTables[i].itemCreated or flagTables[i].itemRemoved then
        registerProxyMenu(true)
      end
    end
  end
end

-- wifi callbacks

-- use lab proxy in lab
local labProxyConfig = ProxyConfigs["Lab Proxy"]
local lastWifi = hs.wifi.currentNetwork()

function system_wifiChangedCallback()
  if labProxyConfig == nil or labProxyConfig.condition == nil then return end

  local curWifi = hs.wifi.currentNetwork()
  if curWifi == nil then
    lastWifi = nil
    if curNetworkService ~= nil then
      disable_proxy()
    end
    registerProxyMenu()
    return
  end

  if lastWifi == nil then
    hs.timer.waitUntil(
        function()
          getCurrentNetworkService()
          return curNetworkService ~= nil
        end,
        function()
          disable_proxy()
          local locations = labProxyConfig.locations
          local _, status_ok = hs.execute(labProxyConfig.condition.shell_command)
          local loc = status_ok and locations[1] or locations[2]
          if status_ok then
            enable_proxy_global("Lab Proxy", nil, loc)
          else
            if findApplication(proxyAppBundleIDs.MonoCloud) then
              hs.application.launchOrFocusByBundleID(proxyAppBundleIDs.MonoCloud)
              clickRightMenuBarItem(proxyAppBundleIDs.MonoCloud, "Outbound Mode", 3)
              enable_proxy_global("MonoCloud")
            elseif findApplication(proxyAppBundleIDs.V2rayU) then
              toggleV2RayU(true)
              clickRightMenuBarItem(proxyAppBundleIDs.V2rayU,
                                    { localized = "Pac Mode", strings = "MainMenu" })
              enable_proxy_PAC("V2rayU")
            elseif findApplication(proxyAppBundleIDs.V2RayX) then
              toggleV2RayX(true)
              clickRightMenuBarItem(proxyAppBundleIDs.V2RayX, "PAC Mode")
              enable_proxy_PAC("V2RayX")
            end
          end
          registerProxyMenu()
        end)
  end

  lastWifi = curWifi
end

-- monitor callbacks

local builtinMonitor = "Built-in Retina Display"

function system_monitorChangedCallback()
  local screens = hs.screen.allScreens()

  -- only for built-in monitor
  local builtinMonitorEnable = hs.fnutils.some(screens, function(screen)
    return screen:name() == builtinMonitor
  end)

  -- for external monitors
  if (builtinMonitorEnable and #screens > 1)
    or (not builtinMonitorEnable and #screens > 0) then
    hs.caffeinate.set("displayIdle", true)
    caffeine:setTitle("AWAKE")
  elseif builtinMonitorEnable and #screens == 1 then
    hs.caffeinate.set("displayIdle", false)
    caffeine:setTitle("SLEEPY")
  end
end

-- battery callbacks

function system_batteryChangedCallback()
  local percent = hs.battery.percentage()
  if percent <= 10 then
    if not hs.battery.isCharging() then
      hs.alert.show("Battery is low, please charge your laptop!", 3)
    end

    if hs.caffeinate.get("displayIdle") then
      hs.caffeinate.set("displayIdle", false)
      caffeine:setTitle("SLEEPY")
    end
    if hs.caffeinate.get("systemIdle") then
      hs.caffeinate.set("systemIdle", false)
    end
  end
end
