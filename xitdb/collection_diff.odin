package xitdb

import "base:runtime"
import "core:bytes"

// =============================================================================
// Structural byte-key collection diff
// =============================================================================
//
// `diff_collection` compares two versions of the same `Hash_Map` / `Hash_Set` / `Counted_*` or
// `Sorted_Map` / `Sorted_Set` (typically the same bucket at two Moments of one database) and reports
// every added, removed, and changed key with its raw key bytes.
//
// Unlike `diff_cursors`, keys are returned as raw bytes (binary keys are safe), the walk never decodes
// unchanged entries, and identical subtrees are skipped by pointer:
// - HAMT maps descend only index blocks whose slots differ: O(changes x depth).
// - B+Tree sorted maps run an ordered merge of both trees that skips any child subtree shared by both
//   versions: O(changes x log N) when structure is shared (the common case for persistent updates),
//   degrading gracefully towards O(N) only where node boundaries were re-split.
// Both cursors must belong to the same database (Slot equality is only meaningful within one file).

Collection_Change_Op :: enum u8 {
	Added,
	Removed,
	Changed,
}

Collection_Change :: struct {
	op:        Collection_Change_Op,
	key:       []u8,        // raw key bytes (allocated with the diff allocator)
	old_value: Read_Cursor, // valid for `.Removed` / `.Changed` (empty slot for set members)
	new_value: Read_Cursor, // valid for `.Added` / `.Changed`
}

@(private = "file")
Diff_Ctx :: struct {
	db_a:      ^Database,
	db_b:      ^Database,
	out:       ^[dynamic]Collection_Change,
	allocator: runtime.Allocator,
}

@(private = "file")
Map_Entry :: struct {
	hash:      []u8,
	key_slot:  Slot,
	value:     Slot_Pointer,
}

diff_collection :: proc(cur_a, cur_b: Read_Cursor, allocator := context.temp_allocator) -> (res: []Collection_Change, err: Error) {
	a := cursor_resolved_cursor(cur_a) or_return
	b := cursor_resolved_cursor(cur_b) or_return
	out := make([dynamic]Collection_Change, 0, 8, allocator)
	ctx := Diff_Ctx{db_a = a.db, db_b = b.db, out = &out, allocator = allocator}
	if a.slot_ptr.slot == b.slot_ptr.slot {
		return out[:], nil
	}

	family :: proc(tag: Tag) -> int {
		#partial switch tag {
		case .None:
			return 0
		case .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set:
			return 1
		case .Sorted_Map, .Sorted_Set:
			return 2
		}
		return -1
	}
	fa, fb := family(a.slot_ptr.slot.tag), family(b.slot_ptr.slot.tag)
	if fa < 0 || fb < 0 || (fa != 0 && fb != 0 && fa != fb) {
		return nil, .Unexpected_Tag
	}
	switch max(fa, fb) {
	case 1:
		_diff_hash_maps(&ctx, a, b) or_return
	case 2:
		_diff_sorted_maps(&ctx, a, b) or_return
	}
	return out[:], nil
}

// -----------------------------------------------------------------------------
// HAMT
// -----------------------------------------------------------------------------

@(private = "file")
_hash_index_pos :: proc(c: Read_Cursor) -> (pos: i64, ok: bool) {
	#partial switch c.slot_ptr.slot.tag {
	case .Hash_Map, .Hash_Set:
		return c.slot_ptr.slot.value, true
	case .Counted_Hash_Map, .Counted_Hash_Set:
		return c.slot_ptr.slot.value + 8, true
	}
	return 0, false
}

@(private = "file")
_diff_hash_maps :: proc(ctx: ^Diff_Ctx, a, b: Read_Cursor) -> Error {
	pos_a, has_a := _hash_index_pos(a)
	pos_b, has_b := _hash_index_pos(b)
	if has_a && has_b {
		return _diff_index_blocks(ctx, pos_a, pos_b)
	}
	// One side is empty: everything on the other side was added / removed.
	entries := make([dynamic]Map_Entry, 0, 16, context.temp_allocator)
	if has_a {
		_collect_index_block(ctx.db_a, pos_a, &entries) or_return
		for e in entries {
			_emit_map(ctx, .Removed, ctx.db_a, e, {}) or_return
		}
	} else if has_b {
		_collect_index_block(ctx.db_b, pos_b, &entries) or_return
		for e in entries {
			_emit_map(ctx, .Added, ctx.db_b, {}, e) or_return
		}
	}
	return nil
}

