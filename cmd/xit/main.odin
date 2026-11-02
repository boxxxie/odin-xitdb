package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"
import xitdb "../../xitdb"

main :: proc() {
	args := os.args[1:]
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
		print_usage()
		return
	}

	// Interactive REPL with in-memory database: `xit --memory`
	if args[0] == "--memory" || args[0] == "-m" {
		core := xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, err := xitdb.database_init(&core, xitdb.sha1_hasher())
		if err != nil {
			fmt.eprintf("Failed to init in-memory database: %v\n", err)
			os.exit(1)
		}
		run_repl(&db, ":memory:")
		return
	}

	// Subcommand mode vs. `xit <db_path>` interactive REPL mode
	cmd := args[0]
	switch cmd {
	case "status", "moments", "get", "pull", "query", "tx", "diff", "history", "compact":
		if len(args) < 2 {
			fmt.eprintf("Missing database file path for '%s'\n", cmd)
			print_usage()
			os.exit(1)
		}
		run_subcommand(cmd, args[1], args[2:])

	case "repl":
		if len(args) < 2 {
			fmt.eprintln("Usage: xit repl <db.xit>")
			os.exit(1)
		}
		open_and_run_repl(args[1])

	case:
		// Treat first argument as database file path and launch interactive REPL
		open_and_run_repl(args[0])
	}
}

open_and_run_repl :: proc(db_path: string) {
	core, open_err := xitdb.core_buffered_file_open(db_path)
	if open_err != nil {
		fmt.eprintf("Failed to open %s: %v\n", db_path, open_err)
		os.exit(1)
	}
	defer xitdb.core_destroy(&core, close_file = true)

	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	if init_err != nil {
		fmt.eprintf("Failed to initialize database %s: %v\n", db_path, init_err)
		os.exit(1)
	}

	run_repl(&db, db_path)
}

run_subcommand :: proc(cmd: string, db_path: string, rest: []string) {
	core, open_err := xitdb.core_buffered_file_open(db_path)
	if open_err != nil {
		fmt.eprintf("Failed to open %s: %v\n", db_path, open_err)
		os.exit(1)
	}
	defer xitdb.core_destroy(&core, close_file = true)

	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	if init_err != nil {
		fmt.eprintf("Failed to initialize %s: %v\n", db_path, init_err)
		os.exit(1)
	}

	switch cmd {
	case "status":
		exec_status(&db, db_path)

	case "moments":
		exec_moments(&db)

	case "get":
		if len(rest) < 1 {
			fmt.eprintln("Usage: xit get <db.xit> '<selector>'")
			os.exit(1)
		}
		exec_selector(&db, rest[0])

	case "pull":
		if len(rest) == 1 {
			exec_pull(&db, -1, rest[0])
		} else if len(rest) >= 2 {
			m_idx := parse_moment_arg(rest[0])
			exec_pull(&db, m_idx, rest[1])
		} else {
			fmt.eprintln("Usage: xit pull <db.xit> [@moment] '<pattern>'")
			os.exit(1)
		}

	case "query":
		if len(rest) < 1 {
			fmt.eprintln("Usage: xit query <db.xit> '<find ... where ...>'")
			os.exit(1)
		}
		exec_datalog(&db, strings.join(rest, " ", context.temp_allocator))

	case "tx":
		if len(rest) < 1 {
			fmt.eprintln("Usage: xit tx <db.xit> '<script_or_file>'")
			os.exit(1)
		}
		script := load_script_or_inline(rest[0])
		exec_tx(&db, script)

	case "diff":
		if len(rest) < 2 {
			fmt.eprintln("Usage: xit diff <db.xit> <moment_a> <moment_b>")
			os.exit(1)
		}
		ma := parse_moment_arg(rest[0])
		mb := parse_moment_arg(rest[1])
		exec_diff(&db, ma, mb)

	case "history":
		if len(rest) < 1 {
			fmt.eprintln("Usage: xit history <db.xit> '<path_selector>'")
			os.exit(1)
		}
		exec_history(&db, rest[0])

	case "compact":
		if len(rest) < 1 {
			fmt.eprintln("Usage: xit compact <src.xit> <dst.xit>")
			os.exit(1)
		}
		exec_compact(&db, rest[0])
	}
}

// ============================================================================
// Interactive REPL
// ============================================================================

