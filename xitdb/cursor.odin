package xitdb

import "base:intrinsics"
import "core:encoding/endian"
import "core:mem"

Read_Cursor :: struct {
	slot_ptr:  Slot_Pointer,
	db:        ^Database,
	frozen_at: i64,
}

Write_Cursor :: struct {
	using read_cursor: Read_Cursor,
	transaction_id:    u64,
}

Read_KV_Pair_Cursor :: struct {
	value_cursor: Read_Cursor,
	key_cursor:   Read_Cursor,
	hash:         []u8,
}

Write_KV_Pair_Cursor :: struct {
	value_cursor: Write_Cursor,
	key_cursor:   Write_Cursor,
	hash:         []u8,
}

new_write_cursor :: proc(slot_ptr: Slot_Pointer, db: ^Database) -> Write_Cursor {
	c := Write_Cursor{
		read_cursor = Read_Cursor{
			slot_ptr  = slot_ptr,
			db        = db,
			frozen_at = 0,
		},
	}
	if slot_ptr.position != nil && !is_root(slot_ptr) {
		if active, ok := db.transaction.?; ok {
			c.transaction_id = active.id
		}
	}
	return c
}

cursor_read_only :: proc(c: Write_Cursor) -> Read_Cursor {
	return c.read_cursor
}

cursor_resolved :: proc(c: Read_Cursor) -> (res: Slot_Pointer, err: Error) {
	if is_root(c.slot_ptr) {
		header := database_read_root_header(c.db) or_return
		position := header.file_size - ROOT_TRAILER_LENGTH
		return Slot_Pointer{position = position, slot = header.root}, nil
	}
	return c.slot_ptr, nil
}

cursor_resolved_cursor :: proc(c: Read_Cursor) -> (res: Read_Cursor, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	return Read_Cursor{slot_ptr = slot_ptr, db = c.db, frozen_at = c.frozen_at}, nil
}

cursor_slot :: proc(c: Read_Cursor) -> (res: Slot, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	return slot_ptr.slot, nil
}

cursor_read_path :: proc(c: Read_Cursor, path: []Path_Part) -> (res: Maybe(Read_Cursor), err: Error) {
	start := cursor_resolved(c) or_return
	slot_ptr: Slot_Pointer
	slot_ptr, err = read_slot_pointer(c.db, .Read_Only, path, 0, start, 0)
	if err != nil {
		if err == .Key_Not_Found {
			return nil, nil
		}
		return nil, err
	}
	return Read_Cursor{slot_ptr = slot_ptr, db = c.db}, nil
}

cursor_read_path_slot :: proc(c: Read_Cursor, path: []Path_Part) -> (res: Maybe(Slot), err: Error) {
	start := cursor_resolved(c) or_return
	slot_ptr: Slot_Pointer
	slot_ptr, err = read_slot_pointer(c.db, .Read_Only, path, 0, start, 0)
	if err != nil {
		if err == .Key_Not_Found {
			return nil, nil
		}
		return nil, err
	}
	if !slot_empty(slot_ptr.slot) {
		return slot_ptr.slot, nil
	}
	return nil, nil
}

cursor_check_writable :: proc(c: ^Write_Cursor) -> Error {
	if c.transaction_id != 0 {
		active, has_tx := c.db.transaction.?
		if !has_tx || active.id != c.transaction_id {
			return .Expired_Transaction
		}
	}
	if !is_root(c.slot_ptr) && c.transaction_id == 0 && c.db.tx_start == nil {
		return .Expected_Tx_Start
	}
	return database_check_frozen_slot(c.db, c.slot_ptr)
}

cursor_reload_slot :: proc(c: ^Write_Cursor) -> Error {
	if (c.transaction_id != 0 || c.db.tx_start != nil) && !is_root(c.slot_ptr) {
		if pos, ok := c.slot_ptr.position.?; ok {
			slot := core_read_slot_at(c.db.core, pos) or_return
			c.slot_ptr = slot_pointer_with_slot(c.slot_ptr, slot)
		}
	}
	return nil
}

cursor_write_path :: proc(c: ^Write_Cursor, path: []Path_Part) -> (res: Write_Cursor, err: Error) {
	cursor_check_writable(c) or_return
	if (c.db.transaction != nil || c.db.tx_start != nil) && is_root(c.slot_ptr) && len(path) > 0 {
		return {}, .Nested_Top_Level_Write
	}

	starts_transaction := c.db.transaction == nil && is_root(c.slot_ptr)
	if starts_transaction {
		c.db.tx_seq += 1
		c.db.transaction = Transaction{id = c.db.tx_seq}
	}
	defer if starts_transaction {
		c.db.transaction = nil
	}

	err = nil
	switch c.slot_ptr.slot.tag {
	case .Array_List, .Linked_Array_List, .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set, .Sorted_Map, .Sorted_Set:
		is_init := false
		if len(path) > 0 {
			_, is_init = init_tag(path[0])
		}
		has_frozen_tx := false
		if active, ok := c.db.transaction.?; ok {
			has_frozen_tx = active.frozen_at != nil || c.frozen_at != 0
		}
		if is_init || has_frozen_tx {
			err = cursor_reload_slot(c)
		}
	case .None, .Index, .Bytes, .Short_Bytes, .Uint, .Int, .Float, .KV_Pair, .Sorted_KV_Pair:
		err = cursor_reload_slot(c)
	}
	slot_ptr: Slot_Pointer
	if err == nil {
		slot_ptr, err = read_slot_pointer(c.db, .Read_Write, path, 0, c.slot_ptr, c.frozen_at)
	}
	if err != nil {
		if c.db.tx_start == nil {
			_ = database_truncate(c.db)
		}
		return {}, err
	}
	if c.db.tx_start == nil {
		core_sync(c.db.core) or_return
	}
	ends_with_ctx := false
	if len(path) > 0 {
		_, ends_with_ctx = path[len(path) - 1].(Context)
	}
	res = new_write_cursor(slot_ptr, c.db)
	res.frozen_at = c.frozen_at
	if ends_with_ctx {
		cursor_reload_slot(c) or_return
		cursor_reload_slot(&res) or_return
	} else if c.slot_ptr.position != nil && c.slot_ptr.position == slot_ptr.position {
		c.slot_ptr = slot_ptr
	} else if active, ok := c.db.transaction.?; !ok || active.frozen_at != nil || c.frozen_at != 0 || c.slot_ptr.slot.tag == .None {
		cursor_reload_slot(c) or_return
	}
	return res, nil
}

cursor_freeze :: proc(c: ^Write_Cursor) -> Error {
	if c.db.tx_start == nil {
		return .Expected_Tx_Start
	}
	length := core_length(c.db.core) or_return
	c.frozen_at = length
	return nil
}

cursor_write :: proc(c: ^Write_Cursor, data: Writeable_Data) -> Error {
	next := cursor_write_path(c, []Path_Part{Write_Data{data = data}}) or_return
	c.slot_ptr = next.slot_ptr
	return nil
}

cursor_write_if_empty :: proc(c: ^Write_Cursor, data: Writeable_Data) -> Error {
	cursor_check_writable(c) or_return
	slot_ptr := cursor_resolved(c.read_cursor) or_return
	if slot_empty(slot_ptr.slot) {
		return cursor_write(c, data)
	}
	return nil
}

cursor_read_uint :: proc(c: Read_Cursor) -> (res: u64, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	if slot_ptr.slot.tag != .Uint {
		return 0, .Unexpected_Tag
	}
	if slot_ptr.slot.value < 0 {
		return 0, .Expected_Unsigned_Long
	}
	return u64(slot_ptr.slot.value), nil
}

cursor_read_int :: proc(c: Read_Cursor) -> (res: i64, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	if slot_ptr.slot.tag != .Int {
		return 0, .Unexpected_Tag
	}
	return slot_ptr.slot.value, nil
}

