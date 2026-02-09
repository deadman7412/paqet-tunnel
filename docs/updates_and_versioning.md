# Updates and Versioning

## Update Paqet (Menu)

- Use `Update Paqet` from main menu.
- Keep server and client on the same Paqet version.
- If a tarball exists in `~/paqet`, updater uses it instead of downloading.

## Update Paqet (Manual)

```bash
systemctl stop paqet-server.service 2>/dev/null || true
systemctl stop paqet-client.service 2>/dev/null || true
cd ~/paqet
rm -f ~/paqet/paqet
tar -xvzf paqet-linux-<arch>-<version>.tar.gz
mv paqet_linux_<arch> paqet
chmod +x paqet
[ -f ~/paqet/server.yaml ] && systemctl restart paqet-server.service
[ -f ~/paqet/client.yaml ] && systemctl restart paqet-client.service
```

## Update Scripts

- Use `Update Scripts (git pull)` from main menu.

## Versioning

Project version uses git tags + `git describe`.

Example:

```text
v0.6.2-14-g3a9b8c1
```

If running from ZIP (without `.git`), menu reads `VERSION`.

Optional pre-push hook:

```bash
cp scripts/hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```
