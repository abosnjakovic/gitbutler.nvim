# Reviewing a diff in the details pane: C comments the line under the cursor,
# Y yanks every comment as one structured blob. Regenerate with `make demo`.
Output "doc/demo/review.gif"
Set Shell "bash"
Set FontSize 15
Set Width 1560
Set Height 620
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear && nvim --clean -u doc/demo/init.lua" Enter
Sleep 1200ms
Type ":set showtabline=0"
Enter
Sleep 200ms
Type ":Butler"
Enter
Sleep 2400ms
Show

Sleep 1000ms
# Down to the commit under review, open the details pane, focus it. The row
# count assumes the demo scenario in scripts/demo.sh.
Type "jjj"
Sleep 800ms
Type "d"
Sleep 2400ms
Type "l"
Sleep 1200ms

# Onto the first added line. C opens a small float in insert mode; Esc leaves
# insert and Enter saves. A dot in the gutter marks the commented line.
Type "jjjjj"
Sleep 900ms
Type "C"
Sleep 1200ms
Type "claims may be nil here"
Sleep 900ms
Escape
Sleep 500ms
Enter
Sleep 2000ms

# A second comment further down the same hunk.
Type "jjjj"
Sleep 800ms
Type "C"
Sleep 1000ms
Type "this changes the caller contract"
Sleep 900ms
Escape
Sleep 500ms
Enter
Sleep 2200ms

# Y drains every comment into both registers as one blob, ready to paste to
# whoever wrote the diff.
Type "Y"
Sleep 2000ms

Type ":tabnew"
Enter
Sleep 700ms
Type "p"
Sleep 400ms
# Park the cursor off the heading: a multi-line charwise paste leaves it on the
# first pasted character, which reads as a missing letter in a still frame.
Type "G"
Sleep 3400ms
