//! zrich: composable terminal output in pure Zig. No runtime dependencies.
const std = @import("std");
const markup_parser = @import("markup.zig");
pub const text = @import("text.zig");
pub const Style = @import("style.zig").Style;
pub const Color = @import("style.zig").Color;
pub const NamedColor = @import("style.zig").NamedColor;
pub const Options = @import("context.zig").Options;
pub const Context = @import("context.zig").Context;
pub const Alignment = @import("context.zig").Alignment;
pub const Panel = @import("panel.zig").Panel;
pub const Table = @import("table.zig").Table;
pub const Column = @import("table.zig").Column;
pub const Overflow = @import("table.zig").Overflow;
pub const Cell = @import("table.zig").Cell;
pub const Progress = @import("progress.zig").Progress;

pub const Console = struct {
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    options: Options = .{},

    pub fn context(self: Console) Context {
        return .{ .writer = self.writer, .options = self.options };
    }

    /// Literal text; brackets have no special meaning. Does not append a newline.
    pub fn write(self: Console, value: []const u8) !void {
        try text.validate(value);
        try self.writer.writeAll(value);
    }

    /// Literal text followed by a newline.
    pub fn print(self: Console, value: []const u8) !void {
        try self.write(value);
        try self.writer.writeByte('\n');
    }

    /// Styled literal text, without an appended newline.
    pub fn styled(self: Console, value: []const u8, style: Style) !void {
        try text.validate(value);
        try self.context().styled(value, style);
    }

    /// Nested [style]markup[/] followed by a newline. [[ emits a literal [.
    pub fn markup(self: Console, value: []const u8) !void {
        try markup_parser.render(self.context(), value);
        try self.writer.writeByte('\n');
    }

    pub fn panel(self: Console, value: Panel) !void {
        try value.render(self.context());
    }

    pub fn table(self: Console, value: Table) !void {
        try value.render(self.context(), self.allocator);
    }

    pub fn progress(self: Console, value: Progress) !void {
        try value.render(self.context(), false, true);
    }

    /// Flushes each update so a buffered writer displays live progress immediately.
    pub fn updateProgress(self: Console, value: Progress, finished: bool) !void {
        try value.render(self.context(), true, finished);
        try self.writer.flush();
    }

    pub fn flush(self: Console) !void {
        try self.writer.flush();
    }
};

test {
    _ = @import("tests.zig");
}
