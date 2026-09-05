# Vault factory

## Relevant repos

### Core vault contracts

git@github.com:yieldnest/yieldnest-vault.git


### Flex strategy contracts

git@github.com:yieldnest/yieldnest-flex-strategy.git

### Vault async withdrawals Contracts

git@github.com:yieldnest/yieldnest-vault-withdrawals.git

### Wrapped token contracts

git@github.com:yieldnest/wrapped-token.git

### Metahooks, hooks, and other periphery contracts

git@github.com:yieldnest/yieldnest-vault-periphery.git

### Safe multisig transaction safeguards

git@github.com:yieldnest/safeguard.git

## RWA Vault Factory

The RWA factory allows one-transaction creation of RWA vaults on demand using the yieldnest-vault logic.

Configure the parameters of the RWA vault and deploy a vault under your control.

What an RWA vault is composed of:

### Main Vault

The top-level vault that represents the ERC20 shares token of the RWA tokenized asset. This is an instance of https://github.com/yieldnest/yieldnest-vault/blob/eth-max-vault/src/Vault.sol

The following notions are defined in the BaseVault. https://github.com/yieldnest/yieldnest-vault/blob/eth-max-vault/src/BaseVault.sol

The Main Vault has 18 decimals.

### Default asset

This is the default asset of the ERC4626 interface of the Main Vault. 

Example: USDC, USDT, SUSD.

Once chosen this asset CANNOT BE CHANGED, without breaking all ERC4626 integrations. Updating the default asset is very high risk and should never be done unless all consequences are fully understood and all potential collateral damage is assessed.

### Base Asset

This is the internal accounting asset of the vault, in which all other assets in the vault are denominated. The effective Base Asset used by the Main Vault MUST have 18 decimals.

Vault creators pass `baseAsset`. The factory derives both the ERC4626 Default Asset and the effective Base Asset from that one parameter:

- If `baseAsset` has 18 decimals, the effective Base Asset and the ERC4626 Default Asset are both `baseAsset`.
- If `baseAsset` has fewer than 18 decimals, the ERC4626 Default Asset is `baseAsset`; the factory deploys a Wrapped Token for `baseAsset` and uses that wrapper as the Main Vault's effective Base Asset. The wrapper is initialized with 18 decimals and a decimal offset of `18 - baseAssetDecimals`.

The Wrapped Token is deployed behind the same OpenZeppelin Transparent Upgradeable Proxy pattern as the Main Vault. Its `ProxyAdmin` is owned by the same deployment timelock used for the Main Vault, so wrapper upgrades follow the same upgradeability rules.



### Rate Provider

The factory deploys the vault's rate provider; vault creators do not supply one.

- Without a flex strategy, the factory deploys the yieldnest-vault `BaseAssetProvider`, pricing the Default Asset at a fixed rate of 1e18 (par). The wrapper (when present) never holds a balance and is never priced.
- With a flex strategy (future revision), the factory will instead deploy the yieldnest-vault `Provider`, wired to the wrapper and the strategy.

Provider changes remain a critical timelocked operation.

### Vault Parameters

These are the key parameters that are used when deploying a new RWA vault via the factory:

- **admin:**  
  The address that will have admin privileges over the vault.

- **processor:**  
  The address that is authorized to process actions within the vault.

- **pauser:**  
  The address that is allowed to pause the vault functionality in the event of an emergency.

- **unpauser:**  
  The address allowed to unpause the vault after it has been paused.

- **feeManager:**  
  The address responsible for managing and collecting any fees associated with the vault.

- **tokenName:**  
  The display name of the vault’s share token.

- **tokenSymbol:**  
  The symbol for the vault's share token, set using the provided function or value.

- **countNativeAsset:**  
  A boolean parameter indicating whether the vault should count the native asset (e.g., ETH, BNB) as part of its total asset value.  
  - If `true`, the vault includes the native asset balance when calculating its total assets under management.
  - If `false`, only ERC20 and explicitly defined assets are considered in total asset calculations.

- **alwaysComputeTotalAssets:**  
  A boolean parameter passed to the Main Vault initializer indicating whether `totalAssets` should always be computed from the vault's configured accounting path instead of using any cached or optimized accounting behavior exposed by the vault implementation.

- **timelockDuration:**  
  The duration (in seconds) of the timelock applied specifically to sensitive operations such as upgrades, asset changes, rate provider changes, and modifications to critical parameters. This timelock enforces a mandatory waiting period between when such an action is proposed (queued) and when it can actually be executed, providing additional time and security for stakeholders to review and react to these potentially impactful changes.


Base Withdrawal fee is 0, as withdrawals don't happen through the buffer. The Buffer is 0.

### Proxy and Upgrade Ownership

Vaults and related upgradeable components are deployed behind OpenZeppelin Transparent Upgradeable Proxies.

Each vault deployment has one OpenZeppelin `ProxyAdmin`. The `ProxyAdmin` is owned by one `TimelockController`.

The same timelock is also assigned wherever the deployment has critical protocol operations. This includes, at minimum:

- upgrades through the `ProxyAdmin`
- provider changes
- asset changes
- buffer changes
- processor rule changes
- allocator manager operations
- hook manager operations
- other critical configuration changes introduced by optional modules

The factory must configure the timelock as the owner or role holder for these critical operations during deployment. Any temporary roles held by the factory or deployer for setup must be renounced or revoked before the deployment is considered complete.

IMPORTANT: the Main Vault's `DEFAULT_ADMIN_ROLE` is assigned to the timelock and nothing else. It is the role admin for every vault role, so this is what makes critical role updates themselves timelocked (e.g. granting or revoking `PROVIDER_MANAGER_ROLE` or `ASSET_MANAGER_ROLE`): they can only happen through a scheduled, delayed timelock operation. Assigning it to any other account would allow instant role changes that bypass the timelock.

