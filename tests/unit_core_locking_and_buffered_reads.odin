#+vet unused shadowing using-stmt style semicolon tabs
package xitdb_tests

import "core:fmt"
import "core:io"
import "core:os"
import "core:testing"
import xitdb "../xitdb"

@(private = "file")
test_temp_path :: proc(t: ^testing.T, suffix: string) -> string {
	dir, err := os.temp_directory(context.temp_allocator)
	if err != nil || len(dir) == 0 {
		dir = "."
	}
	return fmt.tprintf("%s/xitdb_core_lock_%p_%s", dir, t, suffix)
}

@(test)
test_buffered_file_mid_file_positional_reads :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	path := test_temp_path(t, "mid_file_buf_reads.bin")
	_ = os.remove(path)
	defer _ = os.remove(path)

	c, open_err := xitdb.core_buffered_file_open(path, 4096, {.Read, .Write, .Create, .Trunc}, false)
	testing.expect_value(t, open_err, nil)
	defer xitdb.core_destroy(&c, close_file = true)

	// 1. Write 8192 bytes (flushing well past the 4096-byte buffer so data exists on disk)
	initial := make([]u8, 8192, context.temp_allocator)
	for i in 0 ..< len(initial) {
		initial[i] = u8((i * 7 + 3) & 0xff)
	}
	testing.expect_value(t, xitdb.core_seek_to(&c, 0), nil)
	testing.expect_value(t, xitdb.core_write_all(&c, initial), nil)
	testing.expect_value(t, xitdb.core_flush(&c), nil)

	// 2. Perform a mid-file in-place overwrite at [100, 116), placing memory.buf at [100, 116)
	patch := [16]u8{0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0x00, 0xEE, 0xFF}
	expected := make([]u8, 8192, context.temp_allocator)
	copy(expected, initial)
	copy(expected[100:116], patch[:])

	testing.expect_value(t, xitdb.core_seek_to(&c, 100), nil)
	testing.expect_value(t, xitdb.core_write_all(&c, patch[:]), nil)

	// (a) Positional reads strictly after memory_pos + buf_len (both within 4096 and > 4096)
	for offset in ([?]i64{200, 5000}) {
		buf_at: [100]u8
		n, rerr := xitdb.core_read_at(&c, offset, buf_at[:])
		testing.expect_value(t, rerr, nil)
		testing.expect_value(t, n, 100)
		testing.expect_value(t, string(buf_at[:]), string(expected[offset:offset + 100]))

		exact_buf: [100]u8
		testing.expect_value(t, xitdb.core_read_exact_at(&c, offset, exact_buf[:]), nil)
		testing.expect_value(t, string(exact_buf[:]), string(expected[offset:offset + 100]))

		short_buf: [100]u8
		short_slice, serr := xitdb.core_read_short_at(&c, offset, short_buf[:])
		testing.expect_value(t, serr, nil)
		testing.expect_value(t, len(short_slice), 100)
		testing.expect_value(t, string(short_slice), string(expected[offset:offset + 100]))

		blk_buf: [100]u8
		blk_slice, berr := xitdb.core_read_block_at(&c, offset, blk_buf[:])
		testing.expect_value(t, berr, nil)
		testing.expect_value(t, len(blk_slice), 100)
		testing.expect_value(t, string(blk_slice), string(expected[offset:offset + 100]))
	}

	// (b) Read spanning before -> inside -> after buffered window ([90, 130))
	span_exact: [40]u8
	testing.expect_value(t, xitdb.core_read_exact_at(&c, 90, span_exact[:]), nil)
	testing.expect_value(t, string(span_exact[:]), string(expected[90:130]))

	span_short_buf: [40]u8
	span_short, span_serr := xitdb.core_read_short_at(&c, 110, span_short_buf[:20])
	testing.expect_value(t, span_serr, nil)
	testing.expect_value(t, len(span_short), 20)
	testing.expect_value(t, string(span_short), string(expected[110:130]))

	// (c) Real EOF past 8192 still reports EOF / short slice cleanly
	eof_buf: [16]u8
	eof_n, eof_err := xitdb.core_read_at(&c, 8192, eof_buf[:])
	testing.expect_value(t, eof_err, io.Error.EOF)
	testing.expect_value(t, eof_n, 0)

	// (d) Full Database tx > buffer_size (4096) with in-place updates commits & reads cleanly
	db_path := test_temp_path(t, "mid_file_db_tx.xit")
	_ = os.remove(db_path)
	defer _ = os.remove(db_path)

	db_core, db_oerr := xitdb.core_buffered_file_open(db_path, 4096, {.Read, .Write, .Create, .Trunc}, false)
	testing.expect_value(t, db_oerr, nil)
	defer xitdb.core_destroy(&db_core, close_file = true)

	db, init_err := xitdb.database_init(&db_core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	tx := xitdb.tx_init(&db, nil, false, context.temp_allocator)
	for i in 0 ..< 160 {
		key := fmt.tprintf(".items[\"k_%04d\"]", i)
		val := fmt.tprintf("payload_value_%04d_padding_for_size_above_4096_bytes", i)
		testing.expect_value(t, xitdb.tx_put(&tx, key, val), nil)
	}
	_, cerr := xitdb.tx_commit(&tx)
	testing.expect_value(t, cerr, nil)

	got, gerr := xitdb.get_string(&db, "@0.items[\"k_0159\"]", context.temp_allocator)
	testing.expect_value(t, gerr, nil)
	testing.expect_value(t, got, "payload_value_0159_padding_for_size_above_4096_bytes")
}

