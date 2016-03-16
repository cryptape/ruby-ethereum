# -*- encoding : ascii-8bit -*-

require 'test_helper'

class BloomTest < Minitest::Test
  include Ethereum

  def test_bloom_insert_and_query
    b = Bloom.from("\x01")
    assert_equal true, Bloom.query(b, "\x01")
    assert_equal false, Bloom.query(b, "\x00")
  end

  def test_bloom_bits
    assert_equal [[1323], [431], [1319]], Bloom.bits(Utils.decode_hex('0f572e5295c57f15886f9b263e2f6d2d6c7b5ec6'))
  end

  def test_bloom_from_array
    assert_equal 0, Bloom.from_array([])
  end

end

class BloomFixtureTest < Minitest::Test
  include Ethereum

  run_fixtures "VMTests"

  ##
  # The logs sections is a mapping between the blooms and their corresponding
  # log entries. Each log entry has the format:
  #
  # * address: the address of the log entry
  # * data: the data of the log entry
  # * topics: the topics of the log entry, given as an array of values
  #
  def on_fixture_test(name, testdata)
    test_logs = testdata['logs']
    if test_logs && name =~ /log/i
      test_logs.each do |data|
        address = Utils.decode_hex data['address']
        b = Bloom.from address
        data['topics'].each {|t| b = Bloom.insert(b, Utils.decode_hex(t)) }

        topics = data['topics'].map {|t| decode_int_from_hex(t) }
        log = Log.new address, topics, ''
        log_bloom = Bloom.b256 Bloom.from_array(log.bloomables)

        assert_equal Utils.encode_hex(log_bloom), encode_hex_from_int(b)
        assert_equal data['bloom'], Utils.encode_hex(log_bloom)
      end
    end
  end

  def encode_hex_from_int(x)
    Utils.encode_hex Utils.zpad(Utils.int_to_big_endian(x), 256)
  end

  def decode_int_from_hex(x)
    Utils.decode_int Utils.decode_hex(x).sub(/\A(\x00)+/, '')
  end

end
