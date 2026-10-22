use super::*;
use crate::commands::{Command, Direction, MoveFocus, Operation};
use crate::config::{Config, MainOptions};
use crate::ecs::layout::LayoutStrip;
use crate::ecs::state::QueryStateParams;
use crate::events::{DestroySource, Event};
use crate::types::windowset::{ColumnSet, WindowSet};
use bevy::ecs::system::SystemState;
use bevy::prelude::*;
use std::time::Duration;

fn state(h: &mut TestHarness) -> WindowSet {
    let world = h.world();
    SystemState::<QueryStateParams>::new(world)
        .get(world)
        .unwrap()
        .extract_window_set()
        .unwrap()
}

fn columns(h: &mut TestHarness, display: u32) -> Vec<ColumnSet> {
    state(h)
        .displays()
        .iter()
        .find(|d| d.id == display)
        .unwrap()
        .workspaces
        .iter()
        .filter(|w| w.active)
        .flat_map(|w| w.columns.iter().cloned())
        .collect()
}

fn send(h: &mut TestHarness, operation: Operation) {
    h.world().write_message(Event::Command {
        command: Command::Window(operation),
    });
    h.advance(Duration::from_secs(1));
}

fn pair(h: &mut TestHarness) -> (i32, i32, u64) {
    let initial = columns(h, TEST_DISPLAY_ID);
    let (left, right) = (initial[0].windows[0].id, initial[1].windows[0].id);
    send(
        h,
        Operation::PairId {
            window: left,
            direction: Direction::East,
        },
    );
    let paired = columns(h, TEST_DISPLAY_ID);
    let id = paired[0].pair_id.expect("pair created");
    assert_eq!(paired[1].pair_id, Some(id));
    (left, right, id)
}

fn frames(h: &mut TestHarness, ids: &[i32]) -> Vec<IRect> {
    let world = h.world();
    ids.iter()
        .map(|id| {
            world
                .query::<&Window>()
                .iter(world)
                .find(|w| w.id() == *id)
                .unwrap()
                .frame()
        })
        .collect()
}

fn harness(count: i32) -> TestHarness {
    let config: Config = (
        MainOptions {
            auto_center: Some(true),
            ..Default::default()
        },
        vec![],
    )
        .into();
    let mut h = TestHarness::new()
        .with_config(config)
        .with_windows(count)
        .with_focused_window(0);
    h.advance(Duration::from_secs(1));
    h
}

#[test]
fn pairing_preserves_widths_then_thirds_fit_and_focus_stays_still() {
    let mut h = harness(4);
    let before = columns(&mut h, TEST_DISPLAY_ID)
        .iter()
        .map(|c| c.width_ratio)
        .collect::<Vec<_>>();
    let (left, right, _) = pair(&mut h);
    assert_eq!(
        columns(&mut h, TEST_DISPLAY_ID)
            .iter()
            .map(|c| c.width_ratio)
            .collect::<Vec<_>>(),
        before
    );
    send(
        &mut h,
        Operation::PairFitId {
            window: left,
            ratio: 1.0 / 3.0,
        },
    );
    send(&mut h, Operation::FocusId(left));
    let expected = frames(&mut h, &[left, right]);
    assert_eq!(
        expected[0].width() + expected[1].width(),
        TEST_DISPLAY_WIDTH
    );
    assert_eq!(expected[0].max.x, expected[1].min.x);
    assert_eq!(expected[0].min.x, 0);
    for id in [right, left, right, left] {
        send(&mut h, Operation::FocusId(id));
        assert_eq!(
            frames(&mut h, &[left, right]),
            expected,
            "internal focus must not recenter a member"
        );
    }
    let last = columns(&mut h, TEST_DISPLAY_ID).last().unwrap().windows[0].id;
    send(&mut h, Operation::FocusId(last));
    // OS/application focus, the same engine route used by app-launch quicklinks.
    h.mock_state.focus_window(right);
    h.advance(Duration::from_secs(1));
    assert_eq!(frames(&mut h, &[left, right]), expected);
}

