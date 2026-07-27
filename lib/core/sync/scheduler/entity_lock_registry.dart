/// Lock por entidad: evita que dos workers muten el mismo documento a la vez.
class EntityLockRegistry {
  EntityLockRegistry._();
  static final EntityLockRegistry instance = EntityLockRegistry._();

  final Set<String> _held = {};

  String key(String entityType, String? id) =>
      '$entityType:${id ?? '_'}';

  bool tryAcquire(String entityType, String? id) {
    final k = key(entityType, id);
    if (_held.contains(k)) return false;
    _held.add(k);
    return true;
  }

  void release(String entityType, String? id) {
    _held.remove(key(entityType, id));
  }

  bool isHeld(String entityType, String? id) =>
      _held.contains(key(entityType, id));

  int get heldCount => _held.length;

  void resetForTests() => _held.clear();
}
