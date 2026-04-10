import 'package:rpc_dart/rpc_dart.dart';

sealed class NodeRecord implements IRpcSerializable {
  final String type;
  final String key;
  final String vaultId;
  final String? parentKey;
  final bool isSynced;
  final DateTime createdAt;

  /// Timestamp assigned by the server when the record was first stored.
  /// Null for locally-created records that have not yet been synced.
  /// Used as authoritative ordering in [findLeaf] and LWW conflict resolution.
  final int? serverTimestampMs;

  const NodeRecord({
    required this.type,
    required this.key,
    required this.vaultId,
    this.parentKey,
    required this.isSynced,
    required this.createdAt,
    this.serverTimestampMs,
  });

  static NodeRecord fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      VaultRecord.nodeType => VaultRecord.fromJson(json),
      FileRecord.nodeType => FileRecord.fromJson(json),
      ChangeRecord.nodeType => ChangeRecord.fromJson(json),
      MoveRecord.nodeType => MoveRecord.fromJson(json),
      DeleteRecord.nodeType => DeleteRecord.fromJson(json),
      _ => throw ArgumentError('Unknown node type: $type'),
    };
  }

  static NodeRecord fromLocalJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      VaultRecord.nodeType => VaultRecord.fromLocalJson(json),
      FileRecord.nodeType => FileRecord.fromLocalJson(json),
      ChangeRecord.nodeType => ChangeRecord.fromLocalJson(json),
      MoveRecord.nodeType => MoveRecord.fromLocalJson(json),
      DeleteRecord.nodeType => DeleteRecord.fromLocalJson(json),
      _ => throw ArgumentError('Unknown node type: $type'),
    };
  }

  NodeRecord withSynced();
  NodeRecord withUnsynced();
  NodeRecord withOrphaned() => this;
  Map<String, dynamic> toLocalJson();

  Map<String, dynamic> _baseJson() => {
    'type': type,
    'key': key,
    'vaultId': vaultId,
    'createdAt': createdAt.toIso8601String(),
    if (parentKey != null) 'parentKey': parentKey,
    if (serverTimestampMs != null) 'serverTimestampMs': serverTimestampMs,
  };

  Map<String, dynamic> _baseLocalJson() => {
    ..._baseJson(),
    'isSynced': isSynced,
  };
}

class VaultRecord extends NodeRecord {
  static const nodeType = 'vault';

  final String name;
  final String? encryptedPayload;

  const VaultRecord({
    required super.key,
    required super.vaultId,
    super.parentKey,
    super.isSynced = false,
    required super.createdAt,
    super.serverTimestampMs,
    required this.name,
    this.encryptedPayload,
  }) : super(type: nodeType);

  factory VaultRecord.fromJson(Map<String, dynamic> json) => VaultRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: true,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    name: json['name'] as String,
    encryptedPayload: json['encryptedPayload'] as String?,
  );

  factory VaultRecord.fromLocalJson(Map<String, dynamic> json) => VaultRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: json['isSynced'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    name: json['name'] as String,
    encryptedPayload: json['encryptedPayload'] as String?,
  );

  @override
  VaultRecord withSynced() => VaultRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: true,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    name: name,
    encryptedPayload: encryptedPayload,
  );

  @override
  VaultRecord withUnsynced() => VaultRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: false,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    name: name,
    encryptedPayload: encryptedPayload,
  );

  @override
  Map<String, dynamic> toJson() => {
    ..._baseJson(),
    if (encryptedPayload != null) 'encryptedPayload': encryptedPayload,
  };

  @override
  Map<String, dynamic> toLocalJson() => {..._baseLocalJson(), 'name': name};
}

class FileRecord extends NodeRecord {
  static const nodeType = 'file';

  final String fileId;
  final String path;
  final String? encryptedPayload;

  const FileRecord({
    required super.key,
    required super.vaultId,
    super.parentKey,
    super.isSynced = false,
    required super.createdAt,
    super.serverTimestampMs,
    required this.fileId,
    required this.path,
    this.encryptedPayload,
  }) : super(type: nodeType);

  factory FileRecord.fromJson(Map<String, dynamic> json) => FileRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: true,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    fileId: json['fileId'] as String,
    path: json['path'] as String? ?? '',
    encryptedPayload: json['encryptedPayload'] as String?,
  );

  factory FileRecord.fromLocalJson(Map<String, dynamic> json) => FileRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: json['isSynced'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    fileId: json['fileId'] as String,
    path: json['path'] as String,
  );

  @override
  FileRecord withSynced() => FileRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: true,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
    path: path,
    encryptedPayload: encryptedPayload,
  );

  @override
  FileRecord withUnsynced() => FileRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: false,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
    path: path,
    encryptedPayload: encryptedPayload,
  );

  @override
  Map<String, dynamic> toJson() => {
    ..._baseJson(),
    'fileId': fileId,
    if (encryptedPayload != null) 'encryptedPayload': encryptedPayload,
    if (encryptedPayload == null) 'path': path,
  };

  @override
  Map<String, dynamic> toLocalJson() => {
    ..._baseLocalJson(),
    'fileId': fileId,
    'path': path,
  };
}

class ChangeRecord extends NodeRecord {
  static const nodeType = 'change';

  final String fileId;
  final String blobId;
  final int sizeBytes;
  final String? encryptedPayload;

  const ChangeRecord({
    required super.key,
    required super.vaultId,
    super.parentKey,
    super.isSynced = false,
    required super.createdAt,
    super.serverTimestampMs,
    required this.fileId,
    required this.blobId,
    required this.sizeBytes,
    this.encryptedPayload,
  }) : super(type: nodeType);

