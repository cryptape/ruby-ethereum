# Copy the calldata to bytes 32...x+32
~calldatacopy(64, 0, ~calldatasize())
# If we are getting a message NOT from the origin object, then just
# pass it along to the runner code
if msg.sender != %d:
    ~mstore(0, 0)
    ~delegatecall(msg.gas - 50000, self.storage[1], 64, ~calldatasize(), 64 + ~calldatasize(), 10000)
    ~return(64 + ~calldatasize(), ~msize() - 64 - ~calldatasize())
# Run the sig checker code; self.storage[0] = sig checker
# sig checker should return gas price
if not ~delegatecall(250000, self.storage[0], 64, ~calldatasize(), 32, 32):
    ~invalid()
# Compute the gas payment deposit
~mstore(0, ~mload(32) * ~txexecgas())
# Send the gas payment into the deposit contract
if self.balance < ~mload(0):
    ~invalid()
~call(2000, %d, ~mload(0), 0, 0, 0, 32)
# Do the main call; self.storage[1] = main running code
~breakpoint()
x = ~delegatecall(msg.gas - 50000, self.storage[1], 64, ~calldatasize(), 64, 10000)
# Call the deposit contract to refund
~mstore(0, ~mload(32) * msg.gas)
~call(2000, %d, ~mload(0), 0, 32, 0, 32)
~return(64, ~msize() - 64)
