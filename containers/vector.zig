const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Vector(comptime T: type) type {
    return struct {
        size: usize = undefined,
        elements: usize = undefined,
        allocator: Allocator = undefined,
        data: []T = undefined,

        fn init(allocator: Allocator, size: ?usize) !Vector(T) {
            const sz = if (size == null or size.? <= 1) 1 else size.?;
            var ret = .{ .size = sz, .elements = 0, .allocator = allocator, .data = try allocator.alloc(T, sz) };
            @memset(ret.data[0..], undefined);
            return ret;
        }

        fn deinit(self: *Vector(T)) void {
            self.allocator.free(self.data);
            self.data = undefined;
            self.size = undefined;
            self.elements = undefined;
        }

        fn reserve(self: *Vector(T), size: usize) !void {
            if (size <= self.size) return;

            var temp = try self.allocator.alloc(T, size);
            @memset(temp[self.elements..], undefined);

            var idx: usize = 0;
            for (self.data) |elem| {
                temp[idx] = elem;
                idx += 1;
            }

            self.allocator.free(self.data);
            self.data = temp;
            self.size = size;
        }

        fn append(self: *Vector(T), other: *const Vector(T), bAllowShrinkToFit: bool) !void {
            const oldSz: usize = self.size;

            try self.reserve(self.size + other.size);
            @memcpy(self.data[oldSz..], other.data[0..]);

            if (bAllowShrinkToFit) {
                shrink(self) catch return;
            }
        }

        fn shrink(self: *Vector(T)) !void {
            if (self.elements + 1 == self.size) return;

            var temp = try self.allocator.alloc(T, self.elements + 1);

            var idx: usize = 0;
            var idxTemp: usize = 0;
            while (idxTemp < self.elements and idx < self.size) : (idx += 1) {
                if (self.data[idx] == undefined) continue;
                temp[idxTemp] = self.data[idx];
                idxTemp += 1;
            }

            self.allocator.free(self.data);
            self.data = temp;
            self.size = self.elements + 1;
        }

        fn add(self: *Vector(T), value: T) !void {
            if (self.elements == self.size - 1) {
                try reserve(self, self.size + 1);
            }

            self.data[self.elements + 1] = value;
            self.elements += 1;
        }

        fn remove(self: *Vector(T), index: usize, bAllowShrinkToFit: bool) !void {
            if (index >= self.size) return;

            if (self.data[index] != undefined) {
                self.data[index] = undefined;
                self.elements -= 1;
            }

            if (bAllowShrinkToFit) {
                try self.shrink();
            } else {
                var i = index;
                for (self.data[i..], i + 1..) |_, j| {
                    if (j >= self.size) break;
                    self.data[i] = self.data[j];
                    i += 1;
                }
            }
        }

        fn clear(self: *Vector(T)) !void {
            self.deinit();
            self.init(self.allocator, null);
        }

        fn empty(self: *Vector(T)) bool {
            return self.elements == 0;
        }

        fn length(self: *Vector(T)) usize {
            return self.size;
        }

        fn at(self: *Vector(T), index: usize) ?*T {
            if (index >= self.size) return null;
            return &self.data[index];
        }

        fn find(self: *Vector(T), element: *T) ?usize {
            if (element.* == undefined) return null;

            var idx: usize = 0;
            for (self.data) |elem| {
                if (&elem == element) {
                    return idx;
                }
                idx += 1;
            }

            return null;
        }

        fn first(self: *Vector(T)) *T {
            return &self.data[0];
        }

        fn last(self: *Vector(T)) *T {
            return &self.data[self.size - 1];
        }
    };
}

////////////////////////////////////////////////////////////
// Tests
////////////////////////////////////////////////////////////

test "CreateVector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: Allocator = gpa.allocator();
    var vector = try Vector(i32).init(allocator, null);
    defer vector.deinit();

    try std.testing.expect(vector.length() == 1);
}

test "CreateLargeVector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: Allocator = gpa.allocator();
    var vector = try Vector(i32).init(allocator, 0xABCDEF);
    defer vector.deinit();

    try std.testing.expect(vector.length() == 11259375);
}

test "VectorAdd" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: Allocator = gpa.allocator();
    var vector = try Vector(i32).init(allocator, null);
    defer vector.deinit();

    try vector.add(0x7FFFFFFF);

    try std.testing.expect(vector.length() == 2 and vector.at(1).?.* == 0x7FFFFFFF);
}

test "VectorRemove" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: Allocator = gpa.allocator();
    var vector = try Vector(i32).init(allocator, null);
    defer vector.deinit();

    try vector.add(0x7FFFFFFF);
    try vector.add(0x7FFFFFFF);
    try vector.add(0x7FFFFFFF);

    try std.testing.expect(vector.length() == 4);

    try vector.remove(2, false);
    try std.testing.expect(vector.length() == 4);

    try vector.remove(2, true);
    try std.testing.expect(vector.length() == 2);
}

test "VectorAppend" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: Allocator = gpa.allocator();
    var vec1 = try Vector(i32).init(allocator, null);
    var vec2 = try Vector(i32).init(allocator, null);
    defer vec1.deinit();

    try vec1.append(&vec2, false);

    try std.testing.expect(vec1.length() == 2);
}

test "VectorReserveAndShrink" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: Allocator = gpa.allocator();
    var vector = try Vector(i32).init(allocator, null);
    defer vector.deinit();

    try vector.reserve(0xAA);
    const reserved = vector.length();
    try vector.shrink();

    try std.testing.expect(vector.length() == 1 and reserved == 170);
}

test "VectorFirstLast" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: Allocator = gpa.allocator();
    var vector = try Vector(i32).init(allocator, null);
    defer vector.deinit();

    const first = vector.first();
    try std.testing.expect(first == &vector.data[0] and vector.last() == first and first == undefined);
}
