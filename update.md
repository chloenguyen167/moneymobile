# Đề xuất giải pháp: OCR hóa đơn tiếng Việt & Phân loại danh mục thu chi

Trước khi đi vào chi tiết, hai tính năng này có thể dùng chung một triết lý: **kết hợp nhiều tầng xử lý** (rule-based → model nhẹ không cần train → model mạnh hơn khi cần) thay vì đặt cược vào một model duy nhất. Cách này vừa giữ được chi phí = 0, vừa chạy tốt trên Mac, vừa có đường nâng cấp rõ ràng khi có dữ liệu người dùng thật.

## Phần 1 — OCR hóa đơn tiếng Việt

### Vì sao tiếng Việt khó hơn OCR thông thường
Tiếng Việt có 6 thanh điệu + nhiều tổ hợp phụ âm/nguyên âm ghép dấu, nên các model OCR tổng quát (huấn luyện chủ yếu trên tiếng Anh/Trung) thường nhận sai dấu dù nhận đúng chữ cái. Ngoài ra hóa đơn Việt Nam thực tế (giấy in nhiệt mờ dần, ảnh chụp nghiêng/cong, ánh sáng flash) khác xa ảnh scan sạch trong các bộ dữ liệu huấn luyện phổ biến.

Có hai hướng tiếp cận công nghệ khác hẳn nhau, và tôi sẽ trình bày cả hai:### Hướng A — Đọc trực tiếp bằng VLM (Vision-Language Model): khuyến nghị làm trước

Đây là hướng hiện đại nhất và theo tôi nên làm **MVP đầu tiên** vì không cần train, miễn phí, chạy được ngay trên Mac:

- **Cách hoạt động**: đưa thẳng ảnh hóa đơn cho một model thị giác đa phương thức, kèm prompt yêu cầu trả về JSON có cấu trúc (tên cửa hàng, ngày, tổng tiền, danh sách mặt hàng...). Model tự "đọc hiểu" bố cục hóa đơn thay vì phải qua bước tách dòng/nhận diện ký tự riêng biệt. Các model dạng này đã được cải thiện đáng kể cho việc nhận dạng văn bản đa ngữ cảnh, đa ngôn ngữ và trích xuất thông tin có cấu trúc từ hóa đơn, biểu mẫu, bảng biểu.
- **Model đề xuất**: Qwen2.5-VL/Qwen3-VL (bản 7B) hoặc PaddleOCR-VL — model chuyên biệt cho phân tích tài liệu, chỉ ~0.9 tỷ tham số nhưng đạt độ chính xác top đầu trên benchmark phân tích tài liệu OmniDocBench, đủ nhẹ để chạy tốt trên Mac.
- **Chạy trên Mac ra sao**: dùng Ollama — từ đầu năm 2026 Ollama đã chuyển sang dùng thẳng framework MLX của Apple trên Apple Silicon, giúp tốc độ suy luận tăng đáng kể so với trước, gần như "cắm là chạy" không cần cấu hình gì thêm. Máy M-series với RAM ~16GB trở lên chạy ổn bản 7B ở chế độ lượng tử hoá 4-bit.
- **Điểm mạnh**: không cần dataset, không cần train, hiểu ngữ cảnh layout tốt (biết đâu là tổng tiền dù không có nhãn "Total" rõ ràng), dễ mở rộng thêm trường mới chỉ bằng cách sửa prompt.
- **Điểm yếu**: chậm hơn pipeline cổ điển (vài giây/hóa đơn thay vì <1 giây), cần máy có RAM đủ lớn, độ chính xác trên hóa đơn quá mờ/nhàu vẫn có thể sai lệch nếu chưa từng "thấy" kiểu hóa đơn đó.

### Hướng B — Pipeline cổ điển: Detect + Recognize (có thể fine-tune)

Đây là hướng phù hợp khi cần độ chính xác cao hơn, tốc độ nhanh hơn, và footprint nhẹ hơn nhiều (mô hình nhận dạng chỉ vài chục MB, chạy được cả trên di động nếu sau này muốn chuyển bớt xử lý xuống app).

