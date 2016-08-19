# -*- encoding : ascii-8bit -*-

$:.unshift File.expand_path('../../lib', __FILE__)

require 'minitest/autorun'
require 'ethereum'
require 'json'

Logging.logger.root.level = :error

CONTRACTS_DIR = File.expand_path '../contracts', __FILE__

def fixture_root
  File.expand_path('../../fixtures', __FILE__)
end

def fixture_path(path)
  File.join fixture_root, path
end

def load_fixture(path)
  fixture = {}
  name = path.gsub(/(^\/)|(\.json$)/, '').tr('/', '_')

  json = File.open(fixture_path(path)) {|f| JSON.load f }
  json.each do |k, v|
    fixture["#{name}_#{k}"] = v
  end

  to_bytes fixture
end

def to_bytes(obj)
  case obj
  when String
    obj
  when Array
    obj.map {|x| to_bytes(x) }
  when Hash
    h = {}
    obj.each do |k, v|
      k = k if k.instance_of?(String) && (k.size == 40 || k[0,2] == '0x')
      h[k] = to_bytes(v)
    end
    h
  else
    obj
  end
end

def remove_0x_head(s)
  s[0,2] == '0x' ? s[2..-1] : s
end

def encode_hex(s)
  RLP::Utils.encode_hex s
end

def decode_hex(x)
  if x.instance_of?(String)
    RLP::Utils.decode_hex(x[0,2] == '0x' ? x[2..-1] : x)
  else
    x
  end
end

def decode_uint(x)
  if x.instance_of?(String)
    (x[0,2] == '0x' ? x[2..-1] : x).to_i(16)
  else
    x
  end
end

def normalize_hex(s)
  s.size > 2 ? s : '0x00'
end

def normalize_value(k, p)
  if p.has_key?(k)
    if k == :gas
      parse_int_or_hex(p[k])
    elsif k == :callcreates
      p[k].map {|c| callcreate_standard_form c }
    else
      k.to_s
    end
  end

  return nil
end

def parse_int_or_hex(s)
  Ethereum::Utils.parse_int_or_hex s
end

def compare_post_states(shouldbe, reallyis)
  return true if shouldbe.nil? && reallyis.nil?

  raise "state mismatch! shouldbe: #{shouldbe} reallyis: #{reallyis}" if shouldbe.nil? || reallyis.nil?

  shouldbe.each do |k, v|
    if !reallyis.has_key?(k)
      r = {nonce: 0, balance: 0, code: '0x', storage: {}}
    else
      r = acct_standard_form reallyis[k]
    end
    s = acct_standard_form shouldbe[k]

    raise "key #{k} state mismatch! shouldbe: #{s} reallyis: #{r}" if s != r
  end

  true
end

def acct_standard_form(a)
  a = symbolize_keys a

  storage = a[:storage]
    .map {|k,v| [normalize_hex(k), normalize_hex(v)] }
    .select {|(k,v)| v !~ /\A0x0*\z/ }
    .to_h

  { balance: parse_int_or_hex(a[:balance]),
    nonce: parse_int_or_hex(a[:nonce]),
    code: a[:code],
    storage: storage }
end

def symbolize_keys(h)
  h.map {|k,v| [k.to_sym, v] }.to_h
end

def stringify_possible_keys(obj)
  case obj
  when Array
    obj.map {|x| stringify_possible_keys x }
  when Hash
    obj.map {|k,v| [k.to_s, v] }.to_h
  else
    obj
  end
end

module Scanner
  extend self

  def bin(v)
    decode_hex(v)
  end
  alias :trie_root :bin

  def addr(v)
    v[0,2] == '0x' ? v[2..-1] : v
  end

  def int(v)
    v[0,2] == '0x' ? int256b(v[2..-1]) : v.to_i
  end

  def int256b(v)
    Ethereum::Utils.big_endian_to_int Ethereum::Utils.decode_hex(v)
  end

end

module VMTest
  include Ethereum

  def self.included(base)
    class <<base
      def env
        @env ||= Ethereum::Env.new Ethereum::DB::EphemDB.new
      end
    end
  end

  def check_vm_test(params)
    run_vm_test params, :verify
  end

  # @param mode [Symbol] :fill, :verify or :time
  def run_vm_test(params, mode, profiler=nil)
    pre = params['pre']
    exec = params['exec']
    env = params['env']

    env['previousHash'] = encode_hex(self.class.env.config[:genesis_prevhash]) unless env.has_key?('previousHash')
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
    blk = Block.new header, env: self.class.env

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

class Minitest::Test
  class <<self
    def run_fixture(path, limit: nil, except: nil, only: nil)
      fixture = load_fixture(path).to_a
      fixture = fixture[0,limit] if limit

      fixture.each do |name, pairs|
        break if fixture_limit > 0 && fixture_loaded.size >= fixture_limit
        next if except && name =~ except
        next if only && name !~ only
        fixture_loaded.push name

        define_method("test_fixture_#{name}") do
          on_fixture_test name, pairs
        end
      end
    end

    def run_fixtures(path, except: nil, only: nil, options: {})
      Dir[fixture_path("#{path}/**/*.json")].each do |file_path|
        next if except && file_path =~ except
        next if only && file_path !~ only
        run_fixture file_path.sub(fixture_root, ''), **options
      end
    end

    def set_fixture_limit(limit)
      @limit = limit
    end

    def fixture_limit
      @limit ||= 0
    end

    def fixture_loaded
      @loaded ||= []
    end
  end

  def on_fixture_test(name, pairs)
    raise NotImplementedError, "override this method to customize fixture testing"
  end
end
