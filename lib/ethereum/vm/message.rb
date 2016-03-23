# -*- encoding : ascii-8bit -*-

module Ethereum
  class VM

    class Message

      attr_accessor :sender, :to, :value, :gas, :data, :depth, :logs, :code_address, :is_create, :transfers_value

      def initialize(sender, to, value, gas, data, depth:0, code_address:nil, is_create:false, transfers_value: true)
        @sender = sender
        @to = to
        @value = value
        @gas = gas
        @data = data
        @depth = depth
        @logs = []
        @code_address = code_address
        @is_create = is_create
        @transfers_value = transfers_value
      end

      def to_s
        "#<#{self.class.name}:#{object_id} to=#{@to[0,8]}>"
      end
      alias :inspect :to_s
    end

  end
end