cursor_read_float :: proc(c: Read_Cursor) -> (res: f64, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	if slot_ptr.slot.tag != .Float {
		return 0, .Unexpected_Tag
	}
	return transmute(f64)slot_ptr.slot.value, nil
}

cursor_read_bytes :: proc(c: Read_Cursor, max_size: i64 = 0, allocator := context.allocator) -> (res: []u8, err: Error) {
	obj := cursor_read_bytes_object(c, max_size, allocator) or_return
	if obj.format_tag != nil {
		delete(obj.format_tag, allocator)
	}
	return obj.value, nil
}

cursor_read_string :: proc(c: Read_Cursor, max_size: i64 = 0, allocator := context.allocator) -> (res: string, err: Error) {
	b := cursor_read_bytes(c, max_size, allocator) or_return
	return string(b), nil
}

cursor_read_bytes_object :: proc(c: Read_Cursor, max_size: i64 = 0, allocator := context.allocator) -> (res: Bytes, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	#partial switch slot_ptr.slot.tag {
	case .None:
		return Bytes{value = make([]u8, 0, allocator)}, nil

	case .Bytes:
		if slot_ptr.slot.value < 0 {
			return {}, .Expected_Unsigned_Long
		}
		value_size := core_read_long_at(c.db.core, slot_ptr.slot.value) or_return
		if value_size < 0 {
			return {}, .Expected_Unsigned_Long
		}
		if max_size > 0 && value_size > max_size {
			return {}, .Stream_Too_Long
		}
		extra: i64 = 10 if slot_ptr.slot.full else 8
		core_len := core_length(c.db.core) or_return
		if slot_ptr.slot.value > core_len || extra > core_len - slot_ptr.slot.value || value_size > core_len - slot_ptr.slot.value - extra {
			return {}, Xitdb_Error.Unexpected_EOF
		}
		value := make([]u8, int(value_size), allocator)
		err = core_read_exact_at(c.db.core, slot_ptr.slot.value + 8, value)
		if err != nil {
			delete(value, allocator)
			return {}, err
		}
		format_tag: []u8
		if slot_ptr.slot.full {
			format_tag = make([]u8, 2, allocator)
			if ft_err := core_read_exact_at(c.db.core, slot_ptr.slot.value + 8 + value_size, format_tag); ft_err != nil {
				delete(value, allocator)
				delete(format_tag, allocator)
				return {}, ft_err
			}
		}
		return Bytes{value = value, format_tag = format_tag}, nil

	case .Short_Bytes:
		buf: [8]u8
		endian.unchecked_put_u64be(buf[:], u64(slot_ptr.slot.value))
		total_size: i64 = 6 if slot_ptr.slot.full else 8
		value_size: i64 = 0
		for b in buf {
			if b == 0 || value_size == total_size {
				break
			}
			value_size += 1
		}
		if max_size > 0 && value_size > max_size {
			return {}, .Stream_Too_Long
		}
		format_tag: []u8
		if slot_ptr.slot.full {
			format_tag = make([]u8, 2, allocator)
			copy(format_tag, buf[total_size : total_size + 2])
		}
		value := make([]u8, int(value_size), allocator)
		copy(value, buf[:value_size])
		return Bytes{value = value, format_tag = format_tag}, nil

	case:
		return {}, .Unexpected_Tag
	}
}

cursor_read_bytes_buf :: proc(c: Read_Cursor, buffer: []u8) -> (res: Bytes, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	#partial switch slot_ptr.slot.tag {
	case .None:
		if len(buffer) == 0 {
			return Bytes{value = buffer}, nil
		}
		return {}, .End_Of_Stream

	case .Bytes:
		if slot_ptr.slot.value < 0 {
			return {}, .Expected_Unsigned_Long
		}
		value_size := core_read_long_at(c.db.core, slot_ptr.slot.value) or_return
		if value_size < 0 {
			return {}, .Expected_Unsigned_Long
		}
		if value_size > i64(len(buffer)) {
			return {}, .Stream_Too_Long
		}
		extra: i64 = 10 if slot_ptr.slot.full else 8
		core_len := core_length(c.db.core) or_return
		if slot_ptr.slot.value > core_len || extra > core_len - slot_ptr.slot.value || value_size > core_len - slot_ptr.slot.value - extra {
			return {}, Xitdb_Error.Unexpected_EOF
		}
		if slot_ptr.slot.full {
			if value_size <= i64(len(buffer)) - 2 {
				combined := buffer[:value_size + 2]
				core_read_exact_at(c.db.core, slot_ptr.slot.value + 8, combined) or_return
				return Bytes{
					value      = combined[:value_size],
					format_tag = combined[value_size : value_size + 2],
				}, nil
			}
			value := buffer[:value_size]
			core_read_exact_at(c.db.core, slot_ptr.slot.value + 8, value) or_return
			ft := make([]u8, 2, context.temp_allocator)
			core_read_exact_at(c.db.core, slot_ptr.slot.value + 8 + value_size, ft) or_return
			return Bytes{value = value, format_tag = ft}, nil
		}
		value := buffer[:value_size]
		core_read_exact_at(c.db.core, slot_ptr.slot.value + 8, value) or_return
		return Bytes{value = value}, nil

	case .Short_Bytes:
		buf: [8]u8
		endian.unchecked_put_u64be(buf[:], u64(slot_ptr.slot.value))
		total_size: i64 = 6 if slot_ptr.slot.full else 8
		value_size: i64 = 0
		for b in buf {
			if b == 0 || value_size == total_size {
				break
			}
			value_size += 1
		}
		if value_size > i64(len(buffer)) {
			return {}, .Stream_Too_Long
		}
		copy(buffer[:value_size], buf[:value_size])
		format_tag: []u8
		if slot_ptr.slot.full {
			if value_size + 2 <= i64(len(buffer)) {
				buffer[value_size] = buf[total_size]
				buffer[value_size + 1] = buf[total_size + 1]
				format_tag = buffer[value_size : value_size + 2]
			} else {
				ft := make([]u8, 2, context.temp_allocator)
				copy(ft, buf[total_size : total_size + 2])
				format_tag = ft
			}
		}
		return Bytes{value = buffer[:value_size], format_tag = format_tag}, nil

	case:
		return {}, .Unexpected_Tag
	}
}

cursor_read_kv_pair :: proc(c: Read_Cursor, allocator := context.temp_allocator) -> (res: Read_KV_Pair_Cursor, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	if is_key_only_entry(slot_ptr.slot) {
		// A key-only entry is its own key slot, so its key is where the entry is.
		return Read_KV_Pair_Cursor{
			value_cursor = Read_Cursor{slot_ptr = Slot_Pointer{position = nil, slot = Slot{}}, db = c.db, frozen_at = c.frozen_at},
			key_cursor   = Read_Cursor{slot_ptr = Slot_Pointer{position = slot_ptr.position, slot = slot_ptr.slot}, db = c.db, frozen_at = c.frozen_at},
			hash         = nil,
		}, nil
	}
	kv_pair := decode_kv_pair_at(c.db.core, slot_ptr.slot.value, slot_ptr.slot.tag, int(c.db.header.hash_size), allocator) or_return
	key_slot_pos := database_kv_key_position(c.db, slot_ptr.slot) or_return
	value_slot_pos := database_kv_value_position(c.db, slot_ptr.slot) or_return
	return Read_KV_Pair_Cursor{
		value_cursor = Read_Cursor{slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}, db = c.db, frozen_at = c.frozen_at},
		key_cursor   = Read_Cursor{slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}, db = c.db, frozen_at = c.frozen_at},
		hash         = kv_pair.hash,
	}, nil
}

