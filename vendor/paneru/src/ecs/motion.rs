//! Bounded, retargetable native geometry motion. Layout still supplies every target.
use bevy::math::{DVec2, IVec2};

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
}

impl Motion {
    /// Retain fractional points between AX commits. A Hermite segment ends at
    /// zero velocity in bounded time instead of rounding an exponential tail.
    /// Retargeting carries velocity, limited per axis to prevent overshoot.
    pub fn step(&mut self, frame: IVec2, target: IVec2, rate: f64, delta: f64) -> (IVec2, bool) {
        if rate >= 10_000.0 || !rate.is_finite() || rate <= 0.0 {
            return (target, true);
        }
        let fresh = self.duration == 0.0 || frame != self.output;
        if fresh {
            self.current = frame.as_dvec2();
            self.velocity = DVec2::ZERO;
        }
        if fresh || target != self.target {
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
        let step = delta.clamp(0.0, if fresh { 1.0 / 120.0 } else { 1.0 / 30.0 });
        self.elapsed += step;
        let t = (self.elapsed / self.duration).min(1.0);
        let distance = self.target.as_dvec2() - self.start;
        let tangent = self.tangent;
        self.current = self.start
            + distance * (3.0 * t * t - 2.0 * t * t * t)
            + tangent * (t * t * t - 2.0 * t * t + t);
        self.velocity = (distance * (6.0 * t - 6.0 * t * t)
            + tangent * (3.0 * t * t - 4.0 * t + 1.0))
            / self.duration;
        self.output = self.current.round().as_ivec2();
        (self.output, t >= 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settles_exactly_without_overshoot_at_different_refresh_rates() {
        for (hz, frames) in [(30.0, 30), (60.0, 60), (120.0, 120)] {
            let mut motion = Motion::default();
            let target = IVec2::new(2000, -400);
            let mut frame = IVec2::ZERO;
            let mut done = false;
            for _ in 0..frames {
                let (next, finished) = motion.step(frame, target, 14.0, 1.0 / hz);
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
            frame = motion.step(frame, IVec2::splat(1000), 14.0, 1.0 / 120.0).0;
        }
        let interrupted = frame;
        let target = IVec2::splat(-200);
        for _ in 0..40 {
            let next = motion.step(frame, target, 14.0, 1.0 / 120.0).0;
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
        let first = motion.step(IVec2::ZERO, IVec2::splat(1000), 14.0, 2.0).0;
        assert!(first.x > 0 && first.x < 100);
        let mut tiny = Motion::default();
        let mut frame = IVec2::ZERO;
        for _ in 0..40 {
            frame = tiny.step(frame, IVec2::ONE, 8.0, 1.0 / 120.0).0;
        }
        assert_eq!(frame, IVec2::ONE);
        assert_eq!(
            Motion::default().step(frame, IVec2::splat(1000), 1_000_000.0, 0.001),
            (IVec2::splat(1000), true)
        );
    }
}
