# We assume that data takes the following schema:
# bytes 0-31: gasprice
# bytes 32-63: v (ECDSA sig)
# bytes 64-96: r (ECDSA sig)
# bytes 96-127: s (ECDSA sig)
# bytes 128-159: sequence number (formerly called "nonce")
# bytes 172-191: to
# bytes 192-223: value
# bytes 224+: data
~calldatacopy(0, 0, ~calldatasize())
~call(msg.gas - 50000, ~calldataload(160), ~calldataload(192), 224, ~calldatasize() - 224, ~calldatasize(), 10000)
~return(~calldatasize(), ~msize() - ~calldatasize())
