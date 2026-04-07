# CLAUDE.md

## What is Parallel::Subs

A simple Perl module that wraps `Parallel::ForkManager` to run subroutines in
parallel and collect their return values. Supports callbacks, method chaining,
and memory-aware process limits.

Single module: `lib/Parallel/Subs.pm`. No submodules.

## Commands

```bash
# Run tests
prove -lr t/

# Run a single test
perl -Ilib t/edge-cases.t

# Build with Dist::Zilla (requires Perl >= 5.20)
dzil build --in build
cd build && prove -lr t/

# Check POD
podchecker lib/Parallel/Subs.pm
```

## Architecture

- **`lib/Parallel/Subs.pm`** — entire module (single file)
- **`t/`** — test suite using Test2::V0
- **`dist.ini`** — Dist::Zilla build config
- **`cpanfile`** — runtime and test dependencies
- **`.github/cpanfile.ci`** — CI-specific deps (includes dzil plugins)

## Dependencies

- **Runtime**: `Parallel::ForkManager`, `Sys::Info` (CPU detection)
- **Optional**: `Sys::Statistics::Linux::MemStats` (Linux-only memory detection)
- **Test**: `Test2::V0`

## Testing

- Framework: **Test2::V0** (not Test::More)
- Use `dies {}` for testing croak/die behavior
- **Fork testing caveat**: `exit()` in child forks triggers Test2's END blocks.
  Use `POSIX::_exit()` in child subs or `eval {}` patterns when testing failures
  under PFM.
- Tests run on Linux CI (Perl 5.14+). No Windows support.
- `Sys::Info` may produce warnings on macOS — harmless, falls back.

## CI

- GitHub Actions (`.github/workflows/ci.yml`)
- Dynamic Perl version matrix via `perl-actions/perl-versions@v2` (5.14+)
- Runs in `perldocker/perl-tester` containers
- Dist::Zilla build only on Perl >= 5.20 (older Perls run `prove` directly)

## Conventions

- Minimum Perl: **5.10** (declared in dist.ini)
- Method chaining: `add()`, `wait_for_all()` return `$self`
- Jobs stored as hashrefs `{ name => N, code => \&sub }` in `$self->{jobs}`
- Results keyed by job name in `$self->{result}`, sorted numerically by `results()`
- `run_on_finish` callback handles result collection from child processes
- Constructor options: `max_process`, `max_process_per_cpu`, `max_memory`,
  `waitpid_blocking_sleep`
- `max_process` and `max_process_per_cpu` are mutually exclusive in intent
  (though not enforced on master yet)

## Key design decisions

- `add()` croaks on non-CODE input — this is deliberate, not a bug
- `wait_for_all_optimized()` groups jobs per CPU for fewer forks — beta feature,
  does not support callbacks (warns and clears them)
- Error handling in `run_on_finish` currently dies on job failure — this kills
  the parent mid-wait (known issue, fix in progress)
- `Sys::Info` fallback: if CPU detection fails, defaults to 1 process
