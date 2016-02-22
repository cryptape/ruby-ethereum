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

## License

[MIT License](LICENSE)

## TODO

* upgrade rlp gem dependency
* add pruning trie
* refactor abi types
* refactor trie node types
* review `db.commit_refcount_changes` usage
