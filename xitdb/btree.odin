package xitdb

import "core:bytes"
import "core:encoding/endian"

// LinkedArrayList methods (backed by a count-augmented B-Tree)

read_btree_node :: proc(db: ^Database, ptr: i64) -> (res: BTree_Node, err: Error) {
	buf: [BTREE_BRANCH_BLOCK_SIZE]u8 = ---
	block := core_read_block_at(db.core, ptr, buf[:]) or_return
	if len(block) < BTREE_LEAF_BLOCK_SIZE {
		return {}, Xitdb_Error.Unexpected_EOF
	}
	kind_int := block[0]
	if kind_int > u8(BTree_Node_Kind.Branch) {
		return {}, .Invalid_BTree_Node_Kind
	}
	kind := BTree_Node_Kind(kind_int)
	num := int(block[1])
	if num > BTREE_SLOT_COUNT || (kind == .Branch && num == 0) {
		return {}, .Invalid_BTree_Node
	}
	body := block[BTREE_NODE_HEADER_SIZE:]
	node := BTree_Node{kind = kind, num = num}
	switch kind {
	case .Leaf:
		for i in 0 ..< BTREE_SLOT_COUNT {
			s := slot_from_slice(body[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH]) or_return
			if i < num {
				if s.tag == .Index || slot_empty(s) {
					return {}, .Invalid_BTree_Node
				}
				node.values[i] = s
			} else if !slot_empty(s) {
				return {}, .Invalid_BTree_Node
			}
		}
	case .Branch:
		if len(block) < BTREE_BRANCH_BLOCK_SIZE {
			return {}, Xitdb_Error.Unexpected_EOF
		}
		for i in 0 ..< BTREE_SLOT_COUNT {
			s := slot_from_slice(body[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH]) or_return
			if i < num {
				if s.tag != .Index {
					return {}, .Invalid_BTree_Node
				}
				node.children[i] = s
			} else if !slot_empty(s) {
				return {}, .Invalid_BTree_Node
			}
		}
		counts_offset := SLOT_LENGTH * BTREE_SLOT_COUNT
		total: i64 = 0
		for i in 0 ..< BTREE_SLOT_COUNT {
			raw := endian.unchecked_get_u64be(body[counts_offset + i * 8 : counts_offset + (i + 1) * 8])
			if i < num {
				if raw == 0 || raw > u64(max(i64)) {
					return {}, .Invalid_BTree_Node
				}
				ok: bool
				total, ok = _checked_add_i64(total, i64(raw))
				if !ok {
					return {}, .Invalid_BTree_Node
				}
				node.counts[i] = i64(raw)
			} else if raw != 0 {
				return {}, .Invalid_BTree_Node
			}
		}
	}
	return node, nil
}

write_btree_node_at :: proc(db: ^Database, node: BTree_Node, ptr: i64) -> Error {
	core_seek_to(db.core, ptr) or_return
	switch node.kind {
	case .Leaf:
		buf: [BTREE_LEAF_BLOCK_SIZE]u8
		buf[0] = u8(node.kind)
		buf[1] = u8(node.num)
		off := BTREE_NODE_HEADER_SIZE
		for i in 0 ..< node.num {
			sb := slot_to_bytes(node.values[i])
			copy(buf[off:], sb[:])
			off += SLOT_LENGTH
		}
		return core_write_all(db.core, buf[:])
	case .Branch:
		buf: [BTREE_BRANCH_BLOCK_SIZE]u8
		buf[0] = u8(node.kind)
		buf[1] = u8(node.num)
		off := BTREE_NODE_HEADER_SIZE
		for i in 0 ..< node.num {
			sb := slot_to_bytes(node.children[i])
			copy(buf[off:], sb[:])
			off += SLOT_LENGTH
		}
		counts_off := BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
		for i in 0 ..< node.num {
			endian.unchecked_put_u64be(buf[counts_off : counts_off + 8], u64(node.counts[i]))
			counts_off += 8
		}
		return core_write_all(db.core, buf[:])
	}
	return .Unreachable
}

write_btree_node :: proc(db: ^Database, node: BTree_Node) -> (res: i64, err: Error) {
	ptr := core_length(db.core) or_return
	write_btree_node_at(db, node, ptr) or_return
	return ptr, nil
}

btree_reusable :: proc(db: ^Database, ptr, frozen_at: i64) -> bool {
	old, err := database_is_old(db, ptr, frozen_at)
	if err != nil {
		return false
	}
	return !old
}

btree_write_node :: proc(db: ^Database, node: BTree_Node, old_ptr, frozen_at: i64) -> (res: i64, err: Error) {
	if btree_reusable(db, old_ptr, frozen_at) {
		write_btree_node_at(db, node, old_ptr) or_return
		return old_ptr, nil
	}
	return write_btree_node(db, node)
}

btree_new_root :: proc(db: ^Database) -> (res: i64, err: Error) {
	return write_btree_node(db, BTree_Node{kind = .Leaf, num = 0})
}

descend_by_rank :: proc(db: ^Database, header: BTree_Header, rank: i64, $BRANCH_BLOCK_SIZE: int) -> (res: Slot_Pointer, err: Error) {
	is_sorted :: BRANCH_BLOCK_SIZE == SORTED_BRANCH_BLOCK_SIZE
	node_ptr := header.root_ptr
	expected := header.size
	rem := rank
	for depth := 0; ; depth += 1 {
		if depth >= MAX_BTREE_DEPTH {
			return {}, .Invalid_BTree_Node
		}
		when is_sorted {
			node := read_sorted_node(db, node_ptr) or_return
			switch node.kind {
			case .Leaf:
				if i64(node.num) != expected || rem < 0 || rem >= i64(node.num) {
					return {}, .Invalid_BTree_Node
				}
				pos_base, ok1 := _checked_add_i64(node_ptr, BTREE_NODE_HEADER_SIZE)
				slot_pos, ok2 := _checked_add_i64(pos_base, rem * SLOT_LENGTH)
				if !ok1 || !ok2 {
					return {}, .End_Of_Stream
				}
				return Slot_Pointer{position = slot_pos, slot = node.entries[int(rem)]}, nil
			case .Branch:
				if sorted_node_subtree_count(node) != expected {
					return {}, .Invalid_BTree_Node
				}
				chosen := -1
				for j in 0 ..< node.num {
					cnt := node.counts[j]
					if rem < cnt {
						chosen = j
						break
					}
					rem -= cnt
				}
				if chosen < 0 {
					return {}, .Invalid_BTree_Node
				}
				expected = node.counts[chosen]
				node_ptr = node.children[chosen].value
			}
		} else {
			node := read_btree_node(db, node_ptr) or_return
			switch node.kind {
			case .Leaf:
				if i64(node.num) != expected || rem < 0 || rem >= i64(node.num) {
					return {}, .Invalid_BTree_Node
				}
				pos_base, ok1 := _checked_add_i64(node_ptr, BTREE_NODE_HEADER_SIZE)
				slot_pos, ok2 := _checked_add_i64(pos_base, rem * SLOT_LENGTH)
				if !ok1 || !ok2 {
					return {}, .End_Of_Stream
				}
				return Slot_Pointer{position = slot_pos, slot = node.values[int(rem)]}, nil
			case .Branch:
				if btree_node_subtree_count(node) != expected {
					return {}, .Invalid_BTree_Node
				}
				chosen := -1
				for j in 0 ..< node.num {
					cnt := node.counts[j]
					if rem < cnt {
						chosen = j
						break
					}
					rem -= cnt
				}
				if chosen < 0 {
					return {}, .Invalid_BTree_Node
				}
				expected = node.counts[chosen]
				node_ptr = node.children[chosen].value
			}
		}
	}
}

@(private = "file")
_BTree_Write_Frame :: struct {
	node_ptr:  i64,
	child_ptr: i64,
	old_cnt:   i64,
	total_cnt: i64,
	child_idx: u8,
	num:       u8,
	reusable:  bool,
}

