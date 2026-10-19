"use strict";

const state = {
  token: "",
  mfaSessionToken: "",
  mfaFactorId: "",
  mfaChallengeId: "",
  admin: null,
  config: null,
  catalog: {},
  section: "overview",
  userTab: "users",
  rows: [],
  editing: null,
};

const labels = {
  overview: ["Overview", "System health and managed record totals"],
  users: ["User management", "Registered accounts and access status"],
  diseases: ["Disease library", "Curated disease information and recommendations"],
  treatments: ["Treatment management", "Crop disease protocols and daily treatment steps"],
  crops: ["Crop data", "Ordinary users and their registered crop status"],
  analytics: ["Analytics", "Aggregate adoption, treatment, and activity signals"],
  profile: ["My profile", "Administrator identity and farm information"],
  system: ["System data", "Administrative activity and platform records"],
};

const displayColumns = {
  users: ["email", "name", "farm_location", "confirmed_at", "last_sign_in_at", "banned_until"],
  admins: ["email", "name", "access_status", "confirmed_at", "last_sign_in_at", "banned_until"],
  diseases: ["disease_name", "crop_type", "estimated_recovery_days", "is_active", "updated_at"],
  treatments: ["treatment_title", "disease_name", "status", "started_at", "updated_at"],
  crops: ["crop_name", "crop_type", "status", "latest_health_score", "updated_at"],
};

const wideFields = new Set([
  "description", "symptoms", "causes", "treatment_steps", "prevention_steps",
  "severity_notes", "caution_notes", "notes", "summary", "treatment_information",
]);
const arrayFields = new Set(["symptoms", "causes", "treatment_steps", "prevention_steps"]);
const booleanFields = new Set(["is_active", "reassessment_required"]);
const numberFields = new Set(["estimated_recovery_days", "expected_duration_days", "latest_health_score", "confidence_score"]);
const dateFields = new Set(["planted_at", "last_checked_at", "started_at", "ended_at", "diagnosed_at"]);
const selectOptions = {
  crop_type: ["tomato", "pepper", "squash", "eggplant", "pechay"],
  status: ["monitoring", "healthy", "recovering", "critical", "planned", "ongoing", "completed", "cancelled", "needs_reassessment"],
  severity: ["healthy", "mild", "moderate", "severe"],
  diagnosis_mode: ["online", "offline"],
  latest_progress_status: ["insufficient_data", "improving", "stable", "worsening"],
};

