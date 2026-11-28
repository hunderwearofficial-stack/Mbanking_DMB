package mobilecontent

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

type Option struct {
	Value string `json:"value"`
	Label string `json:"label"`
}

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

var Pages = []Page{
	{ID: "umum", Name: "Umum (beberapa layar)", Screen: "lib/core/services/dynamic_config_service.dart",
		Description: "Elemen yang dipakai di lebih dari satu layar.",
		Static:      []string{"Warna, font, ikon, dan tata letak — bagian dari desain aplikasi (Flutter)."}},
	{ID: "splash", Name: "Layar Splash", Screen: "lib/presentation/screens/splash/splash_screen.dart",
		Description: "Layar pertama saat aplikasi dibuka.",
		Static: []string{
			"Gambar latar gedung (splash_building.jpg) dan logo animasi DMB — dibundel langsung di aplikasi.",
			"Teks versi aplikasi (\"DMB Mobile v…\") — berasal dari build aplikasi, bukan konten.",
		}},
	{ID: "onboarding", Name: "Tampilan Awal (Onboarding)", Screen: "lib/presentation/screens/onboarding/onboarding_screen.dart",
		Description: "Layar sambutan penuh sebelum nasabah masuk.",
		Static: []string{
			"Tombol Masuk Sekarang mengarah ke Syarat & Ketentuan (jika belum disetujui) lalu ke Login.",
		}},
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
			"Menu utama (Mutasi, Pinjaman, Deposito, Katalog) dan navigasi bawah — navigasi fitur.",
			"Gambar template kartu rekening — teks saldo ditempatkan di atasnya; mengganti gambar dapat membuat saldo tidak terbaca.",
		}},
	{ID: "helpdesk", Name: "Pusat Bantuan", Screen: "lib/presentation/screens/helpdesk/helpdesk_screen.dart",
		Description: "Teks kanal layanan. Nomor dan alamat diambil dari Kontak Layanan.",
		Static:      []string{"Tombol salin nomor/email — fungsi aplikasi."}},
	{ID: "kontak", Name: "Kontak Layanan", Screen: "lib/core/constants/bank_contact.dart",
		Description: "Dipakai panel bantuan Login, Pusat Bantuan, dan kapsul keamanan Beranda. Wajib berisi kontak resmi bank.",
		Static:      []string{}},
	{ID: "produk", Name: "Parameter Produk & Profil", Screen: "lib/presentation/screens/products/products_catalog_screen.dart",
		Description: "Parameter simulasi deposito/pinjaman dan profil perusahaan yang ditampilkan pada aplikasi.",
		Static:      []string{"Data rekening aktif dan produk riil berasal dari layanan perbankan inti."}},
}

