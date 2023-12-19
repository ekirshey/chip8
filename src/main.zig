const std = @import("std");
const ray = @cImport(@cInclude("raylib.h"));
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

pub fn ConvertKey(key: u8) c_int {
    switch (key) {
        1 => return ray.KEY_ONE,
        2 => return ray.KEY_TWO,
        3 => return ray.KEY_THREE,
        0xC => return ray.KEY_FOUR,
        4 => return ray.KEY_Q,
        5 => return ray.KEY_W,
        6 => return ray.KEY_E,
        0xD => return ray.KEY_R,
        7 => return ray.KEY_A,
        8 => return ray.KEY_S,
        9 => return ray.KEY_D,
        0xE => return ray.KEY_F,
        0xA => return ray.KEY_Z,
        0 => return ray.KEY_X,
        0xB => return ray.KEY_C,
        0xF => return ray.KEY_V,
        else => return -1,
    }
}

const Screen = struct {
    pixels: [64 * 32]u8,
};

const Chip8 = struct {
    screen: [64 * 32]u8,
    pc: u16,
    index_register: u16,
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var memory = [_]u8{0} ** 4096;
    var screen = [_]u8{0} ** (32 * 64);
    var stack = std.ArrayList(u16).init(gpa);
    defer stack.deinit();

    var delay_timer: u8 = 0;
    var sound_timer: u8 = 0;

    var v_reg = [_]u8{0} ** 16;
    var i_reg: u16 = 0;
    const file = try std.fs.cwd().openFile(
        "E:/code/zig/chip8/roms/flightrunner.ch8",
        .{},
    );
    defer file.close();

    const file_stats = try file.stat();

    if (file_stats.size > 4096) {
        std.debug.print("File too large", .{});
        return;
    }

    // It's allocating an arraylist onto the allocator
    const size = try file.reader().readAll(memory[0x200..]);
    _ = size;

    ray.InitWindow(screen_width + 32, screen_height + 32, "My Window Name");
    defer ray.CloseWindow();

    var pc: u16 = 200;
    var refresh = false;
    var wait_for_keypress = false;
    var keypress_reg: u16 = 0;

    const tile_height = screen_height / 32;
    const tile_width = screen_width / 64;

    var rnd = RndGen.init(0);
    var timer: f32 = 0.0;
    var instruction_timer: f32 = 0.0;
    const period: f32 = 1.0 / 60.0; // 60hz
    const instruction_rate: f32 = 1.0 / 700.0;
    while (!ray.WindowShouldClose()) {
        refresh = false;

        timer += ray.GetFrameTime();
        instruction_timer += ray.GetFrameTime();
        if (timer >= period) {
            if (delay_timer > 0) {
                delay_timer -= 1;
            }
            if (sound_timer > 0) {
                sound_timer -= 1;
            }
            timer = 0;
        }

        if (instruction_timer >= instruction_rate) {
            instruction_timer = 0.0;
            if (wait_for_keypress) {
                const input = GetInput();
                if (input != 0) {
                    wait_for_keypress = false;
                    v_reg[keypress_reg] = input;
                }
            } else {
                const instruction = std.mem.readInt(u16, memory[pc .. pc + 2][0..2], .big);
                const id = (instruction & 0xF000) >> 12;
                pc += 2;

                switch (id) {
                    0 => {
                        if (instruction == 0x00E0) {
                            @memset(&screen, 0);
                            refresh = true;
                        } else if (instruction == 0x00EE) {
                            pc = stack.pop();
                        }
                    },
                    1 => {
                        pc = instruction & 0x0FFF;
                    },
                    2 => {
                        try stack.append(pc);
                        pc = instruction & 0x0FFF;
                    },
                    3 => {
                        if (v_reg[(instruction & 0x0F00) >> 8] == (instruction & 0x00FF)) {
                            pc += 2;
                        }
                    },
                    4 => {
                        if (v_reg[(instruction & 0x0F00) >> 8] != (instruction & 0x00FF)) {
                            pc += 2;
                        }
                    },
                    5 => {
                        if (v_reg[(instruction & 0x0F00) >> 8] == v_reg[(instruction & 0x00F0) >> 4]) {
                            pc += 2;
                        }
                    },
                    6 => {
                        v_reg[(instruction & 0x0F00) >> 8] = @intCast(instruction & 0x00FF);
                    },
                    7 => {
                        const result = v_reg[(instruction & 0x0F00) >> 8] + instruction & 0x00FF;
                        v_reg[(instruction & 0x0F00) >> 8] = @intCast(result & 0xFF);
                    },
                    8 => {
                        const op = instruction & 0x000F;
                        switch (op) {
                            0 => {
                                v_reg[(instruction & 0x0F00) >> 8] = v_reg[(instruction & 0x00F0) >> 4];
                            },
                            1 => {
                                v_reg[(instruction & 0x0F00) >> 8] |= v_reg[(instruction & 0x00F0) >> 4];
                                v_reg[0xF] = 0;
                            },
                            2 => {
                                v_reg[(instruction & 0x0F00) >> 8] &= v_reg[(instruction & 0x00F0) >> 4];
                                v_reg[0xF] = 0;
                            },
                            3 => {
                                v_reg[(instruction & 0x0F00) >> 8] ^= v_reg[(instruction & 0x00F0) >> 4];
                                v_reg[0xF] = 0;
                            },
                            4 => {
                                const result: u16 = @as(u16, v_reg[(instruction & 0x0F00) >> 8]) + @as(u16, v_reg[(instruction & 0x00F0) >> 4]);
                                v_reg[(instruction & 0x0F00) >> 8] = @intCast(result & 0xFF);
                                v_reg[0xF] = if (result > 0xFF) 1 else 0;
                            },
                            5 => {
                                const x: i16 = v_reg[(instruction & 0x0F00) >> 8];
                                const y: i16 = v_reg[(instruction & 0x00F0) >> 4];
                                const result: i16 = x - y;
                                v_reg[(instruction & 0x0F00) >> 8] = @intCast(result & 0xFF);
                                v_reg[0xF] = if (x >= y) 1 else 0;
                            },
                            6 => {
                                const y: u8 = v_reg[(instruction & 0x00F0) >> 4];
                                v_reg[(instruction & 0x0F00) >> 8] = y >> 1;
                                v_reg[0xF] = y & 0x01;
                            },
                            7 => {
                                const x: i16 = v_reg[(instruction & 0x0F00) >> 8];
                                const y: i16 = v_reg[(instruction & 0x00F0) >> 4];
                                const result: i16 = y - x;
                                v_reg[(instruction & 0x0F00) >> 8] = @intCast(result & 0xFF);
                                v_reg[0xF] = if (y >= x) 1 else 0;
                            },
                            0xE => {
                                const y: u8 = v_reg[(instruction & 0x00F0) >> 4];
                                v_reg[(instruction & 0x0F00) >> 8] = y << 1;
                                v_reg[0xF] = (y >> 7) & 0x1;
                            },
                            else => {},
                        }
                    },
                    9 => {
                        if (v_reg[(instruction & 0x0F00) >> 8] != v_reg[(instruction & 0x00F0) >> 4]) {
                            pc += 2;
                        }
                    },
                    0xA => {
                        i_reg = instruction & 0x0FFF;
                    },
                    0xB => {
                        pc = v_reg[0] + (instruction & 0x0FFF);
                    },
                    0xC => {
                        const x = (instruction & 0x0F00) >> 8;
                        const val = rnd.random().int(u8);
                        const mask: u8 = @intCast(instruction & 0xFF);
                        v_reg[x] = val & mask;
                    },
                    0xD => { // DXYN
                        const x: u8 = v_reg[(instruction & 0x0F00) >> 8];
                        const y: u8 = v_reg[(instruction & 0x00F0) >> 4];
                        const n = instruction & 0x000F;

                        v_reg[0xF] = 0;
                        for (0..n) |i| {
                            const row = (y + i) % 32;
                            for (0..8) |j| {
                                const col = (x + j) % 64;
                                const new_cell = std.math.shr(u8, memory[i_reg + i], 7 - j) & 0x01;
                                if (screen[row * 64 + col] & new_cell == 1) {
                                    v_reg[0xF] = 1;
                                }
                                screen[row * 64 + col] ^= new_cell;
                            }
                        }
                        refresh = true;
                    },
                    0xE => {
                        const op = instruction & 0x00FF;
                        const x: u16 = (instruction & 0x0F00) >> 8;
                        switch (op) {
                            0x9e => {
                                const key = ConvertKey(v_reg[x]);
                                if (key != -1 and ray.IsKeyDown(key)) {
                                    pc += 2;
                                }
                            },
                            0xA1 => {
                                const key = ConvertKey(v_reg[x]);
                                if (key != -1 and !ray.IsKeyDown(key)) {
                                    pc += 2;
                                }
                            },
                            else => {},
                        }
                    },
                    0xF => {
                        const op = instruction & 0x00FF;
                        const x: u16 = (instruction & 0x0F00) >> 8;
                        switch (op) {
                            0x07 => {
                                v_reg[x] = delay_timer;
                            },
                            0x0A => {
                                wait_for_keypress = true;
                                keypress_reg = x;
                            },
                            0x15 => {
                                delay_timer = v_reg[x];
                            },
                            0x18 => {
                                sound_timer = v_reg[x];
                            },
                            0x1E => {
                                i_reg += v_reg[x];
                            },
                            0x55 => {
                                for (0..x + 1) |i| {
                                    memory[i_reg + i] = v_reg[i];
                                }
                                i_reg += x + 1;
                            },
                            0x65 => {
                                for (0..x + 1) |i| {
                                    v_reg[i] = memory[i_reg + i];
                                }
                                i_reg += x + 1;
                            },
                            0x33 => {
                                var val = v_reg[x];
                                memory[i_reg + 2] = val % 10;
                                val /= 10;
                                memory[i_reg + 1] = val % 10;
                                val /= 10;
                                memory[i_reg] = val % 10;
                                val /= 10;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
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
                if (screen[i * 64 + j] > 0) {
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
