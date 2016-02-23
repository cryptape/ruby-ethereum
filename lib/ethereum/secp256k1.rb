# -*- encoding : ascii-8bit -*-

require 'base64'
require 'ffi'

module Ethereum

  ##
  # bindings for secp256k1 inside bitcoin
  # tag: v0.11.2
  #
  # @see https://github.com/lian/bitcoin-ruby/blob/master/lib/bitcoin/ffi/secp256k1.rb
  #
  module Secp256k1 # original
    extend FFI::Library

    SECP256K1_START_VERIFY = (1 << 0)
    SECP256K1_START_SIGN   = (1 << 1)

    def self.ffi_load_functions(file)
      class_eval <<-RUBY
        ffi_lib [ %[#{file}] ]

        ##
        # source: https://github.com/bitcoin/bitcoin/blob/v0.11.0/src/secp256k1/include/secp256k1.h
        ##

        # secp256k1_context_t* secp256k1_context_create(int flags)
        attach_function :secp256k1_context_create, [:int], :pointer

        # secp256k1_context_t* secp256k1_context_clone(const secp256k1_context_t* ctx)
        attach_function :secp256k1_context_clone, [:pointer], :pointer

        # void secp256k1_context_destroy(secp256k1_context_t* ctx)
        attach_function :secp256k1_context_destroy, [:pointer], :void

        # int secp256k1_ecdsa_verify(const secp256k1_context_t* ctx, const unsigned char *msg32, const unsigned char *sig, int siglen, const unsigned char *pubkey, int pubkeylen)
        attach_function :secp256k1_ecdsa_verify, [:pointer, :pointer, :pointer, :int, :pointer, :int], :int

        # int secp256k1_ecdsa_sign(const secp256k1_context_t* ctx, const unsigned char *msg32, unsigned char *sig, int *siglen, const unsigned char *seckey, secp256k1_nonce_function_t noncefp, const void *ndata)
        attach_function :secp256k1_ecdsa_sign, [:pointer, :pointer, :pointer, :pointer, :pointer, :pointer, :pointer], :int

        # int secp256k1_ecdsa_sign_compact(const secp256k1_context_t* ctx, const unsigned char *msg32, unsigned char *sig64, const unsigned char *seckey, secp256k1_nonce_function_t noncefp, const void *ndata, int *recid)
        attach_function :secp256k1_ecdsa_sign_compact, [:pointer, :pointer, :pointer, :pointer, :pointer, :pointer, :pointer], :int

        # int secp256k1_ecdsa_recover_compact(const secp256k1_context_t* ctx, const unsigned char *msg32, const unsigned char *sig64, unsigned char *pubkey, int *pubkeylen, int compressed, int recid)
        attach_function :secp256k1_ecdsa_recover_compact, [:pointer, :pointer, :pointer, :pointer, :pointer, :int, :int], :int

        # int secp256k1_ec_seckey_verify(const secp256k1_context_t* ctx, const unsigned char *seckey)
        attach_function :secp256k1_ec_seckey_verify, [:pointer, :pointer], :int

        # int secp256k1_ec_pubkey_verify(const secp256k1_context_t* ctx, const unsigned char *pubkey, int pubkeylen)
        attach_function :secp256k1_ec_pubkey_verify, [:pointer, :pointer, :int], :int

        # int secp256k1_ec_pubkey_create(const secp256k1_context_t* ctx, unsigned char *pubkey, int *pubkeylen, const unsigned char *seckey, int compressed)
        attach_function :secp256k1_ec_pubkey_create, [:pointer, :pointer, :pointer, :pointer, :int], :int

        # int secp256k1_ec_pubkey_decompress(const secp256k1_context_t* ctx, unsigned char *pubkey, int *pubkeylen)
        attach_function :secp256k1_ec_pubkey_decompress, [:pointer, :pointer, :pointer], :int

        # int secp256k1_ec_privkey_export(const secp256k1_context_t* ctx, const unsigned char *seckey, unsigned char *privkey, int *privkeylen, int compressed)
        attach_function :secp256k1_ec_privkey_export, [:pointer, :pointer, :pointer, :pointer, :int], :int

        # int secp256k1_ec_privkey_import(const secp256k1_context_t* ctx, unsigned char *seckey, const unsigned char *privkey, int privkeylen)
        attach_function :secp256k1_ec_privkey_import, [:pointer, :pointer, :pointer, :pointer], :int

        # int secp256k1_ec_privkey_tweak_add(const secp256k1_context_t* ctx, unsigned char *seckey, const unsigned char *tweak)
        attach_function :secp256k1_ec_privkey_tweak_add, [:pointer, :pointer, :pointer], :int

        # int secp256k1_ec_pubkey_tweak_add(const secp256k1_context_t* ctx, unsigned char *pubkey, int pubkeylen, const unsigned char *tweak)
        attach_function :secp256k1_ec_pubkey_tweak_add, [:pointer, :pointer, :int, :pointer], :int

        # int secp256k1_ec_privkey_tweak_mul(const secp256k1_context_t* ctx, unsigned char *seckey, const unsigned char *tweak)
        attach_function :secp256k1_ec_privkey_tweak_mul, [:pointer, :pointer, :pointer], :int

        # int secp256k1_ec_pubkey_tweak_mul(const secp256k1_context_t* ctx, unsigned char *pubkey, int pubkeylen, const unsigned char *tweak)
        attach_function :secp256k1_ec_pubkey_tweak_mul, [:pointer, :pointer, :int, :pointer], :int

        # int secp256k1_context_randomize(secp256k1_context_t* ctx, const unsigned char *seed32)
        attach_function :secp256k1_context_randomize, [:pointer, :pointer], :int
      RUBY
    end

    def self.init
      return if @loaded
      lib_path = ENV['SECP256K1_LIB_PATH'] || 'libsecp256k1'
      ffi_load_functions(lib_path)
      @loaded = true
    end

    def self.with_context(flags=nil, seed=nil)
      init
      flags = flags || (SECP256K1_START_VERIFY | SECP256K1_START_SIGN )
      context = secp256k1_context_create(flags)

      ret, tries, max = 0, 0, 20
      while ret != 1
        raise "secp256k1_context_randomize failed." if tries >= max
        tries += 1
        ret = secp256k1_context_randomize(context, FFI::MemoryPointer.from_string(seed || SecureRandom.random_bytes(32)))
      end

      yield(context) if block_given?
    ensure
      secp256k1_context_destroy(context)
    end

    def self.generate_key_pair(compressed=true)
      with_context do |context|

        ret, tries, max = 0, 0, 20
        while ret != 1
          raise "secp256k1_ec_seckey_verify in generate_key_pair failed." if tries >= max
          tries += 1

          priv_key = FFI::MemoryPointer.new(:uchar, 32).put_bytes(0, SecureRandom.random_bytes(32))
          ret = secp256k1_ec_seckey_verify(context, priv_key)
        end

        pub_key, pub_key_length = FFI::MemoryPointer.new(:uchar, 65), FFI::MemoryPointer.new(:int)
        result = secp256k1_ec_pubkey_create(context, pub_key, pub_key_length, priv_key, compressed ? 1 : 0)
        raise "error creating pubkey" unless result

        [ priv_key.read_string(32), pub_key.read_string(pub_key_length.read_int) ]
      end
    end

    def self.sign(data, priv_key)
      with_context do |context|
        msg32 = FFI::MemoryPointer.new(:uchar, 32).put_bytes(0, data)
        seckey = FFI::MemoryPointer.new(:uchar, priv_key.bytesize).put_bytes(0, priv_key)
        raise "priv_key invalid" unless secp256k1_ec_seckey_verify(context, seckey)

        sig, siglen = FFI::MemoryPointer.new(:uchar, 72), FFI::MemoryPointer.new(:int).write_int(72)

        while true do
          break if secp256k1_ecdsa_sign(context, msg32, sig, siglen, seckey, nil, nil)
        end

        sig.read_string(siglen.read_int)
      end
    end

    def self.verify(data, signature, pub_key)
      with_context do |context|
        data_buf = FFI::MemoryPointer.new(:uchar, 32).put_bytes(0, data)
        sig_buf  = FFI::MemoryPointer.new(:uchar, signature.bytesize).put_bytes(0, signature)
        pub_buf  = FFI::MemoryPointer.new(:uchar, pub_key.bytesize).put_bytes(0, pub_key)

        result = secp256k1_ecdsa_verify(context, data_buf, sig_buf, sig_buf.size, pub_buf, pub_buf.size)

        case result
        when  0; false
        when  1; true
        when -1; raise "error invalid pubkey"
        when -2; raise "error invalid signature"
        else   ; raise "error invalid result"
        end
      end
    end

    def self.sign_compact(message, priv_key, compressed=true)
      with_context do |context|
        msg32 = FFI::MemoryPointer.new(:uchar, 32).put_bytes(0, message)
        sig64 = FFI::MemoryPointer.new(:uchar, 64)
        rec_id = FFI::MemoryPointer.new(:int)

        seckey = FFI::MemoryPointer.new(:uchar, priv_key.bytesize).put_bytes(0, priv_key)
        raise "priv_key invalid" unless secp256k1_ec_seckey_verify(context, seckey)

        while true do
          break if secp256k1_ecdsa_sign_compact(context, msg32, sig64, seckey, nil, nil, rec_id)
        end

        header = [27 + rec_id.read_int + (compressed ? 4 : 0)].pack("C")
        [ header, sig64.read_string(64) ].join
      end
    end

    def self.recover_compact(message, signature)
      with_context do |context|
        return nil if signature.bytesize != 65

        version = signature.unpack('C')[0]
        return nil if version < 27 || version > 34

        compressed = version >= 31 ? true : false
        version -= 4 if compressed

        recid = version - 27
        msg32 = FFI::MemoryPointer.new(:uchar, 32).put_bytes(0, message)
        sig64 = FFI::MemoryPointer.new(:uchar, 64).put_bytes(0, signature[1..-1])
        pubkey = FFI::MemoryPointer.new(:uchar, pub_key_len = compressed ? 33 : 65)
        pubkeylen = FFI::MemoryPointer.new(:int).write_int(pub_key_len)

        result = secp256k1_ecdsa_recover_compact(context, msg32, sig64, pubkey, pubkeylen, (compressed ? 1 : 0), recid)

        return nil unless result

        pubkey.read_bytes(pubkeylen.read_int)
      end
    end
  end



  module Secp256k1 # continue, extensions

    # Elliptic curve parameters
    P  = 2**256 - 2**32 - 977
    N  = 115792089237316195423570985008687907852837564279074904382605163141518161494337
    A  = 0
    B  = 7
    Gx = 55066263022277343669578718895168534326250603453777594175500187360389116729240
    Gy = 32670510020758816978083085130507043184471273380659243275938904335757337482424
    G  = [Gx, Gy].freeze

    PUBKEY_ZERO = [0,0].freeze

    class <<self
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
        recover_compact Utils.zpad(msghash, 32), sig
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
