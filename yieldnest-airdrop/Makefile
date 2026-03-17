# Default values
json ?= script/inputs/season-one-eigen-holesky.json
network ?= holesky
deployerAccountName := $(shell grep '^DEPLOYER_ACCOUNT_NAME=' .env | cut -d '=' -f2)
deployerAddress := $(shell grep '^DEPLOYER_ADDRESS=' .env | cut -d '=' -f2)

# Default target
.PHONY: all
all: clean install build

# Clean the cache and output directories
.PHONY: clean
clean:
	rm -rf cache out

# Install dependencies using forge
.PHONY: install
install:
	forge install

# Build the project using forge
.PHONY: build
build:
	forge build

# Compile the project using forge
.PHONY: compile
compile:
	forge compile

# Run the tests using forge
.PHONY: test
test:
	forge test -vvv

# Create a gas snapshot
.PHONY: snapshot
snapshot:
	forge snapshot

# Generate a coverage report
.PHONY: coverage
coverage:
	forge coverage

# Generate a coverage report and create an HTML report
.PHONY: coverage-report
coverage-report:
	forge coverage --report lcov && genhtml lcov.info --output-directory coverage

# Show the coverage report
.PHONY: coverage-show
coverage-show:
	npx http-server ./coverage

# Lint the Solidity files using forge fmt and solhint
.PHONY: lint
lint:
	forge fmt --check && solhint "{script,src,test}/**/*.sol"

# Format the Solidity files using forge fmt
.PHONY: format
format:
	forge fmt --root .

# make simulate json=script/inputs/season-one-eigen-holesky.json network=holesky

.PHONY: simulate
simulate:
	@if [ -z "${network}" ]; then echo "Error: network is required"; exit 1; fi
	@if [ -z "${json}" ]; then echo "Error: input json is required"; exit 1; fi
	@if [ -z "${deployerAccountName}" ]; then echo "Error: deployerAccountName is required"; exit 1; fi
	@if [ -z "${deployerAddress}" ]; then echo "Error: deployerAddress is required"; exit 1; fi
	forge script DeployAirdrop --sig "run(string memory)" ${json} --rpc-url ${network} --account ${deployerAccountName} --sender ${deployerAddress} --slow

# make deploy json=script/inputs/season-one-eigen-holesky.json network=holesky
.PHONY: deploy
deploy:
	@if [ -z "${network}" ]; then echo "Error: network is required"; exit 1; fi
	@if [ -z "${json}" ]; then echo "Error: input json is required"; exit 1; fi
	@if [ -z "${deployerAccountName}" ]; then echo "Error: deployerAccountName is required"; exit 1; fi
	@if [ -z "${deployerAddress}" ]; then echo "Error: deployerAddress is required"; exit 1; fi
	forge script DeployAirdrop --sig "run(string memory)" ${json} --rpc-url ${network} --account ${deployerAccountName} --sender ${deployerAddress} --slow --broadcast --verify

# make verify json=script/inputs/season-one-eigen-holesky.json network=holesky
.PHONY: verify
verify:
	@if [ -z "${network}" ]; then echo "Error: network is required"; exit 1; fi
	@if [ -z "${json}" ]; then echo "Error: input json is required"; exit 1; fi
	forge script VerifyAirdrop --sig "run(string memory)" ${json} --rpc-url ${network}
