// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $DevicesTable extends Devices with TableInfo<$DevicesTable, DeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenHashMeta = const VerificationMeta(
    'tokenHash',
  );
  @override
  late final GeneratedColumn<String> tokenHash = GeneratedColumn<String>(
    'token_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<int> pairedAt = GeneratedColumn<int>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<int> lastSeenAt = GeneratedColumn<int>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revokedAtMeta = const VerificationMeta(
    'revokedAt',
  );
  @override
  late final GeneratedColumn<int> revokedAt = GeneratedColumn<int>(
    'revoked_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  @override
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    name,
    platform,
    tokenHash,
    pairedAt,
    lastSeenAt,
    revokedAt,
    appVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('token_hash')) {
      context.handle(
        _tokenHashMeta,
        tokenHash.isAcceptableOrUnknown(data['token_hash']!, _tokenHashMeta),
      );
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pairedAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('revoked_at')) {
      context.handle(
        _revokedAtMeta,
        revokedAt.isAcceptableOrUnknown(data['revoked_at']!, _revokedAtMeta),
      );
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  DeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      tokenHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_hash'],
      ),
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paired_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_at'],
      ),
      revokedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revoked_at'],
      ),
      appVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_version'],
      ),
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }
}

class DeviceRow extends DataClass implements Insertable<DeviceRow> {
  final String deviceId;
  final String name;
  final String platform;

  /// 仅 Windows 存：token 的 sha256；Android 存 NULL。
  final String? tokenHash;
  final int pairedAt;
  final int? lastSeenAt;

