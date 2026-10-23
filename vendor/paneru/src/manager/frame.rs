//! One native round trip for position and size, with a per-window compatibility fallback.
use std::ptr::{NonNull, null};

use accessibility_sys::{
    AXUIElementCopyMultipleAttributeValues, AXUIElementRef, AXValueGetTypeID, AXValueGetValue,
    kAXCopyMultipleAttributeOptionStopOnError, kAXErrorAttributeUnsupported, kAXErrorFailure,
    kAXErrorNotImplemented, kAXErrorSuccess, kAXPositionAttribute, kAXSizeAttribute,
    kAXValueTypeCGPoint, kAXValueTypeCGSize,
};
use objc2_core_foundation::{CFArray, CFGetTypeID, CFRetained, CFString, CFType, CGRect};

use crate::errors::{Error, Result};
use crate::performance::{Metric, measure};
use crate::platform::OSStatus;
use crate::util::AXUIAttributes;
use crate::util::AXUIWrapper;

thread_local! {
    // These are immutable names, not window state. Each AX worker owns its array.
    static ATTRIBUTES: CFRetained<CFArray<CFString>> = CFArray::from_objects(&[
        &CFString::from_static_str(kAXPositionAttribute),
        &CFString::from_static_str(kAXSizeAttribute),
    ]);
}

#[derive(Debug)]
pub(super) struct FrameReader {
    sequential_only: bool,
}

impl Default for FrameReader {
    fn default() -> Self {
        Self {
            sequential_only: crate::performance::comparison_baseline(),
        }
    }
}

impl FrameReader {
    pub fn read(&mut self, element: &CFRetained<AXUIWrapper>) -> Result<CGRect> {
        self.read_with(
            || batch_frame(element.as_ptr()),
            || sequential_frame(element),
        )
    }

    fn read_with(
        &mut self,
        batch: impl FnOnce() -> std::result::Result<CGRect, OSStatus>,
        sequential: impl FnOnce() -> Result<CGRect>,
    ) -> Result<CGRect> {
        if !self.sequential_only {
            match batch() {
                Ok(frame) => return Ok(frame),
                Err(status) => {
                    // Never cache a transient busy-app error or malformed response.
                    self.sequential_only =
                        status == kAXErrorNotImplemented || status == kAXErrorAttributeUnsupported;
                }
            }
        }
        sequential()
    }
}

fn batch_frame(element: AXUIElementRef) -> std::result::Result<CGRect, OSStatus> {
    let _query = measure(Metric::FrameQuery);
    let mut raw = null();
    let status = ATTRIBUTES.with(|attributes| unsafe {
        AXUIElementCopyMultipleAttributeValues(
            element,
            NonNull::from(&**attributes).as_ptr().cast(),
            kAXCopyMultipleAttributeOptionStopOnError,
            &raw mut raw,
        )
    });
    // Retain ownership even when an app returns an error alongside a partial array.
    let values = NonNull::new(raw.cast_mut().cast::<CFArray<CFType>>())
        .map(|ptr| unsafe { CFRetained::from_raw(ptr) });
    if status != kAXErrorSuccess {
        return Err(status);
    }
    values
        .as_deref()
        .and_then(decode_array)
        .ok_or(kAXErrorFailure)
}

fn sequential_frame(element: &CFRetained<AXUIWrapper>) -> Result<CGRect> {
    let position = {
        let _query = measure(Metric::FrameQuery);
        element.get_attribute::<CFType>(&CFString::from_static_str(kAXPositionAttribute))?
    };
    let size = {
        let _query = measure(Metric::FrameQuery);
        element.get_attribute::<CFType>(&CFString::from_static_str(kAXSizeAttribute))?
    };
    decode_frame(&position, &size)
        .ok_or_else(|| Error::invalid_window("Invalid native position or size"))
}

fn decode_array(values: &CFArray<CFType>) -> Option<CGRect> {
    if values.len() != 2 {
        return None;
    }
    decode_frame(&*values.get(0)?, &*values.get(1)?)
}

