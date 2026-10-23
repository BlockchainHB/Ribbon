// Decorative, looping website demonstrations of window management. Native window state stays
// in the engine. Each scene is a set of infinite WAAPI animations sharing one clock. Only the
// most visible scene plays; offscreen scenes, hidden tabs, and user-paused scenes hold their
// frame. Windows move with transforms; resizes animate the size of contained slots so text
// reflows rather than scales. Reduced motion shows each scene's representative still frame.
type Values = Record<string, string>;
type Stop = { at: number; values: Values; easing?: string };
type Track = { element: Element; frames: Keyframe[] };
type Storyboard = { duration: number; still: number; tracks: Track[] };
type Builder = (root: HTMLElement) => Storyboard;

const travel = 'cubic-bezier(0.77, 0, 0.175, 1)';
const feedback = 'cubic-bezier(0.23, 1, 0.32, 1)';
const fadedOut = { opacity: '0' };
const fadedIn = { opacity: '1' };

// A stop's easing applies to the segment that begins at that stop.
function timeline(element: Element | null, duration: number, stops: Stop[]): Track[] {
  if (!element) return [];
  const state = { ...stops[0].values };
  const frames = stops.map(({ at, values, easing }) => ({ ...Object.assign(state, values), offset: at / duration, easing: easing ?? travel }));
  return [{ element, frames }];
}

const translate = (x: number, y = 0) => `translate(${x}px, ${y}px)`;

