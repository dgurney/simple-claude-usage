# Claude Usage

A macOS menu bar app that shows how much of your Claude plan's usage limits
is left.

The menu bar shows what's left of your 5-hour session and weekly limits.
Click it to see every limit, when each one resets, and the current
[Claude status](https://status.claude.com). Usage refreshes every 5 minutes,
and when you open the menu if it's more than a minute old.

There's also a [GNOME version](https://github.com/dgurney/gnome-claude-usage).

## Requirements

- macOS 26 or later
- [Claude Code](https://claude.com/claude-code), signed in with your Claude
  subscription
- Xcode 27 or later, to build

## Install

```sh
make install
```

Then open Claude Usage from Applications. To start it when you log in,
choose Settings… in its menu and turn on Open at login. To update, quit the
app and run `make install` again.

## Sign-in

The app uses the sign-in that Claude Code keeps in your login keychain, and
reads it the same way Claude Code does, so macOS won't ask for keychain
access. The sign-in is only ever sent to Anthropic.

When the sign-in expires, the app runs `claude doctor` in the background to
renew it, at most once every 5 minutes. It never renews the sign-in itself,
as that could replace the tokens Claude Code relies on. `claude doctor` is
run through your login shell, so `claude` needs to be on the PATH your
terminal uses.

If the menu says Claude Code isn't signed in, or the sign-in can't be
renewed, run `claude` in a terminal.

## Troubleshooting

Problems reaching the servers, reading the keychain, or renewing the sign-in
are logged:

```sh
log stream --predicate 'subsystem == "dev.gurney.claude-usage"'
```

## Development

```sh
make test   # run the tests
make run    # build build/Claude Usage.app and open it
```

## License

MIT
