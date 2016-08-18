# -*- encoding : ascii-8bit -*-

require 'test_helper'

class VMFixtureTest < Minitest::Test
  include Ethereum
  include VMTest

  run_fixtures "VMTests"

  def on_fixture_test(name, data)
    check_vm_test data
  end

end
