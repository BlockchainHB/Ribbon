//! Bounded, retargetable native geometry motion. Layout still supplies every target.
use super::layout::LayoutStrip;
use crate::manager::Display;
use bevy::ecs::{
    entity::Entity,
    hierarchy::ChildOf,
    query::{Or, With},
    resource::Resource,
    system::{Query, Res, SystemParam},
};
use bevy::math::{DVec2, IVec2};
use std::collections::{HashMap, HashSet};

/// Presence enables the experiment. Only this frame's owner ticks are stored;
/// layout, widths and membership remain in their existing ECS components.
#[derive(Default, Resource)]
pub(crate) struct FramePacing {
    pub due: HashSet<u32>,
}

/// Resolve the owner from the canonical strip membership, without another cache.
type MovingEntities<'w, 's> = Query<
    'w,
    's,
    Entity,
    Or<(
        With<super::RepositionMarker>,
        With<super::ResizeMarker>,
        With<super::Scrolling>,
    )>,
>;

#[derive(SystemParam)]
pub(crate) struct MotionOwners<'w, 's> {
    strips: Query<'w, 's, (&'static LayoutStrip, &'static ChildOf)>,
    displays: Query<'w, 's, &'static Display>,
    moving: MovingEntities<'w, 's>,
}

impl MotionOwners<'_, '_> {
    fn display_for(&self, entity: Entity) -> Option<&Display> {
        let parent = self
            .strips
            .get(entity)
            .ok()
            .map(|(_, parent)| parent)
            .or_else(|| {
                self.strips
                    .iter()
                    .find_map(|(strip, parent)| strip.contains(entity).then_some(parent))
            });
        parent.and_then(|parent| self.displays.get(parent.parent()).ok())
    }

    pub fn active_displays(&self) -> Vec<(u32, f64)> {
        self.moving
            .iter()
            .filter_map(|entity| self.display_for(entity))
            .map(|display| (display.id(), display.animation_interval()))
            .collect::<HashMap<_, _>>()
            .into_iter()
            .collect()
    }
}

#[derive(SystemParam)]
pub(super) struct MotionCadence<'w, 's> {
    owners: MotionOwners<'w, 's>,
    pacing: Option<Res<'w, FramePacing>>,
}

impl MotionCadence<'_, '_> {
    pub fn interval_for(&self, entity: Entity) -> f64 {
        if crate::performance::comparison_baseline() {
            return 0.0;
        }
        let display = self.owners.display_for(entity);
        if let (Some(pacing), Some(display)) = (&self.pacing, display) {
            // New intent and endpoints still bypass sampling inside Motion.
            // An owner tick must not pass through another elapsed-time cap.
            return if pacing.due.contains(&display.id()) {
                0.0
            } else {
                f64::INFINITY
            };
        }
        display.map_or(1.0 / 120.0, Display::animation_interval)
    }
}

#[derive(Default)]
pub(super) struct Motion {
    start: DVec2,
    current: DVec2,
    velocity: DVec2,
    tangent: DVec2,
    target: IVec2,
    output: IVec2,
    elapsed: f64,
    duration: f64,
    since_output: f64,
}

