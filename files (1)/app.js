// Shared helpers. Load after config.js and the supabase-js CDN script.
const db = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Call at the top of a protected page. Returns the profile, or redirects.
// allowedRoles: optional array like ["supervisor", "admin"]
async function requireLogin(allowedRoles) {
  const { data } = await db.auth.getSession();
  if (!data.session) {
    location.replace("index.html");
    return new Promise(() => {});           // stop the page from continuing
  }

  const { data: profile } = await db
    .from("profiles").select("full_name, role")
    .eq("id", data.session.user.id).single();

  if (!profile || (allowedRoles && !allowedRoles.includes(profile.role))) {
    document.body.innerHTML =
      '<main class="wrap"><p>You do not have access to this page.</p>' +
      '<button id="deniedLogout" class="link">Log out</button></main>';
    document.getElementById("deniedLogout").onclick = logout;
    return new Promise(() => {});
  }

  const nameEl = document.getElementById("userName");
  if (nameEl) nameEl.textContent = profile.full_name;
  const outEl = document.getElementById("logoutBtn");
  if (outEl) outEl.onclick = logout;
  return profile;
}

async function logout() {
  await db.auth.signOut();
  location.replace("index.html");
}
