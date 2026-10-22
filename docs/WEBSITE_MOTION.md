# Ribbon website motion study and implementation plan

Status: implemented on 22 October 2026; verification is recorded in `website/VERIFICATION.md`.

**Current direction, revised 22 October:** the user found the separate demonstrations too weak and requested that the first/main illustration show swipe → group → stack. Only the hero now animates. Its larger nine-second sequence swipes one column, outlines and reorders the editor/preview pair, then stacks Claude beneath the editor and fills the remaining width. A single control pauses/resumes playback and becomes Replay at completion; reduced motion shows the final stack without a control. Lower illustrations stay static. `HeroScene.astro` and `hero.css` own the primary illustration; `scene-motion.ts` owns its single timeline and lifecycle. The separate-scene storyboards below remain research history, not the current implementation target.
Studied: 22 October 2026. Website baseline: `b44a56ba450913d1fdce171b070317101af0fef4`.

Historical implementation notes (superseded by the hero revision above): the three demos progressively enhance the existing Astro illustrations without new dependencies. Stacking uses a 350 ms shell resize followed by a 450 ms entry into the vacant lower tile, rather than simultaneous crossing, to prevent collisions. The travel/feedback curves live together in `website/src/scripts/scene-motion.ts`. Replay controls are omitted in reduced motion; static frames provide the explanation. Very short viewports use half the viewport height as the visibility threshold so a tall scene can still play. Overview, design, displays, headings, and footer remain still.

## Recommendation

Use three small product demonstrations: **slide through the workspace**, **move a pair together**, and **stack windows vertically**. Give each a distinct place and one idea to explain. Keep the approved typography, whitespace, Cobalt palette, section structure, and white footer. Headings and prose stay visible and still.

The feeling should be calm and precise: windows keep their identity, travel along understandable paths, and settle without bounce. Motion supplies evidence for the copy. It does not become another layer of content or a reason to introduce badges, fake toolbars, or agent status controls.

This plan concerns the Astro marketing website. It changes no native app, engine behavior, shortcut responsiveness, pairing rules, or release binary.

## Research provenance

