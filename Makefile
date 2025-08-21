# include .env file and export its env vars
-include .env

predeploy :; forge script Deploy
deploy :; forge script Deploy --broadcast --verify --verifier blockscout --verifier-url=https://explorer.tatara.katana.network/api

