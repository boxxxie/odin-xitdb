const std = @import("std");
const xitdb = @import("xitdb");

const HashInt = u160;
const Sha256Int = u256;

const BenchResult = struct {
    name: []const u8,
    ops: usize,
    elapsed_ns: i96,
    bytes_used: u64 = 0,
};

fn printHeader(stdout: *std.Io.Writer) !void {
    try stdout.writeAll("========================================================================================================\n");
    try stdout.print("{s:<48} | {s:>8} | {s:>10} | {s:>12} | {s:>12}\n", .{ "Benchmark", "Ops", "Total (ms)", "ns/op", "ops/sec" });
    try stdout.writeAll("--------------------------------------------------------------------------------------------------------\n");
}

fn printResult(stdout: *std.Io.Writer, r: BenchResult) !void {
    const total_ns: f64 = @floatFromInt(@max(r.elapsed_ns, 0));
    const total_ms = total_ns / 1e6;
    const ops_f: f64 = @floatFromInt(@max(r.ops, 1));
    const ns_per_op = total_ns / ops_f;
    const ops_per_sec = (@as(f64, @floatFromInt(r.ops)) * 1e9) / @max(total_ns, 1.0);
    if (r.bytes_used > 0) {
        const kb = @as(f64, @floatFromInt(r.bytes_used)) / 1024.0;
        try stdout.print(
            "{s:<48} | {d:>8} | {d:>10.2} | {d:>12.0} | {d:>12.0}  ({d:.1} KB)\n",
            .{ r.name, r.ops, total_ms, ns_per_op, ops_per_sec, kb },
        );
    } else {
        try stdout.print(
            "{s:<48} | {d:>8} | {d:>10.2} | {d:>12.0} | {d:>12.0}\n",
            .{ r.name, r.ops, total_ms, ns_per_op, ops_per_sec },
        );
    }
    try stdout.flush();
}

inline fn hashSha1(data: []const u8) HashInt {
    var digest: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(data, &digest, .{});
    return std.mem.readInt(HashInt, &digest, .big);
}

inline fn hashSha256(data: []const u8) Sha256Int {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    return std.mem.readInt(Sha256Int, &digest, .big);
}

// ----------------------------------------------------------------------------
// 1. HAMT (`Hash_Map`) Bulk Insert, Point Lookup & Branched Moment Commits
// ----------------------------------------------------------------------------

fn benchHamt(io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.Writer, n: usize) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp = arena.allocator();

    var buffer = std.Io.Writer.Allocating.init(allocator);
    defer buffer.deinit();

    const DB = xitdb.Database(.memory, HashInt);
    var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
    const history = try DB.ArrayList(.read_write).init(db.rootCursor());

    const keys = try temp.alloc([]const u8, n);
    for (0..n) |i| {
        keys[i] = try std.fmt.allocPrint(temp, "user-key-{d:0>6}", .{i});
    }

    // 1a. Bulk insert N keys in a single moment transaction
    const InsertCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const m = try DB.HashMap(.read_write).init(cursor.*);
            for (self.keys, 0..) |k, idx| {
                const h = hashSha1(k);
                try m.putKey(h, .{ .bytes = k });
                try m.put(h, .{ .uint = @intCast(idx) });
            }
        }
    };

    const t0 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = .{} }, InsertCtx{ .keys = keys });
    const elapsed_insert = t0.untilNow(io, .awake).nanoseconds;
    const size_after_insert = try db.committedSize();

    try printResult(stdout, .{
        .name = "HAMT Hash_Map bulk put (1 tx)",
        .ops = n,
        .elapsed_ns = elapsed_insert,
        .bytes_used = size_after_insert,
    });

    // 1b. Point lookup N keys from Moment 0 (with SHA-1 key hashing vs pre-computed digest)
    const m0_cur = (try history.getCursor(0)).?;
    const m0 = try DB.HashMap(.read_only).init(m0_cur);

    const t1 = std.Io.Clock.awake.now(io);
    for (keys, 0..) |k, idx| {
        const vc = (try m0.getCursor(hashSha1(k))).?;
        const v = try vc.readUint();
        std.debug.assert(v == @as(u64, @intCast(idx)));
    }
    const elapsed_get = t1.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT Hash_Map point lookup (with SHA-1)",
        .ops = n,
        .elapsed_ns = elapsed_get,
    });

    const digests = try temp.alloc(HashInt, n);
    for (keys, 0..) |k, idx| {
        digests[idx] = hashSha1(k);
    }

    const t1_pre = std.Io.Clock.awake.now(io);
    for (digests, 0..) |d, idx| {
        const vc = (try m0.getCursor(d)).?;
        const v = try vc.readUint();
        std.debug.assert(v == @as(u64, @intCast(idx)));
    }
    const elapsed_get_pre = t1_pre.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT Hash_Map lookup (pre-hashed digest)",
        .ops = n,
        .elapsed_ns = elapsed_get_pre,
    });

    // 1c. Incremental branched moments (CoW structural sharing on 500 commits)
    const branch_commits: usize = 500;
    const BranchCtx = struct {
        key: []const u8,
        val: u64,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const m = try DB.HashMap(.read_write).init(cursor.*);
            const h = hashSha1(self.key);
            try m.putKey(h, .{ .bytes = self.key });
            try m.put(h, .{ .uint = self.val });
        }
    };

    const t2 = std.Io.Clock.awake.now(io);
    for (0..branch_commits) |i| {
        const prev_slot = (try history.getSlot(-1)).?;
        try history.appendContext(.{ .slot = prev_slot }, BranchCtx{
            .key = keys[i % keys.len],
            .val = @intCast(n + i),
        });
    }
    const elapsed_branch = t2.untilNow(io, .awake).nanoseconds;
    const size_after_branch = try db.committedSize();

    try printResult(stdout, .{
        .name = "HAMT CoW branched moment commits",
        .ops = branch_commits,
        .elapsed_ns = elapsed_branch,
        .bytes_used = size_after_branch - size_after_insert,
    });

    // 1d. HAMT key removal & branch shortening (remove half of the keys in 1 tx)
    const remove_count = n / 2;
    const RemoveHamtCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const m = try DB.HashMap(.read_write).init(cursor.*);
            for (self.keys) |k| {
                _ = try m.remove(hashSha1(k));
            }
        }
    };

    const m0_slot = (try history.getSlot(0)).?;
    const t3 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = m0_slot }, RemoveHamtCtx{ .keys = keys[0..remove_count] });
    const elapsed_rem = t3.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT Hash_Map remove & branch shortening",
        .ops = remove_count,
        .elapsed_ns = elapsed_rem,
    });

    // 1e. HAMT unordered full-tree iterator scan
    const t4 = std.Io.Clock.awake.now(io);
    var hit = try m0.iterator();
    var hcnt: usize = 0;
    while (try hit.next()) |_| {
        hcnt += 1;
    }
    std.debug.assert(hcnt == n);
    const elapsed_hiter = t4.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT Hash_Map unordered iterator scan",
        .ops = n,
        .elapsed_ns = elapsed_hiter,
    });

    // 1f. HAMT in-place key overwrite (same tx, updating existing value slots)
    const OverwriteHamtCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const m = try DB.HashMap(.read_write).init(cursor.*);
            for (self.keys, 0..) |k, idx| {
                const h = hashSha1(k);
                try m.putKey(h, .{ .bytes = k });
                try m.put(h, .{ .uint = @intCast(idx + 1_000_000) });
            }
        }
    };

    const t5 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = m0_slot }, OverwriteHamtCtx{ .keys = keys });
    const elapsed_overwrite = t5.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT Hash_Map in-place overwrite (1 tx)",
        .ops = n,
        .elapsed_ns = elapsed_overwrite,
    });

    // 1g. Counted_Hash_Map bulk put + O(1) count tracking vs remove
    const CountedPutCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const cm = try DB.CountedHashMap(.read_write).init(cursor.*);
            for (self.keys, 0..) |k, idx| {
                const h = hashSha1(k);
                try cm.putKey(h, .{ .bytes = k });
                try cm.put(h, .{ .uint = @intCast(idx) });
            }
        }
    };

    const t6 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = .{} }, CountedPutCtx{ .keys = keys });
    const elapsed_cput = t6.untilNow(io, .awake).nanoseconds;

    const cm_slot = (try history.getSlot(-1)).?;
    const cm_cur = (try history.getCursor(-1)).?;
    const rcm = try DB.CountedHashMap(.read_only).init(cm_cur);
    const cm_cnt = try rcm.count();
    std.debug.assert(cm_cnt == @as(u64, @intCast(n)));

    try printResult(stdout, .{
        .name = "HAMT Counted_Hash_Map bulk put (1 tx)",
        .ops = n,
        .elapsed_ns = elapsed_cput,
    });

    const CountedRemCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const cm = try DB.CountedHashMap(.read_write).init(cursor.*);
            for (self.keys) |k| {
                _ = try cm.remove(hashSha1(k));
            }
        }
    };

    const t7 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = cm_slot }, CountedRemCtx{ .keys = keys[0..remove_count] });
    const elapsed_crem = t7.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT Counted_Hash_Map remove",
        .ops = remove_count,
        .elapsed_ns = elapsed_crem,
    });

    // 1h. HAMT deep suffix-collision splitting (10 shared trailing nibbles = 5 bytes) & collapse
    const coll_n: usize = 500;
    const coll_hashes = try temp.alloc(HashInt, coll_n);
    for (0..coll_n) |i| {
        var h: [20]u8 = @splat(0);
        // Share lower 5 bytes (10 trailing nibbles) so every pair collides to depth >= 10
        h[19] = 0xAA;
        h[18] = 0xBB;
        h[17] = 0xCC;
        h[16] = 0xDD;
        h[15] = 0xEE;
        // Vary bytes 14..0
        h[14] = @intCast(i & 0xFF);
        h[13] = @intCast((i >> 8) & 0xFF);
        h[12] = @intCast((i * 73) & 0xFF);
        coll_hashes[i] = std.mem.readInt(HashInt, &h, .big);
    }

    const CollPutCtx = struct {
        hashes: []const HashInt,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const m = try DB.HashMap(.read_write).init(cursor.*);
            for (self.hashes, 0..) |h, idx| {
                try m.putKey(h, .{ .uint = @intCast(idx) });
                try m.put(h, .{ .uint = @intCast(idx) });
            }
        }
    };

    const t8 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = .{} }, CollPutCtx{ .hashes = coll_hashes });
    const elapsed_coll_put = t8.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT deep suffix-collision put (depth 10+)",
        .ops = coll_n,
        .elapsed_ns = elapsed_coll_put,
    });

    const coll_slot = (try history.getSlot(-1)).?;

    const CollRemCtx = struct {
        hashes: []const HashInt,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const m = try DB.HashMap(.read_write).init(cursor.*);
            for (self.hashes) |h| {
                _ = try m.remove(h);
            }
        }
    };

    const t9 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = coll_slot }, CollRemCtx{ .hashes = coll_hashes });
    const elapsed_coll_rem = t9.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT deep suffix-collision branch collapse",
        .ops = coll_n,
        .elapsed_ns = elapsed_coll_rem,
    });

    // 1i. Counted_Hash_Set key-only put (`Hash_Map_Get_Key` with `if_empty = true`) & lookup
    const CSetPutCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const cs = try DB.CountedHashSet(.read_write).init(cursor.*);
            for (self.keys) |k| {
                try cs.put(hashSha1(k), .{ .bytes = k });
            }
        }
    };

    const t10 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = .{} }, CSetPutCtx{ .keys = keys });
    const elapsed_cset_put = t10.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT Counted_Hash_Set key-only put (1 tx)",
        .ops = n,
        .elapsed_ns = elapsed_cset_put,
    });

    const cset_cur = (try history.getCursor(-1)).?;
    const rcset = try DB.CountedHashSet(.read_only).init(cset_cur);
    const cset_cnt = try rcset.count();
    std.debug.assert(cset_cnt == @as(u64, @intCast(n)));

    const t11 = std.Io.Clock.awake.now(io);
    for (keys) |k| {
        const kc = try rcset.getCursor(hashSha1(k));
        std.debug.assert(kc != null);
    }
    const elapsed_cset_get = t11.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "HAMT Counted_Hash_Set membership check",
        .ops = n,
        .elapsed_ns = elapsed_cset_get,
    });
}

