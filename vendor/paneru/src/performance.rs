//! Opt-in, bounded engine measurements. No window titles, content or per-frame I/O.
use std::path::PathBuf;
use std::sync::LazyLock;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use bevy::app::{App, AppExit, Last, PreUpdate};
use bevy::prelude::*;
use serde_json::{Value, json};

use crate::ecs::params::FrameActivity;
use crate::ecs::systems::{cleanup_on_exit, demux_input_events, pump_events};

const BUCKET_US: u64 = 500;
const BUCKETS: usize = 256;

#[derive(Clone, Copy)]
#[repr(usize)]
pub(crate) enum Metric {
    ActiveFrame,
    IdleWork,
    Layout,
    Shrink,
    Move,
    Grow,
    Focus,
    FrameRead,
    FrameQuery,
    SizeWrite,
    PositionWrite,
    InputToGeometry,
}

const METRICS: [(Metric, &str); 12] = [
    (Metric::ActiveFrame, "active_frame_work"),
    (Metric::IdleWork, "idle_frame_work"),
    (Metric::Layout, "presentation_layout"),
    (Metric::Shrink, "native_shrink_phase"),
    (Metric::Move, "native_move_phase"),
    (Metric::Grow, "native_grow_phase"),
    (Metric::Focus, "native_focus"),
    (Metric::FrameRead, "frame_read"),
    (Metric::FrameQuery, "frame_query"),
    (Metric::SizeWrite, "size_write"),
    (Metric::PositionWrite, "position_write"),
    (
        Metric::InputToGeometry,
        "key_receipt_to_first_geometry_write",
    ),
];

struct Samples {
    count: AtomicU64,
    total_us: AtomicU64,
    max_us: AtomicU64,
    buckets: [AtomicU64; BUCKETS],
}

impl Default for Samples {
    fn default() -> Self {
        Self {
            count: AtomicU64::new(0),
            total_us: AtomicU64::new(0),
            max_us: AtomicU64::new(0),
            buckets: std::array::from_fn(|_| AtomicU64::new(0)),
        }
    }
}

impl Samples {
    fn record(&self, duration: Duration) {
        let micros = u64::try_from(duration.as_micros()).unwrap_or(u64::MAX);
        let bucket = usize::try_from(micros.saturating_sub(1) / BUCKET_US)
            .unwrap_or(BUCKETS - 1)
            .min(BUCKETS - 1);
        self.count.fetch_add(1, Ordering::Relaxed);
        self.total_us.fetch_add(micros, Ordering::Relaxed);
        self.max_us.fetch_max(micros, Ordering::Relaxed);
        self.buckets[bucket].fetch_add(1, Ordering::Relaxed);
    }

    fn snapshot(&self) -> Value {
        let count = self.count.load(Ordering::Relaxed);
        let maximum = self.max_us.load(Ordering::Relaxed);
        let buckets: Vec<_> = self
            .buckets
            .iter()
            .map(|b| b.load(Ordering::Relaxed))
            .collect();
        let percentile = |percent: u64| {
            if count == 0 {
                return 0;
            }
            let rank = (count * percent).div_ceil(100);
            let mut accumulated = 0;
            for (index, samples) in buckets.iter().enumerate() {
                accumulated += samples;
                if accumulated >= rank {
                    return if index == BUCKETS - 1 {
                        maximum
                    } else {
                        (index as u64 + 1) * BUCKET_US
                    };
                }
            }
            maximum
        };
        json!({
            "count": count,
            "total_us": self.total_us.load(Ordering::Relaxed),
            "max_us": maximum,
            "p50_upper_us": percentile(50),
            "p95_upper_us": percentile(95),
            "p99_upper_us": percentile(99),
            "buckets": buckets,
        })
    }
}

struct Profile {
    output: PathBuf,
    comparison_baseline: bool,
    started: Instant,
    samples: [Samples; METRICS.len()],
    input_events: AtomicU64,
    pending_input_us: AtomicU64,
}

static PROFILE: LazyLock<Option<Profile>> = LazyLock::new(|| {
    std::env::var_os("RIBBON_PERF_OUTPUT")
        .filter(|path| !path.is_empty())
        .map(|output| Profile {
            output: output.into(),
            comparison_baseline: std::env::var("RIBBON_PERF_BASELINE").is_ok_and(|v| v == "1"),
            started: Instant::now(),
            samples: std::array::from_fn(|_| Samples::default()),
            input_events: AtomicU64::new(0),
            pending_input_us: AtomicU64::new(0),
        })
});

/// A/B only: the same signed binary retains all correctness guards. Ignored
/// unless opt-in profiling is enabled, and never exposed as a user setting.
pub(crate) fn comparison_baseline() -> bool {
    PROFILE
        .as_ref()
        .is_some_and(|profile| profile.comparison_baseline)
}

pub(crate) struct Measurement {
    metric: Metric,
    started: Option<Instant>,
}

pub(crate) fn measure(metric: Metric) -> Measurement {
    Measurement {
        metric,
        started: PROFILE.as_ref().map(|_| Instant::now()),
    }
}

