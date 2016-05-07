# -*- encoding : ascii-8bit -*-

require 'openssl'

module Ethereum
  module App

    class Keystore

      class PBKDF2
        attr :params

        def initialize
          @params = mkparam
        end

        def name
          'pbkdf2'
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
        attr :params

        def initialize
          @params = mkparams
        end

        def name
          'aes-128-ctr'
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
      end

    end

  end
end
