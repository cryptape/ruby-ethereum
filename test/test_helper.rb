# -*- encoding : ascii-8bit -*-

$:.unshift File.expand_path('../../lib', __FILE__)

require 'pry-byebug'
require 'minitest/autorun'
require 'ethereum'
require 'json'

Logging.logger.root.level = :error

def fixture_root
  File.expand_path('../../fixtures', __FILE__)
end

def fixture_path(path)
  File.join fixture_root, path
end

def load_fixture(path)
  fixture = {}
  name = File.basename(path).sub(/#{File.extname(path)}\z/, '')

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

# some hex string in fixtures miss leading 0
def normalize_hex_without_prefix(s)
  if s[0,2] == '0x'
    (s.size % 2 == 1 ? '0' : '') + s[2..-1]
  else
    s
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
  if s.is_a?(Numeric)
    s
  elsif s[0,2] == '0x'
    Ethereum::Utils.big_endian_to_int decode_hex(normalize_hex_without_prefix(s))
  else
    s.to_i
  end
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
