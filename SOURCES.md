# Sources and history

Merged on 2026-10-29. Each source history is retained as a merge parent; no source repository was deleted or archived.

| Original repository | Imported commit | Module |
| --- | --- | --- |
| [ridaiqianhe/vps-proxy](https://github.com/ridaiqianhe/vps-proxy) | `eccc5e02ffcbe803ab1f477c9dbfb6aafe182a1d` | `modules/vps-proxy` |
| [ridaiqianhe/random-ipv6-socks](https://github.com/ridaiqianhe/random-ipv6-socks) | `06db0da37069b0a04e7d274e08e6d0c682b3c273` | `modules/random-ipv6-socks` |
| [ridaiqianhe/realm](https://github.com/ridaiqianhe/realm) | `d414fdc68998b2d079096e3f8f410325daccb4ff` | `modules/realm` |
| [ridaiqianhe/ssh_changepassword](https://github.com/ridaiqianhe/ssh_changepassword) | `e811d4536d4cadab4a9f5f82e86dde40a3f8fd48` | `modules/ssh` |

The original random-ipv6-socks module retains its MIT license and third-party notices. The other original repositories did not include a standalone license file at import; their existing history and attribution are preserved. No new blanket license is applied to third-party components.

OpsBox adds a common launcher and installer, relocates workflows to the repository root, and replaces the old SSH script with explicit, validated operations. Realm retains its original pinned installer; the self-deletion on uninstall is removed.

## DMITBox system module

On 2026-10-29, integrated the user-supplied DMITBox `2026.08.14` script into `modules/system/`. The user identified the original distribution URL as <https://box.dmitstock.com/>. Preserve the original author's provenance; this addition does not apply a new blanket license to third-party code.

Original attachment SHA-256: `c7b0c85b95d3d4c348d4c38371bba8af27b2346bbac868095631e2b72db788a9`.

The attachment had UTF-8/GB18030 mojibake. The import restores encoding, rewrites unrecoverable display text, removes superseded automatic site-stop implementations, and replaces the startup dispatcher with OpsBox's explicit module dispatcher. Legacy configuration paths and ownership markers remain intact for compatibility. The distribution endpoint returned a Cloudflare challenge during verification, so its response was not executed or imported.

## Realm Gist replacement

The Realm module was replaced on 2026-10-29 with the user's Gist `cf516fc8182035c7cabfbe80fab163db`, revision `db2e7308a6a7c90a2b68ce0deb53f62084c89e62`. The standalone source is retained at `modules/realm/realm.sh`; it no longer depends on the Gist URL.

Imported download SHA-256: `c41eb9ac18d458ef271800730adb92c9b6078d774cb8d7676bd891d11d83bf8b`.

The import retains the source's management, update and rule operations. Integration changes preserve existing `/etc/realm` or `/root/realm` installations, require confirmation before uninstalling, prevent deletion of the script itself, and allow safe sourcing for tests.