The official repository is [emilkowalski/skills](https://github.com/emilkowalski/skills). Research is pinned to [`2d228630ba1446365f614a108cb8252f1feda202`](https://github.com/emilkowalski/skills/tree/2d228630ba1446365f614a108cb8252f1feda202), rather than an unversioned third-party summary. The installed `emil-design-eng` skill matches this upstream skill's substantive guidance; its introductory course link differs.

Reviewed the complete web motion guidance and recipes in:

- [`emil-design-eng`](https://github.com/emilkowalski/skills/blob/2d228630ba1446365f614a108cb8252f1feda202/skills/emil-design-eng/SKILL.md): purpose, timing, easing, transitions, physicality, accessibility, and craft.
- [`animate`](https://github.com/emilkowalski/skills/tree/2d228630ba1446365f614a108cb8252f1feda202/skills/animate): construction decisions and recipes.
- [`animation-vocabulary`](https://github.com/emilkowalski/skills/tree/2d228630ba1446365f614a108cb8252f1feda202/skills/animation-vocabulary): consistent names for the decisions.
- [`find-animation-opportunities`](https://github.com/emilkowalski/skills/tree/2d228630ba1446365f614a108cb8252f1feda202/skills/find-animation-opportunities), [`improve-animations`](https://github.com/emilkowalski/skills/tree/2d228630ba1446365f614a108cb8252f1feda202/skills/improve-animations), and [`review-animations`](https://github.com/emilkowalski/skills/tree/2d228630ba1446365f614a108cb8252f1feda202/skills/review-animations): opportunity selection, audit categories, planning, and review standards.
- [`animation-performance`](https://github.com/emilkowalski/skills/tree/2d228630ba1446365f614a108cb8252f1feda202/skills/animation-performance): rendering costs, animation drivers, inherited variables, blur, and profiling.
- [`apple-design`](https://github.com/emilkowalski/skills/tree/2d228630ba1446365f614a108cb8252f1feda202/skills/apple-design): continuity, direct manipulation, springs, interruption, velocity, and boundaries. Relevant mobile-web sections of `mobile-native` and the native-specific `animate-expo` guidance were also checked for transferable principles. Expo dependencies and native-only recipes are not a proposed website stack.

Cross-checked with Emil's own published explanations:

1. [You Don't Need Animations](https://emilkowal.ski/ui/you-dont-need-animations): restraint and a useful distinction between repeated interactions and product explanation.
2. [7 Practical Animation Tips](https://emilkowal.ski/ui/7-practical-animation-tips): feedback, initial scale, easing, origins, speed, and restrained blur.
3. [Good vs Great Animations](https://emilkowal.ski/ui/good-vs-great-animations): small details, continuity, and choosing the technique for its context.
4. [Great Animations](https://emilkowal.ski/ui/great-animations): the broader relationship between purpose, natural movement, performance, accessibility, and cohesion.
5. [The Magic of Clip Path](https://emilkowal.ski/ui/the-magic-of-clip-path): revealing content without stretching it, coordinated states, and bounded viewport-triggered demonstrations.

This is a study of the public repository and articles, not a claim to have completed the paid course. Numeric timings below are proposed Ribbon tuning values. They are not universal prescriptions from Emil.

## Principles translated into Ribbon decisions

| Principle family | What it means for this website |
| --- | --- |
| Purpose | Every moving scene teaches a specific window-management behavior. No purposeless floating windows or moving decoration. |
| Frequency and restraint | A first-view explanation can take time. Navigation, download activation, repeated key input, and reading should remain immediate. |
| Feedback and latency | Real controls acknowledge a press immediately; their action never waits for a scene to finish. Keep the existing restrained button treatment. |
| Pacing | Show a readable starting arrangement, perform one operation, and leave enough time to understand the result. No rapid sequence of unrelated tricks. |
| Easing | Use a shared travel curve for windows already on screen and an ease-out curve for brief state feedback. Avoid linear window travel and delayed-feeling ease-in entrances. |
| Continuity | A window remains the same window throughout. Its title, contents, dimensions, and direction establish its identity. No teleporting or replacement with a different app mid-transition. |
| Origin and spatial meaning | A window enters through the actual clipped workspace boundary. Any future popover originates at its trigger. Do not grow entire sections from zero scale. |
| Physicality | Smooth deceleration with no overshoot is the default here. Springs are appropriate if we later add direct manipulation; bounce is unnecessary for the three scripted demos. |
| Interruptibility | Scrolling away, changing motion preference, resizing, or replaying cannot leave half-finished geometry or queue another sequence. Interrupt from the visible state or settle cleanly. |
| Gesture tracking | If a later interactive version supports dragging, preserve the grab offset, capture the pointer, track one pointer, and keep movement attached to the pointer. Do not add drag complexity to the initial explanatory version. |
| Velocity and boundaries | Future flick/drag behavior should hand off release velocity, project the endpoint, and resist at boundaries. Those rules do not justify decorative momentum in a scripted demonstration. |
| Stagger and hierarchy | A small stagger can clarify a genuine sequence. Paired windows must move simultaneously: staggering them would teach the wrong behavior. No word-by-word headline entrance. |
| Masking and content clarity | Clip at the scene and window boundaries. Keep type upright and undistorted when window shells change size. A mask is a tool for the resize demo, not a page-wide reveal effect. |
| Blur and shadows | Keep existing static depth. Do not animate large blurs or shadows. A subtle blur can hide a difficult content swap, but none is necessary for these storyboards. |
| Rendering cost | Prefer explicit transforms and opacity on a small number of elements. No `transition: all`, per-frame framework renders, or inherited parent CSS variables driving every child. |
| Animation driver | CSS handles press feedback; WAAPI can sequence the predetermined scenes in the existing Astro site. No React, Motion, or GSAP dependency is justified by this scope. |
| Honest performance claims | CSS and WAAPI can use compositor acceleration; the browser decides. Neither a transform nor a library guarantees 60/120 fps. Measure on target browsers and devices. |
| Reduced motion | Show a useful static arrangement immediately. Cancel running translations when the preference changes. Preserve necessary feedback and all information. |
| Touch and keyboard | No hover requirement or scroll interception. Any replay affordance works by touch and keyboard, with an accessible label and visible focus. |
| Cohesion | Reuse a small set of curves and timings. Keep the current type scale, colors, clean surfaces, and restrained control styling. No new visual language for animation. |
| Review | Inspect at normal speed, slow playback, and frame by frame; profile under load and review again with fresh eyes. Device emulation is not evidence of real iPhone smoothness. |

Some upstream audit checklists use absolute shorthand such as “transform and opacity only”; the dedicated performance skill gives more qualified advice. We should use its measured approach. In particular, scaling a whole text-filled window to imitate resizing distorts the contents. A small, isolated shell/mask animation is preferable if profiling supports it; an expensive technique must have a simpler fallback.

## Audit of the current site

| Before | After | Why |
| --- | --- | --- |
| `WorkspaceScene.astro` shows a static strip with clipped extra windows. | A single inner track moves one column inside the existing fixed stage. | The visitor sees what “scrolling workspace” actually means. |
| The coding scene shows a static agent/IDE arrangement. | Its two adjacent columns move with the same offset, width ratio, and timing. | A useful split and a linked pair become visibly different concepts. |
| Vertical stacking is mentioned in the product but has no website demonstration. | A separate, short section shows two windows sharing one column's height. | Pairing and stacking remain distinguishable. |
| `OverviewScene.astro` already communicates icons and titles clearly. | Keep it still in the initial pass; consider one reorder demonstration only after the three core demos work. | Preserve focus and avoid several simultaneous explanations. |
| The site has restrained press transitions and a reduced-motion CSS rule. | Preserve them; add explicit lifecycle and reduced-motion handling to scripted scenes. | CSS alone cannot stop a WAAPI timeline created by JavaScript. |

Current owners: `website/src/pages/index.astro` (section composition), `website/src/components/WorkspaceScene.astro` (illustrated windows), `website/src/components/OverviewScene.astro` (overview), `website/src/styles/scenes.css` (scene layout), and `website/src/styles/site.css` (page and control styling).

## Three separate storyboards

### 1. Sliding — hero workspace

Question answered: **Where does the rest of my work go?**

Keep the present Codex → IDE → Preview arrangement and clipped continuation. Introduce a fixed-size stage and an inner strip. Move the strip, not each window independently. Widths and gaps remain stable; the newly revealed window enters from the clipped edge. Nothing leaks into the page gutter.

| Time | Frame |
| --- | --- |
| 0–900 ms | Hold the original arrangement so the visitor can identify the windows. |
| 900–1450 ms | Translate the strip to reveal the next useful column. Use measured column positions; avoid arbitrary pixel distances. |
| 1450–3000 ms | Hold the new arrangement, with the newly focused window visibly in view. Stop. |

Use **550 ms** for this travel as a starting point. One movement is enough; do not sweep back and forth. Preserve every window's identity and keep the focused window fully inside the viewport. On small screens, use the existing simpler content and a breakpoint-specific destination; do not shrink an entire desktop into unreadable miniatures.

Static fallback: the current useful strip, including its clipped continuation. The existing caption describes keyboard movement without pretending the illustration accepts native app shortcuts.

### 2. Pairing — agent beside the code

Question answered: **How do I keep these two windows together?**

Show an agent and IDE in a ⅓–⅔ arrangement, followed by a separate preview column. Demonstrate a block reorder: `[Agent + IDE] · Preview` becomes `Preview · [Agent + IDE]`. The linked windows translate together with the same offset and timing; the preview moves into the space they leave. Preserve widths and gaps. This teaches a property that ordinary strip scrolling alone would not explain.

| Time | Frame |
| --- | --- |
| 0–1000 ms | Hold the readable ⅓–⅔ pair. |
| 1000–1200 ms | A quiet, shared outline can briefly establish the pair if movement alone is ambiguous. This is an illustrative cue, not a new Ribbon control. |
| 1200–1700 ms | Reorder the pair as one block past the preview. Both members move in lockstep; the preview shifts to its new position. |
| 1700–3300 ms | Hold the useful result and stop; let the outline fade if used. |

Use **500 ms** travel, **200 ms** maximum for the optional cue. Do not stagger the two windows, pulse indefinitely, shrink them into a single tile, or depict pairing as a vertical stack. Build a quick storyboard first: use clipped continuation and minimal illustrative content so the three identities remain clear inside the existing stage. On small screens, shorten the travel and simplify contents; do not scale the typography down to fit three dense desktop windows. Keep any camera adjustment separate from the reorder so the two operations remain understandable.

Static fallback: agent beside IDE at ⅓–⅔. The sentence about pairing supplies the information without relying on motion alone.

### 3. Stacking — a distinct new feature section

Question answered: **Can two windows share a column?**

Place a concise section after “More agents. One workspace.” and before the design example. Proposed copy:

> **Two windows. One column.**
>
> Stack a browser and terminal while your agent stays beside them.

Use the existing feature-section layout and type scale; no new eyebrow, feature tags, settings screenshot, or extra CTA. A neutral scene complements the Cobalt pairing scene.

Start with an agent in one column and a browser and terminal in neighboring columns. Move the terminal into the browser's column as the browser shortens. End with browser above terminal, each using half the column height with one consistent gap. The agent column keeps its full height. A stack is two usable vertical tiles, not overlapping cards or a fanned pile.

| Time | Frame |
| --- | --- |
| 0–1000 ms | Hold the separate windows. |
| 1000–1600 ms | Coordinate the browser's shell resize and terminal's move into the lower half of the same column. Maintain readable, unscaled content. |
| 1600–3600 ms | Hold the final vertical stack beside the full-height agent. Stop. |

Use **600 ms** for the coordinated operation initially. Do not depict vertical stacks as a permanent pair: the product treats these as different relationships, and explicit stack/unstack operations can detach a pair.

Static fallback: the final vertical stack beside the agent. On narrow screens keep two clear regions and app titles, reducing decorative content before reducing text size. No default return animation; unstacking can be a later user-triggered demonstration if it proves necessary.

## Motion values and playback policy

Proposed shared values, reusing the existing press token:

```css
/* Add alongside the current --press token, not in a parallel theme. */
--motion-travel: cubic-bezier(0.77, 0, 0.175, 1);
--motion-feedback: cubic-bezier(0.23, 1, 0.32, 1);
```

The curves are present in Emil's repository. The 500/550/600 ms demo durations and holds are Ribbon proposals to tune against the actual travel distance. These are explanatory sequences, not delays imposed on real app interaction. Keep ordinary button feedback around the current 150 ms; never delay download/navigation to finish an animation.

- Play once when at least half the scene is visible. The initial hold gives the reader time to orient. Text never starts hidden waiting for JavaScript or intersection detection.
- Run only one demo at a time. If two stages qualify, choose the one with the larger visible share, breaking a tie by proximity to viewport center. Do not interrupt a playing scene merely because the shares swap slightly; transfer ownership when it leaves the eligibility region.
- Pause when the document becomes hidden or the scene leaves view. Returning can resume the unfinished scene; completed scenes stay completed. Do not replay every time the reader scrolls past.
- After completion, offer one quiet replay glyph with an accessible name such as “Replay stacking demonstration.” Preserve a generous touch target and visible keyboard focus. No permanent playback toolbar or row of controls.
- Replaying cancels the previous run. Return to the initial arrangement without a visible backward sweep, then play one sequence. If a reset would be visible, use a brief local opacity transition; never queue rapid replays.
- With `prefers-reduced-motion: reduce`, do not autoplay translations or resizes. Show the fallback immediately. The replay affordance may switch between static before/after states; its accessible label must describe that behavior rather than promise movement.
- Listen for preference changes while the page is open. A change to reduced motion cancels every active timeline and commits the static fallback, including any paused scene.
- Preserve normal scrolling and pinch zoom. No pinned scroll sequences, wheel interception, drag requirement, autoplay sound, or haptics.
- Keep illustrative internals `aria-hidden`; retain each figure's meaningful accessible description and provide a concise explanation of the result. Do not announce every animation frame or make fake window controls focusable.

## Implementation shape

Keep the existing static Astro page and progressive enhancement. No native engine or app process is involved.

1. Add an inner `.workspace-track` within the existing stage in `WorkspaceScene.astro`. Keep stage dimensions and clipping stable. Use variant-specific data hooks for sliding and pairing. Scope current direct-child selectors carefully, including the mobile last-window rule, so the wrapper does not regress layout.
2. Add `StackScene.astro` and its corresponding section in `index.astro`. Reuse `WindowChrome.astro` and the existing window styling. Use illustrative Browser/Terminal content; actual application names are examples, not integrations.
3. Add one small `website/src/scripts/scene-motion.ts` module. It owns visibility, reduced-motion preference, active-scene arbitration, and cancellation. Each scene exposes play, pause, finish, and reset behavior; avoid a generic animation framework or simulated window manager.
4. Use WAAPI for predetermined window translations and opacity, plus CSS for control feedback. Store animation handles and use completion promises; cancel dependent work when a run is superseded. Do not sequence through unmanaged timeout chains.
5. Measure stage/column geometry at initialization and meaningful size changes, not every frame. If a breakpoint changes during playback, cancel and settle to a valid responsive arrangement before measuring again. A completed state must survive resize.
6. For stacking, animate separate window shells and clipped content so text never scales. Prefer transform-based positioning. If shell size or inset clipping must animate, isolate it within the fixed scene, profile Safari and a phone, and fall back to a short state crossfade if the cost is excessive. Do not claim all clipping is GPU accelerated.
7. Keep the DOM's no-JavaScript state informative and visible. Resting styles own the final state after completion; avoid stale fill-mode animations overriding responsive CSS. Remove temporary compositor hints after use, and add them only when measurement demonstrates a need.

Optional later pass: one icon-and-title reorder in the overview, with neighboring items making space in roughly 250–300 ms. Keep it out of the initial three-demo scope. The design scene, display scene, FAQ, CTA, logo, and footer remain still.

## Verification and acceptance

Commands for a future implementation:

```sh
cd /Users/neat/dev/Ribbon/website
npm run check
npm run build
cd /Users/neat/dev/Ribbon
git diff --check
```

Add focused lifecycle checks for the scene controller: cancellation on replay, arbitration between eligible scenes, reduced-motion changes while running/paused, and successful cleanup. Prefer deterministic state assertions over timing-sensitive snapshot tests that only restate CSS values.

Visual review must cover:

- Sliding reveals the next window without changing column widths, leaking past the scene, flashing at an edge, or creating page overflow.
- Pairing visibly preserves the windows' shared movement, width ratio, and gap. Stacking clearly ends with two vertical tiles inside one column.
- No overlap, distorted text, clipped titles, border-radius jumps, or one-pixel seams during resizing. Inspect normal speed and approximately 20% playback speed.
- At 1440, 1024, 768, 390, and 320 CSS px: stable section dimensions, readable labels, correct endpoints, and no layout shift. Check zoom and a breakpoint change during playback.
- Initial reduced motion and live preference changes; JavaScript disabled; rapid replay; keyboard focus during motion; offscreen pause; background tab; two eligible scenes; completed scenes revisited.
- Chrome and Safari recordings under realistic load. At 60 Hz the frame interval is about 16.7 ms; at 120 Hz it is about 8.3 ms. Check long tasks, layout/paint cost, and unnecessary layers rather than promising a frame rate from code alone.
- A real phone check for touch feedback, viewport behavior, and performance. Desktop emulation is useful for layout, but must be reported separately from hardware verification.

Completion means the three capabilities are understandable with motion enabled **and** in their static fallbacks. Passing builds is necessary; a visual motion review is also required. No performance or hardware result is claimed by this plan.

## GitHub image repair delivered alongside this study

The screenshot exposed a fixed one-line SVG heading that exceeded its window width. The code font declaration also lived on a parent group while a `text` selector overrode its inherited font family. SVG font selection varied by viewer.

The repair wraps the heading, preserves code indentation, applies the monospace family directly to code text, and retains editable SVG sources. GitHub uses a 2400 × 960 PNG render at the existing display width for consistent typography across viewers. The website itself continues to use responsive HTML illustrations, which are the right source for the proposed motion.