// Hero: swipe one column, move the editor + preview pair, stack Claude, then return.
function workspace(root: HTMLElement): Storyboard {
  const duration = 11000;
  const viewport = root.querySelector<HTMLElement>('[data-viewport]')!;
  const track = root.querySelector<HTMLElement>('[data-track]')!;
  const editor = root.querySelector<HTMLElement>('[data-editor]')!;
  const preview = root.querySelector<HTMLElement>('[data-preview]')!;
  const companion = root.querySelector<HTMLElement>('[data-companion]')!;
  const outline = root.querySelector<HTMLElement>('[data-group-outline]')!;
  const gap = parseFloat(getComputedStyle(root.querySelector('.hero-stage')!).getPropertyValue('--hero-gap'));
  const full = viewport.clientHeight;
  const half = (full - gap) / 2;
  const down = half + gap;
  const width = viewport.getBoundingClientRect().width;
  const editorLeft = parseFloat(getComputedStyle(editor).left);
  const previewLeft = parseFloat(getComputedStyle(preview).left);
  const companionLeft = parseFloat(getComputedStyle(companion).left);
  const editorWidth = editor.getBoundingClientRect().width;
  const previewWidth = preview.getBoundingClientRect().width;
  const companionWidth = companion.getBoundingClientRect().width;
  const pairWidth = previewLeft + previewWidth - editorLeft;
  const groupMove = companionWidth + gap;
  const narrow = matchMedia('(max-width: 760px)').matches;
  const camera = narrow ? groupMove - (width - pairWidth) / 2 : Math.max(0, pairWidth + groupMove - width);
  const companionGroup = editorLeft - companionLeft;
  const companionStack = editorLeft + groupMove - companionLeft;
  const stackedWidth = width - previewWidth - gap;
  const captions = (name: string, stops: Stop[]) => timeline(root.querySelector(`[data-caption="${name}"]`), duration, stops);
  return {
    duration,
    still: 8200,
    tracks: [
      ...timeline(track, duration, [
        { at: 0, values: { transform: translate(0) } },
        { at: 900, values: {} },
        { at: 1800, values: { transform: translate(-editorLeft) } },
        { at: 3750, values: {} },
        { at: 4300, values: { transform: translate(-editorLeft - camera) } },
        { at: 6200, values: {} },
        { at: 7000, values: { transform: translate(-editorLeft) } },
        { at: 9300, values: {} },
        { at: 10300, values: { transform: translate(0) } },
        { at: duration, values: {} },
      ]),
      ...timeline(editor, duration, [
        { at: 0, values: { transform: translate(0), width: `${editorWidth}px`, height: `${full}px` } },
        { at: 3000, values: {} },
        { at: 3750, values: { transform: translate(groupMove) } },
        { at: 5000, values: {} },
        { at: 5500, values: { height: `${half}px` } },
        { at: 6200, values: {} },
        { at: 7000, values: { transform: translate(0), width: `${stackedWidth}px` } },
        { at: 9300, values: {} },
        { at: 10100, values: { width: `${editorWidth}px`, height: `${full}px` } },
        { at: duration, values: {} },
      ]),
      ...timeline(preview, duration, [
        { at: 0, values: { transform: translate(0) } },
        { at: 3000, values: {} },
        { at: 3750, values: { transform: translate(groupMove) } },
        { at: 6200, values: {} },
        { at: 7000, values: { transform: translate(editorLeft + stackedWidth + gap - previewLeft) } },
        { at: 9300, values: {} },
        { at: 10100, values: { transform: translate(0) } },
        { at: duration, values: {} },
      ]),
      ...timeline(companion, duration, [
        { at: 0, values: { transform: translate(0), width: `${companionWidth}px`, height: `${full}px`, opacity: '1' } },
        { at: 2700, values: {}, easing: feedback },
        { at: 2850, values: { opacity: '0' } },
        { at: 3000, values: {} },
        { at: 3750, values: { transform: translate(companionGroup) }, easing: feedback },
        { at: 3950, values: { opacity: narrow ? '0' : '1' } },
        { at: 5000, values: {} },
        { at: 5500, values: { height: `${half}px`, transform: translate(companionGroup, down) } },
        { at: 6200, values: { transform: translate(companionStack, down), width: `${editorWidth}px`, opacity: '1' } },
        { at: 7000, values: { transform: translate(companionGroup, down), width: `${stackedWidth}px` } },
        { at: 9000, values: {}, easing: feedback },
        { at: 9200, values: { opacity: '0' } },
        { at: 9250, values: {} },
        // Invisible return to its clipped starting slot; it reappears offscreen.
        { at: 9300, values: { transform: translate(0), width: `${companionWidth}px`, height: `${full}px` } },
        { at: 10300, values: {}, easing: feedback },
        { at: 10500, values: { opacity: '1' } },
        { at: duration, values: {} },
      ]),
      ...timeline(outline, duration, [
        { at: 0, values: { opacity: '0', transform: translate(0) } },
        { at: 2450, values: {}, easing: feedback },
        { at: 2700, values: { opacity: '1' } },
        { at: 3000, values: {} },
        { at: 3750, values: { transform: translate(groupMove) } },
        { at: 4750, values: {}, easing: feedback },
        { at: 5000, values: { opacity: '0' } },
        { at: 5100, values: { transform: translate(0) } },
        { at: duration, values: {} },
      ]),
      ...captions('swipe', [
        { at: 0, values: fadedIn },
        { at: 2300, values: {}, easing: feedback },
        { at: 2450, values: fadedOut },
        { at: 9200, values: {}, easing: feedback },
        { at: 9350, values: fadedIn },
        { at: duration, values: {} },
      ]),
      ...captions('group', [
        { at: 0, values: fadedOut },
        { at: 2450, values: {}, easing: feedback },
        { at: 2600, values: fadedIn },
        { at: 4600, values: {}, easing: feedback },
        { at: 4750, values: fadedOut },
        { at: duration, values: {} },
      ]),
      ...captions('stack', [
        { at: 0, values: fadedOut },
        { at: 4750, values: {}, easing: feedback },
        { at: 4900, values: fadedIn },
        { at: 9050, values: {}, easing: feedback },
        { at: 9200, values: fadedOut },
        { at: duration, values: {} },
      ]),
    ],
  };
}

