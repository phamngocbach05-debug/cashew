/// ============================================================================
/// HỆ THỐNG QUẢN LÝ TÀI LIỆU HỌC TẬP THEO KIẾN TRÚC CASHEW (DART IMPLEMENTATION)
/// Môn học: Phát triển Ứng dụng Di động & Kiến trúc Phần mềm
/// Mô hình: 4-Tier Local-First / Reactive Stream / Client UUIDv4 / Tombstone Sync
/// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ============================================================================
// TẦNG CỐT LÕI (CORE DOMAIN ENTITIES & ENUMS)
// ============================================================================

enum DocumentType {
  lecture,      // Bài giảng lý thuyết
  exercise,     // Bài tập / Thực hành
  reference,    // Tài liệu tham khảo / Sách
  examSyllabus, // Đề thi / Đề cương ôn tập
}

extension DocumentTypeExt on DocumentType {
  String get displayName {
    switch (this) {
      case DocumentType.lecture: return 'Bài giảng';
      case DocumentType.exercise: return 'Bài tập';
      case DocumentType.reference: return 'Tài liệu tham khảo';
      case DocumentType.examSyllabus: return 'Đề thi / Đề cương';
    }
  }
}

enum DeleteLogType {
  document,
  subject,
}

/// Tiện ích sinh UUID v4 tại Client (Nguyên tắc cốt lõi của Kiến trúc Cashew)
String generateUuidV4() {
  final random = Random.secure();
  final values = List<int>.generate(16, (i) => random.nextInt(256));
  values[6] = (values[6] & 0x0f) | 0x40; // version 4
  values[8] = (values[8] & 0x3f) | 0x80; // variant
  return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Thực thể Môn học (Tương đương Wallets / Categories trong Cashew)
class Subject {
  final String subjectPk;
  String code;
  String name;
  int credit;
  String lecturer;
  String colorHex;
  String description;
  final DateTime dateTimeCreated;
  DateTime dateTimeModified;

  Subject({
    String? subjectPk,
    required this.code,
    required this.name,
    this.credit = 3,
    this.lecturer = '',
    this.colorHex = '#1F4E79',
    this.description = '',
    DateTime? dateTimeCreated,
    DateTime? dateTimeModified,
  })  : subjectPk = subjectPk ?? generateUuidV4(),
        dateTimeCreated = dateTimeCreated ?? DateTime.now().toUtc(),
        dateTimeModified = dateTimeModified ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'subjectPk': subjectPk,
        'code': code,
        'name': name,
        'credit': credit,
        'lecturer': lecturer,
        'colorHex': colorHex,
        'description': description,
        'dateTimeCreated': dateTimeCreated.toIso8601String(),
        'dateTimeModified': dateTimeModified.toIso8601String(),
      };

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        subjectPk: json['subjectPk'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        credit: json['credit'] as int? ?? 3,
        lecturer: json['lecturer'] as String? ?? '',
        colorHex: json['colorHex'] as String? ?? '#1F4E79',
        description: json['description'] as String? ?? '',
        dateTimeCreated: DateTime.parse(json['dateTimeCreated'] as String),
        dateTimeModified: DateTime.parse(json['dateTimeModified'] as String),
      );
}

/// Thực thể Tài liệu Học tập (Tương đương Transactions trong Cashew)
class Document {
  final String documentPk;
  String title;
  String subjectFk;
  DocumentType docType;
  String author;
  String filePathOrUrl;
  double fileSizeKb;
  String fileExtension;
  String description;
  List<String> tags;
  bool isFavorite;
  int progressPercentage;
  final DateTime dateTimeCreated;
  DateTime dateTimeModified;

