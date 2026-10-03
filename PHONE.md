# 📱 Phone setup (Android)

From a stock Android phone to `mosh nomad` in about 10 minutes. No root.

You need the box running (`make up` on your computer) and the **Tailscale** app
on your phone (Play Store), signed in to the same account and switched on.

---

## 1. Install Termux (from F-Droid, not the Play Store)

The Play Store's Termux is an old, cut-down build. Get the real one from F-Droid:

1. On your phone, open **https://f-droid.org**, download the F-Droid app and
   install it (allow "install unknown apps" for your browser, once).
2. In F-Droid, search **Termux** and pick the one that is exactly:
   - **Termux**, no colon (skip Termux:API, Termux:Boot and the other add-ons)
   - "Terminal emulator with packages", package `com.termux`
   - the suggested **stable** version (0.118.x), not a beta

<details>
<summary>Warnings you will see, and why they are fine</summary>

- **"Unsafe app, built for an older version of Android"**: tap **Install
  anyway**. Termux targets an older Android version on purpose so it can run
  programs; it is a sign of the real Termux, not malware.
- **"Cannot be updated automatically"**: same reason. You tap to confirm updates
  in F-Droid instead.
- **An old security advisory** affects versions up to 0.117; 0.118 is fixed.

</details>

## 2. Set up Termux, once

Open Termux and paste:

```sh
pkg update -y && pkg upgrade -y && pkg install -y openssh mosh
mkdir -p ~/.ssh && printf 'Host nomad\n  User ubuntu\n' >> ~/.ssh/config
```

(If it asks about keeping a config file, press enter.) The second line is the
shortcut that lets you type `nomad` instead of `ubuntu@nomad`.

**Extra keys**: Termux shows a row of keys above the keyboard. For one with Esc,
Ctrl, Tab, arrows and `/ - |` within thumb reach, paste this too:

```sh
mkdir -p ~/.termux && echo "extra-keys = [['ESC','/','-','|','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]" >> ~/.termux/termux.properties && termux-reload-settings
```

## 3. Connect

With the Tailscale app on:

```sh
mosh nomad
```

The first time, type **yes** to trust the box. If your tailnet has SSH check mode
on, a browser opens to approve you; approve it (or turn check mode off, see the
README's one-time security list).

mosh keeps your session alive when you switch between wifi and cellular, and
echoes your typing instantly. `ssh nomad` also works.

## 4. You are in

You land in the **session menu**: pick a running session to land back where you
left off, or **+ new session** to start Claude Code. Each Termux tab (swipe from
the left edge, **New session**) can run a different one. Enter opens, ctrl-x
kills, ctrl-r renames, esc gives a plain shell; inside tmux, ctrl-b then S brings
the menu back.

To sign in to your CLIs, run **`auth`**. Each sign-in shows a short link,
`http://nomad:8085`; open it in your phone's browser, sign in, and paste the code
back into Termux if asked.

---

## Tips

- **Ctrl**: the CTRL key in the extra-keys row, or hold **volume down**.
- **Scrolling**: swipe in the terminal; tmux mouse mode is on, so you can tap
  between panes too.
- **The voice loop**: dictate prompts to Claude (e.g. with Wispr), let it run
  (`claw` skips permission prompts), glance at the output. Voice for the words,
  taps only for control keys like ctrl-c.
- **Do not root your phone.** It is now the key to your dev box.

## Troubleshooting

- **`nomad` does not resolve**: use its tailnet IP. Find the `100.x.y.z` address
  for `nomad` in the Tailscale app, then `mosh ubuntu@100.x.y.z`.
- **Cannot reach the box**: check the Tailscale app is on, and `nomad` shows as
  online in it.
- **mosh: "needs a UTF-8 native locale"**: `LC_ALL=C.UTF-8 mosh nomad`.
- **"Permission denied" or asks for a password**: the shortcut is missing, so it
  tried your phone's username. Re-run the `printf` line from step 2, or use
  `mosh ubuntu@nomad`.
