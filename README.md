# Tuchi — App Quản lý Chi tiêu (OCR + AI Classification)

Triển khai theo [`pipeline_app_quan_ly_chi_tieu.md`](pipeline_app_quan_ly_chi_tieu.md).

**Kiến trúc:** Hybrid Edge-Cloud, hai tầng Cascade (CR-OCR + PVC-Class), Personal Vector Store trên pgvector, Celery cho job định kỳ.

```
Flutter (Riverpod)  →  FastAPI  →  PostgreSQL + pgvector
                         ↓
                    Redis + Celery (forecast, alerts, graph, email sync)
                         ↓
              OCR cascade / Classify cascade / LLM APIs
```

---

## Lộ trình 4 Phase

| Phase | Trạng thái | Nội dung chính |
|---|---|---|
| **Phase 1 — MVP** | ✅ | CR-OCR Fast Track + LLM fallback · PVC-Class cơ bản · Budget & analytics · Chụp hóa đơn |
| **Phase 2** | ✅ | Personal Vector Store · Notification Capture Android · Budget alerts FCM |
| **Phase 3** | ✅ | Vintern Smart Track · LLM taxonomy · Cold-start graph · Holt-Winters · Gmail iOS |
| **Phase 4** | ✅ | Subscription detection · Community graph · GPU metrics & auto-tune · Anomaly alerts |

---

## Phase 1 — MVP

### Backend

| Thành phần | Mô tả |
|---|---|
| **CR-OCR Fast Track** | Regex/heuristic trích `merchant`, `total_amount`, `date`, `items` từ text OCR |
| **Smart Track fallback** | OpenAI/Gemini khi Fast Track confidence thấp |
| **PVC-Class cơ bản** | Rule-based + hash embedding + pgvector kNN + Global Merchant Graph |
| **Human-in-the-loop** | User xác nhận/sửa category → cập nhật vector store |
| **Budget & analytics** | Tổng chi tiêu, pie chart theo category, xu hướng ngày, dự báo cuối tháng đơn giản |
| **Auth** | JWT (register/login) |

### Mobile

| Màn hình | Mô tả |
|---|---|
| **Giao dịch** | Danh sách transaction, swipe xác nhận category |
| **Chụp HĐ** | Camera + Edge Gate IQA (Laplacian variance) trước khi upload |
| **Budget** | Tạo/xem ngân sách theo category |
| **Phân tích** | Biểu đồ pie + line chart chi tiêu |

### API Phase 1

| Endpoint | Mô tả |
|---|---|
| `POST /api/v1/auth/register` | Đăng ký |
| `POST /api/v1/auth/login` | Đăng nhập |
| `GET /api/v1/auth/me` | Thông tin user |
| `POST /api/v1/transactions/process-receipt` | Upload ảnh → OCR + classify |
| `GET /api/v1/transactions` | Danh sách giao dịch |
| `POST /api/v1/transactions` | Tạo giao dịch thủ công |
| `POST /api/v1/transactions/{id}/confirm` | Xác nhận category |
| `GET /api/v1/categories` | Danh sách category |
| `GET /api/v1/analytics/summary` | Tổng hợp chi tiêu |
| `GET/POST /api/v1/budgets` | Quản lý ngân sách |

---

## Phase 2 — Personalization & Android Capture

### Backend

| Thành phần | Mô tả |
|---|---|
| **Personal Vector Store** | Top-k kNN voting trên `personal_merchant_embeddings`, HNSW index |
| **Embedding nâng cao** | Sentence-transformer (`paraphrase-multilingual-mpnet-base-v2`) khi bật |
| **Notification ingest** | Nhận structured fields từ Android, dedup, classify |
| **Template động** | Server phục vụ regex template theo `package_name` |
| **Budget alerts** | Cảnh báo 80%/100% ngân sách, dedup theo category/tháng |
| **FCM push** | Firebase Cloud Messaging cho alert realtime |

### Mobile (Android)

| Thành phần | Mô tả |
|---|---|
| **Notification Listener** | `notification_listener_service` + Foreground Service |
| **On-device parser** | Regex parse amount/merchant trước khi gửi server |
| **Template cache** | Cache template từ server, giảm round-trip |
| **Local notifications** | Hiển thị alert budget trên thiết bị |
| **Alert polling** | Poll `/alerts?unread_only=true` định kỳ |

### API Phase 2

| Endpoint | Mô tả |
|---|---|
| `POST /api/v1/notifications/ingest` | Ingest giao dịch từ notification |
| `GET /api/v1/notification-templates` | Template regex theo app |
| `GET /api/v1/alerts` | Danh sách cảnh báo (`?unread_only=true`) |
| `POST /api/v1/alerts/{id}/read` | Đánh dấu đã đọc |
| `POST /api/v1/devices/register` | Đăng ký FCM token |
| `DELETE /api/v1/devices/unregister` | Huỷ đăng ký FCM |

