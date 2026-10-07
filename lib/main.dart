import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const CashewStudyApp());
}

class CashewStudyApp extends StatelessWidget {
  const CashewStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quản lý Tài liệu Học tập - Kiến trúc Cashew',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F4E79),
          primary: const Color(0xFF1F4E79),
          secondary: const Color(0xFF008080),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

// ============================================================================
// CORE MODELS & ENUMS
// ============================================================================

enum DocumentType { lecture, exercise, reference, exam }

extension DocumentTypeExt on DocumentType {
  String get displayName {
    switch (this) {
      case DocumentType.lecture:
        return 'Bài giảng';
      case DocumentType.exercise:
        return 'Bài tập';
      case DocumentType.reference:
        return 'Tham khảo';
      case DocumentType.exam:
        return 'Đề thi';
    }
  }

  Color get color {
    switch (this) {
      case DocumentType.lecture:
        return Colors.blue.shade700;
      case DocumentType.exercise:
        return Colors.orange.shade800;
      case DocumentType.reference:
        return Colors.teal.shade700;
      case DocumentType.exam:
        return Colors.purple.shade700;
    }
  }
}

String generateUuidV4() {
  final random = Random.secure();
  final values = List<int>.generate(16, (i) => random.nextInt(256));
  values[6] = (values[6] & 0x0f) | 0x40; // version 4
  values[8] = (values[8] & 0x3f) | 0x80; // variant
  return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class Subject {
  final String id;
  final String code;
  final String name;

  Subject({String? id, required this.code, required this.name})
      : id = id ?? generateUuidV4();
}

class StudyDocument {
  final String id;
  String title;
  String subjectId;
  DocumentType type;
  String author;
  double sizeKb;
  int progress;
  bool isFavorite;
  final DateTime createdAt;

  StudyDocument({
    String? id,
    required this.title,
    required this.subjectId,
    required this.type,
    this.author = '',
    this.sizeKb = 1024,
    this.progress = 0,
    this.isFavorite = false,
    DateTime? createdAt,
  })  : id = id ?? generateUuidV4(),
        createdAt = createdAt ?? DateTime.now();
}

class TombstoneLog {
  final String id;
  final String documentId;
  final String title;
  final DateTime deletedAt;

  TombstoneLog({
    String? id,
    required this.documentId,
    required this.title,
    DateTime? deletedAt,
  })  : id = id ?? generateUuidV4(),
        deletedAt = deletedAt ?? DateTime.now();
}

// ============================================================================
// MAIN DASHBOARD SCREEN
// ============================================================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<Subject> _subjects = [
    Subject(code: 'CS301', name: 'Kiến trúc Phần mềm'),
    Subject(code: 'IT402', name: 'Phát triển Ứng dụng Di động'),
    Subject(code: 'CS205', name: 'Cơ sở Dữ liệu Nâng cao'),
  ];

  late final List<StudyDocument> _documents;
  final List<TombstoneLog> _tombstones = [];
  String _searchKeyword = '';
  String? _selectedSubjectFilter;

  @override
  void initState() {
    super.initState();
    // Seed initial data
    _documents = [
      StudyDocument(
        title: 'Slide Bài 1: Tổng quan Kiến trúc Cashew 4 Tầng',
        subjectId: _subjects[0].id,
        type: DocumentType.lecture,
        author: 'TS. Hoang Minh Tri',
        sizeKb: 2450.0,
        progress: 100,
        isFavorite: true,
      ),
      StudyDocument(
        title: 'Bài tập Thực hành TH1: Quản lý Tài liệu Học tập',
        subjectId: _subjects[0].id,
        type: DocumentType.exercise,
        author: 'Bộ môn CNPM',
        sizeKb: 850.0,
        progress: 85,
        isFavorite: true,
      ),
      StudyDocument(
        title: 'Slide Bài 4: SQLite WAL & Reactive Stream',
        subjectId: _subjects[1].id,
        type: DocumentType.lecture,
        author: 'ThS. Le Quang Huy',
        sizeKb: 4200.0,
        progress: 60,
        isFavorite: false,
      ),
      StudyDocument(
        title: 'Sách: Designing Data-Intensive Applications',
        subjectId: _subjects[2].id,
        type: DocumentType.reference,
        author: 'Martin Kleppmann',
        sizeKb: 18200.0,
        progress: 40,
        isFavorite: true,
      ),
    ];
  }