  Document({
    String? documentPk,
    required this.title,
    required this.subjectFk,
    this.docType = DocumentType.lecture,
    this.author = '',
    this.filePathOrUrl = '',
    this.fileSizeKb = 0.0,
    this.fileExtension = '.pdf',
    this.description = '',
    List<String>? tags,
    this.isFavorite = false,
    this.progressPercentage = 0,
    DateTime? dateTimeCreated,
    DateTime? dateTimeModified,
  })  : documentPk = documentPk ?? generateUuidV4(),
        tags = tags ?? [],
        dateTimeCreated = dateTimeCreated ?? DateTime.now().toUtc(),
        dateTimeModified = dateTimeModified ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'documentPk': documentPk,
        'title': title,
        'subjectFk': subjectFk,
        'docType': docType.name,
        'author': author,
        'filePathOrUrl': filePathOrUrl,
        'fileSizeKb': fileSizeKb,
        'fileExtension': fileExtension,
        'description': description,
        'tags': tags,
        'isFavorite': isFavorite,
        'progressPercentage': progressPercentage,
        'dateTimeCreated': dateTimeCreated.toIso8601String(),
        'dateTimeModified': dateTimeModified.toIso8601String(),
      };

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        documentPk: json['documentPk'] as String,
        title: json['title'] as String,
        subjectFk: json['subjectFk'] as String,
        docType: DocumentType.values.byName(json['docType'] as String? ?? 'lecture'),
        author: json['author'] as String? ?? '',
        filePathOrUrl: json['filePathOrUrl'] as String? ?? '',
        fileSizeKb: (json['fileSizeKb'] as num?)?.toDouble() ?? 0.0,
        fileExtension: json['fileExtension'] as String? ?? '.pdf',
        description: json['description'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        isFavorite: json['isFavorite'] as bool? ?? false,
        progressPercentage: json['progressPercentage'] as int? ?? 0,
        dateTimeCreated: DateTime.parse(json['dateTimeCreated'] as String),
        dateTimeModified: DateTime.parse(json['dateTimeModified'] as String),
      );
}

/// Bản ghi Tombstone xóa thực thể (Bảng DeleteLogs chuẩn Cashew)
class DeleteLog {
  final String deleteLogPk;
  final String entryPk;
  final DeleteLogType type;
  final String deviceId;
  final DateTime dateTimeModified;

  DeleteLog({
    String? deleteLogPk,
    required this.entryPk,
    required this.type,
    this.deviceId = 'local-device',
    DateTime? dateTimeModified,
  })  : deleteLogPk = deleteLogPk ?? generateUuidV4(),
        dateTimeModified = dateTimeModified ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'deleteLogPk': deleteLogPk,
        'entryPk': entryPk,
        'type': type.name,
        'deviceId': deviceId,
        'dateTimeModified': dateTimeModified.toIso8601String(),
      };

  factory DeleteLog.fromJson(Map<String, dynamic> json) => DeleteLog(
        deleteLogPk: json['deleteLogPk'] as String,
        entryPk: json['entryPk'] as String,
        type: DeleteLogType.values.byName(json['type'] as String? ?? 'document'),
        deviceId: json['deviceId'] as String? ?? 'local-device',
        dateTimeModified: DateTime.parse(json['dateTimeModified'] as String),
      );
}

// ============================================================================
// TẦNG 3: PERSISTENCE LAYER & REACTIVE STREAMS
// ============================================================================

/// Bộ phát tín hiệu luồng phản ứng (Mô phỏng Drift Stream.watch() trong Cashew)
class ReactiveStreamBus {
  static final ReactiveStreamBus _instance = ReactiveStreamBus._internal();
  factory ReactiveStreamBus() => _instance;
  ReactiveStreamBus._internal();

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void publish(String event, Map<String, dynamic> payload) {
    _controller.add({'event': event, ...payload});
  }
}

/// Kho Lưu trữ Cục bộ Local-First Database
class StudyMaterialDatabase {
  final Map<String, Subject> _subjects = {};
  final Map<String, Document> _documents = {};
  final List<DeleteLog> _deleteLogs = [];
  final ReactiveStreamBus bus = ReactiveStreamBus();

  // Document Operations
  List<Document> getAllDocuments() => _documents.values.toList()
    ..sort((a, b) => b.dateTimeModified.compareTo(a.dateTimeModified));

  Document? getDocumentById(String pk) => _documents[pk];

  void insertDocument(Document doc) {
    _documents[doc.documentPk] = doc;
    bus.publish('DOCUMENT_INSERTED', {'pk': doc.documentPk, 'title': doc.title});
  }

  void updateDocument(Document doc) {
    doc.dateTimeModified = DateTime.now().toUtc();
    _documents[doc.documentPk] = doc;
    bus.publish('DOCUMENT_UPDATED', {'pk': doc.documentPk, 'title': doc.title});
  }

