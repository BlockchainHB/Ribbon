# Ribbon

Keep changes scoped to the local scrolling-window beta. The engine owns layout,
focus and gestures. The native app owns configuration and engine lifecycle.
Never duplicate layout state in Swift. Enforce the managed-app scope in the
engine, including recovery. Do not run an unrestricted engine during automated QA.

Keep upstream modifications small and record them in vendor/paneru/RIBBON.md.
Use pinned, checked-in source and locked dependencies. Preserve upstream notices.
Run scripts/verify.sh for changed product code and record hardware QA separately.
Do not claim a real-desktop check passed on mocked evidence.

Unless specifically asked, do not end responses with suggested next steps.