run_repl :: proc(db: ^xitdb.Database, label: string) {
	fmt.printf("xitdb interactive shell (%s)\n", label)
	fmt.println("Type .help for commands, or enter a selector (@-1.key), pull {...}, find ... where ..., or branch @-1 { ... }")

	line_buf := make([dynamic]u8, 0, 1024)
	defer delete(line_buf)

	script_accum := strings.builder_make()
	defer strings.builder_destroy(&script_accum)
	brace_depth := 0

	for {
		free_all(context.temp_allocator)
		if brace_depth > 0 {
			fmt.print("  ... > ")
		} else {
			fmt.print("xitdb> ")
		}

		line, eof := read_stdin_line(&line_buf)
		if eof && len(line) == 0 {
			fmt.println()
			break
		}

		trimmed := strings.trim_space(line)
		if brace_depth > 0 {
			strings.write_string(&script_accum, line)
			strings.write_byte(&script_accum, '\n')
			brace_depth += count_brace_delta(trimmed)
			if brace_depth <= 0 {
				brace_depth = 0
				full_script := strings.to_string(script_accum)
				eval_repl_input(db, label, full_script)
				strings.builder_reset(&script_accum)
			}
			continue
		}

		if len(trimmed) == 0 {
			continue
		}

		delta := count_brace_delta(trimmed)
		if delta > 0 && (strings.has_prefix(trimmed, "branch ") || strings.has_prefix(trimmed, "find ")) {
			brace_depth = delta
			strings.write_string(&script_accum, line)
			strings.write_byte(&script_accum, '\n')
			continue
		}

		if trimmed == ".quit" || trimmed == ".exit" || trimmed == "quit" || trimmed == "exit" {
			break
		}

		eval_repl_input(db, label, trimmed)
	}
}

eval_repl_input :: proc(db: ^xitdb.Database, label: string, input: string) {
	s := strings.trim_space(input)
	if len(s) == 0 {
		return
	}

	if s == ".help" || s == "help" {
		print_repl_help()
		return
	}
	if s == ".status" || s == "status" {
		exec_status(db, label)
		return
	}
	if s == ".moments" || s == "moments" {
		exec_moments(db)
		return
	}
	if strings.has_prefix(s, ".compact ") {
		target := strings.trim_space(strings.trim_prefix(s, ".compact "))
		exec_compact(db, target)
		return
	}
	if strings.has_prefix(s, "diff ") {
		parts := strings.fields(s[5:], context.temp_allocator)
		if len(parts) != 2 {
			fmt.eprintln("Usage: diff <moment_a> <moment_b>")
			return
		}
		exec_diff(db, parse_moment_arg(parts[0]), parse_moment_arg(parts[1]))
		return
	}
	if strings.has_prefix(s, "history ") {
		path_str := strings.trim_space(strings.trim_prefix(s, "history "))
		exec_history(db, path_str)
		return
	}
	if strings.has_prefix(s, "pull ") {
		rest := strings.trim_space(strings.trim_prefix(s, "pull "))
		if strings.has_prefix(rest, "@") {
			sp := strings.index_byte(rest, ' ')
			if sp > 0 {
				m_idx := parse_moment_arg(rest[:sp])
				exec_pull(db, m_idx, strings.trim_space(rest[sp + 1:]))
				return
			}
		}
		exec_pull(db, -1, rest)
		return
	}
	if strings.has_prefix(s, "find ") {
		exec_datalog(db, s)
		return
	}
	if strings.has_prefix(s, "branch ") || strings.has_prefix(s, "put ") || strings.has_prefix(s, "doc ") {
		exec_tx(db, s)
		return
	}

	// Default: evaluate as Layer 1 path selector
	exec_selector(db, s)
}

// ============================================================================
// Command Executors
// ============================================================================

exec_status :: proc(db: ^xitdb.Database, label: string) {
	committed, c_err := xitdb.database_committed_size(db)
	if c_err != nil {
		fmt.eprintf("Error reading committed size: %v\n", c_err)
		return
	}
	rc := xitdb.database_root_cursor(db).read_cursor
	root_slot, _ := xitdb.cursor_slot(rc)

	hash_id_bytes := xitdb.id_to_bytes(db.header.hash_id)
	fmt.printf("Database:       %s\n", label)
	fmt.printf("Format Version: v%d (magic=%q)\n", db.header.version, string(db.header.magic_number[:]))
	fmt.printf("Hasher:         %s (%d-byte digest, file_id=0x%016x)\n", string(hash_id_bytes[:]), db.header.hash_size, db.header.file_id)
	fmt.printf("Committed Size: %d bytes\n", committed)
	fmt.printf("Root Tag:       %v\n", root_slot.tag)

	if root_slot.tag == .Array_List {
		hist, err := xitdb.read_array_list_init(rc)
		if err == nil {
			cnt, _ := xitdb.array_list_count(hist)
			fmt.printf("Moments:        %d\n", cnt)
		}
	}
}

