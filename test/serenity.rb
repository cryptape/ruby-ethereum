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
casper_ct = Casper.contract

# Deploy Casper contract
gc.tx_state_transition Transaction.new(addr: nil, gas: 4000000, data: Constant::BYTE_EMPTY, code: Casper.code)
genesis.put_code Config::CASPER, gc.get_code(Utils.mk_contract_address(code: Casper.code))
puts "Casper loaded"

# Deploy Ringsig contract
ringsig_file = File.expand_path('../../lib/ethereum/ringsig.se.py', __FILE__)
ringsig_code = Serpent.compile ringsig_file
ringsig_ct = ABI::ContractTranslator.new Serpent.mk_full_signature(ringsig_file)

# Deploy ecrecover account code
code = ECDSAAccount.constructor_code
gc.tx_state_transition Transaction.new(addr: nil, gas: 1000000, data: Constant::BYTE_EMPTY, code: code)
genesis.put_code Config::ECRECOVERACCT, gc.get_code(Utils.mk_contract_address(code: code))
puts "ECRECOVERACCT loaded"

# Deploy EC sender code
code = ECDSAAccount.runner_code
gc.tx_state_transition Transaction.new(addr: nil, gas: 1000000, data: Constant::BYTE_EMPTY, code: code)
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

# Setup validators
keys = (0...(MAX_NODES-2)).map {|i| Utils.zpad_int(i+1) }
keys.each_with_index do |k, i|
  # Generate the address
  addr = ECDSAAccount.privtoaddr k
  raise AssertError, "already initialized" unless Utils.big_endian_to_int(genesis.get_storage(addr, TT256M1)) == 0

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

# Give secondary keys some ether
second_keys = ((MAX_NODES-2)...MAX_NODES).map {|i| Utils.zpad_int(i+1) }
second_keys.each_with_index do |k, i|
  addr = ECDSAAccount.privtoaddr k
  raise AssertError, "already initialized" unless Utils.big_endian_to_int(genesis.get_storage(addr, TT256M1)) == 0

  genesis.set_storage Config::ETHER, addr, 1600.ether
end

# Set the staring RNG seed to equal to number of casper guardians
genesis.set_storage Config::RNGSEEDS, Utils.zpad_int(TT256M1), genesis.get_storage(Config::CASPER, 0)
t = NetworkSimulator::START_TIME + 5
genesis.set_storage Config::GENESIS_TIME, Utils.zpad_int(0), t.to_i
puts "\n\n\n**************************************"
puts "genesis time #{t}"
puts "**************************************\n\n\n"

# Create betting strategy objects for every guardian
mk_bet_strategy = lambda do |state, index, key|
  Guardian::DefaultBetStrategy.new(state.clone, key,
                                  clockwrong: index >= 1 && index < CLOCKWRONG_CUMUL,
                                  bravery: index >= CLOCKWRONG_CUMUL && index < BRAVE_CUMUL ? 0.997 : 0.92,
                                  crazy_bet: index >= BRAVE_CUMUL && index < CRAZYBET_CUMUL,
                                  double_block_suicide: index >= CRAZYBET_CUMUL && index < DBL_BLK_SUICIDE_CUMUL ? 5 : 2**80,
                                  double_bet_suicide: index >= DBL_BLK_SUICIDE_CUMUL && index < DBL_BET_SUICIDE_CUMUL ? 1 : 2**80)
end

bets = keys.each_with_index.map {|k,i| mk_bet_strategy.call genesis, i, k }

min_mfh = -1 # Minimum max finalized height
check_txs = [] # Transactions to status report on

# Simulate a network
n = NetworkSimulator.new latency: 4, agents: bets, broadcast_success_rate: 0.9
n.generate_peers 5
bets.each {|b| b.network = n }

# Submitting ring sig contract as a transaction
puts "submitting ring sig contract\n\n"
ringsig_addr = Utils.mk_contract_address sender: bets[0].addr, code: ringsig_code
puts "Ringsig address #{Utils.encode_hex(ringsig_addr)}"

tx3 = ECDSAAccount.mk_transaction 1, 25.shannon, 2000000, Config::CREATOR, 0, ringsig_code, bets[0].key
bets[0].add_transaction tx3
check_txs.push tx3

ringsig_account_source = <<EOF
def init():
    sstore(0, #{Utils.big_endian_to_int(ringsig_addr)})
    sstore(1, #{Utils.big_endian_to_int(ringsig_addr)})
#{ECDSAAccount.mandatory_account_source}
EOF
ringsig_account_code = Serpent.compile(ringsig_account_source)
ringsig_account_addr = Utils.mk_contract_address sender: bets[0].addr, code: ringsig_account_code

tx4 = ECDSAAccount.mk_transaction 2, 25.shannon, 2000000, Config::CREATOR, 0, ringsig_account_code, bets[0].key
bets[0].add_transaction tx4
check_txs.push tx4
puts "Ringsig account address #{Utils.encode_hex(ringsig_account_addr)}"

# Status verifier
check_correctness = lambda do |bets|
  min_mfh += 1
end

# Keep running until the min finalized height reaches 20
loop do
  n.run 25, sleep: 0.25
  raise "hoooooooo yeahhhhhhhhhhhhhhhhh !!!!!!!!!!!!!!!!!!"
  check_correctness.call bets

  if min_mfh >= 36
    puts 'Reached breakpoint'
    break
  end

  puts "Min mfh: #{min_mfh}"
  puts "Peer lists: #{bets.map {|b| n.peers[b.id].map(&:id) }}"
end
