//! Opt-in display callbacks. Owns timing only, never layout or window state.
use std::cell::Cell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;
use std::sync::{Arc, LazyLock};
use std::time::{Duration, Instant};

use objc2::rc::Retained;
use objc2::{DefinedClass, MainThreadMarker, MainThreadOnly, define_class, msg_send, sel};
use objc2_app_kit::NSScreen;
use objc2_foundation::{NSDefaultRunLoopMode, NSNumber, NSObject, NSRunLoop, NSString};
use objc2_quartz_core::{CADisplayLink, CAFrameRateRange};

use super::EventLoopWaker;

pub(crate) fn enabled() -> bool {
    static ENABLED: LazyLock<bool> = LazyLock::new(|| {
        std::env::var("RIBBON_ANIMATION_CLOCK").is_ok_and(|v| v == "display-link")
    });
    *ENABLED
}

struct TickIvars {
    display: u32,
    pending: Rc<Cell<bool>>,
    waker: Arc<EventLoopWaker>,
}

define_class!(
    // SAFETY: NSObject has no subclass requirements; callbacks and ivars are
    // confined to the main thread and the selector has the declared signature.
    #[unsafe(super(NSObject))]
    #[thread_kind = MainThreadOnly]
    #[name = "RibbonAnimationTick"]
    #[ivars = TickIvars]
    struct TickTarget;

    impl TickTarget {
        #[unsafe(method(animationFrame:))]
        fn frame(&self, _: &CADisplayLink) {
            self.ivars().pending.set(true);
            crate::performance::display_tick(self.ivars().display, false);
            self.ivars().waker.wake();
        }
    }
);

/// A lost callback must not freeze motion. This deadline is a watchdog while a
/// display link exists, and an absolute per-owner timer if it cannot be created.
struct Deadline {
    interval: Duration,
    next: Instant,
}

impl Deadline {
    fn new(interval: f64, now: Instant) -> Self {
        let interval = Duration::from_secs_f64(interval.clamp(1.0 / 240.0, 1.0 / 30.0));
        Self {
            interval,
            next: now + interval,
        }
    }

    fn consume(&mut self, signalled: bool, linked: bool, now: Instant) -> bool {
        if signalled {
            self.next = now + self.interval * 2;
            true
        } else if now >= self.next {
            // Skip missed periods; never generate a burst of catch-up writes.
            let periods = now.duration_since(self.next).as_nanos() / self.interval.as_nanos() + 1;
            self.next += self.interval * u32::try_from(periods).unwrap_or(u32::MAX);
            if linked {
                self.next = now + self.interval * 2;
            }
            true
        } else {
            false
        }
    }
}

struct DisplayClock {
    display: u32,
    link: Option<Retained<CADisplayLink>>,
    pending: Rc<Cell<bool>>,
    deadline: Deadline,
}

impl Drop for DisplayClock {
    fn drop(&mut self) {
        if let Some(link) = &self.link {
            link.invalidate();
        }
        crate::performance::display_stopped(self.display);
    }
}

pub(super) struct DisplayLinks {
    clocks: HashMap<u32, DisplayClock>,
    waker: Arc<EventLoopWaker>,
    marker: MainThreadMarker,
}

impl DisplayLinks {
    pub(super) fn new(waker: Arc<EventLoopWaker>, marker: MainThreadMarker) -> Self {
        Self {
            clocks: HashMap::new(),
            waker,
            marker,
        }
    }

