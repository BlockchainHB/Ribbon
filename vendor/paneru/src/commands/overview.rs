//! Window-addressed overview actions. The GUI renders snapshots; this module
//! alone validates membership and changes the authoritative column order.
use bevy::app::{App, PreUpdate};
use bevy::ecs::hierarchy::ChildOf;
use bevy::ecs::message::MessageReader;
use bevy::ecs::query::Has;
use bevy::ecs::schedule::IntoScheduleConfigs;
use bevy::ecs::system::{Commands, Query};
use objc2_core_foundation::{CFNotificationCenter, CFString};

use crate::commands::{Command, Operation};
use crate::ecs::layout::LayoutStrip;
use crate::ecs::params::Windows;
use crate::ecs::{ActiveWorkspaceMarker, SelectedVirtualMarker, SpawnCommandsExt};
use crate::events::Event;

pub(super) fn register(app: &mut App) {
    app.add_systems(PreUpdate, handle.in_set(crate::ecs::PreUpdateSet::Dispatch));
}

fn show_overview() {
    let Ok(parent) = std::env::var("RIBBON_PARENT_PID") else {
        return;
    };
    if parent.parse::<u32>().ok().is_none_or(|pid| pid < 2) {
        return;
    }
    let Some(center) = CFNotificationCenter::distributed_center() else {
        return;
    };
    let name = CFString::from_static_str("dev.ribbon.show-overview");
    let object = CFString::from_str(&parent);
    // Distributed notifications require a CFString object. Both strings remain
    // alive for the synchronous post; there is no payload and no layout mutation.
    unsafe {
        center.post_notification(Some(&name), (&raw const *object).cast(), None, true);
    };
}

fn handle(
    mut events: MessageReader<Event>,
    windows: Windows,
    mut strips: Query<(
        &mut LayoutStrip,
        &ChildOf,
        Has<ActiveWorkspaceMarker>,
        Has<SelectedVirtualMarker>,
    )>,
    mut commands: Commands,
) {
    for event in events.read() {
        let Event::Command {
            command: Command::Window(operation),
        } = event
        else {
            continue;
        };
        match operation {
            Operation::Overview => show_overview(),
            Operation::FocusId(id) => {
                let Some((_, entity)) = windows.find(*id) else {
                    continue;
                };
                if windows
                    .get_managed(entity)
                    .is_some_and(|(_, _, unmanaged)| unmanaged.is_none())
                    && strips.iter().any(|(strip, _, active, selected)| {
                        (active || selected) && strip.contains(entity)
                    })
                {
                    commands.focus_entity(entity, true);
                }
            }
            Operation::Reorder {
                window,
                anchor,
                after,
            } => {
                let (Some((_, source)), Some((_, target))) =
                    (windows.find(*window), windows.find(*anchor))
                else {
                    continue;
                };
                if [source, target]
                    .into_iter()
                    .any(|e| windows.get_managed(e).is_none_or(|(_, _, u)| u.is_some()))
                {
                    continue;
                }
                for (mut strip, _, active, selected) in &mut strips {
                    if !active && !selected {
                        continue;
                    }
                    if let (Ok(from), Ok(to)) = (strip.index_of(source), strip.index_of(target)) {
                        if from == to {
                            break;
                        }
                        strip.reorder(source, target, *after);
                        let anchor = windows
                            .focused()
                            .map(|(_, e)| e)
                            .filter(|e| strip.contains(*e))
                            .unwrap_or(source);
                        commands.reshuffle_around(anchor);
                        break;
                    }
                }
            }
            _ => (),
        }
    }
}
