class MeetingPlace {
  const MeetingPlace({required this.id, required this.name});

  final int id;
  final String name;

  static MeetingPlace fromMap(Map<String, Object?> m) {
    return MeetingPlace(
      id: (m['id'] as int?) ?? int.parse(m['id'].toString()),
      name: m['name']! as String,
    );
  }

  Map<String, Object?> toMap() => {'id': id, 'name': name};
}

