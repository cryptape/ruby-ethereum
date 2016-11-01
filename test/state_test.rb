# -*- encoding : ascii-8bit -*-

require 'test_helper'

class StateTest < Minitest::Test
  include Ethereum

  run_fixtures "StateTests", except: /stQuadraticComplexityTest|stMemoryStressTest|stPreCompiledContractsTransaction/

  def on_fixture_test(name, data)
    check_state_test data
  end

  def check_state_test(params)
    run_state_test params, :verify
  end

  ENV_KEYS = %w(currentGasLimit currentTimestamp previousHash currentCoinbase currentDifficulty currentNumber).sort.freeze
  PRE_KEYS = %w(code nonce balance storage).sort.freeze

  def run_state_test(params, mode)
    pre  = params['pre']
    exek = params['transaction']
    env  = params['env']

    assert_equal ENV_KEYS, env.keys.sort
    assert_equal 40, env['currentCoinbase'].size

    # setup env
    db_env = Env.new DB::EphemDB.new
    header = BlockHeader.new(
      prevhash: decode_hex(env['previousHash']),
      number: parse_int_or_hex(env['currentNumber']),
      coinbase: decode_hex(env['currentCoinbase']),
      difficulty: parse_int_or_hex(env['currentDifficulty']),
      timestamp: parse_int_or_hex(env['currentTimestamp']),
      gas_limit: [db_env.config[:max_gas_limit], parse_int_or_hex(env['currentGasLimit'])].min # work around https://github.com/ethereum/pyethereum/issues/390, step 1
    )
    blk = Block.new(header, env: db_env)

    # work around https://github.com/ethereum/pyethereum/issues/390, step 2
    blk.gas_limit = parse_int_or_hex env['currentGasLimit']

    # setup state
    pre.each do |addr, h|
      assert_equal 40, addr.size
      assert PRE_KEYS, h.keys.sort

      address = decode_hex addr
      blk.set_nonce address, parse_int_or_hex(h['nonce'])
      blk.set_balance address, parse_int_or_hex(h['balance'])
      blk.set_code address, decode_hex(h['code'][2..-1])
      h['storage'].each do |k, v|
        blk.set_storage_data(
          address,
          Utils.big_endian_to_int(decode_hex(k[2..-1])),
          Utils.big_endian_to_int(decode_hex(v[2..-1]))
        )
      end
    end

    # verify state
    pre.each do |addr, h|
      address = decode_hex addr

      assert_equal parse_int_or_hex(h['nonce']), blk.get_nonce(address)
      assert_equal parse_int_or_hex(h['balance']), blk.get_balance(address)
      assert_equal decode_hex(h['code'][2..-1]), blk.get_code(address)

      h['storage'].each do |k, v|
        assert_equal Utils.big_endian_to_int(decode_hex(v[2..-1])), blk.get_storage_data(address, Utils.big_endian_to_int(decode_hex(k[2..-1])))
      end
    end

    # execute transactions
    patch_external_call blk
    begin
      tx = Transaction.new(
        nonce: parse_int_or_hex(exek['nonce'] || '0'),
        gasprice: parse_int_or_hex(exek['gasPrice'] || '0'),
        startgas: parse_int_or_hex(exek['gasLimit'] || '0'),
        to: Utils.normalize_address(exek['to'], allow_blank: true),
        value: parse_int_or_hex(exek['value'] || '0'),
        data: decode_hex(Utils.remove_0x_head(exek['data']))
      )
    rescue InvalidTransaction
      tx = nil
      success, output = false, Constant::BYTE_EMPTY
      time_pre = Time.now
      time_post = time_pre
    else
      if exek.has_key?('secretKey')
        tx.sign(exek['secretKey'])
      elsif %w(v r s).all? {|k| exek.has_key?(k) }
        tx.v = decode_hex Utils.remove_0x_head(exek['v'])
        tx.r = decode_hex Utils.remove_0x_head(exek['r'])
        tx.s = decode_hex Utils.remove_0x_head(exek['s'])
      else
        assert false, 'no way to sign'
      end

      time_pre = Time.now
      begin
        success, output = blk.apply_transaction(tx)

        blk.commit_state
      rescue InvalidTransaction
        success, output = false, Constant::BYTE_EMPTY
        blk.commit_state
      end
      time_post = Time.now

      if tx.to == Constant::BYTE_EMPTY
        output = blk.get_code(output)
      end
    end

    params2 = Marshal.load Marshal.dump(params)
    params2['logs'] = blk.get_receipt(0).logs.map {|log| log.to_h } if success.true?
    params2['out'] = "0x#{encode_hex(output)}"
    params2['post'] = Marshal.load Marshal.dump(blk.to_h(with_state: true)[:state])
    params2['postStateRoot'] = encode_hex blk.state.root_hash

    case mode
    when :fill
      params2
    when :verify
      params1 = Marshal.load Marshal.dump(params)
      shouldbe, reallyis = params1['post'], params2['post']

      compare_post_states shouldbe, reallyis

      %w(pre exec env callcreates out gas logs postStateRoot).each do |k|
        shouldbe = params1[k]
        reallyis = stringify_possible_keys params2[k]
        if k == 'out' && shouldbe[0] == '#'
          reallyis = "##{(reallyis.size-2)/2}"
        end

        if shouldbe != reallyis
          raise "Mismatch: #{k}:\n shouldbe #{shouldbe}\n reallyis #{reallyis}"
        end
      end
    when :time
      time_post - time_pre
    end
  end

  def patch_external_call(blk)
    class <<blk
      def build_external_call(tx)
        blk = self
        apply_msg = lambda do |msg, code=nil|
          block_hash = lambda do |n|
            h = n >= blk.number || n < blk.number - 256 ?
              Ethereum::Constant::BYTE_EMPTY :
              Ethereum::Utils.keccak256(n.to_s)
            Ethereum::Utils.big_endian_to_int(h)
          end
          singleton_class.send :define_method, :block_hash, &block_hash

          super(msg, code)
        end

        super(tx).tap do |ec|
          ec.singleton_class.send :define_method, :apply_msg, &apply_msg
        end
      end
    end
  end

end
