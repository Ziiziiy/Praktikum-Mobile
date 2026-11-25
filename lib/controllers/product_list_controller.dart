import 'dart:async';

import 'package:get/get.dart';

import '../models/product_model.dart';
import '../services/db_helper.dart';
import '../services/product_service.dart';

/// Filter berdasarkan kondisi stok.
enum StockFilter {
  all('Semua'),
  low('Menipis'),
  out('Habis'),
  safe('Aman');

  final String label;
  const StockFilter(this.label);

  bool matches(ProductModel p) => switch (this) {
    StockFilter.all => true,
    StockFilter.out => p.isOutOfStock,
    StockFilter.low => p.isLowStock && !p.isOutOfStock,
    StockFilter.safe => !p.isLowStock,
  };
}

/// Urutan daftar produk.
enum ProductSort {
  nameAsc('Nama (A-Z)'),
  stockAsc('Stok paling sedikit'),
  category('Kategori');

  final String label;
  const ProductSort(this.label);
}

/// Menyimpan keadaan layar daftar produk. Data tetap dibaca dari SQLite
/// lewat [DbHelper], jadi tidak ada perubahan di Supabase.
class ProductListController extends GetxController {
  // Hasil query SQLite (sudah terfilter kata kunci dan kategori).
  final products = <ProductModel>[].obs;
  final categories = <String>[].obs;
  final loaded = false.obs;

  // Pilihan pengguna.
  final search = ''.obs;
  final category = Rxn<String>();
  final stockFilter = StockFilter.all.obs;
  final sortBy = ProductSort.nameAsc.obs;

  Timer? _debounce;
  int _seq = 0; // mencegah hasil query lama menimpa yang baru

  /// Daftar yang tampil: filter stok + urutan. Dihitung ulang otomatis
  /// oleh Obx setiap salah satu variabel di atas berubah.
  List<ProductModel> get visible {
    final list = products.where(stockFilter.value.matches).toList();
    switch (sortBy.value) {
      case ProductSort.nameAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case ProductSort.stockAsc:
        list.sort((a, b) {
          final c = a.stock.compareTo(b.stock);
          return c != 0
              ? c
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case ProductSort.category:
        list.sort((a, b) {
          final c = a.category.toLowerCase().compareTo(b.category.toLowerCase());
          return c != 0
              ? c
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }
    return list;
  }

  /// Jumlah produk per kondisi stok (untuk angka di chip).
  int countOf(StockFilter f) => products.where(f.matches).length;

  bool get filtering =>
      search.value.trim().isNotEmpty ||
      category.value != null ||
      stockFilter.value != StockFilter.all;

  @override
  void onInit() {
    super.onInit();
    ProductService.instance.changes.addListener(load);
    load();
  }

  @override
  void onClose() {
    ProductService.instance.changes.removeListener(load);
    _debounce?.cancel();
    super.onClose();
  }

  /// Membaca dari cache SQLite, jadi katalog tetap tampil saat offline.
  Future<void> load() async {
    final seq = ++_seq;
    final db = DbHelper.instance;

    final cats = await db.getCategories();
    if (isClosed || seq != _seq) return;

    // Kategori yang dipilih sudah tidak ada (produknya dinonaktifkan).
    if (category.value != null && !cats.contains(category.value)) {
      category.value = null;
      return load();
    }

    final list = await db.getProducts(
      query: search.value,
      category: category.value,
    );
    if (isClosed || seq != _seq) return;

    categories.assignAll(cats);
    products.assignAll(list);
    loaded.value = true;
  }

  void onSearchChanged(String text) {
    search.value = text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), load);
  }

  void clearSearch() {
    search.value = '';
    load();
  }

  void setCategory(String? value) {
    category.value = value;
    load();
  }

  void setStockFilter(StockFilter value) => stockFilter.value = value;

  void setSort(ProductSort value) => sortBy.value = value;
}