fn decode_frame(position: &CFType, size: &CFType) -> Option<CGRect> {
    // AX can return CFNull, an AXError value, or a wrongly typed app response.
    // Check the CF type before calling AXValueGetValue on either object.
    let value_type = unsafe { AXValueGetTypeID() };
    if CFGetTypeID(Some(position)) != value_type || CFGetTypeID(Some(size)) != value_type {
        return None;
    }
    let mut frame = CGRect::default();
    let decoded = unsafe {
        AXValueGetValue(
            NonNull::from(position).as_ptr().cast(),
            kAXValueTypeCGPoint,
            NonNull::from(&mut frame.origin).as_ptr().cast(),
        ) && AXValueGetValue(
            NonNull::from(size).as_ptr().cast(),
            kAXValueTypeCGSize,
            NonNull::from(&mut frame.size).as_ptr().cast(),
        )
    };
    let values = [
        frame.origin.x,
        frame.origin.y,
        frame.size.width,
        frame.size.height,
    ];
    (decoded
        && values
            .iter()
            .all(|v| v.is_finite() && v.abs() < f64::from(i32::MAX) / 2.0)
        && frame.size.width > 0.0
        && frame.size.height > 0.0)
        .then_some(frame)
}

#[cfg(test)]
mod tests {
    use super::*;
    use accessibility_sys::{AXValueCreate, kAXErrorCannotComplete, kAXValueTypeAXError};
    use objc2_core_foundation::{CGPoint, CGSize};

    fn value<T>(kind: u32, data: &T) -> CFRetained<CFType> {
        let raw = unsafe { AXValueCreate(kind, NonNull::from(data).as_ptr().cast()) };
        unsafe { CFRetained::from_raw(NonNull::new(raw).unwrap().cast()) }
    }

    #[test]
    fn batch_decodes_geometry_without_losing_negative_origins_or_odd_sizes() {
        let point = value(kAXValueTypeCGPoint, &CGPoint::new(-1728.0, 355.0));
        let size = value(kAXValueTypeCGSize, &CGSize::new(399.0, 701.0));
        let frame = decode_array(&CFArray::from_objects(&[&*point, &*size])).unwrap();
        assert_eq!(frame.origin, CGPoint::new(-1728.0, 355.0));
        assert_eq!(frame.size, CGSize::new(399.0, 701.0));
    }

    #[test]
    fn malformed_partial_error_and_nonfinite_values_do_not_become_geometry() {
        let point = value(kAXValueTypeCGPoint, &CGPoint::new(5.0, 7.0));
        let size = value(kAXValueTypeCGSize, &CGSize::new(399.0, 701.0));
        let error = value(kAXValueTypeAXError, &kAXErrorCannotComplete);
        assert!(decode_array(&CFArray::from_objects(&[&*point])).is_none());
        assert!(decode_frame(&size, &point).is_none());
        assert!(decode_frame(&point, &error).is_none());
        assert!(decode_frame(&CFString::from_static_str("wrong type"), &size).is_none());
        for width in [f64::NAN, f64::INFINITY, -1.0, 0.0, f64::MAX] {
            let invalid = value(kAXValueTypeCGSize, &CGSize::new(width, 701.0));
            assert!(decode_frame(&point, &invalid).is_none());
        }
    }

    #[test]
    fn confirmed_unsupported_batch_uses_one_fallback_for_the_windows_lifetime() {
        let mut reader = FrameReader::default();
        let frame = CGRect::default();
        assert!(
            reader
                .read_with(|| Err(kAXErrorNotImplemented), || Ok(frame))
                .is_ok()
        );
        assert!(
            reader
                .read_with(|| panic!("unsupported batch retried"), || Ok(frame))
                .is_ok()
        );
    }

    #[test]
    fn transient_failure_retries_batch_and_never_returns_a_fabricated_frame() {
        let mut reader = FrameReader::default();
        assert!(
            reader
                .read_with(|| Err(kAXErrorCannotComplete), || Err(Error::InvalidWindow))
                .is_err()
        );
        let frame = CGRect::new(CGPoint::new(12.0, 30.0), CGSize::new(800.0, 600.0));
        assert_eq!(
            reader
                .read_with(|| Ok(frame), || panic!("successful batch fell back"))
                .unwrap(),
            frame
        );
    }
}
