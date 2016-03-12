# -*- encoding : ascii-8bit -*-

module Ethereum

  ##
  # A transaction is stored as:
  #
  # `[nonce, gasprice, startgas, to, value, data, v, r, s]`
  #
  # `nonce` is the number of transactions already sent by that account, encoded
  # in binary form (eg. 0 -> "", 7 -> "\x07", 1000 -> "\x03\xd8").
  #
  # `(v,r,s)` is the raw Electrum-style signature of the transaction without
  # the signature made with the private key corresponding to the sending
  # account, with `0 <= v <= 3`. From an Electrum-style signature (65 bytes) it
  # is possible to extract the public key, and thereby the address, directly.
  #
  # A valid transaction is one where:
  #
  # 1. the signature is well-formed (ie. `0 <= v <= 3, 0 <= r < P, 0 <= s < N, 0
  # <= r < P - N if v >= 2`), and
  # 2. the sending account has enough funds to pay the fee and the value.
  #
  class Transaction
    include RLP::Sedes::Serializable

    extend Sedes
    set_serializable_fields(
      nonce: big_endian_int,

      gasprice: big_endian_int,
      startgas: big_endian_int,

      to: address,
      value: big_endian_int,
      data: binary,

      v: big_endian_int,
      r: big_endian_int,
      s: big_endian_int
    )

    class <<self
      ##
      # A contract is a special transaction without the `to` argument.
      #
      def contract(nonce, gasprice, startgas, endowment, code, v=0, r=0, s=0)
        new nonce, gasprice, startgas, '', endowment, code, v, r, s
      end
    end

    def initialize(*args)
      fields = {v: 0, r: 0, s: 0}.merge parse_field_args(args)
      fields[:to] = Utils.normalize_address(fields[:to], allow_blank: true)

      serializable_initialize fields

      @sender = nil
      @logs = []

      raise ValidationError, "Values way too high!" if [gasprice, startgas, value, nonce].max > Constant::UINT_MAX
      raise ValidationError, "Startgas too low" if startgas < intrinsic_gas_used

      logger.debug "deserialized tx #{Utils.encode_hex(full_hash)[0,8]}"
    end

    def sender
      unless @sender
        if v && v > 0
          raise ValidationError, "Invalid signature values!" if r >= Secp256k1::N || s >= Secp256k1::N || v < 27 || v > 28 || r == 0 || s == 0

          logger.debug "recovering sender"
          rlpdata = RLP.encode(self, sedes: UnsignedTransaction)
          rawhash = Utils.keccak256 rlpdata
          pub = Secp256k1.ecdsa_raw_recover rawhash, [v,r,s]

          raise ValidationError, "Invalid signature values (x^3+7 is non-residue)" unless pub
          raise ValidationError, "Invalid signature (zero privkey cannot sign)" if pub == Constant::PUBKEY_ZERO

          @sender = PublicKey.new(pub).to_address
        end
      end

      @sender
    end

    def sender=(v)
      @sender = v
    end

    ##
    # Sign this transaction with a private key.
    #
    # A potentially already existing signature would be override.
    #
    def sign(key)
      raise ValidationError, "Zero privkey cannot sign" if [0, '', Constant::PRIVKEY_ZERO].include?(key)

      rawhash = Utils.keccak256 RLP.encode(self, sedes: UnsignedTransaction)
      self.v, self.r, self.s = Secp256k1.ecdsa_raw_sign rawhash, key
      self.sender = PrivateKey.new(key).to_address

      self
    end

    def full_hash
      Utils.keccak256_rlp self
    end

    def log_bloom
      bloomables = @logs.map {|l| l.bloomables }
      Bloom.from_array bloomables.flatten
    end

    def log_bloom_b256
      Bloom.b256 log_bloom
    end

    def intrinsic_gas_used
      num_zero_bytes = data.count(Constant::BYTE_ZERO)
      num_non_zero_bytes = data.size - num_zero_bytes

      Opcodes::GTXCOST +
        Opcodes::GTXDATAZERO*num_zero_bytes +
        Opcodes::GTXDATANONZERO*num_non_zero_bytes
    end

    def to_h
      h = {}
      self.class.serializable_fields.keys.each do |field|
        h[field] = send field
      end

      h[:sender] = sender
      h[:hash] = Utils.encode_hex full_hash
      h
    end

    def log_dict
      h = to_h
      h[:sender] = Utils.encode_hex(h[:sender] || '')
      h[:to] = Utils.encode_hex(h[:to])
      h
    end

    ##
    # returns the address of a contract created by this tx
    #
    def creates
      Contract.make_address(sender, nonce) if [Address::BLANK, Address::ZERO].include?(to)
    end

    def ==(other)
      other.instance_of?(self.class) && full_hash == other.full_hash
    end

    def hash
      Utils.big_endian_to_int full_hash
    end

    def to_s
      "#<#{self.class.name}:#{object_id} #{Utils.encode_hex(full_hash)[0,8]}"
    end

    private

    def logger
      @logger ||= Logger.new 'eth.chain.tx'
    end

  end

  UnsignedTransaction = Transaction.exclude %i(v r s)

end
