const std = @import("std");
const rich = @import("root.zig");
const expect = std.testing.expect;
const equal = std.testing.expectEqualStrings;

fn console(writer: *std.Io.Writer, options: rich.Options) rich.Console {
    return .{ .writer = writer, .allocator = std.testing.allocator, .options = options };
}

test "nested markup restores parent color and weight" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try console(&writer, .{ .color = true }).markup("[green]a[bold]b[/]c[/]");
    try equal("\x1b[0;32ma\x1b[0m\x1b[0;1;32mb\x1b[0m\x1b[0;32mc\x1b[0m\n", writer.buffered());
}

test "plain markup and literal brackets" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try console(&writer, .{}).markup("[bold red]error[/bold red] [[file]");
    try equal("error [file]\n", writer.buffered());
}

test "invalid markup and terminal controls write nothing" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const out = console(&writer, .{});
    try std.testing.expectError(error.UnclosedTag, out.markup("prefix [red]bad"));
    try std.testing.expectError(error.MismatchedClose, out.markup("[red]bad[/blue]"));
    try std.testing.expectError(error.UnexpectedClose, out.markup("[/]"));
    try std.testing.expectError(error.InvalidColor, out.markup("[unknown]bad[/]"));
    try std.testing.expectError(error.ControlCharacter, out.print("x\x1b[2J"));
    try std.testing.expectError(error.InvalidUtf8, out.print("\xff"));
    try equal("", writer.buffered());
}

test "RGB and indexed background style" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const style = try rich.Style.parse("bold #ff8040 on color(21)");
    try console(&writer, .{ .color = true }).styled("ok", style);
    try equal("\x1b[0;1;38;2;255;128;64;48;5;21mok\x1b[0m", writer.buffered());
}

test "display width and wrapping keep combining marks attached" {
    try std.testing.expectEqual(@as(usize, 4), try rich.text.width("你好"));
    try std.testing.expectEqual(@as(usize, 4), try rich.text.width("cafe\u{301}"));
    try std.testing.expectEqual(@as(usize, 3), try rich.text.width("a\nxyz"));
    var lines: rich.text.Lines = .{ .text = "e\u{301}你好\n", .columns = 3 };
    try equal("e\u{301}你", (try lines.next()).?.bytes);
    try equal("好", (try lines.next()).?.bytes);
    try equal("", (try lines.next()).?.bytes);
    try expect(try lines.next() == null);
}

test "panel wraps to requested width" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try console(&writer, .{ .width = 10, .unicode = false }).panel(.{ .title = "Hi", .text = "abcdefgh" });
    try equal("+ Hi ----+\n| abcdef |\n| gh     |\n+--------+\n", writer.buffered());
}

test "table alignment and multiline rows" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try console(&writer, .{ .unicode = false }).table(.{
        .columns = &.{ .{ .header = "Name" }, .{ .header = "N", .alignment = .right } },
        .rows = &.{&.{ .{ .text = "A\nB" }, .{ .text = "12" } }},
    });
    try equal("+------+----+\n| Name |  N |\n+------+----+\n| A    | 12 |\n| B    |    |\n+------+----+\n", writer.buffered());
}

test "narrow table wraps and never exceeds the width" {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try console(&writer, .{ .width = 15 }).table(.{
        .columns = &.{ .{ .header = "Long header" }, .{ .header = "中" } },
        .rows = &.{&.{ .{ .text = "abcdefghijk" }, .{ .text = "你好世界" } }},
    });
    var lines = std.mem.tokenizeScalar(u8, writer.buffered(), '\n');
    while (lines.next()) |line| try std.testing.expectEqual(@as(usize, 15), try rich.text.width(line));
}

test "invalid table shape and impossible width are errors" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.ColumnCountMismatch, console(&writer, .{}).table(.{
        .columns = &.{.{ .header = "x" }},
        .rows = &.{&.{}},
    }));
    try std.testing.expectError(error.InvalidWidth, console(&writer, .{ .width = 9 }).table(.{
        .columns = &.{ .{ .header = "中" }, .{ .header = "文" } },
        .rows = &.{},
    }));
    try equal("", writer.buffered());
}

