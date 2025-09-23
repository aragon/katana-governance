# include .env file and export its env vars
-include .env

# predeploy :; forge script Deploy --sig "deployVe()"

predeploy:
	forge script Deploy --sig "deployVe()" --rpc-url $(RPC_URL)
	forge script Deploy --sig "deployKat()" --rpc-url $(RPC_URL)

deploy :; forge script Deploy --broadcast --verify --verifier blockscout --verifier-url=https://dashboard.tenderly.co/explorer/katana-bokuto/api

