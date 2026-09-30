# Environments and settings

Two kinds of configuration: a small set that can only come from the **environment**
(needed before the database is reachable, or needed to decrypt the database), and
everything else, which a **super-admin sets in the back office** at
`/admin/settings` and which is stored encrypted.

## The three environments

| Env | Config | Database |
| --- | --- | --- |
| `dev` | `config/dev.exs` | `viewninjas_dev` |
| `test` | `config/test.exs` | `viewninjas_test` (sandbox) |
| `prod` | `config/prod.exs` | `DATABASE_URL` |

`config/config.exs` is shared; `config/runtime.exs` runs at boot for every env and
is where the environment variables below are read. There is no dotenv file —
variables come from the shell, `fly secrets`, or the container.

## Set in the back office (`/admin/settings`)

Encrypted at rest, one row per key, with who last changed it. The environment is
the fallback, and a default sits behind that. A secret is never shown back.

| Key | Fallback env var |
| --- | --- |
| `textsms_api_key` | `TEXTSMS_API_KEY` |
| `textsms_partner_id` | `TEXTSMS_PARTNER_ID` |
| `textsms_shortcode` | `TEXTSMS_SHORTCODE` |
| `sms_daily_cap_micros` | `SMS_DAILY_CAP_MICROS` |
| `malipo_base_url` | `MALIPO_BASE_URL` |
| `malipo_secret_key` | `MALIPO_SECRET_KEY` |
| `malipo_webhook_secret` | `MALIPO_WEBHOOK_SECRET` |
| `fx_source_url` | `FX_SOURCE_URL` |
| `fx_source_path` | `FX_SOURCE_PATH` |
| `insight_hash_salt` | `INSIGHT_HASH_SALT` |
| `mailer_from` | `MAILER_FROM` |

Supplier panel keys are the same idea, but have their own screen: a super-admin
or admin edits each panel's base URL, key, `active` flag and capabilities at
`/admin/suppliers` (the key is never shown back). `SECSERS_API_KEY`,
`JAP_API_KEY`, `SMMFOLLOWS_API_KEY` and `<SLUG>_BASE_URL` remain as the bootstrap,
applied by `mix viewninjas.suppliers.setup`.

## Must stay in the environment

| Var | Why it cannot be in the database |
| --- | --- |
| `DATABASE_URL`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POOL_SIZE`, `ECTO_IPV6` | The database itself |
| `CLOAK_KEY` | It decrypts the settings table (and supplier keys); it cannot live inside what it protects |
| `SECRET_KEY_BASE` | Signs sessions/cookies; needed before the endpoint starts |
| `PORT`, `PHX_SERVER`, `PHX_HOST` | Needed before the endpoint starts |
| `DNS_CLUSTER_QUERY` | Read when the cluster child starts |
| `SENTRY_DSN`, `SENTRY_ENVIRONMENT` | Sentry starts as its own OTP app at boot |
| `MAILGUN_API_KEY`, `MAILGUN_DOMAIN` | The mailer adapter is chosen at boot |

`MIX_TEST_PARTITION` (test only) suffixes the test database name.

## Behaviour notes

- A value is read **at call time**: database, then environment, then default. An
  environment value keeps working and the super-admin overrides it without a
  redeploy.
- Before the repo is up — during application start, when the SMS and payment
  providers are chosen — there are no overrides to read, so the environment
  decides and a settings read never crashes a boot.
- Setting the TextSMS key in the back office switches development to the real SMS
  rail; test always uses the in-memory provider.
