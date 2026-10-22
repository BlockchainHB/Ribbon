//! Window-addressed pairing, shared by shortcuts and the native overview.
use bevy::prelude::*;

use super::{Command, Direction, MoveFocus, OffscreenStrips, Operation};
use crate::config::Config;
use crate::ecs::ActiveDisplayMarker;
use crate::ecs::layout::LayoutStrip;
use crate::ecs::params::ActiveDisplayMut;
use crate::ecs::params::Windows;
use crate::ecs::{ActiveWorkspaceMarker, DockPosition, SelectedVirtualMarker, SpawnCommandsExt};
use crate::events::Event;
use crate::manager::Display;
use crate::manager::WindowManager;
use crate::util::round_px;
use bevy::ecs::entity::EntityHashSet;
use bevy::ecs::system::SystemParam;

pub(super) fn register(app: &mut App) {
    app.add_systems(PreUpdate, handle.in_set(crate::ecs::PreUpdateSet::Dispatch));
}

type PairStrips<'w, 's> = Query<
    'w,
    's,
    (
        &'static mut LayoutStrip,
        Entity,
        &'static ChildOf,
        Has<ActiveWorkspaceMarker>,
        Has<SelectedVirtualMarker>,
    ),
>;

fn handle(
    mut events: MessageReader<Event>,
    windows: Windows,
    mut strips: PairStrips,
    displays: Query<(&Display, Option<&DockPosition>)>,
    config: Res<Config>,
    mut commands: Commands,
) {
    for event in events.read() {
        let Event::Command {
            command: Command::Window(op),
        } = event
        else {
            continue;
        };
        let addressed = match op {
            Operation::PairId { window, .. }
            | Operation::PairFitId { window, .. }
            | Operation::UnpairId(window) => windows.find(*window).map(|(_, e)| e),
            _ => windows.focused().map(|(_, e)| e),
        };
        let Some(entity) = addressed else { continue };
        if windows
            .get_managed(entity)
            .is_none_or(|(_, _, u)| u.is_some())
        {
            continue;
        }
        for (mut strip, strip_entity, parent, active, selected) in &mut strips {
            if !(active || selected) || !strip.contains(entity) {
                continue;
            }
            match op {
                Operation::Pair(direction) | Operation::PairId { direction, .. } => {
                    let neighbor = match direction {
                        Direction::West => strip.left_neighbour(entity),
                        Direction::East => strip.right_neighbour(entity),
                        _ => None,
                    };
                    if ![Some(entity), neighbor]
                        .into_iter()
                        .flatten()
                        .all(|e| column_managed(&strip, e, &windows))
                    {
                        break;
                    }
                    if neighbor.is_some_and(|e| {
                        windows.get_managed(e).is_some_and(|(_, _, u)| u.is_none())
                    }) && strip.pair_with(entity, matches!(direction, Direction::East))
                    {
                        commands.reshuffle_around(entity);
                    }
                }
                Operation::Unpair | Operation::UnpairId(_) | Operation::Manage => {
                    strip.unpair(entity);
                }
                Operation::PairFit(ratio) | Operation::PairFitId { ratio, .. } => {
                    if !ratio.is_finite() || !(0.1..=0.9).contains(ratio) {
                        break;
                    }
                    if strip.fit_pair(entity, *ratio) {
                        break;
                    }
                    let Ok((display, dock)) = displays.get(parent.parent()) else {
                        break;
                    };
                    let width = display.actual_display_bounds(dock, &config).width();
                    if let Some(pair) =
                        arrange_neighbors(&strip, entity, *ratio, width, &windows, &mut commands)
                    {
                        commands.entity(strip_entity).insert(pair);
                        commands.reshuffle_around(entity);
                    }
                }
                Operation::Resize(_)
                | Operation::SetWidth(_)
                | Operation::FullWidth
                | Operation::Snap
                | Operation::Balance => strip.forget_pair_fit(entity),
                _ => (),
            }
            break;
        }
    }
}

fn column_managed(strip: &LayoutStrip, entity: Entity, windows: &Windows) -> bool {
    strip
        .index_of(entity)
        .ok()
        .and_then(|i| strip.get(i).ok())
        .is_some_and(|column| {
            !matches!(column, crate::ecs::layout::Column::Fullscren(_))
                && column
                    .window_iter()
                    .all(|e| windows.get_managed(e).is_some_and(|(_, _, u)| u.is_none()))
        })
}

