# -*- encoding : ascii-8bit -*-

require 'test_helper'

class ABIContractTranslatorTest < Minitest::Test
  include Ethereum::ABI

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

end
