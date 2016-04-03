#!/usr/bin/env ruby
# -*- encoding : ascii-8bit -*-

$:.unshift File.expand_path('../../lib', __FILE__)

require 'pry'
require 'pry-byebug'

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
ringsig_file = File.expand_path('../../lib/ethereum/serenity/ringsig.se.py', __FILE__)
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
  puts "*"*100

  # Max finalized heights for each bettor strategy
  mfhs = bets.select {|b| !b.byzantine }.map {|b| b.max_finalized_height }
  mchs = bets.select {|b| !b.byzantine }.map {|b| b.calc_state_roots_from }
  mfchs = bets.select {|b| !b.byzantine }.map {|b| [b.max_finalized_height, b.calc_state_roots_from].min }
  new_min_mfh = mfchs.min

  puts "Max finalized heights: #{bets.map {|b| b.max_finalized_height }}"
  puts "Max calculated stateroots: #{bets.map {|b| b.calc_state_roots_from }}"
  puts "Max height received: #{bets.map {|b| b.blocks.size }.max}"

  puts "Registered induction heights: #{bets.map {|b| b.opinions.values.map {|op| op.induction_height } }}"
  puts "Withdrawn?: #{bets.map {|b| [b.withdrawn, b.seq] }}"

  # Data about bets from each guardian according to every other guardian
  puts "Now: %.2f" % n.now
  puts "According to each guardian ..."
  bets.each do |bet|
    bets_received = bet.opinions.values.map {|op| op.withdrawn ? "#{op.seq} (withdrawn)" : op.seq.to_s }
    blocks_received = bet.blocks.map {|b| b.true? ? '1' : '0' }.join
    puts "(#{bet.index}) Bets received: #{bets_received}, blocks received: #{blocks_received}. Last bet made: %.2f." % bet.last_bet_made
    puts "Probs (in 0-255 repr, from #{new_min_mfh+1}): #{bet.probs[(new_min_mfh+1)..-1].map {|x| Guardian.encode_prob(x).ord }}"
  end

  puts "Indices: #{bets.map {|b| b.index }}"
  puts "Blocks received: #{bets.map {|b| b.blocks.size }}"
  puts "Blocks missing: #{bets.map {|b| b.blocks.select {|blk| blk.false? } }}"

  # Make sure all block hashes for all heights up to the minimum finalized
  # height are the same
  puts "Verifying finalized block hash equivalence"
  (1...bets.size).each do |j|
    if !bets[j].byzantine && !bets[j-1].byzantine
      j_hashes = bets[j].finalized_hashes[0, new_min_mfh+1]
      jm1_hashes = bets[j-1].finalized_hashes[0, new_min_mfh+1]
      raise AssertError, 'finalized block hash mismatch' unless j_hashes == jm1_hashes
    end
  end

  # Checks state roots for finalized heights and makes sure that they are
  # consistent
  puts "Verifying finalized state root correctness"
  root = min_mfh < 0 ? genesis.root : bets[0].stateroots[min_mfh]
  state = State.new root, DB::OverlayDB.new(bets[0].db)
  bets.each do |b|
    unless b.byzantine
      new_min_mfh.times do |i|
        raise AssertError, 'missing finalized state root' if [Constant::WORD_ZERO, nil].include?(b.stateroots[i])
      end
    end
  end

  puts "Executing blocks #{min_mfh+1} to #{[min_mfh, new_min_mfh].max + 1}"
  ((min_mfh+1)...([min_mfh, new_min_mfh].max+1)).each do |i|
    raise AssertError, 'state root mismatch' unless (i > 0 ? state.root == bets[0].stateroots[i-1] : genesis.root)

    j = bets.size - 1
    fh = bets[0].finalized_hashes[i]
    block = fh != Constant::WORD_ZERO ? bets[j].objects[fh] : nil
    block0 = fh != Constant::WORD_ZERO ? bets[0].objects[fh] : nil
    raise AssertError, "block mistmatch" unless block == block0

    state.block_state_transition block, listeners: [my_listen]
    if state.root != bets[0].stateroots[i] && i != [min_mfh, new_min_mfh].max
      puts bets[0].calc_state_roots_from, bets[j].calc_state_roots_from
      puts bets[0].max_finalized_height, bets[j].max_finalized_height
      puts "my state #{state.to_h}"
      puts "given state #{State.new(bets[0].stateroots[i], bets[0].db).to_h}"
      puts "block #{RLP.encode(block)}"

      puts "State root mismatch at block #{i}!"
      puts "state.root: #{Utils.encode_hex(state.root)}\n"
      puts "bet: #{Utils.encode_hex(bets[0].stateroots[i])}"

      raise AssertError, "inconsistent block state transition"
    end
  end

  min_mfh = new_min_mfh
  puts "Min common finalized height: #{new_min_mfh}, integrity checks passed"

  # Last and next blocks to propose by each guardian
  puts "Last block created: #{bets.map {|b| b.last_block_produced }}"
  puts "Next blocks to create: #{bets.map {|b| b.next_block_to_produce }}"

  # Assert equivalence of proposer lists
  min_proposer_length = bets.map {|b| b.proposers.size }.min
  bets.each do |bet|
    raise AssertError, 'inconsistent proposers lits' unless bet.proposers[0, min_proposer_length] == bets[0].proposers[0, min_proposer_length]
  end

  # Guardian sequence numbers as seen by themselves
  puts "Guardian seqs online: #{bets.map {|b| b.seq }}"
  # Guardian sequence numbers as recorded in the chain
  seqs = bets.map {|b| state.call_method Config::CASPER, Casper.contract, 'getGuardianSeq', [b.index >= 0 ? b.index : b.former_index] }
  puts "Guardian seqs on finalized chain (#{new_min_mfh}): #{seqs}"

  h = 0
  while h < bets[3].stateroots.size && ![nil, Constant::WORD_ZERO].include?(bets[3].stateroots[h])
    h += 1
  end

  root = h.true? ? bets[3].stateroots[h-1] : genesis.root
  speculative_state = State.new root, DB::OverlayDB.new(bets[3].db)
  seqs = bets.map {|b| speculative_state.call_method Config::CASPER, Casper.contract, 'getGuardianSeq', [b.index >= 0 ? b.index : b.former_index] }
  puts "Guardian seqs on speculative chain (#{h-1}): #{seqs}"

  # Guardian deposit sizes (over 1500.ether means profit)
  deposits = bets.select {|b| b.index >= 0 }.map {|b| state.call_method Config::CASPER, Casper.contract, 'getGuardianDeposit', [b.index] }
  puts "Guardian deposit sizes: #{deposits}"
  gains = bets.select {|b| b.index >= 0 }.map {|b| state.call_method(Config::CASPER, Casper.contract, 'getGuardianDeposit', [b.index]) - 1500.ether + 47/10**9 * 1500.ether * min_mfh }
  puts "Estimated guardian excess gains: #{gains}"

  bets.each do |bet|
    if bet.index >= 0 && Utils.big_endian_to_int(state.get_storage(Config::BLKNUMBER, Constant::WORD_ZERO)) >= bet.induction_height
      raise AssertError, '' unless state.call_method(Config::CASPER, Casper.contract, 'getGuardianDeposit', [bet.index]) >= 1499.ether || bet.byzantine
    end

    puts "Account signing nonces: #{bets.map {|b| Utils.big_endian_to_int(state.get_storage(b.addr, Utils.zpad_int(2**256-1))) }}"
    puts "Transaction status in unconfirmed_txindex: #{check_txs.map {|tx| bets[0].unconfirmed_txindex.fetch(tx.full_hash, nil) ? '1' : '0' }.join}"
    puts "Transaction status in finalized_txindex: #{check_txs.map {|tx| bets[0].finalized_txindex.fetch(tx.full_hash, nil) ? '1' : '0' }.join}"
    puts "Transaction exceptions: #{check_txs.map {|tx| bets[0].tx_exceptions.fetch(tx.full_hash, 0).to_s }.join}"
  end
