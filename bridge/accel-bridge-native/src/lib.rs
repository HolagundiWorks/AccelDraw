//! C ABI over `shilpi-client::Client`, so a managed host with no Rust
//! toolchain (AccelDraw.Plugin, .NET Framework 4.8) can talk to a running
//! `shilpid` by P/Invoke instead of speaking the wire protocol itself or
//! going through the `shilpi-http` HTTP hop.
//!
//! Layering mirrors AADT's `aadt-vdb` client: the entity <-> record mapping
//! (bbox + JSON payload) stays on the managed side, in
//! `AccelDraw.ShilpiDb`. This crate only proxies the four operations a CAD
//! host actually needs at the storage boundary: put, get, delete, query,
//! save. Every exported function is `unsafe` by necessity (raw pointers
//! across the FFI boundary) — that is the accepted exception to
//! `shilpidb`'s own `#![forbid(unsafe_code)]` policy, scoped to this one
//! bridge crate.

use std::cell::RefCell;
use std::ffi::{c_char, CStr};
use std::net::TcpStream;
use std::ptr;
use std::slice;

use shilpi_client::Client;
use shilpidb::Bbox;

thread_local! {
    static LAST_ERROR: RefCell<String> = RefCell::new(String::new());
}

fn set_last_error(msg: impl Into<String>) {
    LAST_ERROR.with(|cell| *cell.borrow_mut() = msg.into());
}

/// Opaque handle to a live connection. Owned by the caller once returned
/// from [`accel_bridge_connect`]; freed by [`accel_bridge_disconnect`].
pub struct AccelBridgeHandle {
    client: Client<TcpStream>,
}

/// Connects to `shilpid` at `addr` (a null-terminated UTF-8 string, e.g.
/// `"127.0.0.1:7420"`). Returns null on failure — call
/// [`accel_bridge_last_error`] for why.
///
/// # Safety
/// `addr` must be a valid pointer to a null-terminated C string for the
/// duration of the call.
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_connect(addr: *const c_char) -> *mut AccelBridgeHandle {
    if addr.is_null() {
        set_last_error("addr is null");
        return ptr::null_mut();
    }
    let addr = match CStr::from_ptr(addr).to_str() {
        Ok(s) => s,
        Err(e) => {
            set_last_error(format!("addr is not valid UTF-8: {e}"));
            return ptr::null_mut();
        }
    };

    match Client::connect(addr) {
        Ok(client) => Box::into_raw(Box::new(AccelBridgeHandle { client })),
        Err(e) => {
            set_last_error(format!("connect failed: {e}"));
            ptr::null_mut()
        }
    }
}

/// Closes and frees a handle returned by [`accel_bridge_connect`]. Safe to
/// call with null (no-op).
///
/// # Safety
/// `handle` must be either null or a pointer previously returned by
/// [`accel_bridge_connect`] that has not already been freed.
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_disconnect(handle: *mut AccelBridgeHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Inserts or replaces the record at `id`. Returns 0 on success, negative on failure.
///
/// # Safety
/// `handle` must be a live handle from [`accel_bridge_connect`]. `payload`
/// must point to at least `payload_len` readable bytes (or be null iff
/// `payload_len` is 0).
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_put(
    handle: *mut AccelBridgeHandle,
    id: u64,
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,
    payload: *const u8,
    payload_len: usize,
) -> i32 {
    let handle = match handle.as_mut() {
        Some(h) => h,
        None => {
            set_last_error("handle is null");
            return -1;
        }
    };

    let bytes = if payload_len == 0 {
        Vec::new()
    } else {
        slice::from_raw_parts(payload, payload_len).to_vec()
    };

    let bbox = Bbox::from_corners(min_x, min_y, max_x, max_y);
    match handle.client.insert(id, bbox, bytes) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(format!("put failed: {e}"));
            -2
        }
    }
}

