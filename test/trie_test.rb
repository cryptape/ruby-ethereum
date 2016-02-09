require 'test_helper'

class TrieTest < Minitest::Test
  include Ethereum

  run_fixture "TrieTests/trietest.json"

  def on_fixture_test(name, pairs)
  end
end

