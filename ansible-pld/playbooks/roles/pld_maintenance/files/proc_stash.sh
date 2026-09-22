#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# proc_stash records a frequent local system snapshot for post-incident
# analysis. Keep collectors bounded, password-free, and limited to LOGDIR.
# Section headers and metrics.csv columns are a parsing contract: append new
# columns only, and retain the existing section-header format.

set -u
umask 077

# LC_ALL=C keeps decimal values compatible with comma-separated metrics.csv
# and stabilizes collected command output.
export LC_ALL=C

# This override supports contract tests without writing to /var/log. The systemd
# unit does not set this variable, so the production path remains unchanged.
LOGDIR=${PROC_STASH_LOGDIR:-/var/log/ps}

# Bound each collector; the systemd unit provides an independent total timeout.
CMD_TIMEOUT=20

# No lockfile is needed: systemd does not overlap runs of the same service.
# A cron implementation would need robust locking and stale-lock handling.

DATE=$(date +"%Y-%m-%d")
TIME=$(date +"%H-%M-%S")
DAYDIR="${LOGDIR}/${DATE}"
mkdir -p "$DAYDIR"

# ---------------------------------------------------------------------------
# metrics.csv - compact time series for trend analysis
# ---------------------------------------------------------------------------
# metrics.csv is a compact time series; most values come from /proc. Commands
# that may block use a timeout.
CSV="${DAYDIR}/metrics.csv"
CSV_HEADER="ts,load1,load5,load15,procs_run,procs_total,mem_avail_pct,swap_used_pct,tcp_inuse,tcp_tw,cpu_user,cpu_sys,cpu_iowait,cpu_steal,cpu_idle,disk_rd_sect,disk_wr_sect,disk_io_ms,root_used_pct,net_rx_bytes,net_tx_bytes,net_drop,psi_cpu,psi_io,psi_mem,procs_blocked,pgmajfault,oom_kill,file_nr,listen_overflows,listen_drops,ct_count,ct_max,uptime_s,failed_units,reboot_required,cores,mail_queue_count,mail_queue_oldest_s"

# Do not mix schema versions in one daily CSV. On a header change, retain the
# old file beside the new metrics.csv.
if [ -f "$CSV" ]; then
    read -r _hdr < "$CSV" || _hdr=""
    if [ "$_hdr" != "$CSV_HEADER" ]; then
        mv -f "$CSV" "${CSV}.${TIME}.old" 2>/dev/null
    fi
fi
[ -f "$CSV" ] || echo "$CSV_HEADER" > "$CSV"

# Use whole block devices from /sys/block to avoid double-counting partitions.
# Exclude md devices because their component disks already contribute metrics.
DISKS=" "
for _d in /sys/block/*; do
    [ -e "$_d" ] || continue
    _d=${_d##*/}
    case "$_d" in loop*|ram*|sr*|dm-*|zram*|md*) continue ;; esac
    DISKS="${DISKS}${_d} "
done

# Root usage is recorded for trend analysis. The timeout covers df itself.
_root_df=$(timeout "$CMD_TIMEOUT" df -P / 2>/dev/null)
_root_df_rc=$?
if [ "$_root_df_rc" -eq 0 ]; then
    ROOT_USED=$(printf '%s\n' "$_root_df" \
        | awk 'END { sub(/%/, "", $5); print $5 + 0 }')
    case "$ROOT_USED" in ''|*[!0-9]*) ROOT_USED=-1 ;; esac
else
    # Do not record a healthy-looking zero after a collector timeout or error.
    ROOT_USED=-1
fi

# conntrack files exist only when the kernel feature is available; pass them to
# awk only when present.
CT_FILES=""
if [ -r /proc/sys/net/netfilter/nf_conntrack_count ]; then
    CT_FILES="/proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/netfilter/nf_conntrack_max"
fi

# Count failed units separately from snapshot commands.
_failed_output=$(timeout "$CMD_TIMEOUT" systemctl list-units --failed \
    --no-legend --plain 2>/dev/null)
_failed_rc=$?
if [ "$_failed_rc" -eq 0 ]; then
    FAILED_UNITS=$(printf '%s\n' "$_failed_output" \
        | awk 'NF { n++ } END { print n + 0 }')
else
    # -1 is a collector error; 0 is reserved for a healthy system.
    FAILED_UNITS=-1
fi

