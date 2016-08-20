# -*- encoding : ascii-8bit -*-

require 'test_helper'

class ABIContractTranslatorTest < Minitest::Test
  include Ethereum::ABI
  ABI = Ethereum::ABI
  Utils = Ethereum::Utils

  JSON_ABI = '[{"constant":false,"inputs":[{"name":"a","type":"uint256"},{"name":"b","type":"uint256"}],"name":"foo","outputs":[{"name":"","type":"int256"}],"type":"function"},{"constant":false,"inputs":[{"name":"account","type":"address"},{"name":"amount","type":"uint256"}],"name":"issue","outputs":[],"type":"function"},{"constant":false,"inputs":[{"name":"to","type":"address"},{"name":"amount","type":"uint256"}],"name":"transfer","outputs":[],"type":"function"},{"constant":true,"inputs":[{"name":"account","type":"address"}],"name":"getBalance","outputs":[{"name":"","type":"uint256"}],"type":"function"},{"inputs":[],"type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"name":"account","type":"address"},{"indexed":false,"name":"amount","type":"uint256"}],"name":"Issue","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"from","type":"address"},{"indexed":false,"name":"to","type":"address"},{"indexed":false,"name":"amount","type":"uint256"}],"name":"Transfer","type":"event"}]'

  def test_parse_json_abi
    t = ContractTranslator.new JSON_ABI

    foo = t.function('foo')
    assert_equal 79450872, foo[:prefix]
    assert_equal false, foo[:is_constant]
    assert_equal %w(uint256 uint256), foo[:encode_types]
    assert_equal %w(int256), foo[:decode_types]
    assert_equal [%w(uint256 a), %w(uint256 b)], foo[:signature]

    issue = t.event('Issue', %w(address uint))
    assert_equal 'Issue', issue[:name]
    assert_equal %w(account amount), issue[:names]
    assert_equal %w(address uint256), issue[:types]
    assert_equal [false, false], issue[:indexed]
  end

  def test_canonical_types
    t = ContractTranslator.new '[]'

    assert_equal 'bool', t.send(:canonical_type, 'bool')
    assert_equal 'address', t.send(:canonical_type, 'address')

    assert_equal 'int256', t.send(:canonical_type, 'int')
    assert_equal 'uint256', t.send(:canonical_type, 'uint')
    assert_equal 'fixed128x128', t.send(:canonical_type, 'fixed')
    assert_equal 'ufixed128x128', t.send(:canonical_type, 'ufixed')

    assert_equal 'int256[]', t.send(:canonical_type, 'int[]')
    assert_equal 'uint256[]', t.send(:canonical_type, 'uint[]')
    assert_equal 'fixed128x128[]', t.send(:canonical_type, 'fixed[]')
    assert_equal 'ufixed128x128[]', t.send(:canonical_type, 'ufixed[]')

    assert_equal 'int256[100]', t.send(:canonical_type, 'int[100]')
    assert_equal 'uint256[100]', t.send(:canonical_type, 'uint[100]')
    assert_equal 'fixed128x128[100]', t.send(:canonical_type, 'fixed[100]')
    assert_equal 'ufixed128x128[100]', t.send(:canonical_type, 'ufixed[100]')
  end

  def test_function_selector
    baz_selector = Utils.decode_hex('CDCD77C0')
    bar_selector = Utils.decode_hex('AB55044D')
    sam_selector = Utils.decode_hex('A5643BF2')
    f_selector = Utils.decode_hex('8BE65246')

    assert_equal baz_selector, Utils.keccak256('baz(uint32,bool)')[0,4]
    assert_equal bar_selector, Utils.keccak256('bar(fixed128x128[2])')[0,4]
    assert_equal sam_selector, Utils.keccak256('sam(bytes,bool,uint256[])')[0,4]
    assert_equal f_selector, Utils.keccak256('f(uint256,uint32[],bytes10,bytes)')[0,4]

    t = ContractTranslator.new '[]'

    assert_equal Utils.big_endian_to_int(baz_selector), t.method_id('baz', %w(uint32 bool))
    assert_equal Utils.big_endian_to_int(bar_selector), t.method_id('bar', %w(fixed128x128[2]))
    assert_equal Utils.big_endian_to_int(sam_selector), t.method_id('sam', %w(bytes bool uint256[]))
    assert_equal Utils.big_endian_to_int(f_selector), t.method_id('f', %w(uint256 uint32[] bytes10 bytes))

    assert_equal Utils.big_endian_to_int(bar_selector), t.method_id('bar', %w(fixed[2]))
    assert_equal Utils.big_endian_to_int(sam_selector), t.method_id('sam', %w(bytes bool uint[]))
    assert_equal Utils.big_endian_to_int(f_selector), t.method_id('f', %w(uint uint32[] bytes10 bytes))
  end

  def test_event
    event_abi = [{
      'name' => 'Test',
      'anonymous' => false,
      'inputs' => [
        {'indexed' => false, 'name' => 'a', 'type' => 'int256'},
        {'indexed' => false, 'name' => 'b', 'type' => 'int256'}
      ],
      'type' => 'event'
    }]

    contract_abi = ContractTranslator.new event_abi

    normalized_name = contract_abi.send :basename, 'Test'
    encode_types = %w(int256 int256)
    id = contract_abi.event_id normalized_name, encode_types

    topics = [id]
    data = ABI.encode_abi encode_types, [1, 2]

    result = contract_abi.decode_event topics, data
    assert_equal 'Test', result['_event_type']
    assert_equal 1, result['a']
    assert_equal 2, result['b']
  end

end
