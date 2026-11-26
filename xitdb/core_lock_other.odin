#+build !linux
#+build !darwin
#+build !freebsd
#+build !openbsd
#+build !netbsd
#+build !windows
package xitdb

import "core:io"
import "core:os"

// Exclusive file locking is unsupported on this target; fail closed when `lock = true`
// so callers never silently write or truncate without mutual exclusion. Callers that
// explicitly accept unlocked access on this target can pass `lock = false`.
@(private, require_results)
_core_try_lock_exclusive :: proc(_: ^os.File) -> Error {
	return io.Error.Unsupported
}
