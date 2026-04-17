#!/usr/bin/env bash
# Run every package's test suite sequentially. Keeps going even if some fail.
set -uo pipefail
source "$(dirname "$0")/common.sh"

N="$(pkg_count)"
summary="${RESULTS_DIR}/summary.txt"
: > "${summary}"

printf "%-18s %-9s %-8s %-10s %-12s\n" "PACKAGE" "STATUS" "RC" "TORNADO" "TIME(s)" | tee -a "${summary}"
printf "%-18s %-9s %-8s %-10s %-12s\n" "-------" "------" "--" "-------" "-------" | tee -a "${summary}"

for ((i = 0; i < N; i++)); do
    name="$(pkg_field "$i" name)"
    bash "${ROOT_DIR}/scripts/run_one.sh" "${i}" >/dev/null 2>&1 || true
    res="${RESULTS_DIR}/${name}.txt"
    if [[ -f "${res}" ]]; then
        # Parse key=value lines without sourcing (protects against malformed files).
        package="$(awk -F= '/^package=/ {print $2}' "${res}")"
        status="$(awk -F= '/^status=/ {print $2}'   "${res}")"
        exit_code="$(awk -F= '/^exit_code=/ {print $2}' "${res}")"
        tornado="$(awk -F= '/^tornado=/ {print $2}' "${res}")"
        test_secs="$(awk -F= '/^test_secs=/ {print $2}' "${res}")"
        printf "%-18s %-9s %-8s %-10s %-12s\n" \
            "${package:-${name}}" "${status:-UNKNOWN}" "${exit_code:-?}" \
            "${tornado:-?}" "${test_secs:-?}" \
            | tee -a "${summary}"
    else
        printf "%-18s %-9s %-8s %-10s %-12s\n" \
            "${name}" "NORESULT" "?" "?" "?" | tee -a "${summary}"
    fi
done

echo "" | tee -a "${summary}"
echo "Full logs in ${LOGS_DIR}/" | tee -a "${summary}"
echo "Per-package results in ${RESULTS_DIR}/" | tee -a "${summary}"
