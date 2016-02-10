require 'test_helper'

class TrieFixtureTest < Minitest::Test
  include Ethereum

  run_fixture "TrieTests/trietest.json"

  N_PERMUTATIONS = 1000

  def on_fixture_test(name, pairs)
    inserts = pairs['in'].map {|(k,v)| [decode_hex(k), decode_hex(v)]}
    deletes = inserts.select {|(k,v)| v.nil? }

    inserts.permutation.take(N_PERMUTATIONS).each do |perm|
      t = Trie.new DB::EphemDB.new

      perm.each {|(k,v)| v ? t.set(k, v) : t.delete(k) }
      deletes.each {|(k,v)| t.delete(k) } # make sure we delete at the end

      root = ('0x' + encode_hex(t.root_hash)).b
      raise "Mismatch: #{name} #{pairs['root']} != #{root} permutation: #{perm+deletes}" if pairs['root'] != root
    end
  end
end

class TrieTest < Minitest::Test
  include Ethereum

  def setup
    @trie = Trie.new DB::EphemDB.new
  end

  def test_encode_node_on_node_rlp_size_less_than_32
    node = [" \x98vH\x13\xb16\xdd\xf5\xa7T\xf3@c\xfd\x03\x06^6".b, "something"]
    assert_equal node, @trie.send(:encode_node, node)
  end
end
