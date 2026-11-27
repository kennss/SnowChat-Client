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
  static const VerificationMeta _replyToPreviewMeta = const VerificationMeta(
    'replyToPreview',
  );
  @override
  late final GeneratedColumn<String> replyToPreview = GeneratedColumn<String>(
    'reply_to_preview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToSenderIdMeta = const VerificationMeta(
    'replyToSenderId',
  );
  @override
  late final GeneratedColumn<String> replyToSenderId = GeneratedColumn<String>(
    'reply_to_sender_id',
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
  static const VerificationMeta _peerClientIdMeta = const VerificationMeta(
    'peerClientId',
  );
  @override
  late final GeneratedColumn<String> peerClientId = GeneratedColumn<String>(
    'peer_client_id',
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
    replyToPreview,
    replyToSenderId,
    senderDisplayName,
    peerClientId,
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
    if (data.containsKey('reply_to_preview')) {
      context.handle(
        _replyToPreviewMeta,
        replyToPreview.isAcceptableOrUnknown(
          data['reply_to_preview']!,
          _replyToPreviewMeta,
        ),
      );
    }
    if (data.containsKey('reply_to_sender_id')) {
      context.handle(
        _replyToSenderIdMeta,
        replyToSenderId.isAcceptableOrUnknown(
          data['reply_to_sender_id']!,
          _replyToSenderIdMeta,
        ),
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
    if (data.containsKey('peer_client_id')) {
      context.handle(
        _peerClientIdMeta,
        peerClientId.isAcceptableOrUnknown(
          data['peer_client_id']!,
          _peerClientIdMeta,
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
      replyToPreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_preview'],
      ),
      replyToSenderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_sender_id'],
      ),
      senderDisplayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_display_name'],
      ),
      peerClientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_client_id'],
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
  final String? replyToPreview;
  final String? replyToSenderId;
  final String? senderDisplayName;
  final String? peerClientId;
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
    this.replyToPreview,
    this.replyToSenderId,
    this.senderDisplayName,
    this.peerClientId,
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
    if (!nullToAbsent || replyToPreview != null) {
      map['reply_to_preview'] = Variable<String>(replyToPreview);
    }
    if (!nullToAbsent || replyToSenderId != null) {
      map['reply_to_sender_id'] = Variable<String>(replyToSenderId);
    }
    if (!nullToAbsent || senderDisplayName != null) {
      map['sender_display_name'] = Variable<String>(senderDisplayName);
    }
    if (!nullToAbsent || peerClientId != null) {
      map['peer_client_id'] = Variable<String>(peerClientId);
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
      replyToPreview: replyToPreview == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToPreview),
      replyToSenderId: replyToSenderId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToSenderId),
      senderDisplayName: senderDisplayName == null && nullToAbsent
          ? const Value.absent()
          : Value(senderDisplayName),
      peerClientId: peerClientId == null && nullToAbsent
          ? const Value.absent()
          : Value(peerClientId),
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
      replyToPreview: serializer.fromJson<String?>(json['replyToPreview']),
      replyToSenderId: serializer.fromJson<String?>(json['replyToSenderId']),
      senderDisplayName: serializer.fromJson<String?>(
        json['senderDisplayName'],
      ),
      peerClientId: serializer.fromJson<String?>(json['peerClientId']),
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
      'replyToPreview': serializer.toJson<String?>(replyToPreview),
      'replyToSenderId': serializer.toJson<String?>(replyToSenderId),
      'senderDisplayName': serializer.toJson<String?>(senderDisplayName),
      'peerClientId': serializer.toJson<String?>(peerClientId),
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
    Value<String?> replyToPreview = const Value.absent(),
    Value<String?> replyToSenderId = const Value.absent(),
    Value<String?> senderDisplayName = const Value.absent(),
    Value<String?> peerClientId = const Value.absent(),
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
    replyToPreview: replyToPreview.present
        ? replyToPreview.value
        : this.replyToPreview,
    replyToSenderId: replyToSenderId.present
        ? replyToSenderId.value
        : this.replyToSenderId,
    senderDisplayName: senderDisplayName.present
        ? senderDisplayName.value
        : this.senderDisplayName,
    peerClientId: peerClientId.present ? peerClientId.value : this.peerClientId,
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
      replyToPreview: data.replyToPreview.present
          ? data.replyToPreview.value
          : this.replyToPreview,
      replyToSenderId: data.replyToSenderId.present
          ? data.replyToSenderId.value
          : this.replyToSenderId,
      senderDisplayName: data.senderDisplayName.present
          ? data.senderDisplayName.value
          : this.senderDisplayName,
      peerClientId: data.peerClientId.present
          ? data.peerClientId.value
          : this.peerClientId,
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
          ..write('replyToPreview: $replyToPreview, ')
          ..write('replyToSenderId: $replyToSenderId, ')
          ..write('senderDisplayName: $senderDisplayName, ')
          ..write('peerClientId: $peerClientId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
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
    replyToPreview,
    replyToSenderId,
    senderDisplayName,
    peerClientId,
  ]);
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
          other.replyToPreview == this.replyToPreview &&
          other.replyToSenderId == this.replyToSenderId &&
          other.senderDisplayName == this.senderDisplayName &&
          other.peerClientId == this.peerClientId);
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
  final Value<String?> replyToPreview;
  final Value<String?> replyToSenderId;
  final Value<String?> senderDisplayName;
  final Value<String?> peerClientId;
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
    this.replyToPreview = const Value.absent(),
    this.replyToSenderId = const Value.absent(),
    this.senderDisplayName = const Value.absent(),
    this.peerClientId = const Value.absent(),
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
    this.replyToPreview = const Value.absent(),
    this.replyToSenderId = const Value.absent(),
    this.senderDisplayName = const Value.absent(),
    this.peerClientId = const Value.absent(),
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
    Expression<String>? replyToPreview,
    Expression<String>? replyToSenderId,
    Expression<String>? senderDisplayName,
    Expression<String>? peerClientId,
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
      if (replyToPreview != null) 'reply_to_preview': replyToPreview,
      if (replyToSenderId != null) 'reply_to_sender_id': replyToSenderId,
      if (senderDisplayName != null) 'sender_display_name': senderDisplayName,
      if (peerClientId != null) 'peer_client_id': peerClientId,
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
    Value<String?>? replyToPreview,
    Value<String?>? replyToSenderId,
    Value<String?>? senderDisplayName,
    Value<String?>? peerClientId,
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
      replyToPreview: replyToPreview ?? this.replyToPreview,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      senderDisplayName: senderDisplayName ?? this.senderDisplayName,
      peerClientId: peerClientId ?? this.peerClientId,
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
    if (replyToPreview.present) {
      map['reply_to_preview'] = Variable<String>(replyToPreview.value);
    }
    if (replyToSenderId.present) {
      map['reply_to_sender_id'] = Variable<String>(replyToSenderId.value);
    }
    if (senderDisplayName.present) {
      map['sender_display_name'] = Variable<String>(senderDisplayName.value);
    }
    if (peerClientId.present) {
      map['peer_client_id'] = Variable<String>(peerClientId.value);
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
          ..write('replyToPreview: $replyToPreview, ')
          ..write('replyToSenderId: $replyToSenderId, ')
          ..write('senderDisplayName: $senderDisplayName, ')
          ..write('peerClientId: $peerClientId, ')
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

  /// Per-conversation translation target language (null falls back to settings.preferredLanguage).
  /// Value: name from SupportedLanguages — 'Korean', 'English', ...
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

  /// 'user' or 'assistant'
  final String role;

  /// Message text
  final String content;

  /// Session ID (for separating conversations)
  final String sessionId;

  /// Created at
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

class $Gv2GroupsTable extends Gv2Groups
    with TableInfo<$Gv2GroupsTable, Gv2GroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2GroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _masterKeyMeta = const VerificationMeta(
    'masterKey',
  );
  @override
  late final GeneratedColumn<Uint8List> masterKey = GeneratedColumn<Uint8List>(
    'master_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _myCiphertextMeta = const VerificationMeta(
    'myCiphertext',
  );
  @override
  late final GeneratedColumn<String> myCiphertext = GeneratedColumn<String>(
    'my_ciphertext',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 130,
      maxTextLength: 130,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _protocolVersionMeta = const VerificationMeta(
    'protocolVersion',
  );
  @override
  late final GeneratedColumn<int> protocolVersion = GeneratedColumn<int>(
    'protocol_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Gv2Membership, String>
  membership = GeneratedColumn<String>(
    'membership',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<Gv2Membership>($Gv2GroupsTable.$convertermembership);
  @override
  late final GeneratedColumnWithTypeConverter<Gv2Hold, String> hold =
      GeneratedColumn<String>(
        'hold',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(Gv2Hold.none.name),
      ).withConverter<Gv2Hold>($Gv2GroupsTable.$converterhold);
  static const VerificationMeta _holdEvidenceMeta = const VerificationMeta(
    'holdEvidence',
  );
  @override
  late final GeneratedColumn<Uint8List> holdEvidence =
      GeneratedColumn<Uint8List>(
        'hold_evidence',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chainMeta = const VerificationMeta('chain');
  @override
  late final GeneratedColumn<Uint8List> chain = GeneratedColumn<Uint8List>(
    'chain',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateHashMeta = const VerificationMeta(
    'stateHash',
  );
  @override
  late final GeneratedColumn<Uint8List> stateHash = GeneratedColumn<Uint8List>(
    'state_hash',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _headSigMeta = const VerificationMeta(
    'headSig',
  );
  @override
  late final GeneratedColumn<Uint8List> headSig = GeneratedColumn<Uint8List>(
    'head_sig',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateLoadedMeta = const VerificationMeta(
    'stateLoaded',
  );
  @override
  late final GeneratedColumn<bool> stateLoaded = GeneratedColumn<bool>(
    'state_loaded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("state_loaded" IN (0, 1))',
    ),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _titlePayloadMeta = const VerificationMeta(
    'titlePayload',
  );
  @override
  late final GeneratedColumn<Uint8List> titlePayload =
      GeneratedColumn<Uint8List>(
        'title_payload',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
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
  static const VerificationMeta _inviteSeedMeta = const VerificationMeta(
    'inviteSeed',
  );
  @override
  late final GeneratedColumn<Uint8List> inviteSeed = GeneratedColumn<Uint8List>(
    'invite_seed',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _invitedBySnowIdMeta = const VerificationMeta(
    'invitedBySnowId',
  );
  @override
  late final GeneratedColumn<String> invitedBySnowId = GeneratedColumn<String>(
    'invited_by_snow_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _myKeyRevisionMeta = const VerificationMeta(
    'myKeyRevision',
  );
  @override
  late final GeneratedColumn<int> myKeyRevision = GeneratedColumn<int>(
    'my_key_revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _myKeyAtMsMeta = const VerificationMeta(
    'myKeyAtMs',
  );
  @override
  late final GeneratedColumn<int> myKeyAtMs = GeneratedColumn<int>(
    'my_key_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastRemovalRevisionMeta =
      const VerificationMeta('lastRemovalRevision');
  @override
  late final GeneratedColumn<int> lastRemovalRevision = GeneratedColumn<int>(
    'last_removal_revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resetPendingMeta = const VerificationMeta(
    'resetPending',
  );
  @override
  late final GeneratedColumn<bool> resetPending = GeneratedColumn<bool>(
    'reset_pending',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reset_pending" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastSyncAtMsMeta = const VerificationMeta(
    'lastSyncAtMs',
  );
  @override
  late final GeneratedColumn<int> lastSyncAtMs = GeneratedColumn<int>(
    'last_sync_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _changeSentAtMsMeta = const VerificationMeta(
    'changeSentAtMs',
  );
  @override
  late final GeneratedColumn<int> changeSentAtMs = GeneratedColumn<int>(
    'change_sent_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    masterKey,
    myCiphertext,
    protocolVersion,
    membership,
    hold,
    holdEvidence,
    revision,
    chain,
    stateHash,
    headSig,
    stateLoaded,
    deleted,
    titlePayload,
    title,
    inviteSeed,
    invitedBySnowId,
    myKeyRevision,
    myKeyAtMs,
    lastRemovalRevision,
    resetPending,
    lastSyncAtMs,
    changeSentAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2GroupRow> instance, {
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
    if (data.containsKey('master_key')) {
      context.handle(
        _masterKeyMeta,
        masterKey.isAcceptableOrUnknown(data['master_key']!, _masterKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_masterKeyMeta);
    }
    if (data.containsKey('my_ciphertext')) {
      context.handle(
        _myCiphertextMeta,
        myCiphertext.isAcceptableOrUnknown(
          data['my_ciphertext']!,
          _myCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_myCiphertextMeta);
    }
    if (data.containsKey('protocol_version')) {
      context.handle(
        _protocolVersionMeta,
        protocolVersion.isAcceptableOrUnknown(
          data['protocol_version']!,
          _protocolVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_protocolVersionMeta);
    }
    if (data.containsKey('hold_evidence')) {
      context.handle(
        _holdEvidenceMeta,
        holdEvidence.isAcceptableOrUnknown(
          data['hold_evidence']!,
          _holdEvidenceMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('chain')) {
      context.handle(
        _chainMeta,
        chain.isAcceptableOrUnknown(data['chain']!, _chainMeta),
      );
    } else if (isInserting) {
      context.missing(_chainMeta);
    }
    if (data.containsKey('state_hash')) {
      context.handle(
        _stateHashMeta,
        stateHash.isAcceptableOrUnknown(data['state_hash']!, _stateHashMeta),
      );
    } else if (isInserting) {
      context.missing(_stateHashMeta);
    }
    if (data.containsKey('head_sig')) {
      context.handle(
        _headSigMeta,
        headSig.isAcceptableOrUnknown(data['head_sig']!, _headSigMeta),
      );
    }
    if (data.containsKey('state_loaded')) {
      context.handle(
        _stateLoadedMeta,
        stateLoaded.isAcceptableOrUnknown(
          data['state_loaded']!,
          _stateLoadedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_stateLoadedMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('title_payload')) {
      context.handle(
        _titlePayloadMeta,
        titlePayload.isAcceptableOrUnknown(
          data['title_payload']!,
          _titlePayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_titlePayloadMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('invite_seed')) {
      context.handle(
        _inviteSeedMeta,
        inviteSeed.isAcceptableOrUnknown(data['invite_seed']!, _inviteSeedMeta),
      );
    }
    if (data.containsKey('invited_by_snow_id')) {
      context.handle(
        _invitedBySnowIdMeta,
        invitedBySnowId.isAcceptableOrUnknown(
          data['invited_by_snow_id']!,
          _invitedBySnowIdMeta,
        ),
      );
    }
    if (data.containsKey('my_key_revision')) {
      context.handle(
        _myKeyRevisionMeta,
        myKeyRevision.isAcceptableOrUnknown(
          data['my_key_revision']!,
          _myKeyRevisionMeta,
        ),
      );
    }
    if (data.containsKey('my_key_at_ms')) {
      context.handle(
        _myKeyAtMsMeta,
        myKeyAtMs.isAcceptableOrUnknown(data['my_key_at_ms']!, _myKeyAtMsMeta),
      );
    }
    if (data.containsKey('last_removal_revision')) {
      context.handle(
        _lastRemovalRevisionMeta,
        lastRemovalRevision.isAcceptableOrUnknown(
          data['last_removal_revision']!,
          _lastRemovalRevisionMeta,
        ),
      );
    }
    if (data.containsKey('reset_pending')) {
      context.handle(
        _resetPendingMeta,
        resetPending.isAcceptableOrUnknown(
          data['reset_pending']!,
          _resetPendingMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_at_ms')) {
      context.handle(
        _lastSyncAtMsMeta,
        lastSyncAtMs.isAcceptableOrUnknown(
          data['last_sync_at_ms']!,
          _lastSyncAtMsMeta,
        ),
      );
    }
    if (data.containsKey('change_sent_at_ms')) {
      context.handle(
        _changeSentAtMsMeta,
        changeSentAtMs.isAcceptableOrUnknown(
          data['change_sent_at_ms']!,
          _changeSentAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId};
  @override
  Gv2GroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2GroupRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      masterKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}master_key'],
      )!,
      myCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}my_ciphertext'],
      )!,
      protocolVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}protocol_version'],
      )!,
      membership: $Gv2GroupsTable.$convertermembership.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}membership'],
        )!,
      ),
      hold: $Gv2GroupsTable.$converterhold.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hold'],
        )!,
      ),
      holdEvidence: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}hold_evidence'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      chain: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}chain'],
      )!,
      stateHash: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}state_hash'],
      )!,
      headSig: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}head_sig'],
      ),
      stateLoaded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}state_loaded'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      titlePayload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}title_payload'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      inviteSeed: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}invite_seed'],
      ),
      invitedBySnowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invited_by_snow_id'],
      ),
      myKeyRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}my_key_revision'],
      ),
      myKeyAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}my_key_at_ms'],
      ),
      lastRemovalRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_removal_revision'],
      ),
      resetPending: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reset_pending'],
      )!,
      lastSyncAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_sync_at_ms'],
      )!,
      changeSentAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}change_sent_at_ms'],
      ),
    );
  }

  @override
  $Gv2GroupsTable createAlias(String alias) {
    return $Gv2GroupsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Gv2Membership, String, String>
  $convertermembership = const EnumNameConverter<Gv2Membership>(
    Gv2Membership.values,
  );
  static JsonTypeConverter2<Gv2Hold, String, String> $converterhold =
      const EnumNameConverter<Gv2Hold>(Gv2Hold.values);
}

class Gv2GroupRow extends DataClass implements Insertable<Gv2GroupRow> {
  /// Lowercase hex of the 32-byte group id; also the conversation id.
  final String groupId;

  /// 32-byte group master key. Key material.
  final Uint8List masterKey;

  /// This account's member ciphertext in the group (130 hex characters).
  final String myCiphertext;

  /// Protocol version of the log at [revision].
  final int protocolVersion;
  final Gv2Membership membership;
  final Gv2Hold hold;

  /// What justified [hold] = frozen (the two signed heads) or withheld (the
  /// signed head the server does not serve), kept as evidence. UTF-8 JSON.
  final Uint8List? holdEvidence;
  final int revision;

  /// 32-byte chain hash at [revision].
  final Uint8List chain;

  /// 32-byte state hash at [revision].
  final Uint8List stateHash;

  /// The server's 64-byte signature over (groupId, revision, chain); null
  /// while the anchor comes from an invite or a backup and nothing has been
  /// fetched yet.
  final Uint8List? headSig;

  /// False while the member and pending rows do not yet hold the state that
  /// [stateHash] commits to (a fresh invite, a restore, or a repair).
  final bool stateLoaded;

  /// The log's own "deleted" flag at [revision].
  final bool deleted;

  /// Sealed title payload, exactly as in the log (state hash input). Empty
  /// until the state is loaded.
  final Uint8List titlePayload;

  /// Group name decoded from [titlePayload]; null when it does not open.
  final String? title;

  /// One-time invite private seed (32 bytes) while [membership] is invited.
  final Uint8List? inviteSeed;

  /// snowId of whoever sent the 1:1 invite.
  final String? invitedBySnowId;

  /// Revision at which this device's current Sender Key was made; null when
  /// it has none. A removal after this revision forces a new key before the
  /// next send (design §8).
  final int? myKeyRevision;

  /// When this device made its current Sender Key (local clock, ms); null
  /// when it has none. A key older than gv2OwnKeyMaxAge is replaced before
  /// the next message: what a stolen device's keys open of what it sent is
  /// bounded in time, not only by the next removal.
  final int? myKeyAtMs;

  /// Revision of the latest change that took a member out of the group (a
  /// removal or a leave), as far as this device has followed the log; null
  /// when there was none. Written with the state, so it survives a crash
  /// between applying the change and making a new Sender Key.
  final int? lastRemovalRevision;

  /// True for a group taken from the backup (a reinstall) until this device
  /// has told the group that it lost its Sender Keys (member_reset): the
  /// members then give it their keys again and one of them confirms the
  /// head. Kept here so that the notice is sent even when the restore
  /// happened offline. (Schema v12.)
  final bool resetPending;

  /// When the last sync that reached the server's head STARTED, local clock
  /// milliseconds: whatever the server had accepted before then, this
  /// device has. (A group this device created: when it was created.)
  final int lastSyncAtMs;

  /// When this device sent a change of its own whose outcome it has not
  /// learned (local clock milliseconds); null when there is none. Set before
  /// the request goes out and cleared by its answer, or by a sync that
  /// started after it: until then this device may not know a change the
  /// server already took — its own removal of a member — and a message
  /// syncs before it goes. (Schema v13.)
  final int? changeSentAtMs;
  const Gv2GroupRow({
    required this.groupId,
    required this.masterKey,
    required this.myCiphertext,
    required this.protocolVersion,
    required this.membership,
    required this.hold,
    this.holdEvidence,
    required this.revision,
    required this.chain,
    required this.stateHash,
    this.headSig,
    required this.stateLoaded,
    required this.deleted,
    required this.titlePayload,
    this.title,
    this.inviteSeed,
    this.invitedBySnowId,
    this.myKeyRevision,
    this.myKeyAtMs,
    this.lastRemovalRevision,
    required this.resetPending,
    required this.lastSyncAtMs,
    this.changeSentAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['master_key'] = Variable<Uint8List>(masterKey);
    map['my_ciphertext'] = Variable<String>(myCiphertext);
    map['protocol_version'] = Variable<int>(protocolVersion);
    {
      map['membership'] = Variable<String>(
        $Gv2GroupsTable.$convertermembership.toSql(membership),
      );
    }
    {
      map['hold'] = Variable<String>(
        $Gv2GroupsTable.$converterhold.toSql(hold),
      );
    }
    if (!nullToAbsent || holdEvidence != null) {
      map['hold_evidence'] = Variable<Uint8List>(holdEvidence);
    }
    map['revision'] = Variable<int>(revision);
    map['chain'] = Variable<Uint8List>(chain);
    map['state_hash'] = Variable<Uint8List>(stateHash);
    if (!nullToAbsent || headSig != null) {
      map['head_sig'] = Variable<Uint8List>(headSig);
    }
    map['state_loaded'] = Variable<bool>(stateLoaded);
    map['deleted'] = Variable<bool>(deleted);
    map['title_payload'] = Variable<Uint8List>(titlePayload);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || inviteSeed != null) {
      map['invite_seed'] = Variable<Uint8List>(inviteSeed);
    }
    if (!nullToAbsent || invitedBySnowId != null) {
      map['invited_by_snow_id'] = Variable<String>(invitedBySnowId);
    }
    if (!nullToAbsent || myKeyRevision != null) {
      map['my_key_revision'] = Variable<int>(myKeyRevision);
    }
    if (!nullToAbsent || myKeyAtMs != null) {
      map['my_key_at_ms'] = Variable<int>(myKeyAtMs);
    }
    if (!nullToAbsent || lastRemovalRevision != null) {
      map['last_removal_revision'] = Variable<int>(lastRemovalRevision);
    }
    map['reset_pending'] = Variable<bool>(resetPending);
    map['last_sync_at_ms'] = Variable<int>(lastSyncAtMs);
    if (!nullToAbsent || changeSentAtMs != null) {
      map['change_sent_at_ms'] = Variable<int>(changeSentAtMs);
    }
    return map;
  }

