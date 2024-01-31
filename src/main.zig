//! Simple Lua interpreter
//! This is a modified program from Programming in Lua 4th Edition

const std = @import("std");

// The ziglua module is made available in build.zig
const ziglua = @import("ziglua");

// linenoise == readline
const Linenoise = @import("linenoise").Linenoise;

// A Zig function called by Lua must accept a single *Lua parameter and must return an i32.
// This is the Zig equivalent of the lua_CFunction typedef int (*lua_CFunction) (lua_State *L) in the C API
fn adder(lua: *ziglua.Lua) i32 {
  const a = lua.toInteger(1) catch 0;
  const b = lua.toInteger(2) catch 0;
  lua.pushInteger(a + b);
  return 1;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize The Lua vm and get a reference to the main thread
    // Passing a Zig allocator to the Lua state requires a stable pointer
    var lua = try ziglua.Lua.init(&allocator);
    defer lua.deinit();

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    // Open all Lua standard libraries
    lua.openLibs();

    // register functions to a global and run from a Lua "program"
    lua.pushFunction(ziglua.wrap(adder));
    lua.setGlobal("add");

    var stdout = std.io.getStdOut().writer();

    while (try ln.linenoise("lua> ")) |input| {
      defer allocator.free(input);
      try ln.history.add(input);
        
      // Convert line to null-terminated line
      const cline: [:0]const u8 = try allocator.dupeZ(u8, input);
      defer allocator.free(cline);

      // Try with a surrounding return to execute the input as an expression
      const retline = try std.fmt.allocPrintZ(allocator, "return {s};", .{ input });
      defer allocator.free(retline);

      // Load the buffer. It will fail if the loaded code is not valid lua.
      lua.loadBuffer(retline, "=stdin", ziglua.Mode.text) catch {
        // loadBuffer failed because line was not an expression but a statement
        while (lua.getTop() != 0) lua.pop(1);
        // Load the line as a statement
        lua.loadString(cline) catch {
          // If that fail, print an error and loop
          try stdout.print("{s}\n", .{lua.toString(-1) catch unreachable});
          lua.pop(1);
          continue;
        };
      };
      // If we are here it is because we were able to load the input either
      // as an expression or a statement.
      lua.protectedCall(0, ziglua.mult_return, 0) catch {
        try stdout.print("{s}\n", .{lua.toString(-1) catch unreachable});
        lua.pop(1);
      };
      // Prints the result with the appropriate format
      const top_index = lua.getTop();
      if (top_index != 0) {
        switch (lua.typeOf(top_index)) {
          ziglua.LuaType.none => try stdout.print("-> None\n", .{}),
          ziglua.LuaType.nil => try stdout.print("-> Nil\n", .{}),
          ziglua.LuaType.boolean => try stdout.print("-> {}\n", .{ lua.toBoolean(top_index) }),
          ziglua.LuaType.light_userdata => try stdout.print("-> light_userdata???\n", .{}),
          ziglua.LuaType.number => try stdout.print("-> {}\n", .{ lua.toNumber(top_index) catch unreachable }),
          ziglua.LuaType.string => try stdout.print("-> {s}\n", .{ lua.toString(top_index) catch unreachable }),
          ziglua.LuaType.table => try stdout.print("-> table???\n", .{}),
          ziglua.LuaType.function => try stdout.print("-> function\n", .{}),
          ziglua.LuaType.userdata => try stdout.print("-> userdata\n", .{}),
          ziglua.LuaType.thread => try stdout.print("-> thread\n", .{}),
        }
        lua.pop(1);
      }
    }
}

