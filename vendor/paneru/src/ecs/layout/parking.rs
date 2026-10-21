//! Keep parked columns out of neighboring physical displays.
use crate::config::Config;
use bevy::prelude::{Component, IRect, IVec2};

#[derive(Component)]
pub(super) struct AdjacentDisplayParked;

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

#[cfg(test)]
mod tests {
    use super::*;

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