// Shared strip geometry: viewport width, gap, and a slot's resting box.
function strip(root: HTMLElement) {
  const viewport = root.querySelector<HTMLElement>('[data-viewport]')!;
  const style = getComputedStyle(viewport);
  const slot = (name: string) => root.querySelector<HTMLElement>(`[data-slot="${name}"]`)!;
  return { width: viewport.clientWidth, height: viewport.clientHeight, gap: parseFloat(style.getPropertyValue('--g')), slot };
}

// A linked pair moves as one block: Codex + IDE trade places with Safari, then return.
function pair(root: HTMLElement): Storyboard {
  const duration = 9000;
  const { gap, slot } = strip(root);
  const codex = slot('codex');
  const ide = slot('ide');
  const safari = slot('safari');
  const pairWidth = ide.offsetLeft + ide.offsetWidth - codex.offsetLeft;
  const swap = (distance: number): Stop[] => [
    { at: 0, values: { transform: translate(0) } },
    { at: 1300, values: {} },
    { at: 2000, values: { transform: translate(distance) } },
    { at: 4400, values: {} },
    { at: 5100, values: { transform: translate(0) } },
    { at: duration, values: {} },
  ];
  const block = safari.offsetWidth + gap;
  const outline = root.querySelector('[data-outline]');
  return {
    duration,
    still: 3000,
    tracks: [
      ...timeline(codex, duration, swap(block)),
      ...timeline(ide, duration, swap(block)),
      ...timeline(outline, duration, swap(block)),
      ...timeline(safari, duration, swap(-(pairWidth + gap))),
      ...timeline(outline, duration, [
        { at: 0, values: fadedOut },
        { at: 700, values: {}, easing: feedback },
        { at: 1000, values: fadedIn },
        { at: 7600, values: {}, easing: feedback },
        { at: 7900, values: fadedOut },
        { at: duration, values: {} },
      ]),
    ],
  };
}

