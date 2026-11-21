#+build amd64
package xitdb

import "base:intrinsics"
import "core:encoding/endian"
import "core:simd"
import "core:simd/x86"

@(private = "file")
_has_sha_ni: bool

@(init, private = "file")
_init_sha_ni :: proc "contextless" () {
	max_id, _, _, _ := intrinsics.x86_cpuid(0, 0)
	if max_id < 7 {
		return
	}
	_, _, ecx1, edx1 := intrinsics.x86_cpuid(1, 0)
	has_sse2  := ((edx1 >> 26) & 1) != 0
	has_ssse3 := ((ecx1 >> 9)  & 1) != 0
	has_sse41 := ((ecx1 >> 19) & 1) != 0
	_, ebx7, _, _ := intrinsics.x86_cpuid(7, 0)
	has_sha   := ((ebx7 >> 29) & 1) != 0
	_has_sha_ni = has_sse2 && has_ssse3 && has_sse41 && has_sha
}

@(private = "file")
SHA1_SHUF_MASK   :: x86.__m128i{0x08090a0b0c0d0e0f, 0x0001020304050607}
@(private = "file")
SHA256_SHUF_MASK :: x86.__m128i{0x0405060700010203, 0x0c0d0e0f08090a0b}

@(private = "file", enable_target_feature = "sse2,ssse3,sse4.1,sha")
sha1_transf_hw :: proc "contextless" (state: ^[5]u32, data: []u8) #no_bounds_check {
	// Load initial state: state[0..3] = A, B, C, D; state[4] = E
	abcd := intrinsics.unaligned_load((^x86.__m128i)(&state[0]))
	abcd = x86._mm_shuffle_epi32(abcd, 0x1B) // lane 3..0 = A, B, C, D
	e0 := x86._mm_set_epi32(i32(state[4]), 0, 0, 0)

	data := data
	for len(data) >= 64 {
		abcd_save := abcd
		e0_save := e0

		// Rounds 0..3
		msg0 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[0:])))
		msg0 = x86._mm_shuffle_epi8(msg0, SHA1_SHUF_MASK)
		e0 = x86._mm_add_epi32(e0, msg0)
		e1 := abcd
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)

		// Rounds 4..7
		msg1 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[16:])))
		msg1 = x86._mm_shuffle_epi8(msg1, SHA1_SHUF_MASK)
		e1 = x86._mm_sha1nexte_epu32(e1, msg1)
		e0 = abcd
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 0)
		msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)

		// Rounds 8..11
		msg2 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[32:])))
		msg2 = x86._mm_shuffle_epi8(msg2, SHA1_SHUF_MASK)
		e0 = x86._mm_sha1nexte_epu32(e0, msg2)
		e1 = abcd
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
		msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
		msg0 = x86._mm_xor_si128(msg0, msg2)

		// Rounds 12..15
		msg3 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[48:])))
		msg3 = x86._mm_shuffle_epi8(msg3, SHA1_SHUF_MASK)
		e1 = x86._mm_sha1nexte_epu32(e1, msg3)
		e0 = abcd
		msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 0)
		msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
		msg1 = x86._mm_xor_si128(msg1, msg3)

		// Rounds 16..19
		e0 = x86._mm_sha1nexte_epu32(e0, msg0)
		e1 = abcd
		msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
		msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
		msg2 = x86._mm_xor_si128(msg2, msg0)

		// Rounds 20..23
		e1 = x86._mm_sha1nexte_epu32(e1, msg1)
		e0 = abcd
		msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
		msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
		msg3 = x86._mm_xor_si128(msg3, msg1)

		// Rounds 24..27
		e0 = x86._mm_sha1nexte_epu32(e0, msg2)
		e1 = abcd
		msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 1)
		msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
		msg0 = x86._mm_xor_si128(msg0, msg2)

		// Rounds 28..31
		e1 = x86._mm_sha1nexte_epu32(e1, msg3)
		e0 = abcd
		msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
		msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
		msg1 = x86._mm_xor_si128(msg1, msg3)

		// Rounds 32..35
		e0 = x86._mm_sha1nexte_epu32(e0, msg0)
		e1 = abcd
		msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 1)
		msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
		msg2 = x86._mm_xor_si128(msg2, msg0)

		// Rounds 36..39
		e1 = x86._mm_sha1nexte_epu32(e1, msg1)
		e0 = abcd
		msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
		msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
		msg3 = x86._mm_xor_si128(msg3, msg1)

		// Rounds 40..43
		e0 = x86._mm_sha1nexte_epu32(e0, msg2)
		e1 = abcd
		msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
		msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
		msg0 = x86._mm_xor_si128(msg0, msg2)

		// Rounds 44..47
		e1 = x86._mm_sha1nexte_epu32(e1, msg3)
		e0 = abcd
		msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 2)
		msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
		msg1 = x86._mm_xor_si128(msg1, msg3)

		// Rounds 48..51
		e0 = x86._mm_sha1nexte_epu32(e0, msg0)
		e1 = abcd
		msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
		msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
		msg2 = x86._mm_xor_si128(msg2, msg0)

		// Rounds 52..55
		e1 = x86._mm_sha1nexte_epu32(e1, msg1)
		e0 = abcd
		msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 2)
		msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
		msg3 = x86._mm_xor_si128(msg3, msg1)

		// Rounds 56..59
		e0 = x86._mm_sha1nexte_epu32(e0, msg2)
		e1 = abcd
		msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
		msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
		msg0 = x86._mm_xor_si128(msg0, msg2)

		// Rounds 60..63
		e1 = x86._mm_sha1nexte_epu32(e1, msg3)
		e0 = abcd
		msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
		msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
		msg1 = x86._mm_xor_si128(msg1, msg3)

		// Rounds 64..67
		e0 = x86._mm_sha1nexte_epu32(e0, msg0)
		e1 = abcd
		msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 3)
		msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
		msg2 = x86._mm_xor_si128(msg2, msg0)

		// Rounds 68..71
		e1 = x86._mm_sha1nexte_epu32(e1, msg1)
		e0 = abcd
		msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
		msg3 = x86._mm_xor_si128(msg3, msg1)

		// Rounds 72..75
		e0 = x86._mm_sha1nexte_epu32(e0, msg2)
		e1 = abcd
		msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
		abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 3)

		// Rounds 76..79
		e1 = x86._mm_sha1nexte_epu32(e1, msg3)
		e0 = abcd
		abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)

		// Combine state
		e0 = x86._mm_sha1nexte_epu32(e0, e0_save)
		abcd = x86._mm_add_epi32(abcd, abcd_save)

		data = data[64:]
	}

	abcd = x86._mm_shuffle_epi32(abcd, 0x1B)
	intrinsics.unaligned_store((^x86.__m128i)(&state[0]), abcd)
	state[4] = u32(x86._mm_extract_epi32(e0, 3))
}