end

# Keep running until the min finalized height reaches 20
loop do
  n.run 25, sleep: 0.25
  check_correctness.call bets

  p "*************************************************** #{min_mfh}"
  if min_mfh >= 36
    puts 'Reached breakpoint'
    break
  end

  puts "Min mfh: #{min_mfh}"
  puts "Peer lists: #{bets.map {|b| n.peers[b.id].map(&:id) }}"
end

recent_state = State.new bets[0].stateroots[min_mfh], bets[0].db
raise AssertError, 'failed to deploy ringsig' unless recent_state.get_code(ringsig_addr).true?
raise AssertError, 'failed to deploy ringsig account' unless recent_state.get_code(ringsig_account_addr).true?
puts "Length of ringsig contract: #{recent_state.get_code(ringsig_addr).size}"

# Create transactions for a few new guardians to join
puts "*"*100
puts "*"*100
puts "Generating transactions to include new guardians"
second_keys.each_with_index do |k, i|
  index = keys.size + i
  # Make their validation code
  vcode = ECDSAAccount.mk_validation_code k
  # Make the transaction to join as a Casper guardian
  txdata = Casper.contract.encode 'join', [vcode]

  tx = ECDSAAccount.mk_transaction 0, 25.shannon, 1000000, Config::CASPER, 1500.ether, txdata, k, create: true
  puts "Making transaction: #{Utils.encode_hex tx.full_hash}"

  bets[0].add_transaction tx
  check_txs.push tx
