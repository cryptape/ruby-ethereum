# -*- encoding : ascii-8bit -*-

require 'test_helper'

class DifficultyTest < Minitest::Test
  include Ethereum

  run_fixtures "BasicTests", only: /difficulty/, except: /difficultyOlimpic/

  def on_fixture_test(name, params)
    parent_timestamp = parse_int params['parentTimestamp']
    parent_difficulty = parse_int params['parentDifficulty']
    parent_blk_number = parse_int(params['currentBlockNumber']) - 1
    cur_blk_timestamp = parse_int params['currentTimestamp']
    reference_diff = parse_int params['currentDifficulty']

    config = {}
    config[:homestead_fork_blknum] = 0 if name =~ /Homestead/
    config[:homestead_fork_blknum] = 494000 if name =~ /difficultyMorden/
    env = Env.new DB::EphemDB.new, config: Env::DEFAULT_CONFIG.merge(config)

    parent_bh = BlockHeader.new timestamp: parent_timestamp, difficulty: parent_difficulty, number: parent_blk_number
    block = Block.new parent_bh, env: env, making: true

    calculated_diff = Block.calc_difficulty block, cur_blk_timestamp
    assert_equal reference_diff, calculated_diff
  end

  private

  def parse_int(s)
    s.to_i(s =~ /^0x/ ? 16 : 10)
  end

end
