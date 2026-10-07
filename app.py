"""
=============================================================================
ỨNG DỤNG QUẢN LÝ TÀI LIỆU HỌC TẬP - KIẾN TRÚC CASHEW (PHIÊN BẢN GỌN NHẸ)
Tối ưu hóa: 1 tệp duy nhất, phân chia rõ ràng 4 tầng, không cần cài đặt thư viện.
=============================================================================
"""
import sqlite3
import json
import uuid
import sys
import os
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse

# Cấu hình UTF-8 cho Windows
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

# =============================================================================
# 1. TẦNG CỐT LÕI (CORE ENTITIES & ENUMS)
# =============================================================================

def current_time_iso() -> str:
    """Trả về mốc thời gian chuẩn ISO 8601 (UTC)."""
    return datetime.now(timezone.utc).isoformat()

def generate_uuid() -> str:
    """Sinh khóa chính UUID v4 tại Client (Nguyên tắc cốt lõi kiến trúc Cashew)."""
    return str(uuid.uuid4())

class DocumentType:
    LECTURE = "LECTURE"         # Bài giảng lý thuyết
    EXERCISE = "EXERCISE"       # Bài tập / Thực hành
    REFERENCE = "REFERENCE"     # Tài liệu tham khảo / Sách
    EXAM = "EXAM"               # Đề thi / Đề cương

    @staticmethod
    def display(doc_type: str) -> str:
        names = {
            "LECTURE": "Bài giảng",
            "EXERCISE": "Bài tập",
            "REFERENCE": "Tài liệu tham khảo",
            "EXAM": "Đề thi / Đề cương"
        }
        return names.get(doc_type, doc_type)


# =============================================================================
# 2. TẦNG LƯU TRỮ CỤC BỘ (PERSISTENCE LAYER - SQLITE LOCAL-FIRST & TOMBSTONE)
# =============================================================================

