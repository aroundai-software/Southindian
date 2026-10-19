import 'package:Orderx/models/product_model.dart';

const ungroupedItemCategoryKey = '__ungrouped__';
const ungroupedItemCategoryLabel = 'Ungrouped';

String productItemCategoryName(ProductModel product) {
  final category = product.itemCategory?.trim();
  if (category != null && category.isNotEmpty) return category;
  return ungroupedItemCategoryKey;
}

Set<String> hiddenItemCategorySet(Iterable<String> hiddenItemCategoryNames) {
  return hiddenItemCategoryNames
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toSet();
}

bool isProductInEnabledItemCategory(
  ProductModel product,
  Iterable<String> hiddenItemCategoryNames,
) {
  final hidden = hiddenItemCategorySet(hiddenItemCategoryNames);
  if (hidden.isEmpty) return true;
  return !hidden.contains(productItemCategoryName(product));
}

List<ProductModel> filterProductsByEnabledItemCategories(
  List<ProductModel> products,
  Iterable<String> hiddenItemCategoryNames,
) {
  final hidden = hiddenItemCategorySet(hiddenItemCategoryNames);
  if (hidden.isEmpty) return products;
  return products
      .where((product) => !hidden.contains(productItemCategoryName(product)))
      .toList();
}

List<String> parseHiddenItemCategoryNames(dynamic value) {
  if (value == null) return const [];
  if (value is List) {
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '[]' || trimmed == '{}') {
      return const [];
    }
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      final inner = trimmed.substring(1, trimmed.length - 1).trim();
      if (inner.isEmpty) return const [];
      return inner
          .split(',')
          .map((part) => part.trim().replaceAll(RegExp(r'^"|"$'), ''))
          .where((part) => part.isNotEmpty)
          .toList();
    }
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      final inner = trimmed.substring(1, trimmed.length - 1).trim();
      if (inner.isEmpty) return const [];
      return inner
          .split(',')
          .map((part) => part.trim().replaceAll(RegExp(r'^"|"$'), ''))
          .where((part) => part.isNotEmpty)
          .toList();
    }
  }
  return const [];
}
