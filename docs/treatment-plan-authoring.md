# Treatment Plan Authoring

CropCare AI uses `disease_treatment_day_steps` as the authoritative treatment
# Treatment Plan Authoring

plan for a crop. A complete protocol has one detailed row for every calendar day
in its treatment window. Each row becomes one normal task, so it works offline,
appears in the calendar, and can be completed with a photo check-in.

## Required Dataset Fields

The parent disease record must have:

- `treatment_steps`: a JSON list in JSON imports, or a list-like value accepted
  by the dataset importer.
- `estimated_recovery_days`: the number of days in the treatment window.
- `source_name` and `source_url`: a disease-specific, reputable source for the
  management actions.

Each `disease_treatment_day_steps` record must have:

- `disease_knowledge_base_id`: the parent disease record.
- `day_number`: every integer from `1` through `estimated_recovery_days`, with
  no gaps.
- `day_title`: a concise daily goal.
- `tasks`: a JSON list of specific, practical actions.
- `notes`: a short explanation, warning, or reassessment criterion.

Use a realistic recovery window for the disease. CropCare AI limits a single
generated plan to 42 days to avoid creating an unmanageable task list.

## Write Daily Actions

Use a complete daily sequence. A farmer should be able to open any day and know
what to inspect, do, avoid, record, and when to escalate without inferring a
generic action from a previous day.

| Intent | Recommended dataset wording | Result in the daily plan |
| --- | --- | --- |
| One-time sanitation | `Remove and destroy heavily infected leaves on Day 1.` |
| Daily observation | `Inspect leaves daily for new spots, pests, wilt, or spread.` |
| Moisture management | `Check soil moisture daily; water at the base only when needed.` |
| Continuous care | `Avoid overhead irrigation and keep foliage dry.` |
| Repeated product use | `Apply the labeled fungicide every 7 days.` |
| Label range | `Apply copper bactericide every 5 to 7 days.` |

Avoid vague records such as `Treat the plant` or `Monitor closely`. They cannot
produce a reliable care schedule. Prefer concrete observations and actions.

## Product Safety And Sources

An evidence source supports disease identification and nonchemical integrated
management. It does not authorize a pesticide use in the Philippines. Before a
protocol names a pesticide category, product, rate, interval, protective
equipment, re-entry period, or harvest interval, verify the exact product label
and current registration in the Philippine DA Fertilizer and Pesticide Authority
(FPA) registry: https://fpa.da.gov.ph/registered-products/

Never derive Philippine directions from a foreign product recommendation. Until
an exact FPA label is reviewed, write a decision task such as: `Use a product
only when it is currently FPA-registered for this crop and target; follow its
label for timing, rate, PPE, re-entry, and harvest interval.`

Record the scientific management source in the parent disease row. See
`docs/treatment-protocol-evidence.md` for the approved source register.

## Example Day Record

```json
{
  "day_number": 7,
  "day_title": "Midpoint reassessment and product decision",
  "tasks": [
    "Take a photo from the same angle as Day 1 and compare the number of new lesions.",
    "Inspect nearby plants before working on the affected plant.",
    "Use a product only when it is currently FPA-registered for this crop and target; follow its label for timing, rate, PPE, re-entry, and harvest interval."
  ],
  "notes": "Existing damage may remain visible. Improvement means fewer new symptoms or pests."
}
```

This is one detailed, checkable Day 7 task. The treatment protocol must also
contain reviewed rows for every other day in its treatment window.