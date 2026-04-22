# Static assets for Ntripi landing pages

## ntripi-og-default.jpg (1200×630)

Default Open Graph preview image shown when a user shares an itinerary
link to WhatsApp, Twitter, iMessage, etc.

This file must be a valid JPEG at 1200×630 px with the Ntripi logo and
tagline. It is referenced by every share landing page as the `og:image`
and `twitter:image` meta tag.

**The file is not committed to version control** (binary asset).
Add it to this directory before deploying to production.

TODO (Jira Ticket 3): Replace with dynamic per-itinerary preview images
generated from the itinerary's cover image + title overlay.
