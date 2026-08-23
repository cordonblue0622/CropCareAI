-- Run the preview first. It changes no data.
-- The app only uses a day-by-day protocol when every day from 1 through the
-- parent record's estimated_recovery_days is present and active.

with active_days as (
  select
    d.id,
    d.crop_type::text as crop_type,
    d.disease_name,
    d.estimated_recovery_days,
    array_agg(s.day_number order by s.day_number)
      filter (where s.is_active = true) as active_day_numbers
  from public.disease_knowledge_base d
  left join public.disease_treatment_day_steps s
    on s.disease_knowledge_base_id = d.id
  where d.is_active = true
  group by d.id
)
select
  crop_type,
  disease_name,
  estimated_recovery_days,
  coalesce(active_day_numbers, '{}') as active_day_numbers,
  case
    when estimated_recovery_days is null then 'Set a duration and add daily rows.'
    when active_day_numbers = array( select generate_series(1, estimated_recovery_days) )
      then 'Complete daily protocol'
    else 'Needs a contiguous daily protocol'
  end as protocol_status
from active_days
order by crop_type, disease_name;

-- Run this section only after reviewing the preview above. It updates source
-- provenance only; it does not delete, deactivate, or create treatment rows.

begin;

with citations(crop_type, disease_name, source_name, source_url) as (
  values
    ('tomato', 'tomato_bacterial_spot', 'UC IPM: Bacterial Spot', 'https://ipm.ucanr.edu/agriculture/tomato/bacterial-spot'),
    ('tomato', 'Early Blight', 'UC IPM: Early Blight', 'https://ipm.ucanr.edu/agriculture/tomato/early-blight'),
    ('tomato', 'tomato_early_blight', 'UC IPM: Early Blight', 'https://ipm.ucanr.edu/agriculture/tomato/early-blight'),
    ('tomato', 'tomato_late_blight', 'UC IPM: Late Blight', 'https://ipm.ucanr.edu/agriculture/tomato/late-blight'),
    ('tomato', 'tomato_leaf_mold', 'Cornell Vegetables: Tomato Leaf Mold', 'https://www.vegetables.cornell.edu/crops/tomatoes/tomato-leaf-mold/'),
    ('tomato', 'tomato_septoria_leaf_spot', 'Cornell Vegetables: Managing Tomato Diseases Successfully', 'https://www.vegetables.cornell.edu/pest-management/disease-factsheets/managing-tomato-diseases-successfully/'),
    ('tomato', 'tomato_spider_mites', 'University of Minnesota Extension: Twospotted spider mites in home gardens', 'https://extension.umn.edu/yard-and-garden-insects/spider-mites'),
    ('tomato', 'tomato_target_spot', 'Cornell Vegetables: Managing Tomato Diseases Successfully', 'https://www.vegetables.cornell.edu/pest-management/disease-factsheets/managing-tomato-diseases-successfully/'),
    ('tomato', 'tomato_mosaic_virus', 'UC IPM: Tobacco Mosaic', 'https://ipm.ucanr.edu/agriculture/tomato/tobacco-mosaic'),
    ('tomato', 'tomato_yellow_leaf_curl_virus', 'UC IPM: Tomato Yellow Leaf Curl', 'https://ipm.ucanr.edu/agriculture/tomato/tomato-yellow-leaf-curl'),
    ('tomato', 'tomato_healthy', 'UC IPM: Tomato Guidelines', 'https://ipm.ucanr.edu/agriculture/tomato/'),
    ('pepper', 'Bacterial Spot', 'UC IPM: Pepper Guidelines', 'https://ipm.ucanr.edu/agriculture/peppers/'),
    ('pepper', 'pepper_bacterial_spot', 'UC IPM: Pepper Guidelines', 'https://ipm.ucanr.edu/agriculture/peppers/'),
    ('pepper', 'pepper_healthy', 'UC IPM: Pepper Guidelines', 'https://ipm.ucanr.edu/agriculture/peppers/'),
    ('squash', 'squash_powdery_mildew', 'Cornell Vegetables: Cucurbit Powdery Mildew', 'https://www.vegetables.cornell.edu/crops/cucurbits/cucurbit-powdery-mildew/')
)
update public.disease_knowledge_base d
set
  source_name = c.source_name,
  source_url = c.source_url,
  updated_at = now()
from citations c
where d.crop_type::text = c.crop_type
  and lower(trim(d.disease_name)) = lower(c.disease_name)
  and d.is_active = true;

commit;

-- Philippine pesticide registration and the exact product label remain required
-- before adding a product name, rate, mixture, PPE, re-entry interval, or PHI:
-- https://fpa.da.gov.ph/registered-products/