class Database:
    """Quản lý CSDL SQLite cục bộ theo chuẩn Cashew (WAL mode, UUID, Tombstone)."""
    def __init__(self, db_file="database.sqlite"):
        self.db_file = db_file
        self.conn = sqlite3.connect(self.db_file, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        # Kích hoạt WAL mode để đọc/ghi tốc độ cao (<16ms)
        self.conn.execute("PRAGMA journal_mode = WAL;")
        self.conn.execute("PRAGMA foreign_keys = ON;")
        self._init_tables()

    def _init_tables(self):
        cur = self.conn.cursor()
        # Bảng Môn học
        cur.execute("""
        CREATE TABLE IF NOT EXISTS subjects (
            subject_pk TEXT PRIMARY KEY,
            code TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            credit INTEGER DEFAULT 3,
            lecturer TEXT DEFAULT '',
            date_time_modified TEXT NOT NULL
        );
        """)

        # Bảng Tài liệu học tập (Transactions trong Cashew)
        cur.execute("""
        CREATE TABLE IF NOT EXISTS documents (
            document_pk TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            subject_fk TEXT NOT NULL,
            doc_type TEXT NOT NULL,
            author TEXT DEFAULT '',
            file_size_kb REAL DEFAULT 0.0,
            tags TEXT DEFAULT '[]',
            progress INTEGER DEFAULT 0,
            is_favorite INTEGER DEFAULT 0,
            date_time_modified TEXT NOT NULL,
            FOREIGN KEY (subject_fk) REFERENCES subjects (subject_pk) ON DELETE CASCADE
        );
        """)

        # Bảng Tombstone ghi nhận lịch sử xóa (DeleteLogs trong Cashew để đồng bộ)
        cur.execute("""
        CREATE TABLE IF NOT EXISTS delete_logs (
            delete_log_pk TEXT PRIMARY KEY,
            entry_pk TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            date_time_modified TEXT NOT NULL
        );
        """)
        self.conn.commit()

    # --- Thao tác Môn học ---
    def insert_subject(self, code, name, credit=3, lecturer=""):
        pk = generate_uuid()
        now = current_time_iso()
        self.conn.execute(
            "INSERT INTO subjects VALUES (?, ?, ?, ?, ?, ?)",
            (pk, code.strip().upper(), name.strip(), credit, lecturer.strip(), now)
        )
        self.conn.commit()
        return pk

    def get_subjects(self):
        cur = self.conn.cursor()
        cur.execute("SELECT * FROM subjects ORDER BY code ASC")
        return [dict(r) for r in cur.fetchall()]

    # --- Thao tác Tài liệu (CRUD) ---
    def insert_document(self, title, subject_fk, doc_type, author="", file_size_kb=0.0, tags=None, progress=0, is_fav=0):
        pk = generate_uuid()
        now = current_time_iso()
        tags_json = json.dumps(tags or [], ensure_ascii=False)
        self.conn.execute(
            "INSERT INTO documents VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (pk, title.strip(), subject_fk, doc_type, author.strip(), file_size_kb, tags_json, progress, is_fav, now)
        )
        self.conn.commit()
        return pk

    def update_document(self, pk, title=None, author=None, progress=None, is_fav=None):
        doc = self.get_document(pk)
        if not doc:
            return False
        new_title = title if title is not None else doc["title"]
        new_author = author if author is not None else doc["author"]
        new_prog = progress if progress is not None else doc["progress"]
        new_fav = is_fav if is_fav is not None else doc["is_favorite"]
        now = current_time_iso()

        self.conn.execute("""
            UPDATE documents SET title = ?, author = ?, progress = ?, is_favorite = ?, date_time_modified = ?
            WHERE document_pk = ?
        """, (new_title.strip(), new_author.strip(), new_prog, new_fav, now, pk))
        self.conn.commit()
        return True

    def delete_document(self, pk):
        """Xóa tài liệu và lưu bản ghi Tombstone vào delete_logs (Chuẩn Cashew)."""
        doc = self.get_document(pk)
        if not doc:
            return False
        # Xóa khỏi bảng chính
        self.conn.execute("DELETE FROM documents WHERE document_pk = ?", (pk,))
        # Ghi vết xóa Tombstone
        self.conn.execute(
            "INSERT INTO delete_logs VALUES (?, ?, ?, ?)",
            (generate_uuid(), pk, "DOCUMENT", current_time_iso())
        )
        self.conn.commit()
        return True

    def get_document(self, pk):
        cur = self.conn.cursor()
        cur.execute("SELECT * FROM documents WHERE document_pk = ?", (pk,))
        row = cur.fetchone()
        return dict(row) if row else None

    def get_documents(self):
        cur = self.conn.cursor()
        cur.execute("SELECT * FROM documents ORDER BY date_time_modified DESC")
        res = []
        for r in cur.fetchall():
            d = dict(r)
            try:
                d["tags"] = json.loads(d["tags"])
            except Exception:
                d["tags"] = []
            res.append(d)
        return res

    def get_delete_logs(self):
        cur = self.conn.cursor()
        cur.execute("SELECT * FROM delete_logs ORDER BY date_time_modified DESC")
        return [dict(r) for r in cur.fetchall()]


# =============================================================================
# 3. TẦNG NGHIỆP VỤ & TÌM KIẾM (DOMAIN BUSINESS LOGIC ENGINE)
# =============================================================================

class DocumentService:
    """Xử lý toàn bộ logic nghiệp vụ, ràng buộc dữ liệu và tìm kiếm."""
    def __init__(self, db: Database):
        self.db = db

    def add_document(self, title, subject_fk, doc_type, author="", file_size_kb=0.0, tags=None, progress=0, is_fav=0):
        # Ràng buộc nghiệp vụ (Validation)
        if not title or len(title.strip()) < 2:
            raise ValueError("Tiêu đề tài liệu phải có ít nhất 2 ký tự.")
        if progress < 0 or progress > 100:
            raise ValueError("Tiến độ học tập phải từ 0% đến 100%.")

        return self.db.insert_document(title, subject_fk, doc_type, author, file_size_kb, tags, progress, is_fav)

    def edit_document(self, pk, title=None, author=None, progress=None, is_fav=None):
        return self.db.update_document(pk, title, author, progress, is_fav)

    def remove_document(self, pk):
        return self.db.delete_document(pk)

    def search_documents(self, keyword="", subject_fk=None, doc_type=None, only_fav=False):
        """Tìm kiếm đa tiêu chí theo từ khóa, môn học, phân loại và yêu thích."""
        docs = self.db.get_documents()
        kw = keyword.strip().lower()

        results = []
        for d in docs:
            if only_fav and not d["is_favorite"]:
                continue
            if subject_fk and d["subject_fk"] != subject_fk:
                continue
            if doc_type and d["doc_type"] != doc_type:
                continue
            if kw:
                match_title = kw in d["title"].lower()
                match_author = kw in d["author"].lower()
                match_tags = any(kw in t.lower() for t in d.get("tags", []))
                if not (match_title or match_author or match_tags):
                    continue
            results.append(d)
        return results

    def get_statistics(self):
        """Tổng hợp số liệu cho Dashboard."""
        docs = self.db.get_documents()
        subjects = self.db.get_subjects()
        total_size_mb = round(sum(d["file_size_kb"] for d in docs) / 1024.0, 2)
        favs = sum(1 for d in docs if d["is_favorite"])
        avg_prog = round(sum(d["progress"] for d in docs) / len(docs), 1) if docs else 0.0

        by_type = {"LECTURE": 0, "EXERCISE": 0, "REFERENCE": 0, "EXAM": 0}
        for d in docs:
            t = d["doc_type"]
            by_type[t] = by_type.get(t, 0) + 1

        return {
            "total_documents": len(docs),
            "total_subjects": len(subjects),
            "total_size_mb": total_size_mb,
            "favorites": favs,
            "avg_progress": avg_prog,
            "type_breakdown": by_type
        }


# =============================================================================
# 4. TẦNG DỊCH VỤ NGOẠI VI (EXTERNAL SERVICES - SAO LƯU TỰ ĐỘNG)
# =============================================================================

class BackupManager:
    """Tự động sao lưu xoay vòng CSDL (Tương đương accountAndBackup.dart trong Cashew)."""
    def __init__(self, db: Database, backup_dir="backups"):
        self.db = db
        self.backup_dir = backup_dir
        os.makedirs(self.backup_dir, exist_ok=True)

    def backup_to_json(self):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"backup_{timestamp}.json"
        filepath = os.path.join(self.backup_dir, filename)

        data = {
            "backup_time": current_time_iso(),
            "subjects": self.db.get_subjects(),
            "documents": self.db.get_documents(),
            "delete_logs": self.db.get_delete_logs()
        }
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        return filepath


# =============================================================================
# 5. TẦNG GIAO DIỆN (PRESENTATION - CLI & WEB MINI)
# =============================================================================

def seed_initial_data(db: Database):
    """Khởi tạo dữ liệu mẫu nếu CSDL rỗng."""
    if db.get_subjects():
        return
    s1 = db.insert_subject("CS301", "Kiến trúc Phần mềm", 3, "TS. Hoang Minh Tri")
    s2 = db.insert_subject("IT402", "Phát triển Ứng dụng Di động", 4, "ThS. Le Quang Huy")
    s3 = db.insert_subject("CS205", "Cơ sở Dữ liệu Nâng cao", 3, "PGS.TS. Tran Thi Mai")

    db.insert_document("Slide Bài 1: Tổng quan Kiến trúc Cashew 4 Tầng", s1, DocumentType.LECTURE, "TS. Hoang Minh Tri", 2450.0, ["architecture", "cashew"], 100, 1)
    db.insert_document("Bài tập Thực hành TH1: Quản lý Tài liệu Học tập", s1, DocumentType.EXERCISE, "Bo mon CNPM", 850.0, ["assignment", "th1"], 85, 1)
    db.insert_document("Slide Bài 4: SQLite WAL & Reactive Stream", s2, DocumentType.LECTURE, "ThS. Le Quang Huy", 4200.0, ["sqlite", "flutter"], 60, 0)
    db.insert_document("Sách: Designing Data-Intensive Applications", s3, DocumentType.REFERENCE, "Martin Kleppmann", 18200.0, ["database", "reference"], 40, 1)

def run_cli(service: DocumentService, backup_mgr: BackupManager):
    """Giao diện dòng lệnh thân thiện, dễ sử dụng."""
    print("\n" + "="*75)
    print("  📚 HỆ THỐNG QUẢN LÝ TÀI LIỆU HỌC TẬP - KIẾN TRÚC CASHEW (PHIÊN BẢN GỌN NHẸ)")
    print("  Nguyên lý: Local-First SQLite WAL | Client UUIDv4 | Tombstone DeleteLogs")
    print("="*75)

    while True:
        print("""
--- MENU ĐIỀU KHIỂN ---
1. Xem danh sách tài liệu học tập
2. Thêm mới tài liệu (Bài giảng, Bài tập, Tham khảo, Đề thi)
3. Cập nhật thông tin tài liệu
4. Xóa tài liệu (Ghi nhận Tombstone theo chuẩn Cashew)
5. Tìm kiếm & Lọc tài liệu (Theo từ khóa, môn học, phân loại)
6. Xem thống kê Dashboard học tập
7. Sao lưu CSDL ra tệp JSON
0. Thoát chương trình
""")
        choice = input("👉 Chọn chức năng (0-7): ").strip()

        if choice == "1":
            docs = service.db.get_documents()
            subs = {s["subject_pk"]: s for s in service.db.get_subjects()}
            print("\n" + "-"*85)
            print(f"{'STT':<4} {'TIÊU ĐỀ TÀI LIỆU':<35} {'MÔN HỌC':<15} {'PHÂN LOẠI':<15} {'TIẾN ĐỘ':<10}")
            print("-"*85)
            for idx, d in enumerate(docs, start=1):
                sub = subs.get(d["subject_fk"], {})
                sub_code = sub.get("code", "N/A")
                star = "⭐ " if d["is_favorite"] else ""
                type_name = DocumentType.display(d["doc_type"])
                print(f"{idx:<4} {star}{d['title'][:32]:<33} {sub_code:<15} {type_name:<15} {d['progress']}%")
            print("-"*85)

        elif choice == "2":
            print("\n[+] THÊM MỚI TÀI LIỆU")
            subs = service.db.get_subjects()
            print("Danh sách môn học hiện có:")
            for s in subs:
                print(f"  • Mã: {s['code']} - {s['name']} (ID: {s['subject_pk']})")
            code_input = input("Nhập Mã môn học (VD: CS301): ").strip().upper()
            target_sub = next((s for s in subs if s["code"] == code_input), None)
            if not target_sub:
                print("❌ Không tìm thấy mã môn học.")
                continue

            title = input("Tiêu đề tài liệu: ").strip()
            print("Loại: 1. Bài giảng | 2. Bài tập | 3. Tham khảo | 4. Đề thi")
            t_c = input("Chọn loại (1-4, mặc định 1): ").strip()
            t_map = {"1": DocumentType.LECTURE, "2": DocumentType.EXERCISE, "3": DocumentType.REFERENCE, "4": DocumentType.EXAM}
            doc_type = t_map.get(t_c, DocumentType.LECTURE)
            author = input("Tác giả / Giảng viên: ").strip()
            prog_s = input("Tiến độ học (0-100%, mặc định 0): ").strip()
            prog = int(prog_s) if prog_s.isdigit() else 0
            is_fav = 1 if input("Yêu thích? (y/N): ").strip().lower() == "y" else 0

            try:
                pk = service.add_document(title, target_sub["subject_pk"], doc_type, author=author, progress=prog, is_fav=is_fav)
                print(f"✅ Đã thêm tài liệu thành công! (Mã UUID: {pk})")
            except Exception as e:
                print(f"❌ Lỗi: {e}")

        elif choice == "3":
            docs = service.db.get_documents()
            for idx, d in enumerate(docs, start=1):
                print(f"{idx}. {d['title']}")
            i_s = input("Nhập STT tài liệu muốn sửa: ").strip()
            if i_s.isdigit() and 1 <= int(i_s) <= len(docs):
                t_doc = docs[int(i_s) - 1]
                new_t = input(f"Tiêu đề mới [{t_doc['title']}]: ").strip()
                new_p = input(f"Tiến độ mới (0-100) [{t_doc['progress']}%]: ").strip()
                p_val = int(new_p) if new_p.isdigit() else None
                service.edit_document(t_doc["document_pk"], title=new_t or None, progress=p_val)
                print("✅ Cập nhật thành công!")

        elif choice == "4":
            docs = service.db.get_documents()
            for idx, d in enumerate(docs, start=1):
                print(f"{idx}. {d['title']}")
            i_s = input("Nhập STT tài liệu muốn XÓA: ").strip()
            if i_s.isdigit() and 1 <= int(i_s) <= len(docs):
                t_doc = docs[int(i_s) - 1]
                if input(f"Xác nhận xóa '{t_doc['title']}'? (y/N): ").strip().lower() == "y":
                    service.remove_document(t_doc["document_pk"])
                    print("✅ Đã xóa tài liệu và tạo bản ghi Tombstone trong 'delete_logs'.")

        elif choice == "5":
            kw = input("Nhập từ khóa tìm kiếm (Tiêu đề, Tác giả): ").strip()
            res = service.search_documents(keyword=kw)
            print(f"\n🔍 Tìm thấy {len(res)} tài liệu phù hợp:")
            for d in res:
                print(f"  • [{DocumentType.display(d['doc_type'])}] {d['title']} - Tác giả: {d['author'] or 'N/A'}")

        elif choice == "6":
            stats = service.get_statistics()
            print("\n📊 DASHBOARD THỐNG KÊ (CASHEW ANALYTICS)")
            print(f"  • Tổng tài liệu: {stats['total_documents']}")
            print(f"  • Tổng môn học:  {stats['total_subjects']}")
            print(f"  • Dung lượng:    {stats['total_size_mb']} MB")
            print(f"  • Yêu thích:     {stats['favorites']} ⭐")
            print(f"  • Tiến độ TB:    {stats['avg_progress']}%")
            print("  • Phân loại:")
            for k, v in stats["type_breakdown"].items():
                print(f"      - {DocumentType.display(k)}: {v}")

        elif choice == "7":
            fpath = backup_mgr.backup_to_json()
            print(f"✅ Đã tạo sao lưu an toàn tại: {fpath}")

        elif choice == "0":
            print("\nTạm biệt!")
            break

def run_web(service: DocumentService, backup_mgr: BackupManager, port=8000):
    """Máy chủ Web cục bộ nhẹ nhàng (Zero-dependency) phục vụ Dashboard trực quan."""
    class RequestHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path in ("/", "/index.html"):
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                stats = service.get_statistics()
                docs = service.db.get_documents()
                subs = {s["subject_pk"]: s for s in service.db.get_subjects()}
                
                rows_html = ""
                for d in docs:
                    sub = subs.get(d["subject_fk"], {})
                    sub_name = f"{sub.get('code', '')} - {sub.get('name', '')}"
                    star = "⭐ " if d["is_favorite"] else ""
                    rows_html += f"""
                    <tr>
                        <td><strong>{star}{d['title']}</strong><br/><small style='color:#64748b;'>ID: {d['document_pk']}</small></td>
                        <td><span class='badge badge-sub'>{sub_name}</span></td>
                        <td><span class='badge badge-type'>{DocumentType.display(d['doc_type'])}</span></td>
                        <td>{d['progress']}%</td>
                        <td>{d['file_size_kb']} KB</td>
                    </tr>"""
                    
                html = f"""<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Quản lý Tài liệu Học tập - Kiến trúc Cashew</title>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700&display=swap" rel="stylesheet">
<style>
  body {{ font-family: 'Plus Jakarta Sans', sans-serif; background: #f8fafc; margin: 0; padding: 24px; color: #1e293b; }}
  .header {{ background: #1e40af; color: white; padding: 20px 28px; border-radius: 12px; margin-bottom: 24px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }}
  .stats-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; margin-bottom: 24px; }}
  .card {{ background: white; padding: 18px; border-radius: 12px; border: 1px solid #e2e8f0; box-shadow: 0 1px 3px rgba(0,0,0,0.05); }}
  .card-val {{ font-size: 26px; font-weight: 700; color: #1e40af; margin-top: 4px; }}
  .table-box {{ background: white; border-radius: 12px; border: 1px solid #e2e8f0; overflow: hidden; }}
  table {{ width: 100%; border-collapse: collapse; text-align: left; }}
  th {{ background: #f1f5f9; padding: 12px 16px; font-weight: 600; font-size: 13px; text-transform: uppercase; color: #475569; }}
  td {{ padding: 12px 16px; border-top: 1px solid #e2e8f0; font-size: 14px; }}
  .badge {{ padding: 4px 8px; border-radius: 6px; font-size: 12px; font-weight: 600; display: inline-block; }}
  .badge-sub {{ background: #e0f2fe; color: #0369a1; }}
  .badge-type {{ background: #fef3c7; color: #92400e; }}
  .footer {{ text-align: center; margin-top: 32px; font-size: 13px; color: #64748b; }}
</style>
</head>
<body>
  <div class="header">
    <h1 style="margin: 0; font-size: 22px;">📚 QUẢN LÝ TÀI LIỆU HỌC TẬP - KIẾN TRÚC CASHEW</h1>
    <p style="margin: 6px 0 0 0; opacity: 0.9; font-size: 14px;">Mô hình Local-First: SQLite WAL Mode | Client UUIDv4 | Tombstone DeleteLogs</p>
  </div>
  <div class="stats-grid">
    <div class="card"><div>Tổng tài liệu</div><div class="card-val">{stats['total_documents']}</div></div>
    <div class="card"><div>Số môn học</div><div class="card-val">{stats['total_subjects']}</div></div>
    <div class="card"><div>Dung lượng</div><div class="card-val">{stats['total_size_mb']} MB</div></div>
    <div class="card"><div>Yêu thích</div><div class="card-val">{stats['favorites']} ⭐</div></div>
    <div class="card"><div>Tiến độ TB</div><div class="card-val">{stats['avg_progress']}%</div></div>
  </div>
  <div class="table-box">
    <table>
      <thead>
        <tr><th>Tiêu đề tài liệu</th><th>Môn học</th><th>Phân loại</th><th>Tiến độ</th><th>Dung lượng</th></tr>
      </thead>
      <tbody>
        {rows_html}
      </tbody>
    </table>
  </div>
  <div class="footer">Cashew Architecture 4-Tier Pattern • Local Persistence Engine</div>
</body>
</html>"""
                self.wfile.write(html.encode("utf-8"))
            elif parsed.path == "/api/stats":
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(service.get_statistics(), ensure_ascii=False).encode("utf-8"))
            elif parsed.path == "/api/documents":
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(service.db.get_documents(), ensure_ascii=False).encode("utf-8"))
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, format, *args):
            return

    server = HTTPServer(("localhost", port), RequestHandler)
    print(f"\n🌐 WEB SERVER ĐANG CHẠY TẠI: http://localhost:{port}")
    print("👉 Mở trình duyệt web và truy cập địa chỉ trên để xem giao diện.")
    print("Nhấn Ctrl + C để dừng Web Server.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nĐã dừng Web Server.")

def main():
    db = Database("database.sqlite")
    seed_initial_data(db)
    service = DocumentService(db)
    backup_mgr = BackupManager(db)

    if "--web" in sys.argv:
        run_web(service, backup_mgr)
    else:
        run_cli(service, backup_mgr)

if __name__ == "__main__":
    main()
