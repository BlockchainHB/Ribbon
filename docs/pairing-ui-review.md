# Pairing UI review

## Static group cues and native controls

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| LOW | native/Sources/Ribbon/Overview/OverviewView.swift:65 | No representation of linked columns | Small blue link symbol on a native material circle beside each paired icon | A static cue communicates membership without motion or extra title text. |
| LOW | native/Sources/Ribbon/Overview/OverviewView.swift:101 | No grouping actions | Native context menu with directional pairing, Ungroup and arrangement submenu | Keeps the established icon-and-title layout; disabled actions reflect engine membership. |
| LOW | native/Sources/Ribbon/Overview/OverviewController.swift:255 | Reorder assumed one column | Confirm engine movement ranges for pairs and target groups | Prevents a successful block move being reported as a failed one-column drop. |

Actual native captures in light and dark were visually inspected: selected and
unselected icons, pair badges, text alignment, spacing and material contrast.
External native accessibility automation opened the context menu and clicked
Ungroup; the engine independently confirmed removal of membership. The full
desktop run passed in `build/qa/pairing/build16-release-2/report.json`.

Existing press feedback remains 0.96 scale over 120 ms with the existing curve;
Reduce Motion suppresses it. No staged entrance or pairing animation was added.
The first presentation still loads the engine snapshot before sizing the panel.

Not verified in this pairing run: VoiceOver narration, hover/drag animation at
10% speed, OS-level contrast/Reduce Motion preferences, and physical two-monitor
movement. Prior motion receipts are historical evidence, not a replacement for
these checks.

Approve for the inspected one-display visual and Ungroup interaction coverage.
