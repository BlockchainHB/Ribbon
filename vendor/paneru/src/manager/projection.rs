//! App-owned compositor spaces. App frames stay on their owning display while
//! the presentation moves and clips, without resizing the app to an edge slot.
use std::collections::HashMap;
use std::ffi::{CStr, c_void};
use std::ptr::{NonNull, null};
use std::time::{Duration, Instant};

use bevy::math::{IRect, IVec2};
use objc2::rc::{Allocated, Retained};
use objc2::runtime::{AnyClass, AnyObject};
use objc2::{MainThreadMarker, msg_send, sel};
use objc2_core_foundation::{
    CFArray, CFDictionary, CFRetained, CFType, CGAffineTransform, CGPoint, CGRect, CGSize,
};
use objc2_foundation::{NSArray, NSNumber};

use crate::errors::{Error, Result};
use crate::platform::{ConnID, WinID, WorkspaceId};
use crate::util::create_array;
use objc2_core_foundation::CFNumberType;

use super::skylight::SLSMainConnectionID;

const ATTACH_TIMEOUT: Duration = Duration::from_millis(750);

/// The platform boundary is deliberately small; layout, order and width policy
/// remain in ECS. Tests can drive attachment and cleanup without desktop APIs.
#[cfg_attr(test, mockall::automock)]
pub(crate) trait ProjectionApi {
    fn create(&mut self, window: WinID, viewport: IRect) -> Result<WorkspaceId>;
    fn attached(&self, space: WorkspaceId, window: WinID) -> bool;
    fn clip(&mut self, space: WorkspaceId, viewport: IRect) -> Result<()>;
    fn translate(&mut self, space: WorkspaceId, offset: IVec2) -> Result<()>;
    fn visible(&mut self, space: WorkspaceId, visible: bool) -> Result<()>;
    fn destroy(&mut self, space: WorkspaceId);
}

struct Entry {
    space: WorkspaceId,
    viewport: IRect,
    offset: IVec2,
    visible: bool,
    ready: bool,
    deadline: Instant,
}

/// `NonSend` resource: its native resources and every operation stay on the main
/// thread. Keeping native handles here avoids FFI in a Send window's destructor.
pub(crate) struct Projections {
    api: Box<dyn ProjectionApi>,
    entries: HashMap<WinID, Entry>,
}

impl Projections {
    pub(crate) fn native() -> Result<Self> {
        Ok(Self::new(Box::new(NativeApi::new()?)))
    }

    pub(crate) fn new(api: Box<dyn ProjectionApi>) -> Self {
        Self {
            api,
            entries: HashMap::new(),
        }
    }

    /// Prepare hidden spaces before a window reaches a monitor boundary.
    pub(crate) fn prepare(&mut self, window: WinID, viewport: IRect) -> Result<bool> {
        if !self.entries.contains_key(&window) {
            let space = self.api.create(window, viewport)?;
            tracing::debug!(window, space, "prepared hidden compositor space");
            self.entries.insert(
                window,
                Entry {
                    space,
                    viewport,
                    offset: IVec2::ZERO,
                    visible: false,
                    ready: false,
                    deadline: Instant::now() + ATTACH_TIMEOUT,
                },
            );
        }
        let entry = self.entries.get_mut(&window).ok_or(Error::InvalidWindow)?;
        if !entry.ready {
            entry.ready = self.api.attached(entry.space, window);
            tracing::debug!(
                window,
                space = entry.space,
                ready = entry.ready,
                "compositor attachment readback"
            );
            if !entry.ready && Instant::now() >= entry.deadline {
                return Err(Error::Generic(format!(
                    "compositor attachment timed out for window {window}"
                )));
            }
        }
        Ok(entry.ready)
    }

    pub(crate) fn present(&mut self, window: WinID, viewport: IRect, offset: IVec2) -> Result<()> {
        let entry = self.entries.get_mut(&window).ok_or(Error::InvalidWindow)?;
        if !entry.ready {
            return Err(Error::Generic("compositor attachment is pending".into()));
        }
        if entry.viewport != viewport {
            self.api.clip(entry.space, viewport)?;
            entry.viewport = viewport;
        }
        if !entry.visible || entry.offset != offset {
            self.api.translate(entry.space, offset)?;
            entry.offset = offset;
        }
        if !entry.visible {
            self.api.visible(entry.space, true)?;
            entry.visible = true;
        }
        Ok(())
    }

    pub(crate) fn hide(&mut self, window: WinID) -> Result<()> {
        if let Some(entry) = self.entries.get_mut(&window)
            && entry.visible
        {
            self.api.visible(entry.space, false)?;
            entry.visible = false;
        }
        Ok(())
    }

