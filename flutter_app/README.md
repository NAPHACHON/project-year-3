# Flutter member client

รัน `start_flutter.bat` ที่รากโปรเจกต์ หลังเปิด Laravel ด้วย `start.bat` แล้ว

คำสั่งในโฟลเดอร์ flutter_app:

```bat
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 5173 --dart-define=API_BASE_URL=http://localhost:8080/api/v1
```

รองรับ login, **สมัครสมาชิกใหม่**, ตรวจการเชื่อมต่อ API, ดูเครื่อง, จอง, ยกเลิกการจอง, รีเฟรช และ logout ที่เพิกถอน token ผ่าน API โดยหน้าตาใช้โทนเดียวกับ Laravel (CyberCafe Desk)
บัญชีผู้ดูแลให้ทำงานบริหารร้านผ่าน Laravel /dashboard แอปนี้เน้นสมาชิก

การเปลี่ยนที่อยู่เซิร์ฟเวอร์ใช้ --dart-define=API_BASE_URL=... ตอน run/build ต้องรวม /api/v1 และไม่ต้องแก้ lib/main.dart
หน้า http://localhost:8080/flutter เป็น HTML/Blade เดิม ส่วน Flutter จริงเปิด http://localhost:5173
อ่าน docs/fix-api-flutter.md ของโปรเจกต์หลักสำหรับวิธีอัปเดตและแก้ CORS

การสมัครสมาชิกต้องกรอกชื่อ เบอร์โทร อีเมล รหัสผ่าน และยืนยันรหัสผ่าน จากนั้นระบบจะเข้าสู่ระบบให้อัตโนมัติผ่าน API `/api/v1/auth/register`


## การจองบนมือถือ

ถ้าบัญชีมีรายการจองหรือกำลังเล่นอยู่ ระบบจะไม่สร้างรายการที่สอง โดย Flutter จะแสดงการ์ดรายการเดิมพร้อมปุ่มยกเลิก (กรณีสถานะ `reserved`) หากสถานะ `active` ต้องให้ผู้ดูแลปิดเซสชันก่อน เมื่อไม่มีรายการเดิม ปุ่ม `จองเครื่อง` จะทำงานตามปกติและรีเฟรชสถานะจาก API หลังสำเร็จ


## เวลาเล่นและคืนส่วนต่าง
สมาชิกและผู้ดูแลเลือกชั่วโมงและดูยอดก่อนจองได้ ผู้ดูแลรับเงินก่อนเริ่มเล่น สมาชิกกดจบระหว่างเล่นเพื่อคำนวณส่วนต่าง รายการรอคืนเงินและประวัติอยู่ในหน้าเดียวกัน อ่าน `../docs/booking-time-refund.md` ก่อนอัปเดตฐานข้อมูล

รุ่นที่ตรวจ: Flutter 3.35.7 / Dart 3.9.2 หรือใหม่กว่า รองรับฟอร์มแบบ Material 3 และ DropdownButtonFormField.initialValue