@(private = "file")
_diff_index_blocks :: proc(ctx: ^Diff_Ctx, pos_a, pos_b: i64) -> Error {
	if pos_a == pos_b && ctx.db_a == ctx.db_b {
		return nil
	}
	block_a, block_b: [INDEX_BLOCK_SIZE]u8 = ---, ---
	core_read_exact_at(ctx.db_a.core, pos_a, block_a[:]) or_return
	core_read_exact_at(ctx.db_b.core, pos_b, block_b[:]) or_return
	if bytes.equal(block_a[:], block_b[:]) {
		return nil
	}
	for i in 0 ..< SLOT_COUNT {
		sa := slot_from_slice(block_a[i * SLOT_LENGTH:(i + 1) * SLOT_LENGTH]) or_return
		sb := slot_from_slice(block_b[i * SLOT_LENGTH:(i + 1) * SLOT_LENGTH]) or_return
		if sa == sb {
			continue
		}
		if sa.tag == .Index && sb.tag == .Index {
			_diff_index_blocks(ctx, sa.value, sb.value) or_return
			continue
		}
		// Mixed / leaf-level difference: materialize both (small) subtrees and diff them by hash.
		ea := make([dynamic]Map_Entry, 0, 4, context.temp_allocator)
		eb := make([dynamic]Map_Entry, 0, 4, context.temp_allocator)
		_collect_slot(ctx.db_a, sa, pos_a + i64(i * SLOT_LENGTH), &ea) or_return
		_collect_slot(ctx.db_b, sb, pos_b + i64(i * SLOT_LENGTH), &eb) or_return
		_diff_entry_sets(ctx, ea[:], eb[:]) or_return
	}
	return nil
}

@(private = "file")
_collect_index_block :: proc(db: ^Database, pos: i64, out: ^[dynamic]Map_Entry) -> Error {
	block: [INDEX_BLOCK_SIZE]u8 = ---
	core_read_exact_at(db.core, pos, block[:]) or_return
	for i in 0 ..< SLOT_COUNT {
		s := slot_from_slice(block[i * SLOT_LENGTH:(i + 1) * SLOT_LENGTH]) or_return
		_collect_slot(db, s, pos + i64(i * SLOT_LENGTH), out) or_return
	}
	return nil
}

@(private = "file")
_collect_slot :: proc(db: ^Database, s: Slot, slot_pos: i64, out: ^[dynamic]Map_Entry) -> Error {
	#partial switch s.tag {
	case .None:
		return nil
	case .Index:
		return _collect_index_block(db, s.value, out)
	case .KV_Pair:
		hash_size := int(db.header.hash_size)
		hash := make([]u8, hash_size, context.temp_allocator)
		kv := kv_pair_read_buf_at(db.core, s.value, hash) or_return
		key_pos := s.value + i64(hash_size)
		append(out, Map_Entry{
			hash     = kv.hash,
			key_slot = kv.key_slot,
			value    = Slot_Pointer{position = key_pos + SLOT_LENGTH, slot = kv.value_slot},
		})
		return nil
	}
	return .Unexpected_Tag
}

@(private = "file")
_diff_entry_sets :: proc(ctx: ^Diff_Ctx, ea, eb: []Map_Entry) -> Error {
	for a in ea {
		found := false
		for b in eb {
			if bytes.equal(a.hash, b.hash) {
				found = true
				if a.value.slot != b.value.slot {
					_emit_map(ctx, .Changed, ctx.db_b, a, b) or_return
				}
				break
			}
		}
		if !found {
			_emit_map(ctx, .Removed, ctx.db_a, a, {}) or_return
		}
	}
	for b in eb {
		found := false
		for a in ea {
			if bytes.equal(a.hash, b.hash) {
				found = true
				break
			}
		}
		if !found {
			_emit_map(ctx, .Added, ctx.db_b, {}, b) or_return
		}
	}
	return nil
}

