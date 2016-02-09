require 'minitest/autorun'
require 'ethereum'
require 'json'

def fixture_root
  File.expand_path('../../fixtures', __FILE__)
end

def fixture_path(path)
  File.join fixture_root, path
end

def fixture_json(path)
  fixture = {}
  basename = File.basename path

  json = File.open(fixture_path(path)) {|f| JSON.load f }
  json.each do |k, v|
    fixture["#{basename}_#{k}"] = v
  end

  to_bytes fixture
end

def to_bytes(obj)
  case obj
  when String
    obj.b
  when Array
    obj.map {|x| to_bytes(x) }
  when Hash
    h = {}
    obj.each do |k, v|
      k = k.b if k.instance_of?(String) && (k.size == 40 || k[0,2] == '0x')
      h[k] = to_bytes(v)
    end
    h
  else
    obj
  end
end