end

THRESHOLD1 = 115 + 10 * (CLOCKWRONG + CRAZYBET + BRAVE)
THRESHOLD2 = THRESHOLD1 + Constant::ENTER_EXIT_DELAY

orig_ring_pubs = []
#Publish submits to ringsig contract
puts "Sending to ringsig contract"
bets[1...6].each do |bet|
  pub = PublicKey.new(PrivateKey.new(bet.key).to_pubkey).decode(:bin)
  orig_ring_pubs.push pub
  data = ringsig_ct.encode 'submit', pub
  tx = ECDSAAccount.mk_transaction 1, 25.shannon, 750000, ringsig_account_addr, 10**17, data, bet.key
  raise AssertError, 'failed to include ringsig transaction' unless bet.should_include_transaction?(tx)
  bet.add_transaction tx, track: true
  check_txs.push tx
end

# Keep running until the min finalized height reaches 75. We expect that by
# this time all transactions from the previous phase have been included
loop do
  n.run 25, sleep: 0.25
  check_correctness.call bets
  if min_mfh > THRESHOLD1
    puts 'Reached breakpoint'
    break
  end
  puts "Min mfh: #{min_mfh}"
end

recent_state = State.new bets[0].stateroots[min_mfh], bets[0].db
next_index = recent_state.call_method ringsig_account_addr, ringsig_ct, 'getNextIndex', []
raise AssertError, "Next index: #{next_index}, should be 5" unless next_index == 5
ring_pub_data = recent_state.call_method ringsig_account_addr, ringsig_ct, 'getPubs', [0]
ring_pubs = ((ring_pub_data.size+1)/2).times.map do |j|
  i = j*2
  [ring_pub_data[i] % 2**256, ring_pub_data[i+1] % 2**256]
end
puts ring_pubs.sort
puts orig_ring_pubs.sort
raise AssertError, "ring pubs mismatch" unless ring_pubs.sort == orig_ring_pubs.sort
puts "Submitted public keys: #{ring_pubs}"

