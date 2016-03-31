# -*- encoding : ascii-8bit -*-

require 'distribution'

module Ethereum
  class NetworkSimulator

    START_TIME = Time.now

    attr :agents, :peers

    def initialize(latency: 50, agents: [], reliability: 0.9, broadcast_success_rate: 1.0)
      @agents = agents

      dist = normal_distribution latency, (latency*2)/5
      xformer = ->(x) { [x, 0].max }
      @latency_distribution_sample = transform dist, xformer

      @time = 0
      @objqueue = {}
      @peers = {}
      @reliability = reliability
      @broadcast_success_rate = broadcast_success_rate
      @time_sleeping = 0
      @time_running = 0
      @sleepdebt = 0
    end

    def generate_peers(n=5)
      @peers = {}

      @agents.each do |a|
        p = []
        while p.size <= n/2
          p.push @agents.sample
          p.pop if p.last == a
        end

        @peers[a.id] = (@peers[a.id] || []) + p
        p.each {|peer| @peers[peer.id] = (@peers[peer.id] || []) + [a] }
      end
    end

    def broadcast(sender, obj)
      raise ArgumentError, "obj must be bytes" unless obj.instance_of?(String)

      if rand < @broadcast_success_rate
        @peers[sender.id].each do |p|
          recv_time = @time + @latency_distribution_sample.call
          if !@objqueue.has_key?(recv_time)
            @objqueue[recv_time] = []
          end
          @objqueue[recv_time].push [sender.id, p, obj]
        end
      end
    end

    def now
      Time.now.to_f
    end

    private

    def normal_distribution(mean, standev)
      ->{ Distribution::Normal.rng(mean, standev).call.to_i }
    end

    def transform(dist, xformer)
      ->{ xformer.call dist.call }
    end

  end
end
