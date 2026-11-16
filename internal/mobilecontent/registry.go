package mobilecontent

// Registry of the content elements that exist in the Flutter app and are managed from
// the back office. Every key is read by a specific widget (see "Used" on each field);
// defaults are the exact values the app showed before the element became dynamic, so
// version 0 (nothing published yet) renders the app as-is. Layout, navigation, business
// rules, security and transaction logic are NOT in this registry.

// FieldType decides validation (server and app) and the back-office input.
type FieldType string

const (
	TypeText      FieldType = "text"      // single line
	TypeMultiline FieldType = "multiline" // \n allowed
	TypeImage     FieldType = "image"     // "" = image bundled in the app; https:// or /admin/uploads/…
	TypePhone     FieldType = "phone"     // digits, + - ( ) and spaces
	TypeEmail     FieldType = "email"
	TypeBool      FieldType = "bool" // "true" / "false"
	TypeEnum      FieldType = "enum" // one of Options
)

// Field is one manageable element.
type Field struct {
	Key      string    `json:"key"`
	Page     string    `json:"page"`
	Group    string    `json:"group"`
	Label    string    `json:"label"`
	Help     string    `json:"help,omitempty"`
	Used     string    `json:"used"` // Flutter widget that renders it
	Type     FieldType `json:"type"`
	Max      int       `json:"max"`
	Required bool      `json:"required"`
	Default  string    `json:"default"`
	Options  []Option  `json:"options,omitempty"`
}

// Option is an allowed value of an enum field.
type Option struct {
	Value string `json:"value"`
	Label string `json:"label"`
}

// Page groups fields by the Flutter screen they belong to.
type Page struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Screen      string   `json:"screen"` // Flutter source file
	Description string   `json:"description"`
	Static      []string `json:"static"` // elements of this screen that stay in code, with the reason
}

var bannerActions = []Option{
	{Value: "profil", Label: "Buka tab Profil"},
	{Value: "keamanan", Label: "Buka Pengaturan Keamanan"},
	{Value: "none", Label: "Tidak ada aksi"},
}

// Pages lists the Flutter screens with managed content (in app order).
var Pages = []Page{
	{ID: "umum", Name: "Umum (beberapa layar)", Screen: "lib/core/services/dynamic_config_service.dart",
		Description: "Elemen yang dipakai di lebih dari satu layar.",
		Static:      []string{"Warna, font, ikon, dan tata letak — bagian dari desain aplikasi (Flutter)."}},
	{ID: "splash", Name: "Layar Splash", Screen: "lib/presentation/screens/splash/splash_screen.dart",
		Description: "Layar pertama saat aplikasi dibuka.",
		Static:      []string{"Teks versi aplikasi (\"DMB Mobile v…\") — berasal dari build aplikasi, bukan konten."}},
	{ID: "onboarding", Name: "Tampilan Awal (Onboarding)", Screen: "lib/presentation/screens/onboarding/onboarding_screen.dart",
		Description: "Dua slide pengenalan sebelum Syarat & Ketentuan.",
		Static:      []string{"Jumlah slide (2) dan pergantian otomatis — struktur layar."}},
	{ID: "terms", Name: "Syarat & Ketentuan (halaman)", Screen: "lib/presentation/screens/auth/terms_conditions_screen.dart",
		Description: "Judul halaman. Isi dokumen, versi, dan pernyataan persetujuan dikelola di menu Syarat & Ketentuan.",
		Static:      []string{"Tombol \"Setuju & Lanjutkan\" dan aturan aktifnya — bagian dari alur persetujuan yang dicatat backend."}},
	{ID: "login", Name: "Login", Screen: "lib/presentation/screens/auth/login_screen.dart",
		Description: "Layar masuk nasabah dan panel bantuan.",
		Static: []string{
			"Kolom nomor HP/kata sandi, tombol Login, Lupa Password?, Daftar Akun, Ingat Saya, dan pesan validasi — kontrol autentikasi.",
			"Login biometrik — fungsi keamanan perangkat.",
		}},
	{ID: "home", Name: "Beranda", Screen: "lib/presentation/screens/home/home_screen.dart",
		Description: "Sapaan dan carousel banner (3 slot yang ada di aplikasi).",
		Static: []string{
			"Kartu rekening, saldo, nomor rekening — data nasabah dari Core Banking.",
			"Menu utama (Transfer, Mutasi, Pinjaman, Deposito, Katalog) dan navigasi bawah — navigasi fitur.",
			"Gambar template kartu rekening — teks saldo ditempatkan di atasnya; mengganti gambar dapat membuat saldo tidak terbaca.",
		}},
	{ID: "helpdesk", Name: "Pusat Bantuan", Screen: "lib/presentation/screens/helpdesk/helpdesk_screen.dart",
		Description: "Teks kanal layanan. Nomor dan alamat diambil dari Kontak Layanan.",
		Static:      []string{"Tombol salin nomor/email — fungsi aplikasi."}},
	{ID: "kontak", Name: "Kontak Layanan", Screen: "lib/core/constants/bank_contact.dart",
		Description: "Dipakai panel bantuan Login, Pusat Bantuan, dan kapsul keamanan Beranda. Wajib berisi kontak resmi bank.",
		Static:      []string{}},
}

