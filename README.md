# Mac Without Mouse

Utilizing Hammerspoon and Karabiner-Elements to improve your productivity by operating fully via your keyboard and touchpad!

## Installation

Install the latest version of [Hammerspoon](https://www.hammerspoon.org/) and [Karabiner-Elements](https://karabiner-elements.pqrs.org/). You can either download them from official websites or by running below command:

```shell
brew install hammerspoon karabiner-elements --cask
```

Then clone this repository, rename `hammerspoon` to `.hammerspoon` and move it to your home directory, add  move `karabiner` to $HOME/.config. Finally, just launch Hammerspoon and Karabiner-Elements. Now you can throw away your mouse!

## Features

### Hammerspoon

- Various self-customizable hotkeys. See [keybindings](./hammerspoon/config/keybindings.json).

  - Hotkeys to launch, activate or hide applications.

  - Hotkeys to search / switch tabs or windows.

    ![image-20231102163300185](./assets/switch-tabs.png)

  - Hotkeys for monitor / window operation.

  - Hotkeys in specific applications or for specific windows.

  - Hotkeys for operations in Control Center (since Big Sur).

  - Missed hotkeys for some applications like ⌘+W to close window.

  - Key remapping for virtual machines and remote desktops.

  - Hotkeys to visualize or search all hotkeys.

    ![image-20231102162841696](./assets/show-keybindings.png)

    ![image-20231102162809074](./assets/search-keybindings.png)

- Monitoring applications and windows to automatically hide or quit applications.

- A menu bar item to automatically configure your network proxy (supports system proxy, `V2RayX`, `V2rayU`, `MonoProxyMac`)

  ![image-20231102162917625](./assets/proxymenu.png)

- Input sources for specific applications.

- Synchronize configurations and desensitizing them.

- Remove redundant text added by a website when you try to copy text on it.

### Karabiner-Elements

- Map CapsLock to F18 (for hyper modal required by my hammerspoon configuration).
- Fn-related hotkeys.
- Touch pad-related hotkeys.
- Safe quitting applications.

![image-20231102162952494](./assets/karabiner-complex.png)

## Acknowledgement

Some codes are taken from the following repositories:

- [HSKeybindings.spoon](https://github.com/Hammerspoon/Spoons/tree/master/Source/HSKeybindings.spoon)

- [chrome-pak-customizer](https://github.com/myfreeer/chrome-pak-customizer)

- [NIBArchive-Parser](https://github.com/MatrixEditor/nibarchive)
