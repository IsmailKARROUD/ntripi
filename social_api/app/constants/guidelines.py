"""
constants/guidelines.py — Community Guidelines served via GET /guidelines and
included in the GET /auth/tos payload.

Backend-owned for the same reason as the ToS: revising the rules is a deploy,
not an app-store submission. Plain text rather than privacy.py's HTML so one
string serves both the web page (white-space: pre-wrap) and the in-app sheet,
which renders it in a bare Text widget.

The categories below deliberately mirror what the stack actually enforces —
moderation_policy.CATEGORY_THRESHOLDS and report_service's canonical reasons.
Publishing a rule nothing enforces, or enforcing a category no rule announces,
is the discrepancy an app-store reviewer looks for.
"""

GUIDELINES_VERSION = "1.0"
GUIDELINES_DATE = "2026-08-06"

GUIDELINES_CONTENT = """Ntripi is for sharing real travel experiences. These guidelines apply to everything you publish: itineraries, stop names, addresses and notes, annotations, transport details, ratings and reviews, photos, and your profile.

We have no tolerance for objectionable content or abusive behaviour. Breaking these rules can cost you your content or your account.


1. PROHIBITED CONTENT

Do not publish content that is hateful, harassing, sexually explicit, violent, or that promotes illegal activity. The sections below describe each of these in more detail. If content would be unwelcome to a stranger reading your itinerary, it does not belong on Ntripi.


2. HATE SPEECH

Do not attack, demean, or dehumanise people on the basis of race, ethnicity, national origin, religion, caste, sexual orientation, sex, gender, gender identity, disability, or serious disease. This includes slurs, hateful stereotypes, and calls to exclude or harm any such group.

Describing a place honestly is not hate speech. Describing the people who live there as inferior is.


3. HARASSMENT AND BULLYING

Do not target another person with insults, intimidation, or unwanted repeated contact. Do not publish someone else's private information — home address, phone number, workplace, or identity documents — whether or not you obtained it lawfully. Do not encourage others to pile on.

Critical reviews of a business are welcome. Campaigns against an individual are not.


4. SEXUAL OR EXPLICIT CONTENT

Do not post pornography, sexually explicit imagery or writing, or content whose purpose is sexual gratification. Do not use Ntripi to advertise or arrange commercial sexual services.

Any sexual content involving a minor, real or depicted, is absolutely forbidden. It is removed, the account is terminated immediately without warning, and the matter is escalated. There is no appeal and no second chance for this category.


5. VIOLENCE

Do not threaten violence against anyone, incite others to commit it, glorify it, or celebrate a violent event or its perpetrator. Do not post gratuitously graphic imagery of injury or death.

Historical and memorial sites are a legitimate part of travel. Documenting them respectfully is allowed; using them to celebrate atrocity is not.


6. ILLEGAL ACTIVITIES

Do not use Ntripi to organise, promote, or provide instructions for criminal activity — including trafficking of any kind, the sale of weapons or controlled substances, fraud, or the theft or damage of cultural property.

Local law matters when you travel, and noting that something is restricted or dangerous somewhere is useful information. Explaining how to get away with a crime is not.


7. SPAM AND MANIPULATION

Do not post repetitive or automated content, undisclosed advertising, affiliate link farms, or engagement bait. Do not create multiple accounts to inflate ratings, and do not submit ratings for itineraries you have no genuine experience of. Ratings are only useful while they are honest.


8. SELF-HARM

Do not encourage suicide, self-injury, or disordered eating, and do not share methods or instructions.

Content that suggests someone is struggling is treated as a support matter, not a punishable offence. If you are in crisis, please contact your local emergency services or a crisis line in your country — Ntripi is not a substitute for help.


9. REPORTING ABUSE

Every itinerary can be reported from the app: open it, use the report control, and pick the reason that fits best. Reports are reviewed, and reporters are never identified to the person they reported.

You can also block any user. Blocking hides your content from them and theirs from you, in both directions.

Serious concerns can be emailed directly to abuse@ntripi.app.


10. ENFORCEMENT

Depending on severity and history, we may remove or hide content, issue a warning, restrict an account, or terminate it. Content may be hidden automatically — by an automated classifier, or after several people report it — before any person has reviewed it.

An automated action is provisional, not a finding of guilt. When something of yours is actioned we tell you what was actioned and why, in the app under Settings, Account status, and by email.


11. APPEALS

If you believe an action was wrong, you can appeal it from Settings, Account status. Appeals are read by a person. The one exception is content involving minors, which is not appealable.


12. CHANGES

We will update these guidelines as the service and the law evolve. The version and date shown with this document tell you which revision you are reading.


13. CONTACT

Questions about these guidelines, or a report you believe was mishandled: abuse@ntripi.app."""
