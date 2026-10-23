use std::time::Duration;

use crate::events::Event;
use bevy::prelude::*;

use super::*;
use crate::commands::{Command, Direction, Operation, ResizeDirection};
use crate::config::{Config, MainOptions};

#[test]
fn scrolling_resizing_and_reordering_preserve_separation_each_frame() {
    verify_separation(false);
}

#[test]
fn owner_ticks_preserve_separation_through_resize_stack_and_reorder() {
    verify_separation(true);
}

fn verify_separation(paced: bool) {
    let config: Config = (
        MainOptions {
            animation_speed: Some(14.0),
            preset_column_widths: vec![0.25, 0.5, 1.0],
            ..Default::default()
        },
        vec![],
    )
        .into();
    let mut harness = TestHarness::new().with_config(config).with_windows(4);
    harness.advance(Duration::from_millis(800));
    if paced {
        harness
            .world()
            .insert_resource(crate::ecs::motion::FramePacing::default());
    }
    let mut animated_sizes = 0;
    for operation in [
        Operation::Focus(Direction::First),
        Operation::Focus(Direction::Last),
        Operation::Focus(Direction::West),
        Operation::FullWidth,
        Operation::Resize(ResizeDirection::Shrink),
        Operation::FullWidth,
        Operation::FullWidth,
        Operation::Stack(true),
        Operation::Stack(false),
        Operation::Swap(Direction::West),
        Operation::Swap(Direction::East),
        Operation::Focus(Direction::First),
    ] {
        harness.world().write_message(Event::Command {
            command: Command::Window(operation),
        });
        for frame in 0..40 {
            if paced {
                let mut pacing = harness
                    .world()
                    .resource_mut::<crate::ecs::motion::FramePacing>();
                pacing.due.clear();
                if frame % 2 == 0 {
                    pacing.due.insert(TEST_DISPLAY_ID);
                }
            }
            harness.advance(Duration::from_millis(20));
            let world = harness.world();
            let visible = world
                .query::<&Window>()
                .iter(world)
                .map(Window::frame)
                .filter(|frame| {
                    let visible_width = frame.max.x.min(TEST_DISPLAY_WIDTH) - frame.min.x.max(0);
                    visible_width > frame.width() / 2
                })
                .collect::<Vec<_>>();
            for (index, frame) in visible.iter().enumerate() {
                for other in &visible[index + 1..] {
                    let overlap =
                        (frame.max.min(other.max) - frame.min.max(other.min)).max(IVec2::ZERO);
                    assert!(
                        overlap.x == 0 || overlap.y == 0,
                        "tiles overlap: {frame:?}, {other:?}"
                    );
                }
            }
            animated_sizes += usize::from(
                world
                    .query_filtered::<Entity, With<crate::ecs::ResizeMarker>>()
                    .iter(world)
                    .next()
                    .is_some(),
            );
        }
    }
    assert!(
        animated_sizes > 10,
        "resizing must retain intermediate frames"
    );
}

/// A full-width neighbor must fill the exposed edge on either side, without
/// changing its logical width or spilling onto an adjacent physical display.
#[test]
fn native_edge_presentation_is_symmetric_and_preserves_preferred_widths() {
    use crate::ecs::layout::LayoutStrip;
    use crate::ecs::layout::parking::{CompactParked, EdgePresentation};
    use crate::ecs::{Bounds, FocusedMarker, Position};
    let config: Config = (
        MainOptions {
            compact_parking: Some(true),
            ..Default::default()
        },
        vec![],
    )
        .into();
    let mut h = TestHarness::new()
        .with_config(config)
        .with_display(
            EXT_DISPLAY_ID,
            IRect::new(
                TEST_DISPLAY_WIDTH,
                0,
                TEST_DISPLAY_WIDTH + EXT_DISPLAY_WIDTH,
                EXT_DISPLAY_HEIGHT,
            ),
            vec![EXT_WORKSPACE_ID],
        )
        .with_windows(3);
    h.advance(Duration::from_millis(800));
    let world = h.world();
    let entities: Vec<_> = world
        .query::<(Entity, &Window)>()
        .iter(world)
        .map(|(e, _)| e)
        .collect();
    for e in entities {
        world.entity_mut(e).remove::<FocusedMarker>();
        world.entity_mut(e).remove::<crate::ecs::ResizeMarker>();
        world.get_mut::<Bounds>(e).unwrap().0.x = 800;
    }
    let strip = world
        .query::<(Entity, &LayoutStrip)>()
        .iter(world)
        .find(|(_, s)| s.id() == TEST_WORKSPACE_ID)
        .unwrap()
        .0;
    // Both edge tiles expose 400 points around the central 800 point column.
    for origin in [-400, -800] {
        h.world().get_mut::<Position>(strip).unwrap().0.x = origin;
        h.advance(Duration::from_millis(20));
        let world = h.world();
        let windows: Vec<_> = world
            .query::<(
                &Window,
                &Bounds,
                Has<CompactParked>,
                Option<&EdgePresentation>,
            )>()
            .iter(world)
            .map(|(w, b, p, edge)| (w.frame(), b.0.x, p, edge.copied()))
            .collect();
        assert!(windows.iter().any(|(_, _, _, edge)| edge.is_some()));
        for (frame, width, parked, _) in windows {
            assert_eq!(
                width, 800,
                "native edge fitting must not resize the logical strip"
            );
            if !parked {
                assert!(
                    frame.min.x >= 0 && frame.max.x <= TEST_DISPLAY_WIDTH,
                    "visible frame must stay inside its owner: {frame:?}"
                );
            }
        }
    }
}

