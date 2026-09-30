# DTR attendance: plain HTML/CSS/JS + Supabase

No build step, no npm. Just static files.

## Setup
1. Create a Supabase project (pick the Singapore region).
2. SQL editor: paste and run supabase/schema.sql
   (creates tables, rules, the geofence function, and the private photo bucket).
3. Authentication > Providers > Email: turn OFF "Allow new users to sign up"
   so only accounts you create can log in.
4. Edit js/config.js with your Project URL and anon key
   (Project Settings > API). Use the anon key only, never service_role.
5. Add data:
   - Table `areas`: name, latitude, longitude, radius_m (50 to 150 works indoors).
   - Authentication > Users > Add user (email + password) for each person.
   - Table `profiles`: id = that user's ID, full_name, role
     ('trainee' / 'supervisor' / 'admin'), area_id (trainees only).
6. Run locally: open the folder in VS Code and use the Live Server extension
   (or `python -m http.server 8000`). Geolocation works on localhost.

## Deploy (free, needs HTTPS for phone camera + GPS)
Netlify Drop (drag the folder), Cloudflare Pages, GitHub Pages, or Vercel.

## Files
- index.html: login, redirects by role
- submit.html: trainee time in/out with DTR photo and GPS
- admin.html: supervisor review (photos, distance, approve/reject)
- js/app.js: Supabase client, requireLogin(), logout()
- supabase/schema.sql: tables, RLS, submit_attendance() and review_attendance()

## How the security works
- The browser cannot insert into `attendance`. Only submit_attendance() can,
  and it runs on the server: it finds the user's assigned area, checks the
  distance, blocks duplicates per Manila day, and uses server time.
- Photos are in a private bucket; trainees can only touch their own folder,
  supervisors get temporary signed links.
- The page guards (requireLogin) are for convenience. The database rules
  are what actually protect the data.

## Known limits
- GPS can be spoofed on a website. Supervisors can see GPS accuracy and
  distance per entry to spot suspicious ones.
- Forgotten password: reset from the Supabase dashboard.
