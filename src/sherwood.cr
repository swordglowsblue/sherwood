require "./bytecode"
require "./util"

module Sherwood
  VERSION = "0.1.0"

  # -- Bytecode instruction layout --
  #
  # SECTION: Literals
  #   Literals should be followed by n bytes of data to push as the given type.
  #   When encountered, the resulting value will be pushed to the stack.
  # = opcd name n =====================================================================================================================
  #   0x00 null 0
  #   0x01 byte 1
  #   0x02 bool 1
  #   0x03 i32  4
  #   0x04 i64  8
  #   0x05 u32  4
  #   0x06 u64  8
  #   0x07 str  (len:u32)+len
  # 
  # SECTION: Constructors
  #   In contrast to literals, constructors pop their initialization data from the stack like normal opcodes.
  #   When encountered, the resulting value will be pushed to the stack.
  # = opcd name (params) ==============================================================================================================
  #   0x10 list (len:num, members:any*len) -- Highest member on stack will be first in list. Errors if len < 0 or len > u32.
  #
  # SECTION: Stack Operations
  #   Base operations on the data stack itself.
  # = opcd name (params) ==============================================================================================================
  #   0x20 drop (v:any)        -- Removes the top of the stack.
  #   0x21 dupe (v:any)        -- Duplicates the top of the stack.
  #   0x22 swap (a:any, b:any) -- Swaps the top of the stack with the next value down.
  #
  # SECTION: Arithmetic Operations
  #   Basic and bitwise arithmetic operations.
  # = opcd name (params) ==============================================================================================================
  #   0x30 add  (a:num, b:num) -- Adds the two numbers on the top of the stack.
  #   0x31 sub  (a:num, b:num) -- Subtracts the number on the top of the stack from the number below it.
  #   0x32 mul  (a:num, b:num) -- Multiplies the two numbers on the top of the stack.
  #   0x33 div  (a:num, b:num) -- Divides the number on the top of the stack from the number below it.
  #   0x34 mod  (a:num, b:num) -- Gets the remainder of dividing the two numbers on the top of the stack.
  #   0x35 shl  (d:num, n:num) -- Shifts n left by d bits.
  #   0x36 shr  (d:num, n:num) -- Shifts n right by d bits.
  #   0x37 not  (a:num)        -- Bitwise NOT of a.
  #   0x38 and  (a:num, b:num) -- Bitwise AND of a and b.
  #   0x39 or   (a:num, b:num) -- Bitwise OR of a and b.
  #   0x3a xor  (a:num, b:num) -- Bitwise XOR of a and b.
  #
  # SECTION: IO Operations
  #   Basic IO interactions.
  # = opcd name (params) ==============================================================================================================
  #   0x40 getc ()      -- Gets a char from stdin and pushes it as a u32.
  #   0x41 getl ()      -- Gets a line from stdin and pushes it as a str (excluding trailing \r?\n).
  #   0x42 putc (c:num) -- Prints a number from the stack as a character. Errors if c < 0 or c > u32.
  #   0x43 puts (s:str) -- Prints a string from the stack.
  #
  # SECTION: Variable Operations
  #   Opcodes for interactng with variable storage.
  # = opcd name (params) ==============================================================================================================
  #   0x50 vget (name:str)  -- Pushes the value at the given variable name to the stack.
  #   0x51 vput (value:any) -- Stores the value on top of the stack as a variable.
  #   0x52 vdel (name:str)  -- Deletes the value at the given variable name.
  #   TODO: Scoping ops
  #   TODO: Rethink structure / execution model for variables
  #
  # TODO: Control Flow
  # TODO: Type Queries

  alias Any = Nil | Num | Bool | String | Array(Any)
  alias Num = Byte | Int32 | Int64 | UInt32 | UInt64

  def self.runBytecode(prog : IO)
    return self.runBytecode(prog.each_byte.to_a) end
  def self.runBytecode(*prog : Byte)
    return self.runBytecode(prog) end
  def self.runBytecode(prog : Array(Byte))
    return self.runBytecode(Bytecode.new(prog)) end
  def self.runBytecode(prog : Bytecode)
    insp  = 0
    stack = [] of Any
    vars  = {} of UInt64 => Any

    while op = prog[insp]?; case op.opcd
      # SECTION: Literals
      when 0x00 then stack.push(nil)
      when 0x01 then stack.push(op.data[0])
      when 0x02 then stack.push(op.data[0] > 0)
      when 0x03 then stack.push(op.data.map(&.to_i32).bitwiseConcat)
      when 0x04 then stack.push(op.data.map(&.to_i64).bitwiseConcat)
      when 0x05 then stack.push(op.data.map(&.to_u32).bitwiseConcat)
      when 0x06 then stack.push(op.data.map(&.to_u64).bitwiseConcat)
      when 0x07 then stack.push(op.data.skip(4).map(&.chr).sum(""))

      # SECTION: Constructors
      when 0x10 then stack.push(Array(Any).new(popType(Num, stack)) { stack.pop })

      # SECTION: Stack Operations
      when 0x20 then stack.pop()
      when 0x21 then stack.push(stack.last)
      when 0x22 then stack.push(stack.pop(), stack.pop())
        
      # SECTION: Arithmetic Operations
      when 0x30 then stack.push(popType(Num, stack) + popType(Num, stack))
      when 0x31 then stack.push((b = popType(Num, stack); popType(Num, stack)) - b)
      when 0x32 then stack.push(popType(Num, stack) * popType(Num, stack))
      when 0x33 then stack.push((b = popType(Num, stack); popType(Num, stack)) / b)
      when 0x34 then stack.push((b = popType(Num, stack); popType(Num, stack)) % b)
      when 0x35 then stack.push((b = popType(Num, stack); popType(Num, stack)) << b)
      when 0x36 then stack.push((b = popType(Num, stack); popType(Num, stack)) >> b)
      when 0x37 then stack.push(~popType(Num, stack))
      when 0x38 then stack.push(popType(Num, stack) & popType(Num, stack))
      when 0x39 then stack.push(popType(Num, stack) | popType(Num, stack))
      when 0x3a then stack.push(popType(Num, stack) ^ popType(Num, stack))

      # SECTION: IO Operations
      when 0x40 then stack.push(STDIN.raw &.read_char.try(&.ord))
      when 0x41 then stack.push(STDIN.read_line)
      when 0x42 then print popType(Num, stack).chr
      when 0x43 then print popType(String, stack)

      # TODO: Variable Operations
      # TODO: Control Flow
      # TODO: Type Queries
      end

      puts "0x#{op.opcd.to_s(16).rjust(2,'0')} #{stack}"
      insp += 1
    end

    return stack
  end

  private macro popType(typ, stack)
    (v = {{stack}}.pop).as?({{typ}}) || 
      raise "Type error: Expected #{{{typ}}}, got #{typeof(v)}"
  end
  
  # SECTION: Tests
  # TODO: Move to proper spec definition

  private def self.test(desc : String, expected : Array(Any), *bc : Byte) 
    test(desc, expected, bc.to_a) end
  private def self.test(desc : String, expected : Array(Any), bc : Array(Byte))
    result = runBytecode(bc)
    raise "  Test failed: #{desc}\n  Resulting stack: #{result}\n  Expected stack: #{expected}" unless result == expected
    puts  "  Test succeeded: #{desc}"
  end

  def self.runTests
    puts "SECTION: Literals"
    test "0x00 null", [nil],                    0x00
    test "0x01 byte", [0_u8],                   0x01, 0x00
    test "0x02 bool", [false],                  0x02, 0x00
    test "0x03 i32",  [0x0f0f0f0f_i32],         0x03, 0x0f, 0x0f, 0x0f, 0x0f
    test "0x04 i64",  [0x0f0f0f0f0f0f0f0f_i64], 0x04, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f
    test "0x05 u32",  [0x0f0f0f0f_u32],         0x05, 0x0f, 0x0f, 0x0f, 0x0f
    test "0x06 u64",  [0x0f0f0f0f0f0f0f0f_u64], 0x06, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f
    test "0x07 str",  ["Hello, world!"],        [0x07, 0x00, 0x00, 0x00, 13].map(&.to_u8) + "Hello, world!".bytes
    puts

    puts "SECTION: Constructors"
    test "0x10 list", [[true, false]], 0x02, 0, 0x02, 1, 0x01, 2, 0x10
    puts

    puts "SECTION: Stack Operations"
    test "0x20 drop", [] of Any,     0x00, 0x20
    test "0x21 dupe", [nil, nil],    0x00, 0x21
    test "0x22 swap", [true, false], 0x02, 0, 0x02, 1, 0x22
    puts
    
    puts "SECTION: Arithmetic Operations"
    test "0x30 add", [5], 0x01, 2, 0x01, 3, 0x30
    test "0x31 sub", [1], 0x01, 3, 0x01, 2, 0x31
    test "0x32 mul", [6], 0x01, 2, 0x01, 3, 0x32
    test "0x33 div", [2], 0x01, 4, 0x01, 2, 0x33
    test "0x34 mod", [1], 0x01, 5, 0x01, 2, 0x34
    test "0x35 shl", [0b10010000], 0x01, 0b00100100, 0x01, 2, 0x35
    test "0x36 shr", [0b00001001], 0x01, 0b00100100, 0x01, 2, 0x36
    test "0x37 not", [0b11011011], 0x01, 0b00100100, 0x37
    test "0x38 and", [0b00100000], 0x01, 0b00100100, 0x01, 0b11111011, 0x38
    test "0x39 or ", [0b10110100], 0x01, 0b00100100, 0x01, 0b10010000, 0x39
    test "0x3a xor", [0b10110000], 0x01, 0b00100100, 0x01, 0b10010100, 0x3a
    puts

    puts "SECTION: IO Operations"
    puts "(Please input: 'a')"
    test "0x40 getc", ['a'.ord], 0x40
    puts "(Please input: 'abc<ENTER>')"
    test "0x41 getl", ["abc"],   0x41
    test "0x42 putc", [] of Any, 0x01, 97, 0x42
    test "0x43 putl", [] of Any, [0x07, 0x00, 0x00, 0x00, 14].map(&.to_u8) + "Hello, world!\n".bytes + [0x43_u8]
    puts

    # TODO: Variable Operations
    # TODO: Control Flow
    # TODO: Type Queries
  end
end

# Sherwood.runBytecode File.open(ARGV[0])
Sherwood.runTests