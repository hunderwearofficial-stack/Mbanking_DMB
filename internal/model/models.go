package model

import (
	"mbanking-bpr/pkg/money"
	"time"

	"mbanking-bpr/pkg/crypto"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

const (
	TxTypeDebit  = "DEBIT"
	TxTypeCredit = "CREDIT"

	AccountStatusActive  = "Active"
	AccountStatusBlocked = "Blocked"

	AdminRoleSuperAdmin = "SUPER_ADMIN"
	AdminRoleCS         = "CS"
	AdminRoleMarketing  = "MARKETING"
	AdminRoleCompliance = "COMPLIANCE" // read-only audit & compliance monitoring
)

func IsValidAdminRole(role string) bool {
	switch role {
	case AdminRoleSuperAdmin, AdminRoleCS, AdminRoleMarketing, AdminRoleCompliance:
		return true
	}
	return false
}

type User struct {
	ID                  string                 `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	CIF                 string                 `json:"cif" gorm:"type:varchar(20);uniqueIndex;not null;column:cif"`
	FullName            string                 `json:"full_name" gorm:"type:varchar(100);not null;column:full_name"`
	Username            string                 `json:"username" gorm:"type:varchar(50);column:username"`
	PhoneNumber         string                 `json:"phone_number" gorm:"type:varchar(20);uniqueIndex;not null;column:phone_number"`
	Email               crypto.EncryptedString `json:"email" gorm:"type:text;column:email"`
	KodePos             string                 `json:"kode_pos" gorm:"type:varchar(50);column:kode_pos"`
	JenisKelamin        string                 `json:"jenis_kelamin" gorm:"type:varchar(50);column:jenis_kelamin"`
	Agama               string                 `json:"agama" gorm:"type:varchar(255);column:agama"`
	TglLahir            crypto.EncryptedString `json:"tgl_lahir" gorm:"type:text;column:tgl_lahir"`
	TempatLahir         crypto.EncryptedString `json:"tempat_lahir" gorm:"type:text;column:tempat_lahir"`
	NamaIbuKandung      crypto.EncryptedString `json:"nama_ibu_kandung" gorm:"type:text;column:nama_ibu_kandung"`
	PasswordHash        string                 `json:"-" gorm:"type:varchar(255);not null"`
	PINHash             string                 `json:"-" gorm:"type:varchar(255);not null"`
	DeviceID            string                 `json:"device_id" gorm:"type:varchar(128);index"`
	FailedLoginAttempts int                    `json:"failed_login_attempts" gorm:"type:int;default:0;column:failed_login_attempts"`
	FailedPINAttempts   int                    `json:"failed_pin_attempts" gorm:"type:int;default:0;column:failed_pin_attempts"`
	IsActive            bool                   `json:"is_active" gorm:"type:boolean;default:true"`
	CreatedAt           time.Time              `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt           time.Time              `json:"updated_at" gorm:"autoUpdateTime"`

	Accounts []Account `json:"accounts,omitempty" gorm:"foreignKey:UserID;references:ID;constraint:OnDelete:CASCADE"`
}

func (u *User) BeforeCreate(tx *gorm.DB) error {
	if u.ID == "" {
		u.ID = uuid.NewString()
	}
	return nil
}

type Account struct {
	ID               string       `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID           string       `json:"user_id" gorm:"type:uuid;index;not null"`
	AccountNumber    string       `json:"account_number" gorm:"type:varchar(100);uniqueIndex;not null"`
	HolderName       string       `json:"holder_name" gorm:"type:varchar(100);column:holder_name"`
	ProductCode      string       `json:"product_code" gorm:"type:varchar(50);column:product_code"`
	AccountType      string       `json:"account_type" gorm:"type:varchar(255);default:'Savings'"`
	Balance          money.Amount `json:"balance" gorm:"type:decimal(15,2);not null;default:0"`
	MinimumBalance   money.Amount `json:"minimum_balance" gorm:"type:decimal(15,2);not null;default:0;column:minimum_balance"`
	BlockedBalance   money.Amount `json:"blocked_balance" gorm:"type:decimal(15,2);not null;default:0;column:blocked_balance"`
	EffectiveBalance money.Amount `json:"effective_balance" gorm:"type:decimal(15,2);not null;default:0;column:effective_balance"`
	Status           string       `json:"status" gorm:"type:varchar(20);default:'Active'"`
	CreatedAt        time.Time    `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt        time.Time    `json:"updated_at" gorm:"autoUpdateTime"`

	User      *User      `json:"user,omitempty" gorm:"foreignKey:UserID;references:ID"`
	Mutations []Mutation `json:"mutations,omitempty" gorm:"foreignKey:AccountNumber;references:AccountNumber"`
}

func (a *Account) BeforeCreate(tx *gorm.DB) error {
	if a.ID == "" {
		a.ID = uuid.NewString()
	}
	return nil
}

type Mutation struct {
	ID              string       `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	AccountNumber   string       `json:"account_number" gorm:"type:varchar(100);index;not null"`
	TransactionType string       `json:"transaction_type" gorm:"type:varchar(10);not null"` // DEBIT, CREDIT
	Amount          money.Amount `json:"amount" gorm:"type:decimal(15,2);not null"`
	BalanceAfter    money.Amount `json:"balance_after" gorm:"type:decimal(15,2);not null"`
	Description     string       `json:"description" gorm:"type:varchar(255);not null"`
	ReferenceNumber string       `json:"reference_number" gorm:"type:varchar(50);uniqueIndex;not null"`
	CreatedAt       time.Time    `json:"created_at" gorm:"autoCreateTime"`
}

func (m *Mutation) BeforeCreate(tx *gorm.DB) error {
	if m.ID == "" {
		m.ID = uuid.NewString()
	}
	return nil
}

type AdminUser struct {
	ID           string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Username     string    `json:"username" gorm:"type:varchar(50);uniqueIndex;not null"`
	FullName     string    `json:"full_name" gorm:"type:varchar(100);not null"`
	Email        string    `json:"email" gorm:"type:varchar(100)"`
	PasswordHash string    `json:"-" gorm:"type:varchar(255);not null"`
	Role         string    `json:"role" gorm:"type:varchar(30);not null"` // SUPER_ADMIN, CS, MARKETING, COMPLIANCE
	IsActive     bool      `json:"is_active" gorm:"type:boolean;default:true"`
	CreatedAt    time.Time `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt    time.Time `json:"updated_at" gorm:"autoUpdateTime"`

	// SECURITY (audit E-01): officer MFA (TOTP) and per-account lockout. The TOTP secret is
	// AES-GCM encrypted (pkg/crypto) and never serialised.
	TOTPSecret          string     `json:"-" gorm:"column:totp_secret;type:text"`
	TOTPEnabled         bool       `json:"totp_enabled" gorm:"column:totp_enabled;default:false"`
	TOTPLastStep        int64      `json:"-" gorm:"column:totp_last_step;default:0"`
	FailedLoginAttempts int        `json:"failed_login_attempts" gorm:"column:failed_login_attempts;default:0"`
	LockedUntil         *time.Time `json:"locked_until,omitempty" gorm:"column:locked_until"`
}

func (a *AdminUser) BeforeCreate(tx *gorm.DB) error {
	if a.ID == "" {
		a.ID = uuid.NewString()
	}
	return nil
}

type Banner struct {
	ID           string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Title        string    `json:"title" gorm:"type:varchar(120);not null"`
	ImageURL     string    `json:"image_url" gorm:"type:text;not null"`
	TargetUrl    string    `json:"target_url" gorm:"type:varchar(255)"`
	Tag          string    `json:"tag" gorm:"type:varchar(60)"`
	Highlight    string    `json:"highlight" gorm:"type:varchar(255)"`
	BadgeText    string    `json:"badge_text" gorm:"type:varchar(50)"`
	BgColor      string    `json:"bg_color" gorm:"type:varchar(30);default:'#1E293B'"`
	AccentColor  string    `json:"accent_color" gorm:"type:varchar(30);default:'#16984B'"`
	IconName     string    `json:"icon_name" gorm:"type:varchar(50);default:'savings'"`
	IsActive     bool      `json:"is_active" gorm:"type:boolean;default:true"`
	DisplayOrder int       `json:"display_order" gorm:"type:int;default:0"`
	CreatedAt    time.Time `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt    time.Time `json:"updated_at" gorm:"autoUpdateTime"`
}

func (b *Banner) BeforeCreate(tx *gorm.DB) error {
	if b.ID == "" {
		b.ID = uuid.NewString()
	}
	return nil
}

type AppConfig struct {
	ID                   string    `json:"id" gorm:"primaryKey;type:varchar(50);default:'DEFAULT'"`
	BankName             string    `json:"bank_name" gorm:"type:varchar(120);default:'PT BPR DANA MANDIRI BOGOR'"`
	BankShortName        string    `json:"bank_short_name" gorm:"type:varchar(50);default:'Bank DMB'"`
	Tagline              string    `json:"tagline" gorm:"type:varchar(255);default:'Mitra Terpercaya Menuju Sejahtera'"`
	LogoURL              string    `json:"logo_url" gorm:"type:text"`
	LoginBgURL           string    `json:"login_bg_url" gorm:"type:text;column:login_bg_url"`
	SplashBgURL          string    `json:"splash_bg_url" gorm:"type:text;column:splash_bg_url"`
	OnboardingBgURL      string    `json:"onboarding_bg_url" gorm:"type:text;column:onboarding_bg_url"`
	WelcomeTitle         string    `json:"welcome_title" gorm:"type:varchar(150);default:'Selamat Datang di DMB Mobile';column:welcome_title"`
	WelcomeSubtitle      string    `json:"welcome_subtitle" gorm:"type:varchar(255);default:'Transaksi mudah, aman, dan tepercaya bersama BPR Dana Mandiri Bogor';column:welcome_subtitle"`
	LoginTitle           string    `json:"login_title" gorm:"type:varchar(150);default:'Masuk ke Akun M-Banking';column:login_title"`
	LoginSubtitle        string    `json:"login_subtitle" gorm:"type:varchar(255);default:'Silakan masukkan User ID dan Kata Sandi Anda';column:login_subtitle"`
	TermsVersion         string    `json:"terms_version" gorm:"type:varchar(50);default:'Versi 2.4 - Efektif 2026';column:terms_version"`
	HomeGreeting         string    `json:"home_greeting" gorm:"type:varchar(150);default:'Semoga harimu menyenangkan!';column:home_greeting"`
	AnnouncementText     string    `json:"announcement_text" gorm:"type:text;column:announcement_text"`
	TermsPdfURL          string    `json:"terms_pdf_url" gorm:"type:text;column:terms_pdf_url"`
	PrivacyPdfURL        string    `json:"privacy_pdf_url" gorm:"type:text;column:privacy_pdf_url"`
	QuickMenuConfig      string    `json:"quick_menu_config" gorm:"type:text;column:quick_menu_config"`
	CallCenter           string    `json:"call_center" gorm:"type:varchar(50)"`
	WhatsAppCS           string    `json:"whatsapp_cs" gorm:"type:varchar(50)"`
	EmailCS              string    `json:"email_cs" gorm:"type:varchar(100)"`
	WebsiteURL           string    `json:"website_url" gorm:"type:varchar(255)"`
	HeadOfficeAddress    string    `json:"head_office_address" gorm:"type:text"`
	MaintenanceMode      bool      `json:"maintenance_mode" gorm:"type:boolean;default:false"`
	MaintenanceMessage   string    `json:"maintenance_message" gorm:"type:varchar(255);default:'Sistem sedang dalam peningkatan layanan berkala.'"`
	ContentVersion       int       `json:"content_version" gorm:"column:content_version;default:0"`
	EnforceDeviceBinding bool      `json:"enforce_device_binding" gorm:"type:boolean;default:true"`
	MaxLoginAttempts     int       `json:"max_login_attempts" gorm:"type:int;default:3"`
	OTPProvider          string    `json:"otp_provider" gorm:"type:varchar(40);default:'SANDBOX'"` // SANDBOX, JATIS, SMS_GATEWAY
	OTPGatewayURL        string    `json:"otp_gateway_url" gorm:"type:varchar(255)"`
	OTPGatewayToken      string    `json:"-" gorm:"type:text"` // AES-GCM encrypted (audit E-08); legacy plaintext still readable
	UpdatedAt            time.Time `json:"updated_at" gorm:"autoUpdateTime"`
}

type PublicAppConfig struct {
	ContentVersion     int    `json:"content_version"`
	BankName           string `json:"bank_name"`
	BankShortName      string `json:"bank_short_name"`
	Tagline            string `json:"tagline"`
	LogoURL            string `json:"logo_url"`
	LoginBgURL         string `json:"login_bg_url"`
	SplashBgURL        string `json:"splash_bg_url"`
	OnboardingBgURL    string `json:"onboarding_bg_url"`
	WelcomeTitle       string `json:"welcome_title"`
	WelcomeSubtitle    string `json:"welcome_subtitle"`
	LoginTitle         string `json:"login_title"`
	LoginSubtitle      string `json:"login_subtitle"`
	TermsVersion       string `json:"terms_version"`
	HomeGreeting       string `json:"home_greeting"`
	AnnouncementText   string `json:"announcement_text"`
	TermsPdfURL        string `json:"terms_pdf_url"`
	PrivacyPdfURL      string `json:"privacy_pdf_url"`
	QuickMenuConfig    string `json:"quick_menu_config"`
	CallCenter         string `json:"call_center"`
	WhatsAppCS         string `json:"whatsapp_cs"`
	EmailCS            string `json:"email_cs"`
	WebsiteURL         string `json:"website_url"`
	HeadOfficeAddress  string `json:"head_office_address"`
	MaintenanceMode    bool   `json:"maintenance_mode"`
	MaintenanceMessage string `json:"maintenance_message"`
}

func (c *AppConfig) Public() PublicAppConfig {
	return PublicAppConfig{
		ContentVersion: c.ContentVersion,
		BankName:       c.BankName, BankShortName: c.BankShortName, Tagline: c.Tagline, LogoURL: c.LogoURL,
		LoginBgURL: c.LoginBgURL, SplashBgURL: c.SplashBgURL, OnboardingBgURL: c.OnboardingBgURL,
		WelcomeTitle: c.WelcomeTitle, WelcomeSubtitle: c.WelcomeSubtitle,
		LoginTitle: c.LoginTitle, LoginSubtitle: c.LoginSubtitle,
		TermsVersion: c.TermsVersion, HomeGreeting: c.HomeGreeting,
		AnnouncementText: c.AnnouncementText, TermsPdfURL: c.TermsPdfURL, PrivacyPdfURL: c.PrivacyPdfURL,
		QuickMenuConfig: c.QuickMenuConfig,
		CallCenter:      c.CallCenter, WhatsAppCS: c.WhatsAppCS, EmailCS: c.EmailCS, WebsiteURL: c.WebsiteURL,
		HeadOfficeAddress: c.HeadOfficeAddress, MaintenanceMode: c.MaintenanceMode, MaintenanceMessage: c.MaintenanceMessage,
	}
}

type AdminAppConfigView struct {
	AppConfig
	OTPGatewayTokenSet bool `json:"otp_gateway_token_set"`
}

func (c *AppConfig) AdminView() AdminAppConfigView {
	return AdminAppConfigView{
		AppConfig:          *c,
		OTPGatewayTokenSet: c.OTPGatewayToken != "",
	}
}

type UserSession struct {
	ID               string     `json:"id" gorm:"primaryKey;type:uuid"`
	UserID           string     `json:"user_id" gorm:"type:uuid;index;not null"`
	DeviceID         string     `json:"device_id" gorm:"type:varchar(128)"`
	RefreshTokenHash string     `json:"-" gorm:"type:varchar(64);index;not null"`
	PrevRefreshHash  string     `json:"-" gorm:"type:varchar(64);index"`
	RotatedAt        *time.Time `json:"rotated_at"`
	ExpiresAt        time.Time  `json:"expires_at" gorm:"index;not null"`
	RevokedAt        *time.Time `json:"revoked_at" gorm:"index"`
	RevokedReason    string     `json:"revoked_reason" gorm:"type:varchar(60)"`
	IPAddress        string     `json:"ip_address" gorm:"type:varchar(64)"`
	CreatedAt        time.Time  `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt        time.Time  `json:"updated_at" gorm:"autoUpdateTime"`
}

type AuditLog struct {
	ID        string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	ActorType string    `json:"actor_type" gorm:"type:varchar(20);index;not null"` // NASABAH, ADMIN, SYSTEM
	ActorID   string    `json:"actor_id" gorm:"type:varchar(60);index"`
	ActorName string    `json:"actor_name" gorm:"type:varchar(100)"`
	Action    string    `json:"action" gorm:"type:varchar(60);index;not null"`
	Target    string    `json:"target" gorm:"type:varchar(100)"`
	Status    string    `json:"status" gorm:"type:varchar(20);default:'SUCCESS'"` // SUCCESS, WARNING, DANGER
	IPAddress string    `json:"ip_address" gorm:"type:varchar(50)"`
	UserAgent string    `json:"user_agent" gorm:"type:varchar(255)"`
	DeviceID  string    `json:"device_id" gorm:"type:varchar(128)"`
	Details   string    `json:"details" gorm:"type:text"`
	Seq       int64     `json:"seq" gorm:"autoIncrement;uniqueIndex;not null"`
	PrevHash  string    `json:"prev_hash" gorm:"type:varchar(64)"`
	Hash      string    `json:"hash" gorm:"type:varchar(64);index"`
	CreatedAt time.Time `json:"created_at" gorm:"autoCreateTime;index"`
}

func (a *AuditLog) BeforeCreate(tx *gorm.DB) error {
	if a.ID == "" {
		a.ID = uuid.NewString()
	}
	return nil
}

type Notification struct {
	ID        string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID    string    `json:"user_id" gorm:"type:varchar(60);index;not null"` // User UUID or "ALL" for broadcast
	Title     string    `json:"title" gorm:"type:varchar(150);not null"`
	Message   string    `json:"message" gorm:"type:text;not null"`
	Category  string    `json:"category" gorm:"type:varchar(30);default:'INFO'"` // SECURITY, TRANSACTION, PROMO
	IsRead    bool      `json:"is_read" gorm:"type:boolean;default:false"`
	CreatedAt time.Time `json:"created_at" gorm:"autoCreateTime;index"`
}

func (n *Notification) BeforeCreate(tx *gorm.DB) error {
	if n.ID == "" {
		n.ID = uuid.NewString()
	}
	return nil
}

type ProductApplication struct {
	ID              string       `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID          string       `json:"user_id" gorm:"type:varchar(60);index;not null"`
	CIF             string       `json:"cif" gorm:"type:varchar(30)"`
	FullName        string       `json:"full_name" gorm:"type:varchar(100);not null"`
	PhoneNumber     string       `json:"phone_number" gorm:"type:varchar(30);not null"`
	ProductType     string       `json:"product_type" gorm:"type:varchar(30);index;not null"` // DEPOSITO, PINJAMAN
	ProductName     string       `json:"product_name" gorm:"type:varchar(100);not null"`
	Amount          money.Amount `json:"amount" gorm:"type:decimal(15,2);not null"`
	TenorMonths     int          `json:"tenor_months" gorm:"type:int;not null"`
	InterestRate    string       `json:"interest_rate" gorm:"type:varchar(50)"`
	EstimatedReturn money.Amount `json:"estimated_return" gorm:"type:decimal(15,2)"`
	PurposeOrSource string       `json:"purpose_or_source" gorm:"type:varchar(255)"`
	Status          string       `json:"status" gorm:"type:varchar(30);default:'PENDING'"` // PENDING, CONTACTED, APPROVED, REJECTED
	AdminNotes      string       `json:"admin_notes" gorm:"type:text"`
	CreatedAt       time.Time    `json:"created_at" gorm:"autoCreateTime;index"`
	UpdatedAt       time.Time    `json:"updated_at" gorm:"autoUpdateTime"`
}

func (p *ProductApplication) BeforeCreate(tx *gorm.DB) error {
	if p.ID == "" {
		p.ID = uuid.NewString()
	}
	return nil
}

// Maker-checker request kinds and statuses (audit E-03, E-07, G).
const (
	ApprovalConfigSecurity  = "CONFIG_SECURITY"
	ApprovalDeviceReset     = "DEVICE_RESET"
	ApprovalCustomerUnblock = "CUSTOMER_UNBLOCK"
	ApprovalBannerPublish   = "BANNER_PUBLISH"

	ApprovalPending   = "PENDING"
	ApprovalApproved  = "APPROVED"
	ApprovalRejected  = "REJECTED"
	ApprovalCancelled = "CANCELLED"
	ApprovalFailed    = "FAILED"
)

// ApprovalRequest is a sensitive backoffice action waiting for a second officer. The maker
// can never be the checker. Payload is AES-GCM encrypted (it may carry the OTP gateway token).
type ApprovalRequest struct {
	ID              string     `json:"id" gorm:"primaryKey;type:uuid"`
	Kind            string     `json:"kind" gorm:"type:varchar(40);not null"`
	TargetID        string     `json:"target_id" gorm:"type:varchar(64);not null"`
	Summary         string     `json:"summary" gorm:"type:text"`
	Payload         string     `json:"-" gorm:"type:text"`
	Status          string     `json:"status" gorm:"type:varchar(20);not null"`
	RequestedBy     string     `json:"requested_by" gorm:"type:varchar(64);not null"`
	RequestedByName string     `json:"requested_by_name" gorm:"type:varchar(120)"`
	RequestedByRole string     `json:"requested_by_role" gorm:"type:varchar(30)"`
	RequestedAt     time.Time  `json:"requested_at"`
	DecidedBy       *string    `json:"decided_by,omitempty" gorm:"type:varchar(64)"`
	DecidedByName   *string    `json:"decided_by_name,omitempty" gorm:"type:varchar(120)"`
	DecidedAt       *time.Time `json:"decided_at,omitempty"`
	DecisionNote    *string    `json:"decision_note,omitempty" gorm:"type:text"`
}
