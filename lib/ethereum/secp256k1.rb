# -*- encoding : ascii-8bit -*-

require 'base64'
require 'ethereum/ffi/bitcoin_secp256k1'
require 'ethereum/ffi/openssl'

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

    class <<self # extensions
      def ecdsa_raw_sign(msghash, priv, compact=false)
        raise ArgumentError, "private key must be 32 bytes" unless priv.size == 32

        sig = sign_compact Utils.zpad(msghash, 32), priv, compact

        v = Utils.big_endian_to_int sig[0]
        r = Utils.big_endian_to_int sig[1,32]
        s = Utils.big_endian_to_int sig[33,32]

        raise InvalidPrivateKey, "invalid private key: #{priv.inspect}" if r == 0 && s == 0

        [v,r,s]
      end

      def ecdsa_raw_verify(msghash, vrs, pub)
        v, r, s = vrs
        return false if v < 27 || v > 34

        sig = ecdsa_sig_serialize r, s
        verify(Utils.zpad(msghash, 32), sig, pub)
      end

      def ecdsa_raw_recover(msghash, vrs)
        sig = encode_signature *vrs, false
        raw = recover_compact Utils.zpad(msghash, 32), sig
        PublicKey.new(raw).value
      end

      # static int secp256k1_ecdsa_sig_serialize(
      #   unsigned char *sig, int *size, const # secp256k1_ecdsa_sig_t *a
      # )
      def ecdsa_sig_serialize(r, s)
        len = (4 + r.size + s.size).chr
        len_r = r.size.chr
        len_s = s.size.chr
        bytes_r = Utils.int_to_big_endian(r)
        bytes_s = Utils.int_to_big_endian(s)

        "\x30#{len}\x02#{len_r}#{bytes_r}\x02#{len_s}#{bytes_s}"
      end

      def encode_signature(v, r, s, base64=true)
        bytes = "#{v.chr}#{Utils.zpad_int(r)}#{Utils.zpad_int(s)}"
        base64 ? Base64.strict_encode64(bytes) : bytes
      end

      def decode_signature(sig, base64=true)
        bytes = base64 ? Base64.strict_decode64(sig) : sig
        [bytes[0].ord, Utils.big_endian_to_int(bytes[1,32]), Utils.big_endian_to_int(bytes[33,32])]
      end
    end
  end
end