// ----------------------------------------------------------------------------
// 2. Radix Trie (`Array_List`) vs Count-Augmented B-Tree (`Linked_Array_List`)
// ----------------------------------------------------------------------------

fn benchLists(io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.Writer, n: usize) !void {
    const DB = xitdb.Database(.memory, HashInt);

    // 2a. Array_List (16-way Radix Trie)
    {
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();

        var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
        const history = try DB.ArrayList(.read_write).init(db.rootCursor());

        const AppendCtx = struct {
            n: usize,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const list = try DB.ArrayList(.read_write).init(cursor.*);
                for (0..self.n) |i| {
                    try list.append(.{ .uint = @intCast(i) });
                }
            }
        };

        const t0 = std.Io.Clock.awake.now(io);
        try history.appendContext(.{ .slot = .{} }, AppendCtx{ .n = n });
        const elapsed_append = t0.untilNow(io, .awake).nanoseconds;
        const sz = try db.committedSize();

        try printResult(stdout, .{
            .name = "Array_List (Radix Trie) append",
            .ops = n,
            .elapsed_ns = elapsed_append,
            .bytes_used = sz,
        });

        const l_cur = (try history.getCursor(0)).?;
        const rlist = try DB.ArrayList(.read_only).init(l_cur);

        const t1 = std.Io.Clock.awake.now(io);
        for (0..n) |i| {
            const ic = (try rlist.getCursor(@intCast(i))).?;
            const v = try ic.readUint();
            std.debug.assert(v == @as(u64, @intCast(i)));
        }
        const elapsed_get = t1.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Array_List (Radix Trie) random get",
            .ops = n,
            .elapsed_ns = elapsed_get,
        });

        const t2 = std.Io.Clock.awake.now(io);
        var it = try rlist.iterator();
        var cnt: usize = 0;
        while (try it.next()) |c| {
            _ = try c.readUint();
            cnt += 1;
        }
        std.debug.assert(cnt == n);
        const elapsed_iter = t2.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Array_List (Radix Trie) iterator scan",
            .ops = n,
            .elapsed_ns = elapsed_iter,
        });

        const PutArrCtx = struct {
            n: usize,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const list = try DB.ArrayList(.read_write).init(cursor.*);
                for (0..self.n) |i| {
                    try list.put(@intCast(i), .{ .uint = @intCast(i + 1_000_000) });
                }
            }
        };

        const m0_arr_slot = (try history.getSlot(0)).?;
        const t3 = std.Io.Clock.awake.now(io);
        try history.appendContext(.{ .slot = m0_arr_slot }, PutArrCtx{ .n = n });
        const elapsed_put_arr = t3.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Array_List (Radix Trie) in-place put",
            .ops = n,
            .elapsed_ns = elapsed_put_arr,
        });

        const t4 = std.Io.Clock.awake.now(io);
        for (0..n) |i| {
            var ait = try rlist.iteratorFrom(@intCast(i));
            for (0..10) |_| {
                if ((try ait.next()) == null) break;
            }
        }
        const elapsed_arr_seek = t4.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Array_List (Radix Trie) index-seek page(10)",
            .ops = n,
            .elapsed_ns = elapsed_arr_seek,
        });

        const slice_iters: usize = 500;
        const SliceArrCtx = struct {
            pub fn run(_: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const list = try DB.ArrayList(.read_write).init(cursor.*);
                try list.slice(10);
            }
        };

        const t5 = std.Io.Clock.awake.now(io);
        for (0..slice_iters) |_| {
            try history.appendContext(.{ .slot = m0_arr_slot }, SliceArrCtx{});
        }
        const elapsed_arr_slice = t5.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Array_List (Radix Trie) depth-collapse slice",
            .ops = slice_iters,
            .elapsed_ns = elapsed_arr_slice,
        });
    }

    // 2b. Linked_Array_List (Count-Augmented B-Tree)
    {
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();

        var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
        const history = try DB.ArrayList(.read_write).init(db.rootCursor());

        const AppendCtx = struct {
            n: usize,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const list = try DB.LinkedArrayList(.read_write).init(cursor.*);
                for (0..self.n) |i| {
                    try list.append(.{ .uint = @intCast(i) });
                }
            }
        };

        const t0 = std.Io.Clock.awake.now(io);
        try history.appendContext(.{ .slot = .{} }, AppendCtx{ .n = n });
        const elapsed_append = t0.untilNow(io, .awake).nanoseconds;
        const sz = try db.committedSize();

        try printResult(stdout, .{
            .name = "Linked_Array_List (B-Tree) append",
            .ops = n,
            .elapsed_ns = elapsed_append,
            .bytes_used = sz,
        });

        const l_cur = (try history.getCursor(0)).?;
        const rlist = try DB.LinkedArrayList(.read_only).init(l_cur);

        const t1 = std.Io.Clock.awake.now(io);
        for (0..n) |i| {
            const ic = (try rlist.getCursor(@intCast(i))).?;
            const v = try ic.readUint();
            std.debug.assert(v == @as(u64, @intCast(i)));
        }
        const elapsed_get = t1.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Linked_Array_List (B-Tree) random get",
            .ops = n,
            .elapsed_ns = elapsed_get,
        });

        const t2 = std.Io.Clock.awake.now(io);
        var it = try rlist.iterator();
        var cnt: usize = 0;
        while (try it.next()) |c| {
            _ = try c.readUint();
            cnt += 1;
        }
        std.debug.assert(cnt == n);
        const elapsed_iter = t2.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Linked_Array_List (B-Tree) iterator scan",
            .ops = n,
            .elapsed_ns = elapsed_iter,
        });

        // 2c. B-Tree structural rope ops: middle insert, middle remove, slice (`btree_split`) & concat (`btree_join`)
        const mid_ops: usize = 500;
        const InsertMidCtx = struct {
            ops: usize,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const list = try DB.LinkedArrayList(.read_write).init(cursor.*);
                for (0..self.ops) |i| {
                    const c = try list.count();
                    try list.insert(@intCast(c / 2), .{ .uint = @intCast(i) });
                }
            }
        };

        const m0_slot = (try history.getSlot(0)).?;
        const t3 = std.Io.Clock.awake.now(io);
        try history.appendContext(.{ .slot = m0_slot }, InsertMidCtx{ .ops = mid_ops });
        const elapsed_mid_ins = t3.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Linked_Array_List (B-Tree) middle insert",
            .ops = mid_ops,
            .elapsed_ns = elapsed_mid_ins,
        });

        const RemoveMidCtx = struct {
            ops: usize,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const list = try DB.LinkedArrayList(.read_write).init(cursor.*);
                for (0..self.ops) |_| {
                    const c = try list.count();
                    try list.remove(@intCast(c / 2));
                }
            }
        };

        const m1_slot = (try history.getSlot(1)).?;
        const t4 = std.Io.Clock.awake.now(io);
        try history.appendContext(.{ .slot = m1_slot }, RemoveMidCtx{ .ops = mid_ops });
        const elapsed_mid_rem = t4.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Linked_Array_List (B-Tree) middle remove",
            .ops = mid_ops,
            .elapsed_ns = elapsed_mid_rem,
        });

        const RopeCtx = struct {
            base_slot: xitdb.Slot,
            iters: usize,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const list = try DB.LinkedArrayList(.read_write).init(cursor.*);
                for (0..self.iters) |_| {
                    try list.concat(self.base_slot);
                    const c = try list.count();
                    try list.slice(c / 4, c / 2);
                }
            }
        };

        const rctx = RopeCtx{ .base_slot = m0_slot, .iters = 200 };
        const t5 = std.Io.Clock.awake.now(io);
        try history.appendContext(.{ .slot = m0_slot }, rctx);
        const elapsed_rope = t5.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Linked_Array_List (B-Tree) concat + slice",
            .ops = rctx.iters * 2,
            .elapsed_ns = elapsed_rope,
        });

        const PutLalCtx = struct {
            n: usize,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const list = try DB.LinkedArrayList(.read_write).init(cursor.*);
                for (0..self.n) |i| {
                    try list.put(@intCast(i), .{ .uint = @intCast(i + 1_000_000) });
                }
            }
        };

        const t6 = std.Io.Clock.awake.now(io);
        try history.appendContext(.{ .slot = m0_slot }, PutLalCtx{ .n = n });
        const elapsed_put_lal = t6.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Linked_Array_List (B-Tree) in-place put",
            .ops = n,
            .elapsed_ns = elapsed_put_lal,
        });

        const t7 = std.Io.Clock.awake.now(io);
        for (0..n) |i| {
            var lit = try rlist.iteratorFrom(@intCast(i));
            for (0..10) |_| {
                if ((try lit.next()) == null) break;
            }
        }
        const elapsed_lal_seek = t7.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Linked_Array_List (B-Tree) index-seek page(10)",
            .ops = n,
            .elapsed_ns = elapsed_lal_seek,
        });
    }
}

