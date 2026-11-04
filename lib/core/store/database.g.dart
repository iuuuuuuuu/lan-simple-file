// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $DevicesTable extends Devices with TableInfo<$DevicesTable, DeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<Uint8List> pubkey = GeneratedColumn<Uint8List>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _algMeta = const VerificationMeta('alg');
  @override
  late final GeneratedColumn<String> alg = GeneratedColumn<String>(
    'alg',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ed25519'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _avatarHashMeta = const VerificationMeta(
    'avatarHash',
  );
  @override
  late final GeneratedColumn<String> avatarHash = GeneratedColumn<String>(
    'avatar_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _osMeta = const VerificationMeta('os');
  @override
  late final GeneratedColumn<String> os = GeneratedColumn<String>(
    'os',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> firstSeen =
      GeneratedColumn<int>(
        'first_seen',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DevicesTable.$converterfirstSeen);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> lastSeen =
      GeneratedColumn<int>(
        'last_seen',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DevicesTable.$converterlastSeen);
  static const VerificationMeta _onlineMeta = const VerificationMeta('online');
  @override
  late final GeneratedColumn<bool> online = GeneratedColumn<bool>(
    'online',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("online" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isSelfMeta = const VerificationMeta('isSelf');
  @override
  late final GeneratedColumn<bool> isSelf = GeneratedColumn<bool>(
    'is_self',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_self" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isGuestMeta = const VerificationMeta(
    'isGuest',
  );
  @override
  late final GeneratedColumn<bool> isGuest = GeneratedColumn<bool>(
    'is_guest',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_guest" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    peerId,
    pubkey,
    alg,
    name,
    avatarHash,
    os,
    firstSeen,
    lastSeen,
    online,
    isSelf,
    isGuest,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('alg')) {
      context.handle(
        _algMeta,
        alg.isAcceptableOrUnknown(data['alg']!, _algMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('avatar_hash')) {
      context.handle(
        _avatarHashMeta,
        avatarHash.isAcceptableOrUnknown(data['avatar_hash']!, _avatarHashMeta),
      );
    }
    if (data.containsKey('os')) {
      context.handle(_osMeta, os.isAcceptableOrUnknown(data['os']!, _osMeta));
    }
    if (data.containsKey('online')) {
      context.handle(
        _onlineMeta,
        online.isAcceptableOrUnknown(data['online']!, _onlineMeta),
      );
    }
    if (data.containsKey('is_self')) {
      context.handle(
        _isSelfMeta,
        isSelf.isAcceptableOrUnknown(data['is_self']!, _isSelfMeta),
      );
    }
    if (data.containsKey('is_guest')) {
      context.handle(
        _isGuestMeta,
        isGuest.isAcceptableOrUnknown(data['is_guest']!, _isGuestMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerId};
  @override
  DeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceRow(
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}pubkey'],
      )!,
      alg: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alg'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatarHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_hash'],
      )!,
      os: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}os'],
      )!,
      firstSeen: $DevicesTable.$converterfirstSeen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}first_seen'],
        )!,
      ),
      lastSeen: $DevicesTable.$converterlastSeen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_seen'],
        )!,
      ),
      online: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}online'],
      )!,
      isSelf: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_self'],
      )!,
      isGuest: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_guest'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterfirstSeen =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterlastSeen =
      const UnixMillisConverter();
}

class DeviceRow extends DataClass implements Insertable<DeviceRow> {
  final String peerId;

  /// 裸 Ed25519 公钥（32 字节）。
  final Uint8List pubkey;

  /// 签名算法标识；v1 固定 ed25519。
  final String alg;
  final String name;
  final String avatarHash;
  final String os;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final bool online;
  final bool isSelf;
  final bool isGuest;
  final String note;
  const DeviceRow({
    required this.peerId,
    required this.pubkey,
    required this.alg,
    required this.name,
    required this.avatarHash,
    required this.os,
    required this.firstSeen,
    required this.lastSeen,
    required this.online,
    required this.isSelf,
    required this.isGuest,
    required this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_id'] = Variable<String>(peerId);
    map['pubkey'] = Variable<Uint8List>(pubkey);
    map['alg'] = Variable<String>(alg);
    map['name'] = Variable<String>(name);
    map['avatar_hash'] = Variable<String>(avatarHash);
    map['os'] = Variable<String>(os);
    {
      map['first_seen'] = Variable<int>(
        $DevicesTable.$converterfirstSeen.toSql(firstSeen),
      );
    }
    {
      map['last_seen'] = Variable<int>(
        $DevicesTable.$converterlastSeen.toSql(lastSeen),
      );
    }
    map['online'] = Variable<bool>(online);
    map['is_self'] = Variable<bool>(isSelf);
    map['is_guest'] = Variable<bool>(isGuest);
    map['note'] = Variable<String>(note);
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      peerId: Value(peerId),
      pubkey: Value(pubkey),
      alg: Value(alg),
      name: Value(name),
      avatarHash: Value(avatarHash),
      os: Value(os),
      firstSeen: Value(firstSeen),
      lastSeen: Value(lastSeen),
      online: Value(online),
      isSelf: Value(isSelf),
      isGuest: Value(isGuest),
      note: Value(note),
    );
  }