impl Drop for Measurement {
    fn drop(&mut self) {
        if let Some(started) = self.started
            && let Some(profile) = PROFILE.as_ref()
        {
            profile.samples[self.metric as usize].record(started.elapsed());
        }
    }
}

pub(crate) fn input_received() {
    if let Some(profile) = PROFILE.as_ref() {
        profile.input_events.fetch_add(1, Ordering::Relaxed);
        let micros = u64::try_from(profile.started.elapsed().as_micros()).unwrap_or(u64::MAX - 1);
        profile
            .pending_input_us
            .store(micros + 1, Ordering::Relaxed);
    }
}

pub(crate) fn geometry_written() {
    if let Some(profile) = PROFILE.as_ref() {
        let input = profile.pending_input_us.swap(0, Ordering::Relaxed);
        if input != 0 {
            let now = u64::try_from(profile.started.elapsed().as_micros()).unwrap_or(u64::MAX);
            profile.samples[Metric::InputToGeometry as usize]
                .record(Duration::from_micros(now.saturating_sub(input - 1)));
        }
    }
}

fn writes(profile: &Profile) -> u64 {
    profile.samples[Metric::SizeWrite as usize]
        .count
        .load(Ordering::Relaxed)
        + profile.samples[Metric::PositionWrite as usize]
            .count
            .load(Ordering::Relaxed)
}

#[derive(Resource, Default)]
struct FrameProbe {
    started: Option<Instant>,
    writes: u64,
    active: bool,
}

fn begin_frame(mut probe: ResMut<FrameProbe>, activity: FrameActivity) {
    if let Some(profile) = PROFILE.as_ref() {
        probe.started = Some(Instant::now());
        probe.writes = writes(profile);
        probe.active = activity.mid_frame();
    }
}

fn end_frame(
    mut probe: ResMut<FrameProbe>,
    activity: FrameActivity,
    mut exit: MessageReader<AppExit>,
) {
    let Some(profile) = PROFILE.as_ref() else {
        return;
    };
    let exiting = exit.read().next().is_some();
    if let Some(started) = probe.started.take()
        && !exiting
    {
        let metric = if probe.active || activity.mid_frame() || writes(profile) != probe.writes {
            Metric::ActiveFrame
        } else {
            Metric::IdleWork
        };
        profile.samples[metric as usize].record(started.elapsed());
    }
    // A boundary key may legitimately cause no movement. Do not charge the
    // next unrelated frame to that key. Bursts measure the latest receipt.
    profile.pending_input_us.store(0, Ordering::Relaxed);
    if exiting && let Err(error) = flush(profile) {
        tracing::warn!(%error, "Unable to write opt-in performance report");
    }
}

fn flush(profile: &Profile) -> std::io::Result<()> {
    let metrics: serde_json::Map<_, _> = METRICS
        .iter()
        .map(|(metric, name)| {
            (
                (*name).to_string(),
                profile.samples[*metric as usize].snapshot(),
            )
        })
        .collect();
    let report = json!({
        "version": 1,
        "comparison_mode": if profile.comparison_baseline { "uncapped_sequential" } else { "optimized" },
        "elapsed_ms": profile.started.elapsed().as_millis(),
        "bucket_us": BUCKET_US,
        "key_receipts": profile.input_events.load(Ordering::Relaxed),
        "note": "Inclusive overlapping durations; native counters include startup and restoration. Frame work excludes event-loop waiting and exit restoration. Percentiles are histogram upper bounds, not compositor frame times.",
        "metrics": metrics,
    });
    if let Some(parent) = profile
        .output
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
    {
        std::fs::create_dir_all(parent)?;
    }
    let temporary = profile
        .output
        .with_extension(format!("{}.tmp", std::process::id()));
    std::fs::write(&temporary, serde_json::to_vec_pretty(&report)?)?;
    std::fs::rename(temporary, &profile.output)
}

pub(crate) fn register(app: &mut App) {
    if PROFILE.is_none() {
        return;
    }
    app.init_resource::<FrameProbe>();
    app.add_systems(
        PreUpdate,
        begin_frame.after(pump_events).before(demux_input_events),
    );
    app.add_systems(Last, end_frame.after(cleanup_on_exit));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn histogram_reports_bounds_and_keeps_slow_outliers() {
        let samples = Samples::default();
        for _ in 0..99 {
            samples.record(Duration::from_micros(750));
        }
        samples.record(Duration::from_millis(900));
        let report = samples.snapshot();
        assert_eq!(report["count"], 100);
        assert_eq!(report["p50_upper_us"], 1000);
        assert_eq!(report["p95_upper_us"], 1000);
        assert_eq!(report["max_us"], 900_000);
        assert_eq!(report["buckets"].as_array().unwrap().len(), BUCKETS);
    }

    #[test]
    fn empty_histogram_has_no_fabricated_latency() {
        let report = Samples::default().snapshot();
        assert_eq!(report["count"], 0);
        assert_eq!(report["p99_upper_us"], 0);
    }
}
