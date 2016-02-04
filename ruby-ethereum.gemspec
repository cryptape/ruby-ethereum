$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "ethereum/version"

# Describe your gem and declare its dependencies:
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

  s.add_dependency('rlp', ['~> 0.5.0'])

  s.add_development_dependency('rake', ['~> 10.5.0'])
  s.add_development_dependency('minitest', '5.8.3')
  s.add_development_dependency('yard', '0.8.7.6')
end
