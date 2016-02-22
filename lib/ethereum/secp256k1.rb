# -*- encoding : ascii-8bit -*-

require 'bitcoin'

module Bitcoin
  module Secp256k1

    # monkey patch init to load system installed libsecp256k1
    def self.init
      return if @loaded
      lib_path = ENV['SECP256K1_LIB_PATH'] || 'libsecp256k1'
      ffi_load_functions(lib_path)
      @loaded = true
    end

  end
end

module Ethereum
  module Secp256k1

    # Elliptic curve parameters
    P  = 2**256 - 2**32 - 977
    N  = 115792089237316195423570985008687907852837564279074904382605163141518161494337
    A  = 0
    B  = 7
    Gx = 55066263022277343669578718895168534326250603453777594175500187360389116729240
    Gy = 32670510020758816978083085130507043184471273380659243275938904335757337482424
    G  = [Gx, Gy].freeze

    PUBKEY_ZERO = [0,0].freeze

  end
end