# Local mail queue. A count without an age cannot distinguish a transient burst
# from an outage lasting months, so record both values. Do not connect to the
# network or read message contents. `-1` means a collector error; `0` means no
# MTA or an empty queue.
#
# Postfix `postqueue -j` provides the real arrival_time. For Exim, the fourth
# line of a `*-H` file begins with the message acceptance epoch. Do not use the
# file mtime: Exim rewrites `-H` after delivery attempts, which would understate
# the age.
MAIL_QUEUE_BACKEND=none
MAIL_QUEUE_COUNT=0
MAIL_QUEUE_OLDEST_S=0
_mail_oldest_epoch=0

if command -v exim4 >/dev/null 2>&1 || command -v exim >/dev/null 2>&1; then
    MAIL_QUEUE_BACKEND=exim
    if command -v exim4 >/dev/null 2>&1; then
        _exim=exim4
        _exim_spool=/var/spool/exim4/input
    else
        _exim=exim
        _exim_spool=/var/spool/exim/input
    fi
    _mail_count=$(timeout "$CMD_TIMEOUT" "$_exim" -bpc 2>/dev/null)
    _mail_rc=$?
    case "$_mail_count" in
        ''|*[!0-9]*) MAIL_QUEUE_COUNT=-1; MAIL_QUEUE_OLDEST_S=-1 ;;
        *)
            if [ "$_mail_rc" -eq 0 ]; then
                MAIL_QUEUE_COUNT=$_mail_count
                if [ "$MAIL_QUEUE_COUNT" -gt 0 ]; then
                    _mail_epochs=$(timeout "$CMD_TIMEOUT" find "$_exim_spool" \
                        -type f -name '*-H' -exec awk '
                            FNR == 4 {
                                if ($1 ~ /^[0-9]+$/) print $1
                                nextfile
                            }
                        ' {} + 2>/dev/null)
                    _mail_epoch_rc=$?
                    if [ "$_mail_epoch_rc" -eq 0 ]; then
                        _mail_oldest_epoch=$(printf '%s\n' "$_mail_epochs" \
                            | sort -n | head -n 1)
                    else
                        # Do not treat a partial result after a timeout as a
                        # reliable oldest timestamp.
                        _mail_oldest_epoch=invalid
                    fi
                fi
            else
                MAIL_QUEUE_COUNT=-1
                MAIL_QUEUE_OLDEST_S=-1
            fi
            ;;
    esac
elif command -v postqueue >/dev/null 2>&1; then
    MAIL_QUEUE_BACKEND=postfix
    _mail_json=$(timeout "$CMD_TIMEOUT" postqueue -j 2>/dev/null)
    _mail_rc=$?
    if [ "$_mail_rc" -eq 0 ]; then
        # One JSON line equals one message. The parser extracts only the
        # documented numeric arrival_time field; it does not interpret
        # addresses or causes.
        set -- $(printf '%s\n' "$_mail_json" | awk '
            BEGIN { count = 0; oldest = 0 }
            NF {
                count++
                if (match($0, /"arrival_time"[[:space:]]*:[[:space:]]*[0-9]+/)) {
                    value = substr($0, RSTART, RLENGTH)
                    gsub(/[^0-9]/, "", value)
                    if (oldest == 0 || value < oldest) oldest = value
                }
            }
            END { print count, oldest }
        ')
        MAIL_QUEUE_COUNT=${1:-0}
        _mail_oldest_epoch=${2:-0}
        if [ "$MAIL_QUEUE_COUNT" -gt 0 ] && [ "$_mail_oldest_epoch" -eq 0 ]; then
            MAIL_QUEUE_OLDEST_S=-1
        fi
    else
        # Older Postfix versions may not have -j. Preserve the count from the
        # classic summary, but do not pretend to know the age.
        _mail_count=$(timeout "$CMD_TIMEOUT" sh -c '
            postqueue -p 2>/dev/null | awk '\''
                /^Mail queue is empty$/ { value = 0; seen = 1 }
                /^-- .* in [0-9]+ Requests?\.$/ { value = $(NF - 1); seen = 1 }
                END { if (seen) print value }
            '\''
        ')
        case "$_mail_count" in
            ''|*[!0-9]*) MAIL_QUEUE_COUNT=-1 ;;
            *) MAIL_QUEUE_COUNT=$_mail_count ;;
        esac
        MAIL_QUEUE_OLDEST_S=-1
    fi
fi

case "$_mail_oldest_epoch" in
    ''|*[!0-9]*) MAIL_QUEUE_OLDEST_S=-1 ;;
    0) : ;;
    *)
        _mail_now=$(date +%s)
        if [ "$_mail_oldest_epoch" -le "$_mail_now" ]; then
            MAIL_QUEUE_OLDEST_S=$((_mail_now - _mail_oldest_epoch))
        else
            MAIL_QUEUE_OLDEST_S=-1
        fi
        ;;
