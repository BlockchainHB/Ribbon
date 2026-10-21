use std::time::Duration;

use crate::events::Event;
use bevy::prelude::*;

use super::*;
use crate::commands::{Command, Direction, Operation, ResizeDirection};
use crate::config::{Config, MainOptions};

#[test]
fn scrolling_resizing_and_reordering_preserve_separation_each_frame() {
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
        for _ in 0..40 {
            harness.advance(Duration::from_millis(20));
            let world = harness.world();
            let visible = world
                .query::<&Window>()
                .iter(world)
                .map(|window| window.frame())
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
