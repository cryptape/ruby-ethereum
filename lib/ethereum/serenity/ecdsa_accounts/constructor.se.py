# We assume that data takes the following schema:
# bytes 0-31: v (ECDSA sig)
# bytes 32-63: r (ECDSA sig)
# bytes 64-95: s (ECDSA sig)
# bytes 96-127: gasprice
# bytes 128-159: sequence number (formerly called "nonce")
# bytes 172-191: to
# bytes 192-223: value
# bytes 224+: data
# ~calldatacopy(0, 0, ~calldatasize())
# Prepare the transaction data for hashing: gas + non-sig data
~mstore(128, ~txexecgas())
~calldatacopy(160, 96, ~calldatasize() - 96)
# Hash it
~mstore(0, ~sha3(128, ~calldatasize() - 64))
~calldatacopy(32, 0, 96)
# Call ECRECOVER contract to get the sender
~call(5000, 1, 0, 0, 128, 0, 32)
# Check sender correctness; exception if not
if ~mload(0) != self.storage[2]:
    # ~log1(0, 0, 51)
    ~invalid()
# Check value sufficiency
if self.balance < ~calldataload(192) + ~calldataload(96) * ~txexecgas():
    # ~log1(0, 0, 52)
    ~invalid()
# Sequence number operations
with minusone = ~sub(0, 1):
    with curseq = self.storage[minusone]:
        # Check sequence number correctness, exception if not
        if ~calldataload(128) != curseq:
            # ~log3(0, 0, 53, ~calldataload(128), curseq)
            ~invalid()
        # Increment sequence number
        self.storage[minusone] = curseq + 1
        return(~calldataload(96))