@(private = "file")
_read_key_bytes :: proc(db: ^Database, key_slot: Slot, allocator: runtime.Allocator) -> (res: []u8, err: Error) {
	kc := Read_Cursor{slot_ptr = Slot_Pointer{position = nil, slot = key_slot}, db = db}
	return cursor_read_bytes(kc, 0, allocator)
}

@(private = "file")
_emit_map :: proc(ctx: ^Diff_Ctx, op: Collection_Change_Op, key_db: ^Database, a, b: Map_Entry) -> Error {
	key_slot := b.key_slot if op == .Added || op == .Changed else a.key_slot
	key := _read_key_bytes(key_db, key_slot, ctx.allocator) or_return
	ch := Collection_Change{op = op, key = key}
	if op != .Added {
		ch.old_value = Read_Cursor{slot_ptr = a.value, db = ctx.db_a}
	}
	if op != .Removed {
		ch.new_value = Read_Cursor{slot_ptr = b.value, db = ctx.db_b}
	}
	append(ctx.out, ch)
	return nil
}

// -----------------------------------------------------------------------------
// B+Tree (Sorted_Map / Sorted_Set)
// -----------------------------------------------------------------------------

@(private = "file")
MAX_DIFF_TREE_DEPTH :: 32

@(private = "file")
Tree_Frame :: struct {
	node:   Sorted_Node,
	index:  int,
	height: int, // height of `node` (0 == leaf)
}

@(private = "file")
Tree_Walker :: struct {
	db:     ^Database,
	frames: [MAX_DIFF_TREE_DEPTH]Tree_Frame,
	depth:  int,
}

@(private = "file")
Tree_Front_Kind :: enum u8 {
	Done,
	Child,
	Entry,
}

@(private = "file")
Tree_Front :: struct {
	kind:   Tree_Front_Kind,
	slot:   Slot, // child pointer slot or leaf entry slot
	height: int,  // height of the child subtree (Child) / 0 (Entry)
}

@(private = "file")
_walker_init :: proc(w: ^Tree_Walker, c: Read_Cursor) -> Error {
	w.db = c.db
	w.depth = 0
	if c.slot_ptr.slot.tag == .None {
		return nil
	}
	header := _sorted_header(c) or_return
	if header.size == 0 {
		return nil
	}
	h := btree_height(c.db, header.root_ptr) or_return
	return _walker_push(w, header.root_ptr, h)
}

@(private = "file")
_walker_push :: proc(w: ^Tree_Walker, ptr: i64, height: int) -> Error {
	if w.depth >= MAX_DIFF_TREE_DEPTH {
		return .Invalid_BTree_Node
	}
	node := read_sorted_node(w.db, ptr) or_return
	w.frames[w.depth] = Tree_Frame{node = node, index = 0, height = height}
	w.depth += 1
	return nil
}

@(private = "file")
_walker_front :: proc(w: ^Tree_Walker) -> Tree_Front {
	for w.depth > 0 {
		f := &w.frames[w.depth - 1]
		if f.index >= f.node.num {
			w.depth -= 1
			if w.depth > 0 {
				w.frames[w.depth - 1].index += 1
			}
			continue
		}
		if f.node.kind == .Leaf {
			return Tree_Front{kind = .Entry, slot = f.node.entries[f.index], height = 0}
		}
		return Tree_Front{kind = .Child, slot = f.node.children[f.index], height = f.height - 1}
	}
	return Tree_Front{kind = .Done}
}

@(private = "file")
_walker_advance :: proc(w: ^Tree_Walker) {
	if w.depth > 0 {
		w.frames[w.depth - 1].index += 1
	}
}

@(private = "file")
_walker_descend :: proc(w: ^Tree_Walker, front: Tree_Front) -> Error {
	return _walker_push(w, front.slot.value, front.height)
}

@(private = "file")
Sorted_Entry_Info :: struct {
	key_slot: Slot,
	value:    Slot_Pointer,
}