### Biến môi trường Phase 2

| Biến | Mô tả |
|---|---|
| `FCM_ENABLED` | Bật push notification (`true`/`false`) |
| `FIREBASE_CREDENTIALS_PATH` | Đường dẫn file service account Firebase |
| `USE_SENTENCE_EMBEDDINGS` | Dùng sentence-transformer thay hash embedding |

---

## Phase 3 — Smart Track & Forecast & iOS

### Backend

| Thành phần | Mô tả |
|---|---|
| **Smart Track OCR cascade** | Vintern-1B → Gemini Flash → OpenAI → heuristic |
| **LLM Taxonomy Expansion** | TELEClass-style enrichment + dynamic user categories |
| **Cold-start Graph** | Fuzzy merchant lookup + weekly `rebuild_merchant_graph` |
| **Holt-Winters forecast** | Dự báo chi tiêu theo category (`statsmodels`) |
| **Gmail OAuth** | Parse email ngân hàng/VN cho iOS (read-only) |

### Mobile

| Thành phần | Mô tả |
|---|---|
| **Email settings** | Kết nối Gmail OAuth, sync thủ công |
| **Quick add** | Dán text SMS/thông báo → tạo giao dịch |
| **Forecast UI** | Dự báo Holt-Winters theo category trong tab Phân tích |

### API Phase 3

| Endpoint | Mô tả |
|---|---|
| `GET /api/v1/analytics/forecasts` | Dự báo Holt-Winters (`?refresh=true`) |
| `GET /api/v1/email/oauth/url` | URL OAuth Gmail |
| `POST /api/v1/email/connect` | Kết nối Gmail (authorization code) |
| `GET /api/v1/email/status` | Trạng thái kết nối email |
| `POST /api/v1/email/sync` | Sync giao dịch từ email |
| `DELETE /api/v1/email/disconnect` | Ngắt kết nối Gmail |

### Biến môi trường Phase 3

| Biến | Mô tả |
|---|---|
| `VINTERN_API_URL` | URL OpenAI-compatible (vLLM/RunPod/Modal) cho Vintern-1B |
| `VINTERN_API_KEY` | API key Vintern (nếu cần) |
| `VINTERN_MODEL_NAME` | Tên model (mặc định `vintern-1b`) |
| `GEMINI_API_KEY` | Fallback OCR + classification |
| `OPENAI_API_KEY` | Fallback OCR + classification |
| `GMAIL_CLIENT_ID` | OAuth client ID Gmail |
| `GMAIL_CLIENT_SECRET` | OAuth client secret |
| `GMAIL_REDIRECT_URI` | Redirect URI OAuth |

### Vintern trên Modal (khuyến nghị)

Fast Track hiện **không** dùng dữ liệu mock — ảnh hóa đơn được gửi qua Smart Track (Vintern → Gemini → OpenAI).

```bash
# 1. Cài Modal CLI (đã chạy modal setup)
pip install modal
modal token set   # hoặc modal setup

# 2. Deploy Vintern-1B-v3.5 (~10–20 phút lần đầu, tải model ~3.7GB)
cd backend/modal
modal deploy vintern_serve.py
# Hoặc: ./deploy.sh

# 3. Copy URL in ra (dạng https://<workspace>--tuchi-vintern-vinternserver-web.modal.run)
# Thêm vào .env ở thư mục gốc project:
VINTERN_API_URL=https://<workspace>--tuchi-vintern-vinternserver-web.modal.run/v1
VINTERN_MODEL_NAME=vintern-1b

# 4. Restart API để nhận biến môi trường
docker compose up -d api
```

Kiểm tra endpoint:

```bash
curl https://<workspace>--tuchi-vintern-vinternserver-web.modal.run/health
```

