require 'test_helper'

class TransientTrieTest < Minitest::Test
  include Ethereum

  def setup
    db = Minitest::Mock.new
    @trie = Trie.new(db, transient: true)
  end

  def test_get_raise_exception
    assert_raises(Trie::InvalidTransientTrieOperation) { @trie[''] }
  end

  def test_set_raise_exception
    assert_raises(Trie::InvalidTransientTrieOperation) { @trie[''] = '' }
  end

  def test_delete_raise_exception
    assert_raises(Trie::InvalidTransientTrieOperation) { @trie.delete('') }
  end

end