- **Bước 1 — Text detection** (tìm vị trí các dòng chữ trong ảnh): dùng CRAFT, DB (Differentiable Binarization), PAN, hoặc YOLOv8 — các cộng đồng Việt Nam đã fine-tune sẵn các model này cho văn bản tiếng Việt.
- **Bước 2 — Text recognition** (đọc nội dung từng dòng đã cắt): **VietOCR** (kiến trúc CNN + Transformer) là lựa chọn phổ biến và tốt nhất hiện có cho tiếng Việt — được thiết kế riêng để nhận dạng chữ viết tay và chữ đánh máy tiếng Việt, có khả năng tổng quát hoá tốt, đạt độ chính xác khá cao ngay cả trên dữ liệu mới chưa từng huấn luyện. Một pipeline tham khảo đã có sẵn kết hợp phát hiện vùng văn bản bằng PAN rồi dùng VietOCR để trích xuất, kèm bước sửa lỗi từ (word correction).
- **Bước 3 — Trích trường** (parse text thô thành các trường có ý nghĩa): dùng rule/regex (cho số tiền, ngày, mã số thuế) kết hợp mô hình phân loại theo dòng (BERT-based) nếu muốn chính xác cao hơn.
- **Điểm mạnh**: nhanh (dưới 1 giây/hóa đơn), nhẹ, dễ fine-tune từng phần riêng lẻ.
- **Điểm yếu**: cần ghép nhiều model lại với nhau, phức tạp hơn khi bảo trì, độ chính xác phụ thuộc nhiều vào chất lượng bước detect.

### Có cần train không, và train thế nào trên Mac?

**Không bắt buộc** — cả hai hướng trên đều có checkpoint pretrained dùng được ngay. Nhưng nếu muốn nâng độ chính xác cho đúng "phong cách" hóa đơn Việt Nam thực tế (siêu thị, quán ăn, taxi, xăng dầu, hóa đơn điện tử...), đây là cách làm nhanh nhất:

**Dataset khởi điểm**: bộ dữ liệu MC-OCR — 2.436 ảnh hóa đơn tiếng Việt chụp bằng điện thoại di động, được xây dựng qua quy trình gán nhãn kết hợp con người và mô hình — có sẵn công khai trên Kaggle, dùng để fine-tune hoặc ít nhất để đánh giá (benchmark) độ chính xác trước/sau khi tinh chỉnh. Nên bổ sung thêm vài trăm ảnh hóa đơn thật thu thập từ chính người dùng thử nghiệm (đa dạng nguồn: siêu thị, tạp hóa, quán ăn, xăng, Grab...) vì đây mới là phân phối dữ liệu thực tế app sẽ gặp.

**Thời gian train ước tính trên Mac** (tuỳ chọn theo mức độ đầu tư):

| Cách fine-tune | Cần gì | Thời gian ước tính trên Mac M-series | Ghi chú |
|---|---|---|---|
| Fine-tune riêng bước recognition của VietOCR | Vài nghìn dòng chữ đã cắt sẵn + nhãn text | Vài giờ (chạy được trên GPU tích hợp qua MPS vì VietOCR dựa trên PyTorch) | Nhanh nhất, rủi ro thấp nhất, cải thiện rõ với chữ mờ/font lạ |
| Fine-tune cả detect + recognize theo hướng PaddleOCR | Ảnh hóa đơn đầy đủ, có bounding box | Nên train trên **Kaggle GPU miễn phí**, không phải trên Mac | PaddlePaddle (framework của PaddleOCR) chưa tối ưu tốt cho GPU Apple Silicon, cộng đồng Việt Nam làm hướng này đều train trên Kaggle notebook rồi mang model về Mac chỉ để chạy suy luận |
| LoRA fine-tune một VLM nhỏ (Qwen2.5-VL 7B) trên vài trăm cặp ảnh–JSON | Vài trăm hóa đơn đã gán nhãn JSON đầy đủ | Vài giờ, chạy thẳng trên Mac qua MLX-LM | Hướng mạnh nhất về lâu dài: model học luôn cả cách trích trường, không cần bước parse riêng |

