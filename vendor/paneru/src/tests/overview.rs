use super::*;
use crate::commands::{Command, Operation};
use crate::ecs::state::QueryStateParams;
use crate::types::windowset::WindowSet;
use bevy::ecs::system::SystemState;
use bevy::math::IRect;
use std::time::Duration;

fn snapshot(h: &mut TestHarness) -> WindowSet {
    let world = h.world();
    let mut state = SystemState::<QueryStateParams>::new(world);
    state.get(world).unwrap().extract_window_set().unwrap()
}

fn order(h: &mut TestHarness, display: u32) -> Vec<Vec<i32>> {
    snapshot(h)
        .displays()
        .iter()
        .find(|d| d.id == display)
        .unwrap()
        .workspaces
        .iter()
        .filter(|w| w.active)
        .flat_map(|w| w.columns.iter())
        .map(|c| c.windows.iter().map(|w| w.id).collect())
        .collect()
}

fn command(h: &mut TestHarness, op: Operation) {
    h.world().write_message(Event::Command {
        command: Command::Window(op),
    });
    h.advance(Duration::from_secs(1));
}

#[test]
fn overview_inserts_columns_without_exchanging_intervening_tiles() {
    let mut h = TestHarness::new().with_windows(4).with_focused_window(3);
    h.advance(Duration::from_secs(1));
    let initial = order(&mut h, TEST_DISPLAY_ID);
    let (source, target) = (initial[0][0], initial[2][0]);
    command(
        &mut h,
        Operation::Reorder {
            window: source,
            anchor: target,
            after: true,
        },
    );
    assert_eq!(
        order(&mut h, TEST_DISPLAY_ID),
        vec![
            initial[1].clone(),
            initial[2].clone(),
            initial[0].clone(),
            initial[3].clone()
        ]
    );
    command(
        &mut h,
        Operation::Reorder {
            window: source,
            anchor: initial[1][0],
            after: false,
        },
    );
    assert_eq!(order(&mut h, TEST_DISPLAY_ID), initial);
}

#[test]
fn overview_ignores_closed_windows_floating_windows_and_cross_display_drops() {
    let mut h = TestHarness::new()
        .with_display(
            EXT_DISPLAY_ID,
            IRect::new(1024, 0, 2944, 1200),
            vec![EXT_WORKSPACE_ID],
        )
        .with_workspace_window(0, TEST_WORKSPACE_ID, |_| {})
        .with_workspace_window(1, TEST_WORKSPACE_ID, |_| {})
        .with_workspace_window(2, EXT_WORKSPACE_ID, |_| {})
        .with_focused_window(0);
    h.advance(Duration::from_secs(1));
    let before = order(&mut h, TEST_DISPLAY_ID);
    let other = order(&mut h, EXT_DISPLAY_ID);
    assert_eq!(
        other.len(),
        1,
        "overview must include the other display's selected strip"
    );
    command(
        &mut h,
        Operation::Reorder {
            window: 9999,
            anchor: 1,
            after: true,
        },
    );
    command(
        &mut h,
        Operation::Reorder {
            window: 0,
            anchor: 2,
            after: true,
        },
    );
    assert_eq!(order(&mut h, TEST_DISPLAY_ID), before);
    assert_eq!(order(&mut h, EXT_DISPLAY_ID), other);
    command(&mut h, Operation::Manage);
    let floated = order(&mut h, TEST_DISPLAY_ID);
    command(
        &mut h,
        Operation::Reorder {
            window: 0,
            anchor: 1,
            after: true,
        },
    );
    assert_eq!(order(&mut h, TEST_DISPLAY_ID), floated);
}

#[test]
fn overview_moves_a_stack_as_one_column_and_focuses_a_parked_tile() {
    let mut h = TestHarness::new().with_windows(5).with_focused_window(3);
    h.advance(Duration::from_secs(1));
    command(&mut h, Operation::FocusId(3));
    command(&mut h, Operation::Stack(true));
    let before = order(&mut h, TEST_DISPLAY_ID);
    let stack = before.iter().find(|c| c.len() == 2).unwrap().clone();
    let anchor = before.iter().find(|c| c.len() == 1).unwrap()[0];
    command(
        &mut h,
        Operation::Reorder {
            window: stack[0],
            anchor,
            after: false,
        },
    );
    let after = order(&mut h, TEST_DISPLAY_ID);
    let at = after.iter().position(|c| c.contains(&anchor)).unwrap();
    assert_eq!(after[at - 1], stack);
    let last = *after.last().unwrap().last().unwrap();
    command(&mut h, Operation::FocusId(last));
    assert_eq!(snapshot(&mut h).focused(), Some(last));
}

#[test]
fn overview_commands_round_trip_and_reject_incomplete_drags() {
    use crate::types::argv::parse_command;
    for args in [
        vec!["window", "overview"],
        vec!["window", "focusid", "42"],
        vec!["window", "reorder", "42", "12", "after"],
    ] {
        let cmd = parse_command(&args).unwrap();
        let encoded = cmd.to_argv().unwrap();
        assert_eq!(
            parse_command(&encoded.iter().map(String::as_str).collect::<Vec<_>>()).unwrap(),
            cmd
        );
    }
    for args in [
        vec!["window", "reorder", "42", "12"],
        vec!["window", "reorder", "42", "12", "maybe"],
    ] {
        assert!(parse_command(&args).is_err());
    }
}
