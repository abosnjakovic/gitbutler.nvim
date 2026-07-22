# Rub mode: source -> target verb pills (assign / amend / unassign …).
# Regenerate with `make demo` from the repo root.
Output "doc/demo/rub.gif"
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
Sleep 2200ms
Show

Sleep 1200ms
Type "j"
Sleep 1200ms
Type "r"
Sleep 2500ms
Type "j"
Sleep 2000ms
Type "k"
Sleep 1800ms
Escape
Sleep 1500ms
