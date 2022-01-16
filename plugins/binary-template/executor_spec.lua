-- Binary Template plugin for REHex
-- Copyright (C) 2021 Daniel Collins <solemnwarning@solemnwarning.net>
--
-- This program is free software; you can redistribute it and/or modify it
-- under the terms of the GNU General Public License version 2 as published by
-- the Free Software Foundation.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
-- more details.
--
-- You should have received a copy of the GNU General Public License along with
-- this program; if not, write to the Free Software Foundation, Inc., 51
-- Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

local executor = require 'executor'

local function test_interface(data)
	local log = {}
	
	local timeout = os.time() + 5
	
	local interface = {
		set_data_type = function(offset, length, data_type)
			table.insert(log, "set_data_type(" .. offset .. ", " .. length .. ", " .. data_type .. ")")
		end,
		
		set_comment = function(offset, length, comment_text)
			table.insert(log, "set_comment(" .. offset .. ", " .. length .. ", " .. comment_text .. ")")
		end,
		
		yield = function()
			if os.time() >= timeout
			then
				error("Test timeout")
			end
		end,
		
		print = function(s)
			table.insert(log, "print(" .. s .. ")")
		end,
		
		_data = data,
		
		read_data = function(offset, length)
			return data:sub(offset + 1, offset + length)
		end,
		
		file_length = function()
			return data:len()
		end,
	}
	
	return interface, log
end