esac

# A reboot-required marker is recorded when the platform provides one.
REBOOT_REQ=0
[ -f /var/run/reboot-required ] && REBOOT_REQ=1

# Record core count and use it for the relative load warning threshold.
CORES=$(nproc 2>/dev/null || echo 1)

# Use exact FILENAME comparisons: a loose /stat$/ pattern would also match
# /proc/net/sockstat. CPU, disk, and network counters are recorded raw; the
# consumer must treat a negative delta as a reboot.
awk -v ts="$TIME" -v disks="$DISKS" -v rootused="${ROOT_USED:-0}" \
    -v failed="${FAILED_UNITS:-0}" -v rebootreq="$REBOOT_REQ" -v cores="${CORES:-1}" \
    -v mailq="${MAIL_QUEUE_COUNT:--1}" -v mailoldest="${MAIL_QUEUE_OLDEST_S:--1}" '
    FILENAME == "/proc/loadavg" {
        l1 = $1; l5 = $2; l15 = $3
        split($4, p, "/"); prun = p[1]; ptot = p[2]
    }
    FILENAME == "/proc/meminfo" {
        if ($1 == "MemTotal:")     mt = $2
        if ($1 == "MemAvailable:") ma = $2
        if ($1 == "SwapTotal:")    st = $2
        if ($1 == "SwapFree:")     sf = $2
    }
    FILENAME == "/proc/net/sockstat" {
        if ($1 == "TCP:") { inuse = $3; tw = $7 }
    }
    FILENAME == "/proc/stat" && $1 == "cpu" {
        # user+nice, system+irq+softirq, iowait, steal, idle
        cu = $2 + $3; cs = $4 + $7 + $8; ciow = $6; cstl = $9; cidl = $5
    }
    # It is free because /proc/stat is already read. procs_blocked is the count
    # of processes in D state (uninterruptible I/O sleep), which explains load
    # spikes unrelated to CPU.
    FILENAME == "/proc/stat" && $1 == "procs_blocked" { pblk = $2 }
    FILENAME == "/proc/diskstats" {
        if (index(disks, " " $3 " ") == 0) next
        drd += $6; dwr += $10; dio += $13
    }
    FILENAME == "/proc/net/dev" {
        if (FNR <= 2) next                 # two header lines
        gsub(/:/, " ")                     # "eth0:123" -> "eth0 123"; awk splits it again
        if ($1 ~ /^(lo|docker|veth|br-|virbr|tun|tap|vnet)/) next
        nrx += $2; ntx += $10; ndrop += $5 + $13
    }

    # PSI reports directly how long tasks waited - unlike loadavg, which mixes
    # CPU work with disk waits. Use `some avg10`: a value already averaged by
    # the kernel and suitable for percentiles without further processing.
    FILENAME ~ /^\/proc\/pressure\// && $1 == "some" {
        split($2, pa, "=")
        if (FILENAME == "/proc/pressure/cpu")    psi_c = pa[2]
        if (FILENAME == "/proc/pressure/io")     psi_i = pa[2]
        if (FILENAME == "/proc/pressure/memory") psi_m = pa[2]
    }
    FILENAME == "/proc/vmstat" {
        # pgmajfault = pages read from disk, the painful form of memory
        # pressure. oom_kill counts actual kills.
        if ($1 == "pgmajfault") pgmf = $2
        if ($1 == "oom_kill")   oomk = $2
    }
    FILENAME == "/proc/sys/fs/file-nr"                        { fnr = $1 }
    # uptime turns reboot detection from an assumption into a fact: the
    # analyzer does not have to infer it from a counter moving downward.
    FILENAME == "/proc/uptime"                                { upt = $1 }
    FILENAME == "/proc/sys/net/netfilter/nf_conntrack_count"  { ctc = $1 }
    FILENAME == "/proc/sys/net/netfilter/nf_conntrack_max"    { ctm = $1 }

    # An overflowing accept queue is exactly how a connection flood appears
    # from the kernel perspective. The first TcpExt line has names, the
    # second has values.
    FILENAME == "/proc/net/netstat" && $1 == "TcpExt:" {
        if (!te_hdr) {
            for (i = 2; i <= NF; i++) {
                if ($i == "ListenOverflows") te_o = i
                if ($i == "ListenDrops")     te_d = i
            }
            te_hdr = 1
        } else if (!te_val) {
            lov = (te_o ? $te_o : 0); ldr = (te_d ? $te_d : 0)
            te_val = 1
        }
    }
    END {
        mem_avail = (mt > 0) ? 100 * ma / mt : 0
        swap_used = (st > 0) ? 100 * (st - sf) / st : 0
        printf "%s,%s,%s,%s,%s,%s,%.1f,%.1f,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%s,%d,%d,%d,%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n", \
               ts, l1, l5, l15, prun, ptot, mem_avail, swap_used, \
               (inuse == "" ? 0 : inuse), (tw == "" ? 0 : tw), \
               cu, cs, ciow, cstl, cidl, drd, dwr, dio, rootused, nrx, ntx, ndrop, \
               (psi_c == "" ? 0 : psi_c), (psi_i == "" ? 0 : psi_i), (psi_m == "" ? 0 : psi_m), \
               pblk, pgmf, oomk, fnr, lov, ldr, ctc, ctm, \
               upt, failed, rebootreq, cores, mailq, mailoldest
    }