@(test)
test_file_open_exclusive_flock_and_readonly_coexistence :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	for use_buffered in ([?]bool{false, true}) {
		suffix := "flock_buf.xit" if use_buffered else "flock_raw.xit"
		path := test_temp_path(t, suffix)
		_ = os.remove(path)
		defer _ = os.remove(path)

		// 1. Open writable handle #1 and write a committed moment
		c1: xitdb.Core
		oerr1: xitdb.Error
		if use_buffered {
			c1, oerr1 = xitdb.core_buffered_file_open(path, 4096, {.Read, .Write, .Create, .Trunc}, false)
		} else {
			c1, oerr1 = xitdb.core_file_open(path, {.Read, .Write, .Create, .Trunc}, false)
		}
		testing.expect_value(t, oerr1, nil)

		db1, ierr1 := xitdb.database_init(&c1, xitdb.sha1_hasher())
		testing.expect_value(t, ierr1, nil)
		tx := xitdb.tx_init(&db1, nil, false, context.temp_allocator)
		testing.expect_value(t, xitdb.tx_put(&tx, ".marker", "alive"), nil)
		_, cerr := xitdb.tx_commit(&tx)
		testing.expect_value(t, cerr, nil)
		testing.expect_value(t, xitdb.core_flush(&c1), nil)

		// 2. Second writable open (even with .Trunc!) must fail with .File_Locked and preserve data
		c2: xitdb.Core
		oerr2: xitdb.Error
		if use_buffered {
			c2, oerr2 = xitdb.core_buffered_file_open(path, 4096, {.Read, .Write, .Create, .Trunc}, false)
		} else {
			c2, oerr2 = xitdb.core_file_open(path, {.Read, .Write, .Create, .Trunc}, false)
		}
		testing.expect_value(t, oerr2, xitdb.Xitdb_Error.File_Locked)
		if oerr2 == nil {
			_ = xitdb.core_destroy(&c2, close_file = true)
		}

		// Verify handle #1's data was NOT truncated by contended open
		marker, merr := xitdb.get_string(&db1, "@-1.marker", context.temp_allocator)
		testing.expect_value(t, merr, nil)
		testing.expect_value(t, marker, "alive")

		// 3. Concurrent read-only open succeeds while writable handle is held
		ro_core: xitdb.Core
		ro_err: xitdb.Error
		if use_buffered {
			ro_core, ro_err = xitdb.core_buffered_file_open(path, 4096, {.Read}, false)
		} else {
			ro_core, ro_err = xitdb.core_file_open(path, {.Read}, false)
		}
		testing.expect_value(t, ro_err, nil)
		ro_db, ro_ierr := xitdb.database_init(&ro_core, xitdb.sha1_hasher())
		testing.expect_value(t, ro_ierr, nil)
		ro_val, ro_verr := xitdb.get_string(&ro_db, "@-1.marker", context.temp_allocator)
		testing.expect_value(t, ro_verr, nil)
		testing.expect_value(t, ro_val, "alive")
		// core_set_length on read-only handle remains a no-op
		testing.expect_value(t, xitdb.core_set_length(&ro_core, 0), nil)
		testing.expect_value(t, xitdb.core_destroy(&ro_core, close_file = true), nil)

		// 4. Closing handle #1 releases the OS lock so a subsequent writable open succeeds
		testing.expect_value(t, xitdb.core_destroy(&c1, close_file = true), nil)

		c3: xitdb.Core
		oerr3: xitdb.Error
		if use_buffered {
			c3, oerr3 = xitdb.core_buffered_file_open(path, 4096, {.Read, .Write, .Create}, false)
		} else {
			c3, oerr3 = xitdb.core_file_open(path, {.Read, .Write, .Create}, false)
		}
		testing.expect_value(t, oerr3, nil)
		db3, ierr3 := xitdb.database_init(&c3, xitdb.sha1_hasher())
		testing.expect_value(t, ierr3, nil)
		val3, verr3 := xitdb.get_string(&db3, "@-1.marker", context.temp_allocator)
		testing.expect_value(t, verr3, nil)
		testing.expect_value(t, val3, "alive")
		testing.expect_value(t, xitdb.core_destroy(&c3, close_file = true), nil)
	}
}

