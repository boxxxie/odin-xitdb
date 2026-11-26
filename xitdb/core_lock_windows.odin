#+build windows
package xitdb

import "core:os"
import win32 "core:sys/windows"

// Lock a 1-byte sentinel near the top of the signed 64-bit offset space (~8 EiB)
// rather than byte 0: Windows `LockFileEx` locks are mandatory, so locking data
// bytes would cause concurrent read-only handles to fail with ERROR_LOCK_VIOLATION.
@(private = "file")
_WINDOWS_LOCK_OFFSET_LOW :: win32.DWORD(0)
@(private = "file")
_WINDOWS_LOCK_OFFSET_HIGH :: win32.DWORD(0x7FFF_FFFF)

// Acquires a non-blocking exclusive OS lock on `f` (`LockFileEx` on the sentinel byte).
@(private, require_results)
_core_try_lock_exclusive :: proc(f: ^os.File) -> Error {
	if f == nil {
		return Xitdb_Error.Write_Failed
	}
	handle := win32.HANDLE(os.fd(f))
	if handle == nil || handle == win32.INVALID_HANDLE {
		return Xitdb_Error.Write_Failed
	}
	overlapped := win32.OVERLAPPED{
		Offset     = _WINDOWS_LOCK_OFFSET_LOW,
		OffsetHigh = _WINDOWS_LOCK_OFFSET_HIGH,
	}
	flags := win32.LOCKFILE_EXCLUSIVE_LOCK | win32.LOCKFILE_FAIL_IMMEDIATELY
	if win32.LockFileEx(handle, flags, 0, 1, 0, &overlapped) {
		return nil
	}
	switch win32.GetLastError() {
	case win32.ERROR_LOCK_VIOLATION, win32.ERROR_SHARING_VIOLATION:
		return Xitdb_Error.File_Locked
	case:
		return Xitdb_Error.Write_Failed
	}
}