' /proc/loadavg /proc/meminfo /proc/net/sockstat /proc/stat /proc/diskstats /proc/net/dev \
  /proc/pressure/cpu /proc/pressure/io /proc/pressure/memory \
  /proc/vmstat /proc/sys/fs/file-nr /proc/net/netstat /proc/uptime $CT_FILES \
  >> "$CSV" 2>/dev/null

# ---------------------------------------------------------------------------
# Snapshot
# ---------------------------------------------------------------------------
# The filename includes integer load for quick inspection; metrics.csv holds
# the precise time series.
LOAD=$(awk -F '.' '{ print $1 }' /proc/loadavg)
FILE="${DAYDIR}/${TIME}.${LOAD}.txt"

# Each command has a header and a timeout; record a timeout explicitly.
run() {
    printf '# %s %s\n' "$*" '#########################################' >> "$FILE"
    timeout "$CMD_TIMEOUT" "$@" >> "$FILE" 2>&1
    if [ $? -eq 124 ]; then
        echo "(TIMEOUT after ${CMD_TIMEOUT}s - command hung, section incomplete)" >> "$FILE"
    fi
}

run_if_present() {
    if command -v "$1" >/dev/null 2>&1; then
        run "$@"
    else
        printf '# %s %s\n' "$*" '#########################################' >> "$FILE"
        printf '(skipped: command is not installed)\n' >> "$FILE"
    fi
}

uptime > "$FILE" 2>&1

printf '# mail queue summary %s\n' '###################################' >> "$FILE"
printf 'backend=%s count=%s oldest_s=%s\n' \
    "$MAIL_QUEUE_BACKEND" "$MAIL_QUEUE_COUNT" "$MAIL_QUEUE_OLDEST_S" >> "$FILE"

run ps aux
run ps arx -O wchan

# Do not use run() here: the glob could expand to thousands of paths.
printf '# grep /proc/*/attr/current %s\n' '##############################' >> "$FILE"
timeout "$CMD_TIMEOUT" grep "" /proc/*/attr/current >> "$FILE" 2>&1

# Keep only recent dmesg lines: the kernel buffer is mostly repeated between
# snapshots, while a large change is itself useful evidence.
printf '# dmesg -T (last 200 lines) %s\n' '##########################' >> "$FILE"
timeout "$CMD_TIMEOUT" dmesg -T 2>>"$FILE" | tail -n 200 >> "$FILE"

run vmstat --stats
run vmstat --active
run vmstat --slabs
run mpstat -P ALL
run iostat -k -p ALL
# bsd-finger is intentionally not part of the PLD baseline. Retain the
# diagnostic when an operator installs it, but do not make snapshots depend on it.
run_if_present finger -l
run slabtop -o

# ss -s provides a compact view of connection pressure.
run ss -s
run df -h

# ---------------------------------------------------------------------------
# High-load marker
# ---------------------------------------------------------------------------
# Scale the warning threshold with CPU count. The .WARNING file includes uptime
# so it can be reviewed without opening a snapshot.
LOAD_WARN=$((CORES * 4))

if [ "${LOAD:-0}" -gt "$LOAD_WARN" ]; then
    # Keep a high-load snapshot uncompressed for immediate inspection.
    {
        echo "load ${LOAD} > threshold ${LOAD_WARN} (${CORES} cores)"
        uptime
    } > "${FILE}.WARNING" 2>&1
else
    gzip "$FILE"
fi