    pub(crate) fn remove(&mut self, window: WinID) {
        if let Some(entry) = self.entries.remove(&window) {
            self.api.destroy(entry.space);
        }
    }

    pub(crate) fn owns(&self, space: WorkspaceId) -> bool {
        self.entries.values().any(|entry| entry.space == space)
    }

    pub(crate) fn clear(&mut self) {
        for (_, entry) in self.entries.drain() {
            self.api.destroy(entry.space);
        }
    }
}

impl Drop for Projections {
    fn drop(&mut self) {
        self.clear();
    }
}

type CreateSpace = unsafe extern "C" fn(ConnID, u32, *const CFDictionary) -> WorkspaceId;
type DestroySpace = unsafe extern "C" fn(ConnID, WorkspaceId);
type SpaceLevel = unsafe extern "C" fn(ConnID, WorkspaceId, i32);
type NewRegion = unsafe extern "C" fn(*const CGRect, *mut *mut c_void) -> i32;
type SpaceShape = unsafe extern "C" fn(ConnID, WorkspaceId, *const c_void);
// Current ABI includes options. The transform is a C struct passed by value.
type SpaceTransform = unsafe extern "C" fn(ConnID, WorkspaceId, CGAffineTransform, u32);
type SpaceVisibility = unsafe extern "C" fn(ConnID, *const CFArray);

struct NativeApi {
    _main_thread: MainThreadMarker,
    connection: ConnID,
    create: CreateSpace,
    destroy: DestroySpace,
    level: SpaceLevel,
    region: NewRegion,
    shape: SpaceShape,
    transform: SpaceTransform,
    show: SpaceVisibility,
    hide: SpaceVisibility,
    add_class: &'static AnyClass,
}

impl NativeApi {
    fn new() -> Result<Self> {
        if crate::platform::macos_major_version() < 26 {
            return Err(Error::Generic(
                "fixed-content compositor requires macOS 26 or newer".into(),
            ));
        }
        let marker = MainThreadMarker::new().ok_or_else(|| {
            Error::Generic("compositor presentation requires the main thread".into())
        })?;
        let add_class = AnyClass::get(c"SLSBridgedSpaceAddWindowsAndRemoveFromSpacesOperation")
            .ok_or_else(|| Error::Generic("native compositor bridge unavailable".into()))?;
        if add_class
            .instance_method(sel!(initWithSpaceID:windows:options:))
            .is_none()
            || add_class
                .instance_method(sel!(performWithWMBridgeDelegate))
                .is_none()
        {
            return Err(Error::Generic(
                "native compositor bridge methods unavailable".into(),
            ));
        }
        macro_rules! symbol {
            ($name:literal, $ty:ty) => {{
                let pointer = load_symbol($name)?;
                // The ABI is verified against current runtime headers and native
                // fixture tests; no private framework image is loaded or patched.
                unsafe { std::mem::transmute::<*mut c_void, $ty>(pointer) }
            }};
        }
        Ok(Self {
            _main_thread: marker,
            connection: unsafe { SLSMainConnectionID() },
            create: symbol!(c"SLSSpaceCreate", CreateSpace),
            destroy: symbol!(c"SLSSpaceDestroy", DestroySpace),
            level: symbol!(c"SLSSpaceSetAbsoluteLevel", SpaceLevel),
            region: symbol!(c"CGSNewRegionWithRect", NewRegion),
            shape: symbol!(c"SLSSpaceSetShape", SpaceShape),
            transform: symbol!(c"SLSSpaceSetTransform", SpaceTransform),
            show: symbol!(c"SLSShowSpaces", SpaceVisibility),
            hide: symbol!(c"SLSHideSpaces", SpaceVisibility),
            add_class,
        })
    }

    fn set_shape(&self, space: WorkspaceId, viewport: IRect) -> Result<()> {
        let rect = CGRect::new(
            CGPoint::new(f64::from(viewport.min.x), f64::from(viewport.min.y)),
            CGSize::new(f64::from(viewport.width()), f64::from(viewport.height())),
        );
        let mut region = std::ptr::null_mut();
        let status = unsafe { (self.region)(&raw const rect, &raw mut region) };
        let pointer = NonNull::new(region)
            .ok_or_else(|| Error::Generic(format!("compositor clip creation failed: {status}")))?;
        let region: CFRetained<CFType> = unsafe { CFRetained::from_raw(pointer.cast()) };
        if status != 0 {
            return Err(Error::Generic(format!(
                "compositor clip creation failed: {status}"
            )));
        }
        unsafe { (self.shape)(self.connection, space, (&raw const *region).cast()) };
        Ok(())
    }
}

