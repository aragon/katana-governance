# include .env file and export its env vars
-include .env

test-invariant :; forge test --match-path "test/**/invariant/**/*.sol" --show-progress
test-ui :; forge test --no-match-path "test/**/invariant/**/*.sol"

ifeq ($(VERIFIER),etherscan)
  VERIFIER_PARAMS := --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)
endif

ifeq ($(VERIFIER),blockscout)
  VERIFIER_PARAMS := --verifier blockscout --verifier-url "$(VERIFIER_URL)"
endif

predeploy :; forge script Deploy --rpc-url $(RPC_URL)

deploy:; forge script Deploy \
  --rpc-url $(RPC_URL) \
  --retries 5 \
  --delay 7 \
  --broadcast \
  --verify \
  $(VERIFIER_PARAMS)

deployMerkl:; forge script DeployMerkl \
  --rpc-url $(RPC_URL) \
  --retries 6 \
  --delay 15 \
  --broadcast \
  --verify \
  $(VERIFIER_PARAMS)

deployGio:; forge script ProposalDeploy \
  --rpc-url $(RPC_URL) \
  --private-key $(DEPLOYMENT_PRIVATE_KEY) \
  --broadcast

deployGio1:; forge script VoteTest \
  --rpc-url $(RPC_URL) \
  --broadcast


#  target contract 0x0C6086009bB2E5595c21EeF41Ab03B36e5AF2a7B
  # batch executor  0x0beA5B104f586d5129bfb3785152f500312e4cCB