#[test]
fn ungrouping_leaves_geometry_and_independent_arrangement_does_not_link() {
    let mut h = harness(3);
    let (left, right, _) = pair(&mut h);
    send(
        &mut h,
        Operation::PairFitId {
            window: left,
            ratio: 0.5,
        },
    );
    let before = frames(&mut h, &[left, right]);
    send(&mut h, Operation::UnpairId(right));
    assert!(
        columns(&mut h, TEST_DISPLAY_ID)
            .iter()
            .all(|c| c.pair_id.is_none())
    );
    assert_eq!(frames(&mut h, &[left, right]), before);
    send(
        &mut h,
        Operation::PairFitId {
            window: left,
            ratio: 1.0 / 3.0,
        },
    );
    let arranged = frames(&mut h, &[left, right]);
    assert_eq!(arranged[0].min.x, 0);
    assert_eq!(arranged[0].max.x, arranged[1].min.x);
    assert_eq!(arranged[1].max.x, TEST_DISPLAY_WIDTH);
    assert!(
        columns(&mut h, TEST_DISPLAY_ID)
            .iter()
            .all(|c| c.pair_id.is_none())
    );
}

#[test]
fn reorder_moves_either_member_as_a_block_and_cannot_split_target_pair() {
    let mut h = harness(6);
    let (left, right, id) = pair(&mut h);
    let initial = columns(&mut h, TEST_DISPLAY_ID);
    let target = initial[4].windows[0].id;
    send(
        &mut h,
        Operation::PairId {
            window: target,
            direction: Direction::East,
        },
    );
    send(
        &mut h,
        Operation::Reorder {
            window: right,
            anchor: target,
            after: true,
        },
    );
    let after = columns(&mut h, TEST_DISPLAY_ID);
    assert_eq!(after[4].windows[0].id, left);
    assert_eq!(after[5].windows[0].id, right);
    assert_eq!(after[4].pair_id, Some(id));
    assert_eq!(after[2].pair_id, after[3].pair_id);
    send(
        &mut h,
        Operation::Reorder {
            window: left,
            anchor: right,
            after: true,
        },
    );
    assert_eq!(
        columns(&mut h, TEST_DISPLAY_ID),
        after,
        "drop onto one's own pair is a no-op"
    );
    send(&mut h, Operation::FocusId(right));
    send(&mut h, Operation::Swap(Direction::West));
    let moved = columns(&mut h, TEST_DISPLAY_ID);
    assert_eq!(moved[2].windows[0].id, left);
    assert_eq!(moved[3].windows[0].id, right);
}

#[test]
fn closing_stack_leader_preserves_pair_until_the_column_disappears() {
    let mut h = harness(4);
    let initial = columns(&mut h, TEST_DISPLAY_ID);
    let top = initial[0].windows[0].id;
    let stacked = initial[1].windows[0].id;
    send(&mut h, Operation::FocusId(stacked));
    send(&mut h, Operation::Stack(true));
    let (_, _, id) = pair(&mut h);
    for closed in [top, stacked] {
        h.world().write_message(Event::WindowDestroyed {
            window_id: closed,
            source: DestroySource::Accessibility,
        });
        h.advance(Duration::from_secs(1));
        let current = columns(&mut h, TEST_DISPLAY_ID);
        if closed == top {
            assert_eq!(current[0].pair_id, Some(id));
            assert_eq!(current[1].pair_id, Some(id));
        } else {
            assert!(current.iter().all(|c| c.pair_id.is_none()));
        }
    }
}

