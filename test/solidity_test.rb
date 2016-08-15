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

end
