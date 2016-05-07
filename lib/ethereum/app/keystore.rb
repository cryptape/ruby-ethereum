# -*- encoding : ascii-8bit -*-

require 'openssl'

module Ethereum
  module App

    class Keystore

      class PBKDF2
        attr :name, :params

        def initialize(params=nil)
          @name = 'pbkdf2'
          @params = params || mkparams
        end

        def eval(pw)
          OpenSSL::PKCS5.pbkdf2_hmac(
            pw,
            App::Utils.decode_hex(params[:salt]),
            params[:c],
            params[:dklen],
            'SHA256'
          )
        end

        def mkparams
          { prf: 'hmac-sha256',
            dklen: 32,
            c: 262144,
            salt: App::Utils.encode_hex(SecureRandom.random_bytes(16)) }
        end
      end

      class AES128CTR
        attr :name, :params

        def initialize(params=nil)
          @name = 'aes-128-ctr'
          @params = params || mkparams
        end

        def encrypt(text, key)
          cipher = OpenSSL::Cipher.new name
          cipher.encrypt
          cipher.key = key
          cipher.iv = App::Utils.decode_hex(params[:iv])
          cipher.update(text) + cipher.final
        end

        def decrypt(text, key)
          cipher = OpenSSL::Cipher.new name
          cipher.decrypt
          cipher.key = key
          cipher.iv = App::Utils.decode_hex(params[:iv])
          cipher.update(text) + cipher.final
        end

        def mkparams
          {iv: App::Utils.encode_hex(SecureRandom.random_bytes(16))}
        end
      end

      KDF = {
        'pbkdf2' => PBKDF2
      }.freeze

      CIPHER = {
        'aes-128-ctr' => AES128CTR
      }.freeze

      class <<self

        def make_json(priv, pw, kdf=PBKDF2.new, cipher=AES128CTR.new)
          derivedkey = kdf.eval pw

          enckey = derivedkey[0,16]
          c = cipher.encrypt priv, enckey

          mac = Utils.keccak256 "#{derivedkey[16,16]}#{c}"
          uuid = SecureRandom.uuid

          {
            crypto: {
              cipher: cipher.name,
              ciphertext: Utils.encode_hex(c),
              cipherparams: cipher.params,
              kdf: kdf.name,
              kdfparams: kdf.params,
              mac: Utils.encode_hex(mac),
              version: 1
            },
            id: uuid,
            version: 3
          }
        end

        def decode_json(jsondata, pw)
          jsondata = Hashie::Mash.new jsondata

          cryptdata = jsondata.crypto || jsondata.Crypto
          raise ArgumentError, "JSON data must contain 'crypto' object" unless cryptdata

          kdfparams = cryptdata.kdfparams
          kdf = KDF[cryptdata.kdf].new kdfparams

          cipherparams = cryptdata.cipherparams
          cipher = CIPHER[cryptdata.cipher].new cipherparams

          derivedkey = kdf.eval pw
          raise ValueError, "Derived key must be at least 32 bytes long" unless derivedkey.size >= 32

          enckey = derivedkey[0,16]
          ct = Utils.decode_hex cryptdata.ciphertext
          o = cipher.decrypt ct, enckey

          mac1 = Utils.keccak256 "#{derivedkey[16,16]}#{ct}"
          mac2 = Utils.decode_hex cryptdata.mac
          raise ValueError, "MAC mismatch. Password incorrect?" unless mac1 == mac2

          o
        end

        ##
        # Check if json has the structure of a keystore file version 3.
        #
        # Note that this test is not complete, e.g. it doesn't check key
        # derivation or cipher parameters.
        #
        # @param json [Hash] data load from json file
        # @return [Bool] `true` if the data appears to be valid, otherwise
        #   `false`
        #
        def validate(json)
          return false unless json.has_key?('crypto') || json.has_key?('Crypto')
          return false unless json['version'] == 3

          crypto = json['crypto'] || json['Crypto']
          return false unless crypto.has_key?('cipher')
          return false unless crypto.has_key?('ciphertext')
          return false unless crypto.has_key?('kdf')
          return false unless crypto.has_key?('mac')

          true
        end
      end

    end

  end
end