# Create ringsig withdrawal transactions
bets[1...6].each_with_index do |bet, i|
  pub = PublicKey.new(PrivateKey.new(bet.key).to_pubkey).decode(:bin)
  target_addr = 2000 + i
  #x0, s, ix, iy = ringsig_tester.ringsig_sign_substitute Utils.zpad_int(target_addr), PrivateKey.new(bet.key).decode, ring_pubs
  #puts "Verifying ring signature using python code"
  #raise AssertError, '' unless ringsig_tester.ringsig_verify_substitute(Utils.zpad_int(target_addr), x0, s, ix, iy, ring_pubs)

  #data = ringsig_ct.encode 'withdraw', [Utils.int_to_addr(target_addr), x0, s, ix, iy, 0]
  #tx = Transaction.new ringsig_account_addr, 1000000, data: data, code: Constant::BYTE_EMPTY
  #puts "Verifying tx includability"
  #raise AssertError, 'ringsig tx can not be included' unless bet.should_include_transaction?(tx)

  #bet.add_transaction tx
  #check_txs.push tx
end

# Create bet objects for the new guardians
state = State.new genesis.root, bets[0].db
second_bets = second_keys.each_with_index.map {|k, i| mk_bet_strategy.call state, bets.size+i, k }
second_bets.each {|b| b.network = n }

n.agents.concat second_bets
n.generate_peers 5
puts "Increasing number of peers in the network to #{MAX_NODES}!"
recent_state = State.new bets[0].stateroots[min_mfh], bets[0].db

# Check that all signups are successful
signups = recent_state.call_method Config::CASPER, Casper.contract, 'getGuardianSignups', []
puts "Guardians signed up: #{signups}"
raise AssertError, 'some guardian failed to signup' unless signups == MAX_NODES
puts "All new guardians inducted"

ihs = (keys.size + second_keys.size).times.map {|i| recent_state.call_method Config::CASPER, Casper.contract, 'getGuardianInductionHeight', [i] }
puts "Induction heights: #{}"

# Keep running until the min finalized height reaches ~175. We expect that by
# this time all guardians will be actively betting off of each other's bets
loop do
  n.run(25, sleep: 0.25)
  check_correctness.call bets

  puts "Min mfh: #{min_mfh}"
  ihs = (keys.size + second_keys.size).times.map {|i| recent_state.call_method Config::CASPER, Casper.contract, 'getGuardianInductionHeight', [i] }
  puts "Induction heights: #{}"

  if min_mfh > THRESHOLD2
    puts "Reached breakpoint"
    break
  end
end

# Create transactions for old guardians to leave
puts "*"*100
puts "*"*100
puts "Generating transactions to withdraw some guardians"
bets[0,3].each do |bet|
  bet.withdraw
end

BLK_DISTANCE = bets[2].blocks.size - min_mfh

# keep running until ~290
loop do
  n.run(25, sleep: 0.25)
  check_correctness.call bets
  puts "Min mfh: #{min_mfh}"
  whs = (keys.size+second_keys.size).times.map {|i| recent_state.call_method Config::CASPER, Casper.contract, 'getGuardianWithdrawalHeight', [i] }
  puts "Withdrawal heights: #{whs}"

  if min_mfh > 200 + BLK_DISTANCE + Constant::ENTER_EXIT_DELAY
    puts 'Reached breakpoint'
    break
  end

  # Exit early if the withdrawal step already completed
  recent_state = bets[0].get_finalized_state
  active_guardians = 50.times.select {|i| recent_state.call_method(Config::CASPER, Casper.contract, 'getGuardianStatus', [i]) == 2}
  break if active_guardians.size == (MAX_NODES - 3)
end

recent_state = bets[0].get_optimistic_state
# Check that the only remaining active guardians are the ones that have not yet
# signed out
status = MAX_NODES.times.map {|i| recent_state.call_method(Config::CASPER, Casper.contract, 'getGuardianStatus', [i]) }
puts "Guardian status: #{status}"
raise AssertError, 'active guardians mismatch' unless status.select {|s| s == 2 }.size == (MAX_NODES - 3)