#[test]
fn insertion_and_transfer_keep_stable_membership_and_stack_structure() {
    let mut world = World::new();
    let e = (0..5).map(|_| world.spawn_empty().id()).collect::<Vec<_>>();
    let mut strip = LayoutStrip::new(TEST_WORKSPACE_ID, 0);
    for &entity in &e[..3] {
        strip.append(entity);
    }
    assert!(strip.pair_with(e[0], true));
    let id = strip.pair_id(e[0]);
    strip.insert_at(1, e[3]);
    strip.insert_at(0, e[4]);
    assert_eq!(strip.all_windows(), vec![e[4], e[0], e[1], e[3], e[2]]);
    assert_eq!(strip.pair_id(e[1]), id);
    let mut target = LayoutStrip::new(EXT_WORKSPACE_ID, 0);
    strip.extract_windows_into(&[e[0], e[1]].into_iter().collect(), &mut target);
    assert_eq!(target.all_windows(), vec![e[0], e[1]]);
    assert_eq!(target.pair_id(e[1]), id);
    assert!(strip.pair_id(e[4]).is_none());
    target.remove(e[0]);
    assert!(target.pair_id(e[1]).is_none());
}

#[test]
fn paired_transfer_moves_both_columns_and_refits_on_different_monitor() {
    let mut h = TestHarness::new()
        .with_display(
            EXT_DISPLAY_ID,
            IRect::new(1024, 0, 2944, 1200),
            vec![EXT_WORKSPACE_ID],
        )
        .with_windows(4)
        .with_workspace_window(10, EXT_WORKSPACE_ID, |_| {})
        .with_focused_window(0);
    h.advance(Duration::from_secs(1));
    let (left, right, id) = pair(&mut h);
    send(
        &mut h,
        Operation::PairFitId {
            window: left,
            ratio: 1.0 / 3.0,
        },
    );
    send(&mut h, Operation::FocusId(right));
    send(&mut h, Operation::ToNextDisplay(MoveFocus::Follow));
    assert!(
        columns(&mut h, TEST_DISPLAY_ID)
            .iter()
            .all(|c| c.pair_id.is_none())
    );
    let external = columns(&mut h, EXT_DISPLAY_ID);
    let paired = external
        .iter()
        .filter(|c| c.pair_id == Some(id))
        .collect::<Vec<_>>();
    assert_eq!(
        paired.iter().map(|c| c.windows[0].id).collect::<Vec<_>>(),
        vec![left, right]
    );
    let f = frames(&mut h, &[left, right]);
    assert_eq!(f[0].width() + f[1].width(), EXT_DISPLAY_WIDTH);
    assert_eq!(f[0].max.x, f[1].min.x);
    send(&mut h, Operation::ToNextDisplay(MoveFocus::Stay));
    assert_eq!(
        columns(&mut h, TEST_DISPLAY_ID)
            .iter()
            .filter(|c| c.pair_id == Some(id))
            .count(),
        2
    );
}

#[test]
fn oversized_pair_reveals_focused_member_and_floating_detaches() {
    let mut h = harness(4);
    let (left, right, _) = pair(&mut h);
    send(&mut h, Operation::FocusId(left));
    send(&mut h, Operation::SetWidth(1.0));
    for window in [right, left] {
        send(&mut h, Operation::FocusId(window));
        let f = frames(&mut h, &[window])[0];
        assert!(f.min.x >= 0 && f.max.x <= TEST_DISPLAY_WIDTH);
    }
    send(&mut h, Operation::Manage);
    assert!(
        columns(&mut h, TEST_DISPLAY_ID)
            .iter()
            .all(|c| c.pair_id.is_none())
    );
    send(
        &mut h,
        Operation::PairId {
            window: left,
            direction: Direction::East,
        },
    );
    assert!(
        columns(&mut h, TEST_DISPLAY_ID)
            .iter()
            .all(|c| c.pair_id.is_none())
    );
}

