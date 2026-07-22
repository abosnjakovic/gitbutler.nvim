# Hero: one flow through the main features — the commit graph (uncommitted,
# an applied branch, and landed history below the base), rub mode (source ->
# target verb pills), the details pane with the commit header, and jump-to-code.
# Records against the demo scenario in scripts/demo.sh. Regenerate with `make demo`.
Output "doc/demo/butler.gif"
Set Shell "bash"
Set FontSize 15
Set Width 1560
Set Height 940
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
# Rub mode: pick the uncommitted file, watch the verb pill name each target.
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
# Details pane on a commit: the commit / Author / Date / message header + diff.
Type "g"
Sleep 400ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 900ms
Type "d"
Sleep 2600ms
# Jump straight from a hunk into the file to edit it.
Type "l"
Sleep 1100ms
Enter
Sleep 3000ms
