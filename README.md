# zrich

Rich-style CLI output, written in Zig. An early, usable foundation with no runtime
dependencies: styles, nested markup, panels, wrapping tables, and progress bars.

Targets **Zig 0.17** (0.17.0-dev.2350 or newer). The public module is `@import("zrich")`.

Verified on macOS with Zig 0.17.0-dev.2350+bc616127e: all 25 tests
pass, including allocation-failure cleanup and writer-error propagation. The demo
also cross-compiles in ReleaseSafe for x86_64 Linux and Windows; those binaries
have not been run on their target operating systems. Automatic terminal colour,
redirected output, and NO_COLOR behavior were checked locally.

```sh
zig build test
zig build demo
```

`zig build demo` builds and runs the showcase, and refreshes the standalone
binary at `zig-out/bin/zrich-demo`. `zig build` installs that binary without
running it. The demo has no command-line options; it simply shows the library.

Colour is automatic: supported terminals get styled output, while redirected
output stays free of colour escapes. The demo respects non-empty `NO_COLOR` and
`TERM=dumb`, detects the terminal width, and lets `COLUMNS` override it. Configure
the library through `zrich.Options` in your own application.

## Quick start

```zig
const std = @import("std");
const zrich = @import("zrich");

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    const console: zrich.Console = .{
        .writer = &stdout.interface,
        .allocator = init.gpa,
        .options = try zrich.Options.detect(init.io, .stdout(), init.environ_map),
    };

    try console.markup("[bold green]Build succeeded[/]");
    try console.panel(.{
        .title = "zrich",
        .text = "Readable terminal output. Pure Zig.",
        .width = 48,
    });
    try console.table(.{
        .columns = &.{
            .{ .header = "Task" },
            .{ .header = "Count", .alignment = .right },
        },
        .rows = &.{
            &.{ .{ .text = "Compiled" }, .{ .text = "42" } },
            &.{ .{ .text = "Cached" }, .{ .text = "108" } },
        },
    });
    try console.progress(.{ .label = "Building", .completed = 7, .total = 10 });
    try console.flush();
}
```

See [`examples/demo.zig`](examples/demo.zig) for a complete showcase.
[`examples/demo-output.txt`](examples/demo-output.txt) contains captured plain output.

## Add to a project

Until this package has a published URL, put it alongside your project and add a
local dependency to your existing `build.zig.zon`:

```zig
.dependencies = .{
    .zrich = .{ .path = "../zrich" },
},
```

Then, in `build.zig`, after creating your executable:

```zig
const zrich = b.dependency("zrich", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zrich", zrich.module("zrich"));
```

## API and ownership

`Console` borrows a `*std.Io.Writer`. Use stdout, stderr, a file writer,
`std.Io.Writer.fixed`, or `std.Io.Writer.Allocating`. The caller owns and flushes
the writer. Console keeps no global state and does not retain text.

| Method | Behavior |
| --- | --- |
| `write(text)` | Literal text, no newline |
| `print(text)` | Literal text plus newline |
| `styled(text, style)` | Styled literal text, no newline |
| `markup(text)` | Nested style tags plus newline |
| `panel(panel)` | Bordered, hard-wrapped text |
| `table(table)` | Automatic column sizing, alignment, multiline cells, wrapping or ellipsis shortening (`Column.overflow`), and footer rows |
| `progress(snapshot)` | One progress line |
| `updateProgress(snapshot, finished)` | Replaces the current terminal line and flushes |
| `flush()` | Flushes the borrowed writer |

Only table layout allocates, using the supplied allocator; all temporary memory
is released before return, including on errors. Table cells and panel text are
literal; style them with `Cell.style`, `Column.style`, or `Panel.style`.
The renderers can also be called directly with a `Context`.

Calls are synchronous and not internally synchronized. Applications sharing a
writer between threads must serialize writes. I/O failures propagate to the
caller; if a writer fails mid-style, a terminal reset cannot be guaranteed.

## Markup

```text
[bold cyan]Heading[/]
[green]Parent [bold]nested[/] parent again[/]
[#ff8040 on black]RGB foreground[/]
[color(141)]Indexed color[/]
[[literal brackets]
```

Styles: `bold`, `dim`, `italic`, `underline`, `strike`; the sixteen named ANSI
colors (`red`, `bright_red`, etc.); `#rrggbb`; `color(0)` through `color(255)`;
and `on COLOR` for backgrounds. Inner styles inherit outer attributes and can
override colors. Use `[/]` to close the innermost tag, or the exact opening
expression, e.g. `[bold green]ok[/bold green]`. Escape `[` with `[[`.

The parser accepts at most 32 nested tags. It validates the complete input
before writing; malformed markup returns an error without partial output.
Literal methods do not interpret tags, so use them for user-provided text.

## Terminal behavior and limits

- Defaults are 80 columns, Unicode borders, no color, and no live updates.
  `Options.detect` checks TTY/ANSI support and the terminal's current width;
  `COLUMNS` overrides that width when present. Automatic resize tracking is pending.
- Set `unicode = false` for ASCII borders and progress bars. User text is kept
  as supplied. Color detection does not negotiate palette depth: indexed and RGB
  colors require a compatible terminal. There is no color quantization yet.
- Table columns can set `expand = true` to share spare terminal width after every
  column reaches its natural width.
- Unicode 16.0 scalar-width tables support CJK full-width characters and combining
  marks. Ambiguous-width characters count as one. Emoji ZWJ sequences, flags,
  variation selectors, and complex grapheme shaping are **not** measured as full
  clusters yet, so those can misalign. This is not full Rich Unicode parity.
- Wrapping is hard wrapping, not word wrapping. It preserves UTF-8 scalar
  boundaries and following combining marks. Panel titles and progress labels
  are clipped. Invalid UTF-8 and C0/C1 controls (except newline) are rejected,
  including raw escape sequences and tabs. Titles and progress labels must be
  single-line. Widths above 4096 and layouts too narrow for their content return
  errors instead of underflowing or looping.
- Live progress is one line, driven by the caller; no worker thread, timer, cursor
  hiding, or alternate screen. Call `updateProgress(snapshot, true)` to finish.
  Redirected output receives newline snapshots without cursor-control escapes.
  A zero total displays an empty bar at 0%; completion beyond total is clamped.

## Next steps

Full grapheme measurement and word wrapping; styled text spans inside layout;
terminal resize detection; multiple live tasks, spinners and ETA; tree rendering;
structured value pretty-printing; logging; Markdown and syntax highlighting.
This is a first version, not a feature-complete port of Python Rich.

Inspired by [Rich](https://github.com/Textualize/rich). Implemented independently
in Zig. The checked-in Unicode width tables can be regenerated using
`python3 tools/generate_width.py`; Python is only a development utility.
