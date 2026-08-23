-- Run once in the Supabase SQL Editor before shipping an app that writes
-- diagnoses with an exact linked chat conversation.

alter table public.diagnoses
  add column if not exists chat_session_id uuid
  references public.chat_sessions(id) on delete set null;

create index if not exists diagnoses_chat_session_id_idx
  on public.diagnoses (chat_session_id);