    pub(super) fn configure(&mut self, displays: &[(u32, f64)]) {
        self.clocks.retain(|id, clock| {
            displays.iter().any(|(wanted, interval)| {
                *wanted == *id
                    && (clock.deadline.interval.as_secs_f64() - interval).abs() < 0.000_001
            })
        });
        if displays.iter().all(|(id, _)| self.clocks.contains_key(id)) {
            return;
        }
        // Topology is queried only when a clock is added/replaced, never on a tick.
        let screens = NSScreen::screens(self.marker);
        for &(id, interval) in displays {
            if self.clocks.contains_key(&id) {
                continue;
            }
            let pending = Rc::new(Cell::new(false));
            let screen = screens.iter().find(|screen| {
                screen
                    .deviceDescription()
                    .objectForKey(&NSString::from_str("NSScreenNumber"))
                    .and_then(|value| value.downcast::<NSNumber>().ok())
                    .is_some_and(|number| number.unsignedIntValue() == id)
            });
            let link = screen.map(|screen| self.make_link(&screen, id, interval, &pending));
            self.clocks.insert(
                id,
                DisplayClock {
                    display: id,
                    link,
                    pending,
                    deadline: Deadline::new(interval, Instant::now()),
                },
            );
        }
    }

    fn make_link(
        &self,
        screen: &NSScreen,
        display: u32,
        interval: f64,
        pending: &Rc<Cell<bool>>,
    ) -> Retained<CADisplayLink> {
        let allocated = TickTarget::alloc(self.marker).set_ivars(TickIvars {
            display,
            pending: pending.clone(),
            waker: self.waker.clone(),
        });
        let target: Retained<TickTarget> = unsafe { msg_send![super(allocated), init] };
        // SAFETY: target/selector signature matches TickTarget::frame. AppKit
        // retains the target until invalidate; all access remains main-thread.
        let link = unsafe { screen.displayLinkWithTarget_selector(&target, sel!(animationFrame:)) };
        // Respect the owner's selected mode as well as the screen's ceiling.
        // The requested cadence is bounded to the cached 30–240 Hz range.
        #[allow(clippy::cast_precision_loss, clippy::cast_possible_truncation)]
        let hz = (1.0 / interval).min(screen.maximumFramesPerSecond() as f64) as f32;
        link.setPreferredFrameRateRange(CAFrameRateRange {
            minimum: hz,
            maximum: hz,
            preferred: hz,
        });
        // SAFETY: register on this main thread's default runloop, which the
        // existing Cocoa pump services. No foreign-app events are posted.
        unsafe { link.addToRunLoop_forMode(&NSRunLoop::mainRunLoop(), NSDefaultRunLoopMode) };
        link
    }

    pub(super) fn wait(&self, otherwise: f64) -> f64 {
        let now = Instant::now();
        self.clocks
            .values()
            .map(|clock| {
                clock
                    .deadline
                    .next
                    .saturating_duration_since(now)
                    .as_secs_f64()
            })
            .reduce(f64::min)
            .unwrap_or(otherwise)
    }

    pub(super) fn take_due(&mut self) -> HashSet<u32> {
        let now = Instant::now();
        self.clocks
            .iter_mut()
            .filter_map(|(id, clock)| {
                clock
                    .deadline
                    .consume(clock.pending.replace(false), clock.link.is_some(), now)
                    .then(|| {
                        crate::performance::display_tick(*id, true);
                        *id
                    })
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_does_not_restart_the_deadline_and_stalls_do_not_catch_up() {
        let start = Instant::now();
        let mut deadline = Deadline::new(1.0 / 120.0, start);
        for ms in 0..8 {
            assert!(!deadline.consume(false, false, start + Duration::from_millis(ms)));
        }
        assert!(deadline.consume(false, false, start + Duration::from_millis(9)));
        assert!(!deadline.consume(false, false, start + Duration::from_millis(10)));
        assert!(deadline.consume(false, false, start + Duration::from_secs(10)));
        assert!(!deadline.consume(false, false, start + Duration::from_secs(10)));
        assert!(deadline.next > start + Duration::from_secs(10));
    }

    #[test]
    fn callbacks_bypass_elapsed_phase_but_missing_callbacks_have_a_watchdog() {
        let start = Instant::now();
        let mut deadline = Deadline::new(1.0 / 60.0, start);
        let tick = start + Duration::from_millis(15);
        assert!(deadline.consume(true, true, tick));
        assert!(deadline.consume(true, true, tick + Duration::from_millis(16)));
        assert!(!deadline.consume(false, true, tick + Duration::from_millis(40)));
        assert!(deadline.consume(false, true, tick + Duration::from_millis(50)));
    }
}
