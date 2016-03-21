# -*- encoding : ascii-8bit -*-

module Ethereum
  module Tester
    class ABIContract

      attr :address, :abi, :translator

      def initialize(state, abi, address, listen: true, log_listener: nil)
        @state = state
        @abi = abi
        @address = address

        @translator = ABI::ContractTranslator.new abi

        if listen
          if log_listener
            listener = lambda do |log|
              r = @translator.listen(log, noprint: true)
              log_listener.call r if r.true?
            end
          else
            listener = ->(log) { @translator.listen(log, noprint: false) }
          end
        end

        @translator.function_data.each do |f, _|
          generate_function f
        end
      end

      private

      def generate_function(f)
        singleton_class.class_eval <<-EOF
        def #{f}(*args, **kwargs)
          sender = kwargs.delete(:sender) || Fixture.keys[0]
          to = @address
          value = kwargs.delete(:value) || 0
          evmdata = @translator.encode('#{f}', args)
          output = kwargs.delete(:output)

          o = @state._send_tx(sender, to, value, **kwargs.merge(evmdata: evmdata))

          if output == :raw
            outdata = o[:output]
          elsif o[:output].false?
            outdata = nil
          else
            outdata = @translator.decode '#{f}', o[:output]
            outdata = outdata.size == 1 ? outdata[0] : outdata
          end

          kwargs[:profiling].true? ? o.merge(outdata: outdata) : outdata
        end
        EOF
      end

    end
  end
end