/// Fetches the record at `id`. Returns 1 if found (and writes
/// `*out_payload`/`*out_len`/`*out_bbox`), 0 if not found, negative on
/// failure. A found payload must be freed with [`accel_bridge_free_bytes`].
///
/// # Safety
/// `handle` must be live. `out_payload`, `out_len` and `out_bbox` (a 4-`f64`
/// `[minX, minY, maxX, maxY]` buffer) must each point to valid, writable
/// storage of the right size.
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_get(
    handle: *mut AccelBridgeHandle,
    id: u64,
    out_payload: *mut *mut u8,
    out_len: *mut usize,
    out_bbox: *mut f64,
) -> i32 {
    let handle = match handle.as_mut() {
        Some(h) => h,
        None => {
            set_last_error("handle is null");
            return -1;
        }
    };

    match handle.client.get(id) {
        Ok(Some(record)) => {
            let mut boxed = record.payload.into_boxed_slice();
            *out_len = boxed.len();
            *out_payload = boxed.as_mut_ptr();
            std::mem::forget(boxed);

            let b = record.bbox;
            let corners = [b.min.x, b.min.y, b.max.x, b.max.y];
            ptr::copy_nonoverlapping(corners.as_ptr(), out_bbox, 4);
            1
        }
        Ok(None) => 0,
        Err(e) => {
            set_last_error(format!("get failed: {e}"));
            -2
        }
    }
}

/// Frees a byte buffer returned by [`accel_bridge_get`].
///
/// # Safety
/// `ptr`/`len` must be exactly the pointer and length written by a prior
/// [`accel_bridge_get`] call, not yet freed.
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_free_bytes(ptr_: *mut u8, len: usize) {
    if !ptr_.is_null() {
        drop(Box::from_raw(slice::from_raw_parts_mut(ptr_, len)));
    }
}

/// Deletes the record at `id`. Returns 1 if it existed, 0 if not, negative on failure.
///
/// # Safety
/// `handle` must be live.
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_delete(handle: *mut AccelBridgeHandle, id: u64) -> i32 {
    let handle = match handle.as_mut() {
        Some(h) => h,
        None => {
            set_last_error("handle is null");
            return -1;
        }
    };

    match handle.client.delete(id) {
        Ok(true) => 1,
        Ok(false) => 0,
        Err(e) => {
            set_last_error(format!("delete failed: {e}"));
            -2
        }
    }
}

/// Ids of records whose box intersects the given rectangle. Writes
/// `*out_ids`/`*out_count` on success (0 return); free with
/// [`accel_bridge_free_ids`]. Returns negative on failure.
///
/// # Safety
/// `handle` must be live. `out_ids`/`out_count` must point to valid,
/// writable storage.
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_query_bbox(
    handle: *mut AccelBridgeHandle,
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,
    out_ids: *mut *mut u64,
    out_count: *mut usize,
) -> i32 {
    let handle = match handle.as_mut() {
        Some(h) => h,
        None => {
            set_last_error("handle is null");
            return -1;
        }
    };

    let bbox = Bbox::from_corners(min_x, min_y, max_x, max_y);
    match handle.client.query_bbox(bbox) {
        Ok(ids) => {
            let mut boxed = ids.into_boxed_slice();
            *out_count = boxed.len();
            *out_ids = boxed.as_mut_ptr();
            std::mem::forget(boxed);
            0
        }
        Err(e) => {
            set_last_error(format!("query_bbox failed: {e}"));
            -2
        }
    }
}

/// Frees an id buffer returned by [`accel_bridge_query_bbox`].
///
/// # Safety
/// `ptr`/`len` must be exactly the pointer and length written by a prior
/// [`accel_bridge_query_bbox`] call, not yet freed.
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_free_ids(ptr_: *mut u64, len: usize) {
    if !ptr_.is_null() {
        drop(Box::from_raw(slice::from_raw_parts_mut(ptr_, len)));
    }
}

/// Asks the server to flush to its data file. Returns 0 on success, negative on failure.
///
/// # Safety
/// `handle` must be live.
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_save(handle: *mut AccelBridgeHandle) -> i32 {
    let handle = match handle.as_mut() {
        Some(h) => h,
        None => {
            set_last_error("handle is null");
            return -1;
        }
    };

    match handle.client.save() {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(format!("save failed: {e}"));
            -2
        }
    }
}

/// Copies the last error message (UTF-8, not null-terminated) for the
/// calling thread into `buf`, up to `buf_len` bytes. Returns the message's
/// full length, so a caller can pass a null `buf` with `buf_len` 0 first to
/// size the real buffer.
///
/// # Safety
/// `buf` must point to at least `buf_len` writable bytes, or be null iff
/// `buf_len` is 0.
#[no_mangle]
pub unsafe extern "C" fn accel_bridge_last_error(buf: *mut u8, buf_len: usize) -> usize {
    LAST_ERROR.with(|cell| {
        let msg = cell.borrow();
        let bytes = msg.as_bytes();
        if buf_len > 0 && !buf.is_null() {
            let n = bytes.len().min(buf_len);
            ptr::copy_nonoverlapping(bytes.as_ptr(), buf, n);
        }
        bytes.len()
    })
}
