-- Evidence-linked eggplant and pechay treatment protocol templates.
--
-- This script modifies only disease_knowledge_base and
-- disease_treatment_day_steps. It does not change crops, diagnoses,
-- treatments, tasks, progress records, messages, or user accounts.
--
-- Product names, rates, intervals, PPE, re-entry intervals, and harvest
-- intervals are intentionally excluded. Any product decision must follow a
-- current Philippine FPA-registered label for the crop and confirmed target.

begin;

with protocols (
  crop_type,
  label_key,
  disease_name,
  description,
  treatment_steps,
  prevention_steps,
  estimated_recovery_days,
  caution_notes,
  source_name,
  source_url,
  care_group
) as (
  values
    ('eggplant', 'eggplant_healthy', 'Eggplant Healthy',
      'Routine eggplant monitoring plan for a crop with no visible symptoms.',
      $$["Check soil moisture before watering.", "Inspect leaves, shoots, and fruit for early pest or disease signs."]$$::jsonb,
      $$["Keep weeds and crop debris out of the bed.", "Use clean tools between plants."]$$::jsonb,
      7, null,
      'UC IPM: Eggplant Guidelines', 'https://ipm.ucanr.edu/agriculture/eggplant/', 'healthy'),
    ('eggplant', 'eggplant_insect_pest', 'Eggplant Insect Pest',
      'Provisional insect or mite damage. Confirm the pest before selecting a control.',
      $$["Inspect leaf undersides and young shoots for the pest.", "Use a product only after checking a current FPA label for eggplant and the identified target."]$$::jsonb,
      $$["Scout nearby solanaceous crops and weeds.", "Avoid unnecessary broad-spectrum insecticides."]$$::jsonb,
      7, 'The scanner result is provisional. Identify the pest before using a product.',
      'UC IPM: Eggplant Guidelines', 'https://ipm.ucanr.edu/agriculture/eggplant/', 'pest'),
    ('eggplant', 'eggplant_leaf_spot', 'Eggplant Leaf Spot',
      'Provisional leaf-spot diagnosis. Reduce leaf wetness and infected debris while confirming the cause.',
      $$["Water at the soil level and keep foliage dry.", "Use a product only with a current FPA label for eggplant and the confirmed target."]$$::jsonb,
      $$["Avoid handling wet foliage.", "Remove crop debris and keep spacing open for drying."]$$::jsonb,
      7, 'Leaf spots have several causes. Seek local review if fresh lesions continue to spread.',
      'UC IPM: Eggplant Guidelines', 'https://ipm.ucanr.edu/agriculture/eggplant/', 'leaf_spot'),
    ('eggplant', 'eggplant_mosaic_virus', 'Eggplant Mosaic Virus',
      'Mosaic-like symptoms may be viral. There is no direct curative treatment, so containment and confirmation are important.',
      $$["Handle healthy plants before suspect plants.", "Inspect for vector pests and nearby host weeds."]$$::jsonb,
      $$["Use clean planting material.", "Sanitize hands and tools between plants."]$$::jsonb,
      14, 'Do not rely on a product as a cure for a confirmed virus.',
      'UC IPM: Eggplant Mosaic Diseases Caused by Potyviruses', 'https://ipm.ucanr.edu/agriculture/eggplant/mosaic-diseases-caused-by-potyviruses/', 'virus'),
    ('eggplant', 'eggplant_small_leaf', 'Eggplant Small Leaf',
      'Small or distorted leaves can result from vector-borne disease, nutrition, herbicide injury, or stress and need confirmation.',
      $$["Photograph the whole plant and compare affected and normal shoots.", "Inspect for vector pests before changing inputs."]$$::jsonb,
      $$["Use healthy transplants.", "Control weeds that can host vector pests."]$$::jsonb,
      7, 'Do not apply pesticide, fertilizer, or herbicide changes until the cause is confirmed.',
      'UC IPM: Eggplant Guidelines', 'https://ipm.ucanr.edu/agriculture/eggplant/', 'uncertain'),
    ('eggplant', 'eggplant_white_mold', 'Eggplant White Mold',
      'White mold-like growth needs confirmation. Reduce moisture and prevent transfer while seeking a diagnosis.',
      $$["Keep foliage dry and remove only clearly infected material.", "Use a product only with a current FPA label for the confirmed target."]$$::jsonb,
      $$["Remove old crop debris.", "Sanitize tools after symptomatic plants."]$$::jsonb,
      7, 'White growth alone is not a reliable disease diagnosis.',
      'UC IPM: Eggplant Guidelines', 'https://ipm.ucanr.edu/agriculture/eggplant/', 'moisture_disease'),
    ('eggplant', 'eggplant_wilt', 'Eggplant Wilt',
      'Wilt can result from root disease, vascular disease, drought, waterlogging, or injury and needs cause confirmation.',
      $$["Check root-zone moisture and drainage before watering again.", "Seek prompt local review if wilt persists or spreads."]$$::jsonb,
      $$["Use well-drained soil and healthy transplants.", "Avoid moving soil and tools from a wilt area to healthy plants."]$$::jsonb,
      7, 'Wilt is not one disease. Confirm the cause before removing plants or using a pesticide.',
      'UC IPM: Eggplant Verticillium Wilt', 'https://ipm.ucanr.edu/agriculture/eggplant/verticillium-wilt/', 'wilt'),
    ('pechay', 'pechay_healthy', 'Pechay Healthy',
      'Routine pechay monitoring plan for a crop with no visible symptoms.',
      $$["Water at the base without splashing soil onto leaves.", "Inspect leaf undersides and the growing point for pests and spots."]$$::jsonb,
      $$["Keep the bed free of weeds and old crop debris.", "Maintain spacing and drainage so leaves dry after rain."]$$::jsonb,
      7, null,
      'UC IPM: Cole Crops Guidelines', 'https://ipm.ucanr.edu/agriculture/cole-crops/', 'healthy'),
    ('pechay', 'pechay_leaf_spot', 'Pechay Leaf Spot',
      'Leaf spots may be fungal or bacterial. Reduce leaf wetness and infected debris while confirming the cause.',
      $$["Remove severely spotted outer leaves when practical.", "Use a product only with a current FPA label for pechay or the applicable brassica crop and confirmed target."]$$::jsonb,
      $$["Use clean seed or transplants.", "Avoid working in the bed while leaves are wet."]$$::jsonb,
      7, 'Seek local confirmation if fresh spots continue on young leaves.',
      'Cornell Vegetables: Alternaria Leaf Spot of Brassicas', 'https://www.vegetables.cornell.edu/pest-management/disease-factsheets/alternaria-leaf-spot/', 'leaf_spot'),
    ('pechay', 'pechay_soft_rot', 'Pechay Soft Rot',
      'Soft, wet decay can spread rapidly in warm, wet conditions. Protect healthy plants and seek confirmation promptly.',
      $$["Remove severely rotted material promptly and clean tools.", "Correct drainage and avoid leaf injury."]$$::jsonb,
      $$["Avoid standing water.", "Keep the bed clean and remove damaged outer leaves promptly."]$$::jsonb,
      7, 'Soft rot can spread quickly. Remove badly decayed material from the growing area instead of composting it.',
      'UC IPM: Cole Crops Guidelines', 'https://ipm.ucanr.edu/agriculture/cole-crops/', 'rot'),
    ('pechay', 'pechay_aphids', 'Pechay Aphids',
      'Aphids cluster on tender leaves and can distort growth or leave sticky honeydew.',
      $$["Inspect the growing point and leaf undersides.", "Use a product only after confirming aphids and checking a current FPA label for pechay or the applicable brassica crop."]$$::jsonb,
      $$["Scout tender new growth frequently.", "Manage weeds that can host aphids."]$$::jsonb,
      7, 'Avoid unnecessary broad-spectrum insecticides that can disrupt natural enemies.',
      'UC IPM: Cole Crops Aphids', 'https://ipm.ucanr.edu/agriculture/cole-crops/aphids/', 'pest'),
    ('pechay', 'pechay_downy_mildew', 'Pechay Downy Mildew',
      'Yellow patches and growth on leaf undersides in cool, wet conditions may indicate downy mildew.',
      $$["Avoid overhead irrigation and handling wet leaves.", "Use a product only with a current FPA label for pechay or the applicable brassica crop and confirmed target."]$$::jsonb,
      $$["Use clean seed or transplants.", "Inspect after cool, humid, or rainy weather."]$$::jsonb,
      7, 'Seek local confirmation if fresh symptoms are increasing.',
      'UC IPM: Cole Crops Downy Mildew', 'https://ipm.ucanr.edu/agriculture/cole-crops/downy-mildew/', 'moisture_disease')
),
update_existing as (
  update public.disease_knowledge_base d
  set
    description = p.description,
    treatment_steps = array(select jsonb_array_elements_text(p.treatment_steps)),
    prevention_steps = array(select jsonb_array_elements_text(p.prevention_steps)),
    estimated_recovery_days = p.estimated_recovery_days,
    caution_notes = p.caution_notes,
    source_name = p.source_name,
    source_url = p.source_url,
    is_active = true,
    updated_at = now()
  from protocols p
  where d.crop_type::text = p.crop_type
    and lower(trim(d.disease_name)) = lower(p.disease_name)
  returning d.id
),
insert_missing as (
  insert into public.disease_knowledge_base (
    id, crop_type, disease_name, description, treatment_steps,
    prevention_steps, estimated_recovery_days, caution_notes, is_active,
    source_name, source_url, created_at, updated_at
  )
  select
    gen_random_uuid(), p.crop_type::crop_type_enum, p.disease_name,
    p.description,
    array(select jsonb_array_elements_text(p.treatment_steps)),
    array(select jsonb_array_elements_text(p.prevention_steps)),
    p.estimated_recovery_days, p.caution_notes, true,
    p.source_name, p.source_url, now(), now()
  from protocols p
  where not exists (
    select 1
    from public.disease_knowledge_base d
    where d.crop_type::text = p.crop_type
      and lower(trim(d.disease_name)) = lower(p.disease_name)
  )
  returning id, crop_type, disease_name
),
focus_groups (care_group, daily_focus, daily_care, escalation_note) as (
  values
    ('healthy',
      $$["Take a baseline whole-plant photo and inspect leaves, stems, and soil.", "Check root-zone moisture before watering.", "Inspect leaf undersides and new growth for pests or fresh symptoms.", "Remove weeds and fallen debris from around the crop.", "Inspect drainage, spacing, and plant support after weather changes.", "Take a comparison photo and note any new symptom or pest.", "Complete the weekly healthy-crop review and create a new diagnosis for any symptom."]$$::jsonb,
      'Record what you observed today. Focus on new symptoms rather than old marks or damage.',
      'Create a separate diagnosis promptly if new spots, wilt, chewing damage, or distortion appears.'),
    ('pest',
      $$["Take a whole-leaf baseline photo and identify the pest or damage pattern.", "Inspect leaf undersides and growing points for live pests, eggs, webbing, or honeydew.", "Remove only heavily infested material when practical and bag it.", "Check nearby host crops and weeds for the same pest.", "Compare pest activity with the Day 1 photo and protect natural enemies where present.", "Review a product only if the pest is confirmed and the current FPA label matches the crop and target.", "Complete a final photo reassessment and record improving, unchanged, or worsening activity."]$$::jsonb,
      'Work on healthy plants before affected plants and clean tools and hands after contact.',
      'Seek local advice when damage is spreading quickly or the pest cannot be identified.'),
    ('leaf_spot',
      $$["Take a baseline photo of whole affected leaves and record new versus old spots.", "Remove only clearly diseased leaves when there are few, then bag them and sanitize tools.", "Remove fallen debris and water at the soil level to keep foliage dry.", "Inspect nearby plants and new growth for fresh lesions after wet or humid weather.", "Check spacing, weeds, and drainage so leaves can dry quickly.", "Review a product only with a confirmed diagnosis and current FPA label for the crop and target.", "Complete a final comparison photo and record whether fresh lesions are fewer, unchanged, or increasing."]$$::jsonb,
      'Avoid overhead irrigation and handling plants while leaves are wet.',
      'Seek local diagnosis support if lesions are moving into young leaves, stems, or fruit.'),
    ('virus',
      $$["Take a baseline whole-plant photo and inspect nearby host plants for similar symptoms.", "Inspect for vector pests and nearby weeds that can host them.", "Handle healthy plants first and sanitize hands and tools after the suspect plant.", "Record whether new growth is more distorted or mottled than the Day 1 photo.", "Check nearby plants for new symptoms and keep vector scouting active.", "Discuss removal of severely affected plants with a local agriculture adviser.", "Complete the containment reassessment and record contained, unchanged, or spreading."]$$::jsonb,
      'There is no direct curative treatment for a confirmed virus.',
      'Seek local confirmation before removing plants or using any product.'),
    ('uncertain',
      $$["Photograph the whole plant and compare normal and affected shoots.", "Inspect leaf undersides and nearby weeds for possible vector pests.", "Check root-zone moisture, recent fertilizer changes, and possible injury without changing inputs yet.", "Inspect nearby plants for similar stunting or distortion.", "Repeat the whole-plant photo and record whether new growth is changing.", "Arrange local diagnosis support before applying pesticide, fertilizer, or herbicide changes.", "Complete a reassessment and record the evidence for the local adviser."]$$::jsonb,
      'Keep tools clean and avoid moving from suspect plants to healthy plants without sanitation.',
      'Do not treat this provisional label as a confirmed disease.'),
    ('moisture_disease',
      $$["Take a baseline photo of the whole affected area and check for stem or leaf symptoms.", "Avoid handling wet plants and remove only clearly infected material when practical.", "Bag removed material, clean tools, and remove old debris from the growing area.", "Check drainage, airflow, and irrigation so foliage and soil surface do not stay wet unnecessarily.", "Inspect nearby plants for new growth or symptoms after humid or wet weather.", "Review a product only after local confirmation and a current FPA label match.", "Complete a final photo reassessment and record improving, unchanged, or worsening."]$$::jsonb,
      'Keep foliage dry and prevent symptomatic debris from contacting healthy plants.',
      'Seek local diagnosis support if symptoms spread or stems begin to collapse.'),
    ('wilt',
      $$["Take a baseline whole-plant photo and check root-zone moisture and drainage.", "Inspect stems, roots, and nearby plants for one-sided wilt, browning, root rot, or injury.", "Avoid repeated soaking of the soil; correct drought or standing water only when observed.", "Clean tools and avoid moving soil from the affected area to healthy plants.", "Compare wilt timing and spread with the Day 1 photo, especially after heat or irrigation.", "Seek local diagnosis support before removing plants or using a product.", "Complete a final reassessment and record whether wilt is contained, unchanged, or spreading."]$$::jsonb,
      'Wilt has several possible causes, so confirm the cause before treatment.',
      'Escalate promptly when a plant collapses or nearby plants begin to wilt.'),
    ('rot',
      $$["Take a baseline whole-plant photo and inspect drainage and standing water.", "Remove severely rotted material promptly, bag it, and clean tools and hands.", "Avoid further leaf injury and keep irrigation at the soil level so foliage dries quickly.", "Inspect nearby plants for soft tissue, odor, or collapse and remove old debris.", "Check drainage again after rain or irrigation and correct standing water.", "Seek local diagnosis support before applying a product.", "Complete a final reassessment and record whether new rot is absent, unchanged, or spreading."]$$::jsonb,
      'Protect healthy plants by keeping decayed material out of the growing area.',
      'Escalate promptly if nearby plants start softening or collapsing.')
),
targets as (
  select
    d.id as disease_knowledge_base_id,
    p.*,
    f.daily_focus,
    f.daily_care,
    f.escalation_note
  from protocols p
  join public.disease_knowledge_base d
    on d.crop_type::text = p.crop_type
   and lower(trim(d.disease_name)) = lower(p.disease_name)
  join focus_groups f on f.care_group = p.care_group
  union all
  select
    inserted.id as disease_knowledge_base_id,
    p.*,
    f.daily_focus,
    f.daily_care,
    f.escalation_note
  from protocols p
  join insert_missing inserted
    on inserted.crop_type::text = p.crop_type
   and lower(trim(inserted.disease_name)) = lower(p.disease_name)
  join focus_groups f on f.care_group = p.care_group
),
deactivate_existing_template_rows as (
  update public.disease_treatment_day_steps s
  set is_active = false
  from targets t
  where s.disease_knowledge_base_id = t.disease_knowledge_base_id
    and s.is_active = true
  returning s.id
)
insert into public.disease_treatment_day_steps (
  id, disease_knowledge_base_id, day_number, day_title, tasks, notes, is_active
)
select
  gen_random_uuid(),
  t.disease_knowledge_base_id,
  day_number,
  case day_number
    when 1 then 'Baseline assessment'
    when 7 then 'Final reassessment'
    else 'Daily care and comparison'
  end,
  array[
    t.daily_focus ->> (day_number - 1),
    t.daily_care,
    'Record what you observed today in the app. Focus on new symptoms or pests rather than old damage.',
    'Escalation: ' || t.escalation_note
  ]::text[],
  'Source: ' || t.source_name || '. Product directions, when needed, must follow the exact current FPA-registered label.',
  true
from targets t
cross join lateral generate_series(1, t.estimated_recovery_days) as day_number
on conflict (disease_knowledge_base_id, day_number) do update
set
  day_title = excluded.day_title,
  tasks = excluded.tasks,
  notes = excluded.notes,
  is_active = true;

commit;

-- Verify that each active template has every day from 1 through its duration.
with active_days as (
  select
    d.crop_type::text as crop_type,
    d.disease_name,
    d.estimated_recovery_days,
    array_agg(s.day_number order by s.day_number)
      filter (where s.is_active = true) as active_day_numbers
  from public.disease_knowledge_base d
  left join public.disease_treatment_day_steps s
    on s.disease_knowledge_base_id = d.id
  where d.is_active = true
    and d.crop_type::text in ('eggplant', 'pechay')
  group by d.id
)
select
  crop_type,
  disease_name,
  estimated_recovery_days,
  case
    when active_day_numbers = array(select generate_series(1, estimated_recovery_days))
      then 'Complete daily protocol'
    else 'Needs review'
  end as protocol_status
from active_days
order by crop_type, disease_name;