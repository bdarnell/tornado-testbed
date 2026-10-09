# thumbor

On-demand image resizing service, ~10k stars; thumbor is a Tornado
application, and its HTTP loader fetches source images with Tornado's HTTP
clients.

## Why it is here

It is the **only package in the set that exercises `tornado.curl_httpclient`**.
Nothing else here imports it, so before thumbor was added a regression in the
curl client could not turn anything red. thumbor's suite covers about 62% of it.

## What it exercises

- `tornado.curl_httpclient` through thumbor's HTTP loader, which switches to
  `CurlAsyncHTTPClient` via `AsyncHTTPClient.configure(..., max_clients=...)`
  and, when configured, installs a `prepare_curl_callback` that sets libcurl's
  low-speed limits. The tests fetch from a live local Tornado app over HTTP and
  HTTPS, and cover a 404 and a `request_timeout` expiring.
- `tornado.simple_httpclient` for the same loader without curl, and through
  `AsyncHTTPTestCase.fetch`.
- `tornado.web` / `tornado.routing` — the thumbor app itself: URL routing,
  handlers serving image bytes, error statuses.

## What it does not catch

The curl tests check status and body, never response headers. Breaking
`_curl_header_callback` so it drops every header after the status line leaves
all of them passing; corrupting the response body fails `test_load_with_curl`.
Treat this as a check that curl fetches still work end to end, not as coverage
of the curl client's edge cases. The proxy tests mock the client and never
reach libcurl.

## Why the suite is shaped this way

The whole unit suite runs (about 30s). Deselected, each with its reason in
`test.sh`:

- the queued-detector tests, which need Redis servers on fixed ports;
- one curl low-speed-timeout test that fails identically on every Tornado
  version because of how its handler stalls the IOLoop;
- two GIFV tests that shell out to ffmpeg, and the `thumbor-doctor` output
  test, which expects every optional tool (ffmpeg among them) to be
  installed. Installing ffmpeg would be a large system dependency bought for
  no Tornado signal.

`setup.sh` installs the `all` extra (pycurl, opencv, image-format plugins) and
the `tests` extra, and refuses to continue unless `gifsicle` is on PATH:
without it about 10 tests fail with 504s that have nothing to do with Tornado.
CI installs it from `apt_packages` in `package.env`. jpegtran is not required:
thumbor's jpegtran tests skip themselves unless exiftool is installed too.
