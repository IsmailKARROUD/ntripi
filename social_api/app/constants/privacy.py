"""
constants/privacy.py — Privacy Policy text served via GET /privacy.

Placeholder text — to be reviewed and finalized before public launch.
Keeping this in the backend means updating it requires only a backend
deploy, not an app-store submission.
"""

PRIVACY_VERSION = "1.0"
PRIVACY_DATE = "2026-07-16"

PRIVACY_CONTENT = """
<h2>1. Information We Collect</h2>
<p>When you create an account we collect your email address, chosen username,
and a bcrypt hash of your password. We never store your password in plain text.</p>
<p>When you create or edit itineraries we store the content you provide,
including place names, descriptions, stop details, and any ratings you submit.</p>

<h2>2. How We Use Your Information</h2>
<p>We use your email address only to identify your account and, if you request it,
to reset your password. We do not send marketing emails.</p>
<p>Your username and public itineraries are visible to other Ntripi users according
to the visibility settings you choose (public, followers-only, or private).</p>

<h2>3. Data Sharing</h2>
<p>We do not sell, rent, or share your personal information with third parties
for their marketing purposes.</p>
<p>We use OpenStreetMap / Nominatim for geocoding. Searches you make when adding
stops are sent to Nominatim. We do not store the raw search queries.
OpenStreetMap data is used under the Open Database Licence (ODbL).</p>

<h2>4. Data Retention and Deletion</h2>
<p>You may delete your account at any time from the app settings. Account deletion
permanently removes your profile, itineraries, and identifying information.</p>
<p>Ratings you have submitted are retained in anonymised form (score only, no
user link) to preserve the integrity of community scores. You consent to this
when you create your account, as described in our Terms of Service.</p>

<h2>5. Cookies</h2>
<p>Signing in does not use cookies — your session tokens are stored on your
device and sent only in request headers.</p>
<p>Website pages set a single preference cookie (<code>ntripi_lang</code>) to
remember your language choice. It contains no personal data and is never
shared with anyone.</p>
<p>If you sign in with Google, Google may set its own cookies as part of its
sign-in service; those are governed by Google's privacy policy.</p>
<p>We do not use analytics cookies, advertising cookies, or any third-party
tracking scripts.</p>

<h2>6. Security</h2>
<p>All data in transit is encrypted with TLS. Passwords are hashed with bcrypt
before storage. Session tokens are signed JWTs — they cannot be forged without
our server secret key.</p>

<h2>7. Changes to This Policy</h2>
<p>We will update this page when our practices change. The "Last updated" date
at the top of this page reflects the most recent revision.</p>

<h2>8. Contact</h2>
<p>Questions about your data? Email us at
<a href="mailto:privacy@ntripi.app">privacy@ntripi.app</a>.</p>
"""
