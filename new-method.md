# Đề xuất giải pháp cụ thể

## 1. OCR structuring + phân loại category — giải pháp tối ưu

**Dùng ML Kit GenAI Prompt API (Gemini Nano qua AICore) làm engine chính**, với 2 lớp bảo vệ đi kèm:

- **Lớp 0 (luôn chạy trước, miễn phí, tức thời):** regex/heuristic bắt các trường quan trọng nhất (tổng tiền, ngày) từ text OCR + tra cache merchant→category. Nếu match được, không cần gọi AI luôn — vừa nhanh vừa dùng làm **cross-check**: nếu kết quả AI trả về khác xa số regex bắt được, flag cho user xác nhận thay vì tin tuyệt đối vào AI.
- **Lớp 1 (chính, khi cần hiểu ngữ cảnh phức tạp):** ML Kit GenAI Prompt API — gộp chung 1 lần gọi vừa trích xuất field (store, ngày, tổng tiền, items) vừa phân loại category, trả JSON. Đây là lựa chọn tốt nhất hiện tại vì: miễn phí, chạy offline, không cần train, và Google đang bổ sung **Structured Output API** (định nghĩa class output cố định) giúp JSON trả về ổn định hơn nhiều so với parse text tự do.
- **Lớp 2 (fallback thiết bị không hỗ trợ AICore):** LiteRT-LM + Gemma 3n (bản quantized nhỏ, ví dụ E2B) bundle qua Play Feature Delivery — chỉ tải model cho thiết bị nào thực sự cần (giữ APK gốc nhỏ). Cùng kiểu prompt như lớp 1, chỉ khác runtime.

Lý do chọn hướng này thay vì tự train classifier riêng: tập category tài chính cá nhân không quá nhiều, và một model ngôn ngữ (dù nhỏ) xử lý tốt cả 2 việc (extract + classify) trong 1 lần gọi mà không cần dataset huấn luyện — đúng tiêu chí "không cần train nhiều".

## 2. Phân tích/cảnh báo + gợi ý cá nhân hóa — dùng AI, ưu tiên local

Tách rõ 2 phần để vừa chính xác vừa "thông minh":

- **Tính toán số liệu (giữ rule-based, không AI):** ngân sách theo category, giao dịch bất thường (thống kê so với lịch sử), phát hiện chi tiêu định kỳ, xu hướng theo thời gian/theo ngày trong tuần. Đây là input đầu vào, phải chính xác 100% nên không nên giao cho AI tính.
- **Sinh insight + gợi ý cá nhân hóa (AI, ưu tiên local):** đưa các số liệu đã tính sẵn (dạng object nhỏ gọn: top category thay đổi, % vượt ngân sách, pattern chi tiêu cuối tuần...) vào **cùng ML Kit GenAI Prompt API** đã dùng ở tính năng 1 — tái sử dụng hạ tầng, không cần thêm model/dependency mới. Model chỉ được yêu cầu diễn giải và đưa gợi ý dựa trên số liệu đã cho, không được tự tính hay tự bịa con số — tránh rủi ro sai số liệu tài chính.
- Chạy theo lịch (tuần/tháng) hoặc khi có sự kiện đáng chú ý (vượt ngân sách), không chạy sau mỗi giao dịch — vừa tiết kiệm pin vừa hợp lý về mặt sản phẩm (user không cần insight liên tục).

## 3. Config linh động chọn model — thiết kế abstraction layer

Xây một lớp interface chung, ví dụ `AIProvider` với các hàm như `extractReceipt()`, `classifyCategory()`, `generateInsight()` — mọi nơi trong app gọi qua interface này, không gọi thẳng SDK cụ thể. Có 3 implementation cùng tuân theo interface: ML Kit GenAI, LiteRT-LM/Gemma, và Cloud API (Gemini hoặc provider khác). Model đang dùng được lưu trong config (DataStore hoặc Remote Config), có thể đổi runtime mà không cần sửa code — thậm chí cho phép user chọn trong Settings ("ưu tiên tốc độ = local" / "ưu tiên độ chính xác = cloud").**Chú thích màu:** teal = ML Kit GenAI (Gemini Nano, on-device) · coral = LiteRT-LM (Gemma 3n, on-device) · tím = Cloud API (fallback) · xám = cấu hình & use case tiêu thụ.

