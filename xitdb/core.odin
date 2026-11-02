package xitdb

import "base:runtime"
import "core:encoding/endian"
import "core:io"
import "core:os"

DEFAULT_BUFFER_SIZE :: 2 * 1024 * 1024

// Core_Memory stores a xitdb database in a dynamic byte array in memory.
Core_Memory :: struct {
	buf:       [dynamic]u8,
	pos:       i64,
	allocator: runtime.Allocator,
}

// Core_File stores a xitdb database directly on an OS file handle.
Core_File :: struct {
	file:  ^os.File,
	fsync: bool,
}

// Core_Buffered_File wraps an OS file handle with an in-memory contiguous write window
// matching xitdb's CoreBufferedFile semantics.
Core_Buffered_File :: struct {
	memory:          Core_Memory,
	memory_max_size: i64,
	memory_pos:      i64,
	flushed_len:     int,
	pos:             i64,
	file:            Core_File,
	file_len:        Maybe(i64),
}

// Core is the unified storage backend union.
Core :: union {
	Core_Memory,
	Core_File,
	Core_Buffered_File,
}

core_memory_init :: proc(allocator := context.allocator) -> Core {
	return Core_Memory{
		buf       = make([dynamic]u8, 0, 1024, allocator),
		pos       = 0,
		allocator = allocator,
	}
}

core_memory_init_from_bytes :: proc(data: []u8, allocator := context.allocator) -> Core {
	buf := make([dynamic]u8, len(data), allocator)
	copy(buf[:], data)
	return Core_Memory{
		buf       = buf,
		pos       = 0,
		allocator = allocator,
	}
}

core_memory_bytes :: proc(c: ^Core) -> []u8 {
	#partial switch &v in c {
	case Core_Memory:
		return v.buf[:]
	}
	return nil
}

core_file_init :: proc(file: ^os.File, fsync := true) -> Core {
	return Core_File{file = file, fsync = fsync}
}

core_memory_from_bytes :: proc(data: []u8, allocator := context.allocator) -> Core {
	return core_memory_init_from_bytes(data, allocator)
}

core_file_open :: proc(path: string, flags := os.File_Flags{.Read, .Write, .Create}, fsync := true) -> (c: Core, err: Error) {
	f := os.open(path, flags, os.Permissions_Default_File) or_return
	return Core_File{file = f, fsync = fsync}, nil
}

core_buffered_file_init :: proc(file: ^os.File, buffer_size: i64 = DEFAULT_BUFFER_SIZE, fsync := true, allocator := context.allocator) -> Core {
	sz := buffer_size if buffer_size > 0 else DEFAULT_BUFFER_SIZE
	return Core_Buffered_File{
		memory = Core_Memory{
			buf       = make([dynamic]u8, 0, int(min(sz, 65536)), allocator),
			pos       = 0,
			allocator = allocator,
		},
		memory_max_size = sz,
		memory_pos      = 0,
		pos             = 0,
		file            = Core_File{file = file, fsync = fsync},
		file_len        = nil,
	}
}

core_buffered_file_open :: proc(path: string, buffer_size: i64 = DEFAULT_BUFFER_SIZE, flags := os.File_Flags{.Read, .Write, .Create}, fsync := true, allocator := context.allocator) -> (c: Core, err: Error) {
	f := os.open(path, flags, os.Permissions_Default_File) or_return
	return core_buffered_file_init(f, buffer_size, fsync, allocator), nil
}

core_destroy :: proc(c: ^Core, close_file := false) -> Error {
	switch &v in c {
	case Core_Memory:
		delete(v.buf)
		v.buf = nil
		v.pos = 0
	case Core_File:
		if close_file && v.file != nil {
			os.close(v.file) or_return
			v.file = nil
		}
	case Core_Buffered_File:
		_ = _buffered_flush(&v)
		delete(v.memory.buf)
		v.memory.buf = nil
		if close_file && v.file.file != nil {
			os.close(v.file.file) or_return
			v.file.file = nil
		}
	}
	return nil
}

