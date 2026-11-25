import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/product_list_controller.dart';
import '../../core/constants/app_colors.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/product_card.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _search = TextEditingController();
  late final ProductListController _c;

  @override
  void initState() {
    super.initState();
    _c = Get.put(ProductListController());
  }

  @override
  void dispose() {
    _search.dispose();
    Get.delete<ProductListController>();
    super.dispose();
  }

  Future<void> _refresh() async {
    final report = await SyncService.instance.syncAll();
    await _c.load();
    if (!mounted) return;
    if (report.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sinkronisasi gagal: ${report.error}')),
      );
    }
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<ProductModel>(
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${saved.name} ditambahkan.')));
    }
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: AppColors.yellow,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        labelStyle: TextStyle(
          color: selected ? AppColors.black : AppColors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildList() {
    return Obx(() {
      if (!_c.loaded.value) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.yellow),
        );
      }

      final items = _c.visible;
      final filtering = _c.filtering;

      return RefreshIndicator(
        color: AppColors.yellow,
        backgroundColor: AppColors.surface,
        onRefresh: _refresh,
        child: items.isEmpty
            ? CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: filtering
                          ? Icons.search_off_rounded
                          : Icons.inventory_2_outlined,
                      title: filtering
                          ? 'Produk tidak ditemukan'
                          : 'Belum ada produk',
                      message: filtering
                          ? 'Coba kata kunci, kategori, atau filter lain.'
                          : 'Tarik ke bawah untuk memuat ulang.',
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final p = items[i];
                  return ProductCard(
                    product: p,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(productId: p.id),
                      ),
                    ),
                  );
                },
              ),
      );
    });
  }

  /// Chip kondisi stok: Semua / Menipis / Habis / Aman, lengkap dengan jumlahnya.
  Widget _stockChips() {
    return SizedBox(
      height: 44,
      child: Obx(
        () => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final f in StockFilter.values)
              _chip(
                '${f.label} (${_c.countOf(f)})',
                _c.stockFilter.value == f,
                () => _c.setStockFilter(f),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sortMenu() {
    return PopupMenuButton<ProductSort>(
      tooltip: 'Urutkan',
      icon: const Icon(Icons.sort_rounded),
      onSelected: _c.setSort,
      itemBuilder: (_) => [
        for (final s in ProductSort.values)
          CheckedPopupMenuItem<ProductSort>(
            value: s,
            checked: _c.sortBy.value == s,
            child: Text(s.label),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produk & Stok'),
        actions: [_sortMenu()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Produk'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _c.onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari nama atau SKU',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _search,
                  builder: (_, value, __) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _c.clearSearch();
                          },
                        ),
                ),
              ),
            ),
          ),
          // Baris 1: kondisi stok.
          _stockChips(),
          // Baris 2: kategori.
          SizedBox(
            height: 44,
            child: Obx(
              () => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip(
                    'Semua kategori',
                    _c.category.value == null,
                    () => _c.setCategory(null),
                  ),
                  for (final cat in _c.categories)
                    _chip(
                      cat,
                      _c.category.value == cat,
                      () => _c.setCategory(cat),
                    ),
                ],
              ),
            ),
          ),
          Obx(
            () => Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Menampilkan ${_c.visible.length} dari ${_c.products.length} produk',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }
}