# Amend mode: source -> target verb pills. `a` tags the uncommitted file as the
# source, the pill names the verb on every valid target, and <Esc> cancels
# without touching history.
# Records against the demo scenario in scripts/demo.sh. Regenerate with `make demo`.
Output "doc/demo/amend.gif"
Set Shell "bash"
Set FontSize 16
Set Width 1500
Set Height 760
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
# Pick the uncommitted file as the amend source.
Type "j"
Sleep 1200ms
Type "a"
Sleep 2200ms
# Walk the targets: the pill follows the cursor, invalid rows stay dimmed.
Type "j"
Sleep 1600ms
Type "j"
Sleep 1600ms
Type "j"
Sleep 1600ms
Type "j"
Sleep 2000ms
Type "k"
Sleep 1800ms
# Nothing has happened yet — <Esc> leaves history untouched.
Escape
Sleep 1400ms
