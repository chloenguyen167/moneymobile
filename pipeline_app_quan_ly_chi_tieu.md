# Đề xuất Kiến trúc & Pipeline — Mobile App Quản lý Chi tiêu (OCR + AI Classification)

**Phạm vi:** Tài liệu này đặc tả pipeline khả thi, có điểm mới, cho 4 tính năng chính của app: (1) OCR hóa đơn VN, (2) Phân loại chi tiêu tự động, (3) Bắt thông báo giao dịch, (4) Phân tích/Budget/Dự báo/Cảnh báo. Tính năng (1) và (2) được thiết kế để giải quyết trực tiếp các hạn chế đã ghi nhận trong 26 nghiên cứu đã thu thập (xem `OCR_classification.xlsx`). Tính năng (3) và (4) dùng best-practice hiện hành, không cần bám paper, nhưng vẫn được đặc tả đầy đủ để implement được ngay.

**Tech stack mục tiêu:** Flutter (mobile) + Python (backend/ML pipeline).

---

## 0. Tóm tắt điều hành

Kiến trúc đề xuất là **Hybrid Edge-Cloud, hai tầng Cascade** (Cascade OCR + Cascade Classification), nối với nhau qua một **Personal Vector Store** để cá nhân hóa theo từng người dùng. Nguyên lý xuyên suốt:

> Đừng dùng một model "to và đắt" cho mọi trường hợp. Hãy dùng model rẻ/nhanh cho phần lớn case lặp lại (hóa đơn siêu thị quen thuộc, quán quen), và chỉ gọi model nặng (VLM/LLM) cho phần khó (hóa đơn lạ, mặt hàng mới, viết tay, nhòe).

Cơ chế này giải quyết trực tiếp 2 hạn chế lớn nhất xuất hiện xuyên suốt 26 papers: **(a) chi phí tính toán/độ trễ** khi dùng MLLM cho mọi ảnh, và **(b) taxonomy tĩnh + cold-start** khi dùng model phân loại cố định categories.

---

## 1. Hạn chế cốt lõi từ literature review (tổng hợp từ 26 papers)

| # | Cụm hạn chế | Papers liên quan trực tiếp |
|---|---|---|
| 1 | **Error cascading**: OCR sai → classification sai theo; lỗi dấu tiếng Việt tạo tổ hợp OOV quá lớn để sửa bằng rule | #16 (Vietnamese Receipt OCR Hybrid), #12 (Reference-Based Post-OCR LLM), #17 (NCC+CNN reconstruction), #9 (Tesseract receipt extraction) |
| 2 | **Chi phí tính toán & độ trễ cao** của MLLM/Transformer lớn (LayoutLMv3, Vintern-1B, GPT-4) khi chạy cho *mọi* ảnh; ngược lại Tesseract nhẹ nhưng yếu với viết tay/xoay/nhiễu | #6 (Vintern-1B), #18 (LayoutLMv3 + rule-based), #22 (HTTD table detection), #7 (handwritten gated mechanism), #24 (ScanNote) |
| 3 | **Taxonomy tĩnh & cold-start**: model phân loại (SVM, LSTM, CNN) huấn luyện trên category cố định; user mới không có lịch sử để đối chiếu | #8 (SVM banking transaction), #10 (LSTM teen finance), #19 (Rel-Cat / QuickBooks), #1 (Survey text classification) |
| 4 | **Dữ liệu mất cân bằng & OOV**: nhầm lẫn giữa category có từ vựng tương đồng ("mua sắm" vs "ăn uống"); cửa hàng/món mới làm giảm hiệu suất | #10 (LSTM SMOTE), #3 (TELEClass), #14, #15, #23 (LLM taxonomy expansion), #21 (LLM sentence embeddings) |

Pipeline đề xuất ở Mục 3 và 4 giải quyết trực tiếp **2 hạn chế quan trọng nhất**: (2) Chi phí/độ trễ và (3+4) Taxonomy tĩnh/cold-start/OOV — đây cũng chính là 2 điểm nghẽn khiến phần lớn hệ thống academic không "production-ready" được.

