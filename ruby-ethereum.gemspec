$:.push File.expand_path("../lib", __FILE__)

require "ethereum/version"

Gem::Specification.new do |s|
  s.name        = "ruby-ethereum"
  s.version     = Ethereum::VERSION
  s.authors     = ["Jan Xie"]
  s.email       = ["jan.h.xie@gmail.com"]
  s.homepage    = "https://github.com/janx/ruby-ethereum"
  s.summary     = "Core library of the Ethereum project, ruby version."
  s.description = "Ethereum's implementation in ruby."
  s.license     = 'MIT'

  s.files = Dir["{lib}/**/*"] + ["LICENSE", "README.md"]

  s.add_dependency('rlp', '0.7.2')
  s.add_dependency('devp2p', '~> 0.1')
  s.add_dependency('ethash', '~> 0.2')
  s.add_dependency('bitcoin-secp256k1', '~> 0.3')
  s.add_dependency('lru_redux', '~> 1.1')
  s.add_dependency('ffi', '~> 1.9')
  s.add_dependency('digest-sha3', '~> 1.1')
  s.add_dependency('block_logger', '~> 0.1')
  s.add_dependency('leveldb', '0.1.9')

  s.add_development_dependency('rake', '~> 10.5')
  s.add_development_dependency('minitest', '5.8.3')
  s.add_development_dependency('yard', '0.8.7.6')
  s.add_development_dependency('serpent', '~> 0.3')
  s.add_development_dependency('pry-byebug', '~> 2.0')
end
