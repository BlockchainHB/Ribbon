//! Shallow, non-nested links between two existing columns. Identity is the full
//! set of generation-tagged window entities in each column, never its index or
//! current top window. Refresh after topology edits preserves a pair when a
//! stack/tab leader closes, and dissolves it when a column disappears.
use std::ops::Range;

use bevy::ecs::entity::{Entity, EntityHashSet};
use bevy::math::IRect;
use bevy::prelude::Component;

use super::{Column, LayoutStrip};
use crate::manager::Size;

#[derive(Component)]
pub(crate) struct ArrangeNeighbors(pub Entity, pub Entity);

#[derive(Clone, Debug)]
pub(super) struct ColumnPair {
    id: u64,
    members: [Vec<Entity>; 2],
    pub(super) fit: Option<f64>,
    pub(super) fitted_viewport: i32,
}

impl LayoutStrip {
    fn pair_indices(&self, pair: &ColumnPair) -> Option<Range<usize>> {
        let indices = pair.members.each_ref().map(|members| {
            self.columns.iter().position(|c| {
                !matches!(c, Column::Fullscren(_)) && c.window_iter().any(|e| members.contains(&e))
            })
        });
        let (left, right) = (indices[0]?, indices[1]?);
        (right == left + 1).then_some(left..right + 1)
    }

    pub(crate) fn pair_range(&self, entity: Entity) -> Option<Range<usize>> {
        let column = self.index_of(entity).ok()?;
        self.pairs.iter().find_map(|pair| {
            let range = self.pair_indices(pair)?;
            range.contains(&column).then_some(range)
        })
    }

    pub(crate) fn pair_id(&self, entity: Entity) -> Option<u64> {
        let column = self.index_of(entity).ok()?;
        self.pairs.iter().find_map(|pair| {
            self.pair_indices(pair)?
                .contains(&column)
                .then_some(pair.id)
        })
    }

    pub(crate) fn unpair(&mut self, entity: Entity) -> bool {
        let Some(id) = self.pair_id(entity) else {
            return false;
        };
        self.pairs.retain(|pair| pair.id != id);
        true
    }

    pub(crate) fn pair_with(&mut self, entity: Entity, right: bool) -> bool {
        self.refresh_pairs();
        let Ok(index) = self.index_of(entity) else {
            return false;
        };
        let Some(left) = (if right {
            Some(index)
        } else {
            index.checked_sub(1)
        }) else {
            return false;
        };
        let Some(a) = self.columns.get(left) else {
            return false;
        };
        let Some(b) = self.columns.get(left + 1) else {
            return false;
        };
        if [a, b].iter().any(|c| matches!(c, Column::Fullscren(_))) {
            return false;
        }
        let (Some(a_top), Some(b_top)) = (a.top(), b.top()) else {
            return false;
        };
        if self.pair_id(a_top).is_some() || self.pair_id(b_top).is_some() {
            return false;
        }
        self.pairs.push(ColumnPair {
            id: a_top.to_bits(),
            members: [a.window_iter().collect(), b.window_iter().collect()],
            fit: None,
            fitted_viewport: 0,
        });
        true
    }

    pub(super) fn refresh_pairs(&mut self) {
        self.pairs = self
            .pairs
            .iter()
            .filter_map(|pair| {
                let range = self.pair_indices(pair)?;
                Some(ColumnPair {
                    members: [
                        self.columns[range.start].window_iter().collect(),
                        self.columns[range.start + 1].window_iter().collect(),
                    ],
                    ..pair.clone()
                })
            })
            .collect();
    }

    pub(crate) fn movement_range(&self, entity: Entity) -> Option<Range<usize>> {
        self.pair_range(entity).or_else(|| {
            let index = self.index_of(entity).ok()?;
            Some(index..index + 1)
        })
    }

    pub(crate) fn movement_members(&self, entity: Entity) -> Vec<Entity> {
        self.movement_range(entity)
            .into_iter()
            .flat_map(|range| range.flat_map(|index| self.columns[index].window_iter()))
            .collect()
    }

