const std = @import("std");
const zrich = @import("zrich");

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    var options = try zrich.Options.detect(init.io, .stdout(), init.environ_map);
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--color")) options.color = true else if (std.mem.eql(u8, arg, "--plain")) {
            options.color = false;
            options.interactive = false;
        } else if (std.mem.eql(u8, arg, "--ascii")) options.unicode = false else if (std.mem.startsWith(u8, arg, "--width=")) {
            options.width = try std.fmt.parseInt(usize, arg[8..], 10);
        } else return error.UnknownArgument;
    }
    const console: zrich.Console = .{
        .writer = &stdout.interface,
        .allocator = init.gpa,
        .options = options,
    };
    try console.markup("[bold cyan]zrich[/]  expressive terminal output, written in Zig");
    try console.print("");
    try console.panel(.{
        .title = "Small API. Rich output.",
        .text = "Styles, nested markup, wrapping tables, panels, and progress.\nExplicit allocators. Any writer. Zero runtime dependencies.",
    });
    try console.print("");
    try console.markup("[bold]Nested styles:[/] [green]ready [bold]to ship[/] in green[/]  [[literal brackets]");
    try console.markup("[#e5a94b]Truecolor[/]  [color(141)]256 colors[/]  [bold white on blue] backgrounds [/]");
    try console.print("");
    try console.table(.{
        .columns = &.{
            .{ .header = "Component" },
            .{ .header = "Status" },
            .{ .header = "Details" },
        },
        .rows = &.{
            &.{ .{ .text = "Styles" }, .{ .text = "ready", .style = .{ .fg = .{ .named = .green } } }, .{ .text = "ANSI, RGB, 256 colors" } },
            &.{ .{ .text = "Tables" }, .{ .text = "ready", .style = .{ .fg = .{ .named = .green } } }, .{ .text = "Automatic column widths\nMultiline cells and alignment" } },
            &.{ .{ .text = "Unicode" }, .{ .text = "基础" }, .{ .text = "CJK and combining: cafe\u{301}" } },
            &.{ .{ .text = "Allocation" }, .{ .text = "explicit" }, .{ .text = "Only table layout allocates" } },
        },
    });
    try console.print("");
    try console.progress(.{ .label = "Building", .completed = 7, .total = 10 });
    try console.progress(.{ .label = "Tests", .completed = 10, .total = 10, .style = .{ .fg = .{ .named = .cyan } } });
    try console.flush();
}
