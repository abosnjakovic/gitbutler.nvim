# Hero: one flow through the main features — the commit graph, rub mode
# (source -> target verb pills), the details pane, and jump-to-code.
# Records best against a feature branch with a couple of commits plus an
# uncommitted file (see scripts/demo.sh). Regenerate with `make demo`.
Output "doc/demo/butler.gif"
Set Shell "bash"
Set FontSize 15
Set Width 1560
Set Height 880
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear && nvim --clean -u doc/demo/init.lua" Enter
Sleep 1200ms
Type ":Butler"
Enter
Sleep 2400ms
Show

Sleep 1600ms
Type "j"
Sleep 1000ms
Type "r"
Sleep 1900ms
Type "j"
Sleep 1900ms
Type "j"
Sleep 1900ms
Escape
Sleep 1200ms
Type "g"
Sleep 500ms
Type "j"
Sleep 900ms
Type "d"
Sleep 2400ms
Type "l"
Sleep 1100ms
Enter
Sleep 3000ms