fn arrange_neighbors(
    strip: &LayoutStrip,
    entity: Entity,
    ratio: f64,
    width: i32,
    windows: &Windows,
    commands: &mut Commands,
) -> Option<crate::ecs::layout::pairing::ArrangeNeighbors> {
    let neighbor = strip
        .right_neighbour(entity)
        .or_else(|| strip.left_neighbour(entity))?;
    if strip.pair_id(neighbor).is_some()
        || ![entity, neighbor]
            .into_iter()
            .all(|e| column_managed(strip, e, windows))
    {
        return None;
    }
    let (a, b) = (strip.index_of(entity).ok()?, strip.index_of(neighbor).ok()?);
    let first = round_px((f64::from(width) * ratio).floor());
    for (index, target) in [(a.min(b), first), (a.max(b), width - first)] {
        for member in strip.get(index).ok()?.window_iter() {
            if let Some(frame) = windows.moving_frame(member) {
                commands
                    .entity(member)
                    .remove::<crate::ecs::FullWidthMarker>();
                commands.resize_entity(member, frame.size().with_x(target));
            }
        }
    }
    Some(crate::ecs::layout::pairing::ArrangeNeighbors(
        strip.get(a.min(b)).ok()?.top()?,
        strip.get(a.max(b)).ok()?.top()?,
    ))
}

#[derive(SystemParam)]
pub(super) struct TransferParams<'w, 's> {
    pub(super) windows: Windows<'w, 's>,
    pub(super) active_display: ActiveDisplayMut<'w, 's>,
    pub(super) other_workspaces: OffscreenStrips<'w, 's>,
    pub(super) docks: Query<'w, 's, &'static DockPosition>,
    pub(super) window_manager: Res<'w, WindowManager>,
    pub(super) config: Res<'w, Config>,
}

impl TransferParams<'_, '_> {
    pub(super) fn transfer_pair(&mut self, move_focus: MoveFocus, commands: &mut Commands) -> bool {
        let Some((_, entity)) = self.windows.focused() else {
            return false;
        };
        if self.active_display.active_strip().pair_id(entity).is_none() {
            return false;
        }
        self.move_pair(entity, move_focus, commands);
        true
    }

    fn move_pair(&mut self, entity: Entity, move_focus: MoveFocus, commands: &mut Commands) {
        let Self {
            windows,
            active_display,
            other_workspaces,
            docks,
            window_manager,
            config,
        } = self;
        let source_width = active_display.actual_bounds(config).width().max(1);
        let Some(other) = active_display.other().next() else {
            return;
        };
        let destination_id = other.id();
        let mut destination_bounds = other.bounds();
        let Ok(space) = window_manager.active_display_space(destination_id) else {
            return;
        };
        let Some((mut target, target_entity, target_parent)) = other_workspaces
            .iter_mut()
            .find(|(strip, _, _)| strip.id() == space)
        else {
            return;
        };
        if let Some(other) = active_display.other().find(|d| d.id() == destination_id) {
            destination_bounds =
                other.actual_display_bounds(docks.get(target_parent.parent()).ok(), config);
        }
        let source = active_display.active_strip();
        let members = source.movement_members(entity);
        if members
            .iter()
            .any(|e| windows.get_managed(*e).is_none_or(|(_, _, u)| u.is_some()))
        {
            return;
        }
        let range = source.movement_range(entity).unwrap();
        let neighbor = range
            .start
            .checked_sub(1)
            .or_else(|| (range.end < source.len()).then_some(range.end))
            .and_then(|index| source.get(index).ok()?.top());
        let moved = members.iter().copied().collect::<EntityHashSet>();
        active_display
            .active_strip()
            .extract_windows_into(&moved, &mut target);
        for member in members {
            if let Some(frame) = windows.moving_frame(member) {
                let width = round_px(
                    f64::from(frame.width()) / f64::from(source_width)
                        * f64::from(destination_bounds.width()),
                );
                commands.resize_entity(member, frame.size().with_x(width));
            }
        }
        if let Some(neighbor) = neighbor {
            commands.reshuffle_around(neighbor);
        }
        commands.reshuffle_around(entity);
        if matches!(move_focus, MoveFocus::Follow) {
            window_manager.warp_mouse(destination_bounds.center());
            commands
                .entity(target_parent.parent())
                .insert(ActiveDisplayMarker);
            commands.entity(target_entity).insert(ActiveWorkspaceMarker);
            commands.focus_entity(entity, true);
        } else if let Some(neighbor) = neighbor {
            commands.focus_entity(neighbor, false);
        }
    }
}
