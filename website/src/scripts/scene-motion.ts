// Decorative, bounded website demonstrations. Native window state stays in the engine.
type MotionSpec = { element: HTMLElement; frames: Keyframe[]; end: Record<string, string> };
const travel = 'cubic-bezier(0.77, 0, 0.175, 1)';
const feedback = 'cubic-bezier(0.23, 1, 0.32, 1)';

function sequence(element: HTMLElement, start: Record<string, string>, end: Record<string, string>, from: number, to: number): MotionSpec {
  return { element, end, frames: [{ ...start, offset: 0 }, { ...start, offset: from, easing: travel }, { ...end, offset: to }, { ...end, offset: 1 }] };
}

function storyboard(root: HTMLElement): { specs: MotionSpec[]; duration: number } {
  const viewport = root.querySelector<HTMLElement>('[data-viewport]')!;
  if (root.dataset.motion === 'stack') {
    const browser = root.querySelector<HTMLElement>('[data-browser]')!;
    const terminal = root.querySelector<HTMLElement>('[data-terminal]')!;
    const full = viewport.clientHeight;
    const half = browser.offsetHeight;
    const down = terminal.offsetTop;
    const beside = terminal.offsetWidth + parseFloat(getComputedStyle(viewport).getPropertyValue('--stack-gap'));
    // Resize outside the target column first; then enter its vacant lower half.
    const resize = sequence(browser, { height: `${full}px` }, { height: `${half}px` }, 1000 / 3800, 1350 / 3800);
    const enter = sequence(terminal, { transform: `translate(${beside}px, ${-down}px)`, height: `${full}px` }, { transform: 'translate(0px, 0px)', height: `${half}px` }, 1000 / 3800, 1800 / 3800);
    enter.frames = [
      { transform: `translate(${beside}px, ${-down}px)`, height: `${full}px`, offset: 0 },
      { transform: `translate(${beside}px, ${-down}px)`, height: `${full}px`, offset: 1000 / 3800, easing: travel },
      { transform: `translate(${beside}px, 0px)`, height: `${half}px`, offset: 1350 / 3800, easing: travel },
      { transform: 'translate(0px, 0px)', height: `${half}px`, offset: 1800 / 3800 },
      { transform: 'translate(0px, 0px)', height: `${half}px`, offset: 1 },
    ];
    return { specs: [resize, enter], duration: 3800 };
  }

  const track = root.querySelector<HTMLElement>('[data-track]')!;
  const gap = parseFloat(getComputedStyle(track).gap);
  if (root.dataset.motion === 'pair') {
    const pair = root.querySelector<HTMLElement>('[data-pair]')!;
    const preview = track.querySelector<HTMLElement>('.preview-window')!;
    const distance = preview.offsetWidth + gap;
    const camera = Math.max(0, pair.offsetWidth + distance - viewport.clientWidth);
    const move = sequence(pair, { transform: 'translateX(0px)' }, { transform: `translateX(${distance}px)` }, 1200 / 3300, 1700 / 3300);
    const neighbor = sequence(preview, { transform: 'translateX(0px)' }, { transform: `translateX(${-pair.offsetWidth - gap}px)` }, 1200 / 3300, 1700 / 3300);
    // The unrelated window crossfades during the crossing; the linked pair stays solid.
    const crossing: MotionSpec = { element: preview, end: { opacity: '1' }, frames: [
      { opacity: 1, offset: 0 }, { opacity: 1, offset: 1200 / 3300 },
      { opacity: 0, offset: 1330 / 3300 }, { opacity: 0, offset: 1570 / 3300 },
      { opacity: 1, offset: 1700 / 3300 }, { opacity: 1, offset: 1 },
    ] };
    return { specs: [move, neighbor, crossing, sequence(track, { transform: 'translateX(0px)' }, { transform: `translateX(${-camera}px)` }, 1200 / 3300, 1700 / 3300)], duration: 3300 };
  }

  const next = track.children[1] as HTMLElement;
  const distance = Math.max(0, Math.min(next.offsetLeft, track.scrollWidth - viewport.clientWidth));
  return { specs: [sequence(track, { transform: 'translateX(0px)' }, { transform: `translateX(${-distance}px)` }, 900 / 3000, 1450 / 3000)], duration: 3000 };
}