// Open the overview, choose Claude, and the strip scrolls to it; then choose Codex to return.
function overview(root: HTMLElement): Storyboard {
  const duration = 9600;
  const { slot } = strip(root);
  const items = [...root.querySelectorAll<HTMLElement>('[data-item]')];
  const x = (index: number) => items[index].offsetLeft - items[1].offsetLeft;
  const closed = { opacity: '0', transform: 'scale(.96)' };
  const open = { opacity: '1', transform: 'none' };
  const dimmed = { opacity: '.35', transform: 'scale(.97)' };
  const clear = { opacity: '1', transform: 'none' };
  const overlay = (rest: Values, shown: Values): Stop[] => [
    { at: 0, values: rest },
    { at: 1000, values: {}, easing: feedback },
    { at: 1350, values: shown },
    { at: 2700, values: {}, easing: feedback },
    { at: 3000, values: rest },
    { at: 5800, values: {}, easing: feedback },
    { at: 6150, values: shown },
    { at: 7400, values: {}, easing: feedback },
    { at: 7700, values: rest },
    { at: duration, values: {} },
  ];
  const choose = (to: number, at: number): Stop[] => [
    { at, values: {} },
    { at: at + 500, values: { transform: translate(x(to)) }, easing: feedback },
    { at: at + 600, values: { transform: `${translate(x(to))} scale(.88)` }, easing: feedback },
    { at: at + 750, values: { transform: translate(x(to)) } },
  ];
  return {
    duration,
    still: 2600,
    tracks: [
      ...timeline(root.querySelector('[data-overview]'), duration, overlay(closed, open)),
      ...timeline(root.querySelector('[data-workspace]'), duration, overlay(clear, dimmed)),
      ...timeline(root.querySelector('[data-pointer]'), duration, [{ at: 0, values: { transform: translate(x(0)) } }, ...choose(1, 1700), ...choose(0, 6400), { at: duration, values: {} }]),
      ...timeline(root.querySelector('[data-pointer]'), duration, [
        { at: 0, values: fadedOut },
        { at: 1350, values: {}, easing: feedback },
        { at: 1550, values: fadedIn },
        { at: 2700, values: {}, easing: feedback },
        { at: 2900, values: fadedOut },
        { at: 6150, values: {}, easing: feedback },
        { at: 6350, values: fadedIn },
        { at: 7400, values: {}, easing: feedback },
        { at: 7600, values: fadedOut },
        { at: duration, values: {} },
      ]),
      ...timeline(root.querySelector('[data-highlight]'), duration, [
        { at: 0, values: { transform: translate(x(0)) } },
        { at: 2300, values: {}, easing: feedback },
        { at: 2550, values: { transform: translate(x(1)) } },
        { at: 7000, values: {}, easing: feedback },
        { at: 7250, values: { transform: translate(x(0)) } },
        { at: duration, values: {} },
      ]),
      ...timeline(root.querySelector('[data-track]'), duration, [
        { at: 0, values: { transform: translate(0) } },
        { at: 2800, values: {} },
        { at: 3500, values: { transform: translate(-slot('terminal').offsetLeft) } },
        { at: 7500, values: {} },
        { at: 8200, values: { transform: translate(0) } },
        { at: duration, values: {} },
      ]),
    ],
  };
}
// Terminal leaves its own column and joins Safari's: one column, two windows, then unstack.
function stack(root: HTMLElement): Storyboard {
  const duration = 9000;
  const { width, height, gap, slot } = strip(root);
  const unit = (width - 2 * gap) / 100;
  const half = (height - gap) / 2;
  const single = `${32 * unit}px`;
  const column = `${64 * unit + gap}px`;
  const resize = (side: Values, stacked: Values): Stop[] => [
    { at: 0, values: side },
    { at: 1000, values: {} },
    { at: 1800, values: stacked },
    { at: 6200, values: {} },
    { at: 7000, values: side },
    { at: duration, values: {} },
  ];
  return {
    duration,
    still: 4000,
    tracks: [
      ...timeline(slot('browser'), duration, resize({ width: single, height: `${height}px` }, { width: column, height: `${half}px` })),
      ...timeline(slot('terminal'), duration, resize(
        { transform: translate(32 * unit + gap, -(half + gap)), width: single, height: `${height}px` },
        { transform: translate(0), width: column, height: `${half}px` },
      )),
    ],
  };
}

// Paper widens from a half to two-thirds, the strip scrolls to the preview, then everything returns.
function design(root: HTMLElement): Storyboard {
  const duration = 10000;
  const { width, gap, slot } = strip(root);
  const half = (width - gap) / 2;
  const third = (width - gap) / 3;
  const twoThirds = width - gap - third;
  const widths = (rest: Values, wide: Values): Stop[] => [
    { at: 0, values: rest },
    { at: 1000, values: {} },
    { at: 1800, values: wide },
    { at: 8100, values: {} },
    { at: 8900, values: rest },
    { at: duration, values: {} },
  ];
  return {
    duration,
    still: 2600,
    tracks: [
      ...timeline(slot('claude'), duration, widths({ width: `${half}px` }, { width: `${third}px` })),
      ...timeline(slot('paper'), duration, widths({ transform: translate(0), width: `${half}px` }, { transform: translate(third - half), width: `${twoThirds}px` })),
      ...timeline(root.querySelector('[data-track]'), duration, [
        { at: 0, values: { transform: translate(0) } },
        { at: 3400, values: {} },
        { at: 4200, values: { transform: translate(-(third + gap)) } },
        { at: 6500, values: {} },
        { at: 7300, values: { transform: translate(0) } },
        { at: duration, values: {} },
      ]),
    ],
  };
}

const builders: Record<string, Builder> = { workspace, pair, overview, stack, design };

class Scene {
  visible = 0;
  width: number;
  private animations: Animation[] = [];
  private paused = false;
  private running = false;
  private readonly button: HTMLButtonElement | null;

