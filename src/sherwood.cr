require "./bytecode"
require "./util"

module Sherwood
  VERSION = "0.1.0"

  # Standard IO ports, abstracted out for ease of testing
  @@stdin  : IO = STDIN
  @@stdout : IO = STDOUT
  @@stderr : IO = STDERR
  def self.stdin= (@@stdin  : IO); end
  def self.stdout=(@@stdout : IO); end
  def self.stderr=(@@stderr : IO); end
  def self.stdin ; @@stdin  end
  def self.stdout; @@stdout end
  def self.stderr; @@stderr end

  # Type aliases for convenience
  alias SWAny = Nil | SWNum | Bool | String | Array(SWAny)
  alias SWNum = SWInt | SWFlt
  alias SWInt = Byte | Int32 | Int64 | UInt32 | UInt64
  alias SWFlt = Float32 | Float64

  # Runs a set of bytecode.
  def self.runBytecode(prog : IO)
    return self.runBytecode(prog.each_byte.to_a) end
  def self.runBytecode(*prog : Byte)
    return self.runBytecode(prog) end
  def self.runBytecode(prog : Array(Byte))
    return self.runBytecode(Bytecode.new(prog)) end
  def self.runBytecode(prog : Bytecode)
    insp  = 0
    stack = [] of SWAny

    while op = prog[insp]?; case op.opcd
      # SECTION: Literals
      when 0x00 then stack.push(nil)
      when 0x01 then stack.push(op.data[0])
      when 0x02 then stack.push(op.data[0] > 0)
      when 0x03 then stack.push(op.data.map(&.to_i32).bitwiseConcat)
      when 0x04 then stack.push(op.data.map(&.to_i64).bitwiseConcat)
      when 0x05 then stack.push(op.data.map(&.to_u32).bitwiseConcat)
      when 0x06 then stack.push(op.data.map(&.to_u64).bitwiseConcat)
      when 0x07 then stack.push(Float32.fromBytes(op.data))
      when 0x08 then stack.push(Float64.fromBytes(op.data))
      when 0x09 then stack.push(op.data.skip(4).map(&.chr).sum(""))

      # SECTION: Constructors
      when 0x10 then 
        (size = popType(SWInt, stack)) > 0 &&
          stack.push(Array(SWAny).new(size) { stack.pop }) ||
          stack.push([] of SWAny)

      # SECTION: Stack Operations
      when 0x20 then stack.pop()
      when 0x21 then stack.push(stack.last)
      when 0x22 then stack.push(stack.pop(), stack.pop())
        
      # SECTION: Arithmetic Operations
      when 0x30 then stack.push(popType(SWNum, stack) + popType(SWNum, stack))
      when 0x31 then stack.push((b = popType(SWNum, stack); popType(SWNum, stack)) - b)
      when 0x32 then stack.push(popType(SWNum, stack) * popType(SWNum, stack))
      when 0x33 then stack.push((b = popType(SWNum, stack); popType(SWNum, stack)) / b)
      when 0x34 then stack.push((b = popType(SWInt, stack); popType(SWInt, stack)) % b)
      when 0x35 then stack.push((b = popType(SWInt, stack); popType(SWInt, stack)) << b)
      when 0x36 then stack.push((b = popType(SWInt, stack); popType(SWInt, stack)) >> b)
      when 0x37 then stack.push(~popType(SWInt, stack))
      when 0x38 then stack.push(popType(SWInt, stack) & popType(SWInt, stack))
      when 0x39 then stack.push(popType(SWInt, stack) | popType(SWInt, stack))
      when 0x3a then stack.push(popType(SWInt, stack) ^ popType(SWInt, stack))

      # SECTION: IO Operations
      when 0x40 then
        if (csi = @@stdin).is_a?(IO::FileDescriptor) && csi.tty?
          stack.push(csi.raw &.read_char.try(&.ord))
        else
          stack.push(csi.read_char.try(&.ord))
        end
      when 0x41 then stack.push(@@stdin.gets)
      when 0x42 then @@stdout.print popType(SWInt, stack).chr
      when 0x43 then @@stdout.print popType(String, stack)
        
      # SECTION: Type Queries
      when 0x50 then stack.push(stack.last.nil?)
      when 0x51 then stack.push(stack.last.is_a?(Byte))
      when 0x52 then stack.push(stack.last.is_a?(Bool))
      when 0x53 then stack.push(stack.last.is_a?(Int32))
      when 0x54 then stack.push(stack.last.is_a?(Int64))
      when 0x55 then stack.push(stack.last.is_a?(UInt32))
      when 0x56 then stack.push(stack.last.is_a?(UInt64))
      when 0x57 then stack.push(stack.last.is_a?(Float32))
      when 0x58 then stack.push(stack.last.is_a?(Float64))
      when 0x59 then stack.push(stack.last.is_a?(String))

      when 0x60 then stack.push(stack.last.is_a?(Array))

      # TODO: Variable Operations
      # TODO: Control Flow
      end

      {% if flag?(:stack) %} puts "    0x#{op.opcd.to_s(16).rjust(2,'0')} #{stack}" {% end %}
      insp += 1
    end

    return stack
  end

  # Pops a value of the given type from the stack or throws a type error on failure.
  private macro popType(typ, stack)
    (v = {{stack}}.pop).as?({{typ}}) || 
      raise "Type error: Expected #{{{typ}}}, got #{v.class}"
  end
end

# Sherwood.runBytecode File.open(ARGV[0])
