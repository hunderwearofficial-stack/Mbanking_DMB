package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// TransactionType enum
const (
	TxTypeDebit  = "DEBIT"
	TxTypeCredit = "CREDIT"

	TxTransferInternal = "TRANSFER_INTERNAL"
	TxTransferBank     = "TRANSFER_BANK"
	TxPPOB             = "PPOB"

	TxStatusPending = "PENDING"
	TxStatusSuccess = "SUCCESS"
	TxStatusFailed  = "FAILED"

	AccountStatusActive  = "Active"
	AccountStatusBlocked = "Blocked"

	AdminRoleSuperAdmin = "SUPER_ADMIN"
	AdminRoleCS         = "CS"
	AdminRoleMarketing  = "MARKETING"
)

// User represents the customer identity (synced with CBS /api/nasabah) & device binding table
type User struct {
	ID             string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	NIK            string    `json:"nik" gorm:"type:varchar(30);column:nik"`
	CIF            string    `json:"cif" gorm:"type:varchar(20);uniqueIndex;not null;column:cif"`
	FullName       string    `json:"full_name" gorm:"type:varchar(100);not null;column:full_name"`
	PhoneNumber    string    `json:"phone_number" gorm:"type:varchar(20);uniqueIndex;not null;column:phone_number"`
	Email          string    `json:"email" gorm:"type:varchar(100);column:email"`
	Alamat         string    `json:"alamat" gorm:"type:text;column:alamat"`
	KodePos        string    `json:"kode_pos" gorm:"type:varchar(15);column:kode_pos"`
	JenisKelamin   string    `json:"jenis_kelamin" gorm:"type:varchar(5);column:jenis_kelamin"`
	Agama          string    `json:"agama" gorm:"type:varchar(30);column:agama"`
	TglLahir       string    `json:"tgl_lahir" gorm:"type:varchar(40);column:tgl_lahir"`
	TempatLahir    string    `json:"tempat_lahir" gorm:"type:varchar(100);column:tempat_lahir"`
	NamaIbuKandung string    `json:"nama_ibu_kandung" gorm:"type:varchar(100);column:nama_ibu_kandung"`
	PasswordHash   string    `json:"-" gorm:"type:varchar(255);not null"`
	PINHash        string    `json:"-" gorm:"type:varchar(255);not null"`
	DeviceID       string    `json:"device_id" gorm:"type:varchar(100);index"`
	IsActive       bool      `json:"is_active" gorm:"type:boolean;default:true"`
	CreatedAt      time.Time `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt      time.Time `json:"updated_at" gorm:"autoUpdateTime"`

	// Relationships
	Accounts []Account `json:"accounts,omitempty" gorm:"foreignKey:UserID;references:ID;constraint:OnDelete:CASCADE"`
}

func (u *User) BeforeCreate(tx *gorm.DB) error {
	if u.ID == "" {
		u.ID = uuid.NewString()
	}
	return nil
}

// Account represents customer bank account in BPR (synced with CBS /api/savings-account-balance)
type Account struct {
	ID               string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID           string    `json:"user_id" gorm:"type:uuid;index;not null"`
	AccountNumber    string    `json:"account_number" gorm:"type:varchar(30);uniqueIndex;not null"`
	HolderName       string    `json:"holder_name" gorm:"type:varchar(100);column:holder_name"`
	ProductCode      string    `json:"product_code" gorm:"type:varchar(20);column:product_code"`
	AccountType      string    `json:"account_type" gorm:"type:varchar(50);default:'Savings'"`
	Balance          float64   `json:"balance" gorm:"type:decimal(15,2);not null;default:0.00"`
	MinimumBalance   float64   `json:"minimum_balance" gorm:"type:decimal(15,2);not null;default:0.00;column:minimum_balance"`
	BlockedBalance   float64   `json:"blocked_balance" gorm:"type:decimal(15,2);not null;default:0.00;column:blocked_balance"`
	EffectiveBalance float64   `json:"effective_balance" gorm:"type:decimal(15,2);not null;default:0.00;column:effective_balance"`
	Status           string    `json:"status" gorm:"type:varchar(20);default:'Active'"`
	CreatedAt        time.Time `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt        time.Time `json:"updated_at" gorm:"autoUpdateTime"`

	// Relationships
	User      *User      `json:"user,omitempty" gorm:"foreignKey:UserID;references:ID"`
	Mutations []Mutation `json:"mutations,omitempty" gorm:"foreignKey:AccountNumber;references:AccountNumber"`
}

func (a *Account) BeforeCreate(tx *gorm.DB) error {
	if a.ID == "" {
		a.ID = uuid.NewString()
	}
	return nil
}

// Mutation records statement history for account
type Mutation struct {
	ID              string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	AccountNumber   string    `json:"account_number" gorm:"type:varchar(30);index;not null"`
	TransactionType string    `json:"transaction_type" gorm:"type:varchar(10);not null"` // DEBIT, CREDIT
	Amount          float64   `json:"amount" gorm:"type:decimal(15,2);not null"`
	BalanceAfter    float64   `json:"balance_after" gorm:"type:decimal(15,2);not null"`
	Description     string    `json:"description" gorm:"type:varchar(255);not null"`
	ReferenceNumber string    `json:"reference_number" gorm:"type:varchar(50);uniqueIndex;not null"`
	CreatedAt       time.Time `json:"created_at" gorm:"autoCreateTime"`
}