  Gv2GroupsCompanion toCompanion(bool nullToAbsent) {
    return Gv2GroupsCompanion(
      groupId: Value(groupId),
      masterKey: Value(masterKey),
      myCiphertext: Value(myCiphertext),
      protocolVersion: Value(protocolVersion),
      membership: Value(membership),
      hold: Value(hold),
      holdEvidence: holdEvidence == null && nullToAbsent
          ? const Value.absent()
          : Value(holdEvidence),
      revision: Value(revision),
      chain: Value(chain),
      stateHash: Value(stateHash),
      headSig: headSig == null && nullToAbsent
          ? const Value.absent()
          : Value(headSig),
      stateLoaded: Value(stateLoaded),
      deleted: Value(deleted),
      titlePayload: Value(titlePayload),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      inviteSeed: inviteSeed == null && nullToAbsent
          ? const Value.absent()
          : Value(inviteSeed),
      invitedBySnowId: invitedBySnowId == null && nullToAbsent
          ? const Value.absent()
          : Value(invitedBySnowId),
      myKeyRevision: myKeyRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(myKeyRevision),
      myKeyAtMs: myKeyAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(myKeyAtMs),
      lastRemovalRevision: lastRemovalRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRemovalRevision),
      resetPending: Value(resetPending),
      lastSyncAtMs: Value(lastSyncAtMs),
      changeSentAtMs: changeSentAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(changeSentAtMs),
    );
  }

  factory Gv2GroupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2GroupRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      masterKey: serializer.fromJson<Uint8List>(json['masterKey']),
      myCiphertext: serializer.fromJson<String>(json['myCiphertext']),
      protocolVersion: serializer.fromJson<int>(json['protocolVersion']),
      membership: $Gv2GroupsTable.$convertermembership.fromJson(
        serializer.fromJson<String>(json['membership']),
      ),
      hold: $Gv2GroupsTable.$converterhold.fromJson(
        serializer.fromJson<String>(json['hold']),
      ),
      holdEvidence: serializer.fromJson<Uint8List?>(json['holdEvidence']),
      revision: serializer.fromJson<int>(json['revision']),
      chain: serializer.fromJson<Uint8List>(json['chain']),
      stateHash: serializer.fromJson<Uint8List>(json['stateHash']),
      headSig: serializer.fromJson<Uint8List?>(json['headSig']),
      stateLoaded: serializer.fromJson<bool>(json['stateLoaded']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      titlePayload: serializer.fromJson<Uint8List>(json['titlePayload']),
      title: serializer.fromJson<String?>(json['title']),
      inviteSeed: serializer.fromJson<Uint8List?>(json['inviteSeed']),
      invitedBySnowId: serializer.fromJson<String?>(json['invitedBySnowId']),
      myKeyRevision: serializer.fromJson<int?>(json['myKeyRevision']),
      myKeyAtMs: serializer.fromJson<int?>(json['myKeyAtMs']),
      lastRemovalRevision: serializer.fromJson<int?>(
        json['lastRemovalRevision'],
      ),
      resetPending: serializer.fromJson<bool>(json['resetPending']),
      lastSyncAtMs: serializer.fromJson<int>(json['lastSyncAtMs']),
      changeSentAtMs: serializer.fromJson<int?>(json['changeSentAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'masterKey': serializer.toJson<Uint8List>(masterKey),
      'myCiphertext': serializer.toJson<String>(myCiphertext),
      'protocolVersion': serializer.toJson<int>(protocolVersion),
      'membership': serializer.toJson<String>(
        $Gv2GroupsTable.$convertermembership.toJson(membership),
      ),
      'hold': serializer.toJson<String>(
        $Gv2GroupsTable.$converterhold.toJson(hold),
      ),
      'holdEvidence': serializer.toJson<Uint8List?>(holdEvidence),
      'revision': serializer.toJson<int>(revision),
      'chain': serializer.toJson<Uint8List>(chain),
      'stateHash': serializer.toJson<Uint8List>(stateHash),
      'headSig': serializer.toJson<Uint8List?>(headSig),
      'stateLoaded': serializer.toJson<bool>(stateLoaded),
      'deleted': serializer.toJson<bool>(deleted),
      'titlePayload': serializer.toJson<Uint8List>(titlePayload),
      'title': serializer.toJson<String?>(title),
      'inviteSeed': serializer.toJson<Uint8List?>(inviteSeed),
      'invitedBySnowId': serializer.toJson<String?>(invitedBySnowId),
      'myKeyRevision': serializer.toJson<int?>(myKeyRevision),
      'myKeyAtMs': serializer.toJson<int?>(myKeyAtMs),
      'lastRemovalRevision': serializer.toJson<int?>(lastRemovalRevision),
      'resetPending': serializer.toJson<bool>(resetPending),
      'lastSyncAtMs': serializer.toJson<int>(lastSyncAtMs),
      'changeSentAtMs': serializer.toJson<int?>(changeSentAtMs),
    };
  }

  Gv2GroupRow copyWith({
    String? groupId,
    Uint8List? masterKey,
    String? myCiphertext,
    int? protocolVersion,
    Gv2Membership? membership,
    Gv2Hold? hold,
    Value<Uint8List?> holdEvidence = const Value.absent(),
    int? revision,
    Uint8List? chain,
    Uint8List? stateHash,
    Value<Uint8List?> headSig = const Value.absent(),
    bool? stateLoaded,
    bool? deleted,
    Uint8List? titlePayload,
    Value<String?> title = const Value.absent(),
    Value<Uint8List?> inviteSeed = const Value.absent(),
    Value<String?> invitedBySnowId = const Value.absent(),
    Value<int?> myKeyRevision = const Value.absent(),
    Value<int?> myKeyAtMs = const Value.absent(),
    Value<int?> lastRemovalRevision = const Value.absent(),
    bool? resetPending,
    int? lastSyncAtMs,
    Value<int?> changeSentAtMs = const Value.absent(),
  }) => Gv2GroupRow(
    groupId: groupId ?? this.groupId,
    masterKey: masterKey ?? this.masterKey,
    myCiphertext: myCiphertext ?? this.myCiphertext,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    membership: membership ?? this.membership,
    hold: hold ?? this.hold,
    holdEvidence: holdEvidence.present ? holdEvidence.value : this.holdEvidence,
    revision: revision ?? this.revision,
    chain: chain ?? this.chain,
    stateHash: stateHash ?? this.stateHash,
    headSig: headSig.present ? headSig.value : this.headSig,
    stateLoaded: stateLoaded ?? this.stateLoaded,
    deleted: deleted ?? this.deleted,
    titlePayload: titlePayload ?? this.titlePayload,
    title: title.present ? title.value : this.title,
    inviteSeed: inviteSeed.present ? inviteSeed.value : this.inviteSeed,
    invitedBySnowId: invitedBySnowId.present
        ? invitedBySnowId.value
        : this.invitedBySnowId,
    myKeyRevision: myKeyRevision.present
        ? myKeyRevision.value
        : this.myKeyRevision,
    myKeyAtMs: myKeyAtMs.present ? myKeyAtMs.value : this.myKeyAtMs,
    lastRemovalRevision: lastRemovalRevision.present
        ? lastRemovalRevision.value
        : this.lastRemovalRevision,
    resetPending: resetPending ?? this.resetPending,
    lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
    changeSentAtMs: changeSentAtMs.present
        ? changeSentAtMs.value
        : this.changeSentAtMs,
  );
  Gv2GroupRow copyWithCompanion(Gv2GroupsCompanion data) {
    return Gv2GroupRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      masterKey: data.masterKey.present ? data.masterKey.value : this.masterKey,
      myCiphertext: data.myCiphertext.present
          ? data.myCiphertext.value
          : this.myCiphertext,
      protocolVersion: data.protocolVersion.present
          ? data.protocolVersion.value
          : this.protocolVersion,
      membership: data.membership.present
          ? data.membership.value
          : this.membership,
      hold: data.hold.present ? data.hold.value : this.hold,
      holdEvidence: data.holdEvidence.present
          ? data.holdEvidence.value
          : this.holdEvidence,
      revision: data.revision.present ? data.revision.value : this.revision,
      chain: data.chain.present ? data.chain.value : this.chain,
      stateHash: data.stateHash.present ? data.stateHash.value : this.stateHash,
      headSig: data.headSig.present ? data.headSig.value : this.headSig,
      stateLoaded: data.stateLoaded.present
          ? data.stateLoaded.value
          : this.stateLoaded,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      titlePayload: data.titlePayload.present
          ? data.titlePayload.value
          : this.titlePayload,
      title: data.title.present ? data.title.value : this.title,
      inviteSeed: data.inviteSeed.present
          ? data.inviteSeed.value
          : this.inviteSeed,
      invitedBySnowId: data.invitedBySnowId.present
          ? data.invitedBySnowId.value
          : this.invitedBySnowId,
      myKeyRevision: data.myKeyRevision.present
          ? data.myKeyRevision.value
          : this.myKeyRevision,
      myKeyAtMs: data.myKeyAtMs.present ? data.myKeyAtMs.value : this.myKeyAtMs,
      lastRemovalRevision: data.lastRemovalRevision.present
          ? data.lastRemovalRevision.value
          : this.lastRemovalRevision,
      resetPending: data.resetPending.present
          ? data.resetPending.value
          : this.resetPending,
      lastSyncAtMs: data.lastSyncAtMs.present
          ? data.lastSyncAtMs.value
          : this.lastSyncAtMs,
      changeSentAtMs: data.changeSentAtMs.present
          ? data.changeSentAtMs.value
          : this.changeSentAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2GroupRow(')
          ..write('groupId: $groupId, ')
          ..write('masterKey: $masterKey, ')
          ..write('myCiphertext: $myCiphertext, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('membership: $membership, ')
          ..write('hold: $hold, ')
          ..write('holdEvidence: $holdEvidence, ')
          ..write('revision: $revision, ')
          ..write('chain: $chain, ')
          ..write('stateHash: $stateHash, ')
          ..write('headSig: $headSig, ')
          ..write('stateLoaded: $stateLoaded, ')
          ..write('deleted: $deleted, ')
          ..write('titlePayload: $titlePayload, ')
          ..write('title: $title, ')
          ..write('inviteSeed: $inviteSeed, ')
          ..write('invitedBySnowId: $invitedBySnowId, ')
          ..write('myKeyRevision: $myKeyRevision, ')
          ..write('myKeyAtMs: $myKeyAtMs, ')
          ..write('lastRemovalRevision: $lastRemovalRevision, ')
          ..write('resetPending: $resetPending, ')
          ..write('lastSyncAtMs: $lastSyncAtMs, ')
          ..write('changeSentAtMs: $changeSentAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    groupId,
    $driftBlobEquality.hash(masterKey),
    myCiphertext,
    protocolVersion,
    membership,
    hold,
    $driftBlobEquality.hash(holdEvidence),
    revision,
    $driftBlobEquality.hash(chain),
    $driftBlobEquality.hash(stateHash),
    $driftBlobEquality.hash(headSig),
    stateLoaded,
    deleted,
    $driftBlobEquality.hash(titlePayload),
    title,
    $driftBlobEquality.hash(inviteSeed),
    invitedBySnowId,
    myKeyRevision,
    myKeyAtMs,
    lastRemovalRevision,
    resetPending,
    lastSyncAtMs,
    changeSentAtMs,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2GroupRow &&
          other.groupId == this.groupId &&
          $driftBlobEquality.equals(other.masterKey, this.masterKey) &&
          other.myCiphertext == this.myCiphertext &&
          other.protocolVersion == this.protocolVersion &&
          other.membership == this.membership &&
          other.hold == this.hold &&
          $driftBlobEquality.equals(other.holdEvidence, this.holdEvidence) &&
          other.revision == this.revision &&
          $driftBlobEquality.equals(other.chain, this.chain) &&
          $driftBlobEquality.equals(other.stateHash, this.stateHash) &&
          $driftBlobEquality.equals(other.headSig, this.headSig) &&
          other.stateLoaded == this.stateLoaded &&
          other.deleted == this.deleted &&
          $driftBlobEquality.equals(other.titlePayload, this.titlePayload) &&
          other.title == this.title &&
          $driftBlobEquality.equals(other.inviteSeed, this.inviteSeed) &&
          other.invitedBySnowId == this.invitedBySnowId &&
          other.myKeyRevision == this.myKeyRevision &&
          other.myKeyAtMs == this.myKeyAtMs &&
          other.lastRemovalRevision == this.lastRemovalRevision &&
          other.resetPending == this.resetPending &&
          other.lastSyncAtMs == this.lastSyncAtMs &&
          other.changeSentAtMs == this.changeSentAtMs);
}

class Gv2GroupsCompanion extends UpdateCompanion<Gv2GroupRow> {
  final Value<String> groupId;
  final Value<Uint8List> masterKey;
  final Value<String> myCiphertext;
  final Value<int> protocolVersion;
  final Value<Gv2Membership> membership;
  final Value<Gv2Hold> hold;
  final Value<Uint8List?> holdEvidence;
  final Value<int> revision;
  final Value<Uint8List> chain;
  final Value<Uint8List> stateHash;
  final Value<Uint8List?> headSig;
  final Value<bool> stateLoaded;
  final Value<bool> deleted;
  final Value<Uint8List> titlePayload;
  final Value<String?> title;
  final Value<Uint8List?> inviteSeed;
  final Value<String?> invitedBySnowId;
  final Value<int?> myKeyRevision;
  final Value<int?> myKeyAtMs;
  final Value<int?> lastRemovalRevision;
  final Value<bool> resetPending;
  final Value<int> lastSyncAtMs;
  final Value<int?> changeSentAtMs;
  final Value<int> rowid;
  const Gv2GroupsCompanion({
    this.groupId = const Value.absent(),
    this.masterKey = const Value.absent(),
    this.myCiphertext = const Value.absent(),
    this.protocolVersion = const Value.absent(),
    this.membership = const Value.absent(),
    this.hold = const Value.absent(),
    this.holdEvidence = const Value.absent(),
    this.revision = const Value.absent(),
    this.chain = const Value.absent(),
    this.stateHash = const Value.absent(),
    this.headSig = const Value.absent(),
    this.stateLoaded = const Value.absent(),
    this.deleted = const Value.absent(),
    this.titlePayload = const Value.absent(),
    this.title = const Value.absent(),
    this.inviteSeed = const Value.absent(),
    this.invitedBySnowId = const Value.absent(),
    this.myKeyRevision = const Value.absent(),
    this.myKeyAtMs = const Value.absent(),
    this.lastRemovalRevision = const Value.absent(),
    this.resetPending = const Value.absent(),
    this.lastSyncAtMs = const Value.absent(),
    this.changeSentAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Gv2GroupsCompanion.insert({
    required String groupId,
    required Uint8List masterKey,
    required String myCiphertext,
    required int protocolVersion,
    required Gv2Membership membership,
    this.hold = const Value.absent(),
    this.holdEvidence = const Value.absent(),
    required int revision,
    required Uint8List chain,
    required Uint8List stateHash,
    this.headSig = const Value.absent(),
    required bool stateLoaded,
    this.deleted = const Value.absent(),
    required Uint8List titlePayload,
    this.title = const Value.absent(),
    this.inviteSeed = const Value.absent(),
    this.invitedBySnowId = const Value.absent(),
    this.myKeyRevision = const Value.absent(),
    this.myKeyAtMs = const Value.absent(),
    this.lastRemovalRevision = const Value.absent(),
    this.resetPending = const Value.absent(),
    this.lastSyncAtMs = const Value.absent(),
    this.changeSentAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       masterKey = Value(masterKey),
       myCiphertext = Value(myCiphertext),
       protocolVersion = Value(protocolVersion),
       membership = Value(membership),
       revision = Value(revision),
       chain = Value(chain),
       stateHash = Value(stateHash),
       stateLoaded = Value(stateLoaded),
       titlePayload = Value(titlePayload);
  static Insertable<Gv2GroupRow> custom({
    Expression<String>? groupId,
    Expression<Uint8List>? masterKey,
    Expression<String>? myCiphertext,
    Expression<int>? protocolVersion,
    Expression<String>? membership,
    Expression<String>? hold,
    Expression<Uint8List>? holdEvidence,
    Expression<int>? revision,
    Expression<Uint8List>? chain,
    Expression<Uint8List>? stateHash,
    Expression<Uint8List>? headSig,
    Expression<bool>? stateLoaded,
    Expression<bool>? deleted,
    Expression<Uint8List>? titlePayload,
    Expression<String>? title,
    Expression<Uint8List>? inviteSeed,
    Expression<String>? invitedBySnowId,
    Expression<int>? myKeyRevision,
    Expression<int>? myKeyAtMs,
    Expression<int>? lastRemovalRevision,
    Expression<bool>? resetPending,
    Expression<int>? lastSyncAtMs,
    Expression<int>? changeSentAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (masterKey != null) 'master_key': masterKey,
      if (myCiphertext != null) 'my_ciphertext': myCiphertext,
      if (protocolVersion != null) 'protocol_version': protocolVersion,
      if (membership != null) 'membership': membership,
      if (hold != null) 'hold': hold,
      if (holdEvidence != null) 'hold_evidence': holdEvidence,
      if (revision != null) 'revision': revision,
      if (chain != null) 'chain': chain,
      if (stateHash != null) 'state_hash': stateHash,
      if (headSig != null) 'head_sig': headSig,
      if (stateLoaded != null) 'state_loaded': stateLoaded,
      if (deleted != null) 'deleted': deleted,
      if (titlePayload != null) 'title_payload': titlePayload,
      if (title != null) 'title': title,
      if (inviteSeed != null) 'invite_seed': inviteSeed,
      if (invitedBySnowId != null) 'invited_by_snow_id': invitedBySnowId,
      if (myKeyRevision != null) 'my_key_revision': myKeyRevision,
      if (myKeyAtMs != null) 'my_key_at_ms': myKeyAtMs,
      if (lastRemovalRevision != null)
        'last_removal_revision': lastRemovalRevision,
      if (resetPending != null) 'reset_pending': resetPending,
      if (lastSyncAtMs != null) 'last_sync_at_ms': lastSyncAtMs,
      if (changeSentAtMs != null) 'change_sent_at_ms': changeSentAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Gv2GroupsCompanion copyWith({
    Value<String>? groupId,
    Value<Uint8List>? masterKey,
    Value<String>? myCiphertext,
    Value<int>? protocolVersion,
    Value<Gv2Membership>? membership,
    Value<Gv2Hold>? hold,
    Value<Uint8List?>? holdEvidence,
    Value<int>? revision,
    Value<Uint8List>? chain,
    Value<Uint8List>? stateHash,
    Value<Uint8List?>? headSig,
    Value<bool>? stateLoaded,
    Value<bool>? deleted,
    Value<Uint8List>? titlePayload,
    Value<String?>? title,
    Value<Uint8List?>? inviteSeed,
    Value<String?>? invitedBySnowId,
    Value<int?>? myKeyRevision,
    Value<int?>? myKeyAtMs,
    Value<int?>? lastRemovalRevision,
    Value<bool>? resetPending,
    Value<int>? lastSyncAtMs,
    Value<int?>? changeSentAtMs,
    Value<int>? rowid,
  }) {
    return Gv2GroupsCompanion(
      groupId: groupId ?? this.groupId,
      masterKey: masterKey ?? this.masterKey,
      myCiphertext: myCiphertext ?? this.myCiphertext,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      membership: membership ?? this.membership,
      hold: hold ?? this.hold,
      holdEvidence: holdEvidence ?? this.holdEvidence,
      revision: revision ?? this.revision,
      chain: chain ?? this.chain,
      stateHash: stateHash ?? this.stateHash,
      headSig: headSig ?? this.headSig,
      stateLoaded: stateLoaded ?? this.stateLoaded,
      deleted: deleted ?? this.deleted,
      titlePayload: titlePayload ?? this.titlePayload,
      title: title ?? this.title,
      inviteSeed: inviteSeed ?? this.inviteSeed,
      invitedBySnowId: invitedBySnowId ?? this.invitedBySnowId,
      myKeyRevision: myKeyRevision ?? this.myKeyRevision,
      myKeyAtMs: myKeyAtMs ?? this.myKeyAtMs,
      lastRemovalRevision: lastRemovalRevision ?? this.lastRemovalRevision,
      resetPending: resetPending ?? this.resetPending,
      lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
      changeSentAtMs: changeSentAtMs ?? this.changeSentAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (masterKey.present) {
      map['master_key'] = Variable<Uint8List>(masterKey.value);
    }
    if (myCiphertext.present) {
      map['my_ciphertext'] = Variable<String>(myCiphertext.value);
    }
    if (protocolVersion.present) {
      map['protocol_version'] = Variable<int>(protocolVersion.value);
    }
    if (membership.present) {
      map['membership'] = Variable<String>(
        $Gv2GroupsTable.$convertermembership.toSql(membership.value),
      );
    }
    if (hold.present) {
      map['hold'] = Variable<String>(
        $Gv2GroupsTable.$converterhold.toSql(hold.value),
      );
    }
    if (holdEvidence.present) {
      map['hold_evidence'] = Variable<Uint8List>(holdEvidence.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (chain.present) {
      map['chain'] = Variable<Uint8List>(chain.value);
    }
    if (stateHash.present) {
      map['state_hash'] = Variable<Uint8List>(stateHash.value);
    }
    if (headSig.present) {
      map['head_sig'] = Variable<Uint8List>(headSig.value);
    }
    if (stateLoaded.present) {
      map['state_loaded'] = Variable<bool>(stateLoaded.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (titlePayload.present) {
      map['title_payload'] = Variable<Uint8List>(titlePayload.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (inviteSeed.present) {
      map['invite_seed'] = Variable<Uint8List>(inviteSeed.value);
    }
    if (invitedBySnowId.present) {
      map['invited_by_snow_id'] = Variable<String>(invitedBySnowId.value);
    }
    if (myKeyRevision.present) {
      map['my_key_revision'] = Variable<int>(myKeyRevision.value);
    }
    if (myKeyAtMs.present) {
      map['my_key_at_ms'] = Variable<int>(myKeyAtMs.value);
    }
    if (lastRemovalRevision.present) {
      map['last_removal_revision'] = Variable<int>(lastRemovalRevision.value);
    }
    if (resetPending.present) {
      map['reset_pending'] = Variable<bool>(resetPending.value);
    }
    if (lastSyncAtMs.present) {
      map['last_sync_at_ms'] = Variable<int>(lastSyncAtMs.value);
    }
    if (changeSentAtMs.present) {
      map['change_sent_at_ms'] = Variable<int>(changeSentAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2GroupsCompanion(')
          ..write('groupId: $groupId, ')
          ..write('masterKey: $masterKey, ')
          ..write('myCiphertext: $myCiphertext, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('membership: $membership, ')
          ..write('hold: $hold, ')
          ..write('holdEvidence: $holdEvidence, ')
          ..write('revision: $revision, ')
          ..write('chain: $chain, ')
          ..write('stateHash: $stateHash, ')
          ..write('headSig: $headSig, ')
          ..write('stateLoaded: $stateLoaded, ')
          ..write('deleted: $deleted, ')
          ..write('titlePayload: $titlePayload, ')
          ..write('title: $title, ')
          ..write('inviteSeed: $inviteSeed, ')
          ..write('invitedBySnowId: $invitedBySnowId, ')
          ..write('myKeyRevision: $myKeyRevision, ')
          ..write('myKeyAtMs: $myKeyAtMs, ')
          ..write('lastRemovalRevision: $lastRemovalRevision, ')
          ..write('resetPending: $resetPending, ')
          ..write('lastSyncAtMs: $lastSyncAtMs, ')
          ..write('changeSentAtMs: $changeSentAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Gv2MembersTable extends Gv2Members
    with TableInfo<$Gv2MembersTable, Gv2MemberRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2MembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ciphertextMeta = const VerificationMeta(
    'ciphertext',
  );
  @override
  late final GeneratedColumn<String> ciphertext = GeneratedColumn<String>(
    'ciphertext',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 130,
      maxTextLength: 130,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<int> role = GeneratedColumn<int>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _memberPubMeta = const VerificationMeta(
    'memberPub',
  );
  @override
  late final GeneratedColumn<Uint8List> memberPub = GeneratedColumn<Uint8List>(
    'member_pub',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _joinedRevisionMeta = const VerificationMeta(
    'joinedRevision',
  );
  @override
  late final GeneratedColumn<int> joinedRevision = GeneratedColumn<int>(
    'joined_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _memberPayloadMeta = const VerificationMeta(
    'memberPayload',
  );
  @override
  late final GeneratedColumn<Uint8List> memberPayload =
      GeneratedColumn<Uint8List>(
        'member_payload',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  @override
  late final GeneratedColumnWithTypeConverter<Gv2MemberCheckState, String>
  checkState = GeneratedColumn<String>(
    'check_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: Constant(Gv2MemberCheckState.unchecked.name),
  ).withConverter<Gv2MemberCheckState>($Gv2MembersTable.$convertercheckState);
  static const VerificationMeta _snowIdMeta = const VerificationMeta('snowId');
  @override
  late final GeneratedColumn<String> snowId = GeneratedColumn<String>(
    'snow_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accountPublicKeyMeta = const VerificationMeta(
    'accountPublicKey',
  );
  @override
  late final GeneratedColumn<Uint8List> accountPublicKey =
      GeneratedColumn<Uint8List>(
        'account_public_key',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _certIssuedAtMsMeta = const VerificationMeta(
    'certIssuedAtMs',
  );
  @override
  late final GeneratedColumn<int> certIssuedAtMs = GeneratedColumn<int>(
    'cert_issued_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Gv2Reach, String> reach =
      GeneratedColumn<String>(
        'reach',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(Gv2Reach.ok.name),
      ).withConverter<Gv2Reach>($Gv2MembersTable.$converterreach);
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nicknameFetchedDayMeta =
      const VerificationMeta('nicknameFetchedDay');
  @override
  late final GeneratedColumn<int> nicknameFetchedDay = GeneratedColumn<int>(
    'nickname_fetched_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    ciphertext,
    role,
    memberPub,
    joinedRevision,
    memberPayload,
    checkState,
    snowId,
    accountPublicKey,
    certIssuedAtMs,
    reach,
    nickname,
    nicknameFetchedDay,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2MemberRow> instance, {
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
    if (data.containsKey('ciphertext')) {
      context.handle(
        _ciphertextMeta,
        ciphertext.isAcceptableOrUnknown(data['ciphertext']!, _ciphertextMeta),
      );
    } else if (isInserting) {
      context.missing(_ciphertextMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('member_pub')) {
      context.handle(
        _memberPubMeta,
        memberPub.isAcceptableOrUnknown(data['member_pub']!, _memberPubMeta),
      );
    } else if (isInserting) {
      context.missing(_memberPubMeta);
    }
    if (data.containsKey('joined_revision')) {
      context.handle(
        _joinedRevisionMeta,
        joinedRevision.isAcceptableOrUnknown(
          data['joined_revision']!,
          _joinedRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_joinedRevisionMeta);
    }
    if (data.containsKey('member_payload')) {
      context.handle(
        _memberPayloadMeta,
        memberPayload.isAcceptableOrUnknown(
          data['member_payload']!,
          _memberPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_memberPayloadMeta);
    }
    if (data.containsKey('snow_id')) {
      context.handle(
        _snowIdMeta,
        snowId.isAcceptableOrUnknown(data['snow_id']!, _snowIdMeta),
      );
    }
    if (data.containsKey('account_public_key')) {
      context.handle(
        _accountPublicKeyMeta,
        accountPublicKey.isAcceptableOrUnknown(
          data['account_public_key']!,
          _accountPublicKeyMeta,
        ),
      );
    }
    if (data.containsKey('cert_issued_at_ms')) {
      context.handle(
        _certIssuedAtMsMeta,
        certIssuedAtMs.isAcceptableOrUnknown(
          data['cert_issued_at_ms']!,
          _certIssuedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    }
    if (data.containsKey('nickname_fetched_day')) {
      context.handle(
        _nicknameFetchedDayMeta,
        nicknameFetchedDay.isAcceptableOrUnknown(
          data['nickname_fetched_day']!,
          _nicknameFetchedDayMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, ciphertext};
  @override
  Gv2MemberRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2MemberRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      ciphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ciphertext'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}role'],
      )!,
      memberPub: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}member_pub'],
      )!,
      joinedRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}joined_revision'],
      )!,
      memberPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}member_payload'],
      )!,
      checkState: $Gv2MembersTable.$convertercheckState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}check_state'],
        )!,
      ),
      snowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snow_id'],
      ),
      accountPublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}account_public_key'],
      ),
      certIssuedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cert_issued_at_ms'],
      ),
      reach: $Gv2MembersTable.$converterreach.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}reach'],
        )!,
      ),
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      ),
      nicknameFetchedDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}nickname_fetched_day'],
      ),
    );
  }

  @override
  $Gv2MembersTable createAlias(String alias) {
    return $Gv2MembersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Gv2MemberCheckState, String, String>
  $convertercheckState = const EnumNameConverter<Gv2MemberCheckState>(
    Gv2MemberCheckState.values,
  );
  static JsonTypeConverter2<Gv2Reach, String, String> $converterreach =
      const EnumNameConverter<Gv2Reach>(Gv2Reach.values);
}

class Gv2MemberRow extends DataClass implements Insertable<Gv2MemberRow> {
  final String groupId;

  /// Member ciphertext, 130 hex characters.
  final String ciphertext;

  /// 0 member, 1 admin, 2 owner.
  final int role;

  /// 32-byte member signing public key.
  final Uint8List memberPub;
  final int joinedRevision;

  /// Sealed member payload, exactly as in the log (state hash input).
  final Uint8List memberPayload;
  final Gv2MemberCheckState checkState;

  /// The account the ciphertext decrypts to; null until it has been
  /// decrypted. Known even when the check then fails.
  final String? snowId;

  /// Confirmed 32-byte account public key; set only when confirmed.
  final Uint8List? accountPublicKey;

  /// Time of the member certificate, Unix milliseconds; set only when
  /// confirmed. A deletion proof is compared with it.
  final int? certIssuedAtMs;
  final Gv2Reach reach;

  /// Nickname looked up from the server (display only, never identity).
  final String? nickname;

  /// Local day number (days since the epoch) of the last nickname lookup.
  final int? nicknameFetchedDay;
  const Gv2MemberRow({
    required this.groupId,
    required this.ciphertext,
    required this.role,
    required this.memberPub,
    required this.joinedRevision,
    required this.memberPayload,
    required this.checkState,
    this.snowId,
    this.accountPublicKey,
    this.certIssuedAtMs,
    required this.reach,
    this.nickname,
    this.nicknameFetchedDay,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['ciphertext'] = Variable<String>(ciphertext);
    map['role'] = Variable<int>(role);
    map['member_pub'] = Variable<Uint8List>(memberPub);
    map['joined_revision'] = Variable<int>(joinedRevision);
    map['member_payload'] = Variable<Uint8List>(memberPayload);
    {
      map['check_state'] = Variable<String>(
        $Gv2MembersTable.$convertercheckState.toSql(checkState),
      );
    }
    if (!nullToAbsent || snowId != null) {
      map['snow_id'] = Variable<String>(snowId);
    }
    if (!nullToAbsent || accountPublicKey != null) {
      map['account_public_key'] = Variable<Uint8List>(accountPublicKey);
    }
    if (!nullToAbsent || certIssuedAtMs != null) {
      map['cert_issued_at_ms'] = Variable<int>(certIssuedAtMs);
    }
    {
      map['reach'] = Variable<String>(
        $Gv2MembersTable.$converterreach.toSql(reach),
      );
    }
    if (!nullToAbsent || nickname != null) {
      map['nickname'] = Variable<String>(nickname);
    }
    if (!nullToAbsent || nicknameFetchedDay != null) {
      map['nickname_fetched_day'] = Variable<int>(nicknameFetchedDay);
    }
    return map;
  }

  Gv2MembersCompanion toCompanion(bool nullToAbsent) {
    return Gv2MembersCompanion(
      groupId: Value(groupId),
      ciphertext: Value(ciphertext),
      role: Value(role),
      memberPub: Value(memberPub),
      joinedRevision: Value(joinedRevision),
      memberPayload: Value(memberPayload),
      checkState: Value(checkState),
      snowId: snowId == null && nullToAbsent
          ? const Value.absent()
          : Value(snowId),
      accountPublicKey: accountPublicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(accountPublicKey),
      certIssuedAtMs: certIssuedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(certIssuedAtMs),
      reach: Value(reach),
      nickname: nickname == null && nullToAbsent
          ? const Value.absent()
          : Value(nickname),
      nicknameFetchedDay: nicknameFetchedDay == null && nullToAbsent
          ? const Value.absent()
          : Value(nicknameFetchedDay),
    );
  }

  factory Gv2MemberRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2MemberRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      ciphertext: serializer.fromJson<String>(json['ciphertext']),
      role: serializer.fromJson<int>(json['role']),
      memberPub: serializer.fromJson<Uint8List>(json['memberPub']),
      joinedRevision: serializer.fromJson<int>(json['joinedRevision']),
      memberPayload: serializer.fromJson<Uint8List>(json['memberPayload']),
      checkState: $Gv2MembersTable.$convertercheckState.fromJson(
        serializer.fromJson<String>(json['checkState']),
      ),
      snowId: serializer.fromJson<String?>(json['snowId']),
      accountPublicKey: serializer.fromJson<Uint8List?>(
        json['accountPublicKey'],
      ),
      certIssuedAtMs: serializer.fromJson<int?>(json['certIssuedAtMs']),
      reach: $Gv2MembersTable.$converterreach.fromJson(
        serializer.fromJson<String>(json['reach']),
      ),
      nickname: serializer.fromJson<String?>(json['nickname']),
      nicknameFetchedDay: serializer.fromJson<int?>(json['nicknameFetchedDay']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'ciphertext': serializer.toJson<String>(ciphertext),
      'role': serializer.toJson<int>(role),
      'memberPub': serializer.toJson<Uint8List>(memberPub),
      'joinedRevision': serializer.toJson<int>(joinedRevision),
      'memberPayload': serializer.toJson<Uint8List>(memberPayload),
      'checkState': serializer.toJson<String>(
        $Gv2MembersTable.$convertercheckState.toJson(checkState),
      ),
      'snowId': serializer.toJson<String?>(snowId),
      'accountPublicKey': serializer.toJson<Uint8List?>(accountPublicKey),
      'certIssuedAtMs': serializer.toJson<int?>(certIssuedAtMs),
      'reach': serializer.toJson<String>(
        $Gv2MembersTable.$converterreach.toJson(reach),
      ),
      'nickname': serializer.toJson<String?>(nickname),
      'nicknameFetchedDay': serializer.toJson<int?>(nicknameFetchedDay),
    };
  }

  Gv2MemberRow copyWith({
    String? groupId,
    String? ciphertext,
    int? role,
    Uint8List? memberPub,
    int? joinedRevision,
    Uint8List? memberPayload,
    Gv2MemberCheckState? checkState,
    Value<String?> snowId = const Value.absent(),
    Value<Uint8List?> accountPublicKey = const Value.absent(),
    Value<int?> certIssuedAtMs = const Value.absent(),
    Gv2Reach? reach,
    Value<String?> nickname = const Value.absent(),
    Value<int?> nicknameFetchedDay = const Value.absent(),
  }) => Gv2MemberRow(
    groupId: groupId ?? this.groupId,
    ciphertext: ciphertext ?? this.ciphertext,
    role: role ?? this.role,
    memberPub: memberPub ?? this.memberPub,
    joinedRevision: joinedRevision ?? this.joinedRevision,
    memberPayload: memberPayload ?? this.memberPayload,
    checkState: checkState ?? this.checkState,
    snowId: snowId.present ? snowId.value : this.snowId,
    accountPublicKey: accountPublicKey.present
        ? accountPublicKey.value
        : this.accountPublicKey,
    certIssuedAtMs: certIssuedAtMs.present
        ? certIssuedAtMs.value
        : this.certIssuedAtMs,
    reach: reach ?? this.reach,
    nickname: nickname.present ? nickname.value : this.nickname,
    nicknameFetchedDay: nicknameFetchedDay.present
        ? nicknameFetchedDay.value
        : this.nicknameFetchedDay,
  );
  Gv2MemberRow copyWithCompanion(Gv2MembersCompanion data) {
    return Gv2MemberRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      ciphertext: data.ciphertext.present
          ? data.ciphertext.value
          : this.ciphertext,
      role: data.role.present ? data.role.value : this.role,
      memberPub: data.memberPub.present ? data.memberPub.value : this.memberPub,
      joinedRevision: data.joinedRevision.present
          ? data.joinedRevision.value
          : this.joinedRevision,
      memberPayload: data.memberPayload.present
          ? data.memberPayload.value
          : this.memberPayload,
      checkState: data.checkState.present
          ? data.checkState.value
          : this.checkState,
      snowId: data.snowId.present ? data.snowId.value : this.snowId,
      accountPublicKey: data.accountPublicKey.present
          ? data.accountPublicKey.value
          : this.accountPublicKey,
      certIssuedAtMs: data.certIssuedAtMs.present
          ? data.certIssuedAtMs.value
          : this.certIssuedAtMs,
      reach: data.reach.present ? data.reach.value : this.reach,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      nicknameFetchedDay: data.nicknameFetchedDay.present
          ? data.nicknameFetchedDay.value
          : this.nicknameFetchedDay,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2MemberRow(')
          ..write('groupId: $groupId, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('role: $role, ')
          ..write('memberPub: $memberPub, ')
          ..write('joinedRevision: $joinedRevision, ')
          ..write('memberPayload: $memberPayload, ')
          ..write('checkState: $checkState, ')
          ..write('snowId: $snowId, ')
          ..write('accountPublicKey: $accountPublicKey, ')
          ..write('certIssuedAtMs: $certIssuedAtMs, ')
          ..write('reach: $reach, ')
          ..write('nickname: $nickname, ')
          ..write('nicknameFetchedDay: $nicknameFetchedDay')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    ciphertext,
    role,
    $driftBlobEquality.hash(memberPub),
    joinedRevision,
    $driftBlobEquality.hash(memberPayload),
    checkState,
    snowId,
    $driftBlobEquality.hash(accountPublicKey),
    certIssuedAtMs,
    reach,
    nickname,
    nicknameFetchedDay,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2MemberRow &&
          other.groupId == this.groupId &&
          other.ciphertext == this.ciphertext &&
          other.role == this.role &&
          $driftBlobEquality.equals(other.memberPub, this.memberPub) &&
          other.joinedRevision == this.joinedRevision &&
          $driftBlobEquality.equals(other.memberPayload, this.memberPayload) &&
          other.checkState == this.checkState &&
          other.snowId == this.snowId &&
          $driftBlobEquality.equals(
            other.accountPublicKey,
            this.accountPublicKey,
          ) &&
          other.certIssuedAtMs == this.certIssuedAtMs &&
          other.reach == this.reach &&
          other.nickname == this.nickname &&
          other.nicknameFetchedDay == this.nicknameFetchedDay);
}

class Gv2MembersCompanion extends UpdateCompanion<Gv2MemberRow> {
  final Value<String> groupId;
  final Value<String> ciphertext;
  final Value<int> role;
  final Value<Uint8List> memberPub;
  final Value<int> joinedRevision;
  final Value<Uint8List> memberPayload;
  final Value<Gv2MemberCheckState> checkState;
  final Value<String?> snowId;
  final Value<Uint8List?> accountPublicKey;
  final Value<int?> certIssuedAtMs;
  final Value<Gv2Reach> reach;
  final Value<String?> nickname;
  final Value<int?> nicknameFetchedDay;
  final Value<int> rowid;
  const Gv2MembersCompanion({
    this.groupId = const Value.absent(),
    this.ciphertext = const Value.absent(),
    this.role = const Value.absent(),
    this.memberPub = const Value.absent(),
    this.joinedRevision = const Value.absent(),
    this.memberPayload = const Value.absent(),
    this.checkState = const Value.absent(),
    this.snowId = const Value.absent(),
    this.accountPublicKey = const Value.absent(),
    this.certIssuedAtMs = const Value.absent(),
    this.reach = const Value.absent(),
    this.nickname = const Value.absent(),
    this.nicknameFetchedDay = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Gv2MembersCompanion.insert({
    required String groupId,
    required String ciphertext,
    required int role,
    required Uint8List memberPub,
    required int joinedRevision,
    required Uint8List memberPayload,
    this.checkState = const Value.absent(),
    this.snowId = const Value.absent(),
    this.accountPublicKey = const Value.absent(),
    this.certIssuedAtMs = const Value.absent(),
    this.reach = const Value.absent(),
    this.nickname = const Value.absent(),
    this.nicknameFetchedDay = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       ciphertext = Value(ciphertext),
       role = Value(role),
       memberPub = Value(memberPub),
       joinedRevision = Value(joinedRevision),
       memberPayload = Value(memberPayload);
  static Insertable<Gv2MemberRow> custom({
    Expression<String>? groupId,
    Expression<String>? ciphertext,
    Expression<int>? role,
    Expression<Uint8List>? memberPub,
    Expression<int>? joinedRevision,
    Expression<Uint8List>? memberPayload,
    Expression<String>? checkState,
    Expression<String>? snowId,
    Expression<Uint8List>? accountPublicKey,
    Expression<int>? certIssuedAtMs,
    Expression<String>? reach,
    Expression<String>? nickname,
    Expression<int>? nicknameFetchedDay,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (ciphertext != null) 'ciphertext': ciphertext,
      if (role != null) 'role': role,
      if (memberPub != null) 'member_pub': memberPub,
      if (joinedRevision != null) 'joined_revision': joinedRevision,
      if (memberPayload != null) 'member_payload': memberPayload,
      if (checkState != null) 'check_state': checkState,
      if (snowId != null) 'snow_id': snowId,
      if (accountPublicKey != null) 'account_public_key': accountPublicKey,
      if (certIssuedAtMs != null) 'cert_issued_at_ms': certIssuedAtMs,
      if (reach != null) 'reach': reach,
      if (nickname != null) 'nickname': nickname,
      if (nicknameFetchedDay != null)
        'nickname_fetched_day': nicknameFetchedDay,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Gv2MembersCompanion copyWith({
    Value<String>? groupId,
    Value<String>? ciphertext,
    Value<int>? role,
    Value<Uint8List>? memberPub,
    Value<int>? joinedRevision,
    Value<Uint8List>? memberPayload,
    Value<Gv2MemberCheckState>? checkState,
    Value<String?>? snowId,
    Value<Uint8List?>? accountPublicKey,
    Value<int?>? certIssuedAtMs,
    Value<Gv2Reach>? reach,
    Value<String?>? nickname,
    Value<int?>? nicknameFetchedDay,
    Value<int>? rowid,
  }) {
    return Gv2MembersCompanion(
      groupId: groupId ?? this.groupId,
      ciphertext: ciphertext ?? this.ciphertext,
      role: role ?? this.role,
      memberPub: memberPub ?? this.memberPub,
      joinedRevision: joinedRevision ?? this.joinedRevision,
      memberPayload: memberPayload ?? this.memberPayload,
      checkState: checkState ?? this.checkState,
      snowId: snowId ?? this.snowId,
      accountPublicKey: accountPublicKey ?? this.accountPublicKey,
      certIssuedAtMs: certIssuedAtMs ?? this.certIssuedAtMs,
      reach: reach ?? this.reach,
      nickname: nickname ?? this.nickname,
      nicknameFetchedDay: nicknameFetchedDay ?? this.nicknameFetchedDay,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (ciphertext.present) {
      map['ciphertext'] = Variable<String>(ciphertext.value);
    }
    if (role.present) {
      map['role'] = Variable<int>(role.value);
    }
    if (memberPub.present) {
      map['member_pub'] = Variable<Uint8List>(memberPub.value);
    }
    if (joinedRevision.present) {
      map['joined_revision'] = Variable<int>(joinedRevision.value);
    }
    if (memberPayload.present) {
      map['member_payload'] = Variable<Uint8List>(memberPayload.value);
    }
    if (checkState.present) {
      map['check_state'] = Variable<String>(
        $Gv2MembersTable.$convertercheckState.toSql(checkState.value),
      );
    }
    if (snowId.present) {
      map['snow_id'] = Variable<String>(snowId.value);
    }
    if (accountPublicKey.present) {
      map['account_public_key'] = Variable<Uint8List>(accountPublicKey.value);
    }
    if (certIssuedAtMs.present) {
      map['cert_issued_at_ms'] = Variable<int>(certIssuedAtMs.value);
    }
    if (reach.present) {
      map['reach'] = Variable<String>(
        $Gv2MembersTable.$converterreach.toSql(reach.value),
      );
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (nicknameFetchedDay.present) {
      map['nickname_fetched_day'] = Variable<int>(nicknameFetchedDay.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2MembersCompanion(')
          ..write('groupId: $groupId, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('role: $role, ')
          ..write('memberPub: $memberPub, ')
          ..write('joinedRevision: $joinedRevision, ')
          ..write('memberPayload: $memberPayload, ')
          ..write('checkState: $checkState, ')
          ..write('snowId: $snowId, ')
          ..write('accountPublicKey: $accountPublicKey, ')
          ..write('certIssuedAtMs: $certIssuedAtMs, ')
          ..write('reach: $reach, ')
          ..write('nickname: $nickname, ')
          ..write('nicknameFetchedDay: $nicknameFetchedDay, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Gv2PendingTable extends Gv2Pending
    with TableInfo<$Gv2PendingTable, Gv2PendingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2PendingTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ciphertextMeta = const VerificationMeta(
    'ciphertext',
  );
  @override
  late final GeneratedColumn<String> ciphertext = GeneratedColumn<String>(
    'ciphertext',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 130,
      maxTextLength: 130,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _invitedByMeta = const VerificationMeta(
    'invitedBy',
  );
  @override
  late final GeneratedColumn<String> invitedBy = GeneratedColumn<String>(
    'invited_by',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 130,
      maxTextLength: 130,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _invitePubMeta = const VerificationMeta(
    'invitePub',
  );
  @override
  late final GeneratedColumn<Uint8List> invitePub = GeneratedColumn<Uint8List>(
    'invite_pub',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snowIdMeta = const VerificationMeta('snowId');
  @override
  late final GeneratedColumn<String> snowId = GeneratedColumn<String>(
    'snow_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    ciphertext,
    invitedBy,
    invitePub,
    revision,
    snowId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_pending';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2PendingRow> instance, {
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
    if (data.containsKey('ciphertext')) {
      context.handle(
        _ciphertextMeta,
        ciphertext.isAcceptableOrUnknown(data['ciphertext']!, _ciphertextMeta),
      );
    } else if (isInserting) {
      context.missing(_ciphertextMeta);
    }
    if (data.containsKey('invited_by')) {
      context.handle(
        _invitedByMeta,
        invitedBy.isAcceptableOrUnknown(data['invited_by']!, _invitedByMeta),
      );
    } else if (isInserting) {
      context.missing(_invitedByMeta);
    }
    if (data.containsKey('invite_pub')) {
      context.handle(
        _invitePubMeta,
        invitePub.isAcceptableOrUnknown(data['invite_pub']!, _invitePubMeta),
      );
    } else if (isInserting) {
      context.missing(_invitePubMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('snow_id')) {
      context.handle(
        _snowIdMeta,
        snowId.isAcceptableOrUnknown(data['snow_id']!, _snowIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, ciphertext};
  @override
  Gv2PendingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2PendingRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      ciphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ciphertext'],
      )!,
      invitedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invited_by'],
      )!,
      invitePub: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}invite_pub'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      snowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snow_id'],
      ),
    );
  }

  @override
  $Gv2PendingTable createAlias(String alias) {
    return $Gv2PendingTable(attachedDatabase, alias);
  }
}

class Gv2PendingRow extends DataClass implements Insertable<Gv2PendingRow> {
  final String groupId;

  /// Ciphertext of the invited account, 130 hex characters.
  final String ciphertext;

  /// Ciphertext of the member who invited, 130 hex characters.
  final String invitedBy;

  /// 32-byte one-time invite public key.
  final Uint8List invitePub;

  /// Revision of the INVITE.
  final int revision;

  /// The account the ciphertext decrypts to; null until decrypted.
  final String? snowId;
  const Gv2PendingRow({
    required this.groupId,
    required this.ciphertext,
    required this.invitedBy,
    required this.invitePub,
    required this.revision,
    this.snowId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['ciphertext'] = Variable<String>(ciphertext);
    map['invited_by'] = Variable<String>(invitedBy);
    map['invite_pub'] = Variable<Uint8List>(invitePub);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || snowId != null) {
      map['snow_id'] = Variable<String>(snowId);
    }
    return map;
  }

  Gv2PendingCompanion toCompanion(bool nullToAbsent) {
    return Gv2PendingCompanion(
      groupId: Value(groupId),
      ciphertext: Value(ciphertext),
      invitedBy: Value(invitedBy),
      invitePub: Value(invitePub),
      revision: Value(revision),
      snowId: snowId == null && nullToAbsent
          ? const Value.absent()
          : Value(snowId),
    );
  }

  factory Gv2PendingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2PendingRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      ciphertext: serializer.fromJson<String>(json['ciphertext']),
      invitedBy: serializer.fromJson<String>(json['invitedBy']),
      invitePub: serializer.fromJson<Uint8List>(json['invitePub']),
      revision: serializer.fromJson<int>(json['revision']),
      snowId: serializer.fromJson<String?>(json['snowId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'ciphertext': serializer.toJson<String>(ciphertext),
      'invitedBy': serializer.toJson<String>(invitedBy),
      'invitePub': serializer.toJson<Uint8List>(invitePub),
      'revision': serializer.toJson<int>(revision),
      'snowId': serializer.toJson<String?>(snowId),
    };
  }

  Gv2PendingRow copyWith({
    String? groupId,
    String? ciphertext,
    String? invitedBy,
    Uint8List? invitePub,
    int? revision,
    Value<String?> snowId = const Value.absent(),
  }) => Gv2PendingRow(
    groupId: groupId ?? this.groupId,
    ciphertext: ciphertext ?? this.ciphertext,
    invitedBy: invitedBy ?? this.invitedBy,
    invitePub: invitePub ?? this.invitePub,
    revision: revision ?? this.revision,
    snowId: snowId.present ? snowId.value : this.snowId,
  );
  Gv2PendingRow copyWithCompanion(Gv2PendingCompanion data) {
    return Gv2PendingRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      ciphertext: data.ciphertext.present
          ? data.ciphertext.value
          : this.ciphertext,
      invitedBy: data.invitedBy.present ? data.invitedBy.value : this.invitedBy,
      invitePub: data.invitePub.present ? data.invitePub.value : this.invitePub,
      revision: data.revision.present ? data.revision.value : this.revision,
      snowId: data.snowId.present ? data.snowId.value : this.snowId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2PendingRow(')
          ..write('groupId: $groupId, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('invitedBy: $invitedBy, ')
          ..write('invitePub: $invitePub, ')
          ..write('revision: $revision, ')
          ..write('snowId: $snowId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    ciphertext,
    invitedBy,
    $driftBlobEquality.hash(invitePub),
    revision,
    snowId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2PendingRow &&
          other.groupId == this.groupId &&
          other.ciphertext == this.ciphertext &&
          other.invitedBy == this.invitedBy &&
          $driftBlobEquality.equals(other.invitePub, this.invitePub) &&
          other.revision == this.revision &&
          other.snowId == this.snowId);
}

class Gv2PendingCompanion extends UpdateCompanion<Gv2PendingRow> {
  final Value<String> groupId;
  final Value<String> ciphertext;
  final Value<String> invitedBy;
  final Value<Uint8List> invitePub;
  final Value<int> revision;
  final Value<String?> snowId;
  final Value<int> rowid;
  const Gv2PendingCompanion({
    this.groupId = const Value.absent(),
    this.ciphertext = const Value.absent(),
    this.invitedBy = const Value.absent(),
    this.invitePub = const Value.absent(),
    this.revision = const Value.absent(),
    this.snowId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Gv2PendingCompanion.insert({
    required String groupId,
    required String ciphertext,
    required String invitedBy,
    required Uint8List invitePub,
    required int revision,
    this.snowId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       ciphertext = Value(ciphertext),
       invitedBy = Value(invitedBy),
       invitePub = Value(invitePub),
       revision = Value(revision);
  static Insertable<Gv2PendingRow> custom({
    Expression<String>? groupId,
    Expression<String>? ciphertext,
    Expression<String>? invitedBy,
    Expression<Uint8List>? invitePub,
    Expression<int>? revision,
    Expression<String>? snowId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (ciphertext != null) 'ciphertext': ciphertext,
      if (invitedBy != null) 'invited_by': invitedBy,
      if (invitePub != null) 'invite_pub': invitePub,
      if (revision != null) 'revision': revision,
      if (snowId != null) 'snow_id': snowId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Gv2PendingCompanion copyWith({
    Value<String>? groupId,
    Value<String>? ciphertext,
    Value<String>? invitedBy,
    Value<Uint8List>? invitePub,
    Value<int>? revision,
    Value<String?>? snowId,
    Value<int>? rowid,
  }) {
    return Gv2PendingCompanion(
      groupId: groupId ?? this.groupId,
      ciphertext: ciphertext ?? this.ciphertext,
      invitedBy: invitedBy ?? this.invitedBy,
      invitePub: invitePub ?? this.invitePub,
      revision: revision ?? this.revision,
      snowId: snowId ?? this.snowId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (ciphertext.present) {
      map['ciphertext'] = Variable<String>(ciphertext.value);
    }
    if (invitedBy.present) {
      map['invited_by'] = Variable<String>(invitedBy.value);
    }
    if (invitePub.present) {
      map['invite_pub'] = Variable<Uint8List>(invitePub.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (snowId.present) {
      map['snow_id'] = Variable<String>(snowId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2PendingCompanion(')
          ..write('groupId: $groupId, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('invitedBy: $invitedBy, ')
          ..write('invitePub: $invitePub, ')
          ..write('revision: $revision, ')
          ..write('snowId: $snowId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Gv2ServerKeysTable extends Gv2ServerKeys
    with TableInfo<$Gv2ServerKeysTable, Gv2ServerKeysRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2ServerKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverPublicParamsMeta =
      const VerificationMeta('serverPublicParams');
  @override
  late final GeneratedColumn<Uint8List> serverPublicParams =
      GeneratedColumn<Uint8List>(
        'server_public_params',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _headPublicKeyMeta = const VerificationMeta(
    'headPublicKey',
  );
  @override
  late final GeneratedColumn<Uint8List> headPublicKey =
      GeneratedColumn<Uint8List>(
        'head_public_key',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    slot,
    serverPublicParams,
    headPublicKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_server_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2ServerKeysRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    }
    if (data.containsKey('server_public_params')) {
      context.handle(
        _serverPublicParamsMeta,
        serverPublicParams.isAcceptableOrUnknown(
          data['server_public_params']!,
          _serverPublicParamsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverPublicParamsMeta);
    }
    if (data.containsKey('head_public_key')) {
      context.handle(
        _headPublicKeyMeta,
        headPublicKey.isAcceptableOrUnknown(
          data['head_public_key']!,
          _headPublicKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_headPublicKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {slot};
  @override
  Gv2ServerKeysRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2ServerKeysRow(
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      serverPublicParams: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}server_public_params'],
      )!,
      headPublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}head_public_key'],
      )!,
    );
  }

  @override
  $Gv2ServerKeysTable createAlias(String alias) {
    return $Gv2ServerKeysTable(attachedDatabase, alias);
  }
}

class Gv2ServerKeysRow extends DataClass
    implements Insertable<Gv2ServerKeysRow> {
  /// Always 0: there is one server.
  final int slot;

  /// zkgroup server public parameters: credentials and endorsements are
  /// verified against them, presentations are made for them.
  final Uint8List serverPublicParams;

  /// 32-byte Ed25519 key the server signs log heads with.
  final Uint8List headPublicKey;
  const Gv2ServerKeysRow({
    required this.slot,
    required this.serverPublicParams,
    required this.headPublicKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['slot'] = Variable<int>(slot);
    map['server_public_params'] = Variable<Uint8List>(serverPublicParams);
    map['head_public_key'] = Variable<Uint8List>(headPublicKey);
    return map;
  }

  Gv2ServerKeysCompanion toCompanion(bool nullToAbsent) {
    return Gv2ServerKeysCompanion(
      slot: Value(slot),
      serverPublicParams: Value(serverPublicParams),
      headPublicKey: Value(headPublicKey),
    );
  }

  factory Gv2ServerKeysRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2ServerKeysRow(
      slot: serializer.fromJson<int>(json['slot']),
      serverPublicParams: serializer.fromJson<Uint8List>(
        json['serverPublicParams'],
      ),
      headPublicKey: serializer.fromJson<Uint8List>(json['headPublicKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'slot': serializer.toJson<int>(slot),
      'serverPublicParams': serializer.toJson<Uint8List>(serverPublicParams),
      'headPublicKey': serializer.toJson<Uint8List>(headPublicKey),
    };
  }

  Gv2ServerKeysRow copyWith({
    int? slot,
    Uint8List? serverPublicParams,
    Uint8List? headPublicKey,
  }) => Gv2ServerKeysRow(
    slot: slot ?? this.slot,
    serverPublicParams: serverPublicParams ?? this.serverPublicParams,
    headPublicKey: headPublicKey ?? this.headPublicKey,
  );
  Gv2ServerKeysRow copyWithCompanion(Gv2ServerKeysCompanion data) {
    return Gv2ServerKeysRow(
      slot: data.slot.present ? data.slot.value : this.slot,
      serverPublicParams: data.serverPublicParams.present
          ? data.serverPublicParams.value
          : this.serverPublicParams,
      headPublicKey: data.headPublicKey.present
          ? data.headPublicKey.value
          : this.headPublicKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2ServerKeysRow(')
          ..write('slot: $slot, ')
          ..write('serverPublicParams: $serverPublicParams, ')
          ..write('headPublicKey: $headPublicKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    slot,
    $driftBlobEquality.hash(serverPublicParams),
    $driftBlobEquality.hash(headPublicKey),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2ServerKeysRow &&
          other.slot == this.slot &&
          $driftBlobEquality.equals(
            other.serverPublicParams,
            this.serverPublicParams,
          ) &&
          $driftBlobEquality.equals(other.headPublicKey, this.headPublicKey));
}

class Gv2ServerKeysCompanion extends UpdateCompanion<Gv2ServerKeysRow> {
  final Value<int> slot;
  final Value<Uint8List> serverPublicParams;
  final Value<Uint8List> headPublicKey;
  const Gv2ServerKeysCompanion({
    this.slot = const Value.absent(),
    this.serverPublicParams = const Value.absent(),
    this.headPublicKey = const Value.absent(),
  });
  Gv2ServerKeysCompanion.insert({
    this.slot = const Value.absent(),
    required Uint8List serverPublicParams,
    required Uint8List headPublicKey,
  }) : serverPublicParams = Value(serverPublicParams),
       headPublicKey = Value(headPublicKey);
  static Insertable<Gv2ServerKeysRow> custom({
    Expression<int>? slot,
    Expression<Uint8List>? serverPublicParams,
    Expression<Uint8List>? headPublicKey,
  }) {
    return RawValuesInsertable({
      if (slot != null) 'slot': slot,
      if (serverPublicParams != null)
        'server_public_params': serverPublicParams,
      if (headPublicKey != null) 'head_public_key': headPublicKey,
    });
  }

  Gv2ServerKeysCompanion copyWith({
    Value<int>? slot,
    Value<Uint8List>? serverPublicParams,
    Value<Uint8List>? headPublicKey,
  }) {
    return Gv2ServerKeysCompanion(
      slot: slot ?? this.slot,
      serverPublicParams: serverPublicParams ?? this.serverPublicParams,
      headPublicKey: headPublicKey ?? this.headPublicKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (serverPublicParams.present) {
      map['server_public_params'] = Variable<Uint8List>(
        serverPublicParams.value,
      );
    }
    if (headPublicKey.present) {
      map['head_public_key'] = Variable<Uint8List>(headPublicKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2ServerKeysCompanion(')
          ..write('slot: $slot, ')
          ..write('serverPublicParams: $serverPublicParams, ')
          ..write('headPublicKey: $headPublicKey')
          ..write(')'))
        .toString();
  }
}

class $Gv2AuthCredentialsTable extends Gv2AuthCredentials
    with TableInfo<$Gv2AuthCredentialsTable, Gv2AuthCredentialRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2AuthCredentialsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _redemptionTimeMeta = const VerificationMeta(
    'redemptionTime',
  );
  @override
  late final GeneratedColumn<int> redemptionTime = GeneratedColumn<int>(
    'redemption_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snowIdMeta = const VerificationMeta('snowId');
  @override
  late final GeneratedColumn<String> snowId = GeneratedColumn<String>(
    'snow_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _credentialMeta = const VerificationMeta(
    'credential',
  );
  @override
  late final GeneratedColumn<Uint8List> credential = GeneratedColumn<Uint8List>(
    'credential',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [redemptionTime, snowId, credential];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_auth_credentials';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2AuthCredentialRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('redemption_time')) {
      context.handle(
        _redemptionTimeMeta,
        redemptionTime.isAcceptableOrUnknown(
          data['redemption_time']!,
          _redemptionTimeMeta,
        ),
      );
    }
    if (data.containsKey('snow_id')) {
      context.handle(
        _snowIdMeta,
        snowId.isAcceptableOrUnknown(data['snow_id']!, _snowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snowIdMeta);
    }
    if (data.containsKey('credential')) {
      context.handle(
        _credentialMeta,
        credential.isAcceptableOrUnknown(data['credential']!, _credentialMeta),
      );
    } else if (isInserting) {
      context.missing(_credentialMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {redemptionTime};
  @override
  Gv2AuthCredentialRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2AuthCredentialRow(
      redemptionTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}redemption_time'],
      )!,
      snowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snow_id'],
      )!,
      credential: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}credential'],
      )!,
    );
  }

  @override
  $Gv2AuthCredentialsTable createAlias(String alias) {
    return $Gv2AuthCredentialsTable(attachedDatabase, alias);
  }
}

class Gv2AuthCredentialRow extends DataClass
    implements Insertable<Gv2AuthCredentialRow> {
  /// Start of the UTC day the credential is for, epoch seconds.
  final int redemptionTime;

  /// The account the credential was issued to. Rows of another account are
  /// never used and are erased when this account stores its own.
  final String snowId;

  /// The verified credential. Key material.
  final Uint8List credential;
  const Gv2AuthCredentialRow({
    required this.redemptionTime,
    required this.snowId,
    required this.credential,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['redemption_time'] = Variable<int>(redemptionTime);
    map['snow_id'] = Variable<String>(snowId);
    map['credential'] = Variable<Uint8List>(credential);
    return map;
  }

  Gv2AuthCredentialsCompanion toCompanion(bool nullToAbsent) {
    return Gv2AuthCredentialsCompanion(
      redemptionTime: Value(redemptionTime),
      snowId: Value(snowId),
      credential: Value(credential),
    );
  }

  factory Gv2AuthCredentialRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2AuthCredentialRow(
      redemptionTime: serializer.fromJson<int>(json['redemptionTime']),
      snowId: serializer.fromJson<String>(json['snowId']),
      credential: serializer.fromJson<Uint8List>(json['credential']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'redemptionTime': serializer.toJson<int>(redemptionTime),
      'snowId': serializer.toJson<String>(snowId),
      'credential': serializer.toJson<Uint8List>(credential),
    };
  }

  Gv2AuthCredentialRow copyWith({
    int? redemptionTime,
    String? snowId,
    Uint8List? credential,
  }) => Gv2AuthCredentialRow(
    redemptionTime: redemptionTime ?? this.redemptionTime,
    snowId: snowId ?? this.snowId,
    credential: credential ?? this.credential,
  );
  Gv2AuthCredentialRow copyWithCompanion(Gv2AuthCredentialsCompanion data) {
    return Gv2AuthCredentialRow(
      redemptionTime: data.redemptionTime.present
          ? data.redemptionTime.value
          : this.redemptionTime,
      snowId: data.snowId.present ? data.snowId.value : this.snowId,
      credential: data.credential.present
          ? data.credential.value
          : this.credential,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2AuthCredentialRow(')
          ..write('redemptionTime: $redemptionTime, ')
          ..write('snowId: $snowId, ')
          ..write('credential: $credential')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(redemptionTime, snowId, $driftBlobEquality.hash(credential));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2AuthCredentialRow &&
          other.redemptionTime == this.redemptionTime &&
          other.snowId == this.snowId &&
          $driftBlobEquality.equals(other.credential, this.credential));
}

class Gv2AuthCredentialsCompanion
    extends UpdateCompanion<Gv2AuthCredentialRow> {
  final Value<int> redemptionTime;
  final Value<String> snowId;
  final Value<Uint8List> credential;
  const Gv2AuthCredentialsCompanion({
    this.redemptionTime = const Value.absent(),
    this.snowId = const Value.absent(),
    this.credential = const Value.absent(),
  });
  Gv2AuthCredentialsCompanion.insert({
    this.redemptionTime = const Value.absent(),
    required String snowId,
    required Uint8List credential,
  }) : snowId = Value(snowId),
       credential = Value(credential);
  static Insertable<Gv2AuthCredentialRow> custom({
    Expression<int>? redemptionTime,
    Expression<String>? snowId,
    Expression<Uint8List>? credential,
  }) {
    return RawValuesInsertable({
      if (redemptionTime != null) 'redemption_time': redemptionTime,
      if (snowId != null) 'snow_id': snowId,
      if (credential != null) 'credential': credential,
    });
  }

  Gv2AuthCredentialsCompanion copyWith({
    Value<int>? redemptionTime,
    Value<String>? snowId,
    Value<Uint8List>? credential,
  }) {
    return Gv2AuthCredentialsCompanion(
      redemptionTime: redemptionTime ?? this.redemptionTime,
      snowId: snowId ?? this.snowId,
      credential: credential ?? this.credential,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (redemptionTime.present) {
      map['redemption_time'] = Variable<int>(redemptionTime.value);
    }
    if (snowId.present) {
      map['snow_id'] = Variable<String>(snowId.value);
    }
    if (credential.present) {
      map['credential'] = Variable<Uint8List>(credential.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2AuthCredentialsCompanion(')
          ..write('redemptionTime: $redemptionTime, ')
          ..write('snowId: $snowId, ')
          ..write('credential: $credential')
          ..write(')'))
        .toString();
  }
}

class $Gv2EndorsementsTable extends Gv2Endorsements
    with TableInfo<$Gv2EndorsementsTable, Gv2EndorsementRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2EndorsementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ciphertextMeta = const VerificationMeta(
    'ciphertext',
  );
  @override
  late final GeneratedColumn<String> ciphertext = GeneratedColumn<String>(
    'ciphertext',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 130,
      maxTextLength: 130,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endorsementMeta = const VerificationMeta(
    'endorsement',
  );
  @override
  late final GeneratedColumn<Uint8List> endorsement =
      GeneratedColumn<Uint8List>(
        'endorsement',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _expirationMeta = const VerificationMeta(
    'expiration',
  );
  @override
  late final GeneratedColumn<int> expiration = GeneratedColumn<int>(
    'expiration',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    ciphertext,
    endorsement,
    expiration,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_endorsements';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2EndorsementRow> instance, {
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
    if (data.containsKey('ciphertext')) {
      context.handle(
        _ciphertextMeta,
        ciphertext.isAcceptableOrUnknown(data['ciphertext']!, _ciphertextMeta),
      );
    } else if (isInserting) {
      context.missing(_ciphertextMeta);
    }
    if (data.containsKey('endorsement')) {
      context.handle(
        _endorsementMeta,
        endorsement.isAcceptableOrUnknown(
          data['endorsement']!,
          _endorsementMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_endorsementMeta);
    }
    if (data.containsKey('expiration')) {
      context.handle(
        _expirationMeta,
        expiration.isAcceptableOrUnknown(data['expiration']!, _expirationMeta),
      );
    } else if (isInserting) {
      context.missing(_expirationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, ciphertext};
  @override
  Gv2EndorsementRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2EndorsementRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      ciphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ciphertext'],
      )!,
      endorsement: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}endorsement'],
      )!,
      expiration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expiration'],
      )!,
    );
  }

  @override
  $Gv2EndorsementsTable createAlias(String alias) {
    return $Gv2EndorsementsTable(attachedDatabase, alias);
  }
}

class Gv2EndorsementRow extends DataClass
    implements Insertable<Gv2EndorsementRow> {
  final String groupId;

  /// Member ciphertext, 130 hex characters.
  final String ciphertext;

  /// 33-byte endorsement.
  final Uint8List endorsement;

  /// When it stops verifying, epoch seconds (day-aligned).
  final int expiration;
  const Gv2EndorsementRow({
    required this.groupId,
    required this.ciphertext,
    required this.endorsement,
    required this.expiration,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['ciphertext'] = Variable<String>(ciphertext);
    map['endorsement'] = Variable<Uint8List>(endorsement);
    map['expiration'] = Variable<int>(expiration);
    return map;
  }

  Gv2EndorsementsCompanion toCompanion(bool nullToAbsent) {
    return Gv2EndorsementsCompanion(
      groupId: Value(groupId),
      ciphertext: Value(ciphertext),
      endorsement: Value(endorsement),
      expiration: Value(expiration),
    );
  }

  factory Gv2EndorsementRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2EndorsementRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      ciphertext: serializer.fromJson<String>(json['ciphertext']),
      endorsement: serializer.fromJson<Uint8List>(json['endorsement']),
      expiration: serializer.fromJson<int>(json['expiration']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'ciphertext': serializer.toJson<String>(ciphertext),
      'endorsement': serializer.toJson<Uint8List>(endorsement),
      'expiration': serializer.toJson<int>(expiration),
    };
  }

  Gv2EndorsementRow copyWith({
    String? groupId,
    String? ciphertext,
    Uint8List? endorsement,
    int? expiration,
  }) => Gv2EndorsementRow(
    groupId: groupId ?? this.groupId,
    ciphertext: ciphertext ?? this.ciphertext,
    endorsement: endorsement ?? this.endorsement,
    expiration: expiration ?? this.expiration,
  );
  Gv2EndorsementRow copyWithCompanion(Gv2EndorsementsCompanion data) {
    return Gv2EndorsementRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      ciphertext: data.ciphertext.present
          ? data.ciphertext.value
          : this.ciphertext,
      endorsement: data.endorsement.present
          ? data.endorsement.value
          : this.endorsement,
      expiration: data.expiration.present
          ? data.expiration.value
          : this.expiration,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2EndorsementRow(')
          ..write('groupId: $groupId, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('endorsement: $endorsement, ')
          ..write('expiration: $expiration')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    ciphertext,
    $driftBlobEquality.hash(endorsement),
    expiration,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2EndorsementRow &&
          other.groupId == this.groupId &&
          other.ciphertext == this.ciphertext &&
          $driftBlobEquality.equals(other.endorsement, this.endorsement) &&
          other.expiration == this.expiration);
}

class Gv2EndorsementsCompanion extends UpdateCompanion<Gv2EndorsementRow> {
  final Value<String> groupId;
  final Value<String> ciphertext;
  final Value<Uint8List> endorsement;
  final Value<int> expiration;
  final Value<int> rowid;
  const Gv2EndorsementsCompanion({
    this.groupId = const Value.absent(),
    this.ciphertext = const Value.absent(),
    this.endorsement = const Value.absent(),
    this.expiration = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Gv2EndorsementsCompanion.insert({
    required String groupId,
    required String ciphertext,
    required Uint8List endorsement,
    required int expiration,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       ciphertext = Value(ciphertext),
       endorsement = Value(endorsement),
       expiration = Value(expiration);
  static Insertable<Gv2EndorsementRow> custom({
    Expression<String>? groupId,
    Expression<String>? ciphertext,
    Expression<Uint8List>? endorsement,
    Expression<int>? expiration,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (ciphertext != null) 'ciphertext': ciphertext,
      if (endorsement != null) 'endorsement': endorsement,
      if (expiration != null) 'expiration': expiration,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Gv2EndorsementsCompanion copyWith({
    Value<String>? groupId,
    Value<String>? ciphertext,
    Value<Uint8List>? endorsement,
    Value<int>? expiration,
    Value<int>? rowid,
  }) {
    return Gv2EndorsementsCompanion(
      groupId: groupId ?? this.groupId,
      ciphertext: ciphertext ?? this.ciphertext,
      endorsement: endorsement ?? this.endorsement,
      expiration: expiration ?? this.expiration,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (ciphertext.present) {
      map['ciphertext'] = Variable<String>(ciphertext.value);
    }
    if (endorsement.present) {
      map['endorsement'] = Variable<Uint8List>(endorsement.value);
    }
    if (expiration.present) {
      map['expiration'] = Variable<int>(expiration.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2EndorsementsCompanion(')
          ..write('groupId: $groupId, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('endorsement: $endorsement, ')
          ..write('expiration: $expiration, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Gv2InboxRowsTable extends Gv2InboxRows
    with TableInfo<$Gv2InboxRowsTable, Gv2InboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2InboxRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
    'local_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _serverRowIdMeta = const VerificationMeta(
    'serverRowId',
  );
  @override
  late final GeneratedColumn<String> serverRowId = GeneratedColumn<String>(
    'server_row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _digestMeta = const VerificationMeta('digest');
  @override
  late final GeneratedColumn<Uint8List> digest = GeneratedColumn<Uint8List>(
    'digest',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<Gv2InboxKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Gv2InboxKind>($Gv2InboxRowsTable.$converterkind);
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unsealedMeta = const VerificationMeta(
    'unsealed',
  );
  @override
  late final GeneratedColumn<bool> unsealed = GeneratedColumn<bool>(
    'unsealed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("unsealed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Gv2InboxState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Gv2InboxState>($Gv2InboxRowsTable.$converterstate);
  static const VerificationMeta _waitForMeta = const VerificationMeta(
    'waitFor',
  );
  @override
  late final GeneratedColumn<String> waitFor = GeneratedColumn<String>(
    'wait_for',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receivedAtMsMeta = const VerificationMeta(
    'receivedAtMs',
  );
  @override
  late final GeneratedColumn<int> receivedAtMs = GeneratedColumn<int>(
    'received_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    serverRowId,
    digest,
    kind,
    payload,
    unsealed,
    groupId,
    state,
    waitFor,
    receivedAtMs,
    attempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_inbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2InboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    }
    if (data.containsKey('server_row_id')) {
      context.handle(
        _serverRowIdMeta,
        serverRowId.isAcceptableOrUnknown(
          data['server_row_id']!,
          _serverRowIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverRowIdMeta);
    }
    if (data.containsKey('digest')) {
      context.handle(
        _digestMeta,
        digest.isAcceptableOrUnknown(data['digest']!, _digestMeta),
      );
    } else if (isInserting) {
      context.missing(_digestMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('unsealed')) {
      context.handle(
        _unsealedMeta,
        unsealed.isAcceptableOrUnknown(data['unsealed']!, _unsealedMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('wait_for')) {
      context.handle(
        _waitForMeta,
        waitFor.isAcceptableOrUnknown(data['wait_for']!, _waitForMeta),
      );
    }
    if (data.containsKey('received_at_ms')) {
      context.handle(
        _receivedAtMsMeta,
        receivedAtMs.isAcceptableOrUnknown(
          data['received_at_ms']!,
          _receivedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMsMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  Gv2InboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2InboxRow(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_id'],
      )!,
      serverRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_row_id'],
      )!,
      digest: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}digest'],
      )!,
      kind: $Gv2InboxRowsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      )!,
      unsealed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}unsealed'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      state: $Gv2InboxRowsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      waitFor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wait_for'],
      ),
      receivedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_at_ms'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
    );
  }

  @override
  $Gv2InboxRowsTable createAlias(String alias) {
    return $Gv2InboxRowsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Gv2InboxKind, String, String> $converterkind =
      const EnumNameConverter<Gv2InboxKind>(Gv2InboxKind.values);
  static JsonTypeConverter2<Gv2InboxState, String, String> $converterstate =
      const EnumNameConverter<Gv2InboxState>(Gv2InboxState.values);
}

class Gv2InboxRow extends DataClass implements Insertable<Gv2InboxRow> {
  /// Arrival order on this device: the order rows are handled in. (The
  /// server's sequence number restarts when the queue empties, so it orders
  /// only the rows of one fetch.)
  final int localId;

  /// The server queue row it came in (a UUID). A push notification names
  /// this id.
  final String serverRowId;

  /// SHA-256 of the envelope as received. The same envelope stored twice —
  /// redelivered after a lost acknowledgement, or replayed — is one row.
  final Uint8List digest;
  final Gv2InboxKind kind;

  /// The received envelope; or, once [unsealed], what its handler kept of
  /// it (a pairwise envelope can be decrypted only once, so a handler that
  /// has to wait keeps the decrypted form). Message content: never log it.
  final Uint8List payload;
  final bool unsealed;

  /// The group it belongs to (lowercase hex), once known. Rows of one group
  /// are handled one at a time, in [localId] order.
  final String? groupId;
  final Gv2InboxState state;

  /// The sender (snowId) whose Sender Key a [Gv2InboxState.waitingKey] row
  /// waits for.
  final String? waitFor;
  final int receivedAtMs;

  /// Failed handling attempts (the handler threw). The row is dropped after
  /// a few.
  final int attempts;
  const Gv2InboxRow({
    required this.localId,
    required this.serverRowId,
    required this.digest,
    required this.kind,
    required this.payload,
    required this.unsealed,
    this.groupId,
    required this.state,
    this.waitFor,
    required this.receivedAtMs,
    required this.attempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<int>(localId);
    map['server_row_id'] = Variable<String>(serverRowId);
    map['digest'] = Variable<Uint8List>(digest);
    {
      map['kind'] = Variable<String>(
        $Gv2InboxRowsTable.$converterkind.toSql(kind),
      );
    }
    map['payload'] = Variable<Uint8List>(payload);
    map['unsealed'] = Variable<bool>(unsealed);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    {
      map['state'] = Variable<String>(
        $Gv2InboxRowsTable.$converterstate.toSql(state),
      );
    }
    if (!nullToAbsent || waitFor != null) {
      map['wait_for'] = Variable<String>(waitFor);
    }
    map['received_at_ms'] = Variable<int>(receivedAtMs);
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  Gv2InboxRowsCompanion toCompanion(bool nullToAbsent) {
    return Gv2InboxRowsCompanion(
      localId: Value(localId),
      serverRowId: Value(serverRowId),
      digest: Value(digest),
      kind: Value(kind),
      payload: Value(payload),
      unsealed: Value(unsealed),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      state: Value(state),
      waitFor: waitFor == null && nullToAbsent
          ? const Value.absent()
          : Value(waitFor),
      receivedAtMs: Value(receivedAtMs),
      attempts: Value(attempts),
    );
  }

  factory Gv2InboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2InboxRow(
      localId: serializer.fromJson<int>(json['localId']),
      serverRowId: serializer.fromJson<String>(json['serverRowId']),
      digest: serializer.fromJson<Uint8List>(json['digest']),
      kind: $Gv2InboxRowsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      unsealed: serializer.fromJson<bool>(json['unsealed']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      state: $Gv2InboxRowsTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      waitFor: serializer.fromJson<String?>(json['waitFor']),
      receivedAtMs: serializer.fromJson<int>(json['receivedAtMs']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<int>(localId),
      'serverRowId': serializer.toJson<String>(serverRowId),
      'digest': serializer.toJson<Uint8List>(digest),
      'kind': serializer.toJson<String>(
        $Gv2InboxRowsTable.$converterkind.toJson(kind),
      ),
      'payload': serializer.toJson<Uint8List>(payload),
      'unsealed': serializer.toJson<bool>(unsealed),
      'groupId': serializer.toJson<String?>(groupId),
      'state': serializer.toJson<String>(
        $Gv2InboxRowsTable.$converterstate.toJson(state),
      ),
      'waitFor': serializer.toJson<String?>(waitFor),
      'receivedAtMs': serializer.toJson<int>(receivedAtMs),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  Gv2InboxRow copyWith({
    int? localId,
    String? serverRowId,
    Uint8List? digest,
    Gv2InboxKind? kind,
    Uint8List? payload,
    bool? unsealed,
    Value<String?> groupId = const Value.absent(),
    Gv2InboxState? state,
    Value<String?> waitFor = const Value.absent(),
    int? receivedAtMs,
    int? attempts,
  }) => Gv2InboxRow(
    localId: localId ?? this.localId,
    serverRowId: serverRowId ?? this.serverRowId,
    digest: digest ?? this.digest,
    kind: kind ?? this.kind,
    payload: payload ?? this.payload,
    unsealed: unsealed ?? this.unsealed,
    groupId: groupId.present ? groupId.value : this.groupId,
    state: state ?? this.state,
    waitFor: waitFor.present ? waitFor.value : this.waitFor,
    receivedAtMs: receivedAtMs ?? this.receivedAtMs,
    attempts: attempts ?? this.attempts,
  );
  Gv2InboxRow copyWithCompanion(Gv2InboxRowsCompanion data) {
    return Gv2InboxRow(
      localId: data.localId.present ? data.localId.value : this.localId,
      serverRowId: data.serverRowId.present
          ? data.serverRowId.value
          : this.serverRowId,
      digest: data.digest.present ? data.digest.value : this.digest,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
      unsealed: data.unsealed.present ? data.unsealed.value : this.unsealed,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      state: data.state.present ? data.state.value : this.state,
      waitFor: data.waitFor.present ? data.waitFor.value : this.waitFor,
      receivedAtMs: data.receivedAtMs.present
          ? data.receivedAtMs.value
          : this.receivedAtMs,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2InboxRow(')
          ..write('localId: $localId, ')
          ..write('serverRowId: $serverRowId, ')
          ..write('digest: $digest, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('unsealed: $unsealed, ')
          ..write('groupId: $groupId, ')
          ..write('state: $state, ')
          ..write('waitFor: $waitFor, ')
          ..write('receivedAtMs: $receivedAtMs, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    serverRowId,
    $driftBlobEquality.hash(digest),
    kind,
    $driftBlobEquality.hash(payload),
    unsealed,
    groupId,
    state,
    waitFor,
    receivedAtMs,
    attempts,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2InboxRow &&
          other.localId == this.localId &&
          other.serverRowId == this.serverRowId &&
          $driftBlobEquality.equals(other.digest, this.digest) &&
          other.kind == this.kind &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.unsealed == this.unsealed &&
          other.groupId == this.groupId &&
          other.state == this.state &&
          other.waitFor == this.waitFor &&
          other.receivedAtMs == this.receivedAtMs &&
          other.attempts == this.attempts);
}

class Gv2InboxRowsCompanion extends UpdateCompanion<Gv2InboxRow> {
  final Value<int> localId;
  final Value<String> serverRowId;
  final Value<Uint8List> digest;
  final Value<Gv2InboxKind> kind;
  final Value<Uint8List> payload;
  final Value<bool> unsealed;
  final Value<String?> groupId;
  final Value<Gv2InboxState> state;
  final Value<String?> waitFor;
  final Value<int> receivedAtMs;
  final Value<int> attempts;
  const Gv2InboxRowsCompanion({
    this.localId = const Value.absent(),
    this.serverRowId = const Value.absent(),
    this.digest = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.unsealed = const Value.absent(),
    this.groupId = const Value.absent(),
    this.state = const Value.absent(),
    this.waitFor = const Value.absent(),
    this.receivedAtMs = const Value.absent(),
    this.attempts = const Value.absent(),
  });
  Gv2InboxRowsCompanion.insert({
    this.localId = const Value.absent(),
    required String serverRowId,
    required Uint8List digest,
    required Gv2InboxKind kind,
    required Uint8List payload,
    this.unsealed = const Value.absent(),
    this.groupId = const Value.absent(),
    required Gv2InboxState state,
    this.waitFor = const Value.absent(),
    required int receivedAtMs,
    this.attempts = const Value.absent(),
  }) : serverRowId = Value(serverRowId),
       digest = Value(digest),
       kind = Value(kind),
       payload = Value(payload),
       state = Value(state),
       receivedAtMs = Value(receivedAtMs);
  static Insertable<Gv2InboxRow> custom({
    Expression<int>? localId,
    Expression<String>? serverRowId,
    Expression<Uint8List>? digest,
    Expression<String>? kind,
    Expression<Uint8List>? payload,
    Expression<bool>? unsealed,
    Expression<String>? groupId,
    Expression<String>? state,
    Expression<String>? waitFor,
    Expression<int>? receivedAtMs,
    Expression<int>? attempts,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (serverRowId != null) 'server_row_id': serverRowId,
      if (digest != null) 'digest': digest,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (unsealed != null) 'unsealed': unsealed,
      if (groupId != null) 'group_id': groupId,
      if (state != null) 'state': state,
      if (waitFor != null) 'wait_for': waitFor,
      if (receivedAtMs != null) 'received_at_ms': receivedAtMs,
      if (attempts != null) 'attempts': attempts,
    });
  }

  Gv2InboxRowsCompanion copyWith({
    Value<int>? localId,
    Value<String>? serverRowId,
    Value<Uint8List>? digest,
    Value<Gv2InboxKind>? kind,
    Value<Uint8List>? payload,
    Value<bool>? unsealed,
    Value<String?>? groupId,
    Value<Gv2InboxState>? state,
    Value<String?>? waitFor,
    Value<int>? receivedAtMs,
    Value<int>? attempts,
  }) {
    return Gv2InboxRowsCompanion(
      localId: localId ?? this.localId,
      serverRowId: serverRowId ?? this.serverRowId,
      digest: digest ?? this.digest,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      unsealed: unsealed ?? this.unsealed,
      groupId: groupId ?? this.groupId,
      state: state ?? this.state,
      waitFor: waitFor ?? this.waitFor,
      receivedAtMs: receivedAtMs ?? this.receivedAtMs,
      attempts: attempts ?? this.attempts,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (serverRowId.present) {
      map['server_row_id'] = Variable<String>(serverRowId.value);
    }
    if (digest.present) {
      map['digest'] = Variable<Uint8List>(digest.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $Gv2InboxRowsTable.$converterkind.toSql(kind.value),
      );
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (unsealed.present) {
      map['unsealed'] = Variable<bool>(unsealed.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $Gv2InboxRowsTable.$converterstate.toSql(state.value),
      );
    }
    if (waitFor.present) {
      map['wait_for'] = Variable<String>(waitFor.value);
    }
    if (receivedAtMs.present) {
      map['received_at_ms'] = Variable<int>(receivedAtMs.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2InboxRowsCompanion(')
          ..write('localId: $localId, ')
          ..write('serverRowId: $serverRowId, ')
          ..write('digest: $digest, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('unsealed: $unsealed, ')
          ..write('groupId: $groupId, ')
          ..write('state: $state, ')
          ..write('waitFor: $waitFor, ')
          ..write('receivedAtMs: $receivedAtMs, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }
}

class $Gv2SeenTable extends Gv2Seen with TableInfo<$Gv2SeenTable, Gv2SeenRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2SeenTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _digestMeta = const VerificationMeta('digest');
  @override
  late final GeneratedColumn<Uint8List> digest = GeneratedColumn<Uint8List>(
    'digest',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverRowIdMeta = const VerificationMeta(
    'serverRowId',
  );
  @override
  late final GeneratedColumn<String> serverRowId = GeneratedColumn<String>(
    'server_row_id',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<int> day = GeneratedColumn<int>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    digest,
    serverRowId,
    conversationId,
    day,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_seen';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2SeenRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('digest')) {
      context.handle(
        _digestMeta,
        digest.isAcceptableOrUnknown(data['digest']!, _digestMeta),
      );
    } else if (isInserting) {
      context.missing(_digestMeta);
    }
    if (data.containsKey('server_row_id')) {
      context.handle(
        _serverRowIdMeta,
        serverRowId.isAcceptableOrUnknown(
          data['server_row_id']!,
          _serverRowIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverRowIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {digest};
  @override
  Gv2SeenRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2SeenRow(
      digest: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}digest'],
      )!,
      serverRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_row_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      ),
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day'],
      )!,
    );
  }

  @override
  $Gv2SeenTable createAlias(String alias) {
    return $Gv2SeenTable(attachedDatabase, alias);
  }
}

class Gv2SeenRow extends DataClass implements Insertable<Gv2SeenRow> {
  /// SHA-256 of the envelope as received.
  final Uint8List digest;

  /// The server queue row it came in.
  final String serverRowId;

  /// The conversation it was shown in, when it was shown — what a tap on its
  /// push notification opens.
  final String? conversationId;

  /// Local epoch day it was handled.
  final int day;
  const Gv2SeenRow({
    required this.digest,
    required this.serverRowId,
    this.conversationId,
    required this.day,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['digest'] = Variable<Uint8List>(digest);
    map['server_row_id'] = Variable<String>(serverRowId);
    if (!nullToAbsent || conversationId != null) {
      map['conversation_id'] = Variable<String>(conversationId);
    }
    map['day'] = Variable<int>(day);
    return map;
  }

  Gv2SeenCompanion toCompanion(bool nullToAbsent) {
    return Gv2SeenCompanion(
      digest: Value(digest),
      serverRowId: Value(serverRowId),
      conversationId: conversationId == null && nullToAbsent
          ? const Value.absent()
          : Value(conversationId),
      day: Value(day),
    );
  }

  factory Gv2SeenRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2SeenRow(
      digest: serializer.fromJson<Uint8List>(json['digest']),
      serverRowId: serializer.fromJson<String>(json['serverRowId']),
      conversationId: serializer.fromJson<String?>(json['conversationId']),
      day: serializer.fromJson<int>(json['day']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'digest': serializer.toJson<Uint8List>(digest),
      'serverRowId': serializer.toJson<String>(serverRowId),
      'conversationId': serializer.toJson<String?>(conversationId),
      'day': serializer.toJson<int>(day),
    };
  }

  Gv2SeenRow copyWith({
    Uint8List? digest,
    String? serverRowId,
    Value<String?> conversationId = const Value.absent(),
    int? day,
  }) => Gv2SeenRow(
    digest: digest ?? this.digest,
    serverRowId: serverRowId ?? this.serverRowId,
    conversationId: conversationId.present
        ? conversationId.value
        : this.conversationId,
    day: day ?? this.day,
  );
  Gv2SeenRow copyWithCompanion(Gv2SeenCompanion data) {
    return Gv2SeenRow(
      digest: data.digest.present ? data.digest.value : this.digest,
      serverRowId: data.serverRowId.present
          ? data.serverRowId.value
          : this.serverRowId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      day: data.day.present ? data.day.value : this.day,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2SeenRow(')
          ..write('digest: $digest, ')
          ..write('serverRowId: $serverRowId, ')
          ..write('conversationId: $conversationId, ')
          ..write('day: $day')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    $driftBlobEquality.hash(digest),
    serverRowId,
    conversationId,
    day,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2SeenRow &&
          $driftBlobEquality.equals(other.digest, this.digest) &&
          other.serverRowId == this.serverRowId &&
          other.conversationId == this.conversationId &&
          other.day == this.day);
}

class Gv2SeenCompanion extends UpdateCompanion<Gv2SeenRow> {
  final Value<Uint8List> digest;
  final Value<String> serverRowId;
  final Value<String?> conversationId;
  final Value<int> day;
  final Value<int> rowid;
  const Gv2SeenCompanion({
    this.digest = const Value.absent(),
    this.serverRowId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.day = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Gv2SeenCompanion.insert({
    required Uint8List digest,
    required String serverRowId,
    this.conversationId = const Value.absent(),
    required int day,
    this.rowid = const Value.absent(),
  }) : digest = Value(digest),
       serverRowId = Value(serverRowId),
       day = Value(day);
  static Insertable<Gv2SeenRow> custom({
    Expression<Uint8List>? digest,
    Expression<String>? serverRowId,
    Expression<String>? conversationId,
    Expression<int>? day,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (digest != null) 'digest': digest,
      if (serverRowId != null) 'server_row_id': serverRowId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (day != null) 'day': day,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Gv2SeenCompanion copyWith({
    Value<Uint8List>? digest,
    Value<String>? serverRowId,
    Value<String?>? conversationId,
    Value<int>? day,
    Value<int>? rowid,
  }) {
    return Gv2SeenCompanion(
      digest: digest ?? this.digest,
      serverRowId: serverRowId ?? this.serverRowId,
      conversationId: conversationId ?? this.conversationId,
      day: day ?? this.day,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (digest.present) {
      map['digest'] = Variable<Uint8List>(digest.value);
    }
    if (serverRowId.present) {
      map['server_row_id'] = Variable<String>(serverRowId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (day.present) {
      map['day'] = Variable<int>(day.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2SeenCompanion(')
          ..write('digest: $digest, ')
          ..write('serverRowId: $serverRowId, ')
          ..write('conversationId: $conversationId, ')
          ..write('day: $day, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Gv2HeadsTable extends Gv2Heads
    with TableInfo<$Gv2HeadsTable, Gv2HeadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2HeadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chainMeta = const VerificationMeta('chain');
  @override
  late final GeneratedColumn<Uint8List> chain = GeneratedColumn<Uint8List>(
    'chain',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _headSigMeta = const VerificationMeta(
    'headSig',
  );
  @override
  late final GeneratedColumn<Uint8List> headSig = GeneratedColumn<Uint8List>(
    'head_sig',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storedAtMsMeta = const VerificationMeta(
    'storedAtMs',
  );
  @override
  late final GeneratedColumn<int> storedAtMs = GeneratedColumn<int>(
    'stored_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    revision,
    chain,
    headSig,
    storedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_heads';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2HeadRow> instance, {
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
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('chain')) {
      context.handle(
        _chainMeta,
        chain.isAcceptableOrUnknown(data['chain']!, _chainMeta),
      );
    } else if (isInserting) {
      context.missing(_chainMeta);
    }
    if (data.containsKey('head_sig')) {
      context.handle(
        _headSigMeta,
        headSig.isAcceptableOrUnknown(data['head_sig']!, _headSigMeta),
      );
    }
    if (data.containsKey('stored_at_ms')) {
      context.handle(
        _storedAtMsMeta,
        storedAtMs.isAcceptableOrUnknown(
          data['stored_at_ms']!,
          _storedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, revision};
  @override
  Gv2HeadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2HeadRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      chain: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}chain'],
      )!,
      headSig: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}head_sig'],
      ),
      storedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stored_at_ms'],
      )!,
    );
  }

  @override
  $Gv2HeadsTable createAlias(String alias) {
    return $Gv2HeadsTable(attachedDatabase, alias);
  }
}

class Gv2HeadRow extends DataClass implements Insertable<Gv2HeadRow> {
  final String groupId;
  final int revision;
  final Uint8List chain;

  /// The server's signature over this point, when this device verified one
  /// (the last entry of each stored batch, the anchor of a snapshot, the
  /// head of a group it created). Null for the points in between.
  final Uint8List? headSig;

  /// When this device stored the point (local clock, ms). A point other than
  /// the group's current one is pruned once it is older than an envelope
  /// can be (Gv2Store.pruneOld): the table grew with every revision.
  final int storedAtMs;
  const Gv2HeadRow({
    required this.groupId,
    required this.revision,
    required this.chain,
    this.headSig,
    required this.storedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['revision'] = Variable<int>(revision);
    map['chain'] = Variable<Uint8List>(chain);
    if (!nullToAbsent || headSig != null) {
      map['head_sig'] = Variable<Uint8List>(headSig);
    }
    map['stored_at_ms'] = Variable<int>(storedAtMs);
    return map;
  }

  Gv2HeadsCompanion toCompanion(bool nullToAbsent) {
    return Gv2HeadsCompanion(
      groupId: Value(groupId),
      revision: Value(revision),
      chain: Value(chain),
      headSig: headSig == null && nullToAbsent
          ? const Value.absent()
          : Value(headSig),
      storedAtMs: Value(storedAtMs),
    );
  }

  factory Gv2HeadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2HeadRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      revision: serializer.fromJson<int>(json['revision']),
      chain: serializer.fromJson<Uint8List>(json['chain']),
      headSig: serializer.fromJson<Uint8List?>(json['headSig']),
      storedAtMs: serializer.fromJson<int>(json['storedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'revision': serializer.toJson<int>(revision),
      'chain': serializer.toJson<Uint8List>(chain),
      'headSig': serializer.toJson<Uint8List?>(headSig),
      'storedAtMs': serializer.toJson<int>(storedAtMs),
    };
  }

  Gv2HeadRow copyWith({
    String? groupId,
    int? revision,
    Uint8List? chain,
    Value<Uint8List?> headSig = const Value.absent(),
    int? storedAtMs,
  }) => Gv2HeadRow(
    groupId: groupId ?? this.groupId,
    revision: revision ?? this.revision,
    chain: chain ?? this.chain,
    headSig: headSig.present ? headSig.value : this.headSig,
    storedAtMs: storedAtMs ?? this.storedAtMs,
  );
  Gv2HeadRow copyWithCompanion(Gv2HeadsCompanion data) {
    return Gv2HeadRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      revision: data.revision.present ? data.revision.value : this.revision,
      chain: data.chain.present ? data.chain.value : this.chain,
      headSig: data.headSig.present ? data.headSig.value : this.headSig,
      storedAtMs: data.storedAtMs.present
          ? data.storedAtMs.value
          : this.storedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2HeadRow(')
          ..write('groupId: $groupId, ')
          ..write('revision: $revision, ')
          ..write('chain: $chain, ')
          ..write('headSig: $headSig, ')
          ..write('storedAtMs: $storedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    revision,
    $driftBlobEquality.hash(chain),
    $driftBlobEquality.hash(headSig),
    storedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2HeadRow &&
          other.groupId == this.groupId &&
          other.revision == this.revision &&
          $driftBlobEquality.equals(other.chain, this.chain) &&
          $driftBlobEquality.equals(other.headSig, this.headSig) &&
          other.storedAtMs == this.storedAtMs);
}

class Gv2HeadsCompanion extends UpdateCompanion<Gv2HeadRow> {
  final Value<String> groupId;
  final Value<int> revision;
  final Value<Uint8List> chain;
  final Value<Uint8List?> headSig;
  final Value<int> storedAtMs;
  final Value<int> rowid;
  const Gv2HeadsCompanion({
    this.groupId = const Value.absent(),
    this.revision = const Value.absent(),
    this.chain = const Value.absent(),
    this.headSig = const Value.absent(),
    this.storedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Gv2HeadsCompanion.insert({
    required String groupId,
    required int revision,
    required Uint8List chain,
    this.headSig = const Value.absent(),
    this.storedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       revision = Value(revision),
       chain = Value(chain);
  static Insertable<Gv2HeadRow> custom({
    Expression<String>? groupId,
    Expression<int>? revision,
    Expression<Uint8List>? chain,
    Expression<Uint8List>? headSig,
    Expression<int>? storedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (revision != null) 'revision': revision,
      if (chain != null) 'chain': chain,
      if (headSig != null) 'head_sig': headSig,
      if (storedAtMs != null) 'stored_at_ms': storedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Gv2HeadsCompanion copyWith({
    Value<String>? groupId,
    Value<int>? revision,
    Value<Uint8List>? chain,
    Value<Uint8List?>? headSig,
    Value<int>? storedAtMs,
    Value<int>? rowid,
  }) {
    return Gv2HeadsCompanion(
      groupId: groupId ?? this.groupId,
      revision: revision ?? this.revision,
      chain: chain ?? this.chain,
      headSig: headSig ?? this.headSig,
      storedAtMs: storedAtMs ?? this.storedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (chain.present) {
      map['chain'] = Variable<Uint8List>(chain.value);
    }
    if (headSig.present) {
      map['head_sig'] = Variable<Uint8List>(headSig.value);
    }
    if (storedAtMs.present) {
      map['stored_at_ms'] = Variable<int>(storedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2HeadsCompanion(')
          ..write('groupId: $groupId, ')
          ..write('revision: $revision, ')
          ..write('chain: $chain, ')
          ..write('headSig: $headSig, ')
          ..write('storedAtMs: $storedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Gv2SenderKeysTable extends Gv2SenderKeys
    with TableInfo<$Gv2SenderKeysTable, Gv2SenderKeyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2SenderKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  @override
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
    'sender',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 36,
      maxTextLength: 36,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordMeta = const VerificationMeta('record');
  @override
  late final GeneratedColumn<Uint8List> record = GeneratedColumn<Uint8List>(
    'record',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [groupId, sender, record];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_sender_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2SenderKeyRow> instance, {
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
    if (data.containsKey('sender')) {
      context.handle(
        _senderMeta,
        sender.isAcceptableOrUnknown(data['sender']!, _senderMeta),
      );
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('record')) {
      context.handle(
        _recordMeta,
        record.isAcceptableOrUnknown(data['record']!, _recordMeta),
      );
    } else if (isInserting) {
      context.missing(_recordMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, sender};
  @override
  Gv2SenderKeyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2SenderKeyRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      sender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender'],
      )!,
      record: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}record'],
      )!,
    );
  }

  @override
  $Gv2SenderKeysTable createAlias(String alias) {
    return $Gv2SenderKeysTable(attachedDatabase, alias);
  }
}

class Gv2SenderKeyRow extends DataClass implements Insertable<Gv2SenderKeyRow> {
  final String groupId;

  /// The sender's snowId.
  final String sender;

  /// SenderKeyRecord.toJson() as UTF-8. Key material: never log it.
  final Uint8List record;
  const Gv2SenderKeyRow({
    required this.groupId,
    required this.sender,
    required this.record,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['sender'] = Variable<String>(sender);
    map['record'] = Variable<Uint8List>(record);
    return map;
  }

  Gv2SenderKeysCompanion toCompanion(bool nullToAbsent) {
    return Gv2SenderKeysCompanion(
      groupId: Value(groupId),
      sender: Value(sender),
      record: Value(record),
    );
  }

  factory Gv2SenderKeyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2SenderKeyRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      sender: serializer.fromJson<String>(json['sender']),
      record: serializer.fromJson<Uint8List>(json['record']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'sender': serializer.toJson<String>(sender),
      'record': serializer.toJson<Uint8List>(record),
    };
  }

  Gv2SenderKeyRow copyWith({
    String? groupId,
    String? sender,
    Uint8List? record,
  }) => Gv2SenderKeyRow(
    groupId: groupId ?? this.groupId,
    sender: sender ?? this.sender,
    record: record ?? this.record,
  );
  Gv2SenderKeyRow copyWithCompanion(Gv2SenderKeysCompanion data) {
    return Gv2SenderKeyRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      sender: data.sender.present ? data.sender.value : this.sender,
      record: data.record.present ? data.record.value : this.record,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2SenderKeyRow(')
          ..write('groupId: $groupId, ')
          ..write('sender: $sender, ')
          ..write('record: $record')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(groupId, sender, $driftBlobEquality.hash(record));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2SenderKeyRow &&
          other.groupId == this.groupId &&
          other.sender == this.sender &&
          $driftBlobEquality.equals(other.record, this.record));
}

class Gv2SenderKeysCompanion extends UpdateCompanion<Gv2SenderKeyRow> {
  final Value<String> groupId;
  final Value<String> sender;
  final Value<Uint8List> record;
  final Value<int> rowid;
  const Gv2SenderKeysCompanion({
    this.groupId = const Value.absent(),
    this.sender = const Value.absent(),
    this.record = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Gv2SenderKeysCompanion.insert({
    required String groupId,
    required String sender,
    required Uint8List record,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       sender = Value(sender),
       record = Value(record);
  static Insertable<Gv2SenderKeyRow> custom({
    Expression<String>? groupId,
    Expression<String>? sender,
    Expression<Uint8List>? record,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (sender != null) 'sender': sender,
      if (record != null) 'record': record,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Gv2SenderKeysCompanion copyWith({
    Value<String>? groupId,
    Value<String>? sender,
    Value<Uint8List>? record,
    Value<int>? rowid,
  }) {
    return Gv2SenderKeysCompanion(
      groupId: groupId ?? this.groupId,
      sender: sender ?? this.sender,
      record: record ?? this.record,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (record.present) {
      map['record'] = Variable<Uint8List>(record.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2SenderKeysCompanion(')
          ..write('groupId: $groupId, ')
          ..write('sender: $sender, ')
          ..write('record: $record, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Gv2KeyDeliveriesTable extends Gv2KeyDeliveries
    with TableInfo<$Gv2KeyDeliveriesTable, Gv2KeyDeliveryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2KeyDeliveriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _memberMeta = const VerificationMeta('member');
  @override
  late final GeneratedColumn<String> member = GeneratedColumn<String>(
    'member',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 36,
      maxTextLength: 36,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chainIdMeta = const VerificationMeta(
    'chainId',
  );
  @override
  late final GeneratedColumn<int> chainId = GeneratedColumn<int>(
    'chain_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<Uint8List> key = GeneratedColumn<Uint8List>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveredAtMsMeta = const VerificationMeta(
    'deliveredAtMs',
  );
  @override
  late final GeneratedColumn<int> deliveredAtMs = GeneratedColumn<int>(
    'delivered_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    member,
    chainId,
    key,
    deliveredAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_key_deliveries';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2KeyDeliveryRow> instance, {
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
    if (data.containsKey('member')) {
      context.handle(
        _memberMeta,
        member.isAcceptableOrUnknown(data['member']!, _memberMeta),
      );
    } else if (isInserting) {
      context.missing(_memberMeta);
    }
    if (data.containsKey('chain_id')) {
      context.handle(
        _chainIdMeta,
        chainId.isAcceptableOrUnknown(data['chain_id']!, _chainIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chainIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('delivered_at_ms')) {
      context.handle(
        _deliveredAtMsMeta,
        deliveredAtMs.isAcceptableOrUnknown(
          data['delivered_at_ms']!,
          _deliveredAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deliveredAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, member, chainId};
  @override
  Gv2KeyDeliveryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2KeyDeliveryRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      member: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member'],
      )!,
      chainId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chain_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}key'],
      )!,
      deliveredAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delivered_at_ms'],
      )!,
    );
  }

  @override
  $Gv2KeyDeliveriesTable createAlias(String alias) {
    return $Gv2KeyDeliveriesTable(attachedDatabase, alias);
  }
}

class Gv2KeyDeliveryRow extends DataClass
    implements Insertable<Gv2KeyDeliveryRow> {
  final String groupId;

  /// The member's snowId.
  final String member;
  final int chainId;

  /// The Sender Key body of the pairwise message (gv2_pairwise.dart). Key
  /// material: never log it.
  final Uint8List key;

  /// Local clock, milliseconds.
  final int deliveredAtMs;
  const Gv2KeyDeliveryRow({
    required this.groupId,
    required this.member,
    required this.chainId,
    required this.key,
    required this.deliveredAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['member'] = Variable<String>(member);
    map['chain_id'] = Variable<int>(chainId);
    map['key'] = Variable<Uint8List>(key);
    map['delivered_at_ms'] = Variable<int>(deliveredAtMs);
    return map;
  }

  Gv2KeyDeliveriesCompanion toCompanion(bool nullToAbsent) {
    return Gv2KeyDeliveriesCompanion(
      groupId: Value(groupId),
      member: Value(member),
      chainId: Value(chainId),
      key: Value(key),
      deliveredAtMs: Value(deliveredAtMs),
    );
  }

  factory Gv2KeyDeliveryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2KeyDeliveryRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      member: serializer.fromJson<String>(json['member']),
      chainId: serializer.fromJson<int>(json['chainId']),
      key: serializer.fromJson<Uint8List>(json['key']),
      deliveredAtMs: serializer.fromJson<int>(json['deliveredAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'member': serializer.toJson<String>(member),
      'chainId': serializer.toJson<int>(chainId),
      'key': serializer.toJson<Uint8List>(key),
      'deliveredAtMs': serializer.toJson<int>(deliveredAtMs),
    };
  }

  Gv2KeyDeliveryRow copyWith({
    String? groupId,
    String? member,
    int? chainId,
    Uint8List? key,
    int? deliveredAtMs,
  }) => Gv2KeyDeliveryRow(
    groupId: groupId ?? this.groupId,
    member: member ?? this.member,
    chainId: chainId ?? this.chainId,
    key: key ?? this.key,
    deliveredAtMs: deliveredAtMs ?? this.deliveredAtMs,
  );
  Gv2KeyDeliveryRow copyWithCompanion(Gv2KeyDeliveriesCompanion data) {
    return Gv2KeyDeliveryRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      member: data.member.present ? data.member.value : this.member,
      chainId: data.chainId.present ? data.chainId.value : this.chainId,
      key: data.key.present ? data.key.value : this.key,
      deliveredAtMs: data.deliveredAtMs.present
          ? data.deliveredAtMs.value
          : this.deliveredAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2KeyDeliveryRow(')
          ..write('groupId: $groupId, ')
          ..write('member: $member, ')
          ..write('chainId: $chainId, ')
          ..write('key: $key, ')
          ..write('deliveredAtMs: $deliveredAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    member,
    chainId,
    $driftBlobEquality.hash(key),
    deliveredAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2KeyDeliveryRow &&
          other.groupId == this.groupId &&
          other.member == this.member &&
          other.chainId == this.chainId &&
          $driftBlobEquality.equals(other.key, this.key) &&
          other.deliveredAtMs == this.deliveredAtMs);
}

class Gv2KeyDeliveriesCompanion extends UpdateCompanion<Gv2KeyDeliveryRow> {
  final Value<String> groupId;
  final Value<String> member;
  final Value<int> chainId;
  final Value<Uint8List> key;
  final Value<int> deliveredAtMs;
  final Value<int> rowid;
  const Gv2KeyDeliveriesCompanion({
    this.groupId = const Value.absent(),
    this.member = const Value.absent(),
    this.chainId = const Value.absent(),
    this.key = const Value.absent(),
    this.deliveredAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Gv2KeyDeliveriesCompanion.insert({
    required String groupId,
    required String member,
    required int chainId,
    required Uint8List key,
    required int deliveredAtMs,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       member = Value(member),
       chainId = Value(chainId),
       key = Value(key),
       deliveredAtMs = Value(deliveredAtMs);
  static Insertable<Gv2KeyDeliveryRow> custom({
    Expression<String>? groupId,
    Expression<String>? member,
    Expression<int>? chainId,
    Expression<Uint8List>? key,
    Expression<int>? deliveredAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (member != null) 'member': member,
      if (chainId != null) 'chain_id': chainId,
      if (key != null) 'key': key,
      if (deliveredAtMs != null) 'delivered_at_ms': deliveredAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Gv2KeyDeliveriesCompanion copyWith({
    Value<String>? groupId,
    Value<String>? member,
    Value<int>? chainId,
    Value<Uint8List>? key,
    Value<int>? deliveredAtMs,
    Value<int>? rowid,
  }) {
    return Gv2KeyDeliveriesCompanion(
      groupId: groupId ?? this.groupId,
      member: member ?? this.member,
      chainId: chainId ?? this.chainId,
      key: key ?? this.key,
      deliveredAtMs: deliveredAtMs ?? this.deliveredAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (member.present) {
      map['member'] = Variable<String>(member.value);
    }
    if (chainId.present) {
      map['chain_id'] = Variable<int>(chainId.value);
    }
    if (key.present) {
      map['key'] = Variable<Uint8List>(key.value);
    }
    if (deliveredAtMs.present) {
      map['delivered_at_ms'] = Variable<int>(deliveredAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2KeyDeliveriesCompanion(')
          ..write('groupId: $groupId, ')
          ..write('member: $member, ')
          ..write('chainId: $chainId, ')
          ..write('key: $key, ')
          ..write('deliveredAtMs: $deliveredAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Gv2OutboxRowsTable extends Gv2OutboxRows
    with TableInfo<$Gv2OutboxRowsTable, Gv2OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2OutboxRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
    'local_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Gv2OutboxKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Gv2OutboxKind>($Gv2OutboxRowsTable.$converterkind);
  static const VerificationMeta _recipientMeta = const VerificationMeta(
    'recipient',
  );
  @override
  late final GeneratedColumn<String> recipient = GeneratedColumn<String>(
    'recipient',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 36,
      maxTextLength: 36,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
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
  static const VerificationMeta _notBeforeMsMeta = const VerificationMeta(
    'notBeforeMs',
  );
  @override
  late final GeneratedColumn<int> notBeforeMs = GeneratedColumn<int>(
    'not_before_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    groupId,
    kind,
    recipient,
    payload,
    createdAtMs,
    notBeforeMs,
    attempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('recipient')) {
      context.handle(
        _recipientMeta,
        recipient.isAcceptableOrUnknown(data['recipient']!, _recipientMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
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
    if (data.containsKey('not_before_ms')) {
      context.handle(
        _notBeforeMsMeta,
        notBeforeMs.isAcceptableOrUnknown(
          data['not_before_ms']!,
          _notBeforeMsMeta,
        ),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  Gv2OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2OutboxRow(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      kind: $Gv2OutboxRowsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      recipient: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      notBeforeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}not_before_ms'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
    );
  }

  @override
  $Gv2OutboxRowsTable createAlias(String alias) {
    return $Gv2OutboxRowsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Gv2OutboxKind, String, String> $converterkind =
      const EnumNameConverter<Gv2OutboxKind>(Gv2OutboxKind.values);
}

class Gv2OutboxRow extends DataClass implements Insertable<Gv2OutboxRow> {
  /// Queue order: rows are sent in this order.
  final int localId;
  final String groupId;
  final Gv2OutboxKind kind;

  /// The recipient's snowId (pairwise and invite rows); null for a row
  /// that goes to the whole group or to the server.
  final String? recipient;

  /// What is sent, by [kind] (layouts in gv2_outbox.dart):
  ///   pairwise      the plaintext pairwise message
  ///   content       messageId(16) ‖ timestampMs(u64) ‖ expiresIn(u32)
  ///                 ‖ silent(1) ‖ the content plaintext
  ///   changeNotice  empty
  ///   memberNotice  the notice payload
  ///   create        the encoded revision-0 entry
  ///   invite        the 32-byte invite private seed
  /// Message content: never log it.
  final Uint8List payload;

  /// Local clock, milliseconds.
  final int createdAtMs;

  /// Not sent before this time (a backoff after a failed send).
  final int notBeforeMs;

  /// Failed sends so far.
  final int attempts;
  const Gv2OutboxRow({
    required this.localId,
    required this.groupId,
    required this.kind,
    this.recipient,
    required this.payload,
    required this.createdAtMs,
    required this.notBeforeMs,
    required this.attempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<int>(localId);
    map['group_id'] = Variable<String>(groupId);
    {
      map['kind'] = Variable<String>(
        $Gv2OutboxRowsTable.$converterkind.toSql(kind),
      );
    }
    if (!nullToAbsent || recipient != null) {
      map['recipient'] = Variable<String>(recipient);
    }
    map['payload'] = Variable<Uint8List>(payload);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['not_before_ms'] = Variable<int>(notBeforeMs);
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  Gv2OutboxRowsCompanion toCompanion(bool nullToAbsent) {
    return Gv2OutboxRowsCompanion(
      localId: Value(localId),
      groupId: Value(groupId),
      kind: Value(kind),
      recipient: recipient == null && nullToAbsent
          ? const Value.absent()
          : Value(recipient),
      payload: Value(payload),
      createdAtMs: Value(createdAtMs),
      notBeforeMs: Value(notBeforeMs),
      attempts: Value(attempts),
    );
  }

  factory Gv2OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2OutboxRow(
      localId: serializer.fromJson<int>(json['localId']),
      groupId: serializer.fromJson<String>(json['groupId']),
      kind: $Gv2OutboxRowsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      recipient: serializer.fromJson<String?>(json['recipient']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      notBeforeMs: serializer.fromJson<int>(json['notBeforeMs']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<int>(localId),
      'groupId': serializer.toJson<String>(groupId),
      'kind': serializer.toJson<String>(
        $Gv2OutboxRowsTable.$converterkind.toJson(kind),
      ),
      'recipient': serializer.toJson<String?>(recipient),
      'payload': serializer.toJson<Uint8List>(payload),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'notBeforeMs': serializer.toJson<int>(notBeforeMs),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  Gv2OutboxRow copyWith({
    int? localId,
    String? groupId,
    Gv2OutboxKind? kind,
    Value<String?> recipient = const Value.absent(),
    Uint8List? payload,
    int? createdAtMs,
    int? notBeforeMs,
    int? attempts,
  }) => Gv2OutboxRow(
    localId: localId ?? this.localId,
    groupId: groupId ?? this.groupId,
    kind: kind ?? this.kind,
    recipient: recipient.present ? recipient.value : this.recipient,
    payload: payload ?? this.payload,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    notBeforeMs: notBeforeMs ?? this.notBeforeMs,
    attempts: attempts ?? this.attempts,
  );
  Gv2OutboxRow copyWithCompanion(Gv2OutboxRowsCompanion data) {
    return Gv2OutboxRow(
      localId: data.localId.present ? data.localId.value : this.localId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      kind: data.kind.present ? data.kind.value : this.kind,
      recipient: data.recipient.present ? data.recipient.value : this.recipient,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      notBeforeMs: data.notBeforeMs.present
          ? data.notBeforeMs.value
          : this.notBeforeMs,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2OutboxRow(')
          ..write('localId: $localId, ')
          ..write('groupId: $groupId, ')
          ..write('kind: $kind, ')
          ..write('recipient: $recipient, ')
          ..write('payload: $payload, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('notBeforeMs: $notBeforeMs, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    groupId,
    kind,
    recipient,
    $driftBlobEquality.hash(payload),
    createdAtMs,
    notBeforeMs,
    attempts,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2OutboxRow &&
          other.localId == this.localId &&
          other.groupId == this.groupId &&
          other.kind == this.kind &&
          other.recipient == this.recipient &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.createdAtMs == this.createdAtMs &&
          other.notBeforeMs == this.notBeforeMs &&
          other.attempts == this.attempts);
}

class Gv2OutboxRowsCompanion extends UpdateCompanion<Gv2OutboxRow> {
  final Value<int> localId;
  final Value<String> groupId;
  final Value<Gv2OutboxKind> kind;
  final Value<String?> recipient;
  final Value<Uint8List> payload;
  final Value<int> createdAtMs;
  final Value<int> notBeforeMs;
  final Value<int> attempts;
  const Gv2OutboxRowsCompanion({
    this.localId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.kind = const Value.absent(),
    this.recipient = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.notBeforeMs = const Value.absent(),
    this.attempts = const Value.absent(),
  });
  Gv2OutboxRowsCompanion.insert({
    this.localId = const Value.absent(),
    required String groupId,
    required Gv2OutboxKind kind,
    this.recipient = const Value.absent(),
    required Uint8List payload,
    required int createdAtMs,
    this.notBeforeMs = const Value.absent(),
    this.attempts = const Value.absent(),
  }) : groupId = Value(groupId),
       kind = Value(kind),
       payload = Value(payload),
       createdAtMs = Value(createdAtMs);
  static Insertable<Gv2OutboxRow> custom({
    Expression<int>? localId,
    Expression<String>? groupId,
    Expression<String>? kind,
    Expression<String>? recipient,
    Expression<Uint8List>? payload,
    Expression<int>? createdAtMs,
    Expression<int>? notBeforeMs,
    Expression<int>? attempts,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (groupId != null) 'group_id': groupId,
      if (kind != null) 'kind': kind,
      if (recipient != null) 'recipient': recipient,
      if (payload != null) 'payload': payload,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (notBeforeMs != null) 'not_before_ms': notBeforeMs,
      if (attempts != null) 'attempts': attempts,
    });
  }

  Gv2OutboxRowsCompanion copyWith({
    Value<int>? localId,
    Value<String>? groupId,
    Value<Gv2OutboxKind>? kind,
    Value<String?>? recipient,
    Value<Uint8List>? payload,
    Value<int>? createdAtMs,
    Value<int>? notBeforeMs,
    Value<int>? attempts,
  }) {
    return Gv2OutboxRowsCompanion(
      localId: localId ?? this.localId,
      groupId: groupId ?? this.groupId,
      kind: kind ?? this.kind,
      recipient: recipient ?? this.recipient,
      payload: payload ?? this.payload,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      notBeforeMs: notBeforeMs ?? this.notBeforeMs,
      attempts: attempts ?? this.attempts,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $Gv2OutboxRowsTable.$converterkind.toSql(kind.value),
      );
    }
    if (recipient.present) {
      map['recipient'] = Variable<String>(recipient.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (notBeforeMs.present) {
      map['not_before_ms'] = Variable<int>(notBeforeMs.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2OutboxRowsCompanion(')
          ..write('localId: $localId, ')
          ..write('groupId: $groupId, ')
          ..write('kind: $kind, ')
          ..write('recipient: $recipient, ')
          ..write('payload: $payload, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('notBeforeMs: $notBeforeMs, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }
}

class $Gv2MessageIdsTable extends Gv2MessageIds
    with TableInfo<$Gv2MessageIdsTable, Gv2MessageIdRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2MessageIdsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localMessageIdMeta = const VerificationMeta(
    'localMessageId',
  );
  @override
  late final GeneratedColumn<Uint8List> localMessageId =
      GeneratedColumn<Uint8List>(
        'local_message_id',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<int> day = GeneratedColumn<int>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [localMessageId, day];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_message_ids';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2MessageIdRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_message_id')) {
      context.handle(
        _localMessageIdMeta,
        localMessageId.isAcceptableOrUnknown(
          data['local_message_id']!,
          _localMessageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localMessageIdMeta);
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localMessageId};
  @override
  Gv2MessageIdRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2MessageIdRow(
      localMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}local_message_id'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day'],
      )!,
    );
  }

  @override
  $Gv2MessageIdsTable createAlias(String alias) {
    return $Gv2MessageIdsTable(attachedDatabase, alias);
  }
}

class Gv2MessageIdRow extends DataClass implements Insertable<Gv2MessageIdRow> {
  /// The 32-byte local message id.
  final Uint8List localMessageId;

  /// Local epoch day it was handled.
  final int day;
  const Gv2MessageIdRow({required this.localMessageId, required this.day});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_message_id'] = Variable<Uint8List>(localMessageId);
    map['day'] = Variable<int>(day);
    return map;
  }

  Gv2MessageIdsCompanion toCompanion(bool nullToAbsent) {
    return Gv2MessageIdsCompanion(
      localMessageId: Value(localMessageId),
      day: Value(day),
    );
  }

  factory Gv2MessageIdRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2MessageIdRow(
      localMessageId: serializer.fromJson<Uint8List>(json['localMessageId']),
      day: serializer.fromJson<int>(json['day']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localMessageId': serializer.toJson<Uint8List>(localMessageId),
      'day': serializer.toJson<int>(day),
    };
  }

  Gv2MessageIdRow copyWith({Uint8List? localMessageId, int? day}) =>
      Gv2MessageIdRow(
        localMessageId: localMessageId ?? this.localMessageId,
        day: day ?? this.day,
      );
  Gv2MessageIdRow copyWithCompanion(Gv2MessageIdsCompanion data) {
    return Gv2MessageIdRow(
      localMessageId: data.localMessageId.present
          ? data.localMessageId.value
          : this.localMessageId,
      day: data.day.present ? data.day.value : this.day,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2MessageIdRow(')
          ..write('localMessageId: $localMessageId, ')
          ..write('day: $day')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash($driftBlobEquality.hash(localMessageId), day);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2MessageIdRow &&
          $driftBlobEquality.equals(
            other.localMessageId,
            this.localMessageId,
          ) &&
          other.day == this.day);
}

class Gv2MessageIdsCompanion extends UpdateCompanion<Gv2MessageIdRow> {
  final Value<Uint8List> localMessageId;
  final Value<int> day;
  final Value<int> rowid;
  const Gv2MessageIdsCompanion({
    this.localMessageId = const Value.absent(),
    this.day = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Gv2MessageIdsCompanion.insert({
    required Uint8List localMessageId,
    required int day,
    this.rowid = const Value.absent(),
  }) : localMessageId = Value(localMessageId),
       day = Value(day);
  static Insertable<Gv2MessageIdRow> custom({
    Expression<Uint8List>? localMessageId,
    Expression<int>? day,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localMessageId != null) 'local_message_id': localMessageId,
      if (day != null) 'day': day,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Gv2MessageIdsCompanion copyWith({
    Value<Uint8List>? localMessageId,
    Value<int>? day,
    Value<int>? rowid,
  }) {
    return Gv2MessageIdsCompanion(
      localMessageId: localMessageId ?? this.localMessageId,
      day: day ?? this.day,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localMessageId.present) {
      map['local_message_id'] = Variable<Uint8List>(localMessageId.value);
    }
    if (day.present) {
      map['day'] = Variable<int>(day.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2MessageIdsCompanion(')
          ..write('localMessageId: $localMessageId, ')
          ..write('day: $day, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Gv2BackupStatesTable extends Gv2BackupStates
    with TableInfo<$Gv2BackupStatesTable, Gv2BackupStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Gv2BackupStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restoredMeta = const VerificationMeta(
    'restored',
  );
  @override
  late final GeneratedColumn<bool> restored = GeneratedColumn<bool>(
    'restored',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("restored" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<Uint8List> fingerprint =
      GeneratedColumn<Uint8List>(
        'fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _writeDueAtMsMeta = const VerificationMeta(
    'writeDueAtMs',
  );
  @override
  late final GeneratedColumn<int> writeDueAtMs = GeneratedColumn<int>(
    'write_due_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    slot,
    restored,
    etag,
    fingerprint,
    writeDueAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gv2_backup_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<Gv2BackupStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    }
    if (data.containsKey('restored')) {
      context.handle(
        _restoredMeta,
        restored.isAcceptableOrUnknown(data['restored']!, _restoredMeta),
      );
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    }
    if (data.containsKey('write_due_at_ms')) {
      context.handle(
        _writeDueAtMsMeta,
        writeDueAtMs.isAcceptableOrUnknown(
          data['write_due_at_ms']!,
          _writeDueAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {slot};
  @override
  Gv2BackupStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Gv2BackupStateRow(
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      restored: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}restored'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}fingerprint'],
      ),
      writeDueAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}write_due_at_ms'],
      ),
    );
  }

  @override
  $Gv2BackupStatesTable createAlias(String alias) {
    return $Gv2BackupStatesTable(attachedDatabase, alias);
  }
}

class Gv2BackupStateRow extends DataClass
    implements Insertable<Gv2BackupStateRow> {
  /// Always 0: there is one backup per account.
  final int slot;

  /// True once this install has taken in what the backup held when it first
  /// looked (a reinstall restores its groups from it — once). From then on
  /// this device's own groups are the truth and the backup follows them.
  final bool restored;

  /// The server's tag of the blob this device last wrote or read (base64 of
  /// its SHA-256); null when the server holds none. A write names it, so a
  /// blob written by anyone else meanwhile is not overwritten blindly.
  final String? etag;

  /// What the last written list was made from (a hash over the member
  /// groups and what makes an anchor worth renewing): the backup is written
  /// again only when this changes.
  final Uint8List? fingerprint;

  /// When the pending write of the backup is due (local clock, ms); null
  /// when none is pending. A write is not made when a group was joined or a
  /// member removed but at a random time one to six hours later, so the
  /// time of a write does not tie this account to a change of a group
  /// (decided 2026-11-21). Stored: an app that is closed often would never
  /// reach a delay kept in memory.
  final int? writeDueAtMs;
  const Gv2BackupStateRow({
    required this.slot,
    required this.restored,
    this.etag,
    this.fingerprint,
    this.writeDueAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['slot'] = Variable<int>(slot);
    map['restored'] = Variable<bool>(restored);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || fingerprint != null) {
      map['fingerprint'] = Variable<Uint8List>(fingerprint);
    }
    if (!nullToAbsent || writeDueAtMs != null) {
      map['write_due_at_ms'] = Variable<int>(writeDueAtMs);
    }
    return map;
  }

  Gv2BackupStatesCompanion toCompanion(bool nullToAbsent) {
    return Gv2BackupStatesCompanion(
      slot: Value(slot),
      restored: Value(restored),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      fingerprint: fingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(fingerprint),
      writeDueAtMs: writeDueAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(writeDueAtMs),
    );
  }

  factory Gv2BackupStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Gv2BackupStateRow(
      slot: serializer.fromJson<int>(json['slot']),
      restored: serializer.fromJson<bool>(json['restored']),
      etag: serializer.fromJson<String?>(json['etag']),
      fingerprint: serializer.fromJson<Uint8List?>(json['fingerprint']),
      writeDueAtMs: serializer.fromJson<int?>(json['writeDueAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'slot': serializer.toJson<int>(slot),
      'restored': serializer.toJson<bool>(restored),
      'etag': serializer.toJson<String?>(etag),
      'fingerprint': serializer.toJson<Uint8List?>(fingerprint),
      'writeDueAtMs': serializer.toJson<int?>(writeDueAtMs),
    };
  }

  Gv2BackupStateRow copyWith({
    int? slot,
    bool? restored,
    Value<String?> etag = const Value.absent(),
    Value<Uint8List?> fingerprint = const Value.absent(),
    Value<int?> writeDueAtMs = const Value.absent(),
  }) => Gv2BackupStateRow(
    slot: slot ?? this.slot,
    restored: restored ?? this.restored,
    etag: etag.present ? etag.value : this.etag,
    fingerprint: fingerprint.present ? fingerprint.value : this.fingerprint,
    writeDueAtMs: writeDueAtMs.present ? writeDueAtMs.value : this.writeDueAtMs,
  );
  Gv2BackupStateRow copyWithCompanion(Gv2BackupStatesCompanion data) {
    return Gv2BackupStateRow(
      slot: data.slot.present ? data.slot.value : this.slot,
      restored: data.restored.present ? data.restored.value : this.restored,
      etag: data.etag.present ? data.etag.value : this.etag,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      writeDueAtMs: data.writeDueAtMs.present
          ? data.writeDueAtMs.value
          : this.writeDueAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Gv2BackupStateRow(')
          ..write('slot: $slot, ')
          ..write('restored: $restored, ')
          ..write('etag: $etag, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('writeDueAtMs: $writeDueAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    slot,
    restored,
    etag,
    $driftBlobEquality.hash(fingerprint),
    writeDueAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gv2BackupStateRow &&
          other.slot == this.slot &&
          other.restored == this.restored &&
          other.etag == this.etag &&
          $driftBlobEquality.equals(other.fingerprint, this.fingerprint) &&
          other.writeDueAtMs == this.writeDueAtMs);
}

class Gv2BackupStatesCompanion extends UpdateCompanion<Gv2BackupStateRow> {
  final Value<int> slot;
  final Value<bool> restored;
  final Value<String?> etag;
  final Value<Uint8List?> fingerprint;
  final Value<int?> writeDueAtMs;
  const Gv2BackupStatesCompanion({
    this.slot = const Value.absent(),
    this.restored = const Value.absent(),
    this.etag = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.writeDueAtMs = const Value.absent(),
  });
  Gv2BackupStatesCompanion.insert({
    this.slot = const Value.absent(),
    this.restored = const Value.absent(),
    this.etag = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.writeDueAtMs = const Value.absent(),
  });
  static Insertable<Gv2BackupStateRow> custom({
    Expression<int>? slot,
    Expression<bool>? restored,
    Expression<String>? etag,
    Expression<Uint8List>? fingerprint,
    Expression<int>? writeDueAtMs,
  }) {
    return RawValuesInsertable({
      if (slot != null) 'slot': slot,
      if (restored != null) 'restored': restored,
      if (etag != null) 'etag': etag,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (writeDueAtMs != null) 'write_due_at_ms': writeDueAtMs,
    });
  }

  Gv2BackupStatesCompanion copyWith({
    Value<int>? slot,
    Value<bool>? restored,
    Value<String?>? etag,
    Value<Uint8List?>? fingerprint,
    Value<int?>? writeDueAtMs,
  }) {
    return Gv2BackupStatesCompanion(
      slot: slot ?? this.slot,
      restored: restored ?? this.restored,
      etag: etag ?? this.etag,
      fingerprint: fingerprint ?? this.fingerprint,
      writeDueAtMs: writeDueAtMs ?? this.writeDueAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (restored.present) {
      map['restored'] = Variable<bool>(restored.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<Uint8List>(fingerprint.value);
    }
    if (writeDueAtMs.present) {
      map['write_due_at_ms'] = Variable<int>(writeDueAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Gv2BackupStatesCompanion(')
          ..write('slot: $slot, ')
          ..write('restored: $restored, ')
          ..write('etag: $etag, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('writeDueAtMs: $writeDueAtMs')
          ..write(')'))
        .toString();
  }
}

class $BlockedAccountsTable extends BlockedAccounts
    with TableInfo<$BlockedAccountsTable, BlockedAccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlockedAccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _snowIdMeta = const VerificationMeta('snowId');
  @override
  late final GeneratedColumn<String> snowId = GeneratedColumn<String>(
    'snow_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 36,
      maxTextLength: 36,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockedMeta = const VerificationMeta(
    'blocked',
  );
  @override
  late final GeneratedColumn<bool> blocked = GeneratedColumn<bool>(
    'blocked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("blocked" IN (0, 1))',
    ),
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    snowId,
    blocked,
    synced,
    updatedAtMs,
    nickname,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'blocked_accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<BlockedAccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('snow_id')) {
      context.handle(
        _snowIdMeta,
        snowId.isAcceptableOrUnknown(data['snow_id']!, _snowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snowIdMeta);
    }
    if (data.containsKey('blocked')) {
      context.handle(
        _blockedMeta,
        blocked.isAcceptableOrUnknown(data['blocked']!, _blockedMeta),
      );
    } else if (isInserting) {
      context.missing(_blockedMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snowId};
  @override
  BlockedAccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlockedAccountRow(
      snowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snow_id'],
      )!,
      blocked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}blocked'],
      )!,
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      ),
    );
  }

  @override
  $BlockedAccountsTable createAlias(String alias) {
    return $BlockedAccountsTable(attachedDatabase, alias);
  }
}

class BlockedAccountRow extends DataClass
    implements Insertable<BlockedAccountRow> {
  /// The account ("snow" + 32 hex).
  final String snowId;

  /// True: blocked. False: unblocked here while the server still has the
  /// block (the row goes once the server took the unblock).
  final bool blocked;

  /// Whether the server holds what this row says.
  final bool synced;

  /// When this device last changed the row (local clock, ms).
  final int updatedAtMs;

  /// The account's name when it was blocked (contact list / conversation
  /// title), or null. Shown by the blocked-list screen.
  final String? nickname;
  const BlockedAccountRow({
    required this.snowId,
    required this.blocked,
    required this.synced,
    required this.updatedAtMs,
    this.nickname,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['snow_id'] = Variable<String>(snowId);
    map['blocked'] = Variable<bool>(blocked);
    map['synced'] = Variable<bool>(synced);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || nickname != null) {
      map['nickname'] = Variable<String>(nickname);
    }
    return map;
  }

  BlockedAccountsCompanion toCompanion(bool nullToAbsent) {
    return BlockedAccountsCompanion(
      snowId: Value(snowId),
      blocked: Value(blocked),
      synced: Value(synced),
      updatedAtMs: Value(updatedAtMs),
      nickname: nickname == null && nullToAbsent
          ? const Value.absent()
          : Value(nickname),
    );
  }

  factory BlockedAccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlockedAccountRow(
      snowId: serializer.fromJson<String>(json['snowId']),
      blocked: serializer.fromJson<bool>(json['blocked']),
      synced: serializer.fromJson<bool>(json['synced']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      nickname: serializer.fromJson<String?>(json['nickname']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'snowId': serializer.toJson<String>(snowId),
      'blocked': serializer.toJson<bool>(blocked),
      'synced': serializer.toJson<bool>(synced),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'nickname': serializer.toJson<String?>(nickname),
    };
  }

  BlockedAccountRow copyWith({
    String? snowId,
    bool? blocked,
    bool? synced,
    int? updatedAtMs,
    Value<String?> nickname = const Value.absent(),
  }) => BlockedAccountRow(
    snowId: snowId ?? this.snowId,
    blocked: blocked ?? this.blocked,
    synced: synced ?? this.synced,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    nickname: nickname.present ? nickname.value : this.nickname,
  );
  BlockedAccountRow copyWithCompanion(BlockedAccountsCompanion data) {
    return BlockedAccountRow(
      snowId: data.snowId.present ? data.snowId.value : this.snowId,
      blocked: data.blocked.present ? data.blocked.value : this.blocked,
      synced: data.synced.present ? data.synced.value : this.synced,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlockedAccountRow(')
          ..write('snowId: $snowId, ')
          ..write('blocked: $blocked, ')
          ..write('synced: $synced, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('nickname: $nickname')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(snowId, blocked, synced, updatedAtMs, nickname);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockedAccountRow &&
          other.snowId == this.snowId &&
          other.blocked == this.blocked &&
          other.synced == this.synced &&
          other.updatedAtMs == this.updatedAtMs &&
          other.nickname == this.nickname);
}

class BlockedAccountsCompanion extends UpdateCompanion<BlockedAccountRow> {
  final Value<String> snowId;
  final Value<bool> blocked;
  final Value<bool> synced;
  final Value<int> updatedAtMs;
  final Value<String?> nickname;
  final Value<int> rowid;
  const BlockedAccountsCompanion({
    this.snowId = const Value.absent(),
    this.blocked = const Value.absent(),
    this.synced = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.nickname = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlockedAccountsCompanion.insert({
    required String snowId,
    required bool blocked,
    this.synced = const Value.absent(),
    required int updatedAtMs,
    this.nickname = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : snowId = Value(snowId),
       blocked = Value(blocked),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<BlockedAccountRow> custom({
    Expression<String>? snowId,
    Expression<bool>? blocked,
    Expression<bool>? synced,
    Expression<int>? updatedAtMs,
    Expression<String>? nickname,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (snowId != null) 'snow_id': snowId,
      if (blocked != null) 'blocked': blocked,
      if (synced != null) 'synced': synced,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (nickname != null) 'nickname': nickname,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlockedAccountsCompanion copyWith({
    Value<String>? snowId,
    Value<bool>? blocked,
    Value<bool>? synced,
    Value<int>? updatedAtMs,
    Value<String?>? nickname,
    Value<int>? rowid,
  }) {
    return BlockedAccountsCompanion(
      snowId: snowId ?? this.snowId,
      blocked: blocked ?? this.blocked,
      synced: synced ?? this.synced,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      nickname: nickname ?? this.nickname,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (snowId.present) {
      map['snow_id'] = Variable<String>(snowId.value);
    }
    if (blocked.present) {
      map['blocked'] = Variable<bool>(blocked.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlockedAccountsCompanion(')
          ..write('snowId: $snowId, ')
          ..write('blocked: $blocked, ')
          ..write('synced: $synced, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('nickname: $nickname, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DirectOutboxJobsTable extends DirectOutboxJobs
    with TableInfo<$DirectOutboxJobsTable, DirectOutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DirectOutboxJobsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _peerMeta = const VerificationMeta('peer');
  @override
  late final GeneratedColumn<String> peer = GeneratedColumn<String>(
    'peer',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 36,
      maxTextLength: 36,
    ),
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
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _nextAttemptAtMsMeta = const VerificationMeta(
    'nextAttemptAtMs',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAtMs = GeneratedColumn<int>(
    'next_attempt_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    messageId,
    peer,
    kind,
    phase,
    payload,
    createdAtMs,
    attempts,
    nextAttemptAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'direct_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<DirectOutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('peer')) {
      context.handle(
        _peerMeta,
        peer.isAcceptableOrUnknown(data['peer']!, _peerMeta),
      );
    } else if (isInserting) {
      context.missing(_peerMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
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
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at_ms')) {
      context.handle(
        _nextAttemptAtMsMeta,
        nextAttemptAtMs.isAcceptableOrUnknown(
          data['next_attempt_at_ms']!,
          _nextAttemptAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId};
  @override
  DirectOutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DirectOutboxRow(
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      peer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at_ms'],
      )!,
    );
  }

  @override
  $DirectOutboxJobsTable createAlias(String alias) {
    return $DirectOutboxJobsTable(attachedDatabase, alias);
  }
}

class DirectOutboxRow extends DataClass implements Insertable<DirectOutboxRow> {
  /// The local message id (`msg_…`) — also the `cid` the peer deduplicates
  /// by. A control job (kind `control`): a random UUID of its own.
  final String messageId;

  /// The peer ("snow" + 32 hex). A 1:1 room's id is the peer's snowId.
  final String peer;

  /// `text`, `file` or `voice` (MessageType name), or `control` (a contact
  /// notice — DirectOutbox.controlKind).
  final String kind;

  /// DirectOutboxPhase.upload or DirectOutboxPhase.send.
  final String phase;

  /// What the job needs to send without the screen that started it (JSON):
  /// text, ttl, reply fields; for an attachment the kept copy's relative
  /// path, file name, MIME type, size, voice duration, and — once uploaded —
  /// the E2EE metadata (file id and key); for a control job the inner JSON,
  /// whether it travels as a control row and whether it carries the name
  /// certificate. Encrypted at rest with the rest of the database; never
  /// sent anywhere as it is.
  final String payload;

  /// When the message was written (local clock, ms). Orders a peer's jobs;
  /// a job older than DirectOutbox.maxAge fails.
  final int createdAtMs;

  /// Sends tried and not acknowledged (backoff grows with it).
  final int attempts;

  /// Not before this time (local clock, ms); 0 = now.
  final int nextAttemptAtMs;
  const DirectOutboxRow({
    required this.messageId,
    required this.peer,
    required this.kind,
    required this.phase,
    required this.payload,
    required this.createdAtMs,
    required this.attempts,
    required this.nextAttemptAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    map['peer'] = Variable<String>(peer);
    map['kind'] = Variable<String>(kind);
    map['phase'] = Variable<String>(phase);
    map['payload'] = Variable<String>(payload);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['attempts'] = Variable<int>(attempts);
    map['next_attempt_at_ms'] = Variable<int>(nextAttemptAtMs);
    return map;
  }

  DirectOutboxJobsCompanion toCompanion(bool nullToAbsent) {
    return DirectOutboxJobsCompanion(
      messageId: Value(messageId),
      peer: Value(peer),
      kind: Value(kind),
      phase: Value(phase),
      payload: Value(payload),
      createdAtMs: Value(createdAtMs),
      attempts: Value(attempts),
      nextAttemptAtMs: Value(nextAttemptAtMs),
    );
  }

  factory DirectOutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DirectOutboxRow(
      messageId: serializer.fromJson<String>(json['messageId']),
      peer: serializer.fromJson<String>(json['peer']),
      kind: serializer.fromJson<String>(json['kind']),
      phase: serializer.fromJson<String>(json['phase']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAtMs: serializer.fromJson<int>(json['nextAttemptAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'peer': serializer.toJson<String>(peer),
      'kind': serializer.toJson<String>(kind),
      'phase': serializer.toJson<String>(phase),
      'payload': serializer.toJson<String>(payload),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAtMs': serializer.toJson<int>(nextAttemptAtMs),
    };
  }

  DirectOutboxRow copyWith({
    String? messageId,
    String? peer,
    String? kind,
    String? phase,
    String? payload,
    int? createdAtMs,
    int? attempts,
    int? nextAttemptAtMs,
  }) => DirectOutboxRow(
    messageId: messageId ?? this.messageId,
    peer: peer ?? this.peer,
    kind: kind ?? this.kind,
    phase: phase ?? this.phase,
    payload: payload ?? this.payload,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    attempts: attempts ?? this.attempts,
    nextAttemptAtMs: nextAttemptAtMs ?? this.nextAttemptAtMs,
  );
  DirectOutboxRow copyWithCompanion(DirectOutboxJobsCompanion data) {
    return DirectOutboxRow(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      peer: data.peer.present ? data.peer.value : this.peer,
      kind: data.kind.present ? data.kind.value : this.kind,
      phase: data.phase.present ? data.phase.value : this.phase,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAtMs: data.nextAttemptAtMs.present
          ? data.nextAttemptAtMs.value
          : this.nextAttemptAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DirectOutboxRow(')
          ..write('messageId: $messageId, ')
          ..write('peer: $peer, ')
          ..write('kind: $kind, ')
          ..write('phase: $phase, ')
          ..write('payload: $payload, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAtMs: $nextAttemptAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    messageId,
    peer,
    kind,
    phase,
    payload,
    createdAtMs,
    attempts,
    nextAttemptAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DirectOutboxRow &&
          other.messageId == this.messageId &&
          other.peer == this.peer &&
          other.kind == this.kind &&
          other.phase == this.phase &&
          other.payload == this.payload &&
          other.createdAtMs == this.createdAtMs &&
          other.attempts == this.attempts &&
          other.nextAttemptAtMs == this.nextAttemptAtMs);
}

class DirectOutboxJobsCompanion extends UpdateCompanion<DirectOutboxRow> {
  final Value<String> messageId;
  final Value<String> peer;
  final Value<String> kind;
  final Value<String> phase;
  final Value<String> payload;
  final Value<int> createdAtMs;
  final Value<int> attempts;
  final Value<int> nextAttemptAtMs;
  final Value<int> rowid;
  const DirectOutboxJobsCompanion({
    this.messageId = const Value.absent(),
    this.peer = const Value.absent(),
    this.kind = const Value.absent(),
    this.phase = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DirectOutboxJobsCompanion.insert({
    required String messageId,
    required String peer,
    required String kind,
    required String phase,
    required String payload,
    required int createdAtMs,
    this.attempts = const Value.absent(),
    this.nextAttemptAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId),
       peer = Value(peer),
       kind = Value(kind),
       phase = Value(phase),
       payload = Value(payload),
       createdAtMs = Value(createdAtMs);
  static Insertable<DirectOutboxRow> custom({
    Expression<String>? messageId,
    Expression<String>? peer,
    Expression<String>? kind,
    Expression<String>? phase,
    Expression<String>? payload,
    Expression<int>? createdAtMs,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (peer != null) 'peer': peer,
      if (kind != null) 'kind': kind,
      if (phase != null) 'phase': phase,
      if (payload != null) 'payload': payload,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAtMs != null) 'next_attempt_at_ms': nextAttemptAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DirectOutboxJobsCompanion copyWith({
    Value<String>? messageId,
    Value<String>? peer,
    Value<String>? kind,
    Value<String>? phase,
    Value<String>? payload,
    Value<int>? createdAtMs,
    Value<int>? attempts,
    Value<int>? nextAttemptAtMs,
    Value<int>? rowid,
  }) {
    return DirectOutboxJobsCompanion(
      messageId: messageId ?? this.messageId,
      peer: peer ?? this.peer,
      kind: kind ?? this.kind,
      phase: phase ?? this.phase,
      payload: payload ?? this.payload,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      attempts: attempts ?? this.attempts,
      nextAttemptAtMs: nextAttemptAtMs ?? this.nextAttemptAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (peer.present) {
      map['peer'] = Variable<String>(peer.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAtMs.present) {
      map['next_attempt_at_ms'] = Variable<int>(nextAttemptAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DirectOutboxJobsCompanion(')
          ..write('messageId: $messageId, ')
          ..write('peer: $peer, ')
          ..write('kind: $kind, ')
          ..write('phase: $phase, ')
          ..write('payload: $payload, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAtMs: $nextAttemptAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContactListTable extends ContactList
    with TableInfo<$ContactListTable, ContactRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactListTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _snowIdMeta = const VerificationMeta('snowId');
  @override
  late final GeneratedColumn<String> snowId = GeneratedColumn<String>(
    'snow_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 36,
      maxTextLength: 36,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inMyListMeta = const VerificationMeta(
    'inMyList',
  );
  @override
  late final GeneratedColumn<bool> inMyList = GeneratedColumn<bool>(
    'in_my_list',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("in_my_list" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _addedMeMeta = const VerificationMeta(
    'addedMe',
  );
  @override
  late final GeneratedColumn<bool> addedMe = GeneratedColumn<bool>(
    'added_me',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("added_me" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hiddenAtMsMeta = const VerificationMeta(
    'hiddenAtMs',
  );
  @override
  late final GeneratedColumn<int> hiddenAtMs = GeneratedColumn<int>(
    'hidden_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameIssuedAtMsMeta = const VerificationMeta(
    'nameIssuedAtMs',
  );
  @override
  late final GeneratedColumn<int> nameIssuedAtMs = GeneratedColumn<int>(
    'name_issued_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accountPubMeta = const VerificationMeta(
    'accountPub',
  );
  @override
  late final GeneratedColumn<Uint8List> accountPub = GeneratedColumn<Uint8List>(
    'account_pub',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notFoundCountMeta = const VerificationMeta(
    'notFoundCount',
  );
  @override
  late final GeneratedColumn<int> notFoundCount = GeneratedColumn<int>(
    'not_found_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _removedMeAtMsMeta = const VerificationMeta(
    'removedMeAtMs',
  );
  @override
  late final GeneratedColumn<int> removedMeAtMs = GeneratedColumn<int>(
    'removed_me_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    snowId,
    inMyList,
    addedMe,
    hiddenAtMs,
    nickname,
    nameIssuedAtMs,
    accountPub,
    notFoundCount,
    removedMeAtMs,
    createdAtMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contact_list';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContactRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('snow_id')) {
      context.handle(
        _snowIdMeta,
        snowId.isAcceptableOrUnknown(data['snow_id']!, _snowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snowIdMeta);
    }
    if (data.containsKey('in_my_list')) {
      context.handle(
        _inMyListMeta,
        inMyList.isAcceptableOrUnknown(data['in_my_list']!, _inMyListMeta),
      );
    }
    if (data.containsKey('added_me')) {
      context.handle(
        _addedMeMeta,
        addedMe.isAcceptableOrUnknown(data['added_me']!, _addedMeMeta),
      );
    }
    if (data.containsKey('hidden_at_ms')) {
      context.handle(
        _hiddenAtMsMeta,
        hiddenAtMs.isAcceptableOrUnknown(
          data['hidden_at_ms']!,
          _hiddenAtMsMeta,
        ),
      );
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    }
    if (data.containsKey('name_issued_at_ms')) {
      context.handle(
        _nameIssuedAtMsMeta,
        nameIssuedAtMs.isAcceptableOrUnknown(
          data['name_issued_at_ms']!,
          _nameIssuedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('account_pub')) {
      context.handle(
        _accountPubMeta,
        accountPub.isAcceptableOrUnknown(data['account_pub']!, _accountPubMeta),
      );
    }
    if (data.containsKey('not_found_count')) {
      context.handle(
        _notFoundCountMeta,
        notFoundCount.isAcceptableOrUnknown(
          data['not_found_count']!,
          _notFoundCountMeta,
        ),
      );
    }
    if (data.containsKey('removed_me_at_ms')) {
      context.handle(
        _removedMeAtMsMeta,
        removedMeAtMs.isAcceptableOrUnknown(
          data['removed_me_at_ms']!,
          _removedMeAtMsMeta,
        ),
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
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snowId};
  @override
  ContactRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContactRow(
      snowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snow_id'],
      )!,
      inMyList: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}in_my_list'],
      )!,
      addedMe: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}added_me'],
      )!,
      hiddenAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hidden_at_ms'],
      ),
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      ),
      nameIssuedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}name_issued_at_ms'],
      ),
      accountPub: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}account_pub'],
      ),
      notFoundCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}not_found_count'],
      )!,
      removedMeAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}removed_me_at_ms'],
      ),
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $ContactListTable createAlias(String alias) {
    return $ContactListTable(attachedDatabase, alias);
  }
}

class ContactRow extends DataClass implements Insertable<ContactRow> {
  /// The account ("snow" + 32 hex).
  final String snowId;

  /// This user added the account: sent a request, or accepted the account's.
  final bool inMyList;

  /// The account told this user it added them (a sealed contact_added). Opens
  /// nothing — it only changes the label.
  final bool addedMe;

  /// When this user declined the account's request (the row is hidden), or
  /// null. A new contact_added from the account shows the request again.
  final int? hiddenAtMs;

  /// The name from the newest verified name certificate, or null.
  final String? nickname;

  /// Issue time of that certificate (server clock, ms), or null.
  final int? nameIssuedAtMs;

  /// The account public key (32 bytes) that derives [snowId], or null.
  final Uint8List? accountPub;

  /// Sends to the account the server refused in a row with USER_NOT_FOUND
  /// (reset by a send it took, or by a notice from the account). From
  /// ContactStore.unavailableAfterFailures on, the list shows "Account
  /// unavailable" — the row itself is never removed on the server's word.
  /// Kept on this device only (not in the backup).
  final int notFoundCount;

  /// When the account last told this install it removed this user (a sealed
  /// contact_removed), or null — cleared by a later contact_added. The
  /// restore merge reads it: the peer's word on this install is newer than
  /// the backup's addedMe, and a live addedMe=false without it only means "no
  /// word yet". Before the restore of this install ran, a row whose only mark
  /// is this one is kept for it (afterwards such a row goes). Kept on this
  /// device only (not in the backup).
  final int? removedMeAtMs;
  final int createdAtMs;
  final int updatedAtMs;
  const ContactRow({
    required this.snowId,
    required this.inMyList,
    required this.addedMe,
    this.hiddenAtMs,
    this.nickname,
    this.nameIssuedAtMs,
    this.accountPub,
    required this.notFoundCount,
    this.removedMeAtMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['snow_id'] = Variable<String>(snowId);
    map['in_my_list'] = Variable<bool>(inMyList);
    map['added_me'] = Variable<bool>(addedMe);
    if (!nullToAbsent || hiddenAtMs != null) {
      map['hidden_at_ms'] = Variable<int>(hiddenAtMs);
    }
    if (!nullToAbsent || nickname != null) {
      map['nickname'] = Variable<String>(nickname);
    }
    if (!nullToAbsent || nameIssuedAtMs != null) {
      map['name_issued_at_ms'] = Variable<int>(nameIssuedAtMs);
    }
    if (!nullToAbsent || accountPub != null) {
      map['account_pub'] = Variable<Uint8List>(accountPub);
    }
    map['not_found_count'] = Variable<int>(notFoundCount);
    if (!nullToAbsent || removedMeAtMs != null) {
      map['removed_me_at_ms'] = Variable<int>(removedMeAtMs);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  ContactListCompanion toCompanion(bool nullToAbsent) {
    return ContactListCompanion(
      snowId: Value(snowId),
      inMyList: Value(inMyList),
      addedMe: Value(addedMe),
      hiddenAtMs: hiddenAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(hiddenAtMs),
      nickname: nickname == null && nullToAbsent
          ? const Value.absent()
          : Value(nickname),
      nameIssuedAtMs: nameIssuedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(nameIssuedAtMs),
      accountPub: accountPub == null && nullToAbsent
          ? const Value.absent()
          : Value(accountPub),
      notFoundCount: Value(notFoundCount),
      removedMeAtMs: removedMeAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(removedMeAtMs),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory ContactRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContactRow(
      snowId: serializer.fromJson<String>(json['snowId']),
      inMyList: serializer.fromJson<bool>(json['inMyList']),
      addedMe: serializer.fromJson<bool>(json['addedMe']),
      hiddenAtMs: serializer.fromJson<int?>(json['hiddenAtMs']),
      nickname: serializer.fromJson<String?>(json['nickname']),
      nameIssuedAtMs: serializer.fromJson<int?>(json['nameIssuedAtMs']),
      accountPub: serializer.fromJson<Uint8List?>(json['accountPub']),
      notFoundCount: serializer.fromJson<int>(json['notFoundCount']),
      removedMeAtMs: serializer.fromJson<int?>(json['removedMeAtMs']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'snowId': serializer.toJson<String>(snowId),
      'inMyList': serializer.toJson<bool>(inMyList),
      'addedMe': serializer.toJson<bool>(addedMe),
      'hiddenAtMs': serializer.toJson<int?>(hiddenAtMs),
      'nickname': serializer.toJson<String?>(nickname),
      'nameIssuedAtMs': serializer.toJson<int?>(nameIssuedAtMs),
      'accountPub': serializer.toJson<Uint8List?>(accountPub),
      'notFoundCount': serializer.toJson<int>(notFoundCount),
      'removedMeAtMs': serializer.toJson<int?>(removedMeAtMs),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  ContactRow copyWith({
    String? snowId,
    bool? inMyList,
    bool? addedMe,
    Value<int?> hiddenAtMs = const Value.absent(),
    Value<String?> nickname = const Value.absent(),
    Value<int?> nameIssuedAtMs = const Value.absent(),
    Value<Uint8List?> accountPub = const Value.absent(),
    int? notFoundCount,
    Value<int?> removedMeAtMs = const Value.absent(),
    int? createdAtMs,
    int? updatedAtMs,
  }) => ContactRow(
    snowId: snowId ?? this.snowId,
    inMyList: inMyList ?? this.inMyList,
    addedMe: addedMe ?? this.addedMe,
    hiddenAtMs: hiddenAtMs.present ? hiddenAtMs.value : this.hiddenAtMs,
    nickname: nickname.present ? nickname.value : this.nickname,
    nameIssuedAtMs: nameIssuedAtMs.present
        ? nameIssuedAtMs.value
        : this.nameIssuedAtMs,
    accountPub: accountPub.present ? accountPub.value : this.accountPub,
    notFoundCount: notFoundCount ?? this.notFoundCount,
    removedMeAtMs: removedMeAtMs.present
        ? removedMeAtMs.value
        : this.removedMeAtMs,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  ContactRow copyWithCompanion(ContactListCompanion data) {
    return ContactRow(
      snowId: data.snowId.present ? data.snowId.value : this.snowId,
      inMyList: data.inMyList.present ? data.inMyList.value : this.inMyList,
      addedMe: data.addedMe.present ? data.addedMe.value : this.addedMe,
      hiddenAtMs: data.hiddenAtMs.present
          ? data.hiddenAtMs.value
          : this.hiddenAtMs,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      nameIssuedAtMs: data.nameIssuedAtMs.present
          ? data.nameIssuedAtMs.value
          : this.nameIssuedAtMs,
      accountPub: data.accountPub.present
          ? data.accountPub.value
          : this.accountPub,
      notFoundCount: data.notFoundCount.present
          ? data.notFoundCount.value
          : this.notFoundCount,
      removedMeAtMs: data.removedMeAtMs.present
          ? data.removedMeAtMs.value
          : this.removedMeAtMs,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContactRow(')
          ..write('snowId: $snowId, ')
          ..write('inMyList: $inMyList, ')
          ..write('addedMe: $addedMe, ')
          ..write('hiddenAtMs: $hiddenAtMs, ')
          ..write('nickname: $nickname, ')
          ..write('nameIssuedAtMs: $nameIssuedAtMs, ')
          ..write('accountPub: $accountPub, ')
          ..write('notFoundCount: $notFoundCount, ')
          ..write('removedMeAtMs: $removedMeAtMs, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    snowId,
    inMyList,
    addedMe,
    hiddenAtMs,
    nickname,
    nameIssuedAtMs,
    $driftBlobEquality.hash(accountPub),
    notFoundCount,
    removedMeAtMs,
    createdAtMs,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactRow &&
          other.snowId == this.snowId &&
          other.inMyList == this.inMyList &&
          other.addedMe == this.addedMe &&
          other.hiddenAtMs == this.hiddenAtMs &&
          other.nickname == this.nickname &&
          other.nameIssuedAtMs == this.nameIssuedAtMs &&
          $driftBlobEquality.equals(other.accountPub, this.accountPub) &&
          other.notFoundCount == this.notFoundCount &&
          other.removedMeAtMs == this.removedMeAtMs &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class ContactListCompanion extends UpdateCompanion<ContactRow> {
  final Value<String> snowId;
  final Value<bool> inMyList;
  final Value<bool> addedMe;
  final Value<int?> hiddenAtMs;
  final Value<String?> nickname;
  final Value<int?> nameIssuedAtMs;
  final Value<Uint8List?> accountPub;
  final Value<int> notFoundCount;
  final Value<int?> removedMeAtMs;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const ContactListCompanion({
    this.snowId = const Value.absent(),
    this.inMyList = const Value.absent(),
    this.addedMe = const Value.absent(),
    this.hiddenAtMs = const Value.absent(),
    this.nickname = const Value.absent(),
    this.nameIssuedAtMs = const Value.absent(),
    this.accountPub = const Value.absent(),
    this.notFoundCount = const Value.absent(),
    this.removedMeAtMs = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContactListCompanion.insert({
    required String snowId,
    this.inMyList = const Value.absent(),
    this.addedMe = const Value.absent(),
    this.hiddenAtMs = const Value.absent(),
    this.nickname = const Value.absent(),
    this.nameIssuedAtMs = const Value.absent(),
    this.accountPub = const Value.absent(),
    this.notFoundCount = const Value.absent(),
    this.removedMeAtMs = const Value.absent(),
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : snowId = Value(snowId),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<ContactRow> custom({
    Expression<String>? snowId,
    Expression<bool>? inMyList,
    Expression<bool>? addedMe,
    Expression<int>? hiddenAtMs,
    Expression<String>? nickname,
    Expression<int>? nameIssuedAtMs,
    Expression<Uint8List>? accountPub,
    Expression<int>? notFoundCount,
    Expression<int>? removedMeAtMs,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (snowId != null) 'snow_id': snowId,
      if (inMyList != null) 'in_my_list': inMyList,
      if (addedMe != null) 'added_me': addedMe,
      if (hiddenAtMs != null) 'hidden_at_ms': hiddenAtMs,
      if (nickname != null) 'nickname': nickname,
      if (nameIssuedAtMs != null) 'name_issued_at_ms': nameIssuedAtMs,
      if (accountPub != null) 'account_pub': accountPub,
      if (notFoundCount != null) 'not_found_count': notFoundCount,
      if (removedMeAtMs != null) 'removed_me_at_ms': removedMeAtMs,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContactListCompanion copyWith({
    Value<String>? snowId,
    Value<bool>? inMyList,
    Value<bool>? addedMe,
    Value<int?>? hiddenAtMs,
    Value<String?>? nickname,
    Value<int?>? nameIssuedAtMs,
    Value<Uint8List?>? accountPub,
    Value<int>? notFoundCount,
    Value<int?>? removedMeAtMs,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ContactListCompanion(
      snowId: snowId ?? this.snowId,
      inMyList: inMyList ?? this.inMyList,
      addedMe: addedMe ?? this.addedMe,
      hiddenAtMs: hiddenAtMs ?? this.hiddenAtMs,
      nickname: nickname ?? this.nickname,
      nameIssuedAtMs: nameIssuedAtMs ?? this.nameIssuedAtMs,
      accountPub: accountPub ?? this.accountPub,
      notFoundCount: notFoundCount ?? this.notFoundCount,
      removedMeAtMs: removedMeAtMs ?? this.removedMeAtMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (snowId.present) {
      map['snow_id'] = Variable<String>(snowId.value);
    }
    if (inMyList.present) {
      map['in_my_list'] = Variable<bool>(inMyList.value);
    }
    if (addedMe.present) {
      map['added_me'] = Variable<bool>(addedMe.value);
    }
    if (hiddenAtMs.present) {
      map['hidden_at_ms'] = Variable<int>(hiddenAtMs.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (nameIssuedAtMs.present) {
      map['name_issued_at_ms'] = Variable<int>(nameIssuedAtMs.value);
    }
    if (accountPub.present) {
      map['account_pub'] = Variable<Uint8List>(accountPub.value);
    }
    if (notFoundCount.present) {
      map['not_found_count'] = Variable<int>(notFoundCount.value);
    }
    if (removedMeAtMs.present) {
      map['removed_me_at_ms'] = Variable<int>(removedMeAtMs.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactListCompanion(')
          ..write('snowId: $snowId, ')
          ..write('inMyList: $inMyList, ')
          ..write('addedMe: $addedMe, ')
          ..write('hiddenAtMs: $hiddenAtMs, ')
          ..write('nickname: $nickname, ')
          ..write('nameIssuedAtMs: $nameIssuedAtMs, ')
          ..write('accountPub: $accountPub, ')
          ..write('notFoundCount: $notFoundCount, ')
          ..write('removedMeAtMs: $removedMeAtMs, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeerNamesTable extends PeerNames
    with TableInfo<$PeerNamesTable, PeerNameRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeerNamesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerMeta = const VerificationMeta('peer');
  @override
  late final GeneratedColumn<String> peer = GeneratedColumn<String>(
    'peer',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 36,
      maxTextLength: 36,
    ),
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
  static const VerificationMeta _issuedAtMsMeta = const VerificationMeta(
    'issuedAtMs',
  );
  @override
  late final GeneratedColumn<int> issuedAtMs = GeneratedColumn<int>(
    'issued_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _announcedIssuedAtMsMeta =
      const VerificationMeta('announcedIssuedAtMs');
  @override
  late final GeneratedColumn<int> announcedIssuedAtMs = GeneratedColumn<int>(
    'announced_issued_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    peer,
    name,
    issuedAtMs,
    announcedIssuedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'peer_names';
  @override
  VerificationContext validateIntegrity(
    Insertable<PeerNameRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer')) {
      context.handle(
        _peerMeta,
        peer.isAcceptableOrUnknown(data['peer']!, _peerMeta),
      );
    } else if (isInserting) {
      context.missing(_peerMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('issued_at_ms')) {
      context.handle(
        _issuedAtMsMeta,
        issuedAtMs.isAcceptableOrUnknown(
          data['issued_at_ms']!,
          _issuedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('announced_issued_at_ms')) {
      context.handle(
        _announcedIssuedAtMsMeta,
        announcedIssuedAtMs.isAcceptableOrUnknown(
          data['announced_issued_at_ms']!,
          _announcedIssuedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peer};
  @override
  PeerNameRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeerNameRow(
      peer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      issuedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}issued_at_ms'],
      ),
      announcedIssuedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}announced_issued_at_ms'],
      ),
    );
  }

  @override
  $PeerNamesTable createAlias(String alias) {
    return $PeerNamesTable(attachedDatabase, alias);
  }
}

class PeerNameRow extends DataClass implements Insertable<PeerNameRow> {
  /// The peer ("snow" + 32 hex).
  final String peer;

  /// The name of the newest verified certificate the peer sent (null: the
  /// account has no name), or null when none was received.
  final String? name;

  /// Issue time of that certificate (server clock, ms), or null when none was
  /// received.
  final int? issuedAtMs;

  /// Issue time of the newest certificate of this account the server took on
  /// its way to the peer, or null when none was announced yet.
  final int? announcedIssuedAtMs;
  const PeerNameRow({
    required this.peer,
    this.name,
    this.issuedAtMs,
    this.announcedIssuedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer'] = Variable<String>(peer);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || issuedAtMs != null) {
      map['issued_at_ms'] = Variable<int>(issuedAtMs);
    }
    if (!nullToAbsent || announcedIssuedAtMs != null) {
      map['announced_issued_at_ms'] = Variable<int>(announcedIssuedAtMs);
    }
    return map;
  }

  PeerNamesCompanion toCompanion(bool nullToAbsent) {
    return PeerNamesCompanion(
      peer: Value(peer),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      issuedAtMs: issuedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(issuedAtMs),
      announcedIssuedAtMs: announcedIssuedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(announcedIssuedAtMs),
    );
  }

  factory PeerNameRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeerNameRow(
      peer: serializer.fromJson<String>(json['peer']),
      name: serializer.fromJson<String?>(json['name']),
      issuedAtMs: serializer.fromJson<int?>(json['issuedAtMs']),
      announcedIssuedAtMs: serializer.fromJson<int?>(
        json['announcedIssuedAtMs'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peer': serializer.toJson<String>(peer),
      'name': serializer.toJson<String?>(name),
      'issuedAtMs': serializer.toJson<int?>(issuedAtMs),
      'announcedIssuedAtMs': serializer.toJson<int?>(announcedIssuedAtMs),
    };
  }

  PeerNameRow copyWith({
    String? peer,
    Value<String?> name = const Value.absent(),
    Value<int?> issuedAtMs = const Value.absent(),
    Value<int?> announcedIssuedAtMs = const Value.absent(),
  }) => PeerNameRow(
    peer: peer ?? this.peer,
    name: name.present ? name.value : this.name,
    issuedAtMs: issuedAtMs.present ? issuedAtMs.value : this.issuedAtMs,
    announcedIssuedAtMs: announcedIssuedAtMs.present
        ? announcedIssuedAtMs.value
        : this.announcedIssuedAtMs,
  );
  PeerNameRow copyWithCompanion(PeerNamesCompanion data) {
    return PeerNameRow(
      peer: data.peer.present ? data.peer.value : this.peer,
      name: data.name.present ? data.name.value : this.name,
      issuedAtMs: data.issuedAtMs.present
          ? data.issuedAtMs.value
          : this.issuedAtMs,
      announcedIssuedAtMs: data.announcedIssuedAtMs.present
          ? data.announcedIssuedAtMs.value
          : this.announcedIssuedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeerNameRow(')
          ..write('peer: $peer, ')
          ..write('name: $name, ')
          ..write('issuedAtMs: $issuedAtMs, ')
          ..write('announcedIssuedAtMs: $announcedIssuedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(peer, name, issuedAtMs, announcedIssuedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeerNameRow &&
          other.peer == this.peer &&
          other.name == this.name &&
          other.issuedAtMs == this.issuedAtMs &&
          other.announcedIssuedAtMs == this.announcedIssuedAtMs);
}

class PeerNamesCompanion extends UpdateCompanion<PeerNameRow> {
  final Value<String> peer;
  final Value<String?> name;
  final Value<int?> issuedAtMs;
  final Value<int?> announcedIssuedAtMs;
  final Value<int> rowid;
  const PeerNamesCompanion({
    this.peer = const Value.absent(),
    this.name = const Value.absent(),
    this.issuedAtMs = const Value.absent(),
    this.announcedIssuedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeerNamesCompanion.insert({
    required String peer,
    this.name = const Value.absent(),
    this.issuedAtMs = const Value.absent(),
    this.announcedIssuedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : peer = Value(peer);
  static Insertable<PeerNameRow> custom({
    Expression<String>? peer,
    Expression<String>? name,
    Expression<int>? issuedAtMs,
    Expression<int>? announcedIssuedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peer != null) 'peer': peer,
      if (name != null) 'name': name,
      if (issuedAtMs != null) 'issued_at_ms': issuedAtMs,
      if (announcedIssuedAtMs != null)
        'announced_issued_at_ms': announcedIssuedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeerNamesCompanion copyWith({
    Value<String>? peer,
    Value<String?>? name,
    Value<int?>? issuedAtMs,
    Value<int?>? announcedIssuedAtMs,
    Value<int>? rowid,
  }) {
    return PeerNamesCompanion(
      peer: peer ?? this.peer,
      name: name ?? this.name,
      issuedAtMs: issuedAtMs ?? this.issuedAtMs,
      announcedIssuedAtMs: announcedIssuedAtMs ?? this.announcedIssuedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peer.present) {
      map['peer'] = Variable<String>(peer.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (issuedAtMs.present) {
      map['issued_at_ms'] = Variable<int>(issuedAtMs.value);
    }
    if (announcedIssuedAtMs.present) {
      map['announced_issued_at_ms'] = Variable<int>(announcedIssuedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeerNamesCompanion(')
          ..write('peer: $peer, ')
          ..write('name: $name, ')
          ..write('issuedAtMs: $issuedAtMs, ')
          ..write('announcedIssuedAtMs: $announcedIssuedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContactSyncStatesTable extends ContactSyncStates
    with TableInfo<$ContactSyncStatesTable, ContactSyncStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactSyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restoredMeta = const VerificationMeta(
    'restored',
  );
  @override
  late final GeneratedColumn<bool> restored = GeneratedColumn<bool>(
    'restored',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("restored" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _periodMsMeta = const VerificationMeta(
    'periodMs',
  );
  @override
  late final GeneratedColumn<int> periodMs = GeneratedColumn<int>(
    'period_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextWriteAtMsMeta = const VerificationMeta(
    'nextWriteAtMs',
  );
  @override
  late final GeneratedColumn<int> nextWriteAtMs = GeneratedColumn<int>(
    'next_write_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blocksReplacePendingMeta =
      const VerificationMeta('blocksReplacePending');
  @override
  late final GeneratedColumn<bool> blocksReplacePending = GeneratedColumn<bool>(
    'blocks_replace_pending',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("blocks_replace_pending" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _blockKeyVersionMeta = const VerificationMeta(
    'blockKeyVersion',
  );
  @override
  late final GeneratedColumn<int> blockKeyVersion = GeneratedColumn<int>(
    'block_key_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ownNameCertMeta = const VerificationMeta(
    'ownNameCert',
  );
  @override
  late final GeneratedColumn<Uint8List> ownNameCert =
      GeneratedColumn<Uint8List>(
        'own_name_cert',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _ownNameCertAtMsMeta = const VerificationMeta(
    'ownNameCertAtMs',
  );
  @override
  late final GeneratedColumn<int> ownNameCertAtMs = GeneratedColumn<int>(
    'own_name_cert_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restoreNoticeDueMeta = const VerificationMeta(
    'restoreNoticeDue',
  );
  @override
  late final GeneratedColumn<bool> restoreNoticeDue = GeneratedColumn<bool>(
    'restore_notice_due',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("restore_notice_due" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _restoreSavedAtMsMeta = const VerificationMeta(
    'restoreSavedAtMs',
  );
  @override
  late final GeneratedColumn<int> restoreSavedAtMs = GeneratedColumn<int>(
    'restore_saved_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restoreUnreadableMeta = const VerificationMeta(
    'restoreUnreadable',
  );
  @override
  late final GeneratedColumn<bool> restoreUnreadable = GeneratedColumn<bool>(
    'restore_unreadable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("restore_unreadable" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    slot,
    restored,
    etag,
    periodMs,
    nextWriteAtMs,
    blocksReplacePending,
    blockKeyVersion,
    ownNameCert,
    ownNameCertAtMs,
    restoreNoticeDue,
    restoreSavedAtMs,
    restoreUnreadable,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contact_sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContactSyncStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    }
    if (data.containsKey('restored')) {
      context.handle(
        _restoredMeta,
        restored.isAcceptableOrUnknown(data['restored']!, _restoredMeta),
      );
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('period_ms')) {
      context.handle(
        _periodMsMeta,
        periodMs.isAcceptableOrUnknown(data['period_ms']!, _periodMsMeta),
      );
    } else if (isInserting) {
      context.missing(_periodMsMeta);
    }
    if (data.containsKey('next_write_at_ms')) {
      context.handle(
        _nextWriteAtMsMeta,
        nextWriteAtMs.isAcceptableOrUnknown(
          data['next_write_at_ms']!,
          _nextWriteAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextWriteAtMsMeta);
    }
    if (data.containsKey('blocks_replace_pending')) {
      context.handle(
        _blocksReplacePendingMeta,
        blocksReplacePending.isAcceptableOrUnknown(
          data['blocks_replace_pending']!,
          _blocksReplacePendingMeta,
        ),
      );
    }
    if (data.containsKey('block_key_version')) {
      context.handle(
        _blockKeyVersionMeta,
        blockKeyVersion.isAcceptableOrUnknown(
          data['block_key_version']!,
          _blockKeyVersionMeta,
        ),
      );
    }
    if (data.containsKey('own_name_cert')) {
      context.handle(
        _ownNameCertMeta,
        ownNameCert.isAcceptableOrUnknown(
          data['own_name_cert']!,
          _ownNameCertMeta,
        ),
      );
    }
    if (data.containsKey('own_name_cert_at_ms')) {
      context.handle(
        _ownNameCertAtMsMeta,
        ownNameCertAtMs.isAcceptableOrUnknown(
          data['own_name_cert_at_ms']!,
          _ownNameCertAtMsMeta,
        ),
      );
    }
    if (data.containsKey('restore_notice_due')) {
      context.handle(
        _restoreNoticeDueMeta,
        restoreNoticeDue.isAcceptableOrUnknown(
          data['restore_notice_due']!,
          _restoreNoticeDueMeta,
        ),
      );
    }
    if (data.containsKey('restore_saved_at_ms')) {
      context.handle(
        _restoreSavedAtMsMeta,
        restoreSavedAtMs.isAcceptableOrUnknown(
          data['restore_saved_at_ms']!,
          _restoreSavedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('restore_unreadable')) {
      context.handle(
        _restoreUnreadableMeta,
        restoreUnreadable.isAcceptableOrUnknown(
          data['restore_unreadable']!,
          _restoreUnreadableMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {slot};
  @override
  ContactSyncStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContactSyncStateRow(
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      restored: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}restored'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      periodMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}period_ms'],
      )!,
      nextWriteAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_write_at_ms'],
      )!,
      blocksReplacePending: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}blocks_replace_pending'],
      )!,
      blockKeyVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}block_key_version'],
      ),
      ownNameCert: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}own_name_cert'],
      ),
      ownNameCertAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}own_name_cert_at_ms'],
      ),
      restoreNoticeDue: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}restore_notice_due'],
      )!,
      restoreSavedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}restore_saved_at_ms'],
      ),
      restoreUnreadable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}restore_unreadable'],
      )!,
    );
  }

  @override
  $ContactSyncStatesTable createAlias(String alias) {
    return $ContactSyncStatesTable(attachedDatabase, alias);
  }
}

class ContactSyncStateRow extends DataClass
    implements Insertable<ContactSyncStateRow> {
  /// Always 0: one row.
  final int slot;

  /// True once this install looked at the contact backup (restored from it,
  /// or found none, or wrote the empty one of a new account). Once.
  final bool restored;

  /// The server's tag of the blob this device last wrote or read (base64 of
  /// its SHA-256); null when the server holds none.
  final String? etag;

  /// This install's write period (ms), drawn once between 6 and 24 hours.
  final int periodMs;

  /// When the next periodic write is due (local clock, ms).
  final int nextWriteAtMs;

  /// The server's block tags must be replaced by this device's list
  /// (POST /users/blocks/replace): true at first launch and after a restore.
  final bool blocksReplacePending;

  /// The server's block tag key version last seen in a block / unblock /
  /// replace answer, or null. When an answer shows another version, the
  /// tags are replaced by this device's list once (§5.9).
  final int? blockKeyVersion;

  /// This account's own name certificate (bytes as the server issued them),
  /// or null when none was fetched yet.
  final Uint8List? ownNameCert;

  /// When [ownNameCert] was fetched (local clock, ms), or null.
  final int? ownNameCertAtMs;

  /// The restore of this install ran and the user was not told yet what it
  /// found (the notice of §5.10 — shown once, even after an app restart).
  final bool restoreNoticeDue;

  /// When the restored backup was written (its writer's clock, ms); null
  /// when the restore found no backup.
  final int? restoreSavedAtMs;

  /// The server holds a backup this account could not open (another key, or
  /// altered bytes): nothing was restored, the server's block tags were not
  /// replaced and no backup is written over it — [restored] stays false and
  /// every sync tries again; the user is told (§5.10).
  final bool restoreUnreadable;
  const ContactSyncStateRow({
    required this.slot,
    required this.restored,
    this.etag,
    required this.periodMs,
    required this.nextWriteAtMs,
    required this.blocksReplacePending,
    this.blockKeyVersion,
    this.ownNameCert,
    this.ownNameCertAtMs,
    required this.restoreNoticeDue,
    this.restoreSavedAtMs,
    required this.restoreUnreadable,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['slot'] = Variable<int>(slot);
    map['restored'] = Variable<bool>(restored);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    map['period_ms'] = Variable<int>(periodMs);
    map['next_write_at_ms'] = Variable<int>(nextWriteAtMs);
    map['blocks_replace_pending'] = Variable<bool>(blocksReplacePending);
    if (!nullToAbsent || blockKeyVersion != null) {
      map['block_key_version'] = Variable<int>(blockKeyVersion);
    }
    if (!nullToAbsent || ownNameCert != null) {
      map['own_name_cert'] = Variable<Uint8List>(ownNameCert);
    }
    if (!nullToAbsent || ownNameCertAtMs != null) {
      map['own_name_cert_at_ms'] = Variable<int>(ownNameCertAtMs);
    }
    map['restore_notice_due'] = Variable<bool>(restoreNoticeDue);
    if (!nullToAbsent || restoreSavedAtMs != null) {
      map['restore_saved_at_ms'] = Variable<int>(restoreSavedAtMs);
    }
    map['restore_unreadable'] = Variable<bool>(restoreUnreadable);
    return map;
  }

  ContactSyncStatesCompanion toCompanion(bool nullToAbsent) {
    return ContactSyncStatesCompanion(
      slot: Value(slot),
      restored: Value(restored),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      periodMs: Value(periodMs),
      nextWriteAtMs: Value(nextWriteAtMs),
      blocksReplacePending: Value(blocksReplacePending),
      blockKeyVersion: blockKeyVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(blockKeyVersion),
      ownNameCert: ownNameCert == null && nullToAbsent
          ? const Value.absent()
          : Value(ownNameCert),
      ownNameCertAtMs: ownNameCertAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(ownNameCertAtMs),
      restoreNoticeDue: Value(restoreNoticeDue),
      restoreSavedAtMs: restoreSavedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(restoreSavedAtMs),
      restoreUnreadable: Value(restoreUnreadable),
    );
  }

  factory ContactSyncStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContactSyncStateRow(
      slot: serializer.fromJson<int>(json['slot']),
      restored: serializer.fromJson<bool>(json['restored']),
      etag: serializer.fromJson<String?>(json['etag']),
      periodMs: serializer.fromJson<int>(json['periodMs']),
      nextWriteAtMs: serializer.fromJson<int>(json['nextWriteAtMs']),
      blocksReplacePending: serializer.fromJson<bool>(
        json['blocksReplacePending'],
      ),
      blockKeyVersion: serializer.fromJson<int?>(json['blockKeyVersion']),
      ownNameCert: serializer.fromJson<Uint8List?>(json['ownNameCert']),
      ownNameCertAtMs: serializer.fromJson<int?>(json['ownNameCertAtMs']),
      restoreNoticeDue: serializer.fromJson<bool>(json['restoreNoticeDue']),
      restoreSavedAtMs: serializer.fromJson<int?>(json['restoreSavedAtMs']),
      restoreUnreadable: serializer.fromJson<bool>(json['restoreUnreadable']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'slot': serializer.toJson<int>(slot),
      'restored': serializer.toJson<bool>(restored),
      'etag': serializer.toJson<String?>(etag),
      'periodMs': serializer.toJson<int>(periodMs),
      'nextWriteAtMs': serializer.toJson<int>(nextWriteAtMs),
      'blocksReplacePending': serializer.toJson<bool>(blocksReplacePending),
      'blockKeyVersion': serializer.toJson<int?>(blockKeyVersion),
      'ownNameCert': serializer.toJson<Uint8List?>(ownNameCert),
      'ownNameCertAtMs': serializer.toJson<int?>(ownNameCertAtMs),
      'restoreNoticeDue': serializer.toJson<bool>(restoreNoticeDue),
      'restoreSavedAtMs': serializer.toJson<int?>(restoreSavedAtMs),
      'restoreUnreadable': serializer.toJson<bool>(restoreUnreadable),
    };
  }

  ContactSyncStateRow copyWith({
    int? slot,
    bool? restored,
    Value<String?> etag = const Value.absent(),
    int? periodMs,
    int? nextWriteAtMs,
    bool? blocksReplacePending,
    Value<int?> blockKeyVersion = const Value.absent(),
    Value<Uint8List?> ownNameCert = const Value.absent(),
    Value<int?> ownNameCertAtMs = const Value.absent(),
    bool? restoreNoticeDue,
    Value<int?> restoreSavedAtMs = const Value.absent(),
    bool? restoreUnreadable,
  }) => ContactSyncStateRow(
    slot: slot ?? this.slot,
    restored: restored ?? this.restored,
    etag: etag.present ? etag.value : this.etag,
    periodMs: periodMs ?? this.periodMs,
    nextWriteAtMs: nextWriteAtMs ?? this.nextWriteAtMs,
    blocksReplacePending: blocksReplacePending ?? this.blocksReplacePending,
    blockKeyVersion: blockKeyVersion.present
        ? blockKeyVersion.value
        : this.blockKeyVersion,
    ownNameCert: ownNameCert.present ? ownNameCert.value : this.ownNameCert,
    ownNameCertAtMs: ownNameCertAtMs.present
        ? ownNameCertAtMs.value
        : this.ownNameCertAtMs,
    restoreNoticeDue: restoreNoticeDue ?? this.restoreNoticeDue,
    restoreSavedAtMs: restoreSavedAtMs.present
        ? restoreSavedAtMs.value
        : this.restoreSavedAtMs,
    restoreUnreadable: restoreUnreadable ?? this.restoreUnreadable,
  );
  ContactSyncStateRow copyWithCompanion(ContactSyncStatesCompanion data) {
    return ContactSyncStateRow(
      slot: data.slot.present ? data.slot.value : this.slot,
      restored: data.restored.present ? data.restored.value : this.restored,
      etag: data.etag.present ? data.etag.value : this.etag,
      periodMs: data.periodMs.present ? data.periodMs.value : this.periodMs,
      nextWriteAtMs: data.nextWriteAtMs.present
          ? data.nextWriteAtMs.value
          : this.nextWriteAtMs,
      blocksReplacePending: data.blocksReplacePending.present
          ? data.blocksReplacePending.value
          : this.blocksReplacePending,
      blockKeyVersion: data.blockKeyVersion.present
          ? data.blockKeyVersion.value
          : this.blockKeyVersion,
      ownNameCert: data.ownNameCert.present
          ? data.ownNameCert.value
          : this.ownNameCert,
      ownNameCertAtMs: data.ownNameCertAtMs.present
          ? data.ownNameCertAtMs.value
          : this.ownNameCertAtMs,
      restoreNoticeDue: data.restoreNoticeDue.present
          ? data.restoreNoticeDue.value
          : this.restoreNoticeDue,
      restoreSavedAtMs: data.restoreSavedAtMs.present
          ? data.restoreSavedAtMs.value
          : this.restoreSavedAtMs,
      restoreUnreadable: data.restoreUnreadable.present
          ? data.restoreUnreadable.value
          : this.restoreUnreadable,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContactSyncStateRow(')
          ..write('slot: $slot, ')
          ..write('restored: $restored, ')
          ..write('etag: $etag, ')
          ..write('periodMs: $periodMs, ')
          ..write('nextWriteAtMs: $nextWriteAtMs, ')
          ..write('blocksReplacePending: $blocksReplacePending, ')
          ..write('blockKeyVersion: $blockKeyVersion, ')
          ..write('ownNameCert: $ownNameCert, ')
          ..write('ownNameCertAtMs: $ownNameCertAtMs, ')
          ..write('restoreNoticeDue: $restoreNoticeDue, ')
          ..write('restoreSavedAtMs: $restoreSavedAtMs, ')
          ..write('restoreUnreadable: $restoreUnreadable')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    slot,
    restored,
    etag,
    periodMs,
    nextWriteAtMs,
    blocksReplacePending,
    blockKeyVersion,
    $driftBlobEquality.hash(ownNameCert),
    ownNameCertAtMs,
    restoreNoticeDue,
    restoreSavedAtMs,
    restoreUnreadable,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactSyncStateRow &&
          other.slot == this.slot &&
          other.restored == this.restored &&
          other.etag == this.etag &&
          other.periodMs == this.periodMs &&
          other.nextWriteAtMs == this.nextWriteAtMs &&
          other.blocksReplacePending == this.blocksReplacePending &&
          other.blockKeyVersion == this.blockKeyVersion &&
          $driftBlobEquality.equals(other.ownNameCert, this.ownNameCert) &&
          other.ownNameCertAtMs == this.ownNameCertAtMs &&
          other.restoreNoticeDue == this.restoreNoticeDue &&
          other.restoreSavedAtMs == this.restoreSavedAtMs &&
          other.restoreUnreadable == this.restoreUnreadable);
}

class ContactSyncStatesCompanion extends UpdateCompanion<ContactSyncStateRow> {
  final Value<int> slot;
  final Value<bool> restored;
  final Value<String?> etag;
  final Value<int> periodMs;
  final Value<int> nextWriteAtMs;
  final Value<bool> blocksReplacePending;
  final Value<int?> blockKeyVersion;
  final Value<Uint8List?> ownNameCert;
  final Value<int?> ownNameCertAtMs;
  final Value<bool> restoreNoticeDue;
  final Value<int?> restoreSavedAtMs;
  final Value<bool> restoreUnreadable;
  const ContactSyncStatesCompanion({
    this.slot = const Value.absent(),
    this.restored = const Value.absent(),
    this.etag = const Value.absent(),
    this.periodMs = const Value.absent(),
    this.nextWriteAtMs = const Value.absent(),
    this.blocksReplacePending = const Value.absent(),
    this.blockKeyVersion = const Value.absent(),
    this.ownNameCert = const Value.absent(),
    this.ownNameCertAtMs = const Value.absent(),
    this.restoreNoticeDue = const Value.absent(),
    this.restoreSavedAtMs = const Value.absent(),
    this.restoreUnreadable = const Value.absent(),
  });
  ContactSyncStatesCompanion.insert({
    this.slot = const Value.absent(),
    this.restored = const Value.absent(),
    this.etag = const Value.absent(),
    required int periodMs,
    required int nextWriteAtMs,
    this.blocksReplacePending = const Value.absent(),
    this.blockKeyVersion = const Value.absent(),
    this.ownNameCert = const Value.absent(),
    this.ownNameCertAtMs = const Value.absent(),
    this.restoreNoticeDue = const Value.absent(),
    this.restoreSavedAtMs = const Value.absent(),
    this.restoreUnreadable = const Value.absent(),
  }) : periodMs = Value(periodMs),
       nextWriteAtMs = Value(nextWriteAtMs);
  static Insertable<ContactSyncStateRow> custom({
    Expression<int>? slot,
    Expression<bool>? restored,
    Expression<String>? etag,
    Expression<int>? periodMs,
    Expression<int>? nextWriteAtMs,
    Expression<bool>? blocksReplacePending,
    Expression<int>? blockKeyVersion,
    Expression<Uint8List>? ownNameCert,
    Expression<int>? ownNameCertAtMs,
    Expression<bool>? restoreNoticeDue,
    Expression<int>? restoreSavedAtMs,
    Expression<bool>? restoreUnreadable,
  }) {
    return RawValuesInsertable({
      if (slot != null) 'slot': slot,
      if (restored != null) 'restored': restored,
      if (etag != null) 'etag': etag,
      if (periodMs != null) 'period_ms': periodMs,
      if (nextWriteAtMs != null) 'next_write_at_ms': nextWriteAtMs,
      if (blocksReplacePending != null)
        'blocks_replace_pending': blocksReplacePending,
      if (blockKeyVersion != null) 'block_key_version': blockKeyVersion,
      if (ownNameCert != null) 'own_name_cert': ownNameCert,
      if (ownNameCertAtMs != null) 'own_name_cert_at_ms': ownNameCertAtMs,
      if (restoreNoticeDue != null) 'restore_notice_due': restoreNoticeDue,
      if (restoreSavedAtMs != null) 'restore_saved_at_ms': restoreSavedAtMs,
      if (restoreUnreadable != null) 'restore_unreadable': restoreUnreadable,
    });
  }

  ContactSyncStatesCompanion copyWith({
    Value<int>? slot,
    Value<bool>? restored,
    Value<String?>? etag,
    Value<int>? periodMs,
    Value<int>? nextWriteAtMs,
    Value<bool>? blocksReplacePending,
    Value<int?>? blockKeyVersion,
    Value<Uint8List?>? ownNameCert,
    Value<int?>? ownNameCertAtMs,
    Value<bool>? restoreNoticeDue,
    Value<int?>? restoreSavedAtMs,
    Value<bool>? restoreUnreadable,
  }) {
    return ContactSyncStatesCompanion(
      slot: slot ?? this.slot,
      restored: restored ?? this.restored,
      etag: etag ?? this.etag,
      periodMs: periodMs ?? this.periodMs,
      nextWriteAtMs: nextWriteAtMs ?? this.nextWriteAtMs,
      blocksReplacePending: blocksReplacePending ?? this.blocksReplacePending,
      blockKeyVersion: blockKeyVersion ?? this.blockKeyVersion,
      ownNameCert: ownNameCert ?? this.ownNameCert,
      ownNameCertAtMs: ownNameCertAtMs ?? this.ownNameCertAtMs,
      restoreNoticeDue: restoreNoticeDue ?? this.restoreNoticeDue,
      restoreSavedAtMs: restoreSavedAtMs ?? this.restoreSavedAtMs,
      restoreUnreadable: restoreUnreadable ?? this.restoreUnreadable,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (restored.present) {
      map['restored'] = Variable<bool>(restored.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (periodMs.present) {
      map['period_ms'] = Variable<int>(periodMs.value);
    }
    if (nextWriteAtMs.present) {
      map['next_write_at_ms'] = Variable<int>(nextWriteAtMs.value);
    }
    if (blocksReplacePending.present) {
      map['blocks_replace_pending'] = Variable<bool>(
        blocksReplacePending.value,
      );
    }
    if (blockKeyVersion.present) {
      map['block_key_version'] = Variable<int>(blockKeyVersion.value);
    }
    if (ownNameCert.present) {
      map['own_name_cert'] = Variable<Uint8List>(ownNameCert.value);
    }
    if (ownNameCertAtMs.present) {
      map['own_name_cert_at_ms'] = Variable<int>(ownNameCertAtMs.value);
    }
    if (restoreNoticeDue.present) {
      map['restore_notice_due'] = Variable<bool>(restoreNoticeDue.value);
    }
    if (restoreSavedAtMs.present) {
      map['restore_saved_at_ms'] = Variable<int>(restoreSavedAtMs.value);
    }
    if (restoreUnreadable.present) {
      map['restore_unreadable'] = Variable<bool>(restoreUnreadable.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactSyncStatesCompanion(')
          ..write('slot: $slot, ')
          ..write('restored: $restored, ')
          ..write('etag: $etag, ')
          ..write('periodMs: $periodMs, ')
          ..write('nextWriteAtMs: $nextWriteAtMs, ')
          ..write('blocksReplacePending: $blocksReplacePending, ')
          ..write('blockKeyVersion: $blockKeyVersion, ')
          ..write('ownNameCert: $ownNameCert, ')
          ..write('ownNameCertAtMs: $ownNameCertAtMs, ')
          ..write('restoreNoticeDue: $restoreNoticeDue, ')
          ..write('restoreSavedAtMs: $restoreSavedAtMs, ')
          ..write('restoreUnreadable: $restoreUnreadable')
          ..write(')'))
        .toString();
  }
}

abstract class _$SnowDatabase extends GeneratedDatabase {
  _$SnowDatabase(QueryExecutor e) : super(e);
  $SnowDatabaseManager get managers => $SnowDatabaseManager(this);
  late final $LocalMessagesTable localMessages = $LocalMessagesTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $SignalSessionsTable signalSessions = $SignalSessionsTable(this);
  late final $SignalPreKeysTable signalPreKeys = $SignalPreKeysTable(this);
  late final $LocalAttachmentsTable localAttachments = $LocalAttachmentsTable(
    this,
  );
  late final $AiMessagesTable aiMessages = $AiMessagesTable(this);
  late final $IdentityVerificationsTable identityVerifications =
      $IdentityVerificationsTable(this);
  late final $Gv2GroupsTable gv2Groups = $Gv2GroupsTable(this);
  late final $Gv2MembersTable gv2Members = $Gv2MembersTable(this);
  late final $Gv2PendingTable gv2Pending = $Gv2PendingTable(this);
  late final $Gv2ServerKeysTable gv2ServerKeys = $Gv2ServerKeysTable(this);
  late final $Gv2AuthCredentialsTable gv2AuthCredentials =
      $Gv2AuthCredentialsTable(this);
  late final $Gv2EndorsementsTable gv2Endorsements = $Gv2EndorsementsTable(
    this,
  );
  late final $Gv2InboxRowsTable gv2InboxRows = $Gv2InboxRowsTable(this);
  late final $Gv2SeenTable gv2Seen = $Gv2SeenTable(this);
  late final $Gv2HeadsTable gv2Heads = $Gv2HeadsTable(this);
  late final $Gv2SenderKeysTable gv2SenderKeys = $Gv2SenderKeysTable(this);
  late final $Gv2KeyDeliveriesTable gv2KeyDeliveries = $Gv2KeyDeliveriesTable(
    this,
  );
  late final $Gv2OutboxRowsTable gv2OutboxRows = $Gv2OutboxRowsTable(this);
  late final $Gv2MessageIdsTable gv2MessageIds = $Gv2MessageIdsTable(this);
  late final $Gv2BackupStatesTable gv2BackupStates = $Gv2BackupStatesTable(
    this,
  );
  late final $BlockedAccountsTable blockedAccounts = $BlockedAccountsTable(
    this,
  );
  late final $DirectOutboxJobsTable directOutboxJobs = $DirectOutboxJobsTable(
    this,
  );
  late final $ContactListTable contactList = $ContactListTable(this);
  late final $PeerNamesTable peerNames = $PeerNamesTable(this);
  late final $ContactSyncStatesTable contactSyncStates =
      $ContactSyncStatesTable(this);
  late final Index idxMessagesPeerClient = Index(
    'idx_messages_peer_client',
    'CREATE UNIQUE INDEX idx_messages_peer_client ON local_messages (sender_snowchat_id, peer_client_id)',
  );
  late final Index idxGv2MembersSnow = Index(
    'idx_gv2_members_snow',
    'CREATE INDEX idx_gv2_members_snow ON gv2_members (group_id, snow_id)',
  );
  late final Index idxGv2InboxLane = Index(
    'idx_gv2_inbox_lane',
    'CREATE INDEX idx_gv2_inbox_lane ON gv2_inbox (group_id, state)',
  );
  late final Index idxGv2SeenRow = Index(
    'idx_gv2_seen_row',
    'CREATE INDEX idx_gv2_seen_row ON gv2_seen (server_row_id)',
  );
  late final Index idxDirectOutboxPeer = Index(
    'idx_direct_outbox_peer',
    'CREATE INDEX idx_direct_outbox_peer ON direct_outbox (peer, created_at_ms)',
  );
  late final MessageDao messageDao = MessageDao(this as SnowDatabase);
  late final ConversationDao conversationDao = ConversationDao(
    this as SnowDatabase,
  );
  late final AttachmentDao attachmentDao = AttachmentDao(this as SnowDatabase);
  late final AiMessageDao aiMessageDao = AiMessageDao(this as SnowDatabase);
  late final IdentityVerificationDao identityVerificationDao =
      IdentityVerificationDao(this as SnowDatabase);
  late final Gv2Store gv2Store = Gv2Store(this as SnowDatabase);
  late final Gv2InboxStore gv2InboxStore = Gv2InboxStore(this as SnowDatabase);
  late final BlockListDao blockListDao = BlockListDao(this as SnowDatabase);
  late final DirectOutboxDao directOutboxDao = DirectOutboxDao(
    this as SnowDatabase,
  );
  late final ContactDao contactDao = ContactDao(this as SnowDatabase);
  late final Gv2SenderKeyStore gv2SenderKeyStore = Gv2SenderKeyStore(
    this as SnowDatabase,
  );
  late final Gv2OutboxStore gv2OutboxStore = Gv2OutboxStore(
    this as SnowDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localMessages,
    conversations,
    signalSessions,
    signalPreKeys,
    localAttachments,
    aiMessages,
    identityVerifications,
    gv2Groups,
    gv2Members,
    gv2Pending,
    gv2ServerKeys,
    gv2AuthCredentials,
    gv2Endorsements,
    gv2InboxRows,
    gv2Seen,
    gv2Heads,
    gv2SenderKeys,
    gv2KeyDeliveries,
    gv2OutboxRows,
    gv2MessageIds,
    gv2BackupStates,
    blockedAccounts,
    directOutboxJobs,
    contactList,
    peerNames,
    contactSyncStates,
    idxMessagesPeerClient,
    idxGv2MembersSnow,
    idxGv2InboxLane,
    idxGv2SeenRow,
    idxDirectOutboxPeer,
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
      Value<String?> replyToPreview,
      Value<String?> replyToSenderId,
      Value<String?> senderDisplayName,
      Value<String?> peerClientId,
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
      Value<String?> replyToPreview,
      Value<String?> replyToSenderId,
      Value<String?> senderDisplayName,
      Value<String?> peerClientId,
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

  ColumnFilters<String> get replyToPreview => $composableBuilder(
    column: $table.replyToPreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToSenderId => $composableBuilder(
    column: $table.replyToSenderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderDisplayName => $composableBuilder(
    column: $table.senderDisplayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerClientId => $composableBuilder(
    column: $table.peerClientId,
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

  ColumnOrderings<String> get replyToPreview => $composableBuilder(
    column: $table.replyToPreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToSenderId => $composableBuilder(
    column: $table.replyToSenderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderDisplayName => $composableBuilder(
    column: $table.senderDisplayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerClientId => $composableBuilder(
    column: $table.peerClientId,
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

  GeneratedColumn<String> get replyToPreview => $composableBuilder(
    column: $table.replyToPreview,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyToSenderId => $composableBuilder(
    column: $table.replyToSenderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderDisplayName => $composableBuilder(
    column: $table.senderDisplayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerClientId => $composableBuilder(
    column: $table.peerClientId,
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
                Value<String?> replyToPreview = const Value.absent(),
                Value<String?> replyToSenderId = const Value.absent(),
                Value<String?> senderDisplayName = const Value.absent(),
                Value<String?> peerClientId = const Value.absent(),
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
                replyToPreview: replyToPreview,
                replyToSenderId: replyToSenderId,
                senderDisplayName: senderDisplayName,
                peerClientId: peerClientId,
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
                Value<String?> replyToPreview = const Value.absent(),
                Value<String?> replyToSenderId = const Value.absent(),
                Value<String?> senderDisplayName = const Value.absent(),
                Value<String?> peerClientId = const Value.absent(),
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
                replyToPreview: replyToPreview,
                replyToSenderId: replyToSenderId,
                senderDisplayName: senderDisplayName,
                peerClientId: peerClientId,
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
typedef $$Gv2GroupsTableCreateCompanionBuilder =
    Gv2GroupsCompanion Function({
      required String groupId,
      required Uint8List masterKey,
      required String myCiphertext,
      required int protocolVersion,
      required Gv2Membership membership,
      Value<Gv2Hold> hold,
      Value<Uint8List?> holdEvidence,
      required int revision,
      required Uint8List chain,
      required Uint8List stateHash,
      Value<Uint8List?> headSig,
      required bool stateLoaded,
      Value<bool> deleted,
      required Uint8List titlePayload,
      Value<String?> title,
      Value<Uint8List?> inviteSeed,
      Value<String?> invitedBySnowId,
      Value<int?> myKeyRevision,
      Value<int?> myKeyAtMs,
      Value<int?> lastRemovalRevision,
      Value<bool> resetPending,
      Value<int> lastSyncAtMs,
      Value<int?> changeSentAtMs,
      Value<int> rowid,
    });
typedef $$Gv2GroupsTableUpdateCompanionBuilder =
    Gv2GroupsCompanion Function({
      Value<String> groupId,
      Value<Uint8List> masterKey,
      Value<String> myCiphertext,
      Value<int> protocolVersion,
      Value<Gv2Membership> membership,
      Value<Gv2Hold> hold,
      Value<Uint8List?> holdEvidence,
      Value<int> revision,
      Value<Uint8List> chain,
      Value<Uint8List> stateHash,
      Value<Uint8List?> headSig,
      Value<bool> stateLoaded,
      Value<bool> deleted,
      Value<Uint8List> titlePayload,
      Value<String?> title,
      Value<Uint8List?> inviteSeed,
      Value<String?> invitedBySnowId,
      Value<int?> myKeyRevision,
      Value<int?> myKeyAtMs,
      Value<int?> lastRemovalRevision,
      Value<bool> resetPending,
      Value<int> lastSyncAtMs,
      Value<int?> changeSentAtMs,
      Value<int> rowid,
    });

class $$Gv2GroupsTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2GroupsTable> {
  $$Gv2GroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get masterKey => $composableBuilder(
    column: $table.masterKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get myCiphertext => $composableBuilder(
    column: $table.myCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Gv2Membership, Gv2Membership, String>
  get membership => $composableBuilder(
    column: $table.membership,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<Gv2Hold, Gv2Hold, String> get hold =>
      $composableBuilder(
        column: $table.hold,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<Uint8List> get holdEvidence => $composableBuilder(
    column: $table.holdEvidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get chain => $composableBuilder(
    column: $table.chain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get stateHash => $composableBuilder(
    column: $table.stateHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get headSig => $composableBuilder(
    column: $table.headSig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stateLoaded => $composableBuilder(
    column: $table.stateLoaded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get titlePayload => $composableBuilder(
    column: $table.titlePayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get inviteSeed => $composableBuilder(
    column: $table.inviteSeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invitedBySnowId => $composableBuilder(
    column: $table.invitedBySnowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get myKeyRevision => $composableBuilder(
    column: $table.myKeyRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get myKeyAtMs => $composableBuilder(
    column: $table.myKeyAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastRemovalRevision => $composableBuilder(
    column: $table.lastRemovalRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get resetPending => $composableBuilder(
    column: $table.resetPending,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSyncAtMs => $composableBuilder(
    column: $table.lastSyncAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get changeSentAtMs => $composableBuilder(
    column: $table.changeSentAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2GroupsTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2GroupsTable> {
  $$Gv2GroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get masterKey => $composableBuilder(
    column: $table.masterKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get myCiphertext => $composableBuilder(
    column: $table.myCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get membership => $composableBuilder(
    column: $table.membership,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hold => $composableBuilder(
    column: $table.hold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get holdEvidence => $composableBuilder(
    column: $table.holdEvidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get chain => $composableBuilder(
    column: $table.chain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get stateHash => $composableBuilder(
    column: $table.stateHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get headSig => $composableBuilder(
    column: $table.headSig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stateLoaded => $composableBuilder(
    column: $table.stateLoaded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get titlePayload => $composableBuilder(
    column: $table.titlePayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get inviteSeed => $composableBuilder(
    column: $table.inviteSeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invitedBySnowId => $composableBuilder(
    column: $table.invitedBySnowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get myKeyRevision => $composableBuilder(
    column: $table.myKeyRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get myKeyAtMs => $composableBuilder(
    column: $table.myKeyAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastRemovalRevision => $composableBuilder(
    column: $table.lastRemovalRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get resetPending => $composableBuilder(
    column: $table.resetPending,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSyncAtMs => $composableBuilder(
    column: $table.lastSyncAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get changeSentAtMs => $composableBuilder(
    column: $table.changeSentAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2GroupsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2GroupsTable> {
  $$Gv2GroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<Uint8List> get masterKey =>
      $composableBuilder(column: $table.masterKey, builder: (column) => column);

  GeneratedColumn<String> get myCiphertext => $composableBuilder(
    column: $table.myCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Gv2Membership, String> get membership =>
      $composableBuilder(
        column: $table.membership,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<Gv2Hold, String> get hold =>
      $composableBuilder(column: $table.hold, builder: (column) => column);

  GeneratedColumn<Uint8List> get holdEvidence => $composableBuilder(
    column: $table.holdEvidence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<Uint8List> get chain =>
      $composableBuilder(column: $table.chain, builder: (column) => column);

  GeneratedColumn<Uint8List> get stateHash =>
      $composableBuilder(column: $table.stateHash, builder: (column) => column);

  GeneratedColumn<Uint8List> get headSig =>
      $composableBuilder(column: $table.headSig, builder: (column) => column);

  GeneratedColumn<bool> get stateLoaded => $composableBuilder(
    column: $table.stateLoaded,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<Uint8List> get titlePayload => $composableBuilder(
    column: $table.titlePayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<Uint8List> get inviteSeed => $composableBuilder(
    column: $table.inviteSeed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get invitedBySnowId => $composableBuilder(
    column: $table.invitedBySnowId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get myKeyRevision => $composableBuilder(
    column: $table.myKeyRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get myKeyAtMs =>
      $composableBuilder(column: $table.myKeyAtMs, builder: (column) => column);

  GeneratedColumn<int> get lastRemovalRevision => $composableBuilder(
    column: $table.lastRemovalRevision,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get resetPending => $composableBuilder(
    column: $table.resetPending,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSyncAtMs => $composableBuilder(
    column: $table.lastSyncAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get changeSentAtMs => $composableBuilder(
    column: $table.changeSentAtMs,
    builder: (column) => column,
  );
}

class $$Gv2GroupsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2GroupsTable,
          Gv2GroupRow,
          $$Gv2GroupsTableFilterComposer,
          $$Gv2GroupsTableOrderingComposer,
          $$Gv2GroupsTableAnnotationComposer,
          $$Gv2GroupsTableCreateCompanionBuilder,
          $$Gv2GroupsTableUpdateCompanionBuilder,
          (
            Gv2GroupRow,
            BaseReferences<_$SnowDatabase, $Gv2GroupsTable, Gv2GroupRow>,
          ),
          Gv2GroupRow,
          PrefetchHooks Function()
        > {
  $$Gv2GroupsTableTableManager(_$SnowDatabase db, $Gv2GroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2GroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2GroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2GroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<Uint8List> masterKey = const Value.absent(),
                Value<String> myCiphertext = const Value.absent(),
                Value<int> protocolVersion = const Value.absent(),
                Value<Gv2Membership> membership = const Value.absent(),
                Value<Gv2Hold> hold = const Value.absent(),
                Value<Uint8List?> holdEvidence = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<Uint8List> chain = const Value.absent(),
                Value<Uint8List> stateHash = const Value.absent(),
                Value<Uint8List?> headSig = const Value.absent(),
                Value<bool> stateLoaded = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<Uint8List> titlePayload = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<Uint8List?> inviteSeed = const Value.absent(),
                Value<String?> invitedBySnowId = const Value.absent(),
                Value<int?> myKeyRevision = const Value.absent(),
                Value<int?> myKeyAtMs = const Value.absent(),
                Value<int?> lastRemovalRevision = const Value.absent(),
                Value<bool> resetPending = const Value.absent(),
                Value<int> lastSyncAtMs = const Value.absent(),
                Value<int?> changeSentAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2GroupsCompanion(
                groupId: groupId,
                masterKey: masterKey,
                myCiphertext: myCiphertext,
                protocolVersion: protocolVersion,
                membership: membership,
                hold: hold,
                holdEvidence: holdEvidence,
                revision: revision,
                chain: chain,
                stateHash: stateHash,
                headSig: headSig,
                stateLoaded: stateLoaded,
                deleted: deleted,
                titlePayload: titlePayload,
                title: title,
                inviteSeed: inviteSeed,
                invitedBySnowId: invitedBySnowId,
                myKeyRevision: myKeyRevision,
                myKeyAtMs: myKeyAtMs,
                lastRemovalRevision: lastRemovalRevision,
                resetPending: resetPending,
                lastSyncAtMs: lastSyncAtMs,
                changeSentAtMs: changeSentAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required Uint8List masterKey,
                required String myCiphertext,
                required int protocolVersion,
                required Gv2Membership membership,
                Value<Gv2Hold> hold = const Value.absent(),
                Value<Uint8List?> holdEvidence = const Value.absent(),
                required int revision,
                required Uint8List chain,
                required Uint8List stateHash,
                Value<Uint8List?> headSig = const Value.absent(),
                required bool stateLoaded,
                Value<bool> deleted = const Value.absent(),
                required Uint8List titlePayload,
                Value<String?> title = const Value.absent(),
                Value<Uint8List?> inviteSeed = const Value.absent(),
                Value<String?> invitedBySnowId = const Value.absent(),
                Value<int?> myKeyRevision = const Value.absent(),
                Value<int?> myKeyAtMs = const Value.absent(),
                Value<int?> lastRemovalRevision = const Value.absent(),
                Value<bool> resetPending = const Value.absent(),
                Value<int> lastSyncAtMs = const Value.absent(),
                Value<int?> changeSentAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2GroupsCompanion.insert(
                groupId: groupId,
                masterKey: masterKey,
                myCiphertext: myCiphertext,
                protocolVersion: protocolVersion,
                membership: membership,
                hold: hold,
                holdEvidence: holdEvidence,
                revision: revision,
                chain: chain,
                stateHash: stateHash,
                headSig: headSig,
                stateLoaded: stateLoaded,
                deleted: deleted,
                titlePayload: titlePayload,
                title: title,
                inviteSeed: inviteSeed,
                invitedBySnowId: invitedBySnowId,
                myKeyRevision: myKeyRevision,
                myKeyAtMs: myKeyAtMs,
                lastRemovalRevision: lastRemovalRevision,
                resetPending: resetPending,
                lastSyncAtMs: lastSyncAtMs,
                changeSentAtMs: changeSentAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2GroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2GroupsTable,
      Gv2GroupRow,
      $$Gv2GroupsTableFilterComposer,
      $$Gv2GroupsTableOrderingComposer,
      $$Gv2GroupsTableAnnotationComposer,
      $$Gv2GroupsTableCreateCompanionBuilder,
      $$Gv2GroupsTableUpdateCompanionBuilder,
      (
        Gv2GroupRow,
        BaseReferences<_$SnowDatabase, $Gv2GroupsTable, Gv2GroupRow>,
      ),
      Gv2GroupRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2MembersTableCreateCompanionBuilder =
    Gv2MembersCompanion Function({
      required String groupId,
      required String ciphertext,
      required int role,
      required Uint8List memberPub,
      required int joinedRevision,
      required Uint8List memberPayload,
      Value<Gv2MemberCheckState> checkState,
      Value<String?> snowId,
      Value<Uint8List?> accountPublicKey,
      Value<int?> certIssuedAtMs,
      Value<Gv2Reach> reach,
      Value<String?> nickname,
      Value<int?> nicknameFetchedDay,
      Value<int> rowid,
    });
typedef $$Gv2MembersTableUpdateCompanionBuilder =
    Gv2MembersCompanion Function({
      Value<String> groupId,
      Value<String> ciphertext,
      Value<int> role,
      Value<Uint8List> memberPub,
      Value<int> joinedRevision,
      Value<Uint8List> memberPayload,
      Value<Gv2MemberCheckState> checkState,
      Value<String?> snowId,
      Value<Uint8List?> accountPublicKey,
      Value<int?> certIssuedAtMs,
      Value<Gv2Reach> reach,
      Value<String?> nickname,
      Value<int?> nicknameFetchedDay,
      Value<int> rowid,
    });

class $$Gv2MembersTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2MembersTable> {
  $$Gv2MembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get memberPub => $composableBuilder(
    column: $table.memberPub,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get joinedRevision => $composableBuilder(
    column: $table.joinedRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get memberPayload => $composableBuilder(
    column: $table.memberPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Gv2MemberCheckState,
    Gv2MemberCheckState,
    String
  >
  get checkState => $composableBuilder(
    column: $table.checkState,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get accountPublicKey => $composableBuilder(
    column: $table.accountPublicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get certIssuedAtMs => $composableBuilder(
    column: $table.certIssuedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Gv2Reach, Gv2Reach, String> get reach =>
      $composableBuilder(
        column: $table.reach,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nicknameFetchedDay => $composableBuilder(
    column: $table.nicknameFetchedDay,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2MembersTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2MembersTable> {
  $$Gv2MembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get memberPub => $composableBuilder(
    column: $table.memberPub,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get joinedRevision => $composableBuilder(
    column: $table.joinedRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get memberPayload => $composableBuilder(
    column: $table.memberPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkState => $composableBuilder(
    column: $table.checkState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get accountPublicKey => $composableBuilder(
    column: $table.accountPublicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get certIssuedAtMs => $composableBuilder(
    column: $table.certIssuedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reach => $composableBuilder(
    column: $table.reach,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nicknameFetchedDay => $composableBuilder(
    column: $table.nicknameFetchedDay,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2MembersTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2MembersTable> {
  $$Gv2MembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<Uint8List> get memberPub =>
      $composableBuilder(column: $table.memberPub, builder: (column) => column);

  GeneratedColumn<int> get joinedRevision => $composableBuilder(
    column: $table.joinedRevision,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get memberPayload => $composableBuilder(
    column: $table.memberPayload,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Gv2MemberCheckState, String>
  get checkState => $composableBuilder(
    column: $table.checkState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snowId =>
      $composableBuilder(column: $table.snowId, builder: (column) => column);

  GeneratedColumn<Uint8List> get accountPublicKey => $composableBuilder(
    column: $table.accountPublicKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get certIssuedAtMs => $composableBuilder(
    column: $table.certIssuedAtMs,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Gv2Reach, String> get reach =>
      $composableBuilder(column: $table.reach, builder: (column) => column);

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<int> get nicknameFetchedDay => $composableBuilder(
    column: $table.nicknameFetchedDay,
    builder: (column) => column,
  );
}

class $$Gv2MembersTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2MembersTable,
          Gv2MemberRow,
          $$Gv2MembersTableFilterComposer,
          $$Gv2MembersTableOrderingComposer,
          $$Gv2MembersTableAnnotationComposer,
          $$Gv2MembersTableCreateCompanionBuilder,
          $$Gv2MembersTableUpdateCompanionBuilder,
          (
            Gv2MemberRow,
            BaseReferences<_$SnowDatabase, $Gv2MembersTable, Gv2MemberRow>,
          ),
          Gv2MemberRow,
          PrefetchHooks Function()
        > {
  $$Gv2MembersTableTableManager(_$SnowDatabase db, $Gv2MembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2MembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2MembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2MembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> ciphertext = const Value.absent(),
                Value<int> role = const Value.absent(),
                Value<Uint8List> memberPub = const Value.absent(),
                Value<int> joinedRevision = const Value.absent(),
                Value<Uint8List> memberPayload = const Value.absent(),
                Value<Gv2MemberCheckState> checkState = const Value.absent(),
                Value<String?> snowId = const Value.absent(),
                Value<Uint8List?> accountPublicKey = const Value.absent(),
                Value<int?> certIssuedAtMs = const Value.absent(),
                Value<Gv2Reach> reach = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<int?> nicknameFetchedDay = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2MembersCompanion(
                groupId: groupId,
                ciphertext: ciphertext,
                role: role,
                memberPub: memberPub,
                joinedRevision: joinedRevision,
                memberPayload: memberPayload,
                checkState: checkState,
                snowId: snowId,
                accountPublicKey: accountPublicKey,
                certIssuedAtMs: certIssuedAtMs,
                reach: reach,
                nickname: nickname,
                nicknameFetchedDay: nicknameFetchedDay,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String ciphertext,
                required int role,
                required Uint8List memberPub,
                required int joinedRevision,
                required Uint8List memberPayload,
                Value<Gv2MemberCheckState> checkState = const Value.absent(),
                Value<String?> snowId = const Value.absent(),
                Value<Uint8List?> accountPublicKey = const Value.absent(),
                Value<int?> certIssuedAtMs = const Value.absent(),
                Value<Gv2Reach> reach = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<int?> nicknameFetchedDay = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2MembersCompanion.insert(
                groupId: groupId,
                ciphertext: ciphertext,
                role: role,
                memberPub: memberPub,
                joinedRevision: joinedRevision,
                memberPayload: memberPayload,
                checkState: checkState,
                snowId: snowId,
                accountPublicKey: accountPublicKey,
                certIssuedAtMs: certIssuedAtMs,
                reach: reach,
                nickname: nickname,
                nicknameFetchedDay: nicknameFetchedDay,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2MembersTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2MembersTable,
      Gv2MemberRow,
      $$Gv2MembersTableFilterComposer,
      $$Gv2MembersTableOrderingComposer,
      $$Gv2MembersTableAnnotationComposer,
      $$Gv2MembersTableCreateCompanionBuilder,
      $$Gv2MembersTableUpdateCompanionBuilder,
      (
        Gv2MemberRow,
        BaseReferences<_$SnowDatabase, $Gv2MembersTable, Gv2MemberRow>,
      ),
      Gv2MemberRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2PendingTableCreateCompanionBuilder =
    Gv2PendingCompanion Function({
      required String groupId,
      required String ciphertext,
      required String invitedBy,
      required Uint8List invitePub,
      required int revision,
      Value<String?> snowId,
      Value<int> rowid,
    });
typedef $$Gv2PendingTableUpdateCompanionBuilder =
    Gv2PendingCompanion Function({
      Value<String> groupId,
      Value<String> ciphertext,
      Value<String> invitedBy,
      Value<Uint8List> invitePub,
      Value<int> revision,
      Value<String?> snowId,
      Value<int> rowid,
    });

class $$Gv2PendingTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2PendingTable> {
  $$Gv2PendingTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invitedBy => $composableBuilder(
    column: $table.invitedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get invitePub => $composableBuilder(
    column: $table.invitePub,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2PendingTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2PendingTable> {
  $$Gv2PendingTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invitedBy => $composableBuilder(
    column: $table.invitedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get invitePub => $composableBuilder(
    column: $table.invitePub,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2PendingTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2PendingTable> {
  $$Gv2PendingTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => column,
  );

  GeneratedColumn<String> get invitedBy =>
      $composableBuilder(column: $table.invitedBy, builder: (column) => column);

  GeneratedColumn<Uint8List> get invitePub =>
      $composableBuilder(column: $table.invitePub, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get snowId =>
      $composableBuilder(column: $table.snowId, builder: (column) => column);
}

class $$Gv2PendingTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2PendingTable,
          Gv2PendingRow,
          $$Gv2PendingTableFilterComposer,
          $$Gv2PendingTableOrderingComposer,
          $$Gv2PendingTableAnnotationComposer,
          $$Gv2PendingTableCreateCompanionBuilder,
          $$Gv2PendingTableUpdateCompanionBuilder,
          (
            Gv2PendingRow,
            BaseReferences<_$SnowDatabase, $Gv2PendingTable, Gv2PendingRow>,
          ),
          Gv2PendingRow,
          PrefetchHooks Function()
        > {
  $$Gv2PendingTableTableManager(_$SnowDatabase db, $Gv2PendingTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2PendingTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2PendingTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2PendingTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> ciphertext = const Value.absent(),
                Value<String> invitedBy = const Value.absent(),
                Value<Uint8List> invitePub = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String?> snowId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2PendingCompanion(
                groupId: groupId,
                ciphertext: ciphertext,
                invitedBy: invitedBy,
                invitePub: invitePub,
                revision: revision,
                snowId: snowId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String ciphertext,
                required String invitedBy,
                required Uint8List invitePub,
                required int revision,
                Value<String?> snowId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2PendingCompanion.insert(
                groupId: groupId,
                ciphertext: ciphertext,
                invitedBy: invitedBy,
                invitePub: invitePub,
                revision: revision,
                snowId: snowId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2PendingTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2PendingTable,
      Gv2PendingRow,
      $$Gv2PendingTableFilterComposer,
      $$Gv2PendingTableOrderingComposer,
      $$Gv2PendingTableAnnotationComposer,
      $$Gv2PendingTableCreateCompanionBuilder,
      $$Gv2PendingTableUpdateCompanionBuilder,
      (
        Gv2PendingRow,
        BaseReferences<_$SnowDatabase, $Gv2PendingTable, Gv2PendingRow>,
      ),
      Gv2PendingRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2ServerKeysTableCreateCompanionBuilder =
    Gv2ServerKeysCompanion Function({
      Value<int> slot,
      required Uint8List serverPublicParams,
      required Uint8List headPublicKey,
    });
typedef $$Gv2ServerKeysTableUpdateCompanionBuilder =
    Gv2ServerKeysCompanion Function({
      Value<int> slot,
      Value<Uint8List> serverPublicParams,
      Value<Uint8List> headPublicKey,
    });

class $$Gv2ServerKeysTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2ServerKeysTable> {
  $$Gv2ServerKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get serverPublicParams => $composableBuilder(
    column: $table.serverPublicParams,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get headPublicKey => $composableBuilder(
    column: $table.headPublicKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2ServerKeysTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2ServerKeysTable> {
  $$Gv2ServerKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get serverPublicParams => $composableBuilder(
    column: $table.serverPublicParams,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get headPublicKey => $composableBuilder(
    column: $table.headPublicKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2ServerKeysTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2ServerKeysTable> {
  $$Gv2ServerKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<Uint8List> get serverPublicParams => $composableBuilder(
    column: $table.serverPublicParams,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get headPublicKey => $composableBuilder(
    column: $table.headPublicKey,
    builder: (column) => column,
  );
}

class $$Gv2ServerKeysTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2ServerKeysTable,
          Gv2ServerKeysRow,
          $$Gv2ServerKeysTableFilterComposer,
          $$Gv2ServerKeysTableOrderingComposer,
          $$Gv2ServerKeysTableAnnotationComposer,
          $$Gv2ServerKeysTableCreateCompanionBuilder,
          $$Gv2ServerKeysTableUpdateCompanionBuilder,
          (
            Gv2ServerKeysRow,
            BaseReferences<
              _$SnowDatabase,
              $Gv2ServerKeysTable,
              Gv2ServerKeysRow
            >,
          ),
          Gv2ServerKeysRow,
          PrefetchHooks Function()
        > {
  $$Gv2ServerKeysTableTableManager(_$SnowDatabase db, $Gv2ServerKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2ServerKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2ServerKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2ServerKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                Value<Uint8List> serverPublicParams = const Value.absent(),
                Value<Uint8List> headPublicKey = const Value.absent(),
              }) => Gv2ServerKeysCompanion(
                slot: slot,
                serverPublicParams: serverPublicParams,
                headPublicKey: headPublicKey,
              ),
          createCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                required Uint8List serverPublicParams,
                required Uint8List headPublicKey,
              }) => Gv2ServerKeysCompanion.insert(
                slot: slot,
                serverPublicParams: serverPublicParams,
                headPublicKey: headPublicKey,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2ServerKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2ServerKeysTable,
      Gv2ServerKeysRow,
      $$Gv2ServerKeysTableFilterComposer,
      $$Gv2ServerKeysTableOrderingComposer,
      $$Gv2ServerKeysTableAnnotationComposer,
      $$Gv2ServerKeysTableCreateCompanionBuilder,
      $$Gv2ServerKeysTableUpdateCompanionBuilder,
      (
        Gv2ServerKeysRow,
        BaseReferences<_$SnowDatabase, $Gv2ServerKeysTable, Gv2ServerKeysRow>,
      ),
      Gv2ServerKeysRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2AuthCredentialsTableCreateCompanionBuilder =
    Gv2AuthCredentialsCompanion Function({
      Value<int> redemptionTime,
      required String snowId,
      required Uint8List credential,
    });
typedef $$Gv2AuthCredentialsTableUpdateCompanionBuilder =
    Gv2AuthCredentialsCompanion Function({
      Value<int> redemptionTime,
      Value<String> snowId,
      Value<Uint8List> credential,
    });

class $$Gv2AuthCredentialsTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2AuthCredentialsTable> {
  $$Gv2AuthCredentialsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get redemptionTime => $composableBuilder(
    column: $table.redemptionTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get credential => $composableBuilder(
    column: $table.credential,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2AuthCredentialsTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2AuthCredentialsTable> {
  $$Gv2AuthCredentialsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get redemptionTime => $composableBuilder(
    column: $table.redemptionTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get credential => $composableBuilder(
    column: $table.credential,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2AuthCredentialsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2AuthCredentialsTable> {
  $$Gv2AuthCredentialsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get redemptionTime => $composableBuilder(
    column: $table.redemptionTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snowId =>
      $composableBuilder(column: $table.snowId, builder: (column) => column);

  GeneratedColumn<Uint8List> get credential => $composableBuilder(
    column: $table.credential,
    builder: (column) => column,
  );
}

class $$Gv2AuthCredentialsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2AuthCredentialsTable,
          Gv2AuthCredentialRow,
          $$Gv2AuthCredentialsTableFilterComposer,
          $$Gv2AuthCredentialsTableOrderingComposer,
          $$Gv2AuthCredentialsTableAnnotationComposer,
          $$Gv2AuthCredentialsTableCreateCompanionBuilder,
          $$Gv2AuthCredentialsTableUpdateCompanionBuilder,
          (
            Gv2AuthCredentialRow,
            BaseReferences<
              _$SnowDatabase,
              $Gv2AuthCredentialsTable,
              Gv2AuthCredentialRow
            >,
          ),
          Gv2AuthCredentialRow,
          PrefetchHooks Function()
        > {
  $$Gv2AuthCredentialsTableTableManager(
    _$SnowDatabase db,
    $Gv2AuthCredentialsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2AuthCredentialsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2AuthCredentialsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2AuthCredentialsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> redemptionTime = const Value.absent(),
                Value<String> snowId = const Value.absent(),
                Value<Uint8List> credential = const Value.absent(),
              }) => Gv2AuthCredentialsCompanion(
                redemptionTime: redemptionTime,
                snowId: snowId,
                credential: credential,
              ),
          createCompanionCallback:
              ({
                Value<int> redemptionTime = const Value.absent(),
                required String snowId,
                required Uint8List credential,
              }) => Gv2AuthCredentialsCompanion.insert(
                redemptionTime: redemptionTime,
                snowId: snowId,
                credential: credential,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2AuthCredentialsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2AuthCredentialsTable,
      Gv2AuthCredentialRow,
      $$Gv2AuthCredentialsTableFilterComposer,
      $$Gv2AuthCredentialsTableOrderingComposer,
      $$Gv2AuthCredentialsTableAnnotationComposer,
      $$Gv2AuthCredentialsTableCreateCompanionBuilder,
      $$Gv2AuthCredentialsTableUpdateCompanionBuilder,
      (
        Gv2AuthCredentialRow,
        BaseReferences<
          _$SnowDatabase,
          $Gv2AuthCredentialsTable,
          Gv2AuthCredentialRow
        >,
      ),
      Gv2AuthCredentialRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2EndorsementsTableCreateCompanionBuilder =
    Gv2EndorsementsCompanion Function({
      required String groupId,
      required String ciphertext,
      required Uint8List endorsement,
      required int expiration,
      Value<int> rowid,
    });
typedef $$Gv2EndorsementsTableUpdateCompanionBuilder =
    Gv2EndorsementsCompanion Function({
      Value<String> groupId,
      Value<String> ciphertext,
      Value<Uint8List> endorsement,
      Value<int> expiration,
      Value<int> rowid,
    });

class $$Gv2EndorsementsTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2EndorsementsTable> {
  $$Gv2EndorsementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get endorsement => $composableBuilder(
    column: $table.endorsement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiration => $composableBuilder(
    column: $table.expiration,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2EndorsementsTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2EndorsementsTable> {
  $$Gv2EndorsementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get endorsement => $composableBuilder(
    column: $table.endorsement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiration => $composableBuilder(
    column: $table.expiration,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2EndorsementsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2EndorsementsTable> {
  $$Gv2EndorsementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get endorsement => $composableBuilder(
    column: $table.endorsement,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiration => $composableBuilder(
    column: $table.expiration,
    builder: (column) => column,
  );
}

class $$Gv2EndorsementsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2EndorsementsTable,
          Gv2EndorsementRow,
          $$Gv2EndorsementsTableFilterComposer,
          $$Gv2EndorsementsTableOrderingComposer,
          $$Gv2EndorsementsTableAnnotationComposer,
          $$Gv2EndorsementsTableCreateCompanionBuilder,
          $$Gv2EndorsementsTableUpdateCompanionBuilder,
          (
            Gv2EndorsementRow,
            BaseReferences<
              _$SnowDatabase,
              $Gv2EndorsementsTable,
              Gv2EndorsementRow
            >,
          ),
          Gv2EndorsementRow,
          PrefetchHooks Function()
        > {
  $$Gv2EndorsementsTableTableManager(
    _$SnowDatabase db,
    $Gv2EndorsementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2EndorsementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2EndorsementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2EndorsementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> ciphertext = const Value.absent(),
                Value<Uint8List> endorsement = const Value.absent(),
                Value<int> expiration = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2EndorsementsCompanion(
                groupId: groupId,
                ciphertext: ciphertext,
                endorsement: endorsement,
                expiration: expiration,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String ciphertext,
                required Uint8List endorsement,
                required int expiration,
                Value<int> rowid = const Value.absent(),
              }) => Gv2EndorsementsCompanion.insert(
                groupId: groupId,
                ciphertext: ciphertext,
                endorsement: endorsement,
                expiration: expiration,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2EndorsementsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2EndorsementsTable,
      Gv2EndorsementRow,
      $$Gv2EndorsementsTableFilterComposer,
      $$Gv2EndorsementsTableOrderingComposer,
      $$Gv2EndorsementsTableAnnotationComposer,
      $$Gv2EndorsementsTableCreateCompanionBuilder,
      $$Gv2EndorsementsTableUpdateCompanionBuilder,
      (
        Gv2EndorsementRow,
        BaseReferences<
          _$SnowDatabase,
          $Gv2EndorsementsTable,
          Gv2EndorsementRow
        >,
      ),
      Gv2EndorsementRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2InboxRowsTableCreateCompanionBuilder =
    Gv2InboxRowsCompanion Function({
      Value<int> localId,
      required String serverRowId,
      required Uint8List digest,
      required Gv2InboxKind kind,
      required Uint8List payload,
      Value<bool> unsealed,
      Value<String?> groupId,
      required Gv2InboxState state,
      Value<String?> waitFor,
      required int receivedAtMs,
      Value<int> attempts,
    });
typedef $$Gv2InboxRowsTableUpdateCompanionBuilder =
    Gv2InboxRowsCompanion Function({
      Value<int> localId,
      Value<String> serverRowId,
      Value<Uint8List> digest,
      Value<Gv2InboxKind> kind,
      Value<Uint8List> payload,
      Value<bool> unsealed,
      Value<String?> groupId,
      Value<Gv2InboxState> state,
      Value<String?> waitFor,
      Value<int> receivedAtMs,
      Value<int> attempts,
    });

class $$Gv2InboxRowsTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2InboxRowsTable> {
  $$Gv2InboxRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverRowId => $composableBuilder(
    column: $table.serverRowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Gv2InboxKind, Gv2InboxKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get unsealed => $composableBuilder(
    column: $table.unsealed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Gv2InboxState, Gv2InboxState, String>
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get waitFor => $composableBuilder(
    column: $table.waitFor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2InboxRowsTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2InboxRowsTable> {
  $$Gv2InboxRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverRowId => $composableBuilder(
    column: $table.serverRowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get unsealed => $composableBuilder(
    column: $table.unsealed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waitFor => $composableBuilder(
    column: $table.waitFor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2InboxRowsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2InboxRowsTable> {
  $$Gv2InboxRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get serverRowId => $composableBuilder(
    column: $table.serverRowId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get digest =>
      $composableBuilder(column: $table.digest, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Gv2InboxKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<bool> get unsealed =>
      $composableBuilder(column: $table.unsealed, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Gv2InboxState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get waitFor =>
      $composableBuilder(column: $table.waitFor, builder: (column) => column);

  GeneratedColumn<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);
}

class $$Gv2InboxRowsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2InboxRowsTable,
          Gv2InboxRow,
          $$Gv2InboxRowsTableFilterComposer,
          $$Gv2InboxRowsTableOrderingComposer,
          $$Gv2InboxRowsTableAnnotationComposer,
          $$Gv2InboxRowsTableCreateCompanionBuilder,
          $$Gv2InboxRowsTableUpdateCompanionBuilder,
          (
            Gv2InboxRow,
            BaseReferences<_$SnowDatabase, $Gv2InboxRowsTable, Gv2InboxRow>,
          ),
          Gv2InboxRow,
          PrefetchHooks Function()
        > {
  $$Gv2InboxRowsTableTableManager(_$SnowDatabase db, $Gv2InboxRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2InboxRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2InboxRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2InboxRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> localId = const Value.absent(),
                Value<String> serverRowId = const Value.absent(),
                Value<Uint8List> digest = const Value.absent(),
                Value<Gv2InboxKind> kind = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<bool> unsealed = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<Gv2InboxState> state = const Value.absent(),
                Value<String?> waitFor = const Value.absent(),
                Value<int> receivedAtMs = const Value.absent(),
                Value<int> attempts = const Value.absent(),
              }) => Gv2InboxRowsCompanion(
                localId: localId,
                serverRowId: serverRowId,
                digest: digest,
                kind: kind,
                payload: payload,
                unsealed: unsealed,
                groupId: groupId,
                state: state,
                waitFor: waitFor,
                receivedAtMs: receivedAtMs,
                attempts: attempts,
              ),
          createCompanionCallback:
              ({
                Value<int> localId = const Value.absent(),
                required String serverRowId,
                required Uint8List digest,
                required Gv2InboxKind kind,
                required Uint8List payload,
                Value<bool> unsealed = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                required Gv2InboxState state,
                Value<String?> waitFor = const Value.absent(),
                required int receivedAtMs,
                Value<int> attempts = const Value.absent(),
              }) => Gv2InboxRowsCompanion.insert(
                localId: localId,
                serverRowId: serverRowId,
                digest: digest,
                kind: kind,
                payload: payload,
                unsealed: unsealed,
                groupId: groupId,
                state: state,
                waitFor: waitFor,
                receivedAtMs: receivedAtMs,
                attempts: attempts,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2InboxRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2InboxRowsTable,
      Gv2InboxRow,
      $$Gv2InboxRowsTableFilterComposer,
      $$Gv2InboxRowsTableOrderingComposer,
      $$Gv2InboxRowsTableAnnotationComposer,
      $$Gv2InboxRowsTableCreateCompanionBuilder,
      $$Gv2InboxRowsTableUpdateCompanionBuilder,
      (
        Gv2InboxRow,
        BaseReferences<_$SnowDatabase, $Gv2InboxRowsTable, Gv2InboxRow>,
      ),
      Gv2InboxRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2SeenTableCreateCompanionBuilder =
    Gv2SeenCompanion Function({
      required Uint8List digest,
      required String serverRowId,
      Value<String?> conversationId,
      required int day,
      Value<int> rowid,
    });
typedef $$Gv2SeenTableUpdateCompanionBuilder =
    Gv2SeenCompanion Function({
      Value<Uint8List> digest,
      Value<String> serverRowId,
      Value<String?> conversationId,
      Value<int> day,
      Value<int> rowid,
    });

class $$Gv2SeenTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2SeenTable> {
  $$Gv2SeenTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<Uint8List> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverRowId => $composableBuilder(
    column: $table.serverRowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2SeenTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2SeenTable> {
  $$Gv2SeenTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<Uint8List> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverRowId => $composableBuilder(
    column: $table.serverRowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2SeenTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2SeenTable> {
  $$Gv2SeenTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<Uint8List> get digest =>
      $composableBuilder(column: $table.digest, builder: (column) => column);

  GeneratedColumn<String> get serverRowId => $composableBuilder(
    column: $table.serverRowId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);
}

class $$Gv2SeenTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2SeenTable,
          Gv2SeenRow,
          $$Gv2SeenTableFilterComposer,
          $$Gv2SeenTableOrderingComposer,
          $$Gv2SeenTableAnnotationComposer,
          $$Gv2SeenTableCreateCompanionBuilder,
          $$Gv2SeenTableUpdateCompanionBuilder,
          (
            Gv2SeenRow,
            BaseReferences<_$SnowDatabase, $Gv2SeenTable, Gv2SeenRow>,
          ),
          Gv2SeenRow,
          PrefetchHooks Function()
        > {
  $$Gv2SeenTableTableManager(_$SnowDatabase db, $Gv2SeenTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2SeenTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2SeenTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2SeenTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<Uint8List> digest = const Value.absent(),
                Value<String> serverRowId = const Value.absent(),
                Value<String?> conversationId = const Value.absent(),
                Value<int> day = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2SeenCompanion(
                digest: digest,
                serverRowId: serverRowId,
                conversationId: conversationId,
                day: day,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required Uint8List digest,
                required String serverRowId,
                Value<String?> conversationId = const Value.absent(),
                required int day,
                Value<int> rowid = const Value.absent(),
              }) => Gv2SeenCompanion.insert(
                digest: digest,
                serverRowId: serverRowId,
                conversationId: conversationId,
                day: day,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2SeenTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2SeenTable,
      Gv2SeenRow,
      $$Gv2SeenTableFilterComposer,
      $$Gv2SeenTableOrderingComposer,
      $$Gv2SeenTableAnnotationComposer,
      $$Gv2SeenTableCreateCompanionBuilder,
      $$Gv2SeenTableUpdateCompanionBuilder,
      (Gv2SeenRow, BaseReferences<_$SnowDatabase, $Gv2SeenTable, Gv2SeenRow>),
      Gv2SeenRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2HeadsTableCreateCompanionBuilder =
    Gv2HeadsCompanion Function({
      required String groupId,
      required int revision,
      required Uint8List chain,
      Value<Uint8List?> headSig,
      Value<int> storedAtMs,
      Value<int> rowid,
    });
typedef $$Gv2HeadsTableUpdateCompanionBuilder =
    Gv2HeadsCompanion Function({
      Value<String> groupId,
      Value<int> revision,
      Value<Uint8List> chain,
      Value<Uint8List?> headSig,
      Value<int> storedAtMs,
      Value<int> rowid,
    });

class $$Gv2HeadsTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2HeadsTable> {
  $$Gv2HeadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get chain => $composableBuilder(
    column: $table.chain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get headSig => $composableBuilder(
    column: $table.headSig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get storedAtMs => $composableBuilder(
    column: $table.storedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2HeadsTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2HeadsTable> {
  $$Gv2HeadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get chain => $composableBuilder(
    column: $table.chain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get headSig => $composableBuilder(
    column: $table.headSig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get storedAtMs => $composableBuilder(
    column: $table.storedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2HeadsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2HeadsTable> {
  $$Gv2HeadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<Uint8List> get chain =>
      $composableBuilder(column: $table.chain, builder: (column) => column);

  GeneratedColumn<Uint8List> get headSig =>
      $composableBuilder(column: $table.headSig, builder: (column) => column);

  GeneratedColumn<int> get storedAtMs => $composableBuilder(
    column: $table.storedAtMs,
    builder: (column) => column,
  );
}

class $$Gv2HeadsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2HeadsTable,
          Gv2HeadRow,
          $$Gv2HeadsTableFilterComposer,
          $$Gv2HeadsTableOrderingComposer,
          $$Gv2HeadsTableAnnotationComposer,
          $$Gv2HeadsTableCreateCompanionBuilder,
          $$Gv2HeadsTableUpdateCompanionBuilder,
          (
            Gv2HeadRow,
            BaseReferences<_$SnowDatabase, $Gv2HeadsTable, Gv2HeadRow>,
          ),
          Gv2HeadRow,
          PrefetchHooks Function()
        > {
  $$Gv2HeadsTableTableManager(_$SnowDatabase db, $Gv2HeadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2HeadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2HeadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2HeadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<Uint8List> chain = const Value.absent(),
                Value<Uint8List?> headSig = const Value.absent(),
                Value<int> storedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2HeadsCompanion(
                groupId: groupId,
                revision: revision,
                chain: chain,
                headSig: headSig,
                storedAtMs: storedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required int revision,
                required Uint8List chain,
                Value<Uint8List?> headSig = const Value.absent(),
                Value<int> storedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2HeadsCompanion.insert(
                groupId: groupId,
                revision: revision,
                chain: chain,
                headSig: headSig,
                storedAtMs: storedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2HeadsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2HeadsTable,
      Gv2HeadRow,
      $$Gv2HeadsTableFilterComposer,
      $$Gv2HeadsTableOrderingComposer,
      $$Gv2HeadsTableAnnotationComposer,
      $$Gv2HeadsTableCreateCompanionBuilder,
      $$Gv2HeadsTableUpdateCompanionBuilder,
      (Gv2HeadRow, BaseReferences<_$SnowDatabase, $Gv2HeadsTable, Gv2HeadRow>),
      Gv2HeadRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2SenderKeysTableCreateCompanionBuilder =
    Gv2SenderKeysCompanion Function({
      required String groupId,
      required String sender,
      required Uint8List record,
      Value<int> rowid,
    });
typedef $$Gv2SenderKeysTableUpdateCompanionBuilder =
    Gv2SenderKeysCompanion Function({
      Value<String> groupId,
      Value<String> sender,
      Value<Uint8List> record,
      Value<int> rowid,
    });

class $$Gv2SenderKeysTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2SenderKeysTable> {
  $$Gv2SenderKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get record => $composableBuilder(
    column: $table.record,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2SenderKeysTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2SenderKeysTable> {
  $$Gv2SenderKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get record => $composableBuilder(
    column: $table.record,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2SenderKeysTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2SenderKeysTable> {
  $$Gv2SenderKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get sender =>
      $composableBuilder(column: $table.sender, builder: (column) => column);

  GeneratedColumn<Uint8List> get record =>
      $composableBuilder(column: $table.record, builder: (column) => column);
}

class $$Gv2SenderKeysTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2SenderKeysTable,
          Gv2SenderKeyRow,
          $$Gv2SenderKeysTableFilterComposer,
          $$Gv2SenderKeysTableOrderingComposer,
          $$Gv2SenderKeysTableAnnotationComposer,
          $$Gv2SenderKeysTableCreateCompanionBuilder,
          $$Gv2SenderKeysTableUpdateCompanionBuilder,
          (
            Gv2SenderKeyRow,
            BaseReferences<
              _$SnowDatabase,
              $Gv2SenderKeysTable,
              Gv2SenderKeyRow
            >,
          ),
          Gv2SenderKeyRow,
          PrefetchHooks Function()
        > {
  $$Gv2SenderKeysTableTableManager(_$SnowDatabase db, $Gv2SenderKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2SenderKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2SenderKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2SenderKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> sender = const Value.absent(),
                Value<Uint8List> record = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2SenderKeysCompanion(
                groupId: groupId,
                sender: sender,
                record: record,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String sender,
                required Uint8List record,
                Value<int> rowid = const Value.absent(),
              }) => Gv2SenderKeysCompanion.insert(
                groupId: groupId,
                sender: sender,
                record: record,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2SenderKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2SenderKeysTable,
      Gv2SenderKeyRow,
      $$Gv2SenderKeysTableFilterComposer,
      $$Gv2SenderKeysTableOrderingComposer,
      $$Gv2SenderKeysTableAnnotationComposer,
      $$Gv2SenderKeysTableCreateCompanionBuilder,
      $$Gv2SenderKeysTableUpdateCompanionBuilder,
      (
        Gv2SenderKeyRow,
        BaseReferences<_$SnowDatabase, $Gv2SenderKeysTable, Gv2SenderKeyRow>,
      ),
      Gv2SenderKeyRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2KeyDeliveriesTableCreateCompanionBuilder =
    Gv2KeyDeliveriesCompanion Function({
      required String groupId,
      required String member,
      required int chainId,
      required Uint8List key,
      required int deliveredAtMs,
      Value<int> rowid,
    });
typedef $$Gv2KeyDeliveriesTableUpdateCompanionBuilder =
    Gv2KeyDeliveriesCompanion Function({
      Value<String> groupId,
      Value<String> member,
      Value<int> chainId,
      Value<Uint8List> key,
      Value<int> deliveredAtMs,
      Value<int> rowid,
    });

class $$Gv2KeyDeliveriesTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2KeyDeliveriesTable> {
  $$Gv2KeyDeliveriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get member => $composableBuilder(
    column: $table.member,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chainId => $composableBuilder(
    column: $table.chainId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deliveredAtMs => $composableBuilder(
    column: $table.deliveredAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2KeyDeliveriesTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2KeyDeliveriesTable> {
  $$Gv2KeyDeliveriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get member => $composableBuilder(
    column: $table.member,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chainId => $composableBuilder(
    column: $table.chainId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deliveredAtMs => $composableBuilder(
    column: $table.deliveredAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2KeyDeliveriesTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2KeyDeliveriesTable> {
  $$Gv2KeyDeliveriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get member =>
      $composableBuilder(column: $table.member, builder: (column) => column);

  GeneratedColumn<int> get chainId =>
      $composableBuilder(column: $table.chainId, builder: (column) => column);

  GeneratedColumn<Uint8List> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<int> get deliveredAtMs => $composableBuilder(
    column: $table.deliveredAtMs,
    builder: (column) => column,
  );
}

class $$Gv2KeyDeliveriesTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2KeyDeliveriesTable,
          Gv2KeyDeliveryRow,
          $$Gv2KeyDeliveriesTableFilterComposer,
          $$Gv2KeyDeliveriesTableOrderingComposer,
          $$Gv2KeyDeliveriesTableAnnotationComposer,
          $$Gv2KeyDeliveriesTableCreateCompanionBuilder,
          $$Gv2KeyDeliveriesTableUpdateCompanionBuilder,
          (
            Gv2KeyDeliveryRow,
            BaseReferences<
              _$SnowDatabase,
              $Gv2KeyDeliveriesTable,
              Gv2KeyDeliveryRow
            >,
          ),
          Gv2KeyDeliveryRow,
          PrefetchHooks Function()
        > {
  $$Gv2KeyDeliveriesTableTableManager(
    _$SnowDatabase db,
    $Gv2KeyDeliveriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2KeyDeliveriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2KeyDeliveriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2KeyDeliveriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> member = const Value.absent(),
                Value<int> chainId = const Value.absent(),
                Value<Uint8List> key = const Value.absent(),
                Value<int> deliveredAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2KeyDeliveriesCompanion(
                groupId: groupId,
                member: member,
                chainId: chainId,
                key: key,
                deliveredAtMs: deliveredAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String member,
                required int chainId,
                required Uint8List key,
                required int deliveredAtMs,
                Value<int> rowid = const Value.absent(),
              }) => Gv2KeyDeliveriesCompanion.insert(
                groupId: groupId,
                member: member,
                chainId: chainId,
                key: key,
                deliveredAtMs: deliveredAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2KeyDeliveriesTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2KeyDeliveriesTable,
      Gv2KeyDeliveryRow,
      $$Gv2KeyDeliveriesTableFilterComposer,
      $$Gv2KeyDeliveriesTableOrderingComposer,
      $$Gv2KeyDeliveriesTableAnnotationComposer,
      $$Gv2KeyDeliveriesTableCreateCompanionBuilder,
      $$Gv2KeyDeliveriesTableUpdateCompanionBuilder,
      (
        Gv2KeyDeliveryRow,
        BaseReferences<
          _$SnowDatabase,
          $Gv2KeyDeliveriesTable,
          Gv2KeyDeliveryRow
        >,
      ),
      Gv2KeyDeliveryRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2OutboxRowsTableCreateCompanionBuilder =
    Gv2OutboxRowsCompanion Function({
      Value<int> localId,
      required String groupId,
      required Gv2OutboxKind kind,
      Value<String?> recipient,
      required Uint8List payload,
      required int createdAtMs,
      Value<int> notBeforeMs,
      Value<int> attempts,
    });
typedef $$Gv2OutboxRowsTableUpdateCompanionBuilder =
    Gv2OutboxRowsCompanion Function({
      Value<int> localId,
      Value<String> groupId,
      Value<Gv2OutboxKind> kind,
      Value<String?> recipient,
      Value<Uint8List> payload,
      Value<int> createdAtMs,
      Value<int> notBeforeMs,
      Value<int> attempts,
    });

class $$Gv2OutboxRowsTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2OutboxRowsTable> {
  $$Gv2OutboxRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Gv2OutboxKind, Gv2OutboxKind, String>
  get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get recipient => $composableBuilder(
    column: $table.recipient,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notBeforeMs => $composableBuilder(
    column: $table.notBeforeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2OutboxRowsTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2OutboxRowsTable> {
  $$Gv2OutboxRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipient => $composableBuilder(
    column: $table.recipient,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notBeforeMs => $composableBuilder(
    column: $table.notBeforeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2OutboxRowsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2OutboxRowsTable> {
  $$Gv2OutboxRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Gv2OutboxKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get recipient =>
      $composableBuilder(column: $table.recipient, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get notBeforeMs => $composableBuilder(
    column: $table.notBeforeMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);
}

class $$Gv2OutboxRowsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2OutboxRowsTable,
          Gv2OutboxRow,
          $$Gv2OutboxRowsTableFilterComposer,
          $$Gv2OutboxRowsTableOrderingComposer,
          $$Gv2OutboxRowsTableAnnotationComposer,
          $$Gv2OutboxRowsTableCreateCompanionBuilder,
          $$Gv2OutboxRowsTableUpdateCompanionBuilder,
          (
            Gv2OutboxRow,
            BaseReferences<_$SnowDatabase, $Gv2OutboxRowsTable, Gv2OutboxRow>,
          ),
          Gv2OutboxRow,
          PrefetchHooks Function()
        > {
  $$Gv2OutboxRowsTableTableManager(_$SnowDatabase db, $Gv2OutboxRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2OutboxRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2OutboxRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2OutboxRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> localId = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<Gv2OutboxKind> kind = const Value.absent(),
                Value<String?> recipient = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> notBeforeMs = const Value.absent(),
                Value<int> attempts = const Value.absent(),
              }) => Gv2OutboxRowsCompanion(
                localId: localId,
                groupId: groupId,
                kind: kind,
                recipient: recipient,
                payload: payload,
                createdAtMs: createdAtMs,
                notBeforeMs: notBeforeMs,
                attempts: attempts,
              ),
          createCompanionCallback:
              ({
                Value<int> localId = const Value.absent(),
                required String groupId,
                required Gv2OutboxKind kind,
                Value<String?> recipient = const Value.absent(),
                required Uint8List payload,
                required int createdAtMs,
                Value<int> notBeforeMs = const Value.absent(),
                Value<int> attempts = const Value.absent(),
              }) => Gv2OutboxRowsCompanion.insert(
                localId: localId,
                groupId: groupId,
                kind: kind,
                recipient: recipient,
                payload: payload,
                createdAtMs: createdAtMs,
                notBeforeMs: notBeforeMs,
                attempts: attempts,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2OutboxRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2OutboxRowsTable,
      Gv2OutboxRow,
      $$Gv2OutboxRowsTableFilterComposer,
      $$Gv2OutboxRowsTableOrderingComposer,
      $$Gv2OutboxRowsTableAnnotationComposer,
      $$Gv2OutboxRowsTableCreateCompanionBuilder,
      $$Gv2OutboxRowsTableUpdateCompanionBuilder,
      (
        Gv2OutboxRow,
        BaseReferences<_$SnowDatabase, $Gv2OutboxRowsTable, Gv2OutboxRow>,
      ),
      Gv2OutboxRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2MessageIdsTableCreateCompanionBuilder =
    Gv2MessageIdsCompanion Function({
      required Uint8List localMessageId,
      required int day,
      Value<int> rowid,
    });
typedef $$Gv2MessageIdsTableUpdateCompanionBuilder =
    Gv2MessageIdsCompanion Function({
      Value<Uint8List> localMessageId,
      Value<int> day,
      Value<int> rowid,
    });

class $$Gv2MessageIdsTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2MessageIdsTable> {
  $$Gv2MessageIdsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<Uint8List> get localMessageId => $composableBuilder(
    column: $table.localMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2MessageIdsTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2MessageIdsTable> {
  $$Gv2MessageIdsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<Uint8List> get localMessageId => $composableBuilder(
    column: $table.localMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2MessageIdsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2MessageIdsTable> {
  $$Gv2MessageIdsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<Uint8List> get localMessageId => $composableBuilder(
    column: $table.localMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);
}

class $$Gv2MessageIdsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2MessageIdsTable,
          Gv2MessageIdRow,
          $$Gv2MessageIdsTableFilterComposer,
          $$Gv2MessageIdsTableOrderingComposer,
          $$Gv2MessageIdsTableAnnotationComposer,
          $$Gv2MessageIdsTableCreateCompanionBuilder,
          $$Gv2MessageIdsTableUpdateCompanionBuilder,
          (
            Gv2MessageIdRow,
            BaseReferences<
              _$SnowDatabase,
              $Gv2MessageIdsTable,
              Gv2MessageIdRow
            >,
          ),
          Gv2MessageIdRow,
          PrefetchHooks Function()
        > {
  $$Gv2MessageIdsTableTableManager(_$SnowDatabase db, $Gv2MessageIdsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2MessageIdsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2MessageIdsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2MessageIdsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<Uint8List> localMessageId = const Value.absent(),
                Value<int> day = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Gv2MessageIdsCompanion(
                localMessageId: localMessageId,
                day: day,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required Uint8List localMessageId,
                required int day,
                Value<int> rowid = const Value.absent(),
              }) => Gv2MessageIdsCompanion.insert(
                localMessageId: localMessageId,
                day: day,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2MessageIdsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2MessageIdsTable,
      Gv2MessageIdRow,
      $$Gv2MessageIdsTableFilterComposer,
      $$Gv2MessageIdsTableOrderingComposer,
      $$Gv2MessageIdsTableAnnotationComposer,
      $$Gv2MessageIdsTableCreateCompanionBuilder,
      $$Gv2MessageIdsTableUpdateCompanionBuilder,
      (
        Gv2MessageIdRow,
        BaseReferences<_$SnowDatabase, $Gv2MessageIdsTable, Gv2MessageIdRow>,
      ),
      Gv2MessageIdRow,
      PrefetchHooks Function()
    >;
typedef $$Gv2BackupStatesTableCreateCompanionBuilder =
    Gv2BackupStatesCompanion Function({
      Value<int> slot,
      Value<bool> restored,
      Value<String?> etag,
      Value<Uint8List?> fingerprint,
      Value<int?> writeDueAtMs,
    });
typedef $$Gv2BackupStatesTableUpdateCompanionBuilder =
    Gv2BackupStatesCompanion Function({
      Value<int> slot,
      Value<bool> restored,
      Value<String?> etag,
      Value<Uint8List?> fingerprint,
      Value<int?> writeDueAtMs,
    });

class $$Gv2BackupStatesTableFilterComposer
    extends Composer<_$SnowDatabase, $Gv2BackupStatesTable> {
  $$Gv2BackupStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get restored => $composableBuilder(
    column: $table.restored,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get writeDueAtMs => $composableBuilder(
    column: $table.writeDueAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Gv2BackupStatesTableOrderingComposer
    extends Composer<_$SnowDatabase, $Gv2BackupStatesTable> {
  $$Gv2BackupStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get restored => $composableBuilder(
    column: $table.restored,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get writeDueAtMs => $composableBuilder(
    column: $table.writeDueAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Gv2BackupStatesTableAnnotationComposer
    extends Composer<_$SnowDatabase, $Gv2BackupStatesTable> {
  $$Gv2BackupStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<bool> get restored =>
      $composableBuilder(column: $table.restored, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<Uint8List> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get writeDueAtMs => $composableBuilder(
    column: $table.writeDueAtMs,
    builder: (column) => column,
  );
}

class $$Gv2BackupStatesTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $Gv2BackupStatesTable,
          Gv2BackupStateRow,
          $$Gv2BackupStatesTableFilterComposer,
          $$Gv2BackupStatesTableOrderingComposer,
          $$Gv2BackupStatesTableAnnotationComposer,
          $$Gv2BackupStatesTableCreateCompanionBuilder,
          $$Gv2BackupStatesTableUpdateCompanionBuilder,
          (
            Gv2BackupStateRow,
            BaseReferences<
              _$SnowDatabase,
              $Gv2BackupStatesTable,
              Gv2BackupStateRow
            >,
          ),
          Gv2BackupStateRow,
          PrefetchHooks Function()
        > {
  $$Gv2BackupStatesTableTableManager(
    _$SnowDatabase db,
    $Gv2BackupStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Gv2BackupStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Gv2BackupStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Gv2BackupStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                Value<bool> restored = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<Uint8List?> fingerprint = const Value.absent(),
                Value<int?> writeDueAtMs = const Value.absent(),
              }) => Gv2BackupStatesCompanion(
                slot: slot,
                restored: restored,
                etag: etag,
                fingerprint: fingerprint,
                writeDueAtMs: writeDueAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                Value<bool> restored = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<Uint8List?> fingerprint = const Value.absent(),
                Value<int?> writeDueAtMs = const Value.absent(),
              }) => Gv2BackupStatesCompanion.insert(
                slot: slot,
                restored: restored,
                etag: etag,
                fingerprint: fingerprint,
                writeDueAtMs: writeDueAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Gv2BackupStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $Gv2BackupStatesTable,
      Gv2BackupStateRow,
      $$Gv2BackupStatesTableFilterComposer,
      $$Gv2BackupStatesTableOrderingComposer,
      $$Gv2BackupStatesTableAnnotationComposer,
      $$Gv2BackupStatesTableCreateCompanionBuilder,
      $$Gv2BackupStatesTableUpdateCompanionBuilder,
      (
        Gv2BackupStateRow,
        BaseReferences<
          _$SnowDatabase,
          $Gv2BackupStatesTable,
          Gv2BackupStateRow
        >,
      ),
      Gv2BackupStateRow,
      PrefetchHooks Function()
    >;
typedef $$BlockedAccountsTableCreateCompanionBuilder =
    BlockedAccountsCompanion Function({
      required String snowId,
      required bool blocked,
      Value<bool> synced,
      required int updatedAtMs,
      Value<String?> nickname,
      Value<int> rowid,
    });
typedef $$BlockedAccountsTableUpdateCompanionBuilder =
    BlockedAccountsCompanion Function({
      Value<String> snowId,
      Value<bool> blocked,
      Value<bool> synced,
      Value<int> updatedAtMs,
      Value<String?> nickname,
      Value<int> rowid,
    });

class $$BlockedAccountsTableFilterComposer
    extends Composer<_$SnowDatabase, $BlockedAccountsTable> {
  $$BlockedAccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get blocked => $composableBuilder(
    column: $table.blocked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BlockedAccountsTableOrderingComposer
    extends Composer<_$SnowDatabase, $BlockedAccountsTable> {
  $$BlockedAccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get blocked => $composableBuilder(
    column: $table.blocked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BlockedAccountsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $BlockedAccountsTable> {
  $$BlockedAccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get snowId =>
      $composableBuilder(column: $table.snowId, builder: (column) => column);

  GeneratedColumn<bool> get blocked =>
      $composableBuilder(column: $table.blocked, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);
}

class $$BlockedAccountsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $BlockedAccountsTable,
          BlockedAccountRow,
          $$BlockedAccountsTableFilterComposer,
          $$BlockedAccountsTableOrderingComposer,
          $$BlockedAccountsTableAnnotationComposer,
          $$BlockedAccountsTableCreateCompanionBuilder,
          $$BlockedAccountsTableUpdateCompanionBuilder,
          (
            BlockedAccountRow,
            BaseReferences<
              _$SnowDatabase,
              $BlockedAccountsTable,
              BlockedAccountRow
            >,
          ),
          BlockedAccountRow,
          PrefetchHooks Function()
        > {
  $$BlockedAccountsTableTableManager(
    _$SnowDatabase db,
    $BlockedAccountsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlockedAccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlockedAccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlockedAccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> snowId = const Value.absent(),
                Value<bool> blocked = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlockedAccountsCompanion(
                snowId: snowId,
                blocked: blocked,
                synced: synced,
                updatedAtMs: updatedAtMs,
                nickname: nickname,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String snowId,
                required bool blocked,
                Value<bool> synced = const Value.absent(),
                required int updatedAtMs,
                Value<String?> nickname = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlockedAccountsCompanion.insert(
                snowId: snowId,
                blocked: blocked,
                synced: synced,
                updatedAtMs: updatedAtMs,
                nickname: nickname,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BlockedAccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $BlockedAccountsTable,
      BlockedAccountRow,
      $$BlockedAccountsTableFilterComposer,
      $$BlockedAccountsTableOrderingComposer,
      $$BlockedAccountsTableAnnotationComposer,
      $$BlockedAccountsTableCreateCompanionBuilder,
      $$BlockedAccountsTableUpdateCompanionBuilder,
      (
        BlockedAccountRow,
        BaseReferences<
          _$SnowDatabase,
          $BlockedAccountsTable,
          BlockedAccountRow
        >,
      ),
      BlockedAccountRow,
      PrefetchHooks Function()
    >;
typedef $$DirectOutboxJobsTableCreateCompanionBuilder =
    DirectOutboxJobsCompanion Function({
      required String messageId,
      required String peer,
      required String kind,
      required String phase,
      required String payload,
      required int createdAtMs,
      Value<int> attempts,
      Value<int> nextAttemptAtMs,
      Value<int> rowid,
    });
typedef $$DirectOutboxJobsTableUpdateCompanionBuilder =
    DirectOutboxJobsCompanion Function({
      Value<String> messageId,
      Value<String> peer,
      Value<String> kind,
      Value<String> phase,
      Value<String> payload,
      Value<int> createdAtMs,
      Value<int> attempts,
      Value<int> nextAttemptAtMs,
      Value<int> rowid,
    });

class $$DirectOutboxJobsTableFilterComposer
    extends Composer<_$SnowDatabase, $DirectOutboxJobsTable> {
  $$DirectOutboxJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peer => $composableBuilder(
    column: $table.peer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAtMs => $composableBuilder(
    column: $table.nextAttemptAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DirectOutboxJobsTableOrderingComposer
    extends Composer<_$SnowDatabase, $DirectOutboxJobsTable> {
  $$DirectOutboxJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peer => $composableBuilder(
    column: $table.peer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAtMs => $composableBuilder(
    column: $table.nextAttemptAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DirectOutboxJobsTableAnnotationComposer
    extends Composer<_$SnowDatabase, $DirectOutboxJobsTable> {
  $$DirectOutboxJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get peer =>
      $composableBuilder(column: $table.peer, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get nextAttemptAtMs => $composableBuilder(
    column: $table.nextAttemptAtMs,
    builder: (column) => column,
  );
}

class $$DirectOutboxJobsTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $DirectOutboxJobsTable,
          DirectOutboxRow,
          $$DirectOutboxJobsTableFilterComposer,
          $$DirectOutboxJobsTableOrderingComposer,
          $$DirectOutboxJobsTableAnnotationComposer,
          $$DirectOutboxJobsTableCreateCompanionBuilder,
          $$DirectOutboxJobsTableUpdateCompanionBuilder,
          (
            DirectOutboxRow,
            BaseReferences<
              _$SnowDatabase,
              $DirectOutboxJobsTable,
              DirectOutboxRow
            >,
          ),
          DirectOutboxRow,
          PrefetchHooks Function()
        > {
  $$DirectOutboxJobsTableTableManager(
    _$SnowDatabase db,
    $DirectOutboxJobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DirectOutboxJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DirectOutboxJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DirectOutboxJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> messageId = const Value.absent(),
                Value<String> peer = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> nextAttemptAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DirectOutboxJobsCompanion(
                messageId: messageId,
                peer: peer,
                kind: kind,
                phase: phase,
                payload: payload,
                createdAtMs: createdAtMs,
                attempts: attempts,
                nextAttemptAtMs: nextAttemptAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String messageId,
                required String peer,
                required String kind,
                required String phase,
                required String payload,
                required int createdAtMs,
                Value<int> attempts = const Value.absent(),
                Value<int> nextAttemptAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DirectOutboxJobsCompanion.insert(
                messageId: messageId,
                peer: peer,
                kind: kind,
                phase: phase,
                payload: payload,
                createdAtMs: createdAtMs,
                attempts: attempts,
                nextAttemptAtMs: nextAttemptAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DirectOutboxJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $DirectOutboxJobsTable,
      DirectOutboxRow,
      $$DirectOutboxJobsTableFilterComposer,
      $$DirectOutboxJobsTableOrderingComposer,
      $$DirectOutboxJobsTableAnnotationComposer,
      $$DirectOutboxJobsTableCreateCompanionBuilder,
      $$DirectOutboxJobsTableUpdateCompanionBuilder,
      (
        DirectOutboxRow,
        BaseReferences<_$SnowDatabase, $DirectOutboxJobsTable, DirectOutboxRow>,
      ),
      DirectOutboxRow,
      PrefetchHooks Function()
    >;
typedef $$ContactListTableCreateCompanionBuilder =
    ContactListCompanion Function({
      required String snowId,
      Value<bool> inMyList,
      Value<bool> addedMe,
      Value<int?> hiddenAtMs,
      Value<String?> nickname,
      Value<int?> nameIssuedAtMs,
      Value<Uint8List?> accountPub,
      Value<int> notFoundCount,
      Value<int?> removedMeAtMs,
      required int createdAtMs,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$ContactListTableUpdateCompanionBuilder =
    ContactListCompanion Function({
      Value<String> snowId,
      Value<bool> inMyList,
      Value<bool> addedMe,
      Value<int?> hiddenAtMs,
      Value<String?> nickname,
      Value<int?> nameIssuedAtMs,
      Value<Uint8List?> accountPub,
      Value<int> notFoundCount,
      Value<int?> removedMeAtMs,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$ContactListTableFilterComposer
    extends Composer<_$SnowDatabase, $ContactListTable> {
  $$ContactListTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get inMyList => $composableBuilder(
    column: $table.inMyList,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get addedMe => $composableBuilder(
    column: $table.addedMe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hiddenAtMs => $composableBuilder(
    column: $table.hiddenAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nameIssuedAtMs => $composableBuilder(
    column: $table.nameIssuedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get accountPub => $composableBuilder(
    column: $table.accountPub,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notFoundCount => $composableBuilder(
    column: $table.notFoundCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get removedMeAtMs => $composableBuilder(
    column: $table.removedMeAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContactListTableOrderingComposer
    extends Composer<_$SnowDatabase, $ContactListTable> {
  $$ContactListTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get snowId => $composableBuilder(
    column: $table.snowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get inMyList => $composableBuilder(
    column: $table.inMyList,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get addedMe => $composableBuilder(
    column: $table.addedMe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hiddenAtMs => $composableBuilder(
    column: $table.hiddenAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nameIssuedAtMs => $composableBuilder(
    column: $table.nameIssuedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get accountPub => $composableBuilder(
    column: $table.accountPub,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notFoundCount => $composableBuilder(
    column: $table.notFoundCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get removedMeAtMs => $composableBuilder(
    column: $table.removedMeAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContactListTableAnnotationComposer
    extends Composer<_$SnowDatabase, $ContactListTable> {
  $$ContactListTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get snowId =>
      $composableBuilder(column: $table.snowId, builder: (column) => column);

  GeneratedColumn<bool> get inMyList =>
      $composableBuilder(column: $table.inMyList, builder: (column) => column);

  GeneratedColumn<bool> get addedMe =>
      $composableBuilder(column: $table.addedMe, builder: (column) => column);

  GeneratedColumn<int> get hiddenAtMs => $composableBuilder(
    column: $table.hiddenAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<int> get nameIssuedAtMs => $composableBuilder(
    column: $table.nameIssuedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get accountPub => $composableBuilder(
    column: $table.accountPub,
    builder: (column) => column,
  );

  GeneratedColumn<int> get notFoundCount => $composableBuilder(
    column: $table.notFoundCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get removedMeAtMs => $composableBuilder(
    column: $table.removedMeAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$ContactListTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $ContactListTable,
          ContactRow,
          $$ContactListTableFilterComposer,
          $$ContactListTableOrderingComposer,
          $$ContactListTableAnnotationComposer,
          $$ContactListTableCreateCompanionBuilder,
          $$ContactListTableUpdateCompanionBuilder,
          (
            ContactRow,
            BaseReferences<_$SnowDatabase, $ContactListTable, ContactRow>,
          ),
          ContactRow,
          PrefetchHooks Function()
        > {
  $$ContactListTableTableManager(_$SnowDatabase db, $ContactListTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactListTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactListTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactListTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> snowId = const Value.absent(),
                Value<bool> inMyList = const Value.absent(),
                Value<bool> addedMe = const Value.absent(),
                Value<int?> hiddenAtMs = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<int?> nameIssuedAtMs = const Value.absent(),
                Value<Uint8List?> accountPub = const Value.absent(),
                Value<int> notFoundCount = const Value.absent(),
                Value<int?> removedMeAtMs = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactListCompanion(
                snowId: snowId,
                inMyList: inMyList,
                addedMe: addedMe,
                hiddenAtMs: hiddenAtMs,
                nickname: nickname,
                nameIssuedAtMs: nameIssuedAtMs,
                accountPub: accountPub,
                notFoundCount: notFoundCount,
                removedMeAtMs: removedMeAtMs,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String snowId,
                Value<bool> inMyList = const Value.absent(),
                Value<bool> addedMe = const Value.absent(),
                Value<int?> hiddenAtMs = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<int?> nameIssuedAtMs = const Value.absent(),
                Value<Uint8List?> accountPub = const Value.absent(),
                Value<int> notFoundCount = const Value.absent(),
                Value<int?> removedMeAtMs = const Value.absent(),
                required int createdAtMs,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => ContactListCompanion.insert(
                snowId: snowId,
                inMyList: inMyList,
                addedMe: addedMe,
                hiddenAtMs: hiddenAtMs,
                nickname: nickname,
                nameIssuedAtMs: nameIssuedAtMs,
                accountPub: accountPub,
                notFoundCount: notFoundCount,
                removedMeAtMs: removedMeAtMs,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContactListTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $ContactListTable,
      ContactRow,
      $$ContactListTableFilterComposer,
      $$ContactListTableOrderingComposer,
      $$ContactListTableAnnotationComposer,
      $$ContactListTableCreateCompanionBuilder,
      $$ContactListTableUpdateCompanionBuilder,
      (
        ContactRow,
        BaseReferences<_$SnowDatabase, $ContactListTable, ContactRow>,
      ),
      ContactRow,
      PrefetchHooks Function()
    >;
typedef $$PeerNamesTableCreateCompanionBuilder =
    PeerNamesCompanion Function({
      required String peer,
      Value<String?> name,
      Value<int?> issuedAtMs,
      Value<int?> announcedIssuedAtMs,
      Value<int> rowid,
    });
typedef $$PeerNamesTableUpdateCompanionBuilder =
    PeerNamesCompanion Function({
      Value<String> peer,
      Value<String?> name,
      Value<int?> issuedAtMs,
      Value<int?> announcedIssuedAtMs,
      Value<int> rowid,
    });

class $$PeerNamesTableFilterComposer
    extends Composer<_$SnowDatabase, $PeerNamesTable> {
  $$PeerNamesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peer => $composableBuilder(
    column: $table.peer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get issuedAtMs => $composableBuilder(
    column: $table.issuedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get announcedIssuedAtMs => $composableBuilder(
    column: $table.announcedIssuedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PeerNamesTableOrderingComposer
    extends Composer<_$SnowDatabase, $PeerNamesTable> {
  $$PeerNamesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peer => $composableBuilder(
    column: $table.peer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get issuedAtMs => $composableBuilder(
    column: $table.issuedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get announcedIssuedAtMs => $composableBuilder(
    column: $table.announcedIssuedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeerNamesTableAnnotationComposer
    extends Composer<_$SnowDatabase, $PeerNamesTable> {
  $$PeerNamesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peer =>
      $composableBuilder(column: $table.peer, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get issuedAtMs => $composableBuilder(
    column: $table.issuedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get announcedIssuedAtMs => $composableBuilder(
    column: $table.announcedIssuedAtMs,
    builder: (column) => column,
  );
}

class $$PeerNamesTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $PeerNamesTable,
          PeerNameRow,
          $$PeerNamesTableFilterComposer,
          $$PeerNamesTableOrderingComposer,
          $$PeerNamesTableAnnotationComposer,
          $$PeerNamesTableCreateCompanionBuilder,
          $$PeerNamesTableUpdateCompanionBuilder,
          (
            PeerNameRow,
            BaseReferences<_$SnowDatabase, $PeerNamesTable, PeerNameRow>,
          ),
          PeerNameRow,
          PrefetchHooks Function()
        > {
  $$PeerNamesTableTableManager(_$SnowDatabase db, $PeerNamesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeerNamesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeerNamesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeerNamesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> peer = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<int?> issuedAtMs = const Value.absent(),
                Value<int?> announcedIssuedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeerNamesCompanion(
                peer: peer,
                name: name,
                issuedAtMs: issuedAtMs,
                announcedIssuedAtMs: announcedIssuedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peer,
                Value<String?> name = const Value.absent(),
                Value<int?> issuedAtMs = const Value.absent(),
                Value<int?> announcedIssuedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeerNamesCompanion.insert(
                peer: peer,
                name: name,
                issuedAtMs: issuedAtMs,
                announcedIssuedAtMs: announcedIssuedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PeerNamesTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $PeerNamesTable,
      PeerNameRow,
      $$PeerNamesTableFilterComposer,
      $$PeerNamesTableOrderingComposer,
      $$PeerNamesTableAnnotationComposer,
      $$PeerNamesTableCreateCompanionBuilder,
      $$PeerNamesTableUpdateCompanionBuilder,
      (
        PeerNameRow,
        BaseReferences<_$SnowDatabase, $PeerNamesTable, PeerNameRow>,
      ),
      PeerNameRow,
      PrefetchHooks Function()
    >;
typedef $$ContactSyncStatesTableCreateCompanionBuilder =
    ContactSyncStatesCompanion Function({
      Value<int> slot,
      Value<bool> restored,
      Value<String?> etag,
      required int periodMs,
      required int nextWriteAtMs,
      Value<bool> blocksReplacePending,
      Value<int?> blockKeyVersion,
      Value<Uint8List?> ownNameCert,
      Value<int?> ownNameCertAtMs,
      Value<bool> restoreNoticeDue,
      Value<int?> restoreSavedAtMs,
      Value<bool> restoreUnreadable,
    });
typedef $$ContactSyncStatesTableUpdateCompanionBuilder =
    ContactSyncStatesCompanion Function({
      Value<int> slot,
      Value<bool> restored,
      Value<String?> etag,
      Value<int> periodMs,
      Value<int> nextWriteAtMs,
      Value<bool> blocksReplacePending,
      Value<int?> blockKeyVersion,
      Value<Uint8List?> ownNameCert,
      Value<int?> ownNameCertAtMs,
      Value<bool> restoreNoticeDue,
      Value<int?> restoreSavedAtMs,
      Value<bool> restoreUnreadable,
    });

class $$ContactSyncStatesTableFilterComposer
    extends Composer<_$SnowDatabase, $ContactSyncStatesTable> {
  $$ContactSyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get restored => $composableBuilder(
    column: $table.restored,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get periodMs => $composableBuilder(
    column: $table.periodMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextWriteAtMs => $composableBuilder(
    column: $table.nextWriteAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get blocksReplacePending => $composableBuilder(
    column: $table.blocksReplacePending,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get blockKeyVersion => $composableBuilder(
    column: $table.blockKeyVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get ownNameCert => $composableBuilder(
    column: $table.ownNameCert,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ownNameCertAtMs => $composableBuilder(
    column: $table.ownNameCertAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get restoreNoticeDue => $composableBuilder(
    column: $table.restoreNoticeDue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get restoreSavedAtMs => $composableBuilder(
    column: $table.restoreSavedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get restoreUnreadable => $composableBuilder(
    column: $table.restoreUnreadable,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContactSyncStatesTableOrderingComposer
    extends Composer<_$SnowDatabase, $ContactSyncStatesTable> {
  $$ContactSyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get restored => $composableBuilder(
    column: $table.restored,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get periodMs => $composableBuilder(
    column: $table.periodMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextWriteAtMs => $composableBuilder(
    column: $table.nextWriteAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get blocksReplacePending => $composableBuilder(
    column: $table.blocksReplacePending,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get blockKeyVersion => $composableBuilder(
    column: $table.blockKeyVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get ownNameCert => $composableBuilder(
    column: $table.ownNameCert,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ownNameCertAtMs => $composableBuilder(
    column: $table.ownNameCertAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get restoreNoticeDue => $composableBuilder(
    column: $table.restoreNoticeDue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get restoreSavedAtMs => $composableBuilder(
    column: $table.restoreSavedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get restoreUnreadable => $composableBuilder(
    column: $table.restoreUnreadable,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContactSyncStatesTableAnnotationComposer
    extends Composer<_$SnowDatabase, $ContactSyncStatesTable> {
  $$ContactSyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<bool> get restored =>
      $composableBuilder(column: $table.restored, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<int> get periodMs =>
      $composableBuilder(column: $table.periodMs, builder: (column) => column);

  GeneratedColumn<int> get nextWriteAtMs => $composableBuilder(
    column: $table.nextWriteAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get blocksReplacePending => $composableBuilder(
    column: $table.blocksReplacePending,
    builder: (column) => column,
  );

  GeneratedColumn<int> get blockKeyVersion => $composableBuilder(
    column: $table.blockKeyVersion,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get ownNameCert => $composableBuilder(
    column: $table.ownNameCert,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ownNameCertAtMs => $composableBuilder(
    column: $table.ownNameCertAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get restoreNoticeDue => $composableBuilder(
    column: $table.restoreNoticeDue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get restoreSavedAtMs => $composableBuilder(
    column: $table.restoreSavedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get restoreUnreadable => $composableBuilder(
    column: $table.restoreUnreadable,
    builder: (column) => column,
  );
}

class $$ContactSyncStatesTableTableManager
    extends
        RootTableManager<
          _$SnowDatabase,
          $ContactSyncStatesTable,
          ContactSyncStateRow,
          $$ContactSyncStatesTableFilterComposer,
          $$ContactSyncStatesTableOrderingComposer,
          $$ContactSyncStatesTableAnnotationComposer,
          $$ContactSyncStatesTableCreateCompanionBuilder,
          $$ContactSyncStatesTableUpdateCompanionBuilder,
          (
            ContactSyncStateRow,
            BaseReferences<
              _$SnowDatabase,
              $ContactSyncStatesTable,
              ContactSyncStateRow
            >,
          ),
          ContactSyncStateRow,
          PrefetchHooks Function()
        > {
  $$ContactSyncStatesTableTableManager(
    _$SnowDatabase db,
    $ContactSyncStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactSyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactSyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactSyncStatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                Value<bool> restored = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<int> periodMs = const Value.absent(),
                Value<int> nextWriteAtMs = const Value.absent(),
                Value<bool> blocksReplacePending = const Value.absent(),
                Value<int?> blockKeyVersion = const Value.absent(),
                Value<Uint8List?> ownNameCert = const Value.absent(),
                Value<int?> ownNameCertAtMs = const Value.absent(),
                Value<bool> restoreNoticeDue = const Value.absent(),
                Value<int?> restoreSavedAtMs = const Value.absent(),
                Value<bool> restoreUnreadable = const Value.absent(),
              }) => ContactSyncStatesCompanion(
                slot: slot,
                restored: restored,
                etag: etag,
                periodMs: periodMs,
                nextWriteAtMs: nextWriteAtMs,
                blocksReplacePending: blocksReplacePending,
                blockKeyVersion: blockKeyVersion,
                ownNameCert: ownNameCert,
                ownNameCertAtMs: ownNameCertAtMs,
                restoreNoticeDue: restoreNoticeDue,
                restoreSavedAtMs: restoreSavedAtMs,
                restoreUnreadable: restoreUnreadable,
              ),
          createCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                Value<bool> restored = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                required int periodMs,
                required int nextWriteAtMs,
                Value<bool> blocksReplacePending = const Value.absent(),
                Value<int?> blockKeyVersion = const Value.absent(),
                Value<Uint8List?> ownNameCert = const Value.absent(),
                Value<int?> ownNameCertAtMs = const Value.absent(),
                Value<bool> restoreNoticeDue = const Value.absent(),
                Value<int?> restoreSavedAtMs = const Value.absent(),
                Value<bool> restoreUnreadable = const Value.absent(),
              }) => ContactSyncStatesCompanion.insert(
                slot: slot,
                restored: restored,
                etag: etag,
                periodMs: periodMs,
                nextWriteAtMs: nextWriteAtMs,
                blocksReplacePending: blocksReplacePending,
                blockKeyVersion: blockKeyVersion,
                ownNameCert: ownNameCert,
                ownNameCertAtMs: ownNameCertAtMs,
                restoreNoticeDue: restoreNoticeDue,
                restoreSavedAtMs: restoreSavedAtMs,
                restoreUnreadable: restoreUnreadable,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContactSyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$SnowDatabase,
      $ContactSyncStatesTable,
      ContactSyncStateRow,
      $$ContactSyncStatesTableFilterComposer,
      $$ContactSyncStatesTableOrderingComposer,
      $$ContactSyncStatesTableAnnotationComposer,
      $$ContactSyncStatesTableCreateCompanionBuilder,
      $$ContactSyncStatesTableUpdateCompanionBuilder,
      (
        ContactSyncStateRow,
        BaseReferences<
          _$SnowDatabase,
          $ContactSyncStatesTable,
          ContactSyncStateRow
        >,
      ),
      ContactSyncStateRow,
      PrefetchHooks Function()
    >;

class $SnowDatabaseManager {
  final _$SnowDatabase _db;
  $SnowDatabaseManager(this._db);
  $$LocalMessagesTableTableManager get localMessages =>
      $$LocalMessagesTableTableManager(_db, _db.localMessages);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$SignalSessionsTableTableManager get signalSessions =>
      $$SignalSessionsTableTableManager(_db, _db.signalSessions);
  $$SignalPreKeysTableTableManager get signalPreKeys =>
      $$SignalPreKeysTableTableManager(_db, _db.signalPreKeys);
  $$LocalAttachmentsTableTableManager get localAttachments =>
      $$LocalAttachmentsTableTableManager(_db, _db.localAttachments);
  $$AiMessagesTableTableManager get aiMessages =>
      $$AiMessagesTableTableManager(_db, _db.aiMessages);
  $$IdentityVerificationsTableTableManager get identityVerifications =>
      $$IdentityVerificationsTableTableManager(_db, _db.identityVerifications);
  $$Gv2GroupsTableTableManager get gv2Groups =>
      $$Gv2GroupsTableTableManager(_db, _db.gv2Groups);
  $$Gv2MembersTableTableManager get gv2Members =>
      $$Gv2MembersTableTableManager(_db, _db.gv2Members);
  $$Gv2PendingTableTableManager get gv2Pending =>
      $$Gv2PendingTableTableManager(_db, _db.gv2Pending);
  $$Gv2ServerKeysTableTableManager get gv2ServerKeys =>
      $$Gv2ServerKeysTableTableManager(_db, _db.gv2ServerKeys);
  $$Gv2AuthCredentialsTableTableManager get gv2AuthCredentials =>
      $$Gv2AuthCredentialsTableTableManager(_db, _db.gv2AuthCredentials);
  $$Gv2EndorsementsTableTableManager get gv2Endorsements =>
      $$Gv2EndorsementsTableTableManager(_db, _db.gv2Endorsements);
  $$Gv2InboxRowsTableTableManager get gv2InboxRows =>
      $$Gv2InboxRowsTableTableManager(_db, _db.gv2InboxRows);
  $$Gv2SeenTableTableManager get gv2Seen =>
      $$Gv2SeenTableTableManager(_db, _db.gv2Seen);
  $$Gv2HeadsTableTableManager get gv2Heads =>
      $$Gv2HeadsTableTableManager(_db, _db.gv2Heads);
  $$Gv2SenderKeysTableTableManager get gv2SenderKeys =>
      $$Gv2SenderKeysTableTableManager(_db, _db.gv2SenderKeys);
  $$Gv2KeyDeliveriesTableTableManager get gv2KeyDeliveries =>
      $$Gv2KeyDeliveriesTableTableManager(_db, _db.gv2KeyDeliveries);
  $$Gv2OutboxRowsTableTableManager get gv2OutboxRows =>
      $$Gv2OutboxRowsTableTableManager(_db, _db.gv2OutboxRows);
  $$Gv2MessageIdsTableTableManager get gv2MessageIds =>
      $$Gv2MessageIdsTableTableManager(_db, _db.gv2MessageIds);
  $$Gv2BackupStatesTableTableManager get gv2BackupStates =>
      $$Gv2BackupStatesTableTableManager(_db, _db.gv2BackupStates);
  $$BlockedAccountsTableTableManager get blockedAccounts =>
      $$BlockedAccountsTableTableManager(_db, _db.blockedAccounts);
  $$DirectOutboxJobsTableTableManager get directOutboxJobs =>
      $$DirectOutboxJobsTableTableManager(_db, _db.directOutboxJobs);
  $$ContactListTableTableManager get contactList =>
      $$ContactListTableTableManager(_db, _db.contactList);
  $$PeerNamesTableTableManager get peerNames =>
      $$PeerNamesTableTableManager(_db, _db.peerNames);
  $$ContactSyncStatesTableTableManager get contactSyncStates =>
      $$ContactSyncStatesTableTableManager(_db, _db.contactSyncStates);
}
