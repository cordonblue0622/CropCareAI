-- Fields used by the Supabase-backed administrator disease and treatment library.
-- Run once in the Supabase SQL editor as the project owner before deploying
-- the matching backend. The migration is idempotent.

begin;

alter table public.disease_knowledge_base
  add column if not exists severity text,
  add column if not exists treatment_title text,
  add column if not exists treatment_information text;

alter table public.disease_knowledge_base
  drop constraint if exists disease_knowledge_base_severity_check;
alter table public.disease_knowledge_base
  add constraint disease_knowledge_base_severity_check
  check (severity is null or severity in ('healthy', 'mild', 'moderate', 'severe'));

create unique index if not exists disease_treatment_day_steps_disease_day_idx
  on public.disease_treatment_day_steps (disease_knowledge_base_id, day_number);

commit;