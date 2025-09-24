# include .env file and export its env vars
-include .env

predeploy :; forge script Deploy --rpc-url $(RPC_URL)

deploy:; forge script Deploy \
  --rpc-url https://rpc-bokuto.katanarpc.com \
  --retries 4 \
  --delay 5 \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url=https://explorer-bokuto.katanarpc.com/api