// Fields is the registry (keys are stable identifiers shared with the Flutter app).
var Fields = []Field{
	{Key: "app.logo", Page: "umum", Group: "Identitas", Label: "Logo bank", Used: "Splash, Onboarding, Login", Type: TypeImage, Max: 300,
		Help: "Kosong = logo bawaan aplikasi. PNG/JPG/WebP maks. 5 MB."},
	{Key: "app.announcement", Page: "umum", Group: "Pengumuman", Label: "Teks pengumuman", Used: "Login, Beranda", Type: TypeMultiline, Max: 300,
		Help: "Kosong = pengumuman tidak ditampilkan."},

	{Key: "splash.background", Page: "splash", Group: "Gambar", Label: "Gambar latar splash", Used: "SplashScreen", Type: TypeImage, Max: 300,
		Help: "Kosong = artwork bawaan aplikasi."},
	{Key: "splash.tagline", Page: "splash", Group: "Teks", Label: "Tagline", Used: "SplashScreen", Type: TypeText, Max: 120, Required: true,
		Default: "Sahabat Finansial Terpercaya Anda"},
	{Key: "splash.loading_text", Page: "splash", Group: "Teks", Label: "Teks pemuatan", Used: "SplashScreen", Type: TypeText, Max: 80, Required: true,
		Default: "Memuat layanan perbankan..."},
	{Key: "splash.disclaimer", Page: "splash", Group: "Teks", Label: "Pernyataan regulator (OJK/LPS)", Used: "SplashScreen", Type: TypeMultiline, Max: 300, Required: true,
		Help:    "Wajib sesuai status izin resmi bank (ditinjau Kepatuhan).",
		Default: "PT BPR Dana Mandiri Bogor berizin dan diawasi oleh Otoritas Jasa Keuangan (OJK) serta merupakan peserta penjaminan Lembaga Penjamin Simpanan (LPS)."},

	{Key: "onboarding.slide1_title", Page: "onboarding", Group: "Slide 1", Label: "Judul", Used: "OnboardingScreen", Type: TypeText, Max: 120, Required: true,
		Default: "Jadi bestie di dunia finansial anak dengan DMB Mobile"},
	{Key: "onboarding.slide1_desc", Page: "onboarding", Group: "Slide 1", Label: "Deskripsi", Used: "OnboardingScreen", Type: TypeMultiline, Max: 250, Required: true,
		Default: "Dari uang jajan sampai target impian anak, semua bisa didampingi bersama orang tua secara transparan dan mudah."},
	{Key: "onboarding.slide1_image", Page: "onboarding", Group: "Slide 1", Label: "Gambar", Used: "OnboardingScreen", Type: TypeImage, Max: 300,
		Help: "Kosong = ilustrasi bawaan aplikasi."},
	{Key: "onboarding.slide2_title", Page: "onboarding", Group: "Slide 2", Label: "Judul", Used: "OnboardingScreen", Type: TypeText, Max: 120, Required: true,
		Default: "Wujudkan masa depan keluarga dengan tabungan cerdas"},
	{Key: "onboarding.slide2_desc", Page: "onboarding", Group: "Slide 2", Label: "Deskripsi", Used: "OnboardingScreen", Type: TypeMultiline, Max: 250, Required: true,
		Default: "Bebas biaya transfer, bunga deposito menguntungkan, dan proteksi transaksi berlapis dalam genggaman Anda."},
	{Key: "onboarding.slide2_image", Page: "onboarding", Group: "Slide 2", Label: "Gambar", Used: "OnboardingScreen", Type: TypeImage, Max: 300,
		Help: "Kosong = ilustrasi bawaan aplikasi."},
	{Key: "onboarding.button_text", Page: "onboarding", Group: "Tombol", Label: "Teks tombol", Used: "OnboardingScreen", Type: TypeText, Max: 30, Required: true,
		Default: "Mulai Sekarang"},

	{Key: "terms.headline", Page: "terms", Group: "Teks", Label: "Judul halaman", Used: "TermsConditionsScreen", Type: TypeMultiline, Max: 200, Required: true,
		Default: "Ringkasan Informasi dan Syarat Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor"},
	{Key: "terms.instruction", Page: "terms", Group: "Teks", Label: "Instruksi", Used: "TermsConditionsScreen", Type: TypeMultiline, Max: 300, Required: true,
		Default: "Baca dan setujui Ringkasan Informasi serta Syarat dan Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor."},

	{Key: "login.background", Page: "login", Group: "Gambar", Label: "Gambar latar", Used: "LoginScreen", Type: TypeImage, Max: 300,
		Help: "Kosong = artwork bawaan aplikasi."},
	{Key: "login.title", Page: "login", Group: "Teks", Label: "Judul", Used: "LoginScreen", Type: TypeText, Max: 80, Required: true,
		Default: "Selamat Datang"},
	{Key: "login.subtitle", Page: "login", Group: "Teks", Label: "Subjudul", Used: "LoginScreen", Type: TypeMultiline, Max: 150, Required: true,
		Default: "Login untuk melanjutkan\nke layanan DMB Mobile"},
	{Key: "login.footer", Page: "login", Group: "Teks", Label: "Teks bawah", Used: "LoginScreen", Type: TypeText, Max: 80, Required: true,
		Default: "Transaksi Anda aman bersama DMB"},
	{Key: "login.help_badge", Page: "login", Group: "Panel bantuan", Label: "Label panel", Used: "LoginScreen (Pusat Bantuan)", Type: TypeText, Max: 40, Required: true,
		Default: "Layanan Resmi 24 Jam"},
	{Key: "login.help_title", Page: "login", Group: "Panel bantuan", Label: "Judul panel", Used: "LoginScreen (Pusat Bantuan)", Type: TypeText, Max: 60, Required: true,
		Default: "Pusat Bantuan Bank DMB"},
	{Key: "login.help_subtitle", Page: "login", Group: "Panel bantuan", Label: "Subjudul panel", Used: "LoginScreen (Pusat Bantuan)", Type: TypeText, Max: 120, Required: true,
		Default: "Butuh bantuan? Tim kami siap melayani Anda."},
	{Key: "login.security_title", Page: "login", Group: "Panel bantuan", Label: "Judul peringatan keamanan", Used: "LoginScreen (Pusat Bantuan)", Type: TypeText, Max: 60, Required: true,
		Default: "PENTING: JAGA KERAHASIAAN ANDA"},
	{Key: "login.security_text", Page: "login", Group: "Panel bantuan", Label: "Teks peringatan keamanan", Used: "LoginScreen (Pusat Bantuan)", Type: TypeMultiline, Max: 250, Required: true,
		Default: "Petugas Bank DMB TIDAK PERNAH meminta Kata Sandi, PIN, atau Kode OTP Anda melalui kanal apa pun."},

	{Key: "home.greeting_title", Page: "home", Group: "Sapaan", Label: "Sapaan", Used: "HomeScreen", Type: TypeText, Max: 40, Required: true,
		Default: "Selamat Datang,"},
	{Key: "home.greeting_subtitle", Page: "home", Group: "Sapaan", Label: "Kalimat sapaan", Used: "HomeScreen", Type: TypeText, Max: 120, Required: true,
		Default: "Semoga harimu menyenangkan!"},
}

