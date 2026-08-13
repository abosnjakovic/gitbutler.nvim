+++
id = "msr3pviq"
tags = ["lua", "debugging"]
confidence = 0.6
helped = 0
harmed = 0
created = "2026-08-13T05:52:28.370080Z"
last_confirmed = "2026-08-13T05:52:28.370080Z"
+++

To step-debug this plugin: headless nvim with 'set rtp+=<repo>', packadd one-small-step-for-vimkind, osv.launch({port=N, blocking=true}), then strap debug session --lang lua --attach 127.0.0.1:N. Set cli.supported = nil to force the but version re-probe; cli.status() drives status->run->supported. Run 'strap debug continue' in the background BEFORE triggering — attach mode blocks until a stop.
