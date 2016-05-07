# -*- encoding : ascii-8bit -*-

require 'test_helper'

class AppKeystoreTest < Minitest::Test
  include Ethereum

  def test_make_json
    json = App::Keystore.make_json("\x01"*32, 'ethereum')
    assert_equal 'aes-128-ctr', json[:crypto][:cipher]
    assert_equal 'pbkdf2', json[:crypto][:kdf]
  end

  def test_decode_json
    jsondata = App::Keystore.make_json("\x02"*32, 'bitcoin')
    assert_equal "\x02"*32, App::Keystore.decode_json(jsondata, 'bitcoin')

    # pyethapp generated json
    jsondata = JSON.parse(<<-EOF)
      {
        "crypto": {
          "cipher": "aes-128-ctr",
          "cipherparams": {"iv": "748e346f07726241bf790755d81d5bcf"},
          "ciphertext": "a6152a7bb372b3546b5b276ee0b9db075b0ac555a542934572af2ef637ca13db",
          "kdf": "pbkdf2",
          "kdfparams": {
            "c": 262144,
            "dklen": 32,
            "prf": "hmac-sha256",
            "salt": "b65f229ef1416ffa255a382544c67c8c"
          },
          "mac": "9f6e86761ce04a0b613a4ebc9edb35bd8ec0bf40f2062a5eff9361d67e63f75c",
          "version": 1
        },
        "id": "e476a1ad-5d8f-734f-fe43-a93e0f210f09",
        "version": 3
      }
    EOF

    assert_equal "\x01"*32, App::Keystore.decode_json(jsondata, 'ethereum')
  end

end
