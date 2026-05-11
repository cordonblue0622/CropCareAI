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
      sourceName: 'Bundled offline knowledge',
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
      cautionNotes: 'There is no curative treatment once the plant is infected by the virus.',
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
  ];
}