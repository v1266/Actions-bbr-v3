#!/usr/bin/env bash
set -euo pipefail

target="${1:-net/ipv4/tcp_bbr.c}"

if [[ ! -f "$target" ]]; then
  echo "BBRv3 source file not found: $target" >&2
  exit 1
fi

if ! grep -q '^#define BBR_VERSION[[:space:]]*3' "$target"; then
  echo "BBRv3 max profile requires BBR_VERSION=3 in $target." >&2
  exit 1
fi

python3 - "$target" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

replacements = {
    r"static const u32 bbr_probe_rtt_win_ms = .*?;": "static const u32 bbr_probe_rtt_win_ms = 60 * 60 * 1000;",
    r"static const u32 bbr_probe_rtt_cwnd_gain = .*?;": "static const u32 bbr_probe_rtt_cwnd_gain = BBR_UNIT * 3;",
    r"static const u32 bbr_probe_rtt_mode_ms = .*?;": "static const u32 bbr_probe_rtt_mode_ms = 0;",
    r"static const u32 bbr_tso_rtt_shift = .*?;": "static const u32 bbr_tso_rtt_shift = 2;",
    r"static const int bbr_pacing_margin_percent = .*?;": "static const int bbr_pacing_margin_percent = 0;",
    r"static const int bbr_startup_pacing_gain = .*?;": "static const int bbr_startup_pacing_gain = BBR_UNIT * 15 / 4;",
    r"static const int bbr_startup_cwnd_gain = .*?;": "static const int bbr_startup_cwnd_gain = BBR_UNIT * 15 / 4;",
    r"static const int bbr_drain_gain = .*?;": "static const int bbr_drain_gain = BBR_UNIT;",
    r"static const int bbr_cwnd_gain  = .*?;": "static const int bbr_cwnd_gain  = BBR_UNIT * 15 / 4;",
    r"static const u32 bbr_cwnd_min_target = .*?;": "static const u32 bbr_cwnd_min_target = 64;",
    r"static const u32 bbr_full_bw_thresh = .*?;": "static const u32 bbr_full_bw_thresh = BBR_UNIT * 101 / 100;",
    r"static const u32 bbr_full_bw_cnt = .*?;": "static const u32 bbr_full_bw_cnt = 12;",
    r"static const int bbr_extra_acked_gain = .*?;": "static const int bbr_extra_acked_gain = BBR_UNIT * 4;",
    r"static const u32 bbr_extra_acked_max_us = .*?;": "static const u32 bbr_extra_acked_max_us = 1000 * 1000;",
    r"static const bool bbr_precise_ece_ack = .*?;": "static const bool bbr_precise_ece_ack = false;",
    r"static const u32 bbr_ecn_max_rtt_us = .*?;": "static const u32 bbr_ecn_max_rtt_us = 0;",
    r"static const u32 bbr_beta = .*?;": "static const u32 bbr_beta = 0;",
    r"static const u32 bbr_ecn_alpha_gain = .*?;": "static const u32 bbr_ecn_alpha_gain = 0;",
    r"static const u32 bbr_ecn_alpha_init = .*?;": "static const u32 bbr_ecn_alpha_init = 0;",
    r"static const u32 bbr_ecn_factor = .*?;": "static const u32 bbr_ecn_factor = 0;",
    r"static const u32 bbr_ecn_thresh = .*?;": "static const u32 bbr_ecn_thresh = 0;",
    r"static const u32 bbr_ecn_reprobe_gain = .*?;": "static const u32 bbr_ecn_reprobe_gain = 0;",
    r"static const u32 bbr_loss_thresh = [^\n]*": "static const u32 bbr_loss_thresh = BBR_UNIT;  /* max: effectively disabled */",
    r"static const bool bbr_loss_probe_recovery = .*?;": "static const bool bbr_loss_probe_recovery = false;",
    r"static const u32 bbr_full_loss_cnt = .*?;": "static const u32 bbr_full_loss_cnt = 0;",
    r"static const u32 bbr_full_ecn_cnt = .*?;": "static const u32 bbr_full_ecn_cnt = 0;",
    r"static const u32 bbr_inflight_headroom = .*?;": "static const u32 bbr_inflight_headroom = 0;",
    r"static const u32 bbr_bw_probe_cwnd_gain = .*?;": "static const u32 bbr_bw_probe_cwnd_gain = 3;",
    r"static const u32 bbr_bw_probe_max_rounds = .*?;": "static const u32 bbr_bw_probe_max_rounds = 1;",
    r"static const u32 bbr_bw_probe_rand_rounds = .*?;": "static const u32 bbr_bw_probe_rand_rounds = 0;",
    r"static const u32 bbr_bw_probe_base_us = .*?;": "static const u32 bbr_bw_probe_base_us = 1000;",
    r"static const u32 bbr_bw_probe_rand_us = .*?;": "static const u32 bbr_bw_probe_rand_us = 0;",
}