exec_moments :: proc(db: ^xitdb.Database) {
	rc := xitdb.database_root_cursor(db).read_cursor
	hist, err := xitdb.read_array_list_init(rc)
	if err != nil {
		fmt.eprintf("Root is not an Array_List of moments: %v\n", err)
		return
	}
	cnt, _ := xitdb.array_list_count(hist)
	fmt.printf("Total Moments: %d\n", cnt)
	for i: i64 = 0; i < cnt; i += 1 {
		mc_maybe, _ := xitdb.array_list_get_cursor(hist, i)
		mc, ok := mc_maybe.?
		if !ok {
			continue
		}
		m_slot, _ := xitdb.cursor_slot(mc)
		doc_str, _ := xitdb.get_string(db, fmt.tprintf("@%d.__tx.doc", i))
		author_str, _ := xitdb.get_string(db, fmt.tprintf("@%d.__tx.author", i))
		inst_val, _ := xitdb.get_int(db, fmt.tprintf("@%d.__tx.tx_instant", i))

		fmt.printf("  @%-4d | offset=%-8d", i, m_slot.value)
		if len(author_str) > 0 {
			fmt.printf(" | author=%s", author_str)
		}
		if inst_val != 0 {
			fmt.printf(" | instant=%d", inst_val)
		}
		if len(doc_str) > 0 {
			fmt.printf(" | %q", doc_str)
		}
		fmt.println()
	}
}

exec_selector :: proc(db: ^xitdb.Database, selector: string) {
	cur_maybe, err := xitdb.select_cursor(db, selector)
	if err != nil {
		fmt.eprintf("Selector error: %v\n", err)
		return
	}
	cur, ok := cur_maybe.?
	if !ok {
		fmt.println("(nil)")
		return
	}
	pv, p_err := xitdb.pull(cur, "*", context.temp_allocator)
	if p_err != nil {
		fmt.eprintf("Read error: %v\n", p_err)
		return
	}
	print_pull_value(pv, 0)
	fmt.println()
}

exec_pull :: proc(db: ^xitdb.Database, moment_idx: i64, pattern: string) {
	rc := xitdb.database_root_cursor(db).read_cursor
	root_slot, _ := xitdb.cursor_slot(rc)
	target_cur := rc
	if root_slot.tag == .Array_List {
		hist, err := xitdb.read_array_list_init(rc)
		if err != nil {
			fmt.eprintf("Error: %v\n", err)
			return
		}
		mc_maybe, mc_err := xitdb.array_list_get_cursor(hist, moment_idx)
		if mc_err != nil || mc_maybe == nil {
			fmt.eprintf("Moment @%d not found\n", moment_idx)
			return
		}
		target_cur = mc_maybe.?
	}

	pv, err := xitdb.pull(target_cur, pattern, context.temp_allocator)
	if err != nil {
		fmt.eprintf("Pull error: %v\n", err)
		return
	}
	print_pull_value(pv, 0)
	fmt.println()
}

exec_datalog :: proc(db: ^xitdb.Database, query_str: string) {
	res, err := xitdb.query_datalog(db, query_str, -1, context.temp_allocator)
	if err != nil {
		fmt.eprintf("Datalog error: %v\n", err)
		return
	}
	print_datalog_table(res)
}

exec_tx :: proc(db: ^xitdb.Database, script: string) {
	rep, err := xitdb.transact_script(db, script, context.temp_allocator)
	if err != nil {
		fmt.eprintf("Transaction failed: %v\n", err)
		return
	}
	fmt.printf("Committed Moment @%d (committed_size=%d bytes, %d changes)\n", rep.moment_index, rep.commit_size, len(rep.changes))
	for chg in rep.changes {
		fmt.printf("  %-7v %-32s (%v -> %v)\n", chg.op, chg.path_str, chg.old_slot.tag, chg.new_slot.tag)
	}
}

exec_diff :: proc(db: ^xitdb.Database, moment_a, moment_b: i64) {
	diffs, err := xitdb.diff_moments(db, moment_a, moment_b, false, context.temp_allocator)
	if err != nil {
		fmt.eprintf("Diff error: %v\n", err)
		return
	}
	fmt.printf("Diff @%d -> @%d (%d changes):\n", moment_a, moment_b, len(diffs))
	for d in diffs {
		fmt.printf("  %-7v %-32s (%v -> %v)\n", d.op, d.path_str, d.old_slot.tag, d.new_slot.tag)
	}
}

