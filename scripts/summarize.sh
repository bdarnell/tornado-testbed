#!/usr/bin/env bash
# Regenerate results/summary.txt from the per-package result files
# without re-running anything. Useful after re-running a single package.
set -euo pipefail
source "$(dirname "$0")/common.sh"

summary="${RESULTS_DIR}/summary.txt"
: > "${summary}"
printf "%-18s %-12s %-4s %-10s %-8s\n" "PACKAGE" "STATUS" "RC" "TORNADO" "TIME(s)" | tee -a "${summary}"
printf "%-18s %-12s %-4s %-10s %-8s\n" "-------" "------" "--" "-------" "-------" | tee -a "${summary}"

N="$(pkg_count)"
for ((i = 0; i < N; i++)); do
    name="$(pkg_field "$i" name)"
    res="${RESULTS_DIR}/${name}.txt"
    if [[ -f "${res}" ]]; then
        package="$(awk -F= '/^package=/ {print $2}' "${res}")"
        status="$(awk -F= '/^status=/ {print $2}'   "${res}")"
        exit_code="$(awk -F= '/^exit_code=/ {print $2}' "${res}")"
        tornado="$(awk -F= '/^tornado=/ {print $2}' "${res}")"
        test_secs="$(awk -F= '/^test_secs=/ {print $2}' "${res}")"
        printf "%-18s %-12s %-4s %-10s %-8s\n" \
            "${package:-${name}}" "${status:-UNKNOWN}" "${exit_code:-?}" \
            "${tornado:-?}" "${test_secs:-?}" | tee -a "${summary}"
    else
        printf "%-18s %-12s %-4s %-10s %-8s\n" \
            "${name}" "NORESULT" "?" "?" "?" | tee -a "${summary}"
    fi
done
echo "" | tee -a "${summary}"
echo "Logs:    ${LOGS_DIR}/" | tee -a "${summary}"
echo "Results: ${RESULTS_DIR}/" | tee -a "${summary}"
