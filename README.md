# ruby-ethereum

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

* upgrade rlp gem dependency
* add pruning trie
* refactor abi types
* refactor trie node types
* review `db.commit_refcount_changes` usage
