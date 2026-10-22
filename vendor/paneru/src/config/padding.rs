use serde::Deserialize;

#[derive(Deserialize, Clone, Debug, Default)]
#[cfg_attr(test, derive(serde::Serialize))]
pub struct PaddingOptions {
    /// Padding applied at screen edges (in pixels). Independent from between-window gaps.
    /// Default: 0 on all sides.
    // Signed vertical offsets let Ribbon cancel per-window padding at the
    // outer edges while retaining padding between stacked windows.
    pub top: Option<i32>,
    pub bottom: Option<i32>,
    pub left: Option<u16>,
    pub right: Option<u16>,
}