Cả 2 use case (OCR/Category và Insight/Gợi ý) đều gọi qua cùng interface `AIProvider` — tức là code xử lý OCR và code sinh gợi ý cá nhân hóa không cần biết đang chạy model nào phía sau. Muốn đổi từ ML Kit GenAI sang LiteRT-LM hay Cloud API chỉ cần đổi config, không sửa logic nghiệp vụ.


## 4. Đọc thông báo giao dịch ngân hàng/ví điện tử

Đây là phần cần lưu ý kỹ nhất về mặt Android platform:

Dùng NotificationListenerService (API có sẵn của Android) để lắng nghe thông báo hệ thống. User phải cấp quyền thủ công qua màn hình Settings riêng (ACTION_NOTIFICATION_LISTENER_SETTINGS) — không xin được bằng dialog runtime thông thường.
Lọc theo package name của các app ngân hàng/ví (Vietcombank, MB, MoMo, ZaloPay...) — chỉ xử lý thông báo từ whitelist này, bỏ qua hoàn toàn thông báo khác. Điều này vừa tiết kiệm tài nguyên vừa quan trọng cho privacy.

Lưu ý quan trọng khi lên Play Store: quyền Notification Access là "restricted permission" — Google yêu cầu khai báo lý do sử dụng rõ ràng trong Play Console. App quản lý tài chính cá nhân là use-case được chấp nhận phổ biến, nhưng cần có chính sách quyền riêng tư rõ ràng (chỉ xử lý on-device, không lưu/gửi nội dung thông báo ngoài whitelist).

NotificationListenerService lắng nghe thông báo hệ thống, user cấp quyền thủ công qua ACTION_NOTIFICATION_LISTENER_SETTINGS.
Lọc theo whitelist package name (Vietcombank, MB, MoMo, ZaloPay...) — chỉ những app này mới được xử lý tiếp, mọi thông báo khác bị bỏ qua ngay từ bước này.
Lớp 0 — regex parser theo từng bank (fast path, miễn phí, tức thời): phần lớn thông báo giao dịch của các app VN có format khá cố định ("TK ***1234 -50,000đ luc 10:30..."), regex xử lý được ngay không cần AI.
Lớp 1 — AI local qua AIProvider (fallback khi regex không khớp): gửi nội dung thông báo (chỉ vài trăm ký tự) cho ML Kit GenAI Prompt API (Gemini Nano) — cùng interface, cùng model đã load sẵn cho tính năng OCR và insight ở trên, không tốn thêm dependency hay model file nào. Model trả JSON: số tiền, loại giao dịch (thu/chi), thời gian, merchant. Thiết bị không hỗ trợ AICore thì rơi xuống LiteRT-LM/Gemma 3n như đã cấu hình.

Vì sao AI local đặc biệt hợp lý cho tính năng này (hơn cả OCR/insight): nội dung thông báo ngân hàng là dữ liệu nhạy cảm nhất trong toàn bộ app (số tài khoản, số dư, số tiền giao dịch thời gian thực). Xử lý 100% on-device nghĩa là dữ liệu này không bao giờ rời khỏi máy, kể cả gửi tới API của chính Google — đây là điểm nên nêu rõ trong chính sách quyền riêng tư khi xin quyền Notification Access trên Play Console, vừa tăng độ tin cậy với user vừa dễ được duyệt hơn.

Một lợi ích thực tế khác của lớp AI fallback: khi app ngân hàng cập nhật và đổi format thông báo (khá thường xuyên), regex sẽ lập tức parse sai hoặc bỏ sót — nhưng AI fallback vẫn xử lý được ngay mà không cần chờ bạn release bản cập nhật app để sửa regex. Có thể tối ưu thêm: khi AI parse thành công một format mới lần đầu, lưu lại pattern đó vào cache local theo package name — lần sau gặp cùng format thì regex/cache xử lý luôn, không cần gọi AI lại, giữ mọi thứ nhanh và tiết kiệm pin.

Về mặt thực thi: onNotificationPosted() chỉ nên đẩy việc parse (kể cả gọi AI local) sang WorkManager hoặc coroutine nền — không xử lý trực tiếp trên callback chính, để tránh delay hệ thống notification.