@(private = "file")
SHA256_K_0  :: simd.u64x2{0x71374491428a2f98, 0xe9b5dba5b5c0fbcf}
@(private = "file")
SHA256_K_1  :: simd.u64x2{0x59f111f13956c25b, 0xab1c5ed5923f82a4}
@(private = "file")
SHA256_K_2  :: simd.u64x2{0x12835b01d807aa98, 0x550c7dc3243185be}
@(private = "file")
SHA256_K_3  :: simd.u64x2{0x80deb1fe72be5d74, 0xc19bf1749bdc06a7}
@(private = "file")
SHA256_K_4  :: simd.u64x2{0xefbe4786e49b69c1, 0x240ca1cc0fc19dc6}
@(private = "file")
SHA256_K_5  :: simd.u64x2{0x4a7484aa2de92c6f, 0x76f988da5cb0a9dc}
@(private = "file")
SHA256_K_6  :: simd.u64x2{0xa831c66d983e5152, 0xbf597fc7b00327c8}
@(private = "file")
SHA256_K_7  :: simd.u64x2{0xd5a79147c6e00bf3, 0x1429296706ca6351}
@(private = "file")
SHA256_K_8  :: simd.u64x2{0x2e1b213827b70a85, 0x53380d134d2c6dfc}
@(private = "file")
SHA256_K_9  :: simd.u64x2{0x766a0abb650a7354, 0x92722c8581c2c92e}
@(private = "file")
SHA256_K_10 :: simd.u64x2{0xa81a664ba2bfe8a1, 0xc76c51a3c24b8b70}
@(private = "file")
SHA256_K_11 :: simd.u64x2{0xd6990624d192e819, 0x106aa070f40e3585}
@(private = "file")
SHA256_K_12 :: simd.u64x2{0x1e376c0819a4c116, 0x34b0bcb52748774c}
@(private = "file")
SHA256_K_13 :: simd.u64x2{0x4ed8aa4a391c0cb3, 0x682e6ff35b9cca4f}
@(private = "file")
SHA256_K_14 :: simd.u64x2{0x78a5636f748f82ee, 0x8cc7020884c87814}
@(private = "file")
SHA256_K_15 :: simd.u64x2{0xa4506ceb90befffa, 0xc67178f2bef9a3f7}

@(private = "file", enable_target_feature = "sse2,ssse3,sse4.1,sha")
sha256_transf_hw :: proc "contextless" (h: ^[8]u32, data: []u8) #no_bounds_check {
	tmp := intrinsics.unaligned_load((^x86.__m128i)(&h[0]))
	state_1 := intrinsics.unaligned_load((^x86.__m128i)(&h[4]))

	tmp = x86._mm_shuffle_epi32(tmp, 0xb1)            // CDAB
	state_1 = x86._mm_shuffle_epi32(state_1, 0x1b)    // EFGH
	state_0 := x86._mm_alignr_epi8(tmp, state_1, 8)   // ABEF
	state_1 = x86._mm_blend_epi16(state_1, tmp, 0xf0) // CDGH

	data := data
	for len(data) >= 64 {
		state_0_save, state_1_save := state_0, state_1

		// Rounds 0-3
		msg := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data)))
		msg_0 := x86._mm_shuffle_epi8(msg, SHA256_SHUF_MASK)
		msg = x86._mm_add_epi32(msg_0, x86.__m128i(SHA256_K_0))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)

		// Rounds 4-7
		msg_1 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[16:])))
		msg_1 = x86._mm_shuffle_epi8(msg_1, SHA256_SHUF_MASK)
		msg = x86._mm_add_epi32(msg_1, x86.__m128i(SHA256_K_1))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_0 = x86._mm_sha256msg1_epu32(msg_0, msg_1)

		// Rounds 8-11
		msg_2 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[32:])))
		msg_2 = x86._mm_shuffle_epi8(msg_2, SHA256_SHUF_MASK)
		msg = x86._mm_add_epi32(msg_2, x86.__m128i(SHA256_K_2))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_1 = x86._mm_sha256msg1_epu32(msg_1, msg_2)

		// Rounds 12-15
		msg_3 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[48:])))
		msg_3 = x86._mm_shuffle_epi8(msg_3, SHA256_SHUF_MASK)
		msg = x86._mm_add_epi32(msg_3, x86.__m128i(SHA256_K_3))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_3, msg_2, 4)
		msg_0 = x86._mm_add_epi32(msg_0, tmp)
		msg_0 = x86._mm_sha256msg2_epu32(msg_0, msg_3)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_2 = x86._mm_sha256msg1_epu32(msg_2, msg_3)

		// Rounds 16-19
		msg = x86._mm_add_epi32(msg_0, x86.__m128i(SHA256_K_4))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_0, msg_3, 4)
		msg_1 = x86._mm_add_epi32(msg_1, tmp)
		msg_1 = x86._mm_sha256msg2_epu32(msg_1, msg_0)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_3 = x86._mm_sha256msg1_epu32(msg_3, msg_0)

		// Rounds 20-23
		msg = x86._mm_add_epi32(msg_1, x86.__m128i(SHA256_K_5))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_1, msg_0, 4)
		msg_2 = x86._mm_add_epi32(msg_2, tmp)
		msg_2 = x86._mm_sha256msg2_epu32(msg_2, msg_1)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_0 = x86._mm_sha256msg1_epu32(msg_0, msg_1)

		// Rounds 24-27
		msg = x86._mm_add_epi32(msg_2, x86.__m128i(SHA256_K_6))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_2, msg_1, 4)
		msg_3 = x86._mm_add_epi32(msg_3, tmp)
		msg_3 = x86._mm_sha256msg2_epu32(msg_3, msg_2)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_1 = x86._mm_sha256msg1_epu32(msg_1, msg_2)

		// Rounds 28-31
		msg = x86._mm_add_epi32(msg_3, x86.__m128i(SHA256_K_7))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_3, msg_2, 4)
		msg_0 = x86._mm_add_epi32(msg_0, tmp)
		msg_0 = x86._mm_sha256msg2_epu32(msg_0, msg_3)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_2 = x86._mm_sha256msg1_epu32(msg_2, msg_3)

		// Rounds 32-35
		msg = x86._mm_add_epi32(msg_0, x86.__m128i(SHA256_K_8))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_0, msg_3, 4)
		msg_1 = x86._mm_add_epi32(msg_1, tmp)
		msg_1 = x86._mm_sha256msg2_epu32(msg_1, msg_0)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_3 = x86._mm_sha256msg1_epu32(msg_3, msg_0)

		// Rounds 36-39
		msg = x86._mm_add_epi32(msg_1, x86.__m128i(SHA256_K_9))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_1, msg_0, 4)
		msg_2 = x86._mm_add_epi32(msg_2, tmp)
		msg_2 = x86._mm_sha256msg2_epu32(msg_2, msg_1)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_0 = x86._mm_sha256msg1_epu32(msg_0, msg_1)

		// Rounds 40-43
		msg = x86._mm_add_epi32(msg_2, x86.__m128i(SHA256_K_10))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_2, msg_1, 4)
		msg_3 = x86._mm_add_epi32(msg_3, tmp)
		msg_3 = x86._mm_sha256msg2_epu32(msg_3, msg_2)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_1 = x86._mm_sha256msg1_epu32(msg_1, msg_2)

		// Rounds 44-47
		msg = x86._mm_add_epi32(msg_3, x86.__m128i(SHA256_K_11))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_3, msg_2, 4)
		msg_0 = x86._mm_add_epi32(msg_0, tmp)
		msg_0 = x86._mm_sha256msg2_epu32(msg_0, msg_3)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_2 = x86._mm_sha256msg1_epu32(msg_2, msg_3)

		// Rounds 48-51
		msg = x86._mm_add_epi32(msg_0, x86.__m128i(SHA256_K_12))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_0, msg_3, 4)
		msg_1 = x86._mm_add_epi32(msg_1, tmp)
		msg_1 = x86._mm_sha256msg2_epu32(msg_1, msg_0)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)
		msg_3 = x86._mm_sha256msg1_epu32(msg_3, msg_0)

		// Rounds 52-55
		msg = x86._mm_add_epi32(msg_1, x86.__m128i(SHA256_K_13))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_1, msg_0, 4)
		msg_2 = x86._mm_add_epi32(msg_2, tmp)
		msg_2 = x86._mm_sha256msg2_epu32(msg_2, msg_1)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)

		// Rounds 56-59
		msg = x86._mm_add_epi32(msg_2, x86.__m128i(SHA256_K_14))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		tmp = x86._mm_alignr_epi8(msg_2, msg_1, 4)
		msg_3 = x86._mm_add_epi32(msg_3, tmp)
		msg_3 = x86._mm_sha256msg2_epu32(msg_3, msg_2)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)

		// Rounds 60-63
		msg = x86._mm_add_epi32(msg_3, x86.__m128i(SHA256_K_15))
		state_1 = x86._mm_sha256rnds2_epu32(state_1, state_0, msg)
		msg = x86._mm_shuffle_epi32(msg, 0x0e)
		state_0 = x86._mm_sha256rnds2_epu32(state_0, state_1, msg)

		state_0 = x86._mm_add_epi32(state_0, state_0_save)
		state_1 = x86._mm_add_epi32(state_1, state_1_save)

		data = data[64:]
	}

	tmp = x86._mm_shuffle_epi32(state_0, 0x1b)        // FEBA
	state_1 = x86._mm_shuffle_epi32(state_1, 0xb1)    // DCHG
	state_0 = x86._mm_blend_epi16(tmp, state_1, 0xf0) // DCBA
	state_1 = x86._mm_alignr_epi8(state_1, tmp, 8)    // ABEF

	intrinsics.unaligned_store((^x86.__m128i)(&h[0]), state_0)
	intrinsics.unaligned_store((^x86.__m128i)(&h[4]), state_1)
}

