# ruby-ethereum

[![Join the chat at https://gitter.im/janx/ruby-ethereum](https://badges.gitter.im/janx/ruby-ethereum.svg)](https://gitter.im/janx/ruby-ethereum?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

A Ruby implementation of [Ethereum](https://ethereum.org).

## Install Secp256k1

```
git clone git@github.com:bitcoin/bitcoin.git
git checkout v0.11.2

./autogen.sh
./configure
make
sudo make install
```

## Caveats

### Increase Ruby Stack Size Limit

Or some tests will fail because the default stack size cannot hold a maximum (1024) levels
deep VM stack.

Set `RUBY_THREAD_VM_STACK_SIZE` in your shell/environment:

```
export RUBY_THREAD_VM_STACK_SIZE=104857600 # 100M, 100 times default
```

## License

[MIT License](LICENSE)

## TODO

* optimize memory foot print
* add pruning trie
* refactor abi types
* refactor trie node types
* review `db.commit_refcount_changes` usage