btree_insert :: proc(db: ^Database, node_ptr, rank, expected, frozen_at: i64, depth: int = 0) -> (res: BTree_Insert_Result, err: Error) {
	frames: [MAX_BTREE_DEPTH]_BTree_Write_Frame = ---
	frame_len := 0
	cur_ptr := node_ptr
	cur_rem := rank
	cur_exp := expected
	cur_depth := depth
	child: BTree_Insert_Result

	for {
		if cur_depth >= MAX_BTREE_DEPTH {
			return {}, .Invalid_BTree_Node
		}
		if btree_reusable(db, cur_ptr, frozen_at) {
			header_bytes: [BTREE_NODE_HEADER_SIZE]u8
			core_read_exact_at(db.core, cur_ptr, header_bytes[:]) or_return
			kind_int := header_bytes[0]
			if kind_int > u8(BTree_Node_Kind.Branch) {
				return {}, .Invalid_BTree_Node_Kind
			}
			num := int(header_bytes[1])
			if num > BTREE_SLOT_COUNT || (BTree_Node_Kind(kind_int) == .Branch && num == 0) {
				return {}, .Invalid_BTree_Node
			}
			if BTree_Node_Kind(kind_int) == .Leaf {
				r := int(cur_rem)
				if i64(num) != cur_exp || r < 0 || r > num {
					return {}, .Invalid_BTree_Node
				}
				if num < BTREE_SLOT_COUNT {
					total := num + 1
					val_pos := cur_ptr + BTREE_NODE_HEADER_SIZE + i64(r) * SLOT_LENGTH
					empty_slot_bytes := slot_to_bytes(Slot{value = 0, tag = .None, full = true})
					if r < num {
						tail_len := (num - r) * SLOT_LENGTH
						shift_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8
						copy(shift_buf[:SLOT_LENGTH], empty_slot_bytes[:])
						core_read_exact_at(db.core, val_pos, shift_buf[SLOT_LENGTH : SLOT_LENGTH + tail_len]) or_return
						core_seek_to(db.core, val_pos) or_return
						core_write_all(db.core, shift_buf[:SLOT_LENGTH + tail_len]) or_return
					} else {
						core_seek_to(db.core, val_pos) or_return
						core_write_all(db.core, empty_slot_bytes[:]) or_return
					}
					new_hdr := [BTREE_NODE_HEADER_SIZE]u8{kind_int, u8(total)}
					core_seek_to(db.core, cur_ptr) or_return
					core_write_all(db.core, new_hdr[:]) or_return
					child = BTree_Insert_Result{
						node_ptr       = cur_ptr,
						count          = i64(total),
						value_position = val_pos,
					}
					break
				}
			} else {
				counts_pos := cur_ptr + BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
				counts_buf: [8 * BTREE_SLOT_COUNT]u8
				core_read_exact_at(db.core, counts_pos, counts_buf[:num * 8]) or_return
				i := 0
				rem := cur_rem
				total_count: i64 = 0
				old_cnt_i: i64 = 0
				for k in 0 ..< num {
					raw := endian.unchecked_get_u64be(counts_buf[k * 8 : k * 8 + 8])
					if raw == 0 || raw > u64(max(i64)) {
						return {}, .Invalid_BTree_Node
					}
					cnt := i64(raw)
					ok: bool
					total_count, ok = _checked_add_i64(total_count, cnt)
					if !ok {
						return {}, .Invalid_BTree_Node
					}
					if k == i {
						old_cnt_i = cnt
						if i + 1 < num && rem > cnt {
							rem -= cnt
							i += 1
						}
					}
				}
				if total_count != cur_exp || rem > old_cnt_i {
					return {}, .Invalid_BTree_Node
				}
				child_slot_pos := cur_ptr + BTREE_NODE_HEADER_SIZE + i64(i) * SLOT_LENGTH
				child_slot := core_read_slot_at(db.core, child_slot_pos) or_return
				if child_slot.tag != .Index {
					return {}, .Invalid_BTree_Node
				}
				frames[frame_len] = _BTree_Write_Frame{
					node_ptr  = cur_ptr,
					child_ptr = child_slot.value,
					old_cnt   = old_cnt_i,
					total_cnt = total_count,
					child_idx = u8(i),
					num       = u8(num),
					reusable  = true,
				}
				frame_len += 1
				cur_ptr = child_slot.value
				cur_rem = rem
				cur_exp = old_cnt_i
				cur_depth += 1
				continue
			}
		}

		node := read_btree_node(db, cur_ptr) or_return
		switch node.kind {
		case .Leaf:
			r := int(cur_rem)
			if i64(node.num) != cur_exp || r < 0 || r > node.num {
				return {}, .Invalid_BTree_Node
			}
			vals: [BTREE_SLOT_COUNT + 1]Slot
			copy(vals[:r], node.values[:r])
			vals[r] = Slot{value = 0, tag = .None, full = true}
			copy(vals[r + 1 : node.num + 1], node.values[r:node.num])
			total := node.num + 1

			if total <= BTREE_SLOT_COUNT {
				leaf := BTree_Node{kind = .Leaf, num = total}
				copy(leaf.values[:total], vals[:total])
				ptr := btree_write_node(db, leaf, cur_ptr, frozen_at) or_return
				child = BTree_Insert_Result{
					node_ptr       = ptr,
					count          = i64(total),
					value_position = ptr + BTREE_NODE_HEADER_SIZE + i64(r) * SLOT_LENGTH,
				}
			} else {
				// Overflow: split into two leaves (reuse this node for the left half)
				left_n := BTREE_SPLIT_COUNT
				right_n := total - left_n
				left := BTree_Node{kind = .Leaf, num = left_n}
				copy(left.values[:left_n], vals[:left_n])
				right := BTree_Node{kind = .Leaf, num = right_n}
				copy(right.values[:right_n], vals[left_n:total])
				left_ptr := btree_write_node(db, left, cur_ptr, frozen_at) or_return
				right_ptr := write_btree_node(db, right) or_return
				value_position: i64
				if r < left_n {
					value_position = left_ptr + BTREE_NODE_HEADER_SIZE + i64(r) * SLOT_LENGTH
				} else {
					value_position = right_ptr + BTREE_NODE_HEADER_SIZE + i64(r - left_n) * SLOT_LENGTH
				}
				child = BTree_Insert_Result{
					node_ptr       = left_ptr,
					count          = i64(left_n),
					value_position = value_position,
					split          = BTree_Node_Ref{node_ptr = right_ptr, count = i64(right_n)},
				}
			}

		case .Branch:
			if btree_node_subtree_count(node) != cur_exp {
				return {}, .Invalid_BTree_Node
			}
			i := 0
			rem := cur_rem
			for i + 1 < node.num && rem > node.counts[i] {
				rem -= node.counts[i]
				i += 1
			}
			if rem > node.counts[i] {
				return {}, .Invalid_BTree_Node
			}
			frames[frame_len] = _BTree_Write_Frame{
				node_ptr  = cur_ptr,
				child_ptr = node.children[i].value,
				old_cnt   = node.counts[i],
				total_cnt = cur_exp,
				child_idx = u8(i),
				num       = u8(node.num),
				reusable  = false,
			}
			frame_len += 1
			cur_ptr = node.children[i].value
			cur_rem = rem
			cur_exp = node.counts[i]
			cur_depth += 1
			continue
		}
		break
	}

	for idx := frame_len - 1; idx >= 0; idx -= 1 {
		f := frames[idx]
		i := int(f.child_idx)
		if child.split == nil && (f.reusable || btree_reusable(db, f.node_ptr, frozen_at)) {
			if child.node_ptr != f.child_ptr {
				child_slot_pos := f.node_ptr + BTREE_NODE_HEADER_SIZE + i64(i) * SLOT_LENGTH
				core_seek_to(db.core, child_slot_pos) or_return
				core_write_slot(db.core, Slot{value = child.node_ptr, tag = .Index}) or_return
			}
			count_pos := f.node_ptr + BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT + i64(i) * 8
			core_seek_to(db.core, count_pos) or_return
			core_write_i64(db.core, child.count) or_return
			child = BTree_Insert_Result{
				node_ptr       = f.node_ptr,
				count          = f.total_cnt - f.old_cnt + child.count,
				value_position = child.value_position,
			}
			continue
		}

		node := read_btree_node(db, f.node_ptr) or_return
		children: [BTREE_SLOT_COUNT + 1]Slot
		counts: [BTREE_SLOT_COUNT + 1]i64
		copy(children[:node.num], node.children[:node.num])
		copy(counts[:node.num], node.counts[:node.num])
		children[i] = Slot{value = child.node_ptr, tag = .Index}
		counts[i] = child.count
		total := node.num
		if split, ok := child.split.?; ok {
			for j := node.num; j > i + 1; j -= 1 {
				children[j] = children[j - 1]
				counts[j] = counts[j - 1]
			}
			children[i + 1] = Slot{value = split.node_ptr, tag = .Index}
			counts[i + 1] = split.count
			total = node.num + 1
		}

		if total <= BTREE_SLOT_COUNT {
			total_cnt := _sum_counts_i64(counts[:total]) or_return
			branch := BTree_Node{kind = .Branch, num = total}
			copy(branch.children[:total], children[:total])
			copy(branch.counts[:total], counts[:total])
			ptr := btree_write_node(db, branch, f.node_ptr, frozen_at) or_return
			child = BTree_Insert_Result{
				node_ptr       = ptr,
				count          = total_cnt,
				value_position = child.value_position,
			}
			continue
		}

		left_n := BTREE_SPLIT_COUNT
		right_n := total - left_n
		left_cnt := _sum_counts_i64(counts[:left_n]) or_return
		right_cnt := _sum_counts_i64(counts[left_n:total]) or_return
		left := BTree_Node{kind = .Branch, num = left_n}
		copy(left.children[:left_n], children[:left_n])
		copy(left.counts[:left_n], counts[:left_n])
		right := BTree_Node{kind = .Branch, num = right_n}
		copy(right.children[:right_n], children[left_n:total])
		copy(right.counts[:right_n], counts[left_n:total])
		left_ptr := btree_write_node(db, left, f.node_ptr, frozen_at) or_return
		right_ptr := write_btree_node(db, right) or_return
		child = BTree_Insert_Result{
			node_ptr       = left_ptr,
			count          = left_cnt,
			value_position = child.value_position,
			split          = BTree_Node_Ref{node_ptr = right_ptr, count = right_cnt},
		}
	}

	return child, nil
}

btree_grow_root :: proc(db: ^Database, result: BTree_Insert_Result) -> (res: i64, err: Error) {
	return btree_make_root(db, BTree_Join_Result{node_ptr = result.node_ptr, count = result.count, split = result.split})
}

btree_get_for_write :: proc(db: ^Database, node_ptr, rank, expected, frozen_at: i64, depth: int = 0) -> (res: BTree_Write_Slot, err: Error) {
	if depth >= MAX_BTREE_DEPTH {
		return {}, .Invalid_BTree_Node
	}
	header_bytes: [BTREE_NODE_HEADER_SIZE]u8
	core_read_exact_at(db.core, node_ptr, header_bytes[:]) or_return
	kind_int := header_bytes[0]
	if kind_int > u8(BTree_Node_Kind.Branch) {
		return {}, .Invalid_BTree_Node_Kind
	}
	num := int(header_bytes[1])
	if num > BTREE_SLOT_COUNT || (BTree_Node_Kind(kind_int) == .Branch && num == 0) {
		return {}, .Invalid_BTree_Node
	}
	reusable := btree_reusable(db, node_ptr, frozen_at)
	if BTree_Node_Kind(kind_int) == .Leaf {
		if i64(num) != expected || rank < 0 || rank >= i64(num) {
			return {}, .Invalid_BTree_Node
		}
		if reusable {
			val_pos := node_ptr + BTREE_NODE_HEADER_SIZE + rank * SLOT_LENGTH
			slot := core_read_slot_at(db.core, val_pos) or_return
			if slot.tag == .Index || slot_empty(slot) {
				return {}, .Invalid_BTree_Node
			}
			return BTree_Write_Slot{
				node_ptr       = node_ptr,
				value_position = val_pos,
				slot           = slot,
			}, nil
		}
		node := read_btree_node(db, node_ptr) or_return
		new_ptr := write_btree_node(db, node) or_return
		return BTree_Write_Slot{
			node_ptr       = new_ptr,
			value_position = new_ptr + BTREE_NODE_HEADER_SIZE + rank * SLOT_LENGTH,
			slot           = node.values[rank],
		}, nil
	}

	if reusable {
		counts_pos := node_ptr + BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
		counts_buf: [8 * BTREE_SLOT_COUNT]u8
		core_read_exact_at(db.core, counts_pos, counts_buf[:num * 8]) or_return
		i := 0
		rem := rank
		total_count: i64 = 0
		chosen_cnt: i64 = 0
		picking := true
		for k in 0 ..< num {
			raw := endian.unchecked_get_u64be(counts_buf[k * 8 : k * 8 + 8])
			if raw == 0 || raw > u64(max(i64)) {
				return {}, .Invalid_BTree_Node
			}
			cnt := i64(raw)
			ok: bool
			total_count, ok = _checked_add_i64(total_count, cnt)
			if !ok {
				return {}, .Invalid_BTree_Node
			}
			if picking {
				if k + 1 == num || rem < cnt {
					chosen_cnt = cnt
					i = k
					picking = false
				} else {
					rem -= cnt
				}
			}
		}
		if total_count != expected || rem >= chosen_cnt {
			return {}, .Invalid_BTree_Node
		}
		child_slot_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(i) * SLOT_LENGTH
		child_slot := core_read_slot_at(db.core, child_slot_pos) or_return
		if child_slot.tag != .Index {
			return {}, .Invalid_BTree_Node
		}
		child_ptr := child_slot.value
		child := btree_get_for_write(db, child_ptr, rem, chosen_cnt, frozen_at, depth + 1) or_return
		if child.node_ptr != child_ptr {
			core_seek_to(db.core, child_slot_pos) or_return
			core_write_slot(db.core, Slot{value = child.node_ptr, tag = .Index}) or_return
		}
		return BTree_Write_Slot{node_ptr = node_ptr, value_position = child.value_position, slot = child.slot}, nil
	}

	node := read_btree_node(db, node_ptr) or_return
	if btree_node_subtree_count(node) != expected {
		return {}, .Invalid_BTree_Node
	}
	i := 0
	rem := rank
	for i + 1 < node.num && rem >= node.counts[i] {
		rem -= node.counts[i]
		i += 1
	}
	if rem >= node.counts[i] {
		return {}, .Invalid_BTree_Node
	}
	child_ptr := node.children[i].value
	child := btree_get_for_write(db, child_ptr, rem, node.counts[i], frozen_at, depth + 1) or_return
	node.children[i] = Slot{value = child.node_ptr, tag = .Index}
	new_ptr := write_btree_node(db, node) or_return
	return BTree_Write_Slot{node_ptr = new_ptr, value_position = child.value_position, slot = child.slot}, nil
}

BTree_Remove_Result :: struct {
	node_ptr:  i64,
	kind:      BTree_Node_Kind,
	num:       int,
	persisted: bool,
	node:      BTree_Node,
}

