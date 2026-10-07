# 📊 SƠ ĐỒ KIẾN TRÚC HỆ THỐNG - QUẢN LÝ TÀI LIỆU HỌC TẬP (KIẾN TRÚC CASHEW)

Tài liệu này chứa mã nguồn văn bản dạng Mermaid của các sơ đồ kiến trúc hệ thống. Bạn có thể xem trực tiếp trong VS Code (nhấn `Ctrl + Shift + V` để mở Markdown Preview) mà không gặp bất kỳ lỗi font hay binary nào.

---

## 1. Sơ đồ Kiến trúc Tổng thể 4 Tầng (4-Tier Cashew Architecture)

```mermaid
flowchart TB
    subgraph T1["1. TẦNG TRÌNH DIỄN (PRESENTATION LAYER)"]
        CLI["Giao diện Dòng lệnh (CLI Menu Console)"]
        WEB["Giao diện Trực quan Web UI (HTML5/CSS3 Reactive)"]
    end

    subgraph T2["2. TẦNG NGHIỆP VỤ (DOMAIN & SERVICE LAYER)"]
        Val["Bộ kiểm tra Hợp lệ (Validation Engine)"]
        DocSvc["Dịch vụ Tài liệu (Document Service & Search)"]
        StatSvc["Dịch vụ Thống kê (Analytics Service)"]
        SyncEngine["Bộ máy Đồng bộ & Tombstones (Sync Engine)"]
    end

    subgraph T3["3. TẦNG LƯU TRỮ CỤC BỘ (LOCAL PERSISTENCE LAYER - OFFLINE-FIRST)"]
        DBInterface["Giao diện Kho dữ liệu (IDatabase Interface)"]
        SQLite["SQLite Driver (WAL Mode - Phản hồi < 16ms)"]
        DocTable["Bảng Documents (Client-Generated UUIDv4)"]
        TombstoneTable["Bảng Delete Logs (Tombstones cho Delta Sync)"]
    end

    subgraph T4["4. TẦNG KẾT NỐI BÊN NGOÀI (EXTERNAL BACKUP / SYNC LAYER)"]
        BackupMgr["Trình quản lý Sao lưu Tự động (Backup Manager)"]
        RollingStorage["Kho lưu trữ Sao lưu Luân phiên (Tối đa 5 bản)"]
        CloudPayload["Gói dữ liệu Đồng bộ Đám mây (Delta Sync Payload)"]
    end

    CLI --> DocSvc
    CLI --> StatSvc
    WEB --> DocSvc
    WEB --> StatSvc

    DocSvc --> Val
    DocSvc --> DBInterface
    StatSvc --> DBInterface
    SyncEngine --> DBInterface

    DBInterface --> SQLite
    SQLite --> DocTable
    SQLite --> TombstoneTable

    BackupMgr --> SQLite
    BackupMgr --> RollingStorage
    SyncEngine --> CloudPayload
```

---

## 2. Sơ đồ Luồng Dữ liệu (DFD - Data Flow Diagram Cấp 1)

```mermaid
flowchart LR
    SinhVien["👤 Người dùng / Sinh viên"]
    
    subgraph Process["TIẾN TRÌNH XỬ LÝ KIẾN TRÚC CASHEW"]
        P1["(1.0) Thêm / Cập nhật Tài liệu<br/>- Sinh UUIDv4 Client<br/>- Kiểm tra Validation"]
        P2["(2.0) Xóa Tài liệu an toàn<br/>- Ghi nhận Tombstone"]
        P3["(3.0) Tìm kiếm & Thống kê"]
        P4["(4.0) Sao lưu Luân phiên"]
    end

    subgraph Storage["KHO LƯU TRỮ CỤC BỘ"]
        D1[("D1: Bảng Documents")]
        D2[("D2: Bảng Delete_Logs")]
        D3[("D3: Thư mục Backups")]
    end

    SinhVien -->|Nhập thông tin tài liệu| P1
    P1 -->|Lưu tài liệu mới| D1
    P1 -->|Phản hồi trạng thái| SinhVien

    SinhVien -->|Yêu cầu xóa tài liệu| P2
    P2 -->|Xóa bản ghi| D1
    P2 -->|Ghi log xóa Tombstone| D2
    P2 -->|Báo thành công| SinhVien

    SinhVien -->|Truy vấn theo từ khóa/môn| P3
    D1 -->|Truy xuất dữ liệu| P3
    P3 -->|Trả về kết quả & dashboard| SinhVien

    SinhVien -->|Kích hoạt sao lưu| P4
    D1 -.->|Đọc dữ liệu kết xuất| P4
    P4 -->|Ghi file snapshot luân phiên| D3
```

