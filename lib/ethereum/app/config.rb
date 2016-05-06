# -*- encoding : ascii-8bit -*-

require 'fileutils'
require 'yaml'

module Ethereum
  module App

    class Config

      DEFAULT_DATA_DIR = File.join(Dir.home, '.config', 'reth')
      FILENAME = 'config.yaml'

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

        def save(config, data_dir=DEFAULT_DATA_DIR)
          File.open(get_path(data_dir), 'wb') do |f|
            f.write YAML.dump(config)
          end
        end

        def load(data_dir=DEFAULT_DATA_DIR)
          path = get_path data_dir
          File.exist?(path) ? YAML.load_file(path) : {}
        end

        def get_path(data_dir=DEFAULT_DATA_DIR)
          File.join data_dir, FILENAME
        end
      end

    end

  end
end
