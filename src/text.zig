const std = @import("std");
const widths = @import("unicode_width.zig");

pub const Error = error{ InvalidUtf8, ControlCharacter, InvalidWidth, CharacterTooWide };

pub fn validate(value: []const u8) Error!void {
    const view = std.unicode.Utf8View.init(value) catch return error.InvalidUtf8;
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        if ((cp < 0x20 and cp != '\n') or (cp >= 0x7f and cp < 0xa0)) return error.ControlCharacter;
    }
}

pub fn codepointWidth(cp: u21) usize {
    if (cp == '\n' or widths.contains(&widths.zero, cp)) return 0;
    return if (widths.contains(&widths.wide, cp)) 2 else 1;
}

/// Maximum display width of any line. Ambiguous-width characters count as one.
pub fn width(value: []const u8) Error!usize {
    try validate(value);
    var it = (std.unicode.Utf8View.init(value) catch unreachable).iterator();
    var longest: usize = 0;
    var current: usize = 0;
    while (it.nextCodepoint()) |cp| {
        if (cp == '\n') {
            longest = @max(longest, current);
            current = 0;
        } else current += codepointWidth(cp);
    }
    return @max(longest, current);
}

pub const Line = struct { bytes: []const u8, width: usize };

/// Hard-wraps at scalar boundaries, keeping following zero-width marks attached.
/// Input must first pass validate(). A final newline yields a final empty line.
pub const Lines = struct {
    text: []const u8,
    columns: usize,
    offset: usize = 0,
    done: bool = false,

    pub fn next(self: *Lines) Error!?Line {
        if (self.done) return null;
        if (self.columns == 0) return error.InvalidWidth;
        const start = self.offset;
        var used: usize = 0;
        while (self.offset < self.text.len) {
            const n = std.unicode.utf8ByteSequenceLength(self.text[self.offset]) catch return error.InvalidUtf8;
            if (n > self.text.len - self.offset) return error.InvalidUtf8;
            const cp = std.unicode.utf8Decode(self.text[self.offset..][0..n]) catch return error.InvalidUtf8;
            if (cp == '\n') {
                const end = self.offset;
                self.offset += n;
                return .{ .bytes = self.text[start..end], .width = used };
            }
            const w = codepointWidth(cp);
            if (w > self.columns) return error.CharacterTooWide;
            if (used + w > self.columns) return .{ .bytes = self.text[start..self.offset], .width = used };
            used += w;
            self.offset += n;
        }
        self.done = true;
        return .{ .bytes = self.text[start..], .width = used };
    }
};

/// Longest start of a single line that fits in `columns`, keeping following
/// zero-width marks attached. Input must first pass validate().
pub fn prefix(value: []const u8, columns: usize) Line {
    var it = std.unicode.Utf8View.initUnchecked(value).iterator();
    var used: usize = 0;
    while (true) {
        const start = it.i;
        const cp = it.nextCodepoint() orelse break;
        const w = codepointWidth(cp);
        if (used + w > columns) return .{ .bytes = value[0..start], .width = used };
        used += w;
    }
    return .{ .bytes = value, .width = used };
}

/// Longest end of a single line that fits in `columns`, never starting with an
/// orphaned zero-width mark. Input must first pass validate().
pub fn suffix(value: []const u8, columns: usize) Line {
    var it = std.unicode.Utf8View.initUnchecked(value).iterator();
    var used: usize = 0;
    while (it.nextCodepoint()) |cp| used += codepointWidth(cp);
    it.i = 0;
    while (used > columns) used -= codepointWidth(it.nextCodepoint().?);
    var start = it.i;
    while (it.nextCodepoint()) |cp| {
        if (codepointWidth(cp) != 0) break;
        start = it.i;
    }
    return .{ .bytes = value[start..], .width = used };
}
