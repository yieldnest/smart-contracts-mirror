# Vault Factory Spec Review

Scope: `VAULT_FACTORY_SPEC.md`, checked against the referenced repos:

- `yieldnest-vault` `eth-max-vault` at `680d74bc22bec02b8dd653307339bd067b42e1ae`
- `yieldnest-flex-strategy` `main` at `8c242f33886efb63969da045d6d0232ce276e7a4`
- `yieldnest-vault-withdrawals` `main` at `f7a752f364ff9e8e4efa8087186d96e3de190be1`
- `yieldnest-vault-periphery` `eth-max-vault` at `91e64ddcf39d9ca6b61ae9805ba065488171f06b`

## Critical / High Concerns

### Flex strategy `paused` setting appears wrong

The spec says the optional flex strategy should use `paused is false`. The current `FlexStrategyDeployer` calls `strategy.unpause()` unconditionally during configuration. If the strategy is initialized unpaused, that call should revert with `Unpaused()`. The factory should pass `paused = true` to the deployer, or the deployer should only call `unpause()` when it actually initialized paused.

Suggested amendment: replace `paused is false` with `initialize paused, then unpause after all roles, allocator permissions, accounting module wiring, processor rules, and bootstrap steps are complete`.

### No provider/oracle safety model is specified

The vault uses `provider.getRate(asset)` for all share/base/default conversions. A bad provider, wrong rate scale, unsupported asset, stale rate, or malicious wrapper rate can mint too many shares or make withdrawals/accounting revert. The upstream `Provider` is hardcoded for known ETH assets, not arbitrary RWA assets.

Suggested amendment: require an allowlisted provider implementation per asset pair, explicit rate scale invariants, base/default conversion tests, stale-rate checks where applicable, and a `ProcessAccountingGuardHook` by default for cached-accounting vaults.

### `countNativeAsset` can create unbacked or unwithdrawable value

If `countNativeAsset` is true, `computeTotalAssets()` includes the vault's native balance. The vault can receive native value through `receive()`, but the spec does not define a withdrawal/accounting route for native assets. For an RWA vault this can make `totalAssets` include value that users cannot redeem through the configured default asset path.

Suggested amendment: default `countNativeAsset = false` for RWA vaults. Allow true only when native asset accounting, rescue, withdrawal, and processor rules are explicitly specified and tested.

### A zero buffer disables normal ERC4626 withdrawals

The spec says `The Buffer is 0`, but `BaseVault.maxWithdraw()` and `maxRedeem()` return zero when `buffer() == address(0)`, and the default withdrawal path calls the buffer strategy. That means standard ERC4626 `withdraw/redeem` is intentionally unavailable unless another withdrawal path is configured.

Suggested amendment: explicitly state that standard ERC4626 withdrawals are disabled for these RWA vaults, and require deployment/configuration of the async withdrawal system if user exits are expected. If synchronous exits are expected, a valid buffer strategy must be deployed and configured.

### Temporary allocator and deployer roles need exact cleanup

The spec says the factory receives allocator permissions for bootstrap and then renounces them. The flex deployer grants allocator roles to `params.allocators` and a `BOOTSTRAPPER`, then only renounces temporary roles from the deployer contract. It does not automatically revoke allocator roles from the factory if the factory is included in `allocators`.

Suggested amendment: specify exact post-bootstrap role cleanup: factory must renounce or be revoked from `ALLOCATOR_ROLE`; deployer must lose all temporary admin/manager roles; final role holders must be verified on-chain before the factory emits success.

## Spec Mismatches / Missing Amendments

### Base/default asset wording is contradictory

The spec says non-18-decimal default assets need a wrapped 18-decimal base asset, then says if the base asset has 18 decimals, base and default must be the same. Those cannot both hold for a USDC/default + wrapped-USDC/base design.

Suggested amendment: define the rule as: asset index 0 is the base asset and must match vault share decimals; default asset index is either 0 or 1; if index 1 is used, the default asset must be the underlying of the base wrapper and must have decimals less than or equal to the base asset.

### Final fee manager role is missing from the described role flow

The spec includes `feeManager`, and verification scripts expect `FEE_MANAGER_ROLE` on the fee manager, but the default role helper grants only temporary `FEE_MANAGER_ROLE` to the deployer in the max-vault setup. The factory must explicitly grant `FEE_MANAGER_ROLE` to the final fee manager.

Suggested amendment: add `grantRole(FEE_MANAGER_ROLE, feeManager)` to the final vault role setup and verify it before temporary deployer roles are renounced.

### Proxy and upgrade ownership are underspecified