---

## 2. Tech stack tổng thể

| Layer | Công nghệ | Lý do chọn |
|---|---|---|
| Mobile UI | **Flutter (Dart)**, state mgmt: Riverpod | Theo yêu cầu, 1 codebase Android/iOS |
| Local cache/offline | **Drift (SQLite)** | Cho phép xem giao dịch khi mất mạng, sync sau |
| Capture & crop ảnh | `camera`, `flutter_doc_scanner` / `google_mlkit_document_scanner` | Document edge detection có sẵn, không cần tự huấn luyện model crop |
| Đánh giá chất lượng ảnh (IQA) on-device | TFLite model nhỏ (blur/glare classifier) hoặc Laplacian-variance (OpenCV qua `opencv_dart`) | Nhẹ, chạy được trên điện thoại tầm trung |
| Bắt thông báo (Android) | `notification_listener_service` (Flutter plugin) + Foreground Service | Android cho phép qua `NotificationListenerService` API |
| Charts | `fl_chart` | Native Flutter, đủ cho line/bar/pie/heatmap |
| Push notification | Firebase Cloud Messaging | Cảnh báo budget, dự báo |
| API backend | **FastAPI** (Python, async) | Hợp với I/O-bound (gọi LLM/VLM song song), tự sinh OpenAPI cho Flutter codegen |
| OCR fast track | **VietOCR** (CRNN+Transformer) + text detector (DBNet/CRAFT) | SOTA cho tiếng Việt, nhẹ, chạy CPU được |
| OCR smart track | **Vintern-1B** (self-host) hoặc Gemini Flash / GPT-4o-mini (API fallback) | 1B params — đủ nhỏ để self-host, tối ưu tiếng Việt (paper #6) |
| Embedding model | PhoBERT-base fine-tune hoặc sentence-transformer distilled tiếng Việt | Cho fast-track classification |
| Vector DB | **pgvector** (extension Postgres) — gộp chung với DB chính để giảm vận hành | Đủ nhanh ở quy mô triệu vector/user; tránh phải vận hành thêm Qdrant/Milvus ở giai đoạn đầu |
| DB chính | **PostgreSQL** | Quan hệ + JSON + vector trong 1 chỗ |
| Queue/async job | **Celery + Redis** (hoặc Arq cho async-native) | Gọi LLM/VLM không chặn request chính; chạy job phân tích định kỳ |
| Object storage | S3-compatible (Cloudflare R2 / MinIO self-host) | Lưu ảnh hóa đơn, mã hóa at-rest |
| Forecast model | `statsmodels` (Holt-Winters) hoặc Prophet | Đủ tốt với dữ liệu cá nhân ít điểm |
| Auth | Firebase Auth hoặc self-host (JWT) | Tùy ngân sách |
| Infra | Docker Compose (dev) → Cloud Run/Fly.io (API) + Runpod/Modal serverless GPU (cho Vintern-1B, scale-to-zero) | Kiểm soát chi phí GPU — chỉ trả tiền khi smart-track được gọi |

---

## 3. Tính năng OCR — "Confidence-Routed Hybrid OCR" (CR-OCR)

### 3.1 Điểm mới
Một pipeline OCR **3 lớp** với cơ chế **routing theo confidence + đặc điểm ảnh**, kết hợp **post-correction dựa trên reference riêng của người dùng** (thay vì sửa lỗi chính tả chung chung) — khác với cách tiếp cận "chọn 1 trong 2" (toàn Traditional OCR hoặc toàn VLM) mà phần lớn papers đề xuất.

### 3.2 Pipeline chi tiết

**Bước 1 — Edge Gate (on-device, Flutter):**
- Document scanner crop ảnh + xoay góc.
- Tính độ mờ (Laplacian variance) và độ chói (histogram sáng). Nếu dưới ngưỡng → yêu cầu chụp lại ngay, **chặn lỗi từ gốc trước khi nó lan xuống classification** (giải quyết trực tiếp hạn chế #1 — error cascading, lấy cảm hứng từ IQA trong paper #16).
- Output: ảnh đã crop, cờ `is_low_quality`.

**Bước 2 — Fast Track (cloud, CPU instance):**
- Text detection: DBNet/CRAFT → bounding boxes.
- Text recognition: VietOCR.
- Mỗi token có confidence score; tính `avg_confidence` toàn ảnh.
- Validate cấu trúc: regex kiểm tra có tìm được trường `total_amount` hợp lệ (số + đơn vị tiền) và `date` hợp lệ không.

**Bước 3 — Routing logic:**
```
if avg_confidence >= 0.85 AND total_amount_found AND date_found AND NOT is_low_quality:
    → dùng kết quả Fast Track, KHÔNG gọi model nặng
elif avg_confidence >= 0.6:
    → gửi cả ảnh + text thô sang Smart Track để model "vá" thay vì đọc lại từ đầu
else:
    → gửi nguyên ảnh sang Smart Track (End-to-End, bỏ qua text thô)
```
Đây chính là cơ chế giải quyết hạn chế #2 (chi phí/độ trễ): theo paper #16, ~70-80% hóa đơn từ chuỗi siêu thị/cửa hàng lớn có format chuẩn → Fast Track xử lý trong 1-2 giây với chi phí gần 0; chỉ 20-30% case khó (viết tay, rách, nghiêng, hóa đơn lạ) mới chạm tới Smart Track.

**Bước 4 — Smart Track (cloud, GPU serverless):**
- **Vintern-1B** (self-host, ưu tiên vì rẻ và tối ưu tiếng Việt — paper #6) xử lý End-to-End: nhận ảnh → trả trực tiếp JSON (`merchant`, `items[]`, `total_amount`, `date`) mà không qua bước OCR trung gian — tránh được giới hạn của OCR truyền thống với hóa đơn rách/format lạ (paper #18 chứng minh kết hợp Transformer đa phương thức + rule đạt F1 0.98).
- Nếu Vintern-1B confidence vẫn thấp (hóa đơn cực phức tạp, ví dụ sao kê ngân hàng dạng bảng dài) → fallback gọi API Gemini Flash/GPT-4o-mini, có thể kèm logic phát hiện bảng kiểu **TabSniper** (paper #13) cho sao kê ngân hàng nhiều trang.

**Bước 5 — Post-OCR Correction theo Reference cá nhân:**
Lấy cảm hứng từ paper #12 (Reference-Based Post-OCR với LLM cho văn bản có dấu), nhưng thay vì dùng ebook làm reference, hệ thống dùng:
- **Merchant Reference DB**: danh sách tên cửa hàng người dùng đã từng mua + danh sách merchant phổ biến tại VN (xây dần qua thời gian, theo khu vực).
- Fuzzy matching (Levenshtein/Jaccard trên n-gram) giữa text OCR ra và reference DB để sửa lỗi dấu (vd: "Phuc Long" / "Phục Lonq" → "Phúc Long").
- Chỉ gọi LLM để sửa khi fuzzy match không đạt ngưỡng — giữ chi phí thấp.

**Output chuẩn hóa (JSON) — feed thẳng sang Classification, không đẩy text thô gây nhiễu:**
```json
{
  "merchant": "Phúc Long",
  "items": [{"name": "Trà sữa size L", "price": 55000, "qty": 1}],
  "total_amount": 55000,
  "transaction_date": "2026-06-20",
  "ocr_track_used": "fast",
  "ocr_confidence": 0.93
}
```

### 3.3 Hạn chế được giải quyết
- ✅ **Error cascading** (Mục 1.1) — qua Edge Gate + Reference-based correction.
- ✅ **Chi phí tính toán/độ trễ** (Mục 1.2) — qua cơ chế routing cascade, chỉ ~20-30% case chạm GPU.

---

## 4. Tính năng Classification — "Personalized Vector-Cascade Classification" (PVC-Class)

### 4.1 Điểm mới
Kết hợp 3 ý tưởng riêng lẻ trong literature (vector similarity cá nhân hóa, graph cho cold-start, LLM taxonomy expansion) thành **một pipeline cascade duy nhất**, với feature vector **đa trường** (không chỉ text) để giảm nhầm lẫn giữa các category có từ vựng giống nhau.

### 4.2 Pipeline chi tiết

**Bước 1 — Multi-field Embedding:**
Thay vì chỉ embed tên merchant/món hàng (cách làm của LSTM trong paper #10 — vốn nhầm "mua sắm" với "ăn uống" do từ vựng tương đồng), vector hóa nhiều trường cùng lúc:
```
feature_vector = embed(merchant_name + item_names) ⊕ one_hot(amount_bucket) ⊕ one_hot(time_of_day) ⊕ one_hot(weekday/weekend)
```
Giờ giao dịch + khoảng tiền giúp phân biệt case mơ hồ (vd: "Circle K" lúc 7h sáng mua bánh mì → Ăn uống; lúc 23h mua thuốc lá + nước ngọt → có thể là Giải trí/Khác) mà thuần text không phân biệt được.

**Bước 2 — Fast Track (Vector kNN cá nhân):**
- So khớp `feature_vector` với **Personal Vector Store** (pgvector, scoped theo `user_id`) chứa lịch sử giao dịch đã gán nhãn của chính người dùng đó.
- Nếu cosine similarity với điểm gần nhất > 0.85 → gán ngay category đó. Thời gian xử lý: vài chục ms, chi phí ~0.

**Bước 3 — Cold-Start Bootstrap (cho user mới, không có lịch sử):**
Lấy cảm hứng từ **Rel-Cat** (paper #19 — dùng đồ thị quan hệ để giải cold-start), xây **Global Merchant-Category Graph**: một bảng tra cứu tổng hợp (ẩn danh, không gắn với cá nhân) `merchant_name → category phổ biến nhất` từ toàn bộ user base. User mới → tra graph này trước khi phải gọi LLM cho từng giao dịch → giảm đáng kể số lần gọi LLM trong tuần đầu dùng app (giai đoạn cold-start tốn LLM nhất nếu không có cơ chế này).

**Bước 4 — Smart Track (LLM Zero-shot Taxonomy Expansion):**
- Kích hoạt khi: similarity thấp (merchant/món mới hoàn toàn) **hoặc** user mới và graph cũng không có dữ liệu.
- Áp dụng kỹ thuật **Zero-shot Prompting** (paper #15) **kèm taxonomy enrichment** trước khi prompt (kỹ thuật của **TELEClass**, paper #3): hệ thống trích keyword liên quan từ taxonomy hiện có của user bằng embedding-matching trước, đưa vào prompt làm ngữ cảnh — giúp LLM hiểu "không gian nhãn" hiện tại thay vì đề xuất category trùng lặp/rời rạc, đồng thời giảm token & giảm hallucination so với prompt "trần".
- LLM trả về: category đề xuất (có thể là category con mới — *dynamic taxonomy*) + 1 dòng lý do ngắn để hiển thị cho người dùng tham khảo.

**Bước 5 — Human-in-the-loop:**
- UI hiển thị category đề xuất, người dùng vuốt xác nhận hoặc sửa.
- Mọi xác nhận/sửa **ghi ngay** vào Personal Vector Store → lần sau gặp merchant tương tự, Fast Track xử lý được luôn, không tốn LLM nữa.
- Định kỳ (vd: hàng tuần), tín hiệu xác nhận từ nhiều user (ẩn danh hóa) được tổng hợp để cập nhật lại Global Merchant-Category Graph ở Bước 3.

### 4.3 Hạn chế được giải quyết
- ✅ **Taxonomy tĩnh & cold-start** (Mục 1.3) — qua Personal Vector Store (cá nhân hóa danh mục) + Global Graph (cold-start) + LLM dynamic taxonomy.
- ✅ **Dữ liệu mất cân bằng & OOV** (Mục 1.4) — qua multi-field embedding (giảm nhầm lẫn từ vựng tương đồng) + LLM xử lý merchant/món hoàn toàn mới mà không cần retrain.

---

## 5. Tính năng Bắt thông báo giao dịch (Notification Capture)

### 5.1 Pain point cụ thể
- Người dùng VN thường dùng **2-4 app tài chính song song** (app ngân hàng + MoMo/ZaloPay/VNPay...), mỗi app báo giao dịch riêng lẻ → không ai có cái nhìn tổng hợp.
- Giao dịch QR/chuyển khoản **không có hóa đơn giấy** → nếu chỉ dựa vào OCR, app sẽ bỏ sót phần lớn chi tiêu digital.
- Nhập tay là nguyên nhân hàng đầu khiến app quản lý chi tiêu bị bỏ sau vài ngày sử dụng.

### 5.2 Phương pháp

**Android** (khả thi đầy đủ):
- Dùng `NotificationListenerService` (qua plugin `notification_listener_service` hoặc native platform channel) — yêu cầu người dùng cấp quyền "Notification access" 1 lần.
- App chạy 1 **Foreground Service** nhẹ để không bị Android Doze/battery optimization giết tiến trình.
- **Parser theo template**: mỗi ngân hàng/ví có format thông báo khá cố định → maintain bộ regex/template theo `package_name` của app gửi thông báo, ví dụ:
```json
{
  "package": "com.VCB",
  "pattern": "TK (?<account>\\d+).*(?<sign>[+-])(?<amount>[\\d,]+)VND.*luc (?<time>\\d{2}:\\d{2})",
  "type": "bank_sms_style"
}
```
- Template này nên được **serve từ backend** (không hardcode trong app) để cập nhật khi ngân hàng đổi format mà **không cần release app mới**.
- Fallback: nếu app/notification không khớp template nào → gửi text thông báo (đã được người dùng đồng ý) cho 1 model NER nhẹ để trích amount/merchant.
- **Toàn bộ regex parse chạy on-device**; chỉ trường đã trích xuất (amount, merchant, time) được gửi lên server — *không* upload nguyên văn nội dung thông báo (vì có thể chứa số tài khoản/số dư nhạy cảm).

**iOS** (giới hạn nền tảng — cần nói rõ với người dùng):
Apple **không cấp API public** để đọc thông báo của app khác (khác Android). Phương án thay thế cho iOS:
1. **Email parsing**: nhiều ngân hàng/ví gửi email biên nhận → người dùng kết nối Gmail (qua OAuth, đọc-only, scope hẹp), backend quét email theo sender domain quen thuộc và parse tương tự.
2. **Quick-add qua Siri Shortcut / Share Sheet**: cho phép người dùng share thông báo thủ công vào app trong 1 chạm (giảm ma sát so với nhập tay đầy đủ).
3. Khuyến khích chụp hóa đơn/QR receipt — OCR pipeline (Mục 3) gánh phần còn lại trên iOS.

### 5.3 Khử trùng lặp (Deduplication)
Khi cả OCR (chụp hóa đơn) và Notification Capture đều ghi nhận cùng 1 giao dịch:
- Match theo `(amount, time_window ±5 phút, merchant_similarity > 0.7)`.
- Nếu khớp → merge thành 1 record, ưu tiên giữ `items[]` chi tiết từ OCR (notification thường chỉ có tổng tiền) + `merchant` chuẩn từ notification (thường chính xác hơn OCR).

---

## 6. Tính năng Phân tích / Budget / Dự báo / Cảnh báo

### 6.1 Pain point cụ thể
- Người dùng biết "tháng này tiêu nhiều" nhưng không biết **tiêu vào đâu** cho tới khi xem sao kê cuối tháng — quá trễ để điều chỉnh.
- Đặt budget xong nhưng không có cảnh báo sớm → vẫn vượt ngân sách mà không hay.
- Subscription nhỏ lẻ (app, streaming) dễ bị quên, cộng dồn thành khoản chi đáng kể.
- Không có cơ sở nào để biết "tháng này có khả năng tiêu vượt mức không" trước khi nó xảy ra.

### 6.2 Phương pháp (best-practice hiện hành, không cần bám paper)

| Bài toán | Phương pháp | Công cụ |
|---|---|---|
| Budget mặc định cho user mới | Template 50/30/20 (Cần thiết/Muốn/Tiết kiệm), cho phép tùy chỉnh theo category | Rule-based |
| Theo dõi budget realtime | So tổng chi theo category trong kỳ với ngưỡng đã đặt | SQL aggregation, cache theo ngày |
| Dự báo cuối kỳ ("on pace to spend X") | Ngoại suy tuyến tính chi tiêu từ-đầu-kỳ-đến-nay theo tỷ lệ ngày đã qua | Rule-based, tính tức thời |
| Dự báo category theo tháng (tiền điện, tiền nhà — có tính chu kỳ) | Holt-Winters / Exponential Smoothing — phù hợp với ít điểm dữ liệu (6-12 tháng) hơn là deep learning | `statsmodels` |
| Phát hiện chi tiêu bất thường | Z-score / IQR trên lịch sử chi tiêu theo category của chính user đó (giao dịch > 2.5 std dev → cảnh báo) | Job định kỳ (Celery) |
| Phát hiện subscription bị quên | Group theo `(merchant, amount ≈, chu kỳ ~30 ngày)` → liệt kê subscription đang active | SQL window function |
| Cảnh báo | Đẩy tại 80% / 100% / 120% ngân sách theo category, qua push notification | Firebase Cloud Messaging |
| Trực quan hóa | Biểu đồ tròn theo category, line chart xu hướng, heatmap ngày chi nhiều | `fl_chart` |

---

## 7. Kiến trúc hệ thống tổng thể (implementation-ready)

### 7.1 Cấu trúc Flutter app (gợi ý module)
```
lib/
 ├─ core/            (network client, secure storage, theme)
 ├─ features/
 │   ├─ capture/      (camera, document scanner, IQA on-device)
 │   ├─ notification_listener/   (Android only — service + parser cache)
 │   ├─ transactions/ (list, detail, swipe-to-confirm category)
 │   ├─ budget/
 │   ├─ analytics/    (charts, forecast, alerts feed)
 │   └─ auth/
 └─ data/
     ├─ local/        (Drift schema — offline cache)
     └─ remote/       (REST client, generated từ OpenAPI của FastAPI)
```

### 7.2 Backend — microservices (FastAPI)
| Service | Trách nhiệm | Scale |
|---|---|---|
| `gateway-api` | Auth, routing, BFF cho mobile | Luôn chạy, nhẹ |
| `ocr-service` | Cascade OCR (Mục 3) | Fast track CPU luôn chạy; Smart track GPU serverless (scale-to-zero) |
| `classify-service` | Cascade Classification (Mục 4) | CPU cho vector search; gọi LLM API ngoài cho Smart track |
| `notification-parser` | Nhận structured fields từ client, dedup, ghi transaction | Luôn chạy, nhẹ |
| `analytics-worker` | Job định kỳ: forecast, anomaly, budget check | Celery worker, chạy theo lịch (cron) |

### 7.3 Luồng dữ liệu (sequence)
1. User chụp hóa đơn → Edge Gate on-device (crop, IQA) → upload ảnh đã xử lý lên `ocr-service`.
2. `ocr-service` chạy Cascade OCR (Mục 3.2) → trả JSON chuẩn hóa.
3. JSON được gửi sang `classify-service` → chạy Cascade Classification (Mục 4.2) → trả category đề xuất + confidence.
4. Mobile hiển thị kết quả để user xác nhận/sửa (Human-in-the-loop) → ghi transaction vào Postgres + cập nhật Personal Vector Store.
5. Song song, `notification-parser` nhận structured fields từ Android notification listener → kiểm tra trùng với giao dịch vừa tạo ở bước 4 (dedup, Mục 5.3) → nếu mới, đưa qua `classify-service` như bước 3.
6. `analytics-worker` chạy mỗi khi có transaction mới (incremental update nhẹ) + job tổng hợp hàng đêm (forecast, anomaly) → ghi kết quả vào bảng `alerts` → trigger FCM nếu cần.

### 7.4 Database — entity chính (Postgres)
```
users(id, created_at, ...)
merchants(id, name, normalized_name, default_category_id)   -- Global Merchant-Category Graph
categories(id, user_id NULL, parent_id, name, is_user_defined)  -- NULL user_id = category hệ thống
transactions(id, user_id, merchant_id, amount, items JSONB, category_id,
             source ENUM('ocr','notification','manual'), confidence,
             ocr_track_used, created_at)
transaction_embeddings(transaction_id, user_id, embedding VECTOR(768))  -- pgvector
budgets(id, user_id, category_id, period, limit_amount)
alerts(id, user_id, type, payload JSONB, created_at, read_at)
notification_templates(id, package_name, regex_pattern, version)  -- serve động cho client
```

---

## 8. Bảng tổng hợp Điểm mới ↔ Hạn chế giải quyết

| Tính năng | Điểm mới | Hạn chế giải quyết | Papers nền tảng |
|---|---|---|---|
| OCR (CR-OCR) | Routing 3 lớp theo confidence + Reference-based correction cá nhân hóa | Error cascading; Chi phí/độ trễ | #6, #9, #12, #16, #17, #18 |
| Classification (PVC-Class) | Multi-field embedding + Personal Vector Store + Global Cold-start Graph + Taxonomy-enriched zero-shot LLM | Taxonomy tĩnh/cold-start; Mất cân bằng dữ liệu/OOV | #1, #3, #8, #10, #14, #15, #19, #21, #23 |
| Notification Capture | On-device parsing + template động từ server + dedup đa nguồn | (Không cần — pain point UX, không phải limitation học thuật) | — |
| Analytics/Budget/Forecast | Cascade rule-based → statistical → ngoại suy theo pace | (Không cần — pain point UX) | — |

---

## 9. Lộ trình triển khai (gợi ý)

| Phase | Nội dung |
|---|---|
| **MVP** | OCR Fast Track only + LLM fallback đơn giản (chưa cần Vintern self-host) · Category cố định + xác nhận tay · Budget cơ bản |
| **Phase 2** | Personal Vector Store (Fast Track classification) · Notification Capture Android · Cảnh báo budget |
| **Phase 3** | Smart Track đầy đủ (Vintern-1B self-host, LLM taxonomy expansion) · Cold-start Graph · Forecast · iOS email parsing |
| **Phase 4** | Subscription detection · Global graph học từ tín hiệu cộng đồng (ẩn danh) · Tối ưu chi phí GPU |

---

## 10. Lưu ý triển khai thực tế

- **Privacy:** nội dung notification gốc và ảnh hóa đơn gốc nên coi là dữ liệu nhạy cảm — mã hóa at-rest, không log nguyên văn; chỉ structured fields đi qua pipeline phân tích.
- **Chi phí LLM/VLM:** theo dõi tỷ lệ % giao dịch rơi vào Smart Track — đây là chỉ số sức khỏe hệ thống quan trọng nhất (nếu tỷ lệ này tăng dần nghĩa là cơ chế cá nhân hóa đang không học được, cần xem lại ngưỡng confidence).
- **iOS là giới hạn nền tảng, không phải giới hạn kỹ thuật** — cần set kỳ vọng đúng với người dùng iOS ngay từ onboarding (không hứa "tự động bắt mọi giao dịch" như Android).
- **Cold-start Graph dùng dữ liệu cộng đồng ẩn danh** — cần thông báo rõ trong chính sách quyền riêng tư nếu triển khai.
