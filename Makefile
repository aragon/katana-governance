# include .env file and export its env vars
-include .env

deploy :; forge script Deploy --sig mainA
