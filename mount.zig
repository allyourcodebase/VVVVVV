const std = @import("std");
const data_zip = @embedFile("data_zip");
const lang_zip = @embedFile("lang_zip");
const fonts_zip = @embedFile("fonts_zip");

const zips = [_]struct { name: [:0]const u8, data: []const u8 }{
    .{ .name = "data.zip", .data = data_zip },
    .{ .name = "lang", .data = lang_zip },
    .{ .name = "fonts", .data = fonts_zip },
};

extern fn PHYSFS_mount([*:0]const u8, ?[*:0]const u8, c_int) callconv(.c) c_int;
extern fn PHYSFS_mountMemory(*const anyopaque, u64, ?*const anyopaque, [*:0]const u8, ?[*:0]const u8, c_int) callconv(.c) c_int;

export fn VVVVVV_physfs_mount(path: [*:0]const u8, mount_point: ?[*:0]const u8, append: c_int) callconv(.c) c_int {
    const basename = std.fs.path.basename(std.mem.sliceTo(path, 0));
    for (zips) |zip| {
        if (std.mem.eql(u8, basename, std.mem.sliceTo(zip.name, 0))) {
            return PHYSFS_mountMemory(zip.data.ptr, zip.data.len, null, zip.name, mount_point, append);
        }
    }
    return PHYSFS_mount(path, mount_point, append);
}
