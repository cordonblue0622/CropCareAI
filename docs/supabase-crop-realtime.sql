-- Enable cross-device live crop refreshes for authenticated app sessions.
-- Run once in the Supabase SQL editor for the project.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'crops'
  ) then
    alter publication supabase_realtime add table public.crops;
  end if;
end
$$;
