// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $LocalMessagesTable extends LocalMessages
    with TableInfo<$LocalMessagesTable, LocalMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderSnowchatIdMeta = const VerificationMeta(
    'senderSnowchatId',
  );
  @override
  late final GeneratedColumn<String> senderSnowchatId = GeneratedColumn<String>(
    'sender_snowchat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateSentMeta = const VerificationMeta(
    'dateSent',
  );
  @override
  late final GeneratedColumn<int> dateSent = GeneratedColumn<int>(
    'date_sent',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateReceivedMeta = const VerificationMeta(
    'dateReceived',
  );
  @override
  late final GeneratedColumn<int> dateReceived = GeneratedColumn<int>(
    'date_received',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateServerMeta = const VerificationMeta(
    'dateServer',
  );
  @override
  late final GeneratedColumn<int> dateServer = GeneratedColumn<int>(
    'date_server',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(-1),
  );
  static const VerificationMeta _plaintextMeta = const VerificationMeta(
    'plaintext',
  );
  @override
  late final GeneratedColumn<String> plaintext = GeneratedColumn<String>(
    'plaintext',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _readMeta = const VerificationMeta('read');
  @override
  late final GeneratedColumn<bool> read = GeneratedColumn<bool>(
    'read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _outgoingStatusMeta = const VerificationMeta(
    'outgoingStatus',
  );
  @override
  late final GeneratedColumn<String> outgoingStatus = GeneratedColumn<String>(
    'outgoing_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('sent'),
  );
  static const VerificationMeta _hasDeliveryReceiptMeta =
      const VerificationMeta('hasDeliveryReceipt');
  @override
  late final GeneratedColumn<bool> hasDeliveryReceipt = GeneratedColumn<bool>(
    'has_delivery_receipt',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_delivery_receipt" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hasReadReceiptMeta = const VerificationMeta(
    'hasReadReceipt',
  );
  @override
  late final GeneratedColumn<bool> hasReadReceipt = GeneratedColumn<bool>(
    'has_read_receipt',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_read_receipt" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _notifiedMeta = const VerificationMeta(
    'notified',
  );
  @override
  late final GeneratedColumn<bool> notified = GeneratedColumn<bool>(
    'notified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("notified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _expiresInMeta = const VerificationMeta(
    'expiresIn',
  );
  @override
  late final GeneratedColumn<int> expiresIn = GeneratedColumn<int>(
    'expires_in',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _expireStartedMeta = const VerificationMeta(
    'expireStarted',
  );
  @override
  late final GeneratedColumn<int> expireStarted = GeneratedColumn<int>(
    'expire_started',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _metadataMeta = const VerificationMeta(
    'metadata',
  );
  @override
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
    'metadata',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteDeletedMeta = const VerificationMeta(
    'remoteDeleted',
  );
  @override
  late final GeneratedColumn<bool> remoteDeleted = GeneratedColumn<bool>(
    'remote_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("remote_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _mentionsSelfMeta = const VerificationMeta(
    'mentionsSelf',
  );
  @override
  late final GeneratedColumn<bool> mentionsSelf = GeneratedColumn<bool>(
    'mentions_self',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("mentions_self" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _replyToIdMeta = const VerificationMeta(
    'replyToId',
  );
  @override
  late final GeneratedColumn<String> replyToId = GeneratedColumn<String>(
    'reply_to_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _senderDisplayNameMeta = const VerificationMeta(
    'senderDisplayName',
  );
  @override
  late final GeneratedColumn<String> senderDisplayName =
      GeneratedColumn<String>(
        'sender_display_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    senderSnowchatId,
    dateSent,
    dateReceived,
    dateServer,
    plaintext,
    type,
    read,
    outgoingStatus,
    hasDeliveryReceipt,
    hasReadReceipt,
    notified,
    expiresIn,
    expireStarted,
    metadata,
    remoteDeleted,
    mentionsSelf,
    replyToId,
    senderDisplayName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_snowchat_id')) {
      context.handle(
        _senderSnowchatIdMeta,
        senderSnowchatId.isAcceptableOrUnknown(
          data['sender_snowchat_id']!,
          _senderSnowchatIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_senderSnowchatIdMeta);
    }
    if (data.containsKey('date_sent')) {
      context.handle(
        _dateSentMeta,
        dateSent.isAcceptableOrUnknown(data['date_sent']!, _dateSentMeta),
      );
    } else if (isInserting) {
      context.missing(_dateSentMeta);
    }
    if (data.containsKey('date_received')) {
      context.handle(
        _dateReceivedMeta,
        dateReceived.isAcceptableOrUnknown(
          data['date_received']!,
          _dateReceivedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dateReceivedMeta);
    }
    if (data.containsKey('date_server')) {
      context.handle(
        _dateServerMeta,
        dateServer.isAcceptableOrUnknown(data['date_server']!, _dateServerMeta),
      );
    }
    if (data.containsKey('plaintext')) {
      context.handle(
        _plaintextMeta,
        plaintext.isAcceptableOrUnknown(data['plaintext']!, _plaintextMeta),
      );
    } else if (isInserting) {
      context.missing(_plaintextMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('read')) {
      context.handle(
        _readMeta,
        read.isAcceptableOrUnknown(data['read']!, _readMeta),
      );
    }
    if (data.containsKey('outgoing_status')) {
      context.handle(
        _outgoingStatusMeta,
        outgoingStatus.isAcceptableOrUnknown(
          data['outgoing_status']!,
          _outgoingStatusMeta,
        ),
      );
    }
    if (data.containsKey('has_delivery_receipt')) {
      context.handle(
        _hasDeliveryReceiptMeta,
        hasDeliveryReceipt.isAcceptableOrUnknown(
          data['has_delivery_receipt']!,
          _hasDeliveryReceiptMeta,
        ),
      );
    }
    if (data.containsKey('has_read_receipt')) {
      context.handle(
        _hasReadReceiptMeta,
        hasReadReceipt.isAcceptableOrUnknown(
          data['has_read_receipt']!,
          _hasReadReceiptMeta,
        ),
      );
    }
    if (data.containsKey('notified')) {
      context.handle(
        _notifiedMeta,
        notified.isAcceptableOrUnknown(data['notified']!, _notifiedMeta),
      );
    }
    if (data.containsKey('expires_in')) {
      context.handle(
        _expiresInMeta,
        expiresIn.isAcceptableOrUnknown(data['expires_in']!, _expiresInMeta),
      );
    }
    if (data.containsKey('expire_started')) {
      context.handle(
        _expireStartedMeta,
        expireStarted.isAcceptableOrUnknown(
          data['expire_started']!,
          _expireStartedMeta,
        ),
      );
    }
    if (data.containsKey('metadata')) {
      context.handle(
        _metadataMeta,
        metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta),
      );
    }
    if (data.containsKey('remote_deleted')) {
      context.handle(
        _remoteDeletedMeta,
        remoteDeleted.isAcceptableOrUnknown(
          data['remote_deleted']!,
          _remoteDeletedMeta,
        ),
      );
    }
    if (data.containsKey('mentions_self')) {
      context.handle(
        _mentionsSelfMeta,
        mentionsSelf.isAcceptableOrUnknown(
          data['mentions_self']!,
          _mentionsSelfMeta,
        ),
      );
    }
    if (data.containsKey('reply_to_id')) {
      context.handle(
        _replyToIdMeta,
        replyToId.isAcceptableOrUnknown(data['reply_to_id']!, _replyToIdMeta),
      );
    }
    if (data.containsKey('sender_display_name')) {
      context.handle(
        _senderDisplayNameMeta,
        senderDisplayName.isAcceptableOrUnknown(
          data['sender_display_name']!,
          _senderDisplayNameMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      senderSnowchatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_snowchat_id'],
      )!,
      dateSent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_sent'],
      )!,
      dateReceived: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_received'],
      )!,
      dateServer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_server'],
      )!,
      plaintext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plaintext'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      read: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}read'],
      )!,
      outgoingStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outgoing_status'],
      )!,
      hasDeliveryReceipt: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_delivery_receipt'],
      )!,
      hasReadReceipt: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_read_receipt'],
      )!,
      notified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}notified'],
      )!,
      expiresIn: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_in'],
      )!,
      expireStarted: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expire_started'],
      )!,
      metadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata'],
      ),
      remoteDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}remote_deleted'],
      )!,
      mentionsSelf: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}mentions_self'],
      )!,
      replyToId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_id'],
      ),
      senderDisplayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_display_name'],
      ),
    );
  }

  @override
  $LocalMessagesTable createAlias(String alias) {
    return $LocalMessagesTable(attachedDatabase, alias);
  }
}