fn load_symbol(name: &CStr) -> Result<*mut c_void> {
    let pointer = unsafe { libc::dlsym(libc::RTLD_DEFAULT, name.as_ptr()) };
    if pointer.is_null() {
        Err(Error::Generic(format!(
            "compositor capability unavailable: {}",
            name.to_string_lossy()
        )))
    } else {
        Ok(pointer)
    }
}

impl ProjectionApi for NativeApi {
    fn create(&mut self, window: WinID, viewport: IRect) -> Result<WorkspaceId> {
        let space = unsafe { (self.create)(self.connection, 1, null()) };
        if space == 0 {
            return Err(Error::Generic("compositor space creation rejected".into()));
        }
        let result = (|| {
            unsafe { (self.level)(self.connection, space, 0) };
            self.set_shape(space, viewport)?;
            self.visible(space, false)?;
            let windows = NSArray::from_retained_slice(&[NSNumber::new_i32(window)]);
            let allocated: Allocated<AnyObject> = unsafe { msg_send![self.add_class, alloc] };
            let operation: Option<Retained<AnyObject>> = unsafe {
                msg_send![allocated, initWithSpaceID: space, windows: &*windows, options: 0u32]
            };
            let operation = operation
                .ok_or_else(|| Error::Generic("compositor attachment creation failed".into()))?;
            // This asynchronous method returns void. Preserve the original
            // managed Space membership; only add the app-owned presentation.
            let _: () = unsafe { msg_send![&*operation, performWithWMBridgeDelegate] };
            Ok(space)
        })();
        if result.is_err() {
            unsafe { (self.destroy)(self.connection, space) };
        }
        result
    }

    fn attached(&self, space: WorkspaceId, window: WinID) -> bool {
        super::space_window_list_for_connection(self.connection, &[space], None, true)
            .is_ok_and(|windows| windows.contains(&window))
    }

    fn clip(&mut self, space: WorkspaceId, viewport: IRect) -> Result<()> {
        self.set_shape(space, viewport)
    }

    fn translate(&mut self, space: WorkspaceId, offset: IVec2) -> Result<()> {
        let matrix = CGAffineTransform {
            a: 1.0,
            b: 0.0,
            c: 0.0,
            d: 1.0,
            tx: -f64::from(offset.x),
            ty: -f64::from(offset.y),
        };
        unsafe { (self.transform)(self.connection, space, matrix, 0) };
        Ok(())
    }

    fn visible(&mut self, space: WorkspaceId, visible: bool) -> Result<()> {
        let spaces = create_array(&[space], CFNumberType::SInt64Type)?;
        let function = if visible { self.show } else { self.hide };
        unsafe { function(self.connection, &raw const *spaces) };
        Ok(())
    }

    fn destroy(&mut self, space: WorkspaceId) {
        // Destroying an app-owned space removes only that presentation. The
        // window retains its original native Space throughout the session.
        unsafe { (self.destroy)(self.connection, space) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockall::Sequence;
    use mockall::predicate::eq;

    #[test]
    fn waits_for_attachment_and_commits_only_changed_native_state() {
        let viewport = IRect::new(0, 30, 2560, 1331);
        let offset = IVec2::new(2528, 0);
        let mut api = MockProjectionApi::new();
        let mut sequence = Sequence::new();
        api.expect_create()
            .with(eq(42), eq(viewport))
            .times(1)
            .in_sequence(&mut sequence)
            .returning(|_, _| Ok(1300));
        api.expect_attached()
            .with(eq(1300), eq(42))
            .times(1)
            .in_sequence(&mut sequence)
            .return_const(false);
        api.expect_attached()
            .with(eq(1300), eq(42))
            .times(1)
            .in_sequence(&mut sequence)
            .return_const(true);
        api.expect_translate()
            .with(eq(1300), eq(offset))
            .times(1)
            .in_sequence(&mut sequence)
            .returning(|_, _| Ok(()));
        api.expect_visible()
            .with(eq(1300), eq(true))
            .times(1)
            .in_sequence(&mut sequence)
            .returning(|_, _| Ok(()));
        api.expect_destroy()
            .with(eq(1300))
            .times(1)
            .in_sequence(&mut sequence)
            .return_const(());
        api.expect_clip().times(0);

        let mut projections = Projections::new(Box::new(api));
        assert!(!projections.prepare(42, viewport).unwrap());
        assert!(projections.present(42, viewport, offset).is_err());
        assert!(projections.prepare(42, viewport).unwrap());
        projections.present(42, viewport, offset).unwrap();
        projections.present(42, viewport, offset).unwrap();
        projections.remove(42);
        projections.remove(42);
    }
}
