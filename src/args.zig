const ConstU8GraphConfig = @import("drivers/graph_const_u8.zig").Config;
const U32GraphConfig = @import("drivers/graph_u32.zig").Config;
const ConfigurationGraphConfig = @import("drivers/graph_from_config.zig").Config;

pub const Options = struct {
    help: bool = false,
    __commands__: union(enum) {
        driver_graph_const_u8: ConstU8GraphConfig,
        driver_graph_u32: U32GraphConfig,
        driver_graph_from_config: ConfigurationGraphConfig,

        pub const __messages__ = .{
            .driver_graph_const_u8 = "Driver (Graph []const u8)",
            .driver_graph_u32 = "Driver (Graph u32)",
            .driver_graph_from_config = "Driver (Graph from config)",
        };
    },

    pub const __shorts__ = .{
        .help = .h,
    };

    pub const __messages__ = .{
    };
};