func init() {
	defaults := [3][3]string{
		{"DMB Mobile", "Lebih Mudah, Lebih Dekat dengan Anda", "profil"},
		{"Tabungan Mikro DMB", "Simpanan dijamin LPS sesuai ketentuan", "profil"},
		{"Keamanan Berlapis", "PIN transaksi & perangkat terdaftar", "keamanan"},
	}
	for i, d := range defaults {
		n := string(rune('1' + i))
		g := "Banner " + n
		Fields = append(Fields,
			Field{Key: "home.banner" + n + "_visible", Page: "home", Group: g, Label: "Tampilkan", Used: "HomeScreen (carousel)", Type: TypeBool, Max: 5, Required: true, Default: "true"},
			Field{Key: "home.banner" + n + "_title", Page: "home", Group: g, Label: "Judul", Used: "HomeScreen (carousel)", Type: TypeText, Max: 60, Required: true, Default: d[0]},
			Field{Key: "home.banner" + n + "_subtitle", Page: "home", Group: g, Label: "Subjudul", Used: "HomeScreen (carousel)", Type: TypeText, Max: 100, Required: true, Default: d[1]},
			Field{Key: "home.banner" + n + "_image", Page: "home", Group: g, Label: "Gambar (16:9)", Used: "HomeScreen (carousel)", Type: TypeImage, Max: 300,
				Help: "Kosong = gambar bawaan aplikasi."},
			Field{Key: "home.banner" + n + "_action", Page: "home", Group: g, Label: "Aksi saat diketuk", Used: "HomeScreen (carousel)", Type: TypeEnum, Max: 20, Required: true,
				Default: d[2], Options: bannerActions, Help: "Hanya tujuan yang sudah ada di aplikasi."},
		)
	}
	Fields = append(Fields,
		Field{Key: "helpdesk.intro_title", Page: "helpdesk", Group: "Teks", Label: "Judul", Used: "HelpdeskScreen", Type: TypeText, Max: 60, Required: true, Default: "Butuh Bantuan?"},
		Field{Key: "helpdesk.intro_text", Page: "helpdesk", Group: "Teks", Label: "Deskripsi", Used: "HelpdeskScreen", Type: TypeMultiline, Max: 200, Required: true,
			Default: "Tim Customer Care Bank DMB siap melayani Anda melalui kanal komunikasi resmi."},
		Field{Key: "helpdesk.call_center_desc", Page: "helpdesk", Group: "Kanal", Label: "Keterangan Call Center", Used: "HelpdeskScreen", Type: TypeText, Max: 100, Required: true,
			Default: "Layanan bebas pulsa untuk nasabah aktif"},
		Field{Key: "helpdesk.whatsapp_desc", Page: "helpdesk", Group: "Kanal", Label: "Keterangan WhatsApp", Used: "HelpdeskScreen", Type: TypeText, Max: 100, Required: true,
			Default: "Akun bisnis resmi terverifikasi dengan centang hijau"},
		Field{Key: "helpdesk.email_desc", Page: "helpdesk", Group: "Kanal", Label: "Keterangan Email", Used: "HelpdeskScreen", Type: TypeText, Max: 100, Required: true,
			Default: "Dukungan surat elektronik resmi Bank DMB"},

		Field{Key: "contact.call_center_display", Page: "kontak", Group: "Call Center", Label: "Nomor ditampilkan", Used: "Login, Pusat Bantuan, Beranda", Type: TypeText, Max: 30, Required: true, Default: "(0251) 832-1234"},
		Field{Key: "contact.call_center_dial", Page: "kontak", Group: "Call Center", Label: "Nomor untuk disalin", Used: "Login, Pusat Bantuan", Type: TypePhone, Max: 20, Required: true, Default: "02518321234"},
		Field{Key: "contact.whatsapp_display", Page: "kontak", Group: "WhatsApp", Label: "Nomor ditampilkan", Used: "Login, Pusat Bantuan, Beranda", Type: TypeText, Max: 30, Required: true, Default: "0811-9988-7766"},
		Field{Key: "contact.whatsapp_dial", Page: "kontak", Group: "WhatsApp", Label: "Nomor untuk disalin", Used: "Login, Pusat Bantuan", Type: TypePhone, Max: 20, Required: true, Default: "081199887766"},
		Field{Key: "contact.email", Page: "kontak", Group: "Email", Label: "Email layanan", Used: "Login, Pusat Bantuan", Type: TypeEmail, Max: 100, Required: true, Default: "layanan@bprdanamandiri.co.id"},
		Field{Key: "contact.office_short", Page: "kontak", Group: "Kantor", Label: "Alamat singkat", Used: "Login", Type: TypeText, Max: 100, Required: true, Default: "Jl. Pajajaran No. 88, Bogor"},
		Field{Key: "contact.office_address", Page: "kontak", Group: "Kantor", Label: "Alamat lengkap", Used: "Pusat Bantuan", Type: TypeMultiline, Max: 200, Required: true,
			Default: "Jl. Pajajaran No. 88, Kota Bogor, Jawa Barat 16128"},
		Field{Key: "contact.office_hours", Page: "kontak", Group: "Kantor", Label: "Jam layanan", Used: "Pusat Bantuan", Type: TypeText, Max: 80, Required: true, Default: "Senin - Jumat (08.00 - 15.30 WIB)"},
	)
	fieldIndex = map[string]*Field{}
	for i := range Fields {
		fieldIndex[Fields[i].Key] = &Fields[i]
	}
}

var fieldIndex map[string]*Field

// FieldByKey returns the registry entry.
func FieldByKey(k string) (*Field, bool) {
	f, ok := fieldIndex[k]
	return f, ok
}

// legacyColumns maps keys to app_configs columns still read by older app builds
// (GET /api/v1/config). Published values are mirrored there.
var legacyColumns = map[string]string{
	"app.logo":                    "logo_url",
	"app.announcement":            "announcement_text",
	"splash.tagline":              "tagline",
	"login.background":            "login_bg_url",
	"login.title":                 "login_title",
	"login.subtitle":              "login_subtitle",
	"home.greeting_subtitle":      "home_greeting",
	"contact.call_center_display": "call_center",
	"contact.whatsapp_display":    "whats_app_cs",
}