exec_history :: proc(db: ^xitdb.Database, path_selector: string) {
	entries, err := xitdb.history_of(db, path_selector, context.temp_allocator)
	if err != nil {
		fmt.eprintf("History error: %v\n", err)
		return
	}
	fmt.printf("Lineage of %s (%d mutations):\n", path_selector, len(entries))
	for e in entries {
		val_str := "(removed)"
		if c, ok := e.cursor.?; ok {
			pv, _ := xitdb.pull(c, "*", context.temp_allocator)
			val_str = format_pull_inline(pv)
		}
		fmt.printf("  @%-4d | %-20s | (%v -> %v)", e.moment_index, val_str, e.old_slot.tag, e.new_slot.tag)
		if e.tx_instant != 0 {
			fmt.printf(" | instant=%d", e.tx_instant)
		}
		if len(e.tx_doc) > 0 {
			fmt.printf(" | %q", e.tx_doc)
		}
		fmt.println()
	}
}

exec_compact :: proc(db: ^xitdb.Database, target_path: string) {
	before_size, _ := xitdb.database_committed_size(db)
	target_core, open_err := xitdb.core_file_open(target_path, {.Read, .Write, .Create, .Trunc})
	if open_err != nil {
		fmt.eprintf("Failed to open target file %s: %v\n", target_path, open_err)
		return
	}
	defer xitdb.core_destroy(&target_core, close_file = true)

	comp_db, comp_err := xitdb.database_compact(db, &target_core)
	if comp_err != nil {
		fmt.eprintf("Compaction failed: %v\n", comp_err)
		return
	}
	after_size, _ := xitdb.database_committed_size(&comp_db)
	fmt.printf("Compacted into %s: %d bytes -> %d bytes\n", target_path, before_size, after_size)
}

// ============================================================================
// Formatting & Input Helpers
// ============================================================================

print_datalog_table :: proc(res: xitdb.Datalog_Result) {
	if len(res.vars) == 0 {
		return
	}
	widths := make([]int, len(res.vars), context.temp_allocator)
	for v, i in res.vars {
		widths[i] = len(v)
	}
	formatted_rows := make([][]string, len(res.rows), context.temp_allocator)
	for row, r_idx in res.rows {
		frow := make([]string, len(res.vars), context.temp_allocator)
		for cell, c_idx in row {
			s := format_pull_inline(cell)
			frow[c_idx] = s
			if len(s) > widths[c_idx] {
				widths[c_idx] = len(s)
			}
		}
		formatted_rows[r_idx] = frow
	}

	// Header
	for v, i in res.vars {
		if i > 0 {
			fmt.print(" | ")
		}
		fmt.printf("%-*s", widths[i], v)
	}
	fmt.println()

	// Divider
	for w, i in widths {
		if i > 0 {
			fmt.print("-+-")
		}
		for _ in 0 ..< w {
			fmt.print("-")
		}
	}
	fmt.println()

	// Rows
	for frow in formatted_rows {
		for cell, i in frow {
			if i > 0 {
				fmt.print(" | ")
			}
			fmt.printf("%-*s", widths[i], cell)
		}
		fmt.println()
	}
	fmt.printf("(%d rows)\n", len(res.rows))
}

format_pull_inline :: proc(pv: xitdb.Pull_Value) -> string {
	switch v in pv {
	case nil:
		return "nil"
	case u64:
		return fmt.tprintf("%du", v)
	case i64:
		return fmt.tprintf("%d", v)
	case f64:
		return fmt.tprintf("%g", v)
	case string:
		return fmt.tprintf("%q", v)
	case xitdb.Bytes:
		if len(v.format_tag) > 0 {
			return fmt.tprintf("%q^^%s", string(v.value), string(v.format_tag))
		}
		return fmt.tprintf("%q", string(v.value))
	case xitdb.Pull_List:
		b := strings.builder_make(context.temp_allocator)
		strings.write_byte(&b, '[')
		for elem, i in v {
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			strings.write_string(&b, format_pull_inline(elem))
		}
		strings.write_byte(&b, ']')
		return strings.to_string(b)
	case xitdb.Pull_Map:
		b := strings.builder_make(context.temp_allocator)
		strings.write_byte(&b, '{')
		for entry, i in v {
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			fmt.sbprintf(&b, "%s: %s", entry.key, format_pull_inline(entry.val))
		}
		strings.write_byte(&b, '}')
		return strings.to_string(b)
	}
	return "nil"
}

