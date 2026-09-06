# `.probe` SCR agent for the Arch port

Replaces yast2-core's hwinfo-backed `.probe` agent, which cannot exist on Arch
because hwinfo is not packaged. Without it every `SCR.Read(.probe.*)` returns nil.

## Files

| file | install to |
|---|---|
| `servers_non_y2/ag_probe` | `prefix/lib/YaST2/servers_non_y2/ag_probe` (`Directory.agentdir`), `install -Dm755` |
| `scrconf/probe.scr` | `prefix/destdir/usr/share/YaST2/scrconf/probe.scr`, `install -Dm644` |

`.probe` is not claimed by any other `.scr`, so mounting it displaces nothing.

## Paths answered

| path | type | source |
|---|---|---|
| `.probe.architecture` | string | `uname -m` via `%UNAME_TO_YAST_ARCH` |
| `.probe.netcard` | list of maps | `/sys/class/net/*` (only those with a `device/` link) |
| `.probe.disk` | list of maps | `/sys/block/*` (real devices, size > 0, not `sr*`) |
| `.probe.system` | list of maps | `/sys/class/dmi/id` |
| `.probe.is_xen` | boolean | `/sys/hypervisor/type`, `/proc/xen` |
| `.probe.is_vmware` | boolean | `systemd-detect-virt --vm`, DMI vendor |

Every other `.probe` path returns nil via `YaST::SCRAgent`'s default `Read`,
which is exactly what callers get today. `.probe.status.*` accepts and drops
writes (`HwStatus#Save`) so it does not spam the log.

## Why these two paths are not optional

* `Arch.rb#architecture` — nil makes `Arch.x86_64` / `Arch.efi` and every
  downstream decision silently wrong.
* `IscsiClientLib#potential_offload_cards` — calls `.map` on the result, so nil
  raises `NoMethodError` and kills the iSCSI offload tab.

## Two things to know before editing

1. **Booleans and integers must be scalar refs.** `SCRAgent::Run` calls
   `ycp::Return($ret, 1)` — `quote_everything` is true, so a plain Perl scalar
   is serialized as a YCP *string*. A plain `0` for `.probe.is_xen` arrives as
   `"0"`, and `Convert.to_boolean("0")` is nil, not false. Use `bool()` / `int_()`.
2. **The architecture map is a deliberate copy** of `UNAME_TO_YAST_ARCH` in
   `Arch.rb` (patch `10-`). Perl cannot import the Ruby table, and `Arch.rb`'s
   own fallback must keep working when this agent is not mounted. Run
   `ag_probe --selftest` to print the map and check the two still agree.

## Verifying

    ag_probe --selftest        # no SCR, prints every path in YCP form

    Y2DIR=<this dir>:$P/share/YaST2 ruby -e \
      'require "yast"; include Yast; p SCR.Read(path(".probe.netcard"))'

`SELFTEST.txt` holds both, run as the unprivileged user against real hardware.