describe("executor", function()
	it("runs an empty program", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {})
		
		assert.are.same({}, log)
	end)
	
	it("handles top-level variable declarations", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "variable", "int", "foo", nil, nil },
			{ "test.bt", 1, "variable", "int", "bar", nil, { "test.bt", 1, "num", 4 } },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_comment(0, 4, foo)",
			
			"set_data_type(4, 4, s32le)",
			"set_data_type(8, 4, s32le)",
			"set_data_type(12, 4, s32le)",
			"set_data_type(16, 4, s32le)",
			
			"set_comment(4, 16, bar)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("doesn't set data type on char[] variables", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "variable", "char", "single_char", nil, nil },
			{ "test.bt", 1, "variable", "uchar", "single_uchar", nil, nil },
			{ "test.bt", 1, "variable", "char", "char_array", nil, { "test.bt", 1, "num", 10 } },
			{ "test.bt", 1, "variable", "uchar", "uchar_array", nil, { "test.bt", 1, "num", 10 } },
		})
		
		local expect_log = {
			"set_data_type(0, 1, s8)",
			"set_comment(0, 1, single_char)",
			
			"set_data_type(1, 1, u8)",
			"set_comment(1, 1, single_uchar)",
			
			"set_comment(2, 10, char_array)",
			
			"set_data_type(12, 1, u8)",
			"set_data_type(13, 1, u8)",
			"set_data_type(14, 1, u8)",
			"set_data_type(15, 1, u8)",
			"set_data_type(16, 1, u8)",
			"set_data_type(17, 1, u8)",
			"set_data_type(18, 1, u8)",
			"set_data_type(19, 1, u8)",
			"set_data_type(20, 1, u8)",
			"set_data_type(21, 1, u8)",
			"set_comment(12, 10, uchar_array)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles builtin function calls", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "Hello world" } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "Goodbye world" } } },
		})
		
		local expect_log = {
			"print(Hello world)",
			"print(Goodbye world)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles variadic function calls", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "%s %d" },
				{ "test.bt", 1, "str", "test string" },
				{ "test.bt", 1, "num", 1234 } } },
		})
		
		local expect_log = {
			"print(test string 1234)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles custom functions", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "function", "void", "foo", {}, {
				{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "foo called" } } } } },
			{ "test.bt", 1, "function", "void", "bar", {}, {
				{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "bar called" } } } } },
			
			{ "test.bt", 1, "call", "foo", {} },
			{ "test.bt", 1, "call", "foo", {} },
			{ "test.bt", 1, "call", "bar", {} },
		})
		
		local expect_log = {
			"print(foo called)",
			"print(foo called)",
			"print(bar called)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles custom functions with arguments", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "function", "void", "foo", { { "int", "a" }, { "int", "b" }, { "string", "c" } }, {
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "%d, %d, %s" },
					{ "test.bt", 1, "ref", { "a" } },
					{ "test.bt", 1, "ref", { "b" } },
					{ "test.bt", 1, "ref", { "c" } } } } } },
			
			{ "test.bt", 1, "call", "foo", {
				{ "test.bt", 1, "num", 1234 },
				{ "test.bt", 1, "num", 5678 },
				{ "test.bt", 1, "str", "hello" } } },
		})
		
		local expect_log = {
			"print(1234, 5678, hello)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors when attempting to call a function with too few arguments", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "func", { { "int", "a" }, { "int", "b" }, { "string", "c" } }, {} },
				
				{ "test.bt", 2, "call", "func", {
					{ "test.bt", 3, "num", 1 },
					{ "test.bt", 3, "num", 2 } } },
			})
			end, "Attempt to call function func(int, int, string) with incompatible argument types (int, int) at test.bt:2")
	end)
	
	it("errors when attempting to call a function with too many arguments", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "func", { { "int", "a" }, { "int", "b" }, { "string", "c" } }, {} },
				
				{ "test.bt", 2, "call", "func", {
					{ "test.bt", 3, "num", 1 },
					{ "test.bt", 3, "num", 2 },
					{ "test.bt", 3, "str", "x" },
					{ "test.bt", 3, "str", "y" } } },
			})
			end, "Attempt to call function func(int, int, string) with incompatible argument types (int, int, string, string) at test.bt:2")
	end)
	
	it("errors when attempting to call a function with incompatible argument types", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "func", { { "int", "a" }, { "int", "b" }, { "string", "c" } }, {} },
				
				{ "test.bt", 2, "call", "func", {
					{ "test.bt", 3, "num", 1 },
					{ "test.bt", 3, "str", "x" },
					{ "test.bt", 3, "str", "y" } } },
			})
			end, "Attempt to call function func(int, int, string) with incompatible argument types (int, string, string) at test.bt:2")
	end)
	
	it("errors when attempting to call a variadic function with too few arguments", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "call", "Printf", {} },
			})
			end, "Attempt to call function Printf(string, ...) with incompatible argument types () at test.bt:1")
	end)
	
	it("reads int8 values from file", function()
		local interface, log = test_interface(string.char(
			0x00,
			0xFF
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "variable", "char", "a", nil, nil },
			{ "test.bt", 1, "variable", "char", "b", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a = %d" },
				{ "test.bt", 1, "ref", { "a" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "b = %d" },
				{ "test.bt", 1, "ref", { "b" } } } },
		})
		
		local expect_log = {
			"set_data_type(0, 1, s8)",
			"set_comment(0, 1, a)",
			
			"set_data_type(1, 1, s8)",
			"set_comment(1, 1, b)",
			
			"print(a = 0)",
			"print(b = -1)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("reads uint8 values from file", function()
		local interface, log = test_interface(string.char(
			0x00,
			0xFF
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "variable", "uchar", "a", nil, nil },
			{ "test.bt", 1, "variable", "uchar", "b", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a = %d" },
				{ "test.bt", 1, "ref", { "a" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "b = %d" },
				{ "test.bt", 1, "ref", { "b" } } } },
		})
		
		local expect_log = {
			"set_data_type(0, 1, u8)",
			"set_comment(0, 1, a)",
			
			"set_data_type(1, 1, u8)",
			"set_comment(1, 1, b)",
			
			"print(a = 0)",
			"print(b = 255)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("reads int16 (little-endian) values from file", function()
		local interface, log = test_interface(string.char(
			0xFF, 0x20,
			0xFF, 0xFF
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "variable", "int16", "a", nil, nil },
			{ "test.bt", 1, "variable", "int16", "b", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a = %d" },
				{ "test.bt", 1, "ref", { "a" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "b = %d" },
				{ "test.bt", 1, "ref", { "b" } } } },
		})
		
		local expect_log = {
			"set_data_type(0, 2, s16le)",
			"set_comment(0, 2, a)",
			
			"set_data_type(2, 2, s16le)",
			"set_comment(2, 2, b)",
			
			"print(a = 8447)",
			"print(b = -1)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("reads int16 (big-endian) values from file", function()
		local interface, log = test_interface(string.char(
			0x20, 0xFF,
			0xFF, 0xFF
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "BigEndian", {} },
			
			{ "test.bt", 1, "variable", "int16", "a", nil, nil },
			{ "test.bt", 1, "variable", "int16", "b", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a = %d" },
				{ "test.bt", 1, "ref", { "a" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "b = %d" },
				{ "test.bt", 1, "ref", { "b" } } } },
		})
		
		local expect_log = {
			"set_data_type(0, 2, s16be)",
			"set_comment(0, 2, a)",
			
			"set_data_type(2, 2, s16be)",
			"set_comment(2, 2, b)",
			
			"print(a = 8447)",
			"print(b = -1)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("reads uint16 (little-endian) values from file", function()
		local interface, log = test_interface(string.char(
			0xFF, 0x20,
			0xFF, 0xFF
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "variable", "uint16", "a", nil, nil },
			{ "test.bt", 1, "variable", "uint16", "b", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a = %d" },
				{ "test.bt", 1, "ref", { "a" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "b = %d" },
				{ "test.bt", 1, "ref", { "b" } } } },
		})
		
		local expect_log = {
			"set_data_type(0, 2, u16le)",
			"set_comment(0, 2, a)",
			
			"set_data_type(2, 2, u16le)",
			"set_comment(2, 2, b)",
			
			"print(a = 8447)",
			"print(b = 65535)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("reads uint16 (big-endian) values from file", function()
		local interface, log = test_interface(string.char(
			0x20, 0xFF,
			0xFF, 0xFF
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "BigEndian", {} },
			
			{ "test.bt", 1, "variable", "uint16", "a", nil, nil },
			{ "test.bt", 1, "variable", "uint16", "b", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a = %u" },
				{ "test.bt", 1, "ref", { "a" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "b = %u" },
				{ "test.bt", 1, "ref", { "b" } } } },
		})
		
		local expect_log = {
			"set_data_type(0, 2, u16be)",
			"set_comment(0, 2, a)",
			
			"set_data_type(2, 2, u16be)",
			"set_comment(2, 2, b)",
			
			"print(a = 8447)",
			"print(b = 65535)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("reads int32 (little-endian) values from file", function()
		local interface, log = test_interface(string.char(
			0xAA, 0xBB, 0xCC, 0x00,
			0xFF, 0xFF, 0xFF, 0xFF
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "variable", "int32", "a", nil, nil },
			{ "test.bt", 1, "variable", "int32", "b", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a = %d" },
				{ "test.bt", 1, "ref", { "a" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "b = %d" },
				{ "test.bt", 1, "ref", { "b" } } } },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_comment(0, 4, a)",
			
			"set_data_type(4, 4, s32le)",
			"set_comment(4, 4, b)",
			
			"print(a = 13417386)",
			"print(b = -1)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("reads uint64 (little-endian) values from file", function()
		local interface, log = test_interface(string.char(
			0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x00, 0x00, 0x00,
			0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "variable", "uint64", "a", nil, nil },
			{ "test.bt", 1, "variable", "uint64", "b", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a = %u" },
				{ "test.bt", 1, "ref", { "a" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "b = %u" },
				{ "test.bt", 1, "ref", { "b" } } } },
		})
		
		local expect_log = {
			"set_data_type(0, 8, u64le)",
			"set_comment(0, 8, a)",
			
			"set_data_type(8, 8, u64le)",
			"set_comment(8, 8, b)",
			
			"print(a = 1025923398570)",
			"print(b = 18446744073709551615)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("reads array values", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "variable", "int32", "a", nil, { "test.bt", 1, "num", 4 } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a[0] = %d" },
				{ "test.bt", 1, "ref", { "a", { "test.bt", 1, "num", 0 } } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a[1] = %d" },
				{ "test.bt", 1, "ref", { "a", { "test.bt", 1, "num", 1 } } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a[2] = %d" },
				{ "test.bt", 1, "ref", { "a", { "test.bt", 1, "num", 2 } } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "a[3] = %d" },
				{ "test.bt", 1, "ref", { "a", { "test.bt", 1, "num", 3 } } } } },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_data_type(4, 4, s32le)",
			"set_data_type(8, 4, s32le)",
			"set_data_type(12, 4, s32le)",
			"set_comment(0, 16, a)",
			
			"print(a[0] = 1)",
			"print(a[1] = 2)",
			"print(a[2] = 3)",
			"print(a[3] = 4)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors on invalid array index operands", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "call", "LittleEndian", {} },
					
					{ "test.bt", 1, "variable", "int32", "a", nil, { "test.bt", 1, "num", 4 } },
					
					{ "test.bt", 1, "ref", { "a", { "test.bt", 1, "str", "hello" } } },
				})
			end, "Invalid 'string' operand to '[]' operator - expected a number at test.bt:1")
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "call", "LittleEndian", {} },
					
					{ "test.bt", 1, "variable", "int32", "a", nil, { "test.bt", 1, "num", 4 } },
					
					{ "test.bt", 1, "ref", { "a", { "test.bt", 1, "num", -1 } } },
				})
			end, "Attempt to access out-of-range array index -1 at test.bt:1")
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "call", "LittleEndian", {} },
					
					{ "test.bt", 1, "variable", "int32", "a", nil, { "test.bt", 1, "num", 4 } },
					
					{ "test.bt", 1, "ref", { "a", { "test.bt", 1, "num", 4 } } },
				})
			end, "Attempt to access out-of-range array index 4 at test.bt:1")
	end)
	
	it("errors on array access of non-array variable", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "call", "LittleEndian", {} },
					{ "test.bt", 1, "variable", "int32", "a", nil, nil },
					{ "test.bt", 1, "ref", { "a", { "test.bt", 1, "num", 0 } } },
				})
			end, "Attempt to access non-array variable as array at test.bt:1")
	end)
	
	it("handles global structs", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "struct", "mystruct", {},
			{
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "x = %d" },
					{ "test.bt", 1, "ref", { "x" } } } },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "y = %d" },
					{ "test.bt", 1, "ref", { "y" } } } },
			} },
			
			{ "test.bt", 1, "variable", "struct mystruct", "a", nil, nil },
			{ "test.bt", 1, "variable", "struct mystruct", "b", nil, nil },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_comment(0, 4, x)",
			
			"set_data_type(4, 4, s32le)",
			"set_comment(4, 4, y)",
			
			"print(x = 1)",
			"print(y = 2)",
			
			"set_comment(0, 8, a)",
			
			"set_data_type(8, 4, s32le)",
			"set_comment(8, 4, x)",
			
			"set_data_type(12, 4, s32le)",
			"set_comment(12, 4, y)",
			
			"print(x = 3)",
			"print(y = 4)",
			
			"set_comment(8, 8, b)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles global arrays of structs", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "struct", "mystruct", {},
			{
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "x = %d" },
					{ "test.bt", 1, "ref", { "x" } } } },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "y = %d" },
					{ "test.bt", 1, "ref", { "y" } } } },
			} },
			
			{ "test.bt", 1, "variable", "struct mystruct", "a", nil, { "test.bt", 1, "num", 2 } },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_comment(0, 4, x)",
			
			"set_data_type(4, 4, s32le)",
			"set_comment(4, 4, y)",
			
			"print(x = 1)",
				"print(y = 2)",
			
			"set_comment(0, 8, a[0])",
			
			"set_data_type(8, 4, s32le)",
			"set_comment(8, 4, x)",
			
			"set_data_type(12, 4, s32le)",
			"set_comment(12, 4, y)",
			
			"print(x = 3)",
			"print(y = 4)",
			
			"set_comment(8, 8, a[1])",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles nested structs", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "struct", "mystruct", {},
			{
				{ "test.bt", 1, "struct", "bstruct", {},
				{
					{ "test.bt", 1, "variable", "int", "x", nil, nil },
					{ "test.bt", 1, "variable", "int", "y", nil, nil },
					
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "bstruct x = %d" },
						{ "test.bt", 1, "ref", { "x" } } } },
				} },
				
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "struct bstruct", "y", nil, nil },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "mystruct x = %d" },
					{ "test.bt", 1, "ref", { "x" } } } },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "mystruct y.x = %d" },
					{ "test.bt", 1, "ref", { "y", "x" } } } },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "mystruct y.y = %d" },
					{ "test.bt", 1, "ref", { "y", "y" } } } },
			} },
			
			{ "test.bt", 1, "variable", "struct mystruct", "a", nil, nil },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_comment(0, 4, x)",
			
			"set_data_type(4, 4, s32le)",
			"set_comment(4, 4, x)",
			
			"set_data_type(8, 4, s32le)",
			"set_comment(8, 4, y)",
			
			"print(bstruct x = 2)",
			
			"set_comment(4, 8, y)",
			
			"print(mystruct x = 1)",
			"print(mystruct y.x = 2)",
			"print(mystruct y.y = 3)",
			
			"set_comment(0, 12, a)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles global structs with variable declarations", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "struct", "mystruct", {},
			{
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "x = %d" },
					{ "test.bt", 1, "ref", { "x" } } } },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "y = %d" },
					{ "test.bt", 1, "ref", { "y" } } } },
			}, nil, { "a", {}, nil } },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_comment(0, 4, x)",
			
			"set_data_type(4, 4, s32le)",
			"set_comment(4, 4, y)",
			
			"print(x = 1)",
			"print(y = 2)",
			
			"set_comment(0, 8, a)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles global structs with array variable declarations", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "struct", "mystruct", {},
			{
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "x = %d" },
					{ "test.bt", 1, "ref", { "x" } } } },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "y = %d" },
					{ "test.bt", 1, "ref", { "y" } } } },
			}, nil, { "a", {}, { "test.bt", 1, "num", 2 } } },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_comment(0, 4, x)",
			
			"set_data_type(4, 4, s32le)",
			"set_comment(4, 4, y)",
			
			"print(x = 1)",
				"print(y = 2)",
			
			"set_comment(0, 8, a[0])",
			
			"set_data_type(8, 4, s32le)",
			"set_comment(8, 4, x)",
			
			"set_data_type(12, 4, s32le)",
			"set_comment(12, 4, y)",
			
			"print(x = 3)",
			"print(y = 4)",
			
			"set_comment(8, 8, a[1])",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles anonymous structs with variable declarations", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "struct", nil, {},
			{
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "x = %d" },
					{ "test.bt", 1, "ref", { "x" } } } },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "y = %d" },
					{ "test.bt", 1, "ref", { "y" } } } },
			}, nil, { "a", {}, nil } },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_comment(0, 4, x)",
			
			"set_data_type(4, 4, s32le)",
			"set_comment(4, 4, y)",
			
			"print(x = 1)",
			"print(y = 2)",
			
			"set_comment(0, 8, a)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors on struct member redefinition", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "call", "LittleEndian", {} },
					
					{ "test.bt", 1, "struct", "mystruct", {},
					{
						{ "test.bt", 1, "variable", "int", "x", nil, nil },
						{ "test.bt", 1, "variable", "int", "x", nil, nil },
					} },
					
					{ "test.bt", 1, "variable", "struct mystruct", "a", nil, nil },
					{ "test.bt", 1, "variable", "struct mystruct", "b", nil, nil },
				})
			end, "Attempt to redefine struct member 'x' at test.bt:1")
	end)
	
	it("allows passing arguments to a global struct variable definition", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "struct", "mystruct", { { "int", "a" }, { "int", "b" }, { "string", "c" } },
			{
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "a = %d, b = %d, c = %s" },
					{ "test.bt", 1, "ref", { "a" } },
					{ "test.bt", 1, "ref", { "b" } },
					{ "test.bt", 1, "ref", { "c" } } } },
			} },
			
			{ "test.bt", 1, "variable", "struct mystruct", "a", {
				{ "test.bt", 1, "num", 1234 },
				{ "test.bt", 1, "num", 5678 },
				{ "test.bt", 1, "str", "hello" } } },
		})
		
		local expect_log = {
			"set_data_type(0, 4, s32le)",
			"set_comment(0, 4, x)",
			
			"set_data_type(4, 4, s32le)",
			"set_comment(4, 4, y)",
			
			"print(a = 1234, b = 5678, c = hello)",
			
			"set_comment(0, 8, a)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors when declaring a struct variable with too few arguments", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "call", "LittleEndian", {} },
				
				{ "test.bt", 1, "struct", "mystruct", { { "int", "a" }, { "int", "b" }, { "string", "c" } },
				{
					{ "test.bt", 1, "variable", "int", "x", nil, nil },
					{ "test.bt", 1, "variable", "int", "y", nil, nil },
					
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "a = %d, b = %d, c = %s" },
						{ "test.bt", 1, "ref", { "a" } },
						{ "test.bt", 1, "ref", { "b" } },
						{ "test.bt", 1, "ref", { "c" } } } },
				} },
				
				{ "test.bt", 1, "variable", "struct mystruct", "a", {
					{ "test.bt", 1, "num", 1234 },
					{ "test.bt", 1, "num", 5678 } } },
			})
			end, "Attempt to declare struct type 'struct mystruct' with incompatible argument types (int, int) - expected (int, int, string) at test.bt:1")
	end)
	
	it("errors when attempting to declare a struct variable with too many arguments", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "call", "LittleEndian", {} },
				
				{ "test.bt", 1, "struct", "mystruct", { { "int", "a" }, { "int", "b" }, { "string", "c" } },
				{
					{ "test.bt", 1, "variable", "int", "x", nil, nil },
					{ "test.bt", 1, "variable", "int", "y", nil, nil },
					
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "a = %d, b = %d, c = %s" },
						{ "test.bt", 1, "ref", { "a" } },
						{ "test.bt", 1, "ref", { "b" } },
						{ "test.bt", 1, "ref", { "c" } } } },
				} },
				
				{ "test.bt", 1, "variable", "struct mystruct", "a", {
					{ "test.bt", 1, "num", 1234 },
					{ "test.bt", 1, "num", 5678 },
					{ "test.bt", 1, "str", "hello" },
					{ "test.bt", 1, "str", "hello" } } },
			})
			end, "Attempt to declare struct type 'struct mystruct' with incompatible argument types (int, int, string, string) - expected (int, int, string) at test.bt:1")
	end)
	
	it("errors when attempting to declare a struct variable with incompatible argument types", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "call", "LittleEndian", {} },
				
				{ "test.bt", 1, "struct", "mystruct", { { "int", "a" }, { "int", "b" }, { "string", "c" } },
				{
					{ "test.bt", 1, "variable", "int", "x", nil, nil },
					{ "test.bt", 1, "variable", "int", "y", nil, nil },
					
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "a = %d, b = %d, c = %s" },
						{ "test.bt", 1, "ref", { "a" } },
						{ "test.bt", 1, "ref", { "b" } },
						{ "test.bt", 1, "ref", { "c" } } } },
				} },
				
				{ "test.bt", 1, "variable", "struct mystruct", "a", {
					{ "test.bt", 1, "num", 1234 },
					{ "test.bt", 1, "str", "hello" },
					{ "test.bt", 1, "str", "hello" } } },
			})
			end, "Attempt to declare struct type 'struct mystruct' with incompatible argument types (int, string, string) - expected (int, int, string) at test.bt:1")
	end)
	
	it("returns return values from functions", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "function", "int", "func1", {},
			{
				{ "test.bt", 1, "return",
					{ "test.bt", 1, "num", 1 } },
			} },
			
			{ "test.bt", 1, "function", "int", "func2", {},
			{
				{ "test.bt", 1, "return",
					{ "test.bt", 1, "num", 2 } },
			} },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "func1() = %d" },
				{ "test.bt", 1, "call", "func1", {} },
			} },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "func2() = %d" },
				{ "test.bt", 1, "call", "func2", {} },
			} },
		})
		
		local expect_log = {
			"print(func1() = 1)",
			"print(func2() = 2)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows early return from functions", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "function", "int", "ifunc", {},
			{
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "foo" } } },
				
				{ "test.bt", 1, "return",
					{ "test.bt", 1, "num", 1 } },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "bar" } } },
			} },
			
			{ "test.bt", 1, "function", "void", "vfunc", {},
			{
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "baz" } } },
				
				{ "test.bt", 1, "return" },
				
				{ "test.bt", 1, "call", "Printf", {
					{ "test.bt", 1, "str", "quz" } } },
			} },
			
			{ "test.bt", 1, "call", "ifunc", {} },
			{ "test.bt", 1, "call", "vfunc", {} },
		})
		
		local expect_log = {
			"print(foo)",
			"print(baz)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors on incorrect return types", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "int", "ifunc", {},
				{
					{ "test.bt", 1, "return",
						{ "test.bt", 1, "str", "hello" } },
				} },
				
				{ "test.bt", 1, "call", "ifunc", {} },
			})
		end, "return operand type 'string' not compatible with function return type 'int' at test.bt:1")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "int", "ifunc", {},
				{
					{ "test.bt", 1, "return" },
				} },
				
				{ "test.bt", 1, "call", "ifunc", {} },
			})
		end, "return without an operand in function that returns type 'int' at test.bt:1")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "vfunc", {},
				{
					{ "test.bt", 1, "return",
						{ "test.bt", 1, "num", 0 } },
				} },
				
				{ "test.bt", 1, "call", "vfunc", {} },
			})
		end, "return operand type 'int' not compatible with function return type 'void' at test.bt:1")
	end)
	
	it("allows addition of integers with '+' operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "10 + 20 = %s" },
				{ "test.bt", 1, "add",
					{ "test.bt", 1, "num", 10 },
					{ "test.bt", 1, "num", 20 } } } },
		})
		
		local expect_log = {
			"print(10 + 20 = 30)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows addition of real numbers with '+' operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "10.2 + 20.4 = %s" },
				{ "test.bt", 1, "add",
					{ "test.bt", 1, "num", 10.2 },
					{ "test.bt", 1, "num", 20.4 } } } },
		})
		
		local expect_log = {
			"print(10.2 + 20.4 = 30.6)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows concatenation of strings with '+' operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "abc + def = %s" },
				{ "test.bt", 1, "add",
					{ "test.bt", 1, "str", "abc" },
					{ "test.bt", 1, "str", "def" } } } },
		})
		
		local expect_log = {
			"print(abc + def = abcdef)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows concatenation of char arrays with '+' operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "char", "char_array1", nil, { "test.bt", 1, "num", 10 }, { "test.bt", 1, "str", "abc" } },
			{ "test.bt", 1, "local-variable", "char", "char_array2", nil, { "test.bt", 1, "num", 10 }, { "test.bt", 1, "str", "def" } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "char_array1 + char_array2 = %s" },
				{ "test.bt", 1, "add",
					{ "test.bt", 1, "ref", { "char_array1" } },
					{ "test.bt", 1, "ref", { "char_array2" } } } } },
		})
		
		local expect_log = {
			"print(char_array1 + char_array2 = abcdef)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows concatenation of strings and char arrays with '+' operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "char", "char_array2", nil, { "test.bt", 1, "num", 10 }, { "test.bt", 1, "str", "def" } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "abc + char_array2 = %s" },
				{ "test.bt", 1, "add",
					{ "test.bt", 1, "str", "abc" },
					{ "test.bt", 1, "ref", { "char_array2" } } } } },
		})
		
		local expect_log = {
			"print(abc + char_array2 = abcdef)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors on addition of strings and numbers with '+' operator", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "add",
					{ "test.bt", 1, "str", "abc" },
					{ "test.bt", 1, "num", 123 } },
			})
			end, "Invalid operands to '+' operator - 'string' and 'int' at test.bt:1")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "add",
					{ "test.bt", 1, "num", 123 },
					{ "test.bt", 1, "str", "abc" } },
			})
			end, "Invalid operands to '+' operator - 'int' and 'string' at test.bt:1")
	end)
	
	it("implements > operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 > 0 = %d" },
				{ "test.bt", 1, "greater-than",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 0 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 > 1 = %d" },
				{ "test.bt", 1, "greater-than",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 > 2 = %d" },
				{ "test.bt", 1, "greater-than",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 2 }
				} } },
		})
		
		local expect_log = {
			"print(1 > 0 = 1)",
			"print(1 > 1 = 0)",
			"print(1 > 2 = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("implements >= operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 >= 0 = %d" },
				{ "test.bt", 1, "greater-than-or-equal",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 0 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 >= 1 = %d" },
				{ "test.bt", 1, "greater-than-or-equal",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 >= 2 = %d" },
				{ "test.bt", 1, "greater-than-or-equal",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 2 }
				} } },
		})
		
		local expect_log = {
			"print(1 >= 0 = 1)",
			"print(1 >= 1 = 1)",
			"print(1 >= 2 = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
        it("implements < operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "0 < 1 = %d" },
				{ "test.bt", 1, "less-than",
					{ "test.bt", 1, "num", 0 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 < 1 = %d" },
				{ "test.bt", 1, "less-than",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "2 < 1 = %d" },
				{ "test.bt", 1, "less-than",
					{ "test.bt", 1, "num", 2 },
					{ "test.bt", 1, "num", 1 }
				} } },
		})
		
		local expect_log = {
			"print(0 < 1 = 1)",
			"print(1 < 1 = 0)",
			"print(2 < 1 = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("implements <= operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "0 <= 1 = %d" },
				{ "test.bt", 1, "less-than-or-equal",
					{ "test.bt", 1, "num", 0 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 <= 1 = %d" },
				{ "test.bt", 1, "less-than-or-equal",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "2 <= 1 = %d" },
				{ "test.bt", 1, "less-than-or-equal",
					{ "test.bt", 1, "num", 2 },
					{ "test.bt", 1, "num", 1 }
				} } },
		})
		
		local expect_log = {
			"print(0 <= 1 = 1)",
			"print(1 <= 1 = 1)",
			"print(2 <= 1 = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("implements == operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "0 == 1 = %d" },
				{ "test.bt", 1, "equal",
					{ "test.bt", 1, "num", 0 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 == 1 = %d" },
				{ "test.bt", 1, "equal",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "-1 == 1 = %d" },
				{ "test.bt", 1, "equal",
					{ "test.bt", 1, "num", -1 },
					{ "test.bt", 1, "num", 1 }
				} } },
		})
		
		local expect_log = {
			"print(0 == 1 = 0)",
			"print(1 == 1 = 1)",
			"print(-1 == 1 = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("implements != operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "0 != 1 = %d" },
				{ "test.bt", 1, "not-equal",
					{ "test.bt", 1, "num", 0 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "1 != 1 = %d" },
				{ "test.bt", 1, "not-equal",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "num", 1 }
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "-1 != 1 = %d" },
				{ "test.bt", 1, "not-equal",
					{ "test.bt", 1, "num", -1 },
					{ "test.bt", 1, "num", 1 }
				} } },
		})
		
		local expect_log = {
			"print(0 != 1 = 1)",
			"print(1 != 1 = 0)",
			"print(-1 != 1 = 1)",
		}
		
		assert.are.same(expect_log, log)
	end)
        
        it("executes statements from first true branch in if statement", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "if",
				{ { "test.bt", 1, "num", 1 }, {
					{ "test.bt", 1, "call", "Printf",
						{ { "test.bt", 1, "str", "true branch executed (1)" } } },
				} },
				{ { "test.bt", 1, "num", 1 }, {
					{ "test.bt", 1, "call", "Printf",
						{ { "test.bt", 1, "str", "second true branch executed (2)" } } },
				} } },
			{ "test.bt", 1, "if",
				{ { "test.bt", 1, "num", 0 }, {
					{ "test.bt", 1, "call", "Printf",
						{ { "test.bt", 1, "str", "false branch executed (3)" } } },
				} },
				{ { "test.bt", 1, "num", 1 }, {
					{ "test.bt", 1, "call", "Printf",
						{ { "test.bt", 1, "str", "true branch executed (4)" } } },
				} } },
			{ "test.bt", 1, "if",
				{ { "test.bt", 1, "num", 0 }, {
					{ "test.bt", 1, "call", "Printf",
						{ { "test.bt", 1, "str", "false branch executed (5)" } } },
				} },
				{ { "test.bt", 1, "num", 0 }, {
					{ "test.bt", 1, "call", "Printf",
						{ { "test.bt", 1, "str", "false branch executed (6)" } } },
				} } },
			{ "test.bt", 1, "if",
				{ { "test.bt", 1, "num", 0 }, {
					{ "test.bt", 1, "call", "Printf",
						{ { "test.bt", 1, "str", "false branch executed (7)" } } },
				} },
				{ {
					{ "test.bt", 1, "call", "Printf",
						{ { "test.bt", 1, "str", "fallback branch executed (8)" } } },
				} } },
		})
		
		local expect_log = {
			"print(true branch executed (1))",
			"print(true branch executed (4))",
			"print(fallback branch executed (8))",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("implements && operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			-- TRUE && TRUE
			
			{ "test.bt", 1, "function", "int", "true_before_true", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "true_before_true() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 1 } },
			} },
			{ "test.bt", 1, "function", "int", "true_after_true", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "true_after_true() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 1 } },
			} },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "true_before_true() && true_after_true() = %d" },
				{ "test.bt", 1, "logical-and",
					{ "test.bt", 1, "call", "true_before_true", {} },
					{ "test.bt", 1, "call", "true_after_true", {} } },
			} },
			
			-- FALSE && TRUE
			
			{ "test.bt", 1, "function", "int", "false_before_true", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "false_before_true() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 0 } },
			} },
			{ "test.bt", 1, "function", "int", "true_after_false", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "true_after_false() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 1 } },
			} },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "false_before_true() && true_after_false() = %d" },
				{ "test.bt", 1, "logical-and",
					{ "test.bt", 1, "call", "false_before_true", {} },
					{ "test.bt", 1, "call", "true_after_false", {} } },
			} },
			
			-- TRUE && FALSE
			
			{ "test.bt", 1, "function", "int", "true_before_false", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "true_before_false() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 1 } },
			} },
			{ "test.bt", 1, "function", "int", "false_after_true", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "false_after_true() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 0 } },
			} },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "true_before_false() && false_after_true() = %d" },
				{ "test.bt", 1, "logical-and",
					{ "test.bt", 1, "call", "true_before_false", {} },
					{ "test.bt", 1, "call", "false_after_true", {} } },
			} },
			
			-- FALSE && FALSE
			
			{ "test.bt", 1, "function", "int", "false_before_false", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "false_before_false() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 0 } },
			} },
			{ "test.bt", 1, "function", "int", "false_after_false", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "false_after_false() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 0 } },
			} },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "false_before_false() && false_after_false() = %d" },
				{ "test.bt", 1, "logical-and",
					{ "test.bt", 1, "call", "false_before_false", {} },
					{ "test.bt", 1, "call", "false_after_false", {} } },
			} },
		})
		
		local expect_log = {
			"print(true_before_true() called)",
			"print(true_after_true() called)",
			"print(true_before_true() && true_after_true() = 1)",
			
			"print(false_before_true() called)",
			"print(false_before_true() && true_after_false() = 0)",
			
			"print(true_before_false() called)",
			"print(false_after_true() called)",
			"print(true_before_false() && false_after_true() = 0)",
			
			"print(false_before_false() called)",
			"print(false_before_false() && false_after_false() = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors on incorrect types to && operator", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "logical-and",
					{ "test.bt", 1, "str", "hello" },
					{ "test.bt", 1, "num", 1 } },
			})
		end, "Invalid left operand to '&&' operator - expected numeric, got 'string' at test.bt:1")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "voidfunc", {}, {} },
				
				{ "test.bt", 1, "logical-and",
					{ "test.bt", 1, "num", 1 },
					{ "test.bt", 1, "call", "voidfunc", {} } },
			})
		end, "Invalid right operand to '&&' operator - expected numeric, got 'void' at test.bt:1")
	end)
	
	it("implements || operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			-- TRUE || TRUE
			
			{ "test.bt", 1, "function", "int", "true_before_true", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "true_before_true() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 1 } },
			} },
			{ "test.bt", 1, "function", "int", "true_after_true", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "true_after_true() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 1 } },
			} },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "true_before_true() || true_after_true() = %d" },
				{ "test.bt", 1, "logical-or",
					{ "test.bt", 1, "call", "true_before_true", {} },
					{ "test.bt", 1, "call", "true_after_true", {} } },
			} },
			
			-- FALSE || TRUE
			
			{ "test.bt", 1, "function", "int", "false_before_true", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "false_before_true() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 0 } },
			} },
			{ "test.bt", 1, "function", "int", "true_after_false", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "true_after_false() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 1 } },
			} },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "false_before_true() || true_after_false() = %d" },
				{ "test.bt", 1, "logical-or",
					{ "test.bt", 1, "call", "false_before_true", {} },
					{ "test.bt", 1, "call", "true_after_false", {} } },
			} },
			
			-- TRUE || FALSE
			
			{ "test.bt", 1, "function", "int", "true_before_false", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "true_before_false() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 1 } },
			} },
			{ "test.bt", 1, "function", "int", "false_after_true", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "false_after_true() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 0 } },
			} },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "true_before_false() || false_after_true() = %d" },
				{ "test.bt", 1, "logical-or",
					{ "test.bt", 1, "call", "true_before_false", {} },
					{ "test.bt", 1, "call", "false_after_true", {} } },
			} },
			
			-- FALSE || FALSE
			
			{ "test.bt", 1, "function", "int", "false_before_false", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "false_before_false() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 0 } },
			} },
			{ "test.bt", 1, "function", "int", "false_after_false", {}, {
				{ "test.bt", 1, "call", "Printf",
					{ { "test.bt", 1, "str", "false_after_false() called" } } },
				{ "test.bt", 1, "return", { "test.bt", 1, "num", 0 } },
			} },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "false_before_false() || false_after_false() = %d" },
				{ "test.bt", 1, "logical-or",
					{ "test.bt", 1, "call", "false_before_false", {} },
					{ "test.bt", 1, "call", "false_after_false", {} } },
			} },
		})
		
		local expect_log = {
			"print(true_before_true() called)",
			"print(true_before_true() || true_after_true() = 1)",
			
			"print(false_before_true() called)",
			"print(true_after_false() called)",
			"print(false_before_true() || true_after_false() = 1)",
			
			"print(true_before_false() called)",
			"print(true_before_false() || false_after_true() = 1)",
			
			"print(false_before_false() called)",
			"print(false_after_false() called)",
			"print(false_before_false() || false_after_false() = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors on incorrect types to || operator", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "voidfunc", {}, {} },
				
				{ "test.bt", 1, "logical-or",
					{ "test.bt", 1, "call", "voidfunc", {} },
					{ "test.bt", 1, "num", 1 } },
			})
		end, "Invalid left operand to '||' operator - expected numeric, got 'void' at test.bt:1")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "logical-or",
					{ "test.bt", 1, "num", 0 },
					{ "test.bt", 1, "str", "hello" } },
			})
		end, "Invalid right operand to '||' operator - expected numeric, got 'string' at test.bt:1")
	end)
	
	it("implements ! operator", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "!0 = %d" },
				{ "test.bt", 1, "logical-not", { "test.bt", 1, "num", 0 } }
			} },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "!1 = %d" },
				{ "test.bt", 1, "logical-not", { "test.bt", 1, "num", 1 } }
			} },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "!2 = %d" },
				{ "test.bt", 1, "logical-not", { "test.bt", 1, "num", 2 } }
			} },
		})
		
		local expect_log = {
			"print(!0 = 1)",
			"print(!1 = 0)",
			"print(!2 = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors on incorrect type to ! operator", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "voidfunc", {}, {} },
				{ "test.bt", 1, "logical-not", { "test.bt", 1, "call", "voidfunc", {} } },
			})
		end, "Invalid operand to '!' operator - expected numeric, got 'void' at test.bt:1")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "logical-not", { "test.bt", 1, "str", "hello" } },
			})
		end, "Invalid operand to '!' operator - expected numeric, got 'string' at test.bt:1")
	end)
	
	it("allows defining local variables", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "int", "foo", nil, nil, nil },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "foo = %d" },
				{ "test.bt", 1, "ref", { "foo" } } } },
		})
		
		local expect_log = {
			"print(foo = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows defining and initialising local variables", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "int", "foo", nil, nil, { "test.bt", 1, "num", 1234 } },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "foo = %d" },
				{ "test.bt", 1, "ref", { "foo" } } } },
		})
		
		local expect_log = {
			"print(foo = 1234)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows assigning local variables", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "int", "foo", nil, nil, nil },
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "foo" } },
				{ "test.bt", 1, "num", 5678 } },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "foo = %d" },
				{ "test.bt", 1, "ref", { "foo" } } } },
		})
		
		local expect_log = {
			"print(foo = 5678)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows initialising a char array with a string", function()
		local interface, log = test_interface()
		
		local print_elem = function(i)
			return { "test.bt", 10 + i, "call", "Printf", {
				{ "test.bt", 10 + i, "str", "char_array[" .. i .. "] = %d" },
				{ "test.bt", 10 + i, "ref", { "char_array", { "test.bt", 10 + i, "num", i } } } } }
		end
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "char", "char_array", nil, { "test.bt", 1, "num", 10 }, { "test.bt", 1, "str", "hello" } },
			
			print_elem(0),
			print_elem(1),
			print_elem(2),
			print_elem(3),
			print_elem(4),
			print_elem(5),
			print_elem(6),
			print_elem(7),
			print_elem(8),
			print_elem(9),
		})
		
		local expect_log = {
			"print(char_array[0] = 104)",
			"print(char_array[1] = 101)",
			"print(char_array[2] = 108)",
			"print(char_array[3] = 108)",
			"print(char_array[4] = 111)",
			"print(char_array[5] = 0)",
			"print(char_array[6] = 0)",
			"print(char_array[7] = 0)",
			"print(char_array[8] = 0)",
			"print(char_array[9] = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows assigning a string value to a char array", function()
		local interface, log = test_interface()
		
		local print_elem = function(i)
			return { "test.bt", 10 + i, "call", "Printf", {
				{ "test.bt", 10 + i, "str", "char_array[" .. i .. "] = %d" },
				{ "test.bt", 10 + i, "ref", { "char_array", { "test.bt", 10 + i, "num", i } } } } }
		end
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "char", "char_array", nil, { "test.bt", 1, "num", 10 }, nil },
			{ "test.bt", 2, "assign", { "test.bt", 1, "ref", { "char_array" } }, { "test.bt", 1, "str", "hello" } },
			
			print_elem(0),
			print_elem(1),
			print_elem(2),
			print_elem(3),
			print_elem(4),
			print_elem(5),
			print_elem(6),
			print_elem(7),
			print_elem(8),
			print_elem(9),
		})
		
		local expect_log = {
			"print(char_array[0] = 104)",
			"print(char_array[1] = 101)",
			"print(char_array[2] = 108)",
			"print(char_array[3] = 108)",
			"print(char_array[4] = 111)",
			"print(char_array[5] = 0)",
			"print(char_array[6] = 0)",
			"print(char_array[7] = 0)",
			"print(char_array[8] = 0)",
			"print(char_array[9] = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows initialising a string with a char array", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "char", "char_array", nil, { "test.bt", 1, "num", 10 }, { "test.bt", 1, "str", "hello" } },
			{ "test.bt", 2, "local-variable", "string", "string_var", nil, nil, { "test.bt", 2, "ref", { "char_array" } } },
			
			{ "test.bt", 10, "call", "Printf", {
				{ "test.bt", 10, "str", "string_var = %s" },
				{ "test.bt", 10, "ref", { "string_var" } } } },
		})
		
		local expect_log = {
			"print(string_var = hello)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows assigning a char array to a string", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "char", "char_array", nil, { "test.bt", 1, "num", 10 }, { "test.bt", 1, "str", "hello" } },
			{ "test.bt", 2, "local-variable", "string", "string_var", nil, nil, nil },
			{ "test.bt", 3, "assign", { "test.bt", 3, "ref", { "string_var" } }, { "test.bt", 3, "ref", { "char_array" } } },
			
			{ "test.bt", 10, "call", "Printf", {
				{ "test.bt", 10, "str", "string_var = %s" },
				{ "test.bt", 10, "ref", { "string_var" } } } },
		})
		
		local expect_log = {
			"print(string_var = hello)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors on initialisation of uchar array from a string", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "local-variable", "uchar", "uchar_array", nil, { "test.bt", 1, "num", 10 }, { "test.bt", 1, "str", "hello" } },
			})
			end, "can't assign 'string' to type 'uchar[]'")
	end)
	
	it("errors on assignment of string value to uchar array", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "local-variable", "uchar", "uchar_array", nil, { "test.bt", 1, "num", 10 }, nil },
				{ "test.bt", 2, "assign", { "test.bt", 1, "ref", { "uchar_array" } }, { "test.bt", 1, "str", "hello" } },
			})
			end, "can't assign 'string' to type 'uchar[]'")
	end)
	
	it("errors on initialisation of string from uchar array", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "local-variable", "uchar", "uchar_array", nil, { "test.bt", 1, "num", 10 }, nil },
				{ "test.bt", 2, "local-variable", "string", "string_var", nil, nil, { "test.bt", 2, "ref", { "uchar_array" } } },
			})
			end, "can't assign 'uchar[]' to type 'string'")
	end)
	
	it("errors on assignment of uchar array to string", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "local-variable", "uchar", "uchar_array", nil, { "test.bt", 1, "num", 10 }, nil },
				{ "test.bt", 2, "local-variable", "string", "string_var", nil, nil, nil },
				{ "test.bt", 3, "assign", { "test.bt", 3, "ref", { "string_var" } }, { "test.bt", 3, "ref", { "uchar_array" } } },
			})
			end, "can't assign 'uchar[]' to type 'string'")
	end)
	
	it("allows using local array variables", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "int", "foo", nil, { "test.bt", 1, "num", 3 }, nil },
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "foo", { "test.bt", 1, "num", 0 } } },
				{ "test.bt", 1, "num", 1234 } },
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "foo", { "test.bt", 1, "num", 1 } } },
				{ "test.bt", 1, "num", 5678 } },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "foo[0] = %d" },
				{ "test.bt", 1, "ref", { "foo", { "test.bt", 1, "num", 0 } } } } },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "foo[1] = %d" },
				{ "test.bt", 1, "ref", { "foo", { "test.bt", 1, "num", 1 } } } } },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "foo[2] = %d" },
				{ "test.bt", 1, "ref", { "foo", { "test.bt", 1, "num", 2 } } } } },
		})
		
		local expect_log = {
			"print(foo[0] = 1234)",
			"print(foo[1] = 5678)",
			"print(foo[2] = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("implements endianness functions", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			-- Default state
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "IsBigEndian() = %d" },
				{ "test.bt", 1, "call", "IsBigEndian", {} } } },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "IsLittleEndian() = %d" },
				{ "test.bt", 1, "call", "IsLittleEndian", {} } } },
			
			-- After call to BigEndian()
			
			{ "test.bt", 1, "call", "BigEndian", {} },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "IsBigEndian() = %d" },
				{ "test.bt", 1, "call", "IsBigEndian", {} } } },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "IsLittleEndian() = %d" },
				{ "test.bt", 1, "call", "IsLittleEndian", {} } } },
			
			-- After call to LittleEndian()
			
			{ "test.bt", 1, "call", "LittleEndian", {} },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "IsBigEndian() = %d" },
				{ "test.bt", 1, "call", "IsBigEndian", {} } } },
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "IsLittleEndian() = %d" },
				{ "test.bt", 1, "call", "IsLittleEndian", {} } } },
		})
		
		local expect_log = {
			"print(IsBigEndian() = 0)",
			"print(IsLittleEndian() = 1)",
			
			"print(IsBigEndian() = 1)",
			"print(IsLittleEndian() = 0)",
			
			"print(IsBigEndian() = 0)",
			"print(IsLittleEndian() = 1)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("implements file position functions", function()
		local interface, log = test_interface(string.char(
			0x01, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x00, 0x00,
			0x03, 0x00, 0x00, 0x00,
			0x04, 0x00, 0x00, 0x00
		))
		
		local printf_FileSize = function()
			return { "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "FileSize() = %d" },
				{ "test.bt", 1, "call", "FileSize", {} } } }
		end
		
		local printf_FEof = function()
			return { "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "FEof() = %d" },
				{ "test.bt", 1, "call", "FEof", {} } } }
		end
		
		local printf_FTell = function()
			return { "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "FTell() = %d" },
				{ "test.bt", 1, "call", "FTell", {} } } }
		end
		
		local FSeek = function(pos)
			return { "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "FSeek(" .. pos .. ") = %d" },
				{ "test.bt", 1, "call", "FSeek", {
					{ "test.bt", 1, "num", pos } } } } }
		end
		
		local FSkip = function(pos)
			return { "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "FSkip(" .. pos .. ") = %d" },
				{ "test.bt", 1, "call", "FSkip", {
					{ "test.bt", 1, "num", pos } } } } }
		end
		
		executor.execute(interface, {
			-- Default state
			
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			-- Try seeking to invalid offsets
			
			FSeek(-1),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			FSeek(17),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			-- Seek to a valid offset within the file
			
			FSeek(4),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			-- Seek to the end of the file
			
			FSeek(16),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			-- Skip back to the start of the file
			
			FSkip(-16),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			-- Skip to a position within the file
			
			FSkip(12),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			-- Skip to current position
			
			FSkip(0),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			-- Try skipping before start of file
			
			FSkip(-13),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			-- Try skipping past end of file
			
			FSkip(5),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
			
			-- Skip to end of file
			
			FSkip(4),
			printf_FileSize(),
			printf_FEof(),
			printf_FTell(),
		})
		
		local expect_log = {
			"print(FileSize() = 16)",
			"print(FEof() = 0)",
			"print(FTell() = 0)",
			
			"print(FSeek(-1) = -1)",
			"print(FileSize() = 16)",
			"print(FEof() = 0)",
			"print(FTell() = 0)",
			
			"print(FSeek(17) = -1)",
			"print(FileSize() = 16)",
			"print(FEof() = 0)",
			"print(FTell() = 0)",
			
			"print(FSeek(4) = 0)",
			"print(FileSize() = 16)",
			"print(FEof() = 0)",
			"print(FTell() = 4)",
			
			"print(FSeek(16) = 0)",
			"print(FileSize() = 16)",
			"print(FEof() = 1)",
			"print(FTell() = 16)",
			
			"print(FSkip(-16) = 0)",
			"print(FileSize() = 16)",
			"print(FEof() = 0)",
			"print(FTell() = 0)",
			
			"print(FSkip(12) = 0)",
			"print(FileSize() = 16)",
			"print(FEof() = 0)",
			"print(FTell() = 12)",
			
			"print(FSkip(0) = 0)",
			"print(FileSize() = 16)",
			"print(FEof() = 0)",
			"print(FTell() = 12)",
			
			"print(FSkip(-13) = -1)",
			"print(FileSize() = 16)",
			"print(FEof() = 0)",
			"print(FTell() = 12)",
			
			"print(FSkip(5) = -1)",
			"print(FileSize() = 16)",
			"print(FEof() = 0)",
			"print(FTell() = 12)",
			
			"print(FSkip(4) = 0)",
			"print(FileSize() = 16)",
			"print(FEof() = 1)",
			"print(FTell() = 16)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("implements ReadByte() function", function()
		local interface, log = test_interface(string.char(
			0x01, 0xFF, 0xFE, 0x04
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "ReadByte() = %d" },
				{ "test.bt", 1, "call", "ReadByte", {} } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "ReadByte() = %d" },
				{ "test.bt", 1, "call", "ReadByte", {} } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "ReadByte(1) = %d" },
				{ "test.bt", 1, "call", "ReadByte", {
					{ "test.bt", 1, "num", 1 } } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "ReadByte(2) = %d" },
				{ "test.bt", 1, "call", "ReadByte", {
					{ "test.bt", 1, "num", 2 } } } } },
		})
		
		local expect_log = {
			"print(ReadByte() = 1)",
			"print(ReadByte() = 1)",
			"print(ReadByte(1) = -1)",
			"print(ReadByte(2) = -2)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors when ReadByte() is called at end of file", function()
		local interface, log = test_interface(string.char(
			0x01, 0xFF, 0xFE, 0x04
		))
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "call", "FSeek", {
						{ "test.bt", 1, "num", 4, {} } } },
					
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "ReadByte() = %d" },
						{ "test.bt", 1, "call", "ReadByte", {} } } },
				})
			end, "Attempt to read past end of file in ReadByte function")
	end)
	
	it("implements ReadUInt() function", function()
		local interface, log = test_interface(string.char(
			0x00, 0x01, 0x00, 0x00,
			0xFF, 0xFF, 0xFF, 0xFF,
			0x00, 0x02, 0x00, 0x00
		))
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "ReadUInt() = %d" },
				{ "test.bt", 1, "call", "ReadUInt", {} } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "ReadUInt() = %d" },
				{ "test.bt", 1, "call", "ReadUInt", {} } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "ReadUInt(4) = %d" },
				{ "test.bt", 1, "call", "ReadUInt", {
					{ "test.bt", 1, "num", 4 } } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "ReadUInt(8) = %d" },
				{ "test.bt", 1, "call", "ReadUInt", {
					{ "test.bt", 1, "num", 8 } } } } },
		})
		
		local expect_log = {
			"print(ReadUInt() = 256)",
			"print(ReadUInt() = 256)",
			"print(ReadUInt(4) = 4294967295)",
			"print(ReadUInt(8) = 512)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors when ReadUInt() is called at end of file", function()
		local interface, log = test_interface(string.char(
			0x01, 0xFF, 0xFE, 0x04
		))
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "ReadUInt() = %d" },
						{ "test.bt", 1, "call", "ReadUInt", {
							{ "test.bt", 1, "num", 1, {} } } } } },
				})
			end, "Attempt to read past end of file in ReadUInt function")
	end)
	
	it("allows declaring a struct with a typedef", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "struct", "mystruct", {}, {
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
			}, "mystruct_t" },
			
			{ "test.bt", 1, "local-variable", "mystruct_t", "s", nil, nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "s.x = %d" },
				{ "test.bt", 1, "ref", { "s", "x" } } } },
		})
		
		local expect_log = {
			"print(s.x = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows declaring an anonymous struct with a typedef", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "struct", nil, {}, {
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
			}, "mystruct_t" },
			
			{ "test.bt", 1, "local-variable", "mystruct_t", "s", nil, nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "s.x = %d" },
				{ "test.bt", 1, "ref", { "s", "x" } } } },
		})
		
		local expect_log = {
			"print(s.x = 0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows assignment between struct type and typedef", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "struct", "mystruct", {}, {
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
			}, "mystruct_t" },
			
			{ "test.bt", 1, "local-variable", "struct mystruct", "bvar", nil, nil, nil },
			{ "test.bt", 1, "local-variable", "mystruct_t", "tvar", nil, nil, nil },
			
			-- Write into base struct and assign base to typedef
			
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "bvar", "x" } },
				{ "test.bt", 1, "num", 1234 } },
			
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "tvar" } },
				{ "test.bt", 1, "ref", { "bvar" } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "tvar.x = %d" },
				{ "test.bt", 1, "ref", { "tvar", "x" } } } },
			
			-- Write into typedef struct and assign to base
			
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "tvar", "y" } },
				{ "test.bt", 1, "num", 5678 } },
			
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "bvar" } },
				{ "test.bt", 1, "ref", { "tvar" } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "bvar.y = %d" },
				{ "test.bt", 1, "ref", { "bvar", "y" } } } },
		})
		
		local expect_log = {
			"print(tvar.x = 1234)",
			"print(bvar.y = 5678)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows assignment between different typedefs of the same struct", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "struct", "mystruct", {}, {
				{ "test.bt", 1, "variable", "int", "x", nil, nil },
				{ "test.bt", 1, "variable", "int", "y", nil, nil },
			}, "mystruct_t" },
			
			{ "test.bt", 1, "typedef", "struct mystruct", "mystruct_u" },
			
			{ "test.bt", 1, "local-variable", "mystruct_u", "bvar", nil, nil, nil },
			{ "test.bt", 1, "local-variable", "mystruct_t", "tvar", nil, nil, nil },
			
			-- Write into mystruct_u and assign to mystruct_t
			
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "bvar", "x" } },
				{ "test.bt", 1, "num", 1234 } },
			
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "tvar" } },
				{ "test.bt", 1, "ref", { "bvar" } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "tvar.x = %d" },
				{ "test.bt", 1, "ref", { "tvar", "x" } } } },
			
			-- Write into mystruct_t and assign to mystruct_u
			
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "tvar", "y" } },
				{ "test.bt", 1, "num", 5678 } },
			
			{ "test.bt", 1, "assign",
				{ "test.bt", 1, "ref", { "bvar" } },
				{ "test.bt", 1, "ref", { "tvar" } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "bvar.y = %d" },
				{ "test.bt", 1, "ref", { "bvar", "y" } } } },
		})
		
		local expect_log = {
			"print(tvar.x = 1234)",
			"print(bvar.y = 5678)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors on attempt to assign between distinct struct definitions", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "struct", "mystruct1", {}, {
					{ "test.bt", 1, "variable", "int", "x", nil, nil },
					{ "test.bt", 1, "variable", "int", "y", nil, nil },
				}, nil },
				
				{ "test.bt", 1, "struct", "mystruct2", {}, {
					{ "test.bt", 1, "variable", "int", "x", nil, nil },
					{ "test.bt", 1, "variable", "int", "y", nil, nil },
				}, nil },
				
				{ "test.bt", 1, "local-variable", "struct mystruct1", "s1", nil, nil, nil },
				{ "test.bt", 1, "local-variable", "struct mystruct2", "s2", nil, nil, nil },
				
				{ "test.bt", 1, "assign",
					{ "test.bt", 1, "ref", { "s1" } },
					{ "test.bt", 1, "ref", { "s2" } } },
			})
		end, "can't assign 'struct mystruct2' to type 'struct mystruct1'")
	end)
	
	it("allows defining enums", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "enum", "int", "myenum", {
				{ "FOO" },
				{ "BAR" },
				{ "BAZ" },
				{ "B_FOO", { "UNKNOWN FILE", 1, "num", 1 } },
				{ "B_BAR", { "UNKNOWN FILE", 1, "num", 3 } },
				{ "B_BAZ" },
			}, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "FOO = %d" },
				{ "test.bt", 1, "ref", { "FOO" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "BAR = %d" },
				{ "test.bt", 1, "ref", { "BAR" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "BAZ = %d" },
				{ "test.bt", 1, "ref", { "BAZ" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "B_FOO = %d" },
				{ "test.bt", 1, "ref", { "B_FOO" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "B_BAR = %d" },
				{ "test.bt", 1, "ref", { "B_BAR" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "B_BAZ = %d" },
				{ "test.bt", 1, "ref", { "B_BAZ" } } } },
			
			{ "test.bt", 1, "local-variable",
				"enum myenum", "e", nil, nil, { "test.bt", 1, "ref", { "B_BAZ" } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "e = %d" },
				{ "test.bt", 1, "ref", { "e" } } } },
		})
		
		local expect_log = {
			"print(FOO = 0)",
			"print(BAR = 1)",
			"print(BAZ = 2)",
			"print(B_FOO = 1)",
			"print(B_BAR = 3)",
			"print(B_BAZ = 4)",
			"print(e = 4)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows defining enums with a typedef", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "enum", "int", "myenum", {
				{ "FOO", { "UNKNOWN FILE", 1, "num", 1234 } },
				{ "BAR" },
			}, "myenum_t" },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "FOO = %d" },
				{ "test.bt", 1, "ref", { "FOO" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "BAR = %d" },
				{ "test.bt", 1, "ref", { "BAR" } } } },
			
			{ "test.bt", 1, "local-variable",
				"enum myenum", "e1", nil, nil, { "test.bt", 1, "ref", { "FOO" } } },
			
			{ "test.bt", 1, "local-variable",
				"myenum_t", "e2", nil, nil, { "test.bt", 1, "ref", { "BAR" } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "e1 = %d" },
				{ "test.bt", 1, "ref", { "e1" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "e2 = %d" },
				{ "test.bt", 1, "ref", { "e2" } } } },
		})
		
		local expect_log = {
			"print(FOO = 1234)",
			"print(BAR = 1235)",
			"print(e1 = 1234)",
			"print(e2 = 1235)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows defining anonymous enums with a typedef", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "enum", "int", nil, {
				{ "FOO", { "UNKNOWN FILE", 1, "num", 1234 } },
				{ "BAR" },
			}, "myenum_t" },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "FOO = %d" },
				{ "test.bt", 1, "ref", { "FOO" } } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "BAR = %d" },
				{ "test.bt", 1, "ref", { "BAR" } } } },
			
			{ "test.bt", 1, "local-variable",
				"myenum_t", "e", nil, nil, { "test.bt", 1, "ref", { "FOO" } } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "e = %d" },
				{ "test.bt", 1, "ref", { "e" } } } },
		})
		
		local expect_log = {
			"print(FOO = 1234)",
			"print(BAR = 1235)",
			"print(e = 1234)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors when defining an enum with an undefined type", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "enum", "nosuch_t", "myenum", {
					{ "FOO" },
				}, nil },
			})
			end, "Use of undefined type 'nosuch_t' at test.bt:1")
	end)
	
	it("errors when defining the same multiple times in an enum", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "enum", "int", "myenum", {
					{ "FOO" },
					{ "FOO" },
				}, nil },
			})
			end, "Attempt to redefine name 'FOO' at test.bt:1")
	end)
	
	it("errors when reusing an existing variable name as an enum member", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "local-variable", "int", "FOO", nil, nil, nil },
				
				{ "test.bt", 2, "enum", "int", "myenum", {
					{ "FOO" },
				}, nil },
			})
			end, "Attempt to redefine name 'FOO' at test.bt:2")
	end)
	
	it("errors when redefining an enum type", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "enum", "int", "myenum", {
					{ "FOO" },
				}, nil },
				
				{ "test.bt", 2, "enum", "int", "myenum", {
					{ "FOO" },
				}, nil },
			})
			end, "Attempt to redefine type 'enum myenum' at test.bt:2")
	end)
	
	it("errors when redefining a type using typedef enum", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "enum", "int", "myenum", {
					{ "FOO" },
				}, "int" },
			})
			end, "Attempt to redefine type 'int' at test.bt:1")
	end)
	
	it("errors when defining an enum member as a string", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "enum", "int", "myenum", {
					{ "FOO", { "test.bt", 1, "str", "" } },
				}, nil },
			})
			end, "Invalid type 'string' for enum member 'FOO' at test.bt:1")
	end)
	
	it("errors when defining an enum member as a void", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "vfunc", {}, {} },
				
				{ "test.bt", 1, "enum", "int", "myenum", {
					{ "FOO", { "test.bt", 1, "call", "vfunc", {} } },
				}, nil },
			})
			end, "Invalid type 'void' for enum member 'FOO' at test.bt:1")
	end)
	
	it("implements basic for loop behaviour", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "for",
				{ "test.bt", 1, "local-variable", "int", "i", nil, nil, { "test.bt", 1, "num", 0 } },
				{ "test.bt", 1, "less-than",
					{ "test.bt", 1, "ref", { "i" } },
					{ "test.bt", 1, "num", 5 } },
				{ "test.bt", 1, "assign",
					{ "test.bt", 1, "ref", { "i" } },
					{ "test.bt", 1, "add",
						{ "test.bt", 1, "ref", { "i" } },
						{ "test.bt", 1, "num", 1 } } },
				
				{
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "i = %d" },
						{ "test.bt", 1, "ref", { "i" } } } },
				} },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "end" } } },
		})
		
		local expect_log = {
			"print(i = 0)",
			"print(i = 1)",
			"print(i = 2)",
			"print(i = 3)",
			"print(i = 4)",
			"print(end)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows breaking out of a for loop", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "for",
				{ "test.bt", 1, "local-variable", "int", "i", nil, nil, { "test.bt", 1, "num", 0 } },
				{ "test.bt", 1, "less-than",
					{ "test.bt", 1, "ref", { "i" } },
					{ "test.bt", 1, "num", 5 } },
				{ "test.bt", 1, "assign",
					{ "test.bt", 1, "ref", { "i" } },
					{ "test.bt", 1, "add",
						{ "test.bt", 1, "ref", { "i" } },
						{ "test.bt", 1, "num", 1 } } },
				
				{
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "i = %d" },
						{ "test.bt", 1, "ref", { "i" } } } },
					
					{ "test.bt", 1, "break" },
				} },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "end" } } },
		})
		
		local expect_log = {
			"print(i = 0)",
			"print(end)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows continuing to next iteration of a for loop", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "for",
				{ "test.bt", 1, "local-variable", "int", "i", nil, nil, { "test.bt", 1, "num", 0 } },
				{ "test.bt", 1, "less-than",
					{ "test.bt", 1, "ref", { "i" } },
					{ "test.bt", 1, "num", 5 } },
				{ "test.bt", 1, "assign",
					{ "test.bt", 1, "ref", { "i" } },
					{ "test.bt", 1, "add",
						{ "test.bt", 1, "ref", { "i" } },
						{ "test.bt", 1, "num", 1 } } },
				
				{
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "i = %d" },
						{ "test.bt", 1, "ref", { "i" } } } },
					
					{ "test.bt", 1, "continue" },
					
					{ "test.bt", 1, "call", "Printf", {
						{ "test.bt", 1, "str", "i = %d (2)" },
						{ "test.bt", 1, "ref", { "i" } } } },
				} },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "end" } } },
		})
		
		local expect_log = {
			"print(i = 0)",
			"print(i = 1)",
			"print(i = 2)",
			"print(i = 3)",
			"print(i = 4)",
			"print(end)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("can be broken out of an infinite for loop via yield", function()
		local interface, log = test_interface()
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "for", nil, nil, nil, {} },
				})
			end, "Test timeout")
	end)
	
	it("scopes variables defined in for loop initialiser to the loop", function()
		local interface, log = test_interface()
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "for",
						{ "test.bt", 1, "local-variable", "int", "i", nil, nil, { "test.bt", 1, "num", 0 } },
						{ "test.bt", 1, "less-than",
							{ "test.bt", 1, "ref", { "i" } },
							{ "test.bt", 1, "num", 5 } },
						{ "test.bt", 1, "assign",
							{ "test.bt", 1, "ref", { "i" } },
							{ "test.bt", 1, "add",
								{ "test.bt", 1, "ref", { "i" } },
								{ "test.bt", 1, "num", 1 } } },
						
						{} },
					
					{ "test.bt", 2, "ref", { "i" } }
				})
			end, "Attempt to use undefined variable 'i' at test.bt:2")
	end)
	
	it("scopes variables defined in for loop to the loop", function()
		local interface, log = test_interface()
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "for",
						{ "test.bt", 1, "local-variable", "int", "i", nil, nil, { "test.bt", 1, "num", 0 } },
						{ "test.bt", 1, "less-than",
							{ "test.bt", 1, "ref", { "i" } },
							{ "test.bt", 1, "num", 5 } },
						{ "test.bt", 1, "assign",
							{ "test.bt", 1, "ref", { "i" } },
							{ "test.bt", 1, "add",
								{ "test.bt", 1, "ref", { "i" } },
								{ "test.bt", 1, "num", 1 } } },
						
						{
							{ "test.bt", 1, "local-variable", "int", "j", nil, nil, nil },
						} },
					
					{ "test.bt", 2, "ref", { "j" } }
				})
			end, "Attempt to use undefined variable 'j' at test.bt:2")
	end)
	
	it("allows returning from a loop inside a function", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "function", "int", "myfunc", {}, {
				{ "test.bt", 1, "for",
					{ "test.bt", 1, "local-variable", "int", "i", nil, nil, { "test.bt", 1, "num", 0 } },
					{ "test.bt", 1, "less-than",
						{ "test.bt", 1, "ref", { "i" } },
						{ "test.bt", 1, "num", 5 } },
					{ "test.bt", 1, "assign",
						{ "test.bt", 1, "ref", { "i" } },
						{ "test.bt", 1, "add",
							{ "test.bt", 1, "ref", { "i" } },
							{ "test.bt", 1, "num", 1 } } },
					
					{
						{ "test.bt", 1, "return", { "test.bt", 1, "num", 1234 } },
					},
				} } },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "%d" },
				{ "test.bt", 1, "call", "myfunc", {} } } },
		})
		
		local expect_log = {
			"print(1234)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("doesn't allow return from a loop not in a function", function()
		local interface, log = test_interface()
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "for",
						{ "test.bt", 1, "local-variable", "int", "i", nil, nil, { "test.bt", 1, "num", 0 } },
						{ "test.bt", 1, "less-than",
							{ "test.bt", 1, "ref", { "i" } },
							{ "test.bt", 1, "num", 5 } },
						{ "test.bt", 1, "assign",
							{ "test.bt", 1, "ref", { "i" } },
							{ "test.bt", 1, "add",
								{ "test.bt", 1, "ref", { "i" } },
								{ "test.bt", 1, "num", 1 } } },
						
						{
							{ "test.bt", 2, "return", { "test.bt", 1, "num", 1234 } },
						},
					},
				})
			end, "'return' statement not allowed here at test.bt:2")
	end)
	
	it("doesn't allow break outside of a loop", function()
		local interface, log = test_interface()
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "break" },
				})
			end, "'break' statement not allowed here at test.bt:1")
	end)
	
	it("doesn't allow continue outside of a loop", function()
		local interface, log = test_interface()
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "break" },
				})
			end, "'break' statement not allowed here at test.bt:1")
	end)
	
	it("doesn't allow break inside a function call inside a loop", function()
		local interface, log = test_interface()
		
		assert.has_error(
			function()
				executor.execute(interface, {
					{ "test.bt", 1, "function", "int", "breakfunc", {}, {
						{ "test.bt", 2, "break" } } },
					
					{ "test.bt", 1, "for",
						{ "test.bt", 1, "local-variable", "int", "i", nil, nil, { "test.bt", 1, "num", 0 } },
						{ "test.bt", 1, "less-than",
							{ "test.bt", 1, "ref", { "i" } },
							{ "test.bt", 1, "num", 5 } },
						{ "test.bt", 1, "assign",
							{ "test.bt", 1, "ref", { "i" } },
							{ "test.bt", 1, "add",
								{ "test.bt", 1, "ref", { "i" } },
								{ "test.bt", 1, "num", 1 } } },
						
						{
							{ "test.bt", 1, "call", "breakfunc", {} },
						},
					},
				})
			end, "'break' statement not allowed here at test.bt:2")
	end)
	
	it("allows defining typedefs", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "typedef", "int", "myint_t", nil },
			{ "test.bt", 1, "local-variable", "myint_t", "myvar", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "%d" },
				{ "test.bt", 1, "ref", { "myvar" } } } },
		})
		
		local expect_log = {
			"print(0)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("allows defining array typedefs", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "typedef", "int", "myarr_t", { "test.bt", 1, "num", 4 } },
			{ "test.bt", 1, "local-variable", "myarr_t", "myarr", nil, nil },
			
			{ "test.bt", 1, "call", "Printf", {
				{ "test.bt", 1, "str", "%d, %d, %d, %d" },
				{ "test.bt", 1, "ref", { "myarr", { "test.bt", 1, "num", 0 } } },
				{ "test.bt", 1, "ref", { "myarr", { "test.bt", 1, "num", 1 } } },
				{ "test.bt", 1, "ref", { "myarr", { "test.bt", 1, "num", 2 } } },
				{ "test.bt", 1, "ref", { "myarr", { "test.bt", 1, "num", 3 } } } } },
		})
		
		local expect_log = {
			"print(0, 0, 0, 0)"
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors when defining an array typedef of an array type", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "typedef", "int", "myarr_t", { "test.bt", 1, "num", 4 } },
				{ "test.bt", 2, "typedef", "myarr_t", "myarrarr_t", { "test.bt", 2, "num", 4 } },
			})
			end, "Multidimensional arrays are not supported at test.bt:2")
	end)
	
	it("errors when declaring an array variable of an array type", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "typedef", "int", "myarr_t", { "test.bt", 1, "num", 4 } },
				{ "test.bt", 2, "local-variable", "myarr_t", "myarrarr", nil, { "test.bt", 2, "num", 4 } },
			})
			end, "Multidimensional arrays are not supported at test.bt:2")
	end)
	
	it("executes from matching case in a switch statement", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "switch", { "test.bt", 1, "num", 2 }, {
				{ nil,                        { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "default" } } } } },
				{ { "test.bt", 1, "num", 1 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "1" }       } } } },
				{ { "test.bt", 1, "num", 2 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "2" }       } } } },
				{ { "test.bt", 1, "num", 3 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "3" }       } } } },
			} },
		})
		
		local expect_log = {
			"print(2)",
			"print(3)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("executes from default case if none match in a switch statement", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "switch", { "test.bt", 1, "num", 4 }, {
				{ nil,                        { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "default" } } } } },
				{ { "test.bt", 1, "num", 1 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "1" }       } } } },
				{ { "test.bt", 1, "num", 2 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "2" }       } } } },
				{ { "test.bt", 1, "num", 3 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "3" }       } } } },
			} },
		})
		
		local expect_log = {
			"print(default)",
			"print(1)",
			"print(2)",
			"print(3)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("breaks out of a switch statement when a break is encountered", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "switch", { "test.bt", 1, "num", 2 }, {
				{ nil,                        { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "default" } } } } },
				{ { "test.bt", 1, "num", 1 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "1" }       } } } },
				{ { "test.bt", 1, "num", 2 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "2" }       } }, { "test.bt", 1, "break" } } },
				{ { "test.bt", 1, "num", 3 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "3" }       } } } },
			} },
			
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "end" } } },
		})
		
		local expect_log = {
			"print(2)",
			"print(end)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("supports using a switch statement with a string", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "switch", { "test.bt", 1, "str", "0" }, {
				{ { "test.bt", 1, "str", "00"  }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "00"  }       } } } },
				{ { "test.bt", 1, "str", "0"   }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "0"   }       } } } },
				{ { "test.bt", 1, "str", "000" }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "000" }       } } } },
			} },
		})
		
		local expect_log = {
			"print(0)",
			"print(000)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("errors when using an unsupported type with a switch statement", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "vfunc", {}, {} },
				
				{ "test.bt", 2, "switch", { "test.bt", 2, "call", "vfunc", {} }, {
					{ nil,                        { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "default" } } } } },
					{ { "test.bt", 1, "num", 1 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "1" }       } } } },
					{ { "test.bt", 1, "num", 2 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "2" }       } }, { "test.bt", 1, "break" } } },
					{ { "test.bt", 1, "num", 3 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "3" }       } } } },
				} },
			})
			end, "Unexpected type 'void' passed to 'switch' statement (expected number or string) at test.bt:2")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "struct", "mystruct", {},
				{
					{ "test.bt", 1, "variable", "int", "x", nil, nil },
				} },
				
				{ "test.bt", 1, "local-variable", "struct mystruct", "a", nil, nil, nil },
				
				{ "test.bt", 2, "switch", { "test.bt", 2, "ref", { "a" } }, {
					{ nil,                        { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "default" } } } } },
					{ { "test.bt", 1, "num", 1 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "1" }       } } } },
					{ { "test.bt", 1, "num", 2 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "2" }       } }, { "test.bt", 1, "break" } } },
					{ { "test.bt", 1, "num", 3 }, { { "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "3" }       } } } },
				} },
			})
			end, "Unexpected type 'struct mystruct' passed to 'switch' statement (expected number or string) at test.bt:2")
	end)
	
	it("errors when using a different type in a switch/case statement", function()
		local interface, log = test_interface()
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "vfunc", {}, {} },
				
				{ "test.bt", 2, "switch", { "test.bt", 2, "num", 0, {} }, {
					{ { "test.bt", 3, "call", "vfunc", {} }, {} },
					{ { "test.bt", 1, "num", 2 }, {} },
					{ { "test.bt", 1, "num", 3 }, {} },
				} },
			})
			end, "Unexpected type 'void' passed to 'case' statement (expected 'int') at test.bt:3")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 2, "switch", { "test.bt", 2, "num", 0, {} }, {
					{ { "test.bt", 3, "str", "hello" }, {} },
					{ { "test.bt", 1, "num", 2 }, {} },
					{ { "test.bt", 1, "num", 3 }, {} },
				} },
			})
			end, "Unexpected type 'string' passed to 'case' statement (expected 'int') at test.bt:3")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 1, "function", "void", "vfunc", {}, {} },
				
				{ "test.bt", 2, "switch", { "test.bt", 2, "str", "hello", {} }, {
					{ { "test.bt", 3, "call", "vfunc", {} }, {} },
					{ { "test.bt", 1, "num", 2 }, {} },
					{ { "test.bt", 1, "num", 3 }, {} },
				} },
			})
			end, "Unexpected type 'void' passed to 'case' statement (expected 'string') at test.bt:3")
		
		assert.has_error(function()
			executor.execute(interface, {
				{ "test.bt", 2, "switch", { "test.bt", 2, "str", "hello", {} }, {
					{ { "test.bt", 3, "num", 1 }, {} },
					{ { "test.bt", 1, "num", 2 }, {} },
					{ { "test.bt", 1, "num", 3 }, {} },
				} },
			})
			end, "Unexpected type 'int' passed to 'case' statement (expected 'string') at test.bt:3")
	end)
	
	it("allows casting between different integer types", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "local-variable", "int", "i", nil, nil, { "test.bt", 1, "num", 100 } },
			{ "test.bt", 1, "local-variable", "int", "c", nil, nil, { "test.bt", 1, "num", 100 } },
			
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(char)(i) = %d" },           { "test.bt", 1, "cast", "char",          { "test.bt", 1, "ref", { "i" }  } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(unsigned char)(i) = %d" },  { "test.bt", 1, "cast", "unsigned char", { "test.bt", 1, "ref", { "i" }  } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(signed char)(i) = %d" },    { "test.bt", 1, "cast", "signed char",   { "test.bt", 1, "ref", { "i" }  } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(int)(c) = %d"    },         { "test.bt", 1, "cast", "int",           { "test.bt", 1, "ref", { "c" }  } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(unsigned int)(c) = %d"  },  { "test.bt", 1, "cast", "unsigned int",  { "test.bt", 1, "ref", { "c" }  } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(signed int)(c) = %d"  },    { "test.bt", 1, "cast", "signed int",    { "test.bt", 1, "ref", { "c" }  } } } },
		})
		
		local expect_log = {
			"print((char)(i) = 100)",
			"print((unsigned char)(i) = 100)",
			"print((signed char)(i) = 100)",
			"print((int)(c) = 100)",
			"print((unsigned int)(c) = 100)",
			"print((signed int)(c) = 100)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles overflow when casting to unsigned types", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(uchar)(522) = %d" },     { "test.bt", 1, "cast", "uchar",  { "test.bt", 1, "num", 522 } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(ushort)(66536) = %d" },  { "test.bt", 1, "cast", "ushort", { "test.bt", 1, "num", 66536 } } } },
		})
		
		local expect_log = {
			"print((uchar)(522) = 10)",
			"print((ushort)(66536) = 1000)",
		}
		
		assert.are.same(expect_log, log)
	end)
	
	it("handles underflow when casting to unsigned types", function()
		local interface, log = test_interface()
		
		executor.execute(interface, {
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(uchar)(-1) = %d" },   { "test.bt", 1, "cast", "uchar",  { "test.bt", 1, "num", -1 } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(uchar)(-128) = %d" }, { "test.bt", 1, "cast", "uchar",  { "test.bt", 1, "num", -128 } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(uchar)(-129) = %d" }, { "test.bt", 1, "cast", "uchar",  { "test.bt", 1, "num", -129 } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(uchar)(-255) = %d" }, { "test.bt", 1, "cast", "uchar",  { "test.bt", 1, "num", -255 } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(uchar)(-256) = %d" }, { "test.bt", 1, "cast", "uchar",  { "test.bt", 1, "num", -256 } } } },
			{ "test.bt", 1, "call", "Printf", { { "test.bt", 1, "str", "(uchar)(-257) = %d" }, { "test.bt", 1, "cast", "uchar",  { "test.bt", 1, "num", -257 } } } },
		})
		
		local expect_log = {
			"print((uchar)(-1) = 255)",
			"print((uchar)(-128) = 128)",
			"print((uchar)(-129) = 127)",
			"print((uchar)(-255) = 1)",
			"print((uchar)(-256) = 0)",
			"print((uchar)(-257) = 255)",
		}
		
		assert.are.same(expect_log, log)
	end)
end)