class Scene {
  readonly stage: HTMLElement;
  readonly button: HTMLButtonElement;
  ratio = 0;
  center = 0;
  complete = false;
  private allowed = false;
  private epoch = 0;
  private animations: Animation[] = [];
  private specs: MotionSpec[] = [];
  private phase: 'idle' | 'playing' | 'resetting' = 'idle';
  private width: number;
  private resize: ResizeObserver;

  constructor(readonly root: HTMLElement, private changed: () => void, replay: () => void) {
    this.stage = root.querySelector<HTMLElement>('.workspace-scene')!;
    this.button = root.querySelector<HTMLButtonElement>('.scene-replay')!;
    this.button.addEventListener('click', replay);
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
    if (this.complete) return;
    if (active && this.phase === 'idle') { void this.play(); return; }
    for (const animation of this.animations) active ? animation.play() : animation.pause();
    this.root.dataset.motionState = this.phase === 'idle' ? 'idle' : active ? this.phase : 'paused';
  }

  async play(replay = false) {
    const epoch = ++this.epoch;
    this.complete = false;
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
    if (!staticFrame) {
      this.specs = storyboard(this.root).specs;
      for (const { element, end } of this.specs) Object.assign(element.style, end);
    }
    this.complete = true;
    this.phase = 'idle';
    this.root.dataset.motionState = 'complete';
    this.button.hidden = staticFrame;
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
  if (!('animate' in HTMLElement.prototype)) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const roots = [...document.querySelectorAll<HTMLElement>('[data-motion]')];
  let active: Scene | undefined;
  const scenes = roots.map(root => new Scene(root, reconcile, () => {
    if (reduced.matches) return;
    active?.setActive(false);
    active = scenes.find(scene => scene.root === root)!;
    active.setActive(false);
    void active.play(true);
    reconcile();
  }));

  function reconcile() {
    const eligible = (scene: Scene) => !reduced.matches && !document.hidden && scene.ratio >= Math.min(.5, innerHeight / scene.root.offsetHeight / 2) && !scene.complete;
    if (!active || !eligible(active)) active = scenes.filter(eligible).sort((a, b) => b.ratio - a.ratio || a.center - b.center)[0];
    for (const scene of scenes) scene.setActive(scene === active);
  }

  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      const scene = scenes.find(scene => scene.root === entry.target)!;
      scene.ratio = entry.intersectionRatio;
      scene.center = Math.abs(entry.boundingClientRect.top + entry.boundingClientRect.height / 2 - innerHeight / 2);
    }
    reconcile();
  }, { threshold: Array.from({ length: 21 }, (_, index) => index / 20) });
  for (const scene of scenes) observer.observe(scene.root);

  function preferenceChanged() {
    for (const scene of scenes) scene.finish(true);
    if (!reduced.matches) for (const scene of scenes) scene.button.hidden = false;
    reconcile();
  }
  // Initial static presentation needs no timeline, including the finished vertical stack.
  if (reduced.matches) preferenceChanged();
  reduced.addEventListener('change', preferenceChanged);
  document.addEventListener('visibilitychange', reconcile);
  window.addEventListener('pageshow', reconcile);
  window.addEventListener('pagehide', event => {
    if (event.persisted) { scenes.forEach(scene => scene.setActive(false)); return; }
    observer.disconnect();
    scenes.forEach(scene => scene.destroy());
    reduced.removeEventListener('change', preferenceChanged);
    document.removeEventListener('visibilitychange', reconcile);
    window.removeEventListener('pageshow', reconcile);
  });
}

mount();