// ----------------------------------------------------------------------------
// 3. B+Tree (`Sorted_Map`) Out-of-Order Insert, Key Lookup, Rank & Scan
// ----------------------------------------------------------------------------

fn benchSortedMap(io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.Writer, n: usize) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp = arena.allocator();

    var buffer = std.Io.Writer.Allocating.init(allocator);
    defer buffer.deinit();

    const DB = xitdb.Database(.memory, HashInt);
    var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
    const history = try DB.ArrayList(.read_write).init(db.rootCursor());

    const keys = try temp.alloc([]const u8, n);
    for (0..n) |i| {
        const perm = (i * 1999 + 73) % n;
        keys[i] = try std.fmt.allocPrint(temp, "skey-{d:0>6}", .{perm});
    }

    const PutCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const sm = try DB.SortedMap(.read_write).init(cursor.*);
            for (self.keys, 0..) |k, idx| {
                try sm.put(k, .{ .uint = @intCast(idx) });
            }
        }
    };

    const t0 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = .{} }, PutCtx{ .keys = keys });
    const elapsed_put = t0.untilNow(io, .awake).nanoseconds;
    const sz = try db.committedSize();

    try printResult(stdout, .{
        .name = "Sorted_Map (B+Tree) out-of-order put",
        .ops = n,
        .elapsed_ns = elapsed_put,
        .bytes_used = sz,
    });

    const sm_cur = (try history.getCursor(0)).?;
    const sm = try DB.SortedMap(.read_only).init(sm_cur);

    const t1 = std.Io.Clock.awake.now(io);
    for (keys, 0..) |k, idx| {
        const vc = (try sm.getCursor(k)).?;
        const v = try vc.readUint();
        std.debug.assert(v == @as(u64, @intCast(idx)));
    }
    const elapsed_get = t1.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Sorted_Map (B+Tree) key lookup",
        .ops = n,
        .elapsed_ns = elapsed_get,
    });

    const t2 = std.Io.Clock.awake.now(io);
    for (keys) |k| {
        const rk = try sm.rank(k);
        std.debug.assert(rk < @as(u64, @intCast(n)));
    }
    const elapsed_rank = t2.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Sorted_Map (B+Tree) rank query",
        .ops = n,
        .elapsed_ns = elapsed_rank,
    });

    const t3 = std.Io.Clock.awake.now(io);
    var it = try sm.iterator();
    var cnt: usize = 0;
    while (try it.next()) |_| {
        cnt += 1;
    }
    std.debug.assert(cnt == n);
    const elapsed_iter = t3.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Sorted_Map (B+Tree) ordered scan",
        .ops = n,
        .elapsed_ns = elapsed_iter,
    });

    // 3b. Lower-bound range seek (`sorted_map_iterator_from_string`) + 10-item page read
    const t4 = std.Io.Clock.awake.now(io);
    for (keys) |k| {
        var rit = try sm.iteratorFrom(k);
        for (0..10) |_| {
            if ((try rit.next()) == null) break;
        }
    }
    const elapsed_range_seek = t4.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Sorted_Map (B+Tree) lower-bound page(10)",
        .ops = n,
        .elapsed_ns = elapsed_range_seek,
    });

    // 3c. Out-of-order B+Tree key removal & node rebalancing/merging
    const rem_count = n / 2;
    const RemSortedCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const wsm = try DB.SortedMap(.read_write).init(cursor.*);
            for (self.keys) |k| {
                _ = try wsm.remove(k);
            }
        }
    };

    const m0_slot = (try history.getSlot(0)).?;
    const t5 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = m0_slot }, RemSortedCtx{ .keys = keys[0..rem_count] });
    const elapsed_rem = t5.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Sorted_Map (B+Tree) remove & rebalance",
        .ops = rem_count,
        .elapsed_ns = elapsed_rem,
    });

    // 3d. Order-Statistic B+Tree positional select (`sorted_map_get_index_kv_pair`)
    const t6 = std.Io.Clock.awake.now(io);
    for (0..n) |i| {
        const kv_maybe = try sm.getIndexKeyValuePair(@intCast(i));
        std.debug.assert(kv_maybe != null);
    }
    const elapsed_select = t6.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Sorted_Map (B+Tree) get_index select",
        .ops = n,
        .elapsed_ns = elapsed_select,
    });

    // 3e. Order-Statistic B+Tree positional index seek (`sorted_map_iterator_from_index`) + 10-item page
    const t7 = std.Io.Clock.awake.now(io);
    for (0..n) |i| {
        var iit = try sm.iteratorFromIndex(@intCast(i));
        for (0..10) |_| {
            if ((try iit.next()) == null) break;
        }
    }
    const elapsed_index_seek = t7.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Sorted_Map (B+Tree) index-seek page(10)",
        .ops = n,
        .elapsed_ns = elapsed_index_seek,
    });

    // 3f. Sorted_Map in-place overwrite of existing keys (`found == true` in `sorted_put`)
    const OverwriteSortedCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const wsm = try DB.SortedMap(.read_write).init(cursor.*);
            for (self.keys, 0..) |k, idx| {
                try wsm.put(k, .{ .uint = @intCast(idx + 1_000_000) });
            }
        }
    };

    const t8 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = m0_slot }, OverwriteSortedCtx{ .keys = keys });
    const elapsed_overwrite = t8.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Sorted_Map (B+Tree) in-place overwrite",
        .ops = n,
        .elapsed_ns = elapsed_overwrite,
    });

    // 3g. Sorted_Set key-only put (`Sorted_Map_Get_Key` without value slot write) & `sorted_set_contains`
    const SSetPutCtx = struct {
        keys: []const []const u8,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const ss = try DB.SortedSet(.read_write).init(cursor.*);
            for (self.keys) |k| {
                try ss.put(k);
            }
        }
    };

    const sz_before_sset = try db.committedSize();
    const t9 = std.Io.Clock.awake.now(io);
    try history.appendContext(.{ .slot = .{} }, SSetPutCtx{ .keys = keys });
    const elapsed_sset_put = t9.untilNow(io, .awake).nanoseconds;
    const sz_after_sset = try db.committedSize();

    try printResult(stdout, .{
        .name = "Sorted_Set (B+Tree) key-only put (1 tx)",
        .ops = n,
        .elapsed_ns = elapsed_sset_put,
        .bytes_used = sz_after_sset - sz_before_sset,
    });

    const ss_cur = (try history.getCursor(-1)).?;
    const rss = try DB.SortedSet(.read_only).init(ss_cur);

    const t10 = std.Io.Clock.awake.now(io);
    for (keys) |k| {
        const ok = try rss.contains(k);
        std.debug.assert(ok);
    }
    const elapsed_sset_contains = t10.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Sorted_Set (B+Tree) contains lookup",
        .ops = n,
        .elapsed_ns = elapsed_sset_contains,
    });
}

