# Ansible for PLD Linux

Standalone playbooks for PLD Linux Th with systemd. This directory includes
its own roles, inventory, Poldek module, and tests, and does not depend on
the rest of the repository. Run every command below from this directory.

## Quick start

1. Install the required collections:

   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```

2. Create a private inventory that Git ignores:

   ```bash
   cp inventory/local.example.yml inventory/local.yml
   ```

3. In `inventory/local.yml`, replace `pld.example.net`, `192.0.2.10`, and the
   example settings with values for your host. Keep private-key paths in your
   SSH agent, SSH configuration, or a controller environment variable. Verify
   the host SSH key fingerprint outside Ansible and add the trusted key to
   `known_hosts`; host-key checking is intentionally enabled.

   ```bash
   ansible-inventory -i inventory/local.yml --host your-host.example.net
   ```

4. Before running the playbooks, the host must have working Python 3, Poldek,
   and a non-root SSH account with `sudo`. The default account name is
   `pld-admin`; override it through `ansible_user` and `pld_admin_user` in the
   inventory if needed.

5. First, run the preflight for the base profile and hardening:

   ```bash
   ansible-playbook -i inventory/local.yml playbooks/pld-build-sysbase.yml -e target_hosts=pld --check --diff
   ansible-playbook -i inventory/local.yml playbooks/pld-hardening.yml -e target_hosts=pld --check --diff
   ```

After reviewing the result, run the same commands without `--check --diff`.
Hardening does not create administrative accounts or change the base firewall
policy.

6. Monitoring is optional. After setting `nrpe_allowed_hosts` and
   `nrpe_ntp_server`, run its preflight:

   ```bash
   ansible-playbook -i inventory/local.yml playbooks/pld-setup-monitoring.yml -e target_hosts=pld --check --diff
   ```

## Tested on

PLD Linux Th (release 3.0) with systemd, OpenSSH 10.5p1, fail2ban 1.1.1,
audit 4.2.1, and NRPE 4.1.3: check mode, a full run of all three playbooks,
and a second run that reported no changes. Controller: ansible-core 2.21.3
with community.general 13.3.0.

## Packages and monitoring

The local [pld_poldek.py](plugins/modules/pld_poldek.py) module queries the RPM
database once and installs all missing exact package names in a single Poldek
transaction. In check mode it runs `poldek --test`. The module deliberately
does not support package removal.

Before applying monitoring, set `nrpe_allowed_hosts` to the addresses of
monitoring servers as seen by the host. The optional `nrpe_bind_address`
restricts NRPE to one listening address. Without a non-empty
`nrpe_allowed_hosts`, the role does not manage the NRPE access policy.

The monitoring playbook also requires `nrpe_ntp_server` in the inventory; the
repository does not choose a default external time server.

More information: [packages](docs/pld-packages.md),
[hardening](docs/pld-hardening.md), and [TODO](TODO-PLD.md).

## License

Apache License 2.0, see [LICENSE](../LICENSE).