// Zero-allocation KV pair reader that decodes only the key and value slots on the stack without allocating the hash.
cursor_read_kv_pair_slots :: proc(c: Read_Cursor) -> (key_cursor: Read_Cursor, value_cursor: Read_Cursor, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	if is_key_only_entry(slot_ptr.slot) {
		return Read_Cursor{slot_ptr = Slot_Pointer{position = slot_ptr.position, slot = slot_ptr.slot}, db = c.db, frozen_at = c.frozen_at},
			Read_Cursor{slot_ptr = Slot_Pointer{position = nil, slot = Slot{}}, db = c.db, frozen_at = c.frozen_at},
			nil
	}
	if slot_ptr.slot.tag != .KV_Pair && slot_ptr.slot.tag != .Sorted_KV_Pair {
		return {}, {}, .Unexpected_Tag
	}
	key_pos, k_ok := _checked_add_i64(slot_ptr.slot.value, database_kv_key_offset(c.db, slot_ptr.slot.tag))
	if !k_ok {
		return {}, {}, .End_Of_Stream
	}
	val_pos, v_ok := _checked_add_i64(key_pos, SLOT_LENGTH)
	if !v_ok {
		return {}, {}, .End_Of_Stream
	}
	b: [SLOT_LENGTH * 2]u8 = ---
	core_read_exact_at(c.db.core, key_pos, b[:]) or_return
	key_slot := slot_from_slice_raw(b[0:SLOT_LENGTH])
	tag_validate(key_slot.tag) or_return
	val_slot := slot_from_slice_raw(b[SLOT_LENGTH : SLOT_LENGTH * 2])
	tag_validate(val_slot.tag) or_return
	return Read_Cursor{slot_ptr = Slot_Pointer{position = key_pos, slot = key_slot}, db = c.db, frozen_at = c.frozen_at},
		Read_Cursor{slot_ptr = Slot_Pointer{position = val_pos, slot = val_slot}, db = c.db, frozen_at = c.frozen_at},
		nil
}

cursor_write_kv_pair :: proc(c: Write_Cursor, allocator := context.temp_allocator) -> (res: Write_KV_Pair_Cursor, err: Error) {
	rkv := cursor_read_kv_pair(c.read_cursor, allocator) or_return
	return Write_KV_Pair_Cursor{
		value_cursor = Write_Cursor{read_cursor = rkv.value_cursor, transaction_id = c.transaction_id},
		key_cursor   = Write_Cursor{read_cursor = rkv.key_cursor, transaction_id = c.transaction_id},
		hash         = rkv.hash,
	}, nil
}

cursor_count :: proc(c: Read_Cursor) -> (res: i64, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	#partial switch slot_ptr.slot.tag {
	case .None:
		return 0, nil
	case .Array_List:
		hb: [ARRAY_LIST_HEADER_LENGTH]u8
		core_read_exact_at(c.db.core, slot_ptr.slot.value, hb[:]) or_return
		header := array_list_header_from_bytes(hb) or_return
		return header.size, nil
	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
		hb: [BTREE_HEADER_LENGTH]u8
		core_read_exact_at(c.db.core, slot_ptr.slot.value, hb[:]) or_return
		header := btree_header_from_bytes(hb) or_return
		return header.size, nil
	case .Bytes:
		val := core_read_long_at(c.db.core, slot_ptr.slot.value) or_return
		return check_long(val)
	case .Short_Bytes:
		buf: [8]u8
		endian.unchecked_put_u64be(buf[:], u64(slot_ptr.slot.value))
		total_size := 6 if slot_ptr.slot.full else 8
		size := 0
		for b in buf {
			if b == 0 || size == total_size {
				break
			}
			size += 1
		}
		return i64(size), nil
	case .Counted_Hash_Map, .Counted_Hash_Set:
		val := core_read_long_at(c.db.core, slot_ptr.slot.value) or_return
		return check_long(val)
	case:
		return 0, .Unexpected_Tag
	}
}

// Cursor_Reader

Cursor_Reader :: struct {
	parent:            Read_Cursor,
	size:              i64,
	start_position:    i64,
	relative_position: i64,
}

cursor_reader :: proc(c: Read_Cursor) -> (res: Cursor_Reader, err: Error) {
	slot_ptr := cursor_resolved(c) or_return
	#partial switch slot_ptr.slot.tag {
	case .Bytes:
		if slot_ptr.slot.value < 0 {
			return {}, .Expected_Unsigned_Long
		}
		size := core_read_long_at(c.db.core, slot_ptr.slot.value) or_return
		if size < 0 {
			return {}, .Expected_Unsigned_Long
		}
		core_len := core_length(c.db.core) or_return
		extra: i64 = 10 if slot_ptr.slot.full else 8
		if slot_ptr.slot.value > core_len || extra > core_len - slot_ptr.slot.value || size > core_len - slot_ptr.slot.value - extra {
			return {}, Xitdb_Error.Unexpected_EOF
		}
		start_position := slot_ptr.slot.value + 8
		return Cursor_Reader{
			parent            = c,
			size              = size,
			start_position    = start_position,
			relative_position = 0,
		}, nil
	case .Short_Bytes:
		buf: [8]u8 = ---
		endian.unchecked_put_u64be(buf[:], u64(slot_ptr.slot.value))
		total_size := 6 if slot_ptr.slot.full else 8
		value_size := 0
		for b in buf {
			if b == 0 || value_size == total_size {
				break
			}
			value_size += 1
		}
		pos, ok := slot_ptr.position.?
		if !ok {
			return {}, .Expected_Slot_Position
		}
		start_position := pos + 1
		return Cursor_Reader{
			parent            = c,
			size              = i64(value_size),
			start_position    = start_position,
			relative_position = 0,
		}, nil
	case:
		return {}, .Unexpected_Tag
	}
}

cursor_reader_read :: #force_inline proc(r: ^Cursor_Reader, p: []u8) -> (res: int, err: Error) {
	if r.size < r.relative_position {
		return 0, .End_Of_Stream
	}
	if r.start_position < 0 || r.relative_position < 0 || r.start_position > max(i64) - r.relative_position {
		return 0, Xitdb_Error.Unexpected_EOF
	}
	read_size := min(i64(len(p)), r.size - r.relative_position)
	if read_size == 0 {
		return 0, nil
	}
	if src_slice, in_mem, slice_err := core_slice_at(r.parent.db.core, r.start_position + r.relative_position, int(read_size)); in_mem {
		if slice_err != nil {
			return 0, slice_err
		}
		intrinsics.mem_copy_non_overlapping(raw_data(p), raw_data(src_slice), int(read_size))
		r.relative_position += read_size
		return int(read_size), nil
	}
	core_read_exact_at(r.parent.db.core, r.start_position + r.relative_position, p[:read_size]) or_return
	r.relative_position += read_size
	return int(read_size), nil
}

cursor_reader_read_fully :: #force_inline proc(r: ^Cursor_Reader, buf: []u8) -> Error {
	n := i64(len(buf))
	if r.size < r.relative_position || r.size - r.relative_position < n {
		return .End_Of_Stream
	}
	if r.start_position < 0 || r.relative_position < 0 || r.start_position > max(i64) - r.relative_position {
		return Xitdb_Error.Unexpected_EOF
	}
	if n == 0 {
		return nil
	}
	if src_slice, in_mem, slice_err := core_slice_at(r.parent.db.core, r.start_position + r.relative_position, int(n)); in_mem {
		if slice_err != nil {
			return slice_err
		}
		intrinsics.mem_copy_non_overlapping(raw_data(buf), raw_data(src_slice), int(n))
		r.relative_position += n
		return nil
	}
	core_read_exact_at(r.parent.db.core, r.start_position + r.relative_position, buf) or_return
	r.relative_position += n
	return nil
}

cursor_reader_seek_to :: #force_inline proc(r: ^Cursor_Reader, position: i64) -> Error {
	if position < 0 || position > r.size {
		return Xitdb_Error.Invalid_Offset
	}
	r.relative_position = position
	return nil
}