const $ = (selector) => document.querySelector(selector);
const content = $("#content");
const authCallbackParams = new URLSearchParams(window.location.hash.replace(/^#/, ""));
if (window.location.hash) {
  window.history.replaceState(null, document.title, `${window.location.pathname}${window.location.search}`);
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function showStatus(message, isError = false) {
  const target = $("#statusMessage");
  target.textContent = message;
  target.className = `status-message${isError ? " error" : ""}`;
  window.setTimeout(() => target.classList.add("hidden"), 4200);
}

async function api(path, options = {}) {
  const headers = new Headers(options.headers || {});
  headers.set("Authorization", `Bearer ${state.token}`);
  if (options.body) headers.set("Content-Type", "application/json");
  const response = await fetch(path, { ...options, headers, cache: "no-store" });
  if (response.status === 401) {
    signOut(false);
    throw new Error("Your session has expired.");
  }
  if (response.status === 403) {
    throw new Error("Your administrator role does not allow this action.");
  }
  if (!response.ok) {
    let message = "The operation could not be completed.";
    try { message = (await response.json()).detail || message; } catch (_) {}
    const failure = new Error(message);
    failure.status = response.status;
    throw failure;
  }
  if (response.status === 204) return null;
  return response.json();
}

async function supabaseAuth(path, { method = "GET", body } = {}) {
  if (!state.mfaSessionToken) {
    throw new Error("Your sign-in session is missing. Go back and sign in again.");
  }
  const response = await fetch(`${state.config.supabaseUrl}/auth/v1/${path}`, {
    method,
    headers: {
      "apikey": state.config.supabaseAnonKey,
      "Authorization": `******`,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
    cache: "no-store",
  });
  if (!response.ok) {
    let message = `Authenticator request failed (${response.status}).`;
    try {
      const result = await response.json();
      message = result.msg || result.message || result.error_description || result.error || message;
    } catch (_) {}
    throw new Error(`${message} [${method} /auth/v1/${path}]`);
  }
  return response.status === 204 ? null : response.json();
}

async function finishAdminSignIn() {
  const admin = await api("/v1/admin/me");
  const catalog = await api("/v1/admin/resources");
  state.admin = admin;
  state.catalog = catalog;
  $("#adminEmail").textContent = admin.email || "Administrator";
  $("#adminRole").textContent = admin.role;
  $("#adminInitial").textContent = (admin.email || "A").slice(0, 1).toUpperCase();
  $("#loginView").classList.add("hidden");
  $("#appView").classList.remove("hidden");
  await selectSection("overview");
}

function showMfaForm({ enrollmentRequired = false } = {}) {
  $("#loginForm").classList.add("hidden");
  $("#registerForm").classList.add("hidden");
  $("#mfaForm").classList.remove("hidden");
  $("#authModeButton").classList.add("hidden");
  $("#loginTitle").textContent = "Verify your administrator sign-in";
  document.querySelector("#signInHeading .lede").textContent =
    enrollmentRequired
      ? "Set up an authenticator app to protect administrator access."
      : "Complete the second step to access administrator tools.";
  $("#mfaSetupFields").classList.add("hidden");
  $("#mfaCodeFields").classList.add("hidden");
  $("#mfaSubmitButton").textContent = "Preparing...";
  $("#mfaSubmitButton").disabled = true;
  $("#mfaError").textContent = "";
  $("#mfaMessage").textContent = "";
}

async function beginMfaVerification() {
  showMfaForm();
  const factorResponse = await supabaseAuth("factors");
  const factors = Array.isArray(factorResponse)
    ? factorResponse
    : Array.isArray(factorResponse?.all)
      ? factorResponse.all
      : Array.isArray(factorResponse?.totp)
        ? factorResponse.totp
        : [];
  const totpFactors = factors.filter((factor) =>
    (factor.factor_type || factor.type) === "totp"
  );
  const factor = totpFactors.find((item) => item.status === "verified");
  if (factor) {
    state.mfaFactorId = factor.id;
    const challenge = await supabaseAuth(`factors/${encodeURIComponent(factor.id)}/challenge`, {
      method: "POST",
      body: {},
    });
    if (!challenge?.id) throw new Error("Supabase did not create an authenticator challenge.");
    state.mfaChallengeId = challenge.id;
    $("#mfaCodeFields").classList.remove("hidden");
    $("#mfaSubmitButton").disabled = false;
    $("#mfaSubmitButton").textContent = "Verify code";
    $("#mfaMessage").textContent = "Enter the current code from your authenticator app.";
    $("#mfaCode").focus();
    return;
  }
  showMfaForm({ enrollmentRequired: true });
  const unverifiedFactors = totpFactors.filter((item) => item.status === "unverified");
  for (const unverified of unverifiedFactors) {
    await supabaseAuth(`factors/${encodeURIComponent(unverified.id)}`, { method: "DELETE" });
  }
  const enrolled = await supabaseAuth("factors", {
    method: "POST",
    body: { factor_type: "totp", friendly_name: "CropCare AI Admin" },
  });
  if (!enrolled?.id || !enrolled.totp?.qr_code || !enrolled.totp?.secret) {
    throw new Error("Supabase did not return authenticator setup details.");
  }
  state.mfaFactorId = enrolled.id;
  $("#mfaQrCode").src = enrolled.totp.qr_code;
  $("#mfaSecret").textContent = enrolled.totp.secret;
  $("#mfaSetupFields").classList.remove("hidden");
  $("#mfaMessage").textContent = "Scan the QR code, then enter the current code to enable MFA.";
  const challenge = await supabaseAuth(`factors/${encodeURIComponent(state.mfaFactorId)}/challenge`, {
    method: "POST",
    body: {},
  });
  if (!challenge?.id) throw new Error("Supabase did not create an authenticator challenge.");
  state.mfaChallengeId = challenge.id;
  $("#mfaCodeFields").classList.remove("hidden");
  $("#mfaSubmitButton").disabled = false;
  $("#mfaSubmitButton").textContent = "Verify and enable";
  $("#mfaCode").focus();
}

async function submitMfa(event) {
  event.preventDefault();
  const error = $("#mfaError");
  const submit = $("#mfaSubmitButton");
  error.textContent = "";
  submit.disabled = true;
  try {
    if (!state.mfaFactorId) {
      await beginMfaVerification();
      return;
    }
    if (!state.mfaChallengeId) {
      const challenge = await supabaseAuth(
        `factors/${encodeURIComponent(state.mfaFactorId)}/challenge`,
        { method: "POST", body: {} },
      );
      if (!challenge?.id) throw new Error("Supabase did not create an authenticator challenge.");
      state.mfaChallengeId = challenge.id;
      $("#mfaCodeFields").classList.remove("hidden");
      $("#mfaSubmitButton").textContent = "Verify and enable";
      $("#mfaMessage").textContent = "Enter the current code from your authenticator app.";
      $("#mfaCode").focus();
      return;
    }
    const result = await supabaseAuth(
      `factors/${encodeURIComponent(state.mfaFactorId)}/verify`,
      {
        method: "POST",
        body: { challenge_id: state.mfaChallengeId, code: $("#mfaCode").value.trim() },
      },
    );
    if (!result?.access_token) throw new Error("MFA verification did not return a secure session.");
    state.token = result.access_token;
    state.mfaSessionToken = result.access_token;
    state.mfaChallengeId = "";
    await finishAdminSignIn();
  } catch (failure) {
    error.textContent = failure.message;
    submit.textContent = state.mfaChallengeId
      ? $("#mfaSetupFields").classList.contains("hidden")
        ? "Verify code"
        : "Verify and enable"
      : "Try again";
    submit.disabled = false;
  } finally {
    submit.disabled = false;
  }
}

function cancelMfa() {
  void signOut(true);
}

async function signIn(event) {
  event.preventDefault();
  const error = $("#loginError");
  const submit = event.currentTarget.querySelector("button[type=submit]");
  error.textContent = "";
  submit.disabled = true;
  submit.textContent = "Verifying...";
  try {
    if (!state.config) state.config = await fetch("/admin/config", { cache: "no-store" }).then((res) => res.json());
    if (!state.config.supabaseUrl || !state.config.supabaseAnonKey) throw new Error("Administrator authentication is not configured.");
    if (!state.config.adminDataConfigured) throw new Error("Administrator data access is not configured on the server.");
    const email = $("#email").value.trim();
    const passwordInput = $("#password");
    const response = await fetch(`${state.config.supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { "apikey": state.config.supabaseAnonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: passwordInput.value }),
      cache: "no-store",
    });
    passwordInput.value = "";
    if (!response.ok) throw new Error("Email or password is incorrect.");
    const session = await response.json();
    state.token = session.access_token || "";
    if (!state.token) throw new Error("A secure session could not be created.");
    state.mfaSessionToken = state.token;
    try {
      await finishAdminSignIn();
    } catch (failure) {
      if (failure.status !== 428) throw failure;
      await beginMfaVerification();
    }
  } catch (failure) {
    if ($("#mfaForm").classList.contains("hidden")) {
      state.token = "";
      state.mfaSessionToken = "";
      error.textContent = failure.message;
    } else {
      $("#mfaError").textContent = failure.message;
      $("#mfaSubmitButton").disabled = false;
      if (!state.mfaFactorId) $("#mfaSubmitButton").textContent = "Try again";
    }
  } finally {
    submit.disabled = false;
    submit.textContent = "Sign in securely";
  }
}

function setAuthMode(registering) {
  $("#loginForm").classList.toggle("hidden", registering);
  $("#registerForm").classList.toggle("hidden", !registering);
  $("#loginTitle").textContent = registering ? "Create your account" : "Administrator access";
  document.querySelector("#signInHeading .lede").textContent = registering
    ? "Register your identity, then ask a superadmin to approve administrator access."
    : "Secure operations for crop intelligence and account records.";
  $("#authModeButton").textContent = registering ? "Back to sign in" : "Create an account";
  $("#authModeButton").dataset.mode = registering ? "register" : "signin";
  $(registering ? "#registerEmail" : "#email").focus();
}

async function registerAccount(event) {
  event.preventDefault();
  const error = $("#registerError");
  const success = $("#registerSuccess");
  const submit = event.currentTarget.querySelector("button[type=submit]");
  const passwordInput = $("#registerPassword");
  const confirmInput = $("#confirmPassword");
  const firstName = $("#registerFirstName").value.trim();
  const lastName = $("#registerLastName").value.trim();
  error.textContent = "";
  success.textContent = "";
  if (!firstName || !lastName) {
    error.textContent = "Enter your first and last name.";
    return;
  }
  if (passwordInput.value !== confirmInput.value) {
    error.textContent = "Passwords do not match.";
    return;
  }
  submit.disabled = true;
  submit.textContent = "Creating account...";
  try {
    if (!state.config) state.config = await fetch("/admin/config", { cache: "no-store" }).then((res) => res.json());
    if (!state.config.supabaseUrl || !state.config.supabaseAnonKey) throw new Error("Account registration is not configured.");
    const redirectTo = state.config.adminAuthRedirectUrl || `${window.location.origin}/admin`;
    const signupUrl = `${state.config.supabaseUrl}/auth/v1/signup?redirect_to=${encodeURIComponent(redirectTo)}`;
    const response = await fetch(signupUrl, {
      method: "POST",
      headers: { "apikey": state.config.supabaseAnonKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        email: $("#registerEmail").value.trim(),
        password: passwordInput.value,
        data: {
          admin_access_requested: true,
          first_name: firstName,
          last_name: lastName,
          full_name: `${firstName} ${lastName}`,
          display_name: firstName,
        },
      }),
      cache: "no-store",
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      let message = "The account could not be created.";
      message = payload.msg || payload.message || message;
      throw new Error(message);
    }
    const createdUser = payload.user || payload;
    if (!createdUser.id || (Array.isArray(createdUser.identities) && createdUser.identities.length === 0)) {
      throw new Error("No new account was created. This email may already be registered; try signing in or use a different email.");
    }
    success.textContent = "Account created. Confirm your email, then ask a superadmin to approve your admin access. After approval, sign in to set up your authenticator app.";
  } catch (failure) {
    error.textContent = failure.message;
  } finally {
    passwordInput.value = "";
    confirmInput.value = "";
    submit.disabled = false;
    submit.textContent = "Create account";
  }
}

function invitationToken() {
  return authCallbackParams.get("type") === "invite"
    ? authCallbackParams.get("access_token") || ""
    : "";
}

async function initializeAuthCallback() {
  const callbackType = authCallbackParams.get("type") || "";
  const callbackError = authCallbackParams.get("error_description") || "";
  const accessToken = authCallbackParams.get("access_token") || "";
  const message = $("#authCallbackMessage");

  if (callbackType === "invite" && accessToken) {
    await initializeInvitation();
    return;
  }
  if (callbackError) {
    message.className = "form-error";
    message.textContent = callbackError.replaceAll("+", " ");
    return;
  }
  if (!["signup", "email_change"].includes(callbackType) || !accessToken) return;

  message.textContent = callbackType === "email_change"
    ? "Email address confirmed. You can now sign in."
    : "Email confirmed. Ask a superadmin to approve your access, then sign in.";

  try {
    if (!state.config) state.config = await fetch("/admin/config", { cache: "no-store" }).then((res) => res.json());
    await fetch(`${state.config.supabaseUrl}/auth/v1/logout`, {
      method: "POST",
      headers: {
        "apikey": state.config.supabaseAnonKey,
        "Authorization": `Bearer ${accessToken}`,
      },
      cache: "no-store",
    });
  } catch (_) {
    // The callback is already confirmed; sign-out cleanup is best effort.
  }
}

async function initializeInvitation() {
  if (!invitationToken()) return;
  $("#loginForm").classList.add("hidden");
  $("#registerForm").classList.add("hidden");
  $("#authModeButton").classList.add("hidden");
  document.querySelector(".security-note").classList.add("hidden");
  $("#inviteForm").classList.remove("hidden");
  $("#loginTitle").textContent = "Complete your CropCare account";
  document.querySelector("#signInHeading .lede").textContent = "Your email is confirmed. Create a password to finish setting up your account.";
}

async function completeInvitation(event) {
  event.preventDefault();
  const error = $("#inviteError");
  const success = $("#inviteSuccess");
  const password = $("#invitePassword");
  const confirmation = $("#invitePasswordConfirm");
  const submit = event.currentTarget.querySelector("button[type=submit]");
  error.textContent = "";
  success.textContent = "";
  if (password.value !== confirmation.value) {
    error.textContent = "Passwords do not match.";
    return;
  }
  submit.disabled = true;
  submit.textContent = "Confirming...";
  try {
    if (!state.config) state.config = await fetch("/admin/config", { cache: "no-store" }).then((res) => res.json());
    const token = invitationToken();
    if (!token) throw new Error("This invitation link is invalid or has expired.");
    const response = await fetch(`${state.config.supabaseUrl}/auth/v1/user`, {
      method: "PUT",
      headers: {
        "apikey": state.config.supabaseAnonKey,
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ password: password.value }),
      cache: "no-store",
    });
    if (!response.ok) throw new Error("The password could not be created. Request a new invitation link.");
    await fetch(`${state.config.supabaseUrl}/auth/v1/logout`, {
      method: "POST",
      headers: { "apikey": state.config.supabaseAnonKey, "Authorization": `Bearer ${token}` },
    });
    password.value = "";
    confirmation.value = "";
    window.history.replaceState({}, document.title, window.location.pathname);
    success.textContent = "Account confirmed. You can now sign in to the CropCare app.";
    submit.classList.add("hidden");
  } catch (failure) {
    error.textContent = failure.message;
  } finally {
    submit.disabled = false;
    submit.textContent = "Confirm account";
  }
}

async function signOut(callServer = true) {
  const token = state.token;
  state.token = "";
  state.mfaSessionToken = "";
  state.mfaFactorId = "";
  state.mfaChallengeId = "";
  state.admin = null;
  state.rows = [];
  $("#appView").classList.add("hidden");
  $("#loginView").classList.remove("hidden");
  $("#loginForm").reset();
  $("#mfaForm").reset();
  $("#mfaForm").classList.add("hidden");
  $("#loginTitle").textContent = "Administrator access";
  document.querySelector("#signInHeading .lede").textContent =
    "Secure operations for crop intelligence and account records.";
  $("#mfaQrCode").removeAttribute("src");
  $("#mfaSecret").textContent = "";
  $("#mfaSetupFields").classList.add("hidden");
  $("#mfaCodeFields").classList.add("hidden");
  $("#mfaMessage").textContent = "";
  $("#loginForm").classList.remove("hidden");
  $("#authModeButton").classList.remove("hidden");
  if (callServer && token && state.config) {
    try {
      await fetch(`${state.config.supabaseUrl}/auth/v1/logout`, {
        method: "POST",
        headers: { "apikey": state.config.supabaseAnonKey, "Authorization": `Bearer ${token}` },
      });
    } catch (_) {}
  }
}

async function selectSection(section) {
  state.section = section;
  document.querySelectorAll(".nav-item").forEach((button) => button.classList.toggle("active", button.dataset.section === section));
  $("#pageTitle").textContent = labels[section][0];
  $(".sidebar").classList.remove("open");
  content.replaceChildren(loadingState());
  try {
    if (section === "overview") await renderOverview();
    else if (section === "users") await renderUsers();
    else if (section === "diseases") await renderDiseaseLibrary();
    else if (section === "treatments") await renderTreatmentLibrary();
    else if (section === "crops") await renderCropData();
    else if (section === "analytics") await renderAnalytics();
    else if (section === "profile") await renderAdminProfile();
    else if (section === "system") await renderSystem();
  } catch (failure) {
    renderFailure(failure.message);
  }
}

function loadingState() {
  const panel = element("section", "panel glass empty-state");
  panel.textContent = "Loading secure records...";
  return panel;
}

function renderFailure(message) {
  const panel = element("section", "panel glass empty-state");
  panel.append(element("h3", "", "Unable to load this section"), element("p", "", message));
  content.replaceChildren(panel);
}

async function renderOverview() {
  const summary = await api("/v1/admin/summary");
  const hero = element("section", "hero-strip glass");
  const copy = element("div");
  copy.append(element("p", "eyebrow", "Administrator workspace"), element("h3", "", "Crop intelligence, responsibly managed."), element("p", "", "Review account activity, maintain verified disease guidance, and protect the quality of every crop assessment."));
  const date = element("div", "hero-date", new Intl.DateTimeFormat(undefined, { dateStyle: "long" }).format(new Date()));
  hero.append(copy, date);

  const metrics = element("section", "metric-grid");
  const metricNames = ["users", "crops", "treatments", "diseases"];
  metricNames.forEach((name) => {
    const card = element("article", "metric-card glass");
    card.append(element("span", "", labels[name]?.[0] || name), element("strong", "", summary.counts[name] ?? "--"), element("small", "", "Managed records"));
    metrics.append(card);
  });
  content.replaceChildren(hero, metrics);
}

async function renderAnalytics() {
  const data = await api("/v1/admin/analytics");
  const metricLabels = {
    ordinary_users: "Ordinary users",
    active_users_30d: "Active in 30 days",
    current_crops: "Current crops",
    treatment_task_completion_rate: "Task completion",
    improving_crops: "Improving crops",
    crops_needing_attention: "Need attention",
  };
  const metricGrid = element("section", "analytics-metrics");
  Object.entries(metricLabels).forEach(([key, label]) => {
    const card = element("article", "analytics-metric");
    const value = data.metrics[key];
    card.append(
      element("span", "", label),
      element("strong", "", value === null || value === undefined ? "--" : `${value}${key.endsWith("rate") ? "%" : ""}`),
    );
    metricGrid.append(card);
  });

  const popular = analyticsPanel("Most added crops", "Current non-archived crops across ordinary users.");
  popular.append(buildHorizontalBars(data.crop_distribution, "crop_type", "count"));

  const adaptation = analyticsPanel("Treatment adaptation", "Progress, health, and task completion grouped by crop type.");
  const adaptationList = element("div", "adaptation-list");
  (data.treatment_adaptation || []).forEach((item) => {
    const row = element("article", "adaptation-row");
    const heading = element("div", "adaptation-heading");
    heading.append(
      element("strong", "", titleCase(item.crop_type)),
      element("small", "", `${item.crop_count} crops · ${item.total_tasks} treatment tasks`),
    );
    const values = element("div", "adaptation-values");
    [["Improving", item.improving, "good"], ["Stable", item.stable, "stable"], ["Worsening", item.worsening, "poor"], ["Task completion", item.task_completion_rate === null ? "--" : `${item.task_completion_rate}%`, "completion"], ["Avg health", item.average_health_score === null ? "--" : `${item.average_health_score}%`, "health"]].forEach(([label, value, className]) => {
      const stat = element("span", className);
      stat.append(element("small", "", label), element("strong", "", String(value)));
      values.append(stat);
    });
    row.append(heading, values);
    adaptationList.append(row);
  });
  if (!adaptationList.children.length) adaptationList.append(element("div", "empty-state compact", "No crop treatment data yet."));
  adaptation.append(adaptationList);

  const activity = analyticsPanel("Research activity · 14 days", "Diagnosis and crop check-in volume, aggregated by UTC date.");
  activity.append(buildActivityChart(data.activity_by_day || []));

  const signIns = analyticsPanel("Recent sign-in hours", "Latest sign-in per ordinary account, grouped by UTC hour. This is not a complete traffic history.");
  signIns.append(buildHourChart(data.sign_in_hours_utc || []));

  const grid = element("section", "analytics-grid");
  grid.append(popular, adaptation, activity, signIns);
  content.replaceChildren(metricGrid, grid);
}

function analyticsPanel(title, subtitle) {
  const panel = element("section", "analytics-panel glass");
  panel.append(panelHeader(title, subtitle));
  return panel;
}

function buildHorizontalBars(items, labelField, valueField) {
  const chart = element("div", "horizontal-chart");
  const max = Math.max(1, ...(items || []).map((item) => Number(item[valueField]) || 0));
  (items || []).forEach((item) => {
    const row = element("div", "horizontal-bar-row");
    const label = element("strong", "", titleCase(item[labelField]));
    const track = element("div", "bar-track");
    const fill = element("span", "bar-fill");
    fill.style.width = `${(Number(item[valueField]) || 0) * 100 / max}%`;
    track.append(fill);
    row.append(label, track, element("span", "bar-value", String(item[valueField] ?? 0)));
    chart.append(row);
  });
  if (!chart.children.length) chart.append(element("div", "empty-state compact", "No crop records yet."));
  return chart;
}

function buildActivityChart(items) {
  const chart = element("div", "activity-chart");
  const max = Math.max(1, ...items.map((item) => Number(item.diagnoses || 0) + Number(item.check_ins || 0)));
  items.forEach((item) => {
    const column = element("div", "activity-column");
    const bars = element("div", "activity-bars");
    const diagnosis = element("span", "diagnosis-bar");
    const checkIn = element("span", "checkin-bar");
    diagnosis.style.height = `${Number(item.diagnoses || 0) * 100 / max}%`;
    checkIn.style.height = `${Number(item.check_ins || 0) * 100 / max}%`;
    bars.append(diagnosis, checkIn);
    const date = new Date(`${item.date}T00:00:00Z`);
    column.title = `${item.date}: ${item.diagnoses} diagnoses, ${item.check_ins} check-ins`;
    column.append(bars, element("small", "", new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", timeZone: "UTC" }).format(date)));
    chart.append(column);
  });
  return chart;
}

function buildHourChart(items) {
  const chart = element("div", "hour-chart");
  const max = Math.max(1, ...items.map((item) => Number(item.count) || 0));
  items.forEach((item) => {
    const column = element("div", "hour-column");
    const bar = element("span", "hour-bar");
    bar.style.height = `${(Number(item.count) || 0) * 100 / max}%`;
    column.title = `${String(item.hour).padStart(2, "0")}:00 UTC · ${item.count} users`;
    column.append(bar, element("small", "", Number(item.hour) % 3 === 0 ? String(item.hour).padStart(2, "0") : ""));
    chart.append(column);
  });
  return chart;
}

function panelHeader(title, subtitle, actions = []) {
  const header = element("header", "panel-header");
  const copy = element("div");
  copy.append(element("h3", "", title), element("p", "", subtitle));
  const actionGroup = element("div", "panel-actions");
  actions.forEach((action) => actionGroup.append(action));
  header.append(copy, actionGroup);
  return header;
}

function formatValue(value, field) {
  if (value === null || value === undefined || value === "") return "--";
  if (typeof value === "boolean") return value ? "Active" : "Inactive";
  if (Array.isArray(value)) return value.join("; ");
  if (field.endsWith("_at")) {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.valueOf())) return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(parsed);
  }
  if (field === "confidence_score" || field === "latest_health_score") return `${Math.round(Number(value) * (field === "confidence_score" ? 100 : 1))}%`;
  return String(value).replaceAll("_", " ");
}

function buildTable(rows, columns, actionBuilder) {
  const wrap = element("div", "table-wrap");
  if (!rows.length) {
    wrap.append(element("div", "empty-state", "No records found."));
    return wrap;
  }
  const table = element("table");
  const head = element("thead");
  const headerRow = element("tr");
  columns.forEach((column) => headerRow.append(element("th", "", column.replaceAll("_", " "))));
  headerRow.append(element("th", "", "Actions"));
  head.append(headerRow);
  const body = element("tbody");
  rows.forEach((row) => {
    const tableRow = element("tr");
    columns.forEach((column) => {
      const cell = element("td", "truncate", formatValue(row[column], column));
      cell.title = formatValue(row[column], column);
      tableRow.append(cell);
    });
    const actions = element("td", "row-actions");
    actionBuilder(row).forEach((button) => actions.append(button));
    tableRow.append(actions);
    body.append(tableRow);
  });
  table.append(head, body);
  wrap.append(table);
  return wrap;
}

function groupBy(rows, key) {
  return rows.reduce((groups, row) => {
    const value = String(row[key] || "Unspecified").trim().toLowerCase();
    groups[value] ||= [];
    groups[value].push(row);
    return groups;
  }, {});
}

function titleCase(value) {
  return String(value || "").replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function cropIcon(crop) {
  const icons = {
    eggplant: "🍆",
    pechay: "🥬",
    pepper: "🌶️",
    squash: "🎃",
    tomato: "🍅",
  };
  return icons[String(crop || "").trim().toLowerCase()] || "🌱";
}

function buildCropCards(groups, onSelect, emptyMessage) {
  const grid = element("div", "crop-card-grid");
  const entries = Object.entries(groups).sort(([left], [right]) => left.localeCompare(right));
  if (!entries.length) return element("div", "empty-state", emptyMessage);
  entries.forEach(([crop, rows]) => {
    const card = element("button", "crop-card");
    card.type = "button";
    card.append(
      element("span", "crop-card-mark", cropIcon(crop)),
      element("strong", "", titleCase(crop)),
      element("small", "", `${rows.length} ${rows.length === 1 ? "record" : "records"}`),
    );
    card.addEventListener("click", () => onSelect(crop, rows));
    grid.append(card);
  });
  return grid;
}

function appendDetail(container, label, value) {
  if (value === null || value === undefined || value === "") return;
  const block = element("div", "detail-field");
  block.append(element("strong", "", titleCase(label)), element("p", "", formatValue(value, label)));
  container.append(block);
}

function openContentDialog(eyebrow, title, body) {
  $("#contentDialogEyebrow").textContent = eyebrow;
  $("#contentDialogTitle").textContent = title;
  $("#contentDialogBody").replaceChildren(body);
  $("#contentDialog").showModal();
}

function openDetailDialog(eyebrow, title, body) {
  $("#detailDialogEyebrow").textContent = eyebrow;
  $("#detailDialogTitle").textContent = title;
  $("#detailDialogBody").replaceChildren(body);
  $("#detailDialog").showModal();
}

async function renderDiseaseLibrary() {
  const response = await api("/v1/admin/resources/diseases?limit=100");
  state.rows = response.items;
  const panel = element("section", "panel glass");
  const add = element("button", "primary-button", "Add disease");
  add.type = "button";
  add.addEventListener("click", () => openDiseaseForm());
  panel.append(panelHeader(labels.diseases[0], labels.diseases[1], [add]));
  panel.append(buildCropCards(groupBy(state.rows, "crop_type"), showCropDiseases, "No disease records found."));
  content.replaceChildren(panel);
}

function showCropDiseases(crop, diseases) {
  const list = element("div", "detail-stack");
  diseases.sort((left, right) => String(left.disease_name).localeCompare(String(right.disease_name))).forEach((disease) => {
    const section = element("article", "detail-section");
    const heading = element("div", "detail-section-heading");
    const title = element("div");
    title.append(element("h4", "", titleCase(disease.disease_name)), element("small", "", disease.scientific_name || "Crop disease record"));
    const actions = element("div", "row-actions");
    const edit = element("button", "secondary-button", "Edit");
    edit.type = "button";
    edit.addEventListener("click", () => {
      $("#contentDialog").close();
      openRecordDialog("diseases", disease);
    });
    const deactivate = element("button", "danger-button", "Deactivate");
    deactivate.type = "button";
    deactivate.addEventListener("click", () => archiveRecord("diseases", disease));
    actions.append(edit, deactivate);
    heading.append(title, actions);
    section.append(heading);
    const details = element("div", "detail-grid");
    ["label_key", "scientific_name", "severity", "description", "symptoms", "causes", "severity_notes", "estimated_recovery_days", "treatment_title", "treatment_information", "treatment_steps", "prevention_steps", "caution_notes", "is_active", "source_name", "source_url", "created_at", "updated_at"].forEach((field) => appendDetail(details, field, disease[field]));
    section.append(details);
    list.append(section);
  });
  openContentDialog("Disease library", titleCase(crop), list);
}

function openDiseaseForm(record = null) {
  state.editing = { resource: "diseases", record };
  $("#dialogEyebrow").textContent = "Disease library";
  $("#dialogTitle").textContent = record ? "Edit disease" : "Add crop disease";
  $("#recordError").textContent = "";
  const fields = $("#recordFields");
  fields.replaceChildren();
  const fieldNames = record
    ? state.catalog.diseases.editable
    : ["crop_type", "disease_name", "description", "severity", "estimated_recovery_days"];
  fieldNames.forEach((field) => fields.append(buildField(field, record?.[field], ["crop_type", "disease_name", "description", "severity", "estimated_recovery_days"].includes(field))));
  $("#recordDialog").showModal();
}

async function renderTreatmentLibrary() {
  const response = await api("/v1/admin/treatment-protocols");
  state.rows = response.items;
  const panel = element("section", "panel glass");
  const add = element("button", "primary-button", "Add treatment");
  add.type = "button";
  add.addEventListener("click", () => openTreatmentForm());
  panel.append(panelHeader(labels.treatments[0], labels.treatments[1], [add]));
  panel.append(buildCropCards(groupBy(state.rows, "crop_type"), showCropTreatments, "No treatment protocols found."));
  content.replaceChildren(panel);
}

function showCropTreatments(crop, diseases) {
  const list = element("div", "selection-list");
  diseases.sort((left, right) => String(left.disease_name).localeCompare(String(right.disease_name))).forEach((disease) => {
    const button = element("button", "selection-row");
    button.type = "button";
    const copy = element("span");
    copy.append(element("strong", "", titleCase(disease.disease_name)), element("small", "", disease.treatment_title || "Treatment protocol not yet titled"));
    button.append(copy, element("span", "badge", `${disease.estimated_recovery_days || 0} days`));
    button.addEventListener("click", () => showTreatmentDetails(disease));
    list.append(button);
  });
  openContentDialog("Treatment management", titleCase(crop), list);
}

function showTreatmentDetails(disease) {
  const body = element("div", "detail-stack");
  const summary = element("section", "detail-section");
  const actions = element("div", "detail-section-heading");
  const copy = element("div");
  copy.append(
    element("h4", "", disease.treatment_title || `${titleCase(disease.disease_name)} treatment`),
    element("small", "", `${disease.estimated_recovery_days || 0}-day protocol`),
  );
  const edit = element("button", "secondary-button", "Edit treatment");
  edit.type = "button";
  edit.addEventListener("click", () => {
    $("#detailDialog").close();
    $("#contentDialog").close();
    openTreatmentForm(disease);
  });
  actions.append(copy, edit);
  summary.append(actions);
  appendDetail(summary, "treatment_information", disease.treatment_information);
  body.append(summary);
  (disease.daily_steps || []).forEach((step) => {
    const day = element("section", "day-step");
    day.append(element("span", "day-number", `Day ${step.day_number}`), element("h4", "", step.day_title || `Day ${step.day_number}`));
    const tasks = element("ul");
    (step.tasks || []).forEach((task) => tasks.append(element("li", "", task)));
    day.append(tasks);
    if (step.notes) day.append(element("p", "day-note", step.notes));
    body.append(day);
  });
  openDetailDialog(titleCase(disease.crop_type), titleCase(disease.disease_name), body);
}

function openTreatmentForm(disease = null) {
  state.editing = { resource: "treatment-protocol", record: disease };
  $("#dialogEyebrow").textContent = "Treatment management";
  $("#dialogTitle").textContent = disease ? "Edit treatment protocol" : "Add treatment protocol";
  $("#recordError").textContent = "";
  const fields = $("#recordFields");
  fields.replaceChildren();

  const cropField = buildField("crop_type", disease?.crop_type, true);
  const diseaseWrap = element("div");
  const diseaseLabel = element("label", "", "Disease *");
  const diseaseSelect = element("select");
  diseaseSelect.name = "disease_id";
  diseaseSelect.required = true;
  diseaseWrap.append(diseaseLabel, diseaseSelect);
  const titleField = buildField("treatment_title", disease?.treatment_title, true);
  const informationField = buildField("treatment_information", disease?.treatment_information, true);
  const durationField = buildField("expected_duration_days", disease?.estimated_recovery_days, true);
  const steps = element("div", "field-wide daily-step-editor");
  fields.append(cropField, diseaseWrap, titleField, informationField, durationField, steps);

  const cropSelect = cropField.querySelector("select");
  const titleInput = titleField.querySelector("input");
  const informationInput = informationField.querySelector("textarea");
  const durationInput = durationField.querySelector("input");
  durationInput.min = "1";
  durationInput.max = "90";

  function populateDiseases() {
    const crop = cropSelect.value;
    diseaseSelect.replaceChildren(element("option", "", "Select disease"));
    state.rows.filter((row) => row.crop_type === crop).forEach((row) => {
      const option = element("option", "", titleCase(row.disease_name));
      option.value = row.id;
      option.selected = row.id === state.editing.record?.id;
      diseaseSelect.append(option);
    });
  }

  function renderDays(source = []) {
    const duration = Math.min(Math.max(Number(durationInput.value) || 0, 0), 90);
    steps.replaceChildren(element("h4", "", "Daily treatment steps"));
    for (let dayNumber = 1; dayNumber <= duration; dayNumber += 1) {
      const existing = source.find((step) => Number(step.day_number) === dayNumber) || {};
      const day = element("div", "day-editor");
      day.append(element("span", "day-number", `Day ${dayNumber}`));
      const dayTitle = element("input");
      dayTitle.name = `day_${dayNumber}_title`;
      dayTitle.placeholder = "Daily focus";
      dayTitle.value = existing.day_title || `Day ${dayNumber}`;
      const tasks = element("textarea");
      tasks.name = `day_${dayNumber}_tasks`;
      tasks.placeholder = "One treatment step per line";
      tasks.required = true;
      tasks.value = Array.isArray(existing.tasks) ? existing.tasks.join("\n") : "";
      const notes = element("textarea");
      notes.name = `day_${dayNumber}_notes`;
      notes.placeholder = "Optional notes";
      notes.value = existing.notes || "";
      day.append(dayTitle, tasks, notes);
      steps.append(day);
    }
  }

  cropSelect.addEventListener("change", () => {
    state.editing.record = null;
    populateDiseases();
    titleInput.value = "";
    informationInput.value = "";
    durationInput.value = "";
    renderDays();
  });
  diseaseSelect.addEventListener("change", () => {
    const selected = state.rows.find((row) => row.id === diseaseSelect.value) || null;
    state.editing.record = selected;
    titleInput.value = selected?.treatment_title || "";
    informationInput.value = selected?.treatment_information || "";
    durationInput.value = selected?.estimated_recovery_days || "";
    renderDays(selected?.daily_steps || []);
  });
  durationInput.addEventListener("change", () => renderDays(state.editing.record?.daily_steps || []));
  populateDiseases();
  renderDays(disease?.daily_steps || []);
  $("#recordDialog").showModal();
}

async function renderCropData() {
  const loadAllPages = async (urlForOffset, pageSize = 100) => {
    const items = [];
    for (let offset = 0; ; offset += pageSize) {
      const response = await api(urlForOffset(offset));
      const page = Array.isArray(response.items) ? response.items : [];
      items.push(...page);
      if (page.length < pageSize) return items;
    }
  };
  const [allUsers, allCrops] = await Promise.all([
    loadAllPages((page) => `/v1/admin/users?page=${page + 1}&per_page=100`),
    loadAllPages((offset) => `/v1/admin/resources/crops?limit=100&offset=${offset}`),
  ]);
  const users = allUsers.filter((user) => !user.admin_role && !user.admin_access_requested);
  const crops = allCrops.map((crop) => (
    crop.is_deleted === true || crop.is_deleted === 1
      ? { ...crop, status: "deleted" }
      : crop
  ));
  const cropsByUser = groupBy(crops, "user_id");
  const panel = element("section", "panel glass");
  panel.append(panelHeader(labels.crops[0], labels.crops[1]));
  const list = element("div", "user-crop-list");
  if (!users.length) list.append(element("div", "empty-state", "No ordinary users found."));
  users.forEach((user) => {
    const item = element("article", "user-crop-item");
    const button = element("button", "user-crop-heading");
    button.type = "button";
    const name = user.profile?.display_name || user.profile?.full_name || user.email;
    const userCrops = cropsByUser[String(user.id).toLowerCase()] || [];
    const copy = element("span");
    copy.append(element("strong", "", name), element("small", "", `${user.email} · ${userCrops.length} ${userCrops.length === 1 ? "crop" : "crops"}`));
    button.append(copy, element("span", "expand-indicator", "+"));
    const cropList = element("div", "user-crops hidden");
    if (!userCrops.length) cropList.append(element("div", "empty-state compact", "No crops registered for this user."));
    userCrops.forEach((crop) => cropList.append(buildUserCropRow(crop)));
    button.addEventListener("click", () => {
      cropList.classList.toggle("hidden");
      button.querySelector(".expand-indicator").textContent = cropList.classList.contains("hidden") ? "+" : "−";
    });
    item.append(button, cropList);
    list.append(item);
  });
  panel.append(list);
  content.replaceChildren(panel);
}

function buildUserCropRow(crop) {
  const isDeleted = crop.is_deleted === true || crop.is_deleted === 1;
  const row = element("article", "user-crop-row");
  row.tabIndex = 0;
  row.setAttribute("role", "button");
  row.setAttribute("aria-label", `View activity for ${crop.crop_name || titleCase(crop.crop_type)}`);
  const copy = element("div");
  copy.append(
    element("span", "crop-row-icon", cropIcon(crop.crop_type)),
    element("h4", "", crop.crop_name || titleCase(crop.crop_type)),
    element("small", "", [titleCase(crop.crop_type), isDeleted ? "Deleted" : null, crop.plot_code, crop.location_label].filter(Boolean).join(" · ")),
  );
  const stats = element("div", "crop-stats");
  [["Health score", formatValue(crop.latest_health_score, "latest_health_score")], ["Status", isDeleted ? "Deleted" : titleCase(crop.status || "unknown")], ["Progress", titleCase(crop.latest_progress_status || "insufficient data")], ["Last updated", formatValue(crop.updated_at || crop.last_checked_at, "updated_at")]].forEach(([label, value]) => {
    const stat = element("span");
    stat.append(element("small", "", label), element("strong", "", String(value)));
    stats.append(stat);
  });
  const actions = element("div", "row-actions");
  const edit = element("button", "secondary-button", "Edit");
  edit.type = "button";
  edit.addEventListener("click", () => openRecordDialog("crops", crop));
  const archive = element("button", "danger-button", "Archive");
  archive.type = "button";
  archive.disabled = isDeleted;
  archive.textContent = isDeleted ? "Deleted" : "Archive";
  archive.addEventListener("click", () => archiveRecord("crops", crop));
  actions.append(edit, archive);
  row.append(copy, stats, actions);
  row.addEventListener("click", (event) => {
    if (!event.target.closest("button")) showCropActivity(crop);
  });
  row.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      showCropActivity(crop);
    }
  });
  return row;
}

async function showCropActivity(crop) {
  const loading = element("div", "empty-state", "Loading crop activity...");
  openDetailDialog(titleCase(crop.crop_type), crop.crop_name || titleCase(crop.crop_type), loading);
  try {
    const response = await api(`/v1/admin/crops/${encodeURIComponent(crop.id)}/activity`);
    const body = element("div", "crop-activity-view");
    const summary = element("section", "crop-activity-summary");
    const icon = element("span", "crop-activity-icon", cropIcon(response.crop.crop_type));
    const summaryCopy = element("div");
    const cropStatus = response.crop.is_deleted === true || response.crop.is_deleted === 1
      ? "Deleted"
      : titleCase(response.crop.status || "unknown");
    summaryCopy.append(
      element("strong", "", response.crop.crop_name || titleCase(response.crop.crop_type)),
      element("small", "", `${cropStatus} · ${response.crop.latest_health_score ?? "--"}% health`),
    );
    summary.append(icon, summaryCopy);
    body.append(summary);

    const timeline = element("div", "crop-activity-timeline");
    (response.events || []).forEach((activity) => {
      const item = element("article", "crop-activity-item");
      const marker = element("span", `activity-marker ${activity.type || "update"}`);
      const copy = element("div");
      copy.append(
        element("strong", "", activity.title),
        element("p", "", activity.detail),
        element("small", "", formatValue(activity.timestamp, "created_at")),
      );
      const health = element("span", "activity-health", activity.health_score === null || activity.health_score === undefined ? "--" : `${Math.round(Number(activity.health_score))}%`);
      health.title = "Health score at this point";
      item.append(marker, copy, health);
      timeline.append(item);
    });
    if (!timeline.children.length) timeline.append(element("div", "empty-state compact", "No activity has been recorded for this crop yet."));
    body.append(timeline);
    $("#detailDialogBody").replaceChildren(body);
  } catch (failure) {
    $("#detailDialogBody").replaceChildren(element("div", "empty-state", failure.message));
  }
}

async function renderAdminProfile() {
  const response = await api("/v1/admin/users?per_page=100");
  const admin = response.items.find((user) => user.id === state.admin.id);
  if (!admin) throw new Error("Your administrator profile could not be loaded.");
  admin.name = admin.profile?.display_name || admin.profile?.full_name || admin.email;
  const panel = element("section", "panel glass profile-panel");
  const edit = element("button", "primary-button", "Edit profile");
  edit.type = "button";
  edit.addEventListener("click", () => openUserDialog(admin));
  panel.append(panelHeader(labels.profile[0], labels.profile[1], [edit]));
  const details = element("div", "detail-grid");
  appendDetail(details, "email", admin.email);
  appendDetail(details, "role", admin.admin_role);
  Object.entries(admin.profile || {}).forEach(([field, value]) => appendDetail(details, field, value));
  panel.append(details);
  content.replaceChildren(panel);
}

async function renderResource(resource) {
  const response = await api(`/v1/admin/resources/${resource}`);
  state.rows = response.items;
  const panel = element("section", "panel glass");
  const search = element("input", "search-input");
  search.type = "search";
  search.placeholder = `Search ${labels[resource][0].toLowerCase()}`;
  search.setAttribute("aria-label", `Search ${labels[resource][0]}`);
  let timer;
  search.addEventListener("input", () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => searchResource(resource, search.value), 280);
  });
  const add = element("button", "primary-button", "Add record");
  add.type = "button";
  add.addEventListener("click", () => openRecordDialog(resource));
  panel.append(panelHeader(labels[resource][0], labels[resource][1], [search, add]));
  panel.append(buildResourceTable(resource, state.rows));
  content.replaceChildren(panel);
}

async function searchResource(resource, query) {
  try {
    const response = await api(`/v1/admin/resources/${resource}?query=${encodeURIComponent(query)}`);
    state.rows = response.items;
    const previous = content.querySelector(".table-wrap");
    previous?.replaceWith(buildResourceTable(resource, state.rows));
  } catch (failure) { showStatus(failure.message, true); }
}

function buildResourceTable(resource, rows) {
  return buildTable(rows, displayColumns[resource], (row) => {
    const edit = element("button", "secondary-button", "Edit");
    edit.type = "button";
    edit.addEventListener("click", () => openRecordDialog(resource, row));
    const archive = element("button", "danger-button", resource === "diseases" ? "Deactivate" : "Archive");
    archive.type = "button";
    archive.addEventListener("click", () => archiveRecord(resource, row));
    return [edit, archive];
  });
}

async function archiveRecord(resource, row) {
  const name = row.disease_name || row.treatment_title || row.crop_name || row.id;
  if (!window.confirm(`Archive ${name}? This removes it from active application workflows.`)) return;
  try {
    await api(`/v1/admin/resources/${resource}/${encodeURIComponent(row.id)}`, { method: "DELETE" });
    showStatus("Record archived and audit logged.");
    await selectSection(resource);
  } catch (failure) { showStatus(failure.message, true); }
}

async function renderUsers() {
  const response = await api("/v1/admin/users");
  state.rows = response.items.map((row) => ({
    ...row,
    name: row.profile?.display_name || row.profile?.full_name || "--",
    farm_location: [row.profile?.barangay, row.profile?.municipality, row.profile?.province, row.profile?.country].filter(Boolean).join(", ") || "--",
    access_status: row.admin_role || (row.admin_access_requested ? "pending approval" : "standard user"),
  }));
  const panel = element("section", "panel glass");
  const tabs = element("div", "segmented-control");
  [["users", "Users"], ["admins", "Admins"]].forEach(([value, label]) => {
    const tab = element("button", state.userTab === value ? "active" : "", label);
    tab.type = "button";
    tab.setAttribute("aria-pressed", String(state.userTab === value));
    tab.addEventListener("click", () => {
      state.userTab = value;
      tabs.querySelectorAll("button").forEach((button) => {
        const active = button === tab;
        button.classList.toggle("active", active);
        button.setAttribute("aria-pressed", String(active));
      });
      renderUserTable(panel);
    });
    tabs.append(tab);
  });
  const add = element("button", "primary-button", "Add user");
  add.type = "button";
  add.addEventListener("click", openInviteUserDialog);
  panel.append(panelHeader(labels.users[0], labels.users[1], [tabs, add]));
  content.replaceChildren(panel);
  renderUserTable(panel);
}

function openInviteUserDialog() {
  state.editing = { resource: "user-invite", record: null };
  $("#dialogEyebrow").textContent = "User management";
  $("#dialogTitle").textContent = "Add new user";
  $("#recordError").textContent = "";
  const fields = $("#recordFields");
  fields.replaceChildren();
  [
    ["first_name", "First name", "text", true],
    ["last_name", "Last name", "text", true],
    ["farm_address", "Farm address", "text", true],
    ["phone", "Phone number (optional)", "tel", false],
    ["email", "Email address", "email", true],
  ].forEach(([name, labelText, type, required]) => {
    const wrap = element("div", name === "farm_address" ? "field-wide" : "");
    const label = element("label", "", `${labelText}${required ? " *" : ""}`);
    const input = element("input");
    input.name = name;
    input.type = type;
    input.required = required;
    label.htmlFor = `field-${name}`;
    input.id = `field-${name}`;
    wrap.append(label, input);
    fields.append(wrap);
  });
  const roleWrap = element("div");
  const roleLabel = element("label", "", "Role *");
  const roleSelect = element("select");
  roleSelect.name = "role";
  roleSelect.id = "field-role";
  roleSelect.required = true;
  roleLabel.htmlFor = roleSelect.id;
  [["user", "Non-admin"], ["admin", "Admin"]].forEach(([value, labelText]) => {
    const option = element("option", "", labelText);
    option.value = value;
    option.disabled = value === "admin" && state.admin?.role !== "superadmin";
    roleSelect.append(option);
  });
  roleWrap.append(roleLabel, roleSelect);
  fields.append(roleWrap);
  const note = element("p", "field-wide approval-note", "Supabase will email an invitation link. The user confirms the address and creates their own password; administrators never see it.");
  fields.append(note);
  $("#recordDialog").showModal();
}

function renderUserTable(panel) {
  const oldTable = panel.querySelector(".table-wrap");
  const rows = state.rows.filter((row) => state.userTab === "users"
    ? !row.admin_role && !row.admin_access_requested
    : Boolean(row.admin_role || row.admin_access_requested));
  const table = buildTable(rows, displayColumns[state.userTab], (row) => {
    const actions = [];
    const privilegedList = state.userTab === "admins";
    const isSuperadmin = state.admin?.role === "superadmin";
    const isSelf = row.id === state.admin?.id;
    if (!privilegedList || isSuperadmin || isSelf) {
      const edit = element("button", "secondary-button", "Edit");
      edit.type = "button";
      edit.addEventListener("click", () => openUserDialog(row));
      actions.push(edit);
    }
    if (!privilegedList || isSuperadmin) {
      const reset = element("button", "secondary-button", "Reset password");
      reset.type = "button";
      reset.addEventListener("click", () => sendPasswordReset(row));
      actions.push(reset);
    }
    const suspended = Boolean(row.banned_until && new Date(row.banned_until) > new Date());
    if (!isSelf && (!privilegedList || isSuperadmin)) {
      const button = element("button", suspended ? "secondary-button" : "danger-button", suspended ? "Restore" : "Suspend");
      button.type = "button";
      button.addEventListener("click", () => updateSuspension(row, !suspended));
      actions.push(button);
    }
    const role = String(row.admin_role || "").toLowerCase();
    if (state.userTab === "admins" && state.admin?.role === "superadmin" && row.id !== state.admin.id && role !== "superadmin") {
      const approved = role === "admin";
      if (!approved && row.admin_access_requested) {
        const declineButton = element("button", "icon-action danger-button", "×");
        declineButton.type = "button";
        declineButton.title = "Decline administrator request";
        declineButton.setAttribute("aria-label", `Decline administrator request for ${row.email}`);
        declineButton.addEventListener("click", () => updateAdminRole(row, false));
        actions.push(declineButton);
      }
      const roleButton = element("button", `icon-action ${approved ? "danger-button" : "secondary-button"}`, approved ? "×" : "✓");
      roleButton.type = "button";
      roleButton.title = approved ? "Revoke administrator access" : "Approve administrator request";
      roleButton.setAttribute("aria-label", `${approved ? "Revoke administrator access from" : "Approve administrator request for"} ${row.email}`);
      roleButton.addEventListener("click", () => updateAdminRole(row, !approved));
      actions.push(roleButton);
    }
    return actions;
  });
  if (oldTable) oldTable.replaceWith(table);
  else panel.append(table);
}

function openUserDialog(user) {
  state.editing = { resource: "user-profile", record: user };
  $("#dialogEyebrow").textContent = user.admin_role ? "Administrator" : "User";
  $("#dialogTitle").textContent = "Edit profile";
  $("#recordError").textContent = "";
  const fields = $("#recordFields");
  fields.replaceChildren();
  const emailWrap = element("div", "field-wide readonly-field");
  const emailLabel = element("label", "", "Email address");
  const emailInput = element("input");
  emailInput.value = user.email || "";
  emailInput.readOnly = true;
  emailWrap.append(emailLabel, emailInput, element("small", "field-help", "Email changes must be confirmed by the account owner from a signed-in CropCare session."));
  fields.append(emailWrap);
  ["full_name", "display_name", "phone", "barangay", "municipality", "province", "country", "preferred_language"].forEach((field) => {
    fields.append(buildField(field, user.profile?.[field], false));
  });
  $("#recordDialog").showModal();
}

async function sendPasswordReset(user) {
  if (!window.confirm(`Send a secure password reset email to ${user.email}?`)) return;
  try {
    await api(`/v1/admin/users/${encodeURIComponent(user.id)}/password-reset`, { method: "POST" });
    showStatus("Password reset email sent by Supabase.");
  } catch (failure) { showStatus(failure.message, true); }
}

async function updateAdminRole(user, approved) {
  const declining = !approved && user.admin_access_requested && !user.admin_role;
  const verb = approved
    ? "approve administrator access for"
    : declining ? "decline the administrator request from" : "revoke administrator access from";
  if (!window.confirm(`${verb[0].toUpperCase()}${verb.slice(1)} ${user.email}?`)) return;
  try {
    await api(`/v1/admin/users/${encodeURIComponent(user.id)}/admin-role`, {
      method: "PATCH",
      body: JSON.stringify({ approved }),
    });
    showStatus(approved
      ? "Administrator access approved."
      : declining ? "Administrator request declined." : "Administrator access revoked.");
    await renderUsers();
  } catch (failure) { showStatus(failure.message, true); }
}

async function updateSuspension(user, suspended) {
  const verb = suspended ? "suspend" : "restore";
  if (!window.confirm(`${verb[0].toUpperCase()}${verb.slice(1)} ${user.email}?`)) return;
  try {
    await api(`/v1/admin/users/${encodeURIComponent(user.id)}/suspension`, { method: "PATCH", body: JSON.stringify({ suspended }) });
    showStatus(`Account ${suspended ? "suspended" : "restored"}.`);
    await renderUsers();
  } catch (failure) { showStatus(failure.message, true); }
}

async function renderSystem() {
  const response = await api("/v1/admin/audit");
  const panel = element("section", "panel glass");
  panel.append(panelHeader("Administrative audit", "Recent administrator changes. Detailed values are intentionally excluded."));
  const list = element("div", "audit-list");
  if (!response.items.length) list.append(element("div", "empty-state", "No persisted audit events found. Apply the admin security migration to enable audit history."));
  response.items.forEach((item) => {
    const row = element("article", "audit-item");
    row.append(element("span", "", formatValue(item.created_at, "created_at")), element("span", "badge", item.action), element("span", "", item.resource), element("span", "", item.actor_email || item.actor_id));
    list.append(row);
  });
  panel.append(list);
  content.replaceChildren(panel);
}

function openRecordDialog(resource, record = null) {
  state.editing = { resource, record };
  $("#dialogEyebrow").textContent = labels[resource][0];
  $("#dialogTitle").textContent = record ? "Edit record" : "Add record";
  $("#recordError").textContent = "";
  const fields = $("#recordFields");
  fields.replaceChildren();
  const metadata = state.catalog[resource];
  metadata.editable.forEach((field) => fields.append(buildField(field, record?.[field], metadata.required.includes(field))));
  $("#recordDialog").showModal();
}

function buildField(field, value, required) {
  if (booleanFields.has(field)) {
    const wrap = element("div", "checkbox-field");
    const input = element("input");
    input.type = "checkbox";
    input.name = field;
    input.id = `field-${field}`;
    input.checked = value === true;
    const label = element("label", "", field.replaceAll("_", " "));
    label.htmlFor = input.id;
    wrap.append(input, label);
    return wrap;
  }
  const wrap = element("div", wideFields.has(field) ? "field-wide" : "");
  const label = element("label", "", `${field.replaceAll("_", " ")}${required ? " *" : ""}`);
  label.htmlFor = `field-${field}`;
  let input;
  if (wideFields.has(field)) input = element("textarea");
  else if (selectOptions[field]) {
    input = element("select");
    input.append(element("option", "", "Select"));
    selectOptions[field].forEach((option) => {
      const node = element("option", "", option.replaceAll("_", " "));
      node.value = option;
      node.selected = option === value;
      input.append(node);
    });
  } else {
    input = element("input");
    input.type = numberFields.has(field) ? "number" : dateFields.has(field) ? "datetime-local" : "text";
    if (numberFields.has(field)) input.step = field === "confidence_score" ? "0.01" : "1";
  }
  input.id = `field-${field}`;
  input.name = field;
  input.required = required;
  if (!(input instanceof HTMLSelectElement)) {
    if (dateFields.has(field) && value) input.value = String(value).slice(0, 16);
    else if (arrayFields.has(field) && Array.isArray(value)) input.value = value.join("\n");
    else input.value = value ?? "";
  }
  wrap.append(label, input);
  return wrap;
}

async function saveRecord(event) {
  event.preventDefault();
  const { resource, record } = state.editing;
  const data = {};
  new FormData(event.currentTarget).forEach((value, key) => {
    if (arrayFields.has(key)) data[key] = String(value).split("\n").map((item) => item.trim()).filter(Boolean);
    else if (numberFields.has(key)) data[key] = value === "" ? null : Number(value);
    else if (dateFields.has(key)) data[key] = value ? new Date(String(value)).toISOString() : null;
    else data[key] = value;
  });
  if (state.catalog[resource]) {
    booleanFields.forEach((field) => {
      const input = event.currentTarget.elements[field];
      if (state.catalog[resource].editable.includes(field) && input) data[field] = input.checked === true;
    });
  }
  const error = $("#recordError");
  error.textContent = "";
  try {
    if (resource === "user-invite") {
      await api("/v1/admin/users/invite", { method: "POST", body: JSON.stringify(data) });
      $("#recordDialog").close();
      showStatus("Invitation sent. The user must confirm their email and create a password.");
      state.userTab = data.role === "admin" ? "admins" : "users";
      await renderUsers();
      return;
    }
    if (resource === "user-profile") {
      await api(`/v1/admin/users/${encodeURIComponent(record.id)}/profile`, { method: "PATCH", body: JSON.stringify(data) });
      $("#recordDialog").close();
      showStatus("Profile updated and audit logged.");
      if (record.id === state.admin?.id) await renderAdminProfile();
      else await renderUsers();
      return;
    }
    if (resource === "treatment-protocol") {
      const diseaseId = data.disease_id || record?.id;
      if (!diseaseId) throw new Error("Select a disease.");
      const duration = Number(data.expected_duration_days);
      const dailySteps = [];
      for (let dayNumber = 1; dayNumber <= duration; dayNumber += 1) {
        const tasks = String(data[`day_${dayNumber}_tasks`] || "").split("\n").map((task) => task.trim()).filter(Boolean);
        dailySteps.push({
          day_number: dayNumber,
          day_title: data[`day_${dayNumber}_title`] || `Day ${dayNumber}`,
          tasks,
          notes: data[`day_${dayNumber}_notes`] || null,
        });
      }
      await api(`/v1/admin/treatment-protocols/${encodeURIComponent(diseaseId)}`, {
        method: "PUT",
        body: JSON.stringify({
          treatment_title: data.treatment_title,
          treatment_information: data.treatment_information,
          expected_duration_days: duration,
          daily_steps: dailySteps,
        }),
      });
      $("#recordDialog").close();
      showStatus("Treatment protocol and daily steps saved to Supabase.");
      await selectSection("treatments");
      return;
    }
    const path = record ? `/v1/admin/resources/${resource}/${encodeURIComponent(record.id)}` : `/v1/admin/resources/${resource}`;
    await api(path, { method: record ? "PATCH" : "POST", body: JSON.stringify(data) });
    $("#recordDialog").close();
    showStatus(`Record ${record ? "updated" : "created"} and audit logged.`);
    await selectSection(resource);
  } catch (failure) { error.textContent = failure.message; }
}

$("#loginForm").addEventListener("submit", signIn);
$("#mfaForm").addEventListener("submit", submitMfa);
$("#mfaCancelButton").addEventListener("click", cancelMfa);
$("#registerForm").addEventListener("submit", registerAccount);
$("#inviteForm").addEventListener("submit", completeInvitation);
$("#authModeButton").addEventListener("click", () => {
  setAuthMode($("#authModeButton").dataset.mode !== "register");
});
$("#signOutButton").addEventListener("click", () => signOut(true));
$("#adminProfileButton").addEventListener("click", () => selectSection("profile"));
$("#refreshButton").addEventListener("click", () => selectSection(state.section));
$("#menuButton").addEventListener("click", () => $(".sidebar").classList.toggle("open"));
$("#navigation").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-section]");
  if (button) selectSection(button.dataset.section);
});
$("#recordForm").addEventListener("submit", saveRecord);
$("#closeDialogButton").addEventListener("click", () => $("#recordDialog").close());
$("#cancelDialogButton").addEventListener("click", () => $("#recordDialog").close());
$("#closeContentDialogButton").addEventListener("click", () => $("#contentDialog").close());
$("#closeDetailDialogButton").addEventListener("click", () => $("#detailDialog").close());
window.addEventListener("pagehide", () => { state.token = ""; });
initializeAuthCallback();
