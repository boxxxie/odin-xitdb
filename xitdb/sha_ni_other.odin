#+build !amd64
package xitdb

// Non-amd64 SHA-NI stubs; software SHA implementations in types.odin handle all digests.
@(private = "package")
_sha1_sum_into_hw :: #force_inline proc(_: ^[5]u32, _: []u8, _: []u8) -> bool {
	return false
}

// Non-amd64 SHA-NI stubs; software SHA implementations in types.odin handle all digests.
@(private = "package")
_sha256_sum_into_hw :: #force_inline proc(_: ^[8]u32, _: []u8, _: []u8) -> bool {
	return false
}
