# Details pane: a commit's diff with the commit / Author / Date / message
# header, plus per-hunk navigation. Regenerate with `make demo`.
Output "doc/demo/details.gif"
Set Shell "bash"
Set FontSize 15
Set Width 1560
Set Height 860
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

Sleep 1200ms
# Move to a commit and open the details pane.
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 900ms
Type "d"
Sleep 2600ms
# Focus the pane and step through the hunks.
Type "l"
Sleep 1200ms
Type "j"
Sleep 1400ms
Type "j"
Sleep 1800ms