impl Motion {
    /// Retain fractional points between AX commits. A Hermite segment ends at
    /// zero velocity in bounded time instead of rounding an exponential tail.
    /// Retargeting carries velocity, limited per axis to prevent overshoot.
    pub fn step(
        &mut self,
        frame: IVec2,
        target: IVec2,
        rate: f64,
        delta: f64,
        interval: f64,
    ) -> (IVec2, bool) {
        if rate >= 10_000.0 || !rate.is_finite() || rate <= 0.0 {
            return (target, true);
        }
        let fresh = self.duration == 0.0 || frame != self.output;
        if fresh {
            self.current = frame.as_dvec2();
            self.velocity = DVec2::ZERO;
        }
        let retargeted = fresh || target != self.target;
        if !fresh && retargeted {
            // The curve may be ahead of the last sampled native frame. New
            // intent must start at what was actually presented, especially on
            // a reversal, rather than jumping to an uncommitted intermediate.
            self.current = frame.as_dvec2();
        }
        if retargeted {
            self.start = self.current;
            self.target = target;
            self.elapsed = 0.0;
            self.duration = (3.2 / rate).min(0.3);
            let distance = target.as_dvec2() - self.start;
            for axis in 0..2 {
                let limit = 3.0 * distance[axis] / self.duration;
                self.velocity[axis] = if fresh {
                    2.0 * distance[axis] / self.duration
                } else {
                    self.velocity[axis].clamp(limit.min(0.0), limit.max(0.0))
                };
            }
            self.tangent = self.velocity * self.duration;
        }
        // Do not charge an idle event-loop sleep to a newly started transition.
        // Once running, consume actual elapsed time. A slow AX app must not
        // stretch a 230 ms transition into a long tail after a stalled frame.
        let step = delta.clamp(
            0.0,
            if retargeted {
                1.0 / 120.0
            } else {
                self.duration
            },
        );
        self.elapsed += step;
        self.since_output += step;
        let t = (self.elapsed / self.duration).min(1.0);
        let distance = self.target.as_dvec2() - self.start;
        let tangent = self.tangent;
        self.current = self.start
            + distance * (3.0 * t * t - 2.0 * t * t * t)
            + tangent * (t * t * t - 2.0 * t * t + t);
        self.velocity = (distance * (6.0 * t - 6.0 * t * t)
            + tangent * (3.0 * t * t - 4.0 * t + 1.0))
            / self.duration;
        // AX notifications may wake the engine much faster than a display.
        // Advance the curve every time, but coalesce intermediate native targets.
        // New intent and the exact endpoint always bypass this sampling limit.
        if retargeted || t >= 1.0 || self.since_output + f64::EPSILON >= interval {
            self.output = self.current.round().as_ivec2();
            self.since_output = if retargeted || interval <= 0.0 {
                0.0
            } else {
                self.since_output % interval
            };
        }
        (self.output, t >= 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn moving_displays(world: &mut bevy::ecs::world::World) -> [Entity; 2] {
        use bevy::math::IRect;
        let mut members = Vec::new();
        for (id, hz) in [(2, 60.0), (1, 120.0)] {
            let display = world
                .spawn(Display::new(id, IRect::new(0, 0, 2560, 1440), 0).with_refresh_rate(hz))
                .id();
            let member = world
                .spawn(super::super::ResizeMarker(IVec2::new(800, 900)))
                .id();
            let mut strip = LayoutStrip::new(u64::from(id), 0);
            strip.append(member);
            world.spawn((strip, ChildOf(display)));
            members.push(member);
        }
        [members[0], members[1]]
    }

    #[test]
    fn pacing_uses_canonical_owner_and_only_the_owner_tick() {
        use bevy::ecs::{system::SystemState, world::World};
        let mut world = World::new();
        let [external, laptop] = moving_displays(&mut world);
        world.insert_resource(FramePacing {
            due: HashSet::from([1]),
        });
        let mut state = SystemState::<MotionCadence>::new(&mut world);
        let cadence = state.get(&world).unwrap();
        assert!(cadence.interval_for(external).is_infinite());
        assert!(cadence.interval_for(laptop).abs() < f64::EPSILON);
        let mut displays = cadence.owners.active_displays();
        displays.sort_by_key(|(id, _)| *id);
        assert_eq!(displays, vec![(1, 1.0 / 120.0), (2, 1.0 / 60.0)]);
        world
            .entity_mut(external)
            .remove::<super::super::ResizeMarker>();
        let cadence = state.get(&world).unwrap();
        assert_eq!(cadence.owners.active_displays(), vec![(1, 1.0 / 120.0)]);
    }

    #[test]
    fn display_tick_bypasses_second_cap_but_input_and_endpoint_remain_immediate() {
        let mut motion = Motion::default();
        let target = IVec2::splat(2000);
        let first = motion
            .step(IVec2::ZERO, target, 14.0, 0.001, f64::INFINITY)
            .0;
        assert!(first.x > 0);
        let held = motion.step(first, target, 14.0, 0.001, f64::INFINITY).0;
        assert_eq!(held, first);
        let tick = motion.step(held, target, 14.0, 0.006, 0.0).0;
        assert!(tick.x > held.x);
        let new_target = IVec2::splat(4000);
        let retarget = motion.step(tick, new_target, 14.0, 0.001, f64::INFINITY).0;
        assert!(retarget.x > tick.x);
        let (end, finished) = motion.step(retarget, new_target, 14.0, 0.5, f64::INFINITY);
        assert!(finished);
        assert_eq!(end, new_target);
    }

    #[test]
    fn reversal_between_samples_starts_at_the_last_presented_frame() {
        let mut motion = Motion::default();
        let mut frame = motion
            .step(IVec2::ZERO, IVec2::splat(2000), 14.0, 0.008, 1.0 / 60.0)
            .0;
        for _ in 0..10 {
            frame = motion
                .step(frame, IVec2::splat(2000), 14.0, 0.001, 1.0 / 60.0)
                .0;
        }
        assert!(motion.current.x > f64::from(frame.x) + 20.0);
        let target = IVec2::splat(-200);
        for _ in 0..250 {
            let next = motion.step(frame, target, 14.0, 0.001, 1.0 / 60.0).0;
            assert!(next.x <= frame.x && next.x >= target.x);
            frame = next;
        }
        assert_eq!(frame, target);
    }

    #[test]
    fn notification_storm_is_sampled_at_the_owner_cadence_without_extending_duration() {
        for (hz, limit) in [(60.0, 16), (120.0, 30)] {
            let mut motion = Motion::default();
            let mut frame = IVec2::ZERO;
            let target = IVec2::splat(2400);
            let mut writes = 0;
            let mut finished_at = None;
            for tick in 0..1000 {
                let (next, done) = motion.step(frame, target, 14.0, 0.001, 1.0 / hz);
                writes += usize::from(next != frame);
                frame = next;
                if done {
                    finished_at = Some(tick);
                    break;
                }
            }
            assert!(finished_at.unwrap() < 235);
            assert!(writes <= limit);
            assert_eq!(frame, target);
        }
    }

    #[test]
    fn new_intent_and_endpoint_bypass_sampling_and_stalls_do_not_stretch_motion() {
        let mut motion = Motion::default();
        let first = motion
            .step(IVec2::ZERO, IVec2::splat(2000), 14.0, 0.001, 0.1)
            .0;
        assert!(first.x > 0);
        let held = motion.step(first, IVec2::splat(2000), 14.0, 0.001, 0.1).0;
        assert_eq!(held, first);
        let retargeted = motion.step(held, IVec2::splat(4000), 14.0, 0.008, 0.1).0;
        assert!(retargeted.x > held.x);
        assert_eq!(
            motion.step(retargeted, IVec2::splat(4000), 14.0, 0.5, 0.1),
            (IVec2::splat(4000), true)
        );
    }

    #[test]
    fn settles_exactly_without_overshoot_at_different_refresh_rates() {
        for (hz, frames) in [(30.0, 30), (60.0, 60), (120.0, 120)] {
            let mut motion = Motion::default();
            let target = IVec2::new(2000, -400);
            let mut frame = IVec2::ZERO;
            let mut done = false;
            for _ in 0..frames {
                let (next, finished) = motion.step(frame, target, 14.0, 1.0 / hz, 1.0 / hz);
                assert!(next.x >= frame.x && next.x <= target.x);
                assert!(next.y <= frame.y && next.y >= target.y);
                frame = next;
                if finished {
                    done = true;
                    break;
                }
            }
            assert!(done);
            assert_eq!(frame, target);
            assert!(motion.elapsed <= 0.27);
        }
    }

    #[test]
    fn reversal_stays_continuous_and_does_not_overshoot() {
        let mut motion = Motion::default();
        let mut frame = IVec2::ZERO;
        for _ in 0..6 {
            frame = motion
                .step(frame, IVec2::splat(1000), 14.0, 1.0 / 120.0, 1.0 / 120.0)
                .0;
        }
        let interrupted = frame;
        let target = IVec2::splat(-200);
        for _ in 0..40 {
            let next = motion.step(frame, target, 14.0, 1.0 / 120.0, 1.0 / 120.0).0;
            assert!(next.x <= frame.x && next.x >= target.x);
            assert!((next.x - frame.x).abs() < 100);
            frame = next;
        }
        assert!(interrupted.x > 0);
        assert_eq!(frame, target);
    }

    #[test]
    fn subpixel_travel_finishes_and_idle_wakeup_does_not_jump() {
        let mut motion = Motion::default();
        let first = motion
            .step(IVec2::ZERO, IVec2::splat(1000), 14.0, 2.0, 1.0 / 60.0)
            .0;
        assert!(first.x > 0 && first.x < 100);
        let mut tiny = Motion::default();
        let mut frame = IVec2::ZERO;
        for _ in 0..40 {
            frame = tiny
                .step(frame, IVec2::ONE, 8.0, 1.0 / 120.0, 1.0 / 120.0)
                .0;
        }
        assert_eq!(frame, IVec2::ONE);
        assert_eq!(
            Motion::default().step(frame, IVec2::splat(1000), 1_000_000.0, 0.001, 1.0 / 60.0),
            (IVec2::splat(1000), true)
        );
    }
}