btree_remove :: proc(db: ^Database, node_ptr, rank, expected, frozen_at: i64, is_root: bool = false, depth: int = 0) -> (res: BTree_Remove_Result, err: Error) {
	frames: [MAX_BTREE_DEPTH]_BTree_Write_Frame = ---
	frame_len := 0
	cur_ptr := node_ptr
	cur_rem := rank
	cur_exp := expected
	cur_is_root := is_root
	cur_depth := depth
	child: BTree_Remove_Result

	for {
		if cur_depth >= MAX_BTREE_DEPTH {
			return {}, .Invalid_BTree_Node
		}
		if btree_reusable(db, cur_ptr, frozen_at) {
			header_bytes: [BTREE_NODE_HEADER_SIZE]u8
			core_read_exact_at(db.core, cur_ptr, header_bytes[:]) or_return
			kind_int := header_bytes[0]
			if kind_int > u8(BTree_Node_Kind.Branch) {
				return {}, .Invalid_BTree_Node_Kind
			}
			num := int(header_bytes[1])
			if num > BTREE_SLOT_COUNT || (BTree_Node_Kind(kind_int) == .Branch && num == 0) {
				return {}, .Invalid_BTree_Node
			}
			position := cur_ptr + BTREE_NODE_HEADER_SIZE
			if BTree_Node_Kind(kind_int) == .Leaf {
				r := int(cur_rem)
				if i64(num) != cur_exp || r < 0 || r >= num {
					return {}, .Invalid_BTree_Node
				}
				total := num - 1
				if cur_is_root || total >= BTREE_SPLIT_COUNT {
					entry_pos := position + i64(r) * SLOT_LENGTH
					tail_len := (total - r) * SLOT_LENGTH
					shift_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8
					if tail_len > 0 {
						core_read_exact_at(db.core, entry_pos + SLOT_LENGTH, shift_buf[:tail_len]) or_return
					}
					core_seek_to(db.core, entry_pos) or_return
					core_write_all(db.core, shift_buf[:tail_len + SLOT_LENGTH]) or_return
					new_hdr := [BTREE_NODE_HEADER_SIZE]u8{kind_int, u8(total)}
					core_seek_to(db.core, cur_ptr) or_return
					core_write_all(db.core, new_hdr[:]) or_return
					child = BTree_Remove_Result{
						node_ptr  = cur_ptr,
						kind      = .Leaf,
						num       = total,
						persisted = true,
					}
					break
				}
				node := read_btree_node(db, cur_ptr) or_return
				copy(node.values[r : node.num - 1], node.values[r + 1 : node.num])
				node.num -= 1
				node.values[node.num] = Slot{}
				child = BTree_Remove_Result{
					node_ptr  = cur_ptr,
					kind      = .Leaf,
					num       = node.num,
					persisted = false,
					node      = node,
				}
				break
			}

			counts_pos := position + SLOT_LENGTH * BTREE_SLOT_COUNT
			counts_buf: [8 * BTREE_SLOT_COUNT]u8
			core_read_exact_at(db.core, counts_pos, counts_buf[:num * 8]) or_return
			i := 0
			rem := cur_rem
			total_count: i64 = 0
			chosen_cnt: i64 = 0
			picking := true
			for k in 0 ..< num {
				raw := endian.unchecked_get_u64be(counts_buf[k * 8 : k * 8 + 8])
				if raw == 0 || raw > u64(max(i64)) {
					return {}, .Invalid_BTree_Node
				}
				cnt := i64(raw)
				ok: bool
				total_count, ok = _checked_add_i64(total_count, cnt)
				if !ok {
					return {}, .Invalid_BTree_Node
				}
				if picking {
					if k + 1 == num || rem < cnt {
						chosen_cnt = cnt
						i = k
						picking = false
					} else {
						rem -= cnt
					}
				}
			}
			if total_count != cur_exp || rem >= chosen_cnt {
				return {}, .Invalid_BTree_Node
			}
			child_slot_pos := position + i64(i) * SLOT_LENGTH
			child_slot := core_read_slot_at(db.core, child_slot_pos) or_return
			if child_slot.tag != .Index {
				return {}, .Invalid_BTree_Node
			}
			frames[frame_len] = _BTree_Write_Frame{
				node_ptr  = cur_ptr,
				child_ptr = child_slot.value,
				old_cnt   = chosen_cnt,
				total_cnt = total_count,
				child_idx = u8(i),
				num       = u8(num),
				reusable  = true,
			}
			frame_len += 1
			cur_ptr = child_slot.value
			cur_rem = rem
			cur_exp = chosen_cnt
			cur_is_root = false
			cur_depth += 1
			continue
		}

		node := read_btree_node(db, cur_ptr) or_return
		switch node.kind {
		case .Leaf:
			r := int(cur_rem)
			if i64(node.num) != cur_exp || r < 0 || r >= node.num {
				return {}, .Invalid_BTree_Node
			}
			copy(node.values[r : node.num - 1], node.values[r + 1 : node.num])
			node.num -= 1
			node.values[node.num] = Slot{}
			child = BTree_Remove_Result{
				node_ptr  = cur_ptr,
				kind      = .Leaf,
				num       = node.num,
				persisted = false,
				node      = node,
			}

		case .Branch:
			if btree_node_subtree_count(node) != cur_exp {
				return {}, .Invalid_BTree_Node
			}
			i := 0
			rem := cur_rem
			for i + 1 < node.num && rem >= node.counts[i] {
				rem -= node.counts[i]
				i += 1
			}
			if rem >= node.counts[i] {
				return {}, .Invalid_BTree_Node
			}
			frames[frame_len] = _BTree_Write_Frame{
				node_ptr  = cur_ptr,
				child_ptr = node.children[i].value,
				old_cnt   = node.counts[i],
				total_cnt = cur_exp,
				child_idx = u8(i),
				num       = u8(node.num),
				reusable  = false,
			}
			frame_len += 1
			cur_ptr = node.children[i].value
			cur_rem = rem
			cur_exp = node.counts[i]
			cur_is_root = false
			cur_depth += 1
			continue
		}
		break
	}

	for idx := frame_len - 1; idx >= 0; idx -= 1 {
		f := frames[idx]
		i := int(f.child_idx)
		lvl_is_root := is_root && idx == 0

		if f.reusable {
			position := f.node_ptr + BTREE_NODE_HEADER_SIZE
			if child.num >= BTREE_SPLIT_COUNT || int(f.num) == 1 {
				ptr := child.node_ptr
				if !child.persisted {
					ptr = btree_write_node(db, child.node, f.child_ptr, frozen_at) or_return
				}
				if ptr != f.child_ptr {
					child_slot_pos := position + i64(i) * SLOT_LENGTH
					core_seek_to(db.core, child_slot_pos) or_return
					core_write_slot(db.core, Slot{value = ptr, tag = .Index}) or_return
				}
				counts_pos := position + SLOT_LENGTH * BTREE_SLOT_COUNT + i64(i) * 8
				core_seek_to(db.core, counts_pos) or_return
				core_write_i64(db.core, f.old_cnt - 1) or_return
				child = BTree_Remove_Result{
					node_ptr  = f.node_ptr,
					kind      = .Branch,
					num       = int(f.num),
					persisted = true,
				}
				continue
			}

			node := read_btree_node(db, f.node_ptr) or_return
			child_node := child.node
			if child.persisted {
				child_node = read_btree_node(db, child.node_ptr) or_return
			}
			if child_node.num == 0 {
				btree_drop_child(&node, i)
				child = BTree_Remove_Result{
					node_ptr  = f.node_ptr,
					kind      = .Branch,
					num       = node.num,
					persisted = false,
					node      = node,
				}
				continue
			}
			first := i
			neighbor_i := i + 1
			if i + 1 >= node.num {
				first = i - 1
				neighbor_i = first
			}
			neighbor := read_btree_node(db, node.children[neighbor_i].value) or_return
			if neighbor.kind != child_node.kind || btree_node_subtree_count(neighbor) != node.counts[neighbor_i] {
				return {}, .Invalid_BTree_Node
			}
			if child_node.num + neighbor.num <= BTREE_SLOT_COUNT {
				if first == i {
					child_node = btree_concat_nodes(child_node, neighbor)
				} else {
					child_node = btree_concat_nodes(neighbor, child_node)
				}
				btree_drop_child(&node, first + 1)
				i = first
			}
			ptr := btree_write_node(db, child_node, f.child_ptr, frozen_at) or_return
			node.children[i] = Slot{value = ptr, tag = .Index}
			node.counts[i] = btree_node_subtree_count(child_node)
			if lvl_is_root || node.num >= BTREE_SPLIT_COUNT {
				write_btree_node_at(db, node, f.node_ptr) or_return
				child = BTree_Remove_Result{
					node_ptr  = f.node_ptr,
					kind      = .Branch,
					num       = node.num,
					persisted = true,
				}
				continue
			}
			child = BTree_Remove_Result{
				node_ptr  = f.node_ptr,
				kind      = .Branch,
				num       = node.num,
				persisted = false,
				node      = node,
			}
			continue
		}

		node := read_btree_node(db, f.node_ptr) or_return
		if child.num == 0 {
			btree_drop_child(&node, i)
			child = BTree_Remove_Result{
				node_ptr  = f.node_ptr,
				kind      = .Branch,
				num       = node.num,
				persisted = false,
				node      = node,
			}
			continue
		}
		child_node := child.node
		if child.num < BTREE_SPLIT_COUNT && node.num > 1 {
			if child.persisted {
				child_node = read_btree_node(db, child.node_ptr) or_return
			}
			first := i
			neighbor_i := i + 1
			if i + 1 >= node.num {
				first = i - 1
				neighbor_i = first
			}
			neighbor := read_btree_node(db, node.children[neighbor_i].value) or_return
			if neighbor.kind != child_node.kind || btree_node_subtree_count(neighbor) != node.counts[neighbor_i] {
				return {}, .Invalid_BTree_Node
			}
			if child_node.num + neighbor.num <= BTREE_SLOT_COUNT {
				if first == i {
					child_node = btree_concat_nodes(child_node, neighbor)
				} else {
					child_node = btree_concat_nodes(neighbor, child_node)
				}
				btree_drop_child(&node, first + 1)
				i = first
			}
			ptr := btree_write_node(db, child_node, f.child_ptr, frozen_at) or_return
			node.children[i] = Slot{value = ptr, tag = .Index}
			node.counts[i] = btree_node_subtree_count(child_node)
		} else {
			ptr := child.node_ptr
			if !child.persisted {
				ptr = btree_write_node(db, child_node, f.child_ptr, frozen_at) or_return
			}
			node.children[i] = Slot{value = ptr, tag = .Index}
			node.counts[i] -= 1
		}
		child = BTree_Remove_Result{
			node_ptr  = f.node_ptr,
			kind      = node.kind,
			num       = node.num,
			persisted = false,
			node      = node,
		}
	}

	return child, nil
}

btree_drop_child :: proc(branch: ^BTree_Node, i: int) {
	copy(branch.children[i : branch.num - 1], branch.children[i + 1 : branch.num])
	copy(branch.counts[i : branch.num - 1], branch.counts[i + 1 : branch.num])
	branch.num -= 1
	branch.children[branch.num] = Slot{}
	branch.counts[branch.num] = 0
}

btree_concat_nodes :: proc(a, b: BTree_Node) -> BTree_Node {
	a, b := a, b
	node := a
	switch a.kind {
	case .Leaf:
		copy(node.values[a.num : a.num + b.num], b.values[:b.num])
	case .Branch:
		copy(node.children[a.num : a.num + b.num], b.children[:b.num])
		copy(node.counts[a.num : a.num + b.num], b.counts[:b.num])
	}
	node.num = a.num + b.num
	return node
}

btree_height :: proc(db: ^Database, root_ptr: i64) -> (res: int, err: Error) {
	ptr := root_ptr
	height := 0
	for {
		if height >= MAX_BTREE_DEPTH {
			return 0, .Invalid_BTree_Node
		}
		buf: [BTREE_NODE_HEADER_SIZE + SLOT_LENGTH]u8
		core_read_exact_at(db.core, ptr, buf[:]) or_return
		kind_int := buf[0]
		if kind_int > u8(BTree_Node_Kind.Branch) {
			return 0, .Invalid_BTree_Node_Kind
		}
		if BTree_Node_Kind(kind_int) == .Leaf {
			return height, nil
		}
		if buf[1] == 0 {
			return 0, .Invalid_BTree_Node
		}
		height += 1
		child_slot := slot_from_slice(buf[BTREE_NODE_HEADER_SIZE:]) or_return
		if child_slot.tag != .Index {
			return 0, .Invalid_BTree_Node
		}
		ptr = child_slot.value
	}
}

