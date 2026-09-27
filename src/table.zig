const std = @import("std");
const text = @import("text.zig");
const Context = @import("context.zig").Context;
const Alignment = @import("context.zig").Alignment;
const Style = @import("style.zig").Style;

pub const Column = struct {
    header: []const u8,
    alignment: Alignment = .left,
    style: Style = .{},
};
pub const Cell = struct {
    text: []const u8,
    style: Style = .{},
};

/// All strings/slices are borrowed for the duration of render().
pub const Table = struct {
    columns: []const Column,
    rows: []const []const Cell,
    header_style: Style = .{ .bold = true, .fg = .{ .named = .cyan } },
    border_style: Style = .{ .dim = true },

    pub fn render(self: Table, ctx: Context, allocator: std.mem.Allocator) !void {
        const count = self.columns.len;
        if (count == 0) return error.NoColumns;
        if (ctx.options.width > 4096 or ctx.options.width < 5 or count > (ctx.options.width - 1) / 4) return error.InvalidWidth;
        for (self.rows) |row| if (row.len != count) return error.ColumnCountMismatch;
        const sizes = try allocator.alloc(usize, count);
        defer allocator.free(sizes);
        const minimums = try allocator.alloc(usize, count);
        defer allocator.free(minimums);
        const iterators = try allocator.alloc(text.Lines, count);
        defer allocator.free(iterators);
        var total: usize = count * 3 + 1;
        var minimum: usize = total;
        for (self.columns, 0..) |column, i| {
            sizes[i] = @min(ctx.options.width, @max(1, try text.width(column.header)));
            minimums[i] = minWidth(column.header);
            for (self.rows) |row| {
                sizes[i] = @max(sizes[i], @min(ctx.options.width, try text.width(row[i].text)));
                minimums[i] = @max(minimums[i], minWidth(row[i].text));
            }
            total += sizes[i];
            minimum += minimums[i];
        }
        if (minimum > ctx.options.width) return error.InvalidWidth;
        if (total > ctx.options.width) {
            // Find the largest common cap that fits. This avoids a per-character
            // shrinking loop for many very long cells: O(columns * log(width)).
            const budget = ctx.options.width - count * 3 - 1;
            var lo: usize = 1;
            var hi: usize = ctx.options.width;
            while (lo < hi) {
                const cap = lo + (hi - lo + 1) / 2;
                var used: usize = 0;
                for (sizes, minimums) |size, min| used += @max(min, @min(size, cap));
                if (used <= budget) lo = cap else hi = cap - 1;
            }
            var used: usize = 0;
            for (sizes, minimums) |size, min| used += @max(min, @min(size, lo));
            var spare = budget - used;
            for (sizes, minimums) |*size, min| {
                const natural = size.*;
                size.* = @max(min, @min(natural, lo));
                if (spare > 0 and size.* < natural) {
                    size.* += 1;
                    spare -= 1;
                }
            }
        }
        const b = ctx.border();
        try self.rule(ctx, sizes, b.tl, b.top, b.tr);
        for (self.columns, 0..) |column, i| iterators[i] = .{ .text = column.header, .columns = sizes[i] };
        try self.renderRow(ctx, sizes, iterators, null);
        try self.rule(ctx, sizes, b.ml, b.cross, b.mr);
        for (self.rows) |cells| {
            for (cells, 0..) |cell, i| iterators[i] = .{ .text = cell.text, .columns = sizes[i] };
            try self.renderRow(ctx, sizes, iterators, cells);
        }
        try self.rule(ctx, sizes, b.bl, b.bottom, b.br);
    }

    fn minWidth(value: []const u8) usize {
        var it = (std.unicode.Utf8View.init(value) catch unreachable).iterator();
        var min: usize = 1;
        while (it.nextCodepoint()) |cp| min = @max(min, text.codepointWidth(cp));
        return min;
    }

    fn renderRow(self: Table, ctx: Context, sizes: []const usize, iterators: []text.Lines, cells: ?[]const Cell) !void {
        const b = ctx.border();
        while (true) {
            var more = false;
            for (iterators) |it| more = more or !it.done;
            if (!more) break;
            try ctx.styled(b.v, self.border_style);
            for (iterators, sizes, 0..) |*it, size, i| {
                const line = (try it.next()) orelse text.Line{ .bytes = "", .width = 0 };
                try ctx.writer.writeByte(' ');
                const style = if (cells) |values| Style.overlay(self.columns[i].style, values[i].style) else self.header_style;
                try ctx.line(line, size, self.columns[i].alignment, style);
                try ctx.writer.writeByte(' ');
                try ctx.styled(b.v, self.border_style);
            }
            try ctx.writer.writeByte('\n');
        }
    }

    fn rule(self: Table, ctx: Context, sizes: []const usize, left: []const u8, middle: []const u8, right: []const u8) !void {
        try self.border_style.start(ctx.writer, ctx.options.color);
        try ctx.writer.writeAll(left);
        for (sizes, 0..) |size, i| {
            if (i != 0) try ctx.writer.writeAll(middle);
            try ctx.repeat(ctx.border().h, size + 2);
        }
        try ctx.writer.writeAll(right);
        try Style.reset(ctx.writer, ctx.options.color);
        try ctx.writer.writeByte('\n');
    }
};