func (m *Mutation) BeforeCreate(tx *gorm.DB) error {
	if m.ID == "" {
		m.ID = uuid.NewString()
	}
	return nil
}

// Transaction logs all transactions performed via Mobile Banking
type Transaction struct {
	ID              string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID          string    `json:"user_id" gorm:"type:uuid;index;not null"`
	FromAccount     string    `json:"from_account" gorm:"type:varchar(30);index;not null"`
	ToAccount       string    `json:"to_account" gorm:"type:varchar(30);not null"`
	Amount          float64   `json:"amount" gorm:"type:decimal(15,2);not null"`
	TransactionType string    `json:"transaction_type" gorm:"type:varchar(30);not null"` // TRANSFER_INTERNAL, TRANSFER_BANK, PPOB
	Status          string    `json:"status" gorm:"type:varchar(20);not null"`           // PENDING, SUCCESS, FAILED
	CBSReferenceNo  string    `json:"cbs_ref_no" gorm:"type:varchar(50);column:cbs_ref_no"`
	CreatedAt       time.Time `json:"created_at" gorm:"autoCreateTime"`

	// Relationships
	User *User `json:"user,omitempty" gorm:"foreignKey:UserID;references:ID"`
}

func (t *Transaction) BeforeCreate(tx *gorm.DB) error {
	if t.ID == "" {
		t.ID = uuid.NewString()
	}
	return nil
}

// AdminUser represents Bank DMB staff/officer managing backoffice
type AdminUser struct {
	ID           string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Username     string    `json:"username" gorm:"type:varchar(50);uniqueIndex;not null"`
	FullName     string    `json:"full_name" gorm:"type:varchar(100);not null"`
	Email        string    `json:"email" gorm:"type:varchar(100)"`
	PasswordHash string    `json:"-" gorm:"type:varchar(255);not null"`
	Role         string    `json:"role" gorm:"type:varchar(30);default:'SUPER_ADMIN'"` // SUPER_ADMIN, CS, MARKETING
	IsActive     bool      `json:"is_active" gorm:"type:boolean;default:true"`
	CreatedAt    time.Time `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt    time.Time `json:"updated_at" gorm:"autoUpdateTime"`
}

func (a *AdminUser) BeforeCreate(tx *gorm.DB) error {
	if a.ID == "" {
		a.ID = uuid.NewString()
	}
	return nil
}

// Banner represents dynamic marketing/promotional content on M-Banking home
type Banner struct {
	ID           string    `json:"id" gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Tag          string    `json:"tag" gorm:"type:varchar(60);not null"`
	Title        string    `json:"title" gorm:"type:varchar(120);not null"`
	Highlight    string    `json:"highlight" gorm:"type:varchar(255);not null"`
	BadgeText    string    `json:"badge_text" gorm:"type:varchar(50)"`
	BgColor      string    `json:"bg_color" gorm:"type:varchar(30);default:'#1E293B'"`
	AccentColor  string    `json:"accent_color" gorm:"type:varchar(30);default:'#16984B'"`
	IconName     string    `json:"icon_name" gorm:"type:varchar(50);default:'savings'"`
	TargetUrl    string    `json:"target_url" gorm:"type:varchar(255)"`
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

// AppConfig represents Bank identity, logo, transaction limits, and operational settings
type AppConfig struct {
	ID                   string    `json:"id" gorm:"primaryKey;type:varchar(50);default:'DEFAULT'"`
	BankName             string    `json:"bank_name" gorm:"type:varchar(120);default:'PT BPR DANA MANDIRI BOGOR'"`
	BankShortName        string    `json:"bank_short_name" gorm:"type:varchar(50);default:'Bank DMB'"`
	Tagline              string    `json:"tagline" gorm:"type:varchar(255);default:'Mitra Terpercaya Menuju Sejahtera'"`
	LogoURL              string    `json:"logo_url" gorm:"type:text"`
	CallCenter           string    `json:"call_center" gorm:"type:varchar(50);default:'(0251) 832-1234'"`
	WhatsAppCS           string    `json:"whatsapp_cs" gorm:"type:varchar(50);default:'081199887766'"`
	EmailCS              string    `json:"email_cs" gorm:"type:varchar(100);default:'layanan@bprdanamandiribogor.co.id'"`
	WebsiteURL           string    `json:"website_url" gorm:"type:varchar(255);default:'https://bprdanamandiribogor.co.id'"`
	HeadOfficeAddress    string    `json:"head_office_address" gorm:"type:text;default:'Jl. Pajajaran No. 88, Bogor, Jawa Barat'"`
	MaintenanceMode      bool      `json:"maintenance_mode" gorm:"type:boolean;default:false"`
	MaintenanceMessage   string    `json:"maintenance_message" gorm:"type:varchar(255);default:'Sistem sedang dalam peningkatan layanan berkala.'"`
	MinTransferAmount    float64   `json:"min_transfer_amount" gorm:"type:decimal(15,2);default:10000"`
	DailyTransferLimit   float64   `json:"daily_transfer_limit" gorm:"type:decimal(15,2);default:25000000"`
	InterbankTransferFee float64   `json:"interbank_transfer_fee" gorm:"type:decimal(15,2);default:2500"`
	EnforceDeviceBinding bool      `json:"enforce_device_binding" gorm:"type:boolean;default:true"`
	MaxLoginAttempts     int       `json:"max_login_attempts" gorm:"type:int;default:3"`
	UpdatedAt            time.Time `json:"updated_at" gorm:"autoUpdateTime"`
}