cursor_reader_read_all :: proc(r: ^Cursor_Reader, allocator := context.allocator) -> (res: []u8, err: Error) {
	if r.size < r.relative_position {
		return nil, .End_Of_Stream
	}
	remaining := r.size - r.relative_position
	core_len := core_length(r.parent.db.core) or_return
	if r.start_position < 0 || r.relative_position < 0 || r.start_position > core_len || r.relative_position > core_len - r.start_position || remaining > core_len - r.start_position - r.relative_position {
		return nil, Xitdb_Error.Unexpected_EOF
	}
	buf := make([]u8, int(remaining), allocator)
	err = cursor_reader_read_fully(r, buf)
	if err != nil {
		delete(buf, allocator)
		return nil, err
	}
	return buf, nil
}

// Cursor_Writer

Cursor_Writer :: struct {
	parent:            ^Write_Cursor,
	size:              i64,
	slot:              Slot,
	start_position:    i64,
	relative_position: i64,
	format_tag:        []u8,
}

cursor_writer :: proc(c: ^Write_Cursor) -> (res: Cursor_Writer, err: Error) {
	cursor_check_writable(c) or_return
	if is_root(c.slot_ptr) {
		return {}, .Cursor_Not_Writeable
	}
	if c.db.tx_start == nil {
		return {}, .Expected_Tx_Start
	}
	ptr_pos := core_length(c.db.core) or_return
	core_seek_to(c.db.core, ptr_pos) or_return
	core_write_long(c.db.core, 0) or_return
	start_position := core_length(c.db.core) or_return
	return Cursor_Writer{
		parent            = c,
		size              = 0,
		slot              = Slot{value = ptr_pos, tag = .Bytes},
		start_position    = start_position,
		relative_position = 0,
	}, nil
}

cursor_writer_check_writable :: proc(w: ^Cursor_Writer) -> Error {
	cursor_check_writable(w.parent) or_return
	if w.parent.db.tx_start == nil {
		return .Expected_Tx_Start
	}
	if active, ok := w.parent.db.transaction.?; ok {
		if fa, has_fa := active.frozen_at.?; has_fa && w.slot.value < fa {
			return .Frozen_Bytes
		}
	}
	return nil
}

cursor_writer_write :: proc(w: ^Cursor_Writer, p: []u8) -> (res: int, err: Error) {
	cursor_writer_check_writable(w) or_return
	if w.size < w.relative_position {
		return 0, .End_Of_Stream
	}
	new_position := w.relative_position + i64(len(p))
	if new_position > w.size {
		end := core_length(w.parent.db.core) or_return
		if end != w.start_position + w.size {
			return 0, .Unexpected_Writer_Position
		}
	}
	core_seek_to(w.parent.db.core, w.start_position + w.relative_position) or_return
	core_write_all(w.parent.db.core, p) or_return
	w.relative_position = new_position
	if w.relative_position > w.size {
		w.size = w.relative_position
	}
	return len(p), nil
}

cursor_writer_seek_to :: proc(w: ^Cursor_Writer, position: i64) -> Error {
	if position < 0 || position > w.size {
		return Xitdb_Error.Invalid_Offset
	}
	w.relative_position = position
	return nil
}

cursor_writer_finish :: proc(w: ^Cursor_Writer) -> Error {
	cursor_writer_check_writable(w) or_return
	if w.format_tag != nil {
		if len(w.format_tag) != 2 {
			return .Invalid_Format_Tag_Size
		}
		w.slot = slot_with_full(w.slot, true)
		format_tag_pos := core_length(w.parent.db.core) or_return
		core_seek_to(w.parent.db.core, format_tag_pos) or_return
		if w.start_position + w.size != format_tag_pos {
			return .Unexpected_Writer_Position
		}
		core_write_all(w.parent.db.core, w.format_tag) or_return
	}
	core_seek_to(w.parent.db.core, w.slot.value) or_return
	core_write_long(w.parent.db.core, w.size) or_return

	position, pos_ok := w.parent.slot_ptr.position.?
	if !pos_ok {
		return .Cursor_Not_Writeable
	}
	core_seek_to(w.parent.db.core, position) or_return
	core_write_slot(w.parent.db.core, w.slot) or_return

	w.parent.slot_ptr = slot_pointer_with_slot(w.parent.slot_ptr, w.slot)
	if w.parent.db.tx_start == nil {
		return core_sync(w.parent.db.core)
	}
	return nil
}

// Cursor_Iterator - stack-based tree traversal

Iter_Level_Kind :: enum u8 {
	Any,
	BTree_Branch,
	BTree_Leaf,
	Array_Branch,
	Array_Leaf,
}

Iter_Level :: struct {
	position: i64,
	block:    [SLOT_COUNT]Slot,
	index:    u8,
	count:    u8,
	shift:    u8,
	kind:     Iter_Level_Kind,
}

Cursor_Iterator :: struct {
	cursor:    Read_Cursor,
	size:      i64,
	index:     i64,
	stack:     [ITERATOR_STACK_SIZE]Iter_Level,
	stack_len: int,
}

@(private)
_decode_slot_block_raw :: proc(raw: []u8, block: ^[SLOT_COUNT]Slot) -> Error {
	for j in 0 ..< SLOT_COUNT {
		block[j] = slot_from_slice(raw[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH]) or_return
	}
	return nil
}

@(private)
_fill_slot_block_from :: proc(cursor: Read_Cursor, position: i64, start_idx: int, end_idx: int, level: ^Iter_Level) -> Error {
	if position < 0 {
		return Xitdb_Error.Expected_Unsigned_Long
	}
	if _, block_end_ok := _checked_add_i64(position, INDEX_BLOCK_SIZE); !block_end_ok {
		return Xitdb_Error.Unexpected_EOF
	}
	level.position = position
	level.index = u8(start_idx)
	level.count = u8(end_idx)
	level.shift = 0
	level.kind = .Any
	rem_slots := end_idx - start_idx
	if rem_slots <= 0 {
		return nil
	}
	read_pos, r_ok := _checked_add_i64(position, i64(start_idx) * SLOT_LENGTH)
	if !r_ok {
		return Xitdb_Error.Unexpected_EOF
	}
	byte_len := rem_slots * SLOT_LENGTH
	if _, end_ok := _checked_add_i64(read_pos, i64(byte_len)); !end_ok {
		return Xitdb_Error.Unexpected_EOF
	}
	if mem_slice, in_mem, slice_err := core_slice_at(cursor.db.core, read_pos, byte_len); in_mem {
		if slice_err != nil {
			return slice_err
		}
		for j in 0 ..< rem_slots {
			level.block[start_idx + j] = slot_from_slice(mem_slice[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH]) or_return
		}
		return nil
	}
	index_block_bytes: [INDEX_BLOCK_SIZE]u8 = ---
	core_read_exact_at(cursor.db.core, read_pos, index_block_bytes[:byte_len]) or_return
	for j in 0 ..< rem_slots {
		level.block[start_idx + j] = slot_from_slice(index_block_bytes[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH]) or_return
	}
	return nil
}

@(private)
_fill_slot_block_rev :: proc(cursor: Read_Cursor, position: i64, count: int, level: ^Iter_Level) -> Error {
	if position < 0 {
		return Xitdb_Error.Expected_Unsigned_Long
	}
	if _, block_end_ok := _checked_add_i64(position, INDEX_BLOCK_SIZE); !block_end_ok {
		return Xitdb_Error.Unexpected_EOF
	}
	level.position = position
	level.shift = 0
	level.kind = .Any
	if count <= 0 {
		level.index = 0
		level.count = 0
		return nil
	}
	level.index = u8(count - 1)
	level.count = u8(count)
	byte_len := count * SLOT_LENGTH
	if _, end_ok := _checked_add_i64(position, i64(byte_len)); !end_ok {
		return Xitdb_Error.Unexpected_EOF
	}
	if mem_slice, in_mem, slice_err := core_slice_at(cursor.db.core, position, byte_len); in_mem {
		if slice_err != nil {
			return slice_err
		}
		for j in 0 ..< count {
			level.block[j] = slot_from_slice(mem_slice[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH]) or_return
		}
		return nil
	}
	index_block_bytes: [INDEX_BLOCK_SIZE]u8 = ---
	core_read_exact_at(cursor.db.core, position, index_block_bytes[:byte_len]) or_return
	for j in 0 ..< count {
		level.block[j] = slot_from_slice(index_block_bytes[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH]) or_return
	}
	return nil
}

