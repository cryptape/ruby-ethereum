# -*- encoding : ascii-8bit -*-

require_relative 'guardian/bet'
require_relative 'guardian/opinion'
require_relative 'guardian/default_bet_strategy'

module Ethereum
  module Guardian

    class <<self

      ##
      # Convert probability from a number to one-byte encoded form using
      # scientific notation on odds with a 3-bit mantissa: 0 = 65536:1 odds =
      # 0.0015%, 128 = 1:1 odds = 50%, 255 = 1:61440 = 99.9984%.
      #
      def encode_prob(p)
        lastv = "\x00"
        loop do
          q = p / (1.0 - p)
          exp = 0
          while q < 1
            q *= 2.0
            exp -= 1
          end
          while q >= 2
            q /= 2.0
            exp += 1
          end

          mantissa = (q*4 - 3.9999).to_i
          [[255, exp*4 + 128 + mantissa].min, 0].max.chr
        end
      end

      # Convert probability fron one-byte encoded form to a number
      def decode_prob(c)
        c = c.ord
        q = 2.0**((c-128) / 4) * (1 + 0.25 * ((c-128) % 4))
        q / (1.0 + q)
      end

    end

  end
end
