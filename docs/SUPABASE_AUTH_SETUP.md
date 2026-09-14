# Fulus Supabase email verification setup

Fulus uses the Android deep link `fulus://auth/callback` for email confirmation. The app already passes that value as the signup redirect and listens for the callback.

## Required hosted Supabase settings

In **Authentication → URL Configuration** for the Fulus Supabase project:

1. Set **Site URL** to the real production web URL, not `http://localhost:3000`.
2. Add the exact redirect URL:

   `fulus://auth/callback`

3. Keep `http://localhost:3000/**` only if a separate web development client actually needs it.

Supabase only honors a signup redirect when it is present in the project's allowed redirect URLs. If the redirect is not allowed, confirmation can fall back to the configured Site URL, which is why a mobile signup can incorrectly land on a localhost URL.

## Confirmation email template

The **Confirm signup** email should use Supabase's `{{ .ConfirmationURL }}` variable for the confirmation link. Do not hard-code `{{ .SiteURL }}` into the confirmation link when the mobile app supplies a redirect.

If the project uses a custom confirmation template, use the redirect-aware value supplied by Supabase (`{{ .RedirectTo }}`) when constructing the post-confirmation destination.

## Why this matters

The app receives the access and refresh tokens from the `fulus://auth/callback#...` fragment and persists the refresh token securely. The cloud connection screen can then finish business provisioning without making email verification a network dependency for local/offline onboarding.

If a confirmation link reports `otp_expired`, request a fresh confirmation email rather than reusing an older link. Supabase confirmation links are intentionally short-lived.
