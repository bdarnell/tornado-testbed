# flower

Celery monitoring web UI, ~6.5k stars; Flower is a Tornado application.

## What it exercises

The most complete "classic Tornado app" usage in this set:

- `tornado.auth` for OAuth2/Google login -- **the only package here that
  imports it at all**
- `tornado.options` for CLI argument parsing
- `tornado.template` for HTML rendering (the highest template coverage of any
  entry)
- `tornado.locale` for i18n
- `tornado.testing` as its test base

## Standing limitation: tornado.auth stays at ~18%

Although flower is the only consumer of `tornado.auth`, its committed suite only
covers the `authenticate()` / `validate_auth_option()` helpers and HTTP Basic
auth. Nothing drives the OAuth2 login handlers
(`GoogleOAuth2Mixin.get_authenticated_user`, `authorize_redirect`,
`oauth2_request`), which is where most of `auth.py` lives.

Moving that number needs *new* OAuth-flow tests, not more of what exists, so it
is not something running more of this suite can fix.
