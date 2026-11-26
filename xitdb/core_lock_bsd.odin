#+build darwin, freebsd, openbsd, netbsd
package xitdb

import "core:c"
import "core:os"
import "core:sys/posix"

when ODIN_OS == .Darwin {
	foreign import libc "system:System"
} else {
	foreign import libc "system:c"
}

@(private = "file", default_calling_convention = "c")
foreign libc {
	@(link_name = "flock")
	_bsd_flock :: proc(fd: c.int, operation: c.int) -> c.int ---
}

@(private = "file")
_BSD_LOCK_EX :: c.int(2)
@(private = "file")
_BSD_LOCK_NB :: c.int(4)

// Acquires a non-blocking exclusive advisory lock on `f` (`flock(LOCK_EX | LOCK_NB)`).
// Note: on Darwin/FreeBSD/OpenBSD/NetBSD, `posix.Errno.EWOULDBLOCK == .EAGAIN` (35).
@(private, require_results)
_core_try_lock_exclusive :: proc(f: ^os.File) -> Error {
	if f == nil {
		return Xitdb_Error.Write_Failed
	}
	raw_fd := os.fd(f)
	if int(raw_fd) < 0 {
		return Xitdb_Error.Write_Failed
	}
	fd := c.int(raw_fd)
	for {
		if _bsd_flock(fd, _BSD_LOCK_EX | _BSD_LOCK_NB) == 0 {
			return nil
		}
		#partial switch posix.errno() {
		case .EINTR:
			continue
		case .EAGAIN:
			return Xitdb_Error.File_Locked
		case:
			return Xitdb_Error.Write_Failed
		}
	}
}