@(private)
_buffered_write_to_file :: proc(bf: ^Core_Buffered_File, pos: i64, data: []u8) -> Error {
	cached_len := bf.file_len
	bf.file_len = nil
	os.seek(bf.file.file, pos, .Start) or_return
	written := 0
	for written < len(data) {
		n := os.write(bf.file.file, data[written:]) or_return
		if n == 0 {
			return io.Error.Short_Write
		}
		written += n
	}
	if cl, ok := cached_len.?; ok {
		bf.file_len = max(cl, pos + i64(len(data)))
	}
	return nil
}

@(private)
_buffered_flush :: proc(bf: ^Core_Buffered_File) -> Error {
	if len(bf.memory.buf) > bf.flushed_len {
		_buffered_write_to_file(bf, bf.memory_pos + i64(bf.flushed_len), bf.memory.buf[bf.flushed_len:]) or_return
		bf.flushed_len = len(bf.memory.buf)
	}
	return nil
}

core_length :: proc(c: ^Core) -> (length: i64, err: Error) {
	switch &v in c {
	case Core_Memory:
		return i64(len(v.buf)), nil
	case Core_File:
		return os.file_size(v.file)
	case Core_Buffered_File:
		flen: i64
		if fl, ok := v.file_len.?; ok {
			flen = fl
		} else {
			flen = os.file_size(v.file.file) or_return
			v.file_len = flen
		}
		buf_size := i64(len(v.memory.buf))
		if buf_size == 0 {
			return flen, nil
		}
		return max(v.memory_pos + buf_size, flen), nil
	}
	return 0, .Invalid_Database
}

core_seek_to :: proc(c: ^Core, pos: i64) -> Error {
	if pos < 0 {
		return .Expected_Unsigned_Long
	}
	switch &v in c {
	case Core_Memory:
		v.pos = pos
		return nil
	case Core_File:
		os.seek(v.file, pos, .Start) or_return
		return nil
	case Core_Buffered_File:
		v.pos = pos
		return nil
	}
	return .Invalid_Database
}

core_position :: proc(c: ^Core) -> (pos: i64, err: Error) {
	switch &v in c {
	case Core_Memory:
		return v.pos, nil
	case Core_File:
		return os.seek(v.file, 0, .Current)
	case Core_Buffered_File:
		return v.pos, nil
	}
	return 0, .Invalid_Database
}

core_flush :: proc(c: ^Core) -> Error {
	switch &v in c {
	case Core_Memory:
		return nil
	case Core_File:
		return os.flush(v.file)
	case Core_Buffered_File:
		_buffered_flush(&v) or_return
		return os.flush(v.file.file)
	}
	return .Invalid_Database
}

core_sync :: proc(c: ^Core) -> Error {
	switch &v in c {
	case Core_Memory:
		return nil
	case Core_File:
		if !v.fsync {
			return nil
		}
		return os.sync(v.file)
	case Core_Buffered_File:
		_buffered_flush(&v) or_return
		if !v.file.fsync {
			return nil
		}
		return os.sync(v.file.file)
	}
	return .Invalid_Database
}

core_set_length :: proc(c: ^Core, new_len: i64) -> Error {
	if new_len < 0 {
		return .Expected_Unsigned_Long
	}
	switch &v in c {
	case Core_Memory:
		if new_len > i64(len(v.buf)) {
			return Xitdb_Error.Invalid_Offset
		}
		resize(&v.buf, int(new_len))
		if v.pos > new_len {
			v.pos = new_len
		}
		return nil
	case Core_File:
		err := os.truncate(v.file, new_len)
		if err != nil {
			// Read-only file handles ignore setLength just like Zig/Go xitdb.
			return nil
		}
		pos := os.seek(v.file, 0, .Current) or_return
		if pos > new_len {
			os.seek(v.file, new_len, .Start) or_return
		}
		return nil
	case Core_Buffered_File:
		buf_size := i64(len(v.memory.buf))
		if new_len <= v.memory_pos {
			clear(&v.memory.buf)
			v.flushed_len = 0
		} else if new_len < v.memory_pos + buf_size {
			new_buf_len := int(new_len - v.memory_pos)
			resize(&v.memory.buf, new_buf_len)
			if v.flushed_len > new_buf_len {
				v.flushed_len = new_buf_len
			}
		}
		v.file_len = nil
		if err := os.truncate(v.file.file, new_len); err == nil {
			v.file_len = new_len
		}
		if v.pos > new_len {
			v.pos = new_len
		}
		return nil
	}
	return .Invalid_Database
}