class LocalMessage extends DataClass implements Insertable<LocalMessage> {
  final String id;
  final String conversationId;
  final String senderSnowchatId;
  final int dateSent;
  final int dateReceived;
  final int dateServer;
  final String plaintext;
  final String type;
  final bool read;
  final String outgoingStatus;
  final bool hasDeliveryReceipt;
  final bool hasReadReceipt;
  final bool notified;
  final int expiresIn;
  final int expireStarted;
  final String? metadata;
  final bool remoteDeleted;
  final bool mentionsSelf;
  final String? replyToId;
  final String? senderDisplayName;
  const LocalMessage({
    required this.id,
    required this.conversationId,
    required this.senderSnowchatId,
    required this.dateSent,
    required this.dateReceived,
    required this.dateServer,
    required this.plaintext,
    required this.type,
    required this.read,
    required this.outgoingStatus,
    required this.hasDeliveryReceipt,
    required this.hasReadReceipt,
    required this.notified,
    required this.expiresIn,
    required this.expireStarted,
    this.metadata,
    required this.remoteDeleted,
    required this.mentionsSelf,
    this.replyToId,
    this.senderDisplayName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['sender_snowchat_id'] = Variable<String>(senderSnowchatId);
    map['date_sent'] = Variable<int>(dateSent);
    map['date_received'] = Variable<int>(dateReceived);
    map['date_server'] = Variable<int>(dateServer);
    map['plaintext'] = Variable<String>(plaintext);
    map['type'] = Variable<String>(type);
    map['read'] = Variable<bool>(read);
    map['outgoing_status'] = Variable<String>(outgoingStatus);
    map['has_delivery_receipt'] = Variable<bool>(hasDeliveryReceipt);
    map['has_read_receipt'] = Variable<bool>(hasReadReceipt);
    map['notified'] = Variable<bool>(notified);
    map['expires_in'] = Variable<int>(expiresIn);
    map['expire_started'] = Variable<int>(expireStarted);
    if (!nullToAbsent || metadata != null) {
      map['metadata'] = Variable<String>(metadata);
    }
    map['remote_deleted'] = Variable<bool>(remoteDeleted);
    map['mentions_self'] = Variable<bool>(mentionsSelf);
    if (!nullToAbsent || replyToId != null) {
      map['reply_to_id'] = Variable<String>(replyToId);
    }
    if (!nullToAbsent || senderDisplayName != null) {
      map['sender_display_name'] = Variable<String>(senderDisplayName);
    }
    return map;
  }

  LocalMessagesCompanion toCompanion(bool nullToAbsent) {
    return LocalMessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      senderSnowchatId: Value(senderSnowchatId),
      dateSent: Value(dateSent),
      dateReceived: Value(dateReceived),
      dateServer: Value(dateServer),
      plaintext: Value(plaintext),
      type: Value(type),
      read: Value(read),
      outgoingStatus: Value(outgoingStatus),
      hasDeliveryReceipt: Value(hasDeliveryReceipt),
      hasReadReceipt: Value(hasReadReceipt),
      notified: Value(notified),
      expiresIn: Value(expiresIn),
      expireStarted: Value(expireStarted),
      metadata: metadata == null && nullToAbsent
          ? const Value.absent()
          : Value(metadata),
      remoteDeleted: Value(remoteDeleted),
      mentionsSelf: Value(mentionsSelf),
      replyToId: replyToId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToId),
      senderDisplayName: senderDisplayName == null && nullToAbsent
          ? const Value.absent()
          : Value(senderDisplayName),
    );
  }

  factory LocalMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMessage(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      senderSnowchatId: serializer.fromJson<String>(json['senderSnowchatId']),
      dateSent: serializer.fromJson<int>(json['dateSent']),
      dateReceived: serializer.fromJson<int>(json['dateReceived']),
      dateServer: serializer.fromJson<int>(json['dateServer']),
      plaintext: serializer.fromJson<String>(json['plaintext']),
      type: serializer.fromJson<String>(json['type']),
      read: serializer.fromJson<bool>(json['read']),
      outgoingStatus: serializer.fromJson<String>(json['outgoingStatus']),
      hasDeliveryReceipt: serializer.fromJson<bool>(json['hasDeliveryReceipt']),
      hasReadReceipt: serializer.fromJson<bool>(json['hasReadReceipt']),
      notified: serializer.fromJson<bool>(json['notified']),
      expiresIn: serializer.fromJson<int>(json['expiresIn']),
      expireStarted: serializer.fromJson<int>(json['expireStarted']),
      metadata: serializer.fromJson<String?>(json['metadata']),
      remoteDeleted: serializer.fromJson<bool>(json['remoteDeleted']),
      mentionsSelf: serializer.fromJson<bool>(json['mentionsSelf']),
      replyToId: serializer.fromJson<String?>(json['replyToId']),
      senderDisplayName: serializer.fromJson<String?>(
        json['senderDisplayName'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'senderSnowchatId': serializer.toJson<String>(senderSnowchatId),
      'dateSent': serializer.toJson<int>(dateSent),
      'dateReceived': serializer.toJson<int>(dateReceived),
      'dateServer': serializer.toJson<int>(dateServer),
      'plaintext': serializer.toJson<String>(plaintext),
      'type': serializer.toJson<String>(type),
      'read': serializer.toJson<bool>(read),
      'outgoingStatus': serializer.toJson<String>(outgoingStatus),
      'hasDeliveryReceipt': serializer.toJson<bool>(hasDeliveryReceipt),
      'hasReadReceipt': serializer.toJson<bool>(hasReadReceipt),
      'notified': serializer.toJson<bool>(notified),
      'expiresIn': serializer.toJson<int>(expiresIn),
      'expireStarted': serializer.toJson<int>(expireStarted),
      'metadata': serializer.toJson<String?>(metadata),
      'remoteDeleted': serializer.toJson<bool>(remoteDeleted),
      'mentionsSelf': serializer.toJson<bool>(mentionsSelf),
      'replyToId': serializer.toJson<String?>(replyToId),
      'senderDisplayName': serializer.toJson<String?>(senderDisplayName),
    };
  }

  LocalMessage copyWith({
    String? id,
    String? conversationId,
    String? senderSnowchatId,
    int? dateSent,
    int? dateReceived,
    int? dateServer,
    String? plaintext,
    String? type,
    bool? read,
    String? outgoingStatus,
    bool? hasDeliveryReceipt,
    bool? hasReadReceipt,
    bool? notified,
    int? expiresIn,
    int? expireStarted,
    Value<String?> metadata = const Value.absent(),
    bool? remoteDeleted,
    bool? mentionsSelf,
    Value<String?> replyToId = const Value.absent(),
    Value<String?> senderDisplayName = const Value.absent(),
  }) => LocalMessage(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    senderSnowchatId: senderSnowchatId ?? this.senderSnowchatId,
    dateSent: dateSent ?? this.dateSent,
    dateReceived: dateReceived ?? this.dateReceived,
    dateServer: dateServer ?? this.dateServer,
    plaintext: plaintext ?? this.plaintext,
    type: type ?? this.type,
    read: read ?? this.read,
    outgoingStatus: outgoingStatus ?? this.outgoingStatus,
    hasDeliveryReceipt: hasDeliveryReceipt ?? this.hasDeliveryReceipt,
    hasReadReceipt: hasReadReceipt ?? this.hasReadReceipt,
    notified: notified ?? this.notified,
    expiresIn: expiresIn ?? this.expiresIn,
    expireStarted: expireStarted ?? this.expireStarted,
    metadata: metadata.present ? metadata.value : this.metadata,
    remoteDeleted: remoteDeleted ?? this.remoteDeleted,
    mentionsSelf: mentionsSelf ?? this.mentionsSelf,
    replyToId: replyToId.present ? replyToId.value : this.replyToId,
    senderDisplayName: senderDisplayName.present
        ? senderDisplayName.value
        : this.senderDisplayName,
  );
  LocalMessage copyWithCompanion(LocalMessagesCompanion data) {
    return LocalMessage(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      senderSnowchatId: data.senderSnowchatId.present
          ? data.senderSnowchatId.value
          : this.senderSnowchatId,
      dateSent: data.dateSent.present ? data.dateSent.value : this.dateSent,
      dateReceived: data.dateReceived.present
          ? data.dateReceived.value
          : this.dateReceived,
      dateServer: data.dateServer.present
          ? data.dateServer.value
          : this.dateServer,
      plaintext: data.plaintext.present ? data.plaintext.value : this.plaintext,
      type: data.type.present ? data.type.value : this.type,
      read: data.read.present ? data.read.value : this.read,
      outgoingStatus: data.outgoingStatus.present
          ? data.outgoingStatus.value
          : this.outgoingStatus,
      hasDeliveryReceipt: data.hasDeliveryReceipt.present
          ? data.hasDeliveryReceipt.value
          : this.hasDeliveryReceipt,
      hasReadReceipt: data.hasReadReceipt.present
          ? data.hasReadReceipt.value
          : this.hasReadReceipt,
      notified: data.notified.present ? data.notified.value : this.notified,
      expiresIn: data.expiresIn.present ? data.expiresIn.value : this.expiresIn,
      expireStarted: data.expireStarted.present
          ? data.expireStarted.value
          : this.expireStarted,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
      remoteDeleted: data.remoteDeleted.present
          ? data.remoteDeleted.value
          : this.remoteDeleted,
      mentionsSelf: data.mentionsSelf.present
          ? data.mentionsSelf.value
          : this.mentionsSelf,
      replyToId: data.replyToId.present ? data.replyToId.value : this.replyToId,
      senderDisplayName: data.senderDisplayName.present
          ? data.senderDisplayName.value
          : this.senderDisplayName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMessage(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderSnowchatId: $senderSnowchatId, ')
          ..write('dateSent: $dateSent, ')
          ..write('dateReceived: $dateReceived, ')
          ..write('dateServer: $dateServer, ')
          ..write('plaintext: $plaintext, ')
          ..write('type: $type, ')
          ..write('read: $read, ')
          ..write('outgoingStatus: $outgoingStatus, ')
          ..write('hasDeliveryReceipt: $hasDeliveryReceipt, ')
          ..write('hasReadReceipt: $hasReadReceipt, ')
          ..write('notified: $notified, ')
          ..write('expiresIn: $expiresIn, ')
          ..write('expireStarted: $expireStarted, ')
          ..write('metadata: $metadata, ')
          ..write('remoteDeleted: $remoteDeleted, ')
          ..write('mentionsSelf: $mentionsSelf, ')
          ..write('replyToId: $replyToId, ')
          ..write('senderDisplayName: $senderDisplayName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    senderSnowchatId,
    dateSent,
    dateReceived,
    dateServer,
    plaintext,
    type,
    read,
    outgoingStatus,
    hasDeliveryReceipt,
    hasReadReceipt,
    notified,
    expiresIn,
    expireStarted,
    metadata,
    remoteDeleted,
    mentionsSelf,
    replyToId,
    senderDisplayName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMessage &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.senderSnowchatId == this.senderSnowchatId &&
          other.dateSent == this.dateSent &&
          other.dateReceived == this.dateReceived &&
          other.dateServer == this.dateServer &&
          other.plaintext == this.plaintext &&
          other.type == this.type &&
          other.read == this.read &&
          other.outgoingStatus == this.outgoingStatus &&
          other.hasDeliveryReceipt == this.hasDeliveryReceipt &&
          other.hasReadReceipt == this.hasReadReceipt &&
          other.notified == this.notified &&
          other.expiresIn == this.expiresIn &&
          other.expireStarted == this.expireStarted &&
          other.metadata == this.metadata &&
          other.remoteDeleted == this.remoteDeleted &&
          other.mentionsSelf == this.mentionsSelf &&
          other.replyToId == this.replyToId &&
          other.senderDisplayName == this.senderDisplayName);
}

class LocalMessagesCompanion extends UpdateCompanion<LocalMessage> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> senderSnowchatId;
  final Value<int> dateSent;
  final Value<int> dateReceived;
  final Value<int> dateServer;
  final Value<String> plaintext;
  final Value<String> type;
  final Value<bool> read;
  final Value<String> outgoingStatus;
  final Value<bool> hasDeliveryReceipt;
  final Value<bool> hasReadReceipt;
  final Value<bool> notified;
  final Value<int> expiresIn;
  final Value<int> expireStarted;
  final Value<String?> metadata;
  final Value<bool> remoteDeleted;
  final Value<bool> mentionsSelf;
  final Value<String?> replyToId;
  final Value<String?> senderDisplayName;
  final Value<int> rowid;
  const LocalMessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderSnowchatId = const Value.absent(),
    this.dateSent = const Value.absent(),
    this.dateReceived = const Value.absent(),
    this.dateServer = const Value.absent(),
    this.plaintext = const Value.absent(),
    this.type = const Value.absent(),
    this.read = const Value.absent(),
    this.outgoingStatus = const Value.absent(),
    this.hasDeliveryReceipt = const Value.absent(),
    this.hasReadReceipt = const Value.absent(),
    this.notified = const Value.absent(),
    this.expiresIn = const Value.absent(),
    this.expireStarted = const Value.absent(),
    this.metadata = const Value.absent(),
    this.remoteDeleted = const Value.absent(),
    this.mentionsSelf = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.senderDisplayName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String senderSnowchatId,
    required int dateSent,
    required int dateReceived,
    this.dateServer = const Value.absent(),
    required String plaintext,
    this.type = const Value.absent(),
    this.read = const Value.absent(),
    this.outgoingStatus = const Value.absent(),
    this.hasDeliveryReceipt = const Value.absent(),
    this.hasReadReceipt = const Value.absent(),
    this.notified = const Value.absent(),
    this.expiresIn = const Value.absent(),
    this.expireStarted = const Value.absent(),
    this.metadata = const Value.absent(),
    this.remoteDeleted = const Value.absent(),
    this.mentionsSelf = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.senderDisplayName = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       senderSnowchatId = Value(senderSnowchatId),
       dateSent = Value(dateSent),
       dateReceived = Value(dateReceived),
       plaintext = Value(plaintext);
  static Insertable<LocalMessage> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? senderSnowchatId,
    Expression<int>? dateSent,
    Expression<int>? dateReceived,
    Expression<int>? dateServer,
    Expression<String>? plaintext,
    Expression<String>? type,
    Expression<bool>? read,
    Expression<String>? outgoingStatus,
    Expression<bool>? hasDeliveryReceipt,
    Expression<bool>? hasReadReceipt,
    Expression<bool>? notified,
    Expression<int>? expiresIn,
    Expression<int>? expireStarted,
    Expression<String>? metadata,
    Expression<bool>? remoteDeleted,
    Expression<bool>? mentionsSelf,
    Expression<String>? replyToId,
    Expression<String>? senderDisplayName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderSnowchatId != null) 'sender_snowchat_id': senderSnowchatId,
      if (dateSent != null) 'date_sent': dateSent,
      if (dateReceived != null) 'date_received': dateReceived,
      if (dateServer != null) 'date_server': dateServer,
      if (plaintext != null) 'plaintext': plaintext,
      if (type != null) 'type': type,
      if (read != null) 'read': read,
      if (outgoingStatus != null) 'outgoing_status': outgoingStatus,
      if (hasDeliveryReceipt != null)
        'has_delivery_receipt': hasDeliveryReceipt,
      if (hasReadReceipt != null) 'has_read_receipt': hasReadReceipt,
      if (notified != null) 'notified': notified,
      if (expiresIn != null) 'expires_in': expiresIn,
      if (expireStarted != null) 'expire_started': expireStarted,
      if (metadata != null) 'metadata': metadata,
      if (remoteDeleted != null) 'remote_deleted': remoteDeleted,
      if (mentionsSelf != null) 'mentions_self': mentionsSelf,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (senderDisplayName != null) 'sender_display_name': senderDisplayName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? senderSnowchatId,
    Value<int>? dateSent,
    Value<int>? dateReceived,
    Value<int>? dateServer,
    Value<String>? plaintext,
    Value<String>? type,
    Value<bool>? read,
    Value<String>? outgoingStatus,
    Value<bool>? hasDeliveryReceipt,
    Value<bool>? hasReadReceipt,
    Value<bool>? notified,
    Value<int>? expiresIn,
    Value<int>? expireStarted,
    Value<String?>? metadata,
    Value<bool>? remoteDeleted,
    Value<bool>? mentionsSelf,
    Value<String?>? replyToId,
    Value<String?>? senderDisplayName,
    Value<int>? rowid,
  }) {
    return LocalMessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderSnowchatId: senderSnowchatId ?? this.senderSnowchatId,
      dateSent: dateSent ?? this.dateSent,
      dateReceived: dateReceived ?? this.dateReceived,
      dateServer: dateServer ?? this.dateServer,
      plaintext: plaintext ?? this.plaintext,
      type: type ?? this.type,
      read: read ?? this.read,
      outgoingStatus: outgoingStatus ?? this.outgoingStatus,
      hasDeliveryReceipt: hasDeliveryReceipt ?? this.hasDeliveryReceipt,
      hasReadReceipt: hasReadReceipt ?? this.hasReadReceipt,
      notified: notified ?? this.notified,
      expiresIn: expiresIn ?? this.expiresIn,
      expireStarted: expireStarted ?? this.expireStarted,
      metadata: metadata ?? this.metadata,
      remoteDeleted: remoteDeleted ?? this.remoteDeleted,
      mentionsSelf: mentionsSelf ?? this.mentionsSelf,
      replyToId: replyToId ?? this.replyToId,
      senderDisplayName: senderDisplayName ?? this.senderDisplayName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (senderSnowchatId.present) {
      map['sender_snowchat_id'] = Variable<String>(senderSnowchatId.value);
    }
    if (dateSent.present) {
      map['date_sent'] = Variable<int>(dateSent.value);
    }
    if (dateReceived.present) {
      map['date_received'] = Variable<int>(dateReceived.value);
    }
    if (dateServer.present) {
      map['date_server'] = Variable<int>(dateServer.value);
    }
    if (plaintext.present) {
      map['plaintext'] = Variable<String>(plaintext.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (read.present) {
      map['read'] = Variable<bool>(read.value);
    }
    if (outgoingStatus.present) {
      map['outgoing_status'] = Variable<String>(outgoingStatus.value);
    }
    if (hasDeliveryReceipt.present) {
      map['has_delivery_receipt'] = Variable<bool>(hasDeliveryReceipt.value);
    }
    if (hasReadReceipt.present) {
      map['has_read_receipt'] = Variable<bool>(hasReadReceipt.value);
    }
    if (notified.present) {
      map['notified'] = Variable<bool>(notified.value);
    }
    if (expiresIn.present) {
      map['expires_in'] = Variable<int>(expiresIn.value);
    }
    if (expireStarted.present) {
      map['expire_started'] = Variable<int>(expireStarted.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<String>(metadata.value);
    }
    if (remoteDeleted.present) {
      map['remote_deleted'] = Variable<bool>(remoteDeleted.value);
    }
    if (mentionsSelf.present) {
      map['mentions_self'] = Variable<bool>(mentionsSelf.value);
    }
    if (replyToId.present) {
      map['reply_to_id'] = Variable<String>(replyToId.value);
    }
    if (senderDisplayName.present) {
      map['sender_display_name'] = Variable<String>(senderDisplayName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderSnowchatId: $senderSnowchatId, ')
          ..write('dateSent: $dateSent, ')
          ..write('dateReceived: $dateReceived, ')
          ..write('dateServer: $dateServer, ')
          ..write('plaintext: $plaintext, ')
          ..write('type: $type, ')
          ..write('read: $read, ')
          ..write('outgoingStatus: $outgoingStatus, ')
          ..write('hasDeliveryReceipt: $hasDeliveryReceipt, ')
          ..write('hasReadReceipt: $hasReadReceipt, ')
          ..write('notified: $notified, ')
          ..write('expiresIn: $expiresIn, ')
          ..write('expireStarted: $expireStarted, ')
          ..write('metadata: $metadata, ')
          ..write('remoteDeleted: $remoteDeleted, ')
          ..write('mentionsSelf: $mentionsSelf, ')
          ..write('replyToId: $replyToId, ')
          ..write('senderDisplayName: $senderDisplayName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('direct'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _participantIdsMeta = const VerificationMeta(
    'participantIds',
  );
  @override
  late final GeneratedColumn<String> participantIds = GeneratedColumn<String>(
    'participant_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _lastMessageTextMeta = const VerificationMeta(
    'lastMessageText',
  );
  @override
  late final GeneratedColumn<String> lastMessageText = GeneratedColumn<String>(
    'last_message_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageTimeMeta = const VerificationMeta(
    'lastMessageTime',
  );
  @override
  late final GeneratedColumn<int> lastMessageTime = GeneratedColumn<int>(
    'last_message_time',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageSenderIdMeta =
      const VerificationMeta('lastMessageSenderId');
  @override
  late final GeneratedColumn<String> lastMessageSenderId =
      GeneratedColumn<String>(
        'last_message_sender_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastMessageIdMeta = const VerificationMeta(
    'lastMessageId',
  );
  @override
  late final GeneratedColumn<String> lastMessageId = GeneratedColumn<String>(
    'last_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _unreadSelfMentionCountMeta =
      const VerificationMeta('unreadSelfMentionCount');
  @override
  late final GeneratedColumn<int> unreadSelfMentionCount = GeneratedColumn<int>(
    'unread_self_mention_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_read" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<int> lastSeen = GeneratedColumn<int>(
    'last_seen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastScrolledMeta = const VerificationMeta(
    'lastScrolled',
  );
  @override
  late final GeneratedColumn<int> lastScrolled = GeneratedColumn<int>(
    'last_scrolled',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinnedOrderMeta = const VerificationMeta(
    'pinnedOrder',
  );
  @override
  late final GeneratedColumn<int> pinnedOrder = GeneratedColumn<int>(
    'pinned_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isMutedMeta = const VerificationMeta(
    'isMuted',
  );
  @override
  late final GeneratedColumn<bool> isMuted = GeneratedColumn<bool>(
    'is_muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_muted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _disappearingTtlMeta = const VerificationMeta(
    'disappearingTtl',
  );
  @override
  late final GeneratedColumn<int> disappearingTtl = GeneratedColumn<int>(
    'disappearing_ttl',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoTranslateEnabledMeta =
      const VerificationMeta('autoTranslateEnabled');
  @override
  late final GeneratedColumn<bool> autoTranslateEnabled = GeneratedColumn<bool>(
    'auto_translate_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_translate_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _autoTranslateTargetLangMeta =
      const VerificationMeta('autoTranslateTargetLang');
  @override
  late final GeneratedColumn<String> autoTranslateTargetLang =
      GeneratedColumn<String>(
        'auto_translate_target_lang',
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    title,
    participantIds,
    groupId,
    lastMessageText,
    lastMessageTime,
    lastMessageSenderId,
    lastMessageId,
    unreadCount,
    unreadSelfMentionCount,
    isRead,
    lastSeen,
    lastScrolled,
    isPinned,
    pinnedOrder,
    isMuted,
    isArchived,
    isActive,
    disappearingTtl,
    autoTranslateEnabled,
    autoTranslateTargetLang,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('participant_ids')) {
      context.handle(
        _participantIdsMeta,
        participantIds.isAcceptableOrUnknown(
          data['participant_ids']!,
          _participantIdsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_participantIdsMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('last_message_text')) {
      context.handle(
        _lastMessageTextMeta,
        lastMessageText.isAcceptableOrUnknown(
          data['last_message_text']!,
          _lastMessageTextMeta,
        ),
      );
    }
    if (data.containsKey('last_message_time')) {
      context.handle(
        _lastMessageTimeMeta,
        lastMessageTime.isAcceptableOrUnknown(
          data['last_message_time']!,
          _lastMessageTimeMeta,
        ),
      );
    }
    if (data.containsKey('last_message_sender_id')) {
      context.handle(
        _lastMessageSenderIdMeta,
        lastMessageSenderId.isAcceptableOrUnknown(
          data['last_message_sender_id']!,
          _lastMessageSenderIdMeta,
        ),
      );
    }
    if (data.containsKey('last_message_id')) {
      context.handle(
        _lastMessageIdMeta,
        lastMessageId.isAcceptableOrUnknown(
          data['last_message_id']!,
          _lastMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('unread_self_mention_count')) {
      context.handle(
        _unreadSelfMentionCountMeta,
        unreadSelfMentionCount.isAcceptableOrUnknown(
          data['unread_self_mention_count']!,
          _unreadSelfMentionCountMeta,
        ),
      );
    }
    if (data.containsKey('is_read')) {
      context.handle(
        _isReadMeta,
        isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    }
    if (data.containsKey('last_scrolled')) {
      context.handle(
        _lastScrolledMeta,
        lastScrolled.isAcceptableOrUnknown(
          data['last_scrolled']!,
          _lastScrolledMeta,
        ),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('pinned_order')) {
      context.handle(
        _pinnedOrderMeta,
        pinnedOrder.isAcceptableOrUnknown(
          data['pinned_order']!,
          _pinnedOrderMeta,
        ),
      );
    }
    if (data.containsKey('is_muted')) {
      context.handle(
        _isMutedMeta,
        isMuted.isAcceptableOrUnknown(data['is_muted']!, _isMutedMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('disappearing_ttl')) {
      context.handle(
        _disappearingTtlMeta,
        disappearingTtl.isAcceptableOrUnknown(
          data['disappearing_ttl']!,
          _disappearingTtlMeta,
        ),
      );
    }
    if (data.containsKey('auto_translate_enabled')) {
      context.handle(
        _autoTranslateEnabledMeta,
        autoTranslateEnabled.isAcceptableOrUnknown(
          data['auto_translate_enabled']!,
          _autoTranslateEnabledMeta,
        ),
      );
    }
    if (data.containsKey('auto_translate_target_lang')) {
      context.handle(
        _autoTranslateTargetLangMeta,
        autoTranslateTargetLang.isAcceptableOrUnknown(
          data['auto_translate_target_lang']!,
          _autoTranslateTargetLangMeta,
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      participantIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participant_ids'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      lastMessageText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_text'],
      ),
      lastMessageTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_message_time'],
      ),
      lastMessageSenderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_sender_id'],
      ),
      lastMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_id'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      unreadSelfMentionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_self_mention_count'],
      )!,
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen'],
      )!,
      lastScrolled: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_scrolled'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      pinnedOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pinned_order'],
      ),
      isMuted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_muted'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      disappearingTtl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disappearing_ttl'],
      ),
      autoTranslateEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_translate_enabled'],
      )!,
      autoTranslateTargetLang: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auto_translate_target_lang'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String id;
  final String type;
  final String? title;
  final String participantIds;
  final String? groupId;
  final String? lastMessageText;
  final int? lastMessageTime;
  final String? lastMessageSenderId;
  final String? lastMessageId;
  final int unreadCount;
  final int unreadSelfMentionCount;
  final bool isRead;
  final int lastSeen;
  final int lastScrolled;
  final bool isPinned;
  final int? pinnedOrder;
  final bool isMuted;
  final bool isArchived;
  final bool isActive;
  final int? disappearingTtl;
  final bool autoTranslateEnabled;

  /// 채팅방별 번역 타겟 언어 (null이면 settings.preferredLanguage fallback).
  /// 값: SupportedLanguages의 name — 'Korean', 'English', ...
  final String? autoTranslateTargetLang;
  final int createdAt;
  final int updatedAt;
  const Conversation({
    required this.id,
    required this.type,
    this.title,
    required this.participantIds,
    this.groupId,
    this.lastMessageText,
    this.lastMessageTime,
    this.lastMessageSenderId,
    this.lastMessageId,
    required this.unreadCount,
    required this.unreadSelfMentionCount,
    required this.isRead,
    required this.lastSeen,
    required this.lastScrolled,
    required this.isPinned,
    this.pinnedOrder,
    required this.isMuted,
    required this.isArchived,
    required this.isActive,
    this.disappearingTtl,
    required this.autoTranslateEnabled,
    this.autoTranslateTargetLang,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['participant_ids'] = Variable<String>(participantIds);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    if (!nullToAbsent || lastMessageText != null) {
      map['last_message_text'] = Variable<String>(lastMessageText);
    }
    if (!nullToAbsent || lastMessageTime != null) {
      map['last_message_time'] = Variable<int>(lastMessageTime);
    }
    if (!nullToAbsent || lastMessageSenderId != null) {
      map['last_message_sender_id'] = Variable<String>(lastMessageSenderId);
    }
    if (!nullToAbsent || lastMessageId != null) {
      map['last_message_id'] = Variable<String>(lastMessageId);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['unread_self_mention_count'] = Variable<int>(unreadSelfMentionCount);
    map['is_read'] = Variable<bool>(isRead);
    map['last_seen'] = Variable<int>(lastSeen);
    map['last_scrolled'] = Variable<int>(lastScrolled);
    map['is_pinned'] = Variable<bool>(isPinned);
    if (!nullToAbsent || pinnedOrder != null) {
      map['pinned_order'] = Variable<int>(pinnedOrder);
    }
    map['is_muted'] = Variable<bool>(isMuted);
    map['is_archived'] = Variable<bool>(isArchived);
    map['is_active'] = Variable<bool>(isActive);
    if (!nullToAbsent || disappearingTtl != null) {
      map['disappearing_ttl'] = Variable<int>(disappearingTtl);
    }
    map['auto_translate_enabled'] = Variable<bool>(autoTranslateEnabled);
    if (!nullToAbsent || autoTranslateTargetLang != null) {
      map['auto_translate_target_lang'] = Variable<String>(
        autoTranslateTargetLang,
      );
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      type: Value(type),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      participantIds: Value(participantIds),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      lastMessageText: lastMessageText == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageText),
      lastMessageTime: lastMessageTime == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageTime),
      lastMessageSenderId: lastMessageSenderId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageSenderId),
      lastMessageId: lastMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageId),
      unreadCount: Value(unreadCount),
      unreadSelfMentionCount: Value(unreadSelfMentionCount),
      isRead: Value(isRead),
      lastSeen: Value(lastSeen),
      lastScrolled: Value(lastScrolled),
      isPinned: Value(isPinned),
      pinnedOrder: pinnedOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(pinnedOrder),
      isMuted: Value(isMuted),
      isArchived: Value(isArchived),
      isActive: Value(isActive),
      disappearingTtl: disappearingTtl == null && nullToAbsent
          ? const Value.absent()
          : Value(disappearingTtl),
      autoTranslateEnabled: Value(autoTranslateEnabled),
      autoTranslateTargetLang: autoTranslateTargetLang == null && nullToAbsent
          ? const Value.absent()
          : Value(autoTranslateTargetLang),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String?>(json['title']),
      participantIds: serializer.fromJson<String>(json['participantIds']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      lastMessageText: serializer.fromJson<String?>(json['lastMessageText']),
      lastMessageTime: serializer.fromJson<int?>(json['lastMessageTime']),
      lastMessageSenderId: serializer.fromJson<String?>(
        json['lastMessageSenderId'],
      ),
      lastMessageId: serializer.fromJson<String?>(json['lastMessageId']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      unreadSelfMentionCount: serializer.fromJson<int>(
        json['unreadSelfMentionCount'],
      ),
      isRead: serializer.fromJson<bool>(json['isRead']),
      lastSeen: serializer.fromJson<int>(json['lastSeen']),
      lastScrolled: serializer.fromJson<int>(json['lastScrolled']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      pinnedOrder: serializer.fromJson<int?>(json['pinnedOrder']),
      isMuted: serializer.fromJson<bool>(json['isMuted']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      disappearingTtl: serializer.fromJson<int?>(json['disappearingTtl']),
      autoTranslateEnabled: serializer.fromJson<bool>(
        json['autoTranslateEnabled'],
      ),
      autoTranslateTargetLang: serializer.fromJson<String?>(
        json['autoTranslateTargetLang'],
      ),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String?>(title),
      'participantIds': serializer.toJson<String>(participantIds),
      'groupId': serializer.toJson<String?>(groupId),
      'lastMessageText': serializer.toJson<String?>(lastMessageText),
      'lastMessageTime': serializer.toJson<int?>(lastMessageTime),
      'lastMessageSenderId': serializer.toJson<String?>(lastMessageSenderId),
      'lastMessageId': serializer.toJson<String?>(lastMessageId),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'unreadSelfMentionCount': serializer.toJson<int>(unreadSelfMentionCount),
      'isRead': serializer.toJson<bool>(isRead),
      'lastSeen': serializer.toJson<int>(lastSeen),
      'lastScrolled': serializer.toJson<int>(lastScrolled),
      'isPinned': serializer.toJson<bool>(isPinned),
      'pinnedOrder': serializer.toJson<int?>(pinnedOrder),
      'isMuted': serializer.toJson<bool>(isMuted),
      'isArchived': serializer.toJson<bool>(isArchived),
      'isActive': serializer.toJson<bool>(isActive),
      'disappearingTtl': serializer.toJson<int?>(disappearingTtl),
      'autoTranslateEnabled': serializer.toJson<bool>(autoTranslateEnabled),
      'autoTranslateTargetLang': serializer.toJson<String?>(
        autoTranslateTargetLang,
      ),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Conversation copyWith({
    String? id,
    String? type,
    Value<String?> title = const Value.absent(),
    String? participantIds,
    Value<String?> groupId = const Value.absent(),
    Value<String?> lastMessageText = const Value.absent(),
    Value<int?> lastMessageTime = const Value.absent(),
    Value<String?> lastMessageSenderId = const Value.absent(),
    Value<String?> lastMessageId = const Value.absent(),
    int? unreadCount,
    int? unreadSelfMentionCount,
    bool? isRead,
    int? lastSeen,
    int? lastScrolled,
    bool? isPinned,
    Value<int?> pinnedOrder = const Value.absent(),
    bool? isMuted,
    bool? isArchived,
    bool? isActive,
    Value<int?> disappearingTtl = const Value.absent(),
    bool? autoTranslateEnabled,
    Value<String?> autoTranslateTargetLang = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => Conversation(
    id: id ?? this.id,
    type: type ?? this.type,
    title: title.present ? title.value : this.title,
    participantIds: participantIds ?? this.participantIds,
    groupId: groupId.present ? groupId.value : this.groupId,
    lastMessageText: lastMessageText.present
        ? lastMessageText.value
        : this.lastMessageText,
    lastMessageTime: lastMessageTime.present
        ? lastMessageTime.value
        : this.lastMessageTime,
    lastMessageSenderId: lastMessageSenderId.present
        ? lastMessageSenderId.value
        : this.lastMessageSenderId,
    lastMessageId: lastMessageId.present
        ? lastMessageId.value
        : this.lastMessageId,
    unreadCount: unreadCount ?? this.unreadCount,
    unreadSelfMentionCount:
        unreadSelfMentionCount ?? this.unreadSelfMentionCount,
    isRead: isRead ?? this.isRead,
    lastSeen: lastSeen ?? this.lastSeen,
    lastScrolled: lastScrolled ?? this.lastScrolled,
    isPinned: isPinned ?? this.isPinned,
    pinnedOrder: pinnedOrder.present ? pinnedOrder.value : this.pinnedOrder,
    isMuted: isMuted ?? this.isMuted,
    isArchived: isArchived ?? this.isArchived,
    isActive: isActive ?? this.isActive,
    disappearingTtl: disappearingTtl.present
        ? disappearingTtl.value
        : this.disappearingTtl,
    autoTranslateEnabled: autoTranslateEnabled ?? this.autoTranslateEnabled,
    autoTranslateTargetLang: autoTranslateTargetLang.present
        ? autoTranslateTargetLang.value
        : this.autoTranslateTargetLang,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      participantIds: data.participantIds.present
          ? data.participantIds.value
          : this.participantIds,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      lastMessageText: data.lastMessageText.present
          ? data.lastMessageText.value
          : this.lastMessageText,
      lastMessageTime: data.lastMessageTime.present
          ? data.lastMessageTime.value
          : this.lastMessageTime,
      lastMessageSenderId: data.lastMessageSenderId.present
          ? data.lastMessageSenderId.value
          : this.lastMessageSenderId,
      lastMessageId: data.lastMessageId.present
          ? data.lastMessageId.value
          : this.lastMessageId,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      unreadSelfMentionCount: data.unreadSelfMentionCount.present
          ? data.unreadSelfMentionCount.value
          : this.unreadSelfMentionCount,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      lastScrolled: data.lastScrolled.present
          ? data.lastScrolled.value
          : this.lastScrolled,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      pinnedOrder: data.pinnedOrder.present
          ? data.pinnedOrder.value
          : this.pinnedOrder,
      isMuted: data.isMuted.present ? data.isMuted.value : this.isMuted,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      disappearingTtl: data.disappearingTtl.present
          ? data.disappearingTtl.value
          : this.disappearingTtl,
      autoTranslateEnabled: data.autoTranslateEnabled.present
          ? data.autoTranslateEnabled.value
          : this.autoTranslateEnabled,
      autoTranslateTargetLang: data.autoTranslateTargetLang.present
          ? data.autoTranslateTargetLang.value
          : this.autoTranslateTargetLang,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('participantIds: $participantIds, ')
          ..write('groupId: $groupId, ')
          ..write('lastMessageText: $lastMessageText, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('lastMessageSenderId: $lastMessageSenderId, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('unreadSelfMentionCount: $unreadSelfMentionCount, ')
          ..write('isRead: $isRead, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('lastScrolled: $lastScrolled, ')
          ..write('isPinned: $isPinned, ')
          ..write('pinnedOrder: $pinnedOrder, ')
          ..write('isMuted: $isMuted, ')
          ..write('isArchived: $isArchived, ')
          ..write('isActive: $isActive, ')
          ..write('disappearingTtl: $disappearingTtl, ')
          ..write('autoTranslateEnabled: $autoTranslateEnabled, ')
          ..write('autoTranslateTargetLang: $autoTranslateTargetLang, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    type,
    title,
    participantIds,
    groupId,
    lastMessageText,
    lastMessageTime,
    lastMessageSenderId,
    lastMessageId,
    unreadCount,
    unreadSelfMentionCount,
    isRead,
    lastSeen,
    lastScrolled,
    isPinned,
    pinnedOrder,
    isMuted,
    isArchived,
    isActive,
    disappearingTtl,
    autoTranslateEnabled,
    autoTranslateTargetLang,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.type == this.type &&
          other.title == this.title &&
          other.participantIds == this.participantIds &&
          other.groupId == this.groupId &&
          other.lastMessageText == this.lastMessageText &&
          other.lastMessageTime == this.lastMessageTime &&
          other.lastMessageSenderId == this.lastMessageSenderId &&
          other.lastMessageId == this.lastMessageId &&
          other.unreadCount == this.unreadCount &&
          other.unreadSelfMentionCount == this.unreadSelfMentionCount &&
          other.isRead == this.isRead &&
          other.lastSeen == this.lastSeen &&
          other.lastScrolled == this.lastScrolled &&
          other.isPinned == this.isPinned &&
          other.pinnedOrder == this.pinnedOrder &&
          other.isMuted == this.isMuted &&
          other.isArchived == this.isArchived &&
          other.isActive == this.isActive &&
          other.disappearingTtl == this.disappearingTtl &&
          other.autoTranslateEnabled == this.autoTranslateEnabled &&
          other.autoTranslateTargetLang == this.autoTranslateTargetLang &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> id;
  final Value<String> type;
  final Value<String?> title;
  final Value<String> participantIds;
  final Value<String?> groupId;
  final Value<String?> lastMessageText;
  final Value<int?> lastMessageTime;
  final Value<String?> lastMessageSenderId;
  final Value<String?> lastMessageId;
  final Value<int> unreadCount;
  final Value<int> unreadSelfMentionCount;
  final Value<bool> isRead;
  final Value<int> lastSeen;
  final Value<int> lastScrolled;
  final Value<bool> isPinned;
  final Value<int?> pinnedOrder;
  final Value<bool> isMuted;
  final Value<bool> isArchived;
  final Value<bool> isActive;
  final Value<int?> disappearingTtl;
  final Value<bool> autoTranslateEnabled;
  final Value<String?> autoTranslateTargetLang;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.participantIds = const Value.absent(),
    this.groupId = const Value.absent(),
    this.lastMessageText = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.lastMessageSenderId = const Value.absent(),
    this.lastMessageId = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.unreadSelfMentionCount = const Value.absent(),
    this.isRead = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.lastScrolled = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.pinnedOrder = const Value.absent(),
    this.isMuted = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isActive = const Value.absent(),
    this.disappearingTtl = const Value.absent(),
    this.autoTranslateEnabled = const Value.absent(),
    this.autoTranslateTargetLang = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    required String participantIds,
    this.groupId = const Value.absent(),
    this.lastMessageText = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.lastMessageSenderId = const Value.absent(),
    this.lastMessageId = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.unreadSelfMentionCount = const Value.absent(),
    this.isRead = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.lastScrolled = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.pinnedOrder = const Value.absent(),
    this.isMuted = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isActive = const Value.absent(),
    this.disappearingTtl = const Value.absent(),
    this.autoTranslateEnabled = const Value.absent(),
    this.autoTranslateTargetLang = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       participantIds = Value(participantIds),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Conversation> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? participantIds,
    Expression<String>? groupId,
    Expression<String>? lastMessageText,
    Expression<int>? lastMessageTime,
    Expression<String>? lastMessageSenderId,
    Expression<String>? lastMessageId,
    Expression<int>? unreadCount,
    Expression<int>? unreadSelfMentionCount,
    Expression<bool>? isRead,
    Expression<int>? lastSeen,
    Expression<int>? lastScrolled,
    Expression<bool>? isPinned,
    Expression<int>? pinnedOrder,
    Expression<bool>? isMuted,
    Expression<bool>? isArchived,
    Expression<bool>? isActive,
    Expression<int>? disappearingTtl,
    Expression<bool>? autoTranslateEnabled,
    Expression<String>? autoTranslateTargetLang,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (participantIds != null) 'participant_ids': participantIds,
      if (groupId != null) 'group_id': groupId,
      if (lastMessageText != null) 'last_message_text': lastMessageText,
      if (lastMessageTime != null) 'last_message_time': lastMessageTime,
      if (lastMessageSenderId != null)
        'last_message_sender_id': lastMessageSenderId,
      if (lastMessageId != null) 'last_message_id': lastMessageId,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (unreadSelfMentionCount != null)
        'unread_self_mention_count': unreadSelfMentionCount,
      if (isRead != null) 'is_read': isRead,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (lastScrolled != null) 'last_scrolled': lastScrolled,
      if (isPinned != null) 'is_pinned': isPinned,
      if (pinnedOrder != null) 'pinned_order': pinnedOrder,
      if (isMuted != null) 'is_muted': isMuted,
      if (isArchived != null) 'is_archived': isArchived,
      if (isActive != null) 'is_active': isActive,
      if (disappearingTtl != null) 'disappearing_ttl': disappearingTtl,
      if (autoTranslateEnabled != null)
        'auto_translate_enabled': autoTranslateEnabled,
      if (autoTranslateTargetLang != null)
        'auto_translate_target_lang': autoTranslateTargetLang,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String?>? title,
    Value<String>? participantIds,
    Value<String?>? groupId,
    Value<String?>? lastMessageText,
    Value<int?>? lastMessageTime,
    Value<String?>? lastMessageSenderId,
    Value<String?>? lastMessageId,
    Value<int>? unreadCount,
    Value<int>? unreadSelfMentionCount,
    Value<bool>? isRead,
    Value<int>? lastSeen,
    Value<int>? lastScrolled,
    Value<bool>? isPinned,
    Value<int?>? pinnedOrder,
    Value<bool>? isMuted,
    Value<bool>? isArchived,
    Value<bool>? isActive,
    Value<int?>? disappearingTtl,
    Value<bool>? autoTranslateEnabled,
    Value<String?>? autoTranslateTargetLang,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      participantIds: participantIds ?? this.participantIds,
      groupId: groupId ?? this.groupId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      unreadCount: unreadCount ?? this.unreadCount,
      unreadSelfMentionCount:
          unreadSelfMentionCount ?? this.unreadSelfMentionCount,
      isRead: isRead ?? this.isRead,
      lastSeen: lastSeen ?? this.lastSeen,
      lastScrolled: lastScrolled ?? this.lastScrolled,
      isPinned: isPinned ?? this.isPinned,
      pinnedOrder: pinnedOrder ?? this.pinnedOrder,
      isMuted: isMuted ?? this.isMuted,
      isArchived: isArchived ?? this.isArchived,
      isActive: isActive ?? this.isActive,
      disappearingTtl: disappearingTtl ?? this.disappearingTtl,
      autoTranslateEnabled: autoTranslateEnabled ?? this.autoTranslateEnabled,
      autoTranslateTargetLang:
          autoTranslateTargetLang ?? this.autoTranslateTargetLang,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (participantIds.present) {
      map['participant_ids'] = Variable<String>(participantIds.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (lastMessageText.present) {
      map['last_message_text'] = Variable<String>(lastMessageText.value);
    }
    if (lastMessageTime.present) {
      map['last_message_time'] = Variable<int>(lastMessageTime.value);
    }
    if (lastMessageSenderId.present) {
      map['last_message_sender_id'] = Variable<String>(
        lastMessageSenderId.value,
      );
    }
    if (lastMessageId.present) {
      map['last_message_id'] = Variable<String>(lastMessageId.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (unreadSelfMentionCount.present) {
      map['unread_self_mention_count'] = Variable<int>(
        unreadSelfMentionCount.value,
      );
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<int>(lastSeen.value);
    }
    if (lastScrolled.present) {
      map['last_scrolled'] = Variable<int>(lastScrolled.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (pinnedOrder.present) {
      map['pinned_order'] = Variable<int>(pinnedOrder.value);
    }
    if (isMuted.present) {
      map['is_muted'] = Variable<bool>(isMuted.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (disappearingTtl.present) {
      map['disappearing_ttl'] = Variable<int>(disappearingTtl.value);
    }
    if (autoTranslateEnabled.present) {
      map['auto_translate_enabled'] = Variable<bool>(
        autoTranslateEnabled.value,
      );
    }
    if (autoTranslateTargetLang.present) {
      map['auto_translate_target_lang'] = Variable<String>(
        autoTranslateTargetLang.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('participantIds: $participantIds, ')
          ..write('groupId: $groupId, ')
          ..write('lastMessageText: $lastMessageText, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('lastMessageSenderId: $lastMessageSenderId, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('unreadSelfMentionCount: $unreadSelfMentionCount, ')
          ..write('isRead: $isRead, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('lastScrolled: $lastScrolled, ')
          ..write('isPinned: $isPinned, ')
          ..write('pinnedOrder: $pinnedOrder, ')
          ..write('isMuted: $isMuted, ')
          ..write('isArchived: $isArchived, ')
          ..write('isActive: $isActive, ')
          ..write('disappearingTtl: $disappearingTtl, ')
          ..write('autoTranslateEnabled: $autoTranslateEnabled, ')
          ..write('autoTranslateTargetLang: $autoTranslateTargetLang, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContactsTable extends Contacts with TableInfo<$ContactsTable, Contact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _snowChatIdMeta = const VerificationMeta(
    'snowChatId',
  );
  @override
  late final GeneratedColumn<String> snowChatId = GeneratedColumn<String>(
    'snow_chat_id',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publicKeyHexMeta = const VerificationMeta(
    'publicKeyHex',
  );
  @override
  late final GeneratedColumn<String> publicKeyHex = GeneratedColumn<String>(
    'public_key_hex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isBlockedMeta = const VerificationMeta(
    'isBlocked',
  );
  @override
  late final GeneratedColumn<bool> isBlocked = GeneratedColumn<bool>(
    'is_blocked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_blocked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isTrustedMeta = const VerificationMeta(
    'isTrusted',
  );
  @override
  late final GeneratedColumn<bool> isTrusted = GeneratedColumn<bool>(
    'is_trusted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_trusted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    snowChatId,
    displayName,
    publicKeyHex,
    isBlocked,
    isTrusted,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contacts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Contact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('snow_chat_id')) {
      context.handle(
        _snowChatIdMeta,
        snowChatId.isAcceptableOrUnknown(
          data['snow_chat_id']!,
          _snowChatIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snowChatIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('public_key_hex')) {
      context.handle(
        _publicKeyHexMeta,
        publicKeyHex.isAcceptableOrUnknown(
          data['public_key_hex']!,
          _publicKeyHexMeta,
        ),
      );
    }
    if (data.containsKey('is_blocked')) {
      context.handle(
        _isBlockedMeta,
        isBlocked.isAcceptableOrUnknown(data['is_blocked']!, _isBlockedMeta),
      );
    }
    if (data.containsKey('is_trusted')) {
      context.handle(
        _isTrustedMeta,
        isTrusted.isAcceptableOrUnknown(data['is_trusted']!, _isTrustedMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snowChatId};
  @override
  Contact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Contact(
      snowChatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snow_chat_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      publicKeyHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key_hex'],
      ),
      isBlocked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_blocked'],
      )!,
      isTrusted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_trusted'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $ContactsTable createAlias(String alias) {
    return $ContactsTable(attachedDatabase, alias);
  }
}

class Contact extends DataClass implements Insertable<Contact> {
  final String snowChatId;
  final String? displayName;
  final String? publicKeyHex;
  final bool isBlocked;
  final bool isTrusted;
  final DateTime addedAt;
  const Contact({
    required this.snowChatId,
    this.displayName,
    this.publicKeyHex,
    required this.isBlocked,
    required this.isTrusted,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['snow_chat_id'] = Variable<String>(snowChatId);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || publicKeyHex != null) {
      map['public_key_hex'] = Variable<String>(publicKeyHex);
    }
    map['is_blocked'] = Variable<bool>(isBlocked);
    map['is_trusted'] = Variable<bool>(isTrusted);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  ContactsCompanion toCompanion(bool nullToAbsent) {
    return ContactsCompanion(
      snowChatId: Value(snowChatId),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      publicKeyHex: publicKeyHex == null && nullToAbsent
          ? const Value.absent()
          : Value(publicKeyHex),
      isBlocked: Value(isBlocked),
      isTrusted: Value(isTrusted),
      addedAt: Value(addedAt),
    );
  }

  factory Contact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Contact(
      snowChatId: serializer.fromJson<String>(json['snowChatId']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      publicKeyHex: serializer.fromJson<String?>(json['publicKeyHex']),
      isBlocked: serializer.fromJson<bool>(json['isBlocked']),
      isTrusted: serializer.fromJson<bool>(json['isTrusted']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'snowChatId': serializer.toJson<String>(snowChatId),
      'displayName': serializer.toJson<String?>(displayName),
      'publicKeyHex': serializer.toJson<String?>(publicKeyHex),
      'isBlocked': serializer.toJson<bool>(isBlocked),
      'isTrusted': serializer.toJson<bool>(isTrusted),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  Contact copyWith({
    String? snowChatId,
    Value<String?> displayName = const Value.absent(),
    Value<String?> publicKeyHex = const Value.absent(),
    bool? isBlocked,
    bool? isTrusted,
    DateTime? addedAt,
  }) => Contact(
    snowChatId: snowChatId ?? this.snowChatId,
    displayName: displayName.present ? displayName.value : this.displayName,
    publicKeyHex: publicKeyHex.present ? publicKeyHex.value : this.publicKeyHex,
    isBlocked: isBlocked ?? this.isBlocked,
    isTrusted: isTrusted ?? this.isTrusted,
    addedAt: addedAt ?? this.addedAt,
  );
  Contact copyWithCompanion(ContactsCompanion data) {
    return Contact(
      snowChatId: data.snowChatId.present
          ? data.snowChatId.value
          : this.snowChatId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      publicKeyHex: data.publicKeyHex.present
          ? data.publicKeyHex.value
          : this.publicKeyHex,
      isBlocked: data.isBlocked.present ? data.isBlocked.value : this.isBlocked,
      isTrusted: data.isTrusted.present ? data.isTrusted.value : this.isTrusted,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Contact(')
          ..write('snowChatId: $snowChatId, ')
          ..write('displayName: $displayName, ')
          ..write('publicKeyHex: $publicKeyHex, ')
          ..write('isBlocked: $isBlocked, ')
          ..write('isTrusted: $isTrusted, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    snowChatId,
    displayName,
    publicKeyHex,
    isBlocked,
    isTrusted,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Contact &&
          other.snowChatId == this.snowChatId &&
          other.displayName == this.displayName &&
          other.publicKeyHex == this.publicKeyHex &&
          other.isBlocked == this.isBlocked &&
          other.isTrusted == this.isTrusted &&
          other.addedAt == this.addedAt);
}

class ContactsCompanion extends UpdateCompanion<Contact> {
  final Value<String> snowChatId;
  final Value<String?> displayName;
  final Value<String?> publicKeyHex;
  final Value<bool> isBlocked;
  final Value<bool> isTrusted;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const ContactsCompanion({
    this.snowChatId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.publicKeyHex = const Value.absent(),
    this.isBlocked = const Value.absent(),
    this.isTrusted = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContactsCompanion.insert({
    required String snowChatId,
    this.displayName = const Value.absent(),
    this.publicKeyHex = const Value.absent(),
    this.isBlocked = const Value.absent(),
    this.isTrusted = const Value.absent(),
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : snowChatId = Value(snowChatId),
       addedAt = Value(addedAt);
  static Insertable<Contact> custom({
    Expression<String>? snowChatId,
    Expression<String>? displayName,
    Expression<String>? publicKeyHex,
    Expression<bool>? isBlocked,
    Expression<bool>? isTrusted,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (snowChatId != null) 'snow_chat_id': snowChatId,
      if (displayName != null) 'display_name': displayName,
      if (publicKeyHex != null) 'public_key_hex': publicKeyHex,
      if (isBlocked != null) 'is_blocked': isBlocked,
      if (isTrusted != null) 'is_trusted': isTrusted,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContactsCompanion copyWith({
    Value<String>? snowChatId,
    Value<String?>? displayName,
    Value<String?>? publicKeyHex,
    Value<bool>? isBlocked,
    Value<bool>? isTrusted,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return ContactsCompanion(
      snowChatId: snowChatId ?? this.snowChatId,
      displayName: displayName ?? this.displayName,
      publicKeyHex: publicKeyHex ?? this.publicKeyHex,
      isBlocked: isBlocked ?? this.isBlocked,
      isTrusted: isTrusted ?? this.isTrusted,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (snowChatId.present) {
      map['snow_chat_id'] = Variable<String>(snowChatId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (publicKeyHex.present) {
      map['public_key_hex'] = Variable<String>(publicKeyHex.value);
    }
    if (isBlocked.present) {
      map['is_blocked'] = Variable<bool>(isBlocked.value);
    }
    if (isTrusted.present) {
      map['is_trusted'] = Variable<bool>(isTrusted.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactsCompanion(')
          ..write('snowChatId: $snowChatId, ')
          ..write('displayName: $displayName, ')
          ..write('publicKeyHex: $publicKeyHex, ')
          ..write('isBlocked: $isBlocked, ')
          ..write('isTrusted: $isTrusted, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SignalSessionsTable extends SignalSessions
    with TableInfo<$SignalSessionsTable, SignalSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignalSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recipientDeviceIdMeta = const VerificationMeta(
    'recipientDeviceId',
  );
  @override
  late final GeneratedColumn<String> recipientDeviceId =
      GeneratedColumn<String>(
        'recipient_device_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _sessionStateMeta = const VerificationMeta(
    'sessionState',
  );
  @override
  late final GeneratedColumn<Uint8List> sessionState =
      GeneratedColumn<Uint8List>(
        'session_state',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    recipientDeviceId,
    sessionState,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signal_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignalSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('recipient_device_id')) {
      context.handle(
        _recipientDeviceIdMeta,
        recipientDeviceId.isAcceptableOrUnknown(
          data['recipient_device_id']!,
          _recipientDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recipientDeviceIdMeta);
    }
    if (data.containsKey('session_state')) {
      context.handle(
        _sessionStateMeta,
        sessionState.isAcceptableOrUnknown(
          data['session_state']!,
          _sessionStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionStateMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recipientDeviceId};
  @override
  SignalSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignalSession(
      recipientDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_device_id'],
      )!,
      sessionState: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}session_state'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SignalSessionsTable createAlias(String alias) {
    return $SignalSessionsTable(attachedDatabase, alias);
  }
}

class SignalSession extends DataClass implements Insertable<SignalSession> {
  final String recipientDeviceId;
  final Uint8List sessionState;
  final DateTime updatedAt;
  const SignalSession({
    required this.recipientDeviceId,
    required this.sessionState,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['recipient_device_id'] = Variable<String>(recipientDeviceId);
    map['session_state'] = Variable<Uint8List>(sessionState);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SignalSessionsCompanion toCompanion(bool nullToAbsent) {
    return SignalSessionsCompanion(
      recipientDeviceId: Value(recipientDeviceId),
      sessionState: Value(sessionState),
      updatedAt: Value(updatedAt),
    );
  }

  factory SignalSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignalSession(
      recipientDeviceId: serializer.fromJson<String>(json['recipientDeviceId']),
      sessionState: serializer.fromJson<Uint8List>(json['sessionState']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recipientDeviceId': serializer.toJson<String>(recipientDeviceId),
      'sessionState': serializer.toJson<Uint8List>(sessionState),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SignalSession copyWith({
    String? recipientDeviceId,
    Uint8List? sessionState,
    DateTime? updatedAt,
  }) => SignalSession(
    recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
    sessionState: sessionState ?? this.sessionState,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SignalSession copyWithCompanion(SignalSessionsCompanion data) {
    return SignalSession(
      recipientDeviceId: data.recipientDeviceId.present
          ? data.recipientDeviceId.value
          : this.recipientDeviceId,
      sessionState: data.sessionState.present
          ? data.sessionState.value
          : this.sessionState,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignalSession(')
          ..write('recipientDeviceId: $recipientDeviceId, ')
          ..write('sessionState: $sessionState, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    recipientDeviceId,
    $driftBlobEquality.hash(sessionState),
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignalSession &&
          other.recipientDeviceId == this.recipientDeviceId &&
          $driftBlobEquality.equals(other.sessionState, this.sessionState) &&
          other.updatedAt == this.updatedAt);
}

class SignalSessionsCompanion extends UpdateCompanion<SignalSession> {
  final Value<String> recipientDeviceId;
  final Value<Uint8List> sessionState;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SignalSessionsCompanion({
    this.recipientDeviceId = const Value.absent(),
    this.sessionState = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SignalSessionsCompanion.insert({
    required String recipientDeviceId,
    required Uint8List sessionState,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : recipientDeviceId = Value(recipientDeviceId),
       sessionState = Value(sessionState),
       updatedAt = Value(updatedAt);
  static Insertable<SignalSession> custom({
    Expression<String>? recipientDeviceId,
    Expression<Uint8List>? sessionState,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recipientDeviceId != null) 'recipient_device_id': recipientDeviceId,
      if (sessionState != null) 'session_state': sessionState,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SignalSessionsCompanion copyWith({
    Value<String>? recipientDeviceId,
    Value<Uint8List>? sessionState,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SignalSessionsCompanion(
      recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
      sessionState: sessionState ?? this.sessionState,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recipientDeviceId.present) {
      map['recipient_device_id'] = Variable<String>(recipientDeviceId.value);
    }
    if (sessionState.present) {
      map['session_state'] = Variable<Uint8List>(sessionState.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignalSessionsCompanion(')
          ..write('recipientDeviceId: $recipientDeviceId, ')
          ..write('sessionState: $sessionState, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SignalPreKeysTable extends SignalPreKeys
    with TableInfo<$SignalPreKeysTable, SignalPreKey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignalPreKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyIdMeta = const VerificationMeta('keyId');
  @override
  late final GeneratedColumn<int> keyId = GeneratedColumn<int>(
    'key_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<Uint8List> publicKey = GeneratedColumn<Uint8List>(
    'public_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isUsedMeta = const VerificationMeta('isUsed');
  @override
  late final GeneratedColumn<bool> isUsed = GeneratedColumn<bool>(
    'is_used',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_used" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [keyId, publicKey, isUsed, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signal_pre_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignalPreKey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_id')) {
      context.handle(
        _keyIdMeta,
        keyId.isAcceptableOrUnknown(data['key_id']!, _keyIdMeta),
      );
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_publicKeyMeta);
    }
    if (data.containsKey('is_used')) {
      context.handle(
        _isUsedMeta,
        isUsed.isAcceptableOrUnknown(data['is_used']!, _isUsedMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyId};
  @override
  SignalPreKey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignalPreKey(
      keyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}key_id'],
      )!,
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}public_key'],
      )!,
      isUsed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_used'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SignalPreKeysTable createAlias(String alias) {
    return $SignalPreKeysTable(attachedDatabase, alias);
  }
}

class SignalPreKey extends DataClass implements Insertable<SignalPreKey> {
  final int keyId;
  final Uint8List publicKey;
  final bool isUsed;
  final DateTime createdAt;
  const SignalPreKey({
    required this.keyId,
    required this.publicKey,
    required this.isUsed,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_id'] = Variable<int>(keyId);
    map['public_key'] = Variable<Uint8List>(publicKey);
    map['is_used'] = Variable<bool>(isUsed);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SignalPreKeysCompanion toCompanion(bool nullToAbsent) {
    return SignalPreKeysCompanion(
      keyId: Value(keyId),
      publicKey: Value(publicKey),
      isUsed: Value(isUsed),
      createdAt: Value(createdAt),
    );
  }

  factory SignalPreKey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignalPreKey(
      keyId: serializer.fromJson<int>(json['keyId']),
      publicKey: serializer.fromJson<Uint8List>(json['publicKey']),
      isUsed: serializer.fromJson<bool>(json['isUsed']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyId': serializer.toJson<int>(keyId),
      'publicKey': serializer.toJson<Uint8List>(publicKey),
      'isUsed': serializer.toJson<bool>(isUsed),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SignalPreKey copyWith({
    int? keyId,
    Uint8List? publicKey,
    bool? isUsed,
    DateTime? createdAt,
  }) => SignalPreKey(
    keyId: keyId ?? this.keyId,
    publicKey: publicKey ?? this.publicKey,
    isUsed: isUsed ?? this.isUsed,
    createdAt: createdAt ?? this.createdAt,
  );
  SignalPreKey copyWithCompanion(SignalPreKeysCompanion data) {
    return SignalPreKey(
      keyId: data.keyId.present ? data.keyId.value : this.keyId,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      isUsed: data.isUsed.present ? data.isUsed.value : this.isUsed,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignalPreKey(')
          ..write('keyId: $keyId, ')
          ..write('publicKey: $publicKey, ')
          ..write('isUsed: $isUsed, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(keyId, $driftBlobEquality.hash(publicKey), isUsed, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignalPreKey &&
          other.keyId == this.keyId &&
          $driftBlobEquality.equals(other.publicKey, this.publicKey) &&
          other.isUsed == this.isUsed &&
          other.createdAt == this.createdAt);
}

class SignalPreKeysCompanion extends UpdateCompanion<SignalPreKey> {
  final Value<int> keyId;
  final Value<Uint8List> publicKey;
  final Value<bool> isUsed;
  final Value<DateTime> createdAt;
  const SignalPreKeysCompanion({
    this.keyId = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.isUsed = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SignalPreKeysCompanion.insert({
    this.keyId = const Value.absent(),
    required Uint8List publicKey,
    this.isUsed = const Value.absent(),
    required DateTime createdAt,
  }) : publicKey = Value(publicKey),
       createdAt = Value(createdAt);
  static Insertable<SignalPreKey> custom({
    Expression<int>? keyId,
    Expression<Uint8List>? publicKey,
    Expression<bool>? isUsed,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (keyId != null) 'key_id': keyId,
      if (publicKey != null) 'public_key': publicKey,
      if (isUsed != null) 'is_used': isUsed,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SignalPreKeysCompanion copyWith({
    Value<int>? keyId,
    Value<Uint8List>? publicKey,
    Value<bool>? isUsed,
    Value<DateTime>? createdAt,
  }) {
    return SignalPreKeysCompanion(
      keyId: keyId ?? this.keyId,
      publicKey: publicKey ?? this.publicKey,
      isUsed: isUsed ?? this.isUsed,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyId.present) {
      map['key_id'] = Variable<int>(keyId.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<Uint8List>(publicKey.value);
    }
    if (isUsed.present) {
      map['is_used'] = Variable<bool>(isUsed.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignalPreKeysCompanion(')
          ..write('keyId: $keyId, ')
          ..write('publicKey: $publicKey, ')
          ..write('isUsed: $isUsed, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $LocalAttachmentsTable extends LocalAttachments
    with TableInfo<$LocalAttachmentsTable, LocalAttachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _remoteFileIdMeta = const VerificationMeta(
    'remoteFileId',
  );
  @override
  late final GeneratedColumn<String> remoteFileId = GeneratedColumn<String>(
    'remote_file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteKeyMeta = const VerificationMeta(
    'remoteKey',
  );
  @override
  late final GeneratedColumn<String> remoteKey = GeneratedColumn<String>(
    'remote_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteDigestMeta = const VerificationMeta(
    'remoteDigest',
  );
  @override
  late final GeneratedColumn<String> remoteDigest = GeneratedColumn<String>(
    'remote_digest',
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
  static const VerificationMeta _transferStateMeta = const VerificationMeta(
    'transferState',
  );
  @override
  late final GeneratedColumn<int> transferState = GeneratedColumn<int>(
    'transfer_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _blurHashMeta = const VerificationMeta(
    'blurHash',
  );
  @override
  late final GeneratedColumn<String> blurHash = GeneratedColumn<String>(
    'blur_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isVoiceNoteMeta = const VerificationMeta(
    'isVoiceNote',
  );
  @override
  late final GeneratedColumn<bool> isVoiceNote = GeneratedColumn<bool>(
    'is_voice_note',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_voice_note" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageId,
    displayOrder,
    contentType,
    fileName,
    fileSize,
    width,
    height,
    remoteFileId,
    remoteKey,
    remoteDigest,
    localPath,
    transferState,
    blurHash,
    thumbnailPath,
    isVoiceNote,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalAttachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
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
    if (data.containsKey('remote_file_id')) {
      context.handle(
        _remoteFileIdMeta,
        remoteFileId.isAcceptableOrUnknown(
          data['remote_file_id']!,
          _remoteFileIdMeta,
        ),
      );
    }
    if (data.containsKey('remote_key')) {
      context.handle(
        _remoteKeyMeta,
        remoteKey.isAcceptableOrUnknown(data['remote_key']!, _remoteKeyMeta),
      );
    }
    if (data.containsKey('remote_digest')) {
      context.handle(
        _remoteDigestMeta,
        remoteDigest.isAcceptableOrUnknown(
          data['remote_digest']!,
          _remoteDigestMeta,
        ),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('transfer_state')) {
      context.handle(
        _transferStateMeta,
        transferState.isAcceptableOrUnknown(
          data['transfer_state']!,
          _transferStateMeta,
        ),
      );
    }
    if (data.containsKey('blur_hash')) {
      context.handle(
        _blurHashMeta,
        blurHash.isAcceptableOrUnknown(data['blur_hash']!, _blurHashMeta),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('is_voice_note')) {
      context.handle(
        _isVoiceNoteMeta,
        isVoiceNote.isAcceptableOrUnknown(
          data['is_voice_note']!,
          _isVoiceNoteMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalAttachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAttachment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      ),
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      remoteFileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_file_id'],
      ),
      remoteKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_key'],
      ),
      remoteDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_digest'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      transferState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transfer_state'],
      )!,
      blurHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blur_hash'],
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      isVoiceNote: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_voice_note'],
      )!,
    );
  }

  @override
  $LocalAttachmentsTable createAlias(String alias) {
    return $LocalAttachmentsTable(attachedDatabase, alias);
  }
}

class LocalAttachment extends DataClass implements Insertable<LocalAttachment> {
  final String id;
  final String messageId;
  final int displayOrder;
  final String contentType;
  final String? fileName;
  final int fileSize;
  final int width;
  final int height;
  final String? remoteFileId;
  final String? remoteKey;
  final String? remoteDigest;
  final String? localPath;
  final int transferState;
  final String? blurHash;
  final String? thumbnailPath;
  final bool isVoiceNote;
  const LocalAttachment({
    required this.id,
    required this.messageId,
    required this.displayOrder,
    required this.contentType,
    this.fileName,
    required this.fileSize,
    required this.width,
    required this.height,
    this.remoteFileId,
    this.remoteKey,
    this.remoteDigest,
    this.localPath,
    required this.transferState,
    this.blurHash,
    this.thumbnailPath,
    required this.isVoiceNote,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['message_id'] = Variable<String>(messageId);
    map['display_order'] = Variable<int>(displayOrder);
    map['content_type'] = Variable<String>(contentType);
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    map['file_size'] = Variable<int>(fileSize);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    if (!nullToAbsent || remoteFileId != null) {
      map['remote_file_id'] = Variable<String>(remoteFileId);
    }
    if (!nullToAbsent || remoteKey != null) {
      map['remote_key'] = Variable<String>(remoteKey);
    }
    if (!nullToAbsent || remoteDigest != null) {
      map['remote_digest'] = Variable<String>(remoteDigest);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['transfer_state'] = Variable<int>(transferState);
    if (!nullToAbsent || blurHash != null) {
      map['blur_hash'] = Variable<String>(blurHash);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    map['is_voice_note'] = Variable<bool>(isVoiceNote);
    return map;
  }

  LocalAttachmentsCompanion toCompanion(bool nullToAbsent) {
    return LocalAttachmentsCompanion(
      id: Value(id),
      messageId: Value(messageId),
      displayOrder: Value(displayOrder),
      contentType: Value(contentType),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      fileSize: Value(fileSize),
      width: Value(width),
      height: Value(height),
      remoteFileId: remoteFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteFileId),
      remoteKey: remoteKey == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteKey),
      remoteDigest: remoteDigest == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteDigest),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      transferState: Value(transferState),
      blurHash: blurHash == null && nullToAbsent
          ? const Value.absent()
          : Value(blurHash),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      isVoiceNote: Value(isVoiceNote),
    );
  }

  factory LocalAttachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAttachment(
      id: serializer.fromJson<String>(json['id']),
      messageId: serializer.fromJson<String>(json['messageId']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      contentType: serializer.fromJson<String>(json['contentType']),
      fileName: serializer.fromJson<String?>(json['fileName']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      remoteFileId: serializer.fromJson<String?>(json['remoteFileId']),
      remoteKey: serializer.fromJson<String?>(json['remoteKey']),
      remoteDigest: serializer.fromJson<String?>(json['remoteDigest']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      transferState: serializer.fromJson<int>(json['transferState']),
      blurHash: serializer.fromJson<String?>(json['blurHash']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      isVoiceNote: serializer.fromJson<bool>(json['isVoiceNote']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'messageId': serializer.toJson<String>(messageId),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'contentType': serializer.toJson<String>(contentType),
      'fileName': serializer.toJson<String?>(fileName),
      'fileSize': serializer.toJson<int>(fileSize),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'remoteFileId': serializer.toJson<String?>(remoteFileId),
      'remoteKey': serializer.toJson<String?>(remoteKey),
      'remoteDigest': serializer.toJson<String?>(remoteDigest),
      'localPath': serializer.toJson<String?>(localPath),
      'transferState': serializer.toJson<int>(transferState),
      'blurHash': serializer.toJson<String?>(blurHash),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'isVoiceNote': serializer.toJson<bool>(isVoiceNote),
    };
  }

  LocalAttachment copyWith({
    String? id,
    String? messageId,
    int? displayOrder,
    String? contentType,
    Value<String?> fileName = const Value.absent(),
    int? fileSize,
    int? width,
    int? height,
    Value<String?> remoteFileId = const Value.absent(),
    Value<String?> remoteKey = const Value.absent(),
    Value<String?> remoteDigest = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    int? transferState,
    Value<String?> blurHash = const Value.absent(),
    Value<String?> thumbnailPath = const Value.absent(),
    bool? isVoiceNote,
  }) => LocalAttachment(
    id: id ?? this.id,
    messageId: messageId ?? this.messageId,
    displayOrder: displayOrder ?? this.displayOrder,
    contentType: contentType ?? this.contentType,
    fileName: fileName.present ? fileName.value : this.fileName,
    fileSize: fileSize ?? this.fileSize,
    width: width ?? this.width,
    height: height ?? this.height,
    remoteFileId: remoteFileId.present ? remoteFileId.value : this.remoteFileId,
    remoteKey: remoteKey.present ? remoteKey.value : this.remoteKey,
    remoteDigest: remoteDigest.present ? remoteDigest.value : this.remoteDigest,
    localPath: localPath.present ? localPath.value : this.localPath,
    transferState: transferState ?? this.transferState,
    blurHash: blurHash.present ? blurHash.value : this.blurHash,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    isVoiceNote: isVoiceNote ?? this.isVoiceNote,
  );
  LocalAttachment copyWithCompanion(LocalAttachmentsCompanion data) {
    return LocalAttachment(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      remoteFileId: data.remoteFileId.present
          ? data.remoteFileId.value
          : this.remoteFileId,
      remoteKey: data.remoteKey.present ? data.remoteKey.value : this.remoteKey,
      remoteDigest: data.remoteDigest.present
          ? data.remoteDigest.value
          : this.remoteDigest,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      transferState: data.transferState.present
          ? data.transferState.value
          : this.transferState,
      blurHash: data.blurHash.present ? data.blurHash.value : this.blurHash,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      isVoiceNote: data.isVoiceNote.present
          ? data.isVoiceNote.value
          : this.isVoiceNote,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAttachment(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('contentType: $contentType, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('remoteFileId: $remoteFileId, ')
          ..write('remoteKey: $remoteKey, ')
          ..write('remoteDigest: $remoteDigest, ')
          ..write('localPath: $localPath, ')
          ..write('transferState: $transferState, ')
          ..write('blurHash: $blurHash, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('isVoiceNote: $isVoiceNote')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageId,
    displayOrder,
    contentType,
    fileName,
    fileSize,
    width,
    height,
    remoteFileId,
    remoteKey,
    remoteDigest,
    localPath,
    transferState,
    blurHash,
    thumbnailPath,
    isVoiceNote,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAttachment &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.displayOrder == this.displayOrder &&
          other.contentType == this.contentType &&
          other.fileName == this.fileName &&
          other.fileSize == this.fileSize &&
          other.width == this.width &&
          other.height == this.height &&
          other.remoteFileId == this.remoteFileId &&
          other.remoteKey == this.remoteKey &&
          other.remoteDigest == this.remoteDigest &&
          other.localPath == this.localPath &&
          other.transferState == this.transferState &&
          other.blurHash == this.blurHash &&
          other.thumbnailPath == this.thumbnailPath &&
          other.isVoiceNote == this.isVoiceNote);
}

class LocalAttachmentsCompanion extends UpdateCompanion<LocalAttachment> {
  final Value<String> id;
  final Value<String> messageId;
  final Value<int> displayOrder;
  final Value<String> contentType;
  final Value<String?> fileName;
  final Value<int> fileSize;
  final Value<int> width;
  final Value<int> height;
  final Value<String?> remoteFileId;
  final Value<String?> remoteKey;
  final Value<String?> remoteDigest;
  final Value<String?> localPath;
  final Value<int> transferState;
  final Value<String?> blurHash;
  final Value<String?> thumbnailPath;
  final Value<bool> isVoiceNote;
  final Value<int> rowid;
  const LocalAttachmentsCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.contentType = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.remoteFileId = const Value.absent(),
    this.remoteKey = const Value.absent(),
    this.remoteDigest = const Value.absent(),
    this.localPath = const Value.absent(),
    this.transferState = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.isVoiceNote = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalAttachmentsCompanion.insert({
    required String id,
    required String messageId,
    this.displayOrder = const Value.absent(),
    required String contentType,
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.remoteFileId = const Value.absent(),
    this.remoteKey = const Value.absent(),
    this.remoteDigest = const Value.absent(),
    this.localPath = const Value.absent(),
    this.transferState = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.isVoiceNote = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       messageId = Value(messageId),
       contentType = Value(contentType);
  static Insertable<LocalAttachment> custom({
    Expression<String>? id,
    Expression<String>? messageId,
    Expression<int>? displayOrder,
    Expression<String>? contentType,
    Expression<String>? fileName,
    Expression<int>? fileSize,
    Expression<int>? width,
    Expression<int>? height,
    Expression<String>? remoteFileId,
    Expression<String>? remoteKey,
    Expression<String>? remoteDigest,
    Expression<String>? localPath,
    Expression<int>? transferState,
    Expression<String>? blurHash,
    Expression<String>? thumbnailPath,
    Expression<bool>? isVoiceNote,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (displayOrder != null) 'display_order': displayOrder,
      if (contentType != null) 'content_type': contentType,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (remoteFileId != null) 'remote_file_id': remoteFileId,
      if (remoteKey != null) 'remote_key': remoteKey,
      if (remoteDigest != null) 'remote_digest': remoteDigest,
      if (localPath != null) 'local_path': localPath,
      if (transferState != null) 'transfer_state': transferState,
      if (blurHash != null) 'blur_hash': blurHash,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (isVoiceNote != null) 'is_voice_note': isVoiceNote,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalAttachmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? messageId,
    Value<int>? displayOrder,
    Value<String>? contentType,
    Value<String?>? fileName,
    Value<int>? fileSize,
    Value<int>? width,
    Value<int>? height,
    Value<String?>? remoteFileId,
    Value<String?>? remoteKey,
    Value<String?>? remoteDigest,
    Value<String?>? localPath,
    Value<int>? transferState,
    Value<String?>? blurHash,
    Value<String?>? thumbnailPath,
    Value<bool>? isVoiceNote,
    Value<int>? rowid,
  }) {
    return LocalAttachmentsCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      displayOrder: displayOrder ?? this.displayOrder,
      contentType: contentType ?? this.contentType,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      width: width ?? this.width,
      height: height ?? this.height,
      remoteFileId: remoteFileId ?? this.remoteFileId,
      remoteKey: remoteKey ?? this.remoteKey,
      remoteDigest: remoteDigest ?? this.remoteDigest,
      localPath: localPath ?? this.localPath,
      transferState: transferState ?? this.transferState,
      blurHash: blurHash ?? this.blurHash,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isVoiceNote: isVoiceNote ?? this.isVoiceNote,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (remoteFileId.present) {
      map['remote_file_id'] = Variable<String>(remoteFileId.value);
    }
    if (remoteKey.present) {
      map['remote_key'] = Variable<String>(remoteKey.value);
    }
    if (remoteDigest.present) {
      map['remote_digest'] = Variable<String>(remoteDigest.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (transferState.present) {
      map['transfer_state'] = Variable<int>(transferState.value);
    }
    if (blurHash.present) {
      map['blur_hash'] = Variable<String>(blurHash.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (isVoiceNote.present) {
      map['is_voice_note'] = Variable<bool>(isVoiceNote.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('contentType: $contentType, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('remoteFileId: $remoteFileId, ')
          ..write('remoteKey: $remoteKey, ')
          ..write('remoteDigest: $remoteDigest, ')
          ..write('localPath: $localPath, ')
          ..write('transferState: $transferState, ')
          ..write('blurHash: $blurHash, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('isVoiceNote: $isVoiceNote, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WalletBalancesTable extends WalletBalances
    with TableInfo<$WalletBalancesTable, WalletBalance> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WalletBalancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerAddressMeta = const VerificationMeta(
    'ownerAddress',
  );
  @override
  late final GeneratedColumn<String> ownerAddress = GeneratedColumn<String>(
    'owner_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mintAddressMeta = const VerificationMeta(
    'mintAddress',
  );
  @override
  late final GeneratedColumn<String> mintAddress = GeneratedColumn<String>(
    'mint_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawAmountMeta = const VerificationMeta(
    'rawAmount',
  );
  @override
  late final GeneratedColumn<String> rawAmount = GeneratedColumn<String>(
    'raw_amount',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decimalsMeta = const VerificationMeta(
    'decimals',
  );
  @override
  late final GeneratedColumn<int> decimals = GeneratedColumn<int>(
    'decimals',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _logoUrlMeta = const VerificationMeta(
    'logoUrl',
  );
  @override
  late final GeneratedColumn<String> logoUrl = GeneratedColumn<String>(
    'logo_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastUpdatedMsMeta = const VerificationMeta(
    'lastUpdatedMs',
  );
  @override
  late final GeneratedColumn<int> lastUpdatedMs = GeneratedColumn<int>(
    'last_updated_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerAddress,
    mintAddress,
    rawAmount,
    decimals,
    symbol,
    name,
    logoUrl,
    lastUpdatedMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallet_balances';
  @override
  VerificationContext validateIntegrity(
    Insertable<WalletBalance> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_address')) {
      context.handle(
        _ownerAddressMeta,
        ownerAddress.isAcceptableOrUnknown(
          data['owner_address']!,
          _ownerAddressMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerAddressMeta);
    }
    if (data.containsKey('mint_address')) {
      context.handle(
        _mintAddressMeta,
        mintAddress.isAcceptableOrUnknown(
          data['mint_address']!,
          _mintAddressMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mintAddressMeta);
    }
    if (data.containsKey('raw_amount')) {
      context.handle(
        _rawAmountMeta,
        rawAmount.isAcceptableOrUnknown(data['raw_amount']!, _rawAmountMeta),
      );
    } else if (isInserting) {
      context.missing(_rawAmountMeta);
    }
    if (data.containsKey('decimals')) {
      context.handle(
        _decimalsMeta,
        decimals.isAcceptableOrUnknown(data['decimals']!, _decimalsMeta),
      );
    } else if (isInserting) {
      context.missing(_decimalsMeta);
    }
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('logo_url')) {
      context.handle(
        _logoUrlMeta,
        logoUrl.isAcceptableOrUnknown(data['logo_url']!, _logoUrlMeta),
      );
    }
    if (data.containsKey('last_updated_ms')) {
      context.handle(
        _lastUpdatedMsMeta,
        lastUpdatedMs.isAcceptableOrUnknown(
          data['last_updated_ms']!,
          _lastUpdatedMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastUpdatedMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerAddress, mintAddress};
  @override
  WalletBalance map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WalletBalance(
      ownerAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_address'],
      )!,
      mintAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mint_address'],
      )!,
      rawAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_amount'],
      )!,
      decimals: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}decimals'],
      )!,
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      logoUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logo_url'],
      ),
      lastUpdatedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_updated_ms'],
      )!,
    );
  }

  @override
  $WalletBalancesTable createAlias(String alias) {
    return $WalletBalancesTable(attachedDatabase, alias);
  }
}

class WalletBalance extends DataClass implements Insertable<WalletBalance> {
  final String ownerAddress;
  final String mintAddress;
  final String rawAmount;
  final int decimals;
  final String symbol;
  final String? name;
  final String? logoUrl;
  final int lastUpdatedMs;
  const WalletBalance({
    required this.ownerAddress,
    required this.mintAddress,
    required this.rawAmount,
    required this.decimals,
    required this.symbol,
    this.name,
    this.logoUrl,
    required this.lastUpdatedMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_address'] = Variable<String>(ownerAddress);
    map['mint_address'] = Variable<String>(mintAddress);
    map['raw_amount'] = Variable<String>(rawAmount);
    map['decimals'] = Variable<int>(decimals);
    map['symbol'] = Variable<String>(symbol);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || logoUrl != null) {
      map['logo_url'] = Variable<String>(logoUrl);
    }
    map['last_updated_ms'] = Variable<int>(lastUpdatedMs);
    return map;
  }

  WalletBalancesCompanion toCompanion(bool nullToAbsent) {
    return WalletBalancesCompanion(
      ownerAddress: Value(ownerAddress),
      mintAddress: Value(mintAddress),
      rawAmount: Value(rawAmount),
      decimals: Value(decimals),
      symbol: Value(symbol),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      logoUrl: logoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(logoUrl),
      lastUpdatedMs: Value(lastUpdatedMs),
    );
  }

  factory WalletBalance.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WalletBalance(
      ownerAddress: serializer.fromJson<String>(json['ownerAddress']),
      mintAddress: serializer.fromJson<String>(json['mintAddress']),
      rawAmount: serializer.fromJson<String>(json['rawAmount']),
      decimals: serializer.fromJson<int>(json['decimals']),
      symbol: serializer.fromJson<String>(json['symbol']),
      name: serializer.fromJson<String?>(json['name']),
      logoUrl: serializer.fromJson<String?>(json['logoUrl']),
      lastUpdatedMs: serializer.fromJson<int>(json['lastUpdatedMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerAddress': serializer.toJson<String>(ownerAddress),
      'mintAddress': serializer.toJson<String>(mintAddress),
      'rawAmount': serializer.toJson<String>(rawAmount),
      'decimals': serializer.toJson<int>(decimals),
      'symbol': serializer.toJson<String>(symbol),
      'name': serializer.toJson<String?>(name),
      'logoUrl': serializer.toJson<String?>(logoUrl),
      'lastUpdatedMs': serializer.toJson<int>(lastUpdatedMs),
    };
  }

  WalletBalance copyWith({
    String? ownerAddress,
    String? mintAddress,
    String? rawAmount,
    int? decimals,
    String? symbol,
    Value<String?> name = const Value.absent(),
    Value<String?> logoUrl = const Value.absent(),
    int? lastUpdatedMs,
  }) => WalletBalance(
    ownerAddress: ownerAddress ?? this.ownerAddress,
    mintAddress: mintAddress ?? this.mintAddress,
    rawAmount: rawAmount ?? this.rawAmount,
    decimals: decimals ?? this.decimals,
    symbol: symbol ?? this.symbol,
    name: name.present ? name.value : this.name,
    logoUrl: logoUrl.present ? logoUrl.value : this.logoUrl,
    lastUpdatedMs: lastUpdatedMs ?? this.lastUpdatedMs,
  );
  WalletBalance copyWithCompanion(WalletBalancesCompanion data) {
    return WalletBalance(
      ownerAddress: data.ownerAddress.present
          ? data.ownerAddress.value
          : this.ownerAddress,
      mintAddress: data.mintAddress.present
          ? data.mintAddress.value
          : this.mintAddress,
      rawAmount: data.rawAmount.present ? data.rawAmount.value : this.rawAmount,
      decimals: data.decimals.present ? data.decimals.value : this.decimals,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      name: data.name.present ? data.name.value : this.name,
      logoUrl: data.logoUrl.present ? data.logoUrl.value : this.logoUrl,
      lastUpdatedMs: data.lastUpdatedMs.present
          ? data.lastUpdatedMs.value
          : this.lastUpdatedMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WalletBalance(')
          ..write('ownerAddress: $ownerAddress, ')
          ..write('mintAddress: $mintAddress, ')
          ..write('rawAmount: $rawAmount, ')
          ..write('decimals: $decimals, ')
          ..write('symbol: $symbol, ')
          ..write('name: $name, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('lastUpdatedMs: $lastUpdatedMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerAddress,
    mintAddress,
    rawAmount,
    decimals,
    symbol,
    name,
    logoUrl,
    lastUpdatedMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WalletBalance &&
          other.ownerAddress == this.ownerAddress &&
          other.mintAddress == this.mintAddress &&
          other.rawAmount == this.rawAmount &&
          other.decimals == this.decimals &&
          other.symbol == this.symbol &&
          other.name == this.name &&
          other.logoUrl == this.logoUrl &&
          other.lastUpdatedMs == this.lastUpdatedMs);
}

class WalletBalancesCompanion extends UpdateCompanion<WalletBalance> {
  final Value<String> ownerAddress;
  final Value<String> mintAddress;
  final Value<String> rawAmount;
  final Value<int> decimals;
  final Value<String> symbol;
  final Value<String?> name;
  final Value<String?> logoUrl;
  final Value<int> lastUpdatedMs;
  final Value<int> rowid;
  const WalletBalancesCompanion({
    this.ownerAddress = const Value.absent(),
    this.mintAddress = const Value.absent(),
    this.rawAmount = const Value.absent(),
    this.decimals = const Value.absent(),
    this.symbol = const Value.absent(),
    this.name = const Value.absent(),
    this.logoUrl = const Value.absent(),
    this.lastUpdatedMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WalletBalancesCompanion.insert({
    required String ownerAddress,
    required String mintAddress,
    required String rawAmount,
    required int decimals,
    required String symbol,
    this.name = const Value.absent(),
    this.logoUrl = const Value.absent(),
    required int lastUpdatedMs,
    this.rowid = const Value.absent(),
  }) : ownerAddress = Value(ownerAddress),
       mintAddress = Value(mintAddress),
       rawAmount = Value(rawAmount),
       decimals = Value(decimals),
       symbol = Value(symbol),
       lastUpdatedMs = Value(lastUpdatedMs);
  static Insertable<WalletBalance> custom({
    Expression<String>? ownerAddress,
    Expression<String>? mintAddress,
    Expression<String>? rawAmount,
    Expression<int>? decimals,
    Expression<String>? symbol,
    Expression<String>? name,
    Expression<String>? logoUrl,
    Expression<int>? lastUpdatedMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerAddress != null) 'owner_address': ownerAddress,
      if (mintAddress != null) 'mint_address': mintAddress,
      if (rawAmount != null) 'raw_amount': rawAmount,
      if (decimals != null) 'decimals': decimals,
      if (symbol != null) 'symbol': symbol,
      if (name != null) 'name': name,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (lastUpdatedMs != null) 'last_updated_ms': lastUpdatedMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WalletBalancesCompanion copyWith({
    Value<String>? ownerAddress,
    Value<String>? mintAddress,
    Value<String>? rawAmount,
    Value<int>? decimals,
    Value<String>? symbol,
    Value<String?>? name,
    Value<String?>? logoUrl,
    Value<int>? lastUpdatedMs,
    Value<int>? rowid,
  }) {
    return WalletBalancesCompanion(
      ownerAddress: ownerAddress ?? this.ownerAddress,
      mintAddress: mintAddress ?? this.mintAddress,
      rawAmount: rawAmount ?? this.rawAmount,
      decimals: decimals ?? this.decimals,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      lastUpdatedMs: lastUpdatedMs ?? this.lastUpdatedMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerAddress.present) {
      map['owner_address'] = Variable<String>(ownerAddress.value);
    }
    if (mintAddress.present) {
      map['mint_address'] = Variable<String>(mintAddress.value);
    }
    if (rawAmount.present) {
      map['raw_amount'] = Variable<String>(rawAmount.value);
    }
    if (decimals.present) {
      map['decimals'] = Variable<int>(decimals.value);
    }
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (logoUrl.present) {
      map['logo_url'] = Variable<String>(logoUrl.value);
    }
    if (lastUpdatedMs.present) {
      map['last_updated_ms'] = Variable<int>(lastUpdatedMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WalletBalancesCompanion(')
          ..write('ownerAddress: $ownerAddress, ')
          ..write('mintAddress: $mintAddress, ')
          ..write('rawAmount: $rawAmount, ')
          ..write('decimals: $decimals, ')
          ..write('symbol: $symbol, ')
          ..write('name: $name, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('lastUpdatedMs: $lastUpdatedMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WalletTxCacheTable extends WalletTxCache
    with TableInfo<$WalletTxCacheTable, WalletTxCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WalletTxCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
    'signature',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerAddressMeta = const VerificationMeta(
    'ownerAddress',
  );
  @override
  late final GeneratedColumn<String> ownerAddress = GeneratedColumn<String>(
    'owner_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _amountLamportsMeta = const VerificationMeta(
    'amountLamports',
  );
  @override
  late final GeneratedColumn<String> amountLamports = GeneratedColumn<String>(
    'amount_lamports',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _counterpartyMeta = const VerificationMeta(
    'counterparty',
  );
  @override
  late final GeneratedColumn<String> counterparty = GeneratedColumn<String>(
    'counterparty',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tokenMintMeta = const VerificationMeta(
    'tokenMint',
  );
  @override
  late final GeneratedColumn<String> tokenMint = GeneratedColumn<String>(
    'token_mint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _feeLamportsMeta = const VerificationMeta(
    'feeLamports',
  );
  @override
  late final GeneratedColumn<String> feeLamports = GeneratedColumn<String>(
    'fee_lamports',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _blockTimeMeta = const VerificationMeta(
    'blockTime',
  );
  @override
  late final GeneratedColumn<int> blockTime = GeneratedColumn<int>(
    'block_time',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parserVersionMeta = const VerificationMeta(
    'parserVersion',
  );
  @override
  late final GeneratedColumn<int> parserVersion = GeneratedColumn<int>(
    'parser_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _cachedAtMsMeta = const VerificationMeta(
    'cachedAtMs',
  );
  @override
  late final GeneratedColumn<int> cachedAtMs = GeneratedColumn<int>(
    'cached_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    signature,
    ownerAddress,
    type,
    amountLamports,
    counterparty,
    tokenMint,
    feeLamports,
    blockTime,
    parserVersion,
    cachedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallet_tx_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<WalletTxCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
      );
    } else if (isInserting) {
      context.missing(_signatureMeta);
    }
    if (data.containsKey('owner_address')) {
      context.handle(
        _ownerAddressMeta,
        ownerAddress.isAcceptableOrUnknown(
          data['owner_address']!,
          _ownerAddressMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerAddressMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount_lamports')) {
      context.handle(
        _amountLamportsMeta,
        amountLamports.isAcceptableOrUnknown(
          data['amount_lamports']!,
          _amountLamportsMeta,
        ),
      );
    }
    if (data.containsKey('counterparty')) {
      context.handle(
        _counterpartyMeta,
        counterparty.isAcceptableOrUnknown(
          data['counterparty']!,
          _counterpartyMeta,
        ),
      );
    }
    if (data.containsKey('token_mint')) {
      context.handle(
        _tokenMintMeta,
        tokenMint.isAcceptableOrUnknown(data['token_mint']!, _tokenMintMeta),
      );
    }
    if (data.containsKey('fee_lamports')) {
      context.handle(
        _feeLamportsMeta,
        feeLamports.isAcceptableOrUnknown(
          data['fee_lamports']!,
          _feeLamportsMeta,
        ),
      );
    }
    if (data.containsKey('block_time')) {
      context.handle(
        _blockTimeMeta,
        blockTime.isAcceptableOrUnknown(data['block_time']!, _blockTimeMeta),
      );
    }
    if (data.containsKey('parser_version')) {
      context.handle(
        _parserVersionMeta,
        parserVersion.isAcceptableOrUnknown(
          data['parser_version']!,
          _parserVersionMeta,
        ),
      );
    }
    if (data.containsKey('cached_at_ms')) {
      context.handle(
        _cachedAtMsMeta,
        cachedAtMs.isAcceptableOrUnknown(
          data['cached_at_ms']!,
          _cachedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {signature, ownerAddress};
  @override
  WalletTxCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WalletTxCacheData(
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature'],
      )!,
      ownerAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_address'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      amountLamports: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount_lamports'],
      ),
      counterparty: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counterparty'],
      ),
      tokenMint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_mint'],
      ),
      feeLamports: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fee_lamports'],
      ),
      blockTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}block_time'],
      ),
      parserVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parser_version'],
      )!,
      cachedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_at_ms'],
      )!,
    );
  }

  @override
  $WalletTxCacheTable createAlias(String alias) {
    return $WalletTxCacheTable(attachedDatabase, alias);
  }
}

class WalletTxCacheData extends DataClass
    implements Insertable<WalletTxCacheData> {
  final String signature;
  final String ownerAddress;

  /// ParsedTxType.name (solSend / solReceive / splSend / splReceive / unknown)
  final String type;

  /// BigInt as string (lamports for SOL, raw smallest unit for SPL)
  final String? amountLamports;
  final String? counterparty;
  final String? tokenMint;
  final String? feeLamports;
  final int? blockTime;
  final int parserVersion;
  final int cachedAtMs;
  const WalletTxCacheData({
    required this.signature,
    required this.ownerAddress,
    required this.type,
    this.amountLamports,
    this.counterparty,
    this.tokenMint,
    this.feeLamports,
    this.blockTime,
    required this.parserVersion,
    required this.cachedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['signature'] = Variable<String>(signature);
    map['owner_address'] = Variable<String>(ownerAddress);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || amountLamports != null) {
      map['amount_lamports'] = Variable<String>(amountLamports);
    }
    if (!nullToAbsent || counterparty != null) {
      map['counterparty'] = Variable<String>(counterparty);
    }
    if (!nullToAbsent || tokenMint != null) {
      map['token_mint'] = Variable<String>(tokenMint);
    }
    if (!nullToAbsent || feeLamports != null) {
      map['fee_lamports'] = Variable<String>(feeLamports);
    }
    if (!nullToAbsent || blockTime != null) {
      map['block_time'] = Variable<int>(blockTime);
    }
    map['parser_version'] = Variable<int>(parserVersion);
    map['cached_at_ms'] = Variable<int>(cachedAtMs);
    return map;
  }

  WalletTxCacheCompanion toCompanion(bool nullToAbsent) {
    return WalletTxCacheCompanion(
      signature: Value(signature),
      ownerAddress: Value(ownerAddress),
      type: Value(type),
      amountLamports: amountLamports == null && nullToAbsent
          ? const Value.absent()
          : Value(amountLamports),
      counterparty: counterparty == null && nullToAbsent
          ? const Value.absent()
          : Value(counterparty),
      tokenMint: tokenMint == null && nullToAbsent
          ? const Value.absent()
          : Value(tokenMint),
      feeLamports: feeLamports == null && nullToAbsent
          ? const Value.absent()
          : Value(feeLamports),
      blockTime: blockTime == null && nullToAbsent
          ? const Value.absent()
          : Value(blockTime),
      parserVersion: Value(parserVersion),
      cachedAtMs: Value(cachedAtMs),
    );
  }

  factory WalletTxCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WalletTxCacheData(
      signature: serializer.fromJson<String>(json['signature']),
      ownerAddress: serializer.fromJson<String>(json['ownerAddress']),
      type: serializer.fromJson<String>(json['type']),
      amountLamports: serializer.fromJson<String?>(json['amountLamports']),
      counterparty: serializer.fromJson<String?>(json['counterparty']),
      tokenMint: serializer.fromJson<String?>(json['tokenMint']),
      feeLamports: serializer.fromJson<String?>(json['feeLamports']),
      blockTime: serializer.fromJson<int?>(json['blockTime']),
      parserVersion: serializer.fromJson<int>(json['parserVersion']),
      cachedAtMs: serializer.fromJson<int>(json['cachedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'signature': serializer.toJson<String>(signature),
      'ownerAddress': serializer.toJson<String>(ownerAddress),
      'type': serializer.toJson<String>(type),
      'amountLamports': serializer.toJson<String?>(amountLamports),
      'counterparty': serializer.toJson<String?>(counterparty),
      'tokenMint': serializer.toJson<String?>(tokenMint),
      'feeLamports': serializer.toJson<String?>(feeLamports),
      'blockTime': serializer.toJson<int?>(blockTime),
      'parserVersion': serializer.toJson<int>(parserVersion),
      'cachedAtMs': serializer.toJson<int>(cachedAtMs),
    };
  }

  WalletTxCacheData copyWith({
    String? signature,
    String? ownerAddress,
    String? type,
    Value<String?> amountLamports = const Value.absent(),
    Value<String?> counterparty = const Value.absent(),
    Value<String?> tokenMint = const Value.absent(),
    Value<String?> feeLamports = const Value.absent(),
    Value<int?> blockTime = const Value.absent(),
    int? parserVersion,
    int? cachedAtMs,
  }) => WalletTxCacheData(
    signature: signature ?? this.signature,
    ownerAddress: ownerAddress ?? this.ownerAddress,
    type: type ?? this.type,
    amountLamports: amountLamports.present
        ? amountLamports.value
        : this.amountLamports,
    counterparty: counterparty.present ? counterparty.value : this.counterparty,
    tokenMint: tokenMint.present ? tokenMint.value : this.tokenMint,
    feeLamports: feeLamports.present ? feeLamports.value : this.feeLamports,
    blockTime: blockTime.present ? blockTime.value : this.blockTime,
    parserVersion: parserVersion ?? this.parserVersion,
    cachedAtMs: cachedAtMs ?? this.cachedAtMs,
  );
  WalletTxCacheData copyWithCompanion(WalletTxCacheCompanion data) {
    return WalletTxCacheData(
      signature: data.signature.present ? data.signature.value : this.signature,
      ownerAddress: data.ownerAddress.present
          ? data.ownerAddress.value
          : this.ownerAddress,
      type: data.type.present ? data.type.value : this.type,
      amountLamports: data.amountLamports.present
          ? data.amountLamports.value
          : this.amountLamports,
      counterparty: data.counterparty.present
          ? data.counterparty.value
          : this.counterparty,
      tokenMint: data.tokenMint.present ? data.tokenMint.value : this.tokenMint,
      feeLamports: data.feeLamports.present
          ? data.feeLamports.value
          : this.feeLamports,
      blockTime: data.blockTime.present ? data.blockTime.value : this.blockTime,
      parserVersion: data.parserVersion.present
          ? data.parserVersion.value
          : this.parserVersion,
      cachedAtMs: data.cachedAtMs.present
          ? data.cachedAtMs.value
          : this.cachedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WalletTxCacheData(')
          ..write('signature: $signature, ')
          ..write('ownerAddress: $ownerAddress, ')
          ..write('type: $type, ')
          ..write('amountLamports: $amountLamports, ')
          ..write('counterparty: $counterparty, ')
          ..write('tokenMint: $tokenMint, ')
          ..write('feeLamports: $feeLamports, ')
          ..write('blockTime: $blockTime, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('cachedAtMs: $cachedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    signature,
    ownerAddress,
    type,
    amountLamports,
    counterparty,
    tokenMint,
    feeLamports,
    blockTime,
    parserVersion,
    cachedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WalletTxCacheData &&
          other.signature == this.signature &&
          other.ownerAddress == this.ownerAddress &&
          other.type == this.type &&
          other.amountLamports == this.amountLamports &&
          other.counterparty == this.counterparty &&
          other.tokenMint == this.tokenMint &&
          other.feeLamports == this.feeLamports &&
          other.blockTime == this.blockTime &&
          other.parserVersion == this.parserVersion &&
          other.cachedAtMs == this.cachedAtMs);
}

class WalletTxCacheCompanion extends UpdateCompanion<WalletTxCacheData> {
  final Value<String> signature;
  final Value<String> ownerAddress;
  final Value<String> type;
  final Value<String?> amountLamports;
  final Value<String?> counterparty;
  final Value<String?> tokenMint;
  final Value<String?> feeLamports;
  final Value<int?> blockTime;
  final Value<int> parserVersion;
  final Value<int> cachedAtMs;
  final Value<int> rowid;
  const WalletTxCacheCompanion({
    this.signature = const Value.absent(),
    this.ownerAddress = const Value.absent(),
    this.type = const Value.absent(),
    this.amountLamports = const Value.absent(),
    this.counterparty = const Value.absent(),
    this.tokenMint = const Value.absent(),
    this.feeLamports = const Value.absent(),
    this.blockTime = const Value.absent(),
    this.parserVersion = const Value.absent(),
    this.cachedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WalletTxCacheCompanion.insert({
    required String signature,
    required String ownerAddress,
    required String type,
    this.amountLamports = const Value.absent(),
    this.counterparty = const Value.absent(),
    this.tokenMint = const Value.absent(),
    this.feeLamports = const Value.absent(),
    this.blockTime = const Value.absent(),
    this.parserVersion = const Value.absent(),
    required int cachedAtMs,
    this.rowid = const Value.absent(),
  }) : signature = Value(signature),
       ownerAddress = Value(ownerAddress),
       type = Value(type),
       cachedAtMs = Value(cachedAtMs);
  static Insertable<WalletTxCacheData> custom({
    Expression<String>? signature,
    Expression<String>? ownerAddress,
    Expression<String>? type,
    Expression<String>? amountLamports,
    Expression<String>? counterparty,
    Expression<String>? tokenMint,
    Expression<String>? feeLamports,
    Expression<int>? blockTime,
    Expression<int>? parserVersion,
    Expression<int>? cachedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (signature != null) 'signature': signature,
      if (ownerAddress != null) 'owner_address': ownerAddress,
      if (type != null) 'type': type,
      if (amountLamports != null) 'amount_lamports': amountLamports,
      if (counterparty != null) 'counterparty': counterparty,
      if (tokenMint != null) 'token_mint': tokenMint,
      if (feeLamports != null) 'fee_lamports': feeLamports,
      if (blockTime != null) 'block_time': blockTime,
      if (parserVersion != null) 'parser_version': parserVersion,
      if (cachedAtMs != null) 'cached_at_ms': cachedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WalletTxCacheCompanion copyWith({
    Value<String>? signature,
    Value<String>? ownerAddress,
    Value<String>? type,
    Value<String?>? amountLamports,
    Value<String?>? counterparty,
    Value<String?>? tokenMint,
    Value<String?>? feeLamports,
    Value<int?>? blockTime,
    Value<int>? parserVersion,
    Value<int>? cachedAtMs,
    Value<int>? rowid,
  }) {
    return WalletTxCacheCompanion(
      signature: signature ?? this.signature,
      ownerAddress: ownerAddress ?? this.ownerAddress,
      type: type ?? this.type,
      amountLamports: amountLamports ?? this.amountLamports,
      counterparty: counterparty ?? this.counterparty,
      tokenMint: tokenMint ?? this.tokenMint,
      feeLamports: feeLamports ?? this.feeLamports,
      blockTime: blockTime ?? this.blockTime,
      parserVersion: parserVersion ?? this.parserVersion,
      cachedAtMs: cachedAtMs ?? this.cachedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    if (ownerAddress.present) {
      map['owner_address'] = Variable<String>(ownerAddress.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amountLamports.present) {
      map['amount_lamports'] = Variable<String>(amountLamports.value);
    }
    if (counterparty.present) {
      map['counterparty'] = Variable<String>(counterparty.value);
    }
    if (tokenMint.present) {
      map['token_mint'] = Variable<String>(tokenMint.value);
    }
    if (feeLamports.present) {
      map['fee_lamports'] = Variable<String>(feeLamports.value);
    }
    if (blockTime.present) {
      map['block_time'] = Variable<int>(blockTime.value);
    }
    if (parserVersion.present) {
      map['parser_version'] = Variable<int>(parserVersion.value);
    }
    if (cachedAtMs.present) {
      map['cached_at_ms'] = Variable<int>(cachedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WalletTxCacheCompanion(')
          ..write('signature: $signature, ')
          ..write('ownerAddress: $ownerAddress, ')
          ..write('type: $type, ')
          ..write('amountLamports: $amountLamports, ')
          ..write('counterparty: $counterparty, ')
          ..write('tokenMint: $tokenMint, ')
          ..write('feeLamports: $feeLamports, ')
          ..write('blockTime: $blockTime, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('cachedAtMs: $cachedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WalletAddressBookTable extends WalletAddressBook
    with TableInfo<$WalletAddressBookTable, WalletAddressBookData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WalletAddressBookTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _ownerAddressMeta = const VerificationMeta(
    'ownerAddress',
  );
  @override
  late final GeneratedColumn<String> ownerAddress = GeneratedColumn<String>(
    'owner_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('mainnet'),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedMsMeta = const VerificationMeta(
    'lastUsedMs',
  );
  @override
  late final GeneratedColumn<int> lastUsedMs = GeneratedColumn<int>(
    'last_used_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerAddress,
    label,
    address,
    network,
    note,
    createdAtMs,
    lastUsedMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallet_address_book';
  @override
  VerificationContext validateIntegrity(
    Insertable<WalletAddressBookData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('owner_address')) {
      context.handle(
        _ownerAddressMeta,
        ownerAddress.isAcceptableOrUnknown(
          data['owner_address']!,
          _ownerAddressMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerAddressMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('last_used_ms')) {
      context.handle(
        _lastUsedMsMeta,
        lastUsedMs.isAcceptableOrUnknown(
          data['last_used_ms']!,
          _lastUsedMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerAddress, address},
  ];
  @override
  WalletAddressBookData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WalletAddressBookData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      ownerAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_address'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      lastUsedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_used_ms'],
      ),
    );
  }

  @override
  $WalletAddressBookTable createAlias(String alias) {
    return $WalletAddressBookTable(attachedDatabase, alias);
  }
}

class WalletAddressBookData extends DataClass
    implements Insertable<WalletAddressBookData> {
  final int id;
  final String ownerAddress;
  final String label;
  final String address;
  final String network;
  final String? note;
  final int createdAtMs;
  final int? lastUsedMs;
  const WalletAddressBookData({
    required this.id,
    required this.ownerAddress,
    required this.label,
    required this.address,
    required this.network,
    this.note,
    required this.createdAtMs,
    this.lastUsedMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['owner_address'] = Variable<String>(ownerAddress);
    map['label'] = Variable<String>(label);
    map['address'] = Variable<String>(address);
    map['network'] = Variable<String>(network);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    if (!nullToAbsent || lastUsedMs != null) {
      map['last_used_ms'] = Variable<int>(lastUsedMs);
    }
    return map;
  }

  WalletAddressBookCompanion toCompanion(bool nullToAbsent) {
    return WalletAddressBookCompanion(
      id: Value(id),
      ownerAddress: Value(ownerAddress),
      label: Value(label),
      address: Value(address),
      network: Value(network),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAtMs: Value(createdAtMs),
      lastUsedMs: lastUsedMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedMs),
    );
  }

  factory WalletAddressBookData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WalletAddressBookData(
      id: serializer.fromJson<int>(json['id']),
      ownerAddress: serializer.fromJson<String>(json['ownerAddress']),
      label: serializer.fromJson<String>(json['label']),
      address: serializer.fromJson<String>(json['address']),
      network: serializer.fromJson<String>(json['network']),
      note: serializer.fromJson<String?>(json['note']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      lastUsedMs: serializer.fromJson<int?>(json['lastUsedMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ownerAddress': serializer.toJson<String>(ownerAddress),
      'label': serializer.toJson<String>(label),
      'address': serializer.toJson<String>(address),
      'network': serializer.toJson<String>(network),
      'note': serializer.toJson<String?>(note),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'lastUsedMs': serializer.toJson<int?>(lastUsedMs),
    };
  }

  WalletAddressBookData copyWith({
    int? id,
    String? ownerAddress,
    String? label,
    String? address,
    String? network,
    Value<String?> note = const Value.absent(),
    int? createdAtMs,
    Value<int?> lastUsedMs = const Value.absent(),
  }) => WalletAddressBookData(
    id: id ?? this.id,
    ownerAddress: ownerAddress ?? this.ownerAddress,
    label: label ?? this.label,
    address: address ?? this.address,
    network: network ?? this.network,
    note: note.present ? note.value : this.note,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    lastUsedMs: lastUsedMs.present ? lastUsedMs.value : this.lastUsedMs,
  );
  WalletAddressBookData copyWithCompanion(WalletAddressBookCompanion data) {
    return WalletAddressBookData(
      id: data.id.present ? data.id.value : this.id,
      ownerAddress: data.ownerAddress.present
          ? data.ownerAddress.value
          : this.ownerAddress,
      label: data.label.present ? data.label.value : this.label,
      address: data.address.present ? data.address.value : this.address,
      network: data.network.present ? data.network.value : this.network,
      note: data.note.present ? data.note.value : this.note,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      lastUsedMs: data.lastUsedMs.present
          ? data.lastUsedMs.value
          : this.lastUsedMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WalletAddressBookData(')
          ..write('id: $id, ')
          ..write('ownerAddress: $ownerAddress, ')
          ..write('label: $label, ')
          ..write('address: $address, ')
          ..write('network: $network, ')
          ..write('note: $note, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('lastUsedMs: $lastUsedMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerAddress,
    label,
    address,
    network,
    note,
    createdAtMs,
    lastUsedMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WalletAddressBookData &&
          other.id == this.id &&
          other.ownerAddress == this.ownerAddress &&
          other.label == this.label &&
          other.address == this.address &&
          other.network == this.network &&
          other.note == this.note &&
          other.createdAtMs == this.createdAtMs &&
          other.lastUsedMs == this.lastUsedMs);
}

class WalletAddressBookCompanion
    extends UpdateCompanion<WalletAddressBookData> {
  final Value<int> id;
  final Value<String> ownerAddress;
  final Value<String> label;
  final Value<String> address;
  final Value<String> network;
  final Value<String?> note;
  final Value<int> createdAtMs;
  final Value<int?> lastUsedMs;
  const WalletAddressBookCompanion({
    this.id = const Value.absent(),
    this.ownerAddress = const Value.absent(),
    this.label = const Value.absent(),
    this.address = const Value.absent(),
    this.network = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.lastUsedMs = const Value.absent(),
  });
  WalletAddressBookCompanion.insert({
    this.id = const Value.absent(),
    required String ownerAddress,
    required String label,
    required String address,
    this.network = const Value.absent(),
    this.note = const Value.absent(),
    required int createdAtMs,
    this.lastUsedMs = const Value.absent(),
  }) : ownerAddress = Value(ownerAddress),
       label = Value(label),
       address = Value(address),
       createdAtMs = Value(createdAtMs);
  static Insertable<WalletAddressBookData> custom({
    Expression<int>? id,
    Expression<String>? ownerAddress,
    Expression<String>? label,
    Expression<String>? address,
    Expression<String>? network,
    Expression<String>? note,
    Expression<int>? createdAtMs,
    Expression<int>? lastUsedMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerAddress != null) 'owner_address': ownerAddress,
      if (label != null) 'label': label,
      if (address != null) 'address': address,
      if (network != null) 'network': network,
      if (note != null) 'note': note,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (lastUsedMs != null) 'last_used_ms': lastUsedMs,
    });
  }

  WalletAddressBookCompanion copyWith({
    Value<int>? id,
    Value<String>? ownerAddress,
    Value<String>? label,
    Value<String>? address,
    Value<String>? network,
    Value<String?>? note,
    Value<int>? createdAtMs,
    Value<int?>? lastUsedMs,
  }) {
    return WalletAddressBookCompanion(
      id: id ?? this.id,
      ownerAddress: ownerAddress ?? this.ownerAddress,
      label: label ?? this.label,
      address: address ?? this.address,
      network: network ?? this.network,
      note: note ?? this.note,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      lastUsedMs: lastUsedMs ?? this.lastUsedMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ownerAddress.present) {
      map['owner_address'] = Variable<String>(ownerAddress.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (lastUsedMs.present) {
      map['last_used_ms'] = Variable<int>(lastUsedMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WalletAddressBookCompanion(')
          ..write('id: $id, ')
          ..write('ownerAddress: $ownerAddress, ')
          ..write('label: $label, ')
          ..write('address: $address, ')
          ..write('network: $network, ')
          ..write('note: $note, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('lastUsedMs: $lastUsedMs')
          ..write(')'))
        .toString();
  }
}

class $AiMessagesTable extends AiMessages
    with TableInfo<$AiMessagesTable, AiMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
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
    requiredDuringInsert: false,
    defaultValue: const Constant('default'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    role,
    content,
    sessionId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
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
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AiMessagesTable createAlias(String alias) {
    return $AiMessagesTable(attachedDatabase, alias);
  }
}

class AiMessage extends DataClass implements Insertable<AiMessage> {
  /// UUID
  final String id;

  /// 'user' 또는 'assistant'
  final String role;

  /// 메시지 텍스트
  final String content;

  /// 세션 ID (대화 구분용)
  final String sessionId;

  /// 생성 시각
  final DateTime createdAt;
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.sessionId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    map['session_id'] = Variable<String>(sessionId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AiMessagesCompanion toCompanion(bool nullToAbsent) {
    return AiMessagesCompanion(
      id: Value(id),
      role: Value(role),
      content: Value(content),
      sessionId: Value(sessionId),
      createdAt: Value(createdAt),
    );
  }

  factory AiMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiMessage(
      id: serializer.fromJson<String>(json['id']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'sessionId': serializer.toJson<String>(sessionId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AiMessage copyWith({
    String? id,
    String? role,
    String? content,
    String? sessionId,
    DateTime? createdAt,
  }) => AiMessage(
    id: id ?? this.id,
    role: role ?? this.role,
    content: content ?? this.content,
    sessionId: sessionId ?? this.sessionId,
    createdAt: createdAt ?? this.createdAt,
  );
  AiMessage copyWithCompanion(AiMessagesCompanion data) {
    return AiMessage(
      id: data.id.present ? data.id.value : this.id,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiMessage(')
          ..write('id: $id, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('sessionId: $sessionId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, role, content, sessionId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiMessage &&
          other.id == this.id &&
          other.role == this.role &&
          other.content == this.content &&
          other.sessionId == this.sessionId &&
          other.createdAt == this.createdAt);
}

class AiMessagesCompanion extends UpdateCompanion<AiMessage> {
  final Value<String> id;
  final Value<String> role;
  final Value<String> content;
  final Value<String> sessionId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AiMessagesCompanion({
    this.id = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiMessagesCompanion.insert({
    required String id,
    required String role,
    required String content,
    this.sessionId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       role = Value(role),
       content = Value(content);
  static Insertable<AiMessage> custom({
    Expression<String>? id,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? sessionId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (sessionId != null) 'session_id': sessionId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? role,
    Value<String>? content,
    Value<String>? sessionId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AiMessagesCompanion(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiMessagesCompanion(')
          ..write('id: $id, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('sessionId: $sessionId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IdentityVerificationsTable extends IdentityVerifications
    with TableInfo<$IdentityVerificationsTable, IdentityVerification> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IdentityVerificationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerSnowchatIdMeta = const VerificationMeta(
    'peerSnowchatId',
  );
  @override
  late final GeneratedColumn<String> peerSnowchatId = GeneratedColumn<String>(
    'peer_snowchat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinnedEd25519Meta = const VerificationMeta(
    'pinnedEd25519',
  );
  @override
  late final GeneratedColumn<String> pinnedEd25519 = GeneratedColumn<String>(
    'pinned_ed25519',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _safetyNumberMeta = const VerificationMeta(
    'safetyNumber',
  );
  @override
  late final GeneratedColumn<String> safetyNumber = GeneratedColumn<String>(
    'safety_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verifiedMeta = const VerificationMeta(
    'verified',
  );
  @override
  late final GeneratedColumn<bool> verified = GeneratedColumn<bool>(
    'verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("verified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _verifiedAtMeta = const VerificationMeta(
    'verifiedAt',
  );
  @override
  late final GeneratedColumn<int> verifiedAt = GeneratedColumn<int>(
    'verified_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastChangedAtMeta = const VerificationMeta(
    'lastChangedAt',
  );
  @override
  late final GeneratedColumn<int> lastChangedAt = GeneratedColumn<int>(
    'last_changed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wasPreviouslyVerifiedMeta =
      const VerificationMeta('wasPreviouslyVerified');
  @override
  late final GeneratedColumn<bool> wasPreviouslyVerified =
      GeneratedColumn<bool>(
        'was_previously_verified',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("was_previously_verified" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _algorithmVersionMeta = const VerificationMeta(
    'algorithmVersion',
  );
  @override
  late final GeneratedColumn<int> algorithmVersion = GeneratedColumn<int>(
    'algorithm_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  @override
  List<GeneratedColumn> get $columns => [
    peerSnowchatId,
    pinnedEd25519,
    safetyNumber,
    verified,
    verifiedAt,
    lastChangedAt,
    wasPreviouslyVerified,
    algorithmVersion,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'identity_verifications';
  @override
  VerificationContext validateIntegrity(
    Insertable<IdentityVerification> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_snowchat_id')) {
      context.handle(
        _peerSnowchatIdMeta,
        peerSnowchatId.isAcceptableOrUnknown(
          data['peer_snowchat_id']!,
          _peerSnowchatIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerSnowchatIdMeta);
    }
    if (data.containsKey('pinned_ed25519')) {
      context.handle(
        _pinnedEd25519Meta,
        pinnedEd25519.isAcceptableOrUnknown(
          data['pinned_ed25519']!,
          _pinnedEd25519Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pinnedEd25519Meta);
    }
    if (data.containsKey('safety_number')) {
      context.handle(
        _safetyNumberMeta,
        safetyNumber.isAcceptableOrUnknown(
          data['safety_number']!,
          _safetyNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_safetyNumberMeta);
    }
    if (data.containsKey('verified')) {
      context.handle(
        _verifiedMeta,
        verified.isAcceptableOrUnknown(data['verified']!, _verifiedMeta),
      );
    }
    if (data.containsKey('verified_at')) {
      context.handle(
        _verifiedAtMeta,
        verifiedAt.isAcceptableOrUnknown(data['verified_at']!, _verifiedAtMeta),
      );
    }
    if (data.containsKey('last_changed_at')) {
      context.handle(
        _lastChangedAtMeta,
        lastChangedAt.isAcceptableOrUnknown(
          data['last_changed_at']!,
          _lastChangedAtMeta,
        ),
      );
    }
    if (data.containsKey('was_previously_verified')) {
      context.handle(
        _wasPreviouslyVerifiedMeta,
        wasPreviouslyVerified.isAcceptableOrUnknown(
          data['was_previously_verified']!,
          _wasPreviouslyVerifiedMeta,
        ),
      );
    }
    if (data.containsKey('algorithm_version')) {
      context.handle(
        _algorithmVersionMeta,
        algorithmVersion.isAcceptableOrUnknown(
          data['algorithm_version']!,
          _algorithmVersionMeta,
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerSnowchatId};
  @override
  IdentityVerification map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IdentityVerification(
      peerSnowchatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_snowchat_id'],
      )!,
      pinnedEd25519: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pinned_ed25519'],
      )!,
      safetyNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}safety_number'],
      )!,
      verified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}verified'],
      )!,
      verifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}verified_at'],
      ),
      lastChangedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_changed_at'],
      ),
      wasPreviouslyVerified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}was_previously_verified'],
      )!,
      algorithmVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}algorithm_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $IdentityVerificationsTable createAlias(String alias) {
    return $IdentityVerificationsTable(attachedDatabase, alias);
  }
}

class IdentityVerification extends DataClass
    implements Insertable<IdentityVerification> {
  /// Peer SnowChat ID (snow + 32 hex). One row per peer.
  final String peerSnowchatId;

  /// Currently pinned Ed25519 identity key, base64-encoded raw bytes.
  final String pinnedEd25519;

  /// Cached 60-digit Safety Number (no spaces).
  final String safetyNumber;

  /// True iff the user has explicitly marked the current Safety Number as
  /// verified (e.g. compared in person / over a video call).
  final bool verified;

  /// Wall-clock ms-epoch of the last "Mark as Verified" action.
  final int? verifiedAt;

  /// Wall-clock ms-epoch of the last detected key-mismatch event.
  final int? lastChangedAt;

  /// Snapshot of [verified] at the moment of a detected mismatch. Drives the
  /// "previously verified" red banner vs. plain TOFU re-pin amber banner.
  final bool wasPreviouslyVerified;

  /// Safety Number algorithm version used to compute [safetyNumber].
  /// Defaults to 1 (Signal v1 5200-round SHA-512).
  final int algorithmVersion;

  /// ms-epoch of row creation.
  final int createdAt;

  /// ms-epoch of last write.
  final int updatedAt;
  const IdentityVerification({
    required this.peerSnowchatId,
    required this.pinnedEd25519,
    required this.safetyNumber,
    required this.verified,
    this.verifiedAt,
    this.lastChangedAt,
    required this.wasPreviouslyVerified,
    required this.algorithmVersion,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_snowchat_id'] = Variable<String>(peerSnowchatId);
    map['pinned_ed25519'] = Variable<String>(pinnedEd25519);
    map['safety_number'] = Variable<String>(safetyNumber);
    map['verified'] = Variable<bool>(verified);
    if (!nullToAbsent || verifiedAt != null) {
      map['verified_at'] = Variable<int>(verifiedAt);
    }
    if (!nullToAbsent || lastChangedAt != null) {
      map['last_changed_at'] = Variable<int>(lastChangedAt);
    }
    map['was_previously_verified'] = Variable<bool>(wasPreviouslyVerified);
    map['algorithm_version'] = Variable<int>(algorithmVersion);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  IdentityVerificationsCompanion toCompanion(bool nullToAbsent) {
    return IdentityVerificationsCompanion(
      peerSnowchatId: Value(peerSnowchatId),
      pinnedEd25519: Value(pinnedEd25519),
      safetyNumber: Value(safetyNumber),
      verified: Value(verified),
      verifiedAt: verifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedAt),
      lastChangedAt: lastChangedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastChangedAt),
      wasPreviouslyVerified: Value(wasPreviouslyVerified),
      algorithmVersion: Value(algorithmVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory IdentityVerification.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IdentityVerification(
      peerSnowchatId: serializer.fromJson<String>(json['peerSnowchatId']),
      pinnedEd25519: serializer.fromJson<String>(json['pinnedEd25519']),
      safetyNumber: serializer.fromJson<String>(json['safetyNumber']),
      verified: serializer.fromJson<bool>(json['verified']),
      verifiedAt: serializer.fromJson<int?>(json['verifiedAt']),
      lastChangedAt: serializer.fromJson<int?>(json['lastChangedAt']),
      wasPreviouslyVerified: serializer.fromJson<bool>(
        json['wasPreviouslyVerified'],
      ),
      algorithmVersion: serializer.fromJson<int>(json['algorithmVersion']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerSnowchatId': serializer.toJson<String>(peerSnowchatId),
      'pinnedEd25519': serializer.toJson<String>(pinnedEd25519),
      'safetyNumber': serializer.toJson<String>(safetyNumber),
      'verified': serializer.toJson<bool>(verified),
      'verifiedAt': serializer.toJson<int?>(verifiedAt),
      'lastChangedAt': serializer.toJson<int?>(lastChangedAt),
      'wasPreviouslyVerified': serializer.toJson<bool>(wasPreviouslyVerified),
      'algorithmVersion': serializer.toJson<int>(algorithmVersion),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  IdentityVerification copyWith({
    String? peerSnowchatId,
    String? pinnedEd25519,
    String? safetyNumber,
    bool? verified,
    Value<int?> verifiedAt = const Value.absent(),
    Value<int?> lastChangedAt = const Value.absent(),
    bool? wasPreviouslyVerified,
    int? algorithmVersion,
    int? createdAt,
    int? updatedAt,
  }) => IdentityVerification(
    peerSnowchatId: peerSnowchatId ?? this.peerSnowchatId,
    pinnedEd25519: pinnedEd25519 ?? this.pinnedEd25519,
    safetyNumber: safetyNumber ?? this.safetyNumber,
    verified: verified ?? this.verified,
    verifiedAt: verifiedAt.present ? verifiedAt.value : this.verifiedAt,
    lastChangedAt: lastChangedAt.present
        ? lastChangedAt.value
        : this.lastChangedAt,
    wasPreviouslyVerified: wasPreviouslyVerified ?? this.wasPreviouslyVerified,
    algorithmVersion: algorithmVersion ?? this.algorithmVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  IdentityVerification copyWithCompanion(IdentityVerificationsCompanion data) {
    return IdentityVerification(
      peerSnowchatId: data.peerSnowchatId.present
          ? data.peerSnowchatId.value
          : this.peerSnowchatId,
      pinnedEd25519: data.pinnedEd25519.present
          ? data.pinnedEd25519.value
          : this.pinnedEd25519,
      safetyNumber: data.safetyNumber.present
          ? data.safetyNumber.value
          : this.safetyNumber,
      verified: data.verified.present ? data.verified.value : this.verified,
      verifiedAt: data.verifiedAt.present
          ? data.verifiedAt.value
          : this.verifiedAt,
      lastChangedAt: data.lastChangedAt.present
          ? data.lastChangedAt.value
          : this.lastChangedAt,
      wasPreviouslyVerified: data.wasPreviouslyVerified.present
          ? data.wasPreviouslyVerified.value
          : this.wasPreviouslyVerified,
      algorithmVersion: data.algorithmVersion.present
          ? data.algorithmVersion.value
          : this.algorithmVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IdentityVerification(')
          ..write('peerSnowchatId: $peerSnowchatId, ')
          ..write('pinnedEd25519: $pinnedEd25519, ')
          ..write('safetyNumber: $safetyNumber, ')
          ..write('verified: $verified, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('lastChangedAt: $lastChangedAt, ')
          ..write('wasPreviouslyVerified: $wasPreviouslyVerified, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    peerSnowchatId,
    pinnedEd25519,
    safetyNumber,
    verified,
    verifiedAt,
    lastChangedAt,
    wasPreviouslyVerified,
    algorithmVersion,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IdentityVerification &&
          other.peerSnowchatId == this.peerSnowchatId &&
          other.pinnedEd25519 == this.pinnedEd25519 &&
          other.safetyNumber == this.safetyNumber &&
          other.verified == this.verified &&
          other.verifiedAt == this.verifiedAt &&
          other.lastChangedAt == this.lastChangedAt &&
          other.wasPreviouslyVerified == this.wasPreviouslyVerified &&
          other.algorithmVersion == this.algorithmVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class IdentityVerificationsCompanion
    extends UpdateCompanion<IdentityVerification> {
  final Value<String> peerSnowchatId;
  final Value<String> pinnedEd25519;
  final Value<String> safetyNumber;
  final Value<bool> verified;
  final Value<int?> verifiedAt;
  final Value<int?> lastChangedAt;
  final Value<bool> wasPreviouslyVerified;
  final Value<int> algorithmVersion;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const IdentityVerificationsCompanion({
    this.peerSnowchatId = const Value.absent(),
    this.pinnedEd25519 = const Value.absent(),
    this.safetyNumber = const Value.absent(),
    this.verified = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.lastChangedAt = const Value.absent(),
    this.wasPreviouslyVerified = const Value.absent(),
    this.algorithmVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IdentityVerificationsCompanion.insert({
    required String peerSnowchatId,
    required String pinnedEd25519,
    required String safetyNumber,
    this.verified = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.lastChangedAt = const Value.absent(),
    this.wasPreviouslyVerified = const Value.absent(),
    this.algorithmVersion = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : peerSnowchatId = Value(peerSnowchatId),
       pinnedEd25519 = Value(pinnedEd25519),
       safetyNumber = Value(safetyNumber),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<IdentityVerification> custom({
    Expression<String>? peerSnowchatId,
    Expression<String>? pinnedEd25519,
    Expression<String>? safetyNumber,
    Expression<bool>? verified,
    Expression<int>? verifiedAt,
    Expression<int>? lastChangedAt,
    Expression<bool>? wasPreviouslyVerified,
    Expression<int>? algorithmVersion,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerSnowchatId != null) 'peer_snowchat_id': peerSnowchatId,
      if (pinnedEd25519 != null) 'pinned_ed25519': pinnedEd25519,
      if (safetyNumber != null) 'safety_number': safetyNumber,
      if (verified != null) 'verified': verified,
      if (verifiedAt != null) 'verified_at': verifiedAt,
      if (lastChangedAt != null) 'last_changed_at': lastChangedAt,
      if (wasPreviouslyVerified != null)
        'was_previously_verified': wasPreviouslyVerified,
      if (algorithmVersion != null) 'algorithm_version': algorithmVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IdentityVerificationsCompanion copyWith({
    Value<String>? peerSnowchatId,
    Value<String>? pinnedEd25519,
    Value<String>? safetyNumber,
    Value<bool>? verified,
    Value<int?>? verifiedAt,
    Value<int?>? lastChangedAt,
    Value<bool>? wasPreviouslyVerified,
    Value<int>? algorithmVersion,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return IdentityVerificationsCompanion(
      peerSnowchatId: peerSnowchatId ?? this.peerSnowchatId,
      pinnedEd25519: pinnedEd25519 ?? this.pinnedEd25519,
      safetyNumber: safetyNumber ?? this.safetyNumber,
      verified: verified ?? this.verified,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      lastChangedAt: lastChangedAt ?? this.lastChangedAt,
      wasPreviouslyVerified:
          wasPreviouslyVerified ?? this.wasPreviouslyVerified,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerSnowchatId.present) {
      map['peer_snowchat_id'] = Variable<String>(peerSnowchatId.value);
    }
    if (pinnedEd25519.present) {
      map['pinned_ed25519'] = Variable<String>(pinnedEd25519.value);
    }
    if (safetyNumber.present) {
      map['safety_number'] = Variable<String>(safetyNumber.value);
    }
    if (verified.present) {
      map['verified'] = Variable<bool>(verified.value);
    }
    if (verifiedAt.present) {
      map['verified_at'] = Variable<int>(verifiedAt.value);
    }
    if (lastChangedAt.present) {
      map['last_changed_at'] = Variable<int>(lastChangedAt.value);
    }
    if (wasPreviouslyVerified.present) {
      map['was_previously_verified'] = Variable<bool>(
        wasPreviouslyVerified.value,
      );
    }
    if (algorithmVersion.present) {
      map['algorithm_version'] = Variable<int>(algorithmVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IdentityVerificationsCompanion(')
          ..write('peerSnowchatId: $peerSnowchatId, ')
          ..write('pinnedEd25519: $pinnedEd25519, ')
          ..write('safetyNumber: $safetyNumber, ')
          ..write('verified: $verified, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('lastChangedAt: $lastChangedAt, ')
          ..write('wasPreviouslyVerified: $wasPreviouslyVerified, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingTransfersTable extends PendingTransfers
    with TableInfo<$PendingTransfersTable, PendingTransfer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingTransfersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerSnowchatIdMeta = const VerificationMeta(
    'peerSnowchatId',
  );
  @override
  late final GeneratedColumn<String> peerSnowchatId = GeneratedColumn<String>(
    'peer_snowchat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<String> amount = GeneratedColumn<String>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenMeta = const VerificationMeta('token');
  @override
  late final GeneratedColumn<String> token = GeneratedColumn<String>(
    'token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mintMeta = const VerificationMeta('mint');
  @override
  late final GeneratedColumn<String> mint = GeneratedColumn<String>(
    'mint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _decimalsMeta = const VerificationMeta(
    'decimals',
  );
  @override
  late final GeneratedColumn<int> decimals = GeneratedColumn<int>(
    'decimals',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
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
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
    'signature',
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
  @override
  List<GeneratedColumn> get $columns => [
    requestId,
    role,
    peerSnowchatId,
    amount,
    token,
    mint,
    decimals,
    network,
    status,
    signature,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_transfers';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingTransfer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('peer_snowchat_id')) {
      context.handle(
        _peerSnowchatIdMeta,
        peerSnowchatId.isAcceptableOrUnknown(
          data['peer_snowchat_id']!,
          _peerSnowchatIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerSnowchatIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('token')) {
      context.handle(
        _tokenMeta,
        token.isAcceptableOrUnknown(data['token']!, _tokenMeta),
      );
    } else if (isInserting) {
      context.missing(_tokenMeta);
    }
    if (data.containsKey('mint')) {
      context.handle(
        _mintMeta,
        mint.isAcceptableOrUnknown(data['mint']!, _mintMeta),
      );
    }
    if (data.containsKey('decimals')) {
      context.handle(
        _decimalsMeta,
        decimals.isAcceptableOrUnknown(data['decimals']!, _decimalsMeta),
      );
    } else if (isInserting) {
      context.missing(_decimalsMeta);
    }
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    } else if (isInserting) {
      context.missing(_networkMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {requestId};
  @override
  PendingTransfer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingTransfer(
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      peerSnowchatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_snowchat_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount'],
      )!,
      token: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token'],
      )!,
      mint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mint'],
      ),
      decimals: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}decimals'],
      )!,
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PendingTransfersTable createAlias(String alias) {
    return $PendingTransfersTable(attachedDatabase, alias);
  }
}

class PendingTransfer extends DataClass implements Insertable<PendingTransfer> {
  final String requestId;
  final String role;
  final String peerSnowchatId;

  /// lamports / raw smallest units. BigInt-safe String (Float 금지).
  final String amount;
  final String token;
  final String? mint;
  final int decimals;
  final String network;

  /// pending | sent | completed | failed | timeout
  final String status;

  /// Solana tx signature — sender 가 broadcast 후 set.
  /// recoverPending() 이 RPC getSignatureStatus 조회에 사용.
  final String? signature;
  final int createdAt;
  final int updatedAt;
  const PendingTransfer({
    required this.requestId,
    required this.role,
    required this.peerSnowchatId,
    required this.amount,
    required this.token,
    this.mint,
    required this.decimals,
    required this.network,
    required this.status,
    this.signature,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['request_id'] = Variable<String>(requestId);
    map['role'] = Variable<String>(role);
    map['peer_snowchat_id'] = Variable<String>(peerSnowchatId);
    map['amount'] = Variable<String>(amount);
    map['token'] = Variable<String>(token);
    if (!nullToAbsent || mint != null) {
      map['mint'] = Variable<String>(mint);
    }
    map['decimals'] = Variable<int>(decimals);
    map['network'] = Variable<String>(network);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || signature != null) {
      map['signature'] = Variable<String>(signature);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  PendingTransfersCompanion toCompanion(bool nullToAbsent) {
    return PendingTransfersCompanion(
      requestId: Value(requestId),
      role: Value(role),
      peerSnowchatId: Value(peerSnowchatId),
      amount: Value(amount),
      token: Value(token),
      mint: mint == null && nullToAbsent ? const Value.absent() : Value(mint),
      decimals: Value(decimals),
      network: Value(network),
      status: Value(status),
      signature: signature == null && nullToAbsent
          ? const Value.absent()
          : Value(signature),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PendingTransfer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingTransfer(
      requestId: serializer.fromJson<String>(json['requestId']),
      role: serializer.fromJson<String>(json['role']),
      peerSnowchatId: serializer.fromJson<String>(json['peerSnowchatId']),
      amount: serializer.fromJson<String>(json['amount']),
      token: serializer.fromJson<String>(json['token']),
      mint: serializer.fromJson<String?>(json['mint']),
      decimals: serializer.fromJson<int>(json['decimals']),
      network: serializer.fromJson<String>(json['network']),
      status: serializer.fromJson<String>(json['status']),
      signature: serializer.fromJson<String?>(json['signature']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'requestId': serializer.toJson<String>(requestId),
      'role': serializer.toJson<String>(role),
      'peerSnowchatId': serializer.toJson<String>(peerSnowchatId),
      'amount': serializer.toJson<String>(amount),
      'token': serializer.toJson<String>(token),
      'mint': serializer.toJson<String?>(mint),
      'decimals': serializer.toJson<int>(decimals),
      'network': serializer.toJson<String>(network),
      'status': serializer.toJson<String>(status),
      'signature': serializer.toJson<String?>(signature),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  PendingTransfer copyWith({
    String? requestId,
    String? role,
    String? peerSnowchatId,
    String? amount,
    String? token,
    Value<String?> mint = const Value.absent(),
    int? decimals,
    String? network,
    String? status,
    Value<String?> signature = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => PendingTransfer(
    requestId: requestId ?? this.requestId,
    role: role ?? this.role,
    peerSnowchatId: peerSnowchatId ?? this.peerSnowchatId,
    amount: amount ?? this.amount,
    token: token ?? this.token,
    mint: mint.present ? mint.value : this.mint,
    decimals: decimals ?? this.decimals,
    network: network ?? this.network,
    status: status ?? this.status,
    signature: signature.present ? signature.value : this.signature,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PendingTransfer copyWithCompanion(PendingTransfersCompanion data) {
    return PendingTransfer(
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      role: data.role.present ? data.role.value : this.role,
      peerSnowchatId: data.peerSnowchatId.present
          ? data.peerSnowchatId.value
          : this.peerSnowchatId,
      amount: data.amount.present ? data.amount.value : this.amount,
      token: data.token.present ? data.token.value : this.token,
      mint: data.mint.present ? data.mint.value : this.mint,
      decimals: data.decimals.present ? data.decimals.value : this.decimals,
      network: data.network.present ? data.network.value : this.network,
      status: data.status.present ? data.status.value : this.status,
      signature: data.signature.present ? data.signature.value : this.signature,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingTransfer(')
          ..write('requestId: $requestId, ')
          ..write('role: $role, ')
          ..write('peerSnowchatId: $peerSnowchatId, ')
          ..write('amount: $amount, ')
          ..write('token: $token, ')
          ..write('mint: $mint, ')
          ..write('decimals: $decimals, ')
          ..write('network: $network, ')
          ..write('status: $status, ')
          ..write('signature: $signature, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    requestId,
    role,
    peerSnowchatId,
    amount,
    token,
    mint,
    decimals,
    network,
    status,
    signature,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingTransfer &&
          other.requestId == this.requestId &&
          other.role == this.role &&
          other.peerSnowchatId == this.peerSnowchatId &&
          other.amount == this.amount &&
          other.token == this.token &&
          other.mint == this.mint &&
          other.decimals == this.decimals &&
          other.network == this.network &&
          other.status == this.status &&
          other.signature == this.signature &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PendingTransfersCompanion extends UpdateCompanion<PendingTransfer> {
  final Value<String> requestId;
  final Value<String> role;
  final Value<String> peerSnowchatId;
  final Value<String> amount;
  final Value<String> token;
  final Value<String?> mint;
  final Value<int> decimals;
  final Value<String> network;
  final Value<String> status;
  final Value<String?> signature;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const PendingTransfersCompanion({
    this.requestId = const Value.absent(),
    this.role = const Value.absent(),
    this.peerSnowchatId = const Value.absent(),
    this.amount = const Value.absent(),
    this.token = const Value.absent(),
    this.mint = const Value.absent(),
    this.decimals = const Value.absent(),
    this.network = const Value.absent(),
    this.status = const Value.absent(),
    this.signature = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingTransfersCompanion.insert({
    required String requestId,
    required String role,
    required String peerSnowchatId,
    required String amount,
    required String token,
    this.mint = const Value.absent(),
    required int decimals,
    required String network,
    required String status,
    this.signature = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : requestId = Value(requestId),
       role = Value(role),
       peerSnowchatId = Value(peerSnowchatId),
       amount = Value(amount),
       token = Value(token),
       decimals = Value(decimals),
       network = Value(network),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PendingTransfer> custom({
    Expression<String>? requestId,
    Expression<String>? role,
    Expression<String>? peerSnowchatId,
    Expression<String>? amount,
    Expression<String>? token,
    Expression<String>? mint,
    Expression<int>? decimals,
    Expression<String>? network,
    Expression<String>? status,
    Expression<String>? signature,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (requestId != null) 'request_id': requestId,
      if (role != null) 'role': role,
      if (peerSnowchatId != null) 'peer_snowchat_id': peerSnowchatId,
      if (amount != null) 'amount': amount,
      if (token != null) 'token': token,
      if (mint != null) 'mint': mint,
      if (decimals != null) 'decimals': decimals,
      if (network != null) 'network': network,
      if (status != null) 'status': status,
      if (signature != null) 'signature': signature,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingTransfersCompanion copyWith({
    Value<String>? requestId,
    Value<String>? role,
    Value<String>? peerSnowchatId,
    Value<String>? amount,
    Value<String>? token,
    Value<String?>? mint,
    Value<int>? decimals,
    Value<String>? network,
    Value<String>? status,
    Value<String?>? signature,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return PendingTransfersCompanion(
      requestId: requestId ?? this.requestId,
      role: role ?? this.role,
      peerSnowchatId: peerSnowchatId ?? this.peerSnowchatId,
      amount: amount ?? this.amount,
      token: token ?? this.token,
      mint: mint ?? this.mint,
      decimals: decimals ?? this.decimals,
      network: network ?? this.network,
      status: status ?? this.status,
      signature: signature ?? this.signature,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (peerSnowchatId.present) {
      map['peer_snowchat_id'] = Variable<String>(peerSnowchatId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<String>(amount.value);
    }
    if (token.present) {
      map['token'] = Variable<String>(token.value);
    }
    if (mint.present) {
      map['mint'] = Variable<String>(mint.value);
    }
    if (decimals.present) {
      map['decimals'] = Variable<int>(decimals.value);
    }
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingTransfersCompanion(')
          ..write('requestId: $requestId, ')
          ..write('role: $role, ')
          ..write('peerSnowchatId: $peerSnowchatId, ')
          ..write('amount: $amount, ')
          ..write('token: $token, ')
          ..write('mint: $mint, ')
          ..write('decimals: $decimals, ')
          ..write('network: $network, ')
          ..write('status: $status, ')
          ..write('signature: $signature, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SnowDatabase extends GeneratedDatabase {
  _$SnowDatabase(QueryExecutor e) : super(e);
  $SnowDatabaseManager get managers => $SnowDatabaseManager(this);
  late final $LocalMessagesTable localMessages = $LocalMessagesTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $ContactsTable contacts = $ContactsTable(this);
  late final $SignalSessionsTable signalSessions = $SignalSessionsTable(this);
  late final $SignalPreKeysTable signalPreKeys = $SignalPreKeysTable(this);
  late final $LocalAttachmentsTable localAttachments = $LocalAttachmentsTable(
    this,
  );
  late final $WalletBalancesTable walletBalances = $WalletBalancesTable(this);
  late final $WalletTxCacheTable walletTxCache = $WalletTxCacheTable(this);
  late final $WalletAddressBookTable walletAddressBook =
      $WalletAddressBookTable(this);
  late final $AiMessagesTable aiMessages = $AiMessagesTable(this);
  late final $IdentityVerificationsTable identityVerifications =
      $IdentityVerificationsTable(this);
  late final $PendingTransfersTable pendingTransfers = $PendingTransfersTable(
    this,
  );
  late final MessageDao messageDao = MessageDao(this as SnowDatabase);
  late final ConversationDao conversationDao = ConversationDao(
    this as SnowDatabase,
  );
  late final AttachmentDao attachmentDao = AttachmentDao(this as SnowDatabase);
  late final WalletBalanceDao walletBalanceDao = WalletBalanceDao(
    this as SnowDatabase,
  );
  late final WalletTxCacheDao walletTxCacheDao = WalletTxCacheDao(
    this as SnowDatabase,
  );
  late final WalletAddressBookDao walletAddressBookDao = WalletAddressBookDao(
    this as SnowDatabase,
  );
  late final AiMessageDao aiMessageDao = AiMessageDao(this as SnowDatabase);
  late final IdentityVerificationDao identityVerificationDao =
      IdentityVerificationDao(this as SnowDatabase);
  late final PendingTransferDao pendingTransferDao = PendingTransferDao(
    this as SnowDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localMessages,
    conversations,
    contacts,
    signalSessions,
    signalPreKeys,
    localAttachments,
    walletBalances,
    walletTxCache,
    walletAddressBook,
    aiMessages,
    identityVerifications,
    pendingTransfers,
  ];
}

typedef $$LocalMessagesTableCreateCompanionBuilder =
    LocalMessagesCompanion Function({
      required String id,
      required String conversationId,
      required String senderSnowchatId,
      required int dateSent,
      required int dateReceived,
      Value<int> dateServer,
      required String plaintext,
      Value<String> type,
      Value<bool> read,
      Value<String> outgoingStatus,
      Value<bool> hasDeliveryReceipt,
      Value<bool> hasReadReceipt,
      Value<bool> notified,
      Value<int> expiresIn,
      Value<int> expireStarted,
      Value<String?> metadata,
      Value<bool> remoteDeleted,
      Value<bool> mentionsSelf,
      Value<String?> replyToId,
      Value<String?> senderDisplayName,
      Value<int> rowid,
    });
typedef $$LocalMessagesTableUpdateCompanionBuilder =
    LocalMessagesCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String> senderSnowchatId,
      Value<int> dateSent,
      Value<int> dateReceived,
      Value<int> dateServer,
      Value<String> plaintext,
      Value<String> type,
      Value<bool> read,
      Value<String> outgoingStatus,
      Value<bool> hasDeliveryReceipt,
      Value<bool> hasReadReceipt,
      Value<bool> notified,
      Value<int> expiresIn,
      Value<int> expireStarted,
      Value<String?> metadata,
      Value<bool> remoteDeleted,
      Value<bool> mentionsSelf,
      Value<String?> replyToId,
      Value<String?> senderDisplayName,
      Value<int> rowid,
    });

class $$LocalMessagesTableFilterComposer
    extends Composer<_$SnowDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableFilterComposer({
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

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderSnowchatId => $composableBuilder(
    column: $table.senderSnowchatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateSent => $composableBuilder(
    column: $table.dateSent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateReceived => $composableBuilder(
    column: $table.dateReceived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateServer => $composableBuilder(
    column: $table.dateServer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plaintext => $composableBuilder(
    column: $table.plaintext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outgoingStatus => $composableBuilder(
    column: $table.outgoingStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasDeliveryReceipt => $composableBuilder(
    column: $table.hasDeliveryReceipt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasReadReceipt => $composableBuilder(
    column: $table.hasReadReceipt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get notified => $composableBuilder(
    column: $table.notified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresIn => $composableBuilder(
    column: $table.expiresIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expireStarted => $composableBuilder(
    column: $table.expireStarted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get remoteDeleted => $composableBuilder(
    column: $table.remoteDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get mentionsSelf => $composableBuilder(
    column: $table.mentionsSelf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderDisplayName => $composableBuilder(
    column: $table.senderDisplayName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalMessagesTableOrderingComposer
    extends Composer<_$SnowDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableOrderingComposer({
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

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderSnowchatId => $composableBuilder(
    column: $table.senderSnowchatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateSent => $composableBuilder(
    column: $table.dateSent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateReceived => $composableBuilder(
    column: $table.dateReceived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateServer => $composableBuilder(
    column: $table.dateServer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plaintext => $composableBuilder(
    column: $table.plaintext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outgoingStatus => $composableBuilder(
    column: $table.outgoingStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasDeliveryReceipt => $composableBuilder(
    column: $table.hasDeliveryReceipt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasReadReceipt => $composableBuilder(
    column: $table.hasReadReceipt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get notified => $composableBuilder(
    column: $table.notified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresIn => $composableBuilder(
    column: $table.expiresIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expireStarted => $composableBuilder(
    column: $table.expireStarted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get remoteDeleted => $composableBuilder(
    column: $table.remoteDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get mentionsSelf => $composableBuilder(
    column: $table.mentionsSelf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderDisplayName => $composableBuilder(
    column: $table.senderDisplayName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalMessagesTableAnnotationComposer
    extends Composer<_$SnowDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderSnowchatId => $composableBuilder(
    column: $table.senderSnowchatId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dateSent =>
      $composableBuilder(column: $table.dateSent, builder: (column) => column);

  GeneratedColumn<int> get dateReceived => $composableBuilder(
    column: $table.dateReceived,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dateServer => $composableBuilder(
    column: $table.dateServer,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plaintext =>
      $composableBuilder(column: $table.plaintext, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<bool> get read =>
      $composableBuilder(column: $table.read, builder: (column) => column);

  GeneratedColumn<String> get outgoingStatus => $composableBuilder(
    column: $table.outgoingStatus,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasDeliveryReceipt => $composableBuilder(
    column: $table.hasDeliveryReceipt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasReadReceipt => $composableBuilder(
    column: $table.hasReadReceipt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get notified =>
      $composableBuilder(column: $table.notified, builder: (column) => column);

  GeneratedColumn<int> get expiresIn =>
      $composableBuilder(column: $table.expiresIn, builder: (column) => column);

  GeneratedColumn<int> get expireStarted => $composableBuilder(
    column: $table.expireStarted,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);

  GeneratedColumn<bool> get remoteDeleted => $composableBuilder(
    column: $table.remoteDeleted,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get mentionsSelf => $composableBuilder(
    column: $table.mentionsSelf,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyToId =>
      $composableBuilder(column: $table.replyToId, builder: (column) => column);

  GeneratedColumn<String> get senderDisplayName => $composableBuilder(
    column: $table.senderDisplayName,
    builder: (column) => column,
  );
}

class $$LocalMessagesTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $LocalMessagesTable,
          LocalMessage,
          $$LocalMessagesTableFilterComposer,
          $$LocalMessagesTableOrderingComposer,
          $$LocalMessagesTableAnnotationComposer,
          $$LocalMessagesTableCreateCompanionBuilder,
          $$LocalMessagesTableUpdateCompanionBuilder,
          (
            LocalMessage,
            BaseReferences<_$SnowDatabase, $LocalMessagesTable, LocalMessage>,
          ),
          LocalMessage,
          PrefetchHooks Function()
        > {
  $$LocalMessagesTableTableManager(_$SnowDatabase db, $LocalMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> senderSnowchatId = const Value.absent(),
                Value<int> dateSent = const Value.absent(),
                Value<int> dateReceived = const Value.absent(),
                Value<int> dateServer = const Value.absent(),
                Value<String> plaintext = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<String> outgoingStatus = const Value.absent(),
                Value<bool> hasDeliveryReceipt = const Value.absent(),
                Value<bool> hasReadReceipt = const Value.absent(),
                Value<bool> notified = const Value.absent(),
                Value<int> expiresIn = const Value.absent(),
                Value<int> expireStarted = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
                Value<bool> remoteDeleted = const Value.absent(),
                Value<bool> mentionsSelf = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String?> senderDisplayName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMessagesCompanion(
                id: id,
                conversationId: conversationId,
                senderSnowchatId: senderSnowchatId,
                dateSent: dateSent,
                dateReceived: dateReceived,
                dateServer: dateServer,
                plaintext: plaintext,
                type: type,
                read: read,
                outgoingStatus: outgoingStatus,
                hasDeliveryReceipt: hasDeliveryReceipt,
                hasReadReceipt: hasReadReceipt,
                notified: notified,
                expiresIn: expiresIn,
                expireStarted: expireStarted,
                metadata: metadata,
                remoteDeleted: remoteDeleted,
                mentionsSelf: mentionsSelf,
                replyToId: replyToId,
                senderDisplayName: senderDisplayName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String senderSnowchatId,
                required int dateSent,
                required int dateReceived,
                Value<int> dateServer = const Value.absent(),
                required String plaintext,
                Value<String> type = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<String> outgoingStatus = const Value.absent(),
                Value<bool> hasDeliveryReceipt = const Value.absent(),
                Value<bool> hasReadReceipt = const Value.absent(),
                Value<bool> notified = const Value.absent(),
                Value<int> expiresIn = const Value.absent(),
                Value<int> expireStarted = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
                Value<bool> remoteDeleted = const Value.absent(),
                Value<bool> mentionsSelf = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String?> senderDisplayName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                senderSnowchatId: senderSnowchatId,
                dateSent: dateSent,
                dateReceived: dateReceived,
                dateServer: dateServer,
                plaintext: plaintext,
                type: type,
                read: read,
                outgoingStatus: outgoingStatus,
                hasDeliveryReceipt: hasDeliveryReceipt,
                hasReadReceipt: hasReadReceipt,
                notified: notified,
                expiresIn: expiresIn,
                expireStarted: expireStarted,
                metadata: metadata,
                remoteDeleted: remoteDeleted,
                mentionsSelf: mentionsSelf,
                replyToId: replyToId,
                senderDisplayName: senderDisplayName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $LocalMessagesTable,
      LocalMessage,
      $$LocalMessagesTableFilterComposer,
      $$LocalMessagesTableOrderingComposer,
      $$LocalMessagesTableAnnotationComposer,
      $$LocalMessagesTableCreateCompanionBuilder,
      $$LocalMessagesTableUpdateCompanionBuilder,
      (
        LocalMessage,
        BaseReferences<_$SnowDatabase, $LocalMessagesTable, LocalMessage>,
      ),
      LocalMessage,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String id,
      Value<String> type,
      Value<String?> title,
      required String participantIds,
      Value<String?> groupId,
      Value<String?> lastMessageText,
      Value<int?> lastMessageTime,
      Value<String?> lastMessageSenderId,
      Value<String?> lastMessageId,
      Value<int> unreadCount,
      Value<int> unreadSelfMentionCount,
      Value<bool> isRead,
      Value<int> lastSeen,
      Value<int> lastScrolled,
      Value<bool> isPinned,
      Value<int?> pinnedOrder,
      Value<bool> isMuted,
      Value<bool> isArchived,
      Value<bool> isActive,
      Value<int?> disappearingTtl,
      Value<bool> autoTranslateEnabled,
      Value<String?> autoTranslateTargetLang,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> id,
      Value<String> type,
      Value<String?> title,
      Value<String> participantIds,
      Value<String?> groupId,
      Value<String?> lastMessageText,
      Value<int?> lastMessageTime,
      Value<String?> lastMessageSenderId,
      Value<String?> lastMessageId,
      Value<int> unreadCount,
      Value<int> unreadSelfMentionCount,
      Value<bool> isRead,
      Value<int> lastSeen,
      Value<int> lastScrolled,
      Value<bool> isPinned,
      Value<int?> pinnedOrder,
      Value<bool> isMuted,
      Value<bool> isArchived,
      Value<bool> isActive,
      Value<int?> disappearingTtl,
      Value<bool> autoTranslateEnabled,
      Value<String?> autoTranslateTargetLang,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$ConversationsTableFilterComposer
    extends Composer<_$SnowDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get participantIds => $composableBuilder(
    column: $table.participantIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageText => $composableBuilder(
    column: $table.lastMessageText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastMessageTime => $composableBuilder(
    column: $table.lastMessageTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageSenderId => $composableBuilder(
    column: $table.lastMessageSenderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadSelfMentionCount => $composableBuilder(
    column: $table.unreadSelfMentionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastScrolled => $composableBuilder(
    column: $table.lastScrolled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pinnedOrder => $composableBuilder(
    column: $table.pinnedOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get disappearingTtl => $composableBuilder(
    column: $table.disappearingTtl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoTranslateEnabled => $composableBuilder(
    column: $table.autoTranslateEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get autoTranslateTargetLang => $composableBuilder(
    column: $table.autoTranslateTargetLang,
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
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$SnowDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get participantIds => $composableBuilder(
    column: $table.participantIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageText => $composableBuilder(
    column: $table.lastMessageText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageTime => $composableBuilder(
    column: $table.lastMessageTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageSenderId => $composableBuilder(
    column: $table.lastMessageSenderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadSelfMentionCount => $composableBuilder(
    column: $table.unreadSelfMentionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastScrolled => $composableBuilder(
    column: $table.lastScrolled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pinnedOrder => $composableBuilder(
    column: $table.pinnedOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get disappearingTtl => $composableBuilder(
    column: $table.disappearingTtl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoTranslateEnabled => $composableBuilder(
    column: $table.autoTranslateEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get autoTranslateTargetLang => $composableBuilder(
    column: $table.autoTranslateTargetLang,
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
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get participantIds => $composableBuilder(
    column: $table.participantIds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get lastMessageText => $composableBuilder(
    column: $table.lastMessageText,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastMessageTime => $composableBuilder(
    column: $table.lastMessageTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessageSenderId => $composableBuilder(
    column: $table.lastMessageSenderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadSelfMentionCount => $composableBuilder(
    column: $table.unreadSelfMentionCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<int> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<int> get lastScrolled => $composableBuilder(
    column: $table.lastScrolled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<int> get pinnedOrder => $composableBuilder(
    column: $table.pinnedOrder,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isMuted =>
      $composableBuilder(column: $table.isMuted, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<int> get disappearingTtl => $composableBuilder(
    column: $table.disappearingTtl,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoTranslateEnabled => $composableBuilder(
    column: $table.autoTranslateEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get autoTranslateTargetLang => $composableBuilder(
    column: $table.autoTranslateTargetLang,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (
            Conversation,
            BaseReferences<_$SnowDatabase, $ConversationsTable, Conversation>,
          ),
          Conversation,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableManager(_$SnowDatabase db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String> participantIds = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String?> lastMessageText = const Value.absent(),
                Value<int?> lastMessageTime = const Value.absent(),
                Value<String?> lastMessageSenderId = const Value.absent(),
                Value<String?> lastMessageId = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> unreadSelfMentionCount = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<int> lastSeen = const Value.absent(),
                Value<int> lastScrolled = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int?> pinnedOrder = const Value.absent(),
                Value<bool> isMuted = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int?> disappearingTtl = const Value.absent(),
                Value<bool> autoTranslateEnabled = const Value.absent(),
                Value<String?> autoTranslateTargetLang = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                type: type,
                title: title,
                participantIds: participantIds,
                groupId: groupId,
                lastMessageText: lastMessageText,
                lastMessageTime: lastMessageTime,
                lastMessageSenderId: lastMessageSenderId,
                lastMessageId: lastMessageId,
                unreadCount: unreadCount,
                unreadSelfMentionCount: unreadSelfMentionCount,
                isRead: isRead,
                lastSeen: lastSeen,
                lastScrolled: lastScrolled,
                isPinned: isPinned,
                pinnedOrder: pinnedOrder,
                isMuted: isMuted,
                isArchived: isArchived,
                isActive: isActive,
                disappearingTtl: disappearingTtl,
                autoTranslateEnabled: autoTranslateEnabled,
                autoTranslateTargetLang: autoTranslateTargetLang,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> type = const Value.absent(),
                Value<String?> title = const Value.absent(),
                required String participantIds,
                Value<String?> groupId = const Value.absent(),
                Value<String?> lastMessageText = const Value.absent(),
                Value<int?> lastMessageTime = const Value.absent(),
                Value<String?> lastMessageSenderId = const Value.absent(),
                Value<String?> lastMessageId = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> unreadSelfMentionCount = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<int> lastSeen = const Value.absent(),
                Value<int> lastScrolled = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int?> pinnedOrder = const Value.absent(),
                Value<bool> isMuted = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int?> disappearingTtl = const Value.absent(),
                Value<bool> autoTranslateEnabled = const Value.absent(),
                Value<String?> autoTranslateTargetLang = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                id: id,
                type: type,
                title: title,
                participantIds: participantIds,
                groupId: groupId,
                lastMessageText: lastMessageText,
                lastMessageTime: lastMessageTime,
                lastMessageSenderId: lastMessageSenderId,
                lastMessageId: lastMessageId,
                unreadCount: unreadCount,
                unreadSelfMentionCount: unreadSelfMentionCount,
                isRead: isRead,
                lastSeen: lastSeen,
                lastScrolled: lastScrolled,
                isPinned: isPinned,
                pinnedOrder: pinnedOrder,
                isMuted: isMuted,
                isArchived: isArchived,
                isActive: isActive,
                disappearingTtl: disappearingTtl,
                autoTranslateEnabled: autoTranslateEnabled,
                autoTranslateTargetLang: autoTranslateTargetLang,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (
        Conversation,
        BaseReferences<_$SnowDatabase, $ConversationsTable, Conversation>,
      ),
      Conversation,
      PrefetchHooks Function()
    >;
typedef $$ContactsTableCreateCompanionBuilder =
    ContactsCompanion Function({
      required String snowChatId,
      Value<String?> displayName,
      Value<String?> publicKeyHex,
      Value<bool> isBlocked,
      Value<bool> isTrusted,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$ContactsTableUpdateCompanionBuilder =
    ContactsCompanion Function({
      Value<String> snowChatId,
      Value<String?> displayName,
      Value<String?> publicKeyHex,
      Value<bool> isBlocked,
      Value<bool> isTrusted,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$ContactsTableFilterComposer
    extends Composer<_$SnowDatabase, $ContactsTable> {
  $$ContactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get snowChatId => $composableBuilder(
    column: $table.snowChatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKeyHex => $composableBuilder(
    column: $table.publicKeyHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBlocked => $composableBuilder(
    column: $table.isBlocked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isTrusted => $composableBuilder(
    column: $table.isTrusted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContactsTableOrderingComposer
    extends Composer<_$SnowDatabase, $ContactsTable> {
  $$ContactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get snowChatId => $composableBuilder(
    column: $table.snowChatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKeyHex => $composableBuilder(
    column: $table.publicKeyHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBlocked => $composableBuilder(
    column: $table.isBlocked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isTrusted => $composableBuilder(
    column: $table.isTrusted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContactsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $ContactsTable> {
  $$ContactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get snowChatId => $composableBuilder(
    column: $table.snowChatId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get publicKeyHex => $composableBuilder(
    column: $table.publicKeyHex,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isBlocked =>
      $composableBuilder(column: $table.isBlocked, builder: (column) => column);

  GeneratedColumn<bool> get isTrusted =>
      $composableBuilder(column: $table.isTrusted, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$ContactsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $ContactsTable,
          Contact,
          $$ContactsTableFilterComposer,
          $$ContactsTableOrderingComposer,
          $$ContactsTableAnnotationComposer,
          $$ContactsTableCreateCompanionBuilder,
          $$ContactsTableUpdateCompanionBuilder,
          (Contact, BaseReferences<_$SnowDatabase, $ContactsTable, Contact>),
          Contact,
          PrefetchHooks Function()
        > {
  $$ContactsTableTableManager(_$SnowDatabase db, $ContactsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> snowChatId = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> publicKeyHex = const Value.absent(),
                Value<bool> isBlocked = const Value.absent(),
                Value<bool> isTrusted = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactsCompanion(
                snowChatId: snowChatId,
                displayName: displayName,
                publicKeyHex: publicKeyHex,
                isBlocked: isBlocked,
                isTrusted: isTrusted,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String snowChatId,
                Value<String?> displayName = const Value.absent(),
                Value<String?> publicKeyHex = const Value.absent(),
                Value<bool> isBlocked = const Value.absent(),
                Value<bool> isTrusted = const Value.absent(),
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => ContactsCompanion.insert(
                snowChatId: snowChatId,
                displayName: displayName,
                publicKeyHex: publicKeyHex,
                isBlocked: isBlocked,
                isTrusted: isTrusted,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContactsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $ContactsTable,
      Contact,
      $$ContactsTableFilterComposer,
      $$ContactsTableOrderingComposer,
      $$ContactsTableAnnotationComposer,
      $$ContactsTableCreateCompanionBuilder,
      $$ContactsTableUpdateCompanionBuilder,
      (Contact, BaseReferences<_$SnowDatabase, $ContactsTable, Contact>),
      Contact,
      PrefetchHooks Function()
    >;
typedef $$SignalSessionsTableCreateCompanionBuilder =
    SignalSessionsCompanion Function({
      required String recipientDeviceId,
      required Uint8List sessionState,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SignalSessionsTableUpdateCompanionBuilder =
    SignalSessionsCompanion Function({
      Value<String> recipientDeviceId,
      Value<Uint8List> sessionState,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SignalSessionsTableFilterComposer
    extends Composer<_$SnowDatabase, $SignalSessionsTable> {
  $$SignalSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recipientDeviceId => $composableBuilder(
    column: $table.recipientDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get sessionState => $composableBuilder(
    column: $table.sessionState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignalSessionsTableOrderingComposer
    extends Composer<_$SnowDatabase, $SignalSessionsTable> {
  $$SignalSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recipientDeviceId => $composableBuilder(
    column: $table.recipientDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get sessionState => $composableBuilder(
    column: $table.sessionState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignalSessionsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $SignalSessionsTable> {
  $$SignalSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recipientDeviceId => $composableBuilder(
    column: $table.recipientDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get sessionState => $composableBuilder(
    column: $table.sessionState,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SignalSessionsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $SignalSessionsTable,
          SignalSession,
          $$SignalSessionsTableFilterComposer,
          $$SignalSessionsTableOrderingComposer,
          $$SignalSessionsTableAnnotationComposer,
          $$SignalSessionsTableCreateCompanionBuilder,
          $$SignalSessionsTableUpdateCompanionBuilder,
          (
            SignalSession,
            BaseReferences<_$SnowDatabase, $SignalSessionsTable, SignalSession>,
          ),
          SignalSession,
          PrefetchHooks Function()
        > {
  $$SignalSessionsTableTableManager(
    _$SnowDatabase db,
    $SignalSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignalSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignalSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignalSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> recipientDeviceId = const Value.absent(),
                Value<Uint8List> sessionState = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignalSessionsCompanion(
                recipientDeviceId: recipientDeviceId,
                sessionState: sessionState,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recipientDeviceId,
                required Uint8List sessionState,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SignalSessionsCompanion.insert(
                recipientDeviceId: recipientDeviceId,
                sessionState: sessionState,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignalSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $SignalSessionsTable,
      SignalSession,
      $$SignalSessionsTableFilterComposer,
      $$SignalSessionsTableOrderingComposer,
      $$SignalSessionsTableAnnotationComposer,
      $$SignalSessionsTableCreateCompanionBuilder,
      $$SignalSessionsTableUpdateCompanionBuilder,
      (
        SignalSession,
        BaseReferences<_$SnowDatabase, $SignalSessionsTable, SignalSession>,
      ),
      SignalSession,
      PrefetchHooks Function()
    >;
typedef $$SignalPreKeysTableCreateCompanionBuilder =
    SignalPreKeysCompanion Function({
      Value<int> keyId,
      required Uint8List publicKey,
      Value<bool> isUsed,
      required DateTime createdAt,
    });
typedef $$SignalPreKeysTableUpdateCompanionBuilder =
    SignalPreKeysCompanion Function({
      Value<int> keyId,
      Value<Uint8List> publicKey,
      Value<bool> isUsed,
      Value<DateTime> createdAt,
    });

class $$SignalPreKeysTableFilterComposer
    extends Composer<_$SnowDatabase, $SignalPreKeysTable> {
  $$SignalPreKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isUsed => $composableBuilder(
    column: $table.isUsed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignalPreKeysTableOrderingComposer
    extends Composer<_$SnowDatabase, $SignalPreKeysTable> {
  $$SignalPreKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isUsed => $composableBuilder(
    column: $table.isUsed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignalPreKeysTableAnnotationComposer
    extends Composer<_$SnowDatabase, $SignalPreKeysTable> {
  $$SignalPreKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get keyId =>
      $composableBuilder(column: $table.keyId, builder: (column) => column);

  GeneratedColumn<Uint8List> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<bool> get isUsed =>
      $composableBuilder(column: $table.isUsed, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SignalPreKeysTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $SignalPreKeysTable,
          SignalPreKey,
          $$SignalPreKeysTableFilterComposer,
          $$SignalPreKeysTableOrderingComposer,
          $$SignalPreKeysTableAnnotationComposer,
          $$SignalPreKeysTableCreateCompanionBuilder,
          $$SignalPreKeysTableUpdateCompanionBuilder,
          (
            SignalPreKey,
            BaseReferences<_$SnowDatabase, $SignalPreKeysTable, SignalPreKey>,
          ),
          SignalPreKey,
          PrefetchHooks Function()
        > {
  $$SignalPreKeysTableTableManager(_$SnowDatabase db, $SignalPreKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignalPreKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignalPreKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignalPreKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> keyId = const Value.absent(),
                Value<Uint8List> publicKey = const Value.absent(),
                Value<bool> isUsed = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SignalPreKeysCompanion(
                keyId: keyId,
                publicKey: publicKey,
                isUsed: isUsed,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> keyId = const Value.absent(),
                required Uint8List publicKey,
                Value<bool> isUsed = const Value.absent(),
                required DateTime createdAt,
              }) => SignalPreKeysCompanion.insert(
                keyId: keyId,
                publicKey: publicKey,
                isUsed: isUsed,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignalPreKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $SignalPreKeysTable,
      SignalPreKey,
      $$SignalPreKeysTableFilterComposer,
      $$SignalPreKeysTableOrderingComposer,
      $$SignalPreKeysTableAnnotationComposer,
      $$SignalPreKeysTableCreateCompanionBuilder,
      $$SignalPreKeysTableUpdateCompanionBuilder,
      (
        SignalPreKey,
        BaseReferences<_$SnowDatabase, $SignalPreKeysTable, SignalPreKey>,
      ),
      SignalPreKey,
      PrefetchHooks Function()
    >;
typedef $$LocalAttachmentsTableCreateCompanionBuilder =
    LocalAttachmentsCompanion Function({
      required String id,
      required String messageId,
      Value<int> displayOrder,
      required String contentType,
      Value<String?> fileName,
      Value<int> fileSize,
      Value<int> width,
      Value<int> height,
      Value<String?> remoteFileId,
      Value<String?> remoteKey,
      Value<String?> remoteDigest,
      Value<String?> localPath,
      Value<int> transferState,
      Value<String?> blurHash,
      Value<String?> thumbnailPath,
      Value<bool> isVoiceNote,
      Value<int> rowid,
    });
typedef $$LocalAttachmentsTableUpdateCompanionBuilder =
    LocalAttachmentsCompanion Function({
      Value<String> id,
      Value<String> messageId,
      Value<int> displayOrder,
      Value<String> contentType,
      Value<String?> fileName,
      Value<int> fileSize,
      Value<int> width,
      Value<int> height,
      Value<String?> remoteFileId,
      Value<String?> remoteKey,
      Value<String?> remoteDigest,
      Value<String?> localPath,
      Value<int> transferState,
      Value<String?> blurHash,
      Value<String?> thumbnailPath,
      Value<bool> isVoiceNote,
      Value<int> rowid,
    });

class $$LocalAttachmentsTableFilterComposer
    extends Composer<_$SnowDatabase, $LocalAttachmentsTable> {
  $$LocalAttachmentsTableFilterComposer({
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

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
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

  ColumnFilters<String> get remoteFileId => $composableBuilder(
    column: $table.remoteFileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteKey => $composableBuilder(
    column: $table.remoteKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteDigest => $composableBuilder(
    column: $table.remoteDigest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transferState => $composableBuilder(
    column: $table.transferState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blurHash => $composableBuilder(
    column: $table.blurHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVoiceNote => $composableBuilder(
    column: $table.isVoiceNote,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalAttachmentsTableOrderingComposer
    extends Composer<_$SnowDatabase, $LocalAttachmentsTable> {
  $$LocalAttachmentsTableOrderingComposer({
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

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
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

  ColumnOrderings<String> get remoteFileId => $composableBuilder(
    column: $table.remoteFileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteKey => $composableBuilder(
    column: $table.remoteKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteDigest => $composableBuilder(
    column: $table.remoteDigest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transferState => $composableBuilder(
    column: $table.transferState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blurHash => $composableBuilder(
    column: $table.blurHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVoiceNote => $composableBuilder(
    column: $table.isVoiceNote,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalAttachmentsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $LocalAttachmentsTable> {
  $$LocalAttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get remoteFileId => $composableBuilder(
    column: $table.remoteFileId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteKey =>
      $composableBuilder(column: $table.remoteKey, builder: (column) => column);

  GeneratedColumn<String> get remoteDigest => $composableBuilder(
    column: $table.remoteDigest,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get transferState => $composableBuilder(
    column: $table.transferState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get blurHash =>
      $composableBuilder(column: $table.blurHash, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isVoiceNote => $composableBuilder(
    column: $table.isVoiceNote,
    builder: (column) => column,
  );
}

class $$LocalAttachmentsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $LocalAttachmentsTable,
          LocalAttachment,
          $$LocalAttachmentsTableFilterComposer,
          $$LocalAttachmentsTableOrderingComposer,
          $$LocalAttachmentsTableAnnotationComposer,
          $$LocalAttachmentsTableCreateCompanionBuilder,
          $$LocalAttachmentsTableUpdateCompanionBuilder,
          (
            LocalAttachment,
            BaseReferences<
              _$SnowDatabase,
              $LocalAttachmentsTable,
              LocalAttachment
            >,
          ),
          LocalAttachment,
          PrefetchHooks Function()
        > {
  $$LocalAttachmentsTableTableManager(
    _$SnowDatabase db,
    $LocalAttachmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<String?> remoteFileId = const Value.absent(),
                Value<String?> remoteKey = const Value.absent(),
                Value<String?> remoteDigest = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<int> transferState = const Value.absent(),
                Value<String?> blurHash = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<bool> isVoiceNote = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAttachmentsCompanion(
                id: id,
                messageId: messageId,
                displayOrder: displayOrder,
                contentType: contentType,
                fileName: fileName,
                fileSize: fileSize,
                width: width,
                height: height,
                remoteFileId: remoteFileId,
                remoteKey: remoteKey,
                remoteDigest: remoteDigest,
                localPath: localPath,
                transferState: transferState,
                blurHash: blurHash,
                thumbnailPath: thumbnailPath,
                isVoiceNote: isVoiceNote,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String messageId,
                Value<int> displayOrder = const Value.absent(),
                required String contentType,
                Value<String?> fileName = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<String?> remoteFileId = const Value.absent(),
                Value<String?> remoteKey = const Value.absent(),
                Value<String?> remoteDigest = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<int> transferState = const Value.absent(),
                Value<String?> blurHash = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<bool> isVoiceNote = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAttachmentsCompanion.insert(
                id: id,
                messageId: messageId,
                displayOrder: displayOrder,
                contentType: contentType,
                fileName: fileName,
                fileSize: fileSize,
                width: width,
                height: height,
                remoteFileId: remoteFileId,
                remoteKey: remoteKey,
                remoteDigest: remoteDigest,
                localPath: localPath,
                transferState: transferState,
                blurHash: blurHash,
                thumbnailPath: thumbnailPath,
                isVoiceNote: isVoiceNote,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalAttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $LocalAttachmentsTable,
      LocalAttachment,
      $$LocalAttachmentsTableFilterComposer,
      $$LocalAttachmentsTableOrderingComposer,
      $$LocalAttachmentsTableAnnotationComposer,
      $$LocalAttachmentsTableCreateCompanionBuilder,
      $$LocalAttachmentsTableUpdateCompanionBuilder,
      (
        LocalAttachment,
        BaseReferences<_$SnowDatabase, $LocalAttachmentsTable, LocalAttachment>,
      ),
      LocalAttachment,
      PrefetchHooks Function()
    >;
typedef $$WalletBalancesTableCreateCompanionBuilder =
    WalletBalancesCompanion Function({
      required String ownerAddress,
      required String mintAddress,
      required String rawAmount,
      required int decimals,
      required String symbol,
      Value<String?> name,
      Value<String?> logoUrl,
      required int lastUpdatedMs,
      Value<int> rowid,
    });
typedef $$WalletBalancesTableUpdateCompanionBuilder =
    WalletBalancesCompanion Function({
      Value<String> ownerAddress,
      Value<String> mintAddress,
      Value<String> rawAmount,
      Value<int> decimals,
      Value<String> symbol,
      Value<String?> name,
      Value<String?> logoUrl,
      Value<int> lastUpdatedMs,
      Value<int> rowid,
    });

class $$WalletBalancesTableFilterComposer
    extends Composer<_$SnowDatabase, $WalletBalancesTable> {
  $$WalletBalancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerAddress => $composableBuilder(
    column: $table.ownerAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mintAddress => $composableBuilder(
    column: $table.mintAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawAmount => $composableBuilder(
    column: $table.rawAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get decimals => $composableBuilder(
    column: $table.decimals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUpdatedMs => $composableBuilder(
    column: $table.lastUpdatedMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WalletBalancesTableOrderingComposer
    extends Composer<_$SnowDatabase, $WalletBalancesTable> {
  $$WalletBalancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerAddress => $composableBuilder(
    column: $table.ownerAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mintAddress => $composableBuilder(
    column: $table.mintAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawAmount => $composableBuilder(
    column: $table.rawAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get decimals => $composableBuilder(
    column: $table.decimals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUpdatedMs => $composableBuilder(
    column: $table.lastUpdatedMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WalletBalancesTableAnnotationComposer
    extends Composer<_$SnowDatabase, $WalletBalancesTable> {
  $$WalletBalancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerAddress => $composableBuilder(
    column: $table.ownerAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mintAddress => $composableBuilder(
    column: $table.mintAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawAmount =>
      $composableBuilder(column: $table.rawAmount, builder: (column) => column);

  GeneratedColumn<int> get decimals =>
      $composableBuilder(column: $table.decimals, builder: (column) => column);

  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get logoUrl =>
      $composableBuilder(column: $table.logoUrl, builder: (column) => column);

  GeneratedColumn<int> get lastUpdatedMs => $composableBuilder(
    column: $table.lastUpdatedMs,
    builder: (column) => column,
  );
}

class $$WalletBalancesTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $WalletBalancesTable,
          WalletBalance,
          $$WalletBalancesTableFilterComposer,
          $$WalletBalancesTableOrderingComposer,
          $$WalletBalancesTableAnnotationComposer,
          $$WalletBalancesTableCreateCompanionBuilder,
          $$WalletBalancesTableUpdateCompanionBuilder,
          (
            WalletBalance,
            BaseReferences<_$SnowDatabase, $WalletBalancesTable, WalletBalance>,
          ),
          WalletBalance,
          PrefetchHooks Function()
        > {
  $$WalletBalancesTableTableManager(
    _$SnowDatabase db,
    $WalletBalancesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WalletBalancesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WalletBalancesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WalletBalancesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerAddress = const Value.absent(),
                Value<String> mintAddress = const Value.absent(),
                Value<String> rawAmount = const Value.absent(),
                Value<int> decimals = const Value.absent(),
                Value<String> symbol = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> logoUrl = const Value.absent(),
                Value<int> lastUpdatedMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WalletBalancesCompanion(
                ownerAddress: ownerAddress,
                mintAddress: mintAddress,
                rawAmount: rawAmount,
                decimals: decimals,
                symbol: symbol,
                name: name,
                logoUrl: logoUrl,
                lastUpdatedMs: lastUpdatedMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerAddress,
                required String mintAddress,
                required String rawAmount,
                required int decimals,
                required String symbol,
                Value<String?> name = const Value.absent(),
                Value<String?> logoUrl = const Value.absent(),
                required int lastUpdatedMs,
                Value<int> rowid = const Value.absent(),
              }) => WalletBalancesCompanion.insert(
                ownerAddress: ownerAddress,
                mintAddress: mintAddress,
                rawAmount: rawAmount,
                decimals: decimals,
                symbol: symbol,
                name: name,
                logoUrl: logoUrl,
                lastUpdatedMs: lastUpdatedMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WalletBalancesTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $WalletBalancesTable,
      WalletBalance,
      $$WalletBalancesTableFilterComposer,
      $$WalletBalancesTableOrderingComposer,
      $$WalletBalancesTableAnnotationComposer,
      $$WalletBalancesTableCreateCompanionBuilder,
      $$WalletBalancesTableUpdateCompanionBuilder,
      (
        WalletBalance,
        BaseReferences<_$SnowDatabase, $WalletBalancesTable, WalletBalance>,
      ),
      WalletBalance,
      PrefetchHooks Function()
    >;
typedef $$WalletTxCacheTableCreateCompanionBuilder =
    WalletTxCacheCompanion Function({
      required String signature,
      required String ownerAddress,
      required String type,
      Value<String?> amountLamports,
      Value<String?> counterparty,
      Value<String?> tokenMint,
      Value<String?> feeLamports,
      Value<int?> blockTime,
      Value<int> parserVersion,
      required int cachedAtMs,
      Value<int> rowid,
    });
typedef $$WalletTxCacheTableUpdateCompanionBuilder =
    WalletTxCacheCompanion Function({
      Value<String> signature,
      Value<String> ownerAddress,
      Value<String> type,
      Value<String?> amountLamports,
      Value<String?> counterparty,
      Value<String?> tokenMint,
      Value<String?> feeLamports,
      Value<int?> blockTime,
      Value<int> parserVersion,
      Value<int> cachedAtMs,
      Value<int> rowid,
    });

class $$WalletTxCacheTableFilterComposer
    extends Composer<_$SnowDatabase, $WalletTxCacheTable> {
  $$WalletTxCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerAddress => $composableBuilder(
    column: $table.ownerAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amountLamports => $composableBuilder(
    column: $table.amountLamports,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get counterparty => $composableBuilder(
    column: $table.counterparty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenMint => $composableBuilder(
    column: $table.tokenMint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feeLamports => $composableBuilder(
    column: $table.feeLamports,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get blockTime => $composableBuilder(
    column: $table.blockTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedAtMs => $composableBuilder(
    column: $table.cachedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WalletTxCacheTableOrderingComposer
    extends Composer<_$SnowDatabase, $WalletTxCacheTable> {
  $$WalletTxCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerAddress => $composableBuilder(
    column: $table.ownerAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amountLamports => $composableBuilder(
    column: $table.amountLamports,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get counterparty => $composableBuilder(
    column: $table.counterparty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenMint => $composableBuilder(
    column: $table.tokenMint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feeLamports => $composableBuilder(
    column: $table.feeLamports,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get blockTime => $composableBuilder(
    column: $table.blockTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedAtMs => $composableBuilder(
    column: $table.cachedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WalletTxCacheTableAnnotationComposer
    extends Composer<_$SnowDatabase, $WalletTxCacheTable> {
  $$WalletTxCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);

  GeneratedColumn<String> get ownerAddress => $composableBuilder(
    column: $table.ownerAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get amountLamports => $composableBuilder(
    column: $table.amountLamports,
    builder: (column) => column,
  );

  GeneratedColumn<String> get counterparty => $composableBuilder(
    column: $table.counterparty,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tokenMint =>
      $composableBuilder(column: $table.tokenMint, builder: (column) => column);

  GeneratedColumn<String> get feeLamports => $composableBuilder(
    column: $table.feeLamports,
    builder: (column) => column,
  );

  GeneratedColumn<int> get blockTime =>
      $composableBuilder(column: $table.blockTime, builder: (column) => column);

  GeneratedColumn<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cachedAtMs => $composableBuilder(
    column: $table.cachedAtMs,
    builder: (column) => column,
  );
}

class $$WalletTxCacheTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $WalletTxCacheTable,
          WalletTxCacheData,
          $$WalletTxCacheTableFilterComposer,
          $$WalletTxCacheTableOrderingComposer,
          $$WalletTxCacheTableAnnotationComposer,
          $$WalletTxCacheTableCreateCompanionBuilder,
          $$WalletTxCacheTableUpdateCompanionBuilder,
          (
            WalletTxCacheData,
            BaseReferences<
              _$SnowDatabase,
              $WalletTxCacheTable,
              WalletTxCacheData
            >,
          ),
          WalletTxCacheData,
          PrefetchHooks Function()
        > {
  $$WalletTxCacheTableTableManager(_$SnowDatabase db, $WalletTxCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WalletTxCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WalletTxCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WalletTxCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> signature = const Value.absent(),
                Value<String> ownerAddress = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> amountLamports = const Value.absent(),
                Value<String?> counterparty = const Value.absent(),
                Value<String?> tokenMint = const Value.absent(),
                Value<String?> feeLamports = const Value.absent(),
                Value<int?> blockTime = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                Value<int> cachedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WalletTxCacheCompanion(
                signature: signature,
                ownerAddress: ownerAddress,
                type: type,
                amountLamports: amountLamports,
                counterparty: counterparty,
                tokenMint: tokenMint,
                feeLamports: feeLamports,
                blockTime: blockTime,
                parserVersion: parserVersion,
                cachedAtMs: cachedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String signature,
                required String ownerAddress,
                required String type,
                Value<String?> amountLamports = const Value.absent(),
                Value<String?> counterparty = const Value.absent(),
                Value<String?> tokenMint = const Value.absent(),
                Value<String?> feeLamports = const Value.absent(),
                Value<int?> blockTime = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                required int cachedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => WalletTxCacheCompanion.insert(
                signature: signature,
                ownerAddress: ownerAddress,
                type: type,
                amountLamports: amountLamports,
                counterparty: counterparty,
                tokenMint: tokenMint,
                feeLamports: feeLamports,
                blockTime: blockTime,
                parserVersion: parserVersion,
                cachedAtMs: cachedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WalletTxCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $WalletTxCacheTable,
      WalletTxCacheData,
      $$WalletTxCacheTableFilterComposer,
      $$WalletTxCacheTableOrderingComposer,
      $$WalletTxCacheTableAnnotationComposer,
      $$WalletTxCacheTableCreateCompanionBuilder,
      $$WalletTxCacheTableUpdateCompanionBuilder,
      (
        WalletTxCacheData,
        BaseReferences<_$SnowDatabase, $WalletTxCacheTable, WalletTxCacheData>,
      ),
      WalletTxCacheData,
      PrefetchHooks Function()
    >;
typedef $$WalletAddressBookTableCreateCompanionBuilder =
    WalletAddressBookCompanion Function({
      Value<int> id,
      required String ownerAddress,
      required String label,
      required String address,
      Value<String> network,
      Value<String?> note,
      required int createdAtMs,
      Value<int?> lastUsedMs,
    });
typedef $$WalletAddressBookTableUpdateCompanionBuilder =
    WalletAddressBookCompanion Function({
      Value<int> id,
      Value<String> ownerAddress,
      Value<String> label,
      Value<String> address,
      Value<String> network,
      Value<String?> note,
      Value<int> createdAtMs,
      Value<int?> lastUsedMs,
    });

class $$WalletAddressBookTableFilterComposer
    extends Composer<_$SnowDatabase, $WalletAddressBookTable> {
  $$WalletAddressBookTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerAddress => $composableBuilder(
    column: $table.ownerAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUsedMs => $composableBuilder(
    column: $table.lastUsedMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WalletAddressBookTableOrderingComposer
    extends Composer<_$SnowDatabase, $WalletAddressBookTable> {
  $$WalletAddressBookTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerAddress => $composableBuilder(
    column: $table.ownerAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUsedMs => $composableBuilder(
    column: $table.lastUsedMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WalletAddressBookTableAnnotationComposer
    extends Composer<_$SnowDatabase, $WalletAddressBookTable> {
  $$WalletAddressBookTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerAddress => $composableBuilder(
    column: $table.ownerAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastUsedMs => $composableBuilder(
    column: $table.lastUsedMs,
    builder: (column) => column,
  );
}

class $$WalletAddressBookTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $WalletAddressBookTable,
          WalletAddressBookData,
          $$WalletAddressBookTableFilterComposer,
          $$WalletAddressBookTableOrderingComposer,
          $$WalletAddressBookTableAnnotationComposer,
          $$WalletAddressBookTableCreateCompanionBuilder,
          $$WalletAddressBookTableUpdateCompanionBuilder,
          (
            WalletAddressBookData,
            BaseReferences<
              _$SnowDatabase,
              $WalletAddressBookTable,
              WalletAddressBookData
            >,
          ),
          WalletAddressBookData,
          PrefetchHooks Function()
        > {
  $$WalletAddressBookTableTableManager(
    _$SnowDatabase db,
    $WalletAddressBookTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WalletAddressBookTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WalletAddressBookTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WalletAddressBookTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> ownerAddress = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<String> network = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int?> lastUsedMs = const Value.absent(),
              }) => WalletAddressBookCompanion(
                id: id,
                ownerAddress: ownerAddress,
                label: label,
                address: address,
                network: network,
                note: note,
                createdAtMs: createdAtMs,
                lastUsedMs: lastUsedMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String ownerAddress,
                required String label,
                required String address,
                Value<String> network = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required int createdAtMs,
                Value<int?> lastUsedMs = const Value.absent(),
              }) => WalletAddressBookCompanion.insert(
                id: id,
                ownerAddress: ownerAddress,
                label: label,
                address: address,
                network: network,
                note: note,
                createdAtMs: createdAtMs,
                lastUsedMs: lastUsedMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WalletAddressBookTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $WalletAddressBookTable,
      WalletAddressBookData,
      $$WalletAddressBookTableFilterComposer,
      $$WalletAddressBookTableOrderingComposer,
      $$WalletAddressBookTableAnnotationComposer,
      $$WalletAddressBookTableCreateCompanionBuilder,
      $$WalletAddressBookTableUpdateCompanionBuilder,
      (
        WalletAddressBookData,
        BaseReferences<
          _$SnowDatabase,
          $WalletAddressBookTable,
          WalletAddressBookData
        >,
      ),
      WalletAddressBookData,
      PrefetchHooks Function()
    >;
typedef $$AiMessagesTableCreateCompanionBuilder =
    AiMessagesCompanion Function({
      required String id,
      required String role,
      required String content,
      Value<String> sessionId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$AiMessagesTableUpdateCompanionBuilder =
    AiMessagesCompanion Function({
      Value<String> id,
      Value<String> role,
      Value<String> content,
      Value<String> sessionId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$AiMessagesTableFilterComposer
    extends Composer<_$SnowDatabase, $AiMessagesTable> {
  $$AiMessagesTableFilterComposer({
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

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiMessagesTableOrderingComposer
    extends Composer<_$SnowDatabase, $AiMessagesTable> {
  $$AiMessagesTableOrderingComposer({
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

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiMessagesTableAnnotationComposer
    extends Composer<_$SnowDatabase, $AiMessagesTable> {
  $$AiMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AiMessagesTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $AiMessagesTable,
          AiMessage,
          $$AiMessagesTableFilterComposer,
          $$AiMessagesTableOrderingComposer,
          $$AiMessagesTableAnnotationComposer,
          $$AiMessagesTableCreateCompanionBuilder,
          $$AiMessagesTableUpdateCompanionBuilder,
          (
            AiMessage,
            BaseReferences<_$SnowDatabase, $AiMessagesTable, AiMessage>,
          ),
          AiMessage,
          PrefetchHooks Function()
        > {
  $$AiMessagesTableTableManager(_$SnowDatabase db, $AiMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiMessagesCompanion(
                id: id,
                role: role,
                content: content,
                sessionId: sessionId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String role,
                required String content,
                Value<String> sessionId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiMessagesCompanion.insert(
                id: id,
                role: role,
                content: content,
                sessionId: sessionId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $AiMessagesTable,
      AiMessage,
      $$AiMessagesTableFilterComposer,
      $$AiMessagesTableOrderingComposer,
      $$AiMessagesTableAnnotationComposer,
      $$AiMessagesTableCreateCompanionBuilder,
      $$AiMessagesTableUpdateCompanionBuilder,
      (AiMessage, BaseReferences<_$SnowDatabase, $AiMessagesTable, AiMessage>),
      AiMessage,
      PrefetchHooks Function()
    >;
typedef $$IdentityVerificationsTableCreateCompanionBuilder =
    IdentityVerificationsCompanion Function({
      required String peerSnowchatId,
      required String pinnedEd25519,
      required String safetyNumber,
      Value<bool> verified,
      Value<int?> verifiedAt,
      Value<int?> lastChangedAt,
      Value<bool> wasPreviouslyVerified,
      Value<int> algorithmVersion,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$IdentityVerificationsTableUpdateCompanionBuilder =
    IdentityVerificationsCompanion Function({
      Value<String> peerSnowchatId,
      Value<String> pinnedEd25519,
      Value<String> safetyNumber,
      Value<bool> verified,
      Value<int?> verifiedAt,
      Value<int?> lastChangedAt,
      Value<bool> wasPreviouslyVerified,
      Value<int> algorithmVersion,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$IdentityVerificationsTableFilterComposer
    extends Composer<_$SnowDatabase, $IdentityVerificationsTable> {
  $$IdentityVerificationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerSnowchatId => $composableBuilder(
    column: $table.peerSnowchatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pinnedEd25519 => $composableBuilder(
    column: $table.pinnedEd25519,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get safetyNumber => $composableBuilder(
    column: $table.safetyNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastChangedAt => $composableBuilder(
    column: $table.lastChangedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get wasPreviouslyVerified => $composableBuilder(
    column: $table.wasPreviouslyVerified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
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
}

class $$IdentityVerificationsTableOrderingComposer
    extends Composer<_$SnowDatabase, $IdentityVerificationsTable> {
  $$IdentityVerificationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerSnowchatId => $composableBuilder(
    column: $table.peerSnowchatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pinnedEd25519 => $composableBuilder(
    column: $table.pinnedEd25519,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get safetyNumber => $composableBuilder(
    column: $table.safetyNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastChangedAt => $composableBuilder(
    column: $table.lastChangedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get wasPreviouslyVerified => $composableBuilder(
    column: $table.wasPreviouslyVerified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
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
}

class $$IdentityVerificationsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $IdentityVerificationsTable> {
  $$IdentityVerificationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerSnowchatId => $composableBuilder(
    column: $table.peerSnowchatId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pinnedEd25519 => $composableBuilder(
    column: $table.pinnedEd25519,
    builder: (column) => column,
  );

  GeneratedColumn<String> get safetyNumber => $composableBuilder(
    column: $table.safetyNumber,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get verified =>
      $composableBuilder(column: $table.verified, builder: (column) => column);

  GeneratedColumn<int> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastChangedAt => $composableBuilder(
    column: $table.lastChangedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get wasPreviouslyVerified => $composableBuilder(
    column: $table.wasPreviouslyVerified,
    builder: (column) => column,
  );

  GeneratedColumn<int> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$IdentityVerificationsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $IdentityVerificationsTable,
          IdentityVerification,
          $$IdentityVerificationsTableFilterComposer,
          $$IdentityVerificationsTableOrderingComposer,
          $$IdentityVerificationsTableAnnotationComposer,
          $$IdentityVerificationsTableCreateCompanionBuilder,
          $$IdentityVerificationsTableUpdateCompanionBuilder,
          (
            IdentityVerification,
            BaseReferences<
              _$SnowDatabase,
              $IdentityVerificationsTable,
              IdentityVerification
            >,
          ),
          IdentityVerification,
          PrefetchHooks Function()
        > {
  $$IdentityVerificationsTableTableManager(
    _$SnowDatabase db,
    $IdentityVerificationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IdentityVerificationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$IdentityVerificationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$IdentityVerificationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> peerSnowchatId = const Value.absent(),
                Value<String> pinnedEd25519 = const Value.absent(),
                Value<String> safetyNumber = const Value.absent(),
                Value<bool> verified = const Value.absent(),
                Value<int?> verifiedAt = const Value.absent(),
                Value<int?> lastChangedAt = const Value.absent(),
                Value<bool> wasPreviouslyVerified = const Value.absent(),
                Value<int> algorithmVersion = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IdentityVerificationsCompanion(
                peerSnowchatId: peerSnowchatId,
                pinnedEd25519: pinnedEd25519,
                safetyNumber: safetyNumber,
                verified: verified,
                verifiedAt: verifiedAt,
                lastChangedAt: lastChangedAt,
                wasPreviouslyVerified: wasPreviouslyVerified,
                algorithmVersion: algorithmVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerSnowchatId,
                required String pinnedEd25519,
                required String safetyNumber,
                Value<bool> verified = const Value.absent(),
                Value<int?> verifiedAt = const Value.absent(),
                Value<int?> lastChangedAt = const Value.absent(),
                Value<bool> wasPreviouslyVerified = const Value.absent(),
                Value<int> algorithmVersion = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => IdentityVerificationsCompanion.insert(
                peerSnowchatId: peerSnowchatId,
                pinnedEd25519: pinnedEd25519,
                safetyNumber: safetyNumber,
                verified: verified,
                verifiedAt: verifiedAt,
                lastChangedAt: lastChangedAt,
                wasPreviouslyVerified: wasPreviouslyVerified,
                algorithmVersion: algorithmVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IdentityVerificationsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $IdentityVerificationsTable,
      IdentityVerification,
      $$IdentityVerificationsTableFilterComposer,
      $$IdentityVerificationsTableOrderingComposer,
      $$IdentityVerificationsTableAnnotationComposer,
      $$IdentityVerificationsTableCreateCompanionBuilder,
      $$IdentityVerificationsTableUpdateCompanionBuilder,
      (
        IdentityVerification,
        BaseReferences<
          _$SnowDatabase,
          $IdentityVerificationsTable,
          IdentityVerification
        >,
      ),
      IdentityVerification,
      PrefetchHooks Function()
    >;
typedef $$PendingTransfersTableCreateCompanionBuilder =
    PendingTransfersCompanion Function({
      required String requestId,
      required String role,
      required String peerSnowchatId,
      required String amount,
      required String token,
      Value<String?> mint,
      required int decimals,
      required String network,
      required String status,
      Value<String?> signature,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$PendingTransfersTableUpdateCompanionBuilder =
    PendingTransfersCompanion Function({
      Value<String> requestId,
      Value<String> role,
      Value<String> peerSnowchatId,
      Value<String> amount,
      Value<String> token,
      Value<String?> mint,
      Value<int> decimals,
      Value<String> network,
      Value<String> status,
      Value<String?> signature,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$PendingTransfersTableFilterComposer
    extends Composer<_$SnowDatabase, $PendingTransfersTable> {
  $$PendingTransfersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerSnowchatId => $composableBuilder(
    column: $table.peerSnowchatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mint => $composableBuilder(
    column: $table.mint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get decimals => $composableBuilder(
    column: $table.decimals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signature => $composableBuilder(
    column: $table.signature,
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
}

class $$PendingTransfersTableOrderingComposer
    extends Composer<_$SnowDatabase, $PendingTransfersTable> {
  $$PendingTransfersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerSnowchatId => $composableBuilder(
    column: $table.peerSnowchatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mint => $composableBuilder(
    column: $table.mint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get decimals => $composableBuilder(
    column: $table.decimals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signature => $composableBuilder(
    column: $table.signature,
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
}

class $$PendingTransfersTableAnnotationComposer
    extends Composer<_$SnowDatabase, $PendingTransfersTable> {
  $$PendingTransfersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get peerSnowchatId => $composableBuilder(
    column: $table.peerSnowchatId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get token =>
      $composableBuilder(column: $table.token, builder: (column) => column);

  GeneratedColumn<String> get mint =>
      $composableBuilder(column: $table.mint, builder: (column) => column);

  GeneratedColumn<int> get decimals =>
      $composableBuilder(column: $table.decimals, builder: (column) => column);

  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PendingTransfersTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $PendingTransfersTable,
          PendingTransfer,
          $$PendingTransfersTableFilterComposer,
          $$PendingTransfersTableOrderingComposer,
          $$PendingTransfersTableAnnotationComposer,
          $$PendingTransfersTableCreateCompanionBuilder,
          $$PendingTransfersTableUpdateCompanionBuilder,
          (
            PendingTransfer,
            BaseReferences<
              _$SnowDatabase,
              $PendingTransfersTable,
              PendingTransfer
            >,
          ),
          PendingTransfer,
          PrefetchHooks Function()
        > {
  $$PendingTransfersTableTableManager(
    _$SnowDatabase db,
    $PendingTransfersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingTransfersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingTransfersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingTransfersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> requestId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> peerSnowchatId = const Value.absent(),
                Value<String> amount = const Value.absent(),
                Value<String> token = const Value.absent(),
                Value<String?> mint = const Value.absent(),
                Value<int> decimals = const Value.absent(),
                Value<String> network = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> signature = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingTransfersCompanion(
                requestId: requestId,
                role: role,
                peerSnowchatId: peerSnowchatId,
                amount: amount,
                token: token,
                mint: mint,
                decimals: decimals,
                network: network,
                status: status,
                signature: signature,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String requestId,
                required String role,
                required String peerSnowchatId,
                required String amount,
                required String token,
                Value<String?> mint = const Value.absent(),
                required int decimals,
                required String network,
                required String status,
                Value<String?> signature = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PendingTransfersCompanion.insert(
                requestId: requestId,
                role: role,
                peerSnowchatId: peerSnowchatId,
                amount: amount,
                token: token,
                mint: mint,
                decimals: decimals,
                network: network,
                status: status,
                signature: signature,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingTransfersTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $PendingTransfersTable,
      PendingTransfer,
      $$PendingTransfersTableFilterComposer,
      $$PendingTransfersTableOrderingComposer,
      $$PendingTransfersTableAnnotationComposer,
      $$PendingTransfersTableCreateCompanionBuilder,
      $$PendingTransfersTableUpdateCompanionBuilder,
      (
        PendingTransfer,
        BaseReferences<_$SnowDatabase, $PendingTransfersTable, PendingTransfer>,
      ),
      PendingTransfer,
      PrefetchHooks Function()
    >;

class $SnowDatabaseManager {
  final _$SnowDatabase _db;
  $SnowDatabaseManager(this._db);
  $$LocalMessagesTableTableManager get localMessages =>
      $$LocalMessagesTableTableManager(_db, _db.localMessages);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$ContactsTableTableManager get contacts =>
      $$ContactsTableTableManager(_db, _db.contacts);
  $$SignalSessionsTableTableManager get signalSessions =>
      $$SignalSessionsTableTableManager(_db, _db.signalSessions);
  $$SignalPreKeysTableTableManager get signalPreKeys =>
      $$SignalPreKeysTableTableManager(_db, _db.signalPreKeys);
  $$LocalAttachmentsTableTableManager get localAttachments =>
      $$LocalAttachmentsTableTableManager(_db, _db.localAttachments);
  $$WalletBalancesTableTableManager get walletBalances =>
      $$WalletBalancesTableTableManager(_db, _db.walletBalances);
  $$WalletTxCacheTableTableManager get walletTxCache =>
      $$WalletTxCacheTableTableManager(_db, _db.walletTxCache);
  $$WalletAddressBookTableTableManager get walletAddressBook =>
      $$WalletAddressBookTableTableManager(_db, _db.walletAddressBook);
  $$AiMessagesTableTableManager get aiMessages =>
      $$AiMessagesTableTableManager(_db, _db.aiMessages);
  $$IdentityVerificationsTableTableManager get identityVerifications =>
      $$IdentityVerificationsTableTableManager(_db, _db.identityVerifications);
  $$PendingTransfersTableTableManager get pendingTransfers =>
      $$PendingTransfersTableTableManager(_db, _db.pendingTransfers);
}
