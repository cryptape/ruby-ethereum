# -*- encoding : ascii-8bit -*-

require 'test_helper'
require 'serpent'

TEST_EVM_CODE = <<EOF
def main(a,b):
  return (a ^ b)
EOF

class ContractsTest < Minitest::Test
  include Ethereum

  def test_evm
    evm_code = Serpent.compile(TEST_EVM_CODE)
    translator = ABI::ContractTranslator.new Serpent.mk_full_signature(TEST_EVM_CODE)

    data = translator.encode 'main', [2, 5]
    s = Tester::State.new
    c = s.evm evm_code
    o = translator.decode('main', s.send_tx(Tester::Fixture.keys[0], c, 0, evmdata: data))
    assert_equal [32], o
  end

end
