"use strict";

const state = {
  token: "",
  admin: null,
  config: null,
  catalog: {},
  section: "overview",
  rows: [],
  editing: null,
};

const labels = {
  overview: ["Overview", "System health and managed record totals"],
  users: ["User management", "Registered accounts and access status"],
  diseases: ["Disease library", "Curated disease information and recommendations"],
  treatments: ["Treatment management", "Treatment plans assigned to monitored crops"],
  crops: ["Crop data", "Registered crop records and monitoring state"],
  diagnoses: ["Diagnosis data", "Model assessments and clinical metadata"],
  system: ["System data", "Administrative activity and platform records"],
};

const displayColumns = {
  users: ["email", "admin_role", "confirmed_at", "last_sign_in_at", "banned_until"],
  diseases: ["disease_name", "crop_type", "estimated_recovery_days", "is_active", "updated_at"],
  treatments: ["treatment_title", "disease_name", "status", "started_at", "updated_at"],
  crops: ["crop_name", "crop_type", "status", "latest_health_score", "updated_at"],
  diagnoses: ["disease_name", "severity", "confidence_score", "diagnosis_mode", "diagnosed_at"],
};

const wideFields = new Set([
  "description", "symptoms", "causes", "treatment_steps", "prevention_steps",
  "severity_notes", "caution_notes", "notes", "summary",
]);
const arrayFields = new Set(["symptoms", "causes", "treatment_steps", "prevention_steps"]);
const booleanFields = new Set(["is_active", "reassessment_required"]);
const numberFields = new Set(["estimated_recovery_days", "latest_health_score", "confidence_score"]);
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
  if (response.status === 401 || response.status === 403) {
    signOut(false);
    throw new Error(response.status === 403 ? "This account does not have administrator access." : "Your session has expired.");
  }
  if (!response.ok) {
    let message = "The operation could not be completed.";
    try { message = (await response.json()).detail || message; } catch (_) {}
    throw new Error(message);
  }
  if (response.status === 204) return null;
  return response.json();
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
    const [admin, catalog] = await Promise.all([api("/v1/admin/me"), api("/v1/admin/resources")]);
    state.admin = admin;
    state.catalog = catalog;
    $("#adminEmail").textContent = admin.email || "Administrator";
    $("#adminRole").textContent = admin.role;
    $("#adminInitial").textContent = (admin.email || "A").slice(0, 1).toUpperCase();
    $("#loginView").classList.add("hidden");
    $("#appView").classList.remove("hidden");
    await selectSection("overview");
  } catch (failure) {
    state.token = "";
    error.textContent = failure.message;
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
  error.textContent = "";
  success.textContent = "";
  if (passwordInput.value !== confirmInput.value) {
    error.textContent = "Passwords do not match.";
    return;
  }
  submit.disabled = true;
  submit.textContent = "Creating account...";
  try {
    if (!state.config) state.config = await fetch("/admin/config", { cache: "no-store" }).then((res) => res.json());
    if (!state.config.supabaseUrl || !state.config.supabaseAnonKey) throw new Error("Account registration is not configured.");
    const response = await fetch(`${state.config.supabaseUrl}/auth/v1/signup`, {
      method: "POST",
      headers: { "apikey": state.config.supabaseAnonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ email: $("#registerEmail").value.trim(), password: passwordInput.value }),
      cache: "no-store",
    });
    if (!response.ok) {
      let message = "The account could not be created.";
      try { message = (await response.json()).msg || message; } catch (_) {}
      throw new Error(message);
    }
    success.textContent = "Account created. Confirm your email, then contact a superadmin for access approval.";
  } catch (failure) {
    error.textContent = failure.message;
  } finally {
    passwordInput.value = "";
    confirmInput.value = "";
    submit.disabled = false;
    submit.textContent = "Create account";
  }
}

async function signOut(callServer = true) {
  const token = state.token;
  state.token = "";
  state.admin = null;
  state.rows = [];
  $("#appView").classList.add("hidden");
  $("#loginView").classList.remove("hidden");
  $("#loginForm").reset();
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
    else if (section === "system") await renderSystem();
    else await renderResource(section);
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
  const metricNames = ["users", "crops", "diagnoses", "treatments", "diseases"];
  metricNames.forEach((name) => {
    const card = element("article", "metric-card glass");
    card.append(element("span", "", labels[name]?.[0] || name), element("strong", "", summary.counts[name] ?? "--"), element("small", "", "Managed records"));
    metrics.append(card);
  });
  content.replaceChildren(hero, metrics);
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
  state.rows = response.items;
  const panel = element("section", "panel glass");
  panel.append(panelHeader(labels.users[0], labels.users[1]));
  panel.append(buildTable(state.rows, displayColumns.users, (row) => {
    const actions = [];
    const suspended = Boolean(row.banned_until && new Date(row.banned_until) > new Date());
    const button = element("button", suspended ? "secondary-button" : "danger-button", suspended ? "Restore" : "Suspend");
    button.type = "button";
    button.addEventListener("click", () => updateSuspension(row, !suspended));
    actions.push(button);
    const role = String(row.admin_role || "").toLowerCase();
    if (state.admin?.role === "superadmin" && row.id !== state.admin.id && role !== "superadmin") {
      const approved = role === "admin";
      const roleButton = element("button", approved ? "danger-button" : "secondary-button", approved ? "Revoke admin" : "Approve admin");
      roleButton.type = "button";
      roleButton.addEventListener("click", () => updateAdminRole(row, !approved));
      actions.push(roleButton);
    }
    return actions;
  }));
  content.replaceChildren(panel);
}

async function updateAdminRole(user, approved) {
  const verb = approved ? "approve administrator access for" : "revoke administrator access from";
  if (!window.confirm(`${verb[0].toUpperCase()}${verb.slice(1)} ${user.email}?`)) return;
  try {
    await api(`/v1/admin/users/${encodeURIComponent(user.id)}/admin-role`, {
      method: "PATCH",
      body: JSON.stringify({ approved }),
    });
    showStatus(approved ? "Administrator access approved." : "Administrator access revoked.");
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
  booleanFields.forEach((field) => {
    if (state.catalog[resource].editable.includes(field)) data[field] = event.currentTarget.elements[field]?.checked === true;
  });
  const error = $("#recordError");
  error.textContent = "";
  try {
    const path = record ? `/v1/admin/resources/${resource}/${encodeURIComponent(record.id)}` : `/v1/admin/resources/${resource}`;
    await api(path, { method: record ? "PATCH" : "POST", body: JSON.stringify(data) });
    $("#recordDialog").close();
    showStatus(`Record ${record ? "updated" : "created"} and audit logged.`);
    await selectSection(resource);
  } catch (failure) { error.textContent = failure.message; }
}

$("#loginForm").addEventListener("submit", signIn);
$("#registerForm").addEventListener("submit", registerAccount);
$("#authModeButton").addEventListener("click", () => {
  setAuthMode($("#authModeButton").dataset.mode !== "register");
});
$("#signOutButton").addEventListener("click", () => signOut(true));
$("#refreshButton").addEventListener("click", () => selectSection(state.section));
$("#menuButton").addEventListener("click", () => $(".sidebar").classList.toggle("open"));
$("#navigation").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-section]");
  if (button) selectSection(button.dataset.section);
});
$("#recordForm").addEventListener("submit", saveRecord);
$("#closeDialogButton").addEventListener("click", () => $("#recordDialog").close());
$("#cancelDialogButton").addEventListener("click", () => $("#recordDialog").close());
window.addEventListener("pagehide", () => { state.token = ""; });
