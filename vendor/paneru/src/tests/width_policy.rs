use super::*;
use crate::config::{Config, MainOptions};
use crate::ecs::{Bounds, ResizeMarker, SpawnWindowTrigger};
use crate::events::{DestroySource, Event};
use crate::manager::Window;
use bevy::prelude::*;
use std::time::Duration;

fn policy(fill: bool) -> Config {
    (
        MainOptions {
            fill_available_width: Some(fill),
            ..Default::default()
        },
        vec![],
    )
        .into()
}

fn widths(harness: &mut TestHarness) -> Vec<i32> {
    let world = harness.world();
    let mut widths = world
        .query::<&Window>()
        .iter(world)
        .map(|w| w.frame().width())
        .collect::<Vec<_>>();
    widths.sort_unstable();
    widths
}

#[test]
fn fill_round_trip_restores_preferred_sizes_after_overflow_and_close() {
    let mut harness = TestHarness::new().with_config(policy(true)).with_windows(2);
    harness.advance(Duration::from_secs(1));
    assert_eq!(widths(&mut harness), [512, 512]);
    let window = harness.mock_state.spawn_window(
        TEST_PROCESS_ID,
        TEST_WORKSPACE_ID,
        2,
        IRect::new(0, 0, 400, 400),
    );
    harness.world().trigger(SpawnWindowTrigger(vec![window]));
    harness.advance(Duration::from_secs(1));
    assert_eq!(
        widths(&mut harness),
        [400, 400, 400],
        "overflow must restore preferences"
    );
    harness.world().write_message(Event::WindowDestroyed {
        window_id: 2,
        source: DestroySource::Accessibility,
    });
    harness.advance(Duration::from_secs(1));
    assert_eq!(widths(&mut harness), [512, 512]);
    harness.world().insert_resource(policy(false));
    harness.advance(Duration::from_secs(1));
    assert_eq!(widths(&mut harness), [400, 400]);
}

#[test]
fn fill_honors_new_resize_intent_without_accumulating_expansion() {
    let mut harness = TestHarness::new().with_config(policy(true)).with_windows(2);
    harness.advance(Duration::from_secs(1));
    let world = harness.world();
    let (entity, height) = world
        .query::<(Entity, &Bounds)>()
        .iter(world)
        .find_map(|(entity, b)| world.get::<Window>(entity).map(|_| (entity, b.0.y)))
        .unwrap();
    world
        .entity_mut(entity)
        .insert(ResizeMarker(IVec2::new(600, height)));
    harness.advance(Duration::from_secs(1));
    assert_eq!(widths(&mut harness), [410, 614]);
    harness.advance(Duration::from_secs(2));
    assert_eq!(
        widths(&mut harness),
        [410, 614],
        "animation must not replace preferred widths"
    );
    harness.world().insert_resource(policy(false));
    harness.advance(Duration::from_secs(1));
    assert_eq!(widths(&mut harness), [400, 600]);
}

#[test]
fn fill_is_independent_on_differently_sized_displays() {
    let mut harness = TestHarness::new()
        .with_config(policy(true))
        .with_display(
            EXT_DISPLAY_ID,
            IRect::new(1024, 0, 2944, 1200),
            vec![EXT_WORKSPACE_ID],
        )
        .with_workspace_window(0, TEST_WORKSPACE_ID, |_| {})
        .with_workspace_window(1, EXT_WORKSPACE_ID, |_| {})
        .with_workspace_window(2, EXT_WORKSPACE_ID, |_| {});
    harness.advance(Duration::from_secs(1));
    assert_eq!(widths(&mut harness), [960, 960, 1024]);
    harness.world().insert_resource(policy(false));
    harness.advance(Duration::from_secs(1));
    assert_eq!(widths(&mut harness), [400, 400, 400]);
}

#[test]
fn fill_centers_only_overflow_and_full_width_round_trip_retains_preference() {
    use crate::commands::{Command, Direction, Operation};
    let config: Config = (
        MainOptions {
            fill_available_width: Some(true),
            auto_center: Some(true),
            ..Default::default()
        },
        vec![],
    )
        .into();
    let mut harness = TestHarness::new()
        .with_config(config)
        .with_windows(2)
        .with_focused_window(0);
    harness.advance(Duration::from_secs(1));
    for operation in [
        Operation::Focus(Direction::First),
        Operation::Focus(Direction::Last),
        Operation::FullWidth,
        Operation::FullWidth,
    ] {
        harness.world().write_message(Event::Command {
            command: Command::Window(operation),
        });
        harness.advance(Duration::from_secs(1));
    }
    let world = harness.world();
    let frames = world
        .query::<&Window>()
        .iter(world)
        .map(|window| window.frame())
        .collect::<Vec<_>>();
    assert_eq!(frames.iter().map(|f| f.min.x).min(), Some(0));
    assert_eq!(frames.iter().map(|f| f.max.x).max(), Some(1024));
    harness.world().insert_resource(policy(false));
    harness.advance(Duration::from_secs(1));
    assert_eq!(widths(&mut harness), [400, 400]);
}

#[test]
fn fill_display_transfers_preserve_preference_through_six_moves() {
    use crate::commands::{Command, MoveFocus, Operation};
    let mut harness = TestHarness::new()
        .with_config(policy(true))
        .with_display(
            EXT_DISPLAY_ID,
            IRect::new(1024, 0, 2944, 1200),
            vec![EXT_WORKSPACE_ID],
        )
        .with_workspace_window(0, TEST_WORKSPACE_ID, |_| {})
        .with_workspace_window(1, TEST_WORKSPACE_ID, |_| {})
        .with_workspace_window(2, EXT_WORKSPACE_ID, |_| {})
        .with_focused_window(0);
    harness.advance(Duration::from_secs(1));
    for round in 0..6 {
        harness.world().write_message(Event::Command {
            command: Command::Window(Operation::ToNextDisplay(MoveFocus::Follow)),
        });
        harness.advance(Duration::from_secs(1));
        // The mock warp_mouse only moves its cursor; supply the display
        // activation notification macOS sends after the real transfer.
        harness.mock_state.activate_display(if round % 2 == 0 {
            EXT_DISPLAY_ID
        } else {
            TEST_DISPLAY_ID
        });
        harness.advance(Duration::from_millis(300));
    }
    assert_eq!(widths(&mut harness), [512, 512, 1920]);
    harness.world().insert_resource(policy(false));
    harness.advance(Duration::from_secs(1));
    assert_eq!(widths(&mut harness), [400, 400, 400]);
}