#[test]
fn rejected_edge_size_is_parked_before_it_can_spill_and_recovers_on_focus() {
    use crate::ecs::layout::LayoutStrip;
    use crate::ecs::layout::parking::{CompactParked, NativeMinimumWidth};
    use crate::ecs::{Bounds, FocusedMarker, Position};
    let config: Config = (
        MainOptions {
            compact_parking: Some(true),
            ..Default::default()
        },
        vec![],
    )
        .into();
    let mut h = TestHarness::new()
        .with_config(config)
        .with_display(
            EXT_DISPLAY_ID,
            IRect::new(
                TEST_DISPLAY_WIDTH,
                0,
                TEST_DISPLAY_WIDTH + EXT_DISPLAY_WIDTH,
                EXT_DISPLAY_HEIGHT,
            ),
            vec![EXT_WORKSPACE_ID],
        )
        .with_windows(3);
    h.advance(Duration::from_millis(800));
    for id in 0..3 {
        h.mock_state.update_window(id, |w| {
            w.minimum_width = 700;
            w.frame.max.x = w.frame.min.x + 800;
        });
    }
    let world = h.world();
    let ids: Vec<_> = world
        .query::<(Entity, &Window)>()
        .iter(world)
        .map(|(e, _)| e)
        .collect();
    for e in ids {
        world.entity_mut(e).remove::<FocusedMarker>();
        world.get_mut::<Bounds>(e).unwrap().0.x = 800;
    }
    let strip = world
        .query::<(Entity, &LayoutStrip)>()
        .iter(world)
        .find(|(_, s)| s.id() == TEST_WORKSPACE_ID)
        .unwrap()
        .0;
    world.get_mut::<Position>(strip).unwrap().0.x = -400;
    h.advance(Duration::from_millis(20));
    let world = h.world();
    let learned: Vec<_> = world
        .query::<(Entity, &Window, &NativeMinimumWidth, Has<CompactParked>)>()
        .iter(world)
        .map(|(e, w, min, parked)| (e, w.id(), min.0, parked))
        .collect();
    assert!(!learned.is_empty());
    for (_, _, min, parked) in &learned {
        assert_eq!(*min, 700);
        assert!(*parked);
    }
    let (entity, id, _, _) = learned[0];
    assert_eq!(world.get::<Bounds>(entity).unwrap().0.x, 800);
    h.mock_state.set_focused_window(id);
    h.world()
        .write_message(Event::WindowFocused { window_id: id });
    h.advance(Duration::from_millis(600));
    assert!(h.world().get::<CompactParked>(entity).is_none());
    let frame = h.world().get::<Window>(entity).unwrap().frame();
    assert_eq!(frame.width(), 800);
    assert!(frame.min.x >= 0 && frame.max.x <= TEST_DISPLAY_WIDTH);
}

#[test]
fn immediate_exit_restores_frames_after_the_final_motion_and_focus_commit() {
    let config: Config = (
        MainOptions {
            compact_parking: Some(true),
            animation_speed: Some(14.0),
            ..Default::default()
        },
        vec![],
    )
        .into();
    let mut h = TestHarness::new().with_config(config).with_windows(5);
    h.advance(Duration::from_millis(800));
    h.mock_state.set_focused_window(0);
    h.world()
        .write_message(Event::WindowFocused { window_id: 0 });
    h.advance(Duration::from_millis(500));
    h.world().write_message(Event::Command {
        command: Command::Window(Operation::Focus(Direction::Last)),
    });
    h.app.update();
    assert!(
        !h.world()
            .query::<&crate::ecs::RepositionMarker>()
            .iter(h.world())
            .collect::<Vec<_>>()
            .is_empty()
    );
    h.world().write_message(bevy::app::AppExit::Success);
    h.app.update();
    let world = h.world();
    for w in world.query::<&Window>().iter(world) {
        assert_eq!(
            w.frame(),
            IRect::new(
                0,
                TEST_MENUBAR_HEIGHT,
                TEST_WINDOW_WIDTH,
                TEST_DISPLAY_HEIGHT
            ),
            "a final animation/focus write must not overwrite restoration"
        );
    }
}
