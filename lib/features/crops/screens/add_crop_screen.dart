import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/models/crop_model.dart';
import '../providers/crops_provider.dart';
import '../../auth/providers/auth_provider.dart';

class AddCropScreen extends StatefulWidget {
  final CropModel? existing;
  const AddCropScreen({super.key, this.existing});

  @override
  State<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends State<AddCropScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _plotCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _notesCtrl;
  CropType _selectedType = CropType.tomato;
  DateTime? _plantedAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _nameCtrl = TextEditingController(text: c?.cropName ?? '');
    _plotCtrl = TextEditingController(text: c?.plotCode ?? '');
    _locationCtrl = TextEditingController(text: c?.locationLabel ?? '');
    _notesCtrl = TextEditingController(text: c?.notes ?? '');
    if (c != null) {
      _selectedType = c.cropType;
      _plantedAt = c.plantedAt;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _plotCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final cropsProvider = context.read<CropsProvider>();
      if (widget.existing == null) {
        await cropsProvider.addCrop(
          userId: user.id,
          cropName: _nameCtrl.text.trim(),
          cropType: _selectedType,
          plotCode:
              _plotCtrl.text.trim().isEmpty ? null : _plotCtrl.text.trim(),
          locationLabel: _locationCtrl.text.trim().isEmpty
              ? null
              : _locationCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          plantedAt: _plantedAt,
        );
        if (mounted) Navigator.pop(context);
      } else {
        final updatedCrop = widget.existing!.copyWith(
          cropName: _nameCtrl.text.trim(),
          cropType: _selectedType,
          plotCode:
              _plotCtrl.text.trim().isEmpty ? null : _plotCtrl.text.trim(),
          locationLabel: _locationCtrl.text.trim().isEmpty
              ? null
              : _locationCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          plantedAt: _plantedAt,
        );
        final saved = await cropsProvider.updateCrop(updatedCrop);
        if (!saved) throw StateError('Crop update was rejected.');

        var resultCrop = updatedCrop;
        for (final crop in cropsProvider.crops) {
          if (crop.id == updatedCrop.id) {
            resultCrop = crop;
            break;
          }
        }
        if (mounted) Navigator.pop(context, resultCrop);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not save this crop. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _plantedAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _plantedAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundCream,
        title: Text(isEdit ? 'Edit Crop' : 'Add New Crop',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_saving)
            const Center(
                child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2)))
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildLabel('Crop Name *'),
            _buildField(
              controller: _nameCtrl,
              hint: 'e.g. Tomato Plot A',
              validator: (v) =>
                  context.read<CropsProvider>().validateUniqueCropName(
                        cropName: v ?? '',
                        excludingCropId: widget.existing?.id,
                      ),
            ),
            const SizedBox(height: 16),
            _buildLabel('Crop Type *'),
            DropdownButtonFormField<CropType>(
              initialValue: _selectedType,
              decoration: _inputDecoration('Select crop type'),
              items: CropType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child:
                            Text(t.name[0].toUpperCase() + t.name.substring(1)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedType = v!),
            ),
            const SizedBox(height: 16),
            _buildLabel('Plot Code'),
            _buildField(controller: _plotCtrl, hint: 'e.g. PLOT-01'),
            const SizedBox(height: 16),
            _buildLabel('Location'),
            _buildField(
                controller: _locationCtrl, hint: 'e.g. Barangay Mantalongon'),
            const SizedBox(height: 16),
            _buildLabel('Planted At'),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today,
                      size: 18, color: AppColors.textGray),
                  const SizedBox(width: 12),
                  Text(
                    _plantedAt != null
                        ? '${_plantedAt!.year}-${_plantedAt!.month.toString().padLeft(2, '0')}-${_plantedAt!.day.toString().padLeft(2, '0')}'
                        : 'Select date',
                    style: TextStyle(
                        color: _plantedAt != null
                            ? AppColors.textDark
                            : AppColors.textGray),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            _buildLabel('Notes'),
            _buildField(
              controller: _notesCtrl,
              hint: 'Any additional notes...',
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _saving ? 'Saving...' : (isEdit ? 'Update Crop' : 'Add Crop'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark)),
      );

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: _inputDecoration(hint),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(14),
      );
}
