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

    def run(seconds, sleep: 0)
      t = 0

      loop do
        t1 = Time.now.to_f
        tick
        td = Time.now.to_f - t1

        if sleep > td
          tsleep = sleep - td
          sleepdebt_repayment = [@sleepdebt, tsleep*0.5].min
          Kernel.sleep(tsleep - sleepdebt_repayment)

          @time_sleeping += tsleep - sleepdebt_repayment
          @sleepdebt -= sleepdebt_repayment
        else
          @sleepdebt += td - sleep
        end

        @time_running += td
        puts "Tick finished in: %.2f. Total sleep %.2f, running %.2f" % [td, @time_sleeping, @time_running]

        if @sleepdebt > 0
          puts "Sleep debt: %.2f" % @sleepdebt
        end

        t += Time.now.to_f - t1
        return if t >= seconds
      end
    end

    def tick
      if @objqueue.has_key?(@time)
        @objqueue[@time].each do |(sender_id, recipient, obj)|
          if rand < @reliability
            recipient.on_receive(obj, sender_id)
          end
        end

        @objqueue.delete @time
      end

      @agents.each {|a| a.tick }

      @time += 1
    end

    def send_to_one(sender, obj)
      raise ArgumentError, "obj must be bytes" unless obj.instance_of?(String)

      if rand < @broadcast_success_rate
        p = @peers[sender.id].sample
        recv_time = @time + @latency_distribution_sample.call
        @objqueue[recv_time] = [] unless @objqueue.has_key?(recv_time)
        @objqueue[recv_time].push [sender.id, p, obj]
      end
    end

    def direct_send(sender, to_id, obj)
      if rand < @broadcast_success_rate * @reliability
        @agents.each do |a|
          if a.id == to_id
            recv_time = @time + @latency_distribution_sample.call
            @objqueue[recv_time] = [] unless @objqueue.has_key?(recv_time)
            @objqueue[recv_time].push [sender.id, a, obj]
          end
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