    /// Insert a whole movement block beside another one. A drop onto one's own
    /// pair is a no-op; dropping onto another pair never splits that pair.
    pub(crate) fn reorder(&mut self, source: Entity, target: Entity, after: bool) -> bool {
        let (Some(from), Some(to)) = (self.movement_range(source), self.movement_range(target))
        else {
            return false;
        };
        if from == to {
            return false;
        }
        let at = if after { to.end } else { to.start };
        let count = from.len();
        let destination = if at > from.start { at - count } else { at };
        let columns = self.columns.drain(from).collect::<Vec<_>>();
        for (offset, column) in columns.into_iter().enumerate() {
            self.columns.insert(destination + offset, column);
        }
        self.refresh_pairs();
        true
    }

    /// Insertion between two linked columns is redirected past the whole pair.
    pub(super) fn insertion_index(&self, index: usize) -> usize {
        self.pairs
            .iter()
            .filter_map(|p| self.pair_indices(p))
            .find(|range| range.start < index && index < range.end)
            .map_or(index, |range| range.end)
    }

    pub(crate) fn reveal_frame<W>(
        &self,
        entity: Entity,
        height: i32,
        viewport: i32,
        frame: &W,
    ) -> Option<IRect>
    where
        W: Fn(Entity) -> Option<IRect>,
    {
        let range = self.pair_range(entity)?;
        let positions = self.column_positions(frame).collect::<Vec<_>>();
        let left = positions.get(range.start)?.1;
        let (column, x) = positions.get(range.end - 1)?;
        let width = x + column.width(frame)? - left;
        (width <= viewport).then(|| {
            IRect::from_corners(
                bevy::math::IVec2::new(left, 0),
                bevy::math::IVec2::new(left + width, height),
            )
        })
    }

    /// Transfer metadata only when every member transfers. Partial extraction
    /// deliberately dissolves the link. Never restore by application identity.
    pub(super) fn transfer_pairs(&mut self, moved: &EntityHashSet, target: &mut Self) {
        self.refresh_pairs();
        self.pairs.retain(|pair| {
            let all = pair.members.iter().flatten().all(|e| moved.contains(e));
            if all {
                let mut pair = pair.clone();
                pair.fitted_viewport = 0;
                target.pairs.push(pair);
            }
            !all
        });
    }

    pub(crate) fn fit_pair(&mut self, entity: Entity, ratio: f64) -> bool {
        if !ratio.is_finite() || !(0.1..=0.9).contains(&ratio) {
            return false;
        }
        let Some(id) = self.pair_id(entity) else {
            return false;
        };
        let pair = self.pairs.iter_mut().find(|p| p.id == id).unwrap();
        pair.fit = Some(ratio);
        pair.fitted_viewport = 0;
        true
    }

    pub(crate) fn forget_pair_fit(&mut self, entity: Entity) {
        let Some(id) = self.pair_id(entity) else {
            return;
        };
        if let Some(pair) = self.pairs.iter_mut().find(|p| p.id == id) {
            pair.fit = None;
        }
    }

    pub(super) fn pair_fit_requests<W>(&mut self, viewport: Size, frame: &W) -> Vec<(Entity, Size)>
    where
        W: Fn(Entity) -> Option<IRect>,
    {
        if !self
            .pairs
            .iter()
            .any(|p| p.fit.is_some() && p.fitted_viewport != viewport.x)
        {
            return Vec::new();
        }
        self.refresh_pairs();
        let mut requests = Vec::new();
        for pair in &mut self.pairs {
            let Some(ratio) = pair.fit else { continue };
            if pair.fitted_viewport == viewport.x || viewport.x < 2 {
                continue;
            }
            // Logical slots already contain horizontal padding. Split this
            // width once; subtracting a second gap would leave unused space.
            let first = crate::util::round_px((f64::from(viewport.x) * ratio).floor());
            for (members, width) in pair.members.iter().zip([first, viewport.x - first]) {
                for &entity in members {
                    if let Some(old) = frame(entity) {
                        requests.push((entity, old.size().with_x(width)));
                    }
                }
            }
            // Issue once per explicit fit or viewport change. A client refusing
            // the width must not cause an endless AX resize loop.
            pair.fitted_viewport = viewport.x;
        }
        requests
    }
}
