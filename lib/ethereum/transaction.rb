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

    V_MIN = 27
    V_MAX = 28

    EIP155_V_OFFSET = 35
    EIP155_CHAIN_ID = 1
    EIP155_V_MIN = EIP155_V_OFFSET + 2 * EIP155_CHAIN_ID
    EIP155_V_MAX = EIP155_V_MIN + 1

    class <<self
      ##
      # A contract is a special transaction without the `to` argument.
      #
      def contract(nonce, gasprice, startgas, endowment, code, v=0, r=0, s=0)
        new nonce, gasprice, startgas, '', endowment, code, v, r, s
      end

      def encode_v(v, eip155=false)
        eip155 ? (v + EIP155_V_MIN) : (v + V_MIN)
      end

      def decode_v(v)
        return unless v
        if v == V_MIN || v == V_MAX
          v - V_MIN
        elsif v == EIP155_V_MIN || v == EIP155_V_MAX
          v - EIP155_V_MIN
        else
          raise InvalidTransaction, "invalid signature"
        end
      end

      def decode_chain_id(v)
        raise InvalidTransaction, "invalid chain id" if v < EIP155_V_OFFSET+2
        (v - EIP155_V_OFFSET) / 2
      end
    end

    def initialize(*args)
      fields = {v: 0, r: 0, s: 0}.merge parse_field_args(args)
      fields[:to] = Utils.normalize_address(fields[:to], allow_blank: true)

      serializable_initialize fields

      @sender = nil
      @logs = []

      raise InvalidTransaction, "Values way too high!" if [gasprice, startgas, value, nonce].max > Constant::UINT_MAX
      raise InvalidTransaction, "Startgas too low" if startgas < intrinsic_gas_used

      logger.debug "deserialized tx #{Utils.encode_hex(full_hash)[0,8]}"
    end

    def sender
      unless @sender
        v = Transaction.decode_v(self.v)
        if v
          raise InvalidTransaction, "Invalid signature values!" if r >= Secp256k1::N || s >= Secp256k1::N || v > 1 || r == 0 || s == 0

          logger.debug "recovering sender"
          rawhash = Utils.keccak256 signing_data(:verify)

          pub = nil
          begin
            pub = Secp256k1.recover_pubkey rawhash, [v,r,s]
          rescue
            raise InvalidTransaction, "Invalid signature values (x^3+7 is non-residue)"
          end

          raise InvalidTransaction, "Invalid signature (zero privkey cannot sign)" if pub[1..-1] == Constant::PUBKEY_ZERO

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
    def sign(key, eip155=false)
      raise InvalidTransaction, "Zero privkey cannot sign" if [0, '', Constant::PRIVKEY_ZERO, Constant::PRIVKEY_ZERO_HEX].include?(key)

      rawhash = Utils.keccak256 signing_data(:sign)
      key = PrivateKey.new(key).encode(:bin)

      vrs = Secp256k1.recoverable_sign rawhash, key
      self.v = Transaction.encode_v(vrs[0], eip155)
      self.r = vrs[1]
      self.s = vrs[2]

      self.sender = PrivateKey.new(key).to_address

      self
    end

    ##
    # This method should be called for block numbers >=
    # config[:homestead_fork_blknum] only. The >= operator is replaced by >
    # because the integer division N/2 always produces the value which is by
    # 0.5 less than the real N/2.
    #
    def check_low_s
      raise InvalidTransaction, "Invalid signature S value!" if s > Secp256k1::N/2 || s == 0
    end

    def signing_data(mode)
      case mode
      when :sign
        if v == 0 # use encoding rules before EIP155
          RLP.encode(self, sedes: UnsignedTransaction)
        elsif v == EIP155_CHAIN_ID && r == 0 && s == 0 # after EIP155, v is chain_id >= 1
          RLP.encode(self, sedes: Transaction)
        else
          raise InvalidTransaction, "invalid signature"
        end
      when :verify
        if v == V_MIN || v == V_MAX # encoded v before EIP155
          RLP.encode(self, sedes: UnsignedTransaction)
        elsif v == EIP155_V_MIN || v == EIP155_V_MAX # after EIP155, v with chain_id encoded in it
          values = UnsignedTransaction.serializable_fields.keys.map {|k| send k }
          values += [EIP155_CHAIN_ID, 0, 0]
          RLP.encode(values, sedes: Transaction.serializable_sedes)
        end
      else
        raise InvalidTransaction, "invalid signature"
      end
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
      Utils.mk_contract_address(sender, nonce) if [Address::BLANK, Address::ZERO].include?(to)
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
