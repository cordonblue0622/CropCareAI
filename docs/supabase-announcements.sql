-- CropCare AI administrator announcements, discussions, and mobile alert fan-out.
-- Run in the Supabase SQL editor as the project owner before deploying the
-- matching backend. This migration preserves existing rows and is idempotent.

begin;

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  audience text not null default 'admin',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint announcements_title_valid
    check (char_length(btrim(title)) between 1 and 200),
  constraint announcements_body_valid
    check (char_length(btrim(body)) between 1 and 10000),
  constraint announcements_audience_valid
    check (audience in ('admin', 'all_users'))
);

-- Posts created by the earlier all-user announcement migration were already
-- delivered publicly, so preserve their meaning when adding the audience.
alter table public.announcements add column if not exists audience text;
update public.announcements set audience = 'all_users' where audience is null;
alter table public.announcements alter column audience set default 'admin';
alter table public.announcements alter column audience set not null;
alter table public.announcements drop constraint if exists announcements_audience_valid;
alter table public.announcements add constraint announcements_audience_valid
  check (audience in ('admin', 'all_users'));

create table if not exists public.announcement_likes (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  admin_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (announcement_id, admin_id)
);

create table if not exists public.announcement_replies (
  id uuid primary key default gen_random_uuid(),
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now(),
  constraint announcement_replies_body_valid
    check (char_length(btrim(body)) between 1 and 5000)
);

create index if not exists announcements_created_at_idx
  on public.announcements (created_at desc, id desc);
create index if not exists announcement_replies_thread_idx
  on public.announcement_replies (announcement_id, created_at, id);

alter table public.announcements enable row level security;
alter table public.announcement_likes enable row level security;
alter table public.announcement_replies enable row level security;
revoke all on table public.announcements from public, anon, authenticated;
revoke all on table public.announcement_likes from public, anon, authenticated;
revoke all on table public.announcement_replies from public, anon, authenticated;

-- Remove the earlier policy that exposed every post to every signed-in user.
-- All announcement reads and mutations now go through admin-only backend RPCs.
drop policy if exists announcements_read_authenticated on public.announcements;

comment on table public.announcements is
  'Administrator-authored posts. No direct anon or authenticated access.';
comment on table public.announcement_likes is
  'One like per administrator and announcement. Service-role backend access only.';
comment on table public.announcement_replies is
  'Administrator discussion replies. Service-role backend access only.';

-- Replace the earlier RPC rather than leaving a second creation path behind.
drop function if exists public.create_announcement(text, text, uuid);

