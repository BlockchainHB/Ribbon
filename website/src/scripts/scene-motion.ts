// Decorative, bounded website demonstrations. Native window state stays in the engine.
type MotionSpec = { element: HTMLElement; frames: Keyframe[]; end: Record<string, string> };
const travel = 'cubic-bezier(0.77, 0, 0.175, 1)';
const feedback = 'cubic-bezier(0.23, 1, 0.32, 1)';

const duration = 9000;
type Stop = { at: number; values: Record<string, string>; easing?: string };

function timeline(element: HTMLElement, stops: Stop[]): MotionSpec {
  const state = { ...stops[0].values };
  const frames = stops.map(({ at, values, easing }) => ({ ...Object.assign(state, values), offset: at / duration, easing: easing ?? travel }));
  return { element, frames, end: { ...state } };
}

function storyboard(root: HTMLElement): { specs: MotionSpec[]; duration: number } {
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
  const translate = (x: number, y = 0) => `translate(${x}px, ${y}px)`;
  const specs = [
    timeline(track, [
      { at: 0, values: { transform: translate(0) } },
      { at: 900, values: {} },
      { at: 1800, values: { transform: translate(-editorLeft) } },
      { at: 3750, values: {} },
      { at: 4300, values: { transform: translate(-editorLeft - camera) } },
      { at: 6200, values: {} },
      { at: 7000, values: { transform: translate(-editorLeft) } },
      { at: duration, values: {} },
    ]),
    timeline(editor, [
      { at: 0, values: { transform: translate(0), width: `${editorWidth}px`, height: `${full}px` } },
      { at: 3000, values: {} },
      { at: 3750, values: { transform: translate(groupMove) } },
      { at: 5000, values: {} },
      { at: 5500, values: { height: `${half}px` } },
      { at: 6200, values: {} },
      { at: 7000, values: { transform: translate(0), width: `${stackedWidth}px` } },
      { at: duration, values: {} },
    ]),
    timeline(preview, [
      { at: 0, values: { transform: translate(0) } },
      { at: 3000, values: {} },
      { at: 3750, values: { transform: translate(groupMove) } },
      { at: 6200, values: {} },
      { at: 7000, values: { transform: translate(editorLeft + stackedWidth + gap - previewLeft) } },
      { at: duration, values: {} },
    ]),
    timeline(companion, [
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
      { at: duration, values: {} },
    ]),
    timeline(outline, [
      { at: 0, values: { opacity: '0', transform: translate(0) } },
      { at: 2450, values: {}, easing: feedback },
      { at: 2700, values: { opacity: '1' } },
      { at: 3000, values: {} },
      { at: 3750, values: { transform: translate(groupMove) } },
      { at: 4750, values: {}, easing: feedback },
      { at: 5000, values: { opacity: '0' } },
      { at: duration, values: {} },
    ]),
  ];
  for (const [name, from, to] of [['swipe', 0, 2450], ['group', 2450, 4750], ['stack', 4750, duration]] as const) {
    const caption = root.querySelector<HTMLElement>(`[data-caption="${name}"]`)!;
    const stops: Stop[] = [{ at: 0, values: { opacity: from === 0 ? '1' : '0' } }];
    if (from) stops.push({ at: from, values: {}, easing: feedback }, { at: from + 150, values: { opacity: '1' } });
    if (to < duration) stops.push({ at: to - 150, values: {}, easing: feedback }, { at: to, values: { opacity: '0' } });
    stops.push({ at: duration, values: {} });
    specs.push(timeline(caption, stops));
  }
  return { specs, duration };
}

class Scene {
  readonly stage: HTMLElement;
  readonly button: HTMLButtonElement;
  complete = false;
  private allowed = false;
  private userPaused = false;
  private epoch = 0;
  private animations: Animation[] = [];
  private specs: MotionSpec[] = [];
  private phase: 'idle' | 'playing' | 'resetting' = 'idle';
  private width: number;
  private resize: ResizeObserver;

  constructor(readonly root: HTMLElement, private changed: () => void, replay: () => void) {
    this.stage = root.querySelector<HTMLElement>('.workspace-scene')!;
    this.button = root.querySelector<HTMLButtonElement>('.scene-replay')!;
    this.button.addEventListener('click', () => {
      if (this.complete) { replay(); return; }
      this.userPaused = !this.userPaused;
      this.setActive(this.allowed);
    });
    this.width = this.stage.clientWidth;
    this.resize = new ResizeObserver(() => {
      if (Math.abs(this.stage.clientWidth - this.width) < 1) return;
      this.width = this.stage.clientWidth;
      if (this.phase !== 'idle' || this.complete) this.finish(matchMedia('(prefers-reduced-motion: reduce)').matches);
      else { this.clear(); this.prime(); }
    });
    this.resize.observe(this.stage);
    this.prime();
    root.dataset.motionState = 'idle';
  }