// ----------------------------------------------------------------------------
// 4. Compaction & Incremental Replication Throughput
// ----------------------------------------------------------------------------

fn benchCompactionAndReplication(io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.Writer, moments_count: usize) !void {
    const DB = xitdb.Database(.memory, HashInt);

    var buffer = std.Io.Writer.Allocating.init(allocator);
    defer buffer.deinit();

    var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
    const history = try DB.ArrayList(.read_write).init(db.rootCursor());

    const CommitCtx = struct {
        idx: usize,

        pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
            const m = try DB.HashMap(.read_write).init(cursor.*);
            for (0..10) |j| {
                var kbuf: [16]u8 = undefined;
                const k = try std.fmt.bufPrint(&kbuf, "k-{d:0>2}", .{j});
                const h = hashSha1(k);
                try m.putKey(h, .{ .bytes = k });
                try m.put(h, .{ .uint = @intCast(self.idx * 10 + j) });
            }
        }
    };

    for (0..moments_count) |i| {
        const base_slot: ?xitdb.Slot = if (i > 0) try history.getSlot(-1) else null;
        try history.appendContext(.{ .slot = base_slot }, CommitCtx{ .idx = i });
    }

    // 4a. Replicate all moments to a fresh secondary replica
    var rep_buffer = std.Io.Writer.Allocating.init(allocator);
    defer rep_buffer.deinit();
    var rep_db = try DB.init(io, .{ .buffer = &rep_buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });

    var payload_buf = std.Io.Writer.Allocating.init(allocator);
    defer payload_buf.deinit();

    const t0 = std.Io.Clock.awake.now(io);
    const rep_state = try rep_db.replicaState();
    const start_off = try db.replicationStart(rep_state);
    const end_off = try db.committedSize();
    payload_buf.clearRetainingCapacity();
    try db.readCommitted(start_off, end_off, &payload_buf.writer);
    var rep_reader = std.Io.Reader.fixed(payload_buf.written());
    try rep_db.applyReplicated(start_off, &rep_reader, end_off - start_off);
    const elapsed_rep = t0.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Replication (genesis -> 200 moments)",
        .ops = moments_count,
        .elapsed_ns = elapsed_rep,
        .bytes_used = end_off,
    });

    // 4a-delta. Incremental delta replication (100 single-moment commits synced incrementally)
    const delta_commits: usize = 100;
    var t_delta: i96 = 0;
    var delta_bytes: u64 = 0;
    for (0..delta_commits) |i| {
        const s_maybe = try history.getSlot(-1);
        try history.appendContext(.{ .slot = s_maybe }, CommitCtx{ .idx = moments_count + i });

        const td0 = std.Io.Clock.awake.now(io);
        const d_state = try rep_db.replicaState();
        const d_start = try db.replicationStart(d_state);
        const d_end = try db.committedSize();
        payload_buf.clearRetainingCapacity();
        try db.readCommitted(d_start, d_end, &payload_buf.writer);
        var d_reader = std.Io.Reader.fixed(payload_buf.written());
        try rep_db.applyReplicated(d_start, &d_reader, d_end - d_start);
        t_delta += td0.untilNow(io, .awake).nanoseconds;
        delta_bytes += (d_end - d_start);
    }

    try printResult(stdout, .{
        .name = "Replication (incremental 1-moment delta)",
        .ops = delta_commits,
        .elapsed_ns = t_delta,
        .bytes_used = delta_bytes,
    });

    // 4b. Prune to latest 1 moment & compact database
    try history.slice(1);

    var comp_buffer = std.Io.Writer.Allocating.init(allocator);
    defer comp_buffer.deinit();

    const t1 = std.Io.Clock.awake.now(io);
    var offset_map = std.AutoHashMap(u64, u64).init(allocator);
    defer offset_map.deinit();
    var comp_db = try db.compact(.memory, .{ .buffer = &comp_buffer }, &offset_map);
    const elapsed_compact = t1.untilNow(io, .awake).nanoseconds;
    const comp_size = try comp_db.committedSize();

    try printResult(stdout, .{
        .name = "Compaction (Memory_Offset_Map, 200 -> 1)",
        .ops = 1,
        .elapsed_ns = elapsed_compact,
        .bytes_used = comp_size,
    });

    // 4c. Compact using xitdb-backed `File_Offset_Map` (in-memory Core_Memory backing db, matching Odin)
    const OffsetDB = xitdb.Database(.memory, u64);
    const FileOffsetMap = struct {
        map: OffsetDB.HashMap(.read_write),

        pub fn reset(self: *@This()) !void {
            var cursor = self.map.cursor;
            try cursor.write(.{ .slot = null });
            self.map = try OffsetDB.HashMap(.read_write).init(cursor);
        }

        pub fn get(self: *@This(), source_offset: u64) !?u64 {
            const cursor = (try self.map.getCursor(source_offset)) orelse return null;
            return try cursor.readUint();
        }

        pub fn put(self: *@This(), source_offset: u64, target_offset: u64) !void {
            try self.map.put(source_offset, .{ .uint = target_offset });
        }
    };

    var comp_file_buffer = std.Io.Writer.Allocating.init(allocator);
    defer comp_file_buffer.deinit();

    var om_buffer = std.Io.Writer.Allocating.init(allocator);
    defer om_buffer.deinit();
    var om_db = try OffsetDB.init(io, .{ .buffer = &om_buffer });

    const FileCompactCtx = struct {
        src_db: *DB,
        target_buf: *std.Io.Writer.Allocating,
        comp_size_out: *u64,

        pub fn run(self: @This(), cursor: *OffsetDB.Cursor(.read_write)) !void {
            var file_om = FileOffsetMap{ .map = try OffsetDB.HashMap(.read_write).init(cursor.*) };
            var comp_db2 = try self.src_db.compact(.memory, .{ .buffer = self.target_buf }, &file_om);
            self.comp_size_out.* = try comp_db2.committedSize();
        }
    };

    var comp_size2: u64 = 0;
    const t2 = std.Io.Clock.awake.now(io);
    try om_db.runContext(FileCompactCtx{
        .src_db = &db,
        .target_buf = &comp_file_buffer,
        .comp_size_out = &comp_size2,
    });
    const elapsed_file_compact = t2.untilNow(io, .awake).nanoseconds;

    try printResult(stdout, .{
        .name = "Compaction (File_Offset_Map, 200 -> 1)",
        .ops = 1,
        .elapsed_ns = elapsed_file_compact,
        .bytes_used = comp_size2,
    });

    // 4d. Heterogeneous DAG Compaction (`Array_List` + `Linked_Array_List` + `Sorted_Map` + `Counted_Hash_Map` + DAG shared subtrees)
    {
        var dag_src_buffer = std.Io.Writer.Allocating.init(allocator);
        defer dag_src_buffer.deinit();
        var dag_db = try DB.init(io, .{ .buffer = &dag_src_buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });

        const BuildDagCtx = struct {
            pub fn run(_: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const root_map = try DB.CountedHashMap(.read_write).init(cursor.*);

                // 1. Array_List with 200 items
                const al_key = "array_list";
                const al_hash = hashSha1(al_key);
                try root_map.putKey(al_hash, .{ .bytes = al_key });
                const al_wc = try root_map.putCursor(al_hash);
                const al = try DB.ArrayList(.read_write).init(al_wc);
                for (0..200) |i| {
                    var ibuf: [32]u8 = undefined;
                    const item = try std.fmt.bufPrint(&ibuf, "arr-item-{d:0>4}-payload", .{i});
                    try al.append(.{ .bytes = item });
                }
                const al_slot = try al.slot();

                // 2. Linked_Array_List with 200 items
                const lal_key = "linked_list";
                const lal_hash = hashSha1(lal_key);
                try root_map.putKey(lal_hash, .{ .bytes = lal_key });
                const lal_wc = try root_map.putCursor(lal_hash);
                const lal = try DB.LinkedArrayList(.read_write).init(lal_wc);
                for (0..200) |i| {
                    try lal.append(.{ .uint = @intCast(i) });
                }
                const lal_slot = try lal.slot();

                // 3. Sorted_Map with 200 items
                const sm_key = "sorted_map";
                const sm_hash = hashSha1(sm_key);
                try root_map.putKey(sm_hash, .{ .bytes = sm_key });
                const sm_wc = try root_map.putCursor(sm_hash);
                const sm = try DB.SortedMap(.read_write).init(sm_wc);
                for (0..200) |i| {
                    var skbuf: [16]u8 = undefined;
                    const sk = try std.fmt.bufPrint(&skbuf, "skey-{d:0>4}", .{(i * 73) % 200});
                    try sm.put(sk, .{ .uint = @intCast(i) });
                }
                const sm_slot = try sm.slot();

                // 4. DAG structural sharing: reference the same 3 collections under 5 alias keys each
                for (0..5) |alias_i| {
                    var k1buf: [16]u8 = undefined;
                    const k1 = try std.fmt.bufPrint(&k1buf, "alias-al-{d}", .{alias_i});
                    const h1 = hashSha1(k1);
                    try root_map.putKey(h1, .{ .bytes = k1 });
                    try root_map.put(h1, .{ .slot = al_slot });

                    var k2buf: [16]u8 = undefined;
                    const k2 = try std.fmt.bufPrint(&k2buf, "alias-lal-{d}", .{alias_i});
                    const h2 = hashSha1(k2);
                    try root_map.putKey(h2, .{ .bytes = k2 });
                    try root_map.put(h2, .{ .slot = lal_slot });

                    var k3buf: [16]u8 = undefined;
                    const k3 = try std.fmt.bufPrint(&k3buf, "alias-sm-{d}", .{alias_i});
                    const h3 = hashSha1(k3);
                    try root_map.putKey(h3, .{ .bytes = k3 });
                    try root_map.put(h3, .{ .slot = sm_slot });
                }
            }
        };

        try dag_db.runContext(BuildDagCtx{});

        var dag_dst_buffer = std.Io.Writer.Allocating.init(allocator);
        defer dag_dst_buffer.deinit();
        var dag_om = std.AutoHashMap(u64, u64).init(allocator);
        defer dag_om.deinit();

        const t_dag = std.Io.Clock.awake.now(io);
        var dag_comp_db = try dag_db.compact(.memory, .{ .buffer = &dag_dst_buffer }, &dag_om);
        const elapsed_dag = t_dag.untilNow(io, .awake).nanoseconds;
        const dag_comp_sz = try dag_comp_db.committedSize();

        try printResult(stdout, .{
            .name = "Compaction (Heterogeneous DAG + dedup)",
            .ops = 1,
            .elapsed_ns = elapsed_dag,
            .bytes_used = dag_comp_sz,
        });

        // 4f. Post-compaction replica resync (`database_replication_start` divergence detection + full replacement sync)
        var resync_rep_buffer = std.Io.Writer.Allocating.init(allocator);
        defer resync_rep_buffer.deinit();
        var resync_rep_db = try DB.init(io, .{ .buffer = &resync_rep_buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });

        // First sync replica with pre-compaction DAG primary
        const orig_end = try dag_db.committedSize();
        payload_buf.clearRetainingCapacity();
        try dag_db.readCommitted(0, orig_end, &payload_buf.writer);
        var orig_reader = std.Io.Reader.fixed(payload_buf.written());
        try resync_rep_db.applyReplicated(0, &orig_reader, orig_end);

        // Now measure resync against the compacted DAG primary (`dag_comp_db`)
        const t_resync = std.Io.Clock.awake.now(io);
        const r_state = try resync_rep_db.replicaState();
        const resync_start = try dag_comp_db.replicationStart(r_state);
        std.debug.assert(resync_start == 0);
        const comp_end = try dag_comp_db.committedSize();
        payload_buf.clearRetainingCapacity();
        try dag_comp_db.readCommitted(resync_start, comp_end, &payload_buf.writer);
        const comp_payload_len = payload_buf.written().len;
        var comp_reader = std.Io.Reader.fixed(payload_buf.written());
        try resync_rep_db.applyReplicated(resync_start, &comp_reader, comp_end - resync_start);
        const elapsed_resync = t_resync.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Replication (Post-compaction resync)",
            .ops = 1,
            .elapsed_ns = elapsed_resync,
            .bytes_used = comp_payload_len,
        });
    }
}

