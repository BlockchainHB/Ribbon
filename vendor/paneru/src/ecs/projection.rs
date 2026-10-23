//! Presentation policy for fixed-size offscreen windows. Native resources live
//! in the main-thread manager; ECS owns when they are prepared and displayed.
use bevy::prelude::*;

use crate::config::Config;
use crate::events::Event;
use crate::manager::Window;
use crate::manager::projection::Projections;
use crate::manager::{Display, WindowManager};
use crate::platform::WorkspaceId;
use std::collections::HashSet;

#[derive(Resource)]
pub(crate) struct ProjectionEnabled;

pub(super) fn initialize(app: &mut App) -> crate::errors::Result<()> {
    let requested = std::env::var("RIBBON_NATIVE_PROJECTION");
    if requested.as_deref() == Ok("0") {
        return Ok(());
    }
    match Projections::native() {
        Ok(backend) => {
            app.insert_non_send(backend)
                .insert_resource(ProjectionEnabled)
                .init_resource::<NativeVisibleSpaces>();
        }
        Err(error) if requested.as_deref() == Ok("1") => return Err(error),
        Err(error) => {
            tracing::warn!(%error, "fixed-content compositor unavailable; retaining compatibility presentation");
        }
    }
    Ok(())
}

#[derive(Resource, Default)]
pub(crate) struct NativeVisibleSpaces {
    pub visible: HashSet<WorkspaceId>,
    pub fullscreen: HashSet<WorkspaceId>,
}

#[derive(Component, Clone, Copy, PartialEq, Eq)]
pub(crate) struct ProjectionViewport {
    pub clip: IRect,
    pub hidden: bool,
    pub suspended: bool,
}

#[derive(Component)]
pub(crate) struct ProjectionPending;

#[allow(clippy::too_many_arguments)] // Bevy parameters keep native access on the main thread.
pub(super) fn synchronize_spaces(
    mut events: MessageReader<Event>,
    displays: Query<&Display>,
    changed_displays: Query<(), Changed<Display>>,
    manager: Res<WindowManager>,
    mut visible: ResMut<NativeVisibleSpaces>,
    mut windows: Query<&mut super::Bounds, With<ProjectionViewport>>,
    _backend: NonSend<Projections>,
    mut initialized: Local<bool>,
) {
    let mut changed = false;
    for event in events.read() {
        changed |= matches!(event, Event::SpaceChanged);
    }
    if *initialized && !changed && changed_displays.is_empty() {
        return;
    }
    *initialized = true;
    let next = displays
        .iter()
        .filter_map(|display| manager.active_display_space(display.id()).ok())
        .collect();
    let fullscreen = displays
        .iter()
        .filter(|display| manager.is_fullscreen_space(display.id()))
        .filter_map(|display| manager.active_display_space(display.id()).ok())
        .collect();
    if visible.visible != next || visible.fullscreen != fullscreen {
        visible.visible = next;
        visible.fullscreen = fullscreen;
        for mut bounds in &mut windows {
            bounds.set_changed();
        }
    }
}

type PreparationWindows<'w, 's> = Populated<
    'w,
    's,
    (
        Entity,
        &'static Window,
        &'static ProjectionViewport,
        &'static mut super::Position,
        &'static mut super::Bounds,
    ),
    Or<(
        Added<ProjectionViewport>,
        Changed<ProjectionViewport>,
        With<ProjectionPending>,
    )>,
>;

pub(super) fn prepare(
    mut windows: PreparationWindows,
    mut backend: Option<NonSendMut<Projections>>,
    mut commands: Commands,
    mut exit: MessageWriter<AppExit>,
) {
    let Some(backend) = backend.as_mut() else {
        return;
    };
    for (entity, window, viewport, mut position, mut bounds) in &mut windows {
        tracing::trace!(entity = ?entity, window_id = window.id(), "preparing fixed-size window");
        match backend.prepare(window.id(), viewport.clip) {
            Ok(true) => {
                // Attachment can finish after the original geometry change.
                position.set_changed();
                bounds.set_changed();
                commands.entity(entity).try_remove::<ProjectionPending>();
            }
            Ok(false) => {
                commands.entity(entity).try_insert(ProjectionPending);
            }
            Err(error) => {
                tracing::error!(window_id = window.id(), %error, "cannot prepare fixed-size presentation");
                exit.write(AppExit::error());
            }
        }
    }
}