test "progress clamps completion and handles zero totals" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const out = console(&writer, .{ .unicode = false });
    try out.progress(.{ .label = "Job", .completed = 100, .total = 10, .bar_width = 4 });
    try out.progress(.{ .label = "Job", .completed = 0, .total = 0, .bar_width = 4 });
    try equal("Job [====] 100%\nJob [----]   0%\n", writer.buffered());
}

test "progress arithmetic does not overflow u64" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try console(&writer, .{ .unicode = false }).progress(.{ .label = "Max", .completed = std.math.maxInt(u64), .total = std.math.maxInt(u64), .bar_width = 4 });
    try equal("Max [====] 100%\n", writer.buffered());
}

test "live progress falls back to newline snapshots when redirected" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try (rich.Progress{ .label = "Job", .completed = 1, .total = 2, .bar_width = 4 }).render(console(&writer, .{ .unicode = false }).context(), true, false);
    try equal("Job [==--]  50%\n", writer.buffered());
}

test "interactive progress clears current line and terminates on finish" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const ctx = console(&writer, .{ .unicode = false, .interactive = true }).context();
    const progress: rich.Progress = .{ .label = "Job", .completed = 1, .total = 1, .bar_width = 4 };
    try progress.render(ctx, true, false);
    try progress.render(ctx, true, true);
    try equal("\r\x1b[2KJob [====] 100%\r\x1b[2KJob [====] 100%\n", writer.buffered());
}

test "writer failure propagates" {
    var buffer: [2]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.WriteFailed, console(&writer, .{}).print("too long"));
}

fn allocationFailureCase(allocator: std.mem.Allocator) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const out: rich.Console = .{ .writer = &writer, .allocator = allocator };
    try out.table(.{ .columns = &.{.{ .header = "x" }}, .rows = &.{&.{.{ .text = "y" }}} });
}

test "table cleans up on every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailureCase, .{});
}

test "markup nesting is bounded before output" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var input_buffer: [33 * 8 + 1]u8 = undefined;
    var input = std.Io.Writer.fixed(&input_buffer);
    for (0..33) |_| try input.writeAll("[red]");
    try input.writeByte('x');
    for (0..33) |_| try input.writeAll("[/]");
    const nested = input.buffered();
    try std.testing.expectError(error.NestingTooDeep, console(&writer, .{}).markup(nested));
    try equal("", writer.buffered());
    // Removing the outermost pair leaves exactly 32 nested tags.
    try console(&writer, .{}).markup(nested[5 .. nested.len - 3]);
    try equal("x\n", writer.buffered());
}

test "invalid widths and wide characters fail without partial panels" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.InvalidWidth, console(&writer, .{ .width = 0 }).panel(.{ .text = "x" }));
    try std.testing.expectError(error.InvalidWidth, console(&writer, .{ .width = 4097 }).panel(.{ .text = "x" }));
    try std.testing.expectError(error.CharacterTooWide, console(&writer, .{ .width = 5 }).panel(.{ .text = "中" }));
    try equal("", writer.buffered());
}

test "progress leaves the last terminal column free" {
    var buffer: [256]u8 = undefined;
    for (10..65) |width| {
        var writer = std.Io.Writer.fixed(&buffer);
        try console(&writer, .{ .width = width }).progress(.{ .label = "A very long progress label", .completed = 1, .total = 1, .bar_width = 100 });
        try expect(try rich.text.width(writer.buffered()) < width);
    }
}

test "hex colors reject non-hex characters" {
    try std.testing.expectError(error.InvalidColor, rich.Color.parse("#ff__00"));
    try std.testing.expectError(error.InvalidColor, rich.Color.parse("#+12345"));
}