@(private)
_init_iter_level :: proc(cursor: Read_Cursor, position: i64, level: ^Iter_Level) -> Error {
	return _fill_slot_block_from(cursor, position, 0, SLOT_COUNT, level)
}

@(private)
_init_iter_level_rev :: proc(cursor: Read_Cursor, position: i64, level: ^Iter_Level) -> Error {
	return _fill_slot_block_rev(cursor, position, SLOT_COUNT, level)
}

@(private)
_assign_btree_heights :: proc(it: ^Cursor_Iterator) {
	for d in 0 ..< it.stack_len {
		it.stack[d].shift = u8(it.stack_len - 1 - d)
	}
}

@(private)
_read_btree_iter_level :: proc(
	cursor: Read_Cursor,
	node_ptr: i64,
	allow_empty_leaf: bool,
	reverse: bool,
	level: ^Iter_Level,
) -> (subtree_count: i64, edge_count: i64, err: Error) {
	position, pos_ok := _checked_add_i64(node_ptr, BTREE_NODE_HEADER_SIZE)
	if !pos_ok {
		return 0, 0, Xitdb_Error.Unexpected_EOF
	}
	if cursor.slot_ptr.slot.tag == .Linked_Array_List {
		node := read_btree_node(cursor.db, node_ptr) or_return
		level.position = position
		level.count = u8(node.num)
		level.index = u8(node.num - 1) if (reverse && node.num > 0) else 0
		level.shift = 0
		switch node.kind {
		case .Leaf:
			if node.num == 0 && !allow_empty_leaf {
				return 0, 0, .Invalid_BTree_Node
			}
			level.kind = .BTree_Leaf
			copy(level.block[:node.num], node.values[:node.num])
			return i64(node.num), 0, nil
		case .Branch:
			level.kind = .BTree_Branch
			copy(level.block[:node.num], node.children[:node.num])
			edge := node.counts[node.num - 1] if reverse else node.counts[0]
			return btree_node_subtree_count(node), edge, nil
		}
		return 0, 0, .Unreachable
	}
	node := read_sorted_node(cursor.db, node_ptr) or_return
	level.position = position
	level.count = u8(node.num)
	level.index = u8(node.num - 1) if (reverse && node.num > 0) else 0
	level.shift = 0
	switch node.kind {
	case .Leaf:
		if node.num == 0 && !allow_empty_leaf {
			return 0, 0, .Invalid_BTree_Node
		}
		level.kind = .BTree_Leaf
		copy(level.block[:node.num], node.entries[:node.num])
		return i64(node.num), 0, nil
	case .Branch:
		level.kind = .BTree_Branch
		copy(level.block[:node.num], node.children[:node.num])
		edge := node.counts[node.num - 1] if reverse else node.counts[0]
		return sorted_node_subtree_count(node), edge, nil
	}
	return 0, 0, .Unreachable
}

@(private)
_init_btree_stack :: proc(res: ^Cursor_Iterator, cursor: Read_Cursor, header: BTree_Header, reverse: bool) -> Error {
	if header.size == 0 {
		return nil
	}
	is_sorted := cursor.slot_ptr.slot.tag != .Linked_Array_List
	node_ptr := header.root_ptr
	expected := header.size
	for {
		if res.stack_len >= ITERATOR_STACK_SIZE {
			return .Invalid_BTree_Node
		}
		level := &res.stack[res.stack_len]
		subtree_count, edge_count := _read_btree_iter_level(
			cursor,
			node_ptr,
			is_sorted && expected == 0,
			reverse,
			level,
		) or_return
		if subtree_count != expected {
			return .Invalid_BTree_Node
		}
		res.stack_len += 1
		if level.kind == .BTree_Leaf {
			_assign_btree_heights(res)
			return nil
		}
		expected = edge_count
		node_ptr = level.block[level.index].value
	}
}

@(private)
_init_array_list_stack :: proc(
	res: ^Cursor_Iterator,
	cursor: Read_Cursor,
	header: Array_List_Header,
	start_idx: i64,
	reverse: bool,
) -> Error {
	shift := radix_shift(header.size - 1)
	pos := header.ptr
	sh := shift
	for {
		if res.stack_len >= ITERATOR_STACK_SIZE {
			return .Max_Shift_Exceeded
		}
		i := int((start_idx >> (u64(sh) * BIT_COUNT)) & i64(MASK))
		level := &res.stack[res.stack_len]
		if reverse {
			_fill_slot_block_rev(cursor, pos, i + 1, level) or_return
		} else {
			_fill_slot_block_from(cursor, pos, i, SLOT_COUNT, level) or_return
		}
		level.shift = sh
		level.kind = .Array_Leaf if sh == 0 else .Array_Branch
		res.stack_len += 1
		if sh == 0 {
			if level.block[i].tag == .Index || slot_empty(level.block[i]) {
				return .Unexpected_Tag
			}
			return nil
		}
		if level.block[i].tag != .Index {
			return .Unexpected_Tag
		}
		pos = level.block[i].value
		sh -= 1
	}
}

@(private)
_init_counted_hash_iter :: proc(res: ^Cursor_Iterator, cursor: Read_Cursor, reverse: bool) -> Error {
	pos := cursor.slot_ptr.slot.value
	if pos < 0 {
		return Xitdb_Error.Expected_Unsigned_Long
	}
	block_pos, ok1 := _checked_add_i64(pos, 8)
	if !ok1 {
		return Xitdb_Error.Unexpected_EOF
	}
	if _, ok2 := _checked_add_i64(block_pos, INDEX_BLOCK_SIZE); !ok2 {
		return Xitdb_Error.Unexpected_EOF
	}
	raw_buf: [8 + INDEX_BLOCK_SIZE]u8 = ---
	raw := raw_buf[:]
	if mem_slice, in_mem, slice_err := core_slice_at(cursor.db.core, pos, 8 + INDEX_BLOCK_SIZE); in_mem {
		if slice_err != nil {
			return slice_err
		}
		raw = mem_slice
	} else {
		core_read_exact_at(cursor.db.core, pos, raw) or_return
	}
	raw_total := endian.unchecked_get_u64be(raw[:8])
	if raw_total > u64(max(i64)) {
		return .Invalid_Database
	}
	total := i64(raw_total)
	res.size = total
	res.index = total if reverse else 0
	if total > 0 {
		level := &res.stack[0]
		_decode_slot_block_raw(raw[8 : 8 + INDEX_BLOCK_SIZE], &level.block) or_return
		level.position = block_pos
		level.index = (SLOT_COUNT - 1) if reverse else 0
		level.count = SLOT_COUNT
		level.shift = 0
		level.kind = .Any
		res.stack_len = 1
	}
	return nil
}

@(private)
_reset_cursor_iterator :: proc(res: ^Cursor_Iterator) {
	assert(res != nil)
	res.cursor = {}
	res.size = 0
	res.index = 0
	res.stack_len = 0
}

