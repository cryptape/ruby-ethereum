# -*- encoding : ascii-8bit -*-

require 'test_helper'

class TransientTrieTest < Minitest::Test
  include Ethereum

  def setup
    db = Minitest::Mock.new
    @trie = TransientTrie.new(db)
  end

  def test_get_raise_exception
    assert_raises(TransientTrie::InvalidTransientTrieOperation) { @trie[''] }
  end

  def test_set_raise_exception
    assert_raises(TransientTrie::InvalidTransientTrieOperation) { @trie[''] = '' }
  end

  def test_delete_raise_exception
    assert_raises(TransientTrie::InvalidTransientTrieOperation) { @trie.delete('') }
  end

end
