# Hero: the commit graph + details pane (follow-the-cursor diff).
# Regenerate with `make demo` from the repo root.
Output "doc/demo/butler.gif"
Set Shell "bash"
Set FontSize 16
Set Width 1500
Set Height 850
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear && nvim --clean -u doc/demo/init.lua" Enter
Sleep 1200ms
Type ":Butler"
Enter
Sleep 2500ms
Show

Sleep 1500ms
Type "j"
Sleep 900ms
Type "d"
Sleep 2200ms
Type "l"
Sleep 1200ms
Type "j"
Sleep 1400ms
Type "h"
Sleep 1200ms
Type "d"
Sleep 1500ms
