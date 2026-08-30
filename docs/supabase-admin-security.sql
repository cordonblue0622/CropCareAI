-- CropCare AI administrator audit storage.
-- Run once in the Supabase SQL editor as the project owner.
-- Browser clients cannot read or write this table; the backend service role
-- records metadata about administrator mutations without storing field values.

begin;

create table if not exists public.admin_audit_events (
  id uuid primary key,
  actor_id uuid not null,
  actor_email text,
  action text not null check (action in ('create', 'update', 'archive', 'suspend', 'restore', 'approve', 'revoke')),
  resource text not null check (resource in ('users', 'diseases', 'treatments', 'crops', 'diagnoses')),
  record_id text not null,
  changed_fields text[] not null default '{}',
  created_at timestamptz not null default now()
);

alter table public.admin_audit_events
  drop constraint if exists admin_audit_events_action_check;
alter table public.admin_audit_events
  add constraint admin_audit_events_action_check
  check (action in ('create', 'update', 'archive', 'suspend', 'restore', 'approve', 'revoke'));

create index if not exists admin_audit_events_created_at_idx
  on public.admin_audit_events (created_at desc);
create index if not exists admin_audit_events_actor_id_idx
  on public.admin_audit_events (actor_id, created_at desc);

alter table public.admin_audit_events enable row level security;
revoke all on table public.admin_audit_events from anon, authenticated;

comment on table public.admin_audit_events is
  'Append-only metadata for CropCare administrator changes. Accessible through the service-role backend only.';

commit;