**Lộ trình khuyến nghị**: Giai đoạn 1 dùng thẳng Qwen2.5-VL/PaddleOCR-VL qua Ollama (không train, có ngay). Sau khi có vài trăm–vài nghìn hóa đơn thật từ người dùng (đã qua chỉnh sửa/xác nhận), fine-tune LoRA nhẹ trên chính dữ liệu đó để tăng độ chính xác cho các trường hợp khó của riêng app (hóa đơn nhiệt mờ, viết tay, layout lạ).

**Phương án tham khảo thêm (không miễn phí hoàn toàn)**: FPT.AI Reader — sản phẩm OCR hóa đơn chuyên biệt của FPT, độ chính xác 98-99% với hóa đơn in và điện tử, chuyên tối ưu cho hóa đơn VAT và chứng từ tiếng Việt, có gói dùng thử miễn phí 500 request/ngày. Có thể dùng làm mốc so sánh (benchmark) độ chính xác cho hướng tự triển khai, nhưng không phù hợp làm giải pháp chính vì cần internet, giới hạn free tier, và dữ liệu hóa đơn người dùng phải gửi ra ngoài server bên thứ ba.

---

## Phần 2 — Tự động phân loại danh mục thu chi

Nguyên tắc thiết kế: xử lý theo **tầng (cascade)** — tầng rẻ và nhanh xử lý trước, chỉ đẩy lên tầng nặng hơn khi cần, và luôn để người dùng xác nhận khi hệ thống đề xuất danh mục mới (tránh tạo danh mục trùng lặp, không nhất quán).### Tầng 1 — Từ điển quy tắc (rule-based)

- **Cách làm**: xây một bảng ánh xạ "từ khoá merchant/mô tả → danh mục", ví dụ: Circle K, WinMart, Bách Hoá Xanh → *Ăn uống/Tạp hoá*; Grab, Be, Xanh SM → *Di chuyển*; EVN, Điện lực, VNPT, Viettel → *Hóa đơn – Điện nước*; Shopee, Lazada, Tiki → *Mua sắm online*...
- **Vì sao nên có tầng này dù đơn giản**: đây là tầng xử lý phần lớn giao dịch phổ biến ở Việt Nam gần như tức thì, không tốn tài nguyên tính toán, độ chính xác gần như tuyệt đối cho các merchant đã biết, và không cần bất kỳ model AI nào. Danh sách này có thể build sẵn (dữ liệu merchant phổ biến ở VN không khó thu thập) rồi mở rộng dần qua thời gian sử dụng thực tế.

### Tầng 2 — So khớp ngữ nghĩa bằng embedding (không cần train)

Khi giao dịch không khớp merchant nào trong từ điển (ví dụ tên quán lạ, mô tả tự do người dùng gõ tay), dùng model embedding đa ngôn ngữ để so sánh ngữ nghĩa:

- **Cách làm**: mỗi danh mục có sẵn được gán vài câu ví dụ mẫu ("cà phê", "trà sữa", "ăn trưa" cho danh mục Ăn uống...). Mô tả giao dịch mới được encode thành vector rồi so cosine similarity với các câu mẫu; nếu điểm cao nhất vượt ngưỡng (ví dụ 0.75) thì gán luôn danh mục đó — không cần huấn luyện gì thêm, chỉ cần thêm/sửa câu ví dụ.
- **Model đề xuất**: BGE-M3 hoặc multilingual-e5-large-instruct — đây là hai trong số các model embedding đa ngôn ngữ mã nguồn mở tốt nhất hiện nay, hỗ trợ hơn 100 ngôn ngữ bao gồm tiếng Việt, chạy được hoàn toàn local (không cần GPU mạnh, CPU trên Mac cũng đủ nhanh cho tác vụ này vì mỗi lần chỉ encode một câu ngắn).
- **Ưu điểm**: xử lý được các trường hợp "gần giống nhưng không khớp từ khoá cứng" (ví dụ "Phúc Long" không có trong từ điển nhưng ngữ nghĩa gần với "cà phê, trà sữa").

### Tầng 3 — LLM cục bộ: phân loại + đề xuất danh mục mới

Khi cả hai tầng trên đều không chắc chắn (similarity thấp), đây là lúc thực sự cần một model "hiểu ngôn ngữ" để quyết định:

