<p align="center">
  <img src="docs/vikey-icon.png" width="128" height="128" alt="ViKey">
</p>

# ViKey — bộ gõ tiếng Việt kiểu UniKey cho macOS

Gõ giống UniKey trên Windows: **không gạch chân**, không "kẹt" chữ trên Chrome/Electron. ViKey bắt phím toàn hệ thống (CGEventTap). Khi một từ cần đổi dạng (`tieen` → `tiên`), nó nuốt phím vừa gõ, gửi backspace và gõ lại phần chữ khác biệt. Nếu chỉ là gõ thường, phím được cho đi thẳng tới app.

<p align="center">
  <img src="docs/screenshot.png" width="925" alt="Menu ViKey trên menu bar và cửa sổ Giới thiệu ViKey">
</p>

## Cài đặt

### Tải bản build sẵn

**[⬇ Tải ViKey bản mới nhất](https://github.com/sunnysideprojects/vikey/releases/latest)** (file `ViKey-x.y.z.zip`, macOS 13+, Apple Silicon và Intel)

1. Giải nén, kéo `ViKey.app` vào **Applications**.
2. App chỉ được ký ad-hoc (chưa notarize) nên macOS chặn lần đầu mở. Chuột phải vào app → **Open**, hoặc chạy:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ViKey.app
   ```

### Hoặc tự build từ source

```bash
xcode-select --install        # nếu chưa có Command Line Tools
./build.sh --install          # self-test → build universal → cài vào /Applications → mở app
```

### Sau khi cài

Lần đầu mở, macOS sẽ hỏi quyền **Accessibility** → bật ViKey trong System Settings → Privacy & Security → Accessibility. App tự chạy ngay khi có quyền, không cần mở lại.

Sau đó:
- Gỡ bộ gõ "Vietnamese" của macOS trong System Settings → Keyboard → Input Sources, chỉ giữ **ABC**.
- Biểu tượng trên menu bar: **V** đỏ = tiếng Việt, **E** = tiếng Anh.

> Mỗi lần build lại, chữ ký ad-hoc thay đổi nên quyền Accessibility cũ không còn khớp. `--install` đã tự reset quyền, bạn chỉ cần bật lại.

## Tính năng

| | |
|---|---|
| Kiểu gõ | Telex, VNI |
| Chuyển Việt/Anh | ⌃⇧ (mặc định), đổi được sang ⌘⇧ / ⌥⇧ / ⌃⌥ — bấm rồi nhả, không kèm phím khác |
| Đặt dấu tự do | `tiengse` → tiếng, `vieetj` → việt, dấu tự nhảy đúng vị trí khi gõ thêm |
| Kiểu đặt dấu | cũ `hòa, thủy` (mặc định) hoặc mới `hoà, thuỷ` |
| Khôi phục từ tiếng Anh | `windows`, `google`, `class`, `tesst` → `test`... không bị biến dấu |
| Gõ lại để huỷ dấu | `ass` → as, `aaa` → aa, `ddd` → dd, `ww` → w |
| Phím tắt `w` | `w` → ư, `uow`/`uwow` → ươ, `thuowr` → thuở |
| Nhớ trạng thái theo app | ví dụ Terminal luôn E, Slack luôn V |
| Sửa lỗi trình duyệt | thanh địa chỉ Chrome/Edge/Arc/Brave/Firefox/Safari/Cốc Cốc không nuốt chữ vì autocomplete |
| Gõ tắt | dùng chung file `ukmacro.txt` với UniKey (để trên Google Drive được), tự nạp lại khi file đổi |
| Khởi động cùng macOS | qua `SMAppService` |

### Telex
`s` sắc · `f` huyền · `r` hỏi · `x` ngã · `j` nặng · `z` xoá dấu · `aa` â · `ee` ê · `oo` ô · `aw` ă · `ow` ơ · `uw`/`w` ư · `dd` đ

### VNI
`1` sắc · `2` huyền · `3` hỏi · `4` ngã · `5` nặng · `0` xoá dấu · `6` â ê ô · `7` ơ ư · `8` ă · `9` đ

## Cấu trúc

```
Sources/ViKeyCore/      engine thuần Swift, không phụ thuộc AppKit
  Vietnamese.swift      bảng nguyên âm/phụ âm, kiểm tra âm tiết hợp lệ, vị trí dấu, render
  Engine.swift          xử lý phím theo từ: dấu, mũ/móc, huỷ dấu, khôi phục, backspace
  Macro.swift           đọc bảng gõ tắt định dạng UniKey
Sources/ViKey/          app menu bar
  KeyTap.swift          CGEventTap: bắt phím, diff output, gửi backspace + Unicode
  AppDelegate.swift     menu, quyền Accessibility, nhớ trạng thái theo app
  Settings.swift        UserDefaults
  MacroFile.swift       theo dõi file ukmacro.txt (gõ tắt)
  AboutWindow.swift     cửa sổ Giới thiệu
Sources/ViKeySelfTest/  test engine (build.sh chạy trước khi build)
Resources/              Info.plist, AppIcon.icns, logo + font brand
scripts/                vẽ lại icon app (build-icon.sh), đóng khung ảnh chụp màn hình (frame-screenshots.swift)
docs/                   logo và ảnh chụp màn hình dùng trong README
reference/              bản engine Python tương đương + cases.tsv dùng chung
```

Thêm test: bổ sung dòng vào `reference/cases.tsv`, chạy `python3 reference/test_engine.py`, rồi `swift run -c release ViKeySelfTest` (test Swift đọc cùng file này).

## Giới hạn

- Ô mật khẩu (Secure Input) macOS chặn mọi event tap, nên ViKey không hoạt động ở đó, giống mọi bộ gõ dạng này.
- Bấm backspace khi đang ở giữa từ cũ (sau khi click chuột hoặc di chuyển con trỏ) sẽ không khôi phục được từ đó để sửa dấu. UniKey cũng vậy.
- Chỉ xuất Unicode dựng sẵn; không có TCVN3/VNI-Windows.

## Giấy phép

Code theo [MIT](LICENSE). Font Bricolage Grotesque theo SIL OFL 1.1; tên và logo Sunny Side Projects giữ bản quyền (xem cuối [LICENSE](LICENSE)).

---

<img src="https://cdn.jsdelivr.net/gh/sunnysideprojects/brand@main/logos/svg/ssp-mark.svg" width="20"> ViKey · a [Sunny Side Project](https://github.com/sunnysideprojects)
