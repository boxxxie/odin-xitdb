#+build linux, darwin, freebsd, netbsd, openbsd
package xitdb_tests

import "base:runtime"
import "core:c"
import "core:sys/posix"
import "core:testing"

@(private)
_Small_Stack_Run :: struct {
	fn:        proc(rawptr),
	arg:       rawptr,
	allocator: runtime.Allocator,
	logger:    runtime.Logger,
}

@(private)
_small_stack_trampoline :: proc "c" (raw: rawptr) -> rawptr {
	run := (^_Small_Stack_Run)(raw)
	context = runtime.default_context()
	context.allocator = run.allocator
	context.logger = run.logger
	defer {
		if context.temp_allocator.procedure == runtime.default_temp_allocator_proc {
			runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
		}
		runtime.run_thread_local_cleaners()
	}
	run.fn(run.arg)
	return nil
}

// Run `fn(arg)` on a joinable POSIX thread with an explicit stack size
// (expanded under AddressSanitizer where ASan instrumentation inflates frames).
@(private)
_run_on_small_stack :: proc(t: ^testing.T, stack_bytes: int, fn: proc(rawptr), arg: rawptr) {
	effective_stack := stack_bytes
	when .Address in ODIN_SANITIZER_FLAGS {
		effective_stack = max(stack_bytes, 4 * 1024 * 1024)
	}

	attr: posix.pthread_attr_t
	init_err := posix.pthread_attr_init(&attr)
	testing.expect_value(t, init_err, posix.Errno.NONE)
	if init_err != .NONE {
		return
	}
	defer _ = posix.pthread_attr_destroy(&attr)

	detach_err := posix.pthread_attr_setdetachstate(&attr, .CREATE_JOINABLE)
	testing.expect_value(t, detach_err, posix.Errno.NONE)
	stack_err := posix.pthread_attr_setstacksize(&attr, c.size_t(effective_stack))
	testing.expect_value(t, stack_err, posix.Errno.NONE)
	if detach_err != .NONE || stack_err != .NONE {
		return
	}

	run := _Small_Stack_Run{
		fn        = fn,
		arg       = arg,
		allocator = context.allocator,
		logger    = context.logger,
	}
	tid: posix.pthread_t
	create_err := posix.pthread_create(&tid, &attr, _small_stack_trampoline, &run)
	testing.expect_value(t, create_err, posix.Errno.NONE)
	if create_err != .NONE {
		return
	}

	join_err := posix.pthread_join(tid, nil)
	testing.expect_value(t, join_err, posix.Errno.NONE)
}
