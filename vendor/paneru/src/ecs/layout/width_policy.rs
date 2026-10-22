//! Optional expansion of fitting strips. Preferred widths survive derived fill sizes.
use bevy::prelude::*;

use super::{Column, DisplayViewports, LayoutStrip};
use crate::config::Config;
use crate::ecs::{Bounds, FocusedMarker, ResizeMarker, SpawnCommandsExt};
use crate::manager::Window;

#[derive(Component, Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct PreferredWidth {
    pub width: i32,
    applied: i32,
    viewport: i32,
}

impl PreferredWidth {
    fn updated(self, target: i32, viewport: i32) -> Self {
        // An explicit resize is new intent. Animation frames use the same target
        // as `applied`, so they cannot become preferred widths on the next tick.
        let width = if (target - self.applied).abs() > 2 {
            target
        } else if self.viewport != viewport {
            i32::try_from(
                ((i64::from(self.width) * i64::from(viewport)) / i64::from(self.viewport.max(1)))
                    .clamp(1, i64::from(i32::MAX)),
            )
            .unwrap_or(i32::MAX)
        } else {
            self.width
        };
        Self {
            width,
            viewport,
            ..self
        }
    }
}

type WidthWindows<'w, 's> = Query<
    'w,
    's,
    (
        Entity,
        &'static Bounds,
        Option<&'static ResizeMarker>,
        Option<&'static PreferredWidth>,
    ),
    With<Window>,
>;

/// Cumulative integer apportionment consumes every spare point without rounding
/// gaps. Oversized strips are never squeezed; their normal scrolling is retained.
fn expanded_widths(preferred: &[i32], available: i32) -> Vec<i32> {
    let total: i64 = preferred.iter().map(|w| i64::from(*w)).sum();
    if total <= 0 || total >= i64::from(available) || preferred.iter().any(|w| *w <= 0) {
        return preferred.to_vec();
    }
    let mut sum = 0_i64;
    let mut previous = 0;
    preferred
        .iter()
        .map(|width| {
            sum += i64::from(*width);
            let edge = i32::try_from(sum * i64::from(available) / total).unwrap_or(available);
            let result = edge - previous;
            previous = edge;
            result
        })
        .collect()
}

pub(super) fn strip_fits(
    strip: &LayoutStrip,
    windows: &crate::ecs::params::Windows,
    available: i32,
) -> bool {
    strip
        .all_columns()
        .iter()
        .filter_map(|entity| windows.moving_frame(*entity))
        .map(|frame| i64::from(frame.width()))
        .sum::<i64>()
        <= i64::from(available)
}

pub(super) fn apply_width_policy(
    strips: Query<(&LayoutStrip, &ChildOf)>,
    displays: DisplayViewports,
    windows: WidthWindows,
    focused: Query<Entity, With<FocusedMarker>>,
    config: Res<Config>,
    mut commands: Commands,
) {
    let mut managed = std::collections::HashSet::new();
    if config.fill_available_width() {
        for (strip, parent) in &strips {
            let Ok((display, dock)) = displays.get(parent.parent()) else {
                continue;
            };
            let available = display.actual_display_bounds(dock, &config).width();
            if available <= 0 || strip.columns().any(|c| matches!(c, Column::Fullscren(_))) {
                continue;
            }
            let columns = strip.columns().collect::<Vec<_>>();
            let preferred = columns
                .iter()
                .map(|column| {
                    let (_, bounds, resize, stored) = windows.get(column.top()?).ok()?;
                    let target = resize.map_or(bounds.0.x, |r| r.0.x);
                    Some(
                        stored
                            .copied()
                            .unwrap_or(PreferredWidth {
                                width: target,
                                applied: target,
                                viewport: available,
                            })
                            .updated(target, available),
                    )
                })
                .collect::<Option<Vec<_>>>();
            let Some(preferred) = preferred else { continue };
            let anchor = focused
                .iter()
                .find(|entity| strip.contains(*entity))
                .or_else(|| columns.first().and_then(|column| column.top()));
            let mut changed = false;
            let widths = expanded_widths(
                &preferred.iter().map(|p| p.width).collect::<Vec<_>>(),
                available,
            );
            for ((column, preferred), width) in columns.into_iter().zip(preferred).zip(widths) {
                for entity in column.window_iter() {
                    let Ok((_, bounds, resize, stored)) = windows.get(entity) else {
                        continue;
                    };
                    managed.insert(entity);
                    let target = resize.map_or(bounds.0, |r| r.0);
                    let next = PreferredWidth {
                        applied: width,
                        ..preferred
                    };
                    if stored != Some(&next) {
                        commands.entity(entity).insert(next);
                    }
                    if target.x != width {
                        commands.resize_entity(entity, target.with_x(width));
                        changed = true;
                    }
                }
            }
            if changed && let Some(anchor) = anchor {
                commands.reshuffle_around(anchor);
            }
        }
    }
    // Disabling fill, floating a window, or leaving the tiled strip restores its
    // actual preferred size, even if the previous expansion was still animating.
    for (entity, bounds, resize, stored) in &windows {
        if !managed.contains(&entity)
            && let Some(preferred) = stored
        {
            let target = resize.map_or(bounds.0, |r| r.0);
            if target.x != preferred.width {
                commands.resize_entity(entity, target.with_x(preferred.width));
            }
            commands.entity(entity).remove::<PreferredWidth>();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fill_keeps_proportions_and_consumes_rounding_remainder() {
        assert_eq!(expanded_widths(&[300, 600], 1001), [333, 668]);
        assert_eq!(expanded_widths(&[300], 1001), [1001]);
        assert_eq!(
            expanded_widths(&[300, 300, 300], 1001).iter().sum::<i32>(),
            1001
        );
    }

    #[test]
    fn overflow_and_exact_fit_preserve_widths() {
        assert_eq!(expanded_widths(&[600, 600], 1000), [600, 600]);
        assert_eq!(expanded_widths(&[500, 500], 1000), [500, 500]);
        assert!(expanded_widths(&[], 1000).is_empty());
    }

    #[test]
    fn animation_does_not_overwrite_preference_and_display_changes_scale_it() {
        let stored = PreferredWidth {
            width: 300,
            applied: 1000,
            viewport: 1000,
        };
        assert_eq!(stored.updated(1000, 1000).width, 300);
        assert_eq!(stored.updated(1000, 1500).width, 450);
        assert_eq!(stored.updated(700, 1000).width, 700);
    }
}
