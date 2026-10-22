# Using Ribbon

## Install

1. [Download Ribbon](https://github.com/BlockchainHB/Ribbon/releases/download/v0.2.0-beta.1/Ribbon-macOS-arm64.zip), unzip it, and move **Ribbon.app** to **Applications**.
2. Open Ribbon. In **System Settings → Privacy & Security → Accessibility**, allow Ribbon.
3. Return to **Ribbon → Settings → General** and turn on **Window management**.

Requires an Apple silicon Mac and macOS 15 or later. Ribbon starts paused. Normal app windows are included automatically; **Excluded Apps** lets you leave particular apps alone. Avoid running another window manager at the same time.

## Move through your windows

Hold **Control–Option** and press **← / →** to focus another column. Scroll horizontally while holding the same modifiers to move through the strip.

**Control–Option–R** cycles the focused window through 33%, 50%, 67%, 75%, and full width. **Control–Option–F** toggles full width. Each column fills the available screen height; windows in a stack share that height.

In **Settings → Layout**, choose **Preserve widths** or **Fill available space**. Fill expands columns when the whole strip fits. Overflowing strips retain their widths and scroll.

## Arrange and pair

Press **Control–Option–Tab** to see your windows. Drag an icon to reorder its column, or click to focus it. **Shift–← / →** reorders the selected column in this overview; **Return** focuses and **Escape** closes it.

Right-click an icon and choose **Pair with Left** or **Pair with Right** to link two neighboring columns. Moving either member carries the pair. **Ungroup** separates them.

Use **Arrange ½–½**, **⅓–⅔**, or **⅔–⅓** to size two neighboring columns. Arranging their widths does not require pairing them. Pairs are kept for the current session, not saved across restarts.

## Stack

**Control–Option–]** stacks a window vertically with its neighbor. **Control–Option–Shift–]** removes it from the stack. A stack moves as one column.

## Displays

Each display has its own strip. **Control–Option–N** moves the focused column to the next display and follows it. Paired columns travel together. Physical multi-display pairing and reconnect behavior are still being tested.

## Pause and shortcuts

Pause from Ribbon's menu bar menu or **Control–Option–Q**. Ribbon restores the original window positions where applications allow it.

Open **Settings → Shortcuts** to change assignments, add alternatives, or remove a shortcut. Pause window management before recording. Pairing actions have no default shortcuts; assign them here if desired.

## If something looks wrong

Pause Ribbon first. If an interrupted session needs restoring, use **Settings → General → Restore Window Positions**. Some apps enforce minimum sizes or refuse frame changes. Hidden windows may retain a small native edge at the screen boundary.

For a bug report, include your macOS version, display arrangement, app name, and steps to reproduce. Crop out private document contents before attaching screenshots. [Report an issue](https://github.com/BlockchainHB/Ribbon/issues).