### Registry

Factory deployment parameters refer to protocol-controlled addresses through a `Registry`.

The registry maps `bytes32` keys to address values. A helper converts human-readable string keys into `bytes32` keys with `keccak256(bytes(key))`.

The registry itself is deployed behind an OpenZeppelin Transparent Upgradeable Proxy. Its proxy admin is owned by the deployment timelock.

The registry owner can set one key-value pair at a time or bulk update keys and address values. The factory should use registry keys rather than accepting arbitrary protocol-controlled addresses from vault creators.

The factory reads the Main Vault logic and Wrapped Token logic from the registry. The Wrapped Token logic is only required when the requested Base Asset has fewer than 18 decimals.

The registry keys used by the factory are fixed constants compiled into the factory; vault creators cannot choose which keys are read. Key strings are namespaced as `<org>.<repo>.contracts.<source path>` of the implementation:

- `yieldnest.yieldnest-vault.contracts.src.Vault`
- `yieldnest.wrapped-token.contracts.src.WrappedToken`
- `yieldnest.yieldnest-vault-withdrawals.contracts.src.WithdrawalRequest`
- `yieldnest.yieldnest-vault-withdrawals.contracts.src.withdrawers.BaseWithdrawer`
- `yieldnest.yieldnest-vault-withdrawals.contracts.src.BeaconProxyFactory`
- `yieldnest.yieldnest-vault-withdrawals.contracts.src.Bag`

### Hooks

Hook deployment is out of scope for this factory revision.

The factory still assigns the Main Vault hook manager role to the deployment timelock, so future hook installation or hook replacement remains a critical timelocked operation.

When hook deployment is added back, it should use the actual periphery contracts and APIs rather than inferred factory interfaces.

### Async withdrawals

Because the buffer is 0, standard synchronous ERC4626 withdrawals are unavailable. The factory deploys the async withdrawal system from yieldnest-vault-withdrawals as part of every vault deployment:

- **WithdrawalRequest** — the ERC721 request contract, bound to the Main Vault share token.
- **BaseWithdrawer** — the adapter that forwards withdrawals to the Main Vault. The factory grants it the vault's `ASSET_WITHDRAWER_ROLE`.
- **BeaconProxyFactory** — the bag factory used by the WithdrawalRequest to create per-request bags. Its beacon points at the Bag implementation.
- **MinAmountRequestPolicy** — the request policy, deployed directly by the factory with the per-vault `minWithdrawalAmount` (it is constructor-parameterized and not upgradeable, so it does not come from the registry).

The WithdrawalRequest, BaseWithdrawer, and BeaconProxyFactory implementations are read from the registry, together with the Bag implementation. Each of the three is deployed behind an OpenZeppelin Transparent Upgradeable Proxy whose `ProxyAdmin` is owned by the deployment timelock.

The factory also exposes `deployWithdrawalSystem(vault, timelock, resolver, pauser, minWithdrawalAmount, maxDataLength)` publicly, so a withdrawal system can be deployed standalone for an existing vault. In that case the caller is responsible for granting the returned withdrawer the vault's `ASSET_WITHDRAWER_ROLE`; `createVault` performs that grant itself.

Role assignment: the WithdrawalRequest default admin and configuration manager are the deployment timelock; the bag factory default admin and implementation manager are the deployment timelock; the bag factory creator is the WithdrawalRequest.

Additional vault parameters:

- **resolver:**
  The address granted `RESOLVER_ROLE` on the WithdrawalRequest, allowed to resolve withdrawal requests.

- **minWithdrawalAmount:**
  The minimum share amount each withdrawal request must lock, enforced by the MinAmountRequestPolicy.

- **maxDataLength:**
  The maximum bytes allowed in withdrawal request metadata.

The WithdrawalRequest pauser is the same `pauser` address used for the Main Vault (the WithdrawalRequest has a single `PAUSER_ROLE` covering both pause and unpause; the timelock can grant it to additional accounts later).

### Flex strategy - OPTIONAL

TODO: factory deployment of the flex strategy is out of scope for this revision.

The flex strategy may be optionally added manually later.

The factory keeps the `deployStrategy` parameter as an explicit placeholder for a future revision.

The additional parameters here are:

#### Parameters

The parameters are the ones specified here:

https://github.com/yieldnest/yieldnest-flex-strategy/blob/main/script/FlexStrategyDeployer.sol#L16

Additional factory parameter:

- **offRampAddress:**  
  The address that is allowed to receive the flex strategy asset from the flex strategy multisig through the SafeGuard module.


The rules here are that the base asset is the same base asset as the Main Vault.

paused is false.

The Allocators contains the Main Vault and the factory contract that will make the first boostrap deposit.

Once that boostrap action is done, the role is renounced.



#### Flex strategy deposit rules

The vault also preloads deposit/mint withdraw/redeem rules for the flex strategy if it exists.

#### Flex strategy multisig SafeGuard

The flex strategy multisig is expected to be configured with a SafeGuard module.

TODO: factory deployment of the SafeGuard instance is out of scope for this revision. When added, the factory should deploy the SafeGuard instance and configure it with a rule that permits sending the asset of the flex strategy to `offRampAddress`.

The factory does not enable the SafeGuard module on the multisig. It is the user's responsibility to configure the deployed SafeGuard as a module for that multisig after creation.


### Bootstrapping

The Main Vault and Flex Strategy (if added) need to be boostrapped with one unit of the default asset.

Eg. 1 USDC (1e6 in wei), 1 USDT (1e6 in Wei), 1 SUSD, (1e18 in wei).

The factory create call transfers the asset or assets away from the users.

The factory enforces a minimum bootstrap amount of one unit of the default asset (10^decimals) and reverts below it.