@(private = "file")
_sorted_entry_info :: proc(db: ^Database, entry: Slot) -> (info: Sorted_Entry_Info, err: Error) {
	if is_key_only_entry(entry) {
		return Sorted_Entry_Info{key_slot = entry}, nil
	}
	key_pos := entry.value + database_kv_key_offset(db, entry.tag)
	b: [SLOT_LENGTH * 2]u8 = ---
	core_read_exact_at(db.core, key_pos, b[:]) or_return
	info.key_slot = slot_from_slice(b[0:SLOT_LENGTH]) or_return
	val := slot_from_slice(b[SLOT_LENGTH:]) or_return
	info.value = Slot_Pointer{position = key_pos + SLOT_LENGTH, slot = val}
	return info, nil
}

@(private = "file")
_diff_sorted_maps :: proc(ctx: ^Diff_Ctx, a, b: Read_Cursor) -> Error {
	wa, wb: Tree_Walker
	_walker_init(&wa, a) or_return
	_walker_init(&wb, b) or_return
	same_db := ctx.db_a == ctx.db_b

	for {
		fa := _walker_front(&wa)
		fb := _walker_front(&wb)
		if fa.kind == .Done && fb.kind == .Done {
			return nil
		}
		// Shared subtree at the same position in key order: skip it on both sides in O(1).
		if same_db && fa.kind == .Child && fb.kind == .Child && fa.slot == fb.slot {
			_walker_advance(&wa)
			_walker_advance(&wb)
			continue
		}
		// Descend until both fronts are leaf entries, taller subtrees first so that a subtree shared at
		// different depths (after a root split / merge) can still line up and be skipped.
		if fa.kind == .Child || fb.kind == .Child {
			ha := fa.height if fa.kind == .Child else -1
			hb := fb.height if fb.kind == .Child else -1
			if ha >= hb && fa.kind == .Child {
				_walker_descend(&wa, fa) or_return
			}
			if hb >= ha && fb.kind == .Child {
				_walker_descend(&wb, fb) or_return
			}
			continue
		}
		switch {
		case fa.kind == .Done:
			ib := _sorted_entry_info(ctx.db_b, fb.slot) or_return
			_emit_sorted(ctx, .Added, {}, ib) or_return
			_walker_advance(&wb)
		case fb.kind == .Done:
			ia := _sorted_entry_info(ctx.db_a, fa.slot) or_return
			_emit_sorted(ctx, .Removed, ia, {}) or_return
			_walker_advance(&wa)
		case:
			ia := _sorted_entry_info(ctx.db_a, fa.slot) or_return
			ib := _sorted_entry_info(ctx.db_b, fb.slot) or_return
			key_b := _read_key_bytes(ctx.db_b, ib.key_slot, context.temp_allocator) or_return
			cmp := compare_key(ctx.db_a, ia.key_slot, key_b) or_return
			if cmp < 0 {
				_emit_sorted(ctx, .Removed, ia, {}) or_return
				_walker_advance(&wa)
			} else if cmp > 0 {
				_emit_sorted(ctx, .Added, {}, ib) or_return
				_walker_advance(&wb)
			} else {
				if fa.slot != fb.slot && ia.value.slot != ib.value.slot {
					_emit_sorted(ctx, .Changed, ia, ib) or_return
				}
				_walker_advance(&wa)
				_walker_advance(&wb)
			}
		}
	}
}

@(private = "file")
_emit_sorted :: proc(ctx: ^Diff_Ctx, op: Collection_Change_Op, a, b: Sorted_Entry_Info) -> Error {
	key_db := ctx.db_b if op != .Removed else ctx.db_a
	key_slot := b.key_slot if op != .Removed else a.key_slot
	key := _read_key_bytes(key_db, key_slot, ctx.allocator) or_return
	ch := Collection_Change{op = op, key = key}
	if op != .Added {
		ch.old_value = Read_Cursor{slot_ptr = a.value, db = ctx.db_a}
	}
	if op != .Removed {
		ch.new_value = Read_Cursor{slot_ptr = b.value, db = ctx.db_b}
	}
	append(ctx.out, ch)
	return nil
}
