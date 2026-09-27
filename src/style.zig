const std = @import("std");

pub const NamedColor = enum(u4) {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
};

pub const Color = union(enum) {
    named: NamedColor,
    indexed: u8,
    rgb: struct { r: u8, g: u8, b: u8 },

    pub fn parse(value: []const u8) error{InvalidColor}!Color {
        if (std.meta.stringToEnum(NamedColor, value)) |name| return .{ .named = name };
        if (value.len == 7 and value[0] == '#') {
            for (value[1..]) |ch| if (!std.ascii.isHex(ch)) return error.InvalidColor;
            const n = std.fmt.parseInt(u24, value[1..], 16) catch return error.InvalidColor;
            return .{ .rgb = .{ .r = @intCast(n >> 16), .g = @truncate(n >> 8), .b = @truncate(n) } };
        }
        if (std.mem.startsWith(u8, value, "color(") and std.mem.endsWith(u8, value, ")")) {
            return .{ .indexed = std.fmt.parseInt(u8, value[6 .. value.len - 1], 10) catch return error.InvalidColor };
        }
        return error.InvalidColor;
    }

    fn write(self: Color, writer: *std.Io.Writer, background: bool) !void {
        const base: u8 = if (background) 40 else 30;
        switch (self) {
            .named => |name| {
                const n: u8 = @intFromEnum(name);
                try writer.print(";{d}", .{base + n % 8 + @as(u8, if (n >= 8) 60 else 0)});
            },
            .indexed => |n| try writer.print(";{d};5;{d}", .{ base + 8, n }),
            .rgb => |c| try writer.print(";{d};2;{d};{d};{d}", .{ base + 8, c.r, c.g, c.b }),
        }
    }
};

pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    strike: bool = false,

    pub fn overlay(parent: Style, child: Style) Style {
        return .{
            .fg = child.fg orelse parent.fg,
            .bg = child.bg orelse parent.bg,
            .bold = parent.bold or child.bold,
            .dim = parent.dim or child.dim,
            .italic = parent.italic or child.italic,
            .underline = parent.underline or child.underline,
            .strike = parent.strike or child.strike,
        };
    }

    pub fn parse(expression: []const u8) !Style {
        var result: Style = .{};
        var tokens = std.mem.tokenizeScalar(u8, expression, ' ');
        var found = false;
        while (tokens.next()) |token| {
            found = true;
            if (std.mem.eql(u8, token, "bold")) result.bold = true else if (std.mem.eql(u8, token, "dim")) result.dim = true else if (std.mem.eql(u8, token, "italic")) result.italic = true else if (std.mem.eql(u8, token, "underline")) result.underline = true else if (std.mem.eql(u8, token, "strike")) result.strike = true else if (std.mem.eql(u8, token, "on")) {
                result.bg = try Color.parse(tokens.next() orelse return error.InvalidStyle);
            } else result.fg = try Color.parse(token);
        }
        if (!found) return error.InvalidStyle;
        return result;
    }

    /// Starts a complete style. Call reset after writing its text.
    pub fn start(self: Style, writer: *std.Io.Writer, color: bool) !void {
        if (!color) return;
        try writer.writeAll("\x1b[0");
        if (self.bold) try writer.writeAll(";1");
        if (self.dim) try writer.writeAll(";2");
        if (self.italic) try writer.writeAll(";3");
        if (self.underline) try writer.writeAll(";4");
        if (self.strike) try writer.writeAll(";9");
        if (self.fg) |fg| try fg.write(writer, false);
        if (self.bg) |bg| try bg.write(writer, true);
        try writer.writeByte('m');
    }

    pub fn reset(writer: *std.Io.Writer, color: bool) !void {
        if (color) try writer.writeAll("\x1b[0m");
    }
};