var Fields = []Field{
	{Key: "app.logo", Page: "umum", Group: "Identitas", Label: "Logo bank", Used: "Splash, Onboarding, Login", Type: TypeImage, Max: 300,
		Help: "Kosong = logo bawaan aplikasi. PNG/JPG/WebP maks. 5 MB."},
	{Key: "app.announcement", Page: "umum", Group: "Pengumuman", Label: "Teks pengumuman", Used: "Login, Beranda", Type: TypeMultiline, Max: 300,
		Help: "Kosong = pengumuman tidak ditampilkan."},
	{Key: "app.footer", Page: "umum", Group: "Footer", Label: "Teks footer / regulator (OJK & LPS)", Used: "Splash, Login, Aktivasi, Lupa & Reset Password", Type: TypeMultiline, Max: 300, Required: true,
		Help:    "Tampil di bagian bawah layar Splash, Login, Aktivasi, Lupa & Reset Password.",
		Default: "Bank DMB berizin dan diawasi oleh Otoritas Jasa Keuangan (OJK) serta merupakan peserta penjaminan Lembaga Penjamin Simpanan (LPS)."},

	{Key: "splash.tagline", Page: "splash", Group: "Teks", Label: "Tagline", Used: "SplashScreen", Type: TypeText, Max: 120, Required: true,
		Default: "Sahabat Finansial Terpercaya Anda"},

	{Key: "onboarding.background", Page: "onboarding", Group: "Gambar", Label: "Foto latar onboarding", Used: "OnboardingScreen", Type: TypeImage, Max: 300,
		Help:    "Foto 9:16 dari server. PNG/JPG/WebP maks. 5 MB.",
		Default: "/admin/uploads/onboarding_hero.jpg"},
	{Key: "onboarding.title", Page: "onboarding", Group: "Teks", Label: "Judul utama", Used: "OnboardingScreen", Type: TypeText, Max: 120, Required: true,
		Default: "Selamat datang di Bank DMB"},
	{Key: "onboarding.subtitle", Page: "onboarding", Group: "Teks", Label: "Subjudul", Used: "OnboardingScreen", Type: TypeMultiline, Max: 250, Required: true,
		Default: "Pantau saldo tabungan, mutasi rekening, deposito, dan pinjaman Anda secara aman dan real-time."},
	{Key: "onboarding.button_text", Page: "onboarding", Group: "Tombol", Label: "Teks tombol masuk", Used: "OnboardingScreen", Type: TypeText, Max: 30, Required: true,
		Default: "Masuk Sekarang"},

	{Key: "terms.headline", Page: "terms", Group: "Teks", Label: "Judul halaman", Used: "TermsConditionsScreen", Type: TypeMultiline, Max: 200, Required: true,
		Default: "Ringkasan Informasi dan Syarat Ketentuan Mobile Banking Bank DMB"},
	{Key: "terms.instruction", Page: "terms", Group: "Teks", Label: "Instruksi", Used: "TermsConditionsScreen", Type: TypeMultiline, Max: 300, Required: true,
		Default: "Baca dan setujui Ringkasan Informasi serta Syarat dan Ketentuan Mobile Banking Bank DMB."},

	{Key: "login.hero_slide1_badge", Page: "login", Group: "Hero Banner", Label: "Label slide 1", Used: "LoginScreen (Hero Slide 1)", Type: TypeText, Max: 50, Required: true,
		Default: "TABUNGAN DANA MANDIRI"},
	{Key: "login.hero_slide1_title", Page: "login", Group: "Hero Banner", Label: "Judul slide 1", Used: "LoginScreen (Hero Slide 1)", Type: TypeText, Max: 100, Required: true,
		Default: "Menabung aman, usaha makin lancar"},
	{Key: "login.hero_slide2_badge", Page: "login", Group: "Hero Banner", Label: "Label slide 2", Used: "LoginScreen (Hero Slide 2)", Type: TypeText, Max: 50, Required: true,
		Default: "DEPOSITO BERJANGKA"},
	{Key: "login.hero_slide2_title", Page: "login", Group: "Hero Banner", Label: "Judul slide 2", Used: "LoginScreen (Hero Slide 2)", Type: TypeText, Max: 100, Required: true,
		Default: "Imbal hasil kompetitif, dijamin LPS"},
	{Key: "login.hero_slide3_badge", Page: "login", Group: "Hero Banner", Label: "Label slide 3", Used: "LoginScreen (Hero Slide 3)", Type: TypeText, Max: 50, Required: true,
		Default: "LAYANAN DIGITAL"},
	{Key: "login.hero_slide3_title", Page: "login", Group: "Hero Banner", Label: "Judul slide 3", Used: "LoginScreen (Hero Slide 3)", Type: TypeText, Max: 100, Required: true,
		Default: "Pantau saldo dan mutasi kapan saja"},
	{Key: "login.title", Page: "login", Group: "Kartu Masuk", Label: "Judul", Used: "LoginScreen", Type: TypeText, Max: 80, Required: true,
		Default: "Selamat datang"},
	{Key: "login.subtitle", Page: "login", Group: "Kartu Masuk", Label: "Subjudul", Used: "LoginScreen", Type: TypeMultiline, Max: 150, Required: true,
		Default: "Masuk ke akun DMB Anda"},

	{Key: "home.greeting_title", Page: "home", Group: "Sapaan", Label: "Sapaan", Used: "HomeScreen", Type: TypeText, Max: 40, Required: true,
		Default: "Selamat datang,"},
	{Key: "home.greeting_subtitle", Page: "home", Group: "Sapaan", Label: "Kalimat sapaan", Used: "HomeScreen", Type: TypeText, Max: 120, Required: true,
		Default: "Semoga harimu lancar."},
	{Key: "home.greeting_note", Page: "home", Group: "Sapaan", Label: "Teks tambahan di bawah sapaan", Used: "HomeScreen", Type: TypeText, Max: 140, Required: false,
		Default: "Pantau saldo dan transaksi Anda dengan aman."},
	{Key: "home.info_section_title", Page: "home", Group: "Info untuk Anda", Label: "Judul bagian info", Used: "HomeScreen", Type: TypeText, Max: 40, Required: true,
		Default: "Info untuk Anda"},
}

