# -*- encoding : ascii-8bit -*-

require 'test_helper'

class BlockTest < Minitest::Test
  include Ethereum

  def setup
    @db = DB::EphemDB.new
    @db.put Trie::BLANK_ROOT, RLP.encode(Trie::BLANK_NODE)

    @env = Env.new @db

    @header = BlockHeader.new(bloom: 100, nonce: 'ffffffff')
    @header_rlp = RLP.encode @header
  end

  def test_build_from_header
    blk = Block.build_from_header @header_rlp, @env
    assert_equal 100, blk.bloom
    assert_equal 'ffffffff', blk.nonce
  end

  def test_build_from_parent
    Miner.stub(:check_pow, true) do
      parent = Block.build_from_header @header_rlp, @env
      coinbase = "\x02"*20
      blk = Block.build_from_parent parent, coinbase

      assert_equal parent.number+1, blk.number
      assert_equal coinbase, blk.coinbase
      assert_equal parent.full_hash, blk.prevhash
      assert_equal parent.state_root, blk.state_root
    end
  end

  def test_calc_difficulty
    parent = Block.build_from_header @header_rlp, @env
    assert_equal 131136, Block.calc_difficulty(parent, 1)
    assert_equal 131136, Block.calc_difficulty(parent, 10)
    assert_equal 131072, Block.calc_difficulty(parent, 15)
    assert_equal 131072, Block.calc_difficulty(parent, 9999)
  end

  def test_calc_difficulty_homestead
    config = Env::DEFAULT_CONFIG.merge(homestead_fork_blknum: 0)

    parent = Block.build_from_header @header_rlp, @env
    parent.header.make_mutable!
    parent.timestamp = 1451559301
    parent.difficulty = 131200
    parent.instance_variable_set :@config, config

    timestamp = 1451559318
    assert_equal 131200, Block.calc_difficulty(parent, timestamp)
  end

  def test_calc_gaslimit
    parent = Block.build_from_header @header_rlp, @env
    assert_equal 3141592, Block.calc_gaslimit(parent)
  end

  def test_initialize
    parent = Block.build_from_header @header_rlp, @env

    header = BlockHeader.new(
      prevhash: @header.full_hash,
      uncles_hash: Utils.keccak256_rlp([]),
      coinbase: "\x01"*20,

      number: parent.number+1,
      timestamp: 15,
      difficulty: Block.calc_difficulty(parent, 15)
    )

    blk = Block.new header, env: @env, parent: parent
    assert_equal parent.number+1, blk.number
    assert_equal blk, header.block
  end

end

class BlockFixtureTest < Minitest::Test
  include Ethereum

  run_fixtures "BlockchainTests"

  EXCLUDES = %w(
    BlockchainTests_bcWalletTest_walletReorganizeOwners
    BlockchainTests_RandomTests_bl10251623GO_randomBlockTest
    BlockchainTests_RandomTests_bl201507071825GO_randomBlockTest
  )

  @@env = Env.new DB::EphemDB.new

  def parse_alloc(pre)
    alloc = {}

    pre.map do |addr, data|
      parsed_data = {}

      parsed_data[:wei] = data['wei'] if data['wei']
      parsed_data[:balance] = data['balance'] if data['balance']
      parsed_data[:code] = data['code'] if data['code']
      parsed_data[:nonce] = data['nonce'] if data['nonce']
      parsed_data[:storage] = data['storage'] if data['storage']

      alloc[addr] = parsed_data
    end

    alloc
  end

  def on_fixture_test(name, params)
    return if EXCLUDES.include?(name)

    filename, _, testname = name.rpartition('_')

    homestead_fork_blknum = 1000000
    homestead_fork_blknum = 0 if filename =~ /Homestead/
    homestead_fork_blknum = 5 if filename =~ /TestNetwork/

    dao_fork_blknum = filename =~ /bcTheDaoTest/ ? 8 : 1920000

    config_overrides = {
      homestead_fork_blknum: homestead_fork_blknum,
      dao_fork_blknum: dao_fork_blknum
    }

    run_block_test params, config_overrides
  end

  def run_block_test(params, config_overrides={})
    old_config = @@env.config
    @@env = Env.new @@env.db, config: old_config.merge(config_overrides), global_config: @@env.global_config

    bh = params['genesisBlockHeader']
    alloc = parse_alloc params['pre']

    b = Block.genesis(
      @@env,
      start_alloc: alloc,
      bloom: Scanner.int256b(bh['bloom']),
      timestamp: Scanner.int(bh['timestamp']),
      nonce: Scanner.bin(bh['nonce']),
      extra_data: Scanner.bin(bh['extraData']),
      gas_limit: Scanner.int(bh['gasLimit']),
      gas_used: Scanner.int(bh['gasUsed']),
      coinbase: Scanner.addr(decode_hex(bh['coinbase'])),
      difficulty: parse_int_or_hex(bh['difficulty']),
      prevhash: Scanner.bin(bh['parentHash']),
      mixhash: Scanner.bin(bh['mixHash'])
    )

    assert_equal Scanner.bin(bh['receiptTrie']), b.receipts_root
    assert_equal Scanner.bin(bh['transactionsTrie']), b.tx_list_root
    assert_equal Scanner.bin(bh['uncleHash']), Utils.keccak256_rlp(b.uncles)

    h = encode_hex b.state_root
    assert_equal bh['stateRoot'], h
    assert_equal Scanner.bin(bh['hash']), b.full_hash
    #assert b.header.check_pow

    blockmap = {b.full_hash => b}
    @@env.db.put b.full_hash, RLP.encode(b)

    b2 = nil
    params['blocks'].each do |blk|
      if blk.has_key?('blockHeader')
        rlpdata = decode_hex blk['rlp'][2..-1]
        bhdata = RLP.decode(rlpdata)[0]
        blkparent = RLP.decode(RLP.encode(bhdata), sedes: BlockHeader).prevhash

        b2 = RLP.decode rlpdata, sedes: Block, parent: blockmap[blkparent], env: @@env # <- slow
        assert_equal true, b2.validate_uncles

        blockmap[b2.full_hash] = b2
        @@env.db.put b2.full_hash, RLP.encode(b2)
      else
        begin
          rlpdata = decode_hex blk['rlp'][2..-1]
          bhdata = RLP.decode(rlpdata)[0]
          blkparent = RLP.decode(RLP.encode(bhdata), sedes: BlockHeader).prevhash

          b2 = RLP.decode rlpdata, sedes: Block, parent: blockmap[blkparent], env: @@env

          success = b2.validate_uncles
        rescue
          success = false
        end
        assert_equal false, success
      end
    end
  ensure
    @@env = Env.new @@env.db, config: old_config, global_config: @@env.global_config
  end

end