The spec mentions `timelockDuration` for upgrades and sensitive changes, but it does not specify whether the factory deploys transparent proxies, beacon proxies, implementation contracts, proxy admins, or timelocks. The flex deployer expects implementation addresses and a timelock controller; withdrawal requests use proxy factories and predicted proxy addresses.

Suggested amendment: add a concrete deployment graph: implementation source, proxy type, proxy admin, timelock proposer/executor/canceller roles, implementation allowlist, and whether each vault gets its own timelock or uses a shared one.

### Bootstrap sequence is incomplete

The main vault initializes paused, and user-facing `deposit/mint` revert while paused. The spec says the factory bootstraps with one unit of default asset, but does not state how this happens without briefly exposing an incompletely configured vault.

Suggested amendment: define the exact atomic sequence: deploy proxy; initialize paused; add base/default assets in correct order; set provider; set hooks/rules/buffer or async withdrawal contracts; grant temporary bootstrap roles; unpause; perform bootstrap deposit to a deterministic receiver; process accounting if needed; revoke bootstrap roles; verify final state.

### Bootstrap share ownership is unspecified

The one-unit bootstrap deposit mints real shares. If those shares stay with the factory, deployer, or user, they own a claim on future accounting gains/losses. If they are burned or locked, that must be supported by the vault mechanics.

Suggested amendment: specify the bootstrap receiver and lifecycle. Preferred options are a documented treasury/fee-recipient seed position, a dead/locked seed address if legally acceptable, or making the creator explicitly retain the seed shares.

### Flex strategy rule wording is too vague

The spec says the main vault preloads deposit/mint/withdraw/redeem rules for the flex strategy. The processor guard is function-signature based, and the allowed receiver/owner parameters are the actual security boundary.

Suggested amendment: list the exact target, selector, and allowlisted parameters for each rule. For strategy deposits the receiver should generally be the main vault. For withdrawals the receiver/owner constraints should prevent the processor from routing assets or shares anywhere except approved vault/safe paths.

### Hooks are not covered, but are important for this design

Periphery includes `MetaHooks`, `FeeHooks`, and `ProcessAccountingGuardHook`. Hook order matters, especially if fee minting and process-accounting guards are both installed. `FeeHooks` and the guard both reject `alwaysComputeTotalAssets = true`.

Suggested amendment: add hook parameters or defaults: whether hooks are deployed, order inside `MetaHooks`, performance fee recipient, guard ratios, expected performance fee, hook manager, and `alwaysComputeTotalAssets = false` when fee/guard hooks are installed.

### Async withdrawals repo is listed but not integrated

The spec lists the withdrawals repo but does not describe deploying `WithdrawalRequest`, `BaseWithdrawer`, `BeaconProxyFactory`, request policy, resolver, or required vault roles/approvals. This matters because a zero-buffer RWA vault needs a non-standard withdrawal path.

Suggested amendment: either remove the repo from scope or add async withdrawal deployment/configuration as a first-class factory option, including resolver, pauser, request policy, min withdrawal amount, max metadata length, and `ASSET_WITHDRAWER_ROLE`/allocator requirements.

## Factory Improvements

- Add immutable implementation registries with version checks for vault, flex strategy, accounting module/token, hooks, withdrawal request, withdrawer, and proxy factories.
- Use typed config structs and config hashes, and emit a single `VaultCreated(configHash, vault, strategy, withdrawalRequest, hooks, timelock)` event.
- Add a `previewCreate(config)` view returning predicted addresses, asset order, default index, roles, and bootstrap amounts.
- Add `CREATE2` salts for deterministic vault bundles, while preventing salt squatting with creator/config-bound salts.
- Add a post-deploy verifier that reverts the factory transaction unless every invariant holds.
- Split creator-controlled parameters from protocol-controlled parameters. Creator can choose branding and role recipients; protocol should control implementation allowlists, provider allowlists, wrapper allowlists, fee caps, guard minima, and timelock minima.
- Make bootstrap funding explicit: either pull the exact required assets with permit/Permit2, or accept pre-funded assets and refund excess.
- Add emergency controls at the factory level: pause new vault creation, deprecate bad implementation versions, and publish per-version risk metadata.
- Add per-chain deployment manifests and replay protection so the same config cannot silently point at different implementations on different chains.
- Add factory-level tests for full deployment bundles: same-tx success, failed role cleanup, failed provider, wrong asset decimals/order, failed bootstrap, failed unpause, and async withdrawal availability.

## Bottom Line

The factory approach is viable, but the current spec is not yet precise enough for a secure implementation. The largest risks are not in the act of deploying a vault; they are in silently deploying a vault with the wrong provider, wrong asset ordering, disabled withdrawals, missing fee/admin roles, lingering bootstrap privileges, or a flex strategy initialized with a parameter set that conflicts with its deployer.