// Read up to len(p) bytes into p. Returns 0, io.Error.EOF at end of stream.
core_read :: proc(c: ^Core, p: []u8) -> (read_n: int, err: Error) {
	if len(p) == 0 {
		return 0, nil
	}
	switch &v in c {
	case Core_Memory:
		if v.pos >= i64(len(v.buf)) {
			return 0, io.Error.EOF
		}
		avail := int(i64(len(v.buf)) - v.pos)
		to_read := min(len(p), avail)
		copy(p[:to_read], v.buf[int(v.pos):int(v.pos) + to_read])
		v.pos += i64(to_read)
		return to_read, nil
	case Core_File:
		return os.read(v.file, p)
	case Core_Buffered_File:
		buf_len := i64(len(v.memory.buf))
		if buf_len > 0 && v.pos >= v.memory_pos && v.pos < v.memory_pos + buf_len {
			mem_off := int(v.pos - v.memory_pos)
			size := min(len(p), int(buf_len) - mem_off)
			copy(p[:size], v.memory.buf[mem_off:mem_off + size])
			v.pos += i64(size)
			return size, nil
		}
		os.seek(v.file.file, v.pos, .Start) or_return
		max_size := len(p)
		if buf_len > 0 && v.pos < v.memory_pos {
			max_size = min(len(p), int(v.memory_pos - v.pos))
		}
		n, err := os.read(v.file.file, p[:max_size])
		v.pos += i64(n)
		return n, err
	}
	return 0, .Invalid_Database
}

// Read exactly len(p) bytes or return an error (.Unexpected_EOF on short read).
core_read_exact :: proc(c: ^Core, p: []u8) -> Error {
	if len(p) == 0 {
		return nil
	}
	#partial switch &v in c {
	case Core_Memory:
		end_pos := v.pos + i64(len(p))
		if v.pos < 0 || end_pos > i64(len(v.buf)) {
			v.pos = i64(len(v.buf))
			return Xitdb_Error.Unexpected_EOF
		}
		copy(p, v.buf[int(v.pos):int(end_pos)])
		v.pos = end_pos
		return nil
	}
	total := 0
	for total < len(p) {
		n, err := core_read(c, p[total:])
		total += n
		if err != nil {
			if err == io.Error.EOF {
				if total == len(p) {
					return nil
				}
				return Xitdb_Error.Unexpected_EOF
			}
			return err
		}
		if n == 0 {
			return Xitdb_Error.Unexpected_EOF
		}
	}
	return nil
}

// Write all bytes of `p` to `c`.
core_write_all :: proc(c: ^Core, p: []u8) -> Error {
	if len(p) == 0 {
		return nil
	}
	switch &v in c {
	case Core_Memory:
		old_size := int(len(v.buf))
		end_pos := int(v.pos) + len(p)
		if end_pos > old_size {
			resize(&v.buf, end_pos)
		}
		copy(v.buf[int(v.pos):end_pos], p)
		v.pos = i64(end_pos)
		return nil
	case Core_File:
		written := 0
		for written < len(p) {
			n := os.write(v.file, p[written:]) or_return
			if n == 0 {
				return io.Error.Short_Write
			}
			written += n
		}
		return nil
	case Core_Buffered_File:
		n := i64(len(p))
		if v.file_len == nil {
			fl := os.file_size(v.file.file) or_return
			v.file_len = fl
		}
		buf_size := i64(len(v.memory.buf))
		if buf_size > 0 && v.pos + n <= v.memory_pos {
			// Write is strictly before the buffered tail window (e.g. Root_Header at offset 20):
			// write directly to the file without evicting the hot tail buffer.
			_buffered_write_to_file(&v, v.pos, p) or_return
			v.pos += n
			return nil
		}
		if buf_size == 0 {
			v.memory_pos = v.pos
			v.flushed_len = 0
		} else if v.pos > v.memory_pos + buf_size ||
		          (v.pos >= v.memory_pos && v.pos - v.memory_pos + n > v.memory_max_size) {
			_buffered_flush(&v) or_return
			clear(&v.memory.buf)
			v.flushed_len = 0
			v.memory_pos = v.pos
		}
		buf_size = i64(len(v.memory.buf))
		if v.pos >= v.memory_pos && v.pos - v.memory_pos + n <= v.memory_max_size {
			rel_off := int(v.pos - v.memory_pos)
			end_off := rel_off + len(p)
			if end_off > len(v.memory.buf) {
				resize(&v.memory.buf, end_off)
			}
			copy(v.memory.buf[rel_off:end_off], p)
			if rel_off < v.flushed_len {
				if end_off <= v.flushed_len {
					_buffered_write_to_file(&v, v.pos, p) or_return
				} else {
					v.flushed_len = rel_off
				}
			}
		} else {
			if v.pos < v.memory_pos + buf_size && v.pos + n > v.memory_pos {
				_buffered_flush(&v) or_return
				clear(&v.memory.buf)
				v.flushed_len = 0
			}
			_buffered_write_to_file(&v, v.pos, p) or_return
		}
		v.pos += n
		return nil
	}
	return .Invalid_Database
}