// ----------------------------------------------------------------------------
// 5. Hasher Comparison (`SHA-1` 20B vs `SHA-256` 32B) & Byte Storage Paths
// ----------------------------------------------------------------------------

fn benchHashersAndByteStreams(io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.Writer, n: usize) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp = arena.allocator();

    const keys = try temp.alloc([]const u8, n);
    for (0..n) |i| {
        keys[i] = try std.fmt.allocPrint(temp, "hash-bench-key-{d:0>6}", .{i});
    }

    const DBSha1 = xitdb.Database(.memory, HashInt);
    const DBSha256 = xitdb.Database(.memory, Sha256Int);

    // 5a. SHA-1 (20-byte digest) vs SHA-256 (32-byte digest) HAMT insert & footprint
    {
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();
        var db = try DBSha1.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
        const history = try DBSha1.ArrayList(.read_write).init(db.rootCursor());

        const PutSha1Ctx = struct {
            keys: []const []const u8,

            pub fn run(self: @This(), cursor: *DBSha1.Cursor(.read_write)) !void {
                const m = try DBSha1.HashMap(.read_write).init(cursor.*);
                for (self.keys, 0..) |k, idx| {
                    const h = hashSha1(k);
                    try m.putKey(h, .{ .bytes = k });
                    try m.put(h, .{ .uint = @intCast(idx) });
                }
            }
        };

        const t0 = std.Io.Clock.awake.now(io);
        try history.appendContext(.{ .slot = .{} }, PutSha1Ctx{ .keys = keys });
        const elapsed = t0.untilNow(io, .awake).nanoseconds;
        const sz = try db.committedSize();

        try printResult(stdout, .{
            .name = "Hasher: SHA-1 (20B) HAMT put",
            .ops = n,
            .elapsed_ns = elapsed,
            .bytes_used = sz,
        });
    }

    {
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();
        var db = try DBSha256.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha2") });
        const history = try DBSha256.ArrayList(.read_write).init(db.rootCursor());

        const PutSha256Ctx = struct {
            keys: []const []const u8,

            pub fn run(self: @This(), cursor: *DBSha256.Cursor(.read_write)) !void {
                const m = try DBSha256.HashMap(.read_write).init(cursor.*);
                for (self.keys, 0..) |k, idx| {
                    const h = hashSha256(k);
                    try m.putKey(h, .{ .bytes = k });
                    try m.put(h, .{ .uint = @intCast(idx) });
                }
            }
        };

        const t0 = std.Io.Clock.awake.now(io);
        try history.appendContext(.{ .slot = .{} }, PutSha256Ctx{ .keys = keys });
        const elapsed = t0.untilNow(io, .awake).nanoseconds;
        const sz = try db.committedSize();

        try printResult(stdout, .{
            .name = "Hasher: SHA-256 (32B) HAMT put",
            .ops = n,
            .elapsed_ns = elapsed,
            .bytes_used = sz,
        });
    }

    // 5b. Inline `Short_Bytes` (<= 8B) vs External `Bytes` (> 8B) zero-alloc stack reads
    {
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();
        var db = try DBSha1.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
        const m = try DBSha1.HashMap(.read_write).init(db.rootCursor());

        const h_inline = hashSha1("inline");
        try m.putKey(h_inline, .{ .bytes = "inline" });
        try m.put(h_inline, .{ .bytes = "8bytes!!" });

        const h_heap = hashSha1("heap");
        try m.putKey(h_heap, .{ .bytes = "heap" });
        try m.put(h_heap, .{ .bytes = "heap-allocated-32-byte-string!!!" });

        const rm = m.readOnly();
        const inline_cur = (try rm.getCursor(h_inline)).?;
        const heap_cur = (try rm.getCursor(h_heap)).?;

        const reads = n * 5;
        var stack_buf: [64]u8 = undefined;

        const t_in = std.Io.Clock.awake.now(io);
        for (0..reads) |_| {
            const obj = try inline_cur.readBytesObject(&stack_buf);
            std.debug.assert(obj.value.len == 8);
        }
        try printResult(stdout, .{
            .name = "Bytes: Inline Short_Bytes read_bytes_buf",
            .ops = reads,
            .elapsed_ns = t_in.untilNow(io, .awake).nanoseconds,
        });

        const t_hp = std.Io.Clock.awake.now(io);
        for (0..reads) |_| {
            const obj = try heap_cur.readBytesObject(&stack_buf);
            std.debug.assert(obj.value.len == 32);
        }
        try printResult(stdout, .{
            .name = "Bytes: External Bytes read_bytes_buf",
            .ops = reads,
            .elapsed_ns = t_hp.untilNow(io, .awake).nanoseconds,
        });

        // Format-tagged `Bytes` (`slot.full == true`, 2-byte tag) inline (6B) vs external (32B) read_bytes_buf
        const h_tin = hashSha1("tagged_inline");
        try m.putKey(h_tin, .{ .bytes = "tagged_inline" });
        try m.put(h_tin, .{ .bytes_object = .{ .value = "6bytes", .format_tag = "js".* } });

        const h_thp = hashSha1("tagged_heap");
        try m.putKey(h_thp, .{ .bytes = "tagged_heap" });
        try m.put(h_thp, .{ .bytes_object = .{ .value = "heap-allocated-32-byte-string!!!", .format_tag = "md".* } });

        const rm2 = m.readOnly();
        const t_in_cur = (try rm2.getCursor(h_tin)).?;
        const t_hp_cur = (try rm2.getCursor(h_thp)).?;

        const t_tin = std.Io.Clock.awake.now(io);
        for (0..reads) |_| {
            const obj = try t_in_cur.readBytesObject(&stack_buf);
            std.debug.assert(obj.value.len == 6 and obj.format_tag != null);
        }
        try printResult(stdout, .{
            .name = "Bytes: Tagged Short_Bytes read_bytes_buf",
            .ops = reads,
            .elapsed_ns = t_tin.untilNow(io, .awake).nanoseconds,
        });

        const t_thp = std.Io.Clock.awake.now(io);
        for (0..reads) |_| {
            const obj = try t_hp_cur.readBytesObject(&stack_buf);
            std.debug.assert(obj.value.len == 32 and obj.format_tag != null);
        }
        try printResult(stdout, .{
            .name = "Bytes: Tagged External Bytes read_bytes_buf",
            .ops = reads,
            .elapsed_ns = t_thp.untilNow(io, .awake).nanoseconds,
        });
    }

    // 5c. Streaming `Cursor_Writer` & `Cursor_Reader` (1 MB payload in 4 KB chunks)
    {
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();
        var db = try DBSha1.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });

        const chunks_count: usize = 256; // 256 * 4 KB = 1 MB
        var blob_rc: DBSha1.Cursor(.read_only) = undefined;

        const StreamWriteCtx = struct {
            chunks_count: usize,
            blob_rc_out: *DBSha1.Cursor(.read_only),

            pub fn run(self: @This(), cursor: *DBSha1.Cursor(.read_write)) !void {
                var w = try cursor.writer(&.{});
                var chunk: [4096]u8 = @splat(0);
                for (0..self.chunks_count) |i| {
                    chunk[0] = @intCast(i & 0xFF);
                    try w.interface.writeAll(&chunk);
                }
                try w.finish();
                self.blob_rc_out.* = cursor.readOnly();
            }
        };

        const t_sw = std.Io.Clock.awake.now(io);
        try db.runContext(StreamWriteCtx{ .chunks_count = chunks_count, .blob_rc_out = &blob_rc });
        const elapsed_sw = t_sw.untilNow(io, .awake).nanoseconds;
        const sz_sw = try db.committedSize();

        try printResult(stdout, .{
            .name = "Stream: Cursor_Writer (256 x 4KB = 1MB)",
            .ops = chunks_count,
            .elapsed_ns = elapsed_sw,
            .bytes_used = sz_sw,
        });

        const t_sr = std.Io.Clock.awake.now(io);
        var reader = try blob_rc.reader(&.{});
        var read_buf: [4096]u8 = undefined;
        var read_chunks: usize = 0;
        while (true) {
            const nr = try reader.interface.readSliceShort(&read_buf);
            if (nr == 0) break;
            read_chunks += 1;
        }
        std.debug.assert(read_chunks == chunks_count);
        const elapsed_sr = t_sr.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Stream: Cursor_Reader (256 x 4KB = 1MB)",
            .ops = chunks_count,
            .elapsed_ns = elapsed_sr,
        });

        // Random-access seek + 64B read across the 1 MB blob (`cursor_reader_seek_to`)
        const seek_ops = n;
        var small_buf: [64]u8 = undefined;
        const t_rseek = std.Io.Clock.awake.now(io);
        for (0..seek_ops) |i| {
            const off: u64 = @intCast((i * 4099) % (chunks_count * 4096 - 64));
            try reader.seekTo(off);
            try reader.interface.readSliceAll(&small_buf);
        }
        const elapsed_rseek = t_rseek.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Stream: Cursor_Reader random seek + 64B read",
            .ops = seek_ops,
            .elapsed_ns = elapsed_rseek,
        });

        // Random-access in-place patch via `cursor_writer_seek_to`
        const StreamPatchCtx = struct {
            ops: usize,

            pub fn run(self: @This(), cursor: *DBSha1.Cursor(.read_write)) !void {
                var w = try cursor.writer(&.{});
                const init_buf: [65536]u8 = @splat(0);
                try w.interface.writeAll(&init_buf);
                var patch: [16]u8 = @splat(0);
                for (0..self.ops) |i| {
                    const off: u64 = @intCast((i * 1031) % (65536 - 16));
                    try w.seekTo(off);
                    patch[0] = @intCast(i & 0xFF);
                    try w.interface.writeAll(&patch);
                }
                try w.finish();
            }
        };

        const t_wseek = std.Io.Clock.awake.now(io);
        try db.runContext(StreamPatchCtx{ .ops = seek_ops });
        const elapsed_wseek = t_wseek.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Stream: Cursor_Writer random seek + 16B patch",
            .ops = seek_ops,
            .elapsed_ns = elapsed_wseek,
        });
    }

    // 5d. Deeply Nested Multi-Part Atomic Path Traversal (`cursor_write_path` & `cursor_read_path` across 4 nested collections)
    {
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();
        var db = try DBSha1.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });

        const path_ops: usize = 500;
        const h_root = hashSha1("tenant");

        const DeepWriteCtx = struct {
            ops: usize,
            h_root: HashInt,

            pub fn run(self: @This(), cursor: *DBSha1.Cursor(.read_write)) !void {
                // Initialize 4-level hierarchy: Hash_Map -> Array_List -> Linked_Array_List -> Sorted_Map
                _ = try cursor.writePath(void, &.{
                    .{ .hash_map_init = .{ .counted = false, .set = false } },
                    .{ .hash_map_get = .{ .value = self.h_root } },
                    .array_list_init,
                    .array_list_append,
                    .linked_array_list_init,
                    .linked_array_list_append,
                    .{ .sorted_map_init = .{ .set = false } },
                });

                const skey = "deep-sorted-key";
                for (0..self.ops) |i| {
                    _ = try cursor.writePath(void, &.{
                        .{ .hash_map_get = .{ .value = self.h_root } },
                        .{ .array_list_get = 0 },
                        .{ .linked_array_list_get = 0 },
                        .{ .sorted_map_get = .{ .value = skey } },
                        .{ .write = .{ .uint = @intCast(i) } },
                    });
                }
            }
        };

        const t_dw = std.Io.Clock.awake.now(io);
        try db.runContext(DeepWriteCtx{ .ops = path_ops, .h_root = h_root });
        const elapsed_dw = t_dw.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Path: 4-level nested cursor_write_path",
            .ops = path_ops,
            .elapsed_ns = elapsed_dw,
        });

        const rc = db.rootCursor().readOnly();
        const skey = "deep-sorted-key";
        const read_parts = [_]DBSha1.PathPart(void){
            .{ .hash_map_get = .{ .value = h_root } },
            .{ .array_list_get = 0 },
            .{ .linked_array_list_get = 0 },
            .{ .sorted_map_get = .{ .value = skey } },
        };

        const t_dr = std.Io.Clock.awake.now(io);
        for (0..path_ops) |_| {
            const mc = (try rc.readPath(void, &read_parts)).?;
            const v = try mc.readUint();
            std.debug.assert(v == @as(u64, @intCast(path_ops - 1)));
        }
        const elapsed_dr = t_dr.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Path: 4-level nested cursor_read_path",
            .ops = path_ops,
            .elapsed_ns = elapsed_dr,
        });
    }

    // 5e. Full KV-Pair Inspection Scan (`cursor_read_kv_pair` decoding both key and value cursors across `n` entries)
    {
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();
        var db = try DBSha1.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
        const history = try DBSha1.ArrayList(.read_write).init(db.rootCursor());

        const PutSha1Ctx = struct {
            keys: []const []const u8,

            pub fn run(self: @This(), cursor: *DBSha1.Cursor(.read_write)) !void {
                const m = try DBSha1.HashMap(.read_write).init(cursor.*);
                for (self.keys, 0..) |k, idx| {
                    const h = hashSha1(k);
                    try m.putKey(h, .{ .bytes = k });
                    try m.put(h, .{ .uint = @intCast(idx) });
                }
            }
        };

        try history.appendContext(.{ .slot = .{} }, PutSha1Ctx{ .keys = keys });

        const mc = (try history.readOnly().getCursor(0)).?;
        const rm = try DBSha1.HashMap(.read_only).init(mc);

        var key_buf: [64]u8 = undefined;
        var kv_cnt: usize = 0;
        const t_kv = std.Io.Clock.awake.now(io);
        var it = try rm.iterator();
        while (try it.next()) |cur| {
            const kv = try cur.readKeyValuePair();
            const k_obj = try kv.key_cursor.readBytesObject(&key_buf);
            const v_uint = try kv.value_cursor.readUint();
            std.debug.assert(k_obj.value.len > 0 and v_uint < @as(u64, @intCast(n)));
            kv_cnt += 1;
        }
        std.debug.assert(kv_cnt == n);
        const elapsed_kv = t_kv.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Cursor: Full KV-pair scan (read_kv_pair)",
            .ops = n,
            .elapsed_ns = elapsed_kv,
        });
    }
}