  private prime() {
    this.specs = storyboard(this.root).specs;
    for (const { element, frames, end } of this.specs) {
      for (const property of Object.keys(end)) element.style.setProperty(property, String(frames[0][property]));
    }
  }

  setActive(active: boolean) {
    this.allowed = active;
    this.updateControl();
    if (this.complete) return;
    const running = active && !this.userPaused;
    if (running && this.phase === 'idle') { void this.play(); return; }
    for (const animation of this.animations) running ? animation.play() : animation.pause();
    this.root.dataset.motionState = this.phase === 'idle' ? 'idle' : running ? this.phase : 'paused';
  }

  private updateControl() {
    this.button.dataset.control = this.complete ? 'replay' : this.userPaused ? 'play' : 'pause';
    this.button.setAttribute('aria-label', `${this.complete ? 'Replay' : this.userPaused ? 'Resume' : 'Pause'} workspace demonstration`);
  }

  async play(replay = false) {
    const epoch = ++this.epoch;
    this.complete = false;
    this.userPaused = false;
    this.button.hidden = false;
    if (replay) {
      this.phase = 'resetting';
      const opacity = getComputedStyle(this.stage).opacity;
      this.animations.forEach(animation => animation.pause());
      const fade = this.stage.animate([{ opacity }, { opacity: 0 }], { duration: 80, fill: 'forwards' });
      this.animations.push(fade);
      if (!this.allowed) fade.pause();
      try { await fade.finished; } catch { return; }
      if (epoch !== this.epoch) return;
    }
    this.clear();
    const { specs, duration } = storyboard(this.root);
    this.specs = specs;
    this.phase = 'playing';
    this.animations = specs.map(({ element, frames }) => element.animate(frames, { duration, fill: 'both' }));
    if (replay) this.animations.push(this.stage.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 120, easing: feedback, fill: 'both' }));
    this.setActive(this.allowed);
    try {
      await Promise.all(this.animations.map(animation => animation.finished));
      if (epoch === this.epoch) this.finish();
    } catch { /* A superseded run owns no further work. */ }
  }

  finish(staticFrame = false) {
    ++this.epoch;
    this.clear();
    this.specs = storyboard(this.root).specs;
    for (const { element, end } of this.specs) Object.assign(element.style, end);
    this.complete = true;
    this.phase = 'idle';
    this.root.dataset.motionState = 'complete';
    this.button.hidden = staticFrame;
    this.updateControl();
    this.changed();
  }

  private clear() {
    this.animations.forEach(animation => animation.cancel());
    this.animations = [];
    for (const { element, end } of this.specs) for (const property of Object.keys(end)) element.style.removeProperty(property);
    this.specs = [];
  }

  destroy() { ++this.epoch; this.clear(); this.resize.disconnect(); }
}

function mount() {
  const root = document.querySelector<HTMLElement>('[data-motion="workspace"]');
  if (!root || !('animate' in HTMLElement.prototype)) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let ratio = 0;
  const scene = new Scene(root, reconcile, () => {
    if (reduced.matches) return;
    scene.setActive(false);
    void scene.play(true);
    reconcile();
  });

  function reconcile() {
    scene.setActive(!reduced.matches && !document.hidden && ratio >= Math.min(.5, innerHeight / root!.offsetHeight / 2));
  }
  const observer = new IntersectionObserver(([entry]) => {
    ratio = entry.intersectionRatio;
    reconcile();
  }, { threshold: Array.from({ length: 21 }, (_, index) => index / 20) });
  observer.observe(root);

  function preferenceChanged() {
    scene.finish(true);
    scene.button.hidden = reduced.matches;
    reconcile();
  }
  if (reduced.matches) preferenceChanged();
  reduced.addEventListener('change', preferenceChanged);
  document.addEventListener('visibilitychange', reconcile);
  window.addEventListener('pageshow', reconcile);
  window.addEventListener('pagehide', event => {
    if (event.persisted) { scene.setActive(false); return; }
    observer.disconnect();
    scene.destroy();
    reduced.removeEventListener('change', preferenceChanged);
    document.removeEventListener('visibilitychange', reconcile);
    window.removeEventListener('pageshow', reconcile);
  });
}

mount();