  List<StudyDocument> get _filteredDocuments {
    return _documents.where((doc) {
      final matchesKw = _searchKeyword.isEmpty ||
          doc.title.toLowerCase().contains(_searchKeyword.toLowerCase()) ||
          doc.author.toLowerCase().contains(_searchKeyword.toLowerCase());
      final matchesSub = _selectedSubjectFilter == null ||
          doc.subjectId == _selectedSubjectFilter;
      return matchesKw && matchesSub;
    }).toList();
  }

  void _addOrEditDocument({StudyDocument? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final authorCtrl = TextEditingController(text: existing?.author ?? '');
    final progCtrl =
        TextEditingController(text: (existing?.progress ?? 0).toString());
    String selectedSub = existing?.subjectId ?? _subjects.first.id;
    DocumentType selectedType = existing?.type ?? DocumentType.lecture;
    bool isFav = existing?.isFavorite ?? false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(existing == null
                  ? '➕ Thêm Tài Liệu Mới'
                  : '✏️ Cập Nhật Tài Liệu'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 450,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tiêu đề tài liệu *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedSub,
                        decoration: const InputDecoration(
                          labelText: 'Môn học',
                          border: OutlineInputBorder(),
                        ),
                        items: _subjects
                            .map((s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text('${s.code} - ${s.name}'),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() => selectedSub = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<DocumentType>(
                        value: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Phân loại',
                          border: OutlineInputBorder(),
                        ),
                        items: DocumentType.values
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.displayName),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() => selectedType = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: authorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tác giả / Giảng viên',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: progCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Tiến độ học tập (%) (0-100)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('Đánh dấu Yêu thích ⭐'),
                        value: isFav,
                        onChanged: (v) =>
                            setDlgState(() => isFav = v ?? false),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F4E79),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    if (title.length < 2) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Tiêu đề tài liệu phải có ít nhất 2 ký tự!')),
                      );
                      return;
                    }
                    final prog = int.tryParse(progCtrl.text) ?? 0;

                    setState(() {
                      if (existing == null) {
                        _documents.add(StudyDocument(
                          title: title,
                          subjectId: selectedSub,
                          type: selectedType,
                          author: authorCtrl.text.trim(),
                          progress: prog.clamp(0, 100),
                          isFavorite: isFav,
                        ));
                      } else {
                        existing.title = title;
                        existing.subjectId = selectedSub;
                        existing.type = selectedType;
                        existing.author = authorCtrl.text.trim();
                        existing.progress = prog.clamp(0, 100);
                        existing.isFavorite = isFav;
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteDocument(StudyDocument doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa tài liệu'),
        content: Text(
            'Bạn có chắc muốn xóa "${doc.title}"?\n\nTheo chuẩn Cashew, thao tác này sẽ xóa bản ghi cục bộ và tạo một bản ghi Tombstone để phục vụ đồng bộ đám mây.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _documents.remove(doc);
                _tombstones.add(TombstoneLog(
                  documentId: doc.id,
                  title: doc.title,
                ));
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Đã xóa "${doc.title}" và tạo bản ghi Tombstone.')),
              );
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showTombstones() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🪦 Bản Ghi Tombstones (Delete Logs)'),
        content: SizedBox(
          width: 500,
          child: _tombstones.isEmpty
              ? const Text('Chưa có tài liệu nào bị xóa.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _tombstones.length,
                  itemBuilder: (context, i) {
                    final t = _tombstones[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.delete_outline, color: Colors.red),
                      title: Text(t.title),
                      subtitle: Text(
                          'UUID: ${t.documentId}\nThời gian: ${t.deletedAt.toLocal()}'),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSizeMb = (_documents.fold<double>(
                0.0, (sum, d) => sum + d.sizeKb) /
            1024)
        .toStringAsFixed(2);
    final favCount = _documents.where((d) => d.isFavorite).length;
    final avgProg = _documents.isEmpty
        ? 0
        : (_documents.fold<int>(0, (sum, d) => sum + d.progress) /
                _documents.length)
            .round();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
        elevation: 2,
        title: const Row(
          children: [
            Icon(Icons.folder_special, size: 28),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quản lý Tài liệu Học tập',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Kiến trúc Cashew 4 Tầng • Local-First & Tombstones',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_toggle_off),
            tooltip: 'Xem Tombstones Log',
            onPressed: _showTombstones,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle),
            tooltip: 'Thêm tài liệu mới',
            onPressed: () => _addOrEditDocument(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Analytics Dashboard Cards
            Row(
              children: [
                _buildStatCard('Tổng tài liệu', '${_documents.length}',
                    Icons.library_books, Colors.blue),
                const SizedBox(width: 12),
                _buildStatCard('Môn học', '${_subjects.length}',
                    Icons.school, Colors.green),
                const SizedBox(width: 12),
                _buildStatCard('Dung lượng', '$totalSizeMb MB',
                    Icons.pie_chart, Colors.purple),
                const SizedBox(width: 12),
                _buildStatCard('Yêu thích', '$favCount ⭐',
                    Icons.star, Colors.amber),
                const SizedBox(width: 12),
                _buildStatCard('Tiến độ TB', '$avgProg%',
                    Icons.trending_up, Colors.teal),
              ],
            ),
            const SizedBox(height: 24),

            // Search & Filter Box
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Tìm kiếm tài liệu, tác giả...',
                          prefixIcon: Icon(Icons.search),
                          border: InputBorder.none,
                        ),
                        onChanged: (val) =>
                            setState(() => _searchKeyword = val),
                      ),
                    ),
                    const VerticalDivider(width: 32),
                    Expanded(
                      flex: 2,
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        underline: const SizedBox(),
                        value: _selectedSubjectFilter,
                        hint: const Text('Lọc theo môn học'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Tất cả môn học')),
                          ..._subjects.map((s) => DropdownMenuItem(
                                value: s.id,
                                child: Text('${s.code} - ${s.name}'),
                              )),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedSubjectFilter = val),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Document List Table Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Danh Sách Tài Liệu (${_filteredDocuments.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm tài liệu'),
                  onPressed: () => _addOrEditDocument(),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Documents Cards
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredDocuments.length,
              itemBuilder: (ctx, i) {
                final doc = _filteredDocuments[i];
                final sub = _subjects.firstWhere((s) => s.id == doc.subjectId,
                    orElse: () => Subject(code: 'N/A', name: 'Chưa gán'));
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: doc.type.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                doc.type.displayName,
                                style: TextStyle(
                                  color: doc.type.color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${sub.code} • ${sub.name}',
                                style: const TextStyle(
                                  color: Colors.blueGrey,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                doc.isFavorite
                                    ? Icons.star
                                    : Icons.star_border,
                                color: doc.isFavorite
                                    ? Colors.amber
                                    : Colors.grey,
                              ),
                              onPressed: () =>
                                  setState(() => doc.isFavorite = !doc.isFavorite),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Colors.blue, size: 20),
                              onPressed: () =>
                                  _addOrEditDocument(existing: doc),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red, size: 20),
                              onPressed: () => _deleteDocument(doc),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          doc.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tác giả: ${doc.author.isEmpty ? "Chưa rõ" : doc.author}  |  Dung lượng: ${doc.sizeKb} KB  |  UUID: ${doc.id}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: doc.progress / 100,
                                  backgroundColor: Colors.grey.shade200,
                                  color: doc.progress == 100
                                      ? Colors.green
                                      : const Color(0xFF1F4E79),
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${doc.progress}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: doc.progress == 100
                                    ? Colors.green
                                    : const Color(0xFF1F4E79),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Thêm Tài Liệu'),
        onPressed: () => _addOrEditDocument(),
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 1.5,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.blueGrey)),
                  Icon(icon, size: 20, color: color),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