  void deleteDocument(String pk, {String deviceId = 'local-device'}) {
    final doc = _documents.remove(pk);
    if (doc != null) {
      final tombstone = DeleteLog(
        entryPk: pk,
        type: DeleteLogType.document,
        deviceId: deviceId,
      );
      _deleteLogs.add(tombstone);
      bus.publish('DOCUMENT_DELETED', {'pk': pk, 'title': doc.title});
    }
  }

  // Subject Operations
  List<Subject> getAllSubjects() => _subjects.values.toList()
    ..sort((a, b) => a.code.compareTo(b.code));

  Subject? getSubjectById(String pk) => _subjects[pk];

  void insertSubject(Subject sub) {
    _subjects[sub.subjectPk] = sub;
    bus.publish('SUBJECT_INSERTED', {'pk': sub.subjectPk, 'code': sub.code});
  }

  void updateSubject(Subject sub) {
    sub.dateTimeModified = DateTime.now().toUtc();
    _subjects[sub.subjectPk] = sub;
    bus.publish('SUBJECT_UPDATED', {'pk': sub.subjectPk, 'code': sub.code});
  }

  void deleteSubject(String pk, {String deviceId = 'local-device'}) {
    final sub = _subjects.remove(pk);
    if (sub != null) {
      _documents.removeWhere((k, v) => v.subjectFk == pk);
      _deleteLogs.add(DeleteLog(
        entryPk: pk,
        type: DeleteLogType.subject,
        deviceId: deviceId,
      ));
      bus.publish('SUBJECT_DELETED', {'pk': pk, 'code': sub.code});
    }
  }

  List<DeleteLog> getDeleteLogs() => List.unmodifiable(_deleteLogs);
}

// ============================================================================
// TẦNG 2: DOMAIN & BUSINESS LOGIC ENGINE
// ============================================================================

class DocumentService {
  final StudyMaterialDatabase db;
  DocumentService(this.db);

  Document createDocument({
    required String title,
    required String subjectFk,
    DocumentType docType = DocumentType.lecture,
    String author = '',
    String filePathOrUrl = '',
    double fileSizeKb = 0.0,
    String fileExtension = '.pdf',
    String description = '',
    List<String>? tags,
    bool isFavorite = false,
    int progressPercentage = 0,
  }) {
    if (title.trim().length < 2) {
      throw ArgumentError('Tiêu đề tài liệu phải có ít nhất 2 ký tự.');
    }
    if (db.getSubjectById(subjectFk) == null) {
      throw ArgumentError('Môn học không tồn tại trong hệ thống.');
    }
    if (progressPercentage < 0 || progressPercentage > 100) {
      throw ArgumentError('Tiến độ học tập phải từ 0% đến 100%.');
    }

    final doc = Document(
      title: title.trim(),
      subjectFk: subjectFk,
      docType: docType,
      author: author.trim(),
      filePathOrUrl: filePathOrUrl.trim(),
      fileSizeKb: fileSizeKb,
      fileExtension: fileExtension,
      description: description.trim(),
      tags: tags,
      isFavorite: isFavorite,
      progressPercentage: progressPercentage,
    );
    db.insertDocument(doc);
    return doc;
  }

  Document updateDocument(String pk, {
    String? title,
    String? author,
    String? description,
    int? progressPercentage,
    bool? isFavorite,
  }) {
    final doc = db.getDocumentById(pk);
    if (doc == null) throw ArgumentError('Tài liệu không tồn tại.');

    if (title != null && title.trim().isNotEmpty) doc.title = title.trim();
    if (author != null) doc.author = author.trim();
    if (description != null) doc.description = description.trim();
    if (progressPercentage != null) doc.progressPercentage = progressPercentage.clamp(0, 100);
    if (isFavorite != null) doc.isFavorite = isFavorite;

    db.updateDocument(doc);
    return doc;
  }

  void deleteDocument(String pk) => db.deleteDocument(pk);

  List<Document> listAll() => db.getAllDocuments();
}

class SearchEngine {
  final StudyMaterialDatabase db;
  SearchEngine(this.db);

