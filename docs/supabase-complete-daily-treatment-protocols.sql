-- Complete daily treatment protocol templates.
--
-- This script affects only disease_knowledge_base and
-- disease_treatment_day_steps. It never modifies a farmer's treatments,
-- treatment_tasks, diagnoses, crops, images, or progress records.
--
-- It replaces active template rows only for conditions whose current protocol
-- is incomplete. It does not prescribe a pesticide product, rate, mixture,
-- PPE, re-entry interval, or pre-harvest interval. Any product decision must
-- use the exact current Philippine FPA-registered product label.

begin;

with protocols (
  protocol_key,
  crop_type,
  disease_name,
  duration_days,
  source_name,
  source_url,
  daily_care,
  escalation_note,
  daily_focus
) as (
  values
    (
      'tomato_early_blight_legacy',
      'tomato',
      'Early Blight',
      7,
      'UC IPM: Early Blight',
      'https://ipm.ucanr.edu/agriculture/tomato/early-blight',
      'Check soil moisture and water at the soil level only when needed; keep leaves dry and avoid splashing soil onto foliage.',
      'Seek local agriculture advice if new lesions keep appearing on upper leaves or the plant is losing leaves quickly.',
      $$[
        "Inspect older lower leaves for brown target-like spots and take a clear baseline photo.",
        "Remove only the most affected lower leaves; bag them and sanitize tools before touching another plant.",
        "Remove fallen leaves and weeds that can keep infected debris near the crop.",
        "Place clean mulch where practical, keep it away from direct stem contact, and confirm watering reaches the soil rather than foliage.",
        "Compare the affected leaf area with the Day 1 photo and check whether new spots are moving upward.",
        "Support or stake the plant and review a product only if it is currently FPA-registered for tomato and the diagnosed target; follow its exact label.",
        "Complete a final image reassessment and record improved, unchanged, or worsening based on new growth and new lesions; seek local advice for continued spread."
      ]$$::jsonb
    ),
    (
      'tomato_early_blight',
      'tomato',
      'tomato_early_blight',
      7,
      'UC IPM: Early Blight',
      'https://ipm.ucanr.edu/agriculture/tomato/early-blight',
      'Check soil moisture and water at the soil level only when needed; keep leaves dry and avoid splashing soil onto foliage.',
      'Seek local agriculture advice if new lesions keep appearing on upper leaves or the plant is losing leaves quickly.',
      $$[
        "Inspect older lower leaves for brown target-like spots and take a clear baseline photo.",
        "Remove only the most affected lower leaves; bag them and sanitize tools before touching another plant.",
        "Remove fallen leaves and weeds that can keep infected debris near the crop.",
        "Place clean mulch where practical and keep it away from direct stem contact.",
        "Compare the affected leaf area with the Day 1 photo and check whether new spots are moving upward.",
        "Support or stake the plant and open crowded foliage only when leaves are dry.",
        "Complete a final image reassessment, review a product only if it is currently FPA-registered for tomato and the diagnosed target, and record improved, unchanged, or worsening based on new growth and new lesions."
      ]$$::jsonb
    ),
    (
      'tomato_late_blight',
      'tomato',
      'tomato_late_blight',
      7,
      'UC IPM: Late Blight',
      'https://ipm.ucanr.edu/agriculture/tomato/late-blight',
      'Avoid overhead irrigation and handling wet plants. Work on healthy plants before the affected plant and sanitize tools after contact.',
      'Escalate promptly if water-soaked or rapidly enlarging lesions, white growth, stem infection, or fruit infection are increasing.',
      $$[
        "Inspect leaves, stems, and fruit for water-soaked spots, brown blotches, or pale growth on leaf undersides; take a baseline photo.",
        "Separate the affected plant from routine handling and remove only clearly diseased leaves using clean tools.",
        "Bag and remove infected debris; do not leave diseased leaves, volunteer tomatoes, potatoes, or nightshade nearby.",
        "Check the forecast and record cool, wet, or prolonged humid conditions that can accelerate spread.",
        "Inspect upper leaves, stems, and fruit for new lesions; compare them with the Day 1 photo.",
        "Check nearby tomato and potato plants before working in the affected area and record any similar symptoms.",
        "Complete the final reassessment: arrange local agriculture-office review if symptoms are spreading, consider a product only if it is FPA-registered and label-matched after confirmation, and record contained, improving, unchanged, or worsening."
      ]$$::jsonb
    ),
    (
      'tomato_yellow_leaf_curl_virus',
      'tomato',
      'tomato_yellow_leaf_curl_virus',
      21,
      'UC IPM: Tomato Yellow Leaf Curl',
      'https://ipm.ucanr.edu/agriculture/tomato/tomato-yellow-leaf-curl',
      'This virus has no curative treatment. Work with healthy plants first, manage weeds and whitefly pressure, and avoid moving suspect transplants.',
      'Escalate when whiteflies or symptoms are increasing across nearby plants, or when a severely stunted plant becomes a continuing infection source.',
      $$[
        "Inspect the whole plant for upward leaf curl, yellow margins, stunting, and poor flower or fruit set; take a baseline photo.",
        "Check leaf undersides for whiteflies and record whether adults or immature stages are present.",
        "Inspect nearby tomatoes and weeds for similar symptoms or whitefly activity before handling the affected plant.",
        "Remove weeds around the crop that can support whiteflies or virus hosts, then wash hands and clean tools.",
        "Check whether fine insect exclusion material or other physical barriers are intact without trapping heat around the plant.",
        "Assess whether the plant is severely stunted or unproductive and record whether careful removal should be discussed with a local expert.",
        "Take a Day 7 photo and compare new growth, leaf curl, and whitefly activity with Day 1.",
        "Inspect healthy plants first and the affected plant last; clean tools and hands after the affected plant.",
        "Check flowers and young fruit for poor set or abnormal growth and record the observations.",
        "Inspect for new whitefly hotspots on the undersides of young leaves and nearby host plants.",
        "Review crop spacing and weed control so that whitefly scouting is possible throughout the canopy.",
        "Record whether symptoms are limited to the original plant or appearing on nearby tomatoes.",
        "Remove only confirmed severely affected plants when advised locally; bag material and do not leave it among healthy crops.",
        "Take a Day 14 comparison image and record spread, plant vigor, and whitefly pressure.",
        "Inspect new seedlings or transplants before placing them near the affected area.",
        "Check barriers, weeds, and nearby host plants again; correct any gap that lets vectors move easily into the crop.",
        "Record whether healthy neighboring plants remain symptom-free after the containment steps.",
        "Inspect the affected plant for continued production and reassess whether it is an ongoing source of risk.",
        "Prepare a final comparison photo and list remaining vector or spread concerns.",
        "Check all nearby tomato plants for early curl or yellowing and record any crop that needs a separate diagnosis.",
        "Complete the final containment reassessment: upload a photo and record contained, removed, unchanged, or spreading."
      ]$$::jsonb
    ),
    (
      'pepper_bacterial_spot_legacy',
      'pepper',
      'Bacterial Spot',
      7,
      'UC IPM: Pepper Guidelines',
      'https://ipm.ucanr.edu/agriculture/peppers/',
      'Avoid overhead irrigation, water at the soil level only when needed, and clean tools after handling symptomatic foliage.',
      'Seek local agriculture advice if new leaf spots, defoliation, or fruit lesions continue to increase.',
      $$[
        "Inspect leaves, stems, and fruit for small dark spots, yellow halos, and defoliation; take a clear baseline photo.",
        "Remove only clearly affected leaves when there are few, bag them, and sanitize tools and hands after handling them.",
        "Remove fallen leaves and nearby weeds that can hold moisture or harbor disease, then keep crop debris out of the growing area.",
        "Check that irrigation reaches the soil without wetting foliage or splashing soil onto lower leaves.",
        "Inspect new growth, flowers, fruit, and nearby pepper plants for new spots; compare findings with the Day 1 photo.",
        "Review a product only if it is currently FPA-registered for pepper and bacterial spot; follow its exact label and do not mix products without label support.",
        "Complete a final image reassessment and record improving, unchanged, or worsening based on new spots and new leaf loss; seek local review for continued spread."
      ]$$::jsonb
    ),
    (
      'pepper_healthy',
      'pepper',
      'pepper_healthy',
      30,
      'UC IPM: Pepper Guidelines',
      'https://ipm.ucanr.edu/agriculture/peppers/',
      'Check soil moisture before watering, water at the base only when needed, and avoid severe wet-dry swings that stress pepper plants.',
      'Create a separate diagnosis if new leaf spots, curling, wilt, whiteflies, aphids, thrips, or fruit damage appears.',
      $$[
        "Take a baseline photo and inspect leaves, stems, flowers, and fruit for early damage or pest signs.",
        "Check soil moisture at root depth and record whether the plant needed water rather than watering by schedule alone.",
        "Inspect leaf undersides for aphids, thrips, whiteflies, mites, or sticky residue and record any finding.",
        "Remove weeds near the pepper plant and check that leaves and fruit are not resting on soil.",
        "Check whether the plant needs support so fruit-bearing branches do not break or crowd the canopy.",
        "Inspect new growth for distortion, yellowing, or spots and compare it with the baseline photo.",
        "Take a weekly health photo and record whether the crop remains symptom-free.",
        "Check drainage after watering or rain and correct standing water without damaging roots.",
        "Inspect flowers and developing fruit for pest injury, rot, or poor set.",
        "Check spacing and remove only foliage that blocks airflow or is clearly damaged.",
        "Inspect lower leaves and soil surface for disease debris, pests, or splash damage.",
        "Recheck leaf undersides for vector pests and record whether populations are absent, low, or increasing.",
        "Take the second weekly comparison photo and record leaf color, new growth, flower condition, and pest signs.",
        "Check soil moisture and plant support again; look for leaning or branches under fruit weight.",
        "Inspect new leaves and the oldest lower leaves separately so early disease is not missed.",
        "Check that irrigation reaches the root zone without wetting foliage or splashing soil onto leaves.",
        "Inspect nearby pepper plants before the healthy crop and record any disease or pest pressure in the area.",
        "Check leaf undersides for insect eggs, mites, aphids, thrips, whiteflies, or sticky residue and record any change.",
        "Remove only clearly damaged leaves or weeds and keep tools clean before moving between plants.",
        "Take the third weekly comparison photo and record whether the plant remains healthy or needs a new diagnosis.",
        "Check ripening fruit and developing flowers for injury, rot, or signs that support or airflow needs adjustment.",
        "Inspect soil surface, mulch, and drainage after weather changes; remove debris that can harbor pests or disease.",
        "Inspect new growth for curling, mottling, or virus-like symptoms and separate any suspect plant for diagnosis.",
        "Check leaf undersides and nearby weeds for whiteflies, aphids, thrips, or mites before they build up.",
        "Review spacing and canopy density; improve airflow only with light, dry-weather pruning when truly needed.",
        "Inspect fruit, stems, and lower leaves for new disease signs and record any symptom immediately.",
        "Check soil moisture and plant support after harvest or fruit removal, avoiding severe wet-dry stress.",
        "Prepare a final monthly comparison photo and list any changes since the Day 1 baseline.",
        "Review the crop area for debris, weeds, drainage issues, and pest pressure before the final monthly assessment.",
        "Complete the monthly healthy-crop review and continue routine monitoring or create a new diagnosis for any symptom."
      ]$$::jsonb
    ),
    (
      'tomato_healthy',
      'tomato',
      'tomato_healthy',
      30,
      'UC IPM: Tomato Guidelines',
      'https://ipm.ucanr.edu/agriculture/tomato/',
      'Check soil moisture before watering, water at the soil level only when needed, keep foliage dry, and avoid leaving crop debris around the plant.',
      'Create a separate diagnosis promptly if new spots, wilt, curling, mottling, webbing, or pest activity appears.',
      $$[
        "Take a baseline photo and inspect leaves, stems, flowers, and fruit for any early symptom or pest sign.",
        "Check soil moisture at root depth and record whether watering was needed; avoid a fixed watering schedule.",
        "Inspect lower leaves and the soil surface for splash damage, weeds, fallen debris, or early spots.",
        "Inspect both sides of leaves for whiteflies, mites, aphids, or webbing and record any finding.",
        "Check staking or trellising and keep leaves, stems, and fruit from resting on soil.",
        "Inspect new growth for curling, yellowing, distortion, or insect feeding before handling the canopy.",
        "Take the first weekly comparison photo and record whether the plant remains symptom-free.",
        "Check drainage after watering or rain and correct standing water without disturbing the root zone.",
        "Inspect flowers and small fruit for pest injury, rot, or poor set and record any change.",
        "Remove weeds that crowd the plant and check whether enough air can move through the canopy.",
        "Inspect lower leaf undersides for mites and whiteflies, especially during hot or dry weather.",
        "Check mulch or soil cover and adjust it to reduce soil splash while keeping it away from the stem.",
        "Inspect the crop area for old tomato debris, volunteer plants, or nightshade weeds and remove them when practical.",
        "Take the second weekly comparison photo and record leaf color, new growth, flower condition, and pest signs.",
        "Check soil moisture and plant support again; look for cracking, leaning, or branches under fruit weight.",
        "Inspect new leaves and the oldest lower leaves separately so early disease is not missed.",
        "Check that irrigation reaches the root zone without wetting foliage or splashing soil onto leaves.",
        "Inspect nearby tomato plants before the healthy crop and record any disease or pest pressure in the area.",
        "Check leaf undersides for insect eggs, webbing, sticky residue, or honeydew and record any change.",
        "Remove only clearly damaged leaves or weeds and keep tools clean before moving between plants.",
        "Take the third weekly comparison photo and record whether the plant remains healthy or needs a new diagnosis.",
        "Check ripening fruit and developing flowers for injury, rot, or signs that support or airflow needs adjustment.",
        "Inspect soil surface, mulch, and drainage after weather changes; remove debris that can harbor pests or disease.",
        "Inspect new growth for virus-like curling or mottling and separate any suspect plant for diagnosis.",
        "Check leaf undersides and nearby weeds for whiteflies, aphids, thrips, or mites before they build up.",
        "Review spacing and canopy density; improve airflow only with light, dry-weather pruning when truly needed.",
        "Inspect fruit, stems, and lower leaves for new disease signs and record any symptom immediately.",
        "Check soil moisture and plant support after harvest or fruit removal, avoiding severe wet-dry stress.",
        "Prepare a final monthly comparison photo and list any changes since the Day 1 baseline.",
        "Complete the monthly healthy-crop review and continue routine monitoring or create a new diagnosis for any symptom."
      ]$$::jsonb
    ),
    (
      'squash_powdery_mildew',
      'squash',
      'squash_powdery_mildew',
      14,
      'Cornell Vegetables: Cucurbit Powdery Mildew',
      'https://www.vegetables.cornell.edu/crops/cucurbits/cucurbit-powdery-mildew/',
      'Inspect both leaf surfaces, maintain open airflow, and avoid excessive nitrogen that creates dense, susceptible foliage.',
      'Escalate when white growth is increasing across new leaves, plants are losing leaf area quickly, or fruit is exposed to sunburn risk.',
      $$[
        "Inspect upper and lower leaf surfaces for white powdery growth and take a clear baseline photo.",
        "Check older and shaded leaves first, then mark which leaves have active white growth versus old yellowing.",
        "Open crowded vines only enough to improve airflow; avoid heavy pruning that exposes fruit suddenly.",
        "Remove only heavily covered leaves when practical, bag the material, and clean tools after handling it.",
        "Inspect both leaf surfaces again and compare the amount of white growth with Day 1.",
        "Check fruit cover and leaf health so that disease-related defoliation does not expose developing squash to sunburn.",
        "Use a product only when it is currently FPA-registered for squash and powdery mildew; follow its exact label and resistance-management directions.",
        "Inspect new and lower leaves for fresh colonies, and record whether the disease is stable, slowing, or spreading.",
        "Check canopy density, weed pressure, and irrigation practice; correct factors that keep foliage crowded or stressed.",
        "Inspect both leaf surfaces after any wet or humid period and record whether fresh white colonies are appearing.",
        "Check fruit cover, plant vigor, and new leaves before removing any additional heavily covered leaf.",
        "Take a final comparison photo and record the amount of new powdery growth since Day 1.",
        "Record whether new leaves remain free of powdery growth and whether the canopy still protects developing fruit.",
        "Complete the final reassessment and record improved, unchanged, or worsening; seek local support for continued spread."
      ]$$::jsonb
    ),
    (
      'tomato_spider_mites',
      'tomato',
      'tomato_spider_mites',
      7,
      'University of Minnesota Extension: Twospotted spider mites in home gardens',
      'https://extension.umn.edu/yard-and-garden-insects/spider-mites',
      'Inspect leaf undersides for mites and webbing, keep plants from drought stress, reduce dust, and avoid unnecessary broad-spectrum insecticides.',
      'Escalate when webbing, bronzing, or mite activity increases after several days of management or spreads to nearby crops.',
      $$[
        "Inspect lower leaf undersides for live mites, fine webbing, yellow stippling, and bronzing; take a baseline photo.",
        "Remove only heavily infested leaves if there are few; bag them and inspect nearby plants before handling healthy foliage.",
        "Check root-zone moisture and correct drought stress without waterlogging the plant.",
        "Reduce dust and remove weeds that can host mites; inspect the underside of nearby tomato, pepper, eggplant, and squash leaves.",
        "During a cool part of the day, use a gentle water spray on leaf undersides only when practical; check that leaves dry with airflow.",
        "Inspect for webbing and new yellow speckles, then compare activity with the Day 1 photo.",
        "Complete a final photo reassessment, protect natural predators by avoiding unnecessary broad-spectrum insecticides, and review a product only if it is currently FPA-registered for tomato and mites; record improving, unchanged, or worsening."
      ]$$::jsonb
    ),
    (
      'tomato_target_spot',
      'tomato',
      'tomato_target_spot',
      14,
      'Cornell Vegetables: Managing Tomato Diseases Successfully',
      'https://www.vegetables.cornell.edu/pest-management/disease-factsheets/managing-tomato-diseases-successfully/',
      'Keep foliage dry, water at the soil level only when needed, remove infected debris, and avoid handling plants while leaves are wet.',
      'Seek a local diagnosis review if target-like lesions are rapidly moving into new leaves, stems, or fruit.',
      $$[
        "Inspect older and lower leaves for expanding brown spots with target-like rings; take a baseline photo.",
        "Remove only badly affected lower leaves, bag them, and sanitize tools and hands after handling them.",
        "Support the plant and open crowded foliage only when dry so leaves can dry quickly after rain or irrigation.",
        "Apply clean mulch where practical and remove fallen infected debris from the soil surface.",
        "Take a Day 5 photo and compare the number and size of new spots with Day 1.",
        "Remove newly infected leaves only when there are few; avoid heavy pruning and clean tools afterward.",
        "Review a product only if it is currently FPA-registered for tomato and the confirmed target; follow its exact label.",
        "Inspect upper leaves, stems, and fruit for spread beyond the original affected area.",
        "Check nearby tomatoes for similar lesions before handling the affected plant, then sanitize tools.",
        "Take a second progress photo and record whether new lesions are fewer, unchanged, or increasing.",
        "Check spacing, weeds, mulch, and base-watering practice to keep the canopy and soil surface clean.",
        "Repeat debris removal and inspect lower leaves for fresh spots after any wet weather.",
        "Prepare a final comparison photo and record remaining active symptoms.",
        "Complete the final reassessment and record improved, unchanged, or worsening; seek local review for continuing spread."
      ]$$::jsonb
    )
),
targets as (
  select
    d.id as disease_knowledge_base_id,
    p.*
  from protocols p
  join public.disease_knowledge_base d
    on d.crop_type::text = p.crop_type
   and lower(trim(d.disease_name)) = lower(p.disease_name)
   and d.is_active = true
),
deactivate_existing_template_rows as (
  update public.disease_treatment_day_steps s
  set is_active = false
  from targets t
  where s.disease_knowledge_base_id = t.disease_knowledge_base_id
    and s.is_active = true
  returning s.id
),
update_parent_records as (
  update public.disease_knowledge_base d
  set
    estimated_recovery_days = t.duration_days,
    source_name = t.source_name,
    source_url = t.source_url,
    updated_at = now()
  from targets t
  where d.id = t.disease_knowledge_base_id
  returning d.id
)
insert into public.disease_treatment_day_steps (
  id,
  disease_knowledge_base_id,
  day_number,
  day_title,
  tasks,
  notes,
  is_active
)
select
  gen_random_uuid(),
  t.disease_knowledge_base_id,
  day_number,
  case
    when t.protocol_key = 'tomato_early_blight_legacy' then
      case day_number
        when 1 then 'Early blight baseline assessment'
        when 7 then 'Final early blight reassessment'
        else 'Early blight daily control'
      end
    when t.protocol_key = 'tomato_early_blight' then
      case day_number
        when 1 then 'Baseline assessment'
        when 7 then 'Final reassessment and label decision'
        else 'Early blight daily control'
      end
    when t.protocol_key = 'tomato_late_blight' then
      case day_number
        when 1 then 'Urgent baseline assessment'
        when 7 then 'Final late blight reassessment'
        else 'Late blight containment care'
      end
    when t.protocol_key = 'tomato_yellow_leaf_curl_virus' then
      case day_number
        when 1 then 'Virus and vector baseline'
        when 7 then 'First containment reassessment'
        when 14 then 'Second containment reassessment'
        when 21 then 'Final virus management review'
        else 'Whitefly and virus containment'
      end
    when t.protocol_key = 'pepper_bacterial_spot_legacy' then
      case day_number
        when 1 then 'Bacterial spot baseline'
        when 7 then 'Final bacterial spot reassessment'
        else 'Bacterial spot daily control'
      end
    when t.protocol_key = 'pepper_healthy' then
      case day_number
        when 1 then 'Healthy crop baseline'
        when 7 then 'First weekly healthy-crop review'
        when 14 then 'Second weekly healthy-crop review'
        when 21 then 'Third weekly healthy-crop review'
        when 30 then 'Monthly healthy-crop review'
        else 'Healthy pepper daily care'
      end
    when t.protocol_key = 'tomato_healthy' then
      case day_number
        when 1 then 'Healthy crop baseline'
        when 7 then 'First weekly healthy-crop review'
        when 14 then 'Second weekly healthy-crop review'
        when 21 then 'Third weekly healthy-crop review'
        when 30 then 'Monthly healthy-crop review'
        else 'Healthy tomato daily care'
      end
    when t.protocol_key = 'squash_powdery_mildew' then
      case day_number
        when 1 then 'Powdery mildew baseline'
        when 7 then 'Midpoint reassessment and label decision'
        when 14 then 'Final powdery mildew reassessment'
        else 'Powdery mildew daily control'
      end
    when t.protocol_key = 'tomato_spider_mites' then
      case day_number
        when 1 then 'Mite baseline inspection'
        when 7 then 'Final mite reassessment'
        else 'Spider mite daily control'
      end
    when t.protocol_key = 'tomato_target_spot' then
      case day_number
        when 1 then 'Target spot baseline'
        when 7 then 'Midpoint reassessment and label decision'
        when 14 then 'Final target spot reassessment'
        else 'Target spot daily control'
      end
  end,
  array[
    t.daily_focus ->> (day_number - 1),
    t.daily_care,
    'Record what you observed today in the app. Do not treat old damage as failure; focus on whether new symptoms or pests are appearing.',
    'Escalation: ' || t.escalation_note
  ]::text[],
  'Source: ' || t.source_name || '. Product directions, when needed, must follow the exact current FPA-registered label.',
  true
from targets t
cross join lateral generate_series(1, t.duration_days) as day_number
on conflict (disease_knowledge_base_id, day_number) do update
set
  day_title = excluded.day_title,
  tasks = excluded.tasks,
  notes = excluded.notes,
  is_active = true;

commit;

-- Verify the result. Every seeded protocol should report Complete daily protocol.
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
where disease_name in (
  'Early Blight',
  'tomato_early_blight',
  'tomato_late_blight',
  'tomato_yellow_leaf_curl_virus',
  'Bacterial Spot',
  'tomato_healthy',
  'pepper_healthy',
  'squash_powdery_mildew',
  'tomato_spider_mites',
  'tomato_target_spot'
)
order by crop_type, disease_name;