-- Creation and all-user alert fan-out commit together. Admin-only posts never
-- insert notification rows. Every RPC also verifies the trusted auth metadata
-- role as defense in depth behind the FastAPI role and MFA checks.
create or replace function public.create_announcement(
  p_title text,
  p_body text,
  p_audience text,
  p_created_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_announcement public.announcements%rowtype;
  v_recipient_count integer := 0;
begin
  if not exists (
    select 1 from auth.users as actor
    where actor.id = p_created_by
      and actor.raw_app_meta_data ->> 'admin_role' in ('admin', 'superadmin')
  ) then
    raise exception 'Administrator access is required.' using errcode = '42501';
  end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 200 then
    raise exception 'Announcement title must be between 1 and 200 characters.';
  end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 10000 then
    raise exception 'Announcement body must be between 1 and 10000 characters.';
  end if;
  if p_audience not in ('admin', 'all_users') then
    raise exception 'Audience must be admin or all_users.';
  end if;

  insert into public.announcements (title, body, audience, created_by)
  values (btrim(p_title), btrim(p_body), p_audience, p_created_by)
  returning * into v_announcement;

  if v_announcement.audience = 'all_users' then
    insert into public.notifications (
      id, user_id, crop_id, treatment_id, type, title, body,
      scheduled_for, is_read, is_sent, created_at
    )
    select
      gen_random_uuid(),
      profile.id,
      null,
      null,
      'general',
      'CropCare AI Team — ' || v_announcement.title,
      v_announcement.body,
      v_announcement.created_at,
      false,
      true,
      v_announcement.created_at
    from public.profiles as profile;

    get diagnostics v_recipient_count = row_count;
  end if;

  return jsonb_build_object(
    'id', v_announcement.id,
    'title', v_announcement.title,
    'body', v_announcement.body,
    'audience', v_announcement.audience,
    'created_by', v_announcement.created_by,
    'created_at', v_announcement.created_at,
    'recipient_count', v_recipient_count
  );
end;
$$;

revoke all on function public.create_announcement(text, text, text, uuid) from public;
revoke execute on function public.create_announcement(text, text, text, uuid)
  from anon, authenticated;
grant execute on function public.create_announcement(text, text, text, uuid)
  to service_role;

create or replace function public.list_admin_announcements(
  p_admin_id uuid,
  p_limit integer default 200,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_items jsonb;
begin
  if not exists (
    select 1 from auth.users as actor
    where actor.id = p_admin_id
      and actor.raw_app_meta_data ->> 'admin_role' in ('admin', 'superadmin')
  ) then
    raise exception 'Administrator access is required.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit not between 1 and 200 then
    raise exception 'Page size must be between 1 and 200.';
  end if;
  if p_offset is null or p_offset < 0 then
    raise exception 'Page offset cannot be negative.';
  end if;

  select coalesce(
    jsonb_agg(page.post_json order by page.created_at desc, page.id desc),
    '[]'::jsonb
  )
  into v_items
  from (
    select announcement.created_at, announcement.id, jsonb_build_object(
      'id', announcement.id,
      'title', announcement.title,
      'body', announcement.body,
      'audience', announcement.audience,
      'created_by', announcement.created_by,
      'created_at', announcement.created_at,
      'author_name', coalesce(
        nullif(btrim(coalesce(author_profile.display_name, '')), ''),
        nullif(btrim(coalesce(author_profile.full_name, '')), ''),
        nullif(btrim(coalesce(author.raw_user_meta_data ->> 'full_name', '')), ''),
        nullif(author.email, ''),
        'Former administrator'
      ),
      'author_role', coalesce(
        nullif(author.raw_app_meta_data ->> 'admin_role', ''),
        'admin'
      ),
      'likes_count', (
        select count(*) from public.announcement_likes as likes
        where likes.announcement_id = announcement.id
      ),
      'liked_by_current_admin', exists (
        select 1 from public.announcement_likes as current_like
        where current_like.announcement_id = announcement.id
          and current_like.admin_id = p_admin_id
      ),
      'replies_count', (
        select count(*) from public.announcement_replies as reply_count
        where reply_count.announcement_id = announcement.id
      ),
      'replies', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', reply.id,
            'announcement_id', reply.announcement_id,
            'created_by', reply.created_by,
            'created_at', reply.created_at,
            'body', reply.body,
            'author_name', coalesce(
              nullif(btrim(coalesce(reply_profile.display_name, '')), ''),
              nullif(btrim(coalesce(reply_profile.full_name, '')), ''),
              nullif(btrim(coalesce(reply_author.raw_user_meta_data ->> 'full_name', '')), ''),
              nullif(reply_author.email, ''),
              'Former administrator'
            ),
            'author_role', coalesce(
              nullif(reply_author.raw_app_meta_data ->> 'admin_role', ''),
              'admin'
            )
          ) order by reply.created_at, reply.id
        ), '[]'::jsonb)
        from public.announcement_replies as reply
        left join public.profiles as reply_profile on reply_profile.id = reply.created_by
        left join auth.users as reply_author on reply_author.id = reply.created_by
        where reply.announcement_id = announcement.id
      )
    ) as post_json
    from public.announcements as announcement
    left join public.profiles as author_profile on author_profile.id = announcement.created_by
    left join auth.users as author on author.id = announcement.created_by
    order by announcement.created_at desc, announcement.id desc
    limit p_limit offset p_offset
  ) as page;

  return v_items;
