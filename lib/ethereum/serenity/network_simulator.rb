# -*- encoding : ascii-8bit -*-

require 'distribution'

module Ethereum
  class NetworkSimulator

    START_TIME = Time.now

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

    private

    def normal_distribution(mean, standev)
      ->{ Distribution::Normal.rng(mean, standev).call.to_i }
    end

    def transform(dist, xformer)
      ->{ xformer.call dist.call }
    end

  end
end
