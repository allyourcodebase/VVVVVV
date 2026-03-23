const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("upstream", .{});
    const sdl_dep = switch (target.result.os.tag) {
        .linux => b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
            // doesn't support SDL_RENDERER_TARGETTEXTURE
            .render_driver_ogl_es = false,
            // doesn't support SDL_RENDERER_ACCELERATED
            .render_driver_software = false,
        }),
        else => b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
            // TODO: disable render_driver_software here as well if/when SDL supports it
            //.render_driver_software = false,
        }),
    };
    const physfs_dep = b.dependency("physfs", .{});
    const zipcmdline_dep = b.dependency("zipcmdline", .{});
    const makeandplay_dep = b.dependency("makeandplay", .{});

    const exe = b.addExecutable(.{
        .name = "VVVVVV",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.addIncludePath(physfs_dep.path("src"));
    exe.addIncludePath(physfs_dep.path("extras"));

    exe.addCSourceFiles(.{
        .root = upstream.path("."),
        .files = &src,
        // redirect PHYSFS_mount to our own implementation so we can embedd assets into the binary
        .flags = &.{"-DPHYSFS_mount=VVVVVV_physfs_mount"},
    });
    exe.addCSourceFiles(.{
        .root = physfs_dep.path("."),
        .files = &physfs_src,
    });

    // TODO: if steam enabled add SteamNetwork.c
    // TODO: if GOG enabled add GOGNetwork.c

    exe.linkLibCpp();
    exe.linkLibrary(addPhysfs(b, target, optimize));
    {
        const sdl = sdl_dep.artifact("SDL2");
        exe.linkLibrary(sdl);
        exe.addIncludePath(sdl.getEmittedIncludeTree().path(b, "SDL2"));
        exe.linkLibrary(addFAudio(b, target, optimize, sdl));
    }
    exe.linkLibrary(addTinyXml2(b, target, optimize));
    exe.linkLibrary(addCHashmap(b, target, optimize));
    exe.linkLibrary(addSheenBidi(b, target, optimize));
    exe.linkLibrary(addLodepng(b, target, optimize));

    b.installArtifact(exe);

    {
        const zip_exe = zipcmdline_dep.artifact("zip");

        const run_data_zip = b.addRunArtifact(zip_exe);
        const data_zip_file = run_data_zip.addOutputFileArg("data.zip");
        run_data_zip.addDirectoryArg(makeandplay_dep.path("."));

        const run_lang_zip = b.addRunArtifact(zip_exe);
        const lang_zip_file = run_lang_zip.addOutputFileArg("lang.zip");
        run_lang_zip.addDirectoryArg(upstream.path("desktop_version/lang"));

        const run_fonts_zip = b.addRunArtifact(zip_exe);
        const fonts_zip_file = run_fonts_zip.addOutputFileArg("fonts.zip");
        run_fonts_zip.addDirectoryArg(upstream.path("desktop_version/fonts"));

        exe.linkLibrary(b.addLibrary(.{
            .name = "datazip",
            .root_module = b.createModule(.{
                .root_source_file = b.path("mount.zig"),
                .target = target,
                .optimize = .ReleaseSmall,
                .imports = &.{
                    .{ .name = "data_zip", .module = b.createModule(.{
                        .root_source_file = data_zip_file,
                    }) },
                    .{ .name = "lang_zip", .module = b.createModule(.{
                        .root_source_file = lang_zip_file,
                    }) },
                    .{ .name = "fonts_zip", .module = b.createModule(.{
                        .root_source_file = fonts_zip_file,
                    }) },
                },
            }),
        }));
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn addPhysfs(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step.Compile {
    const dep = b.dependency("physfs", .{});
    const root = dep.path(".");
    const lib = b.addLibrary(.{
        .name = "physfs",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    var files: std.ArrayList([]const u8) = .{};
    defer files.deinit(b.allocator);
    files.appendSlice(b.allocator, &.{
        "src/physfs.c",
        "src/physfs_archiver_dir.c",
        "src/physfs_archiver_unpacked.c",
        "src/physfs_archiver_zip.c",
        "src/physfs_byteorder.c",
        "src/physfs_unicode.c",
        "src/physfs_platform_posix.c",
        "src/physfs_platform_unix.c",
        "src/physfs_platform_windows.c",
        "src/physfs_platform_haiku.cpp",
        "src/physfs_platform_android.c",
    }) catch @panic("OOM");
    if (target.result.os.tag.isDarwin()) {
        files.append(b.allocator, "src/physfs_platform_apple.m") catch @panic("OOM");
    }
    lib.addCSourceFiles(.{
        .root = root,
        .files = files.toOwnedSlice(b.allocator) catch @panic("OOM"),
        .flags = &.{
            "-DPHYSFS_SUPPORTS_DEFAULT=0",
            "-DPHYSFS_SUPPORTS_ZIP=1",
        },
    });
    lib.linkLibCpp();
    return lib;
}


fn addTinyXml2(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step.Compile {
    const dep = b.dependency("tinyxml2", .{});
    const root = dep.path(".");
    const lib = b.addLibrary(.{
        .name = "tinyxml2",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.addCSourceFiles(.{
        .root = root,
        .files = &.{
            "tinyxml2.cpp",
        },
    });
    lib.installHeader(
        root.path(b, "tinyxml2.h"),
        "tinyxml2.h",
    );
    lib.linkLibCpp();
    return lib;
}

fn addCHashmap(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step.Compile {
    const dep = b.dependency("c_hashmap", .{});
    const root = dep.path(".");
    const lib = b.addLibrary(.{
        .name = "c-hashmap",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.addCSourceFiles(.{
        .root = root,
        .files = &.{
            "map.c",
        },
    });
    lib.installHeader(
        root.path(b, "map.h"),
        "c-hashmap/map.h",
    );
    lib.linkLibCpp();
    return lib;
}

fn addSheenBidi(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step.Compile {
    const dep = b.dependency("sheen_bidi", .{});
    const root = dep.path(".");
    const lib = b.addLibrary(.{
        .name = "sheenbidi",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    const headers_path = root.path(b, "Headers");
    lib.addIncludePath(headers_path);
    lib.addCSourceFiles(.{
        .root = root,
        .files = &.{
            "Source/SheenBidi.c",
        },
        .flags = &.{"-DSB_CONFIG_UNITY"},
    });
    lib.installHeadersDirectory(headers_path, ".", .{});
    lib.linkLibCpp();
    return lib;
}

fn addFAudio(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sdl: *Build.Step.Compile,
) *Build.Step.Compile {
    const dep = b.dependency("faudio", .{});
    const root = dep.path(".");
    const lib = b.addLibrary(.{
        .name = "faudio",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    const include_path = root.path(b, "include");
    lib.addIncludePath(include_path);
    lib.addIncludePath(sdl.getEmittedIncludeTree().path(b, "SDL2"));

    lib.addCSourceFiles(.{
        .root = root,
        .files = &.{
            "src/FAudio.c",
            "src/FAudio_internal.c",
            "src/FAudio_internal_simd.c",
            "src/FAudio_operationset.c",
            "src/FAudio_platform_sdl2.c",
        },
    });
    lib.installHeadersDirectory(include_path, ".", .{});
    lib.installHeadersDirectory(root.path(b, "src"), ".", .{});
    lib.linkLibCpp();
    lib.linkLibrary(sdl);

    return lib;
}

fn addLodepng(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step.Compile {
    const dep = b.dependency("lodepng", .{});
    const root = dep.path(".");
    const lib = b.addLibrary(.{
        .name = "lodepng",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.addIncludePath(root);

    // The Lore:
    // we generate a ".c" file and use it to include lodepng.cpp so that
    // it gets compiled as a C file and doesn't mangle the symbols.  We don't
    // want the symbols mangled becuase VVVVVV decided it was better to copy
    // the 3 function prototypes it's using from lodepng and wrap them in
    // extern "C" rather than just using their header file.
    const generate_files = b.addWriteFiles();
    const c_wrapper = generate_files.add(
        "lodepng.c",
        "#include <lodepng.cpp>",
    );

    // workaround bug in Zig build system (TODO: create a minimal reproduction and file a bug)
    lib.step.dependOn(&generate_files.step);

    lib.addCSourceFiles(.{
        .root = c_wrapper.dirname(),
        .files = &.{
            "lodepng.c",
        },
        .flags = &.{
            "-DLODEPNG_NO_COMPILE_ALLOCATORS",
            "-DLODEPNG_NO_COMPILE_DISK",
        },
    });
    lib.linkLibCpp();
    return lib;
}

const src = [_][]const u8{
    "desktop_version/src/BinaryBlob.cpp",
    "desktop_version/src/BlockV.cpp",
    "desktop_version/src/ButtonGlyphs.cpp",
    "desktop_version/src/CustomLevels.cpp",
    "desktop_version/src/CWrappers.cpp",
    "desktop_version/src/Editor.cpp",
    "desktop_version/src/Ent.cpp",
    "desktop_version/src/Entity.cpp",
    "desktop_version/src/FileSystemUtils.cpp",
    "desktop_version/src/Finalclass.cpp",
    "desktop_version/src/Font.cpp",
    "desktop_version/src/FontBidi.cpp",
    "desktop_version/src/Game.cpp",
    "desktop_version/src/Graphics.cpp",
    "desktop_version/src/GraphicsResources.cpp",
    "desktop_version/src/GraphicsUtil.cpp",
    "desktop_version/src/Input.cpp",
    "desktop_version/src/KeyPoll.cpp",
    "desktop_version/src/Labclass.cpp",
    "desktop_version/src/LevelDebugger.cpp",
    "desktop_version/src/Localization.cpp",
    "desktop_version/src/LocalizationMaint.cpp",
    "desktop_version/src/LocalizationStorage.cpp",
    "desktop_version/src/Logic.cpp",
    "desktop_version/src/Map.cpp",
    "desktop_version/src/Music.cpp",
    "desktop_version/src/Otherlevel.cpp",
    "desktop_version/src/preloader.cpp",
    "desktop_version/src/Render.cpp",
    "desktop_version/src/RenderFixed.cpp",
    "desktop_version/src/RoomnameTranslator.cpp",
    "desktop_version/src/Screen.cpp",
    "desktop_version/src/Script.cpp",
    "desktop_version/src/Scripts.cpp",
    "desktop_version/src/Spacestation2.cpp",
    "desktop_version/src/TerminalScripts.cpp",
    "desktop_version/src/Textbox.cpp",
    "desktop_version/src/Tower.cpp",
    "desktop_version/src/UtilityClass.cpp",
    "desktop_version/src/WarpClass.cpp",
    "desktop_version/src/XMLUtils.cpp",
    "desktop_version/src/main.cpp",
    "desktop_version/src/DeferCallbacks.c",
    "desktop_version/src/GlitchrunnerMode.c",
    "desktop_version/src/Network.c",
    "desktop_version/src/Textbook.c",
    "desktop_version/src/ThirdPartyDeps.c",
    "desktop_version/src/UTF8.c",
    "desktop_version/src/VFormat.c",
    "desktop_version/src/Vlogging.c",
    "desktop_version/src/Xoshiro.c",
};
const physfs_src = [_][]const u8{
    "extras/physfsrwops.c",
};
