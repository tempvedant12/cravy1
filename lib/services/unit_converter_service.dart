// lib/services/unit_converter_service.dart

class UnitConverterService {
  // Base unit for each group is the one with a factor of 1.0
  static const Map<String, Map<String, double>> _conversions = {
    'mass': {
      'kg': 1000.0,
      'g': 1.0,
      'mg': 0.001,
      'lb': 453.592,
      'oz': 28.3495,
    },
    'volume': {
      'l': 1000.0,
      'ml': 1.0,
      'fl oz': 29.5735,
      'cup': 236.588,
      'tbsp': 14.7868,
      'tsp': 4.92892,
    },
    'count': {
      'pcs': 1.0,
      'dozen': 12.0,
      'unit': 1.0,
      'item': 1.0,
    }
  };

  /// Returns a list of all supported units.
  static List<String> getAllUnits() {
    final List<String> allUnits = [];
    _conversions.forEach((group, units) {
      allUnits.addAll(units.keys);
    });
    return allUnits;
  }

  // Find which group a unit belongs to (e.g., 'kg' -> 'mass')
  static String? _getGroupForUnit(String unit) {
    for (var group in _conversions.entries) {
      if (group.value.containsKey(unit.toLowerCase())) {
        return group.key;
      }
    }
    return null;
  }

  /// Returns a list of units compatible with the given unit.
  static List<String> getCompatibleUnits(String unit) {
    final group = _getGroupForUnit(unit);
    if (group != null) {
      return _conversions[group]!.keys.toList();
    }
    // If the unit is unknown, just return the unit itself
    return [unit];
  }

  /// Converts a value from any compatible unit to the group's base unit.
  /// e.g., convertToBase(1.5, 'kg') -> returns 1500.0 (grams)
  static double convertToBase(double value, String fromUnit) {
    final group = _getGroupForUnit(fromUnit);
    if (group != null) {
      final factor = _conversions[group]![fromUnit.toLowerCase()];
      if (factor != null) {
        return value * factor;
      }
    }
    return value; // Return original value if no conversion is found
  }
}