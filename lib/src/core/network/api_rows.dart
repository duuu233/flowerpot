/// Extracts records from common paginated response shapes.
List<Map<String, dynamic>> extractApiRows(Object? data) {
  Object? rows = data;
  if (data is Map) {
    rows =
        data['pageData'] ??
        data['list'] ??
        data['rows'] ??
        data['records'] ??
        data['data'] ??
        data['items'];
  }
  if (rows is! List) return const <Map<String, dynamic>>[];
  return rows
      .whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}
