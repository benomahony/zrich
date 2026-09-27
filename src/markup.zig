const std = @import("std");
const Style = @import("style.zig").Style;
const Context = @import("context.zig").Context;
const text = @import("text.zig");

pub const max_depth = 32;

/// Validate before writing: a malformed tag never leaves partial output.
pub fn render(ctx: Context, input: []const u8) !void {
    try text.validate(input);
    try parse(null, input);
    try parse(ctx, input);
}

fn parse(ctx: ?Context, input: []const u8) !void {
    const Frame = struct { style: Style, name: []const u8 };
    var stack: [max_depth]Frame = undefined;
    var depth: usize = 0;
    var pos: usize = 0;
    while (pos < input.len) {
        const style: Style = if (depth > 0) stack[depth - 1].style else .{};
        if (std.mem.startsWith(u8, input[pos..], "[[")) {
            if (ctx) |out| try out.styled("[", style);
            pos += 2;
        } else if (input[pos] == '[') {
            const end = std.mem.indexOfScalarPos(u8, input, pos + 1, ']') orelse return error.UnclosedTag;
            const tag = std.mem.trim(u8, input[pos + 1 .. end], " ");
            if (tag.len == 0) return error.InvalidStyle;
            if (tag[0] == '/') {
                if (depth == 0) return error.UnexpectedClose;
                if (tag.len > 1 and !std.mem.eql(u8, tag[1..], stack[depth - 1].name)) return error.MismatchedClose;
                depth -= 1;
            } else {
                if (depth == max_depth) return error.NestingTooDeep;
                stack[depth] = .{ .style = Style.overlay(style, try Style.parse(tag)), .name = tag };
                depth += 1;
            }
            pos = end + 1;
        } else {
            const end = std.mem.indexOfScalarPos(u8, input, pos, '[') orelse input.len;
            if (ctx) |out| try out.styled(input[pos..end], style);
            pos = end;
        }
    }
    if (depth != 0) return error.UnclosedTag;
}