pub(crate) fn commit(
    backend: &mut Projections,
    window: &mut Window,
    viewport: ProjectionViewport,
    target: IRect,
) -> crate::errors::Result<()> {
    tracing::trace!(
        window_id = window.id(),
        ?target,
        suspended = viewport.suspended,
        hidden = viewport.hidden,
        "committing fixed-size window"
    );
    let padding = IVec2::new(window.horizontal_padding(), window.vertical_padding());
    if viewport.suspended {
        // An app-owned space has independent visibility. Never let it expose
        // windows belonging to a different native desktop or fullscreen Space.
        backend.hide(window.id())?;
        window.set_presentation_offset(IVec2::ZERO);
    } else if !viewport.hidden && contained(target, viewport.clip, padding) {
        backend.hide(window.id())?;
        window.set_presentation_offset(IVec2::ZERO);
        window.reposition_native(target.min);
    } else {
        let native = window.native_frame();
        // Make room for a genuine width/height change before the AX growth
        // phase, so the native app never grows across a neighboring display.
        let staging =
            IRect::from_corners(native.min, native.min + native.size().max(target.size()));
        let anchor = safe_anchor(staging, viewport.clip, padding);
        if anchor != native.min {
            window.reposition_native(anchor);
        }
        let offset = target.min - window.native_frame().min;
        backend.present(window.id(), viewport.clip, offset)?;
        window.set_presentation_offset(offset);
    }
    Ok(())
}

/// Rebase a projected presentation after a native resize constrained its anchor.
/// This runs on the main thread after parallel AX workers have completed.
type ResizedProjectionWindows<'w, 's> = Populated<
    'w,
    's,
    (
        &'static mut Window,
        &'static super::Position,
        &'static ProjectionViewport,
    ),
    (Changed<super::Bounds>, Without<ProjectionPending>),
>;

pub(super) fn refresh_after_resize(
    mut windows: ResizedProjectionWindows,
    mut backend: Option<NonSendMut<Projections>>,
    mut exit: MessageWriter<AppExit>,
) {
    let Some(backend) = backend.as_mut() else {
        return;
    };
    for (mut window, position, viewport) in &mut windows {
        let target = IRect::from_corners(position.0, position.0 + window.frame().size());
        if let Err(error) = commit(backend, &mut window, *viewport, target) {
            tracing::error!(%error, "cannot restore fixed-size presentation after resize");
            exit.write(AppExit::error());
        }
    }
}

pub(super) fn reset_policy(
    config: Res<Config>,
    mut backend: Option<NonSendMut<Projections>>,
    mut windows: Query<(Entity, &mut Window), With<ProjectionViewport>>,
    mut commands: Commands,
) {
    if !config.is_changed() || config.compact_parking() {
        return;
    }
    if let Some(backend) = backend.as_mut() {
        backend.clear();
    }
    for (entity, mut window) in &mut windows {
        window.set_presentation_offset(IVec2::ZERO);
        commands
            .entity(entity)
            .try_remove::<(ProjectionViewport, ProjectionPending)>();
    }
}

pub(super) fn unmanage(
    trigger: On<Add, super::Unmanaged>,
    mut windows: Query<&mut Window>,
    mut backend: Option<NonSendMut<Projections>>,
    mut commands: Commands,
) {
    if let Some(backend) = backend.as_mut()
        && let Ok(mut window) = windows.get_mut(trigger.entity)
    {
        backend.remove(window.id());
        window.set_presentation_offset(IVec2::ZERO);
        commands
            .entity(trigger.entity)
            .try_remove::<(ProjectionViewport, ProjectionPending)>();
    }
}

pub(super) fn enter_fullscreen(
    trigger: On<Add, super::NativeFullscreenMarker>,
    strips: Query<&super::layout::LayoutStrip>,
    mut windows: Query<&mut Window>,
    mut backend: Option<NonSendMut<Projections>>,
    mut commands: Commands,
) {
    let (Some(backend), Ok(strip)) = (backend.as_mut(), strips.get(trigger.entity)) else {
        return;
    };
    for entity in strip.all_windows() {
        if let Ok(mut window) = windows.get_mut(entity) {
            backend.remove(window.id());
            window.set_presentation_offset(IVec2::ZERO);
            commands
                .entity(entity)
                .try_remove::<(ProjectionViewport, ProjectionPending)>();
        }
    }
}

pub(crate) fn native_body(frame: IRect, padding: IVec2) -> IRect {
    IRect::from_corners(frame.min + padding, frame.max - padding)
}

pub(crate) fn contained(frame: IRect, viewport: IRect, padding: IVec2) -> bool {
    let body = native_body(frame, padding);
    body.min.cmpge(viewport.min).all() && body.max.cmple(viewport.max).all()
}

