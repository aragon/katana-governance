# avKAT conversion window upgrade

Gate `depositTokenId` so vKAT → avKAT conversion is only allowed while voting is active.

## Steps

1. Ensure `.env` has:

| Variable | Required for |
| --- | --- |
| `DEPLOYMENT_PRIVATE_KEY` | signing the deploy tx |
| `RPC_URL` | chain RPC |
| `VERIFIER` | `etherscan` or `blockscout` |
| `ETHERSCAN_API_KEY` | when `VERIFIER=etherscan` |
| `VERIFIER_URL` | when `VERIFIER=blockscout` |

2. Deploy the new implementation:

```bash
make deployVaultImplementation
```

3. Note the printed `New AvKATVault implementation` address.

4. Open the [Katana vKAT Management DAO multisig](https://app.aragon.org/dao/katana-mainnet/0xb72291652f15cF73651357383c0A86FBba29B675/proposals?proposals=0x69f9105DCc43bAaa78089Fcf811aaaD2C156D269-multisig).

5. Create a proposal with one action:
   - Contract: avKAT vault proxy
   - Function: `upgradeTo(address)`
   - Argument: the new implementation address from step 3
   - Value: `0`

6. Approve and execute the proposal.
