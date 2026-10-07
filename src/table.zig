const std = @import("std");
const text = @import("text.zig");
const Context = @import("context.zig").Context;
const Alignment = @import("context.zig").Alignment;
const Style = @import("style.zig").Style;

/// What a column does with a line that is wider than the column.
pub const Overflow = enum {
    /// Continue the line on the next row.
    wrap,
    /// Keep the start of the line and mark the cut with an ellipsis.
    ellipsis_end,
    /// Keep the end of the line, e.g. a file name, and mark the cut with an ellipsis.
    ellipsis_start,
};

pub const Column = struct {
    header: []const u8,
    alignment: Alignment = .left,
    style: Style = .{},
    overflow: Overflow = .wrap,
    /// Take an equal share of space left after every column reaches its natural width.
    expand: bool = false,
};
pub const Cell = struct {
    text: []const u8,
    style: Style = .{},
};

/// All strings/slices are borrowed for the duration of render().
pub const Table = struct {
    columns: []const Column,
    rows: []const []const Cell,
    /// Rows drawn below a separator after the body, e.g. totals.
    footer: []const []const Cell = &.{},
    header_style: Style = .{ .bold = true, .fg = .{ .named = .cyan } },
    border_style: Style = .{ .dim = true },
    footer_style: Style = .{ .bold = true },

    pub fn render(self: Table, ctx: Context, allocator: std.mem.Allocator) !void {
        const count = self.columns.len;
        if (count == 0) return error.NoColumns;
        if (ctx.options.width > 4096 or ctx.options.width < 5 or count > (ctx.options.width - 1) / 4) return error.InvalidWidth;
        for (self.rows) |row| if (row.len != count) return error.ColumnCountMismatch;
        for (self.footer) |row| if (row.len != count) return error.ColumnCountMismatch;
        const sizes = try allocator.alloc(usize, count);
        defer allocator.free(sizes);
        const minimums = try allocator.alloc(usize, count);
        defer allocator.free(minimums);
        const iterators = try allocator.alloc(CellLines, count);
        defer allocator.free(iterators);
        var total: usize = count * 3 + 1;
        var minimum: usize = total;
        for (self.columns, 0..) |column, i| {
            sizes[i] = @min(ctx.options.width, @max(1, try text.width(column.header)));
            minimums[i] = minWidth(column.header);
            for ([_][]const []const Cell{ self.rows, self.footer }) |rows| for (rows) |row| {
                sizes[i] = @max(sizes[i], @min(ctx.options.width, try text.width(row[i].text)));
                minimums[i] = @max(minimums[i], minWidth(row[i].text));
            };
            // Shortened cells can always shrink to a single column.
            if (column.overflow != .wrap) minimums[i] = 1;
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
        } else if (total < ctx.options.width) {
            var expandable: usize = 0;
            for (self.columns) |column| expandable += @intFromBool(column.expand);
            if (expandable > 0) {
                var spare = ctx.options.width - total;
                for (self.columns, 0..) |column, i| {
                    if (!column.expand) continue;
                    const growth = spare / expandable + @intFromBool(spare % expandable != 0);
                    sizes[i] += growth;
                    spare -= growth;
                    expandable -= 1;
                }
                if (expandable != 0 or spare != 0) unreachable;
            }
        }
        const b = ctx.border();
        const mark: text.Line = if (ctx.options.unicode) .{ .bytes = "…", .width = 1 } else .{ .bytes = "...", .width = 3 };
        try self.rule(ctx, sizes, b.tl, b.top, b.tr);
        for (self.columns, 0..) |column, i| iterators[i] = .init(column.header, sizes[i], column.overflow, mark);
        try self.renderRow(ctx, sizes, iterators, null, self.header_style);
        try self.rule(ctx, sizes, b.ml, b.cross, b.mr);
        for (self.rows) |cells| {
            for (cells, 0..) |cell, i| iterators[i] = .init(cell.text, sizes[i], self.columns[i].overflow, mark);
            try self.renderRow(ctx, sizes, iterators, cells, .{});
        }
        if (self.footer.len != 0) try self.rule(ctx, sizes, b.ml, b.cross, b.mr);
        for (self.footer) |cells| {
            for (cells, 0..) |cell, i| iterators[i] = .init(cell.text, sizes[i], self.columns[i].overflow, mark);
            try self.renderRow(ctx, sizes, iterators, cells, self.footer_style);
        }
        try self.rule(ctx, sizes, b.bl, b.bottom, b.br);
    }

    fn minWidth(value: []const u8) usize {
        var it = (std.unicode.Utf8View.init(value) catch unreachable).iterator();
        var min: usize = 1;
        while (it.nextCodepoint()) |cp| min = @max(min, text.codepointWidth(cp));
        return min;
    }

    /// Header rows pass no cells and use `row_style` alone; other rows layer
    /// column, row and cell styles.
    fn renderRow(self: Table, ctx: Context, sizes: []const usize, iterators: []CellLines, cells: ?[]const Cell, row_style: Style) !void {
        const b = ctx.border();
        while (true) {
            var more = false;
            for (iterators) |it| more = more or !it.lines.done;
            if (!more) break;
            try ctx.styled(b.v, self.border_style);
            for (iterators, sizes, 0..) |*it, size, i| {
                const piece = (try it.next()) orelse Piece{};
                try ctx.writer.writeByte(' ');
                const style = if (cells) |values| Style.overlay(Style.overlay(self.columns[i].style, row_style), values[i].style) else row_style;
                try piece.render(ctx, size, self.columns[i].alignment, style);
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

/// One line of a cell, with an ellipsis where it was shortened.
const Piece = struct {
    line: text.Line = .{ .bytes = "", .width = 0 },
    mark: text.Line = .{ .bytes = "", .width = 0 },
    mark_first: bool = false,

    fn render(self: Piece, ctx: Context, columns: usize, alignment: Alignment, style: Style) !void {
        const remaining = columns - self.line.width - self.mark.width;
        const before = switch (alignment) {
            .left => 0,
            .center => remaining / 2,
            .right => remaining,
        };
        try ctx.repeat(" ", before);
        try style.start(ctx.writer, ctx.options.color);
        if (self.mark_first) try ctx.writer.writeAll(self.mark.bytes);
        try ctx.writer.writeAll(self.line.bytes);
        if (!self.mark_first) try ctx.writer.writeAll(self.mark.bytes);
        try Style.reset(ctx.writer, ctx.options.color);
        try ctx.repeat(" ", remaining - before);
    }
};

/// Splits a cell into lines that fit its column, by wrapping or shortening.
const CellLines = struct {
    lines: text.Lines,
    columns: usize,
    overflow: Overflow,
    mark: text.Line,

    fn init(value: []const u8, columns: usize, overflow: Overflow, mark: text.Line) CellLines {
        // Shortened cells only break at newlines; next() cuts each line to fit.
        const limit = if (overflow == .wrap) columns else std.math.maxInt(usize);
        return .{ .lines = .{ .text = value, .columns = limit }, .columns = columns, .overflow = overflow, .mark = mark };
    }

    fn next(self: *CellLines) !?Piece {
        const line = (try self.lines.next()) orelse return null;
        if (line.width <= self.columns) return .{ .line = line };
        // Only the ASCII "..." can be wider than a column; it is cut to fit.
        var mark = self.mark;
        if (mark.width > self.columns) mark = .{ .bytes = mark.bytes[0..self.columns], .width = self.columns };
        const room = self.columns - mark.width;
        return switch (self.overflow) {
            .wrap => unreachable,
            .ellipsis_end => .{ .line = text.prefix(line.bytes, room), .mark = mark },
            .ellipsis_start => .{ .line = text.suffix(line.bytes, room), .mark = mark, .mark_first = true },
        };
    }
};