@(require_results)
cursor_iterator_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)

	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
	case .Array_List:
		res.cursor = cursor
		position := cursor.slot_ptr.slot.value
		hb: [ARRAY_LIST_HEADER_LENGTH]u8 = ---
		core_read_exact_at(cursor.db.core, position, hb[:]) or_return
		header := array_list_header_from_bytes(hb) or_return
		res.size = header.size
		res.index = 0
		if header.size > 0 {
			_init_array_list_stack(res, cursor, header, 0, false) or_return
		}
	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
		res.cursor = cursor
		position := cursor.slot_ptr.slot.value
		hb: [BTREE_HEADER_LENGTH]u8 = ---
		core_read_exact_at(cursor.db.core, position, hb[:]) or_return
		header := btree_header_from_bytes(hb) or_return
		res.size = header.size
		res.index = 0
		_init_btree_stack(res, cursor, header, false) or_return
	case .Hash_Map, .Hash_Set:
		res.cursor = cursor
		_init_iter_level(cursor, cursor.slot_ptr.slot.value, &res.stack[0]) or_return
		res.stack_len = 1
	case .Counted_Hash_Map, .Counted_Hash_Set:
		res.cursor = cursor
		_init_counted_hash_iter(res, cursor, false) or_return
	case:
		return .Unexpected_Tag
	}
	return nil
}

cursor_iterator :: proc(unresolved_cursor: Read_Cursor) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_init(&res, unresolved_cursor)
	return
}

@(require_results)
cursor_iterator_reverse_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)

	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
	case .Array_List:
		res.cursor = cursor
		position := cursor.slot_ptr.slot.value
		hb: [ARRAY_LIST_HEADER_LENGTH]u8 = ---
		core_read_exact_at(cursor.db.core, position, hb[:]) or_return
		header := array_list_header_from_bytes(hb) or_return
		res.size = header.size
		res.index = header.size
		if header.size > 0 {
			_init_array_list_stack(res, cursor, header, header.size - 1, true) or_return
		}
	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
		res.cursor = cursor
		position := cursor.slot_ptr.slot.value
		hb: [BTREE_HEADER_LENGTH]u8 = ---
		core_read_exact_at(cursor.db.core, position, hb[:]) or_return
		header := btree_header_from_bytes(hb) or_return
		res.size = header.size
		res.index = header.size
		_init_btree_stack(res, cursor, header, true) or_return
	case .Hash_Map, .Hash_Set:
		res.cursor = cursor
		_init_iter_level_rev(cursor, cursor.slot_ptr.slot.value, &res.stack[0]) or_return
		res.stack_len = 1
	case .Counted_Hash_Map, .Counted_Hash_Set:
		res.cursor = cursor
		_init_counted_hash_iter(res, cursor, true) or_return
	case:
		return .Unexpected_Tag
	}
	return nil
}

cursor_iterator_reverse :: proc(unresolved_cursor: Read_Cursor) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_reverse_init(&res, unresolved_cursor)
	return
}

@(private)
_resolve_start_index :: proc(index: i64, size: i64) -> (res: i64, err: bool) {
	resolved := index
	if index < 0 {
		resolved = index + size
	}
	if resolved < 0 || resolved >= size {
		return 0, false
	}
	return resolved, true
}

@(private)
_sorted_header :: proc(cursor: Read_Cursor) -> (res: BTree_Header, err: Error) {
	#partial switch cursor.slot_ptr.slot.tag {
	case .Sorted_Map, .Sorted_Set:
	case:
		return {}, .Unexpected_Tag
	}
	hb: [BTREE_HEADER_LENGTH]u8 = ---
	core_read_exact_at(cursor.db.core, cursor.slot_ptr.slot.value, hb[:]) or_return
	return btree_header_from_bytes(hb)
}

@(private)
_init_btree_stack_from_index :: proc(
	res: ^Cursor_Iterator,
	cursor: Read_Cursor,
	header: BTree_Header,
	idx: i64,
	is_sorted: bool,
	reverse: bool,
) -> Error {
	node_ptr := header.root_ptr
	expected := header.size
	rem := idx
	for {
		if res.stack_len >= ITERATOR_STACK_SIZE {
			return .Invalid_BTree_Node
		}
		position, pos_ok := _checked_add_i64(node_ptr, BTREE_NODE_HEADER_SIZE)
		if !pos_ok {
			return Xitdb_Error.Unexpected_EOF
		}
		level := &res.stack[res.stack_len]
		if is_sorted {
			node := read_sorted_node(cursor.db, node_ptr) or_return
			switch node.kind {
			case .Leaf:
				if i64(node.num) != expected || rem < 0 || rem >= i64(node.num) {
					return .Invalid_BTree_Node
				}
				r := int(rem)
				level.position = position
				level.kind = .BTree_Leaf
				level.shift = 0
				if reverse {
					copy(level.block[: r + 1], node.entries[: r + 1])
					level.index = u8(r)
					level.count = u8(r + 1)
				} else {
					copy(level.block[r:node.num], node.entries[r:node.num])
					level.index = u8(r)
					level.count = u8(node.num)
				}
				res.stack_len += 1
				_assign_btree_heights(res)
				return nil
			case .Branch:
				if sorted_node_subtree_count(node) != expected {
					return .Invalid_BTree_Node
				}
				chosen := -1
				for j in 0 ..< node.num {
					if rem < node.counts[j] {
						chosen = j
						break
					}
					rem -= node.counts[j]
				}
				if chosen < 0 {
					return .Invalid_BTree_Node
				}
				level.position = position
				level.kind = .BTree_Branch
				level.shift = 0
				if reverse {
					copy(level.block[: chosen + 1], node.children[: chosen + 1])
					level.index = u8(chosen)
					level.count = u8(chosen + 1)
				} else {
					copy(level.block[chosen:node.num], node.children[chosen:node.num])
					level.index = u8(chosen)
					level.count = u8(node.num)
				}
				res.stack_len += 1
				expected = node.counts[chosen]
				node_ptr = node.children[chosen].value
			}
		} else {
			node := read_btree_node(cursor.db, node_ptr) or_return
			switch node.kind {
			case .Leaf:
				if i64(node.num) != expected || rem < 0 || rem >= i64(node.num) {
					return .Invalid_BTree_Node
				}
				r := int(rem)
				level.position = position
				level.kind = .BTree_Leaf
				level.shift = 0
				if reverse {
					copy(level.block[: r + 1], node.values[: r + 1])
					level.index = u8(r)
					level.count = u8(r + 1)
				} else {
					copy(level.block[r:node.num], node.values[r:node.num])
					level.index = u8(r)
					level.count = u8(node.num)
				}
				res.stack_len += 1
				_assign_btree_heights(res)
				return nil
			case .Branch:
				if btree_node_subtree_count(node) != expected {
					return .Invalid_BTree_Node
				}
				chosen := -1
				for j in 0 ..< node.num {
					if rem < node.counts[j] {
						chosen = j
						break
					}
					rem -= node.counts[j]
				}
				if chosen < 0 {
					return .Invalid_BTree_Node
				}
				level.position = position
				level.kind = .BTree_Branch
				level.shift = 0
				if reverse {
					copy(level.block[: chosen + 1], node.children[: chosen + 1])
					level.index = u8(chosen)
					level.count = u8(chosen + 1)
				} else {
					copy(level.block[chosen:node.num], node.children[chosen:node.num])
					level.index = u8(chosen)
					level.count = u8(node.num)
				}
				res.stack_len += 1
				expected = node.counts[chosen]
				node_ptr = node.children[chosen].value
			}
		}
	}
}

@(require_results)
cursor_iterator_sorted_from_index_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)
	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
		return nil
	case .Sorted_Map, .Sorted_Set:
		res.cursor = cursor
	case:
		return .Unexpected_Tag
	}
	header := _sorted_header(cursor) or_return
	total := header.size
	idx, ok := _resolve_start_index(start_index, total)
	if !ok {
		res.size = total
		res.index = total
		return nil
	}
	_init_btree_stack_from_index(res, cursor, header, idx, true, false) or_return
	res.size = total
	res.index = idx
	return nil
}

cursor_iterator_sorted_from_index :: proc(unresolved_cursor: Read_Cursor, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_sorted_from_index_init(&res, unresolved_cursor, start_index)
	return
}

