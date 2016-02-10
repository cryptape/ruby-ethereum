require 'test_helper'

class TrieTest < Minitest::Test
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
