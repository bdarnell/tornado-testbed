#!/usr/bin/env bash
# thumbor: full unit suite
#
# Run from the package's checkout by scripts/run_one.sh, inside that package's
# venv, with the Tornado under test already force-installed.
set -euo pipefail

# Coverage flags come from the harness: run_one.sh exports COV_ARGS empty when
# the run is not measuring coverage, so a release gate does not pay for it. The
# default below applies when this script is run by hand.
read -ra cov <<<"${COV_ARGS---cov=tornado --cov-report=term-missing}"

args=(
    -o addopts=
    # thumbor's .coveragerc turns on branch coverage. Branch data cannot be
    # combined with the statement data every other package records, so
    # gen_reports.sh's merged report would fail outright.
    --cov-config=/dev/null
    # pytest-tldr (pulled in by the tests extra) replaces pytest's output,
    # including the "short test summary info" block the CI report quotes.
    -p no:tldr

    tests/

    # Needs Redis servers on fixed ports (6668, and a sentinel on 26379) that
    # thumbor's Makefile starts before the suite. Tests the queued face/feature
    # detector, which talks to Redis, not Tornado.
    --deselect tests/detectors/test_queued_detector.py

    # Asserts that libcurl's LOW_SPEED_LIMIT aborts a slow response. The test
    # handler stalls with a blocking time.sleep(1.2) on the same IOLoop the
    # client runs on, so whether libcurl's low-speed check fires depends on
    # libcurl's own timer handling. It fails identically on tornado 6.4.2,
    # 6.5.5 and 6.5.10 with libcurl 8.22. The other curl tests -- fetch over
    # HTTP and HTTPS, 404, request_timeout -- still run.
    --deselect tests/loaders/test_http_loader.py::HttpCurlTimeoutLoaderTestCase::test_load_with_speed_timeout

    # Render animated GIFs as GIFV video by shelling out to ffmpeg, which CI
    # runners do not have. thumbor's video pipeline, not Tornado: installing
    # ffmpeg would add a large system dependency for no Tornado signal.
    --deselect tests/handlers/test_base_handler_with_gifv.py::ImageOperationsWithGifVTestCase::test_should_convert_animated_gif_to_mp4_when_filter_without_params
    --deselect tests/handlers/test_base_handler_with_gifv.py::ImageOperationsWithGifVTestCase::test_should_convert_animated_gif_to_mp4_with_filter_without_params

    # thumbor's install self-check: compares the full `thumbor-doctor` output,
    # which lists every optional tool (ffmpeg among them) as present or
    # missing, against a fixture that expects all of them. It tests the
    # environment, not Tornado.
    --deselect tests/test_doctor.py::test_get_doctor_output_no_config

    -q
)

python -m pytest "${args[@]}" "${cov[@]}"
