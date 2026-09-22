# TODO - PLD Linux

## Repository

- Add a contribution policy and minimal CI: syntax checks, Python tests, and
  `ansible-lint`.
- Normalize role variable names and long YAML lines instead of silencing lint
  rules with a global `skip_list`.
- Before each release, run a secrets scan and manually review inventory,
  examples, documentation, and Git history.
- Retain only documentation addresses from RFC 5737 ranges; production data
  belongs in private inventory outside the repository.

## Packages

- Keep application, DNS, MTA, and backup roles as separate owner-managed
  components rather than part of the base system profile.
- Design a read-only reporter for potentially orphaned RPM libraries, for
  example `scripts/pld_rpm_orphan_report.py`.

The reporter must work offline against the local RPM database, analyze names
and `PROVIDENAME` capabilities, protect the baseline and active services, and
report candidates only. It must not perform `erase`, modify the cache, or
recommend automatic removal.

## Monitoring

- Document a versioned capabilities contract between the NRPE agent and central
  monitoring without placing production data in this repository.
- Add a clean PLD machine integration test for the base profile, hardening, and
  monitoring.
