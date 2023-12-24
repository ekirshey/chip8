const std = @import("std");
const ray = @cImport(@cInclude("raylib.h"));
const RndGen = std.rand.DefaultPrng;

const EmulatorError = error{
    ROMNotFound,
    ROMSystemResources,
    ROMAccessDenied,
    ROMTooLarge,
    ROMUnexpectedError,
    ROMReadError,
};

const Instruction = struct {
    data: u16,

    pub fn init(raw: u16) Instruction {
        return Instruction{
            .data = raw,
        };
    }

    pub fn opcode(self: Instruction) u4 {
        const op: u4 = @intCast((self.data & 0xF000) >> 12);
        return op;
    }

    pub fn x(self: Instruction) u16 {
        return (self.data & 0x0F00) >> 8;
    }

    pub fn y(self: Instruction) u16 {
        return (self.data & 0x00F0) >> 4;
    }

    pub fn kk(self: Instruction) u8 {
        const val: u8 = @intCast(self.data & 0x00FF);
        return val;
    }

    pub fn subOp(self: Instruction) u4 {
        const op: u4 = @intCast(self.data & 0x000F);
        return op;
    }

    pub fn nnn(self: Instruction) u16 {
        return (self.data & 0x0FFF);
    }
};

const Opcode = enum {
    CLS,
    RST,
    JUMP,
    CALL,
};

