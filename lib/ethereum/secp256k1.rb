# -*- encoding : ascii-8bit -*-

require 'base64'
require 'secp256k1'

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

    class InvalidPrivateKey < StandardError; end

    class <<self # extensions
      def priv_to_pub(priv)
        priv = PrivateKey.new(priv)
        privkey = ::Secp256k1::PrivateKey.new privkey: priv.encode(:bin), raw: true
        pubkey = privkey.pubkey
        PublicKey.new(pubkey.serialize).encode(priv.format)
      end

      def recoverable_sign(msg, privkey)
        pk = ::Secp256k1::PrivateKey.new privkey: privkey, raw: true
        signature = pk.ecdsa_recoverable_serialize pk.ecdsa_sign_recoverable(msg, raw: true)

        v = signature[1]
        r = Utils.big_endian_to_int signature[0][0,32]
        s = Utils.big_endian_to_int signature[0][32,32]

        [v,r,s]
      end

      def signature_verify(msg, vrs, pubkey)
        pk = ::Secp256k1::PublicKey.new(pubkey: pubkey)
        raw_sig = Utils.zpad_int(vrs[1]) + Utils.zpad_int(vrs[2])

        sig = ::Secp256k1::C::ECDSASignature.new
        sig[:data].to_ptr.write_bytes(raw_sig)

        pk.ecdsa_verify(msg, sig)
      end

      def recover_pubkey(msg, vrs, compressed: false)
        pk = ::Secp256k1::PublicKey.new(flags: ::Secp256k1::ALL_FLAGS)
        sig = Utils.zpad_int(vrs[1]) + Utils.zpad_int(vrs[2])
        recsig = pk.ecdsa_recoverable_deserialize(sig, vrs[0])
        pk.public_key = pk.ecdsa_recover msg, recsig, raw: true
        pk.serialize compressed: compressed
      end
    end
  end
end