/// Keep the native app frame on its owner. Oversized native minimums are
/// centered rather than shrunk; the compositor clips their outside portion.
pub(crate) fn safe_anchor(frame: IRect, viewport: IRect, padding: IVec2) -> IVec2 {
    let size = native_body(frame, padding).size();
    let max = viewport.max - size;
    let mut origin = (frame.min + padding).clamp(viewport.min, max.max(viewport.min));
    if size.x > viewport.width() {
        origin.x = viewport.center().x - size.x / 2;
    }
    if size.y > viewport.height() {
        origin.y = viewport.center().y - size.y / 2;
    }
    origin - padding
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::ecs::schedule::ScheduleLabel;

    #[test]
    fn native_fullscreen_retires_owned_presentation_and_coordinate_offset() {
        use crate::manager::MockWindowApi;
        use crate::manager::projection::MockProjectionApi;
        let clip = IRect::new(0, 20, 1024, 768);
        let mut api = MockProjectionApi::new();
        api.expect_create().returning(|_, _| Ok(1300));
        api.expect_attached().return_const(true);
        api.expect_destroy().times(1).return_const(());
        let mut backend = Projections::new(Box::new(api));
        assert!(backend.prepare(42, clip).unwrap());
        let mut api = MockWindowApi::new();
        api.expect_id().return_const(42);
        api.expect_reposition().times(0);
        api.expect_resize().times(0);
        let mut window = Window::new(Box::new(api));
        window.set_presentation_offset(IVec2::new(1000, 0));
        let mut app = App::new();
        app.insert_non_send(backend).add_observer(enter_fullscreen);
        let window = app
            .world_mut()
            .spawn((
                window,
                ProjectionViewport {
                    clip,
                    hidden: true,
                    suspended: false,
                },
                ProjectionPending,
            ))
            .id();
        app.world_mut().spawn((
            super::super::layout::LayoutStrip::fullscreen(9, window),
            super::super::NativeFullscreenMarker {
                layout_strip: Entity::PLACEHOLDER,
                workspace_id: 3,
                index: 0,
            },
        ));
        assert!(!app.world().get::<Window>(window).unwrap().is_projected());
        assert!(app.world().get::<ProjectionViewport>(window).is_none());
        assert!(app.world().get::<ProjectionPending>(window).is_none());
        assert!(
            !app.world()
                .get_non_send::<Projections>()
                .unwrap()
                .owns(1300)
        );
    }

    #[test]
    fn native_space_suspension_hides_projection_without_moving_or_resizing_the_app() {
        use crate::manager::MockWindowApi;
        use crate::manager::projection::MockProjectionApi;
        use mockall::predicate::eq;
        let native = IRect::new(0, 20, 400, 768);
        let clip = IRect::new(0, 20, 1024, 768);
        let target = IRect::new(1000, 20, 1400, 768);
        let mut window = MockWindowApi::new();
        window.expect_id().return_const(42);
        window.expect_frame().return_const(native);
        window.expect_horizontal_padding().return_const(0);
        window.expect_vertical_padding().return_const(0);
        window.expect_reposition().times(0);
        window.expect_resize().times(0);
        let mut window = Window::new(Box::new(window));
        let mut api = MockProjectionApi::new();
        api.expect_create().returning(|_, _| Ok(1300));
        api.expect_attached().return_const(true);
        api.expect_translate()
            .with(eq(1300), eq(IVec2::new(1000, 0)))
            .times(2)
            .returning(|_, _| Ok(()));
        api.expect_visible()
            .with(eq(1300), eq(true))
            .times(2)
            .returning(|_, _| Ok(()));
        api.expect_visible()
            .with(eq(1300), eq(false))
            .times(1)
            .returning(|_, _| Ok(()));
        api.expect_destroy()
            .with(eq(1300))
            .times(1)
            .return_const(());
        let mut backend = Projections::new(Box::new(api));
        assert!(backend.prepare(42, clip).unwrap());
        let mut viewport = ProjectionViewport {
            clip,
            hidden: false,
            suspended: false,
        };
        commit(&mut backend, &mut window, viewport, target).unwrap();
        assert_eq!(window.frame(), target);
        viewport.suspended = true;
        commit(&mut backend, &mut window, viewport, target).unwrap();
        assert_eq!(window.frame(), native);
        viewport.suspended = false;
        commit(&mut backend, &mut window, viewport, target).unwrap();
        assert_eq!(window.frame(), target);
    }

    #[test]
    fn native_content_width_stays_fixed_through_navigation_and_exit_cleans_spaces() {
        use crate::commands::{Command, Direction, Operation};
        use crate::events::Event;
        use crate::manager::projection::MockProjectionApi;
        use crate::tests::TestHarness;
        use std::sync::{Arc, Mutex};
        use std::time::Duration;

        let destroyed = Arc::new(Mutex::new(Vec::new()));
        let mut api = MockProjectionApi::new();
        api.expect_create()
            .returning(|window, _| Ok(10000 + u64::try_from(window).unwrap()));
        let polls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        api.expect_attached()
            .returning(move |_, _| polls.fetch_add(1, std::sync::atomic::Ordering::Relaxed) >= 4);
        api.expect_translate().returning(|_, _| Ok(()));
        api.expect_visible().returning(|_, _| Ok(()));
        api.expect_clip().returning(|_, _| Ok(()));
        let record = destroyed.clone();
        api.expect_destroy()
            .returning(move |space| record.lock().unwrap().push(space));
        let path =
            std::env::temp_dir().join(format!("ribbon-projection-{}.toml", std::process::id()));
        std::fs::write(&path, "[options]\ncompact_parking = true\nfill_available_width = false\n[padding]\ntop = -6\nbottom = -6\nleft = 6\nright = 6\n[windows.spacing]\ntitle = '.*'\nhorizontal_padding = 6\nvertical_padding = 6\n").unwrap();
        let config = Config::new(&path).unwrap();
        std::fs::remove_file(path).unwrap();
        let mut h = TestHarness::new().with_config(config).with_windows(4);
        h.world().insert_non_send(Projections::new(Box::new(api)));
        h.world().insert_resource(ProjectionEnabled);
        h.world().init_resource::<NativeVisibleSpaces>();
        for label in [
            First.intern(),
            PreUpdate.intern(),
            Update.intern(),
            PostUpdate.intern(),
            Last.intern(),
        ] {
            h.app.edit_schedule(label, |schedule| {
                schedule.set_executor(bevy::ecs::schedule::SingleThreadedExecutor::new());
            });
        }
        h.advance(Duration::from_secs(1));
        assert_eq!(
            h.world()
                .query::<&ProjectionViewport>()
                .iter(h.world())
                .count(),
            4
        );
        assert!(
            h.world()
                .query::<&Window>()
                .iter(h.world())
                .any(Window::is_projected),
            "overflow must exercise the compositor path"
        );
        assert!(
            h.world()
                .query::<&Window>()
                .iter(h.world())
                .all(|window| window.native_frame().height() < 1000),
            "pending attachment must replay native height commits"
        );
        for direction in [
            Direction::Last,
            Direction::First,
            Direction::Last,
            Direction::First,
        ] {
            h.world().write_message(Event::Command {
                command: Command::Window(Operation::Focus(direction)),
            });
            for _ in 0..30 {
                h.advance(Duration::from_millis(20));
                let world = h.world();
                let widths: Vec<_> = world
                    .query::<&Window>()
                    .iter(world)
                    .map(|w| w.native_frame().width())
                    .collect();
                assert_eq!(
                    widths,
                    vec![400; 4],
                    "edge motion must never squeeze native content"
                );
            }
        }
        h.world().write_message(AppExit::Success);
        h.advance(Duration::from_millis(20));
        let mut removed = destroyed.lock().unwrap().clone();
        removed.sort_unstable();
        assert_eq!(removed, [10000, 10001, 10002, 10003]);
    }

    #[test]
    fn peeking_keeps_native_dimensions_and_anchors_on_owner() {
        let viewport = IRect::new(0, 30, 2560, 1331);
        let frame = IRect::new(2528, 30, 5088, 1331);
        let padding = IVec2::new(6, 0);
        assert!(!contained(frame, viewport, padding));
        let anchor = safe_anchor(frame, viewport, padding);
        let native = IRect::from_corners(anchor, anchor + frame.size());
        assert_eq!(native.size(), frame.size());
        assert!(contained(native, viewport, padding));
        assert_eq!(anchor, IVec2::new(6, 30));
    }

    #[test]
    fn negative_coordinates_and_oversized_native_minimum_are_preserved() {
        let viewport = IRect::new(-1728, 200, 0, 1300);
        let frame = IRect::new(-3000, 200, -1000, 1500);
        assert_eq!(
            safe_anchor(frame, viewport, IVec2::ZERO),
            IVec2::new(-1864, 100)
        );
    }
}
