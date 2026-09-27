const std = @import("std");
const text = @import("text.zig");
const Context = @import("context.zig").Context;
const Style = @import("style.zig").Style;

pub const Panel = struct {
    text: []const u8,
    title: []const u8 = "",
    width: ?usize = null,
    style: Style = .{},
    border_style: Style = .{ .fg = .{ .named = .cyan } },

    pub fn render(self: Panel, ctx: Context) !void {
        const columns = @min(self.width orelse ctx.options.width, ctx.options.width);
        if (columns < 5 or columns > 4096) return error.InvalidWidth;
        try text.validate(self.text);
        try text.validate(self.title);
        if (std.mem.indexOfScalar(u8, self.title, '\n') != null) return error.MultilineTitle;
        var lines: text.Lines = .{ .text = self.text, .columns = columns - 4 };
        var check = lines;
        while (try check.next()) |_| {}
        var titles: text.Lines = .{ .text = self.title, .columns = columns - 4 };
        const title = (try titles.next()).?;
        const b = ctx.border();
        try self.border_style.start(ctx.writer, ctx.options.color);
        try ctx.writer.writeAll(b.tl);
        if (title.bytes.len > 0) {
            try ctx.writer.print(" {s} ", .{title.bytes});
            try ctx.repeat(b.h, columns - 4 - title.width);
        } else try ctx.repeat(b.h, columns - 2);
        try ctx.writer.writeAll(b.tr);
        try Style.reset(ctx.writer, ctx.options.color);
        try ctx.writer.writeByte('\n');
        while (try lines.next()) |line| {
            try ctx.styled(b.v, self.border_style);
            try ctx.writer.writeByte(' ');
            try ctx.line(line, columns - 4, .left, self.style);
            try ctx.writer.writeByte(' ');
            try ctx.styled(b.v, self.border_style);
            try ctx.writer.writeByte('\n');
        }
        try self.border_style.start(ctx.writer, ctx.options.color);
        try ctx.writer.writeAll(b.bl);
        try ctx.repeat(b.h, columns - 2);
        try ctx.writer.writeAll(b.br);
        try Style.reset(ctx.writer, ctx.options.color);
        try ctx.writer.writeByte('\n');
    }
};
