# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    class Profile

      GENESIS_DIR = File.expand_path('../genesisdata', __FILE__)

      ALL = {
        livenet: {
          eth: {
            network_id: 1,
            genesis: File.join(GENESIS_DIR, 'genesis_frontier.json'),
            genesis_hash: 'd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3',
          },
          discovery: {
            bootstrap_nodes: [
              'enode://487611428e6c99a11a9795a6abe7b529e81315ca6aad66e2a2fc76e3adf263faba0d35466c2f8f68d561dbefa8878d4df5f1f2ddb1fbeab7f42ffb8cd328bd4a@5.1.83.226:30303', # C++
              'enode://a979fb575495b8d6db44f750317d0f4622bf4c2aa3365d6af7c284339968eef29b69ad0dce72a4d8db5ebb4968de0e3bec910127f134779fbcb0cb6d3331163c@52.16.188.185:30303', # GO
              'enode://de471bccee3d042261d52e9bff31458daecc406142b401d4cd848f677479f73104b9fdeb090af9583d3391b7f10cb2ba9e26865dd5fca4fcdc0fb1e3b723c786@54.94.239.50:30303', # GO2
              'enode://2676755dd8477ad3beea32b4e5a144fa10444b70dfa3e05effb0fdfa75683ebd4f75709e1f8126cb5317c5a35cae823d503744e790a3a038ae5dd60f51ee9101@144.76.62.101:30303', # Python
            ]
          },
        },
        testnet: {
          eth: {
            network_id: 2,
            genesis: File.join(GENESIS_DIR, 'genesis_morden.json'),
            genesis_hash: '0cd786a2425d16f152c658316c423e6ce1181e15c3295826d7c9904cba9ce303',
            block: {
              account_initial_nonce: 2 ** 20,
              homestead_fork_blknum: 494000,
            },
          },
          discovery: {
            bootstrap_nodes: [
              'enode://e4533109cc9bd7604e4ff6c095f7a1d807e15b38e9bfeb05d3b7c423ba86af0a9e89abbf40bd9dde4250fef114cd09270fa4e224cbeef8b7bf05a51e8260d6b8@94.242.229.4:40404' # Go
            ]
          },
        }
      }

      class <<self
        def all
          @all ||= Hashie::Mash.new ALL
        end

        def public(name)
          all[name]
        end

        def private(network_id)
          Hashie::Mash.new({
            eth: {
              network_id: network_id
            },
            discovery: {
              bootstrap_nodes: []
            }
          })
        end
      end

    end

  end
end