  factory ChangeRecord.fromJson(Map<String, dynamic> json) => ChangeRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: true,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    fileId: json['fileId'] as String,
    blobId: json['blobId'] as String,
    sizeBytes: 0,
    encryptedPayload: json['encryptedPayload'] as String?,
  );

  factory ChangeRecord.fromLocalJson(Map<String, dynamic> json) => ChangeRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: json['isSynced'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    fileId: json['fileId'] as String,
    blobId: json['blobId'] as String,
    sizeBytes: json['sizeBytes'] as int,
  );

  @override
  ChangeRecord withSynced() => ChangeRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: true,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
    blobId: blobId,
    sizeBytes: sizeBytes,
    encryptedPayload: encryptedPayload,
  );

  @override
  ChangeRecord withUnsynced() => ChangeRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: false,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
    blobId: blobId,
    sizeBytes: sizeBytes,
    encryptedPayload: encryptedPayload,
  );

  @override
  ChangeRecord withOrphaned() => ChangeRecord(
    key: key,
    vaultId: vaultId,
    parentKey: null,
    isSynced: isSynced,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
    blobId: blobId,
    sizeBytes: sizeBytes,
    encryptedPayload: encryptedPayload,
  );

  @override
  Map<String, dynamic> toJson() => {
    ..._baseJson(),
    'fileId': fileId,
    'blobId': blobId,
    if (encryptedPayload != null) 'encryptedPayload': encryptedPayload,
  };

  @override
  Map<String, dynamic> toLocalJson() => {
    ..._baseLocalJson(),
    'fileId': fileId,
    'blobId': blobId,
    'sizeBytes': sizeBytes,
  };
}

class MoveRecord extends NodeRecord {
  static const nodeType = 'move';

  final String fileId;
  final String fromPath;
  final String toPath;
  final String? encryptedPayload;

  const MoveRecord({
    required super.key,
    required super.vaultId,
    super.parentKey,
    super.isSynced = false,
    required super.createdAt,
    super.serverTimestampMs,
    required this.fileId,
    required this.fromPath,
    required this.toPath,
    this.encryptedPayload,
  }) : super(type: nodeType);

  factory MoveRecord.fromJson(Map<String, dynamic> json) => MoveRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: true,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    fileId: json['fileId'] as String,
    fromPath: json['fromPath'] as String? ?? '',
    toPath: json['toPath'] as String? ?? '',
    encryptedPayload: json['encryptedPayload'] as String?,
  );

  factory MoveRecord.fromLocalJson(Map<String, dynamic> json) => MoveRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: json['isSynced'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    fileId: json['fileId'] as String,
    fromPath: json['fromPath'] as String,
    toPath: json['toPath'] as String,
  );

  @override
  MoveRecord withSynced() => MoveRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: true,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
    fromPath: fromPath,
    toPath: toPath,
    encryptedPayload: encryptedPayload,
  );

  @override
  MoveRecord withUnsynced() => MoveRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: false,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
    fromPath: fromPath,
    toPath: toPath,
    encryptedPayload: encryptedPayload,
  );

  @override
  MoveRecord withOrphaned() => MoveRecord(
    key: key,
    vaultId: vaultId,
    parentKey: null,
    isSynced: isSynced,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
    fromPath: fromPath,
    toPath: toPath,
    encryptedPayload: encryptedPayload,
  );

  @override
  Map<String, dynamic> toJson() => {
    ..._baseJson(),
    'fileId': fileId,
    if (encryptedPayload != null) 'encryptedPayload': encryptedPayload,
    if (encryptedPayload == null) ...{'fromPath': fromPath, 'toPath': toPath},
  };

  @override
  Map<String, dynamic> toLocalJson() => {
    ..._baseLocalJson(),
    'fileId': fileId,
    'fromPath': fromPath,
    'toPath': toPath,
  };
}

class DeleteRecord extends NodeRecord {
  static const nodeType = 'delete';

  final String fileId;

  const DeleteRecord({
    required super.key,
    required super.vaultId,
    super.parentKey,
    super.isSynced = false,
    required super.createdAt,
    super.serverTimestampMs,
    required this.fileId,
  }) : super(type: nodeType);

  factory DeleteRecord.fromJson(Map<String, dynamic> json) => DeleteRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: true,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    fileId: json['fileId'] as String,
  );

  factory DeleteRecord.fromLocalJson(Map<String, dynamic> json) => DeleteRecord(
    key: json['key'] as String,
    vaultId: json['vaultId'] as String,
    parentKey: json['parentKey'] as String?,
    isSynced: json['isSynced'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    serverTimestampMs: json['serverTimestampMs'] as int?,
    fileId: json['fileId'] as String,
  );

  @override
  DeleteRecord withSynced() => DeleteRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: true,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
  );

  @override
  DeleteRecord withUnsynced() => DeleteRecord(
    key: key,
    vaultId: vaultId,
    parentKey: parentKey,
    isSynced: false,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
  );

  @override
  DeleteRecord withOrphaned() => DeleteRecord(
    key: key,
    vaultId: vaultId,
    parentKey: null,
    isSynced: isSynced,
    createdAt: createdAt,
    serverTimestampMs: serverTimestampMs,
    fileId: fileId,
  );

  @override
  Map<String, dynamic> toJson() => {..._baseJson(), 'fileId': fileId};

  @override
  Map<String, dynamic> toLocalJson() => {..._baseLocalJson(), 'fileId': fileId};
}
