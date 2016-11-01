# -*- encoding : ascii-8bit -*-

require 'test_helper'

class OpcodesTest < Minitest::Test
  include Ethereum

  def test_eip150_opcode_gascost
    # https://github.com/ethereum/eips/issues/150
    assert_equal 700, Opcodes::EXTCODESIZE[3] + Opcodes::EXTCODELOAD_SUPPLEMENTAL_GAS
    assert_equal 700, Opcodes::EXTCODECOPY[3] + Opcodes::EXTCODELOAD_SUPPLEMENTAL_GAS
    assert_equal 400, Opcodes::BALANCE[3] + Opcodes::BALANCE_SUPPLEMENTAL_GAS
    assert_equal 200, Opcodes::SLOAD[3] + Opcodes::SLOAD_SUPPLEMENTAL_GAS
    assert_equal 700, Opcodes::CALL[3] + Opcodes::CALL_SUPPLEMENTAL_GAS
    assert_equal 700, Opcodes::DELEGATECALL[3] + Opcodes::CALL_SUPPLEMENTAL_GAS
    assert_equal 700, Opcodes::CALLCODE[3] + Opcodes::CALL_SUPPLEMENTAL_GAS
    assert_equal 5000, Opcodes::SUICIDE[3] + Opcodes::SUICIDE_SUPPLEMENTAL_GAS
  end

end
