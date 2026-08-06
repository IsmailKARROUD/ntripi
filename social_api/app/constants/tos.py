"""
constants/tos.py — Terms of Service text served via GET /tos.

Keeping the ToS here (backend) means updating it requires only a backend
deploy, not an app store submission. The Flutter app always fetches the
current version at registration time.

TOS_VERSION is written verbatim into users.tos_accepted_version at
registration, so bumping it is what makes "which document did this person
agree to" answerable after the text changes. Existing rows are never
backfilled — they agreed to the revision they were shown.
"""

TOS_VERSION = "2.0"
TOS_DATE = "2026-08-06"

TOS_SUMMARY = """By creating an account on Ntripi, you agree to the following terms.


1. ACCEPTANCE OF TERMS

Creating an account means you accept these Terms of Service and our Community Guidelines, which form part of this agreement. If you do not accept them, do not create an account. You must be old enough to form a binding contract where you live, and at least 13 years old.


2. YOUR RESPONSIBILITIES

You are responsible for the content you publish — itineraries, stop details, notes, annotations, ratings, photos, and your profile — and for keeping your account credentials secure. You must have the right to publish what you post, including any photograph you upload.

You keep ownership of your content. You grant us the licence needed to store it and to display it to the audience you have chosen through your visibility settings, for as long as you keep it on Ntripi.


3. ZERO TOLERANCE FOR OBJECTIONABLE CONTENT AND ABUSIVE USERS

There is no tolerance on Ntripi for objectionable content or for abusive behaviour towards other users.

You may not publish content that is hateful, harassing, sexually explicit, violent, or that promotes illegal activity, and you may not harass, threaten, impersonate, or abuse anyone using this service. Sexual content involving minors is absolutely forbidden. The full rules are set out in our Community Guidelines.

We remove objectionable content and terminate the accounts of users who post it. Content may be scanned automatically and may be hidden before a person has reviewed it. Every user can report content and block any other user from inside the app.


4. SUSPENSION AND TERMINATION

We may remove or hide content, warn you, restrict your account, or terminate it, where you breach these terms or the Community Guidelines. Serious breaches can result in immediate termination without warning.

Where we act against you we will tell you what we did and why, and you can appeal from Settings, Account status — except for content involving minors, which is not appealable. You may close your account yourself at any time from the app.


5. YOUR DATA AND ACCOUNT DELETION

1. Your personal data (name, email, profile) will be deleted when you close your account.

2. Ratings you submit on itineraries will be retained in anonymized form (score only, no identifying information) after account deletion. This preserves the integrity of community scores for other users.

3. Your itineraries and their content will be permanently deleted when you close your account.

Records we are required to keep for legal or safety reasons are retained as described in our Privacy Policy.


6. PRIVACY

How we collect, use, and retain your information is described in our Privacy Policy, which forms part of this agreement and is linked wherever these terms are published.


7. THE SERVICE

Ntripi is provided as it is. Travel information on Ntripi is written by other travellers, not by us: we do not verify it, and you rely on it at your own risk. Always check local conditions, laws, and safety advice before you travel.


8. CHANGES TO THESE TERMS

We may revise these terms as the service and the law evolve. The version and date shown with this document tell you which revision you are reading.


9. CONTACT

Questions about these terms, or to report abuse: abuse@ntripi.app."""