@(require_results)
cursor_iterator_sorted_from_key_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_key: []u8) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)
	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
		return nil
	case .Sorted_Map, .Sorted_Set:
		res.cursor = cursor
	case:
		return .Unexpected_Tag
	}
	header := _sorted_header(cursor) or_return
	total := header.size
	if total == 0 {
		res.size = 0
		res.index = 0
		return nil
	}
	node_ptr := header.root_ptr
	expected := total
	before: i64 = 0
	for {
		if res.stack_len >= ITERATOR_STACK_SIZE {
			return .Invalid_BTree_Node
		}
		position, pos_ok := _checked_add_i64(node_ptr, BTREE_NODE_HEADER_SIZE)
		if !pos_ok {
			return Xitdb_Error.Unexpected_EOF
		}
		node := read_sorted_node(cursor.db, node_ptr) or_return
		level := &res.stack[res.stack_len]
		switch node.kind {
		case .Leaf:
			if i64(node.num) != expected {
				return .Invalid_BTree_Node
			}
			lo, _ := sorted_leaf_search(cursor.db, &node, start_key) or_return
			next_before, b_ok := _checked_add_i64(before, i64(lo))
			if !b_ok || next_before > total {
				return .Invalid_BTree_Node
			}
			before = next_before
			copy(level.block[:node.num], node.entries[:node.num])
			level.position = position
			level.index = u8(lo)
			level.count = u8(node.num)
			level.shift = 0
			level.kind = .BTree_Leaf
			res.stack_len += 1
			_assign_btree_heights(res)
			res.size = total
			res.index = before
			return nil
		case .Branch:
			if sorted_node_subtree_count(node) != expected {
				return .Invalid_BTree_Node
			}
			i := sorted_branch_search(cursor.db, &node, start_key) or_return
			for k in 0 ..< i {
				b_ok: bool
				before, b_ok = _checked_add_i64(before, node.counts[k])
				if !b_ok {
					return .Invalid_BTree_Node
				}
			}
			copy(level.block[:node.num], node.children[:node.num])
			level.position = position
			level.index = u8(i)
			level.count = u8(node.num)
			level.shift = 0
			level.kind = .BTree_Branch
			res.stack_len += 1
			expected = node.counts[i]
			node_ptr = node.children[i].value
		}
	}
}

cursor_iterator_sorted_from_key :: proc(unresolved_cursor: Read_Cursor, start_key: []u8) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_sorted_from_key_init(&res, unresolved_cursor, start_key)
	return
}

@(require_results)
cursor_iterator_array_list_from_index_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)
	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
		return nil
	case .Array_List:
		res.cursor = cursor
	case:
		return .Unexpected_Tag
	}
	hb: [ARRAY_LIST_HEADER_LENGTH]u8 = ---
	core_read_exact_at(cursor.db.core, cursor.slot_ptr.slot.value, hb[:]) or_return
	header := array_list_header_from_bytes(hb) or_return
	idx, ok := _resolve_start_index(start_index, header.size)
	if !ok {
		res.size = header.size
		res.index = header.size
		return nil
	}
	_init_array_list_stack(res, cursor, header, idx, false) or_return
	res.size = header.size
	res.index = idx
	return nil
}

cursor_iterator_array_list_from_index :: proc(unresolved_cursor: Read_Cursor, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_array_list_from_index_init(&res, unresolved_cursor, start_index)
	return
}

@(require_results)
cursor_iterator_linked_array_list_from_index_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)
	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
		return nil
	case .Linked_Array_List:
		res.cursor = cursor
	case:
		return .Unexpected_Tag
	}
	hb: [BTREE_HEADER_LENGTH]u8 = ---
	core_read_exact_at(cursor.db.core, cursor.slot_ptr.slot.value, hb[:]) or_return
	header := btree_header_from_bytes(hb) or_return
	idx, ok := _resolve_start_index(start_index, header.size)
	if !ok {
		res.size = header.size
		res.index = header.size
		return nil
	}
	_init_btree_stack_from_index(res, cursor, header, idx, false, false) or_return
	res.size = header.size
	res.index = idx
	return nil
}

cursor_iterator_linked_array_list_from_index :: proc(unresolved_cursor: Read_Cursor, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_linked_array_list_from_index_init(&res, unresolved_cursor, start_index)
	return
}

@(require_results)
cursor_iterator_sorted_reverse_from_index_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)
	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
		return nil
	case .Sorted_Map, .Sorted_Set:
		res.cursor = cursor
	case:
		return .Unexpected_Tag
	}
	header := _sorted_header(cursor) or_return
	total := header.size
	idx, ok := _resolve_start_index(start_index, total)
	if !ok {
		res.size = total
		res.index = 0
		return nil
	}
	_init_btree_stack_from_index(res, cursor, header, idx, true, true) or_return
	res.size = total
	res.index = idx + 1
	return nil
}

cursor_iterator_sorted_reverse_from_index :: proc(unresolved_cursor: Read_Cursor, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_sorted_reverse_from_index_init(&res, unresolved_cursor, start_index)
	return
}

@(require_results)
cursor_iterator_sorted_reverse_from_key_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, upper_key: []u8, inclusive: bool = true) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)
	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
		return nil
	case .Sorted_Map, .Sorted_Set:
		res.cursor = cursor
	case:
		return .Unexpected_Tag
	}
	header := _sorted_header(cursor) or_return
	total := header.size
	if total == 0 {
		res.size = 0
		res.index = 0
		return nil
	}
	node_ptr := header.root_ptr
	expected := total
	before: i64 = 0
	for {
		if res.stack_len >= ITERATOR_STACK_SIZE {
			return .Invalid_BTree_Node
		}
		position, pos_ok := _checked_add_i64(node_ptr, BTREE_NODE_HEADER_SIZE)
		if !pos_ok {
			return Xitdb_Error.Unexpected_EOF
		}
		node := read_sorted_node(cursor.db, node_ptr) or_return
		level := &res.stack[res.stack_len]
		switch node.kind {
		case .Leaf:
			if i64(node.num) != expected {
				return .Invalid_BTree_Node
			}
			lo, found := sorted_leaf_search(cursor.db, &node, upper_key) or_return
			leaf_count := (lo + 1) if (found && inclusive) else lo
			next_before, b_ok := _checked_add_i64(before, i64(leaf_count))
			if !b_ok || next_before > total {
				return .Invalid_BTree_Node
			}
			before = next_before
			if before == 0 {
				res.stack_len = 0
				res.size = total
				res.index = 0
				return nil
			}
			if leaf_count > 0 {
				copy(level.block[:leaf_count], node.entries[:leaf_count])
			}
			level.position = position
			level.index = u8(leaf_count - 1) if leaf_count > 0 else 0
			level.count = u8(leaf_count)
			level.shift = 0
			level.kind = .BTree_Leaf
			res.stack_len += 1
			_assign_btree_heights(res)
			res.size = total
			res.index = before
			return nil
		case .Branch:
			if sorted_node_subtree_count(node) != expected {
				return .Invalid_BTree_Node
			}
			lo := 1
			hi := node.num
			for lo < hi {
				mid := int(uint(lo + hi) >> 1)
				c := compare_key(cursor.db, node.separators[mid], upper_key) or_return
				if (c <= 0 if inclusive else c < 0) {
					lo = mid + 1
				} else {
					hi = mid
				}
			}
			i := lo - 1
			for k in 0 ..< i {
				b_ok: bool
				before, b_ok = _checked_add_i64(before, node.counts[k])
				if !b_ok {
					return .Invalid_BTree_Node
				}
			}
			copy(level.block[: i + 1], node.children[: i + 1])
			level.position = position
			level.index = u8(i)
			level.count = u8(i + 1)
			level.shift = 0
			level.kind = .BTree_Branch
			res.stack_len += 1
			expected = node.counts[i]
			node_ptr = node.children[i].value
		}
	}
}

cursor_iterator_sorted_reverse_from_key :: proc(unresolved_cursor: Read_Cursor, upper_key: []u8, inclusive: bool = true) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_sorted_reverse_from_key_init(&res, unresolved_cursor, upper_key, inclusive)
	return
}

