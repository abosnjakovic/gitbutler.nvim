# Timeline: recent commits across every branch and contributor.
# Regenerate with `make demo` from the repo root.
Output "doc/demo/timeline.gif"
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
Type ":ButlerTimeline"
Enter
Sleep 2800ms
Show

Sleep 2000ms
Type "jjjj"
Sleep 1500ms
Type "jjj"
Sleep 2000ms
