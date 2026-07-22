# Landed history: the graph continues below the common base into the trunk's
# already-landed commits. Expand one (<Tab>) for its message + files, then open
# it in the details pane (d) for the full commit. Regenerate with `make demo`.
Output "doc/demo/landed-history.gif"
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

Sleep 1400ms
# Descend past the common base into the landed history.
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 1200ms
# Expand a landed commit: full message + files, inline.
Tab
Sleep 2400ms
# Open it in the details pane: commit / Author / Date / message + diff.
Type "d"
Sleep 3000ms
