require 'rlp'

Dir[File.expand_path('../ethereum/core_ext/**/*.rb', __FILE__)].each {|path| require path }

require 'ethereum/constant'
require 'ethereum/utils'
require 'ethereum/config'
require 'ethereum/logger'

require 'ethereum/abi'
require 'ethereum/fast_rlp'
require 'ethereum/db'
require 'ethereum/trie'
require 'ethereum/transient_trie'

require 'ethereum/index'

module Ethereum
end
