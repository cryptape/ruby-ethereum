#!/usr/bin/env ruby
# -*- encoding : ascii-8bit -*-

$:.unshift File.expand_path('../../lib', __FILE__)

require 'json'
require 'serpent'

require 'ethereum'
require 'ethereum/serenity'

include Ethereum
VM = FastVM

MAX_NODES = 12

CLOCKWRONG = 0
CLOCKWRONG_CUMUL = CLOCKWRONG + 1

BRAVE = 0
BRAVE_CUMUL = CLOCKWRONG_CUMUL + BRAVE

CRAZYBET = 0
CRAZYBET_CUMUL = BRAVE_CUMUL + CRAZYBET

DBL_BLK_SUICIDE = 0
DBL_BLK_SUICIDE_CUMUL = CRAZYBET_CUMUL + DBL_BLK_SUICIDE

DBL_BET_SUICIDE = 0
DBL_BET_SUICIDE_CUMUL = DBL_BLK_SUICIDE_CUMUL + DBL_BET_SUICIDE

raise AssertError, "Negative Numbers or too many nodes with special properties" unless
  0 <= CLOCKWRONG_CUMUL && CLOCKWRONG_CUMUL <= BRAVE_CUMUL && BRAVE_CUMUL <= CRAZYBET_CUMUL &&
    CRAZYBET_CUMUL <= DBL_BLK_SUICIDE_CUMUL && DBL_BLK_SUICIDE_CUMUL <= DBL_BET_SUICIDE_CUMUL &&
    DBL_BET_SUICIDE_CUMUL <= MAX_NODES

puts "Running with #{MAX_NODES} maximum nodes: #{CLOCKWRONG} with wonky clocks, #{BRAVE} brave, #{CRAZYBET} crazy-betting, #{DBL_BLK_SUICIDE} double-block suiciding, #{DBL_BET_SUICIDE} double-bet suiciding"

genesis = State.new Trie::BLANK_NODE, DB::EphemDB.new
genesis.set_gas_limit 10**9
gc = genesis.clone

##
# Casper Contract Setup
#
casper_file = File.expand_path('../../lib/ethereum/casper.se.py', __FILE__)
casper_abi_file = File.expand_path('../../lib/ethereum/_casper.abi', __FILE__)
casper_hash_file = File.expand_path('../../lib/ethereum/_casper.hash', __FILE__)
casper_evm_file = File.expand_path('../../lib/ethereum/_casper.evm', __FILE__)

casper_code = nil
casper_abi = nil
begin
  h = Utils.encode_hex Utils.keccak256(File.binread(casper_file))
  raise AssertError, "casper contract hash mismatch" unless h == File.binread(casper_hash_file)
  casper_code = File.binread(casper_evm_file)
  casper_abi = JSON.parse File.binread(casper_abi_file)
rescue
  puts "Compiling casper contract ..."
  h = Utils.encode_hex Utils.keccak256(File.binread(casper_file))
  casper_code = Serpent.compile casper_file
  casper_abi = Serpent.mk_full_signature casper_file
  File.open(casper_abi_file, 'w') {|f| f.write JSON.dump(abi) }
  File.open(casper_evm_file, 'w') {|f| f.write code }
  File.open(casper_hash_file, 'w') {|f| f.write h }
end
casper_ct = ABI::ContractTranslator.new casper_abi

# Deploy Casper contract
gc.tx_state_transition Transaction.new(nil, 4000000, data: Constant::BYTE_EMPTY, code: casper_code)
genesis.put_code Config::CASPER, gc.get_code(Utils.mk_contract_address(code: casper_code))
puts "Casper loaded"

# Deploy Ringsig contract
ringsig_file = File.expand_path('../../lib/ethereum/ringsig.se.py', __FILE__)
ringsig_code = Serpent.compile ringsig_file
ringsig_ct = ABI::ContractTranslator.new Serpent.mk_full_signature(ringsig_file)

# Deploy ecrecover account code
code = ECDSAAccount.constructor_code
gc.tx_state_transition Transaction.new(nil, 1000000, data: Constant::BYTE_EMPTY, code: code)
genesis.put_code Config::ECRECOVERACCT, gc.get_code(Utils.mk_contract_address(code: code))
puts "ECRECOVERACCT loaded"

# Deploy EC sender code
code = ECDSAAccount.runner_code
gc.tx_state_transition Transaction.new(nil, 1000000, data: Constant::BYTE_EMPTY, code: code)
genesis.put_code Config::BASICSENDER, gc.get_code(Utils.mk_contract_address(code: code))
puts "BASICSENDER loaded"