  List<Document> search({
    String query = '',
    String? subjectFk,
    DocumentType? docType,
    bool onlyFavorites = false,
  }) {
    final q = query.trim().toLowerCase();
    return db.getAllDocuments().where((d) {
      if (onlyFavorites && !d.isFavorite) return false;
      if (subjectFk != null && d.subjectFk != subjectFk) return false;
      if (docType != null && d.docType != docType) return false;
      if (q.isNotEmpty) {
        final matchTitle = d.title.toLowerCase().contains(q);
        final matchAuthor = d.author.toLowerCase().contains(q);
        final matchDesc = d.description.toLowerCase().contains(q);
        final matchTags = d.tags.any((t) => t.toLowerCase().contains(q));
        if (!matchTitle && !matchAuthor && !matchDesc && !matchTags) return false;
      }
      return true;
    }).toList();
  }
}

class StatisticsService {
  final StudyMaterialDatabase db;
  StatisticsService(this.db);

  Map<String, dynamic> getSummary() {
    final docs = db.getAllDocuments();
    final subs = db.getAllSubjects();
    final totalSizeKb = docs.fold<double>(0.0, (sum, d) => sum + d.fileSizeKb);
    final favCount = docs.where((d) => d.isFavorite).length;
    final avgProgress = docs.isEmpty ? 0.0 : docs.fold<int>(0, (s, d) => s + d.progressPercentage) / docs.length;

    final typeCount = <String, int>{};
    for (final t in DocumentType.values) {
      typeCount[t.name] = docs.where((d) => d.docType == t).length;
    }

    return {
      'totalDocs': docs.length,
      'totalSubjects': subs.length,
      'totalSizeMb': (totalSizeKb / 1024.0).toStringAsFixed(2),
      'favorites': favCount,
      'avgProgress': avgProgress.toStringAsFixed(1),
      'typeBreakdown': typeCount,
    };
  }
}

// ============================================================================
// TẦNG 4: EXTERNAL & SYNC ENGINE (LAST-WRITE-WINS & TOMBSTONES)
// ============================================================================

class SyncEngine {
  final StudyMaterialDatabase db;
  final String clientId;
  SyncEngine(this.db, {this.clientId = 'dart-node-mobile'});

  Map<String, dynamic> generateSyncPayload({DateTime? since}) {
    final threshold = since ?? DateTime.fromMillisecondsSinceEpoch(0);
    final subs = db.getAllSubjects().where((s) => s.dateTimeModified.isAfter(threshold)).map((s) => s.toJson()).toList();
    final docs = db.getAllDocuments().where((d) => d.dateTimeModified.isAfter(threshold)).map((d) => d.toJson()).toList();
    final tombstones = db.getDeleteLogs().where((l) => l.dateTimeModified.isAfter(threshold)).map((l) => l.toJson()).toList();

    return {
      'clientId': clientId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'subjects': subs,
      'documents': docs,
      'deleteLogs': tombstones,
    };
  }

  void mergeIncomingSync(Map<String, dynamic> payload) {
    // 1. Process delete tombstones
    for (final logJson in (payload['deleteLogs'] as List<dynamic>? ?? [])) {
      final log = DeleteLog.fromJson(logJson as Map<String, dynamic>);
      if (log.type == DeleteLogType.document) {
        db.deleteDocument(log.entryPk, deviceId: log.deviceId);
      } else {
        db.deleteSubject(log.entryPk, deviceId: log.deviceId);
      }
    }

    // 2. Process documents with LWW
    for (final docJson in (payload['documents'] as List<dynamic>? ?? [])) {
      final remoteDoc = Document.fromJson(docJson as Map<String, dynamic>);
      final localDoc = db.getDocumentById(remoteDoc.documentPk);
      if (localDoc == null || remoteDoc.dateTimeModified.isAfter(localDoc.dateTimeModified)) {
        db.insertDocument(remoteDoc);
      }
    }
  }
}

// ============================================================================
// TẦNG 1: PRESENTATION LAYER & INTERACTIVE RUNNER
// ============================================================================

