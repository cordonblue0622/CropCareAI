import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/crop_model.dart';
import '../auth/providers/auth_provider.dart';

class DeletedCropsHistoryScreen extends StatefulWidget {
  const DeletedCropsHistoryScreen({super.key});

  @override
  State<DeletedCropsHistoryScreen> createState() =>
      _DeletedCropsHistoryScreenState();
}

class _DeletedCropsHistoryScreenState extends State<DeletedCropsHistoryScreen> {
  static const _pageSize = 10;
  int _page = 0;
  late Future<List<CropModel>> _crops;

  @override
  void initState() {
    super.initState();
    _crops = _load();
  }

  Future<List<CropModel>> _load() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return [];
    final rows = await context.read<DatabaseHelper>().queryByUserId(
          AppConstants.cropsTable,
          user.id,
          includeDeleted: true,
        );
    return rows.map(CropModel.fromMap).where((crop) => crop.isDeleted).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.backgroundCream,
        appBar: AppBar(title: const Text('Deleted Crop History')),
        body: FutureBuilder<List<CropModel>>(
          future: _crops,
          builder: (context, snapshot) {
            final crops = snapshot.data ?? const <CropModel>[];
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (crops.isEmpty) {
              return const Center(child: Text('No deleted crops recorded.'));
            }
            final pageCount = (crops.length / _pageSize).ceil();
            final visible = crops.skip(_page * _pageSize).take(_pageSize);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...visible.map(
                  (crop) => Card(
                    color: Colors.white,
                    child: ListTile(
                      leading: const Icon(Icons.eco_outlined,
                          color: AppColors.textGray),
                      title: Text(crop.cropName),
                      subtitle: Text(
                        '${crop.cropType.name} • Removed ${crop.updatedAt.toLocal().toString().split(' ').first}',
                      ),
                    ),
                  ),
                ),
                if (pageCount > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed:
                            _page == 0 ? null : () => setState(() => _page--),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('${_page + 1} / $pageCount'),
                      IconButton(
                        onPressed: _page >= pageCount - 1
                            ? null
                            : () => setState(() => _page++),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      );
}
