const std = @import("std");
const ray = @cImport(@cInclude("raylib.h"));
const chip8 = @import("chip8.zig");
const RndGen = std.rand.DefaultPrng;
const Allocator = std.mem.Allocator;

const screen_width: u32 = 1024;
const screen_height: u32 = 512;
const screen_rows: u32 = 32;
const screen_cols: u32 = 64;

pub fn GetInput() u8 {
    if (ray.IsKeyReleased(ray.KEY_ONE)) {
        return 1;
    } else if (ray.IsKeyReleased(ray.KEY_TWO)) {
        return 2;
    } else if (ray.IsKeyReleased(ray.KEY_THREE)) {
        return 3;
    } else if (ray.IsKeyReleased(ray.KEY_FOUR)) {
        return 0xC;
    } else if (ray.IsKeyReleased(ray.KEY_Q)) {
        return 4;
    } else if (ray.IsKeyReleased(ray.KEY_W)) {
        return 5;
    } else if (ray.IsKeyReleased(ray.KEY_E)) {
        return 6;
    } else if (ray.IsKeyReleased(ray.KEY_R)) {
        return 0xD;
    } else if (ray.IsKeyReleased(ray.KEY_A)) {
        return 7;
    } else if (ray.IsKeyReleased(ray.KEY_S)) {
        return 8;
    } else if (ray.IsKeyReleased(ray.KEY_D)) {
        return 9;
    } else if (ray.IsKeyReleased(ray.KEY_F)) {
        return 0xE;
    } else if (ray.IsKeyReleased(ray.KEY_Z)) {
        return 0xA;
    } else if (ray.IsKeyReleased(ray.KEY_X)) {
        return 0;
    } else if (ray.IsKeyReleased(ray.KEY_C)) {
        return 0xB;
    } else if (ray.IsKeyReleased(ray.KEY_V)) {
        return 0xF;
    }
    return 0;
}

pub fn main() !void {
    const period: f32 = 1.0 / 60.0; // 60hz
    const instruction_rate: f32 = 1.0 / 700.0;
    const tile_height: u32 = screen_height / screen_rows;
    const tile_width: u32 = screen_width / screen_cols;
    var instruction_timer: f32 = 0.0;

    const stderr = std.io.getStdErr().writer();

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) {
        try stderr.print("\nNo ROM provided\n", .{});
        return;
    }

    var emu = chip8.Emulator.init(gpa, period);
    defer emu.deinit();

    try emu.loadRom(args[1]);

    var it = std.mem.split(u8, args[1], "/");
    var window_name: []const u8 = "";
    while (it.next()) |x| {
        window_name = x;
    }

    ray.InitWindow(screen_width + tile_width / 2, screen_height + tile_height / 2, &window_name[0]);
    defer ray.CloseWindow();

    while (!ray.WindowShouldClose()) {
        const frame_time: f32 = ray.GetFrameTime();
        instruction_timer += frame_time;
        emu.updateTimers(frame_time);

        if (instruction_timer >= instruction_rate) {
            instruction_timer = 0.0;
            if (emu.wait_for_keypress) {
                const input = GetInput();
                emu.handleInput(input);
            } else {
                try emu.step();
            }
        }

        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);
        draw(&emu, screen_rows, screen_cols, tile_height, tile_width);
        ray.EndDrawing();
    }
}

pub fn draw(emu: *chip8.Emulator, rows: u32, cols: u32, tile_height: u32, tile_width: u32) void {
    var rect = ray.Rectangle{
        .x = 0,
        .y = 0,
        .height = @floatFromInt(tile_height),
        .width = @floatFromInt(tile_width),
    };
    for (0..rows) |i| {
        for (0..cols) |j| {
            if (emu.output[i * cols + j] > 0) {
                rect.x = @floatFromInt(j * tile_width);
                rect.y = @floatFromInt(i * tile_height);
                ray.DrawRectangleRec(rect, ray.WHITE);
            }
        }
    }
}
