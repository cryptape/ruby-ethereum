# -*- encoding : ascii-8bit -*-

require 'test_helper'

class TesterTest < Minitest::Test
  include Ethereum

  def setup
    @s = Tester::State.new
  end

  def test_abi_contract_infterface
    contract_path = File.join CONTRACTS_DIR, 'simple_contract.sol'
    compiler = Tester::Language.get :solidity

    simple_compiled = compiler.compile_file contract_path
    simple_address = @s.evm simple_compiled['Simple']['bin']

    abi_json = JSON.dump simple_compiled['Simple']['abi']
    abi = Tester::ABIContract.new @s, abi_json, simple_address, listen: false, log_listener: nil, default_key: nil
  end
end
