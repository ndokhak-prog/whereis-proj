class InventoryItem {
  final int? id;
  final String itemName;
  final String category;
  final String floor;
  final String placeLarge;
  final String placeMedium;
  final String placeSmall;
  final int quantity;
  final String? expiryDate;
  final String note;
  final String? photoPath;
  final int createdAt;
  final int updatedAt;

  const InventoryItem({
    this.id,
    required this.itemName,
    this.category = '',
    this.floor = '',
    this.placeLarge = '',
    this.placeMedium = '',
    this.placeSmall = '',
    this.quantity = 1,
    this.expiryDate,
    this.note = '',
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'item_name': itemName,
        'category': category,
        'floor': floor,
        'place_large': placeLarge,
        'place_medium': placeMedium,
        'place_small': placeSmall,
        'quantity': quantity,
        'expiry_date': expiryDate,
        'note': note,
        'photo_path': photoPath,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory InventoryItem.fromMap(Map<String, Object?> m) => InventoryItem(
        id: m['id'] as int?,
        itemName: (m['item_name'] as String?) ?? '',
        category: (m['category'] as String?) ?? '',
        floor: (m['floor'] as String?) ?? '',
        placeLarge: (m['place_large'] as String?) ?? '',
        placeMedium: (m['place_medium'] as String?) ?? '',
        placeSmall: (m['place_small'] as String?) ?? '',
        quantity: (m['quantity'] as int?) ?? 1,
        expiryDate: m['expiry_date'] as String?,
        note: (m['note'] as String?) ?? '',
        photoPath: m['photo_path'] as String?,
        createdAt: (m['created_at'] as int?) ?? 0,
        updatedAt: (m['updated_at'] as int?) ?? 0,
      );

  String get locationText {
    final parts = [floor, placeLarge, placeMedium, placeSmall]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? '(위치 미지정)' : parts.join(' > ');
  }
}
