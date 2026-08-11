# Zig Filewatch
**Zig Filewatch** is a program inspired by a problem I was having when trying to build a web application funny enough.
The stack was htmx, tailscale, and a zig web server.
In the process of doing this I didn't find a program that could watch my files for changes and run commands to rebuild and rerun my server in a way I liked.
This is the inspiration for this application.

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
                .{ .action = "build_zig" },
                .{ .action = "restart" },
            }
        },
    }
}
```
