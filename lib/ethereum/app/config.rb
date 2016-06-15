# -*- encoding : ascii-8bit -*-

require 'fileutils'
require 'json'

require 'hashie'

module Ethereum
  module App

    class Config

      DEFAULT_DATA_DIR = File.join(Dir.home, '.config', 'reth')
      CONFIG_FILE = 'config.json'
      GENESIS_FILE = 'genesis.json'

      Defaults = Hashie::Mash.new({
        p2p: {
          listen_host: '0.0.0.0',
          listen_port: 13333,
          num_peers: 10
        },

        discovery: {
          listen_host: '0.0.0.0',
          listen_port: 13333
        }
      }).freeze

      class <<self
        def setup(data_dir=DEFAULT_DATA_DIR)
          setup_data_dir data_dir
          setup_required_config data_dir
        end

        def setup_data_dir(data_dir=DEFAULT_DATA_DIR)
          FileUtils.mkdir_p(data_dir) unless File.exist?(data_dir)
        end

        def setup_required_config(data_dir=DEFAULT_DATA_DIR)
          path = File.join data_dir, CONFIG_FILE

          unless File.exists?(path)
            config = {
              node: {
                privkey_hex: Utils.encode_hex(Utils.mk_random_privkey)
              }
            }
            save config, path
          end
        end

        def save(config, path)
          File.open(path, 'wb') do |f|
            h = config.instance_of?(Hashie::Mash) ? config.to_hash : config
            f.write JSON.dump(h)
          end
        end

        def load(data_dir=DEFAULT_DATA_DIR)
          config_path = File.join data_dir, CONFIG_FILE
          config = File.exist?(config_path) ? JSON.parse(File.read(config_path)) : {}
          config[:data_dir] = data_dir

          genesis_path = File.join data_dir, GENESIS_FILE
          genesis = File.exist?(genesis_path) ? JSON.parse(File.read(genesis_path)) : nil
          if genesis
            config[:eth] ||= {}
            config[:eth][:genesis] = genesis
          end

          Defaults.deep_merge(config)
        end

        ##
        # Collect default_config from services.
        #
        def get_default_config(services)
          config = {}
          services.each do |s|
            DEVp2p::Utils.update_config_with_defaults config, s.default_config
          end
          config
        end
      end

    end

  end
end