print_pull_value :: proc(pv: xitdb.Pull_Value, indent: int) {
	#partial switch v in pv {
	case xitdb.Pull_Map:
		if len(v) == 0 {
			fmt.print("{}")
			return
		}
		fmt.println("{")
		for entry in v {
			print_indent(indent + 2)
			fmt.printf("%s: ", entry.key)
			print_pull_value(entry.val, indent + 2)
			fmt.println()
		}
		print_indent(indent)
		fmt.print("}")
	case xitdb.Pull_List:
		fmt.print(format_pull_inline(pv))
	case:
		fmt.print(format_pull_inline(pv))
	}
}

print_indent :: proc(spaces: int) {
	for _ in 0 ..< spaces {
		fmt.print(" ")
	}
}

parse_moment_arg :: proc(arg: string) -> i64 {
	s := strings.trim_prefix(strings.trim_space(arg), "@")
	v, ok := strconv.parse_i64(s)
	if !ok {
		return -1
	}
	return v
}

load_script_or_inline :: proc(arg: string) -> string {
	data, err := os.read_entire_file(arg, context.temp_allocator)
	if err == nil {
		return string(data)
	}
	return arg
}

count_brace_delta :: proc(line: string) -> int {
	in_quotes := false
	delta := 0
	for i in 0 ..< len(line) {
		ch := line[i]
		if ch == '"' {
			in_quotes = !in_quotes
		} else if !in_quotes {
			if ch == '{' {
				delta += 1
			} else if ch == '}' {
				delta -= 1
			}
		}
	}
	return delta
}

read_stdin_line :: proc(buf: ^[dynamic]u8) -> (line: string, eof: bool) {
	clear(buf)
	one: [1]u8
	for {
		n, err := os.read(os.stdin, one[:])
		if n > 0 {
			if one[0] == '\n' {
				break
			}
			if one[0] != '\r' {
				append(buf, one[0])
			}
		}
		if err != nil {
			if err == io.Error.EOF {
				return string(buf[:]), true
			}
			return string(buf[:]), true
		}
		if n == 0 {
			return string(buf[:]), true
		}
	}
	return string(buf[:]), false
}

print_usage :: proc() {
	fmt.println(`xit — CLI & Interactive REPL for xitdb

Usage:
  odin run cmd/xit -- <db.xit>                         Launch interactive REPL on <db.xit>
  odin run cmd/xit -- --memory                         Launch interactive REPL in memory
  odin run cmd/xit -- status  <db.xit>                 Inspect header, size, and moment count
  odin run cmd/xit -- moments <db.xit>                 List all moments and __tx commit metadata
  odin run cmd/xit -- get     <db.xit> '<selector>'    Read value at path (e.g. '@-1.users["101"].age')
  odin run cmd/xit -- pull    <db.xit> [@m] '<pat>'    Run Datomic pull projection (e.g. '{users}')
  odin run cmd/xit -- query   <db.xit> '<datalog>'     Run Datalog query ('find ?id, ?name where ...')
  odin run cmd/xit -- tx      <db.xit> '<script|file>' Commit a transaction script block
  odin run cmd/xit -- diff    <db.xit> <m_a> <m_b>     Show O(1) structural diff between two moments
  odin run cmd/xit -- history <db.xit> '<path>'        Show mutation lineage of a path across moments
  odin run cmd/xit -- compact <src.xit> <dst.xit>      Compact database into a fresh file`)
}

print_repl_help :: proc() {
	fmt.println(`REPL Commands:
  .status                        Show database header, size, and moment count
  .moments                       List all historical moments with __tx metadata
  .compact <dst.xit>             Compact database into <dst.xit>
  .quit / .exit                  Exit the shell

DSL Expressions:
  @-1.users["101"].age           Evaluate a Layer 1 path selector
  pull @-1 {users}               Evaluate a Layer 3 Datomic pull pattern
  diff 0 1                       Run Layer 4 structural diff between Moment 0 and Moment 1
  history .users["101"].age      Run Layer 4 temporal lineage for a path
  find ?id, ?name where ...      Run a Layer 5 Datalog query (with B+Tree pushdown, aggs, reach)
  branch @-1 { ... }             Execute a Layer 2 transaction block (multi-line supported)`)
}