btree_checked_height :: proc(db: ^Database, root_ptr, expected_size: i64) -> (res: int, err: Error) {
	ptr := root_ptr
	expected := expected_size
	for height := 0; ; height += 1 {
		if height >= MAX_BTREE_DEPTH {
			return 0, .Invalid_BTree_Node
		}
		node := read_btree_node(db, ptr) or_return
		switch node.kind {
		case .Leaf:
			if i64(node.num) != expected {
				return 0, .Invalid_BTree_Node
			}
			return height, nil
		case .Branch:
			if btree_node_subtree_count(node) != expected {
				return 0, .Invalid_BTree_Node
			}
			expected = node.counts[0]
			ptr = node.children[0].value
		}
	}
}

btree_make_root :: proc(db: ^Database, result: BTree_Join_Result) -> (res: i64, err: Error) {
	if split, ok := result.split.?; ok {
		if _, add_ok := _checked_add_i64(result.count, split.count); !add_ok {
			return 0, .Invalid_BTree_Node
		}
		root := BTree_Node{kind = .Branch, num = 2}
		root.children[0] = Slot{value = result.node_ptr, tag = .Index}
		root.children[1] = Slot{value = split.node_ptr, tag = .Index}
		root.counts[0] = result.count
		root.counts[1] = split.count
		return write_btree_node(db, root)
	}
	return result.node_ptr, nil
}

btree_assemble_leaf :: proc(db: ^Database, vals: []Slot, total: int) -> (res: BTree_Join_Result, err: Error) {
	if total <= BTREE_SLOT_COUNT {
		leaf := BTree_Node{kind = .Leaf, num = total}
		copy(leaf.values[:total], vals[:total])
		ptr := write_btree_node(db, leaf) or_return
		return BTree_Join_Result{node_ptr = ptr, count = i64(total)}, nil
	}
	left_n := total / 2
	left := BTree_Node{kind = .Leaf, num = left_n}
	copy(left.values[:left_n], vals[:left_n])
	right := BTree_Node{kind = .Leaf, num = total - left_n}
	copy(right.values[: total - left_n], vals[left_n:total])
	left_ptr := write_btree_node(db, left) or_return
	right_ptr := write_btree_node(db, right) or_return
	return BTree_Join_Result{
		node_ptr = left_ptr,
		count    = i64(left_n),
		split    = BTree_Node_Ref{node_ptr = right_ptr, count = i64(total - left_n)},
	}, nil
}

btree_assemble_branch :: proc(db: ^Database, children: []Slot, counts: []i64, total: int) -> (res: BTree_Join_Result, err: Error) {
	if total <= BTREE_SLOT_COUNT {
		branch_cnt := _sum_counts_i64(counts[:total]) or_return
		branch := BTree_Node{kind = .Branch, num = total}
		copy(branch.children[:total], children[:total])
		copy(branch.counts[:total], counts[:total])
		ptr := write_btree_node(db, branch) or_return
		return BTree_Join_Result{node_ptr = ptr, count = branch_cnt}, nil
	}
	left_n := total / 2
	left_cnt := _sum_counts_i64(counts[:left_n]) or_return
	right_cnt := _sum_counts_i64(counts[left_n:total]) or_return
	if _, ok := _checked_add_i64(left_cnt, right_cnt); !ok {
		return {}, .Invalid_BTree_Node
	}
	left := BTree_Node{kind = .Branch, num = left_n}
	copy(left.children[:left_n], children[:left_n])
	copy(left.counts[:left_n], counts[:left_n])
	right := BTree_Node{kind = .Branch, num = total - left_n}
	copy(right.children[: total - left_n], children[left_n:total])
	copy(right.counts[: total - left_n], counts[left_n:total])
	left_ptr := write_btree_node(db, left) or_return
	right_ptr := write_btree_node(db, right) or_return
	return BTree_Join_Result{
		node_ptr = left_ptr,
		count    = left_cnt,
		split    = BTree_Node_Ref{node_ptr = right_ptr, count = right_cnt},
	}, nil
}

btree_merge_nodes :: proc(db: ^Database, a: BTree_Node, expected_a: i64, b: BTree_Node, expected_b: i64, expected_height: int) -> (res: BTree_Join_Result, err: Error) {
	a, b := a, b
	if a.kind != b.kind || (expected_height == 0) != (a.kind == .Leaf) {
		return {}, .Invalid_BTree_Node
	}
	if btree_node_subtree_count(a) != expected_a || btree_node_subtree_count(b) != expected_b {
		return {}, .Invalid_BTree_Node
	}
	if a.kind == .Leaf {
		vals: [2 * BTREE_SLOT_COUNT]Slot
		copy(vals[:a.num], a.values[:a.num])
		copy(vals[a.num : a.num + b.num], b.values[:b.num])
		return btree_assemble_leaf(db, vals[: a.num + b.num], a.num + b.num)
	}
	children: [2 * BTREE_SLOT_COUNT]Slot
	counts: [2 * BTREE_SLOT_COUNT]i64
	copy(children[:a.num], a.children[:a.num])
	copy(children[a.num : a.num + b.num], b.children[:b.num])
	copy(counts[:a.num], a.counts[:a.num])
	copy(counts[a.num : a.num + b.num], b.counts[:b.num])
	return btree_assemble_branch(db, children[: a.num + b.num], counts[: a.num + b.num], a.num + b.num)
}

btree_join_right :: proc(db: ^Database, a_ptr: i64, ha: int, expected_a: i64, b_ptr: i64, hb: int, expected_b: i64, depth: int = 0) -> (res: BTree_Join_Result, err: Error) {
	if depth >= MAX_BTREE_DEPTH || ha <= hb {
		return {}, .Invalid_BTree_Node
	}
	a := read_btree_node(db, a_ptr) or_return
	if a.kind != .Branch || a.num == 0 || btree_node_subtree_count(a) != expected_a {
		return {}, .Invalid_BTree_Node
	}
	last := a.num - 1
	sub: BTree_Join_Result
	if ha - 1 == hb {
		last_child := read_btree_node(db, a.children[last].value) or_return
		b_node := read_btree_node(db, b_ptr) or_return
		sub = btree_merge_nodes(db, last_child, a.counts[last], b_node, expected_b, hb) or_return
	} else {
		sub = btree_join_right(db, a.children[last].value, ha - 1, a.counts[last], b_ptr, hb, expected_b, depth + 1) or_return
	}

	children: [BTREE_SLOT_COUNT + 1]Slot
	counts: [BTREE_SLOT_COUNT + 1]i64
	copy(children[:a.num], a.children[:a.num])
	copy(counts[:a.num], a.counts[:a.num])
	children[last] = Slot{value = sub.node_ptr, tag = .Index}
	counts[last] = sub.count
	total := a.num
	if split, ok := sub.split.?; ok {
		children[total] = Slot{value = split.node_ptr, tag = .Index}
		counts[total] = split.count
		total += 1
	}
	return btree_assemble_branch(db, children[:total], counts[:total], total)
}

btree_join_left :: proc(db: ^Database, a_ptr: i64, ha: int, expected_a: i64, b_ptr: i64, hb: int, expected_b: i64, depth: int = 0) -> (res: BTree_Join_Result, err: Error) {
	if depth >= MAX_BTREE_DEPTH || hb <= ha {
		return {}, .Invalid_BTree_Node
	}
	b := read_btree_node(db, b_ptr) or_return
	if b.kind != .Branch || b.num == 0 || btree_node_subtree_count(b) != expected_b {
		return {}, .Invalid_BTree_Node
	}
	sub: BTree_Join_Result
	if hb - 1 == ha {
		a_node := read_btree_node(db, a_ptr) or_return
		first_child := read_btree_node(db, b.children[0].value) or_return
		sub = btree_merge_nodes(db, a_node, expected_a, first_child, b.counts[0], ha) or_return
	} else {
		sub = btree_join_left(db, a_ptr, ha, expected_a, b.children[0].value, hb - 1, b.counts[0], depth + 1) or_return
	}

	children: [BTREE_SLOT_COUNT + 1]Slot
	counts: [BTREE_SLOT_COUNT + 1]i64
	total := 0
	children[total] = Slot{value = sub.node_ptr, tag = .Index}
	counts[total] = sub.count
	total += 1
	if split, ok := sub.split.?; ok {
		children[total] = Slot{value = split.node_ptr, tag = .Index}
		counts[total] = split.count
		total += 1
	}
	for k in 1 ..< b.num {
		children[total] = b.children[k]
		counts[total] = b.counts[k]
		total += 1
	}
	return btree_assemble_branch(db, children[:total], counts[:total], total)
}

btree_join :: proc(db: ^Database, root_a, size_a, root_b, size_b: i64) -> (res: i64, err: Error) {
	ha := btree_checked_height(db, root_a, size_a) or_return
	hb := btree_checked_height(db, root_b, size_b) or_return
	result: BTree_Join_Result
	if ha == hb {
		a := read_btree_node(db, root_a) or_return
		b := read_btree_node(db, root_b) or_return
		result = btree_merge_nodes(db, a, size_a, b, size_b, ha) or_return
	} else if ha > hb {
		result = btree_join_right(db, root_a, ha, size_a, root_b, hb, size_b) or_return
	} else {
		result = btree_join_left(db, root_a, ha, size_a, root_b, hb, size_b) or_return
	}
	return btree_make_root(db, result)
}

btree_subtree :: proc(db: ^Database, children: []Slot, counts: []i64, start, length: int) -> (res: i64, err: Error) {
	if length == 0 {
		return btree_new_root(db)
	}
	if length == 1 {
		return children[start].value, nil
	}
	sub_children: [BTREE_SLOT_COUNT]Slot
	sub_counts: [BTREE_SLOT_COUNT]i64
	copy(sub_children[:length], children[start : start + length])
	copy(sub_counts[:length], counts[start : start + length])
	branch_res := btree_assemble_branch(db, sub_children[:length], sub_counts[:length], length) or_return
	return branch_res.node_ptr, nil
}

btree_split_right :: proc(db: ^Database, root_ptr, rank, expected: i64, depth: int = 0) -> (res: i64, err: Error) {
	if depth >= MAX_BTREE_DEPTH {
		return 0, .Invalid_BTree_Node
	}
	node := read_btree_node(db, root_ptr) or_return
	if node.kind == .Leaf {
		r := int(rank)
		if i64(node.num) != expected || r < 0 || r > node.num {
			return 0, .Invalid_BTree_Node
		}
		if r == 0 {
			return root_ptr, nil
		}
		right := BTree_Node{kind = .Leaf, num = node.num - r}
		copy(right.values[: node.num - r], node.values[r:node.num])
		return write_btree_node(db, right)
	}
	if btree_node_subtree_count(node) != expected {
		return 0, .Invalid_BTree_Node
	}
	if rank == 0 {
		return root_ptr, nil
	}
	i := 0
	rem := rank
	for i + 1 < node.num && rem > node.counts[i] {
		rem -= node.counts[i]
		i += 1
	}
	if rem > node.counts[i] {
		return 0, .Invalid_BTree_Node
	}
	if rem == node.counts[i] {
		return btree_subtree(db, node.children[:], node.counts[:], i + 1, node.num - (i + 1))
	}
	child_right := btree_split_right(db, node.children[i].value, rem, node.counts[i], depth + 1) or_return
	joined_right := child_right
	if i + 1 < node.num {
		right_sub := btree_subtree(db, node.children[:], node.counts[:], i + 1, node.num - (i + 1)) or_return
		right_count := _sum_counts_i64(node.counts[i + 1 : node.num]) or_return
		joined_right = btree_join(db, child_right, node.counts[i] - rem, right_sub, right_count) or_return
	}
	return joined_right, nil
}