#[test]
fn pairing_command_round_trips_and_rejects_invalid_directions_ratios_and_ids() {
    use crate::types::argv::parse_command;
    for args in [
        vec!["pair", "west"],
        vec!["pairid", "42", "east"],
        vec!["unpair"],
        vec!["unpairid", "42"],
        vec!["pairfit", "third"],
        vec!["pairfitid", "42", "0.5"],
    ] {
        let args = [vec!["window"], args].concat();
        let cmd = parse_command(&args).unwrap();
        let encoded = cmd.to_argv().unwrap();
        assert_eq!(
            parse_command(&encoded.iter().map(String::as_str).collect::<Vec<_>>()).unwrap(),
            cmd
        );
    }
    for args in [
        vec!["pair", "north"],
        vec!["pairid", "east"],
        vec!["pairfit", "NaN"],
        vec!["pairfit", "inf"],
        vec!["pairfit", "1"],
        vec!["unpairid", "oops"],
    ] {
        assert!(parse_command(&[vec!["window"], args].concat()).is_err());
    }
}

#[test]
fn fitted_pair_recomputes_after_display_geometry_changes() {
    let mut h = harness(4);
    let (left, right, id) = pair(&mut h);
    send(
        &mut h,
        Operation::PairFitId {
            window: left,
            ratio: 1.0 / 3.0,
        },
    );
    h.mock_state
        .set_display_bounds(TEST_DISPLAY_ID, IRect::new(0, 0, 1537, 900));
    h.world().write_message(Event::DisplayConfigured {
        display_id: TEST_DISPLAY_ID,
    });
    h.advance(Duration::from_secs(2));
    send(&mut h, Operation::FocusId(right));
    let f = frames(&mut h, &[left, right]);
    assert_eq!(f[0].width(), 512);
    assert_eq!(f[1].width(), 1025, "rounding remainder is consumed exactly");
    assert_eq!(f[0].max.x, f[1].min.x);
    assert_eq!(columns(&mut h, TEST_DISPLAY_ID)[0].pair_id, Some(id));
}

#[test]
fn accepted_larger_window_size_does_not_trigger_an_endless_pair_refit() {
    let mut h = harness(4);
    let (left, right, _) = pair(&mut h);
    send(
        &mut h,
        Operation::PairFitId {
            window: left,
            ratio: 0.5,
        },
    );
    // Model an application reporting a larger accepted width through AX.
    let height = frames(&mut h, &[right])[0].height();
    h.mock_state
        .os_resize_window(right, IVec2::new(900, height));
    h.advance(Duration::from_secs(2));
    assert_eq!(frames(&mut h, &[right])[0].width(), 900);
    for window in [left, right] {
        send(&mut h, Operation::FocusId(window));
        let f = frames(&mut h, &[left, right]);
        let selected = f[usize::from(window == right)];
        assert!(selected.min.x >= 0 && selected.max.x <= TEST_DISPLAY_WIDTH);
        // A parked window can be clipped, but can never overlap visible content.
        assert!(
            f[0].max.x <= f[1].min.x
                || f.iter()
                    .any(|f| f.max.x <= 5 || f.min.x >= TEST_DISPLAY_WIDTH - 5)
        );
    }
}

#[test]
fn pair_fit_is_compatible_with_fill_policy_and_explicit_individual_resize() {
    let mut h = harness(3);
    let config: Config = (
        MainOptions {
            fill_available_width: Some(true),
            ..Default::default()
        },
        vec![],
    )
        .into();
    h.world().insert_resource(config);
    let (left, right, _) = pair(&mut h);
    send(
        &mut h,
        Operation::PairFitId {
            window: left,
            ratio: 0.5,
        },
    );
    let f = frames(&mut h, &[left, right]);
    assert_eq!(f[0].width() + f[1].width(), TEST_DISPLAY_WIDTH);
    send(&mut h, Operation::FocusId(left));
    send(&mut h, Operation::SetWidth(0.75));
    assert_eq!(frames(&mut h, &[left])[0].width(), 768);
    h.advance(Duration::from_secs(2));
    assert_eq!(
        frames(&mut h, &[left])[0].width(),
        768,
        "pair fit does not undo an individual resize"
    );
}