  constructor(readonly root: HTMLElement, private readonly build: Builder, changed: () => void) {
    this.button = root.querySelector<HTMLButtonElement>('[data-scene-toggle]');
    this.button?.addEventListener('click', () => {
      this.paused = !this.paused;
      this.label();
      changed();
    });
    this.width = root.clientWidth;
  }

  // Rebuild from current geometry, keeping the loop position across resizes.
  mount(reduced: boolean) {
    const previous = Number(this.animations[0]?.currentTime ?? 0);
    this.cancel();
    this.width = this.root.clientWidth;
    const { duration, still, tracks } = this.build(this.root);
    this.animations = tracks.map(({ element, frames }) => element.animate(frames, { duration, iterations: Infinity, fill: 'both' }));
    const time = reduced ? still : previous % duration;
    for (const animation of this.animations) {
      animation.currentTime = time;
      animation.pause();
    }
    this.running = false;
    if (this.button) this.button.hidden = reduced;
    this.label();
  }

  set(run: boolean) {
    const next = run && !this.paused;
    if (next === this.running) return;
    this.running = next;
    for (const animation of this.animations) next ? animation.play() : animation.pause();
  }

  private label() {
    this.root.dataset.playback = this.paused ? 'paused' : 'playing';
    this.button?.setAttribute('aria-label', `${this.paused ? 'Play' : 'Pause'} ${this.button.dataset.label}`);
  }

  cancel() {
    this.animations.forEach((animation) => animation.cancel());
    this.animations = [];
    this.running = false;
  }
}

function mount() {
  if (!('animate' in Element.prototype)) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let frame = 0;
  const schedule = () => { frame ||= requestAnimationFrame(reconcile); };
  const scenes = [...document.querySelectorAll<HTMLElement>('[data-motion]')].flatMap((root) => {
    const build = builders[root.dataset.motion ?? ''];
    return build ? [new Scene(root, build, schedule)] : [];
  });
  if (!scenes.length) return;
  const byRoot = new Map(scenes.map((scene) => [scene.root as Element, scene]));

  // One scene at a time: the one with the most visible area.
  function reconcile() {
    frame = 0;
    const active = reduced.matches || document.hidden ? null : scenes.reduce<Scene | null>((best, scene) => (scene.visible > (best?.visible ?? 0) ? scene : best), null);
    for (const scene of scenes) scene.set(scene === active);
  }

  const visibility = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      const scene = byRoot.get(entry.target)!;
      // Tall scenes on short viewports qualify once they fill a third of the viewport.
      const needed = Math.min(0.35, (innerHeight / Math.max(entry.boundingClientRect.height, 1)) * 0.35);
      scene.visible = entry.isIntersecting && entry.intersectionRatio >= needed ? entry.intersectionRect.height : 0;
    }
    schedule();
  }, { threshold: [0, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 1] });

  const geometry = new ResizeObserver((entries) => {
    for (const entry of entries) {
      const scene = byRoot.get(entry.target)!;
      if (Math.abs(scene.root.clientWidth - scene.width) < 1) continue;
      scene.mount(reduced.matches);
    }
    schedule();
  });

  function remount() {
    for (const scene of scenes) scene.mount(reduced.matches);
    schedule();
  }

  remount();
  for (const scene of scenes) {
    visibility.observe(scene.root);
    geometry.observe(scene.root);
  }
  reduced.addEventListener('change', remount);
  document.addEventListener('visibilitychange', schedule);
  window.addEventListener('pageshow', schedule);
  window.addEventListener('pagehide', (event) => {
    if (event.persisted) {
      for (const scene of scenes) scene.set(false);
      return;
    }
    visibility.disconnect();
    geometry.disconnect();
    for (const scene of scenes) scene.cancel();
    reduced.removeEventListener('change', remount);
    document.removeEventListener('visibilitychange', schedule);
    window.removeEventListener('pageshow', schedule);
  });
}

mount();
