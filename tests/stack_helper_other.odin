#+build !linux
#+build !darwin
#+build !freebsd
#+build !netbsd
#+build !openbsd
package xitdb_tests

import "core:testing"

// Fallback runner on non-POSIX targets that executes `fn(arg)` on the caller stack.
@(private)
_run_on_small_stack :: proc(t: ^testing.T, stack_bytes: int, fn: proc(rawptr), arg: rawptr) {
	_ = t
	_ = stack_bytes
	fn(arg)
}