func init() {
	defaults := [3][4]string{
		{"UNTUK ANDA", "DMB Mobile", "Lebih Mudah, Lebih Dekat dengan Anda", "profil"},
		{"INFO PRODUK", "Tabungan & Deposito DMB", "Simpanan dijamin LPS sesuai ketentuan", "profil"},
		{"KEAMANAN", "Keamanan Berlapis", "PIN & perangkat terdaftar terlindungi", "keamanan"},
	}
	for i, d := range defaults {
		n := string(rune('1' + i))
		g := "Kartu Info " + n
		Fields = append(Fields,
			Field{Key: "home.banner" + n + "_visible", Page: "home", Group: g, Label: "Tampilkan", Used: "HomeScreen (Info untuk Anda)", Type: TypeBool, Max: 5, Required: true, Default: "true"},
			Field{Key: "home.banner" + n + "_tag", Page: "home", Group: g, Label: "Label badge", Used: "HomeScreen (Info untuk Anda)", Type: TypeText, Max: 24, Required: true, Default: d[0]},
			Field{Key: "home.banner" + n + "_title", Page: "home", Group: g, Label: "Judul", Used: "HomeScreen (Info untuk Anda)", Type: TypeText, Max: 60, Required: true, Default: d[1]},
			Field{Key: "home.banner" + n + "_subtitle", Page: "home", Group: g, Label: "Subjudul", Used: "HomeScreen (Info untuk Anda)", Type: TypeText, Max: 100, Required: true, Default: d[2]},
			Field{Key: "home.banner" + n + "_image", Page: "home", Group: g, Label: "Gambar latar (opsional)", Used: "HomeScreen (Info untuk Anda)", Type: TypeImage, Max: 300,
				Default: map[string]string{"1": "/admin/uploads/home_promo_plant.jpg"}[n],
				Help:    "Kosong = kartu warna biru lembut resmi aplikasi. Ideal 1080x380 px (rasio 2,8:1)."},
			Field{Key: "home.banner" + n + "_action", Page: "home", Group: g, Label: "Aksi saat diketuk", Used: "HomeScreen (Info untuk Anda)", Type: TypeEnum, Max: 20, Required: true,
				Default: d[3], Options: bannerActions, Help: "Hanya tujuan yang sudah ada di aplikasi."},
		)
	}
	Fields = append(Fields,
		Field{Key: "helpdesk.intro_title", Page: "helpdesk", Group: "Teks", Label: "Judul", Used: "HelpdeskScreen", Type: TypeText, Max: 60, Required: true, Default: "Butuh Bantuan?"},
		Field{Key: "helpdesk.intro_text", Page: "helpdesk", Group: "Teks", Label: "Deskripsi", Used: "HelpdeskScreen", Type: TypeMultiline, Max: 200, Required: true,
			Default: "Tim Customer Care Bank DMB siap melayani Anda melalui kanal komunikasi resmi."},
		Field{Key: "helpdesk.call_center_desc", Page: "helpdesk", Group: "Kanal", Label: "Keterangan Call Center", Used: "HelpdeskScreen", Type: TypeText, Max: 100, Required: true,
			Default: "Layanan bebas pulsa untuk nasabah aktif"},
		Field{Key: "helpdesk.email_desc", Page: "helpdesk", Group: "Kanal", Label: "Keterangan Email", Used: "HelpdeskScreen", Type: TypeText, Max: 100, Required: true,
			Default: "Dukungan surat elektronik resmi Bank DMB"},

		Field{Key: "contact.call_center_display", Page: "kontak", Group: "Call Center", Label: "Nomor ditampilkan", Used: "Login, Pusat Bantuan, Beranda", Type: TypeText, Max: 30, Required: true, Default: "(0251) 832-1234"},
		Field{Key: "contact.call_center_dial", Page: "kontak", Group: "Call Center", Label: "Nomor untuk disalin", Used: "Login, Pusat Bantuan", Type: TypePhone, Max: 20, Required: true, Default: "02518321234"},
		Field{Key: "contact.email", Page: "kontak", Group: "Email", Label: "Email layanan", Used: "Login, Pusat Bantuan", Type: TypeEmail, Max: 100, Required: true, Default: "layanan@bprdanamandiri.co.id"},
		Field{Key: "contact.office_short", Page: "kontak", Group: "Kantor", Label: "Alamat singkat", Used: "Login", Type: TypeText, Max: 100, Required: true, Default: "Jl. Pajajaran No. 88, Bogor"},
		Field{Key: "contact.office_address", Page: "kontak", Group: "Kantor", Label: "Alamat lengkap", Used: "Pusat Bantuan", Type: TypeMultiline, Max: 200, Required: true,
			Default: "Jl. Pajajaran No. 88, Kota Bogor, Jawa Barat 16128"},
		Field{Key: "contact.office_hours", Page: "kontak", Group: "Kantor", Label: "Jam layanan", Used: "Pusat Bantuan", Type: TypeText, Max: 80, Required: true, Default: "Senin - Jumat (08.00 - 15.30 WIB)"},

		Field{Key: "product.deposito_rate_bps", Page: "produk", Group: "Simulasi Deposito", Label: "Bunga deposito (bps)", Used: "DepositsScreen, ProductsCatalogScreen", Type: TypeText, Max: 10, Required: true, Default: "625"},
		Field{Key: "product.deposito_rate_label", Page: "produk", Group: "Simulasi Deposito", Label: "Label bunga deposito", Used: "DepositsScreen, ProductsCatalogScreen", Type: TypeText, Max: 40, Required: true, Default: "6,25% p.a."},
		Field{Key: "product.deposito_min_amount", Page: "produk", Group: "Simulasi Deposito", Label: "Nominal minimum deposito", Used: "DepositsScreen, ProductsCatalogScreen", Type: TypeText, Max: 20, Required: true, Default: "1000000"},
		Field{Key: "product.deposito_max_amount", Page: "produk", Group: "Simulasi Deposito", Label: "Nominal maksimum deposito", Used: "DepositsScreen, ProductsCatalogScreen", Type: TypeText, Max: 20, Required: true, Default: "250000000"},
		Field{Key: "product.deposito_tax_threshold", Page: "produk", Group: "Simulasi Deposito", Label: "Batas kena pajak deposito", Used: "DepositsScreen, ProductsCatalogScreen", Type: TypeText, Max: 20, Required: true, Default: "7500000"},
		Field{Key: "product.deposito_tax_percent", Page: "produk", Group: "Simulasi Deposito", Label: "Persentase pajak deposito", Used: "DepositsScreen, ProductsCatalogScreen", Type: TypeText, Max: 5, Required: true, Default: "20"},
		Field{Key: "product.loan_rate_bps", Page: "produk", Group: "Simulasi Pinjaman", Label: "Bunga pinjaman tahunan (bps)", Used: "LoansScreen, ProductsCatalogScreen", Type: TypeText, Max: 10, Required: true, Default: "1500"},
		Field{Key: "product.loan_rate_label", Page: "produk", Group: "Simulasi Pinjaman", Label: "Label bunga pinjaman", Used: "LoansScreen, ProductsCatalogScreen", Type: TypeText, Max: 40, Required: true, Default: "1,25% flat/bln"},
		Field{Key: "product.loan_min_amount", Page: "produk", Group: "Simulasi Pinjaman", Label: "Nominal minimum pinjaman", Used: "LoansScreen, ProductsCatalogScreen", Type: TypeText, Max: 20, Required: true, Default: "5000000"},
		Field{Key: "product.loan_max_amount", Page: "produk", Group: "Simulasi Pinjaman", Label: "Nominal maksimum pinjaman", Used: "LoansScreen, ProductsCatalogScreen", Type: TypeText, Max: 20, Required: true, Default: "250000000"},
		Field{Key: "company.hero_image", Page: "produk", Group: "Profil Perusahaan", Label: "Foto gedung / latar profil bank", Used: "CompanyProfileScreen", Type: TypeImage, Max: 300,
			Help: "Kosong = gradien navy bawaan."},
		Field{Key: "company.hero_title", Page: "produk", Group: "Profil Perusahaan", Label: "Judul utama profil bank", Used: "CompanyProfileScreen", Type: TypeText, Max: 100, Required: true,
			Default: "Mitra Keuangan UMKM Bogor Sejak 1989"},
		Field{Key: "company.established_year", Page: "produk", Group: "Profil Perusahaan", Label: "Tahun berdiri bank", Used: "CompanyProfileScreen", Type: TypeText, Max: 10, Required: true,
			Default: "1989"},
		Field{Key: "company.branches", Page: "produk", Group: "Profil Perusahaan", Label: "Daftar kantor layanan (1 baris per kantor: Nama | Alamat)", Used: "CompanyProfileScreen", Type: TypeMultiline, Max: 2000, Required: true,
			Help:    "Format tiap baris: Nama Kantor | Alamat Lengkap",
			Default: "Kantor Pusat Bogor | Jl Raya Puncak Ciawi No 402, Kel. Bendungan Kec. Ciawi Kab. Bogor, Jawa Barat 16720\nKantor Pusat Sukabumi | Jl. Raya Cikukulu RT. 019 RW. 005 Desa Cisande, Kec. Cicantayan Kab. Sukabumi, Jawa Barat 43155\nKantor Pusat Cianjur | Jl. Raya Cianjur - Bandung RT. 001 RW. 006 No. 7 - 8, Desa Babakancaringin Kec. Karangtengah Kab. Cianjur, Jawa Barat 43281\nKantor Pusat Tangerang Selatan | Ruko Harvest Bintaro Residence No. 27-28, Jl. Merpati Raya Ciputat, Tangerang Selatan, Banten 15413"},
		Field{Key: "company.about_description", Page: "produk", Group: "Profil Perusahaan", Label: "Deskripsi tentang bank", Used: "AboutBankScreen", Type: TypeMultiline, Max: 600, Required: true,
			Default: "Bank DMB berawal di Bogor sebagai BPR yang melayani pedagang pasar dan pengusaha mikro. Fokus kami tetap sama hingga kini: Akses modal usaha yang mudah dan simpanan yang aman, diawasi OJK dan dijamin LPS."},
		Field{Key: "company.vision", Page: "produk", Group: "Profil Perusahaan", Label: "Visi bank", Used: "AboutBankScreen", Type: TypeMultiline, Max: 300, Required: true,
			Default: "Menjadi penyedia layanan keuangan mikro yang terpercaya bagi bangsa, menjadikan kehidupan dan masa depan yang lebih baik."},
		Field{Key: "company.mission", Page: "produk", Group: "Profil Perusahaan", Label: "Misi bank", Used: "AboutBankScreen", Type: TypeMultiline, Max: 500, Required: true,
			Default: "Menjadi mitra pilihan bagi micro-productive segmen yang menjunjung nilai-nilai organisasi dalam memberikan kualitas pelayanan yang handal dan secara bersama menciptakan kesempatan tumbuh dan berkembang."},
		Field{Key: "company.lps_guarantee_text", Page: "produk", Group: "Profil Perusahaan", Label: "Pernyataan penjaminan LPS", Used: "AboutBankScreen, ProductsCatalogScreen", Type: TypeMultiline, Max: 300, Required: true,
			Default: "Simpanan nasabah pada BPR dijamin oleh Lembaga Penjamin Simpanan (LPS) hingga Rp 2 Miliar per nasabah pada satu bank sesuai dengan syarat dan ketentuan yang berlaku."},
	)
	fieldIndex = map[string]*Field{}
	for i := range Fields {
		fieldIndex[Fields[i].Key] = &Fields[i]
	}
}

var fieldIndex map[string]*Field

func FieldByKey(k string) (*Field, bool) {
	f, ok := fieldIndex[k]
	return f, ok
}

var legacyColumns = map[string]string{
	"app.logo":                    "logo_url",
	"app.announcement":            "announcement_text",
	"splash.tagline":              "tagline",
	"login.title":                 "login_title",
	"login.subtitle":              "login_subtitle",
	"home.greeting_subtitle":      "home_greeting",
	"contact.call_center_display": "call_center",
	"contact.email":               "email_cs",
	"contact.office_address":      "head_office_address",
}
