# Screen-Overlay-MacOS
A full screen overlay for meeting reminders and work blocks scheduling, designed for ADHD users and general memory and time blindness support, with aesthetic customization to add moodboards, images and text for motivation and memory.

## Setup Instructions:

1. Run brew install --cask hammerspoon, open it, and allow what it asks for.

2. Put init.lua in ~/.hammerspoon/. If you already have an init.lua there, rename to now_overlay.lua and add require("now_overlay") to yours.
Terminal command: mkdir -p ~/.hammerspoon && mv -i ~/Downloads/init.lua ~/.hammerspoon/init.lua

3. Click the hammer icon in the menu bar → Reload Config.

4. Press ⌃⌥⌘N to set your task and step, then ⌃⌥⌘T to test.


## For future updates, redownload the lua file and run:

mv ~/Downloads/init.lua ~/.hammerspoon/init.lua && killall Hammerspoon; sleep 1; open -a Hammerspoon
