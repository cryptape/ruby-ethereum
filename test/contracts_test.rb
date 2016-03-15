# -*- encoding : ascii-8bit -*-

require 'test_helper'
require 'serpent'

class ContractsTest < Minitest::Test
  include Ethereum

TEST_EVM_CODE = <<EOF
def main(a,b):
  return (a ^ b)
EOF
def test_evm
  evm_code = Serpent.compile(TEST_EVM_CODE)
  translator = ABI::ContractTranslator.new Serpent.mk_full_signature(TEST_EVM_CODE)

  data = translator.encode 'main', [2, 5]
  s = Tester::State.new
  c = s.evm evm_code
  o = translator.decode('main', s.send_tx(Tester::Fixture.keys[0], c, 0, evmdata: data))
  assert_equal [32], o
end

TEST_SIXTEN_CODE = <<EOF
(with 'x 10
  (with 'y 20
    (with 'z 30
      (seq
        (set 'a (add (mul (get 'y) (get 'z)) (get 'x)))
        (return (ref 'a) 32)
      )
    )
  )
)
EOF
def test_sixten
  s = Tester::State.new
  c = Utils.decode_hex '1231231231231234564564564564561231231231'
  s.block.set_code c, Serpent.compile_lll(TEST_SIXTEN_CODE)
  o = s.send_tx(Tester::Fixture.keys[0], c, 0)
  assert_equal 610, Utils.big_endian_to_int(o)
end

TEST_WITH_CODE = <<EOF
def f1():
    o = array(4)
    with x = 5:
        o[0] = x
        with y = 7:
            o[1] = y
            with x = 8:
                o[2] = x
        o[3] = x
    return(o:arr)


def f2():
    with x = 5:
        with y = 7:
            x = 2
        return(x)

def f3():
    with x = 5:
        with y = seq(x = 7, 2):
            return(x)

def f4():
    o = array(4)
    with x = 5:
        o[0] = x
        with y = 7:
            o[1] = y
            with x = x:
                o[2] = x
                with y = x:
                    o[3] = y
    return(o:arr)
EOF
def test_with
  s = Tester::State.new
  c = s.abi_contract TEST_WITH_CODE
  assert_equal [5,7,8,5], c.f1
  assert_equal 2, c.f2
  assert_equal 7, c.f3
  assert_equal [5, 7, 5, 5], c.f4
end

end