// ----------------------------------------------------------------------------
// 6. Storage Backends (`Core_Memory` vs `Core_Buffered_File` vs `Core_File`)
// ----------------------------------------------------------------------------

fn benchBackends(io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.Writer, commits: usize) !void {
    const h_counter = hashSha1("counter");
    const h_label = hashSha1("label");

    // 6a. Core_Memory
    {
        const DB = xitdb.Database(.memory, HashInt);
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();
        var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
        const history = try DB.ArrayList(.read_write).init(db.rootCursor());

        const TxCtx = struct {
            step: usize,
            h_counter: HashInt,
            h_label: HashInt,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const m = try DB.HashMap(.read_write).init(cursor.*);
                try m.putKey(self.h_counter, .{ .bytes = "counter" });
                try m.put(self.h_counter, .{ .uint = @intCast(self.step) });
                try m.putKey(self.h_label, .{ .bytes = "label" });
                try m.put(self.h_label, .{ .bytes = "benchmark-payload-string" });
            }
        };

        const t0 = std.Io.Clock.awake.now(io);
        for (0..commits) |i| {
            const base: ?xitdb.Slot = if (i > 0) try history.getSlot(-1) else null;
            try history.appendContext(.{ .slot = base }, TxCtx{
                .step = i,
                .h_counter = h_counter,
                .h_label = h_label,
            });
        }
        const elapsed = t0.untilNow(io, .awake).nanoseconds;
        const sz = try db.committedSize();

        try printResult(stdout, .{
            .name = "Backend: Core_Memory commits",
            .ops = commits,
            .elapsed_ns = elapsed,
            .bytes_used = sz,
        });
    }

    // 6b. Core_Buffered_File (64 KB buffer, fsync = false)
    {
        const path = "/tmp/xitdb_zig_bench_buffered.db";
        std.Io.Dir.cwd().deleteFile(io, path) catch {};
        const file = try std.Io.Dir.cwd().createFile(io, path, .{ .read = true, .truncate = true });
        defer {
            file.close(io);
            std.Io.Dir.cwd().deleteFile(io, path) catch {};
        }

        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();

        const DB = xitdb.Database(.buffered_file, HashInt);
        var db = try DB.init(io, .{
            .file = file,
            .buffer = &buffer,
            .max_size = 65536,
            .fsync = false,
            .hash_id = xitdb.HashId.fromBytes("sha1"),
        });
        const history = try DB.ArrayList(.read_write).init(db.rootCursor());

        const TxCtx = struct {
            step: usize,
            h_counter: HashInt,
            h_label: HashInt,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const m = try DB.HashMap(.read_write).init(cursor.*);
                try m.putKey(self.h_counter, .{ .bytes = "counter" });
                try m.put(self.h_counter, .{ .uint = @intCast(self.step) });
                try m.putKey(self.h_label, .{ .bytes = "label" });
                try m.put(self.h_label, .{ .bytes = "benchmark-payload-string" });
            }
        };

        const t0 = std.Io.Clock.awake.now(io);
        for (0..commits) |i| {
            const base: ?xitdb.Slot = if (i > 0) try history.getSlot(-1) else null;
            try history.appendContext(.{ .slot = base }, TxCtx{
                .step = i,
                .h_counter = h_counter,
                .h_label = h_label,
            });
        }
        const elapsed = t0.untilNow(io, .awake).nanoseconds;
        const sz = try db.committedSize();

        try printResult(stdout, .{
            .name = "Backend: Core_Buffered_File commits",
            .ops = commits,
            .elapsed_ns = elapsed,
            .bytes_used = sz,
        });
    }

    // 6c. Core_File (unbuffered OS syscalls, fsync = false)
    {
        const path = "/tmp/xitdb_zig_bench_file.db";
        std.Io.Dir.cwd().deleteFile(io, path) catch {};
        const file = try std.Io.Dir.cwd().createFile(io, path, .{ .read = true, .truncate = true });
        defer {
            file.close(io);
            std.Io.Dir.cwd().deleteFile(io, path) catch {};
        }

        const DB = xitdb.Database(.file, HashInt);
        var db = try DB.init(io, .{
            .file = file,
            .fsync = false,
            .hash_id = xitdb.HashId.fromBytes("sha1"),
        });
        const history = try DB.ArrayList(.read_write).init(db.rootCursor());

        const TxCtx = struct {
            step: usize,
            h_counter: HashInt,
            h_label: HashInt,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const m = try DB.HashMap(.read_write).init(cursor.*);
                try m.putKey(self.h_counter, .{ .bytes = "counter" });
                try m.put(self.h_counter, .{ .uint = @intCast(self.step) });
                try m.putKey(self.h_label, .{ .bytes = "label" });
                try m.put(self.h_label, .{ .bytes = "benchmark-payload-string" });
            }
        };

        const t0 = std.Io.Clock.awake.now(io);
        for (0..commits) |i| {
            const base: ?xitdb.Slot = if (i > 0) try history.getSlot(-1) else null;
            try history.appendContext(.{ .slot = base }, TxCtx{
                .step = i,
                .h_counter = h_counter,
                .h_label = h_label,
            });
        }
        const elapsed = t0.untilNow(io, .awake).nanoseconds;
        const sz = try db.committedSize();

        try printResult(stdout, .{
            .name = "Backend: Core_File (unbuffered) commits",
            .ops = commits,
            .elapsed_ns = elapsed,
            .bytes_used = sz,
        });
    }

    // 6d. Mid-transaction `database_freeze` + CoW subtree cloning & transaction rollback truncation
    {
        const DB = xitdb.Database(.memory, HashInt);
        var buffer = std.Io.Writer.Allocating.init(allocator);
        defer buffer.deinit();
        var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });

        const FreezeCowCtx = struct {
            db: *DB,
            iters: usize,

            pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const top = try DB.HashMap(.read_write).init(cursor.*);
                const h_base = hashSha1("base");
                try top.putKey(h_base, .{ .bytes = "base" });
                const base_wc = try top.putCursor(h_base);
                const base_map = try DB.HashMap(.read_write).init(base_wc);
                for (0..16) |j| {
                    var kbuf: [16]u8 = undefined;
                    const k = try std.fmt.bufPrint(&kbuf, "k-{d:0>2}", .{j});
                    const hk = hashSha1(k);
                    try base_map.putKey(hk, .{ .bytes = k });
                    try base_map.put(hk, .{ .uint = @intCast(j) });
                }
                const base_slot = try base_map.slot();
                const hk00 = hashSha1("k-00");

                for (0..self.iters) |i| {
                    try self.db.freeze();
                    var fkbuf: [16]u8 = undefined;
                    const fork_key = try std.fmt.bufPrint(&fkbuf, "fork-{d:0>4}", .{i});
                    const h_fork = hashSha1(fork_key);
                    try top.putKey(h_fork, .{ .bytes = fork_key });
                    try top.put(h_fork, .{ .slot = base_slot });
                    const fork_wc = try top.putCursor(h_fork);
                    const fork_map = try DB.HashMap(.read_write).init(fork_wc);
                    try fork_map.putKey(hk00, .{ .bytes = "k-00" });
                    try fork_map.put(hk00, .{ .uint = @intCast(1000 + i) });
                }
            }
        };

        const t_fc = std.Io.Clock.awake.now(io);
        try db.runContext(FreezeCowCtx{ .db = &db, .iters = commits });
        const elapsed_fc = t_fc.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "Tx: Mid-tx database_freeze + CoW clone",
            .ops = commits,
            .elapsed_ns = elapsed_fc,
        });

        const RollbackCtx = struct {
            pub fn run(_: @This(), cursor: *DB.Cursor(.read_write)) !void {
                const top = try DB.HashMap(.read_write).init(cursor.*);
                const h1 = hashSha1("temp-1");
                try top.putKey(h1, .{ .bytes = "temp-1" });
                try top.put(h1, .{ .uint = 1 });
                const h2 = hashSha1("temp-2");
                try top.putKey(h2, .{ .bytes = "temp-2" });
                try top.put(h2, .{ .bytes = "uncommitted-payload-bytes" });
                return error.KeyNotFound; // Abort transaction to trigger rollback truncation
            }
        };

        const size_before_rb = try db.committedSize();
        const t_rb = std.Io.Clock.awake.now(io);
        for (0..commits) |_| {
            if (db.runContext(RollbackCtx{})) |_| {
                unreachable;
            } else |err| {
                std.debug.assert(err == error.KeyNotFound);
            }
        }
        const elapsed_rb = t_rb.untilNow(io, .awake).nanoseconds;
        const size_after_rb = try db.committedSize();
        std.debug.assert(size_after_rb == size_before_rb);

        try printResult(stdout, .{
            .name = "Tx: Aborted transaction rollback truncate",
            .ops = commits,
            .elapsed_ns = elapsed_rb,
        });

        // 6e. Database re-open & header/root-trailer checksum validation (`database_init` on populated `Core_Memory`)
        const reopen_ops = commits * 10;
        const t_reopen = std.Io.Clock.awake.now(io);
        for (0..reopen_ops) |_| {
            var reopened_db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
            const rc = reopened_db.rootCursor();
            std.debug.assert(rc.slot_ptr.slot.tag == .hash_map);
        }
        const elapsed_reopen = t_reopen.untilNow(io, .awake).nanoseconds;

        try printResult(stdout, .{
            .name = "DB: Re-open & trailer checksum verify",
            .ops = reopen_ops,
            .elapsed_ns = elapsed_reopen,
        });
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    try printHeader(stdout);
    try benchHamt(io, allocator, stdout, 2_000);
    try benchLists(io, allocator, stdout, 2_000);
    try benchSortedMap(io, allocator, stdout, 2_000);
    try benchCompactionAndReplication(io, allocator, stdout, 200);
    try benchHashersAndByteStreams(io, allocator, stdout, 2_000);
    try benchBackends(io, allocator, stdout, 500);
    try stdout.writeAll("========================================================================================================\n");
    try stdout.flush();
}
