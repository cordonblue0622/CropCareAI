# Treatment Protocol Evidence Register

## Standard

Every supported disease needs a contiguous, day-by-day protocol and a
disease-specific source in its parent `disease_knowledge_base` row. This register
records the sources used for diagnosis and nonchemical integrated management.

Pesticide legality and all product-specific directions in the Philippines require
the current FPA registration and exact product label. Do not use a foreign
extension page as a Philippine product prescription.

Official Philippine product registry:

- DA Fertilizer and Pesticide Authority (FPA), Registered Products:
  https://fpa.da.gov.ph/registered-products/

## Canonical Sources

| Crop and condition | Scientific management source | Use in CropCare AI |
| --- | --- | --- |
| Tomato bacterial spot | UC IPM, Bacterial Spot: https://ipm.ucanr.edu/agriculture/tomato/bacterial-spot | Symptoms; pathogen-free transplants; dry foliage; crop hygiene; resistance and label-gated product decision. |
| Tomato early blight | UC IPM, Early Blight: https://ipm.ucanr.edu/agriculture/tomato/early-blight | Older-leaf inspection; debris and volunteer-host control; rotation; leaf-wetness reduction; product decision. |
| Tomato late blight | UC IPM, Late Blight: https://ipm.ucanr.edu/agriculture/tomato/late-blight | Urgent monitoring; removal of volunteer hosts; avoid overhead irrigation; prompt local escalation; label-gated product decision. |
| Tomato leaf mold | Cornell Vegetables, Tomato Leaf Mold: https://www.vegetables.cornell.edu/crops/tomatoes/tomato-leaf-mold/ | Humidity and airflow management; diseased-plant removal; equipment sanitation; resistant varieties. |
| Tomato Septoria leaf spot | Cornell Vegetables, Managing Tomato Diseases Successfully: https://www.vegetables.cornell.edu/pest-management/disease-factsheets/managing-tomato-diseases-successfully/ | Dry foliage; sanitation; rotation; monitoring; fungicide-resistance and label principles. |
| Tomato spider mites | University of Minnesota Extension, Twospotted spider mites in home gardens: https://extension.umn.edu/yard-and-garden-insects/spider-mites | Scouting, drought-stress reduction, water-spray, and natural-enemy protection principles. Philippine product decisions still require an exact current FPA label. |
| Tomato target spot | Cornell Vegetables, Managing Tomato Diseases Successfully: https://www.vegetables.cornell.edu/pest-management/disease-factsheets/managing-tomato-diseases-successfully/ | General tomato sanitation, dry foliage, diagnosis, and label-gated treatment decisions. Add a target-spot-specific source before naming a product. |
| Tomato mosaic virus | UC IPM, Tobacco Mosaic: https://ipm.ucanr.edu/agriculture/tomato/tobacco-mosaic | Mechanical transmission, tobacco and debris sources, sanitation, treated seed, and resistance. |
| Tomato yellow leaf curl virus | UC IPM, Tomato Yellow Leaf Curl: https://ipm.ucanr.edu/agriculture/tomato/tomato-yellow-leaf-curl | Whitefly-vector management, resistant varieties, weed control, exclusion, and roguing. |
| Pepper bacterial spot | UC IPM, Peppers: https://ipm.ucanr.edu/agriculture/peppers/ | Pepper bacterial-spot management category; use with FPA label verification for any product action. |
| Squash powdery mildew | Cornell Vegetables, Cucurbit Powdery Mildew: https://www.vegetables.cornell.edu/crops/cucurbits/cucurbit-powdery-mildew/ | Scouting threshold, resistant varieties, coverage, resistance management, and label precedence. |
| Healthy tomato or pepper monitoring | UC IPM crop guidelines: https://ipm.ucanr.edu/agriculture/tomato/ and https://ipm.ucanr.edu/agriculture/peppers/ | Crop-stage monitoring, sanitation, irrigation, and pest scouting. |
| Eggplant monitoring, pests, leaf spots, small leaf, and white mold-like symptoms | UC IPM, Eggplant: https://ipm.ucanr.edu/agriculture/eggplant/ | Eggplant-specific pest and disease references; conservative scouting, sanitation, moisture management, and label-gated decisions. |
| Eggplant mosaic virus | UC IPM, Mosaic Diseases Caused by Potyviruses: https://ipm.ucanr.edu/agriculture/eggplant/mosaic-diseases-caused-by-potyviruses/ | Containment, vector and weed inspection, sanitation, and local confirmation rather than a claimed cure. |
| Eggplant wilt | UC IPM, Eggplant Verticillium Wilt: https://ipm.ucanr.edu/agriculture/eggplant/verticillium-wilt/ | Whole-plant assessment, drainage and root checks, sanitation, and cause confirmation before a treatment decision. |
| Pechay leaf spot | Cornell Vegetables, Alternaria Leaf Spot of Brassicas: https://www.vegetables.cornell.edu/pest-management/disease-factsheets/alternaria-leaf-spot/ | Leaf-wetness reduction, sanitation, clean seed or transplants, weed management, and label precedence. |
| Pechay healthy monitoring, soft rot, aphids, and downy mildew | UC IPM, Cole Crops: https://ipm.ucanr.edu/agriculture/cole-crops/ | Cole-crop pest and disease monitoring; drainage, sanitation, leaf-wetness reduction, and crop/target-specific label decisions. |

## Publication Rules

1. Store the applicable source title and URL in `disease_knowledge_base`.
2. Add every `day_number` from 1 through `estimated_recovery_days`; do not use
   weekly checkpoints to represent an otherwise daily care plan.
3. Cite FPA as the regulatory source for every product decision.
4. Do not store a product rate, mixture, PPE instruction, re-entry interval, or
   pre-harvest interval without copying it from the exact current FPA-registered
   product label and documenting its review date.
5. Mark a protocol inactive and revise it when its source, product registration,
   or label review becomes outdated.