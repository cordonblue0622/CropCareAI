import '../../core/constants/app_enums.dart';
import '../models/disease_knowledge_model.dart';

class BundledDiseaseKnowledge {
  BundledDiseaseKnowledge._();

  static final DateTime _timestamp =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static List<DiseaseKnowledgeModel> records({String? cropType}) {
    final normalized = cropType?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return List<DiseaseKnowledgeModel>.unmodifiable(_records);
    }
    return List<DiseaseKnowledgeModel>.unmodifiable(
      _records.where((record) => record.cropType.value == normalized),
    );
  }

  static DiseaseKnowledgeModel _record({
    required CropType cropType,
    required String labelKey,
    required String diseaseName,
    required String description,
    List<String>? symptoms,
    List<String>? treatmentSteps,
    List<String>? preventionSteps,
    int? estimatedRecoveryDays,
    String? cautionNotes,
    String? sourceName,
    String? sourceUrl,
  }) {
    return DiseaseKnowledgeModel(
      id: labelKey,
      cropType: cropType,
      labelKey: labelKey,
      diseaseName: diseaseName,
      description: description,
      symptoms: symptoms,
      treatmentSteps: treatmentSteps,
      preventionSteps: preventionSteps,
      estimatedRecoveryDays: estimatedRecoveryDays,
      cautionNotes: cautionNotes,
      sourceName: sourceName ?? 'Bundled offline knowledge',
      sourceUrl: sourceUrl,
      createdAt: _timestamp,
      updatedAt: _timestamp,
    );
  }

  static final List<DiseaseKnowledgeModel> _records = [
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_bacterial_spot',
      diseaseName: 'Tomato Bacterial Spot',
      description:
          'Small dark water-soaked lesions can appear on leaves, stems, and fruit, and they spread quickly with splashing water.',
      symptoms: const [
        'Small dark or black spots on leaves and stems',
        'Rough scabby lesions on fruit surface',
      ],
      treatmentSteps: const [
        'Apply a copper-based bactericide such as copper hydroxide every 5 to 7 days.',
        'Remove heavily infected leaves and avoid touching wet plants.',
        'Keep irrigation at the base of the plant instead of overhead watering.',
      ],
      preventionSteps: const [
        'Use certified disease-free seed or seedlings.',
        'Remove crop debris after harvest and rotate crops.',
      ],
      estimatedRecoveryDays: 14,
    ),
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_early_blight',
      diseaseName: 'Tomato Early Blight',
      description:
          'Early blight usually starts on older lower leaves as brown spots with concentric rings and can move upward if left untreated.',
      symptoms: const [
        'Brown target-like spots on older leaves',
        'Yellowing around lesions and leaf drop',
      ],
      treatmentSteps: const [
        'Remove infected lower leaves as soon as you see them.',
        'Spray chlorothalonil or mancozeb on schedule according to the label.',
        'Use mulch and staking to keep leaves off wet soil and improve airflow.',
      ],
      preventionSteps: const [
        'Avoid overhead watering.',
        'Keep plants spaced and supported for better ventilation.',
      ],
      estimatedRecoveryDays: 14,
    ),
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_late_blight',
      diseaseName: 'Tomato Late Blight',
      description:
          'Late blight is highly destructive and can collapse a tomato plant within days, especially in cool wet weather.',
      symptoms: const [
        'Dark water-soaked lesions on leaves',
        'White mold-like growth on leaf undersides',
      ],
      treatmentSteps: const [
        'Remove and destroy infected leaves and stems immediately.',
        'Apply a labeled late blight fungicide such as metalaxyl plus mancozeb at first sign.',
        'Isolate affected plants from healthy plants if possible.',
      ],
      preventionSteps: const [
        'Do not wet the leaves during irrigation.',
        'Scout daily during cool wet periods and use resistant varieties when available.',
      ],
      estimatedRecoveryDays: 21,
      cautionNotes: 'Do not compost badly infected plant material.',
    ),
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_leaf_mold',
      diseaseName: 'Tomato Leaf Mold',
      description:
          'Leaf mold thrives in humid areas and often shows as pale patches on top of the leaf with olive mold underneath.',
      symptoms: const [
        'Pale yellow patches on the upper leaf surface',
        'Velvety olive-green growth underneath the leaf',
      ],
      treatmentSteps: const [
        'Reduce humidity around the crop and prune crowded foliage.',
        'Apply copper fungicide or chlorothalonil according to the label.',
        'Remove severely infected leaves to slow spread.',
      ],
      preventionSteps: const [
        'Keep good spacing and airflow around plants.',
        'Prefer resistant varieties when available.',
      ],
      estimatedRecoveryDays: 14,
    ),
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_septoria_leaf_spot',
      diseaseName: 'Tomato Septoria Leaf Spot',
      description:
          'Septoria leaf spot causes many small circular spots on lower leaves and can defoliate the plant when unmanaged.',
      symptoms: const [
        'Many small gray or tan spots with dark borders',
        'Heavy spotting beginning on lower leaves',
      ],
      treatmentSteps: const [
        'Remove spotted leaves early before the disease climbs upward.',
        'Apply chlorothalonil or mancozeb according to the product label.',
        'Keep foliage dry and improve airflow around the crop.',
      ],
      preventionSteps: const [
        'Rotate away from tomato for 2 to 3 seasons.',
        'Remove volunteer tomato plants and old residue.',
      ],
      estimatedRecoveryDays: 14,
    ),
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_spider_mites',
      diseaseName: 'Tomato Spider Mites',
      description:
          'Spider mites are tiny pests that cause stippling, bronzing, and fine webbing, especially during hot dry weather.',
      symptoms: const [
        'Yellow or white stippling on leaves',
        'Fine webbing on the underside of leaves',
      ],
      treatmentSteps: const [
        'Wash leaf undersides with water to knock mites down when infestation is still light.',
        'Use neem oil, insecticidal soap, or a labeled miticide such as abamectin for heavier infestations.',
        'Remove badly damaged leaves and keep the crop evenly watered.',
      ],
      preventionSteps: const [
        'Reduce dust around the field and avoid drought stress.',
        'Scout leaf undersides regularly during hot dry weeks.',
      ],
      estimatedRecoveryDays: 10,
    ),
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_target_spot',
      diseaseName: 'Tomato Target Spot',
      description:
          'Target spot creates brown lesions with concentric rings on leaves, stems, and fruit under warm humid conditions.',
      symptoms: const [
        'Brown circular lesions with concentric rings',
        'Yellow halo around spots on leaves',
      ],
      treatmentSteps: const [
        'Remove the most affected leaves to reduce inoculum.',
        'Apply a labeled fungicide such as azoxystrobin or difenoconazole.',
        'Improve airflow by pruning and keeping spacing open.',
      ],
      preventionSteps: const [
        'Destroy crop residue after harvest.',
        'Rotate crops for multiple seasons when possible.',
      ],
      estimatedRecoveryDays: 14,
    ),
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_yellow_leaf_curl_virus',
      diseaseName: 'Tomato Yellow Leaf Curl Virus',
      description:
          'TYLCV causes curled yellowing leaves, stunting, and poor fruit set, and it is spread by whiteflies.',
      symptoms: const [
        'Upward curling leaves with yellow edges',
        'Stunted growth and poor fruit set',
      ],
      treatmentSteps: const [
        'Remove and destroy infected plants as soon as possible.',
        'Control whiteflies using yellow sticky traps and labeled insect control measures.',
        'Protect new seedlings from vector pressure.',
      ],
      preventionSteps: const [
        'Use TYLCV-resistant varieties when available.',
        'Use reflective mulch or insect netting to reduce whitefly pressure.',
      ],
      cautionNotes:
          'There is no curative treatment once the plant is infected by the virus.',
    ),
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_mosaic_virus',
      diseaseName: 'Tomato Mosaic Virus',
      description:
          'Mosaic virus often causes mottled leaves, distortion, and reduced fruit quality, and it can spread by contact and contaminated tools.',
      symptoms: const [
        'Light and dark green mosaic mottling',
        'Leaf distortion and reduced fruit size',
      ],
      treatmentSteps: const [
        'Remove infected plants promptly to limit spread.',
        'Disinfect tools and wash hands before touching healthy plants.',
        'Avoid handling plants after using tobacco products.',
      ],
      preventionSteps: const [
        'Use resistant varieties and clean seedlings.',
        'Sanitize tools between plants and rows.',
      ],
      cautionNotes: 'There is no chemical cure for mosaic virus.',
    ),
    _record(
      cropType: CropType.tomato,
      labelKey: 'tomato_healthy',
      diseaseName: 'Tomato Healthy',
      description:
          'The tomato plant appears healthy. Keep monitoring regularly so disease or pest problems are caught early.',
      treatmentSteps: const [
        'Support plants with stakes or trellis to improve airflow.',
        'Use balanced fertilizer early, then shift toward higher potassium during fruiting.',
        'Scout twice a week for blight, mites, and virus vectors.',
      ],
      preventionSteps: const [
        'Water at the base of the plant.',
        'Keep weeds and old crop debris away from the planting area.',
      ],
    ),
    _record(
      cropType: CropType.pepper,
      labelKey: 'pepper_bacterial_spot',
      diseaseName: 'Bell Pepper Bacterial Spot',
      description:
          'Bacterial spot on pepper causes dark water-soaked lesions and can damage both leaves and fruit, especially during rainy periods.',
      symptoms: const [
        'Dark water-soaked spots on leaves',
        'Brown or black lesions on fruit and leaf drop',
      ],
      treatmentSteps: const [
        'Apply copper hydroxide or copper oxychloride every 5 to 7 days as labeled.',
        'Remove severely infected leaves and fruit from the field.',
        'Avoid overhead irrigation and field work while plants are wet.',
      ],
      preventionSteps: const [
        'Use certified clean seed or seedlings.',
        'Keep splash and handling spread to a minimum.',
      ],
      estimatedRecoveryDays: 14,
    ),
    _record(
      cropType: CropType.pepper,
      labelKey: 'pepper_healthy',
      diseaseName: 'Bell Pepper Healthy',
      description:
          'The pepper plant appears healthy. Maintain consistent nutrition and watch closely for thrips, aphids, and nutrient imbalance.',
      treatmentSteps: const [
        'Maintain soil pH around 6.0 to 6.8.',
        'Use calcium and magnesium support when blossom-end rot risk is high.',
        'Scout regularly for thrips and aphids that can spread viruses.',
      ],
      preventionSteps: const [
        'Avoid severe moisture swings.',
        'Keep the field clean and well ventilated.',
      ],
    ),
    _record(
      cropType: CropType.squash,
      labelKey: 'squash_powdery_mildew',
      diseaseName: 'Squash Powdery Mildew',
      description:
          'Powdery mildew shows as white powder on squash leaves and spreads quickly under warm days and cool nights.',
      symptoms: const [
        'White powdery coating on leaves and petioles',
        'Progressive yellowing and leaf decline',
      ],
      treatmentSteps: const [
        'Apply potassium bicarbonate or sulfur-based fungicide at the first sign of white growth.',
        'Use neem oil on schedule if conditions continue to favor spread.',
        'Remove heavily infected leaves to slow disease pressure.',
      ],
      preventionSteps: const [
        'Plant resistant varieties when available.',
        'Avoid excessive nitrogen that creates dense soft foliage.',
      ],
      estimatedRecoveryDays: 10,
    ),
    _record(
      cropType: CropType.eggplant,
      labelKey: 'eggplant_healthy',
      diseaseName: 'Eggplant Healthy',
      description:
          'The eggplant appears healthy. Continue routine scouting so insect feeding, wilt, and virus-like symptoms are found early.',
      treatmentSteps: const [
        'Check soil moisture before watering and keep the root zone evenly moist without waterlogging it.',
        'Inspect leaf undersides for aphids, whiteflies, thrips, mites, and new feeding damage.',
        'Keep weeds and fallen crop debris out of the bed, and keep fruit and foliage off the soil where practical.',
      ],
      preventionSteps: const [
        'Inspect nearby solanaceous crops before working on this healthy plant.',
        'Use clean tools and avoid moving from symptomatic plants to healthy plants without cleaning up.',
      ],
      sourceName: 'UC IPM: Eggplant Guidelines',
      sourceUrl: 'https://ipm.ucanr.edu/agriculture/eggplant/',
    ),
    _record(
      cropType: CropType.eggplant,
      labelKey: 'eggplant_insect_pest',
      diseaseName: 'Eggplant Insect Pest',
      description:
          'The image suggests insect or mite damage. Confirm the pest on leaf undersides or shoots before choosing a control action.',
      symptoms: const [
        'Chewed holes, stippling, curling, or distorted new growth',
        'Visible insects, webbing, honeydew, or frass on leaves',
      ],
      treatmentSteps: const [
        'Inspect the upper and lower leaf surfaces and young shoots; photograph the pest or its damage before acting.',
        'Remove only heavily infested leaves when the plant can tolerate it, then bag the material and clean tools.',
        'Reduce weeds and inspect nearby eggplant, tomato, and pepper plants for the same pest.',
        'Use a control product only after identifying the pest and confirming a current FPA-registered label for eggplant and that target.',
      ],
      preventionSteps: const [
        'Scout at least twice weekly, especially on new growth and leaf undersides.',
        'Avoid unnecessary broad-spectrum insecticides that can disrupt natural enemies.',
      ],
      estimatedRecoveryDays: 7,
      sourceName: 'UC IPM: Eggplant Guidelines',
      sourceUrl: 'https://ipm.ucanr.edu/agriculture/eggplant/',
    ),
    _record(
      cropType: CropType.eggplant,
      labelKey: 'eggplant_leaf_spot',
      diseaseName: 'Eggplant Leaf Spot',
      description:
          'Leaf spots can have several causes. Keep foliage dry, reduce spread from debris and splashing water, and confirm the cause if spots continue to expand.',
      symptoms: const [
        'Dark, tan, or brown leaf lesions that may enlarge or develop halos',
        'New spots appearing after rain, overhead watering, or humid weather',
      ],
      treatmentSteps: const [
        'Take a baseline photo of whole affected leaves and note whether spots are new, expanding, or limited to old damage.',
        'Remove only clearly diseased leaves when there are few, bag them, and sanitize tools before touching another plant.',
        'Remove fallen debris and water at the soil level so foliage stays as dry as possible.',
        'Seek local diagnosis support if lesions spread to new growth, stems, or fruit; use a product only with a current FPA label for eggplant and the confirmed target.',
      ],
      preventionSteps: const [
        'Avoid overhead irrigation and working among plants while foliage is wet.',
        'Keep spacing and weeds under control so leaves dry after rain or irrigation.',
      ],
      estimatedRecoveryDays: 7,
      sourceName: 'UC IPM: Eggplant Guidelines',
      sourceUrl: 'https://ipm.ucanr.edu/agriculture/eggplant/',
    ),
    _record(
      cropType: CropType.eggplant,
      labelKey: 'eggplant_mosaic_virus',
      diseaseName: 'Eggplant Mosaic Virus',
      description:
          'Mosaic-like mottling and distortion can be caused by a virus. There is no direct curative treatment, so containment and confirmation are important.',
      symptoms: const [
        'Light and dark green mottling, distortion, or stunting',
        'Similar symptoms appearing on nearby solanaceous plants',
      ],
      treatmentSteps: const [
        'Inspect the whole plant and nearby eggplant, tomato, pepper, and weeds for mosaic, distortion, or stunting; take a baseline photo.',
        'Handle healthy plants first, then the suspect plant; wash hands and sanitize tools after contact.',
        'Check for aphids, whiteflies, or thrips and remove nearby weeds that can support vectors or virus hosts.',
        'Request local confirmation before removing plants or using any product; do not rely on a product as a cure for a confirmed virus.',
      ],
      preventionSteps: const [
        'Use clean planting material and keep tools clean between plants.',
        'Scout young growth and vector pests regularly.',
      ],
      estimatedRecoveryDays: 14,
      cautionNotes:
          'A confirmed virus has no curative spray. Follow local agriculture advice before removing a plant.',
      sourceName: 'UC IPM: Eggplant Mosaic Diseases Caused by Potyviruses',
      sourceUrl:
          'https://ipm.ucanr.edu/agriculture/eggplant/mosaic-diseases-caused-by-potyviruses/',
    ),
    _record(
      cropType: CropType.eggplant,
      labelKey: 'eggplant_small_leaf',
      diseaseName: 'Eggplant Small Leaf',
      description:
          'Small or distorted leaves can have several causes, including vector-borne disease, nutrition, herbicide injury, or other stress. This label needs confirmation before treatment.',
      treatmentSteps: const [
        'Photograph the whole plant, including normal and affected shoots, and record when the small-leaf growth began.',
        'Inspect leaf undersides and nearby weeds for aphids, whiteflies, or leafhoppers, and inspect nearby eggplant for similar symptoms.',
        'Avoid pruning heavily or applying pesticide, fertilizer, or herbicide changes until a local diagnosis confirms the cause.',
        'Isolate tools used on the suspect plant and seek local agriculture advice if stunting or distortion is spreading.',
      ],
      preventionSteps: const [
        'Start with healthy transplants and control weeds that can host vector pests.',
        'Monitor new growth and vector activity early in the crop cycle.',
      ],
      estimatedRecoveryDays: 14,
      cautionNotes:
          'This scanner label is provisional; do not treat it as a confirmed disease without local review.',
      sourceName: 'UC IPM: Eggplant Guidelines',
      sourceUrl: 'https://ipm.ucanr.edu/agriculture/eggplant/',
    ),
    _record(
      cropType: CropType.eggplant,
      labelKey: 'eggplant_white_mold',
      diseaseName: 'Eggplant White Mold',
      description:
          'White mold-like growth needs confirmation because several diseases and harmless surface growth can look similar. Reduce moisture and prevent transfer while seeking diagnosis support.',
      treatmentSteps: const [
        'Photograph the entire affected leaf, stem, and nearby plant area; note whether cottony growth, wilt, or stem damage is present.',
        'Avoid handling wet plants, remove only clearly infected material when practical, and bag it rather than composting it.',
        'Clean up crop debris, improve airflow without heavy pruning, and water at the soil level only when needed.',
        'Request local diagnosis support if white growth, stem lesions, or wilting is increasing; use a product only with a current FPA label for the confirmed target.',
      ],
      preventionSteps: const [
        'Keep the canopy and soil surface free of old crop debris.',
        'Avoid prolonged leaf wetness and sanitize tools after symptomatic plants.',
      ],
      estimatedRecoveryDays: 7,
      cautionNotes:
          'Confirm the disease before applying a fungicide because white growth alone is not a reliable diagnosis.',
      sourceName: 'UC IPM: Eggplant Guidelines',
      sourceUrl: 'https://ipm.ucanr.edu/agriculture/eggplant/',
    ),
    _record(
      cropType: CropType.eggplant,
      labelKey: 'eggplant_wilt',
      diseaseName: 'Eggplant Wilt',
      description:
          'Wilting can result from root disease, vascular disease, drought, waterlogging, or injury. Check soil moisture and plant condition before deciding on treatment.',
      symptoms: const [
        'Leaves droop or yellow despite apparently adequate water',
        'Wilt worsens in heat or spreads from lower leaves to the whole plant',
      ],
      treatmentSteps: const [
        'Check root-zone moisture and drainage before watering again; do not compensate for wilt by repeatedly soaking the soil.',
        'Inspect stems, roots, and nearby plants for one-sided wilt, browning, root rot, or insect injury; take a whole-plant photo.',
        'Keep tools and hands clean, avoid moving soil from the affected area, and remove heavily collapsed plants only after local guidance.',
        'Seek prompt local diagnosis if wilt persists after moisture is corrected or is spreading; use a product only with a current FPA label for the confirmed cause.',
      ],
      preventionSteps: const [
        'Use well-drained soil and avoid repeated eggplant or related crops in a known wilt area.',
        'Start with healthy transplants and clean tools before working among plants.',
      ],
      estimatedRecoveryDays: 7,
      cautionNotes:
          'Wilt is not one disease. Confirm the cause before using a pesticide or removing plants.',
      sourceName: 'UC IPM: Eggplant Verticillium Wilt',
      sourceUrl:
          'https://ipm.ucanr.edu/agriculture/eggplant/verticillium-wilt/',
    ),
    _record(
      cropType: CropType.pechay,
      labelKey: 'pechay_healthy',
      diseaseName: 'Pechay Healthy',
      description:
          'The pechay appears healthy. Continue frequent checks because leafy brassicas can change quickly under wet conditions or pest pressure.',
      treatmentSteps: const [
        'Check soil moisture before watering and water at the base without splashing soil onto leaves.',
        'Inspect leaf undersides and the growing point for aphids, caterpillars, chewing holes, and new spots.',
        'Remove weeds and damaged outer leaves, keeping the bed free of old crop debris.',
      ],
      preventionSteps: const [
        'Scout often enough to find pests before they build up on tender leaves.',
        'Keep spacing and drainage adequate so leaves dry after rain or irrigation.',
      ],
      sourceName: 'UC IPM: Cole Crops Guidelines',
      sourceUrl: 'https://ipm.ucanr.edu/agriculture/cole-crops/',
    ),
    _record(
      cropType: CropType.pechay,
      labelKey: 'pechay_leaf_spot',
      diseaseName: 'Pechay Leaf Spot',
      description:
          'Leaf spots on pechay may be caused by fungal or bacterial disease. Reduce leaf wetness and infected debris while confirming the cause.',
      symptoms: const [
        'Small dark, tan, or target-like spots that enlarge or develop yellow halos',
        'New lesions appearing after humid weather, rain, or leaf wetness',
      ],
      treatmentSteps: const [
        'Take a baseline photo of whole affected leaves and note whether spots are new or spreading.',
        'Remove severely spotted outer leaves when practical, bag them, and sanitize tools before handling healthy plants.',
        'Remove crop debris and weeds, and water at the soil level to keep foliage dry.',
        'Seek local confirmation if spots continue on young leaves; use a product only with a current FPA label for pechay or the applicable brassica crop and the confirmed target.',
      ],
      preventionSteps: const [
        'Use clean seed or transplants and avoid working in the bed while leaves are wet.',
        'Rotate away from brassicas where disease has been recurring and manage brassica weeds.',
      ],
      estimatedRecoveryDays: 7,
      sourceName: 'Cornell Vegetables: Alternaria Leaf Spot of Brassicas',
      sourceUrl:
          'https://www.vegetables.cornell.edu/pest-management/disease-factsheets/alternaria-leaf-spot/',
    ),
    _record(
      cropType: CropType.pechay,
      labelKey: 'pechay_soft_rot',
      diseaseName: 'Pechay Soft Rot',
      description:
          'Soft, wet, foul-smelling decay can spread rapidly in warm, wet conditions. Protect healthy plants and seek confirmation promptly.',
      symptoms: const [
        'Soft water-soaked tissue or collapse, sometimes with odor',
        'Decay increasing after injury, standing water, or heavy rain',
      ],
      treatmentSteps: const [
        'Photograph the whole plant and check drainage; avoid watering again until excess moisture has cleared.',
        'Remove severely rotted plants or leaves promptly, bag them, and clean tools and hands afterward.',
        'Improve drainage, avoid leaf injury, and keep irrigation at the soil level so foliage dries quickly.',
        'Seek local agriculture advice if nearby plants begin to soften or collapse; do not apply a product without a confirmed cause and current label.',
      ],
      preventionSteps: const [
        'Avoid standing water and handle leaves gently to prevent wounds.',
        'Keep the bed clean and harvest or remove damaged outer leaves promptly.',
      ],
      estimatedRecoveryDays: 7,
      cautionNotes:
          'Soft rot spreads quickly. Remove badly decayed material from the growing area instead of composting it.',
      sourceName: 'UC IPM: Cole Crops Guidelines',
      sourceUrl: 'https://ipm.ucanr.edu/agriculture/cole-crops/',
    ),
    _record(
      cropType: CropType.pechay,
      labelKey: 'pechay_aphids',
      diseaseName: 'Pechay Aphids',
      description:
          'Aphids cluster on tender leaves and can distort growth or leave sticky honeydew. Check the pest before selecting any product.',
      symptoms: const [
        'Clusters of small soft-bodied insects on leaf undersides or new growth',
        'Curling leaves, sticky honeydew, or ants tending the plant',
      ],
      treatmentSteps: const [
        'Inspect the undersides of leaves and the growing point, and record whether aphids are increasing or natural enemies are present.',
        'Remove only heavily infested outer leaves when practical and use a gentle water spray only if leaves can dry quickly.',
        'Control nearby weeds and check neighboring brassicas so the infestation is not moved through the bed.',
        'Use a control product only after confirming aphids and checking a current FPA label for pechay or the applicable brassica crop.',
      ],
      preventionSteps: const [
        'Scout tender new growth frequently and avoid unnecessary broad-spectrum insecticides.',
        'Manage weeds that can host aphids around the growing area.',
      ],
      estimatedRecoveryDays: 7,
      sourceName: 'UC IPM: Cole Crops Aphids',
      sourceUrl: 'https://ipm.ucanr.edu/agriculture/cole-crops/aphids/',
    ),
    _record(
      cropType: CropType.pechay,
      labelKey: 'pechay_downy_mildew',
      diseaseName: 'Pechay Downy Mildew',
      description:
          'Yellow patches and growth on leaf undersides in cool, wet conditions may indicate downy mildew. Reduce leaf wetness and get confirmation if symptoms spread.',
      treatmentSteps: const [
        'Take a photo of both sides of whole affected leaves and note whether pale or yellow patches match growth underneath.',
        'Avoid overhead irrigation and handling wet leaves; remove only heavily affected material and sanitize tools.',
        'Improve spacing and drainage, remove old crop debris, and inspect nearby brassicas for similar symptoms.',
        'Seek local confirmation if fresh symptoms are increasing; use a product only with a current FPA label for pechay or the applicable brassica crop and confirmed target.',
      ],
      preventionSteps: const [
        'Use clean seed or transplants and avoid prolonged leaf wetness.',
        'Inspect after cool, humid, or rainy weather so new symptoms are caught early.',
      ],
      estimatedRecoveryDays: 7,
      sourceName: 'UC IPM: Cole Crops Downy Mildew',
      sourceUrl: 'https://ipm.ucanr.edu/agriculture/cole-crops/downy-mildew/',
    ),
  ];
}
