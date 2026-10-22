//! Keep parked columns out of neighboring physical displays.
use crate::config::Config;
use bevy::prelude::{Commands, Component, Entity, IRect, IVec2};

#[derive(Component)]
pub(super) struct AdjacentDisplayParked;

/// Presentation only: native geometry must not migrate the logical tile.
#[derive(Component)]
pub(crate) struct CompactParked {
    pub size_limit: IVec2,
}

/// One native commit fence: make room before a parked body returns to view.
#[derive(Component)]
pub(crate) struct NativeReveal;

/// A clipped native presentation. The strip retains the full logical width.
#[derive(Component, Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct EdgePresentation {
    pub frame: IRect,
    pub fallback: ParkedGeometry,
}

/// Learned from an AX resize rejection, so a narrow edge is not retried each frame.
#[derive(Component)]
pub(crate) struct NativeMinimumWidth(pub i32);

/// Foreign windows cannot be masked at a display seam. Fit their native body
/// into the visible slot while leaving strip packing and preferred widths alone.
pub(super) fn visible_edge_frame(
    frame: IRect,
    viewport: IRect,
    minimum_width: i32,
) -> Option<IRect> {
    let mut visible = frame;
    visible.min.x = frame.min.x.max(viewport.min.x);
    visible.max.x = frame.max.x.min(viewport.max.x);
    (visible.width() >= minimum_width.max(200)).then_some(visible)
}

pub(super) fn update_legacy_parking_state(
    commands: &mut Commands,
    entity: Entity,
    parked: bool,
    was_parked: bool,
) {
    if parked == was_parked {
        return;
    }
    if parked {
        commands.entity(entity).try_insert(AdjacentDisplayParked);
    } else {
        commands
            .entity(entity)
            .try_remove::<AdjacentDisplayParked>();
    }
}

pub(super) fn update_parking_state(
    commands: &mut Commands,
    entity: Entity,
    size_limit: Option<IVec2>,
    was_parked: bool,
) {
    if let Some(size_limit) = size_limit {
        commands
            .entity(entity)
            .try_insert(CompactParked { size_limit });
        if !was_parked {
            commands
                .entity(entity)
                .try_insert(crate::ecs::VerifyWindowPosition::default());
        }
    } else {
        commands.entity(entity).try_remove::<CompactParked>();
    }
}