- **Cách làm**: gọi một LLM nhỏ chạy local (ví dụ Qwen3 8B qua Ollama, dùng backend MLX để tận dụng tốc độ trên Apple Silicon) với prompt: đưa mô tả giao dịch + danh sách danh mục hiện có của người dùng, yêu cầu trả JSON dạng `{category, is_new_category, ten_de_xuat_neu_moi, do_tin_cay}`.
- **Đây chính là cơ chế "tự đề xuất danh mục mới"** mà bạn muốn: nếu LLM đánh giá không danh mục nào phù hợp, nó đề xuất tên danh mục mới ngắn gọn, hợp lý theo văn phong tiếng Việt.
- **Quan trọng — không nên tự động tạo danh mục mới ngay lập tức**: nên luôn hiển thị đề xuất cho người dùng xác nhận/sửa tên trước khi lưu vào hệ thống. Đây là cách các app quản lý chi tiêu phổ biến vẫn làm, vì tự động tạo danh mục không kiểm soát dễ dẫn đến danh mục trùng lặp, không nhất quán theo thời gian (ví dụ vừa có "Cà phê" vừa có "Coffee").
- Khi người dùng xác nhận, danh mục mới đó được lưu **và đồng thời trở thành câu ví dụ mới cho Tầng 2** — hệ thống "học" dần theo thời gian mà không cần retrain bất cứ thứ gì.

### Giai đoạn nâng cấp sau này (khi có đủ dữ liệu)

Sau vài tháng vận hành, khi đã tích luỹ đủ dữ liệu gán nhãn/sửa nhãn từ chính người dùng, có thể fine-tune một classifier chuyên biệt bằng **PhoBERT** — model ngôn ngữ tiếng Việt vẫn giữ vị trí hàng đầu cho các bài toán phân loại văn bản tiếng Việt, thường vượt trội các model đa ngôn ngữ tổng quát (mBERT, XLM-RoBERTa) trên tác vụ tiếng Việt thuần. Lưu ý PhoBERT cần bước tách từ (word segmentation, dùng thư viện như underthesea/pyvi) trước khi đưa vào model — bỏ qua bước này khiến độ chính xác giảm đáng kể. Việc này giúp giảm phụ thuộc vào LLM (rẻ hơn, nhanh hơn ở quy mô lớn) nhưng không bắt buộc phải làm ngay từ đầu.

---

## Tổng hợp & lưu ý triển khai

| Thành phần | Model đề xuất | Cần train? | Chạy trên Mac |
|---|---|---|---|
| OCR hóa đơn (MVP) | Qwen2.5-VL 7B hoặc PaddleOCR-VL, qua Ollama | Không | Có, qua MLX |
| OCR hóa đơn (nâng cao) | VietOCR (fine-tune) hoặc LoRA trên VLM | Có, fine-tune nhẹ | Có (PyTorch/MLX), riêng PaddleOCR nên train trên Kaggle GPU miễn phí rồi mang về Mac |
| Phân loại tầng 1 | Từ điển quy tắc | Không | Có (không cần GPU) |
| Phân loại tầng 2 | BGE-M3 / multilingual-e5 | Không | Có (CPU đủ dùng) |
| Phân loại tầng 3 | Qwen3 8B qua Ollama | Không | Có, qua MLX |
| Phân loại (nâng cao) | PhoBERT fine-tune | Có | Có (PyTorch/MPS) |

**Về phần cứng**: các phương án "không cần train" ở trên đều chạy tốt trên Mac Apple Silicon (M1 trở lên), lý tưởng là ≥16GB RAM để chạy đồng thời model VLM 7B và LLM phân loại. Nếu Mac hiện có RAM thấp hơn, vẫn có thể dùng bản lượng tử hoá nhỏ hơn (Qwen2.5-VL ở mức 4-bit, hoặc Qwen3 4B thay vì 8B) với đánh đổi độ chính xác nhẹ.

**Về chi phí vận hành**: toàn bộ pipeline đề xuất là tự lưu trữ (self-hosted), không phụ thuộc API trả phí, nên chi phí biến đổi gần như bằng 0 — chỉ tốn điện/tài nguyên máy chủ chạy Ollama.