@(test)
test_buffered_file_set_length_failure_preserves_buffer :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	path := test_temp_path(t, "set_len_err_buf.bin")
	_ = os.remove(path)
	defer _ = os.remove(path)

	seed, open_err := xitdb.core_buffered_file_open(path, 4096, {.Read, .Write, .Create, .Trunc}, false)
	testing.expect_value(t, open_err, nil)

	initial := make([]u8, 8192, context.temp_allocator)
	for i in 0 ..< len(initial) {
		initial[i] = u8((i * 7 + 3) & 0xff)
	}
	testing.expect_value(t, xitdb.core_seek_to(&seed, 0), nil)
	testing.expect_value(t, xitdb.core_write_all(&seed, initial), nil)
	testing.expect_value(t, xitdb.core_destroy(&seed, close_file = true), nil)

	ro_file, ro_err := os.open(path, {.Read})
	testing.expect_value(t, ro_err, nil)
	c := xitdb.core_buffered_file_init(ro_file, 4096, fsync = false, read_only = false)
	defer _ = xitdb.core_destroy(&c, close_file = true)

	patch := [16]u8{0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0x00, 0xEE, 0xFF}
	expected := make([]u8, 8192, context.temp_allocator)
	copy(expected, initial)
	copy(expected[100:116], patch[:])

	testing.expect_value(t, xitdb.core_seek_to(&c, 100), nil)
	testing.expect_value(t, xitdb.core_write_all(&c, patch[:]), nil)

	set_err := xitdb.core_set_length(&c, 0)
	testing.expect(t, set_err != nil, "expected os.truncate on O_RDONLY handle to fail")

	span_exact: [40]u8
	testing.expect_value(t, xitdb.core_read_exact_at(&c, 90, span_exact[:]), nil)
	testing.expect_value(t, string(span_exact[:]), string(expected[90:130]))
}

@(test)
test_buffered_file_set_length_flushes_before_extending_on_disk :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	path := test_temp_path(t, "set_len_flush_append.bin")
	_ = os.remove(path)
	defer _ = os.remove(path)

	c, open_err := xitdb.core_buffered_file_open(path, 4096, {.Read, .Write, .Create, .Trunc}, false)
	testing.expect_value(t, open_err, nil)
	defer _ = xitdb.core_destroy(&c, close_file = true)

	// Flush 100 bytes to disk, then buffer 100 more bytes (unflushed append at [100, 200))
	head := make([]u8, 100, context.temp_allocator)
	tail := make([]u8, 100, context.temp_allocator)
	for i in 0 ..< 100 {
		head[i] = u8(0x10 + (i & 0x0f))
		tail[i] = u8(0xA0 + (i & 0x0f))
	}
	testing.expect_value(t, xitdb.core_seek_to(&c, 0), nil)
	testing.expect_value(t, xitdb.core_write_all(&c, head), nil)
	testing.expect_value(t, xitdb.core_flush(&c), nil)
	testing.expect_value(t, xitdb.core_write_all(&c, tail), nil)

	// Partially rewind the unflushed append to 150: disk must receive tail[:50], not zeroes
	testing.expect_value(t, xitdb.core_set_length(&c, 150), nil)

	ro, ro_err := xitdb.core_file_open(path, {.Read}, false)
	testing.expect_value(t, ro_err, nil)
	defer _ = xitdb.core_destroy(&ro, close_file = true)

	disk_len, len_err := xitdb.core_length(&ro)
	testing.expect_value(t, len_err, nil)
	testing.expect_value(t, disk_len, i64(150))

	got_tail: [50]u8
	testing.expect_value(t, xitdb.core_read_exact_at(&ro, 100, got_tail[:]), nil)
	testing.expect_value(t, string(got_tail[:]), string(tail[:50]))

	// Also verify lock = false bypasses exclusive flock
	unlocked, uerr := xitdb.core_file_open(path, {.Read, .Write}, false, lock = false)
	testing.expect_value(t, uerr, nil)
	testing.expect_value(t, xitdb.core_destroy(&unlocked, close_file = true), nil)
}
