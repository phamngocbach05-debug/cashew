"""
=============================================================================
BỘ KIỂM THỬ TỰ ĐỘNG TÍNH ĐÚNG ĐẮN CỦA KIẾN TRÚC CASHEW (CHECKLIST MỤC 4)
Kiểm tra ranh giới phân tách lớp, nguyên tắc UUIDv4, Tombstone và nghiệp vụ.
=============================================================================
"""
import unittest
import os
import sys

# Đảm bảo import đúng tệp app.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from app import Database, DocumentService, DocumentType

class TestKienTrucCashew(unittest.TestCase):
    def setUp(self):
        # Dùng CSDL tạm trong bộ nhớ để cô lập kiểm thử
        self.db = Database(":memory:")
        self.service = DocumentService(self.db)
        self.sub_pk = self.db.insert_subject("CS301", "Kien truc Phan mem", 3)

    def test_1_crud_va_uuid_client(self):
        """Kiểm tra Thêm/Sửa tài liệu và sinh khóa chính UUIDv4 tại Client."""
        pk = self.service.add_document("Slide Bai 1", self.sub_pk, DocumentType.LECTURE, author="TS. Tri")
        self.assertTrue(len(pk) >= 32, "Khóa chính phải là chuỗi UUID chuẩn.")

        doc = self.db.get_document(pk)
        self.assertIsNotNone(doc)
        self.assertEqual(doc["title"], "Slide Bai 1")

        # Cập nhật
        self.service.edit_document(pk, title="Slide Bai 1 - Ban Moi", progress=80)
        updated = self.db.get_document(pk)
        self.assertEqual(updated["title"], "Slide Bai 1 - Ban Moi")
        self.assertEqual(updated["progress"], 80)

    def test_2_tombstone_khi_xoa_theo_chuan_cashew(self):
        """Kiểm tra Xóa tài liệu và tự động tạo bản ghi Tombstone trong delete_logs."""
        pk = self.service.add_document("Tai lieu can xoa", self.sub_pk, DocumentType.EXERCISE)
        self.service.remove_document(pk)

        # Đảm bảo đã xóa khỏi bảng chính
        self.assertIsNone(self.db.get_document(pk))

        # Đảm bảo có vết Tombstone trong delete_logs để phục vụ đồng bộ
        logs = self.db.get_delete_logs()
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0]["entry_pk"], pk)
        self.assertEqual(logs[0]["entity_type"], "DOCUMENT")

    def test_3_rang_buoc_nghiep_vu_validation(self):
        """Kiểm tra tầng Domain kiểm soát ràng buộc dữ liệu (ValidationEngine)."""
        # Tiêu đề rỗng -> phải báo lỗi
        with self.assertRaises(ValueError):
            self.service.add_document("", self.sub_pk, DocumentType.LECTURE)

        # Tiến độ vượt quá 100% -> phải báo lỗi
        with self.assertRaises(ValueError):
            self.service.add_document("Bai tap 1", self.sub_pk, DocumentType.EXERCISE, progress=120)

    def test_4_tim_kiem_va_thong_ke(self):
        """Kiểm tra chức năng tìm kiếm đa tiêu chí và tính toán thống kê."""
        self.service.add_document("Giao trinh Java Co Ban", self.sub_pk, DocumentType.REFERENCE, author="Nguyen Van A")
        self.service.add_document("De thi Cuoi Ky Java", self.sub_pk, DocumentType.EXAM, is_fav=1)

        # Tìm kiếm theo từ khóa
        res = self.service.search_documents(keyword="Java")
        self.assertEqual(len(res), 2)

        # Lọc theo loại
        res_exam = self.service.search_documents(doc_type=DocumentType.EXAM)
        self.assertEqual(len(res_exam), 1)

        # Thống kê
        stats = self.service.get_statistics()
        self.assertEqual(stats["total_documents"], 2)
        self.assertEqual(stats["favorites"], 1)

    def test_5_tinh_phan_tach_logic_giua_cac_lop(self):
        """Xác minh tầng Domain hoàn toàn kiểm soát nghiệp vụ thông qua Interface DB."""
        # Tầng Domain độc lập, không phụ thuộc UI
        docs_before = len(self.service.db.get_documents())
        self.service.add_document("Doc doc lap", self.sub_pk, DocumentType.LECTURE)
        docs_after = len(self.service.db.get_documents())
        self.assertEqual(docs_after, docs_before + 1)

if __name__ == "__main__":
    print("=" * 70)
    print("🚀 CHẠY KIỂM THỬ TÍNH ĐÚNG ĐẮN CỦA KIẾN TRÚC CASHEW")
    print("=" * 70)
    unittest.main(verbosity=2)
