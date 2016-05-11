# ruby-ethereum

[![Join the chat at https://gitter.im/janx/ruby-ethereum](https://badges.gitter.im/janx/ruby-ethereum.svg)](https://gitter.im/janx/ruby-ethereum?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

A Ruby implementation of [Ethereum](https://ethereum.org).

## Install Secp256k1

The [ruby-bitcoin-secp256k1 gem](https://github.com/janx/ruby-bitcoin-secp256k1) requires libsecp256k1 with recovery module enabled.

See the gem's [install script](https://github.com/janx/ruby-bitcoin-secp256k1/blob/master/install_lib.sh) for how to install this once you've cloned [libsecp256k1](https://github.com/bitcoin-core/secp256k1/tree/7b549b1abc06fe1c640014603346b85c8bc83e0b).

## Caveats

### Increase Ruby Stack Size Limit

Or some tests will fail because the default stack size cannot hold a maximum (1024) levels
deep VM stack.

Set `RUBY_THREAD_VM_STACK_SIZE` in your shell/environment:

```
export RUBY_THREAD_VM_STACK_SIZE=104857600 # 100M, 100 times default
```

### Fiber Stack Size

[ruby-devp2p](https://github.com/janx/ruby-devp2p) is built on [Celluloid](https://github.com/celluloid/celluloid/), which
uses fibers to schedule tasks. Ruby's default limit on fiber stack size is quite small, which needs to be increased by setting environment variables:

```
export RUBY_FIBER_VM_STACK_SIZE=104857600 # 100MB
export RUBY_FIBER_MACHINE_STACK_SIZE=1048576000
```

## Testing
Setup:
```
git submodule update --init
```
Run:
```
rake
```
## License

[MIT License](LICENSE)

## TODO

* optimize memory foot print
* add pruning trie
* refactor abi types
* refactor trie node types
* review `db.commit_refcount_changes` usage