btree_split_left :: proc(db: ^Database, root_ptr, rank, expected: i64, depth: int = 0) -> (res: i64, err: Error) {
	if depth >= MAX_BTREE_DEPTH {
		return 0, .Invalid_BTree_Node
	}
	node := read_btree_node(db, root_ptr) or_return
	if node.kind == .Leaf {
		r := int(rank)
		if i64(node.num) != expected || r < 0 || r > node.num {
			return 0, .Invalid_BTree_Node
		}
		if r == 0 {
			return btree_new_root(db)
		}
		if r == node.num {
			return root_ptr, nil
		}
		left := BTree_Node{kind = .Leaf, num = r}
		copy(left.values[:r], node.values[:r])
		return write_btree_node(db, left)
	}
	if btree_node_subtree_count(node) != expected {
		return 0, .Invalid_BTree_Node
	}
	if rank == 0 {
		return btree_new_root(db)
	}
	i := 0
	rem := rank
	for i + 1 < node.num && rem > node.counts[i] {
		rem -= node.counts[i]
		i += 1
	}
	if rem > node.counts[i] {
		return 0, .Invalid_BTree_Node
	}
	if rem == node.counts[i] {
		if i + 1 == node.num {
			return root_ptr, nil
		}
		return btree_subtree(db, node.children[:], node.counts[:], 0, i + 1)
	}
	child_left := btree_split_left(db, node.children[i].value, rem, node.counts[i], depth + 1) or_return
	joined_left := child_left
	if i > 0 {
		left_sub := btree_subtree(db, node.children[:], node.counts[:], 0, i) or_return
		left_count := _sum_counts_i64(node.counts[:i]) or_return
		joined_left = btree_join(db, left_sub, left_count, child_left, rem) or_return
	}
	return joined_left, nil
}

btree_split :: proc(db: ^Database, root_ptr, rank, expected: i64, depth: int = 0) -> (res: BTree_Split_Result, err: Error) {
	if depth >= MAX_BTREE_DEPTH {
		return {}, .Invalid_BTree_Node
	}
	node := read_btree_node(db, root_ptr) or_return
	if node.kind == .Leaf {
		r := int(rank)
		if i64(node.num) != expected || r < 0 || r > node.num {
			return {}, .Invalid_BTree_Node
		}
		left := BTree_Node{kind = .Leaf, num = r}
		copy(left.values[:r], node.values[:r])
		right := BTree_Node{kind = .Leaf, num = node.num - r}
		copy(right.values[: node.num - r], node.values[r:node.num])
		left_ptr := write_btree_node(db, left) or_return
		right_ptr := write_btree_node(db, right) or_return
		return BTree_Split_Result{left = left_ptr, right = right_ptr}, nil
	}
	if btree_node_subtree_count(node) != expected {
		return {}, .Invalid_BTree_Node
	}
	i := 0
	rem := rank
	for i + 1 < node.num && rem > node.counts[i] {
		rem -= node.counts[i]
		i += 1
	}
	if rem > node.counts[i] {
		return {}, .Invalid_BTree_Node
	}
	child := btree_split(db, node.children[i].value, rem, node.counts[i], depth + 1) or_return
	joined_left := child.left
	if i > 0 {
		left_sub := btree_subtree(db, node.children[:], node.counts[:], 0, i) or_return
		left_count := _sum_counts_i64(node.counts[:i]) or_return
		joined_left = btree_join(db, left_sub, left_count, child.left, rem) or_return
	}
	joined_right := child.right
	if i + 1 < node.num {
		right_sub := btree_subtree(db, node.children[:], node.counts[:], i + 1, node.num - (i + 1)) or_return
		right_count := _sum_counts_i64(node.counts[i + 1 : node.num]) or_return
		joined_right = btree_join(db, child.right, node.counts[i] - rem, right_sub, right_count) or_return
	}
	return BTree_Split_Result{left = joined_left, right = joined_right}, nil
}

// SortedMap / SortedSet methods (backed by a count-augmented B+Tree)

read_sorted_node :: proc(db: ^Database, ptr: i64) -> (res: Sorted_Node, err: Error) {
	buf: [SORTED_BRANCH_BLOCK_SIZE]u8 = ---
	block := core_read_block_at(db.core, ptr, buf[:]) or_return
	if len(block) < SORTED_LEAF_BLOCK_SIZE {
		return {}, Xitdb_Error.Unexpected_EOF
	}
	kind_int := block[0]
	if kind_int > u8(BTree_Node_Kind.Branch) {
		return {}, .Invalid_BTree_Node_Kind
	}
	kind := BTree_Node_Kind(kind_int)
	num := int(block[1])
	if num > BTREE_SLOT_COUNT || (kind == .Branch && num == 0) {
		return {}, .Invalid_BTree_Node
	}
	body := block[BTREE_NODE_HEADER_SIZE:]
	node := Sorted_Node{kind = kind, num = num}
	switch kind {
	case .Leaf:
		for i in 0 ..< BTREE_SLOT_COUNT {
			s := slot_from_slice(body[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH]) or_return
			if i < num {
				if !is_sorted_entry_tag(s.tag) {
					return {}, .Invalid_BTree_Node
				}
				node.entries[i] = s
			} else if !slot_empty(s) {
				return {}, .Invalid_BTree_Node
			}
		}
	case .Branch:
		if len(block) < SORTED_BRANCH_BLOCK_SIZE {
			return {}, Xitdb_Error.Unexpected_EOF
		}
		for i in 0 ..< BTREE_SLOT_COUNT {
			s := slot_from_slice(body[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH]) or_return
			if i < num {
				if s.tag != .Index {
					return {}, .Invalid_BTree_Node
				}
				node.children[i] = s
			} else if !slot_empty(s) {
				return {}, .Invalid_BTree_Node
			}
		}
		sep_offset := SLOT_LENGTH * BTREE_SLOT_COUNT
		for i in 0 ..< BTREE_SLOT_COUNT {
			s := slot_from_slice(body[sep_offset + i * SLOT_LENGTH : sep_offset + (i + 1) * SLOT_LENGTH]) or_return
			if i == 0 {
				if !slot_empty(s) && s.tag != .Bytes && s.tag != .Short_Bytes {
					return {}, .Invalid_BTree_Node
				}
				node.separators[i] = s
			} else if i < num {
				if s.tag != .Bytes && s.tag != .Short_Bytes {
					return {}, .Invalid_BTree_Node
				}
				node.separators[i] = s
			} else if !slot_empty(s) {
				return {}, .Invalid_BTree_Node
			}
		}
		counts_offset := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
		total: i64 = 0
		for i in 0 ..< BTREE_SLOT_COUNT {
			raw := endian.unchecked_get_u64be(body[counts_offset + i * 8 : counts_offset + (i + 1) * 8])
			if i < num {
				if raw > u64(max(i64)) {
					return {}, .Invalid_BTree_Node
				}
				ok: bool
				total, ok = _checked_add_i64(total, i64(raw))
				if !ok {
					return {}, .Invalid_BTree_Node
				}
				node.counts[i] = i64(raw)
			} else if raw != 0 {
				return {}, .Invalid_BTree_Node
			}
		}
	}
	return node, nil
}

write_sorted_node_at :: proc(db: ^Database, node: Sorted_Node, ptr: i64) -> Error {
	core_seek_to(db.core, ptr) or_return
	switch node.kind {
	case .Leaf:
		buf: [SORTED_LEAF_BLOCK_SIZE]u8
		buf[0] = u8(node.kind)
		buf[1] = u8(node.num)
		off := BTREE_NODE_HEADER_SIZE
		for i in 0 ..< node.num {
			sb := slot_to_bytes(node.entries[i])
			copy(buf[off:], sb[:])
			off += SLOT_LENGTH
		}
		return core_write_all(db.core, buf[:])
	case .Branch:
		buf: [SORTED_BRANCH_BLOCK_SIZE]u8
		buf[0] = u8(node.kind)
		buf[1] = u8(node.num)
		off := BTREE_NODE_HEADER_SIZE
		for i in 0 ..< node.num {
			sb := slot_to_bytes(node.children[i])
			copy(buf[off:], sb[:])
			off += SLOT_LENGTH
		}
		sep_off := BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
		for i in 0 ..< node.num {
			sb := slot_to_bytes(node.separators[i])
			copy(buf[sep_off:], sb[:])
			sep_off += SLOT_LENGTH
		}
		counts_off := BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
		for i in 0 ..< node.num {
			endian.unchecked_put_u64be(buf[counts_off : counts_off + 8], u64(node.counts[i]))
			counts_off += 8
		}
		return core_write_all(db.core, buf[:])
	}
	return .Unreachable
}

write_sorted_node :: proc(db: ^Database, node: Sorted_Node) -> (res: i64, err: Error) {
	ptr := core_length(db.core) or_return
	write_sorted_node_at(db, node, ptr) or_return
	return ptr, nil
}

sorted_write_node :: proc(db: ^Database, node: Sorted_Node, old_ptr, frozen_at: i64) -> (res: i64, err: Error) {
	if btree_reusable(db, old_ptr, frozen_at) {
		write_sorted_node_at(db, node, old_ptr) or_return
		return old_ptr, nil
	}
	return write_sorted_node(db, node)
}

read_kv_pair :: proc(db: ^Database, entry: Slot) -> (res: Key_Value_Pair, err: Error) {
	if is_key_only_entry(entry) {
		return Key_Value_Pair{value_slot = Slot{}, key_slot = entry, hash = nil}, nil
	}
	return decode_kv_pair_at(db.core, entry.value, entry.tag, 0, context.temp_allocator)
}

sorted_entry_key_slot :: #force_inline proc(db: ^Database, entry: Slot) -> (res: Slot, err: Error) {
	if is_key_only_entry(entry) {
		return entry, nil
	}
	return core_read_slot_at(db.core, entry.value)
}

write_kv_pair :: proc(db: ^Database, tag: Tag, kv_pair: Key_Value_Pair) -> (res: Slot, err: Error) {
	pos := core_length(db.core) or_return
	core_seek_to(db.core, pos) or_return
	encode_kv_pair(db.core, tag, kv_pair) or_return
	return Slot{value = pos, tag = tag}, nil
}