missing = []
for pattern, replacement in replacements.items():
    text, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        missing.append(pattern)

def find_matching(source, open_pos, open_char, close_char):
    depth = 0
    i = open_pos
    in_string = None
    in_line_comment = False
    in_block_comment = False
    escaped = False

    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue

        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == in_string:
                in_string = None
            i += 1
            continue

        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if ch in ('"', "'"):
            in_string = ch
            i += 1
            continue
        if ch == open_char:
            depth += 1
        elif ch == close_char:
            depth -= 1
            if depth == 0:
                return i
        i += 1

    return -1

def next_code_char(source, pos):
    i = pos
    while i < len(source):
        if source[i].isspace():
            i += 1
            continue
        if source.startswith("//", i):
            j = source.find("\n", i + 2)
            i = len(source) if j == -1 else j + 1
            continue
        if source.startswith("/*", i):
            j = source.find("*/", i + 2)
            i = len(source) if j == -1 else j + 2
            continue
        return i
    return -1

def replace_function_body(source, name, body):
    for match in re.finditer(rf"\b{re.escape(name)}\s*\(", source):
        open_paren = source.find("(", match.start())
        close_paren = find_matching(source, open_paren, "(", ")")
        if close_paren == -1:
            continue
        code_pos = next_code_char(source, close_paren + 1)
        if code_pos == -1:
            continue
        if source[code_pos] == ";":
            continue
        if source[code_pos] != "{":
            continue
        close_brace = find_matching(source, code_pos, "{", "}")
        if close_brace == -1:
            continue
        return source[:code_pos + 1] + body + source[close_brace:]
    missing.append(f"function {name}")
    return source

pacing_pattern = re.compile(
    r"static const int bbr_pacing_gain\[\] = \{\n"
    r".*?\n"
    r"\};",
    re.S,
)
pacing_replacement = """static const int bbr_pacing_gain[] = {
\tBBR_UNIT * 15 / 4,\t/* UP: max-rate probe */
\tBBR_UNIT,\t\t/* DOWN: no intentional drain */
\tBBR_UNIT * 5 / 4,\t/* CRUISE: keep pressure on the pipe */
\tBBR_UNIT * 2,\t\t/* REFILL: refill aggressively */
};"""
text, pacing_count = pacing_pattern.subn(pacing_replacement, text, count=1)
if pacing_count != 1:
    missing.append("static const int bbr_pacing_gain[]")

extreme_bodies = {
    "bbr_bw": "\n\treturn bbr_max_bw(sk);\n",
    "bbr_can_use_ecn": "\n\treturn false;\n",
    "bbr_check_ecn_too_high_in_startup": "\n\treturn;\n",
    "bbr_update_ecn_alpha": "\n\treturn -1;\n",
    "bbr_plb": "\n\treturn;\n",
    "bbr_handle_queue_too_high_in_startup": "\n\treturn;\n",
    "bbr_is_inflight_too_high": "\n\treturn false;\n",
    "bbr_handle_inflight_too_high": "\n\treturn;\n",
    "bbr_bound_cwnd_for_inflight_model": "\n\treturn;\n",
    "bbr_adapt_lower_bounds": "\n\treturn;\n",
    "bbr_check_loss_too_high_in_startup": "\n\treturn;\n",
    "bbr_check_drain": "\n\treturn;\n",
}

for function_name, body in extreme_bodies.items():
    text = replace_function_body(text, function_name, body)

if missing:
    print("Failed to apply BBRv3 max profile; missing patterns:", file=sys.stderr)
    for item in missing:
        print(f"  {item}", file=sys.stderr)
    sys.exit(1)

path.write_text(text)
PY

grep -nE 'bbr_(startup_pacing_gain|startup_cwnd_gain|cwnd_gain|pacing_gain|beta|loss_thresh|full_loss_cnt|full_ecn_cnt|inflight_headroom|bw_probe_cwnd_gain|probe_rtt_mode_ms|pacing_margin_percent)' "$target"
echo "Applied BBRv3 max profile to $target"