#[derive(Clone, Copy)]
pub(super) struct ParkingDisplay {
    pub bounds: IRect,
    pub viewport: IRect,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ParkedGeometry {
    pub frame: IRect,
    pub size_limit: IVec2,
}

pub(super) struct CompactPresentation {
    pub frame: IRect,
    pub edge: Option<EdgePresentation>,
    pub parking_limit: Option<IVec2>,
}

/// Update presentation markers only when their meaning changes. Return whether
/// native size needs restoring even though the logical Bounds did not change.
pub(super) fn update_native_presentation(
    commands: &mut Commands,
    entity: Entity,
    presentation: &CompactPresentation,
    previous_edge: Option<EdgePresentation>,
    was_parked: bool,
) -> bool {
    if presentation.edge != previous_edge {
        if let Some(edge) = presentation.edge {
            commands.entity(entity).try_insert(edge);
        } else {
            commands.entity(entity).try_remove::<EdgePresentation>();
        }
    }
    if was_parked && presentation.parking_limit.is_none() {
        commands.entity(entity).try_insert(NativeReveal);
    }
    update_parking_state(commands, entity, presentation.parking_limit, was_parked);
    presentation.parking_limit.is_none()
        && (was_parked || previous_edge.is_some() && presentation.edge.is_none())
}

pub(super) fn compact_presentation(
    frame: IRect,
    viewport: IRect,
    owner: IRect,
    displays: &[ParkingDisplay],
    padding: IVec2,
    state: (bool, bool),
    minimum_width: i32,
) -> CompactPresentation {
    let (focused, hidden_workspace) = state;
    let fallback = compact_parking(frame.size(), owner, displays, padding);
    let hidden = hidden_workspace
        || frame.max.x <= viewport.min.x + padding.x
        || frame.min.x >= viewport.max.x - padding.x;
    let oversized_focus = focused && frame.width() > viewport.width();
    let edge = (!hidden
        && !oversized_focus
        && (frame.min.x + padding.x < owner.min.x || frame.max.x - padding.x > owner.max.x))
        .then(|| visible_edge_frame(frame, viewport, minimum_width))
        .flatten()
        .map(|frame| EdgePresentation { frame, fallback });
    let connected: Vec<_> = displays.iter().map(|d| d.bounds).collect();
    let parked = hidden
        || (!oversized_focus
            && edge.is_none()
            && (visible_edge_frame(frame, viewport, minimum_width).is_none()
                || should_park_at_seam(frame, viewport, owner, &connected, padding, focused)));
    CompactPresentation {
        frame: if parked {
            fallback.frame
        } else {
            edge.map_or(frame, |e| e.frame)
        },
        edge: (!parked).then_some(edge).flatten(),
        parking_limit: parked.then_some(fallback.size_limit),
    }
}

/// Keep only a one-point right edge in the desktop. Left-edge `AppKit` parking
/// is constrained to a much wider titlebar remnant. Prefer the owning display,
/// but use an outer display edge when its right corner borders another screen.
/// Native parking does not change strip ownership or logical window size.
pub(super) fn compact_parking(
    size: IVec2,
    owner: IRect,
    displays: &[ParkingDisplay],
    padding: IVec2,
) -> ParkedGeometry {
    let native_size = (size - padding * 2).max(IVec2::ONE);
    displays
        .iter()
        .map(|display| {
            // AppKit keeps at least a titlebar-height band vertically reachable.
            // Request that stable band directly instead of repeatedly fighting it.
            let origin = IVec2::new(display.bounds.max.x - 1, display.viewport.max.y - 32);
            let native = IRect::from_corners(origin, origin + native_size);
            let spill = displays
                .iter()
                .filter(|other| other.bounds != display.bounds)
                .map(|other| intersection_area(native, other.bounds))
                .sum::<i64>();
            let key = (
                spill,
                display.bounds != owner,
                -i64::from(display.bounds.max.x),
                -i64::from(display.viewport.max.y),
            );
            (key, origin - padding, display.viewport.size() + padding * 2)
        })
        .min_by_key(|(key, _, _)| *key)
        .map_or_else(
            || ParkedGeometry {
                frame: IRect::from_corners(owner.min, owner.min + size),
                size_limit: size,
            },
            |(_, origin, size_limit)| ParkedGeometry {
                frame: IRect::from_corners(origin, origin + size),
                size_limit,
            },
        )
}

/// Park at the strip's left or right edge, accounting for physical frame gaps.
pub(super) fn horizontal_parking(
    mut frame: IRect,
    viewport: IRect,
    h_pad: i32,
    config: &Config,
) -> (IRect, bool) {
    let width = frame.width();
    let (_, pad_right, _, pad_left) = config.edge_padding();
    let sliver = config.sliver_width();
    let mut offscreen = false;
    if frame.max.x <= viewport.min.x + h_pad {
        frame.min.x = viewport.min.x - width + sliver - pad_left + h_pad;
        offscreen = true;
    } else if frame.min.x >= viewport.max.x - h_pad {
        frame.min.x = viewport.max.x - sliver + pad_right - h_pad;
        offscreen = true;
    }
    frame.max.x = frame.min.x + width;
    (frame, offscreen)
}

/// AX cannot clip foreign windows at an interior monitor seam. Park before
/// their native body (including a small rounding guard) enters a neighbor.
pub(super) fn crosses_display_seam(
    frame: IRect,
    owner: IRect,
    displays: &[IRect],
    padding: IVec2,
) -> bool {
    let native = IRect::from_corners(
        frame.min + padding - IVec2::splat(2),
        frame.max - padding + IVec2::splat(2),
    );
    displays
        .iter()
        .any(|other| *other != owner && intersection_area(native, *other) > 0)
}

/// App minimum sizes can exceed a monitor. Keep a visible focused tile
/// reachable instead of parking it again whenever the user activates it.
pub(super) fn should_park_at_seam(
    frame: IRect,
    viewport: IRect,
    owner: IRect,
    displays: &[IRect],
    padding: IVec2,
    focused: bool,
) -> bool {
    !(focused && frame.size().cmpgt(viewport.size()).any())
        && crosses_display_seam(frame, owner, displays, padding)
}

fn intersection_area(a: IRect, b: IRect) -> i64 {
    let size = (a.max.min(b.max) - a.min.max(b.min)).max(IVec2::ZERO);
    i64::from(size.x) * i64::from(size.y)
}

/// macOS adopts a window when most of its frame lands on another display.
/// Prefer the normal strip edge, then a free outer edge. Preserve size and
/// leave a sliver on the owning screen so it remains reachable and assigned.
pub(super) fn anchored_parking(
    frame: IRect,
    owner: IRect,
    displays: &[IRect],
    offscreen: bool,
    sliver: i32,
) -> IRect {
    let overlap = |candidate| {
        displays
            .iter()
            .filter(|display| **display != owner)
            .map(|display| intersection_area(candidate, *display))
            .sum::<i64>()
    };
    let neighboring_area = overlap(frame);
    if neighboring_area == 0 || !offscreen && neighboring_area <= intersection_area(frame, owner) {
        return frame;
    }
    let size = frame.size();
    let inside_x = frame
        .min
        .x
        .clamp(owner.min.x, (owner.max.x - size.x).max(owner.min.x));
    let candidates = [
        IVec2::new(owner.min.x - size.x + sliver, frame.min.y),
        IVec2::new(owner.max.x - sliver, frame.min.y),
        IVec2::new(inside_x, owner.max.y - sliver),
        IVec2::new(inside_x, owner.min.y - size.y + sliver),
    ];
    candidates
        .into_iter()
        .map(|origin| IRect::from_corners(origin, origin + size))
        .min_by_key(|candidate| overlap(*candidate))
        .filter(|candidate| overlap(*candidate) < neighboring_area)
        .unwrap_or(frame)
}

/// Compatibility presentation for upstream configurations that retain slivers.
pub(super) fn legacy_parking(
    frame: IRect,
    viewport: IRect,
    owner: IRect,
    displays: &[IRect],
    config: &Config,
    h_pad: i32,
    motion: (bool, bool),
) -> (IRect, bool) {
    let (mut frame, mut offscreen) = horizontal_parking(frame, viewport, h_pad, config);

    let anchored = anchored_parking(frame, owner, displays, offscreen, config.sliver_width());
    let rerouted = anchored != frame;
    frame = anchored;
    offscreen |= rerouted;
    // During swipe, keep full height. The vertical sliver inset only
    // applies to horizontally off-screen windows, so they expose just
    // a `sliver_height` fraction of their height at the viewport's
    // vertical center.
    if !motion.0 && offscreen {
        // Don't compress stacked windows vertically when off-screen.
        // The height reduction corrupts their proportions: when the
        // column scrolls back on-screen, binpack_heights makes the
        // last window absorb all remaining space.
        if !motion.1 {
            let inset = crate::util::round_px(
                f64::from(viewport.height()) * (1.0 - config.sliver_height()) / 2.0,
            );
            frame.min.y += inset;
            frame.max.y += inset;
        }
    }

    // Keep the window anchored to its own display. The parked strip origin
    // only accounts for the first window: everything sitting below it in a
    // stack picks up that offset on top of the corner and lands past the
    // bottom edge, fully inside the display underneath. macOS then adopts
    // the window onto that display, and showing the workspace again brings
    // it back there instead of here. Park those at the corner as well.
    let park_row = viewport.max.y - super::PARKED_STRIP_SLIVER;
    if frame.min.y > park_row {
        let height = frame.height();
        frame.min.y = park_row;
        frame.max.y = park_row + height;
    }

    (frame, rerouted)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_tile_parks_before_crossing_an_interior_monitor_seam() {
        let left = IRect::new(0, 0, 2560, 1440);
        let right = IRect::new(2560, 323, 4288, 1440);
        assert!(crosses_display_seam(
            IRect::new(2300, 42, 2872, 1331),
            left,
            &[left, right],
            IVec2::splat(6)
        ));
        assert!(!crosses_display_seam(
            IRect::new(1982, 42, 2554, 1331),
            left,
            &[left, right],
            IVec2::splat(6)
        ));
    }

    #[test]
    fn compact_parking_uses_outer_edge_without_changing_size() {
        let main = ParkingDisplay {
            bounds: IRect::new(0, 0, 2560, 1440),
            viewport: IRect::new(0, 30, 2560, 1331),
        };
        let laptop = ParkingDisplay {
            bounds: IRect::new(2560, 323, 4288, 1440),
            viewport: IRect::new(2560, 356, 4288, 1440),
        };
        let size = IVec2::new(572, 1313);
        let padding = IVec2::splat(6);
        for owner in [main, laptop] {
            let parked = compact_parking(size, owner.bounds, &[main, laptop], padding).frame;
            assert_eq!(parked.min, IVec2::new(4281, 1402));
            assert_eq!(parked.size(), size);
            let native = IRect::from_corners(parked.min + padding, parked.max - padding);
            assert_eq!(intersection_area(native, main.bounds), 0);
            assert_eq!(intersection_area(native, laptop.viewport), 32);
        }
    }

    #[test]
    fn compact_parking_is_stable_for_offsets_and_display_order() {
        let upper = ParkingDisplay {
            bounds: IRect::new(-1200, -900, 0, 0),
            viewport: IRect::new(-1200, -870, 0, 0),
        };
        let lower = ParkingDisplay {
            bounds: IRect::new(-1200, 0, 0, 900),
            viewport: IRect::new(-1200, 30, 0, 850),
        };
        let size = IVec2::new(800, 600);
        let a = compact_parking(size, upper.bounds, &[upper, lower], IVec2::ZERO);
        let b = compact_parking(size, upper.bounds, &[lower, upper], IVec2::ZERO);
        assert_eq!(a, b);
        assert_eq!(a.frame.min, IVec2::new(-1, 818));
        assert_eq!(intersection_area(a.frame, upper.bounds), 0);
    }

    #[test]
    fn shared_edge_parks_on_the_free_outer_edge() {
        let main = IRect::new(0, 30, 2560, 1440);
        let laptop = IRect::new(2560, 356, 4288, 1440);
        let frame = IRect::new(2555, 356, 3115, 1440);
        let parked = anchored_parking(frame, main, &[main, laptop], true, 5);
        assert_eq!(parked.min.x, -555);
        assert_eq!(parked.size(), frame.size());
        assert_eq!(intersection_area(parked, laptop), 0);
        assert!(intersection_area(parked, main) > 0);

        let frame = IRect::new(2005, 356, 2565, 1416);
        let parked = anchored_parking(frame, laptop, &[main, laptop], true, 5);
        assert_eq!(parked.min.x, 4283);
        assert_eq!(intersection_area(parked, main), 0);
        assert!(intersection_area(parked, laptop) > 0);
    }

    #[test]
    fn partial_columns_cannot_become_owned_by_the_neighbor() {
        let left = IRect::new(-2560, 0, 0, 1440);
        let right = IRect::new(0, 323, 1728, 1440);
        let mostly_right = IRect::new(-100, 400, 460, 1300);
        let parked = anchored_parking(mostly_right, left, &[left, right], false, 5);
        assert_eq!(intersection_area(parked, right), 0);
        let mostly_left = IRect::new(-500, 400, 60, 1300);
        assert_eq!(
            anchored_parking(mostly_left, left, &[left, right], false, 5),
            mostly_left
        );
    }

    #[test]
    fn unshared_edges_and_vertical_displays_keep_existing_positions() {
        let main = IRect::new(0, 0, 2560, 1440);
        let above = IRect::new(0, -1117, 1728, 0);
        let frame = IRect::new(2555, 30, 3115, 1300);
        assert_eq!(anchored_parking(frame, main, &[main], true, 5), frame);
        assert_eq!(
            anchored_parking(frame, main, &[main, above], true, 5),
            frame
        );
    }
}
