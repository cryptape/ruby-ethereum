# -*- encoding : ascii-8bit -*-

module Ethereum
  class SpecialContract

    class ECRecover
      def call(ext, msg)
        gas_cost = Opcodes::GECRECOVER
        return 0, 0, [] if msg.gas < gas_cost

        b = []
        msg.data.extract_copy(b, 0, 0, 32)

        h = Utils.int_array_to_bytes b
        v = msg.data.extract32(32)
        r = msg.data.extract32(64)
        s = msg.data.extract32(96)

        if r >= Secp256k1::N || s >= Secp256k1::N || v < 27 || v > 28
          return 1, msg.gas - gas_cost, []
        end

        recovered_addr = Secp256k1.ecdsa_raw_recover(h, [v,r,s]) rescue nil
        if recovered_addr.false? || recovered_addr == [0,0]
          return 1, msg.gas - gas_cost, []
        end

        pub = PublicKey.new(recovered_addr).encode(:bin)
        pubhash = Utils.keccak256(pub[1..-1])[-Constant::ADDR_BASE_BYTES..-1]
        o = Utils.bytes_to_int_array Utils.zpad(pubhash, 32)

        return 1, msg.gas - gas_cost, o
      end
    end

    class ECAdd
      def call(ext, msg)
        gas_cost = Opcodes::GECADD
        return 0, 0, [] if msg.gas < gas_cost

        x1 = msg.data.extract32 0
        y1 = msg.data.extract32 32
        x2 = msg.data.extract32 64
        y2 = msg.data.extract32 96

        # check point is on curve
        return 0, 0, [] if (x1*x1*x1+7-y1*y1) % Secp256k1::P != 0
        return 0, 0, [] if (x2*x2*x2+7-y2*y2) % Secp256k1::P != 0

        c, d = Jacobian.fast_add([x1,y1], [x2,y2])
        data = "#{Utils.zpad_int(c)}#{Utils.zpad_int(d)}"

        return 1, msg.gas - gas_cost, Utils.bytes_to_int_array(data)
      end
    end

    class ECMul
      def call(ext, msg)
        gas_cost = Opcodes::GECMUL
        return 0, 0, [] if msg.gas < gas_cost

        x1 = msg.data.extract32 0
        y1 = msg.data.extract32 32
        n  = msg.data.extract32 64

        return 0, 0, [] if (x1*x1*x1+7-y1*y1) % Secp256k1::P != 0

        c, d = Jacobian.fast_mul([x1,y1], n)
        data = "#{Utils.zpad_int(c)}#{Utils.zpad_int(d)}"

        return 1, msg.gas - gas_cost, Utils.bytes_to_int_array(data)
      end
    end

    class ModExp
      def call(ext, msg)
        gas_cost = Opcodes::GMODEXP
        return 0, 0, [] if msg.gas < gas_cost

        b = msg.data.extract32(0)
        e = msg.data.extract32(32)
        m = msg.data.extract32(64)

        result = Utils.zpad_int Utils.mod_exp(b, e, m)
        return 1, msg.gas - gas_cost, Utils.bytes_to_int_array(result)
      end
    end

    class SHA256
      def call(ext, msg)
        gas_cost = Opcodes::GSHA256BASE +
          (Utils.ceil32(msg.data.size) / 32) * Opcodes::GSHA256WORD
        return 0, 0, [] if msg.gas < gas_cost

        d = msg.data.extract_all
        o = Utils.bytes_to_int_array Utils.sha256(d)

        return 1, msg.gas - gas_cost, o
      end
    end

    class RIPEMD160
      def call(ext, msg)
        gas_cost = Opcodes::GRIPEMD160BASE +
          (Utils.ceil32(msg.data.size) / 32) * Opcodes::GRIPEMD160WORD
        return 0, 0, [] if msg.gas < gas_cost

        d = msg.data.extract_all
        o = Utils.bytes_to_int_array Utils.zpad(Utils.ripemd160(d), 32)

        return 1, msg.gas - gas_cost, o
      end
    end

    class Identity
      def call(ext, msg)
        gas_cost = Opcodes::GIDENTITYBASE +
          (Utils.ceil32(msg.data.size) / 32) * Opcodes::GIDENTITYWORD
        return 0, 0, [] if msg.gas < gas_cost

        o = []
        msg.data.extract_copy(o, 0, 0, msg.data.size)

        return 1, msg.gas - gas_cost, o
      end
    end

    class SendEther
      def call(ext, msg)
        gas_cost = Opcodes::GCALLVALUETRANSFER
        return 0, 0, [] if msg.gas < gas_cost

        sender_ether = Utils.match_shard Config::ETHER, msg.sender
        to_ether = Utils.match_shard Config::ETHER, msg.to

        to = Utils.int_to_addr(msg.data.extract32(0) % (2 << Constant::ADDR_BASE_BYTES*8))
        value = msg.data.extract32 32

        prebal = Utils.big_endian_to_int ext.get_storage(sender_ether, msg.sender)
        if prebal >= value
          tobal = Utils.big_endian_to_int ext.get_storage(to_ether, to)
          ext.set_storage to_ether, to, tobal+value
          ext.set_storage sender_ether, sender, prebal-value

          return 1, msg.gas - gas_cost, Utils.bytes_to_int_array(Utils.zpad_int(1))
        else
          return 1, msg.gas - gas_cost, Utils.bytes_to_int_array(Utils.zpad_int(0))
        end
      end
    end

    class Log
      def call(ext, msg)
        c_log = Utils.shardify Config::LOG, msg.left_bound
        c_exstate = Utils.shardify Config::EXECUTION_STATE, msg.left_bound

        data = msg.data.extract_all
        topics = 4.times.map {|i| data[i*32, 32] }
        non_empty_topics = topics.select {|t| t }

        gas_cost = Opcodes::GLOGBYTE * [data.size - 128, 0].max +
          Opcodes::GLOGBASE + non_empty_topics.size * Opcodes::GLOGTOPIC
        return 0, 0, [] if msg.gas < gas_cost

        bloom = Utils.big_endian_to_int(ext.get_storage(c_log, Constant::BLOOM))
        topics.each do |t|
          next unless t

          t += "\x00" * (32 - t.size)
          h = Utils.keccak256 t
          5.times {|i| bloom |= 2**h[i].ord }
        end

        ext.set_storage c_log, Constant::BLOOM, Utils.zpad_int(bloom)

        txindex = Utils.zpad ext.get_storage(c_exstate, Constant::TXINDEX), 32
        old_storage = ext.get_storage c_log, txindex
        new_storage = RLP.append old_storage, data
        ext.set_storage c_log, txindex, new_storage

        ext.listeners.each do |l|
          l.call msg.sender, topics.map {|t| Utils.big_endian_to_int(t) }, data[128..-1]
        end

        return 1, msg.gas - gas_cost, [0]*32
      end
    end

    class RLPGet
      def call(ext, msg, output_string=false)
        gas_cost = Opcodes::GRLPBASE +
          (Utils.ceil32(msg.data.size) / 32) * Opcodes::GRLPWORD
        return 0, 0, [] if msg.gas < gas_cost

        data = msg.data.extract_all
        rlpdata = RLP.decode data[32..-1]
        index = Utils.big_endian_to_int data[0, 32]
        raise AssertError, 'target must be string' unless rlpdata[index].instance_of?(String)

        if output_string
          result = Utils.zpad_int(rlpdata[index].size) + rlpdata[index]
        else
          raise AssertError, "cannot return string longer than 32 bytes" unless rlpdata[index].size <= 32
          result = Utils.zpad rlpdata[index], 32
        end

        return 1, msg.gas - gas_cost, Utils.bytes_to_int_array(result)
      rescue
        return 0, 0, []
      end
    end

    class RLPGetBytes32
      def call(ext, msg)
        RPLGet.new.call(ext, msg, false)
      end
    end

    class RLPGetString
      def call(ext, msg)
        RLPGet.new.call(ext, msg, true)
      end
    end

    class Create
      def call(ext, msg)
        gas_cost = Opcodes::GCREATE
        return 0, 0, [] if msg.gas < gas_cost

        code = msg.data.extract_all
        addr = Utils.mk_contract_address sender: msg.sender, code: code, left_bound: msg.left_bound
        exec_gas = msg.gas - gas_cost

        if ext.get_storage(addr, Trie::BLANK_NODE).false?
          cd = FastVM::CallData.new [], 0, 0
          message = FastVM::Message.new Config::NULL_SENDER, addr, msg.value, exec_gas, cd, left_bound: msg.left_bound, right_bound: msg.right_bound

          result, execution_start_gas, data = ext.apply_msg message, code
          return 0, 0, [] if result == 0

          code = Utils.int_array_to_bytes data
          ext.puthashdata code
          ext.set_storage addr, Trie::BLANK_NODE, Utils.keccak256(code)

          return 1, execution_start_gas, Utils.bytes_to_int_array(Utils.zpad(addr, 32))
        else
          return 0, 0, []
        end
      end
    end

    class GasDeposit
      def call(ext, msg)
        gas_cost = Opcodes::GGASDEPOSIT
        return 0, 0, [] if msg.gas < gas_cost

        bal = Utils.big_endian_to_int ext.get_storage(msg.to, msg.sender)
        if msg.value > 0
          ext.set_storage msg.to, msg.sender, bal+msg.value
          return 1, 0, []
        else
          refund = msg.data.extract32 0
          return 0, 0, [] if refund <= bal

          raise NotImplemented
        end
      end
    end

    DEPLOY = {
      1 => ECRecover.new,
      2 => SHA256.new,
      3 => RIPEMD160.new,
      4 => Identity.new,
      5 => ECAdd.new,
      6 => ECMul.new,
      7 => ModExp.new,
      8 => RLPGetBytes32.new,
      9 => RLPGetString.new,

      Utils.big_endian_to_int(Config::ETHER) => SendEther.new,
      Utils.big_endian_to_int(Config::LOG) => Log.new,
      Utils.big_endian_to_int(Config::CREATOR) => Create.new,
      Utils.big_endian_to_int(Config::GAS_DEPOSIT) => GasDeposit.new
    }.freeze

    class <<self
      def [](address)
        DEPLOY[address]
      end
    end

  end
end
