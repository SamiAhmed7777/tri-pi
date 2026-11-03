# TRI-PI legacy artifacts (rollback)

The files here are from the LEGACY era: the C++ `trianglesd` client
(triangles_v5 v6.2.6.6, ARM64) and its packaging. TRI-PI now ships **tri7d**
(the modern Rust full-node client from github.com/SamiAhmed7777/tri7) —
see the repo README for ports (RPC 19112 / P2P 24113 / tor SOCKS 9050),
systemd wiring, and the TRI7-era sync story.

Rollback: copy `bin/trianglesd` back to `/usr/local/bin/trianglesd` and
restore the pre-TRI7 systemd unit from your last legacy release tarball
(tri-pi <= v6.2.6.6). The legacy daemon used `-daemon/-datadir` CLI flags,
P2P 24112, RPC 19199 — none of which apply to tri7d.