pub const Emulator = struct {
    memory: [4096]u8,
    output: [64 * 32]u8,
    pc: u16,
    v_reg: [16]u8,
    i_reg: u16,
    addr_stack: std.ArrayList(u16),
    delay_timer: u8,
    sound_timer: u8,
    rnd: RndGen,
    wait_for_keypress: bool,
    keypress_reg: u16,

    pub fn init(allocator: std.mem.Allocator) Emulator {
        return Emulator{
            .memory = [_]u8{0} ** 4096,
            .output = [_]u8{0} ** (32 * 64),
            .pc = 0,
            .v_reg = [_]u8{0} ** 16,
            .i_reg = 0,
            .addr_stack = std.ArrayList(u16).init(allocator),
            .delay_timer = 0,
            .sound_timer = 0,
            .rnd = RndGen.init(0),
            .wait_for_keypress = false,
            .keypress_reg = 0,
        };
    }

    pub fn deinit(self: *Emulator) void {
        self.addr_stack.deinit();
    }

    pub fn loadRom(self: *Emulator, path: []const u8) EmulatorError!void {
        const file = std.fs.cwd().openFile(
            path,
            .{},
        ) catch {
            return error.ROMNotFound;
        };
        defer file.close();

        const file_stats = file.stat() catch |err| {
            switch (err) {
                std.os.FStatError.SystemResources => {
                    return error.ROMSystemResources;
                },
                std.os.FStatError.AccessDenied => {
                    return error.ROMAccessDenied;
                },
                else => {
                    return error.ROMUnexpectedError;
                },
            }
        };
        if (file_stats.size > 4096) {
            return error.ROMTooLarge;
        }

        const size = file.reader().readAll(self.memory[0x200..]) catch {
            return error.ROMReadError;
        };
        _ = size;
    }

    pub fn updateTimers(self: *Emulator) void {
        if (self.delay_timer > 0) {
            self.delay_timer -= 1;
        }

        if (self.sound_timer > 0) {
            self.sound_timer -= 1;
        }
    }

    pub fn bitOperations(self: *Emulator, instruction: Instruction) void {
        const op = instruction.subOp();
        switch (op) {
            0 => {
                self.v_reg[instruction.x()] = self.v_reg[instruction.y()];
            },
            1 => {
                self.v_reg[instruction.x()] |= self.v_reg[instruction.y()];
                self.v_reg[0xF] = 0;
            },
            2 => {
                self.v_reg[instruction.x()] &= self.v_reg[instruction.y()];
                self.v_reg[0xF] = 0;
            },
            3 => {
                self.v_reg[instruction.x()] ^= self.v_reg[instruction.y()];
                self.v_reg[0xF] = 0;
            },
            4 => {
                const result: u16 = @as(u16, self.v_reg[instruction.x()]) + @as(u16, self.v_reg[instruction.y()]);
                self.v_reg[instruction.x()] = @intCast(result & 0xFF);
                self.v_reg[0xF] = if (result > 0xFF) 1 else 0;
            },
            5 => {
                const x: i16 = self.v_reg[instruction.x()];
                const y: i16 = self.v_reg[instruction.y()];
                const result: i16 = x - y;
                self.v_reg[instruction.x()] = @intCast(result & 0xFF);
                self.v_reg[0xF] = if (x >= y) 1 else 0;
            },
            6 => {
                const y: u8 = self.v_reg[instruction.y()];
                self.v_reg[instruction.x()] = y >> 1;
                self.v_reg[0xF] = y & 0x01;
            },
            7 => {
                const x: i16 = self.v_reg[instruction.x()];
                const y: i16 = self.v_reg[instruction.y()];
                const result: i16 = y - x;
                self.v_reg[instruction.x()] = @intCast(result & 0xFF);
                self.v_reg[0xF] = if (y >= x) 1 else 0;
            },
            0xE => {
                const y: u8 = self.v_reg[instruction.y()];
                self.v_reg[instruction.x()] = y << 1;
                self.v_reg[0xF] = (y >> 7) & 0x1;
            },
            else => {},
        }
    }

    pub fn draw(self: *Emulator, instruction: Instruction) void {
        const x: u8 = self.v_reg[instruction.x()];
        const y: u8 = self.v_reg[instruction.y()];
        const n = instruction.subOp();

        self.v_reg[0xF] = 0;
        for (0..n) |i| {
            const row = (y + i) % 32;
            for (0..8) |j| {
                const col = (x + j) % 64;
                const new_cell = std.math.shr(u8, self.memory[self.i_reg + i], 7 - j) & 0x01;
                if (self.output[row * 64 + col] & new_cell == 1) {
                    self.v_reg[0xF] = 1;
                }
                self.output[row * 64 + col] ^= new_cell;
            }
        }
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

    // TODO pull ray stuff out
    pub fn userInput(self: *Emulator, instruction: Instruction) void {
        const op = instruction.kk();
        const x: u16 = instruction.x();
        switch (op) {
            0x9e => {
                const key = ConvertKey(self.v_reg[x]);
                if (key != -1 and ray.IsKeyDown(key)) {
                    self.pc += 2;
                }
            },
            0xA1 => {
                const key = ConvertKey(self.v_reg[x]);
                if (key != -1 and !ray.IsKeyDown(key)) {
                    self.pc += 2;
                }
            },
            else => {},
        }
    }

    pub fn specialFunctions(self: *Emulator, instruction: Instruction) void {
        const op = instruction.kk();
        const x: u16 = instruction.x();
        switch (op) {
            0x07 => {
                self.v_reg[x] = self.delay_timer;
            },
            0x0A => {
                self.wait_for_keypress = true;
                self.keypress_reg = x;
            },
            0x15 => {
                self.delay_timer = self.v_reg[x];
            },
            0x18 => {
                self.sound_timer = self.v_reg[x];
            },
            0x1E => {
                self.i_reg += self.v_reg[x];
            },
            0x55 => {
                for (0..x + 1) |i| {
                    self.memory[self.i_reg + i] = self.v_reg[i];
                }
                self.i_reg += x + 1;
            },
            0x65 => {
                for (0..x + 1) |i| {
                    self.v_reg[i] = self.memory[self.i_reg + i];
                }
                self.i_reg += x + 1;
            },
            0x33 => {
                var val = self.v_reg[x];
                for (1..4) |i| {
                    self.memory[self.i_reg + (3 - i)] = val % 10;
                    val /= 10;
                }
            },
            else => {},
        }
    }

    pub fn handleInput(self: *Emulator, input: u8) void {
        if (input != 0) {
            self.wait_for_keypress = false;
            self.v_reg[self.keypress_reg] = input;
        }
    }

    pub fn step(self: *Emulator) !void {
        const raw = std.mem.readInt(u16, self.memory[self.pc .. self.pc + 2][0..2], .big);
        const instruction = Instruction.init(raw);

        self.pc += 2;

        switch (instruction.opcode()) {
            0 => {
                if (instruction.data == 0x00E0) {
                    @memset(&self.output, 0);
                } else if (instruction.data == 0x00EE) {
                    self.pc = self.addr_stack.pop();
                }
            },
            1 => {
                self.pc = instruction.nnn();
            },
            2 => {
                try self.addr_stack.append(self.pc);
                self.pc = instruction.nnn();
            },
            3 => {
                if (self.v_reg[instruction.x()] == instruction.kk()) {
                    self.pc += 2;
                }
            },
            4 => {
                if (self.v_reg[instruction.x()] != instruction.kk()) {
                    self.pc += 2;
                }
            },
            5 => {
                if (self.v_reg[instruction.x()] == self.v_reg[instruction.y()]) {
                    self.pc += 2;
                }
            },
            6 => {
                self.v_reg[instruction.x()] = instruction.kk();
            },
            7 => {
                const result: u16 = self.v_reg[instruction.x()] + @as(u16, instruction.kk());
                self.v_reg[instruction.x()] = @intCast(result & 0xFF);
            },
            8 => {
                self.bitOperations(instruction);
            },
            9 => {
                if (self.v_reg[instruction.x()] != self.v_reg[instruction.y()]) {
                    self.pc += 2;
                }
            },
            0xA => {
                self.i_reg = instruction.nnn();
            },
            0xB => {
                self.pc = self.v_reg[0] + (instruction.nnn());
            },
            0xC => {
                const x = instruction.x();
                const val = self.rnd.random().int(u8);
                const mask: u8 = @intCast(instruction.kk());
                self.v_reg[x] = val & mask;
            },
            0xD => {
                self.draw(instruction);
            },
            0xE => {
                self.userInput(instruction);
            },
            0xF => {
                self.specialFunctions(instruction);
            },
        }
    }
};