---

## 3. Sơ đồ Tuần tự (Sequence Diagram: Thêm tài liệu & Xóa tạo Tombstone)

```mermaid
sequenceDiagram
    autonumber
    actor User as Sinh Viên (Client)
    participant UI as Presentation (CLI / Web)
    participant Domain as Domain Service
    participant Val as Validation Engine
    participant DB as SQLite WAL (Local)
    participant Tomb as Tombstone Log

    Note over User,DB: QUY TRÌNH THÊM TÀI LIỆU (LOCAL-FIRST)
    User->>UI: Nhập: Tiêu đề, Môn học, Dung lượng, Đường dẫn
    UI->>Domain: add_document(data)
    Domain->>Val: validate_document(data)
    Val-->>Domain: Hợp lệ (True)
    Domain->>Domain: Tự sinh client_id = UUIDv4()
    Domain->>DB: INSERT INTO documents (id, title, ...)
    DB-->>Domain: Ghi đĩa tức thời (< 16ms)
    Domain-->>UI: Trả về tài liệu hoàn chỉnh kèm UUID
    UI-->>User: Hiển thị thông báo thêm thành công

    Note over User,Tomb: QUY TRÌNH XÓA TÀI LIỆU CHUẨN CASHEW (TOMBSTONE)
    User->>UI: Yêu cầu xóa tài liệu (theo UUID)
    UI->>Domain: delete_document(uuid)
    Domain->>DB: Bắt đầu SQLite Transaction
    Domain->>DB: DELETE FROM documents WHERE id = uuid
    Domain->>Tomb: INSERT INTO delete_logs (id, document_id, deleted_at)
    DB-->>Domain: Commit Transaction thành công
    Domain-->>UI: Xác nhận xóa & lưu log
    UI-->>User: Cập nhật giao diện lập tức
```

---

## 4. Sơ đồ Thực thể Quan hệ (ERD - Database Schema)

```mermaid
erDiagram
    DOCUMENTS {
        TEXT id PK "Khóa chính UUIDv4 (Client sinh)"
        TEXT title "Tiêu đề tài liệu (1-200 ký tự)"
        TEXT subject "Môn học (Toán, Lập trình, Mạng,...)"
        TEXT category "Phân loại (Bài giảng, Bài tập, Đề thi,...)"
        TEXT file_path "Đường dẫn tệp tin"
        REAL file_size_mb "Dung lượng tệp (MB)"
        TEXT file_extension "Định dạng (pdf, docx, pptx, zip)"
        INTEGER is_favorite "Đánh dấu yêu thích (0/1)"
        REAL study_progress "Tiến độ học tập (0.0 - 100.0%)"
        TEXT created_at "Thời gian tạo (ISO 8601 UTC)"
        TEXT updated_at "Thời gian cập nhật (LWW Sync)"
    }

    DELETE_LOGS {
        TEXT id PK "Khóa chính log UUIDv4"
        TEXT document_id "UUID của tài liệu đã bị xóa (Tombstone)"
        TEXT deleted_at "Thời điểm xóa (ISO 8601 UTC)"
    }

    DOCUMENTS ||--o{ DELETE_LOGS : "Tombstone ghi vết khi xóa"
```