compare_key :: proc(db: ^Database, key_slot: Slot, target: []u8) -> (res: int, err: Error) {
	#partial switch key_slot.tag {
	case .Short_Bytes:
		buf: [8]u8 = ---
		endian.unchecked_put_u64be(buf[:], u64(key_slot.value))
		total := 6 if key_slot.full else 8
		length := total
		for i in 0 ..< total {
			if buf[i] == 0 {
				length = i
				break
			}
		}
		return bytes.compare(buf[:length], target), nil
	case .Bytes:
		#partial switch &v in db.core {
		case Core_Memory:
			buf_len := i64(len(v.buf))
			if key_slot.value < 0 || key_slot.value > buf_len || 8 > buf_len - key_slot.value {
				return 0, Xitdb_Error.Unexpected_EOF
			}
			p := int(key_slot.value)
			raw_len := i64(endian.unchecked_get_u64be(v.buf[p : p + 8]))
			if raw_len < 0 || raw_len > buf_len - key_slot.value - 8 {
				return 0, Xitdb_Error.Unexpected_EOF
			}
			return bytes.compare(v.buf[p + 8 : p + 8 + int(raw_len)], target), nil
		case Core_Buffered_File:
			buf_len := i64(len(v.memory.buf))
			if buf_len > 0 && key_slot.value >= v.memory_pos && key_slot.value <= v.memory_pos + buf_len && 8 <= (v.memory_pos + buf_len) - key_slot.value {
				mem_off := int(key_slot.value - v.memory_pos)
				raw_len := i64(endian.unchecked_get_u64be(v.memory.buf[mem_off : mem_off + 8]))
				if raw_len >= 0 && raw_len <= (v.memory_pos + buf_len) - key_slot.value - 8 {
					return bytes.compare(v.memory.buf[mem_off + 8 : mem_off + 8 + int(raw_len)], target), nil
				}
			}
		}
		first_buf: [256]u8 = ---
		first := core_read_short_at(db.core, key_slot.value, first_buf[:]) or_return
		if len(first) < 8 {
			return 0, Xitdb_Error.Unexpected_EOF
		}
		raw_stored_len := i64(endian.unchecked_get_u64be(first[:8]))
		if raw_stored_len < 0 {
			return 0, Xitdb_Error.Unexpected_EOF
		}
		core_len := core_length(db.core) or_return
		if key_slot.value > core_len || 8 > core_len - key_slot.value || raw_stored_len > core_len - key_slot.value - 8 {
			return 0, Xitdb_Error.Unexpected_EOF
		}
		stored_len := int(raw_stored_len)
		avail := len(first) - 8
		if avail < min(stored_len, len(first_buf) - 8) {
			return 0, Xitdb_Error.Unexpected_EOF
		}
		head := first[8 : 8 + min(avail, stored_len)]
		first_cmp := bytes.compare(head, target[:min(len(head), len(target))])
		if first_cmp != 0 {
			return first_cmp, nil
		}
		remaining := stored_len - len(head)
		rest := target[len(head):]
		pos := key_slot.value + 8 + i64(len(head))
		for remaining > 0 {
			if len(rest) == 0 {
				return 1, nil
			}
			chunk_buf: [256]u8 = ---
			n := min(remaining, len(chunk_buf))
			stored := chunk_buf[:n]
			core_read_exact_at(db.core, pos, stored) or_return
			cmp := bytes.compare(stored, rest[:min(n, len(rest))])
			if cmp != 0 {
				return cmp, nil
			}
			pos += i64(n)
			remaining -= n
			rest = rest[n:]
		}
		return -1 if len(rest) > 0 else 0, nil
	case:
		return 0, .Unexpected_Tag
	}
}

