# pam-watchid

A PAM module, written in Swift, for Apple Watch and Touch ID authenticating using:
- `kLAPolicyDeviceOwnerAuthenticationWithBiometricsOrWatch` from macOS 10.15 to macOS 14; or
- `kLAPolicyDeviceOwnerAuthenticationWithBiometricsOrCompanion` in macOS 15 or later

![](https://github.com/mostpinkest/pam-watchid/blob/docs/demo.gif?raw=true)

## About this fork

This is a pinned, hardened fork of [mostpinkest/pam-watchid](https://github.com/mostpinkest/pam-watchid).
It is built by the `pam-watchid` formula in [seanb4t/homebrew-tap](https://github.com/seanb4t/homebrew-tap)
and wired into `/etc/pam.d/sudo_local` by configuration management, not by this repository.

Differences from upstream:

- **Caller guard.** The module skips (`PAM_IGNORE`, so the chain moves on to the password) before
  any prompt unless the request comes from the user logged in at the console, on a terminal,
  outside an SSH session. Upstream prompts the console for any caller, including another admin
  or a `sudo` run over SSH. `make check` runs the guard cases without touching `/etc/pam.d`.
- **No self-installation.** `install.sh` (a `curl | bash` of a moving branch) and `make enable`
  (which edited `sudo_local`) are removed. `make install` only installs the module.
- **Makefile** reads the `version` file with the right case, and builds an optimised module for
  the host architecture only (macOS 27 toolchains cannot link the x86_64 slice of a universal build).
- **CI** builds and runs the guard check; it never installs into the runner's PAM configuration.

The Swift module otherwise tracks upstream; merging a new upstream revision means re-reading
`Sources/pam-watchid/pam_watchid.swift` and re-running `make check`.

## Prerequisites

* The most up to date version of either Xcode or the Xcode command line tools (CLT) for your version of macOS. This includes all of the tools needed to build the module, including `swiftc`, `make`, and `git`. If you do not yet have either installed, you should be prompted automatically to install teh CLT when you first try to follow the [install instructions](#installation). You can also install the CLT manually with the following command:

```sh
xcode-select --install
```

## Installation

### Homebrew

```sh
brew install seanb4t/tap/pam-watchid
```

The formula builds the module into the Homebrew prefix, which your user can write to. Copy it
somewhere root-owned before PAM loads it, for example:

```sh
sudo install -d -o root -g wheel -m 0755 /usr/local/lib/pam
sudo install -o root -g wheel -m 0444 "$(brew --prefix)/lib/pam/pam_watchid.so.2" /usr/local/lib/pam/
```

Every directory on that path must be root-owned and not group- or world-writable.

### Nix

Upstream's module (without this fork's guard) is available from nixpkgs as `pam-watchid` and can be enabled using nix-darwin's [`security.pam.services.sudo_local.watchIdAuth`](https://nix-darwin.github.io/nix-darwin/manual/#opt-security.pam.services.sudo_local.watchIdAuth)

### Manual
1. Run inside a cloned copy of the repo: 
```sh
make install
```
2. Modify the sudo pam config to include the module by its full path, after `pam_tid.so`:
  ```
  auth       sufficient     pam_tid.so
  auth       sufficient     /usr/local/lib/pam/pam_watchid.so.2
  ```
   * *On macOS 14 and later:* Create/edit `/etc/pam.d/sudo_local`. Stock `/etc/pam.d/sudo` includes it first, so leave `/etc/pam.d/sudo` itself alone.
   * *On macOS 13 and earlier:* Edit `/etc/pam.d/sudo` to include both lines at the top.
   * Keep every line `sufficient`, never `required`, so a broken module still reaches the password prompt.

> [!IMPORTANT]
> Note that you might have other `auth` statements, **don't remove them**.
