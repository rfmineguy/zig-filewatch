# Zig Filewatch
**Zig Filewatch** is a program inspired by a problem I was having when trying to build a web application funny enough.
The stack was htmx, tailscale, and a zig web server.
In the process of doing this I didn't find a program that could watch my files for changes and run commands to rebuild and rerun my server in a way I liked.
This is the inspiration for this application.

## Platform compatibility

The managed watch mode uses Unix process groups and an inherited pipe so a new
filesystem event can stop an action and all of the shell commands it started.
That implementation is currently Unix-only.

| Platform | Build status | Watch and cancellation status | Notes |
| --- | --- | --- | --- |
| macOS | Supported target | In development | Uses process groups and Unix pipe file descriptors. |
| Linux | Supported target | In development | Uses process groups and Unix pipe file descriptors. |
| Windows | Unsupported | Unsupported | Windows does not have POSIX process groups or inheritable Unix file descriptors. It needs a separate Job Object and `HANDLE`-based pipe implementation. |
| Other Unix-like systems | Untested | Untested | May work where the required POSIX process APIs are available. |

Windows is intentionally not a supported CI target for now. The project will
revisit it with a platform-specific process-control backend rather than trying
to emulate POSIX cancellation semantics.

## Configuration
The configuration for this program at the moment is a `zig.zon` file.
This is a very expressive configuration format invented by the [Zig](ziglang.org) programming language developers.
Due to this expressiveness I decided to use it as the main configuration language for **Zig Filewatch**.

```zig
.{
    .watchers = .{
        .{
            .patterns = .{ "**/*.zig" },
            .sequence = .{
                .{ .action = "build_css" },
                .{ .action = "build_zig" }
            }
        },
        .{
            .patterns = .{ "**/*.css" },
            .sequence = .{
                .{ .action = "build_css" },
                .{ .action = "build_zig" }
            }
        }
    },
    .actions = .{
        .{
            .id = "restart",
            .sequence = .{
                .{ .shell = "./zig-out/test" }
            }
        },
        .{
            .id = "build_css",
            .sequence = .{
                .{ .shell = "npx @tailwindcss/cli -i ./static/main.css -o ./static/output.css" },
            }
        },
        .{
            .id = "build_zig",
            .sequence = .{
                .{ .shell = "zig build" },
                // .{ .action = "build_zig" },
                .{ .action = "restart" },
            }
        },
    }
}
```
