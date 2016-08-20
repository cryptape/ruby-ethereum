# -*- encoding : ascii-8bit -*-

require 'test_helper'

class ABIFixtureTest < Minitest::Test
  include Ethereum::ABI
  include Ethereum::Utils

  run_fixtures "ABITests"

  def on_fixture_test(name, data)
    run_abi_test data, :verify
  end

  def run_abi_test(params, mode)
    types, args = params['types'], params['args']
    outputs = encode types, args

    assert_equal args, decode(types, outputs)

    case mode
    when :fill
      params['result'] = encode_hex(outputs)
    when :verify
      assert_equal params['result'], encode_hex(outputs)
    when :time
      t1 = Time.now
      encode types, args
      t2 = Time.now
      decode types, outputs
      {encoding: t2-t1, decoding: Time.now-t2}
    else
      raise "invalid mode: #{mode}"
    end
  end
end

class ABITest < Minitest::Test
  include Ethereum::ABI
  include Ethereum::Utils
  ABI = Ethereum::ABI
  Constant = Ethereum::Constant

  def test_use_abi_class_methods
    assert_equal encode(['int256'], [1]), ABI.encode(['int256'], [1])
  end

  def test_abi_encode_var_sized_array
    bytes = "\x00" * 32 * 3
    assert_equal "#{zpad_int(32)}#{zpad_int(3)}#{bytes}", encode(['address[]'], [["\x00" * 20]*3])
  end

  def test_abi_encode_fixed_sized_array
    assert_equal "#{zpad_int(5)}#{zpad_int(6)}", encode(['uint16[2]'], [[5,6]])
  end

  def test_abi_encode_signed_int
    assert_equal 1,  decode(['int8'], encode(['int8'], [1]))[0]
    assert_equal -1, decode(['int8'], encode(['int8'], [-1]))[0]
  end

  def test_abi_encode_primitive_type
    type = Type.parse 'bool'
    assert_equal zpad_int(1), encode_primitive_type(type, true)
    assert_equal zpad_int(0), encode_primitive_type(type, false)

    type = Type.parse 'uint8'
    assert_equal zpad_int(255), encode_primitive_type(type, 255)
    assert_raises(ValueOutOfBounds) { encode_primitive_type(type, 256) }

    type = Type.parse 'int8'
    assert_equal zpad("\x80", 32), encode_primitive_type(type, -128)
    assert_equal zpad("\x7f", 32), encode_primitive_type(type, 127)
    assert_raises(ValueOutOfBounds) { encode_primitive_type(type, -129) }
    assert_raises(ValueOutOfBounds) { encode_primitive_type(type, 128) }

    type = Type.parse 'ufixed128x128'
    assert_equal ("\x00"*32), encode_primitive_type(type, 0)
    assert_equal ("\x00"*15 + "\x01\x20" + "\x00"*15), encode_primitive_type(type, 1.125)
    assert_equal ("\x7f" + "\xff"*15 + "\x00"*16), encode_primitive_type(type, 2**127-1)

    type = Type.parse 'fixed128x128'
    assert_equal ("\xff"*16 + "\x00"*16), encode_primitive_type(type, -1)
    assert_equal ("\x80" + "\x00"*31), encode_primitive_type(type, -2**127)
    assert_equal ("\x7f" + "\xff"*15 + "\x00"*16), encode_primitive_type(type, 2**127-1)
    assert_equal "#{zpad_int(1, 16)}\x20#{"\x00"*15}", encode_primitive_type(type, 1.125)
    assert_equal "#{"\xff"*15}\xfe\xe0#{"\x00"*15}", encode_primitive_type(type, -1.125)
    assert_raises(ValueOutOfBounds) { encode_primitive_type(type, -2**127 - 1) }
    assert_raises(ValueOutOfBounds) { encode_primitive_type(type, 2**127) }

    type = Type.parse 'bytes'
    assert_equal "#{zpad_int(3)}\x01\x02\x03#{"\x00"*29}", encode_primitive_type(type, "\x01\x02\x03")

    type = Type.parse 'bytes8'
    assert_equal "\x01\x02\x03#{"\x00"*29}", encode_primitive_type(type, "\x01\x02\x03")

    type = Type.parse 'hash32'
    assert_equal ("\xff"*32), encode_primitive_type(type, "\xff"*32)
    assert_equal ("\xff"*32), encode_primitive_type(type, "ff"*32)

    type = Type.parse 'address'
    assert_equal zpad("\xff"*20, 32), encode_primitive_type(type, "\xff"*20)
    assert_equal zpad("\xff"*20, 32), encode_primitive_type(type, "ff"*20)
    assert_equal zpad("\xff"*20, 32), encode_primitive_type(type, "0x"+"ff"*20)
  end

  def test_abi_decode_primitive_type
    type = Type.parse 'address'
    assert_equal 'ff'*20, decode_primitive_type(type, encode_primitive_type(type, "0x"+"ff"*20))

    type = Type.parse 'bytes'
    assert_equal "\x01\x02\x03", decode_primitive_type(type, encode_primitive_type(type, "\x01\x02\x03"))

    type = Type.parse 'bytes8'
    assert_equal ("\x01\x02\x03"+"\x00"*5), decode_primitive_type(type, encode_primitive_type(type, "\x01\x02\x03"))

    type = Type.parse 'hash20'
    assert_equal ("\xff"*20), decode_primitive_type(type, encode_primitive_type(type, "ff"*20))

    type = Type.parse 'uint8'
    assert_equal 0, decode_primitive_type(type, encode_primitive_type(type, 0))
    assert_equal 255, decode_primitive_type(type, encode_primitive_type(type, 255))

    type = Type.parse 'int8'
    assert_equal -128, decode_primitive_type(type, encode_primitive_type(type, -128))
    assert_equal 127, decode_primitive_type(type, encode_primitive_type(type, 127))

    type = Type.parse 'ufixed128x128'
    assert_equal 0, decode_primitive_type(type, encode_primitive_type(type, 0))
    assert_equal 125.125, decode_primitive_type(type, encode_primitive_type(type, 125.125))
    assert_equal (2**128-1).to_f, decode_primitive_type(type, encode_primitive_type(type, 2**128-1))

    type = Type.parse 'fixed128x128'
    assert_equal 1, decode_primitive_type(type, encode_primitive_type(type, 1))
    assert_equal -1, decode_primitive_type(type, encode_primitive_type(type, -1))
    assert_equal 125.125, decode_primitive_type(type, encode_primitive_type(type, 125.125))
    assert_equal -125.125, decode_primitive_type(type, encode_primitive_type(type, -125.125))
    assert_equal (2**127-1).to_f, decode_primitive_type(type, encode_primitive_type(type, 2**127-1))
    assert_equal -2**127, decode_primitive_type(type, encode_primitive_type(type, -2**127))

    type = Type.parse 'bool'
    assert_equal true, decode_primitive_type(type, encode_primitive_type(type, true))
    assert_equal false, decode_primitive_type(type, encode_primitive_type(type, false))
  end

  def test_get_int_and_uint
    assert_equal 1, ABI.send(:get_int, true)
    assert_equal 0, ABI.send(:get_int, false)
    assert_equal 0, ABI.send(:get_int, nil)

    assert_equal Constant::UINT_MAX, ABI.send(:get_uint, Constant::UINT_MAX)
    assert_equal Constant::UINT_MAX, ABI.send(:get_uint, int_to_big_endian(Constant::UINT_MAX))

    assert_raises(EncodingError) { ABI.send(:get_uint, Constant::UINT_MAX + 1) }
    assert_raises(EncodingError) { ABI.send(:get_uint, int_to_big_endian(Constant::UINT_MAX + 1)) }

    assert_equal Constant::UINT_MIN, ABI.send(:get_uint, Constant::UINT_MIN)
    assert_equal Constant::UINT_MIN, ABI.send(:get_uint, int_to_big_endian(Constant::UINT_MIN))

    assert_raises(EncodingError) { ABI.send(:get_uint, Constant::UINT_MIN - 1) }
    assert_raises(RLP::Error::SerializationError) { ABI.send(:get_uint, int_to_big_endian(Constant::UINT_MIN - 1)) } # int_to_big_endian fails

    assert_equal Constant::INT_MAX, ABI.send(:get_int, Constant::INT_MAX)
    assert_equal Constant::INT_MAX, ABI.send(:get_int, int_to_big_endian(Constant::INT_MAX))

    assert_raises(EncodingError) { ABI.send(:get_int, Constant::INT_MAX + 1) }
    #assert_raises(EncodingError) { ABI.send(:get_int, int_to_big_endian(Constant::INT_MAX + 1)) }

    assert_equal Constant::INT_MIN, ABI.send(:get_int, Constant::INT_MIN)
    assert_raises(EncodingError) { ABI.send(:get_int, Constant::INT_MIN - 1) }
  end

  def test_encode_int
    int8 = Type.parse 'int8'
    int32 = Type.parse 'int32'
    int256 = Type.parse 'int256'

    int256_maximum = "\x7f\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"
    int256_minimum = "\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    int256_128 = "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x80"
    int256_2_to_31 = "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x80\x00\x00\x00"
    int256_negative_one = "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"

    assert_equal int256_minimum, ABI.encode_primitive_type(int256, int256_minimum)

    assert_equal zpad("\x00", 32), encode_primitive_type(int8, 0)
    assert_equal zpad("\x7f", 32), encode_primitive_type(int8, 2**7 - 1)
    assert_equal zpad("\xff", 32), encode_primitive_type(int8, -1)
    assert_equal zpad("\x80", 32), encode_primitive_type(int8, -2 ** 7)

    assert_raises(ValueOutOfBounds) { encode_primitive_type(int8, 128) }
    assert_raises(ValueOutOfBounds) { encode_primitive_type(int8, -129) }

    assert_equal zpad("\x00", 32), encode_primitive_type(int32, 0)
    assert_equal zpad("\x7f", 32), encode_primitive_type(int32, 2**7 - 1)
    assert_equal zpad("\x7f\xff\xff\xff", 32), encode_primitive_type(int32, 2**31 - 1)
    assert_equal zpad("\xff\xff\xff\xff", 32), encode_primitive_type(int32, -1)
    assert_equal zpad("\xff\xff\xff\x80", 32), encode_primitive_type(int32, -2 ** 7)
    assert_equal zpad("\x80\x00\x00\x00", 32), encode_primitive_type(int32, -2 ** 31)

    assert_raises(ValueOutOfBounds) { encode_primitive_type(int32, 2**32) }
    assert_raises(ValueOutOfBounds) { encode_primitive_type(int32, -2**32) }

    assert_equal zpad("\x00", 32), encode_primitive_type(int256, 0)
    assert_equal zpad("\x7f", 32), encode_primitive_type(int256, 2**7 - 1)
    assert_equal zpad("\x7f\xff\xff\xff", 32), encode_primitive_type(int256, 2**31 - 1)
    assert_equal int256_maximum, encode_primitive_type(int256, 2**255 - 1)
    assert_equal int256_negative_one, encode_primitive_type(int256, -1)
    assert_equal int256_128, encode_primitive_type(int256, -2 ** 7)
    assert_equal int256_2_to_31, encode_primitive_type(int256, -2 ** 31)
    assert_equal int256_minimum, encode_primitive_type(int256, -2 ** 255)

    assert_raises(ValueOutOfBounds) { encode_primitive_type(int256, 2**256) }
    assert_raises(ValueOutOfBounds) { encode_primitive_type(int256, -2**256) }
  end

  def test_encode_uint
    uint8 = Type.parse 'uint8'
    uint32 = Type.parse 'uint32'
    uint256 = Type.parse 'uint256'

    assert_raises(ValueOutOfBounds) { encode_primitive_type(uint8, -1) }
    assert_raises(ValueOutOfBounds) { encode_primitive_type(uint32, -1) }
    assert_raises(ValueOutOfBounds) { encode_primitive_type(uint256, -1) }

    assert_equal zpad("\x00", 32), encode_primitive_type(uint8, 0)
    assert_equal zpad("\x00", 32), encode_primitive_type(uint32, 0)
    assert_equal zpad("\x00", 32), encode_primitive_type(uint256, 0)

    assert_equal zpad("\x01", 32), encode_primitive_type(uint8, 1)
    assert_equal zpad("\x01", 32), encode_primitive_type(uint32, 1)
    assert_equal zpad("\x01", 32), encode_primitive_type(uint256, 1)

    assert_equal zpad("\xff", 32), encode_primitive_type(uint8, 2**8 - 1)
    assert_equal zpad("\xff", 32), encode_primitive_type(uint32, 2**8 - 1)
    assert_equal zpad("\xff", 32), encode_primitive_type(uint256, 2**8 - 1)

    assert_equal zpad("\xff\xff\xff\xff", 32), encode_primitive_type(uint32, 2**32 - 1)
    assert_equal zpad("\xff\xff\xff\xff", 32), encode_primitive_type(uint256, 2**32 - 1)

    uint256_maximum = "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"
    assert_equal uint256_maximum, encode_primitive_type(uint256, Constant::UINT_MAX)
  end

  def test_encode_bool
    bool = Type.parse 'bool'
    uint8 = Type.parse 'uint8'

    assert_equal zpad("\x01", 32), encode_primitive_type(bool, true)
    assert_equal zpad("\x00", 32), encode_primitive_type(bool, false)

    assert_equal encode_primitive_type(uint8, 1), encode_primitive_type(bool, true)
    assert_equal encode_primitive_type(uint8, 0), encode_primitive_type(bool, false)
  end

  def test_encode_fixed
    fixed128x128 = Type.parse 'fixed128x128'

    _2_125 = decode_hex '0000000000000000000000000000000220000000000000000000000000000000'
    _8_5 = decode_hex '0000000000000000000000000000000880000000000000000000000000000000'

    assert_equal _2_125, encode_primitive_type(fixed128x128, 2.125)
    assert_equal _8_5, encode_primitive_type(fixed128x128, 8.5)

    assert_equal "\x00"*15 + "\x01\x20" + "\x00"*15, encode_primitive_type(fixed128x128, 1.125)
    assert_equal "\xff"*15 + "\xfe\xe0" + "\x00"*15, encode_primitive_type(fixed128x128, -1.125)

    assert_raises(ValueOutOfBounds) { encode_primitive_type(fixed128x128, 2**127) }
    assert_raises(ValueOutOfBounds) { encode_primitive_type(fixed128x128, -2**127-1) }
  end

  def test_encode_ufixed
    ufixed128x128 = Type.parse 'ufixed128x128'

    _2_125 = decode_hex '0000000000000000000000000000000220000000000000000000000000000000'
    _8_5 = decode_hex '0000000000000000000000000000000880000000000000000000000000000000'

    assert_equal _2_125, encode_primitive_type(ufixed128x128, 2.125)
    assert_equal _8_5, encode_primitive_type(ufixed128x128, 8.5)

    assert_equal "\x00"*32, encode_primitive_type(ufixed128x128, 0)
    assert_equal "\x00"*15 + "\x01\x20" + "\x00"*15, encode_primitive_type(ufixed128x128, 1.125)
    assert_equal "\x7f" + "\xff"*15 + "\x00"*16, encode_primitive_type(ufixed128x128, 2**127-1)

    assert_raises(ValueOutOfBounds) { encode_primitive_type(ufixed128x128, 2**128) }
    assert_raises(ValueOutOfBounds) { encode_primitive_type(ufixed128x128, -1) }
  end

  def test_encode_dynamic_bytes
    dynamic_bytes = Type.parse 'bytes'
    uint256 = Type.parse 'uint256'

    assert_equal zpad("\x00", 32), encode_primitive_type(dynamic_bytes, '')

    a = encode_primitive_type(uint256, 1) + rpad("\x61", "\x00", 32)
    assert_equal a, encode_primitive_type(dynamic_bytes, "\x61")

    dave_bin = decode_hex '00000000000000000000000000000000000000000000000000000000000000046461766500000000000000000000000000000000000000000000000000000000'
    dave = encode_primitive_type(uint256, 4) + rpad("\x64\x61\x76\x65", "\x00", 32)
    assert_equal dave_bin, encode_primitive_type(dynamic_bytes, "\x64\x61\x76\x65")
    assert_equal dave, encode_primitive_type(dynamic_bytes, "\x64\x61\x76\x65")
  end

  def test_encode_dynamic_string
    string = Type.parse 'string'
    uint256 = Type.parse 'uint256'

    a = 'ã'.force_encoding('UTF-8')
    a_utf8 = a.b

    assert_raises(Ethereum::ValueError) { encode_primitive_type(string, a.codepoints.pack('C*')) }

    a_encoded = encode_primitive_type(uint256, a_utf8.size) + rpad(a_utf8, Constant::BYTE_ZERO, 32)
    assert_equal a_encoded, encode_primitive_type(string, a.b)
  end

  def test_encode_hash
    hash8 = Type.parse 'hash8'
    assert_equal "\x00"*32, encode_primitive_type(hash8, "\x00"*8)
    assert_equal "\x00"*32, encode_primitive_type(hash8, "00"*8)
  end

  def test_encode_address
    address = Type.parse 'address'
    prefixed_address = "0x#{'0' * 40}"
    assert_equal "\x00"*32, encode_primitive_type(address, prefixed_address)
  end

  def test_encode_decode_int
    int8 = Type.parse('int8')
    int32 = Type.parse('int32')
    int256 = Type.parse('int256')

    int8_values = [1, -1, 127, -128]
    int32_values = [1, -1, 127, -128, 2**31 - 1, -2**31]
    int256_values = [1, -1, 127, -128, 2**31 - 1, -2**31, 2**255 - 1, -2**255]

    int8_values.each do |v|
      assert_equal encode_primitive_type(int8, v), ABI.encode_abi(['int8'], [v])
      assert_equal v, ABI.decode_abi(['int8'], ABI.encode_abi(['int8'], [v]))[0]
    end

    int32_values.each do |v|
      assert_equal encode_primitive_type(int32, v), ABI.encode_abi(['int32'], [v])
      assert_equal v, ABI.decode_abi(['int32'], ABI.encode_abi(['int32'], [v]))[0]
    end

    int256_values.each do |v|
      assert_equal encode_primitive_type(int256, v), ABI.encode_abi(['int256'], [v])
      assert_equal v, ABI.decode_abi(['int256'], ABI.encode_abi(['int256'], [v]))[0]
    end
  end

  def test_encode_decode_bool
    assert_equal true, ABI.decode_abi(['bool'], ABI.encode_abi(['bool'], [true]))[0]
    assert_equal false, ABI.decode_abi(['bool'], ABI.encode_abi(['bool'], [false]))[0]
  end

  def test_encode_decode_fixed
    fixed128x128 = Type.parse 'fixed128x128'

    fixed_data = encode_primitive_type fixed128x128, 1
    assert_equal 1, decode_primitive_type(fixed128x128, fixed_data)

    fixed_data = encode_primitive_type fixed128x128, 2**127 - 1
    assert_equal (2**127 - 1).to_f, decode_primitive_type(fixed128x128, fixed_data)

    fixed_data = encode_primitive_type fixed128x128, -1
    assert_equal -1, decode_primitive_type(fixed128x128, fixed_data)

    fixed_data = encode_primitive_type(fixed128x128, -2**127)
    assert_equal -2**127, decode_primitive_type(fixed128x128, fixed_data)
  end

  def test_encode_decode_bytes
    bytes8 = Type.parse 'bytes8'
    dynamic_bytes = Type.parse 'bytes'

    assert_equal "\x01\x02" + "\x00"*6, decode_primitive_type(bytes8, encode_primitive_type(bytes8, "\x01\x02"))
    assert_equal "\x01\x02", decode_primitive_type(dynamic_bytes, encode_primitive_type(dynamic_bytes, "\x01\x02"))
  end

  def test_encode_decode_hash
    hash8 = Type.parse 'hash8'

    hash1 = "\x01" * 8
    assert_equal hash1, decode_primitive_type(hash8, encode_primitive_type(hash8, hash1))
  end

  def test_encode_decode_address
    addr1 = "\x11" * 20
    addr2 = "\x22" * 20
    addr3 = "\x33" * 20

    all_addresses = [addr1, addr2, addr3]
    all_addresses_encoded = all_addresses.map {|addr| encode_hex(addr) }

    assert_equal encode_hex(addr1), ABI.decode_abi(['address'], ABI.encode_abi(['address'], [addr1]))[0]

    addresses_encoded_together = ABI.encode_abi ['address[]'], [all_addresses]
    assert_equal all_addresses_encoded, ABI.decode_abi(['address[]'], addresses_encoded_together)[0]

    address_abi = ['address', 'address', 'address']
    addresses_encoded_splited = ABI.encode_abi address_abi, all_addresses
    assert_equal all_addresses_encoded, ABI.decode_abi(address_abi, addresses_encoded_splited)
  end

end