**Lưu ý:** `GEMINI_API_KEY` cần key hợp lệ từ [Google AI Studio](https://aistudio.google.com/apikey) (dạng `AIza...`). Key không hợp lệ hoặc hết quota sẽ fallback sang Vintern/OpenAI.

---

## Phase 4 — Subscriptions, Community Graph & GPU Optimization

### Backend

| Thành phần | Mô tả |
|---|---|
| **Subscription detection** | Nhận diện giao dịch định kỳ: merchant + amount ±5% + chu kỳ ~25–35 ngày (cả tuần/năm) |
| **Subscription alerts** | Cảnh báo `subscription_detected` khi phát hiện subscription mới |
| **Community graph** | Tín hiệu ẩn danh `CommunityMerchantSignal` → promote vào Global Merchant Graph |
| **GPU pipeline metrics** | Đếm track OCR/classify hàng ngày (`PipelineMetricDaily`) |
| **Pipeline health** | Dashboard % smart track vs mục tiêu, khuyến nghị tối ưu |
| **Auto-tune** | Đề xuất điều chỉnh `ocr_fast_confidence_threshold` hàng tuần |
| **Spending anomaly** | Z-score trên chi tiêu category theo tuần → alert `spending_anomaly` |

### Mobile

| Thành phần | Mô tả |
|---|---|
| **Subscriptions screen** | Danh sách Netflix/Spotify…, tổng chi phí/tháng, dismiss long-press |
| **Analytics — subscription card** | Tóm tắt subscription active |
| **Analytics — pipeline health** | Trạng thái OCR/classify smart track % |

### API Phase 4

| Endpoint | Mô tả |
|---|---|
| `GET /api/v1/subscriptions` | Danh sách subscription (`?refresh=true` để quét lại) |
| `POST /api/v1/subscriptions/detect` | Chạy detection thủ công |
| `POST /api/v1/subscriptions/{id}/dismiss` | Ẩn subscription |
| `GET /api/v1/analytics/pipeline-health` | Metrics OCR/classify + khuyến nghị GPU (`?days=7`) |
| `GET /api/v1/analytics/subscriptions-summary` | Tổng hợp chi phí subscription/tháng |

### Biến môi trường Phase 4

| Biến | Mô tả |
|---|---|
| `SMART_TRACK_TARGET_PCT` | Mục tiêu tối đa % request dùng smart track/GPU (mặc định `25.0`) |
| `COMMUNITY_MIN_DISTINCT_USERS` | Số user khác nhau tối thiểu để promote community signal (mặc định `3`) |

---

## Chạy Backend

**Yêu cầu:** Docker Desktop

```bash
cp .env.example .env
# Điền OPENAI_API_KEY, GEMINI_API_KEY (và các biến phase tùy nhu cầu)
docker compose up -d
```

Services: `postgres` (pgvector) · `redis` · `api` (port 8000) · `worker` · `beat`

```bash
# Kiểm tra
curl http://localhost:8000/health
# OpenAPI docs
open http://localhost:8000/docs
```

### Chạy backend local (không Docker)

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
# Terminal riêng:
celery -A app.worker.celery_app worker --loglevel=info
celery -A app.worker.celery_app beat --loglevel=info
```

---

## Chạy Mobile

```bash
cd mobile && flutter pub get && flutter run
```

**API URL mặc định:** Android emulator `http://10.0.2.2:8000`, iOS simulator `http://localhost:8000`. **iPad thật** cần IP Mac khi build (xem bên dưới).

### Cài iPad qua Apple Configurator (free, ~7 ngày, không cần Apple Developer $99)

**Chuẩn bị một lần**

1. **Xcode** → Settings → Accounts → thêm Apple ID (Personal Team)
2. Mở project: `open mobile/ios/Runner.xcworkspace`
3. Target **Runner** → **Signing & Capabilities**:
   - ✅ Automatically manage signing
   - **Team:** Personal Team (Apple ID của bạn)
   - **Bundle Identifier:** đổi unique, vd `com.tenban.tuchi`
4. Cắm **iPad** USB → Unlock → Trust This Computer
5. Xcode → Window → **Devices and Simulators** → chọn iPad (đăng ký UDID)

**Build file .ipa**

```bash
cd mobile
# Lần đầu — tạo certificate + Team ID (free Apple ID):
./scripts/setup_ios_signing.sh

# Build IPA:
./scripts/build_ipa_ac.sh
```

Script tạo IPA tại `build/ios/ipa/` và copy ra `~/Desktop/Tuchi.ipa`.

**Cài bằng Apple Configurator 2**

1. **Xóa app Tuchi cũ** trên iPad (nếu đã cài bằng Xcode Run / `flutter run` — đó là bản debug)
2. Mở **Apple Configurator**, chọn iPad ở sidebar
3. **Add (+)** → **Apps** → chọn `~/Desktop/Tuchi.ipa` (file **release** từ script)
4. Trên iPad: **Settings → General → VPN & Device Management** → **Trust** developer
5. Backend chạy trên Mac (`docker compose up` hoặc `uvicorn`), iPad **cùng Wi‑Fi** với Mac

> **Lỗi thường gặp:** Màn hình *"debug mode Flutter apps can only be launched from Flutter tooling..."*  
> → App đang là bản **debug**. Xóa app, build lại `./scripts/build_ipa_ac.sh`, cài **Tuchi.ipa** qua Apple Configurator.  
> **Không** dùng Xcode Run (⌘R) hoặc `flutter run` để test trên iPad thật.

| Lưu ý | Chi tiết |
|---|---|
| Hết hạn | ~**7 ngày** — build & cài lại IPA mới |
| Giới hạn free | ~3 app sideload cùng lúc / thiết bị |
| API | iPad **không** dùng `localhost` — phải là IP LAN của Mac |
| Debug vs Release | Chỉ **release IPA** mở được từ icon; Xcode Run = debug |

### Workflow theo nền tảng

| Nền tảng | Luồng chính |
|---|---|
| **Chung** | Đăng ký/đăng nhập → Chụp HĐ hoặc thêm thủ công → Xác nhận category → Xem Budget/Phân tích |
| **Android** | Icon 🔔 → Bật Notification Access → Tự động bắt giao dịch ngân hàng/ví |
| **iOS** | Icon ✉️ → Kết nối Gmail → Sync email · Icon ➕ → Quick add (dán SMS) |
| **Phase 4** | Icon 🔄 → Subscription · Tab Phân tích → Forecast + subscription + pipeline health |

> **Lưu ý iOS:** Không hỗ trợ Notification Listener như Android. Email sync và Quick add là phương án thay thế.

---

## Celery jobs (tất cả phase)

| Job | Lịch | Phase | Mô tả |
|---|---|---|---|
| `run_nightly_analytics` | 2:00 AM hàng ngày | 2, 4 | Budget alerts + spending anomaly (Z-score) |
| `run_nightly_forecasts` | 2:30 AM hàng ngày | 3 | Holt-Winters forecast theo category |
| `rebuild_merchant_graph` | Chủ nhật 3:00 AM | 3, 4 | Global graph + apply community signals |
| `sync_all_emails` | Mỗi 6 giờ | 3 | Sync Gmail cho user đã kết nối |
| `detect_all_subscriptions` | 4:00 AM hàng ngày | 4 | Quét subscription cho mọi user |
| `gpu_auto_tune` | Thứ 2 5:00 AM | 4 | Đề xuất điều chỉnh OCR threshold |

---

## Cấu trúc project

```
tuchi/
├── pipeline_app_quan_ly_chi_tieu.md   # Đặc tả kiến trúc gốc
├── docker-compose.yml
├── .env.example
├── backend/
│   └── app/
│       ├── main.py
│       ├── worker.py                  # Celery + beat schedule
│       ├── routers/                   # auth, transactions, analytics, email, subscriptions…
│       └── services/
│           ├── ocr/                   # fast_track, smart_track, vintern, pipeline
│           ├── classify/              # pipeline, embedding, taxonomy, merchant_graph, community_graph
│           ├── analytics/             # budget, forecast, subscriptions, anomaly
│           ├── email/                 # gmail, oauth
│           ├── metrics/               # pipeline health, auto-tune (Phase 4)
│           └── push/                  # fcm
└── mobile/
    └── lib/
        ├── features/
        │   ├── auth/
        │   ├── capture/               # Edge Gate IQA
        │   ├── transactions/
        │   ├── budget/
        │   ├── analytics/
        │   ├── subscriptions/         # Phase 4
        │   ├── notification_listener/ # Phase 2 (Android)
        │   ├── email/                 # Phase 3 (iOS)
        │   └── quick_add/             # Phase 3
        └── data/remote/tuchi_repository.dart
```

---

## Tech stack

| Layer | Công nghệ |
|---|---|
| Mobile | Flutter, Riverpod, go_router, fl_chart, Drift (deps) |
| Backend | FastAPI, SQLAlchemy async, Celery, Redis |
| Database | PostgreSQL + pgvector (HNSW) |
| OCR | Fast Track (regex/heuristic) → Vintern-1B → Gemini → OpenAI |
| Classification | pgvector kNN + merchant graph + community signals + LLM taxonomy |
| Forecast | statsmodels Holt-Winters |
| Push | Firebase Cloud Messaging |
| Auth | JWT |

---

## Biến môi trường (tổng hợp)

Xem [`.env.example`](.env.example). Tóm tắt:

```bash
# Phase 1
OPENAI_API_KEY=
GEMINI_API_KEY=

# Phase 2
FCM_ENABLED=false
FIREBASE_CREDENTIALS_PATH=
USE_SENTENCE_EMBEDDINGS=false

# Phase 3
VINTERN_API_URL=
VINTERN_API_KEY=
VINTERN_MODEL_NAME=vintern-1b
GMAIL_CLIENT_ID=
GMAIL_CLIENT_SECRET=
GMAIL_REDIRECT_URI=http://localhost:8000/api/v1/email/oauth/callback

# Phase 4
SMART_TRACK_TARGET_PCT=25.0
COMMUNITY_MIN_DISTINCT_USERS=3
```