void main() async {
  print('==================================================================');
  print('  HỆ THỐNG QUẢN LÝ TÀI LIỆU HỌC TẬP - KIẾN TRÚC CASHEW (DART)');
  print('  4-Tier Local-First / Reactive Stream / Client UUID / Tombstone');
  print('==================================================================');

  final db = StudyMaterialDatabase();
  final docService = DocumentService(db);
  final searchEngine = SearchEngine(db);
  final statsService = StatisticsService(db);
  final syncEngine = SyncEngine(db);

  // Đăng ký lắng nghe sự kiện phản ứng thời gian thực (Reactive Stream)
  db.bus.stream.listen((event) {
    print('⚡ [Reactive Stream] Sự kiện phát ra: ${event['event']} -> ${event['title'] ?? event['code'] ?? event['pk']}');
  });

  // Khởi tạo môn học mẫu
  final sub1 = Subject(code: 'CS301', name: 'Kiến trúc Phần mềm', credit: 3, lecturer: 'TS. Hoang Minh Tri');
  final sub2 = Subject(code: 'IT402', name: 'Phát triển Ứng dụng Di động', credit: 4, lecturer: 'ThS. Le Quang Huy');
  db.insertSubject(sub1);
  db.insertSubject(sub2);

  // Khởi tạo tài liệu học tập mẫu
  docService.createDocument(
    title: 'Slide Bài 1: Tổng quan Kiến trúc Cashew 4 Tầng',
    subjectFk: sub1.subjectPk,
    docType: DocumentType.lecture,
    author: 'TS. Hoang Minh Tri',
    fileSizeKb: 2450.0,
    tags: ['cashew', 'architecture', 'offline-first'],
    isFavorite: true,
    progressPercentage: 100,
  );

  docService.createDocument(
    title: 'Bài tập Thực hành TH1: Quản lý Tài liệu Học tập',
    subjectFk: sub1.subjectPk,
    docType: DocumentType.exercise,
    author: 'Bo mon CNPM',
    fileSizeKb: 850.0,
    tags: ['th1', 'assignment'],
    isFavorite: true,
    progressPercentage: 90,
  );

  docService.createDocument(
    title: 'Slide Bài 4: Quản lý SQLite & Reactive Stream trong Flutter',
    subjectFk: sub2.subjectPk,
    docType: DocumentType.lecture,
    author: 'ThS. Le Quang Huy',
    fileSizeKb: 4200.0,
    tags: ['flutter', 'sqlite', 'reactive'],
    isFavorite: false,
    progressPercentage: 70,
  );

  print('\n📊 --- DASHBOARD THỐNG KÊ (CASHEW ANALYTICS) ---');
  final stats = statsService.getSummary();
  print('Tổng số tài liệu: ${stats['totalDocs']}');
  print('Tổng số môn học:  ${stats['totalSubjects']}');
  print('Tổng dung lượng:  ${stats['totalSizeMb']} MB');
  print('Yêu thích:        ${stats['favorites']} ⭐');
  print('Tiến độ trung bình: ${stats['avgProgress']}%');

  print('\n🔍 --- THỰC HIỆN TÌM KIẾM THEO TỪ KHÓA: "cashew" ---');
  final searchResults = searchEngine.search(query: 'cashew');
  for (final d in searchResults) {
    print('• [${d.docType.displayName}] ${d.title} (${d.fileSizeKb} KB) - Tiến độ: ${d.progressPercentage}%');
  }

  print('\n🗑️ --- THỬ NGHIỆM XÓA & TẠO TOMBSTONE SYNC ---');
  if (searchResults.isNotEmpty) {
    final toDelete = searchResults.first;
    docService.deleteDocument(toDelete.documentPk);
    print('Đã xóa "${toDelete.title}". Kiểm tra Tombstones: ${db.getDeleteLogs().length} bản ghi');
  }

  print('\n📦 --- TRÍCH XUẤT DELTA SYNC PAYLOAD (CHO GOOGLE DRIVE) ---');
  final payload = syncEngine.generateSyncPayload();
  print('Client ID: ${payload['clientId']}');
  print('Số documents trong delta: ${(payload['documents'] as List).length}');
  print('Số deleteLogs trong delta: ${(payload['deleteLogs'] as List).length}');
  print('\n✅ Mã nguồn Dart đã sẵn sàng và vận hành hoàn hảo!');
  exit(0);
}
