#!/usr/bin/env ruby
# -*- encoding : ascii-8bit -*-

$:.unshift File.expand_path('../../lib', __FILE__)

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
casper_hash_file = File.expand_path('../../lib/ethereum/_casper.hash', __FILE__)
casper_evm_file = File.expand_path('../../lib/ethereum/_casper.evm', __FILE__)

code = nil
begin
  h = Utils.encode_hex Utils.keccak256(File.binread(casper_file))
  raise AssertError, "casper contract hash mismatch" unless h == File.binread(casper_hash_file)
  code = File.binread(casper_evm_file)
rescue
  h = Utils.encode_hex Utils.keccak256(File.binread(casper_file))
  code = Serpent.compile casper_file
  File.open(casper_evm_file, 'w') {|f| f.write code }
  File.open(casper_hash_file, 'w') {|f| f.write h }
end

# Add Casper contract to blockchain
gc.tx_state_transition Transaction.new(nil, 4000000, data: Constant::BYTE_EMPTY, code: code)
genesis.put_code Config::CASPER, gc.get_code(Utils.mk_contract_address(code: code))
puts "Casper loaded"