// Hardware SHA-NI fast path for SHA-1; returns false on CPUs without SHA-NI support.
@(private = "package")
_sha1_sum_into_hw :: #force_inline proc(state: ^[5]u32, data: []u8, out: []u8) -> bool #no_bounds_check {
	if !_has_sha_ni {
		return false
	}
	full_len := len(data) & ~int(63)
	if full_len > 0 {
		sha1_transf_hw(state, data[:full_len])
	}
	rem := len(data) - full_len
	bit_len := u64(len(data)) * 8
	if rem < 56 {
		tail: [64]u8
		copy(tail[:rem], data[full_len:])
		tail[rem] = 0x80
		endian.unchecked_put_u64be(tail[56:64], bit_len)
		sha1_transf_hw(state, tail[0:64])
	} else {
		tail: [128]u8
		copy(tail[:rem], data[full_len:])
		tail[rem] = 0x80
		endian.unchecked_put_u64be(tail[120:128], bit_len)
		sha1_transf_hw(state, tail[0:128])
	}
	endian.unchecked_put_u32be(out[0:4], state[0])
	endian.unchecked_put_u32be(out[4:8], state[1])
	endian.unchecked_put_u32be(out[8:12], state[2])
	endian.unchecked_put_u32be(out[12:16], state[3])
	endian.unchecked_put_u32be(out[16:20], state[4])
	return true
}

// Hardware SHA-NI fast path for SHA-256; returns false on CPUs without SHA-NI support.
@(private = "package")
_sha256_sum_into_hw :: #force_inline proc(h: ^[8]u32, data: []u8, out: []u8) -> bool #no_bounds_check {
	if !_has_sha_ni {
		return false
	}
	full_len := len(data) & ~int(63)
	if full_len > 0 {
		sha256_transf_hw(h, data[:full_len])
	}
	rem := len(data) - full_len
	bit_len := u64(len(data)) * 8
	if rem < 56 {
		tail: [64]u8
		copy(tail[:rem], data[full_len:])
		tail[rem] = 0x80
		endian.unchecked_put_u64be(tail[56:64], bit_len)
		sha256_transf_hw(h, tail[0:64])
	} else {
		tail: [128]u8
		copy(tail[:rem], data[full_len:])
		tail[rem] = 0x80
		endian.unchecked_put_u64be(tail[120:128], bit_len)
		sha256_transf_hw(h, tail[0:128])
	}
	for j in 0 ..< 8 {
		endian.unchecked_put_u32be(out[j * 4:j * 4 + 4], h[j])
	}
	return true
}
