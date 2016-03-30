#!/usr/bin/env ruby
# -*- encoding : ascii-8bit -*-

$:.unshift File.expand_path('../../lib', __FILE__)

require 'json'
require 'serpent'

require 'ethereum'
require 'ethereum/serenity'

include Ethereum
VM = FastVM

TT256M1 = 2**256 - 1

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

my_listen = lambda do |sender, topics, data|
  jsondata = casper_ct.listen sender, topics, data
  if jsondata.true? && %w(BlockLoss StateLoss).include?(jsondata['_event_type'])
    if bets[jsondata['index']].byzantine.false?
      if jsondata['loss'] < 0
        index = jsondata['index']
        height = jsondata['height']

        if jsondata['odds'] < 10**7 && jsondata['_event_type'] == 'BlockLoss'
          puts "bettor current probs #{bets[index].probs[0,height]}"
          raise "Odds waaaaaaay too low! #{jsondata}"
        end

        if jsondata['odds'] > 10**11
          puts "bettor stateroots: #{bets[index].stateroots}"
          puts "bettor opinion: #{bets[index].opinions[index].stateroots}"
          if bets[0].stateroots.size < height
            puts "in bettor 0 stateroots: #{bets[0].stateroots[height]}"
          end
          raise "Odds waaaaaaay too high! #{jsondata}"
        end
      end
    end
  end

  if jsondata.true? && jsondata['_event_type'] == 'ExcessRewardEvent'
    raise "Excess reward event: #{jsondata}"
  end

  ECDSAAccount.constructor.listen sender, topics, data
  ECDSAAccount.mandatory_account.listen sender, topics, data
  ringsig_ct.listen sender, topics, data
end

#Logger.set_trace 'eth.vm.exit'

# Setup keys
keys = (0...(MAX_NODES-2)).map {|i| Utils.zpad_int(i+1) }
second_keys = ((MAX_NODES-2)...MAX_NODES).map {|i| Utils.zpad_int(i+1) }
keys.each_with_index do |k, i|
  # Generate the address
  addr = ECDSAAccount.privtoaddr k
  raise AssertError, "aleady initialized" unless Utils.big_endian_to_int(genesis.get_storage(addr, TT256M1)) == 0

  # Give them 1600 ether
  genesis.set_storage Config::ETHER, addr, 1600.ether

  # Make their validation code
  vcode = ECDSAAccount.mk_validation_code k
  puts "Length of validation code: #{vcode.size}"

  # Make the transaction to join as a Casper guardian
  txdata = casper_ct.encode 'join', [vcode]
  tx = ECDSAAccount.mk_transaction 0, 25.shannon, 1000000, Config::CASPER, 1500.ether, txdata, k, create: true
  puts 'Joining'

  v = genesis.tx_state_transition tx, listeners: [my_listen]
  index = casper_ct.decode('join', Utils.int_array_to_bytes(v))[0]
  puts "Joined with index #{index}"
  puts "Length of account code: #{genesis.get_code(addr).size}"

  raise AssertError, "missing mandatory account code" unless ECDSAAccount.mandatory_account_code == genesis.get_code(addr).sub(%r!#{"\x00"}+\z!, '')

  raise AssertError, "invalid sequence number" unless Utils.big_endian_to_int(genesis.get_storage(addr, TT256M1)) == 1

  # check that we actually joined Casper with the right validation code
  vcode2 = genesis.call_method Config::CASPER, casper_ct, 'getGuardianValidationCode', [index]
  raise AssertError, "incorrect casper validation code" unless vcode2 == vcode
end