core_read_byte :: proc(c: ^Core) -> (v: u8, err: Error) {
	b: [1]u8
	core_read_exact(c, b[:]) or_return
	return b[0], nil
}

core_write_byte :: proc(c: ^Core, v: u8) -> Error {
	b := [1]u8{v}
	return core_write_all(c, b[:])
}

core_read_u16 :: proc(c: ^Core) -> (v: u16, err: Error) {
	b: [2]u8
	core_read_exact(c, b[:]) or_return
	v, _ = endian.get_u16(b[:], .Big)
	return v, nil
}

core_write_u16 :: proc(c: ^Core, v: u16) -> Error {
	b: [2]u8
	endian.put_u16(b[:], .Big, v)
	return core_write_all(c, b[:])
}

core_read_u32 :: proc(c: ^Core) -> (v: u32, err: Error) {
	b: [4]u8
	core_read_exact(c, b[:]) or_return
	v, _ = endian.get_u32(b[:], .Big)
	return v, nil
}

core_write_u32 :: proc(c: ^Core, v: u32) -> Error {
	b: [4]u8
	endian.put_u32(b[:], .Big, v)
	return core_write_all(c, b[:])
}

core_read_long :: proc(c: ^Core) -> (res: i64, err: Error) {
	b: [8]u8
	core_read_exact(c, b[:]) or_return
	v, _ := endian.get_u64(b[:], .Big)
	if i64(v) < 0 {
		return 0, Xitdb_Error.Expected_Unsigned_Long
	}
	return i64(v), nil
}

core_write_long :: proc(c: ^Core, v: i64) -> Error {
	if v < 0 {
		return Xitdb_Error.Expected_Unsigned_Long
	}
	b: [8]u8
	endian.put_u64(b[:], .Big, u64(v))
	return core_write_all(c, b[:])
}

core_read_i64 :: proc(c: ^Core) -> (res: i64, err: Error) {
	b: [8]u8
	core_read_exact(c, b[:]) or_return
	v, _ := endian.get_u64(b[:], .Big)
	return i64(v), nil
}

core_write_i64 :: proc(c: ^Core, v: i64) -> Error {
	b: [8]u8
	endian.put_u64(b[:], .Big, u64(v))
	return core_write_all(c, b[:])
}

core_read_slot_raw :: proc(c: ^Core) -> (s: Slot, err: Error) {
	buf: [SLOT_LENGTH]u8
	core_read_exact(c, buf[:]) or_return
	return slot_from_bytes_raw(buf), nil
}

core_read_slot :: proc(c: ^Core) -> (s: Slot, err: Error) {
	buf: [SLOT_LENGTH]u8
	core_read_exact(c, buf[:]) or_return
	return slot_from_bytes(buf)
}

core_write_slot :: proc(c: ^Core, s: Slot) -> Error {
	buf := slot_to_bytes(s)
	return core_write_all(c, buf[:])
}