  /// 非空表示已吊销。
  final int? revokedAt;
  final String? appVersion;
  const DeviceRow({
    required this.deviceId,
    required this.name,
    required this.platform,
    this.tokenHash,
    required this.pairedAt,
    this.lastSeenAt,
    this.revokedAt,
    this.appVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['name'] = Variable<String>(name);
    map['platform'] = Variable<String>(platform);
    if (!nullToAbsent || tokenHash != null) {
      map['token_hash'] = Variable<String>(tokenHash);
    }
    map['paired_at'] = Variable<int>(pairedAt);
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<int>(lastSeenAt);
    }
    if (!nullToAbsent || revokedAt != null) {
      map['revoked_at'] = Variable<int>(revokedAt);
    }
    if (!nullToAbsent || appVersion != null) {
      map['app_version'] = Variable<String>(appVersion);
    }
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      deviceId: Value(deviceId),
      name: Value(name),
      platform: Value(platform),
      tokenHash: tokenHash == null && nullToAbsent
          ? const Value.absent()
          : Value(tokenHash),
      pairedAt: Value(pairedAt),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      revokedAt: revokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(revokedAt),
      appVersion: appVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(appVersion),
    );
  }

  factory DeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      name: serializer.fromJson<String>(json['name']),
      platform: serializer.fromJson<String>(json['platform']),
      tokenHash: serializer.fromJson<String?>(json['tokenHash']),
      pairedAt: serializer.fromJson<int>(json['pairedAt']),
      lastSeenAt: serializer.fromJson<int?>(json['lastSeenAt']),
      revokedAt: serializer.fromJson<int?>(json['revokedAt']),
      appVersion: serializer.fromJson<String?>(json['appVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'name': serializer.toJson<String>(name),
      'platform': serializer.toJson<String>(platform),
      'tokenHash': serializer.toJson<String?>(tokenHash),
      'pairedAt': serializer.toJson<int>(pairedAt),
      'lastSeenAt': serializer.toJson<int?>(lastSeenAt),
      'revokedAt': serializer.toJson<int?>(revokedAt),
      'appVersion': serializer.toJson<String?>(appVersion),
    };
  }

  DeviceRow copyWith({
    String? deviceId,
    String? name,
    String? platform,
    Value<String?> tokenHash = const Value.absent(),
    int? pairedAt,
    Value<int?> lastSeenAt = const Value.absent(),
    Value<int?> revokedAt = const Value.absent(),
    Value<String?> appVersion = const Value.absent(),
  }) => DeviceRow(
    deviceId: deviceId ?? this.deviceId,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    tokenHash: tokenHash.present ? tokenHash.value : this.tokenHash,
    pairedAt: pairedAt ?? this.pairedAt,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    revokedAt: revokedAt.present ? revokedAt.value : this.revokedAt,
    appVersion: appVersion.present ? appVersion.value : this.appVersion,
  );
  DeviceRow copyWithCompanion(DevicesCompanion data) {
    return DeviceRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      name: data.name.present ? data.name.value : this.name,
      platform: data.platform.present ? data.platform.value : this.platform,
      tokenHash: data.tokenHash.present ? data.tokenHash.value : this.tokenHash,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      revokedAt: data.revokedAt.present ? data.revokedAt.value : this.revokedAt,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceRow(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('appVersion: $appVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    name,
    platform,
    tokenHash,
    pairedAt,
    lastSeenAt,
    revokedAt,
    appVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceRow &&
          other.deviceId == this.deviceId &&
          other.name == this.name &&
          other.platform == this.platform &&
          other.tokenHash == this.tokenHash &&
          other.pairedAt == this.pairedAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.revokedAt == this.revokedAt &&
          other.appVersion == this.appVersion);
}

class DevicesCompanion extends UpdateCompanion<DeviceRow> {
  final Value<String> deviceId;
  final Value<String> name;
  final Value<String> platform;
  final Value<String?> tokenHash;
  final Value<int> pairedAt;
  final Value<int?> lastSeenAt;
  final Value<int?> revokedAt;
  final Value<String?> appVersion;
  final Value<int> rowid;
  const DevicesCompanion({
    this.deviceId = const Value.absent(),
    this.name = const Value.absent(),
    this.platform = const Value.absent(),
    this.tokenHash = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required String deviceId,
    required String name,
    required String platform,
    this.tokenHash = const Value.absent(),
    required int pairedAt,
    this.lastSeenAt = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       name = Value(name),
       platform = Value(platform),
       pairedAt = Value(pairedAt);
  static Insertable<DeviceRow> custom({
    Expression<String>? deviceId,
    Expression<String>? name,
    Expression<String>? platform,
    Expression<String>? tokenHash,
    Expression<int>? pairedAt,
    Expression<int>? lastSeenAt,
    Expression<int>? revokedAt,
    Expression<String>? appVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (name != null) 'name': name,
      if (platform != null) 'platform': platform,
      if (tokenHash != null) 'token_hash': tokenHash,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (revokedAt != null) 'revoked_at': revokedAt,
      if (appVersion != null) 'app_version': appVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? name,
    Value<String>? platform,
    Value<String?>? tokenHash,
    Value<int>? pairedAt,
    Value<int?>? lastSeenAt,
    Value<int?>? revokedAt,
    Value<String?>? appVersion,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      tokenHash: tokenHash ?? this.tokenHash,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      revokedAt: revokedAt ?? this.revokedAt,
      appVersion: appVersion ?? this.appVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (tokenHash.present) {
      map['token_hash'] = Variable<String>(tokenHash.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<int>(pairedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<int>(lastSeenAt.value);
    }
    if (revokedAt.present) {
      map['revoked_at'] = Variable<int>(revokedAt.value);
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('appVersion: $appVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImagesTable extends Images with TableInfo<$ImagesTable, ImageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
    'hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadedByMeta = const VerificationMeta(
    'uploadedBy',
  );
  @override
  late final GeneratedColumn<String> uploadedBy = GeneratedColumn<String>(
    'uploaded_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    hash,
    size,
    mime,
    width,
    height,
    localPath,
    createdAt,
    uploadedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'images';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('hash')) {
      context.handle(
        _hashMeta,
        hash.isAcceptableOrUnknown(data['hash']!, _hashMeta),
      );
    } else if (isInserting) {
      context.missing(_hashMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('uploaded_by')) {
      context.handle(
        _uploadedByMeta,
        uploadedBy.isAcceptableOrUnknown(data['uploaded_by']!, _uploadedByMeta),
      );
    } else if (isInserting) {
      context.missing(_uploadedByMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hash};
  @override
  ImageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImageRow(
      hash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hash'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      uploadedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uploaded_by'],
      )!,
    );
  }

  @override
  $ImagesTable createAlias(String alias) {
    return $ImagesTable(attachedDatabase, alias);
  }
}

class ImageRow extends DataClass implements Insertable<ImageRow> {
  /// sha256(压缩后字节)。
  final String hash;
  final int size;
  final String mime;
  final int? width;
  final int? height;

  /// 本机文件路径；该端没有文件时为 NULL（可后台补传）。
  final String? localPath;
  final int createdAt;
  final String uploadedBy;
  const ImageRow({
    required this.hash,
    required this.size,
    required this.mime,
    this.width,
    this.height,
    this.localPath,
    required this.createdAt,
    required this.uploadedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['hash'] = Variable<String>(hash);
    map['size'] = Variable<int>(size);
    map['mime'] = Variable<String>(mime);
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['uploaded_by'] = Variable<String>(uploadedBy);
    return map;
  }

  ImagesCompanion toCompanion(bool nullToAbsent) {
    return ImagesCompanion(
      hash: Value(hash),
      size: Value(size),
      mime: Value(mime),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      createdAt: Value(createdAt),
      uploadedBy: Value(uploadedBy),
    );
  }

  factory ImageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImageRow(
      hash: serializer.fromJson<String>(json['hash']),
      size: serializer.fromJson<int>(json['size']),
      mime: serializer.fromJson<String>(json['mime']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      uploadedBy: serializer.fromJson<String>(json['uploadedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hash': serializer.toJson<String>(hash),
      'size': serializer.toJson<int>(size),
      'mime': serializer.toJson<String>(mime),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'localPath': serializer.toJson<String?>(localPath),
      'createdAt': serializer.toJson<int>(createdAt),
      'uploadedBy': serializer.toJson<String>(uploadedBy),
    };
  }

  ImageRow copyWith({
    String? hash,
    int? size,
    String? mime,
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    int? createdAt,
    String? uploadedBy,
  }) => ImageRow(
    hash: hash ?? this.hash,
    size: size ?? this.size,
    mime: mime ?? this.mime,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    localPath: localPath.present ? localPath.value : this.localPath,
    createdAt: createdAt ?? this.createdAt,
    uploadedBy: uploadedBy ?? this.uploadedBy,
  );
  ImageRow copyWithCompanion(ImagesCompanion data) {
    return ImageRow(
      hash: data.hash.present ? data.hash.value : this.hash,
      size: data.size.present ? data.size.value : this.size,
      mime: data.mime.present ? data.mime.value : this.mime,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      uploadedBy: data.uploadedBy.present
          ? data.uploadedBy.value
          : this.uploadedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImageRow(')
          ..write('hash: $hash, ')
          ..write('size: $size, ')
          ..write('mime: $mime, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('localPath: $localPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('uploadedBy: $uploadedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    hash,
    size,
    mime,
    width,
    height,
    localPath,
    createdAt,
    uploadedBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImageRow &&
          other.hash == this.hash &&
          other.size == this.size &&
          other.mime == this.mime &&
          other.width == this.width &&
          other.height == this.height &&
          other.localPath == this.localPath &&
          other.createdAt == this.createdAt &&
          other.uploadedBy == this.uploadedBy);
}

class ImagesCompanion extends UpdateCompanion<ImageRow> {
  final Value<String> hash;
  final Value<int> size;
  final Value<String> mime;
  final Value<int?> width;
  final Value<int?> height;
  final Value<String?> localPath;
  final Value<int> createdAt;
  final Value<String> uploadedBy;
  final Value<int> rowid;
  const ImagesCompanion({
    this.hash = const Value.absent(),
    this.size = const Value.absent(),
    this.mime = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.localPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.uploadedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImagesCompanion.insert({
    required String hash,
    required int size,
    required String mime,
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.localPath = const Value.absent(),
    required int createdAt,
    required String uploadedBy,
    this.rowid = const Value.absent(),
  }) : hash = Value(hash),
       size = Value(size),
       mime = Value(mime),
       createdAt = Value(createdAt),
       uploadedBy = Value(uploadedBy);
  static Insertable<ImageRow> custom({
    Expression<String>? hash,
    Expression<int>? size,
    Expression<String>? mime,
    Expression<int>? width,
    Expression<int>? height,
    Expression<String>? localPath,
    Expression<int>? createdAt,
    Expression<String>? uploadedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hash != null) 'hash': hash,
      if (size != null) 'size': size,
      if (mime != null) 'mime': mime,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (localPath != null) 'local_path': localPath,
      if (createdAt != null) 'created_at': createdAt,
      if (uploadedBy != null) 'uploaded_by': uploadedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImagesCompanion copyWith({
    Value<String>? hash,
    Value<int>? size,
    Value<String>? mime,
    Value<int?>? width,
    Value<int?>? height,
    Value<String?>? localPath,
    Value<int>? createdAt,
    Value<String>? uploadedBy,
    Value<int>? rowid,
  }) {
    return ImagesCompanion(
      hash: hash ?? this.hash,
      size: size ?? this.size,
      mime: mime ?? this.mime,
      width: width ?? this.width,
      height: height ?? this.height,
      localPath: localPath ?? this.localPath,
      createdAt: createdAt ?? this.createdAt,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (uploadedBy.present) {
      map['uploaded_by'] = Variable<String>(uploadedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImagesCompanion(')
          ..write('hash: $hash, ')
          ..write('size: $size, ')
          ..write('mime: $mime, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('localPath: $localPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('uploadedBy: $uploadedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionsTable extends Collections
    with TableInfo<$CollectionsTable, CollectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<String> collectionId = GeneratedColumn<String>(
    'collection_id',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByMeta = const VerificationMeta(
    'updatedBy',
  );
  @override
  late final GeneratedColumn<String> updatedBy = GeneratedColumn<String>(
    'updated_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lamportMeta = const VerificationMeta(
    'lamport',
  );
  @override
  late final GeneratedColumn<int> lamport = GeneratedColumn<int>(
    'lamport',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, FieldClock>, String>
  fieldClocksJson =
      GeneratedColumn<String>(
        'field_clocks_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      ).withConverter<Map<String, FieldClock>>(
        $CollectionsTable.$converterfieldClocksJson,
      );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    collectionId,
    name,
    createdAt,
    updatedAt,
    updatedBy,
    lamport,
    fieldClocksJson,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collections';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by')) {
      context.handle(
        _updatedByMeta,
        updatedBy.isAcceptableOrUnknown(data['updated_by']!, _updatedByMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedByMeta);
    }
    if (data.containsKey('lamport')) {
      context.handle(
        _lamportMeta,
        lamport.isAcceptableOrUnknown(data['lamport']!, _lamportMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {collectionId};
  @override
  CollectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionRow(
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by'],
      )!,
      lamport: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lamport'],
      )!,
      fieldClocksJson: $CollectionsTable.$converterfieldClocksJson.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}field_clocks_json'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CollectionsTable createAlias(String alias) {
    return $CollectionsTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, FieldClock>, String?>
  $converterfieldClocksJson = const FieldClocksConverter();
}

class CollectionRow extends DataClass implements Insertable<CollectionRow> {
  final String collectionId;
  final String name;
  final int createdAt;
  final int updatedAt;
  final String updatedBy;
  final int lamport;
  final Map<String, FieldClock> fieldClocksJson;
  final int? deletedAt;
  const CollectionRow({
    required this.collectionId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    required this.lamport,
    required this.fieldClocksJson,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['collection_id'] = Variable<String>(collectionId);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['updated_by'] = Variable<String>(updatedBy);
    map['lamport'] = Variable<int>(lamport);
    {
      map['field_clocks_json'] = Variable<String>(
        $CollectionsTable.$converterfieldClocksJson.toSql(fieldClocksJson),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  CollectionsCompanion toCompanion(bool nullToAbsent) {
    return CollectionsCompanion(
      collectionId: Value(collectionId),
      name: Value(name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      updatedBy: Value(updatedBy),
      lamport: Value(lamport),
      fieldClocksJson: Value(fieldClocksJson),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory CollectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionRow(
      collectionId: serializer.fromJson<String>(json['collectionId']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      updatedBy: serializer.fromJson<String>(json['updatedBy']),
      lamport: serializer.fromJson<int>(json['lamport']),
      fieldClocksJson: serializer.fromJson<Map<String, FieldClock>>(
        json['fieldClocksJson'],
      ),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'collectionId': serializer.toJson<String>(collectionId),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'updatedBy': serializer.toJson<String>(updatedBy),
      'lamport': serializer.toJson<int>(lamport),
      'fieldClocksJson': serializer.toJson<Map<String, FieldClock>>(
        fieldClocksJson,
      ),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  CollectionRow copyWith({
    String? collectionId,
    String? name,
    int? createdAt,
    int? updatedAt,
    String? updatedBy,
    int? lamport,
    Map<String, FieldClock>? fieldClocksJson,
    Value<int?> deletedAt = const Value.absent(),
  }) => CollectionRow(
    collectionId: collectionId ?? this.collectionId,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
    lamport: lamport ?? this.lamport,
    fieldClocksJson: fieldClocksJson ?? this.fieldClocksJson,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  CollectionRow copyWithCompanion(CollectionsCompanion data) {
    return CollectionRow(
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedBy: data.updatedBy.present ? data.updatedBy.value : this.updatedBy,
      lamport: data.lamport.present ? data.lamport.value : this.lamport,
      fieldClocksJson: data.fieldClocksJson.present
          ? data.fieldClocksJson.value
          : this.fieldClocksJson,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionRow(')
          ..write('collectionId: $collectionId, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('lamport: $lamport, ')
          ..write('fieldClocksJson: $fieldClocksJson, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    collectionId,
    name,
    createdAt,
    updatedAt,
    updatedBy,
    lamport,
    fieldClocksJson,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionRow &&
          other.collectionId == this.collectionId &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.updatedBy == this.updatedBy &&
          other.lamport == this.lamport &&
          other.fieldClocksJson == this.fieldClocksJson &&
          other.deletedAt == this.deletedAt);
}

class CollectionsCompanion extends UpdateCompanion<CollectionRow> {
  final Value<String> collectionId;
  final Value<String> name;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<String> updatedBy;
  final Value<int> lamport;
  final Value<Map<String, FieldClock>> fieldClocksJson;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const CollectionsCompanion({
    this.collectionId = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedBy = const Value.absent(),
    this.lamport = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionsCompanion.insert({
    required String collectionId,
    required String name,
    required int createdAt,
    required int updatedAt,
    required String updatedBy,
    this.lamport = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : collectionId = Value(collectionId),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       updatedBy = Value(updatedBy);
  static Insertable<CollectionRow> custom({
    Expression<String>? collectionId,
    Expression<String>? name,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? updatedBy,
    Expression<int>? lamport,
    Expression<String>? fieldClocksJson,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (collectionId != null) 'collection_id': collectionId,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedBy != null) 'updated_by': updatedBy,
      if (lamport != null) 'lamport': lamport,
      if (fieldClocksJson != null) 'field_clocks_json': fieldClocksJson,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionsCompanion copyWith({
    Value<String>? collectionId,
    Value<String>? name,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<String>? updatedBy,
    Value<int>? lamport,
    Value<Map<String, FieldClock>>? fieldClocksJson,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CollectionsCompanion(
      collectionId: collectionId ?? this.collectionId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      lamport: lamport ?? this.lamport,
      fieldClocksJson: fieldClocksJson ?? this.fieldClocksJson,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (updatedBy.present) {
      map['updated_by'] = Variable<String>(updatedBy.value);
    }
    if (lamport.present) {
      map['lamport'] = Variable<int>(lamport.value);
    }
    if (fieldClocksJson.present) {
      map['field_clocks_json'] = Variable<String>(
        $CollectionsTable.$converterfieldClocksJson.toSql(
          fieldClocksJson.value,
        ),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsCompanion(')
          ..write('collectionId: $collectionId, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('lamport: $lamport, ')
          ..write('fieldClocksJson: $fieldClocksJson, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions
    with TableInfo<$SessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<String> collectionId = GeneratedColumn<String>(
    'collection_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageHashMeta = const VerificationMeta(
    'imageHash',
  );
  @override
  late final GeneratedColumn<String> imageHash = GeneratedColumn<String>(
    'image_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceDeviceMeta = const VerificationMeta(
    'sourceDevice',
  );
  @override
  late final GeneratedColumn<String> sourceDevice = GeneratedColumn<String>(
    'source_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiProviderMeta = const VerificationMeta(
    'aiProvider',
  );
  @override
  late final GeneratedColumn<String> aiProvider = GeneratedColumn<String>(
    'ai_provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiModelMeta = const VerificationMeta(
    'aiModel',
  );
  @override
  late final GeneratedColumn<String> aiModel = GeneratedColumn<String>(
    'ai_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _promptVersionMeta = const VerificationMeta(
    'promptVersion',
  );
  @override
  late final GeneratedColumn<String> promptVersion = GeneratedColumn<String>(
    'prompt_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawResponseMeta = const VerificationMeta(
    'rawResponse',
  );
  @override
  late final GeneratedColumn<String> rawResponse = GeneratedColumn<String>(
    'raw_response',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cachedMeta = const VerificationMeta('cached');
  @override
  late final GeneratedColumn<bool> cached = GeneratedColumn<bool>(
    'cached',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("cached" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _questionCountMeta = const VerificationMeta(
    'questionCount',
  );
  @override
  late final GeneratedColumn<int> questionCount = GeneratedColumn<int>(
    'question_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _latencyMsMeta = const VerificationMeta(
    'latencyMs',
  );
  @override
  late final GeneratedColumn<int> latencyMs = GeneratedColumn<int>(
    'latency_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByMeta = const VerificationMeta(
    'updatedBy',
  );
  @override
  late final GeneratedColumn<String> updatedBy = GeneratedColumn<String>(
    'updated_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lamportMeta = const VerificationMeta(
    'lamport',
  );
  @override
  late final GeneratedColumn<int> lamport = GeneratedColumn<int>(
    'lamport',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, FieldClock>, String>
  fieldClocksJson =
      GeneratedColumn<String>(
        'field_clocks_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      ).withConverter<Map<String, FieldClock>>(
        $SessionsTable.$converterfieldClocksJson,
      );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    taskId,
    collectionId,
    imageHash,
    sourceDevice,
    status,
    errorCode,
    errorMessage,
    aiProvider,
    aiModel,
    promptVersion,
    rawResponse,
    cached,
    questionCount,
    latencyMs,
    createdAt,
    updatedAt,
    updatedBy,
    lamport,
    fieldClocksJson,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
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
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    }
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    }
    if (data.containsKey('image_hash')) {
      context.handle(
        _imageHashMeta,
        imageHash.isAcceptableOrUnknown(data['image_hash']!, _imageHashMeta),
      );
    } else if (isInserting) {
      context.missing(_imageHashMeta);
    }
    if (data.containsKey('source_device')) {
      context.handle(
        _sourceDeviceMeta,
        sourceDevice.isAcceptableOrUnknown(
          data['source_device']!,
          _sourceDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceDeviceMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('ai_provider')) {
      context.handle(
        _aiProviderMeta,
        aiProvider.isAcceptableOrUnknown(data['ai_provider']!, _aiProviderMeta),
      );
    }
    if (data.containsKey('ai_model')) {
      context.handle(
        _aiModelMeta,
        aiModel.isAcceptableOrUnknown(data['ai_model']!, _aiModelMeta),
      );
    }
    if (data.containsKey('prompt_version')) {
      context.handle(
        _promptVersionMeta,
        promptVersion.isAcceptableOrUnknown(
          data['prompt_version']!,
          _promptVersionMeta,
        ),
      );
    }
    if (data.containsKey('raw_response')) {
      context.handle(
        _rawResponseMeta,
        rawResponse.isAcceptableOrUnknown(
          data['raw_response']!,
          _rawResponseMeta,
        ),
      );
    }
    if (data.containsKey('cached')) {
      context.handle(
        _cachedMeta,
        cached.isAcceptableOrUnknown(data['cached']!, _cachedMeta),
      );
    }
    if (data.containsKey('question_count')) {
      context.handle(
        _questionCountMeta,
        questionCount.isAcceptableOrUnknown(
          data['question_count']!,
          _questionCountMeta,
        ),
      );
    }
    if (data.containsKey('latency_ms')) {
      context.handle(
        _latencyMsMeta,
        latencyMs.isAcceptableOrUnknown(data['latency_ms']!, _latencyMsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by')) {
      context.handle(
        _updatedByMeta,
        updatedBy.isAcceptableOrUnknown(data['updated_by']!, _updatedByMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedByMeta);
    }
    if (data.containsKey('lamport')) {
      context.handle(
        _lamportMeta,
        lamport.isAcceptableOrUnknown(data['lamport']!, _lamportMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      ),
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      ),
      imageHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_hash'],
      )!,
      sourceDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_device'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      aiProvider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_provider'],
      ),
      aiModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_model'],
      ),
      promptVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_version'],
      ),
      rawResponse: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_response'],
      ),
      cached: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}cached'],
      )!,
      questionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}question_count'],
      )!,
      latencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latency_ms'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by'],
      )!,
      lamport: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lamport'],
      )!,
      fieldClocksJson: $SessionsTable.$converterfieldClocksJson.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}field_clocks_json'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, FieldClock>, String?>
  $converterfieldClocksJson = const FieldClocksConverter();
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final String sessionId;

  /// 发起端生成的幂等 id。
  final String? taskId;

  /// 所属合集（用户需求 8）。历史数据为 NULL，显示为「未分类」。
  final String? collectionId;

  /// 多页识别的**第一页**；页序见 session_images。
  final String imageHash;
  final String sourceDevice;

  /// queued|analyzing|done|failed|cancelled
  final String status;
  final String? errorCode;
  final String? errorMessage;
  final String? aiProvider;
  final String? aiModel;
  final String? promptVersion;

  /// 解析失败时保留原文。
  final String? rawResponse;
  final bool cached;
  final int questionCount;
  final int? latencyMs;
  final int createdAt;
  final int updatedAt;
  final String updatedBy;
  final int lamport;

  /// 逐字段写入时钟，见 data-model.md 2.2。
  final Map<String, FieldClock> fieldClocksJson;
  final int? deletedAt;
  const SessionRow({
    required this.sessionId,
    this.taskId,
    this.collectionId,
    required this.imageHash,
    required this.sourceDevice,
    required this.status,
    this.errorCode,
    this.errorMessage,
    this.aiProvider,
    this.aiModel,
    this.promptVersion,
    this.rawResponse,
    required this.cached,
    required this.questionCount,
    this.latencyMs,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    required this.lamport,
    required this.fieldClocksJson,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    if (!nullToAbsent || taskId != null) {
      map['task_id'] = Variable<String>(taskId);
    }
    if (!nullToAbsent || collectionId != null) {
      map['collection_id'] = Variable<String>(collectionId);
    }
    map['image_hash'] = Variable<String>(imageHash);
    map['source_device'] = Variable<String>(sourceDevice);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    if (!nullToAbsent || aiProvider != null) {
      map['ai_provider'] = Variable<String>(aiProvider);
    }
    if (!nullToAbsent || aiModel != null) {
      map['ai_model'] = Variable<String>(aiModel);
    }
    if (!nullToAbsent || promptVersion != null) {
      map['prompt_version'] = Variable<String>(promptVersion);
    }
    if (!nullToAbsent || rawResponse != null) {
      map['raw_response'] = Variable<String>(rawResponse);
    }
    map['cached'] = Variable<bool>(cached);
    map['question_count'] = Variable<int>(questionCount);
    if (!nullToAbsent || latencyMs != null) {
      map['latency_ms'] = Variable<int>(latencyMs);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['updated_by'] = Variable<String>(updatedBy);
    map['lamport'] = Variable<int>(lamport);
    {
      map['field_clocks_json'] = Variable<String>(
        $SessionsTable.$converterfieldClocksJson.toSql(fieldClocksJson),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      sessionId: Value(sessionId),
      taskId: taskId == null && nullToAbsent
          ? const Value.absent()
          : Value(taskId),
      collectionId: collectionId == null && nullToAbsent
          ? const Value.absent()
          : Value(collectionId),
      imageHash: Value(imageHash),
      sourceDevice: Value(sourceDevice),
      status: Value(status),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      aiProvider: aiProvider == null && nullToAbsent
          ? const Value.absent()
          : Value(aiProvider),
      aiModel: aiModel == null && nullToAbsent
          ? const Value.absent()
          : Value(aiModel),
      promptVersion: promptVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(promptVersion),
      rawResponse: rawResponse == null && nullToAbsent
          ? const Value.absent()
          : Value(rawResponse),
      cached: Value(cached),
      questionCount: Value(questionCount),
      latencyMs: latencyMs == null && nullToAbsent
          ? const Value.absent()
          : Value(latencyMs),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      updatedBy: Value(updatedBy),
      lamport: Value(lamport),
      fieldClocksJson: Value(fieldClocksJson),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      taskId: serializer.fromJson<String?>(json['taskId']),
      collectionId: serializer.fromJson<String?>(json['collectionId']),
      imageHash: serializer.fromJson<String>(json['imageHash']),
      sourceDevice: serializer.fromJson<String>(json['sourceDevice']),
      status: serializer.fromJson<String>(json['status']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      aiProvider: serializer.fromJson<String?>(json['aiProvider']),
      aiModel: serializer.fromJson<String?>(json['aiModel']),
      promptVersion: serializer.fromJson<String?>(json['promptVersion']),
      rawResponse: serializer.fromJson<String?>(json['rawResponse']),
      cached: serializer.fromJson<bool>(json['cached']),
      questionCount: serializer.fromJson<int>(json['questionCount']),
      latencyMs: serializer.fromJson<int?>(json['latencyMs']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      updatedBy: serializer.fromJson<String>(json['updatedBy']),
      lamport: serializer.fromJson<int>(json['lamport']),
      fieldClocksJson: serializer.fromJson<Map<String, FieldClock>>(
        json['fieldClocksJson'],
      ),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'taskId': serializer.toJson<String?>(taskId),
      'collectionId': serializer.toJson<String?>(collectionId),
      'imageHash': serializer.toJson<String>(imageHash),
      'sourceDevice': serializer.toJson<String>(sourceDevice),
      'status': serializer.toJson<String>(status),
      'errorCode': serializer.toJson<String?>(errorCode),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'aiProvider': serializer.toJson<String?>(aiProvider),
      'aiModel': serializer.toJson<String?>(aiModel),
      'promptVersion': serializer.toJson<String?>(promptVersion),
      'rawResponse': serializer.toJson<String?>(rawResponse),
      'cached': serializer.toJson<bool>(cached),
      'questionCount': serializer.toJson<int>(questionCount),
      'latencyMs': serializer.toJson<int?>(latencyMs),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'updatedBy': serializer.toJson<String>(updatedBy),
      'lamport': serializer.toJson<int>(lamport),
      'fieldClocksJson': serializer.toJson<Map<String, FieldClock>>(
        fieldClocksJson,
      ),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  SessionRow copyWith({
    String? sessionId,
    Value<String?> taskId = const Value.absent(),
    Value<String?> collectionId = const Value.absent(),
    String? imageHash,
    String? sourceDevice,
    String? status,
    Value<String?> errorCode = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    Value<String?> aiProvider = const Value.absent(),
    Value<String?> aiModel = const Value.absent(),
    Value<String?> promptVersion = const Value.absent(),
    Value<String?> rawResponse = const Value.absent(),
    bool? cached,
    int? questionCount,
    Value<int?> latencyMs = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    String? updatedBy,
    int? lamport,
    Map<String, FieldClock>? fieldClocksJson,
    Value<int?> deletedAt = const Value.absent(),
  }) => SessionRow(
    sessionId: sessionId ?? this.sessionId,
    taskId: taskId.present ? taskId.value : this.taskId,
    collectionId: collectionId.present ? collectionId.value : this.collectionId,
    imageHash: imageHash ?? this.imageHash,
    sourceDevice: sourceDevice ?? this.sourceDevice,
    status: status ?? this.status,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    aiProvider: aiProvider.present ? aiProvider.value : this.aiProvider,
    aiModel: aiModel.present ? aiModel.value : this.aiModel,
    promptVersion: promptVersion.present
        ? promptVersion.value
        : this.promptVersion,
    rawResponse: rawResponse.present ? rawResponse.value : this.rawResponse,
    cached: cached ?? this.cached,
    questionCount: questionCount ?? this.questionCount,
    latencyMs: latencyMs.present ? latencyMs.value : this.latencyMs,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
    lamport: lamport ?? this.lamport,
    fieldClocksJson: fieldClocksJson ?? this.fieldClocksJson,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      imageHash: data.imageHash.present ? data.imageHash.value : this.imageHash,
      sourceDevice: data.sourceDevice.present
          ? data.sourceDevice.value
          : this.sourceDevice,
      status: data.status.present ? data.status.value : this.status,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      aiProvider: data.aiProvider.present
          ? data.aiProvider.value
          : this.aiProvider,
      aiModel: data.aiModel.present ? data.aiModel.value : this.aiModel,
      promptVersion: data.promptVersion.present
          ? data.promptVersion.value
          : this.promptVersion,
      rawResponse: data.rawResponse.present
          ? data.rawResponse.value
          : this.rawResponse,
      cached: data.cached.present ? data.cached.value : this.cached,
      questionCount: data.questionCount.present
          ? data.questionCount.value
          : this.questionCount,
      latencyMs: data.latencyMs.present ? data.latencyMs.value : this.latencyMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedBy: data.updatedBy.present ? data.updatedBy.value : this.updatedBy,
      lamport: data.lamport.present ? data.lamport.value : this.lamport,
      fieldClocksJson: data.fieldClocksJson.present
          ? data.fieldClocksJson.value
          : this.fieldClocksJson,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('sessionId: $sessionId, ')
          ..write('taskId: $taskId, ')
          ..write('collectionId: $collectionId, ')
          ..write('imageHash: $imageHash, ')
          ..write('sourceDevice: $sourceDevice, ')
          ..write('status: $status, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('aiProvider: $aiProvider, ')
          ..write('aiModel: $aiModel, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('rawResponse: $rawResponse, ')
          ..write('cached: $cached, ')
          ..write('questionCount: $questionCount, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('lamport: $lamport, ')
          ..write('fieldClocksJson: $fieldClocksJson, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    sessionId,
    taskId,
    collectionId,
    imageHash,
    sourceDevice,
    status,
    errorCode,
    errorMessage,
    aiProvider,
    aiModel,
    promptVersion,
    rawResponse,
    cached,
    questionCount,
    latencyMs,
    createdAt,
    updatedAt,
    updatedBy,
    lamport,
    fieldClocksJson,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.sessionId == this.sessionId &&
          other.taskId == this.taskId &&
          other.collectionId == this.collectionId &&
          other.imageHash == this.imageHash &&
          other.sourceDevice == this.sourceDevice &&
          other.status == this.status &&
          other.errorCode == this.errorCode &&
          other.errorMessage == this.errorMessage &&
          other.aiProvider == this.aiProvider &&
          other.aiModel == this.aiModel &&
          other.promptVersion == this.promptVersion &&
          other.rawResponse == this.rawResponse &&
          other.cached == this.cached &&
          other.questionCount == this.questionCount &&
          other.latencyMs == this.latencyMs &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.updatedBy == this.updatedBy &&
          other.lamport == this.lamport &&
          other.fieldClocksJson == this.fieldClocksJson &&
          other.deletedAt == this.deletedAt);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> sessionId;
  final Value<String?> taskId;
  final Value<String?> collectionId;
  final Value<String> imageHash;
  final Value<String> sourceDevice;
  final Value<String> status;
  final Value<String?> errorCode;
  final Value<String?> errorMessage;
  final Value<String?> aiProvider;
  final Value<String?> aiModel;
  final Value<String?> promptVersion;
  final Value<String?> rawResponse;
  final Value<bool> cached;
  final Value<int> questionCount;
  final Value<int?> latencyMs;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<String> updatedBy;
  final Value<int> lamport;
  final Value<Map<String, FieldClock>> fieldClocksJson;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const SessionsCompanion({
    this.sessionId = const Value.absent(),
    this.taskId = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.imageHash = const Value.absent(),
    this.sourceDevice = const Value.absent(),
    this.status = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.aiProvider = const Value.absent(),
    this.aiModel = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.rawResponse = const Value.absent(),
    this.cached = const Value.absent(),
    this.questionCount = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedBy = const Value.absent(),
    this.lamport = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String sessionId,
    this.taskId = const Value.absent(),
    this.collectionId = const Value.absent(),
    required String imageHash,
    required String sourceDevice,
    required String status,
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.aiProvider = const Value.absent(),
    this.aiModel = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.rawResponse = const Value.absent(),
    this.cached = const Value.absent(),
    this.questionCount = const Value.absent(),
    this.latencyMs = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    required String updatedBy,
    this.lamport = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       imageHash = Value(imageHash),
       sourceDevice = Value(sourceDevice),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       updatedBy = Value(updatedBy);
  static Insertable<SessionRow> custom({
    Expression<String>? sessionId,
    Expression<String>? taskId,
    Expression<String>? collectionId,
    Expression<String>? imageHash,
    Expression<String>? sourceDevice,
    Expression<String>? status,
    Expression<String>? errorCode,
    Expression<String>? errorMessage,
    Expression<String>? aiProvider,
    Expression<String>? aiModel,
    Expression<String>? promptVersion,
    Expression<String>? rawResponse,
    Expression<bool>? cached,
    Expression<int>? questionCount,
    Expression<int>? latencyMs,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? updatedBy,
    Expression<int>? lamport,
    Expression<String>? fieldClocksJson,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (taskId != null) 'task_id': taskId,
      if (collectionId != null) 'collection_id': collectionId,
      if (imageHash != null) 'image_hash': imageHash,
      if (sourceDevice != null) 'source_device': sourceDevice,
      if (status != null) 'status': status,
      if (errorCode != null) 'error_code': errorCode,
      if (errorMessage != null) 'error_message': errorMessage,
      if (aiProvider != null) 'ai_provider': aiProvider,
      if (aiModel != null) 'ai_model': aiModel,
      if (promptVersion != null) 'prompt_version': promptVersion,
      if (rawResponse != null) 'raw_response': rawResponse,
      if (cached != null) 'cached': cached,
      if (questionCount != null) 'question_count': questionCount,
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedBy != null) 'updated_by': updatedBy,
      if (lamport != null) 'lamport': lamport,
      if (fieldClocksJson != null) 'field_clocks_json': fieldClocksJson,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? sessionId,
    Value<String?>? taskId,
    Value<String?>? collectionId,
    Value<String>? imageHash,
    Value<String>? sourceDevice,
    Value<String>? status,
    Value<String?>? errorCode,
    Value<String?>? errorMessage,
    Value<String?>? aiProvider,
    Value<String?>? aiModel,
    Value<String?>? promptVersion,
    Value<String?>? rawResponse,
    Value<bool>? cached,
    Value<int>? questionCount,
    Value<int?>? latencyMs,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<String>? updatedBy,
    Value<int>? lamport,
    Value<Map<String, FieldClock>>? fieldClocksJson,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      sessionId: sessionId ?? this.sessionId,
      taskId: taskId ?? this.taskId,
      collectionId: collectionId ?? this.collectionId,
      imageHash: imageHash ?? this.imageHash,
      sourceDevice: sourceDevice ?? this.sourceDevice,
      status: status ?? this.status,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      aiProvider: aiProvider ?? this.aiProvider,
      aiModel: aiModel ?? this.aiModel,
      promptVersion: promptVersion ?? this.promptVersion,
      rawResponse: rawResponse ?? this.rawResponse,
      cached: cached ?? this.cached,
      questionCount: questionCount ?? this.questionCount,
      latencyMs: latencyMs ?? this.latencyMs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      lamport: lamport ?? this.lamport,
      fieldClocksJson: fieldClocksJson ?? this.fieldClocksJson,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (imageHash.present) {
      map['image_hash'] = Variable<String>(imageHash.value);
    }
    if (sourceDevice.present) {
      map['source_device'] = Variable<String>(sourceDevice.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (aiProvider.present) {
      map['ai_provider'] = Variable<String>(aiProvider.value);
    }
    if (aiModel.present) {
      map['ai_model'] = Variable<String>(aiModel.value);
    }
    if (promptVersion.present) {
      map['prompt_version'] = Variable<String>(promptVersion.value);
    }
    if (rawResponse.present) {
      map['raw_response'] = Variable<String>(rawResponse.value);
    }
    if (cached.present) {
      map['cached'] = Variable<bool>(cached.value);
    }
    if (questionCount.present) {
      map['question_count'] = Variable<int>(questionCount.value);
    }
    if (latencyMs.present) {
      map['latency_ms'] = Variable<int>(latencyMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (updatedBy.present) {
      map['updated_by'] = Variable<String>(updatedBy.value);
    }
    if (lamport.present) {
      map['lamport'] = Variable<int>(lamport.value);
    }
    if (fieldClocksJson.present) {
      map['field_clocks_json'] = Variable<String>(
        $SessionsTable.$converterfieldClocksJson.toSql(fieldClocksJson.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('taskId: $taskId, ')
          ..write('collectionId: $collectionId, ')
          ..write('imageHash: $imageHash, ')
          ..write('sourceDevice: $sourceDevice, ')
          ..write('status: $status, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('aiProvider: $aiProvider, ')
          ..write('aiModel: $aiModel, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('rawResponse: $rawResponse, ')
          ..write('cached: $cached, ')
          ..write('questionCount: $questionCount, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('lamport: $lamport, ')
          ..write('fieldClocksJson: $fieldClocksJson, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionImagesTable extends SessionImages
    with TableInfo<$SessionImagesTable, SessionImageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionImageIdMeta = const VerificationMeta(
    'sessionImageId',
  );
  @override
  late final GeneratedColumn<String> sessionImageId = GeneratedColumn<String>(
    'session_image_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageHashMeta = const VerificationMeta(
    'imageHash',
  );
  @override
  late final GeneratedColumn<String> imageHash = GeneratedColumn<String>(
    'image_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByMeta = const VerificationMeta(
    'updatedBy',
  );
  @override
  late final GeneratedColumn<String> updatedBy = GeneratedColumn<String>(
    'updated_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lamportMeta = const VerificationMeta(
    'lamport',
  );
  @override
  late final GeneratedColumn<int> lamport = GeneratedColumn<int>(
    'lamport',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, FieldClock>, String>
  fieldClocksJson =
      GeneratedColumn<String>(
        'field_clocks_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      ).withConverter<Map<String, FieldClock>>(
        $SessionImagesTable.$converterfieldClocksJson,
      );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionImageId,
    sessionId,
    ordinal,
    imageHash,
    createdAt,
    updatedAt,
    updatedBy,
    lamport,
    fieldClocksJson,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_images';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionImageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_image_id')) {
      context.handle(
        _sessionImageIdMeta,
        sessionImageId.isAcceptableOrUnknown(
          data['session_image_id']!,
          _sessionImageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionImageIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('image_hash')) {
      context.handle(
        _imageHashMeta,
        imageHash.isAcceptableOrUnknown(data['image_hash']!, _imageHashMeta),
      );
    } else if (isInserting) {
      context.missing(_imageHashMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by')) {
      context.handle(
        _updatedByMeta,
        updatedBy.isAcceptableOrUnknown(data['updated_by']!, _updatedByMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedByMeta);
    }
    if (data.containsKey('lamport')) {
      context.handle(
        _lamportMeta,
        lamport.isAcceptableOrUnknown(data['lamport']!, _lamportMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionImageId};
  @override
  SessionImageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionImageRow(
      sessionImageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_image_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      imageHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_hash'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by'],
      )!,
      lamport: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lamport'],
      )!,
      fieldClocksJson: $SessionImagesTable.$converterfieldClocksJson.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}field_clocks_json'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $SessionImagesTable createAlias(String alias) {
    return $SessionImagesTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, FieldClock>, String?>
  $converterfieldClocksJson = const FieldClocksConverter();
}

class SessionImageRow extends DataClass implements Insertable<SessionImageRow> {
  final String sessionImageId;
  final String sessionId;

  /// 会话内的页序，0 起。
  final int ordinal;
  final String imageHash;
  final int createdAt;
  final int updatedAt;
  final String updatedBy;
  final int lamport;
  final Map<String, FieldClock> fieldClocksJson;
  final int? deletedAt;
  const SessionImageRow({
    required this.sessionImageId,
    required this.sessionId,
    required this.ordinal,
    required this.imageHash,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    required this.lamport,
    required this.fieldClocksJson,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_image_id'] = Variable<String>(sessionImageId);
    map['session_id'] = Variable<String>(sessionId);
    map['ordinal'] = Variable<int>(ordinal);
    map['image_hash'] = Variable<String>(imageHash);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['updated_by'] = Variable<String>(updatedBy);
    map['lamport'] = Variable<int>(lamport);
    {
      map['field_clocks_json'] = Variable<String>(
        $SessionImagesTable.$converterfieldClocksJson.toSql(fieldClocksJson),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  SessionImagesCompanion toCompanion(bool nullToAbsent) {
    return SessionImagesCompanion(
      sessionImageId: Value(sessionImageId),
      sessionId: Value(sessionId),
      ordinal: Value(ordinal),
      imageHash: Value(imageHash),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      updatedBy: Value(updatedBy),
      lamport: Value(lamport),
      fieldClocksJson: Value(fieldClocksJson),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory SessionImageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionImageRow(
      sessionImageId: serializer.fromJson<String>(json['sessionImageId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      imageHash: serializer.fromJson<String>(json['imageHash']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      updatedBy: serializer.fromJson<String>(json['updatedBy']),
      lamport: serializer.fromJson<int>(json['lamport']),
      fieldClocksJson: serializer.fromJson<Map<String, FieldClock>>(
        json['fieldClocksJson'],
      ),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionImageId': serializer.toJson<String>(sessionImageId),
      'sessionId': serializer.toJson<String>(sessionId),
      'ordinal': serializer.toJson<int>(ordinal),
      'imageHash': serializer.toJson<String>(imageHash),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'updatedBy': serializer.toJson<String>(updatedBy),
      'lamport': serializer.toJson<int>(lamport),
      'fieldClocksJson': serializer.toJson<Map<String, FieldClock>>(
        fieldClocksJson,
      ),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  SessionImageRow copyWith({
    String? sessionImageId,
    String? sessionId,
    int? ordinal,
    String? imageHash,
    int? createdAt,
    int? updatedAt,
    String? updatedBy,
    int? lamport,
    Map<String, FieldClock>? fieldClocksJson,
    Value<int?> deletedAt = const Value.absent(),
  }) => SessionImageRow(
    sessionImageId: sessionImageId ?? this.sessionImageId,
    sessionId: sessionId ?? this.sessionId,
    ordinal: ordinal ?? this.ordinal,
    imageHash: imageHash ?? this.imageHash,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
    lamport: lamport ?? this.lamport,
    fieldClocksJson: fieldClocksJson ?? this.fieldClocksJson,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  SessionImageRow copyWithCompanion(SessionImagesCompanion data) {
    return SessionImageRow(
      sessionImageId: data.sessionImageId.present
          ? data.sessionImageId.value
          : this.sessionImageId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      imageHash: data.imageHash.present ? data.imageHash.value : this.imageHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedBy: data.updatedBy.present ? data.updatedBy.value : this.updatedBy,
      lamport: data.lamport.present ? data.lamport.value : this.lamport,
      fieldClocksJson: data.fieldClocksJson.present
          ? data.fieldClocksJson.value
          : this.fieldClocksJson,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionImageRow(')
          ..write('sessionImageId: $sessionImageId, ')
          ..write('sessionId: $sessionId, ')
          ..write('ordinal: $ordinal, ')
          ..write('imageHash: $imageHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('lamport: $lamport, ')
          ..write('fieldClocksJson: $fieldClocksJson, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionImageId,
    sessionId,
    ordinal,
    imageHash,
    createdAt,
    updatedAt,
    updatedBy,
    lamport,
    fieldClocksJson,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionImageRow &&
          other.sessionImageId == this.sessionImageId &&
          other.sessionId == this.sessionId &&
          other.ordinal == this.ordinal &&
          other.imageHash == this.imageHash &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.updatedBy == this.updatedBy &&
          other.lamport == this.lamport &&
          other.fieldClocksJson == this.fieldClocksJson &&
          other.deletedAt == this.deletedAt);
}

class SessionImagesCompanion extends UpdateCompanion<SessionImageRow> {
  final Value<String> sessionImageId;
  final Value<String> sessionId;
  final Value<int> ordinal;
  final Value<String> imageHash;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<String> updatedBy;
  final Value<int> lamport;
  final Value<Map<String, FieldClock>> fieldClocksJson;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const SessionImagesCompanion({
    this.sessionImageId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.imageHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedBy = const Value.absent(),
    this.lamport = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionImagesCompanion.insert({
    required String sessionImageId,
    required String sessionId,
    required int ordinal,
    required String imageHash,
    required int createdAt,
    required int updatedAt,
    required String updatedBy,
    this.lamport = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionImageId = Value(sessionImageId),
       sessionId = Value(sessionId),
       ordinal = Value(ordinal),
       imageHash = Value(imageHash),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       updatedBy = Value(updatedBy);
  static Insertable<SessionImageRow> custom({
    Expression<String>? sessionImageId,
    Expression<String>? sessionId,
    Expression<int>? ordinal,
    Expression<String>? imageHash,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? updatedBy,
    Expression<int>? lamport,
    Expression<String>? fieldClocksJson,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionImageId != null) 'session_image_id': sessionImageId,
      if (sessionId != null) 'session_id': sessionId,
      if (ordinal != null) 'ordinal': ordinal,
      if (imageHash != null) 'image_hash': imageHash,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedBy != null) 'updated_by': updatedBy,
      if (lamport != null) 'lamport': lamport,
      if (fieldClocksJson != null) 'field_clocks_json': fieldClocksJson,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionImagesCompanion copyWith({
    Value<String>? sessionImageId,
    Value<String>? sessionId,
    Value<int>? ordinal,
    Value<String>? imageHash,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<String>? updatedBy,
    Value<int>? lamport,
    Value<Map<String, FieldClock>>? fieldClocksJson,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return SessionImagesCompanion(
      sessionImageId: sessionImageId ?? this.sessionImageId,
      sessionId: sessionId ?? this.sessionId,
      ordinal: ordinal ?? this.ordinal,
      imageHash: imageHash ?? this.imageHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      lamport: lamport ?? this.lamport,
      fieldClocksJson: fieldClocksJson ?? this.fieldClocksJson,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionImageId.present) {
      map['session_image_id'] = Variable<String>(sessionImageId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (imageHash.present) {
      map['image_hash'] = Variable<String>(imageHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (updatedBy.present) {
      map['updated_by'] = Variable<String>(updatedBy.value);
    }
    if (lamport.present) {
      map['lamport'] = Variable<int>(lamport.value);
    }
    if (fieldClocksJson.present) {
      map['field_clocks_json'] = Variable<String>(
        $SessionImagesTable.$converterfieldClocksJson.toSql(
          fieldClocksJson.value,
        ),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionImagesCompanion(')
          ..write('sessionImageId: $sessionImageId, ')
          ..write('sessionId: $sessionId, ')
          ..write('ordinal: $ordinal, ')
          ..write('imageHash: $imageHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('lamport: $lamport, ')
          ..write('fieldClocksJson: $fieldClocksJson, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QuestionsTable extends Questions
    with TableInfo<$QuestionsTable, QuestionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QuestionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _questionIdMeta = const VerificationMeta(
    'questionId',
  );
  @override
  late final GeneratedColumn<String> questionId = GeneratedColumn<String>(
    'question_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questionNoMeta = const VerificationMeta(
    'questionNo',
  );
  @override
  late final GeneratedColumn<String> questionNo = GeneratedColumn<String>(
    'question_no',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stemMeta = const VerificationMeta('stem');
  @override
  late final GeneratedColumn<String> stem = GeneratedColumn<String>(
    'stem',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _materialMeta = const VerificationMeta(
    'material',
  );
  @override
  late final GeneratedColumn<String> material = GeneratedColumn<String>(
    'material',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<Option>, String>
  optionsJson = GeneratedColumn<String>(
    'options_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  ).withConverter<List<Option>>($QuestionsTable.$converteroptionsJson);
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> choiceJson =
      GeneratedColumn<String>(
        'choice_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($QuestionsTable.$converterchoiceJson);
  static const VerificationMeta _answerTextMeta = const VerificationMeta(
    'answerText',
  );
  @override
  late final GeneratedColumn<String> answerText = GeneratedColumn<String>(
    'answer_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _analysisMeta = const VerificationMeta(
    'analysis',
  );
  @override
  late final GeneratedColumn<String> analysis = GeneratedColumn<String>(
    'analysis',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _needReviewMeta = const VerificationMeta(
    'needReview',
  );
  @override
  late final GeneratedColumn<bool> needReview = GeneratedColumn<bool>(
    'need_review',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("need_review" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _answerInImageMeta = const VerificationMeta(
    'answerInImage',
  );
  @override
  late final GeneratedColumn<bool> answerInImage = GeneratedColumn<bool>(
    'answer_in_image',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("answer_in_image" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _incompleteMeta = const VerificationMeta(
    'incomplete',
  );
  @override
  late final GeneratedColumn<bool> incomplete = GeneratedColumn<bool>(
    'incomplete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("incomplete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _answerGuessedMeta = const VerificationMeta(
    'answerGuessed',
  );
  @override
  late final GeneratedColumn<bool> answerGuessed = GeneratedColumn<bool>(
    'answer_guessed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("answer_guessed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String>
  warningsJson = GeneratedColumn<String>(
    'warnings_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  ).withConverter<List<String>>($QuestionsTable.$converterwarningsJson);
  static const VerificationMeta _analysisEditedMeta = const VerificationMeta(
    'analysisEdited',
  );
  @override
  late final GeneratedColumn<bool> analysisEdited = GeneratedColumn<bool>(
    'analysis_edited',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("analysis_edited" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _answerEditedMeta = const VerificationMeta(
    'answerEdited',
  );
  @override
  late final GeneratedColumn<bool> answerEdited = GeneratedColumn<bool>(
    'answer_edited',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("answer_edited" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, FieldClock>, String>
  fieldClocksJson =
      GeneratedColumn<String>(
        'field_clocks_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      ).withConverter<Map<String, FieldClock>>(
        $QuestionsTable.$converterfieldClocksJson,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByMeta = const VerificationMeta(
    'updatedBy',
  );
  @override
  late final GeneratedColumn<String> updatedBy = GeneratedColumn<String>(
    'updated_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lamportMeta = const VerificationMeta(
    'lamport',
  );
  @override
  late final GeneratedColumn<int> lamport = GeneratedColumn<int>(
    'lamport',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    questionId,
    sessionId,
    ordinal,
    questionNo,
    stem,
    material,
    type,
    optionsJson,
    choiceJson,
    answerText,
    analysis,
    confidence,
    needReview,
    answerInImage,
    incomplete,
    answerGuessed,
    warningsJson,
    analysisEdited,
    answerEdited,
    fieldClocksJson,
    createdAt,
    updatedAt,
    updatedBy,
    lamport,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'questions';
  @override
  VerificationContext validateIntegrity(
    Insertable<QuestionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('question_id')) {
      context.handle(
        _questionIdMeta,
        questionId.isAcceptableOrUnknown(data['question_id']!, _questionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_questionIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('question_no')) {
      context.handle(
        _questionNoMeta,
        questionNo.isAcceptableOrUnknown(data['question_no']!, _questionNoMeta),
      );
    }
    if (data.containsKey('stem')) {
      context.handle(
        _stemMeta,
        stem.isAcceptableOrUnknown(data['stem']!, _stemMeta),
      );
    } else if (isInserting) {
      context.missing(_stemMeta);
    }
    if (data.containsKey('material')) {
      context.handle(
        _materialMeta,
        material.isAcceptableOrUnknown(data['material']!, _materialMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('answer_text')) {
      context.handle(
        _answerTextMeta,
        answerText.isAcceptableOrUnknown(data['answer_text']!, _answerTextMeta),
      );
    }
    if (data.containsKey('analysis')) {
      context.handle(
        _analysisMeta,
        analysis.isAcceptableOrUnknown(data['analysis']!, _analysisMeta),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('need_review')) {
      context.handle(
        _needReviewMeta,
        needReview.isAcceptableOrUnknown(data['need_review']!, _needReviewMeta),
      );
    }
    if (data.containsKey('answer_in_image')) {
      context.handle(
        _answerInImageMeta,
        answerInImage.isAcceptableOrUnknown(
          data['answer_in_image']!,
          _answerInImageMeta,
        ),
      );
    }
    if (data.containsKey('incomplete')) {
      context.handle(
        _incompleteMeta,
        incomplete.isAcceptableOrUnknown(data['incomplete']!, _incompleteMeta),
      );
    }
    if (data.containsKey('answer_guessed')) {
      context.handle(
        _answerGuessedMeta,
        answerGuessed.isAcceptableOrUnknown(
          data['answer_guessed']!,
          _answerGuessedMeta,
        ),
      );
    }
    if (data.containsKey('analysis_edited')) {
      context.handle(
        _analysisEditedMeta,
        analysisEdited.isAcceptableOrUnknown(
          data['analysis_edited']!,
          _analysisEditedMeta,
        ),
      );
    }
    if (data.containsKey('answer_edited')) {
      context.handle(
        _answerEditedMeta,
        answerEdited.isAcceptableOrUnknown(
          data['answer_edited']!,
          _answerEditedMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by')) {
      context.handle(
        _updatedByMeta,
        updatedBy.isAcceptableOrUnknown(data['updated_by']!, _updatedByMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedByMeta);
    }
    if (data.containsKey('lamport')) {
      context.handle(
        _lamportMeta,
        lamport.isAcceptableOrUnknown(data['lamport']!, _lamportMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {questionId};
  @override
  QuestionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QuestionRow(
      questionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      questionNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_no'],
      ),
      stem: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stem'],
      )!,
      material: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}material'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      optionsJson: $QuestionsTable.$converteroptionsJson.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}options_json'],
        )!,
      ),
      choiceJson: $QuestionsTable.$converterchoiceJson.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}choice_json'],
        )!,
      ),
      answerText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_text'],
      ),
      analysis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}analysis'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
      needReview: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}need_review'],
      )!,
      answerInImage: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}answer_in_image'],
      )!,
      incomplete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}incomplete'],
      )!,
      answerGuessed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}answer_guessed'],
      )!,
      warningsJson: $QuestionsTable.$converterwarningsJson.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}warnings_json'],
        )!,
      ),
      analysisEdited: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}analysis_edited'],
      )!,
      answerEdited: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}answer_edited'],
      )!,
      fieldClocksJson: $QuestionsTable.$converterfieldClocksJson.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}field_clocks_json'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by'],
      )!,
      lamport: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lamport'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $QuestionsTable createAlias(String alias) {
    return $QuestionsTable(attachedDatabase, alias);
  }

  static TypeConverter<List<Option>, String?> $converteroptionsJson =
      const OptionsListConverter();
  static TypeConverter<List<String>, String?> $converterchoiceJson =
      const StringListConverter();
  static TypeConverter<List<String>, String?> $converterwarningsJson =
      const StringListConverter();
  static TypeConverter<Map<String, FieldClock>, String?>
  $converterfieldClocksJson = const FieldClocksConverter();
}

class QuestionRow extends DataClass implements Insertable<QuestionRow> {
  final String questionId;
  final String sessionId;

  /// 会话内的顺序，0 起。
  final int ordinal;
  final String? questionNo;
  final String stem;

  /// 阅读材料 / 文章原文（用户反馈 15）：只有阅读类题目才有，端侧默认折叠。
  /// 空串 = 无附属材料（绝大多数题目）。
  final String material;

  /// single|multi|judge|blank|subjective
  final String type;
  final List<Option> optionsJson;
  final List<String> choiceJson;
  final String? answerText;
  final String analysis;
  final double confidence;
  final bool needReview;
  final bool answerInImage;

  /// 题目不全（用户需求 2）：题干/选项被截断或缺失，卡片加黄框提示。
  final bool incomplete;

  /// 答案是 AI 猜测（用户需求 2）：题干在但选项不全时，AI 推断的答案。
  final bool answerGuessed;
  final List<String> warningsJson;

  /// 字段级 user_edited 标记。
  final bool analysisEdited;
  final bool answerEdited;
  final Map<String, FieldClock> fieldClocksJson;
  final int createdAt;
  final int updatedAt;
  final String updatedBy;
  final int lamport;
  final int? deletedAt;
  const QuestionRow({
    required this.questionId,
    required this.sessionId,
    required this.ordinal,
    this.questionNo,
    required this.stem,
    required this.material,
    required this.type,
    required this.optionsJson,
    required this.choiceJson,
    this.answerText,
    required this.analysis,
    required this.confidence,
    required this.needReview,
    required this.answerInImage,
    required this.incomplete,
    required this.answerGuessed,
    required this.warningsJson,
    required this.analysisEdited,
    required this.answerEdited,
    required this.fieldClocksJson,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    required this.lamport,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['question_id'] = Variable<String>(questionId);
    map['session_id'] = Variable<String>(sessionId);
    map['ordinal'] = Variable<int>(ordinal);
    if (!nullToAbsent || questionNo != null) {
      map['question_no'] = Variable<String>(questionNo);
    }
    map['stem'] = Variable<String>(stem);
    map['material'] = Variable<String>(material);
    map['type'] = Variable<String>(type);
    {
      map['options_json'] = Variable<String>(
        $QuestionsTable.$converteroptionsJson.toSql(optionsJson),
      );
    }
    {
      map['choice_json'] = Variable<String>(
        $QuestionsTable.$converterchoiceJson.toSql(choiceJson),
      );
    }
    if (!nullToAbsent || answerText != null) {
      map['answer_text'] = Variable<String>(answerText);
    }
    map['analysis'] = Variable<String>(analysis);
    map['confidence'] = Variable<double>(confidence);
    map['need_review'] = Variable<bool>(needReview);
    map['answer_in_image'] = Variable<bool>(answerInImage);
    map['incomplete'] = Variable<bool>(incomplete);
    map['answer_guessed'] = Variable<bool>(answerGuessed);
    {
      map['warnings_json'] = Variable<String>(
        $QuestionsTable.$converterwarningsJson.toSql(warningsJson),
      );
    }
    map['analysis_edited'] = Variable<bool>(analysisEdited);
    map['answer_edited'] = Variable<bool>(answerEdited);
    {
      map['field_clocks_json'] = Variable<String>(
        $QuestionsTable.$converterfieldClocksJson.toSql(fieldClocksJson),
      );
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['updated_by'] = Variable<String>(updatedBy);
    map['lamport'] = Variable<int>(lamport);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  QuestionsCompanion toCompanion(bool nullToAbsent) {
    return QuestionsCompanion(
      questionId: Value(questionId),
      sessionId: Value(sessionId),
      ordinal: Value(ordinal),
      questionNo: questionNo == null && nullToAbsent
          ? const Value.absent()
          : Value(questionNo),
      stem: Value(stem),
      material: Value(material),
      type: Value(type),
      optionsJson: Value(optionsJson),
      choiceJson: Value(choiceJson),
      answerText: answerText == null && nullToAbsent
          ? const Value.absent()
          : Value(answerText),
      analysis: Value(analysis),
      confidence: Value(confidence),
      needReview: Value(needReview),
      answerInImage: Value(answerInImage),
      incomplete: Value(incomplete),
      answerGuessed: Value(answerGuessed),
      warningsJson: Value(warningsJson),
      analysisEdited: Value(analysisEdited),
      answerEdited: Value(answerEdited),
      fieldClocksJson: Value(fieldClocksJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      updatedBy: Value(updatedBy),
      lamport: Value(lamport),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory QuestionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QuestionRow(
      questionId: serializer.fromJson<String>(json['questionId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      questionNo: serializer.fromJson<String?>(json['questionNo']),
      stem: serializer.fromJson<String>(json['stem']),
      material: serializer.fromJson<String>(json['material']),
      type: serializer.fromJson<String>(json['type']),
      optionsJson: serializer.fromJson<List<Option>>(json['optionsJson']),
      choiceJson: serializer.fromJson<List<String>>(json['choiceJson']),
      answerText: serializer.fromJson<String?>(json['answerText']),
      analysis: serializer.fromJson<String>(json['analysis']),
      confidence: serializer.fromJson<double>(json['confidence']),
      needReview: serializer.fromJson<bool>(json['needReview']),
      answerInImage: serializer.fromJson<bool>(json['answerInImage']),
      incomplete: serializer.fromJson<bool>(json['incomplete']),
      answerGuessed: serializer.fromJson<bool>(json['answerGuessed']),
      warningsJson: serializer.fromJson<List<String>>(json['warningsJson']),
      analysisEdited: serializer.fromJson<bool>(json['analysisEdited']),
      answerEdited: serializer.fromJson<bool>(json['answerEdited']),
      fieldClocksJson: serializer.fromJson<Map<String, FieldClock>>(
        json['fieldClocksJson'],
      ),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      updatedBy: serializer.fromJson<String>(json['updatedBy']),
      lamport: serializer.fromJson<int>(json['lamport']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'questionId': serializer.toJson<String>(questionId),
      'sessionId': serializer.toJson<String>(sessionId),
      'ordinal': serializer.toJson<int>(ordinal),
      'questionNo': serializer.toJson<String?>(questionNo),
      'stem': serializer.toJson<String>(stem),
      'material': serializer.toJson<String>(material),
      'type': serializer.toJson<String>(type),
      'optionsJson': serializer.toJson<List<Option>>(optionsJson),
      'choiceJson': serializer.toJson<List<String>>(choiceJson),
      'answerText': serializer.toJson<String?>(answerText),
      'analysis': serializer.toJson<String>(analysis),
      'confidence': serializer.toJson<double>(confidence),
      'needReview': serializer.toJson<bool>(needReview),
      'answerInImage': serializer.toJson<bool>(answerInImage),
      'incomplete': serializer.toJson<bool>(incomplete),
      'answerGuessed': serializer.toJson<bool>(answerGuessed),
      'warningsJson': serializer.toJson<List<String>>(warningsJson),
      'analysisEdited': serializer.toJson<bool>(analysisEdited),
      'answerEdited': serializer.toJson<bool>(answerEdited),
      'fieldClocksJson': serializer.toJson<Map<String, FieldClock>>(
        fieldClocksJson,
      ),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'updatedBy': serializer.toJson<String>(updatedBy),
      'lamport': serializer.toJson<int>(lamport),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  QuestionRow copyWith({
    String? questionId,
    String? sessionId,
    int? ordinal,
    Value<String?> questionNo = const Value.absent(),
    String? stem,
    String? material,
    String? type,
    List<Option>? optionsJson,
    List<String>? choiceJson,
    Value<String?> answerText = const Value.absent(),
    String? analysis,
    double? confidence,
    bool? needReview,
    bool? answerInImage,
    bool? incomplete,
    bool? answerGuessed,
    List<String>? warningsJson,
    bool? analysisEdited,
    bool? answerEdited,
    Map<String, FieldClock>? fieldClocksJson,
    int? createdAt,
    int? updatedAt,
    String? updatedBy,
    int? lamport,
    Value<int?> deletedAt = const Value.absent(),
  }) => QuestionRow(
    questionId: questionId ?? this.questionId,
    sessionId: sessionId ?? this.sessionId,
    ordinal: ordinal ?? this.ordinal,
    questionNo: questionNo.present ? questionNo.value : this.questionNo,
    stem: stem ?? this.stem,
    material: material ?? this.material,
    type: type ?? this.type,
    optionsJson: optionsJson ?? this.optionsJson,
    choiceJson: choiceJson ?? this.choiceJson,
    answerText: answerText.present ? answerText.value : this.answerText,
    analysis: analysis ?? this.analysis,
    confidence: confidence ?? this.confidence,
    needReview: needReview ?? this.needReview,
    answerInImage: answerInImage ?? this.answerInImage,
    incomplete: incomplete ?? this.incomplete,
    answerGuessed: answerGuessed ?? this.answerGuessed,
    warningsJson: warningsJson ?? this.warningsJson,
    analysisEdited: analysisEdited ?? this.analysisEdited,
    answerEdited: answerEdited ?? this.answerEdited,
    fieldClocksJson: fieldClocksJson ?? this.fieldClocksJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
    lamport: lamport ?? this.lamport,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  QuestionRow copyWithCompanion(QuestionsCompanion data) {
    return QuestionRow(
      questionId: data.questionId.present
          ? data.questionId.value
          : this.questionId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      questionNo: data.questionNo.present
          ? data.questionNo.value
          : this.questionNo,
      stem: data.stem.present ? data.stem.value : this.stem,
      material: data.material.present ? data.material.value : this.material,
      type: data.type.present ? data.type.value : this.type,
      optionsJson: data.optionsJson.present
          ? data.optionsJson.value
          : this.optionsJson,
      choiceJson: data.choiceJson.present
          ? data.choiceJson.value
          : this.choiceJson,
      answerText: data.answerText.present
          ? data.answerText.value
          : this.answerText,
      analysis: data.analysis.present ? data.analysis.value : this.analysis,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      needReview: data.needReview.present
          ? data.needReview.value
          : this.needReview,
      answerInImage: data.answerInImage.present
          ? data.answerInImage.value
          : this.answerInImage,
      incomplete: data.incomplete.present
          ? data.incomplete.value
          : this.incomplete,
      answerGuessed: data.answerGuessed.present
          ? data.answerGuessed.value
          : this.answerGuessed,
      warningsJson: data.warningsJson.present
          ? data.warningsJson.value
          : this.warningsJson,
      analysisEdited: data.analysisEdited.present
          ? data.analysisEdited.value
          : this.analysisEdited,
      answerEdited: data.answerEdited.present
          ? data.answerEdited.value
          : this.answerEdited,
      fieldClocksJson: data.fieldClocksJson.present
          ? data.fieldClocksJson.value
          : this.fieldClocksJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedBy: data.updatedBy.present ? data.updatedBy.value : this.updatedBy,
      lamport: data.lamport.present ? data.lamport.value : this.lamport,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QuestionRow(')
          ..write('questionId: $questionId, ')
          ..write('sessionId: $sessionId, ')
          ..write('ordinal: $ordinal, ')
          ..write('questionNo: $questionNo, ')
          ..write('stem: $stem, ')
          ..write('material: $material, ')
          ..write('type: $type, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('choiceJson: $choiceJson, ')
          ..write('answerText: $answerText, ')
          ..write('analysis: $analysis, ')
          ..write('confidence: $confidence, ')
          ..write('needReview: $needReview, ')
          ..write('answerInImage: $answerInImage, ')
          ..write('incomplete: $incomplete, ')
          ..write('answerGuessed: $answerGuessed, ')
          ..write('warningsJson: $warningsJson, ')
          ..write('analysisEdited: $analysisEdited, ')
          ..write('answerEdited: $answerEdited, ')
          ..write('fieldClocksJson: $fieldClocksJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('lamport: $lamport, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    questionId,
    sessionId,
    ordinal,
    questionNo,
    stem,
    material,
    type,
    optionsJson,
    choiceJson,
    answerText,
    analysis,
    confidence,
    needReview,
    answerInImage,
    incomplete,
    answerGuessed,
    warningsJson,
    analysisEdited,
    answerEdited,
    fieldClocksJson,
    createdAt,
    updatedAt,
    updatedBy,
    lamport,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QuestionRow &&
          other.questionId == this.questionId &&
          other.sessionId == this.sessionId &&
          other.ordinal == this.ordinal &&
          other.questionNo == this.questionNo &&
          other.stem == this.stem &&
          other.material == this.material &&
          other.type == this.type &&
          other.optionsJson == this.optionsJson &&
          other.choiceJson == this.choiceJson &&
          other.answerText == this.answerText &&
          other.analysis == this.analysis &&
          other.confidence == this.confidence &&
          other.needReview == this.needReview &&
          other.answerInImage == this.answerInImage &&
          other.incomplete == this.incomplete &&
          other.answerGuessed == this.answerGuessed &&
          other.warningsJson == this.warningsJson &&
          other.analysisEdited == this.analysisEdited &&
          other.answerEdited == this.answerEdited &&
          other.fieldClocksJson == this.fieldClocksJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.updatedBy == this.updatedBy &&
          other.lamport == this.lamport &&
          other.deletedAt == this.deletedAt);
}

class QuestionsCompanion extends UpdateCompanion<QuestionRow> {
  final Value<String> questionId;
  final Value<String> sessionId;
  final Value<int> ordinal;
  final Value<String?> questionNo;
  final Value<String> stem;
  final Value<String> material;
  final Value<String> type;
  final Value<List<Option>> optionsJson;
  final Value<List<String>> choiceJson;
  final Value<String?> answerText;
  final Value<String> analysis;
  final Value<double> confidence;
  final Value<bool> needReview;
  final Value<bool> answerInImage;
  final Value<bool> incomplete;
  final Value<bool> answerGuessed;
  final Value<List<String>> warningsJson;
  final Value<bool> analysisEdited;
  final Value<bool> answerEdited;
  final Value<Map<String, FieldClock>> fieldClocksJson;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<String> updatedBy;
  final Value<int> lamport;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const QuestionsCompanion({
    this.questionId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.questionNo = const Value.absent(),
    this.stem = const Value.absent(),
    this.material = const Value.absent(),
    this.type = const Value.absent(),
    this.optionsJson = const Value.absent(),
    this.choiceJson = const Value.absent(),
    this.answerText = const Value.absent(),
    this.analysis = const Value.absent(),
    this.confidence = const Value.absent(),
    this.needReview = const Value.absent(),
    this.answerInImage = const Value.absent(),
    this.incomplete = const Value.absent(),
    this.answerGuessed = const Value.absent(),
    this.warningsJson = const Value.absent(),
    this.analysisEdited = const Value.absent(),
    this.answerEdited = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedBy = const Value.absent(),
    this.lamport = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QuestionsCompanion.insert({
    required String questionId,
    required String sessionId,
    required int ordinal,
    this.questionNo = const Value.absent(),
    required String stem,
    this.material = const Value.absent(),
    required String type,
    this.optionsJson = const Value.absent(),
    this.choiceJson = const Value.absent(),
    this.answerText = const Value.absent(),
    this.analysis = const Value.absent(),
    this.confidence = const Value.absent(),
    this.needReview = const Value.absent(),
    this.answerInImage = const Value.absent(),
    this.incomplete = const Value.absent(),
    this.answerGuessed = const Value.absent(),
    this.warningsJson = const Value.absent(),
    this.analysisEdited = const Value.absent(),
    this.answerEdited = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    required String updatedBy,
    this.lamport = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : questionId = Value(questionId),
       sessionId = Value(sessionId),
       ordinal = Value(ordinal),
       stem = Value(stem),
       type = Value(type),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       updatedBy = Value(updatedBy);
  static Insertable<QuestionRow> custom({
    Expression<String>? questionId,
    Expression<String>? sessionId,
    Expression<int>? ordinal,
    Expression<String>? questionNo,
    Expression<String>? stem,
    Expression<String>? material,
    Expression<String>? type,
    Expression<String>? optionsJson,
    Expression<String>? choiceJson,
    Expression<String>? answerText,
    Expression<String>? analysis,
    Expression<double>? confidence,
    Expression<bool>? needReview,
    Expression<bool>? answerInImage,
    Expression<bool>? incomplete,
    Expression<bool>? answerGuessed,
    Expression<String>? warningsJson,
    Expression<bool>? analysisEdited,
    Expression<bool>? answerEdited,
    Expression<String>? fieldClocksJson,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? updatedBy,
    Expression<int>? lamport,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (questionId != null) 'question_id': questionId,
      if (sessionId != null) 'session_id': sessionId,
      if (ordinal != null) 'ordinal': ordinal,
      if (questionNo != null) 'question_no': questionNo,
      if (stem != null) 'stem': stem,
      if (material != null) 'material': material,
      if (type != null) 'type': type,
      if (optionsJson != null) 'options_json': optionsJson,
      if (choiceJson != null) 'choice_json': choiceJson,
      if (answerText != null) 'answer_text': answerText,
      if (analysis != null) 'analysis': analysis,
      if (confidence != null) 'confidence': confidence,
      if (needReview != null) 'need_review': needReview,
      if (answerInImage != null) 'answer_in_image': answerInImage,
      if (incomplete != null) 'incomplete': incomplete,
      if (answerGuessed != null) 'answer_guessed': answerGuessed,
      if (warningsJson != null) 'warnings_json': warningsJson,
      if (analysisEdited != null) 'analysis_edited': analysisEdited,
      if (answerEdited != null) 'answer_edited': answerEdited,
      if (fieldClocksJson != null) 'field_clocks_json': fieldClocksJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedBy != null) 'updated_by': updatedBy,
      if (lamport != null) 'lamport': lamport,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QuestionsCompanion copyWith({
    Value<String>? questionId,
    Value<String>? sessionId,
    Value<int>? ordinal,
    Value<String?>? questionNo,
    Value<String>? stem,
    Value<String>? material,
    Value<String>? type,
    Value<List<Option>>? optionsJson,
    Value<List<String>>? choiceJson,
    Value<String?>? answerText,
    Value<String>? analysis,
    Value<double>? confidence,
    Value<bool>? needReview,
    Value<bool>? answerInImage,
    Value<bool>? incomplete,
    Value<bool>? answerGuessed,
    Value<List<String>>? warningsJson,
    Value<bool>? analysisEdited,
    Value<bool>? answerEdited,
    Value<Map<String, FieldClock>>? fieldClocksJson,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<String>? updatedBy,
    Value<int>? lamport,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return QuestionsCompanion(
      questionId: questionId ?? this.questionId,
      sessionId: sessionId ?? this.sessionId,
      ordinal: ordinal ?? this.ordinal,
      questionNo: questionNo ?? this.questionNo,
      stem: stem ?? this.stem,
      material: material ?? this.material,
      type: type ?? this.type,
      optionsJson: optionsJson ?? this.optionsJson,
      choiceJson: choiceJson ?? this.choiceJson,
      answerText: answerText ?? this.answerText,
      analysis: analysis ?? this.analysis,
      confidence: confidence ?? this.confidence,
      needReview: needReview ?? this.needReview,
      answerInImage: answerInImage ?? this.answerInImage,
      incomplete: incomplete ?? this.incomplete,
      answerGuessed: answerGuessed ?? this.answerGuessed,
      warningsJson: warningsJson ?? this.warningsJson,
      analysisEdited: analysisEdited ?? this.analysisEdited,
      answerEdited: answerEdited ?? this.answerEdited,
      fieldClocksJson: fieldClocksJson ?? this.fieldClocksJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      lamport: lamport ?? this.lamport,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (questionId.present) {
      map['question_id'] = Variable<String>(questionId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (questionNo.present) {
      map['question_no'] = Variable<String>(questionNo.value);
    }
    if (stem.present) {
      map['stem'] = Variable<String>(stem.value);
    }
    if (material.present) {
      map['material'] = Variable<String>(material.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (optionsJson.present) {
      map['options_json'] = Variable<String>(
        $QuestionsTable.$converteroptionsJson.toSql(optionsJson.value),
      );
    }
    if (choiceJson.present) {
      map['choice_json'] = Variable<String>(
        $QuestionsTable.$converterchoiceJson.toSql(choiceJson.value),
      );
    }
    if (answerText.present) {
      map['answer_text'] = Variable<String>(answerText.value);
    }
    if (analysis.present) {
      map['analysis'] = Variable<String>(analysis.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (needReview.present) {
      map['need_review'] = Variable<bool>(needReview.value);
    }
    if (answerInImage.present) {
      map['answer_in_image'] = Variable<bool>(answerInImage.value);
    }
    if (incomplete.present) {
      map['incomplete'] = Variable<bool>(incomplete.value);
    }
    if (answerGuessed.present) {
      map['answer_guessed'] = Variable<bool>(answerGuessed.value);
    }
    if (warningsJson.present) {
      map['warnings_json'] = Variable<String>(
        $QuestionsTable.$converterwarningsJson.toSql(warningsJson.value),
      );
    }
    if (analysisEdited.present) {
      map['analysis_edited'] = Variable<bool>(analysisEdited.value);
    }
    if (answerEdited.present) {
      map['answer_edited'] = Variable<bool>(answerEdited.value);
    }
    if (fieldClocksJson.present) {
      map['field_clocks_json'] = Variable<String>(
        $QuestionsTable.$converterfieldClocksJson.toSql(fieldClocksJson.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (updatedBy.present) {
      map['updated_by'] = Variable<String>(updatedBy.value);
    }
    if (lamport.present) {
      map['lamport'] = Variable<int>(lamport.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QuestionsCompanion(')
          ..write('questionId: $questionId, ')
          ..write('sessionId: $sessionId, ')
          ..write('ordinal: $ordinal, ')
          ..write('questionNo: $questionNo, ')
          ..write('stem: $stem, ')
          ..write('material: $material, ')
          ..write('type: $type, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('choiceJson: $choiceJson, ')
          ..write('answerText: $answerText, ')
          ..write('analysis: $analysis, ')
          ..write('confidence: $confidence, ')
          ..write('needReview: $needReview, ')
          ..write('answerInImage: $answerInImage, ')
          ..write('incomplete: $incomplete, ')
          ..write('answerGuessed: $answerGuessed, ')
          ..write('warningsJson: $warningsJson, ')
          ..write('analysisEdited: $analysisEdited, ')
          ..write('answerEdited: $answerEdited, ')
          ..write('fieldClocksJson: $fieldClocksJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('lamport: $lamport, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOpsTable extends SyncOps with TableInfo<$SyncOpsTable, SyncOpRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOpsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _opIdMeta = const VerificationMeta('opId');
  @override
  late final GeneratedColumn<String> opId = GeneratedColumn<String>(
    'op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lamportMeta = const VerificationMeta(
    'lamport',
  );
  @override
  late final GeneratedColumn<int> lamport = GeneratedColumn<int>(
    'lamport',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opTypeMeta = const VerificationMeta('opType');
  @override
  late final GeneratedColumn<String> opType = GeneratedColumn<String>(
    'op_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldsJsonMeta = const VerificationMeta(
    'fieldsJson',
  );
  @override
  late final GeneratedColumn<String> fieldsJson = GeneratedColumn<String>(
    'fields_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    opId,
    deviceId,
    lamport,
    entity,
    entityId,
    opType,
    fieldsJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_ops';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOpRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('op_id')) {
      context.handle(
        _opIdMeta,
        opId.isAcceptableOrUnknown(data['op_id']!, _opIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('lamport')) {
      context.handle(
        _lamportMeta,
        lamport.isAcceptableOrUnknown(data['lamport']!, _lamportMeta),
      );
    } else if (isInserting) {
      context.missing(_lamportMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('op_type')) {
      context.handle(
        _opTypeMeta,
        opType.isAcceptableOrUnknown(data['op_type']!, _opTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_opTypeMeta);
    }
    if (data.containsKey('fields_json')) {
      context.handle(
        _fieldsJsonMeta,
        fieldsJson.isAcceptableOrUnknown(data['fields_json']!, _fieldsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldsJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {opId};
  @override
  SyncOpRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOpRow(
      opId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      lamport: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lamport'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      opType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_type'],
      )!,
      fieldsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fields_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncOpsTable createAlias(String alias) {
    return $SyncOpsTable(attachedDatabase, alias);
  }
}

class SyncOpRow extends DataClass implements Insertable<SyncOpRow> {
  /// UUID v4。
  final String opId;

  /// 产生该 op 的设备（含本机应用并转存的对端 op，保留原 device_id）。
  final String deviceId;
  final int lamport;

  /// 'session' | 'question' | 'image' | 'device' | 'snapshot'
  final String entity;
  final String entityId;

  /// 'upsert' | 'delete'
  final String opType;

  /// 只含变更字段，字段级 LWW 的依据。
  final String fieldsJson;
  final int createdAt;
  const SyncOpRow({
    required this.opId,
    required this.deviceId,
    required this.lamport,
    required this.entity,
    required this.entityId,
    required this.opType,
    required this.fieldsJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['op_id'] = Variable<String>(opId);
    map['device_id'] = Variable<String>(deviceId);
    map['lamport'] = Variable<int>(lamport);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['op_type'] = Variable<String>(opType);
    map['fields_json'] = Variable<String>(fieldsJson);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SyncOpsCompanion toCompanion(bool nullToAbsent) {
    return SyncOpsCompanion(
      opId: Value(opId),
      deviceId: Value(deviceId),
      lamport: Value(lamport),
      entity: Value(entity),
      entityId: Value(entityId),
      opType: Value(opType),
      fieldsJson: Value(fieldsJson),
      createdAt: Value(createdAt),
    );
  }

  factory SyncOpRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOpRow(
      opId: serializer.fromJson<String>(json['opId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      lamport: serializer.fromJson<int>(json['lamport']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entityId']),
      opType: serializer.fromJson<String>(json['opType']),
      fieldsJson: serializer.fromJson<String>(json['fieldsJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'opId': serializer.toJson<String>(opId),
      'deviceId': serializer.toJson<String>(deviceId),
      'lamport': serializer.toJson<int>(lamport),
      'entity': serializer.toJson<String>(entity),
      'entityId': serializer.toJson<String>(entityId),
      'opType': serializer.toJson<String>(opType),
      'fieldsJson': serializer.toJson<String>(fieldsJson),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  SyncOpRow copyWith({
    String? opId,
    String? deviceId,
    int? lamport,
    String? entity,
    String? entityId,
    String? opType,
    String? fieldsJson,
    int? createdAt,
  }) => SyncOpRow(
    opId: opId ?? this.opId,
    deviceId: deviceId ?? this.deviceId,
    lamport: lamport ?? this.lamport,
    entity: entity ?? this.entity,
    entityId: entityId ?? this.entityId,
    opType: opType ?? this.opType,
    fieldsJson: fieldsJson ?? this.fieldsJson,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncOpRow copyWithCompanion(SyncOpsCompanion data) {
    return SyncOpRow(
      opId: data.opId.present ? data.opId.value : this.opId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      lamport: data.lamport.present ? data.lamport.value : this.lamport,
      entity: data.entity.present ? data.entity.value : this.entity,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      opType: data.opType.present ? data.opType.value : this.opType,
      fieldsJson: data.fieldsJson.present
          ? data.fieldsJson.value
          : this.fieldsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOpRow(')
          ..write('opId: $opId, ')
          ..write('deviceId: $deviceId, ')
          ..write('lamport: $lamport, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('opType: $opType, ')
          ..write('fieldsJson: $fieldsJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    opId,
    deviceId,
    lamport,
    entity,
    entityId,
    opType,
    fieldsJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOpRow &&
          other.opId == this.opId &&
          other.deviceId == this.deviceId &&
          other.lamport == this.lamport &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.opType == this.opType &&
          other.fieldsJson == this.fieldsJson &&
          other.createdAt == this.createdAt);
}

class SyncOpsCompanion extends UpdateCompanion<SyncOpRow> {
  final Value<String> opId;
  final Value<String> deviceId;
  final Value<int> lamport;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> opType;
  final Value<String> fieldsJson;
  final Value<int> createdAt;
  final Value<int> rowid;
  const SyncOpsCompanion({
    this.opId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.lamport = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.opType = const Value.absent(),
    this.fieldsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOpsCompanion.insert({
    required String opId,
    required String deviceId,
    required int lamport,
    required String entity,
    required String entityId,
    required String opType,
    required String fieldsJson,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : opId = Value(opId),
       deviceId = Value(deviceId),
       lamport = Value(lamport),
       entity = Value(entity),
       entityId = Value(entityId),
       opType = Value(opType),
       fieldsJson = Value(fieldsJson),
       createdAt = Value(createdAt);
  static Insertable<SyncOpRow> custom({
    Expression<String>? opId,
    Expression<String>? deviceId,
    Expression<int>? lamport,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? opType,
    Expression<String>? fieldsJson,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (opId != null) 'op_id': opId,
      if (deviceId != null) 'device_id': deviceId,
      if (lamport != null) 'lamport': lamport,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (opType != null) 'op_type': opType,
      if (fieldsJson != null) 'fields_json': fieldsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOpsCompanion copyWith({
    Value<String>? opId,
    Value<String>? deviceId,
    Value<int>? lamport,
    Value<String>? entity,
    Value<String>? entityId,
    Value<String>? opType,
    Value<String>? fieldsJson,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return SyncOpsCompanion(
      opId: opId ?? this.opId,
      deviceId: deviceId ?? this.deviceId,
      lamport: lamport ?? this.lamport,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      opType: opType ?? this.opType,
      fieldsJson: fieldsJson ?? this.fieldsJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (opId.present) {
      map['op_id'] = Variable<String>(opId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (lamport.present) {
      map['lamport'] = Variable<int>(lamport.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (opType.present) {
      map['op_type'] = Variable<String>(opType.value);
    }
    if (fieldsJson.present) {
      map['fields_json'] = Variable<String>(fieldsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOpsCompanion(')
          ..write('opId: $opId, ')
          ..write('deviceId: $deviceId, ')
          ..write('lamport: $lamport, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('opType: $opType, ')
          ..write('fieldsJson: $fieldsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeerStatesTable extends PeerStates
    with TableInfo<$PeerStatesTable, PeerStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeerStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerDeviceIdMeta = const VerificationMeta(
    'peerDeviceId',
  );
  @override
  late final GeneratedColumn<String> peerDeviceId = GeneratedColumn<String>(
    'peer_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentLamportMeta = const VerificationMeta(
    'sentLamport',
  );
  @override
  late final GeneratedColumn<int> sentLamport = GeneratedColumn<int>(
    'sent_lamport',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ackedLamportMeta = const VerificationMeta(
    'ackedLamport',
  );
  @override
  late final GeneratedColumn<int> ackedLamport = GeneratedColumn<int>(
    'acked_lamport',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<int> lastSyncAt = GeneratedColumn<int>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    peerDeviceId,
    sentLamport,
    ackedLamport,
    lastSyncAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'peer_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<PeerStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_device_id')) {
      context.handle(
        _peerDeviceIdMeta,
        peerDeviceId.isAcceptableOrUnknown(
          data['peer_device_id']!,
          _peerDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerDeviceIdMeta);
    }
    if (data.containsKey('sent_lamport')) {
      context.handle(
        _sentLamportMeta,
        sentLamport.isAcceptableOrUnknown(
          data['sent_lamport']!,
          _sentLamportMeta,
        ),
      );
    }
    if (data.containsKey('acked_lamport')) {
      context.handle(
        _ackedLamportMeta,
        ackedLamport.isAcceptableOrUnknown(
          data['acked_lamport']!,
          _ackedLamportMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerDeviceId};
  @override
  PeerStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeerStateRow(
      peerDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_device_id'],
      )!,
      sentLamport: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sent_lamport'],
      )!,
      ackedLamport: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acked_lamport'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_sync_at'],
      ),
    );
  }

  @override
  $PeerStatesTable createAlias(String alias) {
    return $PeerStatesTable(attachedDatabase, alias);
  }
}

class PeerStateRow extends DataClass implements Insertable<PeerStateRow> {
  final String peerDeviceId;
  final int sentLamport;
  final int ackedLamport;
  final int? lastSyncAt;
  const PeerStateRow({
    required this.peerDeviceId,
    required this.sentLamport,
    required this.ackedLamport,
    this.lastSyncAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_device_id'] = Variable<String>(peerDeviceId);
    map['sent_lamport'] = Variable<int>(sentLamport);
    map['acked_lamport'] = Variable<int>(ackedLamport);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<int>(lastSyncAt);
    }
    return map;
  }

  PeerStatesCompanion toCompanion(bool nullToAbsent) {
    return PeerStatesCompanion(
      peerDeviceId: Value(peerDeviceId),
      sentLamport: Value(sentLamport),
      ackedLamport: Value(ackedLamport),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
    );
  }

  factory PeerStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeerStateRow(
      peerDeviceId: serializer.fromJson<String>(json['peerDeviceId']),
      sentLamport: serializer.fromJson<int>(json['sentLamport']),
      ackedLamport: serializer.fromJson<int>(json['ackedLamport']),
      lastSyncAt: serializer.fromJson<int?>(json['lastSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerDeviceId': serializer.toJson<String>(peerDeviceId),
      'sentLamport': serializer.toJson<int>(sentLamport),
      'ackedLamport': serializer.toJson<int>(ackedLamport),
      'lastSyncAt': serializer.toJson<int?>(lastSyncAt),
    };
  }

  PeerStateRow copyWith({
    String? peerDeviceId,
    int? sentLamport,
    int? ackedLamport,
    Value<int?> lastSyncAt = const Value.absent(),
  }) => PeerStateRow(
    peerDeviceId: peerDeviceId ?? this.peerDeviceId,
    sentLamport: sentLamport ?? this.sentLamport,
    ackedLamport: ackedLamport ?? this.ackedLamport,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
  );
  PeerStateRow copyWithCompanion(PeerStatesCompanion data) {
    return PeerStateRow(
      peerDeviceId: data.peerDeviceId.present
          ? data.peerDeviceId.value
          : this.peerDeviceId,
      sentLamport: data.sentLamport.present
          ? data.sentLamport.value
          : this.sentLamport,
      ackedLamport: data.ackedLamport.present
          ? data.ackedLamport.value
          : this.ackedLamport,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeerStateRow(')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('sentLamport: $sentLamport, ')
          ..write('ackedLamport: $ackedLamport, ')
          ..write('lastSyncAt: $lastSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(peerDeviceId, sentLamport, ackedLamport, lastSyncAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeerStateRow &&
          other.peerDeviceId == this.peerDeviceId &&
          other.sentLamport == this.sentLamport &&
          other.ackedLamport == this.ackedLamport &&
          other.lastSyncAt == this.lastSyncAt);
}

class PeerStatesCompanion extends UpdateCompanion<PeerStateRow> {
  final Value<String> peerDeviceId;
  final Value<int> sentLamport;
  final Value<int> ackedLamport;
  final Value<int?> lastSyncAt;
  final Value<int> rowid;
  const PeerStatesCompanion({
    this.peerDeviceId = const Value.absent(),
    this.sentLamport = const Value.absent(),
    this.ackedLamport = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeerStatesCompanion.insert({
    required String peerDeviceId,
    this.sentLamport = const Value.absent(),
    this.ackedLamport = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : peerDeviceId = Value(peerDeviceId);
  static Insertable<PeerStateRow> custom({
    Expression<String>? peerDeviceId,
    Expression<int>? sentLamport,
    Expression<int>? ackedLamport,
    Expression<int>? lastSyncAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerDeviceId != null) 'peer_device_id': peerDeviceId,
      if (sentLamport != null) 'sent_lamport': sentLamport,
      if (ackedLamport != null) 'acked_lamport': ackedLamport,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeerStatesCompanion copyWith({
    Value<String>? peerDeviceId,
    Value<int>? sentLamport,
    Value<int>? ackedLamport,
    Value<int?>? lastSyncAt,
    Value<int>? rowid,
  }) {
    return PeerStatesCompanion(
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      sentLamport: sentLamport ?? this.sentLamport,
      ackedLamport: ackedLamport ?? this.ackedLamport,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerDeviceId.present) {
      map['peer_device_id'] = Variable<String>(peerDeviceId.value);
    }
    if (sentLamport.present) {
      map['sent_lamport'] = Variable<int>(sentLamport.value);
    }
    if (ackedLamport.present) {
      map['acked_lamport'] = Variable<int>(ackedLamport.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<int>(lastSyncAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeerStatesCompanion(')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('sentLamport: $sentLamport, ')
          ..write('ackedLamport: $ackedLamport, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, TaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageHashMeta = const VerificationMeta(
    'imageHash',
  );
  @override
  late final GeneratedColumn<String> imageHash = GeneratedColumn<String>(
    'image_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceDeviceMeta = const VerificationMeta(
    'sourceDevice',
  );
  @override
  late final GeneratedColumn<String> sourceDevice = GeneratedColumn<String>(
    'source_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<int> finishedAt = GeneratedColumn<int>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    taskId,
    imageHash,
    sourceDevice,
    status,
    attempts,
    errorCode,
    sessionId,
    createdAt,
    startedAt,
    finishedAt,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('image_hash')) {
      context.handle(
        _imageHashMeta,
        imageHash.isAcceptableOrUnknown(data['image_hash']!, _imageHashMeta),
      );
    } else if (isInserting) {
      context.missing(_imageHashMeta);
    }
    if (data.containsKey('source_device')) {
      context.handle(
        _sourceDeviceMeta,
        sourceDevice.isAcceptableOrUnknown(
          data['source_device']!,
          _sourceDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceDeviceMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId};
  @override
  TaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRow(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      imageHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_hash'],
      )!,
      sourceDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_device'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      ),
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}finished_at'],
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      ),
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class TaskRow extends DataClass implements Insertable<TaskRow> {
  /// 发起端生成的 UUID v4，保证幂等。
  final String taskId;
  final String imageHash;
  final String sourceDevice;

  /// queued|analyzing|done|failed|cancelled
  final String status;
  final int attempts;
  final String? errorCode;
  final String? sessionId;
  final int createdAt;
  final int? startedAt;
  final int? finishedAt;

  /// 离线入队时记下的额外参数（`{"image_hashes": [...], "collection_id": "..."}`）。
  /// 多页识别（用户需求 4）与合集（用户需求 8）都必须在断网重连后原样补跑，
  /// 这两个值没有独立列，统一放这里，避免为一个本地协调表再加两列。
  final String? payloadJson;
  const TaskRow({
    required this.taskId,
    required this.imageHash,
    required this.sourceDevice,
    required this.status,
    required this.attempts,
    this.errorCode,
    this.sessionId,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['image_hash'] = Variable<String>(imageHash);
    map['source_device'] = Variable<String>(sourceDevice);
    map['status'] = Variable<String>(status);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<int>(startedAt);
    }
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<int>(finishedAt);
    }
    if (!nullToAbsent || payloadJson != null) {
      map['payload_json'] = Variable<String>(payloadJson);
    }
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      taskId: Value(taskId),
      imageHash: Value(imageHash),
      sourceDevice: Value(sourceDevice),
      status: Value(status),
      attempts: Value(attempts),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      createdAt: Value(createdAt),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      payloadJson: payloadJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadJson),
    );
  }

  factory TaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRow(
      taskId: serializer.fromJson<String>(json['taskId']),
      imageHash: serializer.fromJson<String>(json['imageHash']),
      sourceDevice: serializer.fromJson<String>(json['sourceDevice']),
      status: serializer.fromJson<String>(json['status']),
      attempts: serializer.fromJson<int>(json['attempts']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      startedAt: serializer.fromJson<int?>(json['startedAt']),
      finishedAt: serializer.fromJson<int?>(json['finishedAt']),
      payloadJson: serializer.fromJson<String?>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'imageHash': serializer.toJson<String>(imageHash),
      'sourceDevice': serializer.toJson<String>(sourceDevice),
      'status': serializer.toJson<String>(status),
      'attempts': serializer.toJson<int>(attempts),
      'errorCode': serializer.toJson<String?>(errorCode),
      'sessionId': serializer.toJson<String?>(sessionId),
      'createdAt': serializer.toJson<int>(createdAt),
      'startedAt': serializer.toJson<int?>(startedAt),
      'finishedAt': serializer.toJson<int?>(finishedAt),
      'payloadJson': serializer.toJson<String?>(payloadJson),
    };
  }

  TaskRow copyWith({
    String? taskId,
    String? imageHash,
    String? sourceDevice,
    String? status,
    int? attempts,
    Value<String?> errorCode = const Value.absent(),
    Value<String?> sessionId = const Value.absent(),
    int? createdAt,
    Value<int?> startedAt = const Value.absent(),
    Value<int?> finishedAt = const Value.absent(),
    Value<String?> payloadJson = const Value.absent(),
  }) => TaskRow(
    taskId: taskId ?? this.taskId,
    imageHash: imageHash ?? this.imageHash,
    sourceDevice: sourceDevice ?? this.sourceDevice,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    createdAt: createdAt ?? this.createdAt,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    payloadJson: payloadJson.present ? payloadJson.value : this.payloadJson,
  );
  TaskRow copyWithCompanion(TasksCompanion data) {
    return TaskRow(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      imageHash: data.imageHash.present ? data.imageHash.value : this.imageHash,
      sourceDevice: data.sourceDevice.present
          ? data.sourceDevice.value
          : this.sourceDevice,
      status: data.status.present ? data.status.value : this.status,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRow(')
          ..write('taskId: $taskId, ')
          ..write('imageHash: $imageHash, ')
          ..write('sourceDevice: $sourceDevice, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('errorCode: $errorCode, ')
          ..write('sessionId: $sessionId, ')
          ..write('createdAt: $createdAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    imageHash,
    sourceDevice,
    status,
    attempts,
    errorCode,
    sessionId,
    createdAt,
    startedAt,
    finishedAt,
    payloadJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRow &&
          other.taskId == this.taskId &&
          other.imageHash == this.imageHash &&
          other.sourceDevice == this.sourceDevice &&
          other.status == this.status &&
          other.attempts == this.attempts &&
          other.errorCode == this.errorCode &&
          other.sessionId == this.sessionId &&
          other.createdAt == this.createdAt &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt &&
          other.payloadJson == this.payloadJson);
}

class TasksCompanion extends UpdateCompanion<TaskRow> {
  final Value<String> taskId;
  final Value<String> imageHash;
  final Value<String> sourceDevice;
  final Value<String> status;
  final Value<int> attempts;
  final Value<String?> errorCode;
  final Value<String?> sessionId;
  final Value<int> createdAt;
  final Value<int?> startedAt;
  final Value<int?> finishedAt;
  final Value<String?> payloadJson;
  final Value<int> rowid;
  const TasksCompanion({
    this.taskId = const Value.absent(),
    this.imageHash = const Value.absent(),
    this.sourceDevice = const Value.absent(),
    this.status = const Value.absent(),
    this.attempts = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String taskId,
    required String imageHash,
    required String sourceDevice,
    required String status,
    this.attempts = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.sessionId = const Value.absent(),
    required int createdAt,
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       imageHash = Value(imageHash),
       sourceDevice = Value(sourceDevice),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<TaskRow> custom({
    Expression<String>? taskId,
    Expression<String>? imageHash,
    Expression<String>? sourceDevice,
    Expression<String>? status,
    Expression<int>? attempts,
    Expression<String>? errorCode,
    Expression<String>? sessionId,
    Expression<int>? createdAt,
    Expression<int>? startedAt,
    Expression<int>? finishedAt,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (imageHash != null) 'image_hash': imageHash,
      if (sourceDevice != null) 'source_device': sourceDevice,
      if (status != null) 'status': status,
      if (attempts != null) 'attempts': attempts,
      if (errorCode != null) 'error_code': errorCode,
      if (sessionId != null) 'session_id': sessionId,
      if (createdAt != null) 'created_at': createdAt,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? taskId,
    Value<String>? imageHash,
    Value<String>? sourceDevice,
    Value<String>? status,
    Value<int>? attempts,
    Value<String?>? errorCode,
    Value<String?>? sessionId,
    Value<int>? createdAt,
    Value<int?>? startedAt,
    Value<int?>? finishedAt,
    Value<String?>? payloadJson,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      taskId: taskId ?? this.taskId,
      imageHash: imageHash ?? this.imageHash,
      sourceDevice: sourceDevice ?? this.sourceDevice,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      errorCode: errorCode ?? this.errorCode,
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (imageHash.present) {
      map['image_hash'] = Variable<String>(imageHash.value);
    }
    if (sourceDevice.present) {
      map['source_device'] = Variable<String>(sourceDevice.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<int>(finishedAt.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('taskId: $taskId, ')
          ..write('imageHash: $imageHash, ')
          ..write('sourceDevice: $sourceDevice, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('errorCode: $errorCode, ')
          ..write('sessionId: $sessionId, ')
          ..write('createdAt: $createdAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('payloadJson: $payloadJson, ')
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

class $AiUsageTable extends AiUsage with TableInfo<$AiUsageTable, AiUsageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiUsageTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _calledAtMeta = const VerificationMeta(
    'calledAt',
  );
  @override
  late final GeneratedColumn<int> calledAt = GeneratedColumn<int>(
    'called_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promptVersionMeta = const VerificationMeta(
    'promptVersion',
  );
  @override
  late final GeneratedColumn<String> promptVersion = GeneratedColumn<String>(
    'prompt_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageHashMeta = const VerificationMeta(
    'imageHash',
  );
  @override
  late final GeneratedColumn<String> imageHash = GeneratedColumn<String>(
    'image_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _okMeta = const VerificationMeta('ok');
  @override
  late final GeneratedColumn<bool> ok = GeneratedColumn<bool>(
    'ok',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("ok" IN (0, 1))',
    ),
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latencyMsMeta = const VerificationMeta(
    'latencyMs',
  );
  @override
  late final GeneratedColumn<int> latencyMs = GeneratedColumn<int>(
    'latency_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    calledAt,
    model,
    promptVersion,
    imageHash,
    ok,
    errorCode,
    latencyMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_usage';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiUsageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('called_at')) {
      context.handle(
        _calledAtMeta,
        calledAt.isAcceptableOrUnknown(data['called_at']!, _calledAtMeta),
      );
    } else if (isInserting) {
      context.missing(_calledAtMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('prompt_version')) {
      context.handle(
        _promptVersionMeta,
        promptVersion.isAcceptableOrUnknown(
          data['prompt_version']!,
          _promptVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_promptVersionMeta);
    }
    if (data.containsKey('image_hash')) {
      context.handle(
        _imageHashMeta,
        imageHash.isAcceptableOrUnknown(data['image_hash']!, _imageHashMeta),
      );
    } else if (isInserting) {
      context.missing(_imageHashMeta);
    }
    if (data.containsKey('ok')) {
      context.handle(_okMeta, ok.isAcceptableOrUnknown(data['ok']!, _okMeta));
    } else if (isInserting) {
      context.missing(_okMeta);
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('latency_ms')) {
      context.handle(
        _latencyMsMeta,
        latencyMs.isAcceptableOrUnknown(data['latency_ms']!, _latencyMsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiUsageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiUsageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      calledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}called_at'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      promptVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_version'],
      )!,
      imageHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_hash'],
      )!,
      ok: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}ok'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      latencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latency_ms'],
      ),
    );
  }

  @override
  $AiUsageTable createAlias(String alias) {
    return $AiUsageTable(attachedDatabase, alias);
  }
}

class AiUsageRow extends DataClass implements Insertable<AiUsageRow> {
  final String id;
  final int calledAt;
  final String model;
  final String promptVersion;
  final String imageHash;
  final bool ok;
  final String? errorCode;
  final int? latencyMs;
  const AiUsageRow({
    required this.id,
    required this.calledAt,
    required this.model,
    required this.promptVersion,
    required this.imageHash,
    required this.ok,
    this.errorCode,
    this.latencyMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['called_at'] = Variable<int>(calledAt);
    map['model'] = Variable<String>(model);
    map['prompt_version'] = Variable<String>(promptVersion);
    map['image_hash'] = Variable<String>(imageHash);
    map['ok'] = Variable<bool>(ok);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || latencyMs != null) {
      map['latency_ms'] = Variable<int>(latencyMs);
    }
    return map;
  }

  AiUsageCompanion toCompanion(bool nullToAbsent) {
    return AiUsageCompanion(
      id: Value(id),
      calledAt: Value(calledAt),
      model: Value(model),
      promptVersion: Value(promptVersion),
      imageHash: Value(imageHash),
      ok: Value(ok),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      latencyMs: latencyMs == null && nullToAbsent
          ? const Value.absent()
          : Value(latencyMs),
    );
  }

  factory AiUsageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiUsageRow(
      id: serializer.fromJson<String>(json['id']),
      calledAt: serializer.fromJson<int>(json['calledAt']),
      model: serializer.fromJson<String>(json['model']),
      promptVersion: serializer.fromJson<String>(json['promptVersion']),
      imageHash: serializer.fromJson<String>(json['imageHash']),
      ok: serializer.fromJson<bool>(json['ok']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      latencyMs: serializer.fromJson<int?>(json['latencyMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'calledAt': serializer.toJson<int>(calledAt),
      'model': serializer.toJson<String>(model),
      'promptVersion': serializer.toJson<String>(promptVersion),
      'imageHash': serializer.toJson<String>(imageHash),
      'ok': serializer.toJson<bool>(ok),
      'errorCode': serializer.toJson<String?>(errorCode),
      'latencyMs': serializer.toJson<int?>(latencyMs),
    };
  }

  AiUsageRow copyWith({
    String? id,
    int? calledAt,
    String? model,
    String? promptVersion,
    String? imageHash,
    bool? ok,
    Value<String?> errorCode = const Value.absent(),
    Value<int?> latencyMs = const Value.absent(),
  }) => AiUsageRow(
    id: id ?? this.id,
    calledAt: calledAt ?? this.calledAt,
    model: model ?? this.model,
    promptVersion: promptVersion ?? this.promptVersion,
    imageHash: imageHash ?? this.imageHash,
    ok: ok ?? this.ok,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    latencyMs: latencyMs.present ? latencyMs.value : this.latencyMs,
  );
  AiUsageRow copyWithCompanion(AiUsageCompanion data) {
    return AiUsageRow(
      id: data.id.present ? data.id.value : this.id,
      calledAt: data.calledAt.present ? data.calledAt.value : this.calledAt,
      model: data.model.present ? data.model.value : this.model,
      promptVersion: data.promptVersion.present
          ? data.promptVersion.value
          : this.promptVersion,
      imageHash: data.imageHash.present ? data.imageHash.value : this.imageHash,
      ok: data.ok.present ? data.ok.value : this.ok,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      latencyMs: data.latencyMs.present ? data.latencyMs.value : this.latencyMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiUsageRow(')
          ..write('id: $id, ')
          ..write('calledAt: $calledAt, ')
          ..write('model: $model, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('imageHash: $imageHash, ')
          ..write('ok: $ok, ')
          ..write('errorCode: $errorCode, ')
          ..write('latencyMs: $latencyMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    calledAt,
    model,
    promptVersion,
    imageHash,
    ok,
    errorCode,
    latencyMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiUsageRow &&
          other.id == this.id &&
          other.calledAt == this.calledAt &&
          other.model == this.model &&
          other.promptVersion == this.promptVersion &&
          other.imageHash == this.imageHash &&
          other.ok == this.ok &&
          other.errorCode == this.errorCode &&
          other.latencyMs == this.latencyMs);
}

class AiUsageCompanion extends UpdateCompanion<AiUsageRow> {
  final Value<String> id;
  final Value<int> calledAt;
  final Value<String> model;
  final Value<String> promptVersion;
  final Value<String> imageHash;
  final Value<bool> ok;
  final Value<String?> errorCode;
  final Value<int?> latencyMs;
  final Value<int> rowid;
  const AiUsageCompanion({
    this.id = const Value.absent(),
    this.calledAt = const Value.absent(),
    this.model = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.imageHash = const Value.absent(),
    this.ok = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiUsageCompanion.insert({
    required String id,
    required int calledAt,
    required String model,
    required String promptVersion,
    required String imageHash,
    required bool ok,
    this.errorCode = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       calledAt = Value(calledAt),
       model = Value(model),
       promptVersion = Value(promptVersion),
       imageHash = Value(imageHash),
       ok = Value(ok);
  static Insertable<AiUsageRow> custom({
    Expression<String>? id,
    Expression<int>? calledAt,
    Expression<String>? model,
    Expression<String>? promptVersion,
    Expression<String>? imageHash,
    Expression<bool>? ok,
    Expression<String>? errorCode,
    Expression<int>? latencyMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (calledAt != null) 'called_at': calledAt,
      if (model != null) 'model': model,
      if (promptVersion != null) 'prompt_version': promptVersion,
      if (imageHash != null) 'image_hash': imageHash,
      if (ok != null) 'ok': ok,
      if (errorCode != null) 'error_code': errorCode,
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiUsageCompanion copyWith({
    Value<String>? id,
    Value<int>? calledAt,
    Value<String>? model,
    Value<String>? promptVersion,
    Value<String>? imageHash,
    Value<bool>? ok,
    Value<String?>? errorCode,
    Value<int?>? latencyMs,
    Value<int>? rowid,
  }) {
    return AiUsageCompanion(
      id: id ?? this.id,
      calledAt: calledAt ?? this.calledAt,
      model: model ?? this.model,
      promptVersion: promptVersion ?? this.promptVersion,
      imageHash: imageHash ?? this.imageHash,
      ok: ok ?? this.ok,
      errorCode: errorCode ?? this.errorCode,
      latencyMs: latencyMs ?? this.latencyMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (calledAt.present) {
      map['called_at'] = Variable<int>(calledAt.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (promptVersion.present) {
      map['prompt_version'] = Variable<String>(promptVersion.value);
    }
    if (imageHash.present) {
      map['image_hash'] = Variable<String>(imageHash.value);
    }
    if (ok.present) {
      map['ok'] = Variable<bool>(ok.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (latencyMs.present) {
      map['latency_ms'] = Variable<int>(latencyMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiUsageCompanion(')
          ..write('id: $id, ')
          ..write('calledAt: $calledAt, ')
          ..write('model: $model, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('imageHash: $imageHash, ')
          ..write('ok: $ok, ')
          ..write('errorCode: $errorCode, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$QuizSyncDb extends GeneratedDatabase {
  _$QuizSyncDb(QueryExecutor e) : super(e);
  $QuizSyncDbManager get managers => $QuizSyncDbManager(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $ImagesTable images = $ImagesTable(this);
  late final $CollectionsTable collections = $CollectionsTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $SessionImagesTable sessionImages = $SessionImagesTable(this);
  late final $QuestionsTable questions = $QuestionsTable(this);
  late final $SyncOpsTable syncOps = $SyncOpsTable(this);
  late final $PeerStatesTable peerStates = $PeerStatesTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $AiUsageTable aiUsage = $AiUsageTable(this);
  late final Index idxImagesCreated = Index(
    'idx_images_created',
    'CREATE INDEX idx_images_created ON images (created_at)',
  );
  late final Index idxCollectionsCreated = Index(
    'idx_collections_created',
    'CREATE INDEX idx_collections_created ON collections (created_at)',
  );
  late final Index idxSessionsCreated = Index(
    'idx_sessions_created',
    'CREATE INDEX idx_sessions_created ON sessions (created_at)',
  );
  late final Index idxSessionsHash = Index(
    'idx_sessions_hash',
    'CREATE INDEX idx_sessions_hash ON sessions (image_hash)',
  );
  late final Index idxSessionsStatus = Index(
    'idx_sessions_status',
    'CREATE INDEX idx_sessions_status ON sessions (status)',
  );
  late final Index idxSessionsCollection = Index(
    'idx_sessions_collection',
    'CREATE INDEX idx_sessions_collection ON sessions (collection_id)',
  );
  late final Index idxSessionImagesSession = Index(
    'idx_session_images_session',
    'CREATE INDEX idx_session_images_session ON session_images (session_id, ordinal)',
  );
  late final Index idxQuestionsSession = Index(
    'idx_questions_session',
    'CREATE INDEX idx_questions_session ON questions (session_id, ordinal)',
  );
  late final Index idxQuestionsStem = Index(
    'idx_questions_stem',
    'CREATE INDEX idx_questions_stem ON questions (stem)',
  );
  late final Index idxOpsLamport = Index(
    'idx_ops_lamport',
    'CREATE INDEX idx_ops_lamport ON sync_ops (device_id, lamport)',
  );
  late final Index idxOpsEntity = Index(
    'idx_ops_entity',
    'CREATE INDEX idx_ops_entity ON sync_ops (entity, entity_id)',
  );
  late final Index idxTasksStatus = Index(
    'idx_tasks_status',
    'CREATE INDEX idx_tasks_status ON tasks (status, created_at)',
  );
  late final Index idxUsageCalled = Index(
    'idx_usage_called',
    'CREATE INDEX idx_usage_called ON ai_usage (called_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    devices,
    images,
    collections,
    sessions,
    sessionImages,
    questions,
    syncOps,
    peerStates,
    tasks,
    settings,
    aiUsage,
    idxImagesCreated,
    idxCollectionsCreated,
    idxSessionsCreated,
    idxSessionsHash,
    idxSessionsStatus,
    idxSessionsCollection,
    idxSessionImagesSession,
    idxQuestionsSession,
    idxQuestionsStem,
    idxOpsLamport,
    idxOpsEntity,
    idxTasksStatus,
    idxUsageCalled,
  ];
}

typedef $$DevicesTableCreateCompanionBuilder = DevicesCompanion Function({
  required String deviceId,
  required String name,
  required String platform,
  Value<String?> tokenHash,
  required int pairedAt,
  Value<int?> lastSeenAt,
  Value<int?> revokedAt,
  Value<String?> appVersion,
  Value<int> rowid,
});
typedef $$DevicesTableUpdateCompanionBuilder = DevicesCompanion Function({
  Value<String> deviceId,
  Value<String> name,
  Value<String> platform,
  Value<String?> tokenHash,
  Value<int> pairedAt,
  Value<int?> lastSeenAt,
  Value<int?> revokedAt,
  Value<String?> appVersion,
  Value<int> rowid,
});

class $$DevicesTableFilterComposer
    extends Composer<_$QuizSyncDb, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revokedAt => $composableBuilder(
    column: $table.revokedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DevicesTableOrderingComposer
    extends Composer<_$QuizSyncDb, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revokedAt => $composableBuilder(
    column: $table.revokedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get tokenHash =>
      $composableBuilder(column: $table.tokenHash, builder: (column) => column);

  GeneratedColumn<int> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);

  GeneratedColumn<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revokedAt =>
      $composableBuilder(column: $table.revokedAt, builder: (column) => column);

  GeneratedColumn<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => column,
  );
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $DevicesTable,
          DeviceRow,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (DeviceRow, BaseReferences<_$QuizSyncDb, $DevicesTable, DeviceRow>),
          DeviceRow,
          PrefetchHooks Function()
        > {
  $$DevicesTableTableManager(_$QuizSyncDb db, $DevicesTable table)
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
                Value<String> deviceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<String?> tokenHash = const Value.absent(),
                Value<int> pairedAt = const Value.absent(),
                Value<int?> lastSeenAt = const Value.absent(),
                Value<int?> revokedAt = const Value.absent(),
                Value<String?> appVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                deviceId: deviceId,
                name: name,
                platform: platform,
                tokenHash: tokenHash,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                revokedAt: revokedAt,
                appVersion: appVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required String name,
                required String platform,
                Value<String?> tokenHash = const Value.absent(),
                required int pairedAt,
                Value<int?> lastSeenAt = const Value.absent(),
                Value<int?> revokedAt = const Value.absent(),
                Value<String?> appVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                deviceId: deviceId,
                name: name,
                platform: platform,
                tokenHash: tokenHash,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                revokedAt: revokedAt,
                appVersion: appVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DevicesTable, DeviceRow>(table),
                  BaseReferences<_$QuizSyncDb, $DevicesTable, DeviceRow>(
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
      _$QuizSyncDb,
      $DevicesTable,
      DeviceRow,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (DeviceRow, BaseReferences<_$QuizSyncDb, $DevicesTable, DeviceRow>),
      DeviceRow,
      PrefetchHooks Function()
    >;
typedef $$ImagesTableCreateCompanionBuilder = ImagesCompanion Function({
  required String hash,
  required int size,
  required String mime,
  Value<int?> width,
  Value<int?> height,
  Value<String?> localPath,
  required int createdAt,
  required String uploadedBy,
  Value<int> rowid,
});
typedef $$ImagesTableUpdateCompanionBuilder = ImagesCompanion Function({
  Value<String> hash,
  Value<int> size,
  Value<String> mime,
  Value<int?> width,
  Value<int?> height,
  Value<String?> localPath,
  Value<int> createdAt,
  Value<String> uploadedBy,
  Value<int> rowid,
});

class $$ImagesTableFilterComposer extends Composer<_$QuizSyncDb, $ImagesTable> {
  $$ImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hash => $composableBuilder(
    column: $table.hash,
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

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploadedBy => $composableBuilder(
    column: $table.uploadedBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImagesTableOrderingComposer
    extends Composer<_$QuizSyncDb, $ImagesTable> {
  $$ImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hash => $composableBuilder(
    column: $table.hash,
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

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadedBy => $composableBuilder(
    column: $table.uploadedBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImagesTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $ImagesTable> {
  $$ImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get uploadedBy => $composableBuilder(
    column: $table.uploadedBy,
    builder: (column) => column,
  );
}

class $$ImagesTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $ImagesTable,
          ImageRow,
          $$ImagesTableFilterComposer,
          $$ImagesTableOrderingComposer,
          $$ImagesTableAnnotationComposer,
          $$ImagesTableCreateCompanionBuilder,
          $$ImagesTableUpdateCompanionBuilder,
          (ImageRow, BaseReferences<_$QuizSyncDb, $ImagesTable, ImageRow>),
          ImageRow,
          PrefetchHooks Function()
        > {
  $$ImagesTableTableManager(_$QuizSyncDb db, $ImagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> hash = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> uploadedBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImagesCompanion(
                hash: hash,
                size: size,
                mime: mime,
                width: width,
                height: height,
                localPath: localPath,
                createdAt: createdAt,
                uploadedBy: uploadedBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String hash,
                required int size,
                required String mime,
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                required int createdAt,
                required String uploadedBy,
                Value<int> rowid = const Value.absent(),
              }) => ImagesCompanion.insert(
                hash: hash,
                size: size,
                mime: mime,
                width: width,
                height: height,
                localPath: localPath,
                createdAt: createdAt,
                uploadedBy: uploadedBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImagesTable, ImageRow>(table),
                  BaseReferences<_$QuizSyncDb, $ImagesTable, ImageRow>(
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

typedef $$ImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$QuizSyncDb,
      $ImagesTable,
      ImageRow,
      $$ImagesTableFilterComposer,
      $$ImagesTableOrderingComposer,
      $$ImagesTableAnnotationComposer,
      $$ImagesTableCreateCompanionBuilder,
      $$ImagesTableUpdateCompanionBuilder,
      (ImageRow, BaseReferences<_$QuizSyncDb, $ImagesTable, ImageRow>),
      ImageRow,
      PrefetchHooks Function()
    >;
typedef $$CollectionsTableCreateCompanionBuilder =
    CollectionsCompanion Function({
      required String collectionId,
      required String name,
      required int createdAt,
      required int updatedAt,
      required String updatedBy,
      Value<int> lamport,
      Value<Map<String, FieldClock>> fieldClocksJson,
      Value<int?> deletedAt,
      Value<int> rowid,
    });
typedef $$CollectionsTableUpdateCompanionBuilder =
    CollectionsCompanion Function({
      Value<String> collectionId,
      Value<String> name,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<String> updatedBy,
      Value<int> lamport,
      Value<Map<String, FieldClock>> fieldClocksJson,
      Value<int?> deletedAt,
      Value<int> rowid,
    });

class $$CollectionsTableFilterComposer
    extends Composer<_$QuizSyncDb, $CollectionsTable> {
  $$CollectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedBy => $composableBuilder(
    column: $table.updatedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, FieldClock>,
    Map<String, FieldClock>,
    String
  >
  get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CollectionsTableOrderingComposer
    extends Composer<_$QuizSyncDb, $CollectionsTable> {
  $$CollectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedBy => $composableBuilder(
    column: $table.updatedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionsTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $CollectionsTable> {
  $$CollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedBy =>
      $composableBuilder(column: $table.updatedBy, builder: (column) => column);

  GeneratedColumn<int> get lamport =>
      $composableBuilder(column: $table.lamport, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, FieldClock>, String>
  get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$CollectionsTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $CollectionsTable,
          CollectionRow,
          $$CollectionsTableFilterComposer,
          $$CollectionsTableOrderingComposer,
          $$CollectionsTableAnnotationComposer,
          $$CollectionsTableCreateCompanionBuilder,
          $$CollectionsTableUpdateCompanionBuilder,
          (
            CollectionRow,
            BaseReferences<_$QuizSyncDb, $CollectionsTable, CollectionRow>,
          ),
          CollectionRow,
          PrefetchHooks Function()
        > {
  $$CollectionsTableTableManager(_$QuizSyncDb db, $CollectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> collectionId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> updatedBy = const Value.absent(),
                Value<int> lamport = const Value.absent(),
                Value<Map<String, FieldClock>> fieldClocksJson =
                    const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion(
                collectionId: collectionId,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedBy: updatedBy,
                lamport: lamport,
                fieldClocksJson: fieldClocksJson,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String collectionId,
                required String name,
                required int createdAt,
                required int updatedAt,
                required String updatedBy,
                Value<int> lamport = const Value.absent(),
                Value<Map<String, FieldClock>> fieldClocksJson =
                    const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion.insert(
                collectionId: collectionId,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedBy: updatedBy,
                lamport: lamport,
                fieldClocksJson: fieldClocksJson,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CollectionsTable, CollectionRow>(table),
                  BaseReferences<
                    _$QuizSyncDb,
                    $CollectionsTable,
                    CollectionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CollectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$QuizSyncDb,
      $CollectionsTable,
      CollectionRow,
      $$CollectionsTableFilterComposer,
      $$CollectionsTableOrderingComposer,
      $$CollectionsTableAnnotationComposer,
      $$CollectionsTableCreateCompanionBuilder,
      $$CollectionsTableUpdateCompanionBuilder,
      (
        CollectionRow,
        BaseReferences<_$QuizSyncDb, $CollectionsTable, CollectionRow>,
      ),
      CollectionRow,
      PrefetchHooks Function()
    >;
typedef $$SessionsTableCreateCompanionBuilder = SessionsCompanion Function({
  required String sessionId,
  Value<String?> taskId,
  Value<String?> collectionId,
  required String imageHash,
  required String sourceDevice,
  required String status,
  Value<String?> errorCode,
  Value<String?> errorMessage,
  Value<String?> aiProvider,
  Value<String?> aiModel,
  Value<String?> promptVersion,
  Value<String?> rawResponse,
  Value<bool> cached,
  Value<int> questionCount,
  Value<int?> latencyMs,
  required int createdAt,
  required int updatedAt,
  required String updatedBy,
  Value<int> lamport,
  Value<Map<String, FieldClock>> fieldClocksJson,
  Value<int?> deletedAt,
  Value<int> rowid,
});
typedef $$SessionsTableUpdateCompanionBuilder = SessionsCompanion Function({
  Value<String> sessionId,
  Value<String?> taskId,
  Value<String?> collectionId,
  Value<String> imageHash,
  Value<String> sourceDevice,
  Value<String> status,
  Value<String?> errorCode,
  Value<String?> errorMessage,
  Value<String?> aiProvider,
  Value<String?> aiModel,
  Value<String?> promptVersion,
  Value<String?> rawResponse,
  Value<bool> cached,
  Value<int> questionCount,
  Value<int?> latencyMs,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<String> updatedBy,
  Value<int> lamport,
  Value<Map<String, FieldClock>> fieldClocksJson,
  Value<int?> deletedAt,
  Value<int> rowid,
});

class $$SessionsTableFilterComposer
    extends Composer<_$QuizSyncDb, $SessionsTable> {
  $$SessionsTableFilterComposer({
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

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageHash => $composableBuilder(
    column: $table.imageHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceDevice => $composableBuilder(
    column: $table.sourceDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiModel => $composableBuilder(
    column: $table.aiModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawResponse => $composableBuilder(
    column: $table.rawResponse,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get cached => $composableBuilder(
    column: $table.cached,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get questionCount => $composableBuilder(
    column: $table.questionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedBy => $composableBuilder(
    column: $table.updatedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, FieldClock>,
    Map<String, FieldClock>,
    String
  >
  get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionsTableOrderingComposer
    extends Composer<_$QuizSyncDb, $SessionsTable> {
  $$SessionsTableOrderingComposer({
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

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageHash => $composableBuilder(
    column: $table.imageHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceDevice => $composableBuilder(
    column: $table.sourceDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiModel => $composableBuilder(
    column: $table.aiModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawResponse => $composableBuilder(
    column: $table.rawResponse,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cached => $composableBuilder(
    column: $table.cached,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get questionCount => $composableBuilder(
    column: $table.questionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedBy => $composableBuilder(
    column: $table.updatedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageHash =>
      $composableBuilder(column: $table.imageHash, builder: (column) => column);

  GeneratedColumn<String> get sourceDevice => $composableBuilder(
    column: $table.sourceDevice,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiModel =>
      $composableBuilder(column: $table.aiModel, builder: (column) => column);

  GeneratedColumn<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawResponse => $composableBuilder(
    column: $table.rawResponse,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get cached =>
      $composableBuilder(column: $table.cached, builder: (column) => column);

  GeneratedColumn<int> get questionCount => $composableBuilder(
    column: $table.questionCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get latencyMs =>
      $composableBuilder(column: $table.latencyMs, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedBy =>
      $composableBuilder(column: $table.updatedBy, builder: (column) => column);

  GeneratedColumn<int> get lamport =>
      $composableBuilder(column: $table.lamport, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, FieldClock>, String>
  get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $SessionsTable,
          SessionRow,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (
            SessionRow,
            BaseReferences<_$QuizSyncDb, $SessionsTable, SessionRow>,
          ),
          SessionRow,
          PrefetchHooks Function()
        > {
  $$SessionsTableTableManager(_$QuizSyncDb db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String?> taskId = const Value.absent(),
                Value<String?> collectionId = const Value.absent(),
                Value<String> imageHash = const Value.absent(),
                Value<String> sourceDevice = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> aiProvider = const Value.absent(),
                Value<String?> aiModel = const Value.absent(),
                Value<String?> promptVersion = const Value.absent(),
                Value<String?> rawResponse = const Value.absent(),
                Value<bool> cached = const Value.absent(),
                Value<int> questionCount = const Value.absent(),
                Value<int?> latencyMs = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> updatedBy = const Value.absent(),
                Value<int> lamport = const Value.absent(),
                Value<Map<String, FieldClock>> fieldClocksJson =
                    const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                sessionId: sessionId,
                taskId: taskId,
                collectionId: collectionId,
                imageHash: imageHash,
                sourceDevice: sourceDevice,
                status: status,
                errorCode: errorCode,
                errorMessage: errorMessage,
                aiProvider: aiProvider,
                aiModel: aiModel,
                promptVersion: promptVersion,
                rawResponse: rawResponse,
                cached: cached,
                questionCount: questionCount,
                latencyMs: latencyMs,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedBy: updatedBy,
                lamport: lamport,
                fieldClocksJson: fieldClocksJson,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                Value<String?> taskId = const Value.absent(),
                Value<String?> collectionId = const Value.absent(),
                required String imageHash,
                required String sourceDevice,
                required String status,
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> aiProvider = const Value.absent(),
                Value<String?> aiModel = const Value.absent(),
                Value<String?> promptVersion = const Value.absent(),
                Value<String?> rawResponse = const Value.absent(),
                Value<bool> cached = const Value.absent(),
                Value<int> questionCount = const Value.absent(),
                Value<int?> latencyMs = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                required String updatedBy,
                Value<int> lamport = const Value.absent(),
                Value<Map<String, FieldClock>> fieldClocksJson =
                    const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                sessionId: sessionId,
                taskId: taskId,
                collectionId: collectionId,
                imageHash: imageHash,
                sourceDevice: sourceDevice,
                status: status,
                errorCode: errorCode,
                errorMessage: errorMessage,
                aiProvider: aiProvider,
                aiModel: aiModel,
                promptVersion: promptVersion,
                rawResponse: rawResponse,
                cached: cached,
                questionCount: questionCount,
                latencyMs: latencyMs,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedBy: updatedBy,
                lamport: lamport,
                fieldClocksJson: fieldClocksJson,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionsTable, SessionRow>(table),
                  BaseReferences<_$QuizSyncDb, $SessionsTable, SessionRow>(
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

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$QuizSyncDb,
      $SessionsTable,
      SessionRow,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (SessionRow, BaseReferences<_$QuizSyncDb, $SessionsTable, SessionRow>),
      SessionRow,
      PrefetchHooks Function()
    >;
typedef $$SessionImagesTableCreateCompanionBuilder =
    SessionImagesCompanion Function({
      required String sessionImageId,
      required String sessionId,
      required int ordinal,
      required String imageHash,
      required int createdAt,
      required int updatedAt,
      required String updatedBy,
      Value<int> lamport,
      Value<Map<String, FieldClock>> fieldClocksJson,
      Value<int?> deletedAt,
      Value<int> rowid,
    });
typedef $$SessionImagesTableUpdateCompanionBuilder =
    SessionImagesCompanion Function({
      Value<String> sessionImageId,
      Value<String> sessionId,
      Value<int> ordinal,
      Value<String> imageHash,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<String> updatedBy,
      Value<int> lamport,
      Value<Map<String, FieldClock>> fieldClocksJson,
      Value<int?> deletedAt,
      Value<int> rowid,
    });

class $$SessionImagesTableFilterComposer
    extends Composer<_$QuizSyncDb, $SessionImagesTable> {
  $$SessionImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionImageId => $composableBuilder(
    column: $table.sessionImageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageHash => $composableBuilder(
    column: $table.imageHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedBy => $composableBuilder(
    column: $table.updatedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, FieldClock>,
    Map<String, FieldClock>,
    String
  >
  get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionImagesTableOrderingComposer
    extends Composer<_$QuizSyncDb, $SessionImagesTable> {
  $$SessionImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionImageId => $composableBuilder(
    column: $table.sessionImageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageHash => $composableBuilder(
    column: $table.imageHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedBy => $composableBuilder(
    column: $table.updatedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionImagesTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $SessionImagesTable> {
  $$SessionImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionImageId => $composableBuilder(
    column: $table.sessionImageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get imageHash =>
      $composableBuilder(column: $table.imageHash, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedBy =>
      $composableBuilder(column: $table.updatedBy, builder: (column) => column);

  GeneratedColumn<int> get lamport =>
      $composableBuilder(column: $table.lamport, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, FieldClock>, String>
  get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$SessionImagesTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $SessionImagesTable,
          SessionImageRow,
          $$SessionImagesTableFilterComposer,
          $$SessionImagesTableOrderingComposer,
          $$SessionImagesTableAnnotationComposer,
          $$SessionImagesTableCreateCompanionBuilder,
          $$SessionImagesTableUpdateCompanionBuilder,
          (
            SessionImageRow,
            BaseReferences<_$QuizSyncDb, $SessionImagesTable, SessionImageRow>,
          ),
          SessionImageRow,
          PrefetchHooks Function()
        > {
  $$SessionImagesTableTableManager(_$QuizSyncDb db, $SessionImagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionImageId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> imageHash = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> updatedBy = const Value.absent(),
                Value<int> lamport = const Value.absent(),
                Value<Map<String, FieldClock>> fieldClocksJson =
                    const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionImagesCompanion(
                sessionImageId: sessionImageId,
                sessionId: sessionId,
                ordinal: ordinal,
                imageHash: imageHash,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedBy: updatedBy,
                lamport: lamport,
                fieldClocksJson: fieldClocksJson,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionImageId,
                required String sessionId,
                required int ordinal,
                required String imageHash,
                required int createdAt,
                required int updatedAt,
                required String updatedBy,
                Value<int> lamport = const Value.absent(),
                Value<Map<String, FieldClock>> fieldClocksJson =
                    const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionImagesCompanion.insert(
                sessionImageId: sessionImageId,
                sessionId: sessionId,
                ordinal: ordinal,
                imageHash: imageHash,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedBy: updatedBy,
                lamport: lamport,
                fieldClocksJson: fieldClocksJson,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionImagesTable, SessionImageRow>(table),
                  BaseReferences<
                    _$QuizSyncDb,
                    $SessionImagesTable,
                    SessionImageRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$QuizSyncDb,
      $SessionImagesTable,
      SessionImageRow,
      $$SessionImagesTableFilterComposer,
      $$SessionImagesTableOrderingComposer,
      $$SessionImagesTableAnnotationComposer,
      $$SessionImagesTableCreateCompanionBuilder,
      $$SessionImagesTableUpdateCompanionBuilder,
      (
        SessionImageRow,
        BaseReferences<_$QuizSyncDb, $SessionImagesTable, SessionImageRow>,
      ),
      SessionImageRow,
      PrefetchHooks Function()
    >;
typedef $$QuestionsTableCreateCompanionBuilder = QuestionsCompanion Function({
  required String questionId,
  required String sessionId,
  required int ordinal,
  Value<String?> questionNo,
  required String stem,
  Value<String> material,
  required String type,
  Value<List<Option>> optionsJson,
  Value<List<String>> choiceJson,
  Value<String?> answerText,
  Value<String> analysis,
  Value<double> confidence,
  Value<bool> needReview,
  Value<bool> answerInImage,
  Value<bool> incomplete,
  Value<bool> answerGuessed,
  Value<List<String>> warningsJson,
  Value<bool> analysisEdited,
  Value<bool> answerEdited,
  Value<Map<String, FieldClock>> fieldClocksJson,
  required int createdAt,
  required int updatedAt,
  required String updatedBy,
  Value<int> lamport,
  Value<int?> deletedAt,
  Value<int> rowid,
});
typedef $$QuestionsTableUpdateCompanionBuilder = QuestionsCompanion Function({
  Value<String> questionId,
  Value<String> sessionId,
  Value<int> ordinal,
  Value<String?> questionNo,
  Value<String> stem,
  Value<String> material,
  Value<String> type,
  Value<List<Option>> optionsJson,
  Value<List<String>> choiceJson,
  Value<String?> answerText,
  Value<String> analysis,
  Value<double> confidence,
  Value<bool> needReview,
  Value<bool> answerInImage,
  Value<bool> incomplete,
  Value<bool> answerGuessed,
  Value<List<String>> warningsJson,
  Value<bool> analysisEdited,
  Value<bool> answerEdited,
  Value<Map<String, FieldClock>> fieldClocksJson,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<String> updatedBy,
  Value<int> lamport,
  Value<int?> deletedAt,
  Value<int> rowid,
});

class $$QuestionsTableFilterComposer
    extends Composer<_$QuizSyncDb, $QuestionsTable> {
  $$QuestionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionNo => $composableBuilder(
    column: $table.questionNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stem => $composableBuilder(
    column: $table.stem,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get material => $composableBuilder(
    column: $table.material,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<Option>, List<Option>, String>
  get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get choiceJson => $composableBuilder(
    column: $table.choiceJson,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get answerText => $composableBuilder(
    column: $table.answerText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get analysis => $composableBuilder(
    column: $table.analysis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needReview => $composableBuilder(
    column: $table.needReview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get answerInImage => $composableBuilder(
    column: $table.answerInImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get incomplete => $composableBuilder(
    column: $table.incomplete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get answerGuessed => $composableBuilder(
    column: $table.answerGuessed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get warningsJson => $composableBuilder(
    column: $table.warningsJson,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get analysisEdited => $composableBuilder(
    column: $table.analysisEdited,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get answerEdited => $composableBuilder(
    column: $table.answerEdited,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, FieldClock>,
    Map<String, FieldClock>,
    String
  >
  get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedBy => $composableBuilder(
    column: $table.updatedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QuestionsTableOrderingComposer
    extends Composer<_$QuizSyncDb, $QuestionsTable> {
  $$QuestionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionNo => $composableBuilder(
    column: $table.questionNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stem => $composableBuilder(
    column: $table.stem,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get material => $composableBuilder(
    column: $table.material,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get choiceJson => $composableBuilder(
    column: $table.choiceJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get answerText => $composableBuilder(
    column: $table.answerText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get analysis => $composableBuilder(
    column: $table.analysis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needReview => $composableBuilder(
    column: $table.needReview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get answerInImage => $composableBuilder(
    column: $table.answerInImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get incomplete => $composableBuilder(
    column: $table.incomplete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get answerGuessed => $composableBuilder(
    column: $table.answerGuessed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get warningsJson => $composableBuilder(
    column: $table.warningsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get analysisEdited => $composableBuilder(
    column: $table.analysisEdited,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get answerEdited => $composableBuilder(
    column: $table.answerEdited,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedBy => $composableBuilder(
    column: $table.updatedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QuestionsTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $QuestionsTable> {
  $$QuestionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get questionNo => $composableBuilder(
    column: $table.questionNo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stem =>
      $composableBuilder(column: $table.stem, builder: (column) => column);

  GeneratedColumn<String> get material =>
      $composableBuilder(column: $table.material, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<Option>, String> get optionsJson =>
      $composableBuilder(
        column: $table.optionsJson,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<List<String>, String> get choiceJson =>
      $composableBuilder(
        column: $table.choiceJson,
        builder: (column) => column,
      );

  GeneratedColumn<String> get answerText => $composableBuilder(
    column: $table.answerText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get analysis =>
      $composableBuilder(column: $table.analysis, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get needReview => $composableBuilder(
    column: $table.needReview,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get answerInImage => $composableBuilder(
    column: $table.answerInImage,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get incomplete => $composableBuilder(
    column: $table.incomplete,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get answerGuessed => $composableBuilder(
    column: $table.answerGuessed,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get warningsJson =>
      $composableBuilder(
        column: $table.warningsJson,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get analysisEdited => $composableBuilder(
    column: $table.analysisEdited,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get answerEdited => $composableBuilder(
    column: $table.answerEdited,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Map<String, FieldClock>, String>
  get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedBy =>
      $composableBuilder(column: $table.updatedBy, builder: (column) => column);

  GeneratedColumn<int> get lamport =>
      $composableBuilder(column: $table.lamport, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$QuestionsTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $QuestionsTable,
          QuestionRow,
          $$QuestionsTableFilterComposer,
          $$QuestionsTableOrderingComposer,
          $$QuestionsTableAnnotationComposer,
          $$QuestionsTableCreateCompanionBuilder,
          $$QuestionsTableUpdateCompanionBuilder,
          (
            QuestionRow,
            BaseReferences<_$QuizSyncDb, $QuestionsTable, QuestionRow>,
          ),
          QuestionRow,
          PrefetchHooks Function()
        > {
  $$QuestionsTableTableManager(_$QuizSyncDb db, $QuestionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QuestionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QuestionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QuestionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> questionId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String?> questionNo = const Value.absent(),
                Value<String> stem = const Value.absent(),
                Value<String> material = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<List<Option>> optionsJson = const Value.absent(),
                Value<List<String>> choiceJson = const Value.absent(),
                Value<String?> answerText = const Value.absent(),
                Value<String> analysis = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<bool> needReview = const Value.absent(),
                Value<bool> answerInImage = const Value.absent(),
                Value<bool> incomplete = const Value.absent(),
                Value<bool> answerGuessed = const Value.absent(),
                Value<List<String>> warningsJson = const Value.absent(),
                Value<bool> analysisEdited = const Value.absent(),
                Value<bool> answerEdited = const Value.absent(),
                Value<Map<String, FieldClock>> fieldClocksJson =
                    const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> updatedBy = const Value.absent(),
                Value<int> lamport = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QuestionsCompanion(
                questionId: questionId,
                sessionId: sessionId,
                ordinal: ordinal,
                questionNo: questionNo,
                stem: stem,
                material: material,
                type: type,
                optionsJson: optionsJson,
                choiceJson: choiceJson,
                answerText: answerText,
                analysis: analysis,
                confidence: confidence,
                needReview: needReview,
                answerInImage: answerInImage,
                incomplete: incomplete,
                answerGuessed: answerGuessed,
                warningsJson: warningsJson,
                analysisEdited: analysisEdited,
                answerEdited: answerEdited,
                fieldClocksJson: fieldClocksJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedBy: updatedBy,
                lamport: lamport,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String questionId,
                required String sessionId,
                required int ordinal,
                Value<String?> questionNo = const Value.absent(),
                required String stem,
                Value<String> material = const Value.absent(),
                required String type,
                Value<List<Option>> optionsJson = const Value.absent(),
                Value<List<String>> choiceJson = const Value.absent(),
                Value<String?> answerText = const Value.absent(),
                Value<String> analysis = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<bool> needReview = const Value.absent(),
                Value<bool> answerInImage = const Value.absent(),
                Value<bool> incomplete = const Value.absent(),
                Value<bool> answerGuessed = const Value.absent(),
                Value<List<String>> warningsJson = const Value.absent(),
                Value<bool> analysisEdited = const Value.absent(),
                Value<bool> answerEdited = const Value.absent(),
                Value<Map<String, FieldClock>> fieldClocksJson =
                    const Value.absent(),
                required int createdAt,
                required int updatedAt,
                required String updatedBy,
                Value<int> lamport = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QuestionsCompanion.insert(
                questionId: questionId,
                sessionId: sessionId,
                ordinal: ordinal,
                questionNo: questionNo,
                stem: stem,
                material: material,
                type: type,
                optionsJson: optionsJson,
                choiceJson: choiceJson,
                answerText: answerText,
                analysis: analysis,
                confidence: confidence,
                needReview: needReview,
                answerInImage: answerInImage,
                incomplete: incomplete,
                answerGuessed: answerGuessed,
                warningsJson: warningsJson,
                analysisEdited: analysisEdited,
                answerEdited: answerEdited,
                fieldClocksJson: fieldClocksJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedBy: updatedBy,
                lamport: lamport,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QuestionsTable, QuestionRow>(table),
                  BaseReferences<_$QuizSyncDb, $QuestionsTable, QuestionRow>(
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

typedef $$QuestionsTableProcessedTableManager =
    ProcessedTableManager<
      _$QuizSyncDb,
      $QuestionsTable,
      QuestionRow,
      $$QuestionsTableFilterComposer,
      $$QuestionsTableOrderingComposer,
      $$QuestionsTableAnnotationComposer,
      $$QuestionsTableCreateCompanionBuilder,
      $$QuestionsTableUpdateCompanionBuilder,
      (QuestionRow, BaseReferences<_$QuizSyncDb, $QuestionsTable, QuestionRow>),
      QuestionRow,
      PrefetchHooks Function()
    >;
typedef $$SyncOpsTableCreateCompanionBuilder = SyncOpsCompanion Function({
  required String opId,
  required String deviceId,
  required int lamport,
  required String entity,
  required String entityId,
  required String opType,
  required String fieldsJson,
  required int createdAt,
  Value<int> rowid,
});
typedef $$SyncOpsTableUpdateCompanionBuilder = SyncOpsCompanion Function({
  Value<String> opId,
  Value<String> deviceId,
  Value<int> lamport,
  Value<String> entity,
  Value<String> entityId,
  Value<String> opType,
  Value<String> fieldsJson,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$SyncOpsTableFilterComposer
    extends Composer<_$QuizSyncDb, $SyncOpsTable> {
  $$SyncOpsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get opType => $composableBuilder(
    column: $table.opType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldsJson => $composableBuilder(
    column: $table.fieldsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOpsTableOrderingComposer
    extends Composer<_$QuizSyncDb, $SyncOpsTable> {
  $$SyncOpsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get opType => $composableBuilder(
    column: $table.opType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldsJson => $composableBuilder(
    column: $table.fieldsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOpsTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $SyncOpsTable> {
  $$SyncOpsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get opId =>
      $composableBuilder(column: $table.opId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get lamport =>
      $composableBuilder(column: $table.lamport, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get opType =>
      $composableBuilder(column: $table.opType, builder: (column) => column);

  GeneratedColumn<String> get fieldsJson => $composableBuilder(
    column: $table.fieldsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncOpsTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $SyncOpsTable,
          SyncOpRow,
          $$SyncOpsTableFilterComposer,
          $$SyncOpsTableOrderingComposer,
          $$SyncOpsTableAnnotationComposer,
          $$SyncOpsTableCreateCompanionBuilder,
          $$SyncOpsTableUpdateCompanionBuilder,
          (SyncOpRow, BaseReferences<_$QuizSyncDb, $SyncOpsTable, SyncOpRow>),
          SyncOpRow,
          PrefetchHooks Function()
        > {
  $$SyncOpsTableTableManager(_$QuizSyncDb db, $SyncOpsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOpsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOpsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOpsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> opId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> lamport = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> opType = const Value.absent(),
                Value<String> fieldsJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOpsCompanion(
                opId: opId,
                deviceId: deviceId,
                lamport: lamport,
                entity: entity,
                entityId: entityId,
                opType: opType,
                fieldsJson: fieldsJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String opId,
                required String deviceId,
                required int lamport,
                required String entity,
                required String entityId,
                required String opType,
                required String fieldsJson,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncOpsCompanion.insert(
                opId: opId,
                deviceId: deviceId,
                lamport: lamport,
                entity: entity,
                entityId: entityId,
                opType: opType,
                fieldsJson: fieldsJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncOpsTable, SyncOpRow>(table),
                  BaseReferences<_$QuizSyncDb, $SyncOpsTable, SyncOpRow>(
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

typedef $$SyncOpsTableProcessedTableManager =
    ProcessedTableManager<
      _$QuizSyncDb,
      $SyncOpsTable,
      SyncOpRow,
      $$SyncOpsTableFilterComposer,
      $$SyncOpsTableOrderingComposer,
      $$SyncOpsTableAnnotationComposer,
      $$SyncOpsTableCreateCompanionBuilder,
      $$SyncOpsTableUpdateCompanionBuilder,
      (SyncOpRow, BaseReferences<_$QuizSyncDb, $SyncOpsTable, SyncOpRow>),
      SyncOpRow,
      PrefetchHooks Function()
    >;
typedef $$PeerStatesTableCreateCompanionBuilder = PeerStatesCompanion Function({
  required String peerDeviceId,
  Value<int> sentLamport,
  Value<int> ackedLamport,
  Value<int?> lastSyncAt,
  Value<int> rowid,
});
typedef $$PeerStatesTableUpdateCompanionBuilder = PeerStatesCompanion Function({
  Value<String> peerDeviceId,
  Value<int> sentLamport,
  Value<int> ackedLamport,
  Value<int?> lastSyncAt,
  Value<int> rowid,
});

class $$PeerStatesTableFilterComposer
    extends Composer<_$QuizSyncDb, $PeerStatesTable> {
  $$PeerStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sentLamport => $composableBuilder(
    column: $table.sentLamport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ackedLamport => $composableBuilder(
    column: $table.ackedLamport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PeerStatesTableOrderingComposer
    extends Composer<_$QuizSyncDb, $PeerStatesTable> {
  $$PeerStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sentLamport => $composableBuilder(
    column: $table.sentLamport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ackedLamport => $composableBuilder(
    column: $table.ackedLamport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeerStatesTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $PeerStatesTable> {
  $$PeerStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sentLamport => $composableBuilder(
    column: $table.sentLamport,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ackedLamport => $composableBuilder(
    column: $table.ackedLamport,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );
}

class $$PeerStatesTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $PeerStatesTable,
          PeerStateRow,
          $$PeerStatesTableFilterComposer,
          $$PeerStatesTableOrderingComposer,
          $$PeerStatesTableAnnotationComposer,
          $$PeerStatesTableCreateCompanionBuilder,
          $$PeerStatesTableUpdateCompanionBuilder,
          (
            PeerStateRow,
            BaseReferences<_$QuizSyncDb, $PeerStatesTable, PeerStateRow>,
          ),
          PeerStateRow,
          PrefetchHooks Function()
        > {
  $$PeerStatesTableTableManager(_$QuizSyncDb db, $PeerStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeerStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeerStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeerStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> peerDeviceId = const Value.absent(),
                Value<int> sentLamport = const Value.absent(),
                Value<int> ackedLamport = const Value.absent(),
                Value<int?> lastSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeerStatesCompanion(
                peerDeviceId: peerDeviceId,
                sentLamport: sentLamport,
                ackedLamport: ackedLamport,
                lastSyncAt: lastSyncAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerDeviceId,
                Value<int> sentLamport = const Value.absent(),
                Value<int> ackedLamport = const Value.absent(),
                Value<int?> lastSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeerStatesCompanion.insert(
                peerDeviceId: peerDeviceId,
                sentLamport: sentLamport,
                ackedLamport: ackedLamport,
                lastSyncAt: lastSyncAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PeerStatesTable, PeerStateRow>(table),
                  BaseReferences<_$QuizSyncDb, $PeerStatesTable, PeerStateRow>(
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

typedef $$PeerStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$QuizSyncDb,
      $PeerStatesTable,
      PeerStateRow,
      $$PeerStatesTableFilterComposer,
      $$PeerStatesTableOrderingComposer,
      $$PeerStatesTableAnnotationComposer,
      $$PeerStatesTableCreateCompanionBuilder,
      $$PeerStatesTableUpdateCompanionBuilder,
      (
        PeerStateRow,
        BaseReferences<_$QuizSyncDb, $PeerStatesTable, PeerStateRow>,
      ),
      PeerStateRow,
      PrefetchHooks Function()
    >;
typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String taskId,
  required String imageHash,
  required String sourceDevice,
  required String status,
  Value<int> attempts,
  Value<String?> errorCode,
  Value<String?> sessionId,
  required int createdAt,
  Value<int?> startedAt,
  Value<int?> finishedAt,
  Value<String?> payloadJson,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> taskId,
  Value<String> imageHash,
  Value<String> sourceDevice,
  Value<String> status,
  Value<int> attempts,
  Value<String?> errorCode,
  Value<String?> sessionId,
  Value<int> createdAt,
  Value<int?> startedAt,
  Value<int?> finishedAt,
  Value<String?> payloadJson,
  Value<int> rowid,
});

class $$TasksTableFilterComposer extends Composer<_$QuizSyncDb, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageHash => $composableBuilder(
    column: $table.imageHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceDevice => $composableBuilder(
    column: $table.sourceDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TasksTableOrderingComposer extends Composer<_$QuizSyncDb, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageHash => $composableBuilder(
    column: $table.imageHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceDevice => $composableBuilder(
    column: $table.sourceDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get imageHash =>
      $composableBuilder(column: $table.imageHash, builder: (column) => column);

  GeneratedColumn<String> get sourceDevice => $composableBuilder(
    column: $table.sourceDevice,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $TasksTable,
          TaskRow,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (TaskRow, BaseReferences<_$QuizSyncDb, $TasksTable, TaskRow>),
          TaskRow,
          PrefetchHooks Function()
        > {
  $$TasksTableTableManager(_$QuizSyncDb db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> imageHash = const Value.absent(),
                Value<String> sourceDevice = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> startedAt = const Value.absent(),
                Value<int?> finishedAt = const Value.absent(),
                Value<String?> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                taskId: taskId,
                imageHash: imageHash,
                sourceDevice: sourceDevice,
                status: status,
                attempts: attempts,
                errorCode: errorCode,
                sessionId: sessionId,
                createdAt: createdAt,
                startedAt: startedAt,
                finishedAt: finishedAt,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String imageHash,
                required String sourceDevice,
                required String status,
                Value<int> attempts = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                required int createdAt,
                Value<int?> startedAt = const Value.absent(),
                Value<int?> finishedAt = const Value.absent(),
                Value<String?> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                taskId: taskId,
                imageHash: imageHash,
                sourceDevice: sourceDevice,
                status: status,
                attempts: attempts,
                errorCode: errorCode,
                sessionId: sessionId,
                createdAt: createdAt,
                startedAt: startedAt,
                finishedAt: finishedAt,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TasksTable, TaskRow>(table),
                  BaseReferences<_$QuizSyncDb, $TasksTable, TaskRow>(
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

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$QuizSyncDb,
      $TasksTable,
      TaskRow,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (TaskRow, BaseReferences<_$QuizSyncDb, $TasksTable, TaskRow>),
      TaskRow,
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
    extends Composer<_$QuizSyncDb, $SettingsTable> {
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
    extends Composer<_$QuizSyncDb, $SettingsTable> {
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
    extends Composer<_$QuizSyncDb, $SettingsTable> {
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
          _$QuizSyncDb,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$QuizSyncDb, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$QuizSyncDb db, $SettingsTable table)
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
                  BaseReferences<_$QuizSyncDb, $SettingsTable, SettingRow>(
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
      _$QuizSyncDb,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$QuizSyncDb, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$AiUsageTableCreateCompanionBuilder = AiUsageCompanion Function({
  required String id,
  required int calledAt,
  required String model,
  required String promptVersion,
  required String imageHash,
  required bool ok,
  Value<String?> errorCode,
  Value<int?> latencyMs,
  Value<int> rowid,
});
typedef $$AiUsageTableUpdateCompanionBuilder = AiUsageCompanion Function({
  Value<String> id,
  Value<int> calledAt,
  Value<String> model,
  Value<String> promptVersion,
  Value<String> imageHash,
  Value<bool> ok,
  Value<String?> errorCode,
  Value<int?> latencyMs,
  Value<int> rowid,
});

class $$AiUsageTableFilterComposer
    extends Composer<_$QuizSyncDb, $AiUsageTable> {
  $$AiUsageTableFilterComposer({
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

  ColumnFilters<int> get calledAt => $composableBuilder(
    column: $table.calledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageHash => $composableBuilder(
    column: $table.imageHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get ok => $composableBuilder(
    column: $table.ok,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiUsageTableOrderingComposer
    extends Composer<_$QuizSyncDb, $AiUsageTable> {
  $$AiUsageTableOrderingComposer({
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

  ColumnOrderings<int> get calledAt => $composableBuilder(
    column: $table.calledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageHash => $composableBuilder(
    column: $table.imageHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get ok => $composableBuilder(
    column: $table.ok,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiUsageTableAnnotationComposer
    extends Composer<_$QuizSyncDb, $AiUsageTable> {
  $$AiUsageTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get calledAt =>
      $composableBuilder(column: $table.calledAt, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageHash =>
      $composableBuilder(column: $table.imageHash, builder: (column) => column);

  GeneratedColumn<bool> get ok =>
      $composableBuilder(column: $table.ok, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<int> get latencyMs =>
      $composableBuilder(column: $table.latencyMs, builder: (column) => column);
}

class $$AiUsageTableTableManager
    extends
        RootTableManager<
          _$QuizSyncDb,
          $AiUsageTable,
          AiUsageRow,
          $$AiUsageTableFilterComposer,
          $$AiUsageTableOrderingComposer,
          $$AiUsageTableAnnotationComposer,
          $$AiUsageTableCreateCompanionBuilder,
          $$AiUsageTableUpdateCompanionBuilder,
          (AiUsageRow, BaseReferences<_$QuizSyncDb, $AiUsageTable, AiUsageRow>),
          AiUsageRow,
          PrefetchHooks Function()
        > {
  $$AiUsageTableTableManager(_$QuizSyncDb db, $AiUsageTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiUsageTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiUsageTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiUsageTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> calledAt = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String> promptVersion = const Value.absent(),
                Value<String> imageHash = const Value.absent(),
                Value<bool> ok = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int?> latencyMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiUsageCompanion(
                id: id,
                calledAt: calledAt,
                model: model,
                promptVersion: promptVersion,
                imageHash: imageHash,
                ok: ok,
                errorCode: errorCode,
                latencyMs: latencyMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int calledAt,
                required String model,
                required String promptVersion,
                required String imageHash,
                required bool ok,
                Value<String?> errorCode = const Value.absent(),
                Value<int?> latencyMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiUsageCompanion.insert(
                id: id,
                calledAt: calledAt,
                model: model,
                promptVersion: promptVersion,
                imageHash: imageHash,
                ok: ok,
                errorCode: errorCode,
                latencyMs: latencyMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiUsageTable, AiUsageRow>(table),
                  BaseReferences<_$QuizSyncDb, $AiUsageTable, AiUsageRow>(
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

typedef $$AiUsageTableProcessedTableManager =
    ProcessedTableManager<
      _$QuizSyncDb,
      $AiUsageTable,
      AiUsageRow,
      $$AiUsageTableFilterComposer,
      $$AiUsageTableOrderingComposer,
      $$AiUsageTableAnnotationComposer,
      $$AiUsageTableCreateCompanionBuilder,
      $$AiUsageTableUpdateCompanionBuilder,
      (AiUsageRow, BaseReferences<_$QuizSyncDb, $AiUsageTable, AiUsageRow>),
      AiUsageRow,
      PrefetchHooks Function()
    >;

class $QuizSyncDbManager {
  final _$QuizSyncDb _db;
  $QuizSyncDbManager(this._db);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$ImagesTableTableManager get images =>
      $$ImagesTableTableManager(_db, _db.images);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db, _db.collections);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$SessionImagesTableTableManager get sessionImages =>
      $$SessionImagesTableTableManager(_db, _db.sessionImages);
  $$QuestionsTableTableManager get questions =>
      $$QuestionsTableTableManager(_db, _db.questions);
  $$SyncOpsTableTableManager get syncOps =>
      $$SyncOpsTableTableManager(_db, _db.syncOps);
  $$PeerStatesTableTableManager get peerStates =>
      $$PeerStatesTableTableManager(_db, _db.peerStates);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$AiUsageTableTableManager get aiUsage =>
      $$AiUsageTableTableManager(_db, _db.aiUsage);
}
