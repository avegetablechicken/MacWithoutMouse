mode=$(defaults read com.apple.touchbar.agent PresentationModeGlobal)
if [[ $mode == "fullControlStrip" ]]; then
  defaults write com.apple.touchbar.agent PresentationModeGlobal appWithControlStrip
else
  defaults write com.apple.touchbar.agent PresentationModeGlobal fullControlStrip
fi
killall "ControlStrip"