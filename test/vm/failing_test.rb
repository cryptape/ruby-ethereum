# -*- encoding : ascii-8bit -*-

require 'test_helper'

class VMFixtureFailingTest < Minitest::Test
  include Ethereum
  include VMTest

  Failing = %w(
    vmSystemOperationsTest_ABAcallsSuicide1
    vmSystemOperationsTest_ABAcallsSuicide0
    vmSystemOperationsTest_callcodeToReturn1
    vmEnvironmentalInfoTest_env1
    vmSystemOperationsTest_createNameRegistrator
    vmSystemOperationsTest_CallRecursiveBomb0
    vmSystemOperationsTest_CallToReturn1
    vmSystemOperationsTest_CallToPrecompiledContract
    vmSystemOperationsTest_CallToNameRegistrator0
    vmSystemOperationsTest_callcodeToNameRegistrator0
    vmSystemOperationsTest_ABAcalls0
  ).sort
  FailingRegex = /#{Failing.join('|')}/

  run_fixtures "VMTests", only: /vmSystemOperationsTest|vmEnvironmentalInfoTest/, options: {only: FailingRegex}

  def on_fixture_test(name, data)
    check_vm_test to_bytes(data)

    if name =~ /#{Failing[1]}/
      found = false
      data['post'].each_value do |address_data|
        storage = address_data['storage']
        next unless storage.include?('0x23')

        assert_equal '0x01', storage['0x23']
        storage['0x23'] = '0x02'
        found = true
        break
      end
      assert found, 'Did not find 0x23 in storage values'

      assert_raises(RuntimeError) { check_vm_test to_bytes(data) }
    end
  end

end
