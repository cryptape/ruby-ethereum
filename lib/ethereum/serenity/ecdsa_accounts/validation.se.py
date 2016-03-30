# We assume that data takes the following schema:
# bytes 0-31: hash
# bytes 32-63: v (ECDSA sig)
# bytes 64-95: r (ECDSA sig)
# bytes 96-127: s (ECDSA sig)

# Call ECRECOVER contract to get the sender
~calldatacopy(0, 0, 128)
~call(5000, 1, 0, 0, 128, 0, 32)
# Check sender correctness
return(~mload(0) == 0x82a978b3f5962a5b0957d9ee9eef472ee55b42f1)
