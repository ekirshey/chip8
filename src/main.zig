const std = @import("std");
const Allocator = std.mem.Allocator;

const Chip8 = struct {
    screen: [64 * 32]u8,
    pc: u16,
    index_register: u16,
};

pub fn main() !void {
    var buffer_storage: [4096]u8 = undefined;
    var memory_fba = std.heap.FixedBufferAllocator.init(&buffer_storage);
    const allocator = memory_fba.allocator();
    const memory = try allocator.alloc(u8, 4096);
    @memset(memory, 0);

    var screen = [_]u64{0} ** 32;

    var v_reg = [_]u8{0} ** 16;
    var i_reg: u16 = 0;
    const file = try std.fs.cwd().openFile(
        "E:/code/zig/chip8/ibm.ch8",
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

    var pc: u16 = 200;
    var refresh = false;
    var dont_inc = false;
    while (true) {
        refresh = false;
        dont_inc = false;

        const instruction = std.mem.readInt(u16, memory[pc .. pc + 2][0..2], .big);
        const id = (instruction & 0xF000) >> 12;

        switch (id) {
            0 => {
                if (instruction == 0x00E0) {
                    @memset(&screen, 0);
                    refresh = true;
                }
            },
            1 => {
                pc = instruction & 0x0FFF;
                dont_inc = true;
            },
            6 => {
                v_reg[instruction & 0x0F00 >> 8] = @intCast(instruction & 0x00FF);
            },
            7 => {
                v_reg[instruction & 0x0F00 >> 8] += @intCast(instruction & 0x00FF);
            },
            0xA => {
                i_reg = instruction & 0x0FFF;
            },
            0xD => { // DXYN
                v_reg[15] = 0;
                const x = v_reg[instruction & 0x0F00 >> 8] % 64;
                const y = v_reg[instruction & 0x00F0 >> 4] % 32;
                const n = instruction & 0x000F;

                for (0..n) |i| {
                    const n_row = memory[i_reg + i];
                    const mask: u64 = std.math.shr(u64, n_row, x);
                    screen[y] ^= mask;
                    //TODO handle vf
                }
                refresh = true;
            },
            else => {},
        }

        if (!dont_inc) {
            pc += 2;
        }
        if (pc >= memory.len) {
            break;
        }

        if (refresh) {
            clearScreen();
            draw(&screen);
        }
    }
}

fn draw(screen: []u64) void {
    for (0..32) |i| {
        std.debug.print("{b:0>64} ", .{screen[i]});
        std.debug.print("\n", .{});
    }
}

fn clearScreen() void {
    std.debug.print("\x1b[2J\x1b[H", .{});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
