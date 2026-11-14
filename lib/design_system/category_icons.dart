import 'package:flutter/material.dart';

/// Icon for a spending label. Matches the category first (Food, Transport…),
/// then familiar words in a merchant or note (Starbucks, Blinkit, Uber…),
/// so the same thing gets the same icon everywhere.
IconData iconForLabel(String label, {String? category}) {
  for (final text in [category, label]) {
    if (text == null) continue;
    final t = text.toLowerCase();
    for (final e in _rules) {
      if (e.$1.any(t.contains)) return e.$2;
    }
  }
  return Icons.sell_rounded;
}

/// Whether [label] / [category] matched something specific (not the fallback).
bool hasSpecificIcon(String label, {String? category}) =>
    iconForLabel(label, category: category) != Icons.sell_rounded;

const List<(List<String>, IconData)> _rules = [
  (
    ['coffee', 'starbucks', 'cafe', 'café', 'chai', 'tea', 'barista'],
    Icons.local_cafe_rounded,
  ),
  (
    [
      'grocer',
      'blinkit',
      'zepto',
      'instamart',
      'bigbasket',
      'dmart',
      'vegetable',
      'fruit',
      'milk',
      'supermarket',
      'kirana',
    ],
    Icons.local_grocery_store_rounded,
  ),
  (
    [
      'food',
      'dining',
      'restaurant',
      'swiggy',
      'zomato',
      'pizza',
      'burger',
      'biryani',
      'kitchen',
      'dhaba',
      'bakery',
      'meal',
      'lunch',
      'dinner',
      'breakfast',
      'snack',
      'domino',
      'mcdonald',
      'kfc',
      'subway',
    ],
    Icons.restaurant_rounded,
  ),
  (
    ['uber', 'ola', 'rapido', 'cab', 'taxi', 'auto', 'ride'],
    Icons.local_taxi_rounded,
  ),
  (
    ['metro', 'bus', 'train', 'irctc', 'railway', 'transit'],
    Icons.directions_transit_rounded,
  ),
  (
    ['petrol', 'diesel', 'fuel', 'gas station', 'hp ', 'indian oil'],
    Icons.local_gas_station_rounded,
  ),
  (
    [
      'flight',
      'airline',
      'indigo',
      'air india',
      'travel',
      'trip',
      'hotel',
      'makemytrip',
      'airbnb',
      'cleartrip',
    ],
    Icons.flight_rounded,
  ),
  (
    ['transport', 'parking', 'toll', 'fastag', 'commute'],
    Icons.directions_car_rounded,
  ),
  (
    [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'nykaa',
      'shopping',
      'mall',
      'clothes',
      'fashion',
      'store',
    ],
    Icons.shopping_bag_rounded,
  ),
  (
    [
      'pharmacy',
      'medic',
      'apollo',
      'chemist',
      'hospital',
      'clinic',
      'doctor',
      'health',
      'lab test',
      'dental',
    ],
    Icons.medical_services_rounded,
  ),
  (
    [
      'electric',
      'water bill',
      'broadband',
      'wifi',
      'recharge',
      'jio',
      'airtel',
      'vi ',
      'dth',
      'bill',
      'utility',
      'gas bill',
      'emi',
    ],
    Icons.receipt_long_rounded,
  ),
  (['rent', 'maintenance', 'society', 'housing'], Icons.home_rounded),
  (
    [
      'netflix',
      'spotify',
      'prime',
      'hotstar',
      'youtube',
      'subscription',
      'movie',
      'cinema',
      'bookmyshow',
      'game',
      'fun',
      'entertain',
      'concert',
      'party',
    ],
    Icons.movie_rounded,
  ),
  (['gym', 'fitness', 'cult', 'sport', 'yoga'], Icons.fitness_center_rounded),
  (
    [
      'school',
      'tuition',
      'course',
      'udemy',
      'book',
      'education',
      'college',
      'fees',
    ],
    Icons.school_rounded,
  ),
  (['gift', 'donat', 'charity'], Icons.card_giftcard_rounded),
  (
    ['salon', 'spa', 'haircut', 'beauty', 'grooming'],
    Icons.content_cut_rounded,
  ),
  (['pet', 'vet', 'dog', 'cat food'], Icons.pets_rounded),
  (['insurance', 'premium', 'lic '], Icons.shield_rounded),
  (
    ['invest', 'sip', 'mutual', 'stock', 'zerodha', 'groww'],
    Icons.trending_up_rounded,
  ),
  (['atm', 'cash'], Icons.payments_rounded),
  (['salary', 'income', 'paid back', 'refund'], Icons.south_west_rounded),
  (['lent', 'owe', 'loan'], Icons.handshake_rounded),
  (['imported'], Icons.download_rounded),
  (['other', 'general', 'misc'], Icons.category_rounded),
];
