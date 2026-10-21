//! Ribbon's application boundary and owned-helper lifetime. Missing scope is demo-only.
use std::collections::HashSet;
use std::sync::LazyLock;
use std::time::Duration;

use bevy::math::{IRect, IVec2};

use crate::events::{Event, EventSender};

pub const FIXTURE_BUNDLE: &str = "dev.ribbon.fixture";
const EXCLUDED_BUNDLES: [&str; 2] = ["dev.ribbon.app", "com.apple.systempreferences"];

#[derive(Debug)]
pub struct ApplicationScope(HashSet<String>);

impl ApplicationScope {
    fn parse(value: Option<&str>) -> Self {
        let value = value.unwrap_or(FIXTURE_BUNDLE);
        let ids = value.split(',').map(str::trim).collect::<Vec<_>>();
        if ids.is_empty()
            || ids.iter().any(|id| {
                id.is_empty()
                    || !id.contains('.')
                    || !id
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b".-".contains(&b))
            })
        {
            return Self(HashSet::new());
        }
        Self(ids.into_iter().map(str::to_string).collect())
    }

    fn allows(&self, bundle: &str) -> bool {
        !EXCLUDED_BUNDLES.contains(&bundle) && self.0.contains(bundle)
    }
}

static SCOPE: LazyLock<ApplicationScope> =
    LazyLock::new(|| ApplicationScope::parse(std::env::var("RIBBON_MANAGED_APPS").ok().as_deref()));

pub fn allows_bundle(bundle: &str) -> bool {
    SCOPE.allows(bundle)
}

/// A dead GUI must not leave a detached window manager intercepting input.
pub fn watch_parent(sender: EventSender) {
    let Some(parent) = std::env::var("RIBBON_PARENT_PID")
        .ok()
        .and_then(|value| value.parse::<u32>().ok())
        .filter(|pid| *pid > 1)
    else {
        return;
    };
    std::thread::spawn(move || {
        loop {
            // getppid has no memory or threading preconditions.
            let current = unsafe { libc::getppid() };
            if u32::try_from(current).ok() != Some(parent) {
                let _ = sender.send(Event::Exit);
                break;
            }
            std::thread::sleep(Duration::from_millis(250));
        }
    });
}

/// Retain the original placement when its display is present; fit it safely otherwise.
pub fn restoration_frame(original: IRect, displays: &[IRect]) -> Option<IRect> {
    let display = displays
        .iter()
        .filter(|display| display.min.cmplt(display.max).all())
        .find(|display| display.contains(original.center()))
        .or_else(|| {
            displays
                .iter()
                .find(|display| display.min.cmplt(display.max).all())
        })?;
    let size = original
        .size()
        .clamp(IVec2::ONE, display.size().max(IVec2::ONE));
    let origin = original.min.clamp(display.min, display.max - size);
    Some(IRect::from_corners(origin, origin + size))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_scope_only_allows_fixture() {
        let scope = ApplicationScope::parse(None);
        assert!(scope.allows(FIXTURE_BUNDLE));
        assert!(!scope.allows("com.apple.Safari"));
    }

    #[test]
    fn invalid_scope_fails_closed_instead_of_expanding() {
        for invalid in ["", "*", "com.apple.Safari,", "com.apple.Safari;other"] {
            let scope = ApplicationScope::parse(Some(invalid));
            assert!(!scope.allows(FIXTURE_BUNDLE));
            assert!(!scope.allows("com.apple.Safari"));
        }
    }

    #[test]
    fn explicit_scope_is_exact_and_excludes_our_settings() {
        let scope = ApplicationScope::parse(Some("com.apple.Safari, dev.ribbon.app"));
        assert!(scope.allows("com.apple.Safari"));
        assert!(!scope.allows("com.apple.Safari.Other"));
        assert!(!scope.allows("dev.ribbon.app"));
    }

    #[test]
    fn original_frame_survives_and_disconnected_display_is_recovered() {
        let display = IRect::new(0, 0, 1440, 900);
        let original = IRect::new(100, 120, 900, 720);
        assert_eq!(restoration_frame(original, &[display]), Some(original));
        let disconnected = IRect::new(2200, 120, 4000, 1200);
        let restored = restoration_frame(disconnected, &[display]).unwrap();
        assert!(display.contains(restored.min));
        assert!(restored.max.x <= display.max.x && restored.max.y <= display.max.y);
        assert_eq!(restoration_frame(original, &[]), None);
        assert_eq!(restoration_frame(original, &[IRect::EMPTY]), None);
        let left = IRect::new(-1728, 323, 0, 1440);
        let on_left = IRect::new(-1600, 400, -800, 1000);
        assert_eq!(restoration_frame(on_left, &[display, left]), Some(on_left));
    }
}