end;
$$;

revoke all on function public.list_admin_announcements(uuid, integer, integer) from public;
revoke execute on function public.list_admin_announcements(uuid, integer, integer)
  from anon, authenticated;
grant execute on function public.list_admin_announcements(uuid, integer, integer)
  to service_role;

create or replace function public.set_announcement_like(
  p_announcement_id uuid,
  p_admin_id uuid,
  p_liked boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_likes_count integer;
begin
  if not exists (
    select 1 from auth.users as actor
    where actor.id = p_admin_id
      and actor.raw_app_meta_data ->> 'admin_role' in ('admin', 'superadmin')
  ) then
    raise exception 'Administrator access is required.' using errcode = '42501';
  end if;
  if p_liked is null then
    raise exception 'Liked must be true or false.';
  end if;
  if not exists (
    select 1 from public.announcements where id = p_announcement_id
  ) then
    raise exception 'Announcement not found.';
  end if;

  if p_liked then
    insert into public.announcement_likes (announcement_id, admin_id)
    values (p_announcement_id, p_admin_id)
    on conflict (announcement_id, admin_id) do nothing;
  else
    delete from public.announcement_likes
    where announcement_id = p_announcement_id and admin_id = p_admin_id;
  end if;

  select count(*) into v_likes_count
  from public.announcement_likes
  where announcement_id = p_announcement_id;

  return jsonb_build_object(
    'announcement_id', p_announcement_id,
    'liked', p_liked,
    'likes_count', v_likes_count
  );
end;
$$;

revoke all on function public.set_announcement_like(uuid, uuid, boolean) from public;
revoke execute on function public.set_announcement_like(uuid, uuid, boolean)
  from anon, authenticated;
grant execute on function public.set_announcement_like(uuid, uuid, boolean)
  to service_role;

create or replace function public.create_announcement_reply(
  p_announcement_id uuid,
  p_body text,
  p_created_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reply public.announcement_replies%rowtype;
  v_author_name text;
  v_author_role text;
begin
  if not exists (
    select 1 from auth.users as actor
    where actor.id = p_created_by
      and actor.raw_app_meta_data ->> 'admin_role' in ('admin', 'superadmin')
  ) then
    raise exception 'Administrator access is required.' using errcode = '42501';
  end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 5000 then
    raise exception 'Reply must be between 1 and 5000 characters.';
  end if;
  if not exists (
    select 1 from public.announcements where id = p_announcement_id
  ) then
    raise exception 'Announcement not found.';
  end if;

  insert into public.announcement_replies (announcement_id, body, created_by)
  values (p_announcement_id, btrim(p_body), p_created_by)
  returning * into v_reply;

  select
    coalesce(
      nullif(btrim(coalesce(author_profile.display_name, '')), ''),
      nullif(btrim(coalesce(author_profile.full_name, '')), ''),
      nullif(btrim(coalesce(author.raw_user_meta_data ->> 'full_name', '')), ''),
      nullif(author.email, ''),
      'Administrator'
    ),
    coalesce(nullif(author.raw_app_meta_data ->> 'admin_role', ''), 'admin')
  into v_author_name, v_author_role
  from auth.users as author
  left join public.profiles as author_profile on author_profile.id = author.id
  where author.id = p_created_by;

  return jsonb_build_object(
    'id', v_reply.id,
    'announcement_id', v_reply.announcement_id,
    'body', v_reply.body,
    'created_by', v_reply.created_by,
    'created_at', v_reply.created_at,
    'author_name', v_author_name,
    'author_role', v_author_role
  );
end;
$$;

revoke all on function public.create_announcement_reply(uuid, text, uuid) from public;
revoke execute on function public.create_announcement_reply(uuid, text, uuid)
  from anon, authenticated;
grant execute on function public.create_announcement_reply(uuid, text, uuid)
  to service_role;

commit;
