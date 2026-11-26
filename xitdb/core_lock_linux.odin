#+build linux
package xitdb

import "core:os"
import "core:sys/linux"

// Acquires a non-blocking exclusive advisory lock on `f` (`flock(LOCK_EX | LOCK_NB)`).
// Note: in `core:sys/linux`, `.EWOULDBLOCK == .EAGAIN`.
@(private, require_results)
_core_try_lock_exclusive :: proc(f: ^os.File) -> Error {
	if f == nil {
		return Xitdb_Error.Write_Failed
	}
	raw_fd := os.fd(f)
	if int(raw_fd) < 0 {
		return Xitdb_Error.Write_Failed
	}
	fd := linux.Fd(raw_fd)
	for {
		errno := linux.flock(fd, {.EX, .NB})
		#partial switch errno {
		case .NONE:
			return nil
		case .EINTR:
			continue
		case .EAGAIN:
			return Xitdb_Error.File_Locked
		case:
			return Xitdb_Error.Write_Failed
		}
	}
}
