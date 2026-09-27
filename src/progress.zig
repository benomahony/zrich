const std = @import("std");
const text = @import("text.zig");
const Context = @import("context.zig").Context;
const Style = @import("style.zig").Style;

/// A single progress snapshot. The caller owns scheduling and task state.
pub const Progress = struct {
    label: []const u8 = "Progress",
    completed: u64,
    total: u64,
    bar_width: usize = 24,
    style: Style = .{ .fg = .{ .named = .green } },

    /// Live mode replaces the current line only on interactive terminals.
    /// Pass finished=true on the final update to terminate that line.
    pub fn render(self: Progress, ctx: Context, live: bool, finished: bool) !void {
        try text.validate(self.label);
        if (std.mem.indexOfScalar(u8, self.label, '\n') != null) return error.MultilineLabel;
        if (ctx.options.width < 10 or ctx.options.width > 4096 or self.bar_width == 0) return error.InvalidWidth;
        const bar_columns = @min(self.bar_width, ctx.options.width - 9);
        const label_columns = ctx.options.width - bar_columns - 9;
        var label: text.Line = .{ .bytes = "", .width = 0 };
        if (label_columns > 0) {
            var labels: text.Lines = .{ .text = self.label, .columns = label_columns };
            label = (try labels.next()).?;
        }
        const completed = @min(self.completed, self.total);
        const filled: usize = if (self.total == 0) 0 else @intCast(@as(u128, completed) * bar_columns / self.total);
        const percent: u8 = if (self.total == 0) 0 else @intCast(@as(u128, completed) * 100 / self.total);
        if (live and ctx.options.interactive) try ctx.writer.writeAll("\r\x1b[2K");
        try ctx.writer.writeAll(label.bytes);
        try ctx.writer.writeAll(" [");
        try self.style.start(ctx.writer, ctx.options.color);
        try ctx.repeat(if (ctx.options.unicode) "━" else "=", filled);
        try Style.reset(ctx.writer, ctx.options.color);
        try ctx.repeat(if (ctx.options.unicode) "─" else "-", bar_columns - filled);
        try ctx.writer.print("] {d: >3}%", .{percent});
        if (!live or !ctx.options.interactive or finished) try ctx.writer.writeByte('\n');
    }
};
