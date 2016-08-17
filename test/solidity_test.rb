# -*- encoding : ascii-8bit -*-

require 'test_helper'

class SolidityTest < Minitest::Test
  include Ethereum

  def setup
    @s = Tester::State.new
  end

  def test_compile_from_file
    Dir.mktmpdir('contracts-') do |dir|
      lib_path = File.join dir, 'Other.sol'
      File.write lib_path, <<-EOF
          library Other {
              function seven() returns (int256 y) {
                  y = 7;
              }
          }
      EOF

      user_path = File.join dir, 'user.sol'
      File.write user_path, <<-EOF
          import "Other.sol";
          contract user {
              function test() returns (int256 seven) {
                  seven = Other.seven();
              }
          }
      EOF

      # library calls need CALLCODE opcode
      db = DB::EphemDB.new
      env = Env.new db, config: Env::DEFAULT_CONFIG.merge(homestead_fork_blknum: 0)
      @s = Tester::State.new env: env

      lib_contract = @s.abi_contract(nil, path: lib_path, language: :solidity)
      assert_equal 7, lib_contract.seven

      lib_user = @s.abi_contract nil, path: user_path, libraries: {'Other' => Utils.encode_hex(lib_contract.address) }, language: :solidity
      assert_equal 7, lib_user.test
    end
  end

  SERPENT_CONTRACT = <<-EOF
      extern solidity: [sub2:[]:i]

      def main(a):
          return(a.sub2() * 2)

      def sub1():
          return(5)
  EOF
  SOLIDITY_CONTRACT = <<-EOF
      contract serpent { function sub1() returns (int256 y) {} }

      contract zoo {
          function main(address a) returns (int256 y) {
              y = serpent(a).sub1() * 2;
          }
          function sub2() returns (int256 y) {
              y = 7;
          }
          function sub3(address a) returns (address b) {
              b = a;
          }
      }
  EOF
  def test_interop
    c1 = @s.abi_contract SERPENT_CONTRACT
    c2 = @s.abi_contract SOLIDITY_CONTRACT, language: :solidity
    assert_equal 5, c1.sub1
    assert_equal 7, c2.sub2
    assert_equal Utils.encode_hex(c2.address), c2.sub3(Utils.encode_hex(c2.address))
    assert_equal 14, c1.main(c2.address)
    assert_equal 10, c2.main(c1.address)
  end

  COMPILE_RICH_CONTRACT = <<-EOF
      contract contract_add {
          function add7(uint a) returns(uint d) { return a + 7; }
          function add42(uint a) returns(uint d) { return a + 42; }
      }
      contract contract_sub {
          function subtract7(uint a) returns(uint d) { return a - 7; }
          function subtract42(uint a) returns(uint d) { return a - 42; }
      }
  EOF
  def test_solidity_compile_rich
    skip "bytecode in test seems to be wrong"
    contract_info = Tester::Language.get(:solidity).compile_rich COMPILE_RICH_CONTRACT

    assert_equal 2, contract_info.size
    assert_equal %w(contract_add contract_sub), contract_info.keys
    assert_equal %w(code info), contract_info['contract_add'].keys
    assert_equal %w(abiDefinition compilerVersion developerDoc language languageVersion source userDoc), contract_info['contract_add']['info'].keys

    #assert_equal '', contract_info['contract_add']['code']
    #assert_equal '', contract_info['contract_sub']['code']

    assert_equal %w(add7 add42), contract_info['contract_add']['info']['abiDefinition'].map {|d| d['name'] }
    assert_equal %w(subtract7 subtract42), contract_info['contract_sub']['info']['abiDefinition'].map {|d| d['name'] }
  end

  CONSTRUCTOR_CONTRACT = <<-EOF
      contract testme {
          uint value;
          function testme(uint a) {
              value = a;
          }
          function getValue() returns (uint) {
              return value;
          }
      }
  EOF
  def test_constructor
    contract = @s.abi_contract(CONSTRUCTOR_CONTRACT, language: :solidity, constructor_parameters: [2])
    assert_equal 2, contract.getValue
  end

  def test_abi_contract
    one_contract = <<-EOF
        contract foo {
            function seven() returns (int256 y) {
                y = 7;
            }
            function mul2(int256 x) returns (int256 y) {
                y = x * 2;
            }
        }
    EOF

    two_contracts = one_contract + <<-EOF
        contract baz {
            function echo(address a) returns (address b) {
                b = a;
                return b;
            }
            function eight() returns (int256 y) {
                y = 8;
            }
        }
    EOF

    contract = @s.abi_contract one_contract, language: :solidity
    assert_equal 7, contract.seven
    assert_equal 4, contract.mul2(2)
    assert_equal -4, contract.mul2(-2)


  end

end