  factory DeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceRow(
      peerId: serializer.fromJson<String>(json['peerId']),
      pubkey: serializer.fromJson<Uint8List>(json['pubkey']),
      alg: serializer.fromJson<String>(json['alg']),
      name: serializer.fromJson<String>(json['name']),
      avatarHash: serializer.fromJson<String>(json['avatarHash']),
      os: serializer.fromJson<String>(json['os']),
      firstSeen: serializer.fromJson<DateTime>(json['firstSeen']),
      lastSeen: serializer.fromJson<DateTime>(json['lastSeen']),
      online: serializer.fromJson<bool>(json['online']),
      isSelf: serializer.fromJson<bool>(json['isSelf']),
      isGuest: serializer.fromJson<bool>(json['isGuest']),
      note: serializer.fromJson<String>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerId': serializer.toJson<String>(peerId),
      'pubkey': serializer.toJson<Uint8List>(pubkey),
      'alg': serializer.toJson<String>(alg),
      'name': serializer.toJson<String>(name),
      'avatarHash': serializer.toJson<String>(avatarHash),
      'os': serializer.toJson<String>(os),
      'firstSeen': serializer.toJson<DateTime>(firstSeen),
      'lastSeen': serializer.toJson<DateTime>(lastSeen),
      'online': serializer.toJson<bool>(online),
      'isSelf': serializer.toJson<bool>(isSelf),
      'isGuest': serializer.toJson<bool>(isGuest),
      'note': serializer.toJson<String>(note),
    };
  }

  DeviceRow copyWith({
    String? peerId,
    Uint8List? pubkey,
    String? alg,
    String? name,
    String? avatarHash,
    String? os,
    DateTime? firstSeen,
    DateTime? lastSeen,
    bool? online,
    bool? isSelf,
    bool? isGuest,
    String? note,
  }) => DeviceRow(
    peerId: peerId ?? this.peerId,
    pubkey: pubkey ?? this.pubkey,
    alg: alg ?? this.alg,
    name: name ?? this.name,
    avatarHash: avatarHash ?? this.avatarHash,
    os: os ?? this.os,
    firstSeen: firstSeen ?? this.firstSeen,
    lastSeen: lastSeen ?? this.lastSeen,
    online: online ?? this.online,
    isSelf: isSelf ?? this.isSelf,
    isGuest: isGuest ?? this.isGuest,
    note: note ?? this.note,
  );
  DeviceRow copyWithCompanion(DevicesCompanion data) {
    return DeviceRow(
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      alg: data.alg.present ? data.alg.value : this.alg,
      name: data.name.present ? data.name.value : this.name,
      avatarHash: data.avatarHash.present
          ? data.avatarHash.value
          : this.avatarHash,
      os: data.os.present ? data.os.value : this.os,
      firstSeen: data.firstSeen.present ? data.firstSeen.value : this.firstSeen,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      online: data.online.present ? data.online.value : this.online,
      isSelf: data.isSelf.present ? data.isSelf.value : this.isSelf,
      isGuest: data.isGuest.present ? data.isGuest.value : this.isGuest,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceRow(')
          ..write('peerId: $peerId, ')
          ..write('pubkey: $pubkey, ')
          ..write('alg: $alg, ')
          ..write('name: $name, ')
          ..write('avatarHash: $avatarHash, ')
          ..write('os: $os, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('online: $online, ')
          ..write('isSelf: $isSelf, ')
          ..write('isGuest: $isGuest, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    peerId,
    $driftBlobEquality.hash(pubkey),
    alg,
    name,
    avatarHash,
    os,
    firstSeen,
    lastSeen,
    online,
    isSelf,
    isGuest,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceRow &&
          other.peerId == this.peerId &&
          $driftBlobEquality.equals(other.pubkey, this.pubkey) &&
          other.alg == this.alg &&
          other.name == this.name &&
          other.avatarHash == this.avatarHash &&
          other.os == this.os &&
          other.firstSeen == this.firstSeen &&
          other.lastSeen == this.lastSeen &&
          other.online == this.online &&
          other.isSelf == this.isSelf &&
          other.isGuest == this.isGuest &&
          other.note == this.note);
}

class DevicesCompanion extends UpdateCompanion<DeviceRow> {
  final Value<String> peerId;
  final Value<Uint8List> pubkey;
  final Value<String> alg;
  final Value<String> name;
  final Value<String> avatarHash;
  final Value<String> os;
  final Value<DateTime> firstSeen;
  final Value<DateTime> lastSeen;
  final Value<bool> online;
  final Value<bool> isSelf;
  final Value<bool> isGuest;
  final Value<String> note;
  final Value<int> rowid;
  const DevicesCompanion({
    this.peerId = const Value.absent(),
    this.pubkey = const Value.absent(),
    this.alg = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarHash = const Value.absent(),
    this.os = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.online = const Value.absent(),
    this.isSelf = const Value.absent(),
    this.isGuest = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required String peerId,
    required Uint8List pubkey,
    this.alg = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarHash = const Value.absent(),
    this.os = const Value.absent(),
    required DateTime firstSeen,
    required DateTime lastSeen,
    this.online = const Value.absent(),
    this.isSelf = const Value.absent(),
    this.isGuest = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : peerId = Value(peerId),
       pubkey = Value(pubkey),
       firstSeen = Value(firstSeen),
       lastSeen = Value(lastSeen);
  static Insertable<DeviceRow> custom({
    Expression<String>? peerId,
    Expression<Uint8List>? pubkey,
    Expression<String>? alg,
    Expression<String>? name,
    Expression<String>? avatarHash,
    Expression<String>? os,
    Expression<int>? firstSeen,
    Expression<int>? lastSeen,
    Expression<bool>? online,
    Expression<bool>? isSelf,
    Expression<bool>? isGuest,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerId != null) 'peer_id': peerId,
      if (pubkey != null) 'pubkey': pubkey,
      if (alg != null) 'alg': alg,
      if (name != null) 'name': name,
      if (avatarHash != null) 'avatar_hash': avatarHash,
      if (os != null) 'os': os,
      if (firstSeen != null) 'first_seen': firstSeen,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (online != null) 'online': online,
      if (isSelf != null) 'is_self': isSelf,
      if (isGuest != null) 'is_guest': isGuest,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? peerId,
    Value<Uint8List>? pubkey,
    Value<String>? alg,
    Value<String>? name,
    Value<String>? avatarHash,
    Value<String>? os,
    Value<DateTime>? firstSeen,
    Value<DateTime>? lastSeen,
    Value<bool>? online,
    Value<bool>? isSelf,
    Value<bool>? isGuest,
    Value<String>? note,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      peerId: peerId ?? this.peerId,
      pubkey: pubkey ?? this.pubkey,
      alg: alg ?? this.alg,
      name: name ?? this.name,
      avatarHash: avatarHash ?? this.avatarHash,
      os: os ?? this.os,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      online: online ?? this.online,
      isSelf: isSelf ?? this.isSelf,
      isGuest: isGuest ?? this.isGuest,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (pubkey.present) {
      map['pubkey'] = Variable<Uint8List>(pubkey.value);
    }
    if (alg.present) {
      map['alg'] = Variable<String>(alg.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatarHash.present) {
      map['avatar_hash'] = Variable<String>(avatarHash.value);
    }
    if (os.present) {
      map['os'] = Variable<String>(os.value);
    }
    if (firstSeen.present) {
      map['first_seen'] = Variable<int>(
        $DevicesTable.$converterfirstSeen.toSql(firstSeen.value),
      );
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<int>(
        $DevicesTable.$converterlastSeen.toSql(lastSeen.value),
      );
    }
    if (online.present) {
      map['online'] = Variable<bool>(online.value);
    }
    if (isSelf.present) {
      map['is_self'] = Variable<bool>(isSelf.value);
    }
    if (isGuest.present) {
      map['is_guest'] = Variable<bool>(isGuest.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('peerId: $peerId, ')
          ..write('pubkey: $pubkey, ')
          ..write('alg: $alg, ')
          ..write('name: $name, ')
          ..write('avatarHash: $avatarHash, ')
          ..write('os: $os, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('online: $online, ')
          ..write('isSelf: $isSelf, ')
          ..write('isGuest: $isGuest, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SharesTable extends Shares with TableInfo<$SharesTable, ShareRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SharesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rootKindMeta = const VerificationMeta(
    'rootKind',
  );
  @override
  late final GeneratedColumn<String> rootKind = GeneratedColumn<String>(
    'root_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rootUriMeta = const VerificationMeta(
    'rootUri',
  );
  @override
  late final GeneratedColumn<String> rootUri = GeneratedColumn<String>(
    'root_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerPeerIdMeta = const VerificationMeta(
    'ownerPeerId',
  );
  @override
  late final GeneratedColumn<String> ownerPeerId = GeneratedColumn<String>(
    'owner_peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SharesTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> expiresAt =
      GeneratedColumn<int>(
        'expires_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($SharesTable.$converterexpiresAtn);
  @override
  late final GeneratedColumnWithTypeConverter<ShareMode, String> mode =
      GeneratedColumn<String>(
        'mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ShareMode>($SharesTable.$convertermode);
  static const VerificationMeta _passwordHashMeta = const VerificationMeta(
    'passwordHash',
  );
  @override
  late final GeneratedColumn<String> passwordHash = GeneratedColumn<String>(
    'password_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxSpeedKbpsMeta = const VerificationMeta(
    'maxSpeedKbps',
  );
  @override
  late final GeneratedColumn<int> maxSpeedKbps = GeneratedColumn<int>(
    'max_speed_kbps',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _missingMeta = const VerificationMeta(
    'missing',
  );
  @override
  late final GeneratedColumn<bool> missing = GeneratedColumn<bool>(
    'missing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("missing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> revokedAt =
      GeneratedColumn<int>(
        'revoked_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($SharesTable.$converterrevokedAtn);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isEphemeralMeta = const VerificationMeta(
    'isEphemeral',
  );
  @override
  late final GeneratedColumn<bool> isEphemeral = GeneratedColumn<bool>(
    'is_ephemeral',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_ephemeral" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    rootKind,
    rootUri,
    displayName,
    ownerPeerId,
    createdAt,
    expiresAt,
    mode,
    passwordHash,
    groupId,
    maxSpeedKbps,
    enabled,
    missing,
    revokedAt,
    sessionId,
    isEphemeral,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'share';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShareRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('root_kind')) {
      context.handle(
        _rootKindMeta,
        rootKind.isAcceptableOrUnknown(data['root_kind']!, _rootKindMeta),
      );
    } else if (isInserting) {
      context.missing(_rootKindMeta);
    }
    if (data.containsKey('root_uri')) {
      context.handle(
        _rootUriMeta,
        rootUri.isAcceptableOrUnknown(data['root_uri']!, _rootUriMeta),
      );
    } else if (isInserting) {
      context.missing(_rootUriMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('owner_peer_id')) {
      context.handle(
        _ownerPeerIdMeta,
        ownerPeerId.isAcceptableOrUnknown(
          data['owner_peer_id']!,
          _ownerPeerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerPeerIdMeta);
    }
    if (data.containsKey('password_hash')) {
      context.handle(
        _passwordHashMeta,
        passwordHash.isAcceptableOrUnknown(
          data['password_hash']!,
          _passwordHashMeta,
        ),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('max_speed_kbps')) {
      context.handle(
        _maxSpeedKbpsMeta,
        maxSpeedKbps.isAcceptableOrUnknown(
          data['max_speed_kbps']!,
          _maxSpeedKbpsMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('missing')) {
      context.handle(
        _missingMeta,
        missing.isAcceptableOrUnknown(data['missing']!, _missingMeta),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('is_ephemeral')) {
      context.handle(
        _isEphemeralMeta,
        isEphemeral.isAcceptableOrUnknown(
          data['is_ephemeral']!,
          _isEphemeralMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShareRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShareRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      rootKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root_kind'],
      )!,
      rootUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root_uri'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      ownerPeerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_peer_id'],
      )!,
      createdAt: $SharesTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      expiresAt: $SharesTable.$converterexpiresAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}expires_at'],
        ),
      ),
      mode: $SharesTable.$convertermode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mode'],
        )!,
      ),
      passwordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password_hash'],
      ),
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      maxSpeedKbps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_speed_kbps'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      missing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}missing'],
      )!,
      revokedAt: $SharesTable.$converterrevokedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}revoked_at'],
        ),
      ),
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      isEphemeral: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_ephemeral'],
      )!,
    );
  }

  @override
  $SharesTable createAlias(String alias) {
    return $SharesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertercreatedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterexpiresAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converterexpiresAtn =
      NullAwareTypeConverter.wrap($converterexpiresAt);
  static JsonTypeConverter2<ShareMode, String, String> $convertermode =
      const EnumNameConverter<ShareMode>(ShareMode.values);
  static TypeConverter<DateTime, int> $converterrevokedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converterrevokedAtn =
      NullAwareTypeConverter.wrap($converterrevokedAt);
}

class ShareRow extends DataClass implements Insertable<ShareRow> {
  final String id;

  /// folder 或 file。
  final String kind;
  final String rootKind;
  final String rootUri;
  final String displayName;
  final String ownerPeerId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final ShareMode mode;
  final String? passwordHash;
  final String? groupId;
  final int? maxSpeedKbps;
  final bool enabled;
  final bool missing;
  final DateTime? revokedAt;

  /// 网页会话分享绑定的 guest 会话 id。
  final String? sessionId;

  /// 是否随会话失效：网页会话分享为 true。
  final bool isEphemeral;
  const ShareRow({
    required this.id,
    required this.kind,
    required this.rootKind,
    required this.rootUri,
    required this.displayName,
    required this.ownerPeerId,
    required this.createdAt,
    this.expiresAt,
    required this.mode,
    this.passwordHash,
    this.groupId,
    this.maxSpeedKbps,
    required this.enabled,
    required this.missing,
    this.revokedAt,
    this.sessionId,
    required this.isEphemeral,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['root_kind'] = Variable<String>(rootKind);
    map['root_uri'] = Variable<String>(rootUri);
    map['display_name'] = Variable<String>(displayName);
    map['owner_peer_id'] = Variable<String>(ownerPeerId);
    {
      map['created_at'] = Variable<int>(
        $SharesTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<int>(
        $SharesTable.$converterexpiresAtn.toSql(expiresAt),
      );
    }
    {
      map['mode'] = Variable<String>($SharesTable.$convertermode.toSql(mode));
    }
    if (!nullToAbsent || passwordHash != null) {
      map['password_hash'] = Variable<String>(passwordHash);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    if (!nullToAbsent || maxSpeedKbps != null) {
      map['max_speed_kbps'] = Variable<int>(maxSpeedKbps);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['missing'] = Variable<bool>(missing);
    if (!nullToAbsent || revokedAt != null) {
      map['revoked_at'] = Variable<int>(
        $SharesTable.$converterrevokedAtn.toSql(revokedAt),
      );
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['is_ephemeral'] = Variable<bool>(isEphemeral);
    return map;
  }

  SharesCompanion toCompanion(bool nullToAbsent) {
    return SharesCompanion(
      id: Value(id),
      kind: Value(kind),
      rootKind: Value(rootKind),
      rootUri: Value(rootUri),
      displayName: Value(displayName),
      ownerPeerId: Value(ownerPeerId),
      createdAt: Value(createdAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      mode: Value(mode),
      passwordHash: passwordHash == null && nullToAbsent
          ? const Value.absent()
          : Value(passwordHash),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      maxSpeedKbps: maxSpeedKbps == null && nullToAbsent
          ? const Value.absent()
          : Value(maxSpeedKbps),
      enabled: Value(enabled),
      missing: Value(missing),
      revokedAt: revokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(revokedAt),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      isEphemeral: Value(isEphemeral),
    );
  }

  factory ShareRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShareRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      rootKind: serializer.fromJson<String>(json['rootKind']),
      rootUri: serializer.fromJson<String>(json['rootUri']),
      displayName: serializer.fromJson<String>(json['displayName']),
      ownerPeerId: serializer.fromJson<String>(json['ownerPeerId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      mode: $SharesTable.$convertermode.fromJson(
        serializer.fromJson<String>(json['mode']),
      ),
      passwordHash: serializer.fromJson<String?>(json['passwordHash']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      maxSpeedKbps: serializer.fromJson<int?>(json['maxSpeedKbps']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      missing: serializer.fromJson<bool>(json['missing']),
      revokedAt: serializer.fromJson<DateTime?>(json['revokedAt']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      isEphemeral: serializer.fromJson<bool>(json['isEphemeral']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'rootKind': serializer.toJson<String>(rootKind),
      'rootUri': serializer.toJson<String>(rootUri),
      'displayName': serializer.toJson<String>(displayName),
      'ownerPeerId': serializer.toJson<String>(ownerPeerId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'mode': serializer.toJson<String>(
        $SharesTable.$convertermode.toJson(mode),
      ),
      'passwordHash': serializer.toJson<String?>(passwordHash),
      'groupId': serializer.toJson<String?>(groupId),
      'maxSpeedKbps': serializer.toJson<int?>(maxSpeedKbps),
      'enabled': serializer.toJson<bool>(enabled),
      'missing': serializer.toJson<bool>(missing),
      'revokedAt': serializer.toJson<DateTime?>(revokedAt),
      'sessionId': serializer.toJson<String?>(sessionId),
      'isEphemeral': serializer.toJson<bool>(isEphemeral),
    };
  }

  ShareRow copyWith({
    String? id,
    String? kind,
    String? rootKind,
    String? rootUri,
    String? displayName,
    String? ownerPeerId,
    DateTime? createdAt,
    Value<DateTime?> expiresAt = const Value.absent(),
    ShareMode? mode,
    Value<String?> passwordHash = const Value.absent(),
    Value<String?> groupId = const Value.absent(),
    Value<int?> maxSpeedKbps = const Value.absent(),
    bool? enabled,
    bool? missing,
    Value<DateTime?> revokedAt = const Value.absent(),
    Value<String?> sessionId = const Value.absent(),
    bool? isEphemeral,
  }) => ShareRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    rootKind: rootKind ?? this.rootKind,
    rootUri: rootUri ?? this.rootUri,
    displayName: displayName ?? this.displayName,
    ownerPeerId: ownerPeerId ?? this.ownerPeerId,
    createdAt: createdAt ?? this.createdAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    mode: mode ?? this.mode,
    passwordHash: passwordHash.present ? passwordHash.value : this.passwordHash,
    groupId: groupId.present ? groupId.value : this.groupId,
    maxSpeedKbps: maxSpeedKbps.present ? maxSpeedKbps.value : this.maxSpeedKbps,
    enabled: enabled ?? this.enabled,
    missing: missing ?? this.missing,
    revokedAt: revokedAt.present ? revokedAt.value : this.revokedAt,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    isEphemeral: isEphemeral ?? this.isEphemeral,
  );
  ShareRow copyWithCompanion(SharesCompanion data) {
    return ShareRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      rootKind: data.rootKind.present ? data.rootKind.value : this.rootKind,
      rootUri: data.rootUri.present ? data.rootUri.value : this.rootUri,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      ownerPeerId: data.ownerPeerId.present
          ? data.ownerPeerId.value
          : this.ownerPeerId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      mode: data.mode.present ? data.mode.value : this.mode,
      passwordHash: data.passwordHash.present
          ? data.passwordHash.value
          : this.passwordHash,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      maxSpeedKbps: data.maxSpeedKbps.present
          ? data.maxSpeedKbps.value
          : this.maxSpeedKbps,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      missing: data.missing.present ? data.missing.value : this.missing,
      revokedAt: data.revokedAt.present ? data.revokedAt.value : this.revokedAt,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      isEphemeral: data.isEphemeral.present
          ? data.isEphemeral.value
          : this.isEphemeral,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShareRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('rootKind: $rootKind, ')
          ..write('rootUri: $rootUri, ')
          ..write('displayName: $displayName, ')
          ..write('ownerPeerId: $ownerPeerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('mode: $mode, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('groupId: $groupId, ')
          ..write('maxSpeedKbps: $maxSpeedKbps, ')
          ..write('enabled: $enabled, ')
          ..write('missing: $missing, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('sessionId: $sessionId, ')
          ..write('isEphemeral: $isEphemeral')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    rootKind,
    rootUri,
    displayName,
    ownerPeerId,
    createdAt,
    expiresAt,
    mode,
    passwordHash,
    groupId,
    maxSpeedKbps,
    enabled,
    missing,
    revokedAt,
    sessionId,
    isEphemeral,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShareRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.rootKind == this.rootKind &&
          other.rootUri == this.rootUri &&
          other.displayName == this.displayName &&
          other.ownerPeerId == this.ownerPeerId &&
          other.createdAt == this.createdAt &&
          other.expiresAt == this.expiresAt &&
          other.mode == this.mode &&
          other.passwordHash == this.passwordHash &&
          other.groupId == this.groupId &&
          other.maxSpeedKbps == this.maxSpeedKbps &&
          other.enabled == this.enabled &&
          other.missing == this.missing &&
          other.revokedAt == this.revokedAt &&
          other.sessionId == this.sessionId &&
          other.isEphemeral == this.isEphemeral);
}

class SharesCompanion extends UpdateCompanion<ShareRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> rootKind;
  final Value<String> rootUri;
  final Value<String> displayName;
  final Value<String> ownerPeerId;
  final Value<DateTime> createdAt;
  final Value<DateTime?> expiresAt;
  final Value<ShareMode> mode;
  final Value<String?> passwordHash;
  final Value<String?> groupId;
  final Value<int?> maxSpeedKbps;
  final Value<bool> enabled;
  final Value<bool> missing;
  final Value<DateTime?> revokedAt;
  final Value<String?> sessionId;
  final Value<bool> isEphemeral;
  final Value<int> rowid;
  const SharesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.rootKind = const Value.absent(),
    this.rootUri = const Value.absent(),
    this.displayName = const Value.absent(),
    this.ownerPeerId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.mode = const Value.absent(),
    this.passwordHash = const Value.absent(),
    this.groupId = const Value.absent(),
    this.maxSpeedKbps = const Value.absent(),
    this.enabled = const Value.absent(),
    this.missing = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.isEphemeral = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SharesCompanion.insert({
    required String id,
    required String kind,
    required String rootKind,
    required String rootUri,
    required String displayName,
    required String ownerPeerId,
    required DateTime createdAt,
    this.expiresAt = const Value.absent(),
    required ShareMode mode,
    this.passwordHash = const Value.absent(),
    this.groupId = const Value.absent(),
    this.maxSpeedKbps = const Value.absent(),
    this.enabled = const Value.absent(),
    this.missing = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.isEphemeral = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       rootKind = Value(rootKind),
       rootUri = Value(rootUri),
       displayName = Value(displayName),
       ownerPeerId = Value(ownerPeerId),
       createdAt = Value(createdAt),
       mode = Value(mode);
  static Insertable<ShareRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? rootKind,
    Expression<String>? rootUri,
    Expression<String>? displayName,
    Expression<String>? ownerPeerId,
    Expression<int>? createdAt,
    Expression<int>? expiresAt,
    Expression<String>? mode,
    Expression<String>? passwordHash,
    Expression<String>? groupId,
    Expression<int>? maxSpeedKbps,
    Expression<bool>? enabled,
    Expression<bool>? missing,
    Expression<int>? revokedAt,
    Expression<String>? sessionId,
    Expression<bool>? isEphemeral,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (rootKind != null) 'root_kind': rootKind,
      if (rootUri != null) 'root_uri': rootUri,
      if (displayName != null) 'display_name': displayName,
      if (ownerPeerId != null) 'owner_peer_id': ownerPeerId,
      if (createdAt != null) 'created_at': createdAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (mode != null) 'mode': mode,
      if (passwordHash != null) 'password_hash': passwordHash,
      if (groupId != null) 'group_id': groupId,
      if (maxSpeedKbps != null) 'max_speed_kbps': maxSpeedKbps,
      if (enabled != null) 'enabled': enabled,
      if (missing != null) 'missing': missing,
      if (revokedAt != null) 'revoked_at': revokedAt,
      if (sessionId != null) 'session_id': sessionId,
      if (isEphemeral != null) 'is_ephemeral': isEphemeral,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SharesCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? rootKind,
    Value<String>? rootUri,
    Value<String>? displayName,
    Value<String>? ownerPeerId,
    Value<DateTime>? createdAt,
    Value<DateTime?>? expiresAt,
    Value<ShareMode>? mode,
    Value<String?>? passwordHash,
    Value<String?>? groupId,
    Value<int?>? maxSpeedKbps,
    Value<bool>? enabled,
    Value<bool>? missing,
    Value<DateTime?>? revokedAt,
    Value<String?>? sessionId,
    Value<bool>? isEphemeral,
    Value<int>? rowid,
  }) {
    return SharesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      rootKind: rootKind ?? this.rootKind,
      rootUri: rootUri ?? this.rootUri,
      displayName: displayName ?? this.displayName,
      ownerPeerId: ownerPeerId ?? this.ownerPeerId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      mode: mode ?? this.mode,
      passwordHash: passwordHash ?? this.passwordHash,
      groupId: groupId ?? this.groupId,
      maxSpeedKbps: maxSpeedKbps ?? this.maxSpeedKbps,
      enabled: enabled ?? this.enabled,
      missing: missing ?? this.missing,
      revokedAt: revokedAt ?? this.revokedAt,
      sessionId: sessionId ?? this.sessionId,
      isEphemeral: isEphemeral ?? this.isEphemeral,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rootKind.present) {
      map['root_kind'] = Variable<String>(rootKind.value);
    }
    if (rootUri.present) {
      map['root_uri'] = Variable<String>(rootUri.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (ownerPeerId.present) {
      map['owner_peer_id'] = Variable<String>(ownerPeerId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $SharesTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(
        $SharesTable.$converterexpiresAtn.toSql(expiresAt.value),
      );
    }
    if (mode.present) {
      map['mode'] = Variable<String>(
        $SharesTable.$convertermode.toSql(mode.value),
      );
    }
    if (passwordHash.present) {
      map['password_hash'] = Variable<String>(passwordHash.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (maxSpeedKbps.present) {
      map['max_speed_kbps'] = Variable<int>(maxSpeedKbps.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (missing.present) {
      map['missing'] = Variable<bool>(missing.value);
    }
    if (revokedAt.present) {
      map['revoked_at'] = Variable<int>(
        $SharesTable.$converterrevokedAtn.toSql(revokedAt.value),
      );
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (isEphemeral.present) {
      map['is_ephemeral'] = Variable<bool>(isEphemeral.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SharesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('rootKind: $rootKind, ')
          ..write('rootUri: $rootUri, ')
          ..write('displayName: $displayName, ')
          ..write('ownerPeerId: $ownerPeerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('mode: $mode, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('groupId: $groupId, ')
          ..write('maxSpeedKbps: $maxSpeedKbps, ')
          ..write('enabled: $enabled, ')
          ..write('missing: $missing, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('sessionId: $sessionId, ')
          ..write('isEphemeral: $isEphemeral, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShareItemsTable extends ShareItems
    with TableInfo<$ShareItemsTable, ShareItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShareItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _shareIdMeta = const VerificationMeta(
    'shareId',
  );
  @override
  late final GeneratedColumn<String> shareId = GeneratedColumn<String>(
    'share_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES share (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _itemKeyMeta = const VerificationMeta(
    'itemKey',
  );
  @override
  late final GeneratedColumn<String> itemKey = GeneratedColumn<String>(
    'item_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relPathMeta = const VerificationMeta(
    'relPath',
  );
  @override
  late final GeneratedColumn<String> relPath = GeneratedColumn<String>(
    'rel_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> mtime =
      GeneratedColumn<int>(
        'mtime',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($ShareItemsTable.$convertermtimen);
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDirMeta = const VerificationMeta('isDir');
  @override
  late final GeneratedColumn<bool> isDir = GeneratedColumn<bool>(
    'is_dir',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dir" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    shareId,
    itemKey,
    relPath,
    size,
    mtime,
    mime,
    isDir,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'share_item';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShareItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('share_id')) {
      context.handle(
        _shareIdMeta,
        shareId.isAcceptableOrUnknown(data['share_id']!, _shareIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shareIdMeta);
    }
    if (data.containsKey('item_key')) {
      context.handle(
        _itemKeyMeta,
        itemKey.isAcceptableOrUnknown(data['item_key']!, _itemKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_itemKeyMeta);
    }
    if (data.containsKey('rel_path')) {
      context.handle(
        _relPathMeta,
        relPath.isAcceptableOrUnknown(data['rel_path']!, _relPathMeta),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    }
    if (data.containsKey('is_dir')) {
      context.handle(
        _isDirMeta,
        isDir.isAcceptableOrUnknown(data['is_dir']!, _isDirMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {shareId, itemKey};
  @override
  ShareItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShareItemRow(
      shareId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}share_id'],
      )!,
      itemKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_key'],
      )!,
      relPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rel_path'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      mtime: $ShareItemsTable.$convertermtimen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}mtime'],
        ),
      ),
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      ),
      isDir: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dir'],
      )!,
    );
  }

  @override
  $ShareItemsTable createAlias(String alias) {
    return $ShareItemsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertermtime =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $convertermtimen =
      NullAwareTypeConverter.wrap($convertermtime);
}

class ShareItemRow extends DataClass implements Insertable<ShareItemRow> {
  final String shareId;
  final String itemKey;

  /// 相对 root 的路径投影，与 itemKey 同源，供按路径前缀查询。
  final String relPath;
  final int size;
  final DateTime? mtime;
  final String? mime;
  final bool isDir;
  const ShareItemRow({
    required this.shareId,
    required this.itemKey,
    required this.relPath,
    required this.size,
    this.mtime,
    this.mime,
    required this.isDir,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['share_id'] = Variable<String>(shareId);
    map['item_key'] = Variable<String>(itemKey);
    map['rel_path'] = Variable<String>(relPath);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || mtime != null) {
      map['mtime'] = Variable<int>(
        $ShareItemsTable.$convertermtimen.toSql(mtime),
      );
    }
    if (!nullToAbsent || mime != null) {
      map['mime'] = Variable<String>(mime);
    }
    map['is_dir'] = Variable<bool>(isDir);
    return map;
  }

  ShareItemsCompanion toCompanion(bool nullToAbsent) {
    return ShareItemsCompanion(
      shareId: Value(shareId),
      itemKey: Value(itemKey),
      relPath: Value(relPath),
      size: Value(size),
      mtime: mtime == null && nullToAbsent
          ? const Value.absent()
          : Value(mtime),
      mime: mime == null && nullToAbsent ? const Value.absent() : Value(mime),
      isDir: Value(isDir),
    );
  }

  factory ShareItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShareItemRow(
      shareId: serializer.fromJson<String>(json['shareId']),
      itemKey: serializer.fromJson<String>(json['itemKey']),
      relPath: serializer.fromJson<String>(json['relPath']),
      size: serializer.fromJson<int>(json['size']),
      mtime: serializer.fromJson<DateTime?>(json['mtime']),
      mime: serializer.fromJson<String?>(json['mime']),
      isDir: serializer.fromJson<bool>(json['isDir']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'shareId': serializer.toJson<String>(shareId),
      'itemKey': serializer.toJson<String>(itemKey),
      'relPath': serializer.toJson<String>(relPath),
      'size': serializer.toJson<int>(size),
      'mtime': serializer.toJson<DateTime?>(mtime),
      'mime': serializer.toJson<String?>(mime),
      'isDir': serializer.toJson<bool>(isDir),
    };
  }

  ShareItemRow copyWith({
    String? shareId,
    String? itemKey,
    String? relPath,
    int? size,
    Value<DateTime?> mtime = const Value.absent(),
    Value<String?> mime = const Value.absent(),
    bool? isDir,
  }) => ShareItemRow(
    shareId: shareId ?? this.shareId,
    itemKey: itemKey ?? this.itemKey,
    relPath: relPath ?? this.relPath,
    size: size ?? this.size,
    mtime: mtime.present ? mtime.value : this.mtime,
    mime: mime.present ? mime.value : this.mime,
    isDir: isDir ?? this.isDir,
  );
  ShareItemRow copyWithCompanion(ShareItemsCompanion data) {
    return ShareItemRow(
      shareId: data.shareId.present ? data.shareId.value : this.shareId,
      itemKey: data.itemKey.present ? data.itemKey.value : this.itemKey,
      relPath: data.relPath.present ? data.relPath.value : this.relPath,
      size: data.size.present ? data.size.value : this.size,
      mtime: data.mtime.present ? data.mtime.value : this.mtime,
      mime: data.mime.present ? data.mime.value : this.mime,
      isDir: data.isDir.present ? data.isDir.value : this.isDir,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShareItemRow(')
          ..write('shareId: $shareId, ')
          ..write('itemKey: $itemKey, ')
          ..write('relPath: $relPath, ')
          ..write('size: $size, ')
          ..write('mtime: $mtime, ')
          ..write('mime: $mime, ')
          ..write('isDir: $isDir')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(shareId, itemKey, relPath, size, mtime, mime, isDir);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShareItemRow &&
          other.shareId == this.shareId &&
          other.itemKey == this.itemKey &&
          other.relPath == this.relPath &&
          other.size == this.size &&
          other.mtime == this.mtime &&
          other.mime == this.mime &&
          other.isDir == this.isDir);
}

class ShareItemsCompanion extends UpdateCompanion<ShareItemRow> {
  final Value<String> shareId;
  final Value<String> itemKey;
  final Value<String> relPath;
  final Value<int> size;
  final Value<DateTime?> mtime;
  final Value<String?> mime;
  final Value<bool> isDir;
  final Value<int> rowid;
  const ShareItemsCompanion({
    this.shareId = const Value.absent(),
    this.itemKey = const Value.absent(),
    this.relPath = const Value.absent(),
    this.size = const Value.absent(),
    this.mtime = const Value.absent(),
    this.mime = const Value.absent(),
    this.isDir = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShareItemsCompanion.insert({
    required String shareId,
    required String itemKey,
    this.relPath = const Value.absent(),
    this.size = const Value.absent(),
    this.mtime = const Value.absent(),
    this.mime = const Value.absent(),
    this.isDir = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : shareId = Value(shareId),
       itemKey = Value(itemKey);
  static Insertable<ShareItemRow> custom({
    Expression<String>? shareId,
    Expression<String>? itemKey,
    Expression<String>? relPath,
    Expression<int>? size,
    Expression<int>? mtime,
    Expression<String>? mime,
    Expression<bool>? isDir,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (shareId != null) 'share_id': shareId,
      if (itemKey != null) 'item_key': itemKey,
      if (relPath != null) 'rel_path': relPath,
      if (size != null) 'size': size,
      if (mtime != null) 'mtime': mtime,
      if (mime != null) 'mime': mime,
      if (isDir != null) 'is_dir': isDir,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShareItemsCompanion copyWith({
    Value<String>? shareId,
    Value<String>? itemKey,
    Value<String>? relPath,
    Value<int>? size,
    Value<DateTime?>? mtime,
    Value<String?>? mime,
    Value<bool>? isDir,
    Value<int>? rowid,
  }) {
    return ShareItemsCompanion(
      shareId: shareId ?? this.shareId,
      itemKey: itemKey ?? this.itemKey,
      relPath: relPath ?? this.relPath,
      size: size ?? this.size,
      mtime: mtime ?? this.mtime,
      mime: mime ?? this.mime,
      isDir: isDir ?? this.isDir,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (shareId.present) {
      map['share_id'] = Variable<String>(shareId.value);
    }
    if (itemKey.present) {
      map['item_key'] = Variable<String>(itemKey.value);
    }
    if (relPath.present) {
      map['rel_path'] = Variable<String>(relPath.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (mtime.present) {
      map['mtime'] = Variable<int>(
        $ShareItemsTable.$convertermtimen.toSql(mtime.value),
      );
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (isDir.present) {
      map['is_dir'] = Variable<bool>(isDir.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShareItemsCompanion(')
          ..write('shareId: $shareId, ')
          ..write('itemKey: $itemKey, ')
          ..write('relPath: $relPath, ')
          ..write('size: $size, ')
          ..write('mtime: $mtime, ')
          ..write('mime: $mime, ')
          ..write('isDir: $isDir, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GrantsTable extends Grants with TableInfo<$GrantsTable, GrantRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GrantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _shareIdMeta = const VerificationMeta(
    'shareId',
  );
  @override
  late final GeneratedColumn<String> shareId = GeneratedColumn<String>(
    'share_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES share (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> grantedAt =
      GeneratedColumn<int>(
        'granted_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($GrantsTable.$convertergrantedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> expiresAt =
      GeneratedColumn<int>(
        'expires_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($GrantsTable.$converterexpiresAtn);
  @override
  List<GeneratedColumn> get $columns => [shareId, peerId, grantedAt, expiresAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'grant';
  @override
  VerificationContext validateIntegrity(
    Insertable<GrantRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('share_id')) {
      context.handle(
        _shareIdMeta,
        shareId.isAcceptableOrUnknown(data['share_id']!, _shareIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shareIdMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {shareId, peerId};
  @override
  GrantRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GrantRow(
      shareId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}share_id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      grantedAt: $GrantsTable.$convertergrantedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}granted_at'],
        )!,
      ),
      expiresAt: $GrantsTable.$converterexpiresAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}expires_at'],
        ),
      ),
    );
  }

  @override
  $GrantsTable createAlias(String alias) {
    return $GrantsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertergrantedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterexpiresAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converterexpiresAtn =
      NullAwareTypeConverter.wrap($converterexpiresAt);
}

class GrantRow extends DataClass implements Insertable<GrantRow> {
  final String shareId;
  final String peerId;
  final DateTime grantedAt;
  final DateTime? expiresAt;
  const GrantRow({
    required this.shareId,
    required this.peerId,
    required this.grantedAt,
    this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['share_id'] = Variable<String>(shareId);
    map['peer_id'] = Variable<String>(peerId);
    {
      map['granted_at'] = Variable<int>(
        $GrantsTable.$convertergrantedAt.toSql(grantedAt),
      );
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<int>(
        $GrantsTable.$converterexpiresAtn.toSql(expiresAt),
      );
    }
    return map;
  }

  GrantsCompanion toCompanion(bool nullToAbsent) {
    return GrantsCompanion(
      shareId: Value(shareId),
      peerId: Value(peerId),
      grantedAt: Value(grantedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
    );
  }

  factory GrantRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GrantRow(
      shareId: serializer.fromJson<String>(json['shareId']),
      peerId: serializer.fromJson<String>(json['peerId']),
      grantedAt: serializer.fromJson<DateTime>(json['grantedAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'shareId': serializer.toJson<String>(shareId),
      'peerId': serializer.toJson<String>(peerId),
      'grantedAt': serializer.toJson<DateTime>(grantedAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
    };
  }

  GrantRow copyWith({
    String? shareId,
    String? peerId,
    DateTime? grantedAt,
    Value<DateTime?> expiresAt = const Value.absent(),
  }) => GrantRow(
    shareId: shareId ?? this.shareId,
    peerId: peerId ?? this.peerId,
    grantedAt: grantedAt ?? this.grantedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
  );
  GrantRow copyWithCompanion(GrantsCompanion data) {
    return GrantRow(
      shareId: data.shareId.present ? data.shareId.value : this.shareId,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      grantedAt: data.grantedAt.present ? data.grantedAt.value : this.grantedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GrantRow(')
          ..write('shareId: $shareId, ')
          ..write('peerId: $peerId, ')
          ..write('grantedAt: $grantedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(shareId, peerId, grantedAt, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GrantRow &&
          other.shareId == this.shareId &&
          other.peerId == this.peerId &&
          other.grantedAt == this.grantedAt &&
          other.expiresAt == this.expiresAt);
}

class GrantsCompanion extends UpdateCompanion<GrantRow> {
  final Value<String> shareId;
  final Value<String> peerId;
  final Value<DateTime> grantedAt;
  final Value<DateTime?> expiresAt;
  final Value<int> rowid;
  const GrantsCompanion({
    this.shareId = const Value.absent(),
    this.peerId = const Value.absent(),
    this.grantedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GrantsCompanion.insert({
    required String shareId,
    required String peerId,
    required DateTime grantedAt,
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : shareId = Value(shareId),
       peerId = Value(peerId),
       grantedAt = Value(grantedAt);
  static Insertable<GrantRow> custom({
    Expression<String>? shareId,
    Expression<String>? peerId,
    Expression<int>? grantedAt,
    Expression<int>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (shareId != null) 'share_id': shareId,
      if (peerId != null) 'peer_id': peerId,
      if (grantedAt != null) 'granted_at': grantedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GrantsCompanion copyWith({
    Value<String>? shareId,
    Value<String>? peerId,
    Value<DateTime>? grantedAt,
    Value<DateTime?>? expiresAt,
    Value<int>? rowid,
  }) {
    return GrantsCompanion(
      shareId: shareId ?? this.shareId,
      peerId: peerId ?? this.peerId,
      grantedAt: grantedAt ?? this.grantedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (shareId.present) {
      map['share_id'] = Variable<String>(shareId.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (grantedAt.present) {
      map['granted_at'] = Variable<int>(
        $GrantsTable.$convertergrantedAt.toSql(grantedAt.value),
      );
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(
        $GrantsTable.$converterexpiresAtn.toSql(expiresAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GrantsCompanion(')
          ..write('shareId: $shareId, ')
          ..write('peerId: $peerId, ')
          ..write('grantedAt: $grantedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ThreadsTable extends Threads with TableInfo<$ThreadsTable, ThreadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThreadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _avatarHashMeta = const VerificationMeta(
    'avatarHash',
  );
  @override
  late final GeneratedColumn<String> avatarHash = GeneratedColumn<String>(
    'avatar_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMsgHlcMeta = const VerificationMeta(
    'lastMsgHlc',
  );
  @override
  late final GeneratedColumn<String> lastMsgHlc = GeneratedColumn<String>(
    'last_msg_hlc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMsgPreviewMeta = const VerificationMeta(
    'lastMsgPreview',
  );
  @override
  late final GeneratedColumn<String> lastMsgPreview = GeneratedColumn<String>(
    'last_msg_preview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unreadMeta = const VerificationMeta('unread');
  @override
  late final GeneratedColumn<int> unread = GeneratedColumn<int>(
    'unread',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mutedMeta = const VerificationMeta('muted');
  @override
  late final GeneratedColumn<bool> muted = GeneratedColumn<bool>(
    'muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("muted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($ThreadsTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> deletedAt =
      GeneratedColumn<int>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($ThreadsTable.$converterdeletedAtn);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    title,
    avatarHash,
    peerId,
    groupId,
    lastMsgHlc,
    lastMsgPreview,
    unread,
    muted,
    pinned,
    createdAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'thread';
  @override
  VerificationContext validateIntegrity(
    Insertable<ThreadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('avatar_hash')) {
      context.handle(
        _avatarHashMeta,
        avatarHash.isAcceptableOrUnknown(data['avatar_hash']!, _avatarHashMeta),
      );
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('last_msg_hlc')) {
      context.handle(
        _lastMsgHlcMeta,
        lastMsgHlc.isAcceptableOrUnknown(
          data['last_msg_hlc']!,
          _lastMsgHlcMeta,
        ),
      );
    }
    if (data.containsKey('last_msg_preview')) {
      context.handle(
        _lastMsgPreviewMeta,
        lastMsgPreview.isAcceptableOrUnknown(
          data['last_msg_preview']!,
          _lastMsgPreviewMeta,
        ),
      );
    }
    if (data.containsKey('unread')) {
      context.handle(
        _unreadMeta,
        unread.isAcceptableOrUnknown(data['unread']!, _unreadMeta),
      );
    }
    if (data.containsKey('muted')) {
      context.handle(
        _mutedMeta,
        muted.isAcceptableOrUnknown(data['muted']!, _mutedMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ThreadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThreadRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      avatarHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_hash'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      ),
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      lastMsgHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_msg_hlc'],
      ),
      lastMsgPreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_msg_preview'],
      ),
      unread: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread'],
      )!,
      muted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}muted'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      createdAt: $ThreadsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      deletedAt: $ThreadsTable.$converterdeletedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
    );
  }

  @override
  $ThreadsTable createAlias(String alias) {
    return $ThreadsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertercreatedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterdeletedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converterdeletedAtn =
      NullAwareTypeConverter.wrap($converterdeletedAt);
}

class ThreadRow extends DataClass implements Insertable<ThreadRow> {
  final String id;

  /// direct 或 group。
  final String kind;
  final String title;
  final String avatarHash;
  final String? peerId;
  final String? groupId;
  final String? lastMsgHlc;
  final String? lastMsgPreview;
  final int unread;
  final bool muted;
  final bool pinned;
  final DateTime createdAt;
  final DateTime? deletedAt;
  const ThreadRow({
    required this.id,
    required this.kind,
    required this.title,
    required this.avatarHash,
    this.peerId,
    this.groupId,
    this.lastMsgHlc,
    this.lastMsgPreview,
    required this.unread,
    required this.muted,
    required this.pinned,
    required this.createdAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['title'] = Variable<String>(title);
    map['avatar_hash'] = Variable<String>(avatarHash);
    if (!nullToAbsent || peerId != null) {
      map['peer_id'] = Variable<String>(peerId);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    if (!nullToAbsent || lastMsgHlc != null) {
      map['last_msg_hlc'] = Variable<String>(lastMsgHlc);
    }
    if (!nullToAbsent || lastMsgPreview != null) {
      map['last_msg_preview'] = Variable<String>(lastMsgPreview);
    }
    map['unread'] = Variable<int>(unread);
    map['muted'] = Variable<bool>(muted);
    map['pinned'] = Variable<bool>(pinned);
    {
      map['created_at'] = Variable<int>(
        $ThreadsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(
        $ThreadsTable.$converterdeletedAtn.toSql(deletedAt),
      );
    }
    return map;
  }

  ThreadsCompanion toCompanion(bool nullToAbsent) {
    return ThreadsCompanion(
      id: Value(id),
      kind: Value(kind),
      title: Value(title),
      avatarHash: Value(avatarHash),
      peerId: peerId == null && nullToAbsent
          ? const Value.absent()
          : Value(peerId),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      lastMsgHlc: lastMsgHlc == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMsgHlc),
      lastMsgPreview: lastMsgPreview == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMsgPreview),
      unread: Value(unread),
      muted: Value(muted),
      pinned: Value(pinned),
      createdAt: Value(createdAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ThreadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThreadRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      title: serializer.fromJson<String>(json['title']),
      avatarHash: serializer.fromJson<String>(json['avatarHash']),
      peerId: serializer.fromJson<String?>(json['peerId']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      lastMsgHlc: serializer.fromJson<String?>(json['lastMsgHlc']),
      lastMsgPreview: serializer.fromJson<String?>(json['lastMsgPreview']),
      unread: serializer.fromJson<int>(json['unread']),
      muted: serializer.fromJson<bool>(json['muted']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'title': serializer.toJson<String>(title),
      'avatarHash': serializer.toJson<String>(avatarHash),
      'peerId': serializer.toJson<String?>(peerId),
      'groupId': serializer.toJson<String?>(groupId),
      'lastMsgHlc': serializer.toJson<String?>(lastMsgHlc),
      'lastMsgPreview': serializer.toJson<String?>(lastMsgPreview),
      'unread': serializer.toJson<int>(unread),
      'muted': serializer.toJson<bool>(muted),
      'pinned': serializer.toJson<bool>(pinned),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ThreadRow copyWith({
    String? id,
    String? kind,
    String? title,
    String? avatarHash,
    Value<String?> peerId = const Value.absent(),
    Value<String?> groupId = const Value.absent(),
    Value<String?> lastMsgHlc = const Value.absent(),
    Value<String?> lastMsgPreview = const Value.absent(),
    int? unread,
    bool? muted,
    bool? pinned,
    DateTime? createdAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ThreadRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    avatarHash: avatarHash ?? this.avatarHash,
    peerId: peerId.present ? peerId.value : this.peerId,
    groupId: groupId.present ? groupId.value : this.groupId,
    lastMsgHlc: lastMsgHlc.present ? lastMsgHlc.value : this.lastMsgHlc,
    lastMsgPreview: lastMsgPreview.present
        ? lastMsgPreview.value
        : this.lastMsgPreview,
    unread: unread ?? this.unread,
    muted: muted ?? this.muted,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt ?? this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ThreadRow copyWithCompanion(ThreadsCompanion data) {
    return ThreadRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      title: data.title.present ? data.title.value : this.title,
      avatarHash: data.avatarHash.present
          ? data.avatarHash.value
          : this.avatarHash,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      lastMsgHlc: data.lastMsgHlc.present
          ? data.lastMsgHlc.value
          : this.lastMsgHlc,
      lastMsgPreview: data.lastMsgPreview.present
          ? data.lastMsgPreview.value
          : this.lastMsgPreview,
      unread: data.unread.present ? data.unread.value : this.unread,
      muted: data.muted.present ? data.muted.value : this.muted,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThreadRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('avatarHash: $avatarHash, ')
          ..write('peerId: $peerId, ')
          ..write('groupId: $groupId, ')
          ..write('lastMsgHlc: $lastMsgHlc, ')
          ..write('lastMsgPreview: $lastMsgPreview, ')
          ..write('unread: $unread, ')
          ..write('muted: $muted, ')
          ..write('pinned: $pinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    title,
    avatarHash,
    peerId,
    groupId,
    lastMsgHlc,
    lastMsgPreview,
    unread,
    muted,
    pinned,
    createdAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThreadRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.title == this.title &&
          other.avatarHash == this.avatarHash &&
          other.peerId == this.peerId &&
          other.groupId == this.groupId &&
          other.lastMsgHlc == this.lastMsgHlc &&
          other.lastMsgPreview == this.lastMsgPreview &&
          other.unread == this.unread &&
          other.muted == this.muted &&
          other.pinned == this.pinned &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt);
}

class ThreadsCompanion extends UpdateCompanion<ThreadRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> title;
  final Value<String> avatarHash;
  final Value<String?> peerId;
  final Value<String?> groupId;
  final Value<String?> lastMsgHlc;
  final Value<String?> lastMsgPreview;
  final Value<int> unread;
  final Value<bool> muted;
  final Value<bool> pinned;
  final Value<DateTime> createdAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ThreadsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.title = const Value.absent(),
    this.avatarHash = const Value.absent(),
    this.peerId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.lastMsgHlc = const Value.absent(),
    this.lastMsgPreview = const Value.absent(),
    this.unread = const Value.absent(),
    this.muted = const Value.absent(),
    this.pinned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ThreadsCompanion.insert({
    required String id,
    required String kind,
    this.title = const Value.absent(),
    this.avatarHash = const Value.absent(),
    this.peerId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.lastMsgHlc = const Value.absent(),
    this.lastMsgPreview = const Value.absent(),
    this.unread = const Value.absent(),
    this.muted = const Value.absent(),
    this.pinned = const Value.absent(),
    required DateTime createdAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       createdAt = Value(createdAt);
  static Insertable<ThreadRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? title,
    Expression<String>? avatarHash,
    Expression<String>? peerId,
    Expression<String>? groupId,
    Expression<String>? lastMsgHlc,
    Expression<String>? lastMsgPreview,
    Expression<int>? unread,
    Expression<bool>? muted,
    Expression<bool>? pinned,
    Expression<int>? createdAt,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (title != null) 'title': title,
      if (avatarHash != null) 'avatar_hash': avatarHash,
      if (peerId != null) 'peer_id': peerId,
      if (groupId != null) 'group_id': groupId,
      if (lastMsgHlc != null) 'last_msg_hlc': lastMsgHlc,
      if (lastMsgPreview != null) 'last_msg_preview': lastMsgPreview,
      if (unread != null) 'unread': unread,
      if (muted != null) 'muted': muted,
      if (pinned != null) 'pinned': pinned,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ThreadsCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? title,
    Value<String>? avatarHash,
    Value<String?>? peerId,
    Value<String?>? groupId,
    Value<String?>? lastMsgHlc,
    Value<String?>? lastMsgPreview,
    Value<int>? unread,
    Value<bool>? muted,
    Value<bool>? pinned,
    Value<DateTime>? createdAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ThreadsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      avatarHash: avatarHash ?? this.avatarHash,
      peerId: peerId ?? this.peerId,
      groupId: groupId ?? this.groupId,
      lastMsgHlc: lastMsgHlc ?? this.lastMsgHlc,
      lastMsgPreview: lastMsgPreview ?? this.lastMsgPreview,
      unread: unread ?? this.unread,
      muted: muted ?? this.muted,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (avatarHash.present) {
      map['avatar_hash'] = Variable<String>(avatarHash.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (lastMsgHlc.present) {
      map['last_msg_hlc'] = Variable<String>(lastMsgHlc.value);
    }
    if (lastMsgPreview.present) {
      map['last_msg_preview'] = Variable<String>(lastMsgPreview.value);
    }
    if (unread.present) {
      map['unread'] = Variable<int>(unread.value);
    }
    if (muted.present) {
      map['muted'] = Variable<bool>(muted.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $ThreadsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(
        $ThreadsTable.$converterdeletedAtn.toSql(deletedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThreadsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('avatarHash: $avatarHash, ')
          ..write('peerId: $peerId, ')
          ..write('groupId: $groupId, ')
          ..write('lastMsgHlc: $lastMsgHlc, ')
          ..write('lastMsgPreview: $lastMsgPreview, ')
          ..write('unread: $unread, ')
          ..write('muted: $muted, ')
          ..write('pinned: $pinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GrpsTable extends Grps with TableInfo<$GrpsTable, GrpRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GrpsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _avatarHashMeta = const VerificationMeta(
    'avatarHash',
  );
  @override
  late final GeneratedColumn<String> avatarHash = GeneratedColumn<String>(
    'avatar_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _ownerPeerIdMeta = const VerificationMeta(
    'ownerPeerId',
  );
  @override
  late final GeneratedColumn<String> ownerPeerId = GeneratedColumn<String>(
    'owner_peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($GrpsTable.$convertercreatedAt);
  static const VerificationMeta _epochMeta = const VerificationMeta('epoch');
  @override
  late final GeneratedColumn<int> epoch = GeneratedColumn<int>(
    'epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    avatarHash,
    ownerPeerId,
    createdAt,
    epoch,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'grp';
  @override
  VerificationContext validateIntegrity(
    Insertable<GrpRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('avatar_hash')) {
      context.handle(
        _avatarHashMeta,
        avatarHash.isAcceptableOrUnknown(data['avatar_hash']!, _avatarHashMeta),
      );
    }
    if (data.containsKey('owner_peer_id')) {
      context.handle(
        _ownerPeerIdMeta,
        ownerPeerId.isAcceptableOrUnknown(
          data['owner_peer_id']!,
          _ownerPeerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerPeerIdMeta);
    }
    if (data.containsKey('epoch')) {
      context.handle(
        _epochMeta,
        epoch.isAcceptableOrUnknown(data['epoch']!, _epochMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GrpRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GrpRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatarHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_hash'],
      )!,
      ownerPeerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_peer_id'],
      )!,
      createdAt: $GrpsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      epoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epoch'],
      )!,
    );
  }

  @override
  $GrpsTable createAlias(String alias) {
    return $GrpsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertercreatedAt =
      const UnixMillisConverter();
}

class GrpRow extends DataClass implements Insertable<GrpRow> {
  final String id;
  final String name;
  final String avatarHash;
  final String ownerPeerId;
  final DateTime createdAt;
  final int epoch;
  const GrpRow({
    required this.id,
    required this.name,
    required this.avatarHash,
    required this.ownerPeerId,
    required this.createdAt,
    required this.epoch,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['avatar_hash'] = Variable<String>(avatarHash);
    map['owner_peer_id'] = Variable<String>(ownerPeerId);
    {
      map['created_at'] = Variable<int>(
        $GrpsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    map['epoch'] = Variable<int>(epoch);
    return map;
  }

  GrpsCompanion toCompanion(bool nullToAbsent) {
    return GrpsCompanion(
      id: Value(id),
      name: Value(name),
      avatarHash: Value(avatarHash),
      ownerPeerId: Value(ownerPeerId),
      createdAt: Value(createdAt),
      epoch: Value(epoch),
    );
  }

  factory GrpRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GrpRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      avatarHash: serializer.fromJson<String>(json['avatarHash']),
      ownerPeerId: serializer.fromJson<String>(json['ownerPeerId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      epoch: serializer.fromJson<int>(json['epoch']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'avatarHash': serializer.toJson<String>(avatarHash),
      'ownerPeerId': serializer.toJson<String>(ownerPeerId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'epoch': serializer.toJson<int>(epoch),
    };
  }

  GrpRow copyWith({
    String? id,
    String? name,
    String? avatarHash,
    String? ownerPeerId,
    DateTime? createdAt,
    int? epoch,
  }) => GrpRow(
    id: id ?? this.id,
    name: name ?? this.name,
    avatarHash: avatarHash ?? this.avatarHash,
    ownerPeerId: ownerPeerId ?? this.ownerPeerId,
    createdAt: createdAt ?? this.createdAt,
    epoch: epoch ?? this.epoch,
  );
  GrpRow copyWithCompanion(GrpsCompanion data) {
    return GrpRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      avatarHash: data.avatarHash.present
          ? data.avatarHash.value
          : this.avatarHash,
      ownerPeerId: data.ownerPeerId.present
          ? data.ownerPeerId.value
          : this.ownerPeerId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      epoch: data.epoch.present ? data.epoch.value : this.epoch,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GrpRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarHash: $avatarHash, ')
          ..write('ownerPeerId: $ownerPeerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('epoch: $epoch')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, avatarHash, ownerPeerId, createdAt, epoch);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GrpRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.avatarHash == this.avatarHash &&
          other.ownerPeerId == this.ownerPeerId &&
          other.createdAt == this.createdAt &&
          other.epoch == this.epoch);
}

class GrpsCompanion extends UpdateCompanion<GrpRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> avatarHash;
  final Value<String> ownerPeerId;
  final Value<DateTime> createdAt;
  final Value<int> epoch;
  final Value<int> rowid;
  const GrpsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarHash = const Value.absent(),
    this.ownerPeerId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.epoch = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GrpsCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.avatarHash = const Value.absent(),
    required String ownerPeerId,
    required DateTime createdAt,
    this.epoch = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerPeerId = Value(ownerPeerId),
       createdAt = Value(createdAt);
  static Insertable<GrpRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? avatarHash,
    Expression<String>? ownerPeerId,
    Expression<int>? createdAt,
    Expression<int>? epoch,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (avatarHash != null) 'avatar_hash': avatarHash,
      if (ownerPeerId != null) 'owner_peer_id': ownerPeerId,
      if (createdAt != null) 'created_at': createdAt,
      if (epoch != null) 'epoch': epoch,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GrpsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? avatarHash,
    Value<String>? ownerPeerId,
    Value<DateTime>? createdAt,
    Value<int>? epoch,
    Value<int>? rowid,
  }) {
    return GrpsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarHash: avatarHash ?? this.avatarHash,
      ownerPeerId: ownerPeerId ?? this.ownerPeerId,
      createdAt: createdAt ?? this.createdAt,
      epoch: epoch ?? this.epoch,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatarHash.present) {
      map['avatar_hash'] = Variable<String>(avatarHash.value);
    }
    if (ownerPeerId.present) {
      map['owner_peer_id'] = Variable<String>(ownerPeerId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $GrpsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (epoch.present) {
      map['epoch'] = Variable<int>(epoch.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GrpsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarHash: $avatarHash, ')
          ..write('ownerPeerId: $ownerPeerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('epoch: $epoch, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupMembersTable extends GroupMembers
    with TableInfo<$GroupMembersTable, GroupMemberRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES grp (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('member'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> joinedAt =
      GeneratedColumn<int>(
        'joined_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($GroupMembersTable.$converterjoinedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> lastSeen =
      GeneratedColumn<int>(
        'last_seen',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($GroupMembersTable.$converterlastSeenn);
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    peerId,
    role,
    joinedAt,
    lastSeen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_member';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupMemberRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, peerId};
  @override
  GroupMemberRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupMemberRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      joinedAt: $GroupMembersTable.$converterjoinedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}joined_at'],
        )!,
      ),
      lastSeen: $GroupMembersTable.$converterlastSeenn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_seen'],
        ),
      ),
    );
  }

  @override
  $GroupMembersTable createAlias(String alias) {
    return $GroupMembersTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterjoinedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterlastSeen =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converterlastSeenn =
      NullAwareTypeConverter.wrap($converterlastSeen);
}

class GroupMemberRow extends DataClass implements Insertable<GroupMemberRow> {
  final String groupId;
  final String peerId;
  final String role;
  final DateTime joinedAt;
  final DateTime? lastSeen;
  const GroupMemberRow({
    required this.groupId,
    required this.peerId,
    required this.role,
    required this.joinedAt,
    this.lastSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['peer_id'] = Variable<String>(peerId);
    map['role'] = Variable<String>(role);
    {
      map['joined_at'] = Variable<int>(
        $GroupMembersTable.$converterjoinedAt.toSql(joinedAt),
      );
    }
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<int>(
        $GroupMembersTable.$converterlastSeenn.toSql(lastSeen),
      );
    }
    return map;
  }

  GroupMembersCompanion toCompanion(bool nullToAbsent) {
    return GroupMembersCompanion(
      groupId: Value(groupId),
      peerId: Value(peerId),
      role: Value(role),
      joinedAt: Value(joinedAt),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
    );
  }

  factory GroupMemberRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupMemberRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      peerId: serializer.fromJson<String>(json['peerId']),
      role: serializer.fromJson<String>(json['role']),
      joinedAt: serializer.fromJson<DateTime>(json['joinedAt']),
      lastSeen: serializer.fromJson<DateTime?>(json['lastSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'peerId': serializer.toJson<String>(peerId),
      'role': serializer.toJson<String>(role),
      'joinedAt': serializer.toJson<DateTime>(joinedAt),
      'lastSeen': serializer.toJson<DateTime?>(lastSeen),
    };
  }

  GroupMemberRow copyWith({
    String? groupId,
    String? peerId,
    String? role,
    DateTime? joinedAt,
    Value<DateTime?> lastSeen = const Value.absent(),
  }) => GroupMemberRow(
    groupId: groupId ?? this.groupId,
    peerId: peerId ?? this.peerId,
    role: role ?? this.role,
    joinedAt: joinedAt ?? this.joinedAt,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
  );
  GroupMemberRow copyWithCompanion(GroupMembersCompanion data) {
    return GroupMemberRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      role: data.role.present ? data.role.value : this.role,
      joinedAt: data.joinedAt.present ? data.joinedAt.value : this.joinedAt,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupMemberRow(')
          ..write('groupId: $groupId, ')
          ..write('peerId: $peerId, ')
          ..write('role: $role, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(groupId, peerId, role, joinedAt, lastSeen);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupMemberRow &&
          other.groupId == this.groupId &&
          other.peerId == this.peerId &&
          other.role == this.role &&
          other.joinedAt == this.joinedAt &&
          other.lastSeen == this.lastSeen);
}

class GroupMembersCompanion extends UpdateCompanion<GroupMemberRow> {
  final Value<String> groupId;
  final Value<String> peerId;
  final Value<String> role;
  final Value<DateTime> joinedAt;
  final Value<DateTime?> lastSeen;
  final Value<int> rowid;
  const GroupMembersCompanion({
    this.groupId = const Value.absent(),
    this.peerId = const Value.absent(),
    this.role = const Value.absent(),
    this.joinedAt = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupMembersCompanion.insert({
    required String groupId,
    required String peerId,
    this.role = const Value.absent(),
    required DateTime joinedAt,
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       peerId = Value(peerId),
       joinedAt = Value(joinedAt);
  static Insertable<GroupMemberRow> custom({
    Expression<String>? groupId,
    Expression<String>? peerId,
    Expression<String>? role,
    Expression<int>? joinedAt,
    Expression<int>? lastSeen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (peerId != null) 'peer_id': peerId,
      if (role != null) 'role': role,
      if (joinedAt != null) 'joined_at': joinedAt,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupMembersCompanion copyWith({
    Value<String>? groupId,
    Value<String>? peerId,
    Value<String>? role,
    Value<DateTime>? joinedAt,
    Value<DateTime?>? lastSeen,
    Value<int>? rowid,
  }) {
    return GroupMembersCompanion(
      groupId: groupId ?? this.groupId,
      peerId: peerId ?? this.peerId,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (joinedAt.present) {
      map['joined_at'] = Variable<int>(
        $GroupMembersTable.$converterjoinedAt.toSql(joinedAt.value),
      );
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<int>(
        $GroupMembersTable.$converterlastSeenn.toSql(lastSeen.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupMembersCompanion(')
          ..write('groupId: $groupId, ')
          ..write('peerId: $peerId, ')
          ..write('role: $role, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupKeysTable extends GroupKeys
    with TableInfo<$GroupKeysTable, GroupKeyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES grp (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _epochMeta = const VerificationMeta('epoch');
  @override
  late final GeneratedColumn<int> epoch = GeneratedColumn<int>(
    'epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wrappedForPeerMeta = const VerificationMeta(
    'wrappedForPeer',
  );
  @override
  late final GeneratedColumn<String> wrappedForPeer = GeneratedColumn<String>(
    'wrapped_for_peer',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wrappedBlobMeta = const VerificationMeta(
    'wrappedBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> wrappedBlob =
      GeneratedColumn<Uint8List>(
        'wrapped_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    epoch,
    wrappedForPeer,
    wrappedBlob,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_key';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupKeyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('epoch')) {
      context.handle(
        _epochMeta,
        epoch.isAcceptableOrUnknown(data['epoch']!, _epochMeta),
      );
    } else if (isInserting) {
      context.missing(_epochMeta);
    }
    if (data.containsKey('wrapped_for_peer')) {
      context.handle(
        _wrappedForPeerMeta,
        wrappedForPeer.isAcceptableOrUnknown(
          data['wrapped_for_peer']!,
          _wrappedForPeerMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wrappedForPeerMeta);
    }
    if (data.containsKey('wrapped_blob')) {
      context.handle(
        _wrappedBlobMeta,
        wrappedBlob.isAcceptableOrUnknown(
          data['wrapped_blob']!,
          _wrappedBlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wrappedBlobMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, epoch, wrappedForPeer};
  @override
  GroupKeyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupKeyRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      epoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epoch'],
      )!,
      wrappedForPeer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wrapped_for_peer'],
      )!,
      wrappedBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}wrapped_blob'],
      )!,
    );
  }

  @override
  $GroupKeysTable createAlias(String alias) {
    return $GroupKeysTable(attachedDatabase, alias);
  }
}

class GroupKeyRow extends DataClass implements Insertable<GroupKeyRow> {
  final String groupId;
  final int epoch;
  final String wrappedForPeer;
  final Uint8List wrappedBlob;
  const GroupKeyRow({
    required this.groupId,
    required this.epoch,
    required this.wrappedForPeer,
    required this.wrappedBlob,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['epoch'] = Variable<int>(epoch);
    map['wrapped_for_peer'] = Variable<String>(wrappedForPeer);
    map['wrapped_blob'] = Variable<Uint8List>(wrappedBlob);
    return map;
  }

  GroupKeysCompanion toCompanion(bool nullToAbsent) {
    return GroupKeysCompanion(
      groupId: Value(groupId),
      epoch: Value(epoch),
      wrappedForPeer: Value(wrappedForPeer),
      wrappedBlob: Value(wrappedBlob),
    );
  }

  factory GroupKeyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupKeyRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      epoch: serializer.fromJson<int>(json['epoch']),
      wrappedForPeer: serializer.fromJson<String>(json['wrappedForPeer']),
      wrappedBlob: serializer.fromJson<Uint8List>(json['wrappedBlob']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'epoch': serializer.toJson<int>(epoch),
      'wrappedForPeer': serializer.toJson<String>(wrappedForPeer),
      'wrappedBlob': serializer.toJson<Uint8List>(wrappedBlob),
    };
  }

  GroupKeyRow copyWith({
    String? groupId,
    int? epoch,
    String? wrappedForPeer,
    Uint8List? wrappedBlob,
  }) => GroupKeyRow(
    groupId: groupId ?? this.groupId,
    epoch: epoch ?? this.epoch,
    wrappedForPeer: wrappedForPeer ?? this.wrappedForPeer,
    wrappedBlob: wrappedBlob ?? this.wrappedBlob,
  );
  GroupKeyRow copyWithCompanion(GroupKeysCompanion data) {
    return GroupKeyRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      epoch: data.epoch.present ? data.epoch.value : this.epoch,
      wrappedForPeer: data.wrappedForPeer.present
          ? data.wrappedForPeer.value
          : this.wrappedForPeer,
      wrappedBlob: data.wrappedBlob.present
          ? data.wrappedBlob.value
          : this.wrappedBlob,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupKeyRow(')
          ..write('groupId: $groupId, ')
          ..write('epoch: $epoch, ')
          ..write('wrappedForPeer: $wrappedForPeer, ')
          ..write('wrappedBlob: $wrappedBlob')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    epoch,
    wrappedForPeer,
    $driftBlobEquality.hash(wrappedBlob),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupKeyRow &&
          other.groupId == this.groupId &&
          other.epoch == this.epoch &&
          other.wrappedForPeer == this.wrappedForPeer &&
          $driftBlobEquality.equals(other.wrappedBlob, this.wrappedBlob));
}

class GroupKeysCompanion extends UpdateCompanion<GroupKeyRow> {
  final Value<String> groupId;
  final Value<int> epoch;
  final Value<String> wrappedForPeer;
  final Value<Uint8List> wrappedBlob;
  final Value<int> rowid;
  const GroupKeysCompanion({
    this.groupId = const Value.absent(),
    this.epoch = const Value.absent(),
    this.wrappedForPeer = const Value.absent(),
    this.wrappedBlob = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupKeysCompanion.insert({
    required String groupId,
    required int epoch,
    required String wrappedForPeer,
    required Uint8List wrappedBlob,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       epoch = Value(epoch),
       wrappedForPeer = Value(wrappedForPeer),
       wrappedBlob = Value(wrappedBlob);
  static Insertable<GroupKeyRow> custom({
    Expression<String>? groupId,
    Expression<int>? epoch,
    Expression<String>? wrappedForPeer,
    Expression<Uint8List>? wrappedBlob,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (epoch != null) 'epoch': epoch,
      if (wrappedForPeer != null) 'wrapped_for_peer': wrappedForPeer,
      if (wrappedBlob != null) 'wrapped_blob': wrappedBlob,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupKeysCompanion copyWith({
    Value<String>? groupId,
    Value<int>? epoch,
    Value<String>? wrappedForPeer,
    Value<Uint8List>? wrappedBlob,
    Value<int>? rowid,
  }) {
    return GroupKeysCompanion(
      groupId: groupId ?? this.groupId,
      epoch: epoch ?? this.epoch,
      wrappedForPeer: wrappedForPeer ?? this.wrappedForPeer,
      wrappedBlob: wrappedBlob ?? this.wrappedBlob,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (epoch.present) {
      map['epoch'] = Variable<int>(epoch.value);
    }
    if (wrappedForPeer.present) {
      map['wrapped_for_peer'] = Variable<String>(wrappedForPeer.value);
    }
    if (wrappedBlob.present) {
      map['wrapped_blob'] = Variable<Uint8List>(wrappedBlob.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupKeysCompanion(')
          ..write('groupId: $groupId, ')
          ..write('epoch: $epoch, ')
          ..write('wrappedForPeer: $wrappedForPeer, ')
          ..write('wrappedBlob: $wrappedBlob, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages
    with TableInfo<$MessagesTable, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderPeerIdMeta = const VerificationMeta(
    'senderPeerId',
  );
  @override
  late final GeneratedColumn<String> senderPeerId = GeneratedColumn<String>(
    'sender_peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<MessageKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MessageKind>($MessagesTable.$converterkind);
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> ts =
      GeneratedColumn<int>(
        'ts',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($MessagesTable.$converterts);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _attachJsonMeta = const VerificationMeta(
    'attachJson',
  );
  @override
  late final GeneratedColumn<String> attachJson = GeneratedColumn<String>(
    'attach_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sigMeta = const VerificationMeta('sig');
  @override
  late final GeneratedColumn<String> sig = GeneratedColumn<String>(
    'sig',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> revokedAt =
      GeneratedColumn<int>(
        'revoked_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($MessagesTable.$converterrevokedAtn);
  static const VerificationMeta _revokeReasonMeta = const VerificationMeta(
    'revokeReason',
  );
  @override
  late final GeneratedColumn<String> revokeReason = GeneratedColumn<String>(
    'revoke_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> editedAt =
      GeneratedColumn<int>(
        'edited_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($MessagesTable.$convertereditedAtn);
  static const VerificationMeta _deletedByMeta = const VerificationMeta(
    'deletedBy',
  );
  @override
  late final GeneratedColumn<String> deletedBy = GeneratedColumn<String>(
    'deleted_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    threadId,
    senderPeerId,
    kind,
    hlc,
    ts,
    body,
    attachJson,
    sig,
    revokedAt,
    revokeReason,
    editedAt,
    deletedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('sender_peer_id')) {
      context.handle(
        _senderPeerIdMeta,
        senderPeerId.isAcceptableOrUnknown(
          data['sender_peer_id']!,
          _senderPeerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_senderPeerIdMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('attach_json')) {
      context.handle(
        _attachJsonMeta,
        attachJson.isAcceptableOrUnknown(data['attach_json']!, _attachJsonMeta),
      );
    }
    if (data.containsKey('sig')) {
      context.handle(
        _sigMeta,
        sig.isAcceptableOrUnknown(data['sig']!, _sigMeta),
      );
    }
    if (data.containsKey('revoke_reason')) {
      context.handle(
        _revokeReasonMeta,
        revokeReason.isAcceptableOrUnknown(
          data['revoke_reason']!,
          _revokeReasonMeta,
        ),
      );
    }
    if (data.containsKey('deleted_by')) {
      context.handle(
        _deletedByMeta,
        deletedBy.isAcceptableOrUnknown(data['deleted_by']!, _deletedByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      senderPeerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_peer_id'],
      )!,
      kind: $MessagesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      ts: $MessagesTable.$converterts.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}ts'],
        )!,
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      attachJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attach_json'],
      )!,
      sig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sig'],
      )!,
      revokedAt: $MessagesTable.$converterrevokedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}revoked_at'],
        ),
      ),
      revokeReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revoke_reason'],
      ),
      editedAt: $MessagesTable.$convertereditedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}edited_at'],
        ),
      ),
      deletedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_by'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MessageKind, String, String> $converterkind =
      const EnumNameConverter<MessageKind>(MessageKind.values);
  static TypeConverter<DateTime, int> $converterts =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterrevokedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converterrevokedAtn =
      NullAwareTypeConverter.wrap($converterrevokedAt);
  static TypeConverter<DateTime, int> $convertereditedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $convertereditedAtn =
      NullAwareTypeConverter.wrap($convertereditedAt);
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  final String id;
  final String threadId;
  final String senderPeerId;
  final MessageKind kind;

  /// HLC 的定宽文本形式，见 [zeroPaddedHlc]。
  ///
  /// 定宽的理由：HLC 的字典序只有在毫秒 13 位、计数器 6 位定宽时才等价于
  /// 数值序；否则 9:xxx 会排在 10:xxx 之后。定宽后 ORDER BY hlc 与
  /// Hlc.compareTo 顺序一致，不需要额外排序列。
  final String hlc;
  final DateTime ts;
  final String body;
  final String attachJson;
  final String sig;
  final DateTime? revokedAt;
  final String? revokeReason;
  final DateTime? editedAt;

  /// 删除者：群主删他人消息时记录其 peerId；null 表示发送者本人操作。
  /// 与契约 [MessageRecord.deletedBy] 一一对应，必须有真实列，
  /// 不得塞进 revoke_reason（见决策笔记 derived-group-fields-must-hit-storage）。
  final String? deletedBy;
  const MessageRow({
    required this.id,
    required this.threadId,
    required this.senderPeerId,
    required this.kind,
    required this.hlc,
    required this.ts,
    required this.body,
    required this.attachJson,
    required this.sig,
    this.revokedAt,
    this.revokeReason,
    this.editedAt,
    this.deletedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['thread_id'] = Variable<String>(threadId);
    map['sender_peer_id'] = Variable<String>(senderPeerId);
    {
      map['kind'] = Variable<String>($MessagesTable.$converterkind.toSql(kind));
    }
    map['hlc'] = Variable<String>(hlc);
    {
      map['ts'] = Variable<int>($MessagesTable.$converterts.toSql(ts));
    }
    map['body'] = Variable<String>(body);
    map['attach_json'] = Variable<String>(attachJson);
    map['sig'] = Variable<String>(sig);
    if (!nullToAbsent || revokedAt != null) {
      map['revoked_at'] = Variable<int>(
        $MessagesTable.$converterrevokedAtn.toSql(revokedAt),
      );
    }
    if (!nullToAbsent || revokeReason != null) {
      map['revoke_reason'] = Variable<String>(revokeReason);
    }
    if (!nullToAbsent || editedAt != null) {
      map['edited_at'] = Variable<int>(
        $MessagesTable.$convertereditedAtn.toSql(editedAt),
      );
    }
    if (!nullToAbsent || deletedBy != null) {
      map['deleted_by'] = Variable<String>(deletedBy);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      threadId: Value(threadId),
      senderPeerId: Value(senderPeerId),
      kind: Value(kind),
      hlc: Value(hlc),
      ts: Value(ts),
      body: Value(body),
      attachJson: Value(attachJson),
      sig: Value(sig),
      revokedAt: revokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(revokedAt),
      revokeReason: revokeReason == null && nullToAbsent
          ? const Value.absent()
          : Value(revokeReason),
      editedAt: editedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(editedAt),
      deletedBy: deletedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedBy),
    );
  }

  factory MessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      id: serializer.fromJson<String>(json['id']),
      threadId: serializer.fromJson<String>(json['threadId']),
      senderPeerId: serializer.fromJson<String>(json['senderPeerId']),
      kind: $MessagesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      hlc: serializer.fromJson<String>(json['hlc']),
      ts: serializer.fromJson<DateTime>(json['ts']),
      body: serializer.fromJson<String>(json['body']),
      attachJson: serializer.fromJson<String>(json['attachJson']),
      sig: serializer.fromJson<String>(json['sig']),
      revokedAt: serializer.fromJson<DateTime?>(json['revokedAt']),
      revokeReason: serializer.fromJson<String?>(json['revokeReason']),
      editedAt: serializer.fromJson<DateTime?>(json['editedAt']),
      deletedBy: serializer.fromJson<String?>(json['deletedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'threadId': serializer.toJson<String>(threadId),
      'senderPeerId': serializer.toJson<String>(senderPeerId),
      'kind': serializer.toJson<String>(
        $MessagesTable.$converterkind.toJson(kind),
      ),
      'hlc': serializer.toJson<String>(hlc),
      'ts': serializer.toJson<DateTime>(ts),
      'body': serializer.toJson<String>(body),
      'attachJson': serializer.toJson<String>(attachJson),
      'sig': serializer.toJson<String>(sig),
      'revokedAt': serializer.toJson<DateTime?>(revokedAt),
      'revokeReason': serializer.toJson<String?>(revokeReason),
      'editedAt': serializer.toJson<DateTime?>(editedAt),
      'deletedBy': serializer.toJson<String?>(deletedBy),
    };
  }

  MessageRow copyWith({
    String? id,
    String? threadId,
    String? senderPeerId,
    MessageKind? kind,
    String? hlc,
    DateTime? ts,
    String? body,
    String? attachJson,
    String? sig,
    Value<DateTime?> revokedAt = const Value.absent(),
    Value<String?> revokeReason = const Value.absent(),
    Value<DateTime?> editedAt = const Value.absent(),
    Value<String?> deletedBy = const Value.absent(),
  }) => MessageRow(
    id: id ?? this.id,
    threadId: threadId ?? this.threadId,
    senderPeerId: senderPeerId ?? this.senderPeerId,
    kind: kind ?? this.kind,
    hlc: hlc ?? this.hlc,
    ts: ts ?? this.ts,
    body: body ?? this.body,
    attachJson: attachJson ?? this.attachJson,
    sig: sig ?? this.sig,
    revokedAt: revokedAt.present ? revokedAt.value : this.revokedAt,
    revokeReason: revokeReason.present ? revokeReason.value : this.revokeReason,
    editedAt: editedAt.present ? editedAt.value : this.editedAt,
    deletedBy: deletedBy.present ? deletedBy.value : this.deletedBy,
  );
  MessageRow copyWithCompanion(MessagesCompanion data) {
    return MessageRow(
      id: data.id.present ? data.id.value : this.id,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      senderPeerId: data.senderPeerId.present
          ? data.senderPeerId.value
          : this.senderPeerId,
      kind: data.kind.present ? data.kind.value : this.kind,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      ts: data.ts.present ? data.ts.value : this.ts,
      body: data.body.present ? data.body.value : this.body,
      attachJson: data.attachJson.present
          ? data.attachJson.value
          : this.attachJson,
      sig: data.sig.present ? data.sig.value : this.sig,
      revokedAt: data.revokedAt.present ? data.revokedAt.value : this.revokedAt,
      revokeReason: data.revokeReason.present
          ? data.revokeReason.value
          : this.revokeReason,
      editedAt: data.editedAt.present ? data.editedAt.value : this.editedAt,
      deletedBy: data.deletedBy.present ? data.deletedBy.value : this.deletedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('id: $id, ')
          ..write('threadId: $threadId, ')
          ..write('senderPeerId: $senderPeerId, ')
          ..write('kind: $kind, ')
          ..write('hlc: $hlc, ')
          ..write('ts: $ts, ')
          ..write('body: $body, ')
          ..write('attachJson: $attachJson, ')
          ..write('sig: $sig, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('revokeReason: $revokeReason, ')
          ..write('editedAt: $editedAt, ')
          ..write('deletedBy: $deletedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    threadId,
    senderPeerId,
    kind,
    hlc,
    ts,
    body,
    attachJson,
    sig,
    revokedAt,
    revokeReason,
    editedAt,
    deletedBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.id == this.id &&
          other.threadId == this.threadId &&
          other.senderPeerId == this.senderPeerId &&
          other.kind == this.kind &&
          other.hlc == this.hlc &&
          other.ts == this.ts &&
          other.body == this.body &&
          other.attachJson == this.attachJson &&
          other.sig == this.sig &&
          other.revokedAt == this.revokedAt &&
          other.revokeReason == this.revokeReason &&
          other.editedAt == this.editedAt &&
          other.deletedBy == this.deletedBy);
}

class MessagesCompanion extends UpdateCompanion<MessageRow> {
  final Value<String> id;
  final Value<String> threadId;
  final Value<String> senderPeerId;
  final Value<MessageKind> kind;
  final Value<String> hlc;
  final Value<DateTime> ts;
  final Value<String> body;
  final Value<String> attachJson;
  final Value<String> sig;
  final Value<DateTime?> revokedAt;
  final Value<String?> revokeReason;
  final Value<DateTime?> editedAt;
  final Value<String?> deletedBy;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.threadId = const Value.absent(),
    this.senderPeerId = const Value.absent(),
    this.kind = const Value.absent(),
    this.hlc = const Value.absent(),
    this.ts = const Value.absent(),
    this.body = const Value.absent(),
    this.attachJson = const Value.absent(),
    this.sig = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.revokeReason = const Value.absent(),
    this.editedAt = const Value.absent(),
    this.deletedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String threadId,
    required String senderPeerId,
    required MessageKind kind,
    required String hlc,
    required DateTime ts,
    this.body = const Value.absent(),
    this.attachJson = const Value.absent(),
    this.sig = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.revokeReason = const Value.absent(),
    this.editedAt = const Value.absent(),
    this.deletedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       threadId = Value(threadId),
       senderPeerId = Value(senderPeerId),
       kind = Value(kind),
       hlc = Value(hlc),
       ts = Value(ts);
  static Insertable<MessageRow> custom({
    Expression<String>? id,
    Expression<String>? threadId,
    Expression<String>? senderPeerId,
    Expression<String>? kind,
    Expression<String>? hlc,
    Expression<int>? ts,
    Expression<String>? body,
    Expression<String>? attachJson,
    Expression<String>? sig,
    Expression<int>? revokedAt,
    Expression<String>? revokeReason,
    Expression<int>? editedAt,
    Expression<String>? deletedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (threadId != null) 'thread_id': threadId,
      if (senderPeerId != null) 'sender_peer_id': senderPeerId,
      if (kind != null) 'kind': kind,
      if (hlc != null) 'hlc': hlc,
      if (ts != null) 'ts': ts,
      if (body != null) 'body': body,
      if (attachJson != null) 'attach_json': attachJson,
      if (sig != null) 'sig': sig,
      if (revokedAt != null) 'revoked_at': revokedAt,
      if (revokeReason != null) 'revoke_reason': revokeReason,
      if (editedAt != null) 'edited_at': editedAt,
      if (deletedBy != null) 'deleted_by': deletedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? threadId,
    Value<String>? senderPeerId,
    Value<MessageKind>? kind,
    Value<String>? hlc,
    Value<DateTime>? ts,
    Value<String>? body,
    Value<String>? attachJson,
    Value<String>? sig,
    Value<DateTime?>? revokedAt,
    Value<String?>? revokeReason,
    Value<DateTime?>? editedAt,
    Value<String?>? deletedBy,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      kind: kind ?? this.kind,
      hlc: hlc ?? this.hlc,
      ts: ts ?? this.ts,
      body: body ?? this.body,
      attachJson: attachJson ?? this.attachJson,
      sig: sig ?? this.sig,
      revokedAt: revokedAt ?? this.revokedAt,
      revokeReason: revokeReason ?? this.revokeReason,
      editedAt: editedAt ?? this.editedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (senderPeerId.present) {
      map['sender_peer_id'] = Variable<String>(senderPeerId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $MessagesTable.$converterkind.toSql(kind.value),
      );
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (ts.present) {
      map['ts'] = Variable<int>($MessagesTable.$converterts.toSql(ts.value));
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (attachJson.present) {
      map['attach_json'] = Variable<String>(attachJson.value);
    }
    if (sig.present) {
      map['sig'] = Variable<String>(sig.value);
    }
    if (revokedAt.present) {
      map['revoked_at'] = Variable<int>(
        $MessagesTable.$converterrevokedAtn.toSql(revokedAt.value),
      );
    }
    if (revokeReason.present) {
      map['revoke_reason'] = Variable<String>(revokeReason.value);
    }
    if (editedAt.present) {
      map['edited_at'] = Variable<int>(
        $MessagesTable.$convertereditedAtn.toSql(editedAt.value),
      );
    }
    if (deletedBy.present) {
      map['deleted_by'] = Variable<String>(deletedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('threadId: $threadId, ')
          ..write('senderPeerId: $senderPeerId, ')
          ..write('kind: $kind, ')
          ..write('hlc: $hlc, ')
          ..write('ts: $ts, ')
          ..write('body: $body, ')
          ..write('attachJson: $attachJson, ')
          ..write('sig: $sig, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('revokeReason: $revokeReason, ')
          ..write('editedAt: $editedAt, ')
          ..write('deletedBy: $deletedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentsTable extends Attachments
    with TableInfo<$AttachmentsTable, AttachRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _msgIdMeta = const VerificationMeta('msgId');
  @override
  late final GeneratedColumn<String> msgId = GeneratedColumn<String>(
    'msg_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shareIdMeta = const VerificationMeta(
    'shareId',
  );
  @override
  late final GeneratedColumn<String> shareId = GeneratedColumn<String>(
    'share_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerPeerIdMeta = const VerificationMeta(
    'ownerPeerId',
  );
  @override
  late final GeneratedColumn<String> ownerPeerId = GeneratedColumn<String>(
    'owner_peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemKeyMeta = const VerificationMeta(
    'itemKey',
  );
  @override
  late final GeneratedColumn<String> itemKey = GeneratedColumn<String>(
    'item_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDirMeta = const VerificationMeta('isDir');
  @override
  late final GeneratedColumn<bool> isDir = GeneratedColumn<bool>(
    'is_dir',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dir" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _subPathMeta = const VerificationMeta(
    'subPath',
  );
  @override
  late final GeneratedColumn<String> subPath = GeneratedColumn<String>(
    'sub_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    msgId,
    shareId,
    ownerPeerId,
    itemKey,
    name,
    size,
    mime,
    isDir,
    subPath,
    localPath,
    state,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attach';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttachRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('msg_id')) {
      context.handle(
        _msgIdMeta,
        msgId.isAcceptableOrUnknown(data['msg_id']!, _msgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_msgIdMeta);
    }
    if (data.containsKey('share_id')) {
      context.handle(
        _shareIdMeta,
        shareId.isAcceptableOrUnknown(data['share_id']!, _shareIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shareIdMeta);
    }
    if (data.containsKey('owner_peer_id')) {
      context.handle(
        _ownerPeerIdMeta,
        ownerPeerId.isAcceptableOrUnknown(
          data['owner_peer_id']!,
          _ownerPeerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerPeerIdMeta);
    }
    if (data.containsKey('item_key')) {
      context.handle(
        _itemKeyMeta,
        itemKey.isAcceptableOrUnknown(data['item_key']!, _itemKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_itemKeyMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    }
    if (data.containsKey('is_dir')) {
      context.handle(
        _isDirMeta,
        isDir.isAcceptableOrUnknown(data['is_dir']!, _isDirMeta),
      );
    }
    if (data.containsKey('sub_path')) {
      context.handle(
        _subPathMeta,
        subPath.isAcceptableOrUnknown(data['sub_path']!, _subPathMeta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AttachRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttachRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      msgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}msg_id'],
      )!,
      shareId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}share_id'],
      )!,
      ownerPeerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_peer_id'],
      )!,
      itemKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_key'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      ),
      isDir: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dir'],
      )!,
      subPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sub_path'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
    );
  }

  @override
  $AttachmentsTable createAlias(String alias) {
    return $AttachmentsTable(attachedDatabase, alias);
  }
}

class AttachRow extends DataClass implements Insertable<AttachRow> {
  final String id;
  final String msgId;
  final String shareId;
  final String ownerPeerId;
  final String itemKey;
  final String name;
  final int size;
  final String? mime;
  final bool isDir;
  final String? subPath;
  final String? localPath;
  final String state;
  const AttachRow({
    required this.id,
    required this.msgId,
    required this.shareId,
    required this.ownerPeerId,
    required this.itemKey,
    required this.name,
    required this.size,
    this.mime,
    required this.isDir,
    this.subPath,
    this.localPath,
    required this.state,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['msg_id'] = Variable<String>(msgId);
    map['share_id'] = Variable<String>(shareId);
    map['owner_peer_id'] = Variable<String>(ownerPeerId);
    map['item_key'] = Variable<String>(itemKey);
    map['name'] = Variable<String>(name);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || mime != null) {
      map['mime'] = Variable<String>(mime);
    }
    map['is_dir'] = Variable<bool>(isDir);
    if (!nullToAbsent || subPath != null) {
      map['sub_path'] = Variable<String>(subPath);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['state'] = Variable<String>(state);
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      id: Value(id),
      msgId: Value(msgId),
      shareId: Value(shareId),
      ownerPeerId: Value(ownerPeerId),
      itemKey: Value(itemKey),
      name: Value(name),
      size: Value(size),
      mime: mime == null && nullToAbsent ? const Value.absent() : Value(mime),
      isDir: Value(isDir),
      subPath: subPath == null && nullToAbsent
          ? const Value.absent()
          : Value(subPath),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      state: Value(state),
    );
  }

  factory AttachRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttachRow(
      id: serializer.fromJson<String>(json['id']),
      msgId: serializer.fromJson<String>(json['msgId']),
      shareId: serializer.fromJson<String>(json['shareId']),
      ownerPeerId: serializer.fromJson<String>(json['ownerPeerId']),
      itemKey: serializer.fromJson<String>(json['itemKey']),
      name: serializer.fromJson<String>(json['name']),
      size: serializer.fromJson<int>(json['size']),
      mime: serializer.fromJson<String?>(json['mime']),
      isDir: serializer.fromJson<bool>(json['isDir']),
      subPath: serializer.fromJson<String?>(json['subPath']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      state: serializer.fromJson<String>(json['state']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'msgId': serializer.toJson<String>(msgId),
      'shareId': serializer.toJson<String>(shareId),
      'ownerPeerId': serializer.toJson<String>(ownerPeerId),
      'itemKey': serializer.toJson<String>(itemKey),
      'name': serializer.toJson<String>(name),
      'size': serializer.toJson<int>(size),
      'mime': serializer.toJson<String?>(mime),
      'isDir': serializer.toJson<bool>(isDir),
      'subPath': serializer.toJson<String?>(subPath),
      'localPath': serializer.toJson<String?>(localPath),
      'state': serializer.toJson<String>(state),
    };
  }

  AttachRow copyWith({
    String? id,
    String? msgId,
    String? shareId,
    String? ownerPeerId,
    String? itemKey,
    String? name,
    int? size,
    Value<String?> mime = const Value.absent(),
    bool? isDir,
    Value<String?> subPath = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    String? state,
  }) => AttachRow(
    id: id ?? this.id,
    msgId: msgId ?? this.msgId,
    shareId: shareId ?? this.shareId,
    ownerPeerId: ownerPeerId ?? this.ownerPeerId,
    itemKey: itemKey ?? this.itemKey,
    name: name ?? this.name,
    size: size ?? this.size,
    mime: mime.present ? mime.value : this.mime,
    isDir: isDir ?? this.isDir,
    subPath: subPath.present ? subPath.value : this.subPath,
    localPath: localPath.present ? localPath.value : this.localPath,
    state: state ?? this.state,
  );
  AttachRow copyWithCompanion(AttachmentsCompanion data) {
    return AttachRow(
      id: data.id.present ? data.id.value : this.id,
      msgId: data.msgId.present ? data.msgId.value : this.msgId,
      shareId: data.shareId.present ? data.shareId.value : this.shareId,
      ownerPeerId: data.ownerPeerId.present
          ? data.ownerPeerId.value
          : this.ownerPeerId,
      itemKey: data.itemKey.present ? data.itemKey.value : this.itemKey,
      name: data.name.present ? data.name.value : this.name,
      size: data.size.present ? data.size.value : this.size,
      mime: data.mime.present ? data.mime.value : this.mime,
      isDir: data.isDir.present ? data.isDir.value : this.isDir,
      subPath: data.subPath.present ? data.subPath.value : this.subPath,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      state: data.state.present ? data.state.value : this.state,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttachRow(')
          ..write('id: $id, ')
          ..write('msgId: $msgId, ')
          ..write('shareId: $shareId, ')
          ..write('ownerPeerId: $ownerPeerId, ')
          ..write('itemKey: $itemKey, ')
          ..write('name: $name, ')
          ..write('size: $size, ')
          ..write('mime: $mime, ')
          ..write('isDir: $isDir, ')
          ..write('subPath: $subPath, ')
          ..write('localPath: $localPath, ')
          ..write('state: $state')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    msgId,
    shareId,
    ownerPeerId,
    itemKey,
    name,
    size,
    mime,
    isDir,
    subPath,
    localPath,
    state,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttachRow &&
          other.id == this.id &&
          other.msgId == this.msgId &&
          other.shareId == this.shareId &&
          other.ownerPeerId == this.ownerPeerId &&
          other.itemKey == this.itemKey &&
          other.name == this.name &&
          other.size == this.size &&
          other.mime == this.mime &&
          other.isDir == this.isDir &&
          other.subPath == this.subPath &&
          other.localPath == this.localPath &&
          other.state == this.state);
}

class AttachmentsCompanion extends UpdateCompanion<AttachRow> {
  final Value<String> id;
  final Value<String> msgId;
  final Value<String> shareId;
  final Value<String> ownerPeerId;
  final Value<String> itemKey;
  final Value<String> name;
  final Value<int> size;
  final Value<String?> mime;
  final Value<bool> isDir;
  final Value<String?> subPath;
  final Value<String?> localPath;
  final Value<String> state;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.id = const Value.absent(),
    this.msgId = const Value.absent(),
    this.shareId = const Value.absent(),
    this.ownerPeerId = const Value.absent(),
    this.itemKey = const Value.absent(),
    this.name = const Value.absent(),
    this.size = const Value.absent(),
    this.mime = const Value.absent(),
    this.isDir = const Value.absent(),
    this.subPath = const Value.absent(),
    this.localPath = const Value.absent(),
    this.state = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    required String id,
    required String msgId,
    required String shareId,
    required String ownerPeerId,
    required String itemKey,
    this.name = const Value.absent(),
    this.size = const Value.absent(),
    this.mime = const Value.absent(),
    this.isDir = const Value.absent(),
    this.subPath = const Value.absent(),
    this.localPath = const Value.absent(),
    this.state = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       msgId = Value(msgId),
       shareId = Value(shareId),
       ownerPeerId = Value(ownerPeerId),
       itemKey = Value(itemKey);
  static Insertable<AttachRow> custom({
    Expression<String>? id,
    Expression<String>? msgId,
    Expression<String>? shareId,
    Expression<String>? ownerPeerId,
    Expression<String>? itemKey,
    Expression<String>? name,
    Expression<int>? size,
    Expression<String>? mime,
    Expression<bool>? isDir,
    Expression<String>? subPath,
    Expression<String>? localPath,
    Expression<String>? state,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (msgId != null) 'msg_id': msgId,
      if (shareId != null) 'share_id': shareId,
      if (ownerPeerId != null) 'owner_peer_id': ownerPeerId,
      if (itemKey != null) 'item_key': itemKey,
      if (name != null) 'name': name,
      if (size != null) 'size': size,
      if (mime != null) 'mime': mime,
      if (isDir != null) 'is_dir': isDir,
      if (subPath != null) 'sub_path': subPath,
      if (localPath != null) 'local_path': localPath,
      if (state != null) 'state': state,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? msgId,
    Value<String>? shareId,
    Value<String>? ownerPeerId,
    Value<String>? itemKey,
    Value<String>? name,
    Value<int>? size,
    Value<String?>? mime,
    Value<bool>? isDir,
    Value<String?>? subPath,
    Value<String?>? localPath,
    Value<String>? state,
    Value<int>? rowid,
  }) {
    return AttachmentsCompanion(
      id: id ?? this.id,
      msgId: msgId ?? this.msgId,
      shareId: shareId ?? this.shareId,
      ownerPeerId: ownerPeerId ?? this.ownerPeerId,
      itemKey: itemKey ?? this.itemKey,
      name: name ?? this.name,
      size: size ?? this.size,
      mime: mime ?? this.mime,
      isDir: isDir ?? this.isDir,
      subPath: subPath ?? this.subPath,
      localPath: localPath ?? this.localPath,
      state: state ?? this.state,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (msgId.present) {
      map['msg_id'] = Variable<String>(msgId.value);
    }
    if (shareId.present) {
      map['share_id'] = Variable<String>(shareId.value);
    }
    if (ownerPeerId.present) {
      map['owner_peer_id'] = Variable<String>(ownerPeerId.value);
    }
    if (itemKey.present) {
      map['item_key'] = Variable<String>(itemKey.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (isDir.present) {
      map['is_dir'] = Variable<bool>(isDir.value);
    }
    if (subPath.present) {
      map['sub_path'] = Variable<String>(subPath.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('msgId: $msgId, ')
          ..write('shareId: $shareId, ')
          ..write('ownerPeerId: $ownerPeerId, ')
          ..write('itemKey: $itemKey, ')
          ..write('name: $name, ')
          ..write('size: $size, ')
          ..write('mime: $mime, ')
          ..write('isDir: $isDir, ')
          ..write('subPath: $subPath, ')
          ..write('localPath: $localPath, ')
          ..write('state: $state, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OffersTable extends Offers with TableInfo<$OffersTable, OfferRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OffersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromPeerMeta = const VerificationMeta(
    'fromPeer',
  );
  @override
  late final GeneratedColumn<String> fromPeer = GeneratedColumn<String>(
    'from_peer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fromSessionMeta = const VerificationMeta(
    'fromSession',
  );
  @override
  late final GeneratedColumn<String> fromSession = GeneratedColumn<String>(
    'from_session',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<OfferOrigin, String> origin =
      GeneratedColumn<String>(
        'origin',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<OfferOrigin>($OffersTable.$converterorigin);
  static const VerificationMeta _toPeerMeta = const VerificationMeta('toPeer');
  @override
  late final GeneratedColumn<String> toPeer = GeneratedColumn<String>(
    'to_peer',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attachJsonMeta = const VerificationMeta(
    'attachJson',
  );
  @override
  late final GeneratedColumn<String> attachJson = GeneratedColumn<String>(
    'attach_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sizeTotalMeta = const VerificationMeta(
    'sizeTotal',
  );
  @override
  late final GeneratedColumn<int> sizeTotal = GeneratedColumn<int>(
    'size_total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($OffersTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> decidedAt =
      GeneratedColumn<int>(
        'decided_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($OffersTable.$converterdecidedAtn);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> expireAt =
      GeneratedColumn<int>(
        'expire_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($OffersTable.$converterexpireAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fromPeer,
    fromSession,
    origin,
    toPeer,
    attachJson,
    sizeTotal,
    status,
    createdAt,
    decidedAt,
    note,
    expireAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offer';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfferRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('from_peer')) {
      context.handle(
        _fromPeerMeta,
        fromPeer.isAcceptableOrUnknown(data['from_peer']!, _fromPeerMeta),
      );
    }
    if (data.containsKey('from_session')) {
      context.handle(
        _fromSessionMeta,
        fromSession.isAcceptableOrUnknown(
          data['from_session']!,
          _fromSessionMeta,
        ),
      );
    }
    if (data.containsKey('to_peer')) {
      context.handle(
        _toPeerMeta,
        toPeer.isAcceptableOrUnknown(data['to_peer']!, _toPeerMeta),
      );
    } else if (isInserting) {
      context.missing(_toPeerMeta);
    }
    if (data.containsKey('attach_json')) {
      context.handle(
        _attachJsonMeta,
        attachJson.isAcceptableOrUnknown(data['attach_json']!, _attachJsonMeta),
      );
    }
    if (data.containsKey('size_total')) {
      context.handle(
        _sizeTotalMeta,
        sizeTotal.isAcceptableOrUnknown(data['size_total']!, _sizeTotalMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfferRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfferRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fromPeer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_peer'],
      ),
      fromSession: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_session'],
      ),
      origin: $OffersTable.$converterorigin.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}origin'],
        )!,
      ),
      toPeer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_peer'],
      )!,
      attachJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attach_json'],
      )!,
      sizeTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_total'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: $OffersTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      decidedAt: $OffersTable.$converterdecidedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}decided_at'],
        ),
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      expireAt: $OffersTable.$converterexpireAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}expire_at'],
        )!,
      ),
    );
  }

  @override
  $OffersTable createAlias(String alias) {
    return $OffersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<OfferOrigin, String, String> $converterorigin =
      const EnumNameConverter<OfferOrigin>(OfferOrigin.values);
  static TypeConverter<DateTime, int> $convertercreatedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterdecidedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converterdecidedAtn =
      NullAwareTypeConverter.wrap($converterdecidedAt);
  static TypeConverter<DateTime, int> $converterexpireAt =
      const UnixMillisConverter();
}

class OfferRow extends DataClass implements Insertable<OfferRow> {
  final String id;
  final String? fromPeer;
  final String? fromSession;

  /// offer 来源：peer 表示节点，webSession 表示网页访客。
  ///
  /// **与契约 OfferRecord.origin 一一对应**，是一等存储列，不是从
  /// from_peer / from_session 的空值推导出来的。
  /// 推导在「会话撤销后把 from_session 清空」时会静默漂移成 peer，
  /// 这类错误在联调中极难发现，因此这里显式落列。
  ///
  /// 注意：OfferOrigin 声明在 contracts/types.dart（不在 store.dart），
  /// 而本表所在的 library 由 database.dart 承载，故 database.dart 需要
  /// 同时 import 两个契约文件（生成物作为 part 只共享 database.dart 的 import 集）。
  final OfferOrigin origin;
  final String toPeer;
  final String attachJson;
  final int sizeTotal;

  /// pending / accepted / rejected / expired / cancelled。
  ///
  /// 存文本而非枚举：契约用 OfferStatusWire 值对象表达，且线上字段名已冻结，
  /// 这里保持与线上值域一致，不做二次映射。
  final String status;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? note;
  final DateTime expireAt;
  const OfferRow({
    required this.id,
    this.fromPeer,
    this.fromSession,
    required this.origin,
    required this.toPeer,
    required this.attachJson,
    required this.sizeTotal,
    required this.status,
    required this.createdAt,
    this.decidedAt,
    this.note,
    required this.expireAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || fromPeer != null) {
      map['from_peer'] = Variable<String>(fromPeer);
    }
    if (!nullToAbsent || fromSession != null) {
      map['from_session'] = Variable<String>(fromSession);
    }
    {
      map['origin'] = Variable<String>(
        $OffersTable.$converterorigin.toSql(origin),
      );
    }
    map['to_peer'] = Variable<String>(toPeer);
    map['attach_json'] = Variable<String>(attachJson);
    map['size_total'] = Variable<int>(sizeTotal);
    map['status'] = Variable<String>(status);
    {
      map['created_at'] = Variable<int>(
        $OffersTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    if (!nullToAbsent || decidedAt != null) {
      map['decided_at'] = Variable<int>(
        $OffersTable.$converterdecidedAtn.toSql(decidedAt),
      );
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    {
      map['expire_at'] = Variable<int>(
        $OffersTable.$converterexpireAt.toSql(expireAt),
      );
    }
    return map;
  }

  OffersCompanion toCompanion(bool nullToAbsent) {
    return OffersCompanion(
      id: Value(id),
      fromPeer: fromPeer == null && nullToAbsent
          ? const Value.absent()
          : Value(fromPeer),
      fromSession: fromSession == null && nullToAbsent
          ? const Value.absent()
          : Value(fromSession),
      origin: Value(origin),
      toPeer: Value(toPeer),
      attachJson: Value(attachJson),
      sizeTotal: Value(sizeTotal),
      status: Value(status),
      createdAt: Value(createdAt),
      decidedAt: decidedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(decidedAt),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      expireAt: Value(expireAt),
    );
  }

  factory OfferRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfferRow(
      id: serializer.fromJson<String>(json['id']),
      fromPeer: serializer.fromJson<String?>(json['fromPeer']),
      fromSession: serializer.fromJson<String?>(json['fromSession']),
      origin: $OffersTable.$converterorigin.fromJson(
        serializer.fromJson<String>(json['origin']),
      ),
      toPeer: serializer.fromJson<String>(json['toPeer']),
      attachJson: serializer.fromJson<String>(json['attachJson']),
      sizeTotal: serializer.fromJson<int>(json['sizeTotal']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      decidedAt: serializer.fromJson<DateTime?>(json['decidedAt']),
      note: serializer.fromJson<String?>(json['note']),
      expireAt: serializer.fromJson<DateTime>(json['expireAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fromPeer': serializer.toJson<String?>(fromPeer),
      'fromSession': serializer.toJson<String?>(fromSession),
      'origin': serializer.toJson<String>(
        $OffersTable.$converterorigin.toJson(origin),
      ),
      'toPeer': serializer.toJson<String>(toPeer),
      'attachJson': serializer.toJson<String>(attachJson),
      'sizeTotal': serializer.toJson<int>(sizeTotal),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'decidedAt': serializer.toJson<DateTime?>(decidedAt),
      'note': serializer.toJson<String?>(note),
      'expireAt': serializer.toJson<DateTime>(expireAt),
    };
  }

  OfferRow copyWith({
    String? id,
    Value<String?> fromPeer = const Value.absent(),
    Value<String?> fromSession = const Value.absent(),
    OfferOrigin? origin,
    String? toPeer,
    String? attachJson,
    int? sizeTotal,
    String? status,
    DateTime? createdAt,
    Value<DateTime?> decidedAt = const Value.absent(),
    Value<String?> note = const Value.absent(),
    DateTime? expireAt,
  }) => OfferRow(
    id: id ?? this.id,
    fromPeer: fromPeer.present ? fromPeer.value : this.fromPeer,
    fromSession: fromSession.present ? fromSession.value : this.fromSession,
    origin: origin ?? this.origin,
    toPeer: toPeer ?? this.toPeer,
    attachJson: attachJson ?? this.attachJson,
    sizeTotal: sizeTotal ?? this.sizeTotal,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    decidedAt: decidedAt.present ? decidedAt.value : this.decidedAt,
    note: note.present ? note.value : this.note,
    expireAt: expireAt ?? this.expireAt,
  );
  OfferRow copyWithCompanion(OffersCompanion data) {
    return OfferRow(
      id: data.id.present ? data.id.value : this.id,
      fromPeer: data.fromPeer.present ? data.fromPeer.value : this.fromPeer,
      fromSession: data.fromSession.present
          ? data.fromSession.value
          : this.fromSession,
      origin: data.origin.present ? data.origin.value : this.origin,
      toPeer: data.toPeer.present ? data.toPeer.value : this.toPeer,
      attachJson: data.attachJson.present
          ? data.attachJson.value
          : this.attachJson,
      sizeTotal: data.sizeTotal.present ? data.sizeTotal.value : this.sizeTotal,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      decidedAt: data.decidedAt.present ? data.decidedAt.value : this.decidedAt,
      note: data.note.present ? data.note.value : this.note,
      expireAt: data.expireAt.present ? data.expireAt.value : this.expireAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfferRow(')
          ..write('id: $id, ')
          ..write('fromPeer: $fromPeer, ')
          ..write('fromSession: $fromSession, ')
          ..write('origin: $origin, ')
          ..write('toPeer: $toPeer, ')
          ..write('attachJson: $attachJson, ')
          ..write('sizeTotal: $sizeTotal, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('decidedAt: $decidedAt, ')
          ..write('note: $note, ')
          ..write('expireAt: $expireAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    fromPeer,
    fromSession,
    origin,
    toPeer,
    attachJson,
    sizeTotal,
    status,
    createdAt,
    decidedAt,
    note,
    expireAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfferRow &&
          other.id == this.id &&
          other.fromPeer == this.fromPeer &&
          other.fromSession == this.fromSession &&
          other.origin == this.origin &&
          other.toPeer == this.toPeer &&
          other.attachJson == this.attachJson &&
          other.sizeTotal == this.sizeTotal &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.decidedAt == this.decidedAt &&
          other.note == this.note &&
          other.expireAt == this.expireAt);
}

class OffersCompanion extends UpdateCompanion<OfferRow> {
  final Value<String> id;
  final Value<String?> fromPeer;
  final Value<String?> fromSession;
  final Value<OfferOrigin> origin;
  final Value<String> toPeer;
  final Value<String> attachJson;
  final Value<int> sizeTotal;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime?> decidedAt;
  final Value<String?> note;
  final Value<DateTime> expireAt;
  final Value<int> rowid;
  const OffersCompanion({
    this.id = const Value.absent(),
    this.fromPeer = const Value.absent(),
    this.fromSession = const Value.absent(),
    this.origin = const Value.absent(),
    this.toPeer = const Value.absent(),
    this.attachJson = const Value.absent(),
    this.sizeTotal = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.decidedAt = const Value.absent(),
    this.note = const Value.absent(),
    this.expireAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OffersCompanion.insert({
    required String id,
    this.fromPeer = const Value.absent(),
    this.fromSession = const Value.absent(),
    required OfferOrigin origin,
    required String toPeer,
    this.attachJson = const Value.absent(),
    this.sizeTotal = const Value.absent(),
    required String status,
    required DateTime createdAt,
    this.decidedAt = const Value.absent(),
    this.note = const Value.absent(),
    required DateTime expireAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       origin = Value(origin),
       toPeer = Value(toPeer),
       status = Value(status),
       createdAt = Value(createdAt),
       expireAt = Value(expireAt);
  static Insertable<OfferRow> custom({
    Expression<String>? id,
    Expression<String>? fromPeer,
    Expression<String>? fromSession,
    Expression<String>? origin,
    Expression<String>? toPeer,
    Expression<String>? attachJson,
    Expression<int>? sizeTotal,
    Expression<String>? status,
    Expression<int>? createdAt,
    Expression<int>? decidedAt,
    Expression<String>? note,
    Expression<int>? expireAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromPeer != null) 'from_peer': fromPeer,
      if (fromSession != null) 'from_session': fromSession,
      if (origin != null) 'origin': origin,
      if (toPeer != null) 'to_peer': toPeer,
      if (attachJson != null) 'attach_json': attachJson,
      if (sizeTotal != null) 'size_total': sizeTotal,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (decidedAt != null) 'decided_at': decidedAt,
      if (note != null) 'note': note,
      if (expireAt != null) 'expire_at': expireAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OffersCompanion copyWith({
    Value<String>? id,
    Value<String?>? fromPeer,
    Value<String?>? fromSession,
    Value<OfferOrigin>? origin,
    Value<String>? toPeer,
    Value<String>? attachJson,
    Value<int>? sizeTotal,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<DateTime?>? decidedAt,
    Value<String?>? note,
    Value<DateTime>? expireAt,
    Value<int>? rowid,
  }) {
    return OffersCompanion(
      id: id ?? this.id,
      fromPeer: fromPeer ?? this.fromPeer,
      fromSession: fromSession ?? this.fromSession,
      origin: origin ?? this.origin,
      toPeer: toPeer ?? this.toPeer,
      attachJson: attachJson ?? this.attachJson,
      sizeTotal: sizeTotal ?? this.sizeTotal,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      decidedAt: decidedAt ?? this.decidedAt,
      note: note ?? this.note,
      expireAt: expireAt ?? this.expireAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fromPeer.present) {
      map['from_peer'] = Variable<String>(fromPeer.value);
    }
    if (fromSession.present) {
      map['from_session'] = Variable<String>(fromSession.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(
        $OffersTable.$converterorigin.toSql(origin.value),
      );
    }
    if (toPeer.present) {
      map['to_peer'] = Variable<String>(toPeer.value);
    }
    if (attachJson.present) {
      map['attach_json'] = Variable<String>(attachJson.value);
    }
    if (sizeTotal.present) {
      map['size_total'] = Variable<int>(sizeTotal.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $OffersTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (decidedAt.present) {
      map['decided_at'] = Variable<int>(
        $OffersTable.$converterdecidedAtn.toSql(decidedAt.value),
      );
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (expireAt.present) {
      map['expire_at'] = Variable<int>(
        $OffersTable.$converterexpireAt.toSql(expireAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OffersCompanion(')
          ..write('id: $id, ')
          ..write('fromPeer: $fromPeer, ')
          ..write('fromSession: $fromSession, ')
          ..write('origin: $origin, ')
          ..write('toPeer: $toPeer, ')
          ..write('attachJson: $attachJson, ')
          ..write('sizeTotal: $sizeTotal, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('decidedAt: $decidedAt, ')
          ..write('note: $note, ')
          ..write('expireAt: $expireAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransfersTable extends Transfers
    with TableInfo<$TransfersTable, TransferRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransfersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TransferDirection, String>
  direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<TransferDirection>($TransfersTable.$converterdirection);
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shareIdMeta = const VerificationMeta(
    'shareId',
  );
  @override
  late final GeneratedColumn<String> shareId = GeneratedColumn<String>(
    'share_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemKeyMeta = const VerificationMeta(
    'itemKey',
  );
  @override
  late final GeneratedColumn<String> itemKey = GeneratedColumn<String>(
    'item_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesTotalMeta = const VerificationMeta(
    'bytesTotal',
  );
  @override
  late final GeneratedColumn<int> bytesTotal = GeneratedColumn<int>(
    'bytes_total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesDoneMeta = const VerificationMeta(
    'bytesDone',
  );
  @override
  late final GeneratedColumn<int> bytesDone = GeneratedColumn<int>(
    'bytes_done',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<TransferStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TransferStatus>($TransfersTable.$converterstatus);
  static const VerificationMeta _speedBpsMeta = const VerificationMeta(
    'speedBps',
  );
  @override
  late final GeneratedColumn<int> speedBps = GeneratedColumn<int>(
    'speed_bps',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TransfersTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> finishedAt =
      GeneratedColumn<int>(
        'finished_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TransfersTable.$converterfinishedAtn);
  static const VerificationMeta _errMeta = const VerificationMeta('err');
  @override
  late final GeneratedColumn<String> err = GeneratedColumn<String>(
    'err',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    direction,
    peerId,
    shareId,
    itemKey,
    bytesTotal,
    bytesDone,
    status,
    speedBps,
    createdAt,
    finishedAt,
    err,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfer';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransferRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('share_id')) {
      context.handle(
        _shareIdMeta,
        shareId.isAcceptableOrUnknown(data['share_id']!, _shareIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shareIdMeta);
    }
    if (data.containsKey('item_key')) {
      context.handle(
        _itemKeyMeta,
        itemKey.isAcceptableOrUnknown(data['item_key']!, _itemKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_itemKeyMeta);
    }
    if (data.containsKey('bytes_total')) {
      context.handle(
        _bytesTotalMeta,
        bytesTotal.isAcceptableOrUnknown(data['bytes_total']!, _bytesTotalMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesTotalMeta);
    }
    if (data.containsKey('bytes_done')) {
      context.handle(
        _bytesDoneMeta,
        bytesDone.isAcceptableOrUnknown(data['bytes_done']!, _bytesDoneMeta),
      );
    }
    if (data.containsKey('speed_bps')) {
      context.handle(
        _speedBpsMeta,
        speedBps.isAcceptableOrUnknown(data['speed_bps']!, _speedBpsMeta),
      );
    }
    if (data.containsKey('err')) {
      context.handle(
        _errMeta,
        err.isAcceptableOrUnknown(data['err']!, _errMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransferRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransferRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      direction: $TransfersTable.$converterdirection.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}direction'],
        )!,
      ),
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      shareId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}share_id'],
      )!,
      itemKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_key'],
      )!,
      bytesTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes_total'],
      )!,
      bytesDone: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes_done'],
      )!,
      status: $TransfersTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      speedBps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}speed_bps'],
      ),
      createdAt: $TransfersTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      finishedAt: $TransfersTable.$converterfinishedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}finished_at'],
        ),
      ),
      err: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}err'],
      ),
    );
  }

  @override
  $TransfersTable createAlias(String alias) {
    return $TransfersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TransferDirection, String, String>
  $converterdirection = const EnumNameConverter<TransferDirection>(
    TransferDirection.values,
  );
  static JsonTypeConverter2<TransferStatus, String, String> $converterstatus =
      const EnumNameConverter<TransferStatus>(TransferStatus.values);
  static TypeConverter<DateTime, int> $convertercreatedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterfinishedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converterfinishedAtn =
      NullAwareTypeConverter.wrap($converterfinishedAt);
}

class TransferRow extends DataClass implements Insertable<TransferRow> {
  final String id;
  final TransferDirection direction;
  final String peerId;
  final String shareId;
  final String itemKey;
  final int bytesTotal;
  final int bytesDone;
  final TransferStatus status;
  final int? speedBps;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final String? err;
  const TransferRow({
    required this.id,
    required this.direction,
    required this.peerId,
    required this.shareId,
    required this.itemKey,
    required this.bytesTotal,
    required this.bytesDone,
    required this.status,
    this.speedBps,
    required this.createdAt,
    this.finishedAt,
    this.err,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['direction'] = Variable<String>(
        $TransfersTable.$converterdirection.toSql(direction),
      );
    }
    map['peer_id'] = Variable<String>(peerId);
    map['share_id'] = Variable<String>(shareId);
    map['item_key'] = Variable<String>(itemKey);
    map['bytes_total'] = Variable<int>(bytesTotal);
    map['bytes_done'] = Variable<int>(bytesDone);
    {
      map['status'] = Variable<String>(
        $TransfersTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || speedBps != null) {
      map['speed_bps'] = Variable<int>(speedBps);
    }
    {
      map['created_at'] = Variable<int>(
        $TransfersTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<int>(
        $TransfersTable.$converterfinishedAtn.toSql(finishedAt),
      );
    }
    if (!nullToAbsent || err != null) {
      map['err'] = Variable<String>(err);
    }
    return map;
  }

  TransfersCompanion toCompanion(bool nullToAbsent) {
    return TransfersCompanion(
      id: Value(id),
      direction: Value(direction),
      peerId: Value(peerId),
      shareId: Value(shareId),
      itemKey: Value(itemKey),
      bytesTotal: Value(bytesTotal),
      bytesDone: Value(bytesDone),
      status: Value(status),
      speedBps: speedBps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedBps),
      createdAt: Value(createdAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      err: err == null && nullToAbsent ? const Value.absent() : Value(err),
    );
  }

  factory TransferRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransferRow(
      id: serializer.fromJson<String>(json['id']),
      direction: $TransfersTable.$converterdirection.fromJson(
        serializer.fromJson<String>(json['direction']),
      ),
      peerId: serializer.fromJson<String>(json['peerId']),
      shareId: serializer.fromJson<String>(json['shareId']),
      itemKey: serializer.fromJson<String>(json['itemKey']),
      bytesTotal: serializer.fromJson<int>(json['bytesTotal']),
      bytesDone: serializer.fromJson<int>(json['bytesDone']),
      status: $TransfersTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      speedBps: serializer.fromJson<int?>(json['speedBps']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
      err: serializer.fromJson<String?>(json['err']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'direction': serializer.toJson<String>(
        $TransfersTable.$converterdirection.toJson(direction),
      ),
      'peerId': serializer.toJson<String>(peerId),
      'shareId': serializer.toJson<String>(shareId),
      'itemKey': serializer.toJson<String>(itemKey),
      'bytesTotal': serializer.toJson<int>(bytesTotal),
      'bytesDone': serializer.toJson<int>(bytesDone),
      'status': serializer.toJson<String>(
        $TransfersTable.$converterstatus.toJson(status),
      ),
      'speedBps': serializer.toJson<int?>(speedBps),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
      'err': serializer.toJson<String?>(err),
    };
  }

  TransferRow copyWith({
    String? id,
    TransferDirection? direction,
    String? peerId,
    String? shareId,
    String? itemKey,
    int? bytesTotal,
    int? bytesDone,
    TransferStatus? status,
    Value<int?> speedBps = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> finishedAt = const Value.absent(),
    Value<String?> err = const Value.absent(),
  }) => TransferRow(
    id: id ?? this.id,
    direction: direction ?? this.direction,
    peerId: peerId ?? this.peerId,
    shareId: shareId ?? this.shareId,
    itemKey: itemKey ?? this.itemKey,
    bytesTotal: bytesTotal ?? this.bytesTotal,
    bytesDone: bytesDone ?? this.bytesDone,
    status: status ?? this.status,
    speedBps: speedBps.present ? speedBps.value : this.speedBps,
    createdAt: createdAt ?? this.createdAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    err: err.present ? err.value : this.err,
  );
  TransferRow copyWithCompanion(TransfersCompanion data) {
    return TransferRow(
      id: data.id.present ? data.id.value : this.id,
      direction: data.direction.present ? data.direction.value : this.direction,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      shareId: data.shareId.present ? data.shareId.value : this.shareId,
      itemKey: data.itemKey.present ? data.itemKey.value : this.itemKey,
      bytesTotal: data.bytesTotal.present
          ? data.bytesTotal.value
          : this.bytesTotal,
      bytesDone: data.bytesDone.present ? data.bytesDone.value : this.bytesDone,
      status: data.status.present ? data.status.value : this.status,
      speedBps: data.speedBps.present ? data.speedBps.value : this.speedBps,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      err: data.err.present ? data.err.value : this.err,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransferRow(')
          ..write('id: $id, ')
          ..write('direction: $direction, ')
          ..write('peerId: $peerId, ')
          ..write('shareId: $shareId, ')
          ..write('itemKey: $itemKey, ')
          ..write('bytesTotal: $bytesTotal, ')
          ..write('bytesDone: $bytesDone, ')
          ..write('status: $status, ')
          ..write('speedBps: $speedBps, ')
          ..write('createdAt: $createdAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('err: $err')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    direction,
    peerId,
    shareId,
    itemKey,
    bytesTotal,
    bytesDone,
    status,
    speedBps,
    createdAt,
    finishedAt,
    err,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransferRow &&
          other.id == this.id &&
          other.direction == this.direction &&
          other.peerId == this.peerId &&
          other.shareId == this.shareId &&
          other.itemKey == this.itemKey &&
          other.bytesTotal == this.bytesTotal &&
          other.bytesDone == this.bytesDone &&
          other.status == this.status &&
          other.speedBps == this.speedBps &&
          other.createdAt == this.createdAt &&
          other.finishedAt == this.finishedAt &&
          other.err == this.err);
}

class TransfersCompanion extends UpdateCompanion<TransferRow> {
  final Value<String> id;
  final Value<TransferDirection> direction;
  final Value<String> peerId;
  final Value<String> shareId;
  final Value<String> itemKey;
  final Value<int> bytesTotal;
  final Value<int> bytesDone;
  final Value<TransferStatus> status;
  final Value<int?> speedBps;
  final Value<DateTime> createdAt;
  final Value<DateTime?> finishedAt;
  final Value<String?> err;
  final Value<int> rowid;
  const TransfersCompanion({
    this.id = const Value.absent(),
    this.direction = const Value.absent(),
    this.peerId = const Value.absent(),
    this.shareId = const Value.absent(),
    this.itemKey = const Value.absent(),
    this.bytesTotal = const Value.absent(),
    this.bytesDone = const Value.absent(),
    this.status = const Value.absent(),
    this.speedBps = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.err = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransfersCompanion.insert({
    required String id,
    required TransferDirection direction,
    required String peerId,
    required String shareId,
    required String itemKey,
    required int bytesTotal,
    this.bytesDone = const Value.absent(),
    required TransferStatus status,
    this.speedBps = const Value.absent(),
    required DateTime createdAt,
    this.finishedAt = const Value.absent(),
    this.err = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       direction = Value(direction),
       peerId = Value(peerId),
       shareId = Value(shareId),
       itemKey = Value(itemKey),
       bytesTotal = Value(bytesTotal),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<TransferRow> custom({
    Expression<String>? id,
    Expression<String>? direction,
    Expression<String>? peerId,
    Expression<String>? shareId,
    Expression<String>? itemKey,
    Expression<int>? bytesTotal,
    Expression<int>? bytesDone,
    Expression<String>? status,
    Expression<int>? speedBps,
    Expression<int>? createdAt,
    Expression<int>? finishedAt,
    Expression<String>? err,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (direction != null) 'direction': direction,
      if (peerId != null) 'peer_id': peerId,
      if (shareId != null) 'share_id': shareId,
      if (itemKey != null) 'item_key': itemKey,
      if (bytesTotal != null) 'bytes_total': bytesTotal,
      if (bytesDone != null) 'bytes_done': bytesDone,
      if (status != null) 'status': status,
      if (speedBps != null) 'speed_bps': speedBps,
      if (createdAt != null) 'created_at': createdAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (err != null) 'err': err,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransfersCompanion copyWith({
    Value<String>? id,
    Value<TransferDirection>? direction,
    Value<String>? peerId,
    Value<String>? shareId,
    Value<String>? itemKey,
    Value<int>? bytesTotal,
    Value<int>? bytesDone,
    Value<TransferStatus>? status,
    Value<int?>? speedBps,
    Value<DateTime>? createdAt,
    Value<DateTime?>? finishedAt,
    Value<String?>? err,
    Value<int>? rowid,
  }) {
    return TransfersCompanion(
      id: id ?? this.id,
      direction: direction ?? this.direction,
      peerId: peerId ?? this.peerId,
      shareId: shareId ?? this.shareId,
      itemKey: itemKey ?? this.itemKey,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      bytesDone: bytesDone ?? this.bytesDone,
      status: status ?? this.status,
      speedBps: speedBps ?? this.speedBps,
      createdAt: createdAt ?? this.createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
      err: err ?? this.err,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(
        $TransfersTable.$converterdirection.toSql(direction.value),
      );
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (shareId.present) {
      map['share_id'] = Variable<String>(shareId.value);
    }
    if (itemKey.present) {
      map['item_key'] = Variable<String>(itemKey.value);
    }
    if (bytesTotal.present) {
      map['bytes_total'] = Variable<int>(bytesTotal.value);
    }
    if (bytesDone.present) {
      map['bytes_done'] = Variable<int>(bytesDone.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $TransfersTable.$converterstatus.toSql(status.value),
      );
    }
    if (speedBps.present) {
      map['speed_bps'] = Variable<int>(speedBps.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $TransfersTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<int>(
        $TransfersTable.$converterfinishedAtn.toSql(finishedAt.value),
      );
    }
    if (err.present) {
      map['err'] = Variable<String>(err.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransfersCompanion(')
          ..write('id: $id, ')
          ..write('direction: $direction, ')
          ..write('peerId: $peerId, ')
          ..write('shareId: $shareId, ')
          ..write('itemKey: $itemKey, ')
          ..write('bytesTotal: $bytesTotal, ')
          ..write('bytesDone: $bytesDone, ')
          ..write('status: $status, ')
          ..write('speedBps: $speedBps, ')
          ..write('createdAt: $createdAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('err: $err, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GuestSessionsTable extends GuestSessions
    with TableInfo<$GuestSessionsTable, GuestSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GuestSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostPeerMeta = const VerificationMeta(
    'hostPeer',
  );
  @override
  late final GeneratedColumn<String> hostPeer = GeneratedColumn<String>(
    'host_peer',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<Uint8List> pubkey = GeneratedColumn<Uint8List>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($GuestSessionsTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> lastBeat =
      GeneratedColumn<int>(
        'last_beat',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($GuestSessionsTable.$converterlastBeat);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> revokedAt =
      GeneratedColumn<int>(
        'revoked_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($GuestSessionsTable.$converterrevokedAtn);
  static const VerificationMeta _quotaBytesMeta = const VerificationMeta(
    'quotaBytes',
  );
  @override
  late final GeneratedColumn<int> quotaBytes = GeneratedColumn<int>(
    'quota_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _usedBytesMeta = const VerificationMeta(
    'usedBytes',
  );
  @override
  late final GeneratedColumn<int> usedBytes = GeneratedColumn<int>(
    'used_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    hostPeer,
    pubkey,
    createdAt,
    lastBeat,
    revokedAt,
    quotaBytes,
    usedBytes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'guest_session';
  @override
  VerificationContext validateIntegrity(
    Insertable<GuestSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('host_peer')) {
      context.handle(
        _hostPeerMeta,
        hostPeer.isAcceptableOrUnknown(data['host_peer']!, _hostPeerMeta),
      );
    } else if (isInserting) {
      context.missing(_hostPeerMeta);
    }
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('quota_bytes')) {
      context.handle(
        _quotaBytesMeta,
        quotaBytes.isAcceptableOrUnknown(data['quota_bytes']!, _quotaBytesMeta),
      );
    }
    if (data.containsKey('used_bytes')) {
      context.handle(
        _usedBytesMeta,
        usedBytes.isAcceptableOrUnknown(data['used_bytes']!, _usedBytesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  GuestSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GuestSessionRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      hostPeer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_peer'],
      )!,
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}pubkey'],
      )!,
      createdAt: $GuestSessionsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      lastBeat: $GuestSessionsTable.$converterlastBeat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_beat'],
        )!,
      ),
      revokedAt: $GuestSessionsTable.$converterrevokedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}revoked_at'],
        ),
      ),
      quotaBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quota_bytes'],
      )!,
      usedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}used_bytes'],
      )!,
    );
  }

  @override
  $GuestSessionsTable createAlias(String alias) {
    return $GuestSessionsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertercreatedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterlastBeat =
      const UnixMillisConverter();
  static TypeConverter<DateTime, int> $converterrevokedAt =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converterrevokedAtn =
      NullAwareTypeConverter.wrap($converterrevokedAt);
}

class GuestSessionRow extends DataClass implements Insertable<GuestSessionRow> {
  final String sessionId;
  final String hostPeer;
  final Uint8List pubkey;
  final DateTime createdAt;
  final DateTime lastBeat;
  final DateTime? revokedAt;
  final int quotaBytes;
  final int usedBytes;
  const GuestSessionRow({
    required this.sessionId,
    required this.hostPeer,
    required this.pubkey,
    required this.createdAt,
    required this.lastBeat,
    this.revokedAt,
    required this.quotaBytes,
    required this.usedBytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['host_peer'] = Variable<String>(hostPeer);
    map['pubkey'] = Variable<Uint8List>(pubkey);
    {
      map['created_at'] = Variable<int>(
        $GuestSessionsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['last_beat'] = Variable<int>(
        $GuestSessionsTable.$converterlastBeat.toSql(lastBeat),
      );
    }
    if (!nullToAbsent || revokedAt != null) {
      map['revoked_at'] = Variable<int>(
        $GuestSessionsTable.$converterrevokedAtn.toSql(revokedAt),
      );
    }
    map['quota_bytes'] = Variable<int>(quotaBytes);
    map['used_bytes'] = Variable<int>(usedBytes);
    return map;
  }

  GuestSessionsCompanion toCompanion(bool nullToAbsent) {
    return GuestSessionsCompanion(
      sessionId: Value(sessionId),
      hostPeer: Value(hostPeer),
      pubkey: Value(pubkey),
      createdAt: Value(createdAt),
      lastBeat: Value(lastBeat),
      revokedAt: revokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(revokedAt),
      quotaBytes: Value(quotaBytes),
      usedBytes: Value(usedBytes),
    );
  }

  factory GuestSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GuestSessionRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      hostPeer: serializer.fromJson<String>(json['hostPeer']),
      pubkey: serializer.fromJson<Uint8List>(json['pubkey']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastBeat: serializer.fromJson<DateTime>(json['lastBeat']),
      revokedAt: serializer.fromJson<DateTime?>(json['revokedAt']),
      quotaBytes: serializer.fromJson<int>(json['quotaBytes']),
      usedBytes: serializer.fromJson<int>(json['usedBytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'hostPeer': serializer.toJson<String>(hostPeer),
      'pubkey': serializer.toJson<Uint8List>(pubkey),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastBeat': serializer.toJson<DateTime>(lastBeat),
      'revokedAt': serializer.toJson<DateTime?>(revokedAt),
      'quotaBytes': serializer.toJson<int>(quotaBytes),
      'usedBytes': serializer.toJson<int>(usedBytes),
    };
  }

  GuestSessionRow copyWith({
    String? sessionId,
    String? hostPeer,
    Uint8List? pubkey,
    DateTime? createdAt,
    DateTime? lastBeat,
    Value<DateTime?> revokedAt = const Value.absent(),
    int? quotaBytes,
    int? usedBytes,
  }) => GuestSessionRow(
    sessionId: sessionId ?? this.sessionId,
    hostPeer: hostPeer ?? this.hostPeer,
    pubkey: pubkey ?? this.pubkey,
    createdAt: createdAt ?? this.createdAt,
    lastBeat: lastBeat ?? this.lastBeat,
    revokedAt: revokedAt.present ? revokedAt.value : this.revokedAt,
    quotaBytes: quotaBytes ?? this.quotaBytes,
    usedBytes: usedBytes ?? this.usedBytes,
  );
  GuestSessionRow copyWithCompanion(GuestSessionsCompanion data) {
    return GuestSessionRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      hostPeer: data.hostPeer.present ? data.hostPeer.value : this.hostPeer,
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastBeat: data.lastBeat.present ? data.lastBeat.value : this.lastBeat,
      revokedAt: data.revokedAt.present ? data.revokedAt.value : this.revokedAt,
      quotaBytes: data.quotaBytes.present
          ? data.quotaBytes.value
          : this.quotaBytes,
      usedBytes: data.usedBytes.present ? data.usedBytes.value : this.usedBytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GuestSessionRow(')
          ..write('sessionId: $sessionId, ')
          ..write('hostPeer: $hostPeer, ')
          ..write('pubkey: $pubkey, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastBeat: $lastBeat, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('quotaBytes: $quotaBytes, ')
          ..write('usedBytes: $usedBytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    hostPeer,
    $driftBlobEquality.hash(pubkey),
    createdAt,
    lastBeat,
    revokedAt,
    quotaBytes,
    usedBytes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GuestSessionRow &&
          other.sessionId == this.sessionId &&
          other.hostPeer == this.hostPeer &&
          $driftBlobEquality.equals(other.pubkey, this.pubkey) &&
          other.createdAt == this.createdAt &&
          other.lastBeat == this.lastBeat &&
          other.revokedAt == this.revokedAt &&
          other.quotaBytes == this.quotaBytes &&
          other.usedBytes == this.usedBytes);
}

class GuestSessionsCompanion extends UpdateCompanion<GuestSessionRow> {
  final Value<String> sessionId;
  final Value<String> hostPeer;
  final Value<Uint8List> pubkey;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastBeat;
  final Value<DateTime?> revokedAt;
  final Value<int> quotaBytes;
  final Value<int> usedBytes;
  final Value<int> rowid;
  const GuestSessionsCompanion({
    this.sessionId = const Value.absent(),
    this.hostPeer = const Value.absent(),
    this.pubkey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastBeat = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.quotaBytes = const Value.absent(),
    this.usedBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GuestSessionsCompanion.insert({
    required String sessionId,
    required String hostPeer,
    required Uint8List pubkey,
    required DateTime createdAt,
    required DateTime lastBeat,
    this.revokedAt = const Value.absent(),
    this.quotaBytes = const Value.absent(),
    this.usedBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       hostPeer = Value(hostPeer),
       pubkey = Value(pubkey),
       createdAt = Value(createdAt),
       lastBeat = Value(lastBeat);
  static Insertable<GuestSessionRow> custom({
    Expression<String>? sessionId,
    Expression<String>? hostPeer,
    Expression<Uint8List>? pubkey,
    Expression<int>? createdAt,
    Expression<int>? lastBeat,
    Expression<int>? revokedAt,
    Expression<int>? quotaBytes,
    Expression<int>? usedBytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (hostPeer != null) 'host_peer': hostPeer,
      if (pubkey != null) 'pubkey': pubkey,
      if (createdAt != null) 'created_at': createdAt,
      if (lastBeat != null) 'last_beat': lastBeat,
      if (revokedAt != null) 'revoked_at': revokedAt,
      if (quotaBytes != null) 'quota_bytes': quotaBytes,
      if (usedBytes != null) 'used_bytes': usedBytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GuestSessionsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? hostPeer,
    Value<Uint8List>? pubkey,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastBeat,
    Value<DateTime?>? revokedAt,
    Value<int>? quotaBytes,
    Value<int>? usedBytes,
    Value<int>? rowid,
  }) {
    return GuestSessionsCompanion(
      sessionId: sessionId ?? this.sessionId,
      hostPeer: hostPeer ?? this.hostPeer,
      pubkey: pubkey ?? this.pubkey,
      createdAt: createdAt ?? this.createdAt,
      lastBeat: lastBeat ?? this.lastBeat,
      revokedAt: revokedAt ?? this.revokedAt,
      quotaBytes: quotaBytes ?? this.quotaBytes,
      usedBytes: usedBytes ?? this.usedBytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (hostPeer.present) {
      map['host_peer'] = Variable<String>(hostPeer.value);
    }
    if (pubkey.present) {
      map['pubkey'] = Variable<Uint8List>(pubkey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $GuestSessionsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (lastBeat.present) {
      map['last_beat'] = Variable<int>(
        $GuestSessionsTable.$converterlastBeat.toSql(lastBeat.value),
      );
    }
    if (revokedAt.present) {
      map['revoked_at'] = Variable<int>(
        $GuestSessionsTable.$converterrevokedAtn.toSql(revokedAt.value),
      );
    }
    if (quotaBytes.present) {
      map['quota_bytes'] = Variable<int>(quotaBytes.value);
    }
    if (usedBytes.present) {
      map['used_bytes'] = Variable<int>(usedBytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GuestSessionsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('hostPeer: $hostPeer, ')
          ..write('pubkey: $pubkey, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastBeat: $lastBeat, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('quotaBytes: $quotaBytes, ')
          ..write('usedBytes: $usedBytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MsgSeensTable extends MsgSeens
    with TableInfo<$MsgSeensTable, MsgSeenRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MsgSeensTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES thread (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastHlcMeta = const VerificationMeta(
    'lastHlc',
  );
  @override
  late final GeneratedColumn<String> lastHlc = GeneratedColumn<String>(
    'last_hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [threadId, peerId, lastHlc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'msg_seen';
  @override
  VerificationContext validateIntegrity(
    Insertable<MsgSeenRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('last_hlc')) {
      context.handle(
        _lastHlcMeta,
        lastHlc.isAcceptableOrUnknown(data['last_hlc']!, _lastHlcMeta),
      );
    } else if (isInserting) {
      context.missing(_lastHlcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {threadId, peerId};
  @override
  MsgSeenRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MsgSeenRow(
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      lastHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_hlc'],
      )!,
    );
  }

  @override
  $MsgSeensTable createAlias(String alias) {
    return $MsgSeensTable(attachedDatabase, alias);
  }
}

class MsgSeenRow extends DataClass implements Insertable<MsgSeenRow> {
  final String threadId;
  final String peerId;

  /// 定宽 HLC 文本，规则见 [zeroPaddedHlc]。
  final String lastHlc;
  const MsgSeenRow({
    required this.threadId,
    required this.peerId,
    required this.lastHlc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['thread_id'] = Variable<String>(threadId);
    map['peer_id'] = Variable<String>(peerId);
    map['last_hlc'] = Variable<String>(lastHlc);
    return map;
  }

  MsgSeensCompanion toCompanion(bool nullToAbsent) {
    return MsgSeensCompanion(
      threadId: Value(threadId),
      peerId: Value(peerId),
      lastHlc: Value(lastHlc),
    );
  }

  factory MsgSeenRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MsgSeenRow(
      threadId: serializer.fromJson<String>(json['threadId']),
      peerId: serializer.fromJson<String>(json['peerId']),
      lastHlc: serializer.fromJson<String>(json['lastHlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'threadId': serializer.toJson<String>(threadId),
      'peerId': serializer.toJson<String>(peerId),
      'lastHlc': serializer.toJson<String>(lastHlc),
    };
  }

  MsgSeenRow copyWith({String? threadId, String? peerId, String? lastHlc}) =>
      MsgSeenRow(
        threadId: threadId ?? this.threadId,
        peerId: peerId ?? this.peerId,
        lastHlc: lastHlc ?? this.lastHlc,
      );
  MsgSeenRow copyWithCompanion(MsgSeensCompanion data) {
    return MsgSeenRow(
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      lastHlc: data.lastHlc.present ? data.lastHlc.value : this.lastHlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MsgSeenRow(')
          ..write('threadId: $threadId, ')
          ..write('peerId: $peerId, ')
          ..write('lastHlc: $lastHlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(threadId, peerId, lastHlc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MsgSeenRow &&
          other.threadId == this.threadId &&
          other.peerId == this.peerId &&
          other.lastHlc == this.lastHlc);
}

class MsgSeensCompanion extends UpdateCompanion<MsgSeenRow> {
  final Value<String> threadId;
  final Value<String> peerId;
  final Value<String> lastHlc;
  final Value<int> rowid;
  const MsgSeensCompanion({
    this.threadId = const Value.absent(),
    this.peerId = const Value.absent(),
    this.lastHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MsgSeensCompanion.insert({
    required String threadId,
    required String peerId,
    required String lastHlc,
    this.rowid = const Value.absent(),
  }) : threadId = Value(threadId),
       peerId = Value(peerId),
       lastHlc = Value(lastHlc);
  static Insertable<MsgSeenRow> custom({
    Expression<String>? threadId,
    Expression<String>? peerId,
    Expression<String>? lastHlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (threadId != null) 'thread_id': threadId,
      if (peerId != null) 'peer_id': peerId,
      if (lastHlc != null) 'last_hlc': lastHlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MsgSeensCompanion copyWith({
    Value<String>? threadId,
    Value<String>? peerId,
    Value<String>? lastHlc,
    Value<int>? rowid,
  }) {
    return MsgSeensCompanion(
      threadId: threadId ?? this.threadId,
      peerId: peerId ?? this.peerId,
      lastHlc: lastHlc ?? this.lastHlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (lastHlc.present) {
      map['last_hlc'] = Variable<String>(lastHlc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MsgSeensCompanion(')
          ..write('threadId: $threadId, ')
          ..write('peerId: $peerId, ')
          ..write('lastHlc: $lastHlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeerBlocksTable extends PeerBlocks
    with TableInfo<$PeerBlocksTable, PeerBlockRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeerBlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> until =
      GeneratedColumn<int>(
        'until',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($PeerBlocksTable.$converteruntiln);
  @override
  List<GeneratedColumn> get $columns => [peerId, reason, until];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'peer_block';
  @override
  VerificationContext validateIntegrity(
    Insertable<PeerBlockRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerId};
  @override
  PeerBlockRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeerBlockRow(
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      until: $PeerBlocksTable.$converteruntiln.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}until'],
        ),
      ),
    );
  }

  @override
  $PeerBlocksTable createAlias(String alias) {
    return $PeerBlocksTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converteruntil =
      const UnixMillisConverter();
  static TypeConverter<DateTime?, int?> $converteruntiln =
      NullAwareTypeConverter.wrap($converteruntil);
}

class PeerBlockRow extends DataClass implements Insertable<PeerBlockRow> {
  final String peerId;
  final String reason;
  final DateTime? until;
  const PeerBlockRow({required this.peerId, required this.reason, this.until});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_id'] = Variable<String>(peerId);
    map['reason'] = Variable<String>(reason);
    if (!nullToAbsent || until != null) {
      map['until'] = Variable<int>(
        $PeerBlocksTable.$converteruntiln.toSql(until),
      );
    }
    return map;
  }

  PeerBlocksCompanion toCompanion(bool nullToAbsent) {
    return PeerBlocksCompanion(
      peerId: Value(peerId),
      reason: Value(reason),
      until: until == null && nullToAbsent
          ? const Value.absent()
          : Value(until),
    );
  }

  factory PeerBlockRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeerBlockRow(
      peerId: serializer.fromJson<String>(json['peerId']),
      reason: serializer.fromJson<String>(json['reason']),
      until: serializer.fromJson<DateTime?>(json['until']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerId': serializer.toJson<String>(peerId),
      'reason': serializer.toJson<String>(reason),
      'until': serializer.toJson<DateTime?>(until),
    };
  }

  PeerBlockRow copyWith({
    String? peerId,
    String? reason,
    Value<DateTime?> until = const Value.absent(),
  }) => PeerBlockRow(
    peerId: peerId ?? this.peerId,
    reason: reason ?? this.reason,
    until: until.present ? until.value : this.until,
  );
  PeerBlockRow copyWithCompanion(PeerBlocksCompanion data) {
    return PeerBlockRow(
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      reason: data.reason.present ? data.reason.value : this.reason,
      until: data.until.present ? data.until.value : this.until,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeerBlockRow(')
          ..write('peerId: $peerId, ')
          ..write('reason: $reason, ')
          ..write('until: $until')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(peerId, reason, until);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeerBlockRow &&
          other.peerId == this.peerId &&
          other.reason == this.reason &&
          other.until == this.until);
}

class PeerBlocksCompanion extends UpdateCompanion<PeerBlockRow> {
  final Value<String> peerId;
  final Value<String> reason;
  final Value<DateTime?> until;
  final Value<int> rowid;
  const PeerBlocksCompanion({
    this.peerId = const Value.absent(),
    this.reason = const Value.absent(),
    this.until = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeerBlocksCompanion.insert({
    required String peerId,
    this.reason = const Value.absent(),
    this.until = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : peerId = Value(peerId);
  static Insertable<PeerBlockRow> custom({
    Expression<String>? peerId,
    Expression<String>? reason,
    Expression<int>? until,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerId != null) 'peer_id': peerId,
      if (reason != null) 'reason': reason,
      if (until != null) 'until': until,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeerBlocksCompanion copyWith({
    Value<String>? peerId,
    Value<String>? reason,
    Value<DateTime?>? until,
    Value<int>? rowid,
  }) {
    return PeerBlocksCompanion(
      peerId: peerId ?? this.peerId,
      reason: reason ?? this.reason,
      until: until ?? this.until,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (until.present) {
      map['until'] = Variable<int>(
        $PeerBlocksTable.$converteruntiln.toSql(until.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeerBlocksCompanion(')
          ..write('peerId: $peerId, ')
          ..write('reason: $reason, ')
          ..write('until: $until, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $SharesTable shares = $SharesTable(this);
  late final $ShareItemsTable shareItems = $ShareItemsTable(this);
  late final $GrantsTable grants = $GrantsTable(this);
  late final $ThreadsTable threads = $ThreadsTable(this);
  late final $GrpsTable grps = $GrpsTable(this);
  late final $GroupMembersTable groupMembers = $GroupMembersTable(this);
  late final $GroupKeysTable groupKeys = $GroupKeysTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final $OffersTable offers = $OffersTable(this);
  late final $TransfersTable transfers = $TransfersTable(this);
  late final $GuestSessionsTable guestSessions = $GuestSessionsTable(this);
  late final $MsgSeensTable msgSeens = $MsgSeensTable(this);
  late final $PeerBlocksTable peerBlocks = $PeerBlocksTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final Index idxShareOwner = Index(
    'idx_share_owner',
    'CREATE INDEX idx_share_owner ON share (owner_peer_id)',
  );
  late final Index idxShareSession = Index(
    'idx_share_session',
    'CREATE INDEX idx_share_session ON share (session_id)',
  );
  late final Index idxMessageThreadHlc = Index(
    'idx_message_thread_hlc',
    'CREATE INDEX idx_message_thread_hlc ON message (thread_id, hlc)',
  );
  late final Index idxAttachMsg = Index(
    'idx_attach_msg',
    'CREATE INDEX idx_attach_msg ON "attach" (msg_id)',
  );
  late final Index idxOfferToStatus = Index(
    'idx_offer_to_status',
    'CREATE INDEX idx_offer_to_status ON offer (to_peer, status)',
  );
  late final Index idxTransferStatus = Index(
    'idx_transfer_status',
    'CREATE INDEX idx_transfer_status ON transfer (status)',
  );
  late final Index idxGuestHost = Index(
    'idx_guest_host',
    'CREATE INDEX idx_guest_host ON guest_session (host_peer)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    devices,
    shares,
    shareItems,
    grants,
    threads,
    grps,
    groupMembers,
    groupKeys,
    messages,
    attachments,
    offers,
    transfers,
    guestSessions,
    msgSeens,
    peerBlocks,
    settings,
    idxShareOwner,
    idxShareSession,
    idxMessageThreadHlc,
    idxAttachMsg,
    idxOfferToStatus,
    idxTransferStatus,
    idxGuestHost,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'share',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('share_item', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'share',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('grant', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'grp',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('group_member', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'grp',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('group_key', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'thread',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('msg_seen', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$DevicesTableCreateCompanionBuilder = DevicesCompanion Function({
  required String peerId,
  required Uint8List pubkey,
  Value<String> alg,
  Value<String> name,
  Value<String> avatarHash,
  Value<String> os,
  required DateTime firstSeen,
  required DateTime lastSeen,
  Value<bool> online,
  Value<bool> isSelf,
  Value<bool> isGuest,
  Value<String> note,
  Value<int> rowid,
});
typedef $$DevicesTableUpdateCompanionBuilder = DevicesCompanion Function({
  Value<String> peerId,
  Value<Uint8List> pubkey,
  Value<String> alg,
  Value<String> name,
  Value<String> avatarHash,
  Value<String> os,
  Value<DateTime> firstSeen,
  Value<DateTime> lastSeen,
  Value<bool> online,
  Value<bool> isSelf,
  Value<bool> isGuest,
  Value<String> note,
  Value<int> rowid,
});

class $$DevicesTableFilterComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alg => $composableBuilder(
    column: $table.alg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarHash => $composableBuilder(
    column: $table.avatarHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get os => $composableBuilder(
    column: $table.os,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get firstSeen =>
      $composableBuilder(
        column: $table.firstSeen,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get lastSeen =>
      $composableBuilder(
        column: $table.lastSeen,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get online => $composableBuilder(
    column: $table.online,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSelf => $composableBuilder(
    column: $table.isSelf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isGuest => $composableBuilder(
    column: $table.isGuest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alg => $composableBuilder(
    column: $table.alg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarHash => $composableBuilder(
    column: $table.avatarHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get os => $composableBuilder(
    column: $table.os,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get online => $composableBuilder(
    column: $table.online,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSelf => $composableBuilder(
    column: $table.isSelf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isGuest => $composableBuilder(
    column: $table.isGuest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<Uint8List> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<String> get alg =>
      $composableBuilder(column: $table.alg, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatarHash => $composableBuilder(
    column: $table.avatarHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get os =>
      $composableBuilder(column: $table.os, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get firstSeen =>
      $composableBuilder(column: $table.firstSeen, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<bool> get online =>
      $composableBuilder(column: $table.online, builder: (column) => column);

  GeneratedColumn<bool> get isSelf =>
      $composableBuilder(column: $table.isSelf, builder: (column) => column);

  GeneratedColumn<bool> get isGuest =>
      $composableBuilder(column: $table.isGuest, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DevicesTable,
          DeviceRow,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (DeviceRow, BaseReferences<_$AppDatabase, $DevicesTable, DeviceRow>),
          DeviceRow,
          PrefetchHooks Function()
        > {
  $$DevicesTableTableManager(_$AppDatabase db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> peerId = const Value.absent(),
                Value<Uint8List> pubkey = const Value.absent(),
                Value<String> alg = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> avatarHash = const Value.absent(),
                Value<String> os = const Value.absent(),
                Value<DateTime> firstSeen = const Value.absent(),
                Value<DateTime> lastSeen = const Value.absent(),
                Value<bool> online = const Value.absent(),
                Value<bool> isSelf = const Value.absent(),
                Value<bool> isGuest = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                peerId: peerId,
                pubkey: pubkey,
                alg: alg,
                name: name,
                avatarHash: avatarHash,
                os: os,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                online: online,
                isSelf: isSelf,
                isGuest: isGuest,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerId,
                required Uint8List pubkey,
                Value<String> alg = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> avatarHash = const Value.absent(),
                Value<String> os = const Value.absent(),
                required DateTime firstSeen,
                required DateTime lastSeen,
                Value<bool> online = const Value.absent(),
                Value<bool> isSelf = const Value.absent(),
                Value<bool> isGuest = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                peerId: peerId,
                pubkey: pubkey,
                alg: alg,
                name: name,
                avatarHash: avatarHash,
                os: os,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                online: online,
                isSelf: isSelf,
                isGuest: isGuest,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DevicesTable, DeviceRow>(table),
                  BaseReferences<_$AppDatabase, $DevicesTable, DeviceRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DevicesTable,
      DeviceRow,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (DeviceRow, BaseReferences<_$AppDatabase, $DevicesTable, DeviceRow>),
      DeviceRow,
      PrefetchHooks Function()
    >;
typedef $$SharesTableCreateCompanionBuilder = SharesCompanion Function({
  required String id,
  required String kind,
  required String rootKind,
  required String rootUri,
  required String displayName,
  required String ownerPeerId,
  required DateTime createdAt,
  Value<DateTime?> expiresAt,
  required ShareMode mode,
  Value<String?> passwordHash,
  Value<String?> groupId,
  Value<int?> maxSpeedKbps,
  Value<bool> enabled,
  Value<bool> missing,
  Value<DateTime?> revokedAt,
  Value<String?> sessionId,
  Value<bool> isEphemeral,
  Value<int> rowid,
});
typedef $$SharesTableUpdateCompanionBuilder = SharesCompanion Function({
  Value<String> id,
  Value<String> kind,
  Value<String> rootKind,
  Value<String> rootUri,
  Value<String> displayName,
  Value<String> ownerPeerId,
  Value<DateTime> createdAt,
  Value<DateTime?> expiresAt,
  Value<ShareMode> mode,
  Value<String?> passwordHash,
  Value<String?> groupId,
  Value<int?> maxSpeedKbps,
  Value<bool> enabled,
  Value<bool> missing,
  Value<DateTime?> revokedAt,
  Value<String?> sessionId,
  Value<bool> isEphemeral,
  Value<int> rowid,
});

final class $$SharesTableReferences
    extends BaseReferences<_$AppDatabase, $SharesTable, ShareRow> {
  $$SharesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ShareItemsTable, List<ShareItemRow>>
  _shareItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.shareItems,
    aliasName: 'share__id__share_item__share_id',
  );

  $$ShareItemsTableProcessedTableManager get shareItemsRefs {
    final manager = $$ShareItemsTableTableManager(
      $_db,
      $_db.shareItems,
    ).filter((f) => f.shareId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_shareItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$GrantsTable, List<GrantRow>> _grantsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.grants,
    aliasName: 'share__id__grant__share_id',
  );

  $$GrantsTableProcessedTableManager get grantsRefs {
    final manager = $$GrantsTableTableManager(
      $_db,
      $_db.grants,
    ).filter((f) => f.shareId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_grantsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SharesTableFilterComposer
    extends Composer<_$AppDatabase, $SharesTable> {
  $$SharesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootKind => $composableBuilder(
    column: $table.rootKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootUri => $composableBuilder(
    column: $table.rootUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get expiresAt =>
      $composableBuilder(
        column: $table.expiresAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<ShareMode, ShareMode, String> get mode =>
      $composableBuilder(
        column: $table.mode,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxSpeedKbps => $composableBuilder(
    column: $table.maxSpeedKbps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get missing => $composableBuilder(
    column: $table.missing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get revokedAt =>
      $composableBuilder(
        column: $table.revokedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEphemeral => $composableBuilder(
    column: $table.isEphemeral,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> shareItemsRefs(
    Expression<bool> Function($$ShareItemsTableFilterComposer f) f,
  ) {
    final $$ShareItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shareItems,
      getReferencedColumn: (t) => t.shareId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShareItemsTableFilterComposer(
            $db: $db,
            $table: $db.shareItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> grantsRefs(
    Expression<bool> Function($$GrantsTableFilterComposer f) f,
  ) {
    final $$GrantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.grants,
      getReferencedColumn: (t) => t.shareId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GrantsTableFilterComposer(
            $db: $db,
            $table: $db.grants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SharesTableOrderingComposer
    extends Composer<_$AppDatabase, $SharesTable> {
  $$SharesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootKind => $composableBuilder(
    column: $table.rootKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootUri => $composableBuilder(
    column: $table.rootUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxSpeedKbps => $composableBuilder(
    column: $table.maxSpeedKbps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get missing => $composableBuilder(
    column: $table.missing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revokedAt => $composableBuilder(
    column: $table.revokedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEphemeral => $composableBuilder(
    column: $table.isEphemeral,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SharesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SharesTable> {
  $$SharesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get rootKind =>
      $composableBuilder(column: $table.rootKind, builder: (column) => column);

  GeneratedColumn<String> get rootUri =>
      $composableBuilder(column: $table.rootUri, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ShareMode, String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<int> get maxSpeedKbps => $composableBuilder(
    column: $table.maxSpeedKbps,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get missing =>
      $composableBuilder(column: $table.missing, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get revokedAt =>
      $composableBuilder(column: $table.revokedAt, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<bool> get isEphemeral => $composableBuilder(
    column: $table.isEphemeral,
    builder: (column) => column,
  );

  Expression<T> shareItemsRefs<T extends Object>(
    Expression<T> Function($$ShareItemsTableAnnotationComposer a) f,
  ) {
    final $$ShareItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shareItems,
      getReferencedColumn: (t) => t.shareId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShareItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.shareItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> grantsRefs<T extends Object>(
    Expression<T> Function($$GrantsTableAnnotationComposer a) f,
  ) {
    final $$GrantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.grants,
      getReferencedColumn: (t) => t.shareId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GrantsTableAnnotationComposer(
            $db: $db,
            $table: $db.grants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SharesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SharesTable,
          ShareRow,
          $$SharesTableFilterComposer,
          $$SharesTableOrderingComposer,
          $$SharesTableAnnotationComposer,
          $$SharesTableCreateCompanionBuilder,
          $$SharesTableUpdateCompanionBuilder,
          (ShareRow, $$SharesTableReferences),
          ShareRow,
          PrefetchHooks Function({bool shareItemsRefs, bool grantsRefs})
        > {
  $$SharesTableTableManager(_$AppDatabase db, $SharesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SharesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SharesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SharesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> rootKind = const Value.absent(),
                Value<String> rootUri = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> ownerPeerId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<ShareMode> mode = const Value.absent(),
                Value<String?> passwordHash = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<int?> maxSpeedKbps = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> missing = const Value.absent(),
                Value<DateTime?> revokedAt = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<bool> isEphemeral = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SharesCompanion(
                id: id,
                kind: kind,
                rootKind: rootKind,
                rootUri: rootUri,
                displayName: displayName,
                ownerPeerId: ownerPeerId,
                createdAt: createdAt,
                expiresAt: expiresAt,
                mode: mode,
                passwordHash: passwordHash,
                groupId: groupId,
                maxSpeedKbps: maxSpeedKbps,
                enabled: enabled,
                missing: missing,
                revokedAt: revokedAt,
                sessionId: sessionId,
                isEphemeral: isEphemeral,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String rootKind,
                required String rootUri,
                required String displayName,
                required String ownerPeerId,
                required DateTime createdAt,
                Value<DateTime?> expiresAt = const Value.absent(),
                required ShareMode mode,
                Value<String?> passwordHash = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<int?> maxSpeedKbps = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> missing = const Value.absent(),
                Value<DateTime?> revokedAt = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<bool> isEphemeral = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SharesCompanion.insert(
                id: id,
                kind: kind,
                rootKind: rootKind,
                rootUri: rootUri,
                displayName: displayName,
                ownerPeerId: ownerPeerId,
                createdAt: createdAt,
                expiresAt: expiresAt,
                mode: mode,
                passwordHash: passwordHash,
                groupId: groupId,
                maxSpeedKbps: maxSpeedKbps,
                enabled: enabled,
                missing: missing,
                revokedAt: revokedAt,
                sessionId: sessionId,
                isEphemeral: isEphemeral,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SharesTable, ShareRow>(table),
                  $$SharesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({shareItemsRefs = false, grantsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (shareItemsRefs) db.shareItems,
                    if (grantsRefs) db.grants,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (shareItemsRefs)
                        await $_getPrefetchedDataByColumns<
                          ShareRow,
                          $SharesTable,
                          ShareItemRow,
                          $ShareItemsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SharesTableReferences
                              ._shareItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SharesTableReferences(
                                db,
                                table,
                                p0,
                              ).shareItemsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'share_id',
                          typedResults: items,
                        ),
                      if (grantsRefs)
                        await $_getPrefetchedDataByColumns<
                          ShareRow,
                          $SharesTable,
                          GrantRow,
                          $GrantsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SharesTableReferences
                              ._grantsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SharesTableReferences(db, table, p0).grantsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'share_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SharesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SharesTable,
      ShareRow,
      $$SharesTableFilterComposer,
      $$SharesTableOrderingComposer,
      $$SharesTableAnnotationComposer,
      $$SharesTableCreateCompanionBuilder,
      $$SharesTableUpdateCompanionBuilder,
      (ShareRow, $$SharesTableReferences),
      ShareRow,
      PrefetchHooks Function({bool shareItemsRefs, bool grantsRefs})
    >;
typedef $$ShareItemsTableCreateCompanionBuilder = ShareItemsCompanion Function({
  required String shareId,
  required String itemKey,
  Value<String> relPath,
  Value<int> size,
  Value<DateTime?> mtime,
  Value<String?> mime,
  Value<bool> isDir,
  Value<int> rowid,
});
typedef $$ShareItemsTableUpdateCompanionBuilder = ShareItemsCompanion Function({
  Value<String> shareId,
  Value<String> itemKey,
  Value<String> relPath,
  Value<int> size,
  Value<DateTime?> mtime,
  Value<String?> mime,
  Value<bool> isDir,
  Value<int> rowid,
});

final class $$ShareItemsTableReferences
    extends BaseReferences<_$AppDatabase, $ShareItemsTable, ShareItemRow> {
  $$ShareItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SharesTable _shareIdTable(_$AppDatabase db) =>
      db.shares.createAlias('share_item__share_id__share__id');

  $$SharesTableProcessedTableManager get shareId {
    final $_column = $_itemColumn<String>('share_id')!;

    final manager = $$SharesTableTableManager(
      $_db,
      $_db.shares,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shareIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ShareItemsTableFilterComposer
    extends Composer<_$AppDatabase, $ShareItemsTable> {
  $$ShareItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relPath => $composableBuilder(
    column: $table.relPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get mtime =>
      $composableBuilder(
        column: $table.mtime,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDir => $composableBuilder(
    column: $table.isDir,
    builder: (column) => ColumnFilters(column),
  );

  $$SharesTableFilterComposer get shareId {
    final $$SharesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shareId,
      referencedTable: $db.shares,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SharesTableFilterComposer(
            $db: $db,
            $table: $db.shares,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShareItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShareItemsTable> {
  $$ShareItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relPath => $composableBuilder(
    column: $table.relPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDir => $composableBuilder(
    column: $table.isDir,
    builder: (column) => ColumnOrderings(column),
  );

  $$SharesTableOrderingComposer get shareId {
    final $$SharesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shareId,
      referencedTable: $db.shares,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SharesTableOrderingComposer(
            $db: $db,
            $table: $db.shares,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShareItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShareItemsTable> {
  $$ShareItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemKey =>
      $composableBuilder(column: $table.itemKey, builder: (column) => column);

  GeneratedColumn<String> get relPath =>
      $composableBuilder(column: $table.relPath, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get mtime =>
      $composableBuilder(column: $table.mtime, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<bool> get isDir =>
      $composableBuilder(column: $table.isDir, builder: (column) => column);

  $$SharesTableAnnotationComposer get shareId {
    final $$SharesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shareId,
      referencedTable: $db.shares,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SharesTableAnnotationComposer(
            $db: $db,
            $table: $db.shares,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShareItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShareItemsTable,
          ShareItemRow,
          $$ShareItemsTableFilterComposer,
          $$ShareItemsTableOrderingComposer,
          $$ShareItemsTableAnnotationComposer,
          $$ShareItemsTableCreateCompanionBuilder,
          $$ShareItemsTableUpdateCompanionBuilder,
          (ShareItemRow, $$ShareItemsTableReferences),
          ShareItemRow,
          PrefetchHooks Function({bool shareId})
        > {
  $$ShareItemsTableTableManager(_$AppDatabase db, $ShareItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShareItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShareItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShareItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> shareId = const Value.absent(),
                Value<String> itemKey = const Value.absent(),
                Value<String> relPath = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<DateTime?> mtime = const Value.absent(),
                Value<String?> mime = const Value.absent(),
                Value<bool> isDir = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShareItemsCompanion(
                shareId: shareId,
                itemKey: itemKey,
                relPath: relPath,
                size: size,
                mtime: mtime,
                mime: mime,
                isDir: isDir,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String shareId,
                required String itemKey,
                Value<String> relPath = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<DateTime?> mtime = const Value.absent(),
                Value<String?> mime = const Value.absent(),
                Value<bool> isDir = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShareItemsCompanion.insert(
                shareId: shareId,
                itemKey: itemKey,
                relPath: relPath,
                size: size,
                mtime: mtime,
                mime: mime,
                isDir: isDir,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShareItemsTable, ShareItemRow>(table),
                  $$ShareItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shareId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shareId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.shareId,
                        referencedTable: $$ShareItemsTableReferences
                            ._shareIdTable(db),
                        referencedColumn: $$ShareItemsTableReferences
                            ._shareIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ShareItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShareItemsTable,
      ShareItemRow,
      $$ShareItemsTableFilterComposer,
      $$ShareItemsTableOrderingComposer,
      $$ShareItemsTableAnnotationComposer,
      $$ShareItemsTableCreateCompanionBuilder,
      $$ShareItemsTableUpdateCompanionBuilder,
      (ShareItemRow, $$ShareItemsTableReferences),
      ShareItemRow,
      PrefetchHooks Function({bool shareId})
    >;
typedef $$GrantsTableCreateCompanionBuilder = GrantsCompanion Function({
  required String shareId,
  required String peerId,
  required DateTime grantedAt,
  Value<DateTime?> expiresAt,
  Value<int> rowid,
});
typedef $$GrantsTableUpdateCompanionBuilder = GrantsCompanion Function({
  Value<String> shareId,
  Value<String> peerId,
  Value<DateTime> grantedAt,
  Value<DateTime?> expiresAt,
  Value<int> rowid,
});

final class $$GrantsTableReferences
    extends BaseReferences<_$AppDatabase, $GrantsTable, GrantRow> {
  $$GrantsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SharesTable _shareIdTable(_$AppDatabase db) =>
      db.shares.createAlias('grant__share_id__share__id');

  $$SharesTableProcessedTableManager get shareId {
    final $_column = $_itemColumn<String>('share_id')!;

    final manager = $$SharesTableTableManager(
      $_db,
      $_db.shares,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shareIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GrantsTableFilterComposer
    extends Composer<_$AppDatabase, $GrantsTable> {
  $$GrantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get grantedAt =>
      $composableBuilder(
        column: $table.grantedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get expiresAt =>
      $composableBuilder(
        column: $table.expiresAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$SharesTableFilterComposer get shareId {
    final $$SharesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shareId,
      referencedTable: $db.shares,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SharesTableFilterComposer(
            $db: $db,
            $table: $db.shares,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GrantsTableOrderingComposer
    extends Composer<_$AppDatabase, $GrantsTable> {
  $$GrantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get grantedAt => $composableBuilder(
    column: $table.grantedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SharesTableOrderingComposer get shareId {
    final $$SharesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shareId,
      referencedTable: $db.shares,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SharesTableOrderingComposer(
            $db: $db,
            $table: $db.shares,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GrantsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GrantsTable> {
  $$GrantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get grantedAt =>
      $composableBuilder(column: $table.grantedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  $$SharesTableAnnotationComposer get shareId {
    final $$SharesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shareId,
      referencedTable: $db.shares,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SharesTableAnnotationComposer(
            $db: $db,
            $table: $db.shares,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GrantsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GrantsTable,
          GrantRow,
          $$GrantsTableFilterComposer,
          $$GrantsTableOrderingComposer,
          $$GrantsTableAnnotationComposer,
          $$GrantsTableCreateCompanionBuilder,
          $$GrantsTableUpdateCompanionBuilder,
          (GrantRow, $$GrantsTableReferences),
          GrantRow,
          PrefetchHooks Function({bool shareId})
        > {
  $$GrantsTableTableManager(_$AppDatabase db, $GrantsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GrantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GrantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GrantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> shareId = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<DateTime> grantedAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GrantsCompanion(
                shareId: shareId,
                peerId: peerId,
                grantedAt: grantedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String shareId,
                required String peerId,
                required DateTime grantedAt,
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GrantsCompanion.insert(
                shareId: shareId,
                peerId: peerId,
                grantedAt: grantedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GrantsTable, GrantRow>(table),
                  $$GrantsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shareId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shareId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.shareId,
                        referencedTable: $$GrantsTableReferences._shareIdTable(
                          db,
                        ),
                        referencedColumn: $$GrantsTableReferences
                            ._shareIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GrantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GrantsTable,
      GrantRow,
      $$GrantsTableFilterComposer,
      $$GrantsTableOrderingComposer,
      $$GrantsTableAnnotationComposer,
      $$GrantsTableCreateCompanionBuilder,
      $$GrantsTableUpdateCompanionBuilder,
      (GrantRow, $$GrantsTableReferences),
      GrantRow,
      PrefetchHooks Function({bool shareId})
    >;
typedef $$ThreadsTableCreateCompanionBuilder = ThreadsCompanion Function({
  required String id,
  required String kind,
  Value<String> title,
  Value<String> avatarHash,
  Value<String?> peerId,
  Value<String?> groupId,
  Value<String?> lastMsgHlc,
  Value<String?> lastMsgPreview,
  Value<int> unread,
  Value<bool> muted,
  Value<bool> pinned,
  required DateTime createdAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$ThreadsTableUpdateCompanionBuilder = ThreadsCompanion Function({
  Value<String> id,
  Value<String> kind,
  Value<String> title,
  Value<String> avatarHash,
  Value<String?> peerId,
  Value<String?> groupId,
  Value<String?> lastMsgHlc,
  Value<String?> lastMsgPreview,
  Value<int> unread,
  Value<bool> muted,
  Value<bool> pinned,
  Value<DateTime> createdAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$ThreadsTableReferences
    extends BaseReferences<_$AppDatabase, $ThreadsTable, ThreadRow> {
  $$ThreadsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MsgSeensTable, List<MsgSeenRow>>
  _msgSeensRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.msgSeens,
    aliasName: 'thread__id__msg_seen__thread_id',
  );

  $$MsgSeensTableProcessedTableManager get msgSeensRefs {
    final manager = $$MsgSeensTableTableManager(
      $_db,
      $_db.msgSeens,
    ).filter((f) => f.threadId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_msgSeensRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ThreadsTableFilterComposer
    extends Composer<_$AppDatabase, $ThreadsTable> {
  $$ThreadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarHash => $composableBuilder(
    column: $table.avatarHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMsgHlc => $composableBuilder(
    column: $table.lastMsgHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMsgPreview => $composableBuilder(
    column: $table.lastMsgPreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unread => $composableBuilder(
    column: $table.unread,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get muted => $composableBuilder(
    column: $table.muted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  Expression<bool> msgSeensRefs(
    Expression<bool> Function($$MsgSeensTableFilterComposer f) f,
  ) {
    final $$MsgSeensTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.msgSeens,
      getReferencedColumn: (t) => t.threadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MsgSeensTableFilterComposer(
            $db: $db,
            $table: $db.msgSeens,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ThreadsTableOrderingComposer
    extends Composer<_$AppDatabase, $ThreadsTable> {
  $$ThreadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarHash => $composableBuilder(
    column: $table.avatarHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMsgHlc => $composableBuilder(
    column: $table.lastMsgHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMsgPreview => $composableBuilder(
    column: $table.lastMsgPreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unread => $composableBuilder(
    column: $table.unread,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get muted => $composableBuilder(
    column: $table.muted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ThreadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ThreadsTable> {
  $$ThreadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get avatarHash => $composableBuilder(
    column: $table.avatarHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get lastMsgHlc => $composableBuilder(
    column: $table.lastMsgHlc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMsgPreview => $composableBuilder(
    column: $table.lastMsgPreview,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unread =>
      $composableBuilder(column: $table.unread, builder: (column) => column);

  GeneratedColumn<bool> get muted =>
      $composableBuilder(column: $table.muted, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> msgSeensRefs<T extends Object>(
    Expression<T> Function($$MsgSeensTableAnnotationComposer a) f,
  ) {
    final $$MsgSeensTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.msgSeens,
      getReferencedColumn: (t) => t.threadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MsgSeensTableAnnotationComposer(
            $db: $db,
            $table: $db.msgSeens,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ThreadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ThreadsTable,
          ThreadRow,
          $$ThreadsTableFilterComposer,
          $$ThreadsTableOrderingComposer,
          $$ThreadsTableAnnotationComposer,
          $$ThreadsTableCreateCompanionBuilder,
          $$ThreadsTableUpdateCompanionBuilder,
          (ThreadRow, $$ThreadsTableReferences),
          ThreadRow,
          PrefetchHooks Function({bool msgSeensRefs})
        > {
  $$ThreadsTableTableManager(_$AppDatabase db, $ThreadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThreadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThreadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThreadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> avatarHash = const Value.absent(),
                Value<String?> peerId = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String?> lastMsgHlc = const Value.absent(),
                Value<String?> lastMsgPreview = const Value.absent(),
                Value<int> unread = const Value.absent(),
                Value<bool> muted = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThreadsCompanion(
                id: id,
                kind: kind,
                title: title,
                avatarHash: avatarHash,
                peerId: peerId,
                groupId: groupId,
                lastMsgHlc: lastMsgHlc,
                lastMsgPreview: lastMsgPreview,
                unread: unread,
                muted: muted,
                pinned: pinned,
                createdAt: createdAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                Value<String> title = const Value.absent(),
                Value<String> avatarHash = const Value.absent(),
                Value<String?> peerId = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String?> lastMsgHlc = const Value.absent(),
                Value<String?> lastMsgPreview = const Value.absent(),
                Value<int> unread = const Value.absent(),
                Value<bool> muted = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThreadsCompanion.insert(
                id: id,
                kind: kind,
                title: title,
                avatarHash: avatarHash,
                peerId: peerId,
                groupId: groupId,
                lastMsgHlc: lastMsgHlc,
                lastMsgPreview: lastMsgPreview,
                unread: unread,
                muted: muted,
                pinned: pinned,
                createdAt: createdAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ThreadsTable, ThreadRow>(table),
                  $$ThreadsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({msgSeensRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (msgSeensRefs) db.msgSeens],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (msgSeensRefs)
                    await $_getPrefetchedDataByColumns<
                      ThreadRow,
                      $ThreadsTable,
                      MsgSeenRow,
                      $MsgSeensTable
                    >(
                      currentTable: table,
                      referencedTable: $$ThreadsTableReferences
                          ._msgSeensRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ThreadsTableReferences(db, table, p0).msgSeensRefs,
                      currentColumn: 'id',
                      referencedColumn: 'thread_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ThreadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ThreadsTable,
      ThreadRow,
      $$ThreadsTableFilterComposer,
      $$ThreadsTableOrderingComposer,
      $$ThreadsTableAnnotationComposer,
      $$ThreadsTableCreateCompanionBuilder,
      $$ThreadsTableUpdateCompanionBuilder,
      (ThreadRow, $$ThreadsTableReferences),
      ThreadRow,
      PrefetchHooks Function({bool msgSeensRefs})
    >;
typedef $$GrpsTableCreateCompanionBuilder = GrpsCompanion Function({
  required String id,
  Value<String> name,
  Value<String> avatarHash,
  required String ownerPeerId,
  required DateTime createdAt,
  Value<int> epoch,
  Value<int> rowid,
});
typedef $$GrpsTableUpdateCompanionBuilder = GrpsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> avatarHash,
  Value<String> ownerPeerId,
  Value<DateTime> createdAt,
  Value<int> epoch,
  Value<int> rowid,
});

final class $$GrpsTableReferences
    extends BaseReferences<_$AppDatabase, $GrpsTable, GrpRow> {
  $$GrpsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$GroupMembersTable, List<GroupMemberRow>>
  _groupMembersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.groupMembers,
    aliasName: 'grp__id__group_member__group_id',
  );

  $$GroupMembersTableProcessedTableManager get groupMembersRefs {
    final manager = $$GroupMembersTableTableManager(
      $_db,
      $_db.groupMembers,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_groupMembersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$GroupKeysTable, List<GroupKeyRow>>
  _groupKeysRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.groupKeys,
    aliasName: 'grp__id__group_key__group_id',
  );

  $$GroupKeysTableProcessedTableManager get groupKeysRefs {
    final manager = $$GroupKeysTableTableManager(
      $_db,
      $_db.groupKeys,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_groupKeysRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GrpsTableFilterComposer extends Composer<_$AppDatabase, $GrpsTable> {
  $$GrpsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarHash => $composableBuilder(
    column: $table.avatarHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> groupMembersRefs(
    Expression<bool> Function($$GroupMembersTableFilterComposer f) f,
  ) {
    final $$GroupMembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.groupMembers,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupMembersTableFilterComposer(
            $db: $db,
            $table: $db.groupMembers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> groupKeysRefs(
    Expression<bool> Function($$GroupKeysTableFilterComposer f) f,
  ) {
    final $$GroupKeysTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.groupKeys,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupKeysTableFilterComposer(
            $db: $db,
            $table: $db.groupKeys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GrpsTableOrderingComposer extends Composer<_$AppDatabase, $GrpsTable> {
  $$GrpsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarHash => $composableBuilder(
    column: $table.avatarHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GrpsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GrpsTable> {
  $$GrpsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatarHash => $composableBuilder(
    column: $table.avatarHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get epoch =>
      $composableBuilder(column: $table.epoch, builder: (column) => column);

  Expression<T> groupMembersRefs<T extends Object>(
    Expression<T> Function($$GroupMembersTableAnnotationComposer a) f,
  ) {
    final $$GroupMembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.groupMembers,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupMembersTableAnnotationComposer(
            $db: $db,
            $table: $db.groupMembers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> groupKeysRefs<T extends Object>(
    Expression<T> Function($$GroupKeysTableAnnotationComposer a) f,
  ) {
    final $$GroupKeysTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.groupKeys,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupKeysTableAnnotationComposer(
            $db: $db,
            $table: $db.groupKeys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GrpsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GrpsTable,
          GrpRow,
          $$GrpsTableFilterComposer,
          $$GrpsTableOrderingComposer,
          $$GrpsTableAnnotationComposer,
          $$GrpsTableCreateCompanionBuilder,
          $$GrpsTableUpdateCompanionBuilder,
          (GrpRow, $$GrpsTableReferences),
          GrpRow,
          PrefetchHooks Function({bool groupMembersRefs, bool groupKeysRefs})
        > {
  $$GrpsTableTableManager(_$AppDatabase db, $GrpsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GrpsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GrpsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GrpsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> avatarHash = const Value.absent(),
                Value<String> ownerPeerId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> epoch = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GrpsCompanion(
                id: id,
                name: name,
                avatarHash: avatarHash,
                ownerPeerId: ownerPeerId,
                createdAt: createdAt,
                epoch: epoch,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> name = const Value.absent(),
                Value<String> avatarHash = const Value.absent(),
                required String ownerPeerId,
                required DateTime createdAt,
                Value<int> epoch = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GrpsCompanion.insert(
                id: id,
                name: name,
                avatarHash: avatarHash,
                ownerPeerId: ownerPeerId,
                createdAt: createdAt,
                epoch: epoch,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GrpsTable, GrpRow>(table),
                  $$GrpsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({groupMembersRefs = false, groupKeysRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (groupMembersRefs) db.groupMembers,
                    if (groupKeysRefs) db.groupKeys,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (groupMembersRefs)
                        await $_getPrefetchedDataByColumns<
                          GrpRow,
                          $GrpsTable,
                          GroupMemberRow,
                          $GroupMembersTable
                        >(
                          currentTable: table,
                          referencedTable: $$GrpsTableReferences
                              ._groupMembersRefsTable(db),
                          managerFromTypedResult: (p0) => $$GrpsTableReferences(
                            db,
                            table,
                            p0,
                          ).groupMembersRefs,
                          currentColumn: 'id',
                          referencedColumn: 'group_id',
                          typedResults: items,
                        ),
                      if (groupKeysRefs)
                        await $_getPrefetchedDataByColumns<
                          GrpRow,
                          $GrpsTable,
                          GroupKeyRow,
                          $GroupKeysTable
                        >(
                          currentTable: table,
                          referencedTable: $$GrpsTableReferences
                              ._groupKeysRefsTable(db),
                          managerFromTypedResult: (p0) => $$GrpsTableReferences(
                            db,
                            table,
                            p0,
                          ).groupKeysRefs,
                          currentColumn: 'id',
                          referencedColumn: 'group_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$GrpsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GrpsTable,
      GrpRow,
      $$GrpsTableFilterComposer,
      $$GrpsTableOrderingComposer,
      $$GrpsTableAnnotationComposer,
      $$GrpsTableCreateCompanionBuilder,
      $$GrpsTableUpdateCompanionBuilder,
      (GrpRow, $$GrpsTableReferences),
      GrpRow,
      PrefetchHooks Function({bool groupMembersRefs, bool groupKeysRefs})
    >;
typedef $$GroupMembersTableCreateCompanionBuilder =
    GroupMembersCompanion Function({
      required String groupId,
      required String peerId,
      Value<String> role,
      required DateTime joinedAt,
      Value<DateTime?> lastSeen,
      Value<int> rowid,
    });
typedef $$GroupMembersTableUpdateCompanionBuilder =
    GroupMembersCompanion Function({
      Value<String> groupId,
      Value<String> peerId,
      Value<String> role,
      Value<DateTime> joinedAt,
      Value<DateTime?> lastSeen,
      Value<int> rowid,
    });

final class $$GroupMembersTableReferences
    extends BaseReferences<_$AppDatabase, $GroupMembersTable, GroupMemberRow> {
  $$GroupMembersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GrpsTable _groupIdTable(_$AppDatabase db) =>
      db.grps.createAlias('group_member__group_id__grp__id');

  $$GrpsTableProcessedTableManager get groupId {
    final $_column = $_itemColumn<String>('group_id')!;

    final manager = $$GrpsTableTableManager(
      $_db,
      $_db.grps,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GroupMembersTableFilterComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get joinedAt =>
      $composableBuilder(
        column: $table.joinedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get lastSeen =>
      $composableBuilder(
        column: $table.lastSeen,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$GrpsTableFilterComposer get groupId {
    final $$GrpsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.grps,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GrpsTableFilterComposer(
            $db: $db,
            $table: $db.grps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupMembersTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get joinedAt => $composableBuilder(
    column: $table.joinedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  $$GrpsTableOrderingComposer get groupId {
    final $$GrpsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.grps,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GrpsTableOrderingComposer(
            $db: $db,
            $table: $db.grps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupMembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get joinedAt =>
      $composableBuilder(column: $table.joinedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  $$GrpsTableAnnotationComposer get groupId {
    final $$GrpsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.grps,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GrpsTableAnnotationComposer(
            $db: $db,
            $table: $db.grps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupMembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupMembersTable,
          GroupMemberRow,
          $$GroupMembersTableFilterComposer,
          $$GroupMembersTableOrderingComposer,
          $$GroupMembersTableAnnotationComposer,
          $$GroupMembersTableCreateCompanionBuilder,
          $$GroupMembersTableUpdateCompanionBuilder,
          (GroupMemberRow, $$GroupMembersTableReferences),
          GroupMemberRow,
          PrefetchHooks Function({bool groupId})
        > {
  $$GroupMembersTableTableManager(_$AppDatabase db, $GroupMembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<DateTime> joinedAt = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupMembersCompanion(
                groupId: groupId,
                peerId: peerId,
                role: role,
                joinedAt: joinedAt,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String peerId,
                Value<String> role = const Value.absent(),
                required DateTime joinedAt,
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupMembersCompanion.insert(
                groupId: groupId,
                peerId: peerId,
                role: role,
                joinedAt: joinedAt,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GroupMembersTable, GroupMemberRow>(table),
                  $$GroupMembersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (groupId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.groupId,
                        referencedTable: $$GroupMembersTableReferences
                            ._groupIdTable(db),
                        referencedColumn: $$GroupMembersTableReferences
                            ._groupIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GroupMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupMembersTable,
      GroupMemberRow,
      $$GroupMembersTableFilterComposer,
      $$GroupMembersTableOrderingComposer,
      $$GroupMembersTableAnnotationComposer,
      $$GroupMembersTableCreateCompanionBuilder,
      $$GroupMembersTableUpdateCompanionBuilder,
      (GroupMemberRow, $$GroupMembersTableReferences),
      GroupMemberRow,
      PrefetchHooks Function({bool groupId})
    >;
typedef $$GroupKeysTableCreateCompanionBuilder = GroupKeysCompanion Function({
  required String groupId,
  required int epoch,
  required String wrappedForPeer,
  required Uint8List wrappedBlob,
  Value<int> rowid,
});
typedef $$GroupKeysTableUpdateCompanionBuilder = GroupKeysCompanion Function({
  Value<String> groupId,
  Value<int> epoch,
  Value<String> wrappedForPeer,
  Value<Uint8List> wrappedBlob,
  Value<int> rowid,
});

final class $$GroupKeysTableReferences
    extends BaseReferences<_$AppDatabase, $GroupKeysTable, GroupKeyRow> {
  $$GroupKeysTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GrpsTable _groupIdTable(_$AppDatabase db) =>
      db.grps.createAlias('group_key__group_id__grp__id');

  $$GrpsTableProcessedTableManager get groupId {
    final $_column = $_itemColumn<String>('group_id')!;

    final manager = $$GrpsTableTableManager(
      $_db,
      $_db.grps,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GroupKeysTableFilterComposer
    extends Composer<_$AppDatabase, $GroupKeysTable> {
  $$GroupKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wrappedForPeer => $composableBuilder(
    column: $table.wrappedForPeer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get wrappedBlob => $composableBuilder(
    column: $table.wrappedBlob,
    builder: (column) => ColumnFilters(column),
  );

  $$GrpsTableFilterComposer get groupId {
    final $$GrpsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.grps,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GrpsTableFilterComposer(
            $db: $db,
            $table: $db.grps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupKeysTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupKeysTable> {
  $$GroupKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wrappedForPeer => $composableBuilder(
    column: $table.wrappedForPeer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get wrappedBlob => $composableBuilder(
    column: $table.wrappedBlob,
    builder: (column) => ColumnOrderings(column),
  );

  $$GrpsTableOrderingComposer get groupId {
    final $$GrpsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.grps,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GrpsTableOrderingComposer(
            $db: $db,
            $table: $db.grps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupKeysTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupKeysTable> {
  $$GroupKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get epoch =>
      $composableBuilder(column: $table.epoch, builder: (column) => column);

  GeneratedColumn<String> get wrappedForPeer => $composableBuilder(
    column: $table.wrappedForPeer,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get wrappedBlob => $composableBuilder(
    column: $table.wrappedBlob,
    builder: (column) => column,
  );

  $$GrpsTableAnnotationComposer get groupId {
    final $$GrpsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.grps,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GrpsTableAnnotationComposer(
            $db: $db,
            $table: $db.grps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupKeysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupKeysTable,
          GroupKeyRow,
          $$GroupKeysTableFilterComposer,
          $$GroupKeysTableOrderingComposer,
          $$GroupKeysTableAnnotationComposer,
          $$GroupKeysTableCreateCompanionBuilder,
          $$GroupKeysTableUpdateCompanionBuilder,
          (GroupKeyRow, $$GroupKeysTableReferences),
          GroupKeyRow,
          PrefetchHooks Function({bool groupId})
        > {
  $$GroupKeysTableTableManager(_$AppDatabase db, $GroupKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<int> epoch = const Value.absent(),
                Value<String> wrappedForPeer = const Value.absent(),
                Value<Uint8List> wrappedBlob = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupKeysCompanion(
                groupId: groupId,
                epoch: epoch,
                wrappedForPeer: wrappedForPeer,
                wrappedBlob: wrappedBlob,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required int epoch,
                required String wrappedForPeer,
                required Uint8List wrappedBlob,
                Value<int> rowid = const Value.absent(),
              }) => GroupKeysCompanion.insert(
                groupId: groupId,
                epoch: epoch,
                wrappedForPeer: wrappedForPeer,
                wrappedBlob: wrappedBlob,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GroupKeysTable, GroupKeyRow>(table),
                  $$GroupKeysTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (groupId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.groupId,
                        referencedTable: $$GroupKeysTableReferences
                            ._groupIdTable(db),
                        referencedColumn: $$GroupKeysTableReferences
                            ._groupIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GroupKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupKeysTable,
      GroupKeyRow,
      $$GroupKeysTableFilterComposer,
      $$GroupKeysTableOrderingComposer,
      $$GroupKeysTableAnnotationComposer,
      $$GroupKeysTableCreateCompanionBuilder,
      $$GroupKeysTableUpdateCompanionBuilder,
      (GroupKeyRow, $$GroupKeysTableReferences),
      GroupKeyRow,
      PrefetchHooks Function({bool groupId})
    >;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String threadId,
  required String senderPeerId,
  required MessageKind kind,
  required String hlc,
  required DateTime ts,
  Value<String> body,
  Value<String> attachJson,
  Value<String> sig,
  Value<DateTime?> revokedAt,
  Value<String?> revokeReason,
  Value<DateTime?> editedAt,
  Value<String?> deletedBy,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> threadId,
  Value<String> senderPeerId,
  Value<MessageKind> kind,
  Value<String> hlc,
  Value<DateTime> ts,
  Value<String> body,
  Value<String> attachJson,
  Value<String> sig,
  Value<DateTime?> revokedAt,
  Value<String?> revokeReason,
  Value<DateTime?> editedAt,
  Value<String?> deletedBy,
  Value<int> rowid,
});

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderPeerId => $composableBuilder(
    column: $table.senderPeerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MessageKind, MessageKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get ts =>
      $composableBuilder(
        column: $table.ts,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachJson => $composableBuilder(
    column: $table.attachJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get revokedAt =>
      $composableBuilder(
        column: $table.revokedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get revokeReason => $composableBuilder(
    column: $table.revokeReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get editedAt =>
      $composableBuilder(
        column: $table.editedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get deletedBy => $composableBuilder(
    column: $table.deletedBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderPeerId => $composableBuilder(
    column: $table.senderPeerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachJson => $composableBuilder(
    column: $table.attachJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revokedAt => $composableBuilder(
    column: $table.revokedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revokeReason => $composableBuilder(
    column: $table.revokeReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get editedAt => $composableBuilder(
    column: $table.editedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedBy => $composableBuilder(
    column: $table.deletedBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get senderPeerId => $composableBuilder(
    column: $table.senderPeerId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<MessageKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get attachJson => $composableBuilder(
    column: $table.attachJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sig =>
      $composableBuilder(column: $table.sig, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get revokedAt =>
      $composableBuilder(column: $table.revokedAt, builder: (column) => column);

  GeneratedColumn<String> get revokeReason => $composableBuilder(
    column: $table.revokeReason,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, int> get editedAt =>
      $composableBuilder(column: $table.editedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedBy =>
      $composableBuilder(column: $table.deletedBy, builder: (column) => column);
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          MessageRow,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (
            MessageRow,
            BaseReferences<_$AppDatabase, $MessagesTable, MessageRow>,
          ),
          MessageRow,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> threadId = const Value.absent(),
                Value<String> senderPeerId = const Value.absent(),
                Value<MessageKind> kind = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<DateTime> ts = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> attachJson = const Value.absent(),
                Value<String> sig = const Value.absent(),
                Value<DateTime?> revokedAt = const Value.absent(),
                Value<String?> revokeReason = const Value.absent(),
                Value<DateTime?> editedAt = const Value.absent(),
                Value<String?> deletedBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                threadId: threadId,
                senderPeerId: senderPeerId,
                kind: kind,
                hlc: hlc,
                ts: ts,
                body: body,
                attachJson: attachJson,
                sig: sig,
                revokedAt: revokedAt,
                revokeReason: revokeReason,
                editedAt: editedAt,
                deletedBy: deletedBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String threadId,
                required String senderPeerId,
                required MessageKind kind,
                required String hlc,
                required DateTime ts,
                Value<String> body = const Value.absent(),
                Value<String> attachJson = const Value.absent(),
                Value<String> sig = const Value.absent(),
                Value<DateTime?> revokedAt = const Value.absent(),
                Value<String?> revokeReason = const Value.absent(),
                Value<DateTime?> editedAt = const Value.absent(),
                Value<String?> deletedBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                threadId: threadId,
                senderPeerId: senderPeerId,
                kind: kind,
                hlc: hlc,
                ts: ts,
                body: body,
                attachJson: attachJson,
                sig: sig,
                revokedAt: revokedAt,
                revokeReason: revokeReason,
                editedAt: editedAt,
                deletedBy: deletedBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, MessageRow>(table),
                  BaseReferences<_$AppDatabase, $MessagesTable, MessageRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      MessageRow,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (MessageRow, BaseReferences<_$AppDatabase, $MessagesTable, MessageRow>),
      MessageRow,
      PrefetchHooks Function()
    >;
typedef $$AttachmentsTableCreateCompanionBuilder =
    AttachmentsCompanion Function({
      required String id,
      required String msgId,
      required String shareId,
      required String ownerPeerId,
      required String itemKey,
      Value<String> name,
      Value<int> size,
      Value<String?> mime,
      Value<bool> isDir,
      Value<String?> subPath,
      Value<String?> localPath,
      Value<String> state,
      Value<int> rowid,
    });
typedef $$AttachmentsTableUpdateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<String> id,
      Value<String> msgId,
      Value<String> shareId,
      Value<String> ownerPeerId,
      Value<String> itemKey,
      Value<String> name,
      Value<int> size,
      Value<String?> mime,
      Value<bool> isDir,
      Value<String?> subPath,
      Value<String?> localPath,
      Value<String> state,
      Value<int> rowid,
    });

class $$AttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get msgId => $composableBuilder(
    column: $table.msgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shareId => $composableBuilder(
    column: $table.shareId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDir => $composableBuilder(
    column: $table.isDir,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subPath => $composableBuilder(
    column: $table.subPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get msgId => $composableBuilder(
    column: $table.msgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shareId => $composableBuilder(
    column: $table.shareId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDir => $composableBuilder(
    column: $table.isDir,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subPath => $composableBuilder(
    column: $table.subPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get msgId =>
      $composableBuilder(column: $table.msgId, builder: (column) => column);

  GeneratedColumn<String> get shareId =>
      $composableBuilder(column: $table.shareId, builder: (column) => column);

  GeneratedColumn<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get itemKey =>
      $composableBuilder(column: $table.itemKey, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<bool> get isDir =>
      $composableBuilder(column: $table.isDir, builder: (column) => column);

  GeneratedColumn<String> get subPath =>
      $composableBuilder(column: $table.subPath, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);
}

class $$AttachmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AttachmentsTable,
          AttachRow,
          $$AttachmentsTableFilterComposer,
          $$AttachmentsTableOrderingComposer,
          $$AttachmentsTableAnnotationComposer,
          $$AttachmentsTableCreateCompanionBuilder,
          $$AttachmentsTableUpdateCompanionBuilder,
          (
            AttachRow,
            BaseReferences<_$AppDatabase, $AttachmentsTable, AttachRow>,
          ),
          AttachRow,
          PrefetchHooks Function()
        > {
  $$AttachmentsTableTableManager(_$AppDatabase db, $AttachmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> msgId = const Value.absent(),
                Value<String> shareId = const Value.absent(),
                Value<String> ownerPeerId = const Value.absent(),
                Value<String> itemKey = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> mime = const Value.absent(),
                Value<bool> isDir = const Value.absent(),
                Value<String?> subPath = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion(
                id: id,
                msgId: msgId,
                shareId: shareId,
                ownerPeerId: ownerPeerId,
                itemKey: itemKey,
                name: name,
                size: size,
                mime: mime,
                isDir: isDir,
                subPath: subPath,
                localPath: localPath,
                state: state,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String msgId,
                required String shareId,
                required String ownerPeerId,
                required String itemKey,
                Value<String> name = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> mime = const Value.absent(),
                Value<bool> isDir = const Value.absent(),
                Value<String?> subPath = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion.insert(
                id: id,
                msgId: msgId,
                shareId: shareId,
                ownerPeerId: ownerPeerId,
                itemKey: itemKey,
                name: name,
                size: size,
                mime: mime,
                isDir: isDir,
                subPath: subPath,
                localPath: localPath,
                state: state,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AttachmentsTable, AttachRow>(table),
                  BaseReferences<_$AppDatabase, $AttachmentsTable, AttachRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AttachmentsTable,
      AttachRow,
      $$AttachmentsTableFilterComposer,
      $$AttachmentsTableOrderingComposer,
      $$AttachmentsTableAnnotationComposer,
      $$AttachmentsTableCreateCompanionBuilder,
      $$AttachmentsTableUpdateCompanionBuilder,
      (AttachRow, BaseReferences<_$AppDatabase, $AttachmentsTable, AttachRow>),
      AttachRow,
      PrefetchHooks Function()
    >;
typedef $$OffersTableCreateCompanionBuilder = OffersCompanion Function({
  required String id,
  Value<String?> fromPeer,
  Value<String?> fromSession,
  required OfferOrigin origin,
  required String toPeer,
  Value<String> attachJson,
  Value<int> sizeTotal,
  required String status,
  required DateTime createdAt,
  Value<DateTime?> decidedAt,
  Value<String?> note,
  required DateTime expireAt,
  Value<int> rowid,
});
typedef $$OffersTableUpdateCompanionBuilder = OffersCompanion Function({
  Value<String> id,
  Value<String?> fromPeer,
  Value<String?> fromSession,
  Value<OfferOrigin> origin,
  Value<String> toPeer,
  Value<String> attachJson,
  Value<int> sizeTotal,
  Value<String> status,
  Value<DateTime> createdAt,
  Value<DateTime?> decidedAt,
  Value<String?> note,
  Value<DateTime> expireAt,
  Value<int> rowid,
});

class $$OffersTableFilterComposer
    extends Composer<_$AppDatabase, $OffersTable> {
  $$OffersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromPeer => $composableBuilder(
    column: $table.fromPeer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromSession => $composableBuilder(
    column: $table.fromSession,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<OfferOrigin, OfferOrigin, String> get origin =>
      $composableBuilder(
        column: $table.origin,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get toPeer => $composableBuilder(
    column: $table.toPeer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachJson => $composableBuilder(
    column: $table.attachJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeTotal => $composableBuilder(
    column: $table.sizeTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get decidedAt =>
      $composableBuilder(
        column: $table.decidedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get expireAt =>
      $composableBuilder(
        column: $table.expireAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$OffersTableOrderingComposer
    extends Composer<_$AppDatabase, $OffersTable> {
  $$OffersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromPeer => $composableBuilder(
    column: $table.fromPeer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromSession => $composableBuilder(
    column: $table.fromSession,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toPeer => $composableBuilder(
    column: $table.toPeer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachJson => $composableBuilder(
    column: $table.attachJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeTotal => $composableBuilder(
    column: $table.sizeTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get decidedAt => $composableBuilder(
    column: $table.decidedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expireAt => $composableBuilder(
    column: $table.expireAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OffersTableAnnotationComposer
    extends Composer<_$AppDatabase, $OffersTable> {
  $$OffersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromPeer =>
      $composableBuilder(column: $table.fromPeer, builder: (column) => column);

  GeneratedColumn<String> get fromSession => $composableBuilder(
    column: $table.fromSession,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<OfferOrigin, String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get toPeer =>
      $composableBuilder(column: $table.toPeer, builder: (column) => column);

  GeneratedColumn<String> get attachJson => $composableBuilder(
    column: $table.attachJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeTotal =>
      $composableBuilder(column: $table.sizeTotal, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get decidedAt =>
      $composableBuilder(column: $table.decidedAt, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get expireAt =>
      $composableBuilder(column: $table.expireAt, builder: (column) => column);
}

class $$OffersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OffersTable,
          OfferRow,
          $$OffersTableFilterComposer,
          $$OffersTableOrderingComposer,
          $$OffersTableAnnotationComposer,
          $$OffersTableCreateCompanionBuilder,
          $$OffersTableUpdateCompanionBuilder,
          (OfferRow, BaseReferences<_$AppDatabase, $OffersTable, OfferRow>),
          OfferRow,
          PrefetchHooks Function()
        > {
  $$OffersTableTableManager(_$AppDatabase db, $OffersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OffersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OffersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OffersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> fromPeer = const Value.absent(),
                Value<String?> fromSession = const Value.absent(),
                Value<OfferOrigin> origin = const Value.absent(),
                Value<String> toPeer = const Value.absent(),
                Value<String> attachJson = const Value.absent(),
                Value<int> sizeTotal = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> decidedAt = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> expireAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OffersCompanion(
                id: id,
                fromPeer: fromPeer,
                fromSession: fromSession,
                origin: origin,
                toPeer: toPeer,
                attachJson: attachJson,
                sizeTotal: sizeTotal,
                status: status,
                createdAt: createdAt,
                decidedAt: decidedAt,
                note: note,
                expireAt: expireAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> fromPeer = const Value.absent(),
                Value<String?> fromSession = const Value.absent(),
                required OfferOrigin origin,
                required String toPeer,
                Value<String> attachJson = const Value.absent(),
                Value<int> sizeTotal = const Value.absent(),
                required String status,
                required DateTime createdAt,
                Value<DateTime?> decidedAt = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required DateTime expireAt,
                Value<int> rowid = const Value.absent(),
              }) => OffersCompanion.insert(
                id: id,
                fromPeer: fromPeer,
                fromSession: fromSession,
                origin: origin,
                toPeer: toPeer,
                attachJson: attachJson,
                sizeTotal: sizeTotal,
                status: status,
                createdAt: createdAt,
                decidedAt: decidedAt,
                note: note,
                expireAt: expireAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OffersTable, OfferRow>(table),
                  BaseReferences<_$AppDatabase, $OffersTable, OfferRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OffersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OffersTable,
      OfferRow,
      $$OffersTableFilterComposer,
      $$OffersTableOrderingComposer,
      $$OffersTableAnnotationComposer,
      $$OffersTableCreateCompanionBuilder,
      $$OffersTableUpdateCompanionBuilder,
      (OfferRow, BaseReferences<_$AppDatabase, $OffersTable, OfferRow>),
      OfferRow,
      PrefetchHooks Function()
    >;
typedef $$TransfersTableCreateCompanionBuilder = TransfersCompanion Function({
  required String id,
  required TransferDirection direction,
  required String peerId,
  required String shareId,
  required String itemKey,
  required int bytesTotal,
  Value<int> bytesDone,
  required TransferStatus status,
  Value<int?> speedBps,
  required DateTime createdAt,
  Value<DateTime?> finishedAt,
  Value<String?> err,
  Value<int> rowid,
});
typedef $$TransfersTableUpdateCompanionBuilder = TransfersCompanion Function({
  Value<String> id,
  Value<TransferDirection> direction,
  Value<String> peerId,
  Value<String> shareId,
  Value<String> itemKey,
  Value<int> bytesTotal,
  Value<int> bytesDone,
  Value<TransferStatus> status,
  Value<int?> speedBps,
  Value<DateTime> createdAt,
  Value<DateTime?> finishedAt,
  Value<String?> err,
  Value<int> rowid,
});

class $$TransfersTableFilterComposer
    extends Composer<_$AppDatabase, $TransfersTable> {
  $$TransfersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TransferDirection, TransferDirection, String>
  get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shareId => $composableBuilder(
    column: $table.shareId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytesTotal => $composableBuilder(
    column: $table.bytesTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytesDone => $composableBuilder(
    column: $table.bytesDone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TransferStatus, TransferStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get speedBps => $composableBuilder(
    column: $table.speedBps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get finishedAt =>
      $composableBuilder(
        column: $table.finishedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get err => $composableBuilder(
    column: $table.err,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransfersTableOrderingComposer
    extends Composer<_$AppDatabase, $TransfersTable> {
  $$TransfersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shareId => $composableBuilder(
    column: $table.shareId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytesTotal => $composableBuilder(
    column: $table.bytesTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytesDone => $composableBuilder(
    column: $table.bytesDone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get speedBps => $composableBuilder(
    column: $table.speedBps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get err => $composableBuilder(
    column: $table.err,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransfersTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransfersTable> {
  $$TransfersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TransferDirection, String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get shareId =>
      $composableBuilder(column: $table.shareId, builder: (column) => column);

  GeneratedColumn<String> get itemKey =>
      $composableBuilder(column: $table.itemKey, builder: (column) => column);

  GeneratedColumn<int> get bytesTotal => $composableBuilder(
    column: $table.bytesTotal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bytesDone =>
      $composableBuilder(column: $table.bytesDone, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TransferStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get speedBps =>
      $composableBuilder(column: $table.speedBps, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get finishedAt =>
      $composableBuilder(
        column: $table.finishedAt,
        builder: (column) => column,
      );

  GeneratedColumn<String> get err =>
      $composableBuilder(column: $table.err, builder: (column) => column);
}

class $$TransfersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransfersTable,
          TransferRow,
          $$TransfersTableFilterComposer,
          $$TransfersTableOrderingComposer,
          $$TransfersTableAnnotationComposer,
          $$TransfersTableCreateCompanionBuilder,
          $$TransfersTableUpdateCompanionBuilder,
          (
            TransferRow,
            BaseReferences<_$AppDatabase, $TransfersTable, TransferRow>,
          ),
          TransferRow,
          PrefetchHooks Function()
        > {
  $$TransfersTableTableManager(_$AppDatabase db, $TransfersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransfersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransfersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransfersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<TransferDirection> direction = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<String> shareId = const Value.absent(),
                Value<String> itemKey = const Value.absent(),
                Value<int> bytesTotal = const Value.absent(),
                Value<int> bytesDone = const Value.absent(),
                Value<TransferStatus> status = const Value.absent(),
                Value<int?> speedBps = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<String?> err = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransfersCompanion(
                id: id,
                direction: direction,
                peerId: peerId,
                shareId: shareId,
                itemKey: itemKey,
                bytesTotal: bytesTotal,
                bytesDone: bytesDone,
                status: status,
                speedBps: speedBps,
                createdAt: createdAt,
                finishedAt: finishedAt,
                err: err,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required TransferDirection direction,
                required String peerId,
                required String shareId,
                required String itemKey,
                required int bytesTotal,
                Value<int> bytesDone = const Value.absent(),
                required TransferStatus status,
                Value<int?> speedBps = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<String?> err = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransfersCompanion.insert(
                id: id,
                direction: direction,
                peerId: peerId,
                shareId: shareId,
                itemKey: itemKey,
                bytesTotal: bytesTotal,
                bytesDone: bytesDone,
                status: status,
                speedBps: speedBps,
                createdAt: createdAt,
                finishedAt: finishedAt,
                err: err,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TransfersTable, TransferRow>(table),
                  BaseReferences<_$AppDatabase, $TransfersTable, TransferRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransfersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransfersTable,
      TransferRow,
      $$TransfersTableFilterComposer,
      $$TransfersTableOrderingComposer,
      $$TransfersTableAnnotationComposer,
      $$TransfersTableCreateCompanionBuilder,
      $$TransfersTableUpdateCompanionBuilder,
      (
        TransferRow,
        BaseReferences<_$AppDatabase, $TransfersTable, TransferRow>,
      ),
      TransferRow,
      PrefetchHooks Function()
    >;
typedef $$GuestSessionsTableCreateCompanionBuilder =
    GuestSessionsCompanion Function({
      required String sessionId,
      required String hostPeer,
      required Uint8List pubkey,
      required DateTime createdAt,
      required DateTime lastBeat,
      Value<DateTime?> revokedAt,
      Value<int> quotaBytes,
      Value<int> usedBytes,
      Value<int> rowid,
    });
typedef $$GuestSessionsTableUpdateCompanionBuilder =
    GuestSessionsCompanion Function({
      Value<String> sessionId,
      Value<String> hostPeer,
      Value<Uint8List> pubkey,
      Value<DateTime> createdAt,
      Value<DateTime> lastBeat,
      Value<DateTime?> revokedAt,
      Value<int> quotaBytes,
      Value<int> usedBytes,
      Value<int> rowid,
    });

class $$GuestSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $GuestSessionsTable> {
  $$GuestSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostPeer => $composableBuilder(
    column: $table.hostPeer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get lastBeat =>
      $composableBuilder(
        column: $table.lastBeat,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get revokedAt =>
      $composableBuilder(
        column: $table.revokedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get quotaBytes => $composableBuilder(
    column: $table.quotaBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usedBytes => $composableBuilder(
    column: $table.usedBytes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GuestSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $GuestSessionsTable> {
  $$GuestSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostPeer => $composableBuilder(
    column: $table.hostPeer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastBeat => $composableBuilder(
    column: $table.lastBeat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revokedAt => $composableBuilder(
    column: $table.revokedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quotaBytes => $composableBuilder(
    column: $table.quotaBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usedBytes => $composableBuilder(
    column: $table.usedBytes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GuestSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GuestSessionsTable> {
  $$GuestSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get hostPeer =>
      $composableBuilder(column: $table.hostPeer, builder: (column) => column);

  GeneratedColumn<Uint8List> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get lastBeat =>
      $composableBuilder(column: $table.lastBeat, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get revokedAt =>
      $composableBuilder(column: $table.revokedAt, builder: (column) => column);

  GeneratedColumn<int> get quotaBytes => $composableBuilder(
    column: $table.quotaBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get usedBytes =>
      $composableBuilder(column: $table.usedBytes, builder: (column) => column);
}

class $$GuestSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GuestSessionsTable,
          GuestSessionRow,
          $$GuestSessionsTableFilterComposer,
          $$GuestSessionsTableOrderingComposer,
          $$GuestSessionsTableAnnotationComposer,
          $$GuestSessionsTableCreateCompanionBuilder,
          $$GuestSessionsTableUpdateCompanionBuilder,
          (
            GuestSessionRow,
            BaseReferences<_$AppDatabase, $GuestSessionsTable, GuestSessionRow>,
          ),
          GuestSessionRow,
          PrefetchHooks Function()
        > {
  $$GuestSessionsTableTableManager(_$AppDatabase db, $GuestSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GuestSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GuestSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GuestSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> hostPeer = const Value.absent(),
                Value<Uint8List> pubkey = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastBeat = const Value.absent(),
                Value<DateTime?> revokedAt = const Value.absent(),
                Value<int> quotaBytes = const Value.absent(),
                Value<int> usedBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GuestSessionsCompanion(
                sessionId: sessionId,
                hostPeer: hostPeer,
                pubkey: pubkey,
                createdAt: createdAt,
                lastBeat: lastBeat,
                revokedAt: revokedAt,
                quotaBytes: quotaBytes,
                usedBytes: usedBytes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String hostPeer,
                required Uint8List pubkey,
                required DateTime createdAt,
                required DateTime lastBeat,
                Value<DateTime?> revokedAt = const Value.absent(),
                Value<int> quotaBytes = const Value.absent(),
                Value<int> usedBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GuestSessionsCompanion.insert(
                sessionId: sessionId,
                hostPeer: hostPeer,
                pubkey: pubkey,
                createdAt: createdAt,
                lastBeat: lastBeat,
                revokedAt: revokedAt,
                quotaBytes: quotaBytes,
                usedBytes: usedBytes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GuestSessionsTable, GuestSessionRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $GuestSessionsTable,
                    GuestSessionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GuestSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GuestSessionsTable,
      GuestSessionRow,
      $$GuestSessionsTableFilterComposer,
      $$GuestSessionsTableOrderingComposer,
      $$GuestSessionsTableAnnotationComposer,
      $$GuestSessionsTableCreateCompanionBuilder,
      $$GuestSessionsTableUpdateCompanionBuilder,
      (
        GuestSessionRow,
        BaseReferences<_$AppDatabase, $GuestSessionsTable, GuestSessionRow>,
      ),
      GuestSessionRow,
      PrefetchHooks Function()
    >;
typedef $$MsgSeensTableCreateCompanionBuilder = MsgSeensCompanion Function({
  required String threadId,
  required String peerId,
  required String lastHlc,
  Value<int> rowid,
});
typedef $$MsgSeensTableUpdateCompanionBuilder = MsgSeensCompanion Function({
  Value<String> threadId,
  Value<String> peerId,
  Value<String> lastHlc,
  Value<int> rowid,
});

final class $$MsgSeensTableReferences
    extends BaseReferences<_$AppDatabase, $MsgSeensTable, MsgSeenRow> {
  $$MsgSeensTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ThreadsTable _threadIdTable(_$AppDatabase db) =>
      db.threads.createAlias('msg_seen__thread_id__thread__id');

  $$ThreadsTableProcessedTableManager get threadId {
    final $_column = $_itemColumn<String>('thread_id')!;

    final manager = $$ThreadsTableTableManager(
      $_db,
      $_db.threads,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_threadIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MsgSeensTableFilterComposer
    extends Composer<_$AppDatabase, $MsgSeensTable> {
  $$MsgSeensTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastHlc => $composableBuilder(
    column: $table.lastHlc,
    builder: (column) => ColumnFilters(column),
  );

  $$ThreadsTableFilterComposer get threadId {
    final $$ThreadsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.threadId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableFilterComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MsgSeensTableOrderingComposer
    extends Composer<_$AppDatabase, $MsgSeensTable> {
  $$MsgSeensTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastHlc => $composableBuilder(
    column: $table.lastHlc,
    builder: (column) => ColumnOrderings(column),
  );

  $$ThreadsTableOrderingComposer get threadId {
    final $$ThreadsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.threadId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableOrderingComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MsgSeensTableAnnotationComposer
    extends Composer<_$AppDatabase, $MsgSeensTable> {
  $$MsgSeensTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get lastHlc =>
      $composableBuilder(column: $table.lastHlc, builder: (column) => column);

  $$ThreadsTableAnnotationComposer get threadId {
    final $$ThreadsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.threadId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableAnnotationComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MsgSeensTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MsgSeensTable,
          MsgSeenRow,
          $$MsgSeensTableFilterComposer,
          $$MsgSeensTableOrderingComposer,
          $$MsgSeensTableAnnotationComposer,
          $$MsgSeensTableCreateCompanionBuilder,
          $$MsgSeensTableUpdateCompanionBuilder,
          (MsgSeenRow, $$MsgSeensTableReferences),
          MsgSeenRow,
          PrefetchHooks Function({bool threadId})
        > {
  $$MsgSeensTableTableManager(_$AppDatabase db, $MsgSeensTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MsgSeensTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MsgSeensTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MsgSeensTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> threadId = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<String> lastHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MsgSeensCompanion(
                threadId: threadId,
                peerId: peerId,
                lastHlc: lastHlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String threadId,
                required String peerId,
                required String lastHlc,
                Value<int> rowid = const Value.absent(),
              }) => MsgSeensCompanion.insert(
                threadId: threadId,
                peerId: peerId,
                lastHlc: lastHlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MsgSeensTable, MsgSeenRow>(table),
                  $$MsgSeensTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({threadId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (threadId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.threadId,
                        referencedTable: $$MsgSeensTableReferences
                            ._threadIdTable(db),
                        referencedColumn: $$MsgSeensTableReferences
                            ._threadIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MsgSeensTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MsgSeensTable,
      MsgSeenRow,
      $$MsgSeensTableFilterComposer,
      $$MsgSeensTableOrderingComposer,
      $$MsgSeensTableAnnotationComposer,
      $$MsgSeensTableCreateCompanionBuilder,
      $$MsgSeensTableUpdateCompanionBuilder,
      (MsgSeenRow, $$MsgSeensTableReferences),
      MsgSeenRow,
      PrefetchHooks Function({bool threadId})
    >;
typedef $$PeerBlocksTableCreateCompanionBuilder = PeerBlocksCompanion Function({
  required String peerId,
  Value<String> reason,
  Value<DateTime?> until,
  Value<int> rowid,
});
typedef $$PeerBlocksTableUpdateCompanionBuilder = PeerBlocksCompanion Function({
  Value<String> peerId,
  Value<String> reason,
  Value<DateTime?> until,
  Value<int> rowid,
});

class $$PeerBlocksTableFilterComposer
    extends Composer<_$AppDatabase, $PeerBlocksTable> {
  $$PeerBlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get until =>
      $composableBuilder(
        column: $table.until,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$PeerBlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $PeerBlocksTable> {
  $$PeerBlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get until => $composableBuilder(
    column: $table.until,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeerBlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $PeerBlocksTable> {
  $$PeerBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get until =>
      $composableBuilder(column: $table.until, builder: (column) => column);
}

class $$PeerBlocksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PeerBlocksTable,
          PeerBlockRow,
          $$PeerBlocksTableFilterComposer,
          $$PeerBlocksTableOrderingComposer,
          $$PeerBlocksTableAnnotationComposer,
          $$PeerBlocksTableCreateCompanionBuilder,
          $$PeerBlocksTableUpdateCompanionBuilder,
          (
            PeerBlockRow,
            BaseReferences<_$AppDatabase, $PeerBlocksTable, PeerBlockRow>,
          ),
          PeerBlockRow,
          PrefetchHooks Function()
        > {
  $$PeerBlocksTableTableManager(_$AppDatabase db, $PeerBlocksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeerBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeerBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeerBlocksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> peerId = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<DateTime?> until = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeerBlocksCompanion(
                peerId: peerId,
                reason: reason,
                until: until,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerId,
                Value<String> reason = const Value.absent(),
                Value<DateTime?> until = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeerBlocksCompanion.insert(
                peerId: peerId,
                reason: reason,
                until: until,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PeerBlocksTable, PeerBlockRow>(table),
                  BaseReferences<_$AppDatabase, $PeerBlocksTable, PeerBlockRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PeerBlocksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PeerBlocksTable,
      PeerBlockRow,
      $$PeerBlocksTableFilterComposer,
      $$PeerBlocksTableOrderingComposer,
      $$PeerBlocksTableAnnotationComposer,
      $$PeerBlocksTableCreateCompanionBuilder,
      $$PeerBlocksTableUpdateCompanionBuilder,
      (
        PeerBlockRow,
        BaseReferences<_$AppDatabase, $PeerBlocksTable, PeerBlockRow>,
      ),
      PeerBlockRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$SharesTableTableManager get shares =>
      $$SharesTableTableManager(_db, _db.shares);
  $$ShareItemsTableTableManager get shareItems =>
      $$ShareItemsTableTableManager(_db, _db.shareItems);
  $$GrantsTableTableManager get grants =>
      $$GrantsTableTableManager(_db, _db.grants);
  $$ThreadsTableTableManager get threads =>
      $$ThreadsTableTableManager(_db, _db.threads);
  $$GrpsTableTableManager get grps => $$GrpsTableTableManager(_db, _db.grps);
  $$GroupMembersTableTableManager get groupMembers =>
      $$GroupMembersTableTableManager(_db, _db.groupMembers);
  $$GroupKeysTableTableManager get groupKeys =>
      $$GroupKeysTableTableManager(_db, _db.groupKeys);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db, _db.attachments);
  $$OffersTableTableManager get offers =>
      $$OffersTableTableManager(_db, _db.offers);
  $$TransfersTableTableManager get transfers =>
      $$TransfersTableTableManager(_db, _db.transfers);
  $$GuestSessionsTableTableManager get guestSessions =>
      $$GuestSessionsTableTableManager(_db, _db.guestSessions);
  $$MsgSeensTableTableManager get msgSeens =>
      $$MsgSeensTableTableManager(_db, _db.msgSeens);
  $$PeerBlocksTableTableManager get peerBlocks =>
      $$PeerBlocksTableTableManager(_db, _db.peerBlocks);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
