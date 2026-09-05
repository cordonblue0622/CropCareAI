from typing import Any

from app.core.config import Settings
from app.schemas.chat import ChatRequest
from app.services.supabase_service import SupabaseService


_CROP_ALIASES: dict[str, tuple[str, ...]] = {
    "tomato": ("tomato", "kamatis"),
    "pepper": ("pepper", "bell pepper", "capsicum"),
    "squash": ("squash", "kalabasa"),
    "eggplant": ("eggplant", "talong"),
    "pechay": ("pechay", "bok choy", "bokchoy"),
}

# Inline fallback knowledge for every label the trained model recognises.
# Used when Supabase is unavailable or not yet populated.
# Source: FAO crop-protection guidelines and PCAARRD Philippines recommendations.
_INLINE_KNOWLEDGE: dict[str, dict[str, str]] = {
    "corn_cercospora_leaf_spot_gray_leaf_spot": {
        "title": "Corn Cercospora Leaf Spot / Gray Leaf Spot",
        "summary": (
            "Gray rectangular lesions (2–5 cm) on lower leaves that expand upward. "
            "Caused by Cercospora zeae-maydis fungus, favoured by high humidity and poor air circulation. "
            "Treatment: Apply mancozeb or propiconazole fungicide early. Remove severely infected leaves. "
            "Rotate crops and choose resistant varieties. Prevention: 2–3 year rotation with non-host crops."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "corn_common_rust": {
        "title": "Corn Common Rust",
        "summary": (
            "Small brick-red to brown powdery pustules on both leaf surfaces. "
            "Caused by Puccinia sorghi, spreads via windborne spores. "
            "Treatment: Apply propiconazole or tebuconazole at early pustule stage. "
            "Plant resistant hybrids. Most damage occurs before tasselling – scout weekly. "
            "Prevention: Avoid late planting when weather favours rust."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "corn_northern_leaf_blight": {
        "title": "Corn Northern Leaf Blight",
        "summary": (
            "Long (5–15 cm) cigar-shaped grey-green lesions on leaves. "
            "Caused by Exserohilum turcicum fungus, thrives in cool wet weather. "
            "Treatment: Mancozeb or azoxystrobin at first lesion appearance. Destroy crop debris. "
            "Prevention: Plant resistant varieties; crop rotation with sorghum or soybeans. "
            "Severe infections can reduce yield 30–50% if upper leaves are affected."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "corn_healthy": {
        "title": "Corn – Healthy",
        "summary": (
            "The corn plant appears healthy. Maintain soil fertility with balanced NPK fertiliser. "
            "Scout weekly for early pest/disease signs. Ensure adequate irrigation during silking. "
            "Preventive fungicide application is not needed unless disease pressure is observed in surrounding fields."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "eggplant_healthy": {
        "title": "Eggplant – Healthy",
        "summary": (
            "The eggplant appears healthy. Maintain consistent soil moisture; avoid waterlogging. "
            "Apply balanced fertiliser (14-14-14 NPK) every 3 weeks during fruiting. "
            "Monitor for sucking insects (mites, aphids, thrips) which can spread viruses quickly."
        ),
        "treatment_steps": [
            "Day 1: Keep the soil evenly moist without waterlogging the roots.",
            "Day 2: Inspect leaf undersides for mites, aphids, and thrips.",
            "Day 3: Apply balanced fertiliser only on the scheduled feeding day during fruiting.",
            "Day 4: Remove damaged leaves and keep the bed clean to reduce pest pressure.",
        ],
        "source": "FAO/PCAARRD inline knowledge",
    },
    "eggplant_insect_pest": {
        "title": "Eggplant Insect Pest Damage",
        "summary": (
            "Visible feeding damage, holes, or stippling on leaves indicates insect infestation "
            "(likely eggplant fruit and shoot borer, mites, or aphids). "
            "Immediate action: Inspect undersides of leaves; identify the pest first. "
            "Treatment: Spray spinosad or neem oil (organic) for borers/aphids. "
            "For mites: miticide such as abamectin. Remove and destroy infested shoots. "
            "Prevention: Use yellow sticky traps; intercrop with marigold."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "eggplant_leaf_spot": {
        "title": "Eggplant Leaf Spot",
        "summary": (
            "Brown or black circular spots with yellow halos on leaves, caused by Cercospora or Alternaria fungi. "
            "Treatment: Remove affected leaves. Apply copper-based fungicide (copper oxychloride) every 7–10 days. "
            "Improve air circulation by pruning crowded branches. "
            "Prevention: Avoid overhead irrigation; use drip irrigation or water at the base only."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "eggplant_mosaic_virus": {
        "title": "Eggplant Mosaic Virus",
        "summary": (
            "Mosaic yellow-green mottling on leaves, leaf curl, and stunted growth. "
            "Caused by Tobacco Mosaic Virus or Cucumber Mosaic Virus; spread by aphids and contact. "
            "There is NO chemical cure for viruses. Immediate action: Remove and destroy infected plants to prevent spread. "
            "Control aphid vectors with insecticidal soap or neem oil. "
            "Prevention: Use certified virus-free seedlings; disinfect tools between plants."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "eggplant_small_leaf": {
        "title": "Eggplant Small Leaf (Phyllody / Big Bud)",
        "summary": (
            "Abnormally small, stunted leaves and/or flowers turning leaf-like. "
            "Caused by phytoplasma, transmitted by leafhoppers. "
            "No cure. Remove and destroy all infected plants immediately to prevent further leafhopper spread. "
            "Control leafhoppers with imidacloprid or spinosad. "
            "Prevention: Use reflective mulch to repel leafhoppers; avoid planting near infected fields."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "eggplant_white_mold": {
        "title": "Eggplant White Mold (Sclerotinia)",
        "summary": (
            "White cottony growth on stems/leaves near the soil; wilting of entire branches. "
            "Caused by Sclerotinia sclerotiorum; thrives in cool, humid conditions. "
            "Treatment: Remove and destroy infected plant parts. Apply iprodione or thiophanate-methyl fungicide. "
            "Improve drainage; reduce plant density for better airflow. "
            "Prevention: Deep ploughing to bury sclerotia; 3-year rotation with cereals."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "eggplant_wilt": {
        "title": "Eggplant Wilt (Fusarium / Bacterial)",
        "summary": (
            "Sudden wilting of plants despite adequate water. Caused by Fusarium oxysporum (fungal) "
            "or Ralstonia solanacearum (bacterial). "
            "Bacterial wilt confirmation: cut stem – milky bacterial ooze in water confirms R. solanacearum. "
            "No effective cure. Remove and destroy affected plants; do NOT compost. "
            "Disinfect tools with 70% alcohol between plants. "
            "Prevention: Resistant varieties; raise bed pH to 6.5–7 with lime; avoid wounding roots."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "pepper_bacterial_spot": {
        "title": "Bell Pepper Bacterial Spot",
        "summary": (
            "Dark water-soaked spots on leaves and fruit that turn brown/black; defoliation. "
            "Caused by Xanthomonas campestris; spread by rain splash and handling. "
            "Treatment: Apply copper hydroxide or copper oxychloride every 5–7 days. Avoid overhead watering. "
            "Remove severely infected leaves and fruit. "
            "Prevention: Use certified disease-free seed; avoid working in field when plants are wet."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "pepper_healthy": {
        "title": "Bell Pepper – Healthy",
        "summary": (
            "The pepper plant appears healthy. Maintain soil pH 6.0–6.8. "
            "Apply calcium and magnesium foliar sprays to prevent blossom-end rot. "
            "Scout regularly for thrips and aphids which vector pepper viruses."
        ),
        "treatment_steps": [
            "Day 1: Water at the base and keep the soil evenly moist.",
            "Day 2: Check leaves and young shoots for thrips, aphids, and fresh spots.",
            "Day 3: Check flowers and fruits for blossom-end rot and apply calcium-magnesium feed only if needed.",
            "Day 4: Remove weeds and keep the plant area open for airflow.",
        ],
        "source": "FAO/PCAARRD inline knowledge",
    },
    "squash_powdery_mildew": {
        "title": "Squash Powdery Mildew",
        "summary": (
            "White powdery coating on leaf surfaces, stems, and petioles. "
            "Caused by Podosphaera xanthii; spreads fast in warm, dry days with cool nights. "
            "Treatment: Apply potassium bicarbonate (organic) or sulfur-based fungicide at first sign. "
            "Neem oil spray every 7 days is effective. Remove heavily infected leaves. "
            "Prevention: Plant resistant varieties; avoid excessive nitrogen fertiliser which encourages lush foliage."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_bacterial_spot": {
        "title": "Tomato Bacterial Spot",
        "summary": (
            "Small dark water-soaked lesions on leaves, stems, and fruit; scabby fruit surface. "
            "Caused by Xanthomonas spp.; spread by rain and irrigation splash. "
            "Treatment: Copper-based bactericide (copper hydroxide) every 5–7 days. Avoid overhead irrigation. "
            "Prevention: Certified disease-free seed; crop rotation; remove plant debris after harvest."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_early_blight": {
        "title": "Tomato Early Blight",
        "summary": (
            "Brown spots with concentric rings (target-board pattern) on lower older leaves, causing yellowing. "
            "Caused by Alternaria solani fungus. "
            "Treatment: Apply chlorothalonil or mancozeb fungicide every 7 days. Remove infected lower leaves. "
            "Prevention: Mulch around base; avoid overhead watering; stake plants for airflow."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_late_blight": {
        "title": "Tomato Late Blight",
        "summary": (
            "Dark water-soaked lesions on leaves with white mold on undersides; entire plant can collapse within days. "
            "Caused by Phytophthora infestans; the same pathogen as the Irish Potato Famine. Extremely destructive. "
            "Immediate action: Apply metalaxyl+mancozeb or cymoxanil fungicide at first sign. "
            "Remove and destroy ALL infected plant parts. Do NOT compost. "
            "Prevention: Avoid wetting leaves; plant resistant varieties; scout daily during cool wet weather."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_leaf_mold": {
        "title": "Tomato Leaf Mold",
        "summary": (
            "Pale greenish-yellow patches on upper leaf surface; velvety olive-green mold on undersides. "
            "Caused by Passalora fulva; favoured by high humidity (>85%) and poor ventilation. "
            "Treatment: Apply copper fungicide or chlorothalonil. Reduce humidity in greenhouse; prune for airflow. "
            "Prevention: Use resistant varieties; ensure 50–70 cm plant spacing."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_septoria_leaf_spot": {
        "title": "Tomato Septoria Leaf Spot",
        "summary": (
            "Numerous small circular spots with dark borders and grey/tan centres on lower leaves; severe defoliation. "
            "Caused by Septoria lycopersici fungus. "
            "Treatment: Remove infected leaves immediately. Apply chlorothalonil or mancozeb. "
            "Prevention: Crop rotation (2-3 years); remove volunteer tomato plants; avoid overhead irrigation."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_spider_mites": {
        "title": "Tomato Spider Mites (Two-spotted)",
        "summary": (
            "Tiny yellow/white stippling on leaves; fine webbing on undersides; leaves turn bronze and drop. "
            "Caused by Tetranychus urticae; explodes in hot, dry conditions. "
            "Treatment: Spray water on undersides to knock off mites. Apply abamectin or spiromesifen miticide. "
            "Neem oil or insecticidal soap for mild infestations. "
            "Prevention: Keep plants well-watered; avoid dusty conditions; introduce predatory mites (Phytoseiulus persimilis)."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_target_spot": {
        "title": "Tomato Target Spot",
        "summary": (
            "Circular brown lesions with concentric rings and yellow halos on leaves, stems, and fruit. "
            "Caused by Corynespora cassiicola fungus; worse in warm humid conditions. "
            "Treatment: Apply azoxystrobin or difenoconazole fungicide. Remove affected leaves. "
            "Prevention: 3-year rotation; destroy crop residue; prune for good airflow."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_yellow_leaf_curl_virus": {
        "title": "Tomato Yellow Leaf Curl Virus (TYLCV)",
        "summary": (
            "Upward leaf curling, yellowing of leaf edges, stunted growth, reduced fruit set. "
            "Caused by TYLCV transmitted exclusively by silverleaf whitefly (Bemisia tabaci). "
            "No cure. Immediately remove and destroy infected plants. "
            "Control whiteflies with yellow sticky traps and imidacloprid or thiamethoxam. "
            "Prevention: Use TYLCV-resistant varieties; use reflective silver mulch; "
            "install 50-mesh insect-proof netting in nurseries."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_mosaic_virus": {
        "title": "Tomato Mosaic Virus (ToMV)",
        "summary": (
            "Light and dark green mosaic mottling on leaves, leaf distortion, and reduced fruit size. "
            "Highly contagious via contact, tools, and hands. "
            "No cure. Remove infected plants. Disinfect tools with 10% bleach or 70% alcohol between plants. "
            "Wash hands before handling plants. "
            "Prevention: Use ToMV-resistant varieties; avoid tobacco products near plants (ToMV survives in dried tobacco)."
        ),
        "source": "FAO/PCAARRD inline knowledge",
    },
    "tomato_healthy": {
        "title": "Tomato – Healthy",
        "summary": (
            "The tomato plant appears healthy. Support stems with stakes or trellis. "
            "Apply balanced fertiliser (16-16-16) at transplanting, then shift to high-potassium "
            "(like 12-12-17) once fruiting starts. Scout twice a week for early detection of blight and pests."
        ),
        "treatment_steps": [
            "Day 1: Water at the base and keep stems supported on stakes or a trellis.",
            "Day 2: Inspect leaves for early blight spots, wilting, or pest damage.",
            "Day 3: Feed with balanced fertiliser, or shift to higher potassium once fruiting starts.",
            "Day 4: Remove weeds and keep lower leaves away from wet soil to maintain airflow.",
        ],
        "source": "FAO/PCAARRD inline knowledge",
    },
}


class KnowledgeService:
    def __init__(self, settings: Settings):
        self._settings = settings
        self._supabase = SupabaseService(settings)

    async def fetch_relevant_records(self, payload: ChatRequest) -> list[dict[str, Any]]:
        disease_name = payload.diagnosis.disease_name if payload.diagnosis else None
        crop_type = payload.diagnosis.crop_type if payload.diagnosis else None
        label_key = payload.diagnosis.label_key if payload.diagnosis else None
        hint = (payload.hint_crop_type or "").strip().lower() or None

        latest_crop = self._infer_crop_from_text(payload.user_message)
        latest_matches = self._matching_inline_records(payload.user_message)
        if latest_crop:
            crop_type = latest_crop
            hint = latest_crop
            disease_name = None
            label_key = None
        elif len(latest_matches) == 1:
            matched_key, matched_record = latest_matches[0]
            crop_type = matched_key.split("_", 1)[0]
            hint = crop_type
            disease_name = str(matched_record.get("title") or "") or None
            label_key = matched_key

        if (crop_type or "").strip() == "" and hint:
            crop_type = hint

        # 1. Try Supabase first (authoritative source when populated)
        if self._settings.supabase_url and self._settings.supabase_service_role_key:
            rows = await self._supabase.fetch_knowledge(
                crop_type=crop_type,
                disease_name=disease_name,
                label_key=label_key,
            )
            if rows:
                return rows

            # No direct disease match, but the chat is still scoped to a crop.
            if not payload.diagnosis and hint:
                overview = await self._supabase.fetch_knowledge_for_crop_overview(hint)
                if overview:
                    return overview

        # 2. Fall back to inline knowledge keyed by the model label_key
        if label_key and label_key in _INLINE_KNOWLEDGE:
            return [_INLINE_KNOWLEDGE[label_key]]

        # 3. Partial match on crop_type if no label_key
        if crop_type:
            matches = [
                v for k, v in _INLINE_KNOWLEDGE.items()
                if k.startswith(crop_type.lower())
            ]
            if matches:
                return matches[:2]

        return []

    def _infer_crop_from_text(self, text: str) -> str | None:
        normalized = (text or "").strip().lower()
        for crop, aliases in _CROP_ALIASES.items():
            if any(alias in normalized for alias in aliases):
                return crop
        return None

    def _matching_inline_records(
        self,
        text: str,
    ) -> list[tuple[str, dict[str, Any]]]:
        normalized = (text or "").strip().lower()
        if not normalized:
            return []

        matches: list[tuple[str, dict[str, Any]]] = []
        for label_key, record in _INLINE_KNOWLEDGE.items():
            title = str(record.get("title") or "").lower()
            disease_words = label_key.split("_", 1)[-1].replace("_", " ")
            if disease_words in normalized or disease_words in title and disease_words in normalized:
                matches.append((label_key, record))
        return matches
