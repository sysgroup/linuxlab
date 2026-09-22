# PLD Linux hardening

`pld-hardening.yml` applies an SSH, sysctl, fail2ban, and auditd baseline to
PLD Linux Th with systemd. The role uses its own RPM names and paths, so it
does not depend on a Debian/Ubuntu hardening role.

## Requirements

- PLD Linux Th with systemd;
- Poldek installed;
- a non-root account with sudo. By default, the role expects `pld-admin`; set
  `pld_admin_user` and `ansible_user` if you use a different name.

## Scope

- installs `openssh-server`, `fail2ban`, and `audit` through `pld_poldek`;
- validates the SSH and fail2ban configuration before deployment;
- applies an explicit sysctl baseline;
- configures auditd and log retention;
- does not change the firewall policy or `AllowUsers`.

## Safe rollout

```bash
ansible-playbook -i inventory/local.yml playbooks/pld-hardening.yml -e target_hosts=pld --list-hosts
ansible-playbook -i inventory/local.yml playbooks/pld-hardening.yml -e target_hosts=pld --check --diff
ansible-playbook -i inventory/local.yml playbooks/pld-hardening.yml -e target_hosts=pld --diff
```

After deployment, use a separate SSH session to verify administrative account
access and service status:

```bash
ansible -i inventory/local.yml pld --become -m command -a 'fail2ban-client status sshd'
ansible -i inventory/local.yml pld --become -m command -a '/sbin/auditctl -s'
```

## Files from an earlier version

The role writes `00-pld-hardening.conf`, `60-pld-hardening.conf`,
`99-pld-hardening.local`, and `10-pld-base.rules`, `30-pld-hardening.rules`,
`99-pld-finalize.rules`. If a host already carries the same settings under
other names, list those files in `pld_hardening_legacy_files`:

```yaml
pld_hardening_legacy_files:
  - /etc/fail2ban/jail.d/99-old-hardening.local
  - /etc/audit/rules.d/30-old-hardening.rules
```

Otherwise the old copies stay active next to the new ones: fail2ban and sshd
read their directories in name order, so a file sorted later would override
the managed jail, and `augenrules` would load every audit rule twice. Each
component removes only entries in its own directory, after its own file is in
place, and then reloads the service. The list accepts only a file directly in
`/etc/ssh/sshd_config.d`, `/etc/sysctl.d`, `/etc/fail2ban/jail.d`, or
`/etc/audit/rules.d` that the role does not manage.

A sysctl value set only by a removed file stays in the running kernel until
the next boot.

## Tags

`packages`, `sshd`, `sysctl`, `fail2ban`, `auditd`, `verify`.
