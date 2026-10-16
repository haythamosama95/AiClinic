# NFR-08 Staging operating cost

Steady-load figures for the staging profile (05 §7):

- about 1,440 ABO cron runs;
- 288 platform cron runs;
- 2,880 backend pulls, each writing one `feed_consumer` row;
- about 168·o + 4·L + P/7 reversal inquiries a day, where o is new payments per day, L is payments funding a live, queued or held term, and P is other payments under 180 days old. At o = 5, L = 300 and P = 1,500 that is about 2,250 a day;
- about two DO row writes per AI request.

This load stays inside the included allowances of the Cloudflare Workers Paid plan and the Supabase project.
