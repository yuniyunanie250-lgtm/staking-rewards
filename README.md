# staking-rewards

A staking rewards pool in the shape of Synthetix's `StakingRewards`: a fixed
amount of reward tokens spread across all stakers over a period.

The interesting part is that this is O(1) per user. Naively, paying N stakers
means N transfers per reward tick. Instead the contract tracks a single
cumulative `rewardPerToken` value and each account stores the value it last saw;
`earned` is the difference. No loop, no per-user bookkeeping on the hot path.

## Model

- `notifyRewardAmount(reward, duration)` pulls the reward tokens up front and
  sets `rewardRate = reward / duration`. Funding up front is what makes the
  per-second rate solvent.
- `stake` / `withdraw` move the staking token and snapshot the caller's reward
  position via the `updateReward` modifier.
- `earned(account)` is the live claimable amount.
- `getReward` pays it out; `exit` does withdraw-everything plus getReward.

## Known behaviours worth understanding before reusing

- **Rounding leaks dust.** Integer division in `rewardPerToken` leaves a few wei
  behind; this is normal and matches the original implementation.
- **No lock-up.** Stake and withdraw are always available. Adding a lock changes
  the reward maths because the snapshot has to happen at unlock time.
- **`rewardRate` truncates.** If `reward < duration` then `rewardRate` is zero
  and nothing accrues. Fund realistically or use a larger scaling factor.
- **Token transfers use a low-level call** so the contract works with non-standard
  ERC-20s that return no data. It does not protect against reentrant tokens.

## Development

```bash
forge install foundry-rs/forge-std
forge test -vvv
```

## License

MIT
