# otp_test

A JSON-only Rails API using Devise for accounts and `devise-jwt` for stateless
tokens, with a mandatory email one-time passcode as a second factor.

**A password alone never returns a token.** Registering or logging in only
emails a 6-digit code; the JWT is issued exclusively by
`POST /otp/verify`.

```
POST /signup ─┐
              ├─→ code emailed ─→ POST /otp/verify ─→ JWT ─→ authenticated requests
POST /login  ─┘
```

## Requirements

- Ruby 4.0.6 (see `.ruby-version`)
- SQLite

## Setup

```bash
bundle install
bin/rails db:prepare
bin/rails server
```

The app is `config.api_only`, so there is no session store. Authentication is
entirely token-based.

## Viewing OTP emails in development

Development uses [letter_opener](https://github.com/ryanb/letter_opener), so
codes never leave your machine — each email opens in your browser and is also
written to `tmp/letter_opener/`. To read a code from the command line:

```bash
grep -rhoE "[0-9]{6}" tmp/letter_opener/*/rich.html | head -1
```

## API

Send `Content-Type: application/json` on requests with a body, and
`Accept: application/json` on every request. The `Accept` header matters:
without it, Devise's 401 responses come back as plain text rather than JSON.

| Method | Path | Purpose | Success |
| --- | --- | --- | --- |
| `POST` | `/signup` | Create an account, email a code | 201 |
| `POST` | `/login` | First factor, email a code | 200 |
| `POST` | `/otp/verify` | Second factor, **returns the JWT** | 200 |
| `POST` | `/otp/resend` | Email a replacement code | 202 |
| `GET` | `/me` | Example protected route | 200 |
| `DELETE` | `/logout` | Revoke the current token | 204 |

### Register

Creates the user and emails a code. Note the absence of a token in the response.

```bash
curl -i -X POST http://localhost:3000/signup \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"user":{"email":"user@example.com","password":"password","password_confirmation":"password"}}'
```

```json
{
  "message": "Signed up. Check your email for a verification code.",
  "email": "user@example.com",
  "otp_required": true
}
```

Validation failures return `422` with every message:

```json
{
  "errors": [
    "Email is invalid",
    "Password confirmation doesn't match Password",
    "Password is too short (minimum is 6 characters)"
  ]
}
```

### Log in (first factor)

Checks the password and emails a fresh code. Still no token.

```bash
curl -i -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"user":{"email":"user@example.com","password":"password"}}'
```

```json
{
  "message": "Password accepted. Check your email for a verification code.",
  "email": "user@example.com",
  "otp_required": true
}
```

A wrong password or unknown email returns `401`:

```json
{ "error": "Invalid Email or password." }
```

### Verify the OTP (second factor)

The only endpoint that mints a token. The JWT arrives in the `Authorization`
**response header**, not in the body.

```bash
curl -i -X POST http://localhost:3000/otp/verify \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"email":"user@example.com","code":"123456"}'
```

```
HTTP/1.1 200 OK
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJqdGkiOiJjMTg1N...
```

```json
{ "user": { "id": 1, "email": "user@example.com" } }
```

Anything wrong — bad code, expired code, already-used code, unknown email, or
too many attempts — returns the same `401`, so the response never reveals which:

```json
{ "error": "Invalid or expired code." }
```

### Resend a code

Issues a new code and resets the attempt counter, which is also how a locked-out
user recovers.

```bash
curl -i -X POST http://localhost:3000/otp/resend \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"email":"user@example.com"}'
```

Always `202` with the same body whether or not the account exists, so the
endpoint cannot be used to discover registered emails:

```json
{ "message": "If that account exists, a new code has been sent." }
```

### Authenticated requests

Send the token back as a `Bearer` credential.

```bash
curl -i http://localhost:3000/me \
  -H "Accept: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9..."
```

```json
{
  "user": {
    "id": 1,
    "email": "user@example.com",
    "otp_verified_at": "2026-09-08T11:38:07.805Z"
  }
}
```

Protect your own endpoints the same way `MeController` does:

```ruby
class ThingsController < ApplicationController
  before_action :authenticate_user!

  def index
    render json: { things: current_user.things }
  end
end
```

### Log out

Revokes the presented token immediately.

```bash
curl -i -X DELETE http://localhost:3000/logout \
  -H "Accept: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9..."
```

Returns `204` with no body. Reusing the token afterwards gives `401`
(`revoked token`). Tokens issued later are unaffected.

## OTP rules

All of these live in `app/models/user.rb`:

- 6 digits, generated with `SecureRandom`
- Valid for 10 minutes
- Single use — verifying consumes it
- 5 wrong attempts locks the code; `/otp/resend` clears the lock
- Only a bcrypt digest is stored, never the code itself

## How the token layer works

Tokens are stateless and signed with HS256, expiring after 1 day. Revocation
uses `devise-jwt`'s `JTIMatcher` strategy: each user row holds a `jti` claim,
and logging out rotates it, which invalidates any token carrying the old value.

Two pieces of configuration are load-bearing and easy to break:

- `config/initializers/devise_jwt_dispatch.rb` restricts token issuance to
  `POST /otp/verify`. `devise-jwt` otherwise derives dispatch paths from the
  Devise routes and **appends** them to whatever you configure, which would hand
  out tokens at `/login` and `/signup` and defeat the second factor.
- `config.skip_session_storage` includes `:params_auth`, and sign-in is called
  as `sign_in(user, store: false)`. Without both, Warden tries to write to a
  session that an `api_only` app does not have, raising `DisabledSessionError`.

The `json` gem is pinned to `~> 2.21` in the `Gemfile`. Active Support 8.1
passes `JSON.parse` options positionally, which `json` 3.x rejects, breaking
*all* JSON request parsing with a `400 Bad Request`. Rails has fixed this
upstream; drop the pin once a release including the fix is out.

## Tests

```bash
bin/rails test
```

- `test/models/user_test.rb` — OTP generation, verification, expiry, replay,
  lockout, and `jti` rotation
- `test/integration/authentication_flow_test.rb` — the endpoints above end to
  end, including that no token is issued before OTP verification
- `test/mailers/otp_mailer_test.rb` — email recipient, subject, and contents

`test/fixtures/users.yml` is intentionally empty. Fixtures are inserted with raw
SQL, which skips both password encryption and the callback that fills the
non-null `jti` column, so tests build users through the model.

## Before deploying

- Generate a dedicated JWT secret and store it in credentials as
  `devise_jwt_secret_key`. It currently falls back to `secret_key_base`, so
  rotating that would silently invalidate every issued token.
- `User#deliver_otp!` uses `deliver_now`, which blocks the request on SMTP.
  Switch to `deliver_later` with a Solid Queue worker running.
- Rate-limit `/login` and `/otp/resend`. Nothing currently caps how often a
  caller can trigger emails.
