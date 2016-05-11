# -*- encoding : ascii-8bit -*-

require 'test_helper'

class AppProfileTest < Minitest::Test
  include Ethereum

  def test_get_profile_by_name
    assert_equal 1, App::Profile[:livenet][:eth][:network_id]
  end

end
