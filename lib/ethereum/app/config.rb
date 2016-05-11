# -*- encoding : ascii-8bit -*-

require 'fileutils'
require 'yaml'

require 'hashie'

module Ethereum
  module App

    class Config

      DEFAULT_DATA_DIR = File.join(Dir.home, '.config', 'reth')
      FILENAME = 'config.yaml'

      Defaults = Hashie::Mash.new({
        p2p: {
          listen_host: '0.0.0.0',
          listen_port: 13333,
          num_peers: 10
        },

        discovery: {
          listen_host: '0.0.0.0',
          listen_port: 13333,
          bootstrap_nodes: [
            'enode://a255fad01ada3d61bbd07dba21fbb165eb073f8f7ae7ec6381ed6b9a382833278333335b5934f3282b28eb9d44e39c5244a2aec75c9b48ea0e4b57219cf36d85@127.0.0.1:30303'
          ]
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
          path = get_path data_dir

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
            f.write YAML.dump(h)
          end
        end

        def load(data_dir=DEFAULT_DATA_DIR)
          path = get_path data_dir
          config = File.exist?(path) ? YAML.load_file(path) : {}
          config[:data_dir] = data_dir
          Defaults.deep_merge(config)
        end

        def get_path(data_dir=DEFAULT_DATA_DIR)
          File.join data_dir, FILENAME
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
