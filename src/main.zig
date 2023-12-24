const std = @import("std");
const ray = @cImport(@cInclude("raylib.h"));
const chip8 = @import("chip8.zig");
const RndGen = std.rand.DefaultPrng;
const Allocator = std.mem.Allocator;

const screen_width: u32 = 1024;
const screen_height: u32 = 512;

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

const Screen = struct {
    pixels: [64 * 32]u8,
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var emu = chip8.Emulator.init(gpa);
    defer emu.deinit();

    try emu.loadRom("E:/code/zig/chip8/roms/flags.ch8");

    ray.InitWindow(screen_width + 32, screen_height + 32, "Chip8");
    defer ray.CloseWindow();

    const tile_height = screen_height / 32;
    const tile_width = screen_width / 64;

    var timer: f32 = 0.0;
    var instruction_timer: f32 = 0.0;
    const period: f32 = 1.0 / 60.0; // 60hz
    const instruction_rate: f32 = 1.0 / 700.0;
    while (!ray.WindowShouldClose()) {
        timer += ray.GetFrameTime();
        instruction_timer += ray.GetFrameTime();
        if (timer >= period) {
            emu.updateTimers();
            timer = 0;
        }

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
        var rect = ray.Rectangle{
            .x = 0,
            .y = 0,
            .height = tile_height,
            .width = tile_width,
        };
        for (0..32) |i| {
            for (0..64) |j| {
                if (emu.output[i * 64 + j] > 0) {
                    rect.x = @floatFromInt(j * tile_width);
                    rect.y = @floatFromInt(i * tile_height);
                    ray.DrawRectangleRec(rect, ray.WHITE);
                }
            }
        }
        ray.EndDrawing();
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
