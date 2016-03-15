# -*- encoding : ascii-8bit -*-

require 'test_helper'

class VMFixtureTest < Minitest::Test
  include Ethereum

  run_fixtures "VMTests"

  @@env = Env.new DB::EphemDB.new

  def on_fixture_test(name, data)
    check_vm_test data
  end

  def check_vm_test(params)
    run_vm_test params, :verify
  end

  # @param mode [Symbol] :fill, :verify or :time
  def run_vm_test(params, mode, profiler=nil)
    pre = params['pre']
    exec = params['exec']
    env = params['env']

    env['previousHash'] = encode_hex(@@env.config[:genesis_prevhash]) unless env.has_key?('previousHash')
    assert_equal %w(currentCoinbase currentDifficulty currentGasLimit currentNumber currentTimestamp previousHash).sort, env.keys.sort

    # setup env
    header = BlockHeader.new(
      prevhash: decode_hex(env['previousHash']),
      number: parse_int_or_hex(env['currentNumber']),
      coinbase: decode_hex(env['currentCoinbase']),
      difficulty: parse_int_or_hex(env['currentDifficulty']),
      gas_limit: parse_int_or_hex(env['currentGasLimit']),
      timestamp: parse_int_or_hex(env['currentTimestamp'])
    )
    blk = Block.new header, env: @@env

    # setup pre allocations
    pre.each do |address, h|
      assert_equal 40, address.size
      assert_equal %w(balance code nonce storage), h.keys.sort

      address = decode_hex address

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

    # execute transactions
    sender = decode_hex exec['caller']
    to = decode_hex exec['address']
    nonce = blk.get_nonce sender
    gasprice = parse_int_or_hex exec['gasPrice']
    startgas = parse_int_or_hex exec['gas']
    value = parse_int_or_hex exec['value']
    data = decode_hex exec['data'][2..-1]

    # bypass gas check in tx initialization by temporarily increasing startgas
    num_zero_bytes = data.count(Constant::BYTE_ZERO)
    num_non_zero_bytes = data.size - num_zero_bytes
    intrinsic_gas = Opcodes::GTXCOST +
      Opcodes::GTXDATAZERO*num_zero_bytes +
      Opcodes::GTXDATANONZERO*num_non_zero_bytes

    startgas += intrinsic_gas
    tx = Transaction.new nonce: nonce, gasprice: gasprice, startgas: startgas, to: to, value: value, data: data
    tx.startgas -= intrinsic_gas
    tx.sender = sender

    # capture apply_message calls
    apply_message_calls = []

    ext = get_ext_wrapper ExternalCall.new(blk, tx), apply_message_calls

    cd = VM::CallData.new(Utils.bytes_to_int_array(tx.data))
    msg = VM::Message.new tx.sender, tx.to, tx.value, tx.startgas, cd
    code = decode_hex exec['code'][2..-1]

    t1 = Time.now
    #profiler.enable if profiler # TODO
    success, gas_remained, output = VM.execute(ext, msg, code)
    #profiler.disable if profiler

    blk.commit_state
    blk.suicides.each {|s| blk.del_account(s) }
    t2 = Time.now

    # Generally expected that the test implementer will read env, exec and pre
    # then check their results against gas, logs, out, post and callcreates.
    #
    # If an exception is expected, then latter sections are absent in the test.
    # Since the reverting of the state is not part of the VM tests.

    params2 = Marshal.load Marshal.dump(params) # poorman's deep copy

    if success != 0
      params2['callcreates'] = apply_message_calls
      params2['out'] = "0x#{encode_hex Utils.int_array_to_bytes(output)}"
      params2['gas'] = gas_remained.to_s
      params2['logs'] = blk.logs.map {|l| l.to_h }
      params2['post'] = blk.to_h(with_state: true)[:state]
    end

    case mode
    when :fill
      params2
    when :verify
      assert !params.has_key?('post'), 'failed, but expected to succeed' unless success

      params1 = Marshal.load Marshal.dump(params) # poorman's deep copy
      shouldbe, reallyis = params1['post'], params2['post']
      compare_post_states shouldbe, reallyis

      %w(pre exec env callcreates out gas logs).each do |k|
        shouldbe = normalize_value k, params1
        reallyis = normalize_value k, params2
        raise "Mismatch: #{k}\n shouldbe: #{shouldbe} reallyis: #{reallyis}" if shouldbe != reallyis
      end
    when :time
      t2 - t1
    end
  end

  def get_ext_wrapper(ext, apply_message_calls)
    class <<ext
      attr_accessor :apply_message_calls

      alias :orig_apply_msg :apply_msg
      alias :orig_create :create
      alias :orig_block_hash :block_hash

      def apply_msg(msg, code=nil)
        hexdata = encode_hex msg.data.extract_all

        apply_message_calls.push(
          gasLimit: msg.gas,
          value: msg.value,
          to: encode_hex(msg.to),
          data: "0x#{hexdata}"
        )

        [1, msg.gas, Ethereum::Constant::BYTE_EMPTY]
      end

      def create(msg)
        sender = msg.sender.size == 40 ? decode_hex(msg.sender) : msg.sender
        nonce = Ethereum::Utils.encode_int @block.get_nonce(msg.sender)
        addr = Ethereum::Utils.keccak256_rlp([sender, nonce])[12..-1]
        hexdata = encode_hex msg.data.extract_all

        apply_message_calls.push(
          gasLimit: msg.gas,
          value: msg.value,
          to: Ethereum::Constant::BYTE_EMPTY,
          data: "0x#{hexdata}"
        )

        [1, msg.gas, addr]
      end

      def block_hash(n)
        if n >= block_number || n < block_number-256
          Ethereum::Constant::BYTE_EMPTY
        else
          Ethereum::Utils.keccak256 n.to_s
        end
      end
    end

    ext.apply_message_calls = apply_message_calls

    ext
  end

end