// Binary search a Sorted_Node (.Leaf) for `key`.
// Returns `(index, true, nil)` on exact match, or `(lower_bound_index, false, nil)` if not found.
sorted_leaf_search :: proc(db: ^Database, node: ^Sorted_Node, key: []u8) -> (idx: int, found: bool, err: Error) {
	lo := 0
	hi := node.num
	for lo < hi {
		mid := int(uint(lo + hi) >> 1)
		key_slot := sorted_entry_key_slot(db, node.entries[mid]) or_return
		cmp := compare_key(db, key_slot, key) or_return
		if cmp == 0 {
			return mid, true, nil
		} else if cmp < 0 {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo, false, nil
}

// Binary search a Sorted_Node (.Branch) for the child index `0 ..< node.num` containing `key`.
sorted_branch_search :: proc(db: ^Database, node: ^Sorted_Node, key: []u8) -> (idx: int, err: Error) {
	lo := 1
	hi := node.num
	for lo < hi {
		mid := int(uint(lo + hi) >> 1)
		c := compare_key(db, node.separators[mid], key) or_return
		if c <= 0 {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo - 1, nil
}

sorted_get :: proc(db: ^Database, header: BTree_Header, key: []u8) -> (res: Maybe(Slot), err: Error) {
	if header.size == 0 {
		return nil, nil
	}
	node_ptr := header.root_ptr
	expected := header.size
	for depth := 0; ; depth += 1 {
		if depth >= MAX_BTREE_DEPTH {
			return nil, .Invalid_BTree_Node
		}
		node := read_sorted_node(db, node_ptr) or_return
		switch node.kind {
		case .Leaf:
			if i64(node.num) != expected {
				return nil, .Invalid_BTree_Node
			}
			idx, found := sorted_leaf_search(db, &node, key) or_return
			if !found {
				return nil, nil
			}
			return node.entries[idx], nil
		case .Branch:
			if sorted_node_subtree_count(node) != expected {
				return nil, .Invalid_BTree_Node
			}
			i := sorted_branch_search(db, &node, key) or_return
			expected = node.counts[i]
			node_ptr = node.children[i].value
		}
	}
}

sorted_rank :: proc(db: ^Database, header: BTree_Header, key: []u8) -> (res: i64, err: Error) {
	if header.size == 0 {
		return 0, nil
	}
	node_ptr := header.root_ptr
	expected := header.size
	rank: i64 = 0
	for depth := 0; ; depth += 1 {
		if depth >= MAX_BTREE_DEPTH {
			return 0, .Invalid_BTree_Node
		}
		node := read_sorted_node(db, node_ptr) or_return
		switch node.kind {
		case .Leaf:
			if i64(node.num) != expected {
				return 0, .Invalid_BTree_Node
			}
			idx, _ := sorted_leaf_search(db, &node, key) or_return
			total, ok := _checked_add_i64(rank, i64(idx))
			if !ok || total > header.size {
				return 0, .Invalid_BTree_Node
			}
			return total, nil
		case .Branch:
			if sorted_node_subtree_count(node) != expected {
				return 0, .Invalid_BTree_Node
			}
			i := sorted_branch_search(db, &node, key) or_return
			for k in 0 ..< i {
				ok: bool
				rank, ok = _checked_add_i64(rank, node.counts[k])
				if !ok {
					return 0, .Invalid_BTree_Node
				}
			}
			expected = node.counts[i]
			node_ptr = node.children[i].value
		}
	}
}

write_key :: proc(db: ^Database, key: []u8) -> (res: Slot, err: Error) {
	if len(key) <= 8 {
		has_zero := false
		for b in key {
			if b == 0 {
				has_zero = true
				break
			}
		}
		if !has_zero {
			value: [8]u8
			copy(value[:], key)
			return Slot{value = i64(endian.unchecked_get_u64be(value[:])), tag = .Short_Bytes}, nil
		}
	}
	pos := core_length(db.core) or_return
	core_seek_to(db.core, pos) or_return
	if len(key) <= 248 {
		buf: [256]u8 = ---
		endian.unchecked_put_u64be(buf[0:8], u64(len(key)))
		copy(buf[8:8 + len(key)], key)
		core_write_all(db.core, buf[:8 + len(key)]) or_return
		return Slot{value = pos, tag = .Bytes}, nil
	}
	core_write_i64(db.core, i64(len(key))) or_return
	core_write_all(db.core, key) or_return
	return Slot{value = pos, tag = .Bytes}, nil
}

write_sorted_pair :: proc(db: ^Database, key_slot: Slot) -> (res: Slot, err: Error) {
	return write_kv_pair(db, .Sorted_KV_Pair, Key_Value_Pair{
		value_slot = Slot{},
		key_slot   = key_slot,
		hash       = nil,
	})
}

write_sorted_key_and_entry :: proc(db: ^Database, key: []u8, key_only: bool) -> (key_slot: Slot, entry: Slot, err: Error) {
	if len(key) <= 8 {
		has_zero := false
		for b in key {
			if b == 0 {
				has_zero = true
				break
			}
		}
		if !has_zero {
			value: [8]u8
			copy(value[:], key)
			key_slot = Slot{value = i64(endian.unchecked_get_u64be(value[:])), tag = .Short_Bytes}
			if key_only {
				return key_slot, key_slot, nil
			}
			entry = write_sorted_pair(db, key_slot) or_return
			return key_slot, entry, nil
		}
	}
	pos := core_length(db.core) or_return
	core_seek_to(db.core, pos) or_return
	key_slot = Slot{value = pos, tag = .Bytes}
	if key_only {
		if len(key) <= 248 {
			buf: [256]u8 = ---
			endian.unchecked_put_u64be(buf[0:8], u64(len(key)))
			copy(buf[8:8 + len(key)], key)
			core_write_all(db.core, buf[:8 + len(key)]) or_return
			return key_slot, key_slot, nil
		}
		core_write_i64(db.core, i64(len(key))) or_return
		core_write_all(db.core, key) or_return
		return key_slot, key_slot, nil
	}
	pair_pos := pos + 8 + i64(len(key))
	entry = Slot{value = pair_pos, tag = .Sorted_KV_Pair}
	if len(key) <= 230 {
		buf: [256]u8 = ---
		endian.unchecked_put_u64be(buf[0:8], u64(len(key)))
		copy(buf[8 : 8 + len(key)], key)
		ks_bytes := slot_to_bytes(key_slot)
		vs_bytes := slot_to_bytes(Slot{})
		pair_off := 8 + len(key)
		copy(buf[pair_off : pair_off + SLOT_LENGTH], ks_bytes[:])
		copy(buf[pair_off + SLOT_LENGTH : pair_off + SORTED_KV_PAIR_LENGTH], vs_bytes[:])
		core_write_all(db.core, buf[:pair_off + SORTED_KV_PAIR_LENGTH]) or_return
		return key_slot, entry, nil
	}
	core_write_i64(db.core, i64(len(key))) or_return
	core_write_all(db.core, key) or_return
	entry = write_sorted_pair(db, key_slot) or_return
	return key_slot, entry, nil
}

sorted_put :: proc(db: ^Database, node_ptr: i64, key: []u8, expected: i64, key_only, can_add: bool, frozen_at: i64, depth: int = 0) -> (res: Sorted_Insert_Result, err: Error) {
	frames: [MAX_BTREE_DEPTH]_BTree_Write_Frame = ---
	frame_len := 0
	cur_ptr := node_ptr
	cur_exp := expected
	cur_depth := depth
	child: Sorted_Insert_Result

	for {
		if cur_depth >= MAX_BTREE_DEPTH {
			return {}, .Invalid_BTree_Node
		}
		if btree_reusable(db, cur_ptr, frozen_at) {
			node_buf: [SORTED_BRANCH_BLOCK_SIZE]u8 = ---
			block := core_read_short_at(db.core, cur_ptr, node_buf[:]) or_return
			if len(block) < SORTED_LEAF_BLOCK_SIZE {
				return {}, Xitdb_Error.Unexpected_EOF
			}
			kind_int := block[0]
			if kind_int > u8(BTree_Node_Kind.Branch) {
				return {}, .Invalid_BTree_Node_Kind
			}
			num := int(block[1])
			if num > BTREE_SLOT_COUNT || (BTree_Node_Kind(kind_int) == .Branch && num == 0) {
				return {}, .Invalid_BTree_Node
			}
			position := cur_ptr + BTREE_NODE_HEADER_SIZE
			if BTree_Node_Kind(kind_int) == .Leaf {
				if i64(num) != cur_exp {
					return {}, .Invalid_BTree_Node
				}
				entries_buf := block[BTREE_NODE_HEADER_SIZE : BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT]
				lo := 0
				hi := num
				matched_slot: Slot
				found := false
				for lo < hi {
					mid := int(uint(lo + hi) >> 1)
					entry_slot := slot_from_slice(entries_buf[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH]) or_return
					if !is_sorted_entry_tag(entry_slot.tag) {
						return {}, .Invalid_BTree_Node
					}
					key_slot := sorted_entry_key_slot(db, entry_slot) or_return
					cmp := compare_key(db, key_slot, key) or_return
					if cmp == 0 {
						lo = mid
						matched_slot = entry_slot
						found = true
						break
					} else if cmp < 0 {
						lo = mid + 1
					} else {
						hi = mid
					}
				}
				if found {
					if key_only {
						child = Sorted_Insert_Result{
							node_ptr = cur_ptr,
							count    = i64(num),
							entry    = matched_slot,
							added    = false,
						}
						break
					}
					entry := matched_slot
					rewritten := false
					if is_key_only_entry(entry) {
						entry = write_sorted_pair(db, entry) or_return
						rewritten = true
					} else if !btree_reusable(db, entry.value, frozen_at) {
						kv := read_kv_pair(db, entry) or_return
						entry = write_kv_pair(db, entry.tag, kv) or_return
						rewritten = true
					}
					if rewritten {
						entry_pos := position + i64(lo) * SLOT_LENGTH
						core_seek_to(db.core, entry_pos) or_return
						core_write_slot(db.core, entry) or_return
					}
					child = Sorted_Insert_Result{
						node_ptr = cur_ptr,
						count    = i64(num),
						entry    = entry,
						added    = false,
					}
					break
				}
				if !can_add {
					return {}, .Invalid_BTree_Node
				}
				idx := lo
				key_slot, entry := write_sorted_key_and_entry(db, key, key_only) or_return
				if num < BTREE_SLOT_COUNT {
					total := num + 1
					entry_pos := position + i64(idx) * SLOT_LENGTH
					eb := slot_to_bytes(entry)
					if idx < num {
						tail_len := (num - idx) * SLOT_LENGTH
						shift_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
						copy(shift_buf[:SLOT_LENGTH], eb[:])
						copy(shift_buf[SLOT_LENGTH : SLOT_LENGTH + tail_len], entries_buf[idx * SLOT_LENGTH : num * SLOT_LENGTH])
						core_seek_to(db.core, entry_pos) or_return
						core_write_all(db.core, shift_buf[:SLOT_LENGTH + tail_len]) or_return
					} else {
						core_seek_to(db.core, entry_pos) or_return
						core_write_all(db.core, eb[:]) or_return
					}
					new_hdr := [BTREE_NODE_HEADER_SIZE]u8{kind_int, u8(total)}
					core_seek_to(db.core, cur_ptr) or_return
					core_write_all(db.core, new_hdr[:]) or_return
					child = Sorted_Insert_Result{
						node_ptr = cur_ptr,
						count    = i64(total),
						entry    = entry,
						added    = true,
					}
					break
				}
				entries: [BTREE_SLOT_COUNT + 1]Slot = ---
				for j in 0 ..< idx {
					entries[j] = slot_from_slice(entries_buf[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH]) or_return
				}
				entries[idx] = entry
				for j in idx ..< num {
					entries[j + 1] = slot_from_slice(entries_buf[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH]) or_return
				}
				total := num + 1
				left_n := BTREE_SPLIT_COUNT
				right_n := total - left_n
				left := Sorted_Node{kind = .Leaf, num = left_n}
				copy(left.entries[:left_n], entries[:left_n])
				right := Sorted_Node{kind = .Leaf, num = right_n}
				copy(right.entries[:right_n], entries[left_n:total])
				separator: Slot
				if left_n == idx {
					separator = key_slot
				} else {
					separator = sorted_entry_key_slot(db, entries[left_n]) or_return
				}
				left_ptr := sorted_write_node(db, left, cur_ptr, frozen_at) or_return
				right_ptr := write_sorted_node(db, right) or_return
				child = Sorted_Insert_Result{
					node_ptr = left_ptr,
					count    = i64(left_n),
					entry    = entry,
					added    = true,
					split    = Sorted_Split{node_ptr = right_ptr, count = i64(right_n), separator = separator},
				}
				break
			}

			if len(block) < SORTED_BRANCH_BLOCK_SIZE {
				return {}, Xitdb_Error.Unexpected_EOF
			}
			branch_buf := block[BTREE_NODE_HEADER_SIZE:SORTED_BRANCH_BLOCK_SIZE]
			counts_base := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
			total_cnt: i64 = 0
			for k in 0 ..< num {
				raw := endian.unchecked_get_u64be(branch_buf[counts_base + k * 8 : counts_base + (k + 1) * 8])
				if raw > u64(max(i64)) {
					return {}, .Invalid_BTree_Node
				}
				ok: bool
				total_cnt, ok = _checked_add_i64(total_cnt, i64(raw))
				if !ok {
					return {}, .Invalid_BTree_Node
				}
			}
			if total_cnt != cur_exp {
				return {}, .Invalid_BTree_Node
			}
			lo := 1
			hi := num
			sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
			for lo < hi {
				mid := int(uint(lo + hi) >> 1)
				sep_slot := slot_from_slice(branch_buf[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH]) or_return
				c := compare_key(db, sep_slot, key) or_return
				if c <= 0 {
					lo = mid + 1
				} else {
					hi = mid
				}
			}
			i := lo - 1
			child_slot := slot_from_slice(branch_buf[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH]) or_return
			if child_slot.tag != .Index {
				return {}, .Invalid_BTree_Node
			}
			counts_off := counts_base + i * 8
			old_cnt := i64(endian.unchecked_get_u64be(branch_buf[counts_off : counts_off + 8]))
			frames[frame_len] = _BTree_Write_Frame{
				node_ptr  = cur_ptr,
				child_ptr = child_slot.value,
				old_cnt   = old_cnt,
				total_cnt = total_cnt,
				child_idx = u8(i),
				num       = u8(num),
				reusable  = true,
			}
			frame_len += 1
			cur_ptr = child_slot.value
			cur_exp = old_cnt
			cur_depth += 1
			continue
		}

		node := read_sorted_node(db, cur_ptr) or_return
		switch node.kind {
		case .Leaf:
			if i64(node.num) != cur_exp {
				return {}, .Invalid_BTree_Node
			}
			idx, found := sorted_leaf_search(db, &node, key) or_return

			if found {
				if key_only {
					child = Sorted_Insert_Result{
						node_ptr = cur_ptr,
						count    = i64(node.num),
						entry    = node.entries[idx],
						added    = false,
					}
					break
				}
				entry := node.entries[idx]
				if is_key_only_entry(entry) {
					entry = write_sorted_pair(db, entry) or_return
				} else if !btree_reusable(db, entry.value, frozen_at) {
					kv := read_kv_pair(db, entry) or_return
					entry = write_kv_pair(db, entry.tag, kv) or_return
				}
				leaf := node
				leaf.entries[idx] = entry
				ptr := sorted_write_node(db, leaf, cur_ptr, frozen_at) or_return
				child = Sorted_Insert_Result{
					node_ptr = ptr,
					count    = i64(node.num),
					entry    = entry,
					added    = false,
				}
				break
			}

			if !can_add {
				return {}, .Invalid_BTree_Node
			}
			key_slot, entry := write_sorted_key_and_entry(db, key, key_only) or_return
			entries: [BTREE_SLOT_COUNT + 1]Slot
			copy(entries[:idx], node.entries[:idx])
			entries[idx] = entry
			copy(entries[idx + 1 : node.num + 1], node.entries[idx:node.num])
			total := node.num + 1

			if total <= BTREE_SLOT_COUNT {
				leaf := Sorted_Node{kind = .Leaf, num = total}
				copy(leaf.entries[:total], entries[:total])
				ptr := sorted_write_node(db, leaf, cur_ptr, frozen_at) or_return
				child = Sorted_Insert_Result{
					node_ptr = ptr,
					count    = i64(total),
					entry    = entry,
					added    = true,
				}
				break
			}

			left_n := BTREE_SPLIT_COUNT
			right_n := total - left_n
			left := Sorted_Node{kind = .Leaf, num = left_n}
			copy(left.entries[:left_n], entries[:left_n])
			right := Sorted_Node{kind = .Leaf, num = right_n}
			copy(right.entries[:right_n], entries[left_n:total])
			separator: Slot
			if left_n == idx {
				separator = key_slot
			} else {
				separator = sorted_entry_key_slot(db, entries[left_n]) or_return
			}
			left_ptr := sorted_write_node(db, left, cur_ptr, frozen_at) or_return
			right_ptr := write_sorted_node(db, right) or_return
			child = Sorted_Insert_Result{
				node_ptr = left_ptr,
				count    = i64(left_n),
				entry    = entry,
				added    = true,
				split    = Sorted_Split{node_ptr = right_ptr, count = i64(right_n), separator = separator},
			}

		case .Branch:
			if sorted_node_subtree_count(node) != cur_exp {
				return {}, .Invalid_BTree_Node
			}
			i := sorted_branch_search(db, &node, key) or_return
			frames[frame_len] = _BTree_Write_Frame{
				node_ptr  = cur_ptr,
				child_ptr = node.children[i].value,
				old_cnt   = node.counts[i],
				total_cnt = cur_exp,
				child_idx = u8(i),
				num       = u8(node.num),
				reusable  = false,
			}
			frame_len += 1
			cur_ptr = node.children[i].value
			cur_exp = node.counts[i]
			cur_depth += 1
			continue
		}
		break
	}

	for idx := frame_len - 1; idx >= 0; idx -= 1 {
		f := frames[idx]
		i := int(f.child_idx)

		if f.reusable && child.split == nil {
			position := f.node_ptr + BTREE_NODE_HEADER_SIZE
			if child.node_ptr != f.child_ptr {
				child_slot_pos := position + i64(i) * SLOT_LENGTH
				core_seek_to(db.core, child_slot_pos) or_return
				core_write_slot(db.core, Slot{value = child.node_ptr, tag = .Index}) or_return
			}
			branch_cnt := f.total_cnt
			if child.added {
				cnt_added, add_ok := _checked_add_i64(f.old_cnt, 1)
				if !add_ok {
					return {}, .Invalid_BTree_Node
				}
				total_added, total_ok := _checked_add_i64(f.total_cnt, 1)
				if !total_ok {
					return {}, .Invalid_BTree_Node
				}
				branch_cnt = total_added
				count_pos := position + i64(SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + i * 8)
				core_seek_to(db.core, count_pos) or_return
				core_write_i64(db.core, cnt_added) or_return
			}
			child = Sorted_Insert_Result{
				node_ptr = f.node_ptr,
				count    = branch_cnt,
				entry    = child.entry,
				added    = child.added,
			}
			continue
		}

		if !f.reusable && !child.added && child.node_ptr == f.child_ptr {
			child = Sorted_Insert_Result{
				node_ptr = f.node_ptr,
				count    = f.total_cnt,
				entry    = child.entry,
				added    = false,
			}
			continue
		}

		node := read_sorted_node(db, f.node_ptr) or_return
		children: [BTREE_SLOT_COUNT + 1]Slot
		separators: [BTREE_SLOT_COUNT + 1]Slot
		counts: [BTREE_SLOT_COUNT + 1]i64
		copy(children[:node.num], node.children[:node.num])
		copy(separators[:node.num], node.separators[:node.num])
		copy(counts[:node.num], node.counts[:node.num])
		children[i] = Slot{value = child.node_ptr, tag = .Index}
		if child.split != nil {
			counts[i] = child.count
		} else if child.added {
			cnt_added, add_ok := _checked_add_i64(node.counts[i], 1)
			if !add_ok {
				return {}, .Invalid_BTree_Node
			}
			counts[i] = cnt_added
		} else {
			counts[i] = node.counts[i]
		}
		total := node.num
		if split, ok := child.split.?; ok {
			for j := node.num; j > i + 1; j -= 1 {
				children[j] = children[j - 1]
				separators[j] = separators[j - 1]
				counts[j] = counts[j - 1]
			}
			children[i + 1] = Slot{value = split.node_ptr, tag = .Index}
			separators[i + 1] = split.separator
			counts[i + 1] = split.count
			total = node.num + 1
		}

		if total <= BTREE_SLOT_COUNT {
			branch_cnt := _sum_counts_i64(counts[:total]) or_return
			branch := Sorted_Node{kind = .Branch, num = total}
			copy(branch.children[:total], children[:total])
			copy(branch.separators[:total], separators[:total])
			copy(branch.counts[:total], counts[:total])
			ptr := sorted_write_node(db, branch, f.node_ptr, frozen_at) or_return
			child = Sorted_Insert_Result{
				node_ptr = ptr,
				count    = branch_cnt,
				entry    = child.entry,
				added    = child.added,
			}
			continue
		}

		left_n := BTREE_SPLIT_COUNT
		right_n := total - left_n
		left_cnt := _sum_counts_i64(counts[:left_n]) or_return
		right_cnt := _sum_counts_i64(counts[left_n:total]) or_return
		left := Sorted_Node{kind = .Branch, num = left_n}
		copy(left.children[:left_n], children[:left_n])
		copy(left.separators[:left_n], separators[:left_n])
		copy(left.counts[:left_n], counts[:left_n])
		right := Sorted_Node{kind = .Branch, num = right_n}
		copy(right.children[:right_n], children[left_n:total])
		copy(right.separators[:right_n], separators[left_n:total])
		copy(right.counts[:right_n], counts[left_n:total])
		separator := separators[left_n]
		left_ptr := sorted_write_node(db, left, f.node_ptr, frozen_at) or_return
		right_ptr := write_sorted_node(db, right) or_return
		child = Sorted_Insert_Result{
			node_ptr = left_ptr,
			count    = left_cnt,
			entry    = child.entry,
			added    = child.added,
			split    = Sorted_Split{node_ptr = right_ptr, count = right_cnt, separator = separator},
		}
	}

	return child, nil
}

sorted_remove :: proc(db: ^Database, node_ptr: i64, key: []u8, expected, frozen_at: i64, depth: int = 0) -> (res: Sorted_Remove_Result, err: Error) {
	frames: [MAX_BTREE_DEPTH]_BTree_Write_Frame = ---
	frame_len := 0
	cur_ptr := node_ptr
	cur_exp := expected
	cur_depth := depth
	child: Sorted_Remove_Result

	for {
		if cur_depth >= MAX_BTREE_DEPTH {
			return {}, .Invalid_BTree_Node
		}
		if btree_reusable(db, cur_ptr, frozen_at) {
			node_buf: [SORTED_BRANCH_BLOCK_SIZE]u8 = ---
			block := core_read_short_at(db.core, cur_ptr, node_buf[:]) or_return
			if len(block) < SORTED_LEAF_BLOCK_SIZE {
				return {}, Xitdb_Error.Unexpected_EOF
			}
			kind_int := block[0]
			if kind_int > u8(BTree_Node_Kind.Branch) {
				return {}, .Invalid_BTree_Node_Kind
			}
			num := int(block[1])
			if num > BTREE_SLOT_COUNT || (BTree_Node_Kind(kind_int) == .Branch && num == 0) {
				return {}, .Invalid_BTree_Node
			}
			position := cur_ptr + BTREE_NODE_HEADER_SIZE
			if BTree_Node_Kind(kind_int) == .Leaf {
				if i64(num) != cur_exp {
					return {}, .Invalid_BTree_Node
				}
				entries_buf := block[BTREE_NODE_HEADER_SIZE : BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT]
				lo := 0
				hi := num
				found := false
				for lo < hi {
					mid := int(uint(lo + hi) >> 1)
					entry_slot := slot_from_slice(entries_buf[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH]) or_return
					if !is_sorted_entry_tag(entry_slot.tag) {
						return {}, .Invalid_BTree_Node
					}
					key_slot := sorted_entry_key_slot(db, entry_slot) or_return
					cmp := compare_key(db, key_slot, key) or_return
					if cmp == 0 {
						lo = mid
						found = true
						break
					} else if cmp < 0 {
						lo = mid + 1
					} else {
						hi = mid
					}
				}
				if !found {
					return Sorted_Remove_Result{node_ptr = node_ptr, found = false}, nil
				}
				idx := lo
				total := num - 1
				entry_pos := position + i64(idx) * SLOT_LENGTH
				tail_len := (total - idx) * SLOT_LENGTH
				shift_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8
				if tail_len > 0 {
					copy(shift_buf[:tail_len], entries_buf[(idx + 1) * SLOT_LENGTH : num * SLOT_LENGTH])
				}
				core_seek_to(db.core, entry_pos) or_return
				core_write_all(db.core, shift_buf[:tail_len + SLOT_LENGTH]) or_return
				new_hdr := [BTREE_NODE_HEADER_SIZE]u8{kind_int, u8(total)}
				core_seek_to(db.core, cur_ptr) or_return
				core_write_all(db.core, new_hdr[:]) or_return
				child = Sorted_Remove_Result{node_ptr = cur_ptr, found = true}
				break
			}

			if len(block) < SORTED_BRANCH_BLOCK_SIZE {
				return {}, Xitdb_Error.Unexpected_EOF
			}
			branch_buf := block[BTREE_NODE_HEADER_SIZE:SORTED_BRANCH_BLOCK_SIZE]
			counts_base := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
			total_cnt: i64 = 0
			for k in 0 ..< num {
				raw := endian.unchecked_get_u64be(branch_buf[counts_base + k * 8 : counts_base + (k + 1) * 8])
				if raw > u64(max(i64)) {
					return {}, .Invalid_BTree_Node
				}
				ok: bool
				total_cnt, ok = _checked_add_i64(total_cnt, i64(raw))
				if !ok {
					return {}, .Invalid_BTree_Node
				}
			}
			if total_cnt != cur_exp {
				return {}, .Invalid_BTree_Node
			}
			lo := 1
			hi := num
			sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
			for lo < hi {
				mid := int(uint(lo + hi) >> 1)
				sep_slot := slot_from_slice(branch_buf[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH]) or_return
				c := compare_key(db, sep_slot, key) or_return
				if c <= 0 {
					lo = mid + 1
				} else {
					hi = mid
				}
			}
			i := lo - 1
			child_slot := slot_from_slice(branch_buf[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH]) or_return
			if child_slot.tag != .Index {
				return {}, .Invalid_BTree_Node
			}
			old_cnt := i64(endian.unchecked_get_u64be(branch_buf[counts_base + i * 8 : counts_base + (i + 1) * 8]))
			frames[frame_len] = _BTree_Write_Frame{
				node_ptr  = cur_ptr,
				child_ptr = child_slot.value,
				old_cnt   = old_cnt,
				total_cnt = total_cnt,
				child_idx = u8(i),
				num       = u8(num),
				reusable  = true,
			}
			frame_len += 1
			cur_ptr = child_slot.value
			cur_exp = old_cnt
			cur_depth += 1
			continue
		}

		node := read_sorted_node(db, cur_ptr) or_return
		switch node.kind {
		case .Leaf:
			if i64(node.num) != cur_exp {
				return {}, .Invalid_BTree_Node
			}
			idx, found := sorted_leaf_search(db, &node, key) or_return
			if !found {
				return Sorted_Remove_Result{node_ptr = node_ptr, found = false}, nil
			}
			leaf := Sorted_Node{kind = .Leaf, num = node.num - 1}
			copy(leaf.entries[:idx], node.entries[:idx])
			copy(leaf.entries[idx : node.num - 1], node.entries[idx + 1 : node.num])
			ptr := sorted_write_node(db, leaf, cur_ptr, frozen_at) or_return
			child = Sorted_Remove_Result{node_ptr = ptr, found = true}

		case .Branch:
			if sorted_node_subtree_count(node) != cur_exp {
				return {}, .Invalid_BTree_Node
			}
			i := sorted_branch_search(db, &node, key) or_return
			frames[frame_len] = _BTree_Write_Frame{
				node_ptr  = cur_ptr,
				child_ptr = node.children[i].value,
				old_cnt   = node.counts[i],
				total_cnt = cur_exp,
				child_idx = u8(i),
				num       = u8(node.num),
				reusable  = false,
			}
			frame_len += 1
			cur_ptr = node.children[i].value
			cur_exp = node.counts[i]
			cur_depth += 1
			continue
		}
		break
	}

	for idx := frame_len - 1; idx >= 0; idx -= 1 {
		f := frames[idx]
		i := int(f.child_idx)
		if f.reusable {
			if f.old_cnt <= 0 {
				return {}, .Invalid_BTree_Node
			}
			position := f.node_ptr + BTREE_NODE_HEADER_SIZE
			if !(f.old_cnt == 1 && int(f.num) > 1) {
				if child.node_ptr != f.child_ptr {
					child_slot_pos := position + i64(i) * SLOT_LENGTH
					core_seek_to(db.core, child_slot_pos) or_return
					core_write_slot(db.core, Slot{value = child.node_ptr, tag = .Index}) or_return
				}
				count_pos := position + i64(SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + i * 8)
				core_seek_to(db.core, count_pos) or_return
				core_write_i64(db.core, f.old_cnt - 1) or_return
				child = Sorted_Remove_Result{node_ptr = f.node_ptr, found = true}
				continue
			}
			branch := read_sorted_node(db, f.node_ptr) or_return
			copy(branch.children[i : branch.num - 1], branch.children[i + 1 : branch.num])
			copy(branch.separators[i : branch.num - 1], branch.separators[i + 1 : branch.num])
			copy(branch.counts[i : branch.num - 1], branch.counts[i + 1 : branch.num])
			branch.num -= 1
			branch.children[branch.num] = Slot{}
			branch.separators[branch.num] = Slot{}
			branch.counts[branch.num] = 0
			branch.separators[0] = Slot{}
			ptr := sorted_write_node(db, branch, f.node_ptr, frozen_at) or_return
			child = Sorted_Remove_Result{node_ptr = ptr, found = true}
			continue
		}

		branch := read_sorted_node(db, f.node_ptr) or_return
		if branch.counts[i] <= 0 {
			return {}, .Invalid_BTree_Node
		}
		if branch.counts[i] == 1 && branch.num > 1 {
			copy(branch.children[i : branch.num - 1], branch.children[i + 1 : branch.num])
			copy(branch.separators[i : branch.num - 1], branch.separators[i + 1 : branch.num])
			copy(branch.counts[i : branch.num - 1], branch.counts[i + 1 : branch.num])
			branch.num -= 1
			branch.children[branch.num] = Slot{}
			branch.separators[branch.num] = Slot{}
			branch.counts[branch.num] = 0
			branch.separators[0] = Slot{}
		} else {
			branch.children[i] = Slot{value = child.node_ptr, tag = .Index}
			branch.counts[i] -= 1
		}
		ptr := sorted_write_node(db, branch, f.node_ptr, frozen_at) or_return
		child = Sorted_Remove_Result{node_ptr = ptr, found = true}
	}

	return child, nil
}

sorted_grow_root :: proc(db: ^Database, result: Sorted_Insert_Result) -> (res: i64, err: Error) {
	if split, ok := result.split.?; ok {
		root := Sorted_Node{kind = .Branch, num = 2}
		root.children[0] = Slot{value = result.node_ptr, tag = .Index}
		root.children[1] = Slot{value = split.node_ptr, tag = .Index}
		root.separators[1] = split.separator
		root.counts[0] = result.count
		root.counts[1] = split.count
		return write_sorted_node(db, root)
	}
	return result.node_ptr, nil
}

sorted_target_slot :: proc(db: ^Database, entry: Slot, target: Sorted_Map_Get_Target) -> (res: Slot_Pointer, err: Error) {
	switch _ in target {
	case Sorted_Map_Get_KV_Pair:
		return Slot_Pointer{position = nil, slot = entry}, nil
	case Sorted_Map_Get_Key:
		key_slot := sorted_entry_key_slot(db, entry) or_return
		return Slot_Pointer{position = nil, slot = key_slot}, nil
	case Sorted_Map_Get_Value:
		if is_key_only_entry(entry) {
			return Slot_Pointer{position = nil, slot = Slot{}}, nil
		}
		pos_maybe := database_kv_value_position(db, entry) or_return
		pos, has_pos := pos_maybe.?
		if !has_pos {
			return {}, .Unexpected_Tag
		}
		val_slot := core_read_slot_at(db.core, pos) or_return
		return Slot_Pointer{position = pos, slot = val_slot}, nil
	}
	return {}, .Unexpected_Tag
}