@(require_results)
cursor_iterator_array_list_reverse_from_index_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)
	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
		return nil
	case .Array_List:
		res.cursor = cursor
	case:
		return .Unexpected_Tag
	}
	hb: [ARRAY_LIST_HEADER_LENGTH]u8 = ---
	core_read_exact_at(cursor.db.core, cursor.slot_ptr.slot.value, hb[:]) or_return
	header := array_list_header_from_bytes(hb) or_return
	idx, ok := _resolve_start_index(start_index, header.size)
	if !ok {
		res.size = header.size
		res.index = 0
		return nil
	}
	_init_array_list_stack(res, cursor, header, idx, true) or_return
	res.size = header.size
	res.index = idx + 1
	return nil
}

cursor_iterator_array_list_reverse_from_index :: proc(unresolved_cursor: Read_Cursor, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_array_list_reverse_from_index_init(&res, unresolved_cursor, start_index)
	return
}

@(require_results)
cursor_iterator_linked_array_list_reverse_from_index_init :: proc(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> (err: Error) {
	assert(res != nil)
	defer if err != nil {
		mem.zero_item(res)
	}
	cursor := cursor_resolved_cursor(unresolved_cursor) or_return
	_reset_cursor_iterator(res)
	#partial switch cursor.slot_ptr.slot.tag {
	case .None:
		res.cursor = cursor
		return nil
	case .Linked_Array_List:
		res.cursor = cursor
	case:
		return .Unexpected_Tag
	}
	hb: [BTREE_HEADER_LENGTH]u8 = ---
	core_read_exact_at(cursor.db.core, cursor.slot_ptr.slot.value, hb[:]) or_return
	header := btree_header_from_bytes(hb) or_return
	idx, ok := _resolve_start_index(start_index, header.size)
	if !ok {
		res.size = header.size
		res.index = 0
		return nil
	}
	_init_btree_stack_from_index(res, cursor, header, idx, false, true) or_return
	res.size = header.size
	res.index = idx + 1
	return nil
}

cursor_iterator_linked_array_list_reverse_from_index :: proc(unresolved_cursor: Read_Cursor, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
	err = cursor_iterator_linked_array_list_reverse_from_index_init(&res, unresolved_cursor, start_index)
	return
}

@(private)
_iterator_step_internal :: proc(it: ^Cursor_Iterator, $REVERSE: bool) -> (res: Maybe(Read_Cursor), err: Error) {
	for it.stack_len > 0 {
		level := &it.stack[it.stack_len - 1]
		if level.index >= level.count {
			it.stack_len -= 1
			if it.stack_len > 0 {
				when REVERSE {
					it.stack[it.stack_len - 1].index -= 1
				} else {
					it.stack[it.stack_len - 1].index += 1
				}
			}
			continue
		}
		next_slot := level.block[level.index]
		switch level.kind {
		case .BTree_Branch:
			if next_slot.tag != .Index || level.shift == 0 || it.stack_len >= ITERATOR_STACK_SIZE {
				return nil, .Invalid_BTree_Node
			}
			next_shift := level.shift - 1
			expected_kind: Iter_Level_Kind = .BTree_Leaf if next_shift == 0 else .BTree_Branch
			child_level := &it.stack[it.stack_len]
			_read_btree_iter_level(
				it.cursor,
				next_slot.value,
				it.cursor.slot_ptr.slot.tag != .Linked_Array_List,
				REVERSE,
				child_level,
			) or_return
			if child_level.kind != expected_kind {
				return nil, .Invalid_BTree_Node
			}
			child_level.shift = next_shift
			it.stack_len += 1
			continue
		case .Array_Branch:
			if next_slot.tag != .Index || level.shift == 0 || it.stack_len >= ITERATOR_STACK_SIZE {
				return nil, .Unexpected_Tag
			}
			next_shift := level.shift - 1
			child_level := &it.stack[it.stack_len]
			when REVERSE {
				_init_iter_level_rev(it.cursor, next_slot.value, child_level) or_return
			} else {
				_init_iter_level(it.cursor, next_slot.value, child_level) or_return
			}
			child_level.shift = next_shift
			child_level.kind = .Array_Leaf if next_shift == 0 else .Array_Branch
			it.stack_len += 1
			continue
		case .BTree_Leaf:
			if next_slot.tag == .Index || slot_empty(next_slot) {
				return nil, .Invalid_BTree_Node
			}
		case .Array_Leaf:
			if next_slot.tag == .Index || slot_empty(next_slot) {
				return nil, .Unexpected_Tag
			}
		case .Any:
			if next_slot.tag == .Index {
				max_hash_depth := min((int(it.cursor.db.header.hash_size) * 8) / BIT_COUNT, ITERATOR_STACK_SIZE)
				if it.stack_len >= max_hash_depth {
					return nil, .Key_Offset_Exceeded
				}
				child_level := &it.stack[it.stack_len]
				when REVERSE {
					_init_iter_level_rev(it.cursor, next_slot.value, child_level) or_return
				} else {
					_init_iter_level(it.cursor, next_slot.value, child_level) or_return
				}
				it.stack_len += 1
				continue
			}
		}
		slot_idx := level.index
		when REVERSE {
			level.index -= 1
		} else {
			level.index += 1
		}
		if !slot_empty(next_slot) {
			position := level.position + i64(slot_idx) * SLOT_LENGTH
			return Read_Cursor{
				slot_ptr  = Slot_Pointer{position = position, slot = next_slot},
				db        = it.cursor.db,
				frozen_at = it.cursor.frozen_at,
			}, nil
		}
	}
	return nil, nil
}

cursor_iterator_next :: proc(it: ^Cursor_Iterator) -> (res: Maybe(Read_Cursor), err: Error) {
	#partial switch it.cursor.slot_ptr.slot.tag {
	case .None:
		return nil, nil
	case .Array_List:
		if it.index == it.size {
			return nil, nil
		}
		item := _iterator_step_internal(it, false) or_return
		if item == nil {
			return nil, .Unexpected_Tag
		}
		it.index += 1
		return item, nil
	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
		if it.index == it.size {
			return nil, nil
		}
		item := _iterator_step_internal(it, false) or_return
		if item == nil {
			return nil, .Invalid_BTree_Node
		}
		it.index += 1
		return item, nil
	case .Counted_Hash_Map, .Counted_Hash_Set:
		if it.index == it.size {
			return nil, nil
		}
		item := _iterator_step_internal(it, false) or_return
		if item == nil {
			return nil, .Invalid_Database
		}
		it.index += 1
		return item, nil
	case .Hash_Map, .Hash_Set:
		return _iterator_step_internal(it, false)
	case:
		return nil, .Unexpected_Tag
	}
}

cursor_iterator_prev :: proc(it: ^Cursor_Iterator) -> (res: Maybe(Read_Cursor), err: Error) {
	#partial switch it.cursor.slot_ptr.slot.tag {
	case .None:
		return nil, nil
	case .Array_List:
		if it.index == 0 {
			return nil, nil
		}
		item := _iterator_step_internal(it, true) or_return
		if item == nil {
			return nil, .Unexpected_Tag
		}
		it.index -= 1
		return item, nil
	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
		if it.index == 0 {
			return nil, nil
		}
		item := _iterator_step_internal(it, true) or_return
		if item == nil {
			return nil, .Invalid_BTree_Node
		}
		it.index -= 1
		return item, nil
	case .Counted_Hash_Map, .Counted_Hash_Set:
		if it.index == 0 {
			return nil, nil
		}
		item := _iterator_step_internal(it, true) or_return
		if item == nil {
			return nil, .Invalid_Database
		}
		it.index -= 1
		return item, nil
	case .Hash_Map, .Hash_Set:
		return _iterator_step_internal(it, true)
	case:
		return nil, .Unexpected_Tag
	}
}
