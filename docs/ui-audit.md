# Settings implementation and native review

Latest direction: the user-supplied macOS System Settings screenshot takes
precedence over the previous toolbar specification. The engine manages normal
applications automatically; Excluded Apps contains optional exclusions.

| Before | After | Reason |
| --- | --- | --- |
| Preference-tab toolbar | Native NavigationSplitView sidebar with blue selection | Match the current System Settings structure requested by the user. |
| SDK 15 executable stamp | Current SDK through SwiftPM native backend, packaging guard >= 26 | Let native controls and window chrome adopt the current appearance. |
| Disabled minimize and zoom buttons | Standard system window controls | Preserve modern native window behavior. |
| Manual grids / column forms | Grouped forms with labels leading and controls trailing | Use platform row geometry and surfaces. |
| Application opt-in setup | Automatic all-app policy with optional exclusions | Newly opened apps should be eligible without configuration. |
| Snapshot-only selected-app recovery | Policy-aware recovery, legacy journals remain restricted | Recover visibility for newly launched apps without touching exclusions. |
| Repeated shortcut controls | Roomy grouped shortcut rows, native search and shared editing sheet | Retain full customization while reducing row clutter. |

The shortcut and exclusion search fields reserve clearance for their native glass
drawing and use semantic text colors. The placeholder says Search. Sidebar-toggle
controls are removed; modifier and trackpad values align at the trailing edge.

Visual review receipts are recorded in docs/verification.json and the current
build/qa directory. Earlier toolbar captures are before-state evidence only.
Native window screenshots and physical fixture suites are recorded separately
from unit/component tests. No unrestricted engine is run